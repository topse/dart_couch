import 'dart:async';

import 'package:dart_couch/dart_couch.dart';
import 'package:dart_couch/src/local_storage_engine/database.dart';
import 'package:test/test.dart';

import 'helper/helper.dart';

/// The local continuous changes feed (`AppDatabase.watchDocumentBatches`, the
/// basis of `changes(feedmode: continuous)`, the use* streams and push
/// replication) must
///  - emit every seq exactly once and in strict order, also under bursts and
///    with writes racing the initial replay,
///  - cost a bounded number of queries: ≤ 2 per write per feed in the live
///    phase and ≈ ceil(N / 500) + 1 for a replay of N documents (it used to
///    re-read the whole table per write and issue one query per document),
///  - stop querying once cancelled, after the database was deleted and after
///    the storage was closed.
const int _page = AppDatabase.watchPageSize;

String _docId(int i) => 'doc-${i.toString().padLeft(5, '0')}';

int _seqOf(ChangeEntry e) => int.parse(e.seq.split('-').first);

Future<void> _populate(DartCouchDb db, int from, int to) async {
  for (var i = from; i < to; i += _page) {
    await db.bulkDocs([
      for (var j = i; j < i + _page && j < to; j++)
        CouchDocumentBase(id: _docId(j), unmappedProps: {'n': j}),
    ]);
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

/// Every watcher of [db] has processed every completed write and [watchers]
/// watchers are live (see [AppDatabase.watchScansIdle]).
Future<void> _watchersSettled(DartCouchDb db, {required int watchers}) {
  final store = (db as LocalDartCouchDb).db;
  return _until(
    () => store.activeWatchers == watchers && store.watchScansIdle,
    reason: 'watchers did not settle',
  );
}

var _barrierCounter = 0;

/// Writes a barrier document and waits until [c] received it. The feed is
/// seq-ordered, so every entry emitted before it has been delivered: returns
/// those entries (without the barrier).
Future<List<ChangeEntry>> _untilBarrier(DartCouchDb db, _Collector c) async {
  final id = 'zz-barrier-${_barrierCounter++}';
  await db.put(CouchDocumentBase(id: id, unmappedProps: {'barrier': true}));
  await c.waitFor((e) => e.any((x) => x.id == id));
  return c.entries.takeWhile((x) => x.id != id).toList();
}

/// Collects continuous change entries until [until] holds.
class _Collector {
  final entries = <ChangeEntry>[];
  final errors = <Object>[];
  late final StreamSubscription<ChangesResult> sub;
  Completer<void>? _waiter;
  bool Function(List<ChangeEntry>)? _until;

  _Collector(Stream<ChangesResult> stream) {
    sub = stream.listen((r) {
      if (r.type != ChangesResultType.continuous) return;
      entries.add(r.continuous!);
      _check();
    }, onError: errors.add);
  }

  void _check() {
    final w = _waiter;
    if (w != null && !w.isCompleted && _until!(entries)) w.complete();
  }

  Future<void> waitFor(bool Function(List<ChangeEntry>) until) {
    _until = until;
    _waiter = Completer<void>();
    _check();
    return _waiter!.future.timeout(const Duration(seconds: 30));
  }

  List<int> get seqs => entries.map(_seqOf).toList();
}

void main() {
  DartCouchDb.ensureInitialized();
  configureTestLogging();

  group('continuous changes feed ordering', () {
    late LocalDartCouchServer server;
    late DartCouchDb db;

    setUp(() async {
      server = LocalDartCouchServer(prepareSqliteDir());
      db = await server.createDatabase('watch_order');
    });

    tearDown(() async {
      await server.dispose();
    });

    test('burst of 1000 concurrent writes: every seq once, in order', () async {
      const n = 1000;
      final c = _Collector(
        db.changes(since: '0', feedmode: FeedMode.continuous),
      );
      await Future.wait([
        for (var i = 0; i < n; i++)
          db.put(CouchDocumentBase(id: _docId(i), unmappedProps: {'n': i})),
      ]);
      await c.waitFor((e) => e.length >= n);
      final before = await _untilBarrier(db, c);
      await c.sub.cancel();

      expect(c.errors, isEmpty);
      expect(before.map(_seqOf), [for (var s = 1; s <= n; s++) s]);
      expect(before.map((e) => e.id).toSet().length, n);
    });

    test('updates re-emit the document under its new seq only', () async {
      await _populate(db, 0, 3); // seqs 1..3
      final c = _Collector(
        db.changes(since: '0', feedmode: FeedMode.continuous),
      );
      await c.waitFor((e) => e.length >= 3);
      final d1 = (await db.get(_docId(1)))!;
      await db.put(
        CouchDocumentBase(id: d1.id, rev: d1.rev, unmappedProps: {'n': 99}),
      ); // seq 4
      final d0 = (await db.get(_docId(0)))!;
      await db.remove(d0.id!, d0.rev!); // seq 5
      await c.waitFor((e) => e.length >= 5);
      final before = await _untilBarrier(db, c);
      await c.sub.cancel();

      expect(before.map(_seqOf), [1, 2, 3, 4, 5]);
      expect(before[3].id, _docId(1));
      expect(before[3].changes.single.rev, startsWith('2-'));
      expect(before[4].id, _docId(0));
      expect(before[4].deleted, isTrue);
    });

    test(
      'since replay racing concurrent writes: no gap, no duplicate',
      () async {
        const existing = 1203; // > 2 pages, last page partial
        const since = 300;
        const extra = 400;
        await _populate(db, 0, existing); // seqs 1..1203

        final c = _Collector(
          db.changes(since: '$since', feedmode: FeedMode.continuous),
        );
        // Write while the replay pages are being read (not awaited first).
        final writer = () async {
          for (var i = existing; i < existing + extra; i++) {
            await db.put(
              CouchDocumentBase(id: _docId(i), unmappedProps: {'n': i}),
            );
          }
        }();
        await writer;
        await c.waitFor(
          (e) => e.isNotEmpty && _seqOf(e.last) >= existing + extra,
        );
        final before = await _untilBarrier(db, c);
        await c.sub.cancel();

        expect(c.errors, isEmpty);
        expect(before.map(_seqOf), [
          for (var s = since + 1; s <= existing + extra; s++) s,
        ]);
      },
    );

    test('since=now emits only future changes', () async {
      await _populate(db, 0, 10);
      final c = _Collector(
        db.changes(since: 'now', feedmode: FeedMode.continuous),
      );
      // Defined state: 'now' is resolved and the watcher's first scan done.
      await _watchersSettled(db, watchers: 1);
      await db.put(CouchDocumentBase(id: 'later', unmappedProps: {'n': -1}));
      final before = await _untilBarrier(db, c);
      await c.sub.cancel();
      expect(before.map((e) => e.id), ['later']);
      expect(before.map(_seqOf), [11]);
    });

    test('include_docs delivers bodies; tombstones carry no body', () async {
      await _populate(db, 0, 2);
      final d0 = (await db.get(_docId(0)))!;
      await db.remove(d0.id!, d0.rev!);
      final c = _Collector(
        db.changes(
          since: '0',
          feedmode: FeedMode.continuous,
          includeDocs: true,
        ),
      );
      await c.waitFor((e) => e.length >= 2);
      await c.sub.cancel();
      final byId = {for (final e in c.entries) e.id: e};
      expect(byId[_docId(1)]!.doc?.id, _docId(1));
      expect(byId[_docId(0)]!.deleted, isTrue);
    });
  });

  group('continuous changes feed query budget', () {
    late LocalDartCouchServer server;
    late LocalDartCouchDb db;
    var dbCounter = 0;
    var serverDisposed = false;

    setUpAll(() {
      // Must be enabled before the database connection is opened.
      DbQueryStats.enabled = true;
    });

    tearDownAll(() {
      DbQueryStats.enabled = false;
    });

    setUp(() async {
      serverDisposed = false;
      server = LocalDartCouchServer(prepareSqliteDir());
      db =
          (await server.createDatabase('watch_budget_${dbCounter++}'))
              as LocalDartCouchDb;
    });

    tearDown(() async {
      if (!serverDisposed) await server.dispose();
    });

    var putCounter = 0;
    Future<void> putOne() => db.put(
      CouchDocumentBase(id: 'p${putCounter++}', unmappedProps: {'x': 1}),
    );

    /// Queries a single put costs on its own (no feed listening).
    Future<int> baselinePut() async {
      await putOne(); // warm-up
      await _watchersSettled(db, watchers: 0);
      final before = DbQueryStats.total;
      await putOne();
      await _watchersSettled(db, watchers: 0);
      return DbQueryStats.total - before;
    }

    for (final feeds in [1, 3]) {
      test(
        'a single write costs <= 2 queries per feed ($feeds feeds)',
        () async {
          await _populate(db, 0, 50);
          final base = await baselinePut();

          final collectors = [
            for (var i = 0; i < feeds; i++)
              _Collector(
                db.changes(since: 'now', feedmode: FeedMode.continuous),
              ),
          ];
          await _watchersSettled(db, watchers: feeds);

          for (var round = 0; round < 3; round++) {
            final before = DbQueryStats.total;
            await putOne();
            for (final c in collectors) {
              await c.waitFor((e) => e.length >= round + 1);
            }
            await _watchersSettled(db, watchers: feeds);
            final feedQueries = DbQueryStats.total - before - base;
            expect(
              feedQueries,
              lessThanOrEqualTo(2 * feeds),
              reason: 'round $round: $feedQueries feed queries',
            );
          }
          for (final c in collectors) {
            await c.sub.cancel();
          }
        },
      );
    }

    for (final n in [1203, 1500]) {
      test('replay of $n docs costs about ceil(n/500)+1 queries', () async {
        await _populate(db, 0, n);
        final pages = (n + _page - 1) ~/ _page;

        // since == null: pages only (+1 empty page when n % 500 == 0).
        var before = DbQueryStats.total;
        var received = 0;
        var done = Completer<void>();
        var sub = db.db.watchDocumentBatches(db.dbid, true).listen((b) {
          received += b.length;
          if (received >= n && !done.isCompleted) done.complete();
        });
        await done.future.timeout(const Duration(seconds: 30));
        await _watchersSettled(db, watchers: 1);
        expect(received, n);
        expect(DbQueryStats.total - before, lessThanOrEqualTo(pages + 1));
        await sub.cancel();

        // since given: + 1 query for the current update seq.
        before = DbQueryStats.total;
        received = 0;
        done = Completer<void>();
        sub = db.db.watchDocumentBatches(db.dbid, false, since: 0).listen((b) {
          received += b.length;
          if (received >= n && !done.isCompleted) done.complete();
        });
        await done.future.timeout(const Duration(seconds: 30));
        await _watchersSettled(db, watchers: 1);
        expect(received, n);
        expect(DbQueryStats.total - before, lessThanOrEqualTo(pages + 2));
        await sub.cancel();
      });
    }

    test('cancel stops further queries', () async {
      await _populate(db, 0, 20);
      final base = await baselinePut();
      final c = _Collector(
        db.changes(since: '0', feedmode: FeedMode.continuous),
      );
      await c.waitFor((e) => e.length >= 20);
      await c.sub.cancel();
      await _watchersSettled(db, watchers: 0);

      final before = DbQueryStats.total;
      for (var i = 0; i < 5; i++) {
        await putOne();
      }
      await _watchersSettled(db, watchers: 0);
      expect(DbQueryStats.total - before, lessThanOrEqualTo(5 * base));
    });

    test('database deletion ends the watcher without errors', () async {
      await _populate(db, 0, 5);
      final errors = <Object>[];
      final done = Completer<void>();
      db.db
          .watchDocumentBatches(db.dbid, true)
          .listen((_) {}, onError: errors.add, onDone: () => done.complete());
      await _watchersSettled(db, watchers: 1);
      await server.deleteDatabase(db.dbname);
      await done.future.timeout(const Duration(seconds: 5));
      expect(errors, isEmpty);
    });

    test(
      'closing the storage ends the watcher; no queries afterwards',
      () async {
        await _populate(db, 0, 5);
        final errors = <Object>[];
        final done = Completer<void>();
        db.db
            .watchDocumentBatches(db.dbid, true, since: 0)
            .listen((_) {}, onError: errors.add, onDone: () => done.complete());
        await _watchersSettled(db, watchers: 1);
        await server.dispose();
        serverDisposed = true;
        await done.future.timeout(const Duration(seconds: 5));
        final after = DbQueryStats.total;
        await _watchersSettled(db, watchers: 0);
        expect(errors, isEmpty);
        expect(DbQueryStats.total, after);
      },
    );
  });
}
