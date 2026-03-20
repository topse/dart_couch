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

  /// Mutex to serialize view updates
  final Mutex _updateMutex = Mutex();

  ViewCtrl({
    required this.dbid,
    required this.db,
    required this.view,
    required this.dbGetFunction,
  });

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
        /// When using the 'keys' parameter (e.g., with _all_docs), we need to find
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
          // Convert normalized key to string for comparison with stored keys
          final String keyAsString = normalizedKey is String
              ? normalizedKey
              : jsonEncode(normalizedKey);
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

      // Debug: Log what we're about to return
      final rows = await Future.wait(
        pagedEntries.map((e) async {
          if (e.entry == null) {
            // For missing documents when using keys parameter, we should return
            // null for id and 'not_found' for error to match CouchDB behavior.
            final result = ViewEntry(
              id: null, // null for non-existent documents
              key: _tryParseJson(e.key),
              value: null,
              error: "not_found",
            );
            return result;
          }
          final result = ViewEntry(
            id: e.entry!.docid,
            key: _tryParseJson(e.entry!.key),
            value: _tryParseJson(e.entry!.value),
            doc: includeDocs == false
                ? null
                : (await dbGetFunction(
                    e.entry!.docid,
                    attachments: attachments,
                  )),
          );
          return result;
        }).toList(),
      );

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

  Future<void> _updateViewEntries() async {
    // 1. find the current updateSeq from the database
    int curUpdateSeq = await db.getCurrentUpdateSeq(view.database);

    log.info(
      '_updateViewEntries: curUpdateSeq=$curUpdateSeq, view.updateSeq=${view.updateSeq}, viewId=${view.id}',
    );

    // check if a view update is needed
    if (curUpdateSeq == view.updateSeq) {
      log.info('_updateViewEntries: View is up to date, skipping');
      return;
    }

    // 2. get all documents, that have a higher sequence number than the last views update sequence
    List<LocalDocumentWithBlob> docs = await db.getDocuments(
      dbid,
      true,
      seqNumber: view.updateSeq,
    );

    log.info('_updateViewEntries: Got ${docs.length} documents to process');

    if (docs.isEmpty) return;

    // start the javascript engine
    final jsEngine = JsEngine();

    try {
      // 3. Setup the JavaScript environment with emit function
      jsEngine.evaluate('''
        var exception = null;
        var emitted = [];
        function emit(key, value) {
          emitted.push({key: key, value: value});
        }
      ''');

      // Inject the map function into the runtime
      jsEngine.evaluate('var mapFunction = ${view.mapFunction};');

      // 3b. Process each document with the map function
      for (var doc in docs) {
        // Skip _local documents - they are never replicated or indexed in views
        if (doc.document.docid.startsWith('_local/')) continue;

        // Special handling for design documents:
        // - For _all_docs view: include design documents (CouchDB behavior)
        // - For custom views: exclude design documents from results
        // - BUT: we still need to process design documents internally for view management
        //   to detect when view definitions change
        if (doc.document.docid.startsWith('_design/')) {
          // Only include design documents in _all_docs view results
          // For custom views, skip them in the final results but still process them
          // for view management purposes
          if (view.viewPathShort != '_all_docs') {
            continue;
          }
        }

        // Handle deleted documents: remove old view entries and skip map function
        if (doc.document.deleted == true) {
          await _removeOldViewEntries(doc.document.docid);
          continue;
        }

        // Clear previous emitted results
        jsEngine.evaluate('emitted = []; exception = null;');

        if (doc.data == null) {
          log.warning(
            'Document ${doc.document.docid} has no blob data, skipping view indexing',
          );
          continue;
        }

        // Execute map function for the document
        final mapResult = jsEngine.evaluate('''
          try {
            mapFunction(${doc.data});
          } catch (e) {
            console.error('Map function error for doc ${doc.document.docid}: ' + e.toString());
            exception = e;
          }
        ''');

        if (mapResult.isError) {
          log.severe(
            'JS evaluation failed for document ${doc.document.docid}: ${mapResult.stringResult}',
          );
          continue;
        }

        // check exception
        final JsEvalResult e = jsEngine.evaluate('exception;');
        if (!e.isError && e.stringResult != 'null') {
          log.severe(
            'Error in map function for document ${doc.document.docid}: ${e.stringResult}',
          );
          // CouchDB behavior: log the error but continue processing other documents
          // Skip this document and continue with the next one
          continue;
        }

        // Get emitted results
        final JsEvalResult result = jsEngine.evaluate(
          'JSON.stringify(emitted)',
        );
        if (!result.isError && result.stringResult != 'undefined') {
          final List<dynamic> emittedResults = List<dynamic>.from(
            jsonDecode(result.stringResult),
          );

          /*if (emittedResults.isNotEmpty) {
            log.fine(
              'Document ${doc.document.docid} emitted ${emittedResults.length} results',
            );
          }*/

          // First remove old view entries for this document
          await _removeOldViewEntries(doc.document.docid);

          // Then store new view entries
          for (var emitted in emittedResults) {
            await _storeViewEntry(
              docid: doc.document.docid,
              seqNumber: doc.document.seq,
              key: emitted['key'],
              value: emitted['value'],
            );
          }
        }
      }

      // 4. Update the last indexed sequence number in the views table
      await _updateViewSequence(curUpdateSeq);

      // Reload the view object to get the updated updateSeq
      final updatedView = await (db.select(
        db.localViews,
      )..where((tbl) => tbl.id.equals(view.id))).getSingle();
      view = updatedView;

      // Log how many entries were stored
      final entryCount =
          await (db.selectOnly(db.localViewEntries)
                ..addColumns([db.localViewEntries.id.count()])
                ..where(db.localViewEntries.fkview.equals(view.id)))
              .getSingle();
      log.info(
        'View now has ${entryCount.read(db.localViewEntries.id.count())} entries, updateSeq updated to ${view.updateSeq}',
      );
    } catch (e) {
      log.severe('Error executing JavaScript map function: $e');
      rethrow; // Re-throw the error to let the caller handle it
    } finally {
      jsEngine.dispose();
    }
  }

  Future<void> _removeOldViewEntries(String docid) async {
    await (db.delete(
          db.localViewEntries,
        )..where((tbl) => tbl.fkview.equals(view.id) & tbl.docid.equals(docid)))
        .go();
  }

  Future<void> _storeViewEntry({
    required String docid,
    required int seqNumber,
    required dynamic key,
    required dynamic value,
  }) async {
    try {
      await db
          .into(db.localViewEntries)
          .insert(
            LocalViewEntriesCompanion.insert(
              fkview: view.id,
              docid: docid,
              key: jsonEncode(key),
              value: jsonEncode(value),
            ),
          );
    } catch (e) {
      log.severe('Failed to store view entry for $docid: $e');
      rethrow;
    }
  }

  Future<void> _updateViewSequence(int sequence) async {
    await (db.update(db.localViews)..where((tbl) => tbl.id.equals(view.id)))
        .write(LocalViewsCompanion(updateSeq: Value(sequence)));
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

class _ViewEntryIntermediate {
  final String key;
  final LocalViewEntry? entry;
  _ViewEntryIntermediate(this.key, this.entry);
}
