// Unit tests for the use* streams' scheduling (key filtering, normal-mode
// batches, max-wait debounce, single-flight) and for the shared document-body
// cache (rev-checked reuse, refcounts/LRU, invalidation, races). They use a
// fake, rev-aware in-memory host for UseDartCouchMixin, so no CouchDB is
// required and query/fetch counts are exact.
import 'dart:async';

import 'package:dart_couch/dart_couch.dart';
import 'package:test/test.dart';

import 'helper/helper.dart';

class _FakeDoc {
  _FakeDoc(this.rev, this.v);
  String rev;
  int v;
  bool deleted = false;
}

class _FakeHost with UseDartCouchMixin {
  /// The current feed (a new one per `changes()` call, so tests can end or
  /// fail it and observe the restart).
  StreamController<ChangesResult>? _feed;
  int feedStarts = 0;

  final Map<String, _FakeDoc> docs = <String, _FakeDoc>{};
  int _gen = 0;

  // Counters.
  int metaCalls = 0; // allDocs(includeDocs: false)
  int bodyCalls = 0; // allDocs(includeDocs: true)
  int queryCalls = 0;
  int queryIncludeDocsCalls = 0;
  int getCalls = 0;
  int inFlight = 0;
  int maxInFlight = 0;
  final List<List<String>?> bodyKeys = <List<String>?>[];

  int get allDocsCalls => metaCalls + bodyCalls;

  Duration latency = Duration.zero; // every allDocs call
  Duration bodyLatency = Duration.zero; // allDocs(includeDocs: true) only
  Duration getLatency = Duration.zero;

  /// Runs at the start of every body fetch, before its snapshot is taken.
  void Function()? onBodyFetch;

  /// Rows returned by [query] (ids, in view order).
  List<String> viewIds = <String>[];

  /// Emit `value: {'_id': id}` view rows (CouchDB linked documents).
  bool linkedViewRows = false;

  void resetCounters() {
    metaCalls = 0;
    bodyCalls = 0;
    queryCalls = 0;
    queryIncludeDocsCalls = 0;
    getCalls = 0;
    maxInFlight = 0;
    bodyKeys.clear();
  }

  String _nextRev(String id) {
    _gen++;
    final g = (docs[id] == null ? 0 : int.parse(docs[id]!.rev.split('-')[0]));
    return '${g + 1}-h$_gen';
  }

  ChangeEntry _entry(String id) {
    final d = docs[id];
    return ChangeEntry(
      id: id,
      seq: '$_gen-x',
      changes: d == null ? [] : [RevisionListEntry(rev: d.rev)],
      deleted: d?.deleted ?? false,
    );
  }

  void _emit(ChangesResult c) {
    final f = _feed;
    if (f != null && !f.isClosed) f.add(c);
  }

  /// Creates/updates [id] without a feed event (simulates feed lag / a gap).
  String writeSilently(String id) {
    final rev = _nextRev(id);
    final d = docs[id];
    if (d == null) {
      docs[id] = _FakeDoc(rev, _gen);
    } else {
      d
        ..rev = rev
        ..v = _gen
        ..deleted = false;
    }
    return rev;
  }

  /// Emits the feed event for the current state of [id].
  void announce(String id) => _emit(ChangesResult.continuous(_entry(id)));

  String write(String id) {
    final rev = writeSilently(id);
    announce(id);
    return rev;
  }

  /// Old name kept for the scheduling tests.
  void touch(String id) => write(id);

  void delete(String id) {
    final rev = _nextRev(id);
    docs[id]!
      ..rev = rev
      ..deleted = true;
    announce(id);
  }

  void touchBatch(List<String> ids) {
    for (final id in ids) {
      if (!id.startsWith('_local/')) writeSilently(id);
    }
    _emit(
      ChangesResult.normal(
        ChangesResultNormal(
          lastSeq: '$_gen-x',
          pending: 0,
          results: [for (final id in ids) _entry(id)],
        ),
      ),
    );
  }

  /// Feed event without a rev (unknown shape).
  void announceWithoutRev(String id) => _emit(
    ChangesResult.continuous(ChangeEntry(id: id, seq: '$_gen-x', changes: [])),
  );

  void failFeed() => _feed?.addError(Exception('feed failed'));
  Future<void> endFeed() async => _feed?.close();

  CouchDocumentBase _body(String id, _FakeDoc d, bool attachments) =>
      CouchDocumentBase(
        id: id,
        rev: d.rev,
        unmappedProps: {'v': d.v, 'att': attachments ? 'inline' : 'stub'},
      );

  @override
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
  }) {
    feedStarts++;
    final f = _feed = StreamController<ChangesResult>.broadcast();
    return f.stream;
  }

  @override
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
  }) async {
    if (includeDocs) {
      bodyCalls++;
      bodyKeys.add(keys == null ? null : List<String>.of(keys));
      onBodyFetch?.call();
    } else {
      metaCalls++;
    }
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;

    // Snapshot first, then the latency: the result reflects the call start.
    final List<ViewEntry> rows;
    if (keys != null) {
      rows = [
        for (final k in keys)
          if (docs[k] == null)
            ViewEntry(key: k, error: 'not_found')
          else if (docs[k]!.deleted)
            ViewEntry(
              id: k,
              key: k,
              value: {'rev': docs[k]!.rev, 'deleted': true},
            )
          else
            ViewEntry(
              id: k,
              key: k,
              value: {'rev': docs[k]!.rev},
              doc: includeDocs ? _body(k, docs[k]!, attachments) : null,
            ),
      ];
    } else {
      final ids = docs.keys.where((id) => !docs[id]!.deleted).toList()..sort();
      rows = [
        for (final id in ids)
          ViewEntry(
            id: id,
            key: id,
            value: {'rev': docs[id]!.rev},
            doc: includeDocs ? _body(id, docs[id]!, attachments) : null,
          ),
      ];
    }
    final total = docs.values.where((d) => !d.deleted).length;

    final delay = latency + (includeDocs ? bodyLatency : Duration.zero);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    inFlight--;
    return ViewResult(totalRows: total, offset: 0, rows: rows);
  }

  @override
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
  }) async {
    queryCalls++;
    if (includeDocs) queryIncludeDocsCalls++;
    Iterable<String> ids = viewIds.where(
      (id) => docs[id] != null && !docs[id]!.deleted,
    );
    if (skip != null) ids = ids.skip(skip);
    if (limit != null) ids = ids.take(limit);
    return ViewResult(
      totalRows: viewIds.length,
      offset: skip ?? 0,
      rows: [
        for (final id in ids)
          ViewEntry(
            id: id,
            key: id,
            value: linkedViewRows ? {'_id': id} : 1,
            doc: includeDocs ? _body(id, docs[id]!, attachments) : null,
          ),
      ],
    );
  }

  @override
  Future<CouchDocumentBase?> get(
    String docid, {
    String? rev,
    bool revs = false,
    bool revsInfo = false,
    bool attachments = false,
    bool conflicts = false,
    bool deletedConflicts = false,
    bool meta = false,
  }) async {
    getCalls++;
    final d = docs[docid];
    final result = d == null || d.deleted ? null : _body(docid, d, attachments);
    if (getLatency > Duration.zero) await Future<void>.delayed(getLatency);
    return result;
  }
}

/// Waits (bounded) until [condition] holds — a defined state, never a fixed
/// delay — and fails the test if it does not.
Future<void> _until(bool Function() condition, {String? reason}) async {
  expect(
    await waitForCondition(
      () async => condition(),
      maxAttempts: 500,
      interval: const Duration(milliseconds: 10),
    ),
    isTrue,
    reason: reason,
  );
}

/// Every use* emit has finished and nothing is scheduled.
Future<void> _idle(_FakeHost host) => _until(() => host.useIdle);

/// Runs [action] (a write that announces [id] on the feed), then waits until
/// the feed delivered that entry and every resulting emit finished.
Future<T> _after<T>(_FakeHost host, String id, T Function() action) async {
  final delivered = host.useFeedEvent((e) => e.id == id);
  final result = action();
  await delivered;
  await _idle(host);
  return result;
}

/// The cache invariant: every emitted row carrying `value.rev` has its body
/// at exactly that rev (or no body for deleted / not-found rows).
void expectRevConsistent(ViewResult? r) {
  if (r == null) return;
  for (final row in r.rows) {
    final v = row.value;
    if (v is Map && v['rev'] is String) {
      if (v['deleted'] == true) {
        expect(row.doc, isNull, reason: 'deleted row ${row.id} has a body');
      } else {
        expect(
          row.doc?.rev,
          v['rev'],
          reason: 'row ${row.id}: body rev must equal value.rev',
        );
      }
    }
  }
}

Map<String, String?> _revsOf(ViewResult? r) => {
  for (final row in r?.rows ?? const <ViewEntry>[])
    if (row.id != null) row.id!: row.doc?.rev,
};

void main() {
  configureTestLogging();
  late _FakeHost host;

  setUp(() => host = _FakeHost());
  tearDown(() async {
    host.dispose();
  });

  group('scheduling', () {
    test('useAllDocs(keys: []) re-checks only total_rows on changes and '
        'emits only when it changed', () async {
      host.writeSilently('a');
      final emits = <ViewResult?>[];
      final sub = host.useAllDocs(keys: [], debounceMs: 20).listen(emits.add);
      await _idle(host);
      expect(host.allDocsCalls, 1, reason: 'initial metadata query only');
      expect(emits.single!.totalRows, 1);

      // Update of an existing doc: total_rows unchanged -> one cheap
      // metadata re-check, no emit, never a body fetch.
      await _after(host, 'a', () => host.touch('a'));
      expect(host.metaCalls, 2);
      expect(emits, hasLength(1));

      // New docs change total_rows (CouchDB counts the whole db) -> emit.
      await _after(host, 'b', () => host.touchBatch(['b', 'c']));
      expect(host.metaCalls, 3);
      expect(emits, hasLength(2));
      expect(emits.last!.totalRows, 3);
      expect(emits.last!.rows, isEmpty);
      expect(host.bodyCalls, 0);
      await sub.cancel();
    });

    test('useAllDocs(keys: null) still watches everything', () async {
      final sub = host.useAllDocs(debounceMs: 20).listen((_) {});
      await _idle(host);
      expect(host.metaCalls, 1);
      await _after(host, 'anything', () => host.touch('anything'));
      expect(host.metaCalls, 2);
      expect(host.bodyKeys.last, ['anything']);
      await sub.cancel();
    });

    test(
      'useView: a normal-mode batch refetches exactly the changed bodies',
      () async {
        for (final id in ['a', 'b', 'c']) {
          host.writeSilently(id);
        }
        host.viewIds = ['a', 'b', 'c'];
        final sub = host
            .useView('d/v', includeDocs: true, debounceMs: 20)
            .listen((_) {});
        await _idle(host);
        expect(host.bodyKeys.length, 1);
        expect(host.bodyKeys.first, unorderedEquals(['a', 'b', 'c']));

        // Batch with two ids plus a local doc that must be ignored.
        await _after(host, 'b', () => host.touchBatch(['_local/x', 'b', 'c']));
        expect(host.bodyKeys.length, 2);
        expect(host.bodyKeys.last, unorderedEquals(['b', 'c']));
        await sub.cancel();
      },
    );

    test(
      'max wait: continuous writes cannot postpone the emit forever',
      () async {
        host.writeSilently('a');
        // debounceMs 500 -> max wait 1500 ms. Writes every 100 ms keep
        // resetting a plain trailing debounce, so only the max wait can emit.
        final emits = <int>[];
        final sub = host.useAllDocs(debounceMs: 500).listen((r) {
          emits.add(r!.rows.first.doc!.unmappedProps['v'] as int);
        });
        await _idle(host);
        final initialEmits = emits.length;

        final writer = Timer.periodic(
          const Duration(milliseconds: 100),
          (_) => host.touch('a'),
        );
        // Defined state: an emit while the writes continue (bounded well
        // above the 1500 ms max wait).
        await _until(
          () => emits.length > initialEmits,
          reason: 'no emit during continuous writes',
        );
        writer.cancel();
        await sub.cancel();
      },
    );

    test(
      'single-flight: never concurrent, last emit reflects final state',
      () async {
        host.writeSilently('a');
        host.latency = const Duration(milliseconds: 60);
        final emits = <ViewResult?>[];
        final sub = host.useAllDocs(debounceMs: 10).listen(emits.add);

        // Each change arrives while a fetch is in flight.
        for (var i = 0; i < 6; i++) {
          await _until(() => host.inFlight > 0);
          final delivered = host.useFeedEvent((e) => e.id == 'a');
          host.touch('a');
          await delivered;
        }
        final finalRev = host.docs['a']!.rev;
        await _idle(host);

        expect(host.maxInFlight, 1);
        expect(emits, isNotEmpty);
        emits.forEach(expectRevConsistent);
        expect(emits.last!.rows.single.doc!.rev, finalRev);
        await sub.cancel();
      },
    );

    test('cancel stops pending reruns and timers', () async {
      host.writeSilently('a');
      host.latency = const Duration(milliseconds: 100);
      final sub = host.useAllDocs(debounceMs: 10).listen((_) {});
      await _until(() => host.inFlight > 0); // initial fetch in flight
      final delivered = host.useFeedEvent((e) => e.id == 'a');
      host.touch('a'); // schedules a debounced rerun
      host.touch('a');
      await delivered;
      expect(host.useIdle, isFalse);
      await sub.cancel();
      final callsAtCancel = host.allDocsCalls;
      // Defined state: the in-flight run has finished (the cancelled
      // scheduler leaves the registry only then).
      await _until(() => host.useIdle && host.inFlight == 0);
      expect(host.allDocsCalls, callsAtCancel);
    });
  });

  group('shared body cache', () {
    void seed(List<String> ids) {
      for (final id in ids) {
        host.writeSilently(id);
      }
    }

    test('K=3 useAllDocs + 1 useView: one put -> exactly one body fetch; '
        'a late subscriber fetches no bodies', () async {
      seed(['a', 'b', 'c', 'd']);
      host.viewIds = ['a', 'b', 'c', 'd'];
      final last = <int, ViewResult?>{};
      final subs = <StreamSubscription>[
        for (var i = 0; i < 3; i++)
          host.useAllDocs(debounceMs: 20).listen((r) => last[i] = r),
        host
            .useView('d/v', includeDocs: true, debounceMs: 20)
            .listen((r) => last[3] = r),
      ];
      await _idle(host);
      expect(last.length, 4);

      host.resetCounters();
      final newRev = await _after(host, 'b', () => host.write('b'));

      expect(host.bodyCalls, 1, reason: 'one body fetch for all subscribers');
      expect(host.bodyKeys.single, ['b']);
      for (final r in last.values) {
        expectRevConsistent(r);
        expect(_revsOf(r)['b'], newRev);
      }
      // Bodies are shared between subscriptions (same object).
      final bodies = last.values
          .map((r) => r!.rows.firstWhere((e) => e.id == 'b').doc)
          .toList();
      for (final b in bodies) {
        expect(identical(b, bodies.first), isTrue);
      }

      host.resetCounters();
      ViewResult? late;
      final lateSub = host.useAllDocs(debounceMs: 20).listen((r) => late = r);
      await _until(() => host.useIdle && late != null);
      expect(host.bodyCalls, 0, reason: 'late subscriber reuses the cache');
      expect(late!.rows.length, 4);
      expectRevConsistent(late);

      await lateSub.cancel();
      for (final s in subs) {
        await s.cancel();
      }
    });

    test('useDoc is served from bodies another subscription fetched', () async {
      seed(['a']);
      final docs = <CouchDocumentBase?>[];
      final subAll = host.useAllDocs(debounceMs: 10).listen((_) {});
      final subDoc = host.useDoc('a', debounceMs: 60).listen(docs.add);
      await _idle(host);

      host.resetCounters();
      final rev = await _after(host, 'a', () => host.write('a'));
      expect(host.getCalls, 0);
      expect(host.bodyCalls, 1);
      expect(docs.last!.rev, rev);
      await subAll.cancel();
      await subDoc.cancel();
    });

    test('useDoc never emits a stale document after a deletion', () async {
      seed(['a']);
      final docs = <CouchDocumentBase?>[];
      final sub = host.useDoc('a', debounceMs: 10).listen(docs.add);
      await _idle(host);
      expect(docs.single, isNotNull);

      host.getLatency = const Duration(milliseconds: 150);
      final getsBefore = host.getCalls;
      host.write('a'); // its fetch snapshots this rev
      await _until(() => host.getCalls > getsBefore); // get in flight
      await _after(host, 'a', () => host.delete('a'));

      expect(docs.last, isNull);
      final nullAt = docs.indexOf(null);
      expect(docs.skip(nullAt).every((d) => d == null), isTrue);
      await sub.cancel();
    });

    test('a joined in-flight fetch at an older rev is not served', () async {
      seed(['a']);
      host.bodyLatency = const Duration(milliseconds: 120);
      final first = <ViewResult?>[];
      final second = <ViewResult?>[];
      final s1 = host.useAllDocs(keys: ['a'], debounceMs: 10).listen(first.add);
      // s1's body fetch (old rev) is in flight.
      await _until(() => host.bodyCalls == 1 && host.inFlight > 0);
      final newRev = host.writeSilently('a');
      final s2 = host
          .useAllDocs(keys: ['a'], debounceMs: 10)
          .listen(second.add);
      await _idle(host);

      first.forEach(expectRevConsistent);
      second.forEach(expectRevConsistent);
      expect(second.first!.rows.single.doc!.rev, newRev);
      expect(host.bodyCalls, 2, reason: 'join mismatched -> fresh fetch');
      await s1.cancel();
      await s2.cancel();
    });

    test(
      'a write between metadata and body fetch is retried, never mixed',
      () async {
        seed(['a', 'b']);
        var fired = false;
        host.onBodyFetch = () {
          if (fired) return;
          fired = true;
          host.writeSilently('a');
        };
        final emits = <ViewResult?>[];
        final sub = host.useAllDocs(debounceMs: 10).listen(emits.add);
        await _idle(host);
        emits.forEach(expectRevConsistent);
        expect(_revsOf(emits.last)['a'], host.docs['a']!.rev);
        expect(host.metaCalls, 2, reason: 'one retry of the metadata pass');
        await sub.cancel();
      },
    );

    test('useView: a write between view query and bodies is retried', () async {
      seed(['a']);
      host.viewIds = ['a'];
      var fired = false;
      host.onBodyFetch = () {
        if (fired) return;
        fired = true;
        host.writeSilently('a');
      };
      final emits = <ViewResult?>[];
      final sub = host
          .useView('d/v', includeDocs: true, debounceMs: 10)
          .listen(emits.add);
      await _idle(host);
      expect(emits.last!.rows.single.doc!.rev, host.docs['a']!.rev);
      await sub.cancel();
    });

    test('deletion: range row removed, keys row value.deleted', () async {
      seed(['a', 'b']);
      final range = <ViewResult?>[];
      final keyed = <ViewResult?>[];
      final s1 = host.useAllDocs(debounceMs: 10).listen(range.add);
      final s2 = host
          .useAllDocs(keys: ['a', 'b', 'zz'], debounceMs: 10)
          .listen(keyed.add);
      await _idle(host);
      await _after(host, 'a', () => host.delete('a'));

      expect(range.last!.rows.map((r) => r.id), ['b']);
      final rows = keyed.last!.rows;
      expect(rows[0].id, 'a');
      expect((rows[0].value as Map)['deleted'], isTrue);
      expect(rows[0].doc, isNull);
      expect(rows[1].doc!.rev, host.docs['b']!.rev);
      expect(rows[2].error, 'not_found');
      expect(rows[2].doc, isNull);
      keyed.forEach(expectRevConsistent);
      await s1.cancel();
      await s2.cancel();
    });

    test('attachments: true never receives shared (stub) bodies', () async {
      seed(['a', 'b']);
      host.viewIds = ['a', 'b'];
      ViewResult? shared;
      ViewResult? withAtts;
      ViewResult? viewAtts;
      final s1 = host.useAllDocs(debounceMs: 10).listen((r) => shared = r);
      await _idle(host);
      final s2 = host
          .useAllDocs(attachments: true, debounceMs: 10)
          .listen((r) => withAtts = r);
      final s3 = host
          .useView('d/v', includeDocs: true, attachments: true, debounceMs: 10)
          .listen((r) => viewAtts = r);
      await _idle(host);
      await _after(host, 'a', () => host.write('a'));

      for (final row in shared!.rows) {
        expect(row.doc!.unmappedProps['att'], 'stub');
      }
      for (final row in [...withAtts!.rows, ...viewAtts!.rows]) {
        expect(row.doc!.unmappedProps['att'], 'inline');
      }
      expectRevConsistent(withAtts);
      await s1.cancel();
      await s2.cancel();
      await s3.cancel();
    });

    test('feed error invalidates the cache; the next emit refetches', () async {
      seed(['a', 'b']);
      final errors = <Object>[];
      final sub = host
          .useAllDocs(debounceMs: 10)
          .listen((_) {}, onError: errors.add);
      await _idle(host);
      expect(host.useCacheStats.entries, 2);

      host.failFeed();
      await _until(
        () => errors.isNotEmpty,
        reason: 'feed errors still reach the stream',
      );
      expect(host.useCacheStats.entries, 0);
      expect(host.useCacheStats.invalidations, 1);

      host.resetCounters();
      await _after(host, 'a', () => host.write('a'));
      expect(host.bodyKeys.single, unorderedEquals(['a', 'b']));
      await sub.cancel();
    });

    test(
      'feed end + restart: cache dropped, live subscriptions resync',
      () async {
        seed(['a']);
        final emits = <ViewResult?>[];
        final sub = host.useAllDocs(debounceMs: 10).listen(emits.add);
        await _idle(host);
        await host.endFeed();
        await _until(
          () => host.useCacheStats.entries == 0,
          reason: 'feed end drops the cache',
        );

        // A change during the gap is never announced.
        final gapRev = host.writeSilently('a');
        // The next subscriber restarts the feed; the live one resyncs.
        final other = host.useDoc('zz', debounceMs: 10).listen((_) {});
        await _until(
          () => host.useIdle && _revsOf(emits.last)['a'] == gapRev,
          reason: 'live subscription resynced to the gap rev',
        );
        expect(host.feedStarts, 2);
        await other.cancel();
        await sub.cancel();
      },
    );

    test('feed event without a rev drops the cached body', () async {
      seed(['a']);
      final sub = host.useAllDocs(debounceMs: 10).listen((_) {});
      await _idle(host);
      expect(host.useCacheStats.entries, 1);
      final delivered = host.useFeedEvent((e) => e.id == 'a');
      host.announceWithoutRev('a');
      await delivered;
      expect(host.useCacheStats.entries, 0);
      await sub.cancel();
    });

    test(
      'eviction: referenced bodies stay, unreferenced ones are LRU-bounded',
      () async {
        seed(['a', 'b', 'c', 'd', 'e']);
        host.useCacheCapacity = 2;
        final sub = host.useAllDocs(debounceMs: 10).listen((_) {});
        await _idle(host);
        expect(host.useCacheStats.entries, 5, reason: 'all referenced');
        expect(host.useCacheStats.unreferenced, 0);

        await sub.cancel();
        expect(host.useCacheStats.unreferenced, 2);
        expect(host.useCacheStats.entries, 2);

        host.useCacheCapacity = 0;
        expect(host.useCacheStats.entries, 0);
      },
    );

    test(
      'capacity 0: bodies are evicted as soon as nobody references them',
      () async {
        seed(['a', 'b', 'c']);
        host.useCacheCapacity = 0;
        host.viewIds = ['a', 'b', 'c'];
        final sub = host
            .useView('d/v', includeDocs: true, debounceMs: 10)
            .listen((_) {});
        await _idle(host);
        expect(host.useCacheStats.entries, 3);

        // Membership change: only 'c' is referenced afterwards.
        host.viewIds = ['c'];
        await _after(host, 'c', () => host.write('c'));
        expect(host.useCacheStats.entries, 1);

        await sub.cancel();
        expect(host.useCacheStats.entries, 0);
      },
    );

    test('limit/skip changes adjust the referenced ids', () async {
      seed(['a', 'b', 'c']);
      host.useCacheCapacity = 0;
      host.viewIds = ['a', 'b', 'c'];
      ViewResult? r;
      final sub = host
          .useView('d/v', includeDocs: true, limit: 1, skip: 1, debounceMs: 10)
          .listen((v) => r = v);
      await _idle(host);
      expect(r!.rows.single.id, 'b');
      expect(host.useCacheStats.entries, 1);

      await _after(host, 'b', () => host.delete('b'));
      expect(r!.rows.single.id, 'c');
      expect(r!.rows.single.doc!.rev, host.docs['c']!.rev);
      expect(host.useCacheStats.entries, 1);
      await sub.cancel();
    });

    test(
      'view rows linking other documents (value._id) use the plain query',
      () async {
        seed(['a']);
        host.viewIds = ['a'];
        host.linkedViewRows = true;
        ViewResult? r;
        final sub = host
            .useView('d/v', includeDocs: true, debounceMs: 10)
            .listen((v) => r = v);
        await _idle(host);
        expect(host.queryIncludeDocsCalls, 1);
        expect(r!.rows.single.doc!.rev, host.docs['a']!.rev);
        await sub.cancel();
      },
    );

    test('useViewWithChanges still emits row deltas', () async {
      seed(['a', 'b']);
      host.viewIds = ['a', 'b'];
      final updates = <ViewUpdate>[];
      final sub = host
          .useViewWithChanges('d/v', includeDocs: true, debounceMs: 10)
          .listen(updates.add);
      await _idle(host);
      await _after(host, 'b', () => host.write('b'));
      expect(updates.first, isA<ViewSnapshot>());
      final delta = updates.last as ViewChanges;
      expect(delta.changes.single, isA<ViewRowChanged>());
      expect((delta.changes.single as ViewRowChanged).row.id, 'b');
      await sub.cancel();
    });

    test('direct get/allDocs calls are not served from the cache', () async {
      seed(['a']);
      ViewResult? r;
      final sub = host.useAllDocs(debounceMs: 10).listen((v) => r = v);
      await _idle(host);
      final cached = r!.rows.single.doc;
      final stats = host.useCacheStats.toString();

      host.resetCounters();
      final direct = await host.allDocs(includeDocs: true);
      final got = await host.get('a');
      expect(host.bodyCalls, 1);
      expect(host.getCalls, 1);
      expect(identical(direct.rows.single.doc, cached), isFalse);
      expect(identical(got, cached), isFalse);
      expect(host.useCacheStats.toString(), stats);
      await sub.cancel();
    });
  });
}
