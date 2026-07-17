import 'dart:async';

import 'dart_couch_db.dart';
import 'messages/changes_result.dart';
import 'messages/couch_document_base.dart';
import 'messages/view_result.dart';
import 'view_diff.dart';

/// A PouchDB-like reactive API mixin for DartCouchDb.
///
/// Provides `useDocument` and `useView` functions that return streams
/// of resources that automatically update when changes occur.
///
/// Example usage:
/// ```dart
/// // Watch a document for changes
/// final docStream = db.useDocument('my-doc-id');
/// await for (final doc in docStream) {
///   print('Document updated: ${doc?.id} rev ${doc?.rev}');
/// }
///
/// // Watch a view for changes
/// final viewStream = db.useView('mydesign/myview');
/// await for (final result in viewStream) {
///   print('View has ${result.totalRows} rows');
/// }
/// ```
mixin UseDartCouchMixin {
  // Abstract methods that the host class must implement
  Stream<ChangesResult> changes({
    List<String>? docIds,
    bool descending = false,
    FeedMode feedmode = FeedMode.normal,
    int heartbeat = 30000,
    bool includeDocs = false,
    bool attachments = false,
    bool attEncodingInfo = false,
    int? lastEventId,
    int limit = 0,
    String? since,
    bool styleAllDocs = false,
    int? timeout,
    int? seqInterval,
    ChangesFilter? filter,
    String? view,
  });

  Future<CouchDocumentBase?> get(
    String docid, {
    String? rev,
    bool revs = false,
    bool revsInfo = false,
    bool attachments = false,
    bool conflicts = false,
    bool deletedConflicts = false,
    bool meta = false,
  });

  Future<ViewResult?> query(
    String viewPathShort, {
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
  });

  Future<ViewResult> allDocs({
    bool includeDocs = false,
    bool attachments = false,
    String? startkey,
    String? endkey,
    bool inclusiveEnd = true,
    int? limit,
    int? skip,
    bool descending = false,
    String? key,
    List<String>? keys,
  });

  // Shared changes stream - only one HTTP connection for all subscribers
  StreamSubscription<ChangesResult>? _sharedChangesSub;
  final StreamController<ChangesResult> _changesController =
      StreamController<ChangesResult>.broadcast();

  void _ensureChangesStream() {
    _sharedChangesSub ??=
        changes(
          feedmode: FeedMode.continuous,
          since: 'now',
          includeDocs: false,
          // 30 s heartbeat keeps the connection alive well within the typical
          // 60-second proxy_read_timeout of reverse proxies such as Synology nginx.
          heartbeat: 30000,
        ).listen(
          (change) => _changesController.add(change),
          onError: (error) => _changesController.addError(error),
          cancelOnError: false,
        );
  }

  void _startChangesListener() {
    _ensureChangesStream();
  }

  void _stopChangesListener() {
    // Only stop if there are no more listeners
    if (!_changesController.hasListener) {
      unawaited(_sharedChangesSub?.cancel() ?? Future.value());
      _sharedChangesSub = null;
    }
  }

  Stream<ChangesResult> get _sharedChanges => _changesController.stream;

  void dispose() {
    unawaited(_sharedChangesSub?.cancel() ?? Future.value());
    _sharedChangesSub = null;
    unawaited(_changesController.close());
  }

  /// Creates a reactive stream that emits the current state of a document
  /// whenever it changes in the database.
  ///
  /// The stream will:
  /// - Emit the current document state immediately upon subscription
  /// - Emit updates whenever the document changes (create, update, delete)
  /// - Emit null if the document is deleted or doesn't exist
  /// - Continue until the stream is cancelled
  ///
  /// Parameters:
  /// - [docId]: The document ID to watch
  /// - [attachments]: Whether to include attachments (default: false)
  ///
  /// Returns a broadcast stream that can be listened to by multiple subscribers.
  ///
  /// Example:
  /// ```dart
  /// final docStream = db.useDocument('user-123');
  /// final subscription = docStream.listen((doc) {
  ///   if (doc == null) {
  ///     print('Document deleted or not found');
  ///   } else {
  ///     print('Document: ${doc.id}, Rev: ${doc.rev}');
  ///   }
  /// });
  ///
  /// // Later: cancel the subscription
  /// await subscription.cancel();
  /// ```
  Stream<CouchDocumentBase?> useDoc(
    String docId, {
    bool attachments = false,
    int debounceMs = 300,
  }) {
    late StreamController<CouchDocumentBase?> controller;
    StreamSubscription? changesSub;
    Timer? debounceTimer;

    Future<void> fetchAndEmit() async {
      if (!controller.hasListener) return;

      try {
        final doc = await get(docId, attachments: attachments);
        if (controller.hasListener && !controller.isClosed) {
          controller.add(doc);
        }
      } catch (e) {
        if (controller.hasListener && !controller.isClosed) {
          controller.addError(e);
        }
      }
    }

    void startListening() {
      _startChangesListener();

      // Emit initial state
      unawaited(fetchAndEmit());

      // Listen to shared changes feed, filtering for our specific document
      changesSub = _sharedChanges.listen(
        (change) {
          bool docChanged = false;
          bool isDeleted = false;

          // Extract document change information based on change type
          if (change.type == ChangesResultType.continuous) {
            final entry = change.continuous;
            if (entry?.id == docId) {
              docChanged = true;
              isDeleted = entry?.deleted ?? false;
            }
          } else if (change.type == ChangesResultType.normal) {
            // Check normal results
            final entry = change.normal?.results.firstWhere(
              (r) => r.id == docId,
              orElse: () =>
                  ChangeEntry(id: '', seq: '0', changes: [], deleted: false),
            );
            if (entry != null && entry.id == docId) {
              // Check if we found the actual document
              docChanged = true;
              isDeleted = entry.deleted;
            }
          }

          if (!docChanged) return;

          // Handle deletion immediately - emit null without fetching
          if (isDeleted) {
            if (controller.hasListener && !controller.isClosed) {
              controller.add(null);
            }
            return;
          }

          // For non-deleted changes, debounce and fetch the latest state
          debounceTimer?.cancel();
          debounceTimer = Timer(Duration(milliseconds: debounceMs), () {
            if (controller.hasListener) unawaited(fetchAndEmit());
          });
        },
        onError: (error) {
          if (controller.hasListener && !controller.isClosed) {
            controller.addError(error);
          }
        },
        cancelOnError: false,
      );
    }

    controller = StreamController<CouchDocumentBase?>.broadcast(
      onListen: startListening,
      onCancel: () {
        debounceTimer?.cancel();
        unawaited(changesSub?.cancel() ?? Future.value());
        _stopChangesListener();
      },
    );

    return controller.stream;
  }

  /// Creates a reactive stream that emits the current state of a view
  /// whenever any document affecting the view changes.
  ///
  /// The stream will:
  /// - Emit the current view result immediately upon subscription
  /// - Emit updates whenever documents in the view's index change
  /// - Continue until the stream is cancelled
  /// - if the view does not exist yet, emits null until it is created
  /// - if the view exists but has no rows, emits an empty ViewResult
  /// - if the view is deleted, emits null
  ///
  /// Parameters:
  /// - [viewPathShort]: The view path in format "designDoc/viewName"
  /// - [includeDocs]: Whether to include full documents in results (default: false)
  /// - [attachments]: Whether to include attachments (default: false)
  /// - [startkey]: Optional start key for range queries
  /// - [endkey]: Optional end key for range queries
  /// - [key]: Optional single key to query
  /// - [keys]: Optional list of keys to query
  /// - [limit]: Maximum number of rows to return
  /// - [skip]: Number of rows to skip
  /// - [descending]: Reverse sort order (default: false)
  /// - [group]: Enable grouping for reduce views (default: false)
  /// - [groupLevel]: Group level for reduce views
  /// - [reduce]: Whether to use reduce function (default: true)
  /// - [debounceMs]: Milliseconds to wait before re-querying after changes (default: 300)
  ///
  /// Returns a broadcast stream that can be listened to by multiple subscribers.
  ///
  /// Example:
  /// ```dart
  /// final viewStream = db.useView(
  ///   'mydesign/byDate',
  ///   startkey: '2023-01-01',
  ///   endkey: '2023-12-31',
  ///   includeDocs: true,
  /// );
  ///
  /// await for (final result in viewStream) {
  ///   print('View has ${result.totalRows} total rows');
  ///   for (final row in result.rows) {
  ///     print('  ${row.key}: ${row.value}');
  ///   }
  /// }
  /// ```
  Stream<ViewResult?> useView(
    String viewPathShort, {
    bool includeDocs = false,
    bool attachments = false,
    String? startkey,
    String? endkey,
    String? key,
    List<String>? keys,
    int? limit,
    int? skip,
    bool descending = false,
    bool group = false,
    int? groupLevel,
    bool reduce = true,
    int debounceMs = 300,
  }) {
    late StreamController<ViewResult?> controller;
    StreamSubscription? changesSub;
    Timer? debounceTimer;

    // Incremental document cache for the includeDocs path: document bodies are
    // keyed by doc id and reused across emits, so only documents that actually
    // changed are re-fetched instead of re-loading the whole view on every
    // change. [dirtyIds] accumulates the ids reported by the shared changes
    // feed since the last emit. Both are unused when includeDocs is false.
    final Map<String, CouchDocumentBase> docCache =
        <String, CouchDocumentBase>{};
    Set<String> dirtyIds = <String>{};

    Future<void> fetchAndEmit() async {
      if (!controller.hasListener) return;

      try {
        // Cheap path: no document bodies to materialise (also covers reduce
        // queries, where includeDocs is invalid). The view query is already
        // lightweight, so emit its result directly.
        if (!includeDocs) {
          final result = await query(
            viewPathShort,
            includeDocs: false,
            attachments: attachments,
            startkey: startkey,
            endkey: endkey,
            key: key,
            keys: keys,
            limit: limit,
            skip: skip,
            descending: descending,
            group: group,
            groupLevel: groupLevel,
            reduce: reduce,
          );
          if (controller.hasListener && !controller.isClosed) {
            controller.add(result);
          }
          return;
        }

        // Incremental path. Snapshot and reset the set of ids changed since the
        // last emit; any change arriving during this run accumulates into the
        // fresh set and triggers a subsequent emit (eventual consistency).
        final Set<String> dirty = dirtyIds;
        dirtyIds = <String>{};

        // 1. Query view metadata only (id/key/value) — no document bodies.
        final meta = await query(
          viewPathShort,
          includeDocs: false,
          attachments: false,
          startkey: startkey,
          endkey: endkey,
          key: key,
          keys: keys,
          limit: limit,
          skip: skip,
          descending: descending,
          group: group,
          groupLevel: groupLevel,
          reduce: reduce,
        );

        if (meta == null) {
          docCache.clear();
          if (controller.hasListener && !controller.isClosed) {
            controller.add(null);
          }
          return;
        }

        // 2. Decide which document bodies must be (re)fetched: those reported
        //    changed since the last emit, and any not already cached.
        final Set<String> liveIds = <String>{};
        final List<String> needed = <String>[];
        for (final row in meta.rows) {
          final id = row.id;
          if (id == null) continue;
          if (liveIds.add(id)) {
            if (dirty.contains(id) || !docCache.containsKey(id)) {
              needed.add(id);
            }
          }
        }

        // 3. Evict cached bodies no longer present in the view (e.g. deleted or
        //    no longer matched by the map). This is how deletions leave the
        //    result on the unfiltered changes feed.
        docCache.removeWhere((id, _) => !liveIds.contains(id));

        // 4. Batch-fetch only the needed bodies and refresh the cache.
        if (needed.isNotEmpty) {
          final fetched = await allDocs(
            keys: needed,
            includeDocs: true,
            attachments: attachments,
          );
          for (final row in fetched.rows) {
            final id = row.id;
            final doc = row.doc;
            if (id != null && doc != null) {
              docCache[id] = doc;
            }
          }
        }

        // 5. Assemble the snapshot, attaching cached bodies to metadata rows.
        final rows = meta.rows
            .map(
              (r) => ViewEntry(
                id: r.id,
                key: r.key,
                value: r.value,
                doc: r.id == null ? null : docCache[r.id],
                error: r.error,
              ),
            )
            .toList();

        if (controller.hasListener && !controller.isClosed) {
          controller.add(
            ViewResult(
              totalRows: meta.totalRows,
              offset: meta.offset,
              rows: rows,
            ),
          );
        }
      } catch (e) {
        if (controller.hasListener && !controller.isClosed) {
          controller.addError(e);
        }
      }
    }

    void startListening() {
      _startChangesListener();

      // Emit initial state
      unawaited(fetchAndEmit());

      // Listen to the shared (unfiltered) changes feed. The feed is unfiltered
      // so deletions are observed too — essential for the incremental path to
      // drop deleted rows from the result. Each change records its doc id as
      // dirty (so its body is re-fetched) and schedules a debounced re-query.
      changesSub = _sharedChanges.listen(
        (change) {
          // Skip local documents and design documents unless they affect views
          String? changedDocId;

          if (change.type == ChangesResultType.continuous) {
            changedDocId = change.continuous?.id;
          } else if (change.type == ChangesResultType.normal) {
            // For normal mode, any change might affect the view
            if (change.normal?.results.isEmpty ?? true) return;
            changedDocId = change.normal!.results.first.id;
          }

          // Skip local documents (they don't appear in views)
          if (changedDocId?.startsWith('_local/') ?? false) {
            return;
          }

          // Mark the changed document for re-fetch on the next emit.
          if (includeDocs && changedDocId != null) {
            dirtyIds.add(changedDocId);
          }

          // Debounce to avoid excessive re-queries
          debounceTimer?.cancel();
          debounceTimer = Timer(Duration(milliseconds: debounceMs), () {
            if (controller.hasListener) unawaited(fetchAndEmit());
          });
        },
        onError: (error) {
          if (controller.hasListener && !controller.isClosed) {
            controller.addError(error);
          }
        },
        cancelOnError: false,
      );
    }

    controller = StreamController<ViewResult?>.broadcast(
      onListen: startListening,
      onCancel: () {
        debounceTimer?.cancel();
        unawaited(changesSub?.cancel() ?? Future.value());
        _stopChangesListener();
      },
    );

    return controller.stream;
  }

  /// Like [useView], but emits the view **with its changes**: a [ViewUpdate]
  /// that is either a full [ViewSnapshot] or an incremental [ViewChanges] batch.
  ///
  /// - The first event is always a [ViewSnapshot] (the same `ViewResult` shape
  ///   [useView] emits) — render it directly, no diffing needed.
  /// - Subsequent events are [ViewChanges] (an ordered [ViewRowChange] edit
  ///   script) whenever the rows change — apply them to the list you hold.
  /// - If the view appears or disappears (a null boundary), a fresh
  ///   [ViewSnapshot] is emitted instead of a delta, so you rebuild cleanly.
  ///
  /// This lets a UI rebuild (or animate) only the rows that actually changed.
  /// The returned stream is single-subscription: each `listen` starts its own
  /// underlying [useView] subscription and its own initial snapshot.
  ///
  /// Parameters are identical to [useView].
  Stream<ViewUpdate> useViewWithChanges(
    String viewPathShort, {
    bool includeDocs = false,
    bool attachments = false,
    String? startkey,
    String? endkey,
    String? key,
    List<String>? keys,
    int? limit,
    int? skip,
    bool descending = false,
    bool group = false,
    int? groupLevel,
    bool reduce = true,
    int debounceMs = 300,
  }) {
    return _diffViewResultStream(
      () => useView(
        viewPathShort,
        includeDocs: includeDocs,
        attachments: attachments,
        startkey: startkey,
        endkey: endkey,
        key: key,
        keys: keys,
        limit: limit,
        skip: skip,
        descending: descending,
        group: group,
        groupLevel: groupLevel,
        reduce: reduce,
        debounceMs: debounceMs,
      ),
    );
  }

  /// Wraps a [ViewResult] snapshot stream (such as [useView] or [useAllDocs])
  /// into a [ViewUpdate] stream: the first event and any null boundary become a
  /// [ViewSnapshot]; two consecutive non-null results become an incremental
  /// [ViewChanges] (skipped when nothing changed). Single-subscription, so each
  /// listener gets its own [source] subscription and its own initial snapshot.
  Stream<ViewUpdate> _diffViewResultStream(
    Stream<ViewResult?> Function() source,
  ) {
    late StreamController<ViewUpdate> controller;
    StreamSubscription<ViewResult?>? sub;
    ViewResult? previous;
    bool hasPrevious = false;

    controller = StreamController<ViewUpdate>(
      onListen: () {
        sub = source().listen(
          (current) {
            if (controller.isClosed) return;
            // First event, or a null boundary (view appeared/disappeared):
            // emit a full snapshot rather than diffing across null.
            if (!hasPrevious || previous == null || current == null) {
              hasPrevious = true;
              previous = current;
              controller.add(ViewSnapshot(current));
              return;
            }
            // Both sides present: emit the delta (skip if nothing changed).
            final changes = ViewDiff.compute(previous!.rows, current.rows);
            previous = current;
            if (changes.isNotEmpty) {
              controller.add(ViewChanges(changes));
            }
          },
          onError: (error) {
            if (!controller.isClosed) controller.addError(error);
          },
          cancelOnError: false,
        );
      },
      onCancel: () async {
        await sub?.cancel();
        sub = null;
      },
    );

    return controller.stream;
  }

  /// Creates a reactive stream that emits all documents matching the given keys
  /// whenever any of them change.
  ///
  /// This is similar to `allDocs` but reactive - it will emit updates
  /// whenever any of the specified documents change.
  ///
  /// Parameters:
  /// - [keys]: List of document IDs to watch (required)
  /// - [includeDocs]: Whether to include full documents (default: true)
  /// - [attachments]: Whether to include attachments (default: false)
  /// - [debounceMs]: Milliseconds to wait before re-querying after changes (default: 200)
  ///
  /// Returns a broadcast stream emitting ViewResult with the current state.
  ///
  /// Example:
  /// ```dart
  /// final docsStream = db.useAllDocs(
  ///   keys: ['doc1', 'doc2', 'doc3'],
  ///   includeDocs: true,
  /// );
  ///
  /// await for (final result in docsStream) {
  ///   for (final row in result.rows) {
  ///     print('${row.id}: ${row.doc?.rev}');
  ///   }
  /// }
  /// ```
  Stream<ViewResult?> useAllDocs({
    List<String>? keys,
    bool includeDocs = true,
    bool attachments = false,
    int debounceMs = 300,
  }) {
    late StreamController<ViewResult?> controller;
    StreamSubscription? changesSub;
    Timer? debounceTimer;
    final keysSet = keys != null ? Set<String>.from(keys) : <String>{};

    Future<void> fetchAndEmit() async {
      if (!controller.hasListener) return;

      try {
        final result = await allDocs(
          keys: keys,
          includeDocs: includeDocs,
          attachments: attachments,
        );

        if (controller.hasListener && !controller.isClosed) {
          controller.add(result);
        }
      } catch (e) {
        if (controller.hasListener && !controller.isClosed) {
          controller.addError(e);
        }
      }
    }

    void startListening() {
      _startChangesListener();

      // Emit initial state
      unawaited(fetchAndEmit());

      // Listen to shared changes feed, filtering for our specific documents
      changesSub = _sharedChanges.listen(
        (change) {
          // When no keys filter is specified, every change is relevant
          // (we're watching all documents)
          bool relevantChange = keysSet.isEmpty;

          if (!relevantChange) {
            if (change.type == ChangesResultType.continuous) {
              final id = change.continuous?.id;
              relevantChange = id != null && keysSet.contains(id);
            } else if (change.type == ChangesResultType.normal) {
              relevantChange =
                  change.normal?.results.any((r) => keysSet.contains(r.id)) ??
                  false;
            }
          }

          if (!relevantChange) return;

          // Debounce rapid changes
          debounceTimer?.cancel();
          debounceTimer = Timer(Duration(milliseconds: debounceMs), () {
            if (controller.hasListener) unawaited(fetchAndEmit());
          });
        },
        onError: (error) {
          if (controller.hasListener && !controller.isClosed) {
            controller.addError(error);
          }
        },
        cancelOnError: false,
      );
    }

    controller = StreamController<ViewResult?>.broadcast(
      onListen: startListening,
      onCancel: () {
        debounceTimer?.cancel();
        unawaited(changesSub?.cancel() ?? Future.value());
        _stopChangesListener();
      },
    );

    return controller.stream;
  }

  /// Like [useAllDocs], but emits the documents **with their changes** as a
  /// [ViewUpdate] stream: an initial [ViewSnapshot] followed by incremental
  /// [ViewChanges] deltas. See [useViewWithChanges] for the emission contract.
  ///
  /// Parameters are identical to [useAllDocs].
  Stream<ViewUpdate> useAllDocsWithChanges({
    List<String>? keys,
    bool includeDocs = true,
    bool attachments = false,
    int debounceMs = 300,
  }) {
    return _diffViewResultStream(
      () => useAllDocs(
        keys: keys,
        includeDocs: includeDocs,
        attachments: attachments,
        debounceMs: debounceMs,
      ),
    );
  }
}
