import 'dart:async';
import 'dart:collection';

import 'package:logging/logging.dart';

import 'dart_couch_db.dart';
import 'local_storage_engine/db_query_stats.dart';
import 'messages/changes_result.dart';
import 'messages/couch_document_base.dart';
import 'messages/view_result.dart';
import 'view_diff.dart';

final Logger _useLog = Logger('dart_couch-use');

/// Schedules the fetch-and-emit work of one `use*` subscription.
///
/// - Trailing debounce of `debounceMs`, bounded by a max wait of
///   `max(1000 ms, 3 x debounceMs)`, so continuous writes cannot postpone an
///   emit forever.
/// - Single-flight: the run callback never executes concurrently. A request
///   arriving while a run is in flight sets a rerun flag; exactly one more run
///   follows the current one, so the final state is always emitted.
/// - [cancel] stops timers and pending reruns.
class _EmitScheduler {
  _EmitScheduler(this._run, int debounceMs, this._registry)
    : _debounce = Duration(milliseconds: debounceMs),
      _maxWait = Duration(
        milliseconds: debounceMs * 3 > 1000 ? debounceMs * 3 : 1000,
      ) {
    _registry.add(this);
  }

  final Future<void> Function() _run;

  /// The live schedulers of one mixin instance (see
  /// [UseDartCouchMixin.useIdle]). A cancelled scheduler leaves it once its
  /// last run has finished.
  final Set<_EmitScheduler> _registry;

  /// No emit is scheduled (debounce / max-wait timer) or running.
  bool get idle =>
      !_running && _debounceTimer == null && _maxWaitTimer == null;
  final Duration _debounce;
  final Duration _maxWait;
  Timer? _debounceTimer;
  Timer? _maxWaitTimer;
  bool _running = false;
  bool _rerun = false;
  bool _cancelled = false;

  /// Debounced request (used for change notifications).
  void schedule() {
    if (_cancelled) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _fire);
    _maxWaitTimer ??= Timer(_maxWait, _fire);
  }

  void _fire() {
    _clearTimers();
    request();
  }

  /// Immediate request (initial emit); coalesced if a run is in flight.
  void request() {
    if (_cancelled) return;
    if (_running) {
      _rerun = true;
      return;
    }
    _running = true;
    unawaited(_loop());
  }

  Future<void> _loop() async {
    try {
      do {
        _rerun = false;
        await _run();
      } while (_rerun && !_cancelled);
    } finally {
      _running = false;
      if (_cancelled) _registry.remove(this);
    }
  }

  void _clearTimers() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _maxWaitTimer?.cancel();
    _maxWaitTimer = null;
  }

  void cancel() {
    _cancelled = true;
    _rerun = false;
    _clearTimers();
    if (!_running) _registry.remove(this);
  }
}

/// Counters of the document-body cache shared by the `use*` streams of one
/// database instance ([UseDartCouchMixin.useCacheStats]). Diagnostics and
/// tests only; the numbers carry no consistency meaning.
class UseCacheStats {
  UseCacheStats._(this._cache);

  final _DocBodyCache _cache;
  int _hits = 0;
  int _joined = 0;
  int _fetchedDocs = 0;
  int _fetches = 0;
  int _invalidations = 0;

  /// Bodies served from the cache (rev matched).
  int get hits => _hits;

  /// Bodies served by a fetch another subscription already had in flight.
  int get joined => _joined;

  /// Document ids requested from the database by body fetches.
  int get fetchedDocs => _fetchedDocs;

  /// Body fetches issued (`allDocs(keys: …, includeDocs: true)` calls).
  int get fetches => _fetches;

  /// Full invalidations (changes feed error / end / restart).
  int get invalidations => _invalidations;

  /// Bodies currently cached (referenced ones plus the LRU tail).
  int get entries => _cache._entries.length;

  /// Cached bodies no subscription references (bounded by the capacity).
  int get unreferenced => _cache._lru.length;

  /// Resets the counters (not the cache contents).
  void reset() {
    _hits = 0;
    _joined = 0;
    _fetchedDocs = 0;
    _fetches = 0;
    _invalidations = 0;
  }

  @override
  String toString() =>
      'UseCacheStats(hits: $_hits, joined: $_joined, fetches: $_fetches, '
      'fetchedDocs: $_fetchedDocs, invalidations: $_invalidations, '
      'entries: $entries, unreferenced: $unreferenced)';
}

class _CacheEntry {
  _CacheEntry(this.rev, this.doc);
  final String rev;
  final CouchDocumentBase doc;
}

/// Bodies at exactly the requested revs, plus the ids whose requested rev
/// could not be obtained even by a fresh fetch (the document moved on or
/// vanished since the caller's metadata was read).
class _Resolved {
  _Resolved(this.docs, this.stale, this.fetched);
  final Map<String, CouchDocumentBase> docs;
  final Set<String> stale;

  /// Ids that had to be fetched by this call (diagnostics).
  final int fetched;
}

class _FetchBatch {
  final Set<String> ids = <String>{};
  final Completer<Map<String, ViewEntry>> completer =
      Completer<Map<String, ViewEntry>>();
}

/// Read-only document-body cache serving only the `use*` streams.
///
/// Consistency model — the cache never decides *which* revision is current:
/// - A body is keyed by `(id, rev)`. A CouchDB revision identifies immutable
///   content, so a cached body can never be "wrong" for its rev; staleness is
///   only a question of which rev is current.
/// - The current rev always comes from a fresh source owned by the caller:
///   the `value.rev` of a metadata row queried for this very emit, or the
///   winning rev of the newest changes-feed event (useDoc). A body is served
///   only on an exact rev match ([peek] / [resolve]); anything else is
///   fetched.
/// - Fetches go through `allDocs(keys: …, includeDocs: true)` only and the
///   returned rows are verified again (`doc.rev == value.rev == wanted`).
///   Joining another subscription's in-flight fetch is allowed because its
///   result is rev-checked too; a mismatch triggers a fresh fetch that starts
///   after the caller's metadata was read.
/// - Feed events drop superseded / deleted bodies; a feed error, end or
///   restart drops everything ([invalidateAll]) and in-flight results from
///   before the invalidation are not stored.
/// - Nothing is ever written to any database; direct API calls never see it.
///
/// Memory: bodies are reference-counted by the ids the subscriptions'
/// current emits reference. Unreferenced bodies stay in an LRU bounded by
/// [capacity] (0 = evict immediately).
class _DocBodyCache {
  _DocBodyCache(this._fetch, {int capacity = 1000})
    : _capacity = capacity < 0 ? 0 : capacity;

  final Future<ViewResult> Function(List<String> ids) _fetch;
  final Map<String, _CacheEntry> _entries = <String, _CacheEntry>{};
  final Map<String, int> _refCounts = <String, int>{};

  /// Ids with a cached body and refCount 0, least recently used first.
  final LinkedHashSet<String> _lru = LinkedHashSet<String>();
  final Map<String, _FetchBatch> _inflight = <String, _FetchBatch>{};
  _FetchBatch? _pending;
  int _generation = 0;
  int _capacity;
  late final UseCacheStats stats = UseCacheStats._(this);

  int get capacity => _capacity;
  set capacity(int value) {
    _capacity = value < 0 ? 0 : value;
    _trim();
  }

  /// The cached body of [id] if it is at exactly [rev].
  CouchDocumentBase? peek(String id, String rev) {
    final e = _entries[id];
    if (e == null || e.rev != rev) return null;
    if (_lru.remove(id)) _lru.add(id);
    return e.doc;
  }

  /// Offers a body obtained by a direct `get` (useDoc). Stored under its own
  /// rev; never used to decide which rev is current.
  void offer(String id, CouchDocumentBase doc) {
    final rev = doc.rev;
    if (rev == null || doc.deleted || doc.id != id) return;
    _store(id, rev, doc);
  }

  void retain(Iterable<String> ids) {
    for (final id in ids) {
      final c = (_refCounts[id] ?? 0) + 1;
      _refCounts[id] = c;
      if (c == 1) _lru.remove(id);
    }
  }

  void release(Iterable<String> ids) {
    for (final id in ids) {
      final c = (_refCounts[id] ?? 0) - 1;
      if (c > 0) {
        _refCounts[id] = c;
        continue;
      }
      _refCounts.remove(id);
      if (_entries.containsKey(id)) {
        _lru.remove(id);
        _lru.add(id);
      }
    }
    _trim();
  }

  /// Drops bodies superseded by a changes-feed event. Entries are rev-keyed,
  /// so this is about memory, not correctness — except that an event of an
  /// unknown shape (no rev) conservatively drops the entry.
  void onChange(ChangesResult change) {
    void apply(ChangeEntry e) {
      final rev = e.changes.isNotEmpty ? e.changes.first.rev : null;
      if (e.deleted || rev == null || _entries[e.id]?.rev != rev) {
        _drop(e.id);
      }
    }

    if (change.type == ChangesResultType.continuous) {
      final e = change.continuous;
      if (e != null) apply(e);
    } else {
      final results = change.normal?.results;
      if (results == null) {
        invalidateAll();
        return;
      }
      results.forEach(apply);
    }
  }

  /// Forgets every body. Reference counts are kept (they mirror what live
  /// subscriptions hold and are balanced by their releases).
  void invalidateAll() {
    _entries.clear();
    _lru.clear();
    _generation++;
    stats._invalidations++;
  }

  /// Returns the bodies of `want` (id → rev) at exactly those revs.
  Future<_Resolved> resolve(Map<String, String> want) async {
    final docs = <String, CouchDocumentBase>{};
    final stale = <String>{};
    final joined = <_FetchBatch, List<String>>{};
    final fresh = <String>[];
    want.forEach((id, rev) {
      final hit = peek(id, rev);
      if (hit != null) {
        docs[id] = hit;
        stats._hits++;
        return;
      }
      final batch = _inflight[id];
      if (batch != null) {
        (joined[batch] ??= <String>[]).add(id);
      } else {
        fresh.add(id);
      }
    });
    if (joined.isEmpty && fresh.isEmpty) return _Resolved(docs, stale, 0);

    // Dispatch the fresh request right away so it runs concurrently with the
    // joined ones; Future.wait observes every error.
    final joinedBatches = joined.keys.toList(growable: false);
    final results = await Future.wait<Map<String, ViewEntry>>([
      for (final b in joinedBatches) b.completer.future,
      if (fresh.isNotEmpty) _fetchFresh(fresh),
    ]);

    final retry = <String>[];
    for (var i = 0; i < joinedBatches.length; i++) {
      final rows = results[i];
      for (final id in joined[joinedBatches[i]]!) {
        final d = _docAt(rows[id], want[id]!);
        if (d != null) {
          docs[id] = d;
          stats._joined++;
        } else {
          retry.add(id);
        }
      }
    }
    if (fresh.isNotEmpty) {
      final rows = results.last;
      for (final id in fresh) {
        final d = _docAt(rows[id], want[id]!);
        if (d != null) {
          docs[id] = d;
        } else {
          stale.add(id);
        }
      }
    }
    if (retry.isNotEmpty) {
      // The joined fetch may have started before the caller's metadata was
      // read: fetch again, strictly after it.
      final rows = await _fetchFresh(retry);
      for (final id in retry) {
        final d = _docAt(rows[id], want[id]!);
        if (d != null) {
          docs[id] = d;
        } else {
          stale.add(id);
        }
      }
    }
    return _Resolved(docs, stale, fresh.length + retry.length);
  }

  static CouchDocumentBase? _docAt(ViewEntry? row, String rev) {
    if (row == null || row.error != null) return null;
    final doc = row.doc;
    final value = row.value;
    if (doc == null || doc.rev != rev || doc.deleted) return null;
    if (value is! Map || value['rev'] != rev || value['deleted'] == true) {
      return null;
    }
    return doc;
  }

  /// Fetch [ids] in a batch that is dispatched after this call (collected in
  /// a microtask window with other callers' fresh requests).
  Future<Map<String, ViewEntry>> _fetchFresh(Iterable<String> ids) {
    var batch = _pending;
    if (batch == null) {
      batch = _pending = _FetchBatch();
      scheduleMicrotask(_dispatch);
    }
    batch.ids.addAll(ids);
    return batch.completer.future;
  }

  void _dispatch() {
    final batch = _pending;
    if (batch == null) return;
    _pending = null;
    final ids = batch.ids.toList(growable: false);
    for (final id in ids) {
      _inflight[id] = batch;
    }
    stats._fetches++;
    stats._fetchedDocs += ids.length;
    batch.completer.complete(_runFetch(batch, ids, _generation));
  }

  Future<Map<String, ViewEntry>> _runFetch(
    _FetchBatch batch,
    List<String> ids,
    int generation,
  ) async {
    try {
      final result = await _fetch(ids);
      final byId = <String, ViewEntry>{};
      for (final row in result.rows) {
        final id = row.id;
        if (id != null) byId.putIfAbsent(id, () => row);
      }
      // Results of a fetch that started before an invalidation are handed to
      // the (rev-checking) waiters but not stored.
      if (generation == _generation) {
        byId.forEach((id, row) {
          final value = row.value;
          final rev = value is Map ? value['rev'] : null;
          if (rev is String && _docAt(row, rev) != null) {
            _store(id, rev, row.doc!);
          }
        });
      }
      return byId;
    } finally {
      for (final id in ids) {
        if (identical(_inflight[id], batch)) _inflight.remove(id);
      }
    }
  }

  void _store(String id, String rev, CouchDocumentBase doc) {
    _entries[id] = _CacheEntry(rev, doc);
    _lru.remove(id);
    if ((_refCounts[id] ?? 0) == 0) {
      _lru.add(id);
      _trim();
    }
  }

  void _drop(String id) {
    _entries.remove(id);
    _lru.remove(id);
  }

  void _trim() {
    while (_lru.length > _capacity) {
      final id = _lru.first;
      _lru.remove(id);
      _entries.remove(id);
    }
  }

  void clear() {
    _entries.clear();
    _lru.clear();
    _refCounts.clear();
    _generation++;
  }
}

/// The ids one subscription currently references in a [_DocBodyCache].
class _BodyRefs {
  _BodyRefs(this._cache);
  final _DocBodyCache _cache;
  Set<String> _held = <String>{};
  // After releaseAll (subscription cancelled) a still-running emit must not
  // take new references that nobody would release.
  bool _closed = false;

  bool get isClosed => _closed;

  /// Adds references (before fetching), keeping the existing ones.
  void retain(Set<String> ids) {
    if (_closed) return;
    final add = ids.difference(_held);
    if (add.isEmpty) return;
    _cache.retain(add);
    _held = _held.union(add);
  }

  /// After an emit: reference exactly [ids].
  void settle(Set<String> ids) {
    if (_closed) return;
    retain(ids);
    final drop = _held.difference(ids);
    _held = Set<String>.of(ids);
    if (drop.isNotEmpty) _cache.release(drop);
  }

  void releaseAll() {
    _closed = true;
    final drop = _held;
    _held = <String>{};
    if (drop.isNotEmpty) _cache.release(drop);
  }
}

/// Number of metadata/body passes a cached emit attempts before it falls back
/// to the plain (uncached) query. Retries only happen under concurrent writes.
const int _maxCachedAttempts = 3;

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
///
/// ## Shared document bodies
///
/// The `includeDocs: true` streams ([useAllDocs], [useView],
/// [useViewWithChanges], [useAllDocsWithChanges]) and [useDoc] of one
/// database instance share a read-only cache of document bodies keyed by
/// `(id, rev)`: a changed document is fetched once, not once per
/// subscription. Each emit still reads its own row metadata, and a body is
/// only emitted at exactly the rev that metadata (or, for [useDoc], the
/// newest changes-feed event) reports, so results are identical to an
/// uncached query. `attachments: true` subscriptions use private bodies.
/// Direct calls (`get`, `allDocs`, `query`, …) never use this cache.
///
/// **Emitted documents may be the same object in several emits and several
/// subscriptions — treat them as immutable.** Do not modify an emitted
/// document (e.g. its `unmappedProps` map) in place; use `copyWith`.
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

  // Emits when the shared feed restarts after it ended unexpectedly: changes
  // during the gap are unknown, so every live subscription re-fetches.
  final StreamController<void> _resyncController =
      StreamController<void>.broadcast();
  bool _feedBroken = false;

  /// Document bodies shared by the `use*` streams of this instance (see
  /// [_DocBodyCache]). Never consulted by direct API calls.
  late final _DocBodyCache _bodyCache = _DocBodyCache(
    (ids) => allDocs(keys: ids, includeDocs: true, attachments: false),
  );

  /// Per-subscription caches of `attachments: true` subscriptions (inline
  /// attachment data stays out of the shared cache). Registered so feed
  /// events and invalidations reach them too.
  final Set<_DocBodyCache> _privateBodyCaches = <_DocBodyCache>{};

  /// Maximum number of document bodies the shared `use*` cache keeps that no
  /// live subscription references (LRU). Bodies referenced by a live
  /// subscription's current emit are kept regardless. 0 evicts unreferenced
  /// bodies immediately. Default 1000.
  int get useCacheCapacity => _bodyCache.capacity;
  set useCacheCapacity(int value) => _bodyCache.capacity = value;

  /// Diagnostic counters of the shared `use*` document-body cache.
  UseCacheStats get useCacheStats => _bodyCache.stats;

  final Set<_EmitScheduler> _schedulers = <_EmitScheduler>{};
  final List<(bool Function(ChangeEntry), Completer<void>)> _feedWaiters =
      <(bool Function(ChangeEntry), Completer<void>)>[];

  /// Diagnostics / tests: true when no `use*` subscription of this instance
  /// has an emit scheduled (debounce or max-wait timer) or running, including
  /// runs of subscriptions cancelled while in flight.
  ///
  /// Together with [useFeedEvent] this gives tests a defined state to wait
  /// for ("the change was delivered and every resulting emit has finished")
  /// instead of a fixed delay.
  bool get useIdle => _schedulers.every((s) => s.idle);

  /// Diagnostics / tests: completes once the changes feed shared by the
  /// `use*` streams has delivered an entry matching [where] to every live
  /// subscription. Register it **before** the write that produces the entry.
  /// Completes with an error when the instance is disposed first.
  Future<void> useFeedEvent(bool Function(ChangeEntry entry) where) {
    final c = Completer<void>();
    _feedWaiters.add((where, c));
    return c.future;
  }

  void _completeFeedWaiters(ChangesResult change) {
    if (_feedWaiters.isEmpty) return;
    final entries = <ChangeEntry>[
      if (change.continuous != null) change.continuous!,
      ...?change.normal?.results,
    ];
    _feedWaiters.removeWhere((w) {
      if (!entries.any(w.$1)) return false;
      // _changesController is asynchronous: the data events for the
      // subscriptions are queued before this completion, so they are
      // delivered first.
      w.$2.complete();
      return true;
    });
  }

  void _invalidateBodyCaches() {
    _bodyCache.invalidateAll();
    for (final c in _privateBodyCaches) {
      c.invalidateAll();
    }
  }

  void _ensureChangesStream() {
    if (_sharedChangesSub != null) return;
    final bool restartAfterBreak = _feedBroken;
    _feedBroken = false;
    _sharedChangesSub =
        changes(
          feedmode: FeedMode.continuous,
          since: 'now',
          includeDocs: false,
          // 30 s heartbeat keeps the connection alive well within the typical
          // 60-second proxy_read_timeout of reverse proxies such as Synology nginx.
          heartbeat: 30000,
        ).listen(
          (change) {
            // Caches first, so subscribers reacting to this event never see
            // a body the event superseded.
            _bodyCache.onChange(change);
            for (final c in _privateBodyCaches) {
              c.onChange(change);
            }
            _changesController.add(change);
            _completeFeedWaiters(change);
          },
          onError: (error) {
            _invalidateBodyCaches();
            _changesController.addError(error);
          },
          onDone: () {
            // The feed ended (error, database deleted, connection closed).
            // Nothing can be proven fresh any more; the next subscriber
            // restarts the feed and live subscriptions resync then.
            _sharedChangesSub = null;
            _feedBroken = true;
            _invalidateBodyCaches();
          },
          cancelOnError: false,
        );
    if (restartAfterBreak) {
      _invalidateBodyCaches();
      if (!_resyncController.isClosed) _resyncController.add(null);
    }
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
    unawaited(_resyncController.close());
    _bodyCache.clear();
    for (final c in _privateBodyCaches) {
      c.clear();
    }
    _privateBodyCaches.clear();
    for (final w in _feedWaiters) {
      w.$2.completeError(StateError('disposed before the feed event'));
    }
    _feedWaiters.clear();
  }

  /// One emit of an `includeDocs: true` subscription through [cache]:
  /// metadata ([meta], no bodies) for this emit, then bodies at exactly the
  /// revs that metadata reports.
  ///
  /// - [rowsCarryRevs] (`_all_docs`): each row's `value.rev` is the rev to
  ///   serve. Otherwise (views) the row ids' current revs are read with one
  ///   cheap `allDocs(keys: ids, includeDocs: false)` after the view query.
  /// - If a body at the wanted rev can't be obtained (concurrent write) the
  ///   whole pass is repeated; after [_maxCachedAttempts] passes, or whenever
  ///   the metadata can't be interpreted safely (rows without rev, view rows
  ///   linking other documents via `value._id`), [direct] — the plain,
  ///   uncached query — provides the result.
  ///
  /// Returns the result to emit and the number of bodies fetched. Stops early
  /// (returning `(null, n)`, nothing to emit) once [refs] is closed, i.e. the
  /// subscription was cancelled.
  Future<(ViewResult?, int)> _cachedDocsEmit({
    required _DocBodyCache cache,
    required _BodyRefs refs,
    required bool rowsCarryRevs,
    required Future<ViewResult?> Function() meta,
    required Future<ViewResult?> Function() direct,
  }) async {
    int fetched = 0;
    for (var attempt = 0; attempt < _maxCachedAttempts; attempt++) {
      if (refs.isClosed) return (null, fetched);
      final m = await meta();
      if (refs.isClosed) return (null, fetched);
      if (m == null) {
        refs.settle(const <String>{});
        return (null, fetched);
      }

      final want = <String, String>{};
      if (rowsCarryRevs) {
        var usable = true;
        for (final row in m.rows) {
          final id = row.id;
          if (id == null || row.error != null) continue;
          final v = row.value;
          if (v is Map && v['deleted'] == true) continue;
          final rev = v is Map ? v['rev'] : null;
          if (rev is! String || (want[id] ?? rev) != rev) {
            usable = false;
            break;
          }
          want[id] = rev;
        }
        if (!usable) break;
      } else {
        final ids = <String>{};
        var usable = true;
        for (final row in m.rows) {
          final id = row.id;
          if (id == null || row.error != null) continue;
          final v = row.value;
          if (v is Map && v.containsKey('_id')) {
            // include_docs follows value._id (linked documents) on CouchDB;
            // leave that to the server's own include_docs.
            usable = false;
            break;
          }
          ids.add(id);
        }
        if (!usable) break;
        if (ids.isNotEmpty) {
          final revs = await allDocs(
            keys: ids.toList(growable: false),
            includeDocs: false,
          );
          for (final r in revs.rows) {
            final id = r.id;
            final v = r.value;
            if (id == null || r.error != null || v is! Map) continue;
            final rev = v['rev'];
            if (v['deleted'] == true || rev is! String) continue;
            if (ids.contains(id)) want[id] = rev;
          }
          if (refs.isClosed) return (null, fetched);
          // A row's document vanished since the view query: re-query.
          if (want.length != ids.length) continue;
        }
      }

      refs.retain(want.keys.toSet());
      final res = await cache.resolve(want);
      fetched += res.fetched;
      if (refs.isClosed) return (null, fetched);
      if (res.stale.isNotEmpty) continue;

      final rows = <ViewEntry>[
        for (final r in m.rows)
          ViewEntry(
            id: r.id,
            key: r.key,
            value: r.value,
            error: r.error,
            doc: r.id != null && r.error == null ? res.docs[r.id] : null,
          ),
      ];
      refs.settle(want.keys.toSet());
      return (
        ViewResult(totalRows: m.totalRows, offset: m.offset, rows: rows),
        fetched,
      );
    }

    // Uncached reference path.
    if (refs.isClosed) return (null, fetched);
    final result = await direct();
    refs.settle(const <String>{});
    return (result, fetched);
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
    StreamSubscription<void>? resyncSub;
    _EmitScheduler? scheduler;

    // The shared body cache is used for regular documents without inline
    // attachments only (`_local/` docs are not content-addressed by rev and
    // never appear in the feed or in _all_docs).
    final bool cacheable = !attachments && !docId.startsWith('_local/');
    // Winning rev of the newest feed event for docId; null = unknown (initial
    // emit, unknown event shape, after a deletion or resync) → fetch.
    String? feedRev;
    // Bumped on every deletion event: a fetch that was in flight when the
    // deletion was emitted must not emit its (older) document afterwards.
    int deleteEpoch = 0;

    Future<void> fetchAndEmit() async {
      if (!controller.hasListener) return;

      try {
        final int epoch = deleteEpoch;
        final String? rev = feedRev;
        CouchDocumentBase? doc = cacheable && rev != null
            ? _bodyCache.peek(docId, rev)
            : null;
        if (doc != null) {
          _bodyCache.stats._hits++;
        } else {
          doc = await get(docId, attachments: attachments);
          if (cacheable && doc != null) _bodyCache.offer(docId, doc);
        }
        if (epoch != deleteEpoch) return;
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
      feedRev = null;
      if (cacheable) _bodyCache.retain(<String>[docId]);

      final sched = scheduler = _EmitScheduler(fetchAndEmit, debounceMs, _schedulers);

      // Emit initial state
      sched.request();

      resyncSub = _resyncController.stream.listen((_) {
        feedRev = null;
        sched.request();
      });

      // Listen to shared changes feed, filtering for our specific document
      changesSub = _sharedChanges.listen(
        (change) {
          ChangeEntry? entry;

          // Extract document change information based on change type
          if (change.type == ChangesResultType.continuous) {
            final e = change.continuous;
            if (e?.id == docId) entry = e;
          } else if (change.type == ChangesResultType.normal) {
            // The newest entry for docId in the batch wins.
            for (final r in change.normal?.results ?? const <ChangeEntry>[]) {
              if (r.id == docId) entry = r;
            }
          }

          if (entry == null) return;

          // Handle deletion immediately - emit null without fetching
          if (entry.deleted) {
            feedRev = null;
            deleteEpoch++;
            if (controller.hasListener && !controller.isClosed) {
              controller.add(null);
            }
            return;
          }

          feedRev = entry.changes.isNotEmpty ? entry.changes.first.rev : null;

          // For non-deleted changes, debounce and fetch the latest state
          sched.schedule();
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
        scheduler?.cancel();
        unawaited(changesSub?.cancel() ?? Future.value());
        unawaited(resyncSub?.cancel() ?? Future.value());
        if (cacheable) _bodyCache.release(<String>[docId]);
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
    StreamSubscription<void>? resyncSub;
    _EmitScheduler? scheduler;

    // includeDocs path: bodies come from the shared per-instance cache (or a
    // private one for attachments: true), always at the rev the documents
    // currently have — see _cachedDocsEmit. Created per listen.
    _DocBodyCache? cache;
    _BodyRefs? refs;
    // Diagnostics only (DbQueryStats.enabled): bodies re-fetched by the last emit.
    int lastRefetched = 0;

    Future<void> fetchAndEmitImpl() async {
      lastRefetched = 0;
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

        // Cached path: view metadata for this emit, current revs of its ids,
        // then bodies at exactly those revs (shared cache, rev-checked).
        final runRefs = refs!;
        final (result, fetched) = await _cachedDocsEmit(
          cache: cache!,
          refs: runRefs,
          rowsCarryRevs: false,
          meta: () => query(
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
          ),
          direct: () => query(
            viewPathShort,
            includeDocs: true,
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
          ),
        );
        lastRefetched = fetched;
        // Cancelled mid-emit (possibly re-listened since): emit nothing.
        if (runRefs.isClosed) return;

        if (controller.hasListener && !controller.isClosed) {
          controller.add(result);
        }
      } catch (e) {
        if (controller.hasListener && !controller.isClosed) {
          controller.addError(e);
        }
      }
    }

    Future<void> fetchAndEmit() async {
      if (!DbQueryStats.enabled) return fetchAndEmitImpl();
      final sw = Stopwatch()..start();
      final q0 = DbQueryStats.total;
      await fetchAndEmitImpl();
      _useLog.info(
        'useView($viewPathShort, includeDocs: $includeDocs) emit: '
        '${sw.elapsedMilliseconds} ms, ${DbQueryStats.total - q0} queries '
        '(incl. concurrent queries), '
        'refetched $lastRefetched docs',
      );
    }

    void startListening() {
      _startChangesListener();

      if (includeDocs) {
        final c = cache = attachments ? _newPrivateBodyCache() : _bodyCache;
        refs = _BodyRefs(c);
      }

      final sched = scheduler = _EmitScheduler(fetchAndEmit, debounceMs, _schedulers);

      // Emit initial state
      sched.request();

      resyncSub = _resyncController.stream.listen((_) => sched.request());

      // Listen to the shared (unfiltered) changes feed. The feed is unfiltered
      // so deletions are observed too. Every emit re-queries the view
      // metadata; only bodies whose rev changed are fetched again.
      changesSub = _sharedChanges.listen(
        (change) {
          // Skip local documents and design documents unless they affect views
          final List<String> changedIds = <String>[];

          if (change.type == ChangesResultType.continuous) {
            final id = change.continuous?.id;
            if (id != null) changedIds.add(id);
          } else if (change.type == ChangesResultType.normal) {
            // For normal mode, every result in the batch might affect the view
            final results = change.normal?.results;
            if (results == null || results.isEmpty) return;
            for (final r in results) {
              changedIds.add(r.id);
            }
          }

          // Skip local documents (they don't appear in views)
          changedIds.removeWhere((id) => id.startsWith('_local/'));
          if (changedIds.isEmpty) return;

          // Debounce to avoid excessive re-queries
          sched.schedule();
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
        scheduler?.cancel();
        unawaited(changesSub?.cancel() ?? Future.value());
        unawaited(resyncSub?.cancel() ?? Future.value());
        refs?.releaseAll();
        refs = null;
        _disposePrivateBodyCache(cache);
        cache = null;
        _stopChangesListener();
      },
    );

    return controller.stream;
  }

  _DocBodyCache _newPrivateBodyCache() {
    final c = _DocBodyCache(
      (ids) => allDocs(keys: ids, includeDocs: true, attachments: true),
      capacity: 0,
    );
    _privateBodyCaches.add(c);
    return c;
  }

  void _disposePrivateBodyCache(_DocBodyCache? c) {
    if (c == null || identical(c, _bodyCache)) return;
    _privateBodyCaches.remove(c);
    c.clear();
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
    StreamSubscription<void>? resyncSub;
    _EmitScheduler? scheduler;
    // null = watch all documents; an empty list = watch nothing.
    final Set<String>? keysSet = keys != null ? Set<String>.from(keys) : null;
    // includeDocs path (see _cachedDocsEmit); created per listen.
    _DocBodyCache? cache;
    _BodyRefs? refs;
    // `total_rows` counts the whole database, so a change to a document
    // outside [keysSet] can still change the result. Such changes only
    // re-check it: the run emits when [forceEmit] is set (initial emit, resync,
    // a change to a watched id) or when `total_rows` differs from [lastTotal].
    bool forceEmit = true;
    int? lastTotal;

    Future<void> fetchAndEmit() async {
      if (!controller.hasListener) return;
      final force = forceEmit;
      forceEmit = false;

      try {
        final sw = DbQueryStats.enabled ? (Stopwatch()..start()) : null;
        final q0 = DbQueryStats.total;
        final ViewResult? result;
        int refetched = 0;
        if (!includeDocs) {
          result = await allDocs(
            keys: keys,
            includeDocs: false,
            attachments: attachments,
          );
        } else {
          // Metadata (`value.rev` per row) is re-queried for every emit —
          // cheap, no bodies — and only bodies whose rev changed are fetched.
          final runRefs = refs!;
          final (r, fetched) = await _cachedDocsEmit(
            cache: cache!,
            refs: runRefs,
            rowsCarryRevs: true,
            meta: () => allDocs(keys: keys, includeDocs: false),
            direct: () => allDocs(
              keys: keys,
              includeDocs: true,
              attachments: attachments,
            ),
          );
          // Cancelled mid-emit (possibly re-listened since): emit nothing.
          result = runRefs.isClosed ? null : r;
          refetched = fetched;
        }
        // Only null when the subscription was cancelled mid-emit.
        if (result == null) return;
        if (!force && result.totalRows == lastTotal) return;
        lastTotal = result.totalRows;
        if (sw != null) {
          _useLog.info(
            'useAllDocs(keys: ${keys?.length ?? 'all'}, includeDocs: '
            '$includeDocs) emit: ${sw.elapsedMilliseconds} ms, '
            '${DbQueryStats.total - q0} queries (incl. concurrent), '
            '${result.rows.length} rows, refetched $refetched docs',
          );
        }

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
      forceEmit = true;
      lastTotal = null;
      _startChangesListener();

      if (includeDocs) {
        final c = cache = attachments ? _newPrivateBodyCache() : _bodyCache;
        refs = _BodyRefs(c);
      }

      final sched = scheduler = _EmitScheduler(fetchAndEmit, debounceMs, _schedulers);

      // Emit initial state
      sched.request();

      resyncSub = _resyncController.stream.listen((_) {
        forceEmit = true;
        sched.request();
      });

      // Listen to shared changes feed, filtering for our specific documents
      changesSub = _sharedChanges.listen(
        (change) {
          // When no keys filter is specified (null), every change is relevant
          // (we're watching all documents). An empty list watches nothing.
          bool relevantChange = keysSet == null;

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

          // A change outside the watched ids only re-checks `total_rows`.
          if (relevantChange) forceEmit = true;

          // Debounce rapid changes
          sched.schedule();
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
        scheduler?.cancel();
        unawaited(changesSub?.cancel() ?? Future.value());
        unawaited(resyncSub?.cancel() ?? Future.value());
        refs?.releaseAll();
        refs = null;
        _disposePrivateBodyCache(cache);
        cache = null;
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
