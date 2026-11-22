library;

import 'dart:convert';
import '../../quickjs/js_engine.dart';
import 'package:logging/logging.dart';
import 'package:drift/drift.dart';
import 'package:mutex/mutex.dart';

import '../../dart_couch_db.dart' show UpdateMode;
import '../../messages/couch_document_base.dart';
import '../../messages/view_result.dart';
import '../database.dart';

final log = Logger('dart_couch-view_ctrl');

/// Batched winner-document loader: maps each requested docid to its current
/// winning document, or `null` when missing or deleted.
typedef DbGetManyFunction =
    Future<Map<String, CouchDocumentBase?>> Function(
      List<String> docids, {
      bool attachments,
    });

class JavascriptException implements Exception {
  final String message;
  JavascriptException(this.message);

  @override
  String toString() => 'JavascriptException: $message';
}

class ViewCtrl {
  final int dbid;
  final AppDatabase db;
  LocalView view; // Made non-final so we can reload it

  final Future<CouchDocumentBase?> Function(
    String docid, {
    String? rev,
    bool revs,
    bool revsInfo,
    bool attachments,
  })
  dbGetFunction;

  /// Batched loader used for `include_docs`: returns the current winner of
  /// every requested docid (`null` for missing/deleted) — per document the
  /// same result as [dbGetFunction] without `rev`/`revs`/`revsInfo` — in a
  /// bounded number of queries instead of ~2 per row.
  final DbGetManyFunction dbGetManyFunction;

  /// Mutex to serialize view updates
  final Mutex _updateMutex = Mutex();

  /// Rows per [dbGetManyFunction] call when resolving `include_docs`; bounds
  /// the intermediate per-batch memory and matches the storage layer's
  /// `IN (...)` chunk size.
  static const int _includeDocsBatchSize = AppDatabase.batchReadChunkSize;

  /// Documents per indexing page in [_updateViewEntries] (one page query +
  /// at most one write batch per page). Keeps `IN (...)` lists below
  /// SQLite's bound-variable limit and bounds memory for large databases.
  static const int _indexPageSize = AppDatabase.batchReadChunkSize;

  /// Documents processed without any entry change whose seq advance may stay
  /// in memory before it is persisted anyway (see [_updateViewEntries]).
  static const int _maxUnpersistedDocs = AppDatabase.batchReadChunkSize;

  /// Documents processed since the view's updateSeq was last written.
  int _unpersistedDocs = 0;

  /// Database update seq read by [ViewMgr.getView] just before handing this
  /// controller out; consumed by the next [_updateViewEntries] to skip its
  /// own seq query. Always a value read before the update starts, so a lower
  /// bound of what the update must cover.
  int? _dbSeqHint;

  ViewCtrl({
    required this.dbid,
    required this.db,
    required this.view,
    required this.dbGetFunction,
    required this.dbGetManyFunction,
  });

  /// Records the database update seq [seq] just read by the caller (see
  /// [_dbSeqHint]).
  void noteDbUpdateSeq(int seq) {
    final h = _dbSeqHint;
    if (h == null || seq > h) _dbSeqHint = seq;
  }

  /// Replaces the view row (e.g. after ViewMgr re-validated it against its
  /// design document). Call inside [runExclusive].
  void adoptView(LocalView row) {
    view = row;
    _unpersistedDocs = 0;
  }

  /// Runs [action] mutually exclusive with this view's queries / index
  /// updates.
  Future<T> runExclusive<T>(Future<T> Function() action) =>
      _updateMutex.protect(action);

  /// The view's JavaScript map function source.
  String get mapFunction => view.mapFunction;

  /// Creates a reusable evaluator that runs this view's map function as a
  /// `_changes` filter (CouchDB `filter=_view`): a document passes iff the
  /// map emits at least one row for it.
  ///
  /// The caller owns the returned evaluator and MUST [ViewMapFilter.dispose]
  /// it (it holds a [JsEngine]).
  ViewMapFilter createMapFilter() => ViewMapFilter(mapFunction);

  Future<ViewResult> query({
    bool includeDocs = false,
    bool attachments = false,
    bool attEncodingInfo = false,
    bool conflicts = false,

    String? startkey,
    String? startkeyDocid,
    String? endkey,
    String? endkeyDocid,
    String? key,
    List<String>? keys,

    bool inclusiveEnd = true,

    bool group = false,
    int? groupLevel,

    bool reduce = true,

    int? limit,
    int? skip,
    bool descending = false,
    bool sorted = true,

    bool stable = false,
    UpdateMode updateMode = UpdateMode.modeTrue,
    bool updateSeq = false,
  }) async {
    assert(attEncodingInfo == false);
    assert(conflicts == false);
    assert(
      startkey != null || startkeyDocid == null,
      'startkeyDocid requires startkey',
    );
    assert(
      endkey != null || endkeyDocid == null,
      'endkeyDocid requires endkey',
    );
    assert(key == null || keys == null, 'key and keys cannot be combined');
    assert(!stable, "stable is not supported yet");
    assert(updateMode == UpdateMode.modeTrue);
    assert(updateSeq == false);

    if (reduce && view.reduceFunction == null) {
      // View has no reduce function - ignore reduce=true (CouchDB default behavior)
      reduce = false;
    }
    if ((group || groupLevel != null) && !reduce) {
      throw ArgumentError('group/group_level require reduce=true');
    }
    if (reduce && includeDocs) {
      throw ArgumentError('include_docs is invalid for reduce queries');
    }

    return await _updateMutex.protect(() async {
      await _updateViewEntries();
      var query = db.select(db.localViewEntries)
        ..where((tbl) => tbl.fkview.equals(view.id));

      if (sorted == true) {
        query = query
          ..orderBy([
            (tbl) => OrderingTerm(
              expression: tbl.key,
              mode: descending ? OrderingMode.desc : OrderingMode.asc,
            ),
          ]);
      }

      List<LocalViewEntry> entries = await query.get();

      final dynamic normalizedKey = key != null ? _normalizeViewKey(key) : null;
      final List<dynamic>? normalizedKeys = keys
          ?.map(_normalizeViewKey)
          .toList();
      final dynamic normalizedStartkey = startkey != null
          ? _normalizeViewKey(startkey)
          : null;
      final dynamic normalizedEndkey = endkey != null
          ? _normalizeViewKey(endkey)
          : null;

      List<_ViewEntryIntermediate> filteredEntries;

      if (normalizedKeys != null) {
        /// When using the 'keys' parameter, we need to find
        /// exact matches for each requested key. This is different from range queries
        /// where we filter entries within a range.
        ///
        /// Key format inconsistency note:
        /// - Documents are stored with keys in JSON format (e.g., "all-doc-a")
        /// - Query keys are normalized but may not be JSON-encoded (e.g., all-doc-a)
        /// - We need to try both formats to ensure we find matches
        final Map<String, List<LocalViewEntry>> grouped =
            <String, List<LocalViewEntry>>{};
        for (final entry in entries) {
          grouped.putIfAbsent(entry.key, () => <LocalViewEntry>[]).add(entry);
        }

        filteredEntries = [];
        for (final k in normalizedKeys) {
          // Convert the normalized key to JSON string for comparison with stored keys
          // This handles the case where query keys are simple strings
          final String keyAsString = k is String ? k : jsonEncode(k);
          // Also try the JSON-encoded version since that's how keys are stored
          // This handles the case where keys were stored as JSON strings
          final String keyAsJsonString = jsonEncode(k);

          // Try both formats to find a match. This ensures we handle the format
          // inconsistency between how keys are stored vs. how they're queried.
          final matches = grouped[keyAsString] ?? grouped[keyAsJsonString];
          if (matches != null) {
            for (final m in matches) {
              filteredEntries.add(_ViewEntryIntermediate(m.key, m));
            }
          } else {
            // Key not found - include it in results with error flag
            // This matches CouchDB behavior where requested keys are always returned
            // Note: For non-existent documents, we return null for id and 'not_found' for error
            // We create the ViewEntry directly here since we don't have a database entry
            filteredEntries.add(_ViewEntryIntermediate(keyAsString, null));
          }
        }
      } else {
        Iterable<LocalViewEntry> temp = entries;

        if (normalizedKey != null) {
          // Always JSON-encode to match the storage format (jsonEncode in _storeViewEntry)
          final String keyAsString = jsonEncode(normalizedKey);
          temp = temp.where((entry) => entry.key == keyAsString);
        }

        final bool needsRangeFilter =
            normalizedStartkey != null || normalizedEndkey != null;
        if (needsRangeFilter) {
          temp = temp.where(
            (entry) => _isWithinRange(
              entry: entry,
              startkey: normalizedStartkey,
              startkeyDocid: startkeyDocid,
              endkey: normalizedEndkey,
              endkeyDocid: endkeyDocid,
              inclusiveEnd: inclusiveEnd,
              descending: descending,
            ),
          );
        }
        filteredEntries = temp
            .map((e) => _ViewEntryIntermediate(e.key, e))
            .toList();
      }

      // If reduce is requested and the view has a reduce function, execute it
      if (reduce && view.reduceFunction != null) {
        return await _executeReduceQuery(
          entries: filteredEntries,
          group: group,
          groupLevel: groupLevel,
          skip: skip,
          limit: limit,
        );
      }

      int totalrows = entries.length;

      final iterableAfterSkip = filteredEntries.skip(skip ?? 0);
      final Iterable<_ViewEntryIntermediate> pagedEntries = limit != null
          ? iterableAfterSkip.take(limit)
          : iterableAfterSkip;

      final paged = pagedEntries.toList(growable: false);

      ViewEntry toRow(_ViewEntryIntermediate e, CouchDocumentBase? doc) {
        if (e.entry == null) {
          // For missing documents when using keys parameter, we should return
          // null for id and 'not_found' for error to match CouchDB behavior.
          return ViewEntry(
            id: null, // null for non-existent documents
            key: _tryParseJson(e.key),
            value: null,
            error: "not_found",
          );
        }
        return ViewEntry(
          id: e.entry!.docid,
          key: _tryParseJson(e.entry!.key),
          value: _tryParseJson(e.entry!.value),
          doc: doc,
        );
      }

      final List<ViewEntry> rows;
      if (!includeDocs) {
        rows = [for (final e in paged) toRow(e, null)];
      } else {
        // Resolve docs in batches: one batched load per chunk of rows instead
        // of ~2 queries per row. Row order and duplicate rows (a doc emitting
        // several rows, repeated `keys`) are preserved; each distinct docid
        // is loaded once per chunk.
        rows = <ViewEntry>[];
        for (var i = 0; i < paged.length; i += _includeDocsBatchSize) {
          final chunk = paged.sublist(
            i,
            i + _includeDocsBatchSize > paged.length
                ? paged.length
                : i + _includeDocsBatchSize,
          );
          final docids = <String>{
            for (final e in chunk)
              if (e.entry != null) e.entry!.docid,
          }.toList(growable: false);
          final docs = docids.isEmpty
              ? const <String, CouchDocumentBase?>{}
              : await dbGetManyFunction(docids, attachments: attachments);
          for (final e in chunk) {
            rows.add(toRow(e, e.entry == null ? null : docs[e.entry!.docid]));
          }
        }
      }

      return ViewResult(totalRows: totalrows, offset: skip ?? 0, rows: rows);
    });
  }

  dynamic _tryParseJson(String jsonString) {
    try {
      return jsonDecode(jsonString);
    } catch (e) {
      return jsonString;
    }
  }

  /// Normalizes a view key by attempting to parse it as JSON.
  ///
  /// CouchDB stores keys in various formats depending on how they were created:
  /// - Simple strings: stored as JSON strings with quotes (e.g., "key")
  /// - Numbers: stored as JSON numbers (e.g., 123)
  /// - Objects: stored as JSON objects (e.g., {"field": "value"})
  /// - Arrays: stored as JSON arrays (e.g., ["a", "b"])
  ///
  /// This method attempts to parse the raw key as JSON. If successful, it returns
  /// the parsed value (which could be a string, number, object, etc.). If parsing
  /// fails, it returns the raw key as-is.
  ///
  /// Example:
  /// - _normalizeViewKey('"key"') returns 'key' (string without quotes)
  /// - _normalizeViewKey('123') returns 123 (number)
  /// - _normalizeViewKey('key') returns 'key' (raw string when JSON parsing fails)
  ///
  /// Note: This creates an inconsistency where keys can be stored in different formats
  /// in the database vs. how they're queried. The query logic must handle both formats.
  dynamic _normalizeViewKey(String rawKey) {
    try {
      return jsonDecode(rawKey);
    } catch (_) {
      return rawKey;
    }
  }

  /// Compares two keys according to CouchDB collation rules.
  /// Returns: negative if a < b, 0 if a == b, positive if a > b
  int _compareKeys(dynamic a, dynamic b) {
    // Get collation order (null=0, false=1, true=2, num=3, string=4, array=5, object=6)
    int getTypeOrder(dynamic val) {
      if (val == null) return 0;
      if (val is bool) return val ? 2 : 1;
      if (val is num) return 3;
      if (val is String) return 4;
      if (val is List) return 5;
      if (val is Map) return 6;
      return 7; // unknown type
    }

    final int typeA = getTypeOrder(a);
    final int typeB = getTypeOrder(b);

    // Different types: compare by type order
    if (typeA != typeB) {
      return typeA.compareTo(typeB);
    }

    // Same type: compare values
    if (a == null) return 0;
    if (a is bool) return a == b ? 0 : (a ? 1 : -1);
    if (a is num && b is num) return a.compareTo(b);
    if (a is String && b is String) return a.compareTo(b);

    if (a is List && b is List) {
      // Compare arrays element by element
      final int minLen = a.length < b.length ? a.length : b.length;
      for (int i = 0; i < minLen; i++) {
        final int cmp = _compareKeys(a[i], b[i]);
        if (cmp != 0) return cmp;
      }
      // All compared elements are equal, shorter array comes first
      return a.length.compareTo(b.length);
    }

    if (a is Map && b is Map) {
      // For objects, we'll do a simple comparison
      // In CouchDB, {} represents the highest value (used as endkey sentinel)
      final bool aEmpty = a.isEmpty;
      final bool bEmpty = b.isEmpty;
      if (aEmpty && bEmpty) return 0;
      if (aEmpty) return 1; // empty object is highest
      if (bEmpty) return -1; // empty object is highest

      // For non-empty objects, compare as JSON strings
      // (this is a simplification; full CouchDB comparison is more complex)
      return jsonEncode(a).compareTo(jsonEncode(b));
    }

    // Fallback: convert to string and compare
    return a.toString().compareTo(b.toString());
  }

  bool _isWithinRange({
    required LocalViewEntry entry,
    required dynamic startkey,
    required String? startkeyDocid,
    required dynamic endkey,
    required String? endkeyDocid,
    required bool inclusiveEnd,
    required bool descending,
  }) {
    // Parse the entry key for comparison
    final dynamic entryKey = _tryParseJson(entry.key);

    if (startkey != null) {
      final int cmp = _compareKeys(entryKey, startkey);
      if (!descending) {
        if (cmp < 0) return false;
        if (cmp == 0 && startkeyDocid != null) {
          if (entry.docid.compareTo(startkeyDocid) < 0) return false;
        }
      } else {
        if (cmp > 0) return false;
        if (cmp == 0 && startkeyDocid != null) {
          if (entry.docid.compareTo(startkeyDocid) > 0) return false;
        }
      }
    }

    if (endkey != null) {
      final int cmp = _compareKeys(entryKey, endkey);
      if (!descending) {
        if (cmp > 0) return false;
        if (cmp == 0) {
          if (endkeyDocid != null) {
            final docCmp = entry.docid.compareTo(endkeyDocid);
            final bool allowed = inclusiveEnd ? docCmp <= 0 : docCmp < 0;
            if (!allowed) return false;
          } else if (!inclusiveEnd) {
            return false;
          }
        }
      } else {
        if (cmp < 0) return false;
        if (cmp == 0) {
          if (endkeyDocid != null) {
            final docCmp = entry.docid.compareTo(endkeyDocid);
            final bool allowed = inclusiveEnd ? docCmp >= 0 : docCmp > 0;
            if (!allowed) return false;
          } else if (!inclusiveEnd) {
            return false;
          }
        }
      }
    }

    return true;
  }

  /// Brings the index up to date with the database.
  ///
  /// Walks the documents changed since [LocalView.updateSeq] in seq-ordered
  /// pages of [_indexPageSize] and, per page,
  ///  1. loads the page (bodies + "has live conflicts" + "has entries in this
  ///     view" flags) in one query,
  ///  2. loads `_conflicts` and the old entries only for the docs flagged,
  ///  3. runs the map function and compares old vs new entries per doc,
  ///  4. writes the deletes + inserts of the docs whose entries changed and
  ///     the advanced updateSeq in ONE drift batch (one round trip, atomic).
  ///
  /// Per document the outcome is the same as re-indexing it from scratch:
  /// `_local/` and `_design/` docs are skipped, a tombstone loses its
  /// entries, a doc without blob or whose map errors keeps its old entries
  /// (logged), otherwise its entries become exactly what the map emitted (in
  /// emit order). Re-processing a doc is idempotent, which is what makes the
  /// paging restartable and lets small no-op advances stay in memory (see
  /// [_maxUnpersistedDocs]).
  Future<void> _updateViewEntries() async {
    // 1. find the current updateSeq from the database (ViewMgr.getView
    //    usually just read it and left it as a hint)
    final int? hint = _dbSeqHint;
    _dbSeqHint = null;
    final int curUpdateSeq =
        hint ?? await db.getCurrentUpdateSeq(view.database);

    log.fine(
      () =>
          '_updateViewEntries: curUpdateSeq=$curUpdateSeq, view.updateSeq=${view.updateSeq}, viewId=${view.id}',
    );

    // check if a view update is needed
    if (curUpdateSeq == view.updateSeq) {
      log.fine('_updateViewEntries: View is up to date, skipping');
      return;
    }

    JsEngine? jsEngine;
    JsEngine engine() => jsEngine ??= _createMapEngine();
    var processed = 0;
    var written = 0;

    try {
      var afterSeq = view.updateSeq;
      while (true) {
        // 2. next page of documents with a higher sequence number. No upper
        //    bound: a doc rewritten during the walk moves to a higher seq and
        //    is picked up by a later page (or the next update).
        final page = await db.getViewIndexPage(
          dbid,
          view.id,
          afterSeq,
          limit: _indexPageSize,
        );
        final bool lastPage = page.length < _indexPageSize;

        // Every doc with seq <= the page's last seq has been seen. After the
        // last page every doc that existed when curUpdateSeq was read has
        // been seen as well (a doc rewritten since then has a higher seq
        // than curUpdateSeq), so the index is current up to curUpdateSeq.
        var newSeq = page.isEmpty ? afterSeq : page.last.document.seq;
        if (lastPage && curUpdateSeq > newSeq) newSeq = curUpdateSeq;

        final writes = page.isEmpty
            ? const _PageWrites.empty()
            : await _indexPage(page, engine);
        processed += page.length;
        _unpersistedDocs += page.length;

        if (newSeq != view.updateSeq || writes.hasWrites) {
          // Persist when entries change (the seq rides along for free), on
          // every non-final page of a long walk (restart point), and after
          // [_maxUnpersistedDocs] no-op docs. A small no-op advance (a write
          // the view does not emit for) stays in memory: losing it only
          // means re-mapping those docs once, which is idempotent.
          final persist =
              writes.hasWrites ||
              !lastPage ||
              _unpersistedDocs >= _maxUnpersistedDocs;
          if (persist) {
            final viewId = view.id;
            await db.batch((b) {
              if (writes.deleteDocids.isNotEmpty) {
                b.deleteWhere(
                  db.localViewEntries,
                  (t) =>
                      t.fkview.equals(viewId) &
                      t.docid.isIn(writes.deleteDocids),
                );
              }
              if (writes.inserts.isNotEmpty) {
                b.insertAll(db.localViewEntries, writes.inserts);
              }
              b.update(
                db.localViews,
                LocalViewsCompanion(updateSeq: Value(newSeq)),
                where: (t) => t.id.equals(viewId),
              );
            });
            _unpersistedDocs = 0;
            written += writes.inserts.length;
          }
          // In-memory row; no reload query needed.
          view = view.copyWith(updateSeq: newSeq);
        }

        if (lastPage) break;
        afterSeq = newSeq;
      }

      log.fine(
        () =>
            '_updateViewEntries: processed $processed documents, wrote $written entries',
      );

      // Log how many entries were stored. Diagnostic only: the COUNT is an
      // extra query, so it only runs when FINE logging is enabled.
      if (log.isLoggable(Level.FINE)) {
        final entryCount =
            await (db.selectOnly(db.localViewEntries)
                  ..addColumns([db.localViewEntries.id.count()])
                  ..where(db.localViewEntries.fkview.equals(view.id)))
                .getSingle();
        log.fine(
          'View now has ${entryCount.read(db.localViewEntries.id.count())} entries, updateSeq updated to ${view.updateSeq}',
        );
      }
    } catch (e) {
      log.severe('Error executing JavaScript map function: $e');
      rethrow; // Re-throw the error to let the caller handle it
    } finally {
      jsEngine?.dispose();
    }
  }

  /// A JS engine with `emit` and this view's map function installed.
  JsEngine _createMapEngine() {
    final jsEngine = JsEngine();
    // Setup the JavaScript environment with emit function
    jsEngine.evaluate('''
        var exception = null;
        var emitted = [];
        function emit(key, value) {
          emitted.push({key: key, value: value});
        }
      ''');

    // Inject the map function into the runtime
    jsEngine.evaluate('var mapFunction = ${view.mapFunction};');
    return jsEngine;
  }

  /// Maps one page of changed documents and returns the entry writes it
  /// needs (nothing for docs whose entries are unchanged).
  Future<_PageWrites> _indexPage(
    List<ViewIndexSourceDoc> page,
    JsEngine Function() engine,
  ) async {
    final candidates = <ViewIndexSourceDoc>[
      for (final doc in page)
        // Skip _local documents - they are never replicated or indexed in
        // views. Design documents are not fed to design-document views
        // (CouchDB behaviour). `_all_docs`, which does list them, is not a
        // ViewCtrl view: it is served from the documents table directly.
        if (!doc.document.docid.startsWith('_local/') &&
            !doc.document.docid.startsWith('_design/'))
          doc,
    ];
    if (candidates.isEmpty) return const _PageWrites.empty();

    bool mapped(ViewIndexSourceDoc d) =>
        d.document.deleted != true && d.data != null;

    // CouchDB feeds the map function the winning revision PLUS a `_conflicts`
    // member when the document is in conflict (REPLICATION_AND_CONFLICT_MODEL.md
    // "View map functions"), so a view can locate conflicted docs via
    // `if (doc._conflicts) emit(...)`. Load the live (non-deleted) leaf revs
    // of this page's conflicted docs (flagged by the page query) and inject
    // `_conflicts` below. A doc's `seq` is bumped whenever its leaf set
    // changes (see AppDatabase.updateDocumentSeq), so incremental re-indexing
    // picks up a conflict appearing or being resolved. Non-conflicted docs
    // (the common case) are fed their stored blob untouched — no extra cost.
    final Map<int, List<String>> liveConflicts = await db
        .liveConflictRevsForDocs([
          for (final d in candidates)
            if (d.hasLiveConflicts && mapped(d)) d.document.id,
        ]);

    // Old entries, only for docs the view currently has entries for.
    final Map<String, List<LocalViewEntry>> oldEntries = await db
        .viewEntriesForDocs(view.id, [
          for (final d in candidates)
            if (d.hasViewEntries && mapped(d)) d.document.docid,
        ]);

    final deleteDocids = <String>[];
    final inserts = <LocalViewEntriesCompanion>[];

    for (final doc in candidates) {
      final String docid = doc.document.docid;

      // Handle deleted documents: remove old view entries and skip map function
      if (doc.document.deleted == true) {
        if (doc.hasViewEntries) deleteDocids.add(docid);
        continue;
      }

      if (doc.data == null) {
        log.warning('Document $docid has no blob data, skipping view indexing');
        continue;
      }

      final jsEngine = engine();

      // Clear previous emitted results
      jsEngine.evaluate('emitted = []; exception = null;');

      // Feed the winner plus `_conflicts` (CouchDB-faithful) when this doc has
      // live conflict leaves; otherwise the stored blob verbatim.
      final List<String>? docConflicts = liveConflicts[doc.document.id];
      final String mapInput;
      if (docConflicts != null && docConflicts.isNotEmpty) {
        final Map<String, dynamic> withConflicts =
            jsonDecode(doc.data!) as Map<String, dynamic>;
        withConflicts['_conflicts'] = docConflicts;
        mapInput = jsonEncode(withConflicts);
      } else {
        mapInput = doc.data!;
      }

      // Execute map function for the document
      final mapResult = jsEngine.evaluate('''
          try {
            mapFunction($mapInput);
          } catch (e) {
            console.error('Map function error for doc $docid: ' + e.toString());
            exception = e;
          }
        ''');

      if (mapResult.isError) {
        log.severe(
          'JS evaluation failed for document $docid: ${mapResult.stringResult}',
        );
        continue;
      }

      // check exception
      final JsEvalResult e = jsEngine.evaluate('exception;');
      if (!e.isError && e.stringResult != 'null') {
        log.severe(
          'Error in map function for document $docid: ${e.stringResult}',
        );
        // CouchDB behavior: log the error but continue processing other documents
        // Skip this document and continue with the next one
        continue;
      }

      // Get emitted results
      final JsEvalResult result = jsEngine.evaluate('JSON.stringify(emitted)');
      if (result.isError || result.stringResult == 'undefined') continue;

      final List<dynamic> emittedResults = List<dynamic>.from(
        jsonDecode(result.stringResult),
      );
      // Stored form, exactly as before: JSON-encoded key and value.
      final newRows = <(String, String)>[
        for (final emitted in emittedResults)
          (jsonEncode(emitted['key']), jsonEncode(emitted['value'])),
      ];

      final List<LocalViewEntry> old =
          oldEntries[docid] ?? const <LocalViewEntry>[];
      if (_sameEntries(old, newRows)) continue; // unchanged: no writes

      // Replace this doc's entries. The delete also runs when no old entries
      // were seen (cheap no-op), so a concurrent indexer of the same view can
      // never leave duplicates behind.
      deleteDocids.add(docid);
      for (final (key, value) in newRows) {
        inserts.add(
          LocalViewEntriesCompanion.insert(
            fkview: view.id,
            docid: docid,
            key: key,
            value: value,
          ),
        );
      }
    }

    return _PageWrites(deleteDocids, inserts);
  }

  /// Whether [old] (in row-id order) holds exactly [rows] in that order.
  static bool _sameEntries(
    List<LocalViewEntry> old,
    List<(String, String)> rows,
  ) {
    if (old.length != rows.length) return false;
    for (var i = 0; i < old.length; i++) {
      if (old[i].key != rows[i].$1 || old[i].value != rows[i].$2) {
        return false;
      }
    }
    return true;
  }

  /// Resolves built-in reduce function names to their JavaScript implementations.
  /// Custom reduce functions are returned as-is.
  String _resolveReduceFunction(String reduceFunction) {
    switch (reduceFunction) {
      case '_count':
        return 'function(keys, values, rereduce) { if (rereduce) { return values.reduce(function(a, b) { return a + b; }, 0); } else { return values.length; } }';
      case '_sum':
        return 'function(keys, values, rereduce) { return values.reduce(function(a, b) { return a + b; }, 0); }';
      case '_stats':
        return '''function(keys, values, rereduce) {
          if (rereduce) {
            return values.reduce(function(acc, val) {
              return {
                sum: acc.sum + val.sum,
                count: acc.count + val.count,
                min: Math.min(acc.min, val.min),
                max: Math.max(acc.max, val.max),
                sumsqr: acc.sumsqr + val.sumsqr
              };
            });
          } else {
            var stats = {sum: 0, count: 0, min: Infinity, max: -Infinity, sumsqr: 0};
            for (var i = 0; i < values.length; i++) {
              var v = values[i];
              stats.sum += v;
              stats.count++;
              stats.min = Math.min(stats.min, v);
              stats.max = Math.max(stats.max, v);
              stats.sumsqr += v * v;
            }
            return stats;
          }
        }''';
      default:
        return reduceFunction;
    }
  }

  /// Groups view entries by key for reduce aggregation.
  /// When no grouping is requested, all entries go into a single group with key=null.
  /// With group=true, entries are grouped by their full key.
  /// With groupLevel, array keys are grouped by their first N elements.
  Map<String, List<LocalViewEntry>> _groupEntriesByKey({
    required List<LocalViewEntry> entries,
    required bool group,
    required int? groupLevel,
  }) {
    if (!group && groupLevel == null) {
      // No grouping: single reduction over all entries
      return {'null': entries};
    }

    final Map<String, List<LocalViewEntry>> grouped = {};
    for (final entry in entries) {
      final String groupKey = _getGroupKey(entry.key, groupLevel);
      grouped.putIfAbsent(groupKey, () => []).add(entry);
    }
    return grouped;
  }

  /// Extracts the group key from a JSON-encoded key string.
  /// For group_level, truncates array keys to the first N elements.
  String _getGroupKey(String jsonKey, int? groupLevel) {
    if (groupLevel == null) {
      return jsonKey; // Full key for group=true
    }

    final dynamic key = _tryParseJson(jsonKey);
    if (key is List && groupLevel > 0) {
      return jsonEncode(key.take(groupLevel).toList());
    }
    return jsonKey;
  }

  /// Executes a reduce query by grouping filtered entries and running
  /// the reduce function via JavaScript.
  Future<ViewResult> _executeReduceQuery({
    required List<_ViewEntryIntermediate> entries,
    required bool group,
    required int? groupLevel,
    required int? skip,
    required int? limit,
  }) async {
    // Filter out null entries (not-found entries from keys queries)
    final List<LocalViewEntry> validEntries = entries
        .where((e) => e.entry != null)
        .map((e) => e.entry!)
        .toList();

    // Group entries by key
    final Map<String, List<LocalViewEntry>> grouped = _groupEntriesByKey(
      entries: validEntries,
      group: group,
      groupLevel: groupLevel,
    );

    // Resolve the reduce function (substitute built-ins with JS code)
    final String jsReduceCode = _resolveReduceFunction(view.reduceFunction!);

    // Start JavaScript runtime for reduce execution
    final jsRuntime = JsEngine();

    try {
      // Setup JS environment
      jsRuntime.evaluate('''
        var exception = null;
        var reduceFunction = $jsReduceCode;
      ''');

      List<ViewEntry> reducedRows = [];

      for (final groupEntry in grouped.entries) {
        final String groupKeyJson = groupEntry.key;
        final List<LocalViewEntry> groupEntries = groupEntry.value;

        // Prepare keys array: [[key, docid], [key, docid], ...]
        final List<List<dynamic>> keysArray = groupEntries
            .map((e) => [_tryParseJson(e.key), e.docid])
            .toList();

        // Prepare values array
        final List<dynamic> valuesArray = groupEntries
            .map((e) => _tryParseJson(e.value))
            .toList();

        // Execute reduce function
        jsRuntime.evaluate('exception = null;');
        final JsEvalResult result = jsRuntime.evaluate('''
          (function() {
            try {
              var r = reduceFunction(${jsonEncode(keysArray)}, ${jsonEncode(valuesArray)}, false);
              return JSON.stringify(r);
            } catch (e) {
              exception = e.toString();
              return null;
            }
          })()
        ''');

        // Check for errors
        final JsEvalResult err = jsRuntime.evaluate('exception;');
        if (!err.isError && err.stringResult != 'null') {
          log.severe('Error in reduce function: ${err.stringResult}');
          throw JavascriptException(
            'Reduce function error: ${err.stringResult}',
          );
        }

        dynamic reducedValue;
        if (!result.isError &&
            result.stringResult != 'null' &&
            result.stringResult != 'undefined') {
          reducedValue = jsonDecode(result.stringResult);
        }

        // Determine the group key for the result
        dynamic resultKey;
        if (!group && groupLevel == null) {
          resultKey = null; // Ungrouped reduce: key is null
        } else {
          resultKey = _tryParseJson(groupKeyJson);
        }

        reducedRows.add(ViewEntry(key: resultKey, value: reducedValue));
      }

      // Apply skip/limit to reduced results
      final Iterable<ViewEntry> afterSkip = reducedRows.skip(skip ?? 0);
      final List<ViewEntry> pagedRows = limit != null
          ? afterSkip.take(limit).toList()
          : afterSkip.toList();

      return ViewResult(
        totalRows: reducedRows.length,
        offset: skip ?? 0,
        rows: pagedRows,
      );
    } catch (e) {
      log.severe('Error executing reduce function: $e');
      rethrow;
    } finally {
      jsRuntime.dispose();
    }
  }
}

/// Entry writes of one indexing page.
class _PageWrites {
  /// Docs whose entries are removed (tombstones, changed docs).
  final List<String> deleteDocids;

  /// New entries of the changed docs.
  final List<LocalViewEntriesCompanion> inserts;

  const _PageWrites(this.deleteDocids, this.inserts);
  const _PageWrites.empty() : deleteDocids = const [], inserts = const [];

  bool get hasWrites => deleteDocids.isNotEmpty || inserts.isNotEmpty;
}

class _ViewEntryIntermediate {
  final String key;
  final LocalViewEntry? entry;
  _ViewEntryIntermediate(this.key, this.entry);
}

/// Evaluates a view's map function as a `_changes` filter (CouchDB
/// `filter=_view`): a document "passes" iff the map function emits at least
/// one row for it.
///
/// A single [JsEngine] is reused across many documents, so create one per
/// filtered changes subscription and [dispose] it when the subscription ends.
/// This mirrors the map-execution semantics of [ViewCtrl._updateViewEntries]
/// (only `emit` is injected; map errors are caught and treated as "no emit",
/// matching CouchDB which logs and skips errored documents).
class ViewMapFilter {
  final JsEngine _engine;
  bool _disposed = false;

  ViewMapFilter._(this._engine);

  factory ViewMapFilter(String mapFunction) {
    final engine = JsEngine();
    // emit() only needs to record THAT something was emitted, not the payload.
    engine.evaluate('''
      var emitted = [];
      function emit(key, value) { emitted.push(1); }
    ''');
    engine.evaluate('var mapFunction = $mapFunction;');
    return ViewMapFilter._(engine);
  }

  /// Returns true if running the map function over [docJson] emits ≥1 row.
  ///
  /// Returns false if the map throws (CouchDB logs and skips such documents).
  /// For tombstones (`{_id, _rev, _deleted:true}`) the map typically accesses
  /// absent fields and emits nothing, so deletions are excluded — see the
  /// `filter=_view` deletion caveat documented on `changes()`.
  bool emits(Map<String, dynamic> docJson) {
    if (_disposed) throw StateError('ViewMapFilter has been disposed');
    final result = _engine.evaluate('''
      (function() {
        emitted = [];
        try {
          mapFunction(${jsonEncode(docJson)});
          return emitted.length;
        } catch (e) {
          return -1;
        }
      })()
    ''');
    if (result.isError) return false;
    final n = int.tryParse(result.stringResult.trim()) ?? 0;
    return n > 0;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _engine.dispose();
  }
}
