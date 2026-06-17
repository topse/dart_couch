import 'dart:async';

import 'package:logging/logging.dart';

import 'dart_couch_db.dart';
import 'messages/couch_db_status_codes.dart';
import 'messages/couch_document_base.dart';
import 'value_notifier.dart';

final _log = Logger('DocStore');

/// The narrow database surface the document primitives depend on — three
/// operations only. Depending on this rather than the full [DartCouchDb] keeps
/// the primitives portable and, crucially, makes them testable with a trivial
/// fake: no real CouchDB, no changes feed, no debounce timing. [CouchDocDb]
/// adapts a real [DartCouchDb] to it for production.
abstract interface class DocDb {
  /// The current document for [docId], or null if absent/deleted.
  Future<CouchDocumentBase?> get(String docId);

  /// Writes [doc] and returns it with its new `_rev`. Must throw a
  /// [CouchDbException] with [CouchDbStatusCodes.conflict] on a rev mismatch.
  Future<CouchDocumentBase> put(CouchDocumentBase doc);

  /// Emits the document's state on subscribe and on every subsequent change;
  /// null when the document is absent/deleted. Maps to [DartCouchDb.useDoc].
  Stream<CouchDocumentBase?> watch(String docId);
}

/// Adapts a real [DartCouchDb] to the [DocDb] port. The single point where the
/// primitives touch the full CouchDB surface; everything else depends on
/// [DocDb], so a test can supply its own fake.
class CouchDocDb implements DocDb {
  CouchDocDb(this._db);

  final DartCouchDb _db;

  @override
  Future<CouchDocumentBase?> get(String docId) => _db.get(docId);

  @override
  Future<CouchDocumentBase> put(CouchDocumentBase doc) => _db.put(doc);

  @override
  Stream<CouchDocumentBase?> watch(String docId) => _db.useDoc(docId);
}

/// Builds the full document to persist, given the latest known `_rev`.
///
/// Invoked by [SaveDocWriter] at write time and re-invoked on a conflict retry
/// (against a refreshed rev), so it must read the caller's current state each
/// time rather than capturing a stale snapshot. Derive the document so the rev
/// flows through — either stamp the [String] arg (`Doc(..., rev: rev)`) or
/// `copyWith` from a base that already carries the right rev.
typedef DocBuild = CouchDocumentBase Function(String? rev);

/// A write that transforms a document into its next desired state, used by
/// [LiveDocHandle]. Must return a document *derived from* its argument
/// (`base.copyWith(...)`), so `_id`/`_rev` are preserved.
typedef DocMutation<T extends CouchDocumentBase> = T Function(T base);

/// The reusable kernel for **fire-and-forget, rev-safe, coalesced** writes to a
/// single CouchDB document — and nothing else. It owns:
///
/// - the current `_rev`,
/// - the [DartCouchDb.useDoc] subscription and external-vs-own-write detection,
/// - the write loop: serialise, coalesce, `put`, retry on conflict.
///
/// It holds **no document data**. The consumer owns its own representation and
/// supplies a [DocBuild] that produces the document to write. This is the right
/// layer for a consumer whose in-memory model differs from the document shape
/// (e.g. an index rebuilt from a view, or `HearingStatsService`'s per-item
/// stats map) — no redundant second copy of the document is kept here.
///
/// For the common "the document *is* my model, and I write deltas" case, use
/// [LiveDocHandle], which composes a [SaveDocWriter] and adds the owned-document
/// sugar (held value, mutation API, auto-merge, reactive state).
///
/// ## Offline-first scope
///
/// `db.put` writes to the **local** store; replication and true divergent
/// conflict resolution belong to the replication layer's `conflictResolver`. A
/// `409` here is only ever a **local `_rev` mismatch** — a replicated-in change
/// (or another local writer) bumped the head since we last synced. The writer's
/// job is narrow: keep the local rev current and re-apply on local conflict.
///
/// ## Behaviour contracts (test spec) — W*
///
/// - **W1 Serialised.** Only one `put` is in flight at a time; writes never
///   race each other on `_rev`.
/// - **W2 Coalescing.** A [save] queued while a `put` is in flight replaces the
///   queued build — N rapid [save]s during one in-flight write cost at most two
///   puts (the in-flight one + one rebuilt from the latest state), not N.
/// - **W3 Rev currency.** After a successful `put`, `_rev` is the saved rev and
///   [onSaved] fires with the saved document; the next build sees the new rev.
/// - **W4 Own-write echo ignored.** The `useDoc` emission echoing our own write
///   (rev == `_rev`) does not fire [onExternalChange].
/// - **W5 External change.** A `useDoc` emission with a different rev (or null
///   on delete) updates `_rev` and fires [onExternalChange] with the fetched
///   document (or null).
/// - **W6 Conflict retry.** A `put` throwing [CouchDbStatusCodes.conflict]
///   re-reads the document (updating `_rev` and firing [onExternalChange] so the
///   consumer can merge), then re-invokes the same build against the fresh rev.
///   Bounded by `maxAttempts`; after that the build is dropped and logged.
/// - **W7 Settle.** [settle] completes only when no build is queued or in
///   flight.
///
/// ## Example
///
/// ```dart
/// // You own the data (here a stats map); the writer owns the rev.
/// final writer = store.writer(PlayLog.docIdFor(uuid));
/// // Reconcile your own state when the document changes underneath you:
/// writer.onExternalChange = (doc) => reloadStatsFrom(doc);
/// await writer.start();
///
/// // Build the whole document from your own state; `rev` is supplied for you
/// // (and re-supplied on a conflict retry), so read live state in the closure:
/// writer.save((rev) => PlayLog(
///   id: PlayLog.docIdFor(uuid), deviceId: uuid, items: buildItems(), rev: rev,
/// ));
/// await writer.settle(); // (tests/shutdown) await the write to land
/// ```
class SaveDocWriter {
  SaveDocWriter({required DocDb db, required String docId, int maxAttempts = 5})
    : _db = db,
      _docId = docId,
      _maxAttempts = maxAttempts;

  final DocDb _db;
  final String _docId;
  final int _maxAttempts;

  String? _rev;
  DocBuild? _pendingBuild;
  bool _draining = false;
  int _attempts = 0;
  final List<Completer<void>> _settlers = [];
  StreamSubscription<CouchDocumentBase?>? _sub;

  /// Fired when the document changes for a reason that is **not** our own write
  /// (W5/W6): an external write/delete on the changes stream, or a conflict
  /// re-read. Carries the freshly-fetched document (or null on delete). Lets a
  /// consumer that owns the data reconcile its own state before the next build.
  void Function(CouchDocumentBase? doc)? onExternalChange;

  /// Fired after each of our writes lands (W3), carrying the saved document
  /// (with its new rev). Lets a consumer holding the document adopt the new rev.
  void Function(CouchDocumentBase saved)? onSaved;

  /// The latest known revision, or null if the document does not exist yet.
  String? get rev => _rev;

  /// Loads the current rev and subscribes to changes. Returns the loaded
  /// document (or null if absent) so the caller can seed its own state. Call
  /// once before use.
  Future<CouchDocumentBase?> start() async {
    CouchDocumentBase? doc;
    try {
      doc = await _db.get(_docId);
      _rev = doc?.rev;
    } catch (e) {
      _log.warning('$_docId: failed initial load: $e');
    }
    _sub = _db
        .watch(_docId)
        .listen(
          _adoptExternal,
          onError: (Object e) {
            _log.warning('$_docId: watch error: $e');
          },
        );
    return doc;
  }

  /// Requests a save. Fire-and-forget: returns immediately. [build] is invoked
  /// at write time (and on each conflict retry), so it must read the caller's
  /// current state rather than capture a snapshot. Coalesces (W2): a build
  /// queued while another is in flight replaces it.
  void save(DocBuild build) {
    _pendingBuild = build;
    unawaited(_drain());
  }

  /// Completes when no build is queued and none is in flight (W7).
  Future<void> settle() {
    if (!_draining && _pendingBuild == null) return Future.value();
    final completer = Completer<void>();
    _settlers.add(completer);
    return completer.future;
  }

  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
    onExternalChange = null;
    onSaved = null;
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_pendingBuild != null) {
        final build = _pendingBuild!;
        _pendingBuild = null;
        final doc = build(_rev);
        try {
          final saved = await _db.put(doc);
          _rev = saved.rev;
          _attempts = 0;
          onSaved?.call(saved);
        } catch (e) {
          final isConflict =
              e is CouchDbException &&
              e.statusCode == CouchDbStatusCodes.conflict;
          _attempts++;
          if (_attempts > _maxAttempts) {
            _log.severe(
              '$_docId: giving up build after $_attempts attempts: $e',
            );
            _attempts = 0; // drop this build to avoid an infinite loop
          } else if (isConflict) {
            // W6: local rev moved under us — re-read (which fires
            // onExternalChange so the consumer can merge), then retry the same
            // build against the fresh rev unless a newer build superseded it.
            await _resyncFromDb();
            _pendingBuild ??= build;
          } else {
            _log.warning(
              '$_docId: put failed ($e), retry $_attempts/$_maxAttempts',
            );
            await Future<void>.delayed(Duration(milliseconds: 100 * _attempts));
            _pendingBuild ??= build;
          }
        }
      }
    } finally {
      _draining = false;
      _completeSettlers();
    }
  }

  Future<void> _resyncFromDb() async {
    try {
      _adoptExternal(await _db.get(_docId));
    } catch (e) {
      _log.warning('$_docId: failed to resync after conflict: $e');
    }
  }

  /// Adopts an externally-observed state (a stream emission or a conflict
  /// re-read). No-op when the rev is unchanged — that is exactly our own write
  /// echoing back, which must not fire [onExternalChange] (W4).
  void _adoptExternal(CouchDocumentBase? doc) {
    final newRev = doc?.rev;
    if (newRev == _rev) return;
    if (doc == null) {
      _log.info('$_docId: deleted externally');
    } else {
      _log.info('$_docId: external change (rev ${doc.rev})');
    }
    _rev = newRev;
    onExternalChange?.call(doc);
  }

  void _completeSettlers() {
    if (_draining || _pendingBuild != null) return;
    final waiters = List<Completer<void>>.of(_settlers);
    _settlers.clear();
    for (final c in waiters) {
      if (!c.isCompleted) c.complete();
    }
  }
}

/// Single source of truth for one CouchDB document, with optimistic reads and
/// **fire-and-forget, rev-safe, coalesced** delta writes.
///
/// The owned-document layer over [SaveDocWriter] — for the case where the
/// document *is* your model and you write deltas (`update((d) => d.copyWith(
/// ...))`). The writer underneath supplies all the rev/serialise/retry/stream
/// machinery; this class adds:
///
/// - the held typed [current] value and a reactive [state],
/// - the delta [update] API,
/// - **auto-merge**: an external change re-applies your still-unconfirmed
///   mutations on top, so concurrent writes (e.g. a companion purge) don't
///   clobber pending local writes.
///
/// Rev handling needs no generic rev-stamping: [_base] receives its rev from
/// the writer's [SaveDocWriter.onSaved] / [SaveDocWriter.onExternalChange]
/// callbacks (both carry a runtime-`T` document), and each mutation's `copyWith`
/// preserves it — so the document handed to the writer always carries the right
/// rev.
///
/// ## Behaviour contracts (test spec) — H*
///
/// - **H1 Optimistic read.** After [update] returns, [current] already reflects
///   the mutation, before any `put` completes.
/// - **H2 Coalescing.** Inherits W2 — many rapid [update]s collapse into one
///   put per drain cycle.
/// - **H3 No mid-flight loss/flicker.** [current] always equals [_base] with
///   *all* unconfirmed mutations (in-flight batch + queued) applied; a mutation
///   leaves that set only once the `put` including it succeeds.
/// - **H4 External merge.** An external change adopts the external base and
///   re-applies the unconfirmed mutations on top (no clobber). Fires
///   [onExternalChange] for consumers keeping a derived projection.
/// - **H5 Own-write echo ignored / conflict retry / external delete** follow
///   from the underlying W4/W6/W5 — an external delete resets [_base] to the
///   construction [emptyValue] so the next write re-creates the document.
///
/// ## Example
///
/// ```dart
/// final id = PlayPosition.docIdFor(uuid);
/// final handle = store.handle<PlayPosition>(
///   id,
///   emptyValue: PlayPosition(id: id, deviceId: uuid), // empty doc, rev null
/// );
/// await handle.start(); // load current state + watch for changes
///
/// // Optimistic, fire-and-forget delta write — no await, no rev juggling:
/// handle.update((doc) => doc.copyWith(
///   items: {...doc.items, itemId: PlayPositionItem(title: title, done: true)},
/// ));
///
/// final entry = handle.current.items[itemId]; // optimistic state, readable now
/// handle.state.addListener(rebuild);           // reactive (Flutter-free)
/// ```
class LiveDocHandle<T extends CouchDocumentBase> {
  LiveDocHandle({required SaveDocWriter writer, required T emptyValue})
    : _writer = writer,
      _emptyValue = emptyValue,
      _base = emptyValue,
      _state = DcValueNotifier<T>(emptyValue) {
    _writer.onExternalChange = _onExternal;
    _writer.onSaved = _onSaved;
  }

  final SaveDocWriter _writer;

  /// The empty document for this type (id set, rev null), used whenever the real
  /// document is absent: at first load before it exists, and as the reset target
  /// after an external delete (so the next write re-creates it).
  final T _emptyValue;

  /// The last document the DB confirmed — the authoritative rev source. Updated
  /// only from the writer's callbacks (never via generic rev-stamping).
  T _base;

  /// Mutations whose `put` is in flight (kept until it succeeds, so they keep
  /// contributing to [current] — H3 — and re-apply on a conflict retry).
  List<DocMutation<T>> _inFlight = [];

  /// Mutations queued after the in-flight batch.
  List<DocMutation<T>> _pending = [];

  final DcValueNotifier<T> _state;

  /// Optional typed re-export of [SaveDocWriter.onExternalChange], for a
  /// consumer that keeps a projection derived from this document.
  void Function(T current)? onExternalChange;

  /// Latest known state of the document (optimistic — H1/H3).
  T get current => _state.value;

  /// Listen here to rebuild when the document changes. Flutter-free.
  DcValueListenable<T> get state => _state;

  /// Load the current state and start watching for changes. Call once.
  Future<void> start() async {
    final doc = await _writer.start();
    if (doc is T) {
      _base = doc;
    } else if (doc == null) {
      _base = _emptyValue;
    } else {
      _log.severe(
        '$runtimeType: loaded ${doc.runtimeType}, not $T — '
        'mapper not registered?',
      );
    }
    _recompute();
  }

  /// Queue a delta write. Fire-and-forget; [current] updates synchronously.
  void update(DocMutation<T> mutate) {
    _pending.add(mutate);
    _recompute();
    _writer.save(_build);
  }

  /// Completes when every queued write has been persisted (W7).
  Future<void> settle() => _writer.settle();

  void dispose() {
    _writer.onExternalChange = null;
    _writer.onSaved = null;
    _state.dispose();
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  /// Build closure handed to the writer. Promotes queued mutations into the
  /// in-flight batch and returns the document to write — [_base] with all
  /// unconfirmed mutations applied. The mutations' `copyWith` preserves
  /// [_base]'s rev (kept current via [_onSaved]/[_onExternal]), so the written
  /// document carries the right rev; the [rev] argument is therefore unused.
  CouchDocumentBase _build(String? rev) {
    _inFlight = [..._inFlight, ..._pending];
    _pending = [];
    return _apply(_base, _inFlight);
  }

  void _onSaved(CouchDocumentBase saved) {
    if (saved is T) {
      _base = saved; // new rev + the content we just persisted
    } else {
      _log.severe('$runtimeType: saved ${saved.runtimeType}, not $T');
    }
    _inFlight = []; // confirmed — stop contributing to current
    _recompute();
  }

  void _onExternal(CouchDocumentBase? doc) {
    if (doc == null) {
      _base = _emptyValue; // H5: external delete → re-create on next write
    } else if (doc is T) {
      _base = doc;
    } else {
      _log.severe('$runtimeType: external ${doc.runtimeType}, not $T');
      return;
    }
    _recompute(); // H4: unconfirmed mutations re-apply on top
    onExternalChange?.call(_state.value);
  }

  void _recompute() =>
      _state.value = _apply(_base, [..._inFlight, ..._pending]);

  T _apply(T base, List<DocMutation<T>> muts) {
    var doc = base;
    for (final m in muts) {
      doc = m(doc);
    }
    return doc;
  }
}

/// One-shot rev-safe update of the document [docId]: read the current value,
/// apply [build], `put`, and retry on conflict (re-reading each time). Returns
/// the saved document, or null if [build] aborted or the update failed.
///
/// [build] receives the current document (or null if absent) and returns the
/// document to write — derive it from the argument (e.g. `cur?.copyWith(...)`)
/// so the rev flows through. Return null to abort (e.g. don't recreate a
/// document that was deleted out from under you).
///
/// No held state, no subscription — for fire-once writes (clearing a flag, a
/// startup read-modify-write) that don't warrant a live [LiveDocHandle] or a
/// long-lived [SaveDocWriter].
///
/// ## Example
///
/// ```dart
/// // Clear a flag on a doc that may have changed under us; returning null
/// // aborts (e.g. don't recreate a doc that was deleted out from under you).
/// await updateDoc<MediaItem>(db, itemId, (cur) => cur?.copyWith(isNew: false));
/// ```
Future<T?> updateDoc<T extends CouchDocumentBase>(
  DocDb db,
  String docId,
  T? Function(T? current) build, {
  int maxAttempts = 5,
}) async {
  for (var attempt = 1; ; attempt++) {
    final T? current;
    try {
      final fetched = await db.get(docId);
      if (fetched == null) {
        current = null;
      } else if (fetched is T) {
        current = fetched;
      } else {
        _log.severe(
          '$docId: get returned ${fetched.runtimeType}, not $T — '
          'mapper not registered?',
        );
        return null;
      }
    } catch (e) {
      _log.warning('$docId: updateDoc load failed: $e');
      return null;
    }

    final next = build(current);
    if (next == null) return null; // caller aborted

    try {
      return await db.put(next) as T;
    } catch (e) {
      final isConflict =
          e is CouchDbException && e.statusCode == CouchDbStatusCodes.conflict;
      if (!isConflict || attempt >= maxAttempts) {
        _log.warning('$docId: updateDoc failed (attempt $attempt): $e');
        return null;
      }
      // Conflict — loop: re-read, rebuild against the fresh rev, retry.
    }
  }
}

/// Application-wide registry keyed by document id — the central single source
/// of truth for documents. Hand it the [DartCouchDb] once (via DI) and request
/// the writer / handle for a document, or do a one-shot [update].
///
/// Writers and handles are created lazily and cached for the store's lifetime
/// (fine for the handful of per-device documents this app holds). The caller is
/// responsible for awaiting [SaveDocWriter.start] / [LiveDocHandle.start].
///
/// ## Example
///
/// ```dart
/// // Wire once — CouchDocDb adapts the real DartCouchDb to the DocDb port:
/// final store = DocStore(CouchDocDb(db));
///
/// final handle = store.handle<PlayPosition>(id, emptyValue: PlayPosition(id: id, deviceId: uuid));
/// final writer = store.writer(PlayLog.docIdFor(uuid));
/// await store.update<MediaItem>(itemId, (cur) => cur?.copyWith(isNew: false));
/// ```
class DocStore {
  /// [db] is the narrow [DocDb] port — in production a [CouchDocDb] wrapping the
  /// real [DartCouchDb] (`DocStore(CouchDocDb(db))`); in tests a fake.
  DocStore(this._db);

  final DocDb _db;
  final Map<String, SaveDocWriter> _writers = {};
  final Map<String, LiveDocHandle<CouchDocumentBase>> _handles = {};

  /// The single [SaveDocWriter] for [docId] (created on first request, cached).
  /// There must be exactly one writer per document id app-wide — two writers on
  /// the same id would each serialise their own queue but race each other on the
  /// rev. Don't also request a [handle] for the same id.
  SaveDocWriter writer(String docId) =>
      _writers.putIfAbsent(docId, () => SaveDocWriter(db: _db, docId: docId));

  /// A [LiveDocHandle] for [docId], backed by its [writer]. [emptyValue] (an
  /// empty document with the id set and rev null) is used only on first
  /// creation.
  LiveDocHandle<T> handle<T extends CouchDocumentBase>(
    String docId, {
    required T emptyValue,
  }) {
    final existing = _handles[docId];
    if (existing != null) return existing as LiveDocHandle<T>;
    final created = LiveDocHandle<T>(
      writer: writer(docId),
      emptyValue: emptyValue,
    );
    _handles[docId] = created;
    return created;
  }

  /// One-shot rev-safe update — see [updateDoc].
  Future<T?> update<T extends CouchDocumentBase>(
    String docId,
    T? Function(T? current) build, {
    int maxAttempts = 5,
  }) => updateDoc<T>(_db, docId, build, maxAttempts: maxAttempts);

  void dispose() {
    for (final w in _writers.values) {
      w.dispose();
    }
    _writers.clear();
    _handles.clear();
  }
}
