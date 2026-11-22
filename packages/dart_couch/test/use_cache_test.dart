// The shared use* document-body cache against real backends (Http, Local,
// OfflineFirst). Guards that the cache is result-neutral — every settled emit
// equals a direct (uncached) query made right after it — for a matrix of
// useAllDocs / useView parameter combinations, plus rev consistency,
// replication, conflict-winner switches, deletions, attachments, fetch counts
// and eviction. Requires the Docker CouchDB test setup (Linux).
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_couch/dart_couch.dart';
import 'package:test/test.dart';

import 'helper/couch_test_manager.dart';
import 'helper/helper.dart';

enum _Mode { http, local, offline }

String _norm(ViewResult? r) => r == null ? 'null' : jsonEncode(r.toMap());

/// For view queries with duplicate `keys`, CouchDB (3.x, q > 1 shards) does
/// not fix the row order: it differs between `include_docs=true/false` and
/// GET/POST, and rows of a repeated key are even spread across its
/// occurrences (see CLAUDE.md "Known CouchDB deviations"). Compare such
/// results as a multiset of rows per key: sorted by (key, id).
String _normDupKeys(ViewResult? r) {
  if (r == null) return 'null';
  final m = r.toMap();
  final rows = [for (final row in m['rows'] as List) jsonEncode(row)]..sort();
  m['rows'] = rows;
  return jsonEncode(m);
}

/// Every emitted row carrying `value.rev` has its body at exactly that rev.
void _expectRevConsistent(ViewResult? r, String name) {
  if (r == null) return;
  for (final row in r.rows) {
    final v = row.value;
    if (v is Map && v['rev'] is String && row.doc != null) {
      expect(row.doc!.rev, v['rev'], reason: '$name: row ${row.id}');
    }
    if (v is Map && v['deleted'] == true) {
      expect(row.doc, isNull, reason: '$name: deleted row ${row.id}');
    }
  }
}

/// One use* subscription and its uncached reference query.
class _Case {
  _Case(this.name, this.stream, this.reference, {this.norm = _norm});
  final String name;
  final Stream<ViewResult?> Function(DartCouchDb db) stream;
  final Future<ViewResult?> Function(DartCouchDb db) reference;
  final String Function(ViewResult?) norm;
  final List<ViewResult?> emits = <ViewResult?>[];
}

Future<void> _expectSettled(
  DartCouchDb db,
  List<_Case> cases,
  String step,
) async {
  for (final c in cases) {
    // Defined state: the last emit equals the uncached query (asserted below
    // either way, so a timeout surfaces as the mismatch).
    await waitForCondition(
      () async =>
          c.emits.isNotEmpty &&
          c.norm(c.emits.last) == c.norm(await c.reference(db)),
      maxAttempts: 60,
      interval: const Duration(milliseconds: 250),
    );
    expect(
      c.norm(c.emits.isEmpty ? null : c.emits.last),
      c.norm(await c.reference(db)),
      reason: '${c.name} after "$step" must equal the uncached query',
    );
    for (final e in c.emits) {
      _expectRevConsistent(e, c.name);
    }
  }
}

Future<String> _putItem(DartCouchDb db, String id, String group, int n) async {
  final existing = await db.getRaw(id);
  final res = await db.putRaw({
    '_id': id,
    '_rev': ?existing?['_rev'],
    if (existing?['_attachments'] != null)
      '_attachments': existing!['_attachments'],
    'type': 'item',
    'group': group,
    'n': n,
  });
  return res['_rev'] as String;
}

/// Waits until no use* emit of [db] is scheduled or running.
Future<void> _expectIdle(DartCouchDb db) async {
  expect(
    await waitForCondition(
      () async => db.useIdle,
      maxAttempts: 200,
      interval: const Duration(milliseconds: 50),
    ),
    isTrue,
    reason: 'use* streams did not settle',
  );
}

/// A feed entry for [id] at a rev other than [oldRev] (the next write).
bool Function(ChangeEntry) _nextRevOf(String id, String oldRev) =>
    (e) => e.id == id && e.changes.any((c) => c.rev != oldRev);

Future<String> _revOf(DartCouchDb db, String id) async =>
    (await db.getRaw(id))!['_rev'] as String;

void main() {
  DartCouchDb.ensureInitialized();
  configureTestLogging();

  final cm = CouchTestManager();
  setUpAll(() async => cm.init());
  tearDownAll(() async => cm.dispose());

  for (final mode in _Mode.values) {
    group('use* body cache - ${mode.name}', () => _tests(cm, mode));
  }

  group('use* body cache - OfflineFirst replication', () {
    setUp(() async => cm.prepareNewTest());
    tearDown(() async => cm.cleanupAfterTest());

    test('a server-side update pulled into the local db reaches every '
        'subscriber at the new rev, never the old one afterwards', () async {
      final db = await cm.offlineDb();
      final server = await cm.httpDb();
      await server.putRaw({
        '_id': '_design/c',
        'views': {
          'by_group': {'map': 'function(doc){ emit(doc.group, doc.n); }'},
        },
      });
      for (var i = 0; i < 4; i++) {
        await _putItem(server, 'd$i', 'g${i % 2}', i);
      }
      await waitForSync(db, maxSeconds: 15);
      expect(
        await waitForCondition(() async => await db.getRaw('d3') != null),
        isTrue,
      );

      final allEmits = <ViewResult?>[];
      final keyEmits = <ViewResult?>[];
      final viewEmits = <ViewResult?>[];
      final docEmits = <CouchDocumentBase?>[];
      final subs = [
        db.useAllDocs(debounceMs: 50).listen(allEmits.add),
        db.useAllDocs(keys: ['d1', 'd2'], debounceMs: 50).listen(keyEmits.add),
        db
            .useView('c/by_group', includeDocs: true, debounceMs: 50)
            .listen(viewEmits.add),
        db.useDoc('d1', debounceMs: 50).listen(docEmits.add),
      ];
      expect(
        await waitForCondition(
          () async =>
              allEmits.isNotEmpty &&
              keyEmits.isNotEmpty &&
              viewEmits.isNotEmpty &&
              docEmits.isNotEmpty,
        ),
        isTrue,
      );
      final oldRev = await _revOf(db, 'd1');

      final delivered = db.useFeedEvent(_nextRevOf('d1', oldRev));
      final newRev = await _putItem(server, 'd1', 'g1', 100);
      String? revIn(ViewResult? r) =>
          r?.rows.firstWhere((e) => e.id == 'd1').doc?.rev;
      final arrived = await waitForCondition(
        () async =>
            revIn(allEmits.last) == newRev &&
            revIn(keyEmits.last) == newRev &&
            revIn(viewEmits.last) == newRev &&
            docEmits.last?.rev == newRev,
        maxAttempts: 60,
      );
      expect(arrived, isTrue);
      // Defined state: the pulled change reached every subscription and all
      // resulting emits finished -- a stale emit could only come before.
      await delivered;
      await _expectIdle(db);

      void neverOldAfterNew(List<String?> revs, String name) {
        final first = revs.indexOf(newRev);
        expect(first, isNonNegative, reason: name);
        expect(revs.skip(first), isNot(contains(oldRev)), reason: name);
      }

      neverOldAfterNew(allEmits.map(revIn).toList(), 'useAllDocs');
      neverOldAfterNew(keyEmits.map(revIn).toList(), 'useAllDocs(keys)');
      neverOldAfterNew(viewEmits.map(revIn).toList(), 'useView');
      neverOldAfterNew(docEmits.map((d) => d?.rev).toList(), 'useDoc');
      for (final e in [...allEmits, ...keyEmits]) {
        _expectRevConsistent(e, 'replication');
      }
      for (final s in subs) {
        await s.cancel();
      }
    });
  });
}

void _tests(CouchTestManager cm, _Mode mode) {
  late DartCouchDb db;

  setUp(() async {
    await cm.prepareNewTest();
    db = switch (mode) {
      _Mode.http => await cm.httpDb(),
      _Mode.local => await cm.localDb(),
      _Mode.offline => await cm.offlineDb(),
    };
    await db.putRaw({
      '_id': '_design/c',
      'views': {
        'by_group': {
          'map':
              "function(doc){ if (doc.type === 'item') emit(doc.group, doc.n); }",
        },
        'count': {
          'map':
              "function(doc){ if (doc.type === 'item') emit(doc.group, 1); }",
          'reduce': '_count',
        },
      },
    });
    for (var i = 0; i < 6; i++) {
      await _putItem(db, 'd$i', 'g${i % 3}', i);
    }
  });

  tearDown(() async => cm.cleanupAfterTest());

  test(
    'parameter matrix: every settled emit equals the uncached query',
    () async {
      final g0 = jsonEncode('g0');
      final g1 = jsonEncode('g1');
      final g2 = jsonEncode('g2');
      final keys = ['d1', 'd3', 'missing', 'd1', '_design/c'];
      final cases = <_Case>[
        for (final includeDocs in [true, false]) ...[
          _Case(
            'useAllDocs(includeDocs: $includeDocs)',
            (db) => db.useAllDocs(includeDocs: includeDocs, debounceMs: 50),
            (db) => db.allDocs(includeDocs: includeDocs),
          ),
          _Case(
            'useAllDocs(keys, includeDocs: $includeDocs)',
            (db) => db.useAllDocs(
              keys: keys,
              includeDocs: includeDocs,
              debounceMs: 50,
            ),
            (db) => db.allDocs(keys: keys, includeDocs: includeDocs),
          ),
          _Case(
            'useView(includeDocs: $includeDocs)',
            (db) => db.useView(
              'c/by_group',
              includeDocs: includeDocs,
              debounceMs: 50,
            ),
            (db) => db.query('c/by_group', includeDocs: includeDocs),
          ),
        ],
        _Case(
          'useAllDocs(keys: [])',
          (db) => db.useAllDocs(keys: const [], debounceMs: 50),
          (db) => db.allDocs(keys: const [], includeDocs: true),
        ),
        _Case(
          'useAllDocs(attachments: true)',
          (db) => db.useAllDocs(attachments: true, debounceMs: 50),
          (db) => db.allDocs(includeDocs: true, attachments: true),
        ),
        _Case(
          'useAllDocs(keys, attachments: true)',
          (db) => db.useAllDocs(keys: keys, attachments: true, debounceMs: 50),
          (db) => db.allDocs(keys: keys, includeDocs: true, attachments: true),
        ),
        _Case(
          'useView(key)',
          (db) => db.useView(
            'c/by_group',
            key: g1,
            includeDocs: true,
            debounceMs: 50,
          ),
          (db) => db.query('c/by_group', key: g1, includeDocs: true),
        ),
        _Case(
          'useView(keys incl. duplicate)',
          (db) => db.useView(
            'c/by_group',
            keys: [g0, g2, g0],
            includeDocs: true,
            debounceMs: 50,
          ),
          (db) => db.query('c/by_group', keys: [g0, g2, g0], includeDocs: true),
          norm: _normDupKeys,
        ),
        _Case(
          'useView(startkey/endkey)',
          (db) => db.useView(
            'c/by_group',
            startkey: g0,
            endkey: g1,
            includeDocs: true,
            debounceMs: 50,
          ),
          (db) => db.query(
            'c/by_group',
            startkey: g0,
            endkey: g1,
            includeDocs: true,
          ),
        ),
        _Case(
          'useView(limit/skip)',
          (db) => db.useView(
            'c/by_group',
            limit: 2,
            skip: 1,
            includeDocs: true,
            debounceMs: 50,
          ),
          (db) => db.query('c/by_group', limit: 2, skip: 1, includeDocs: true),
        ),
        _Case(
          'useView(descending)',
          (db) => db.useView(
            'c/by_group',
            descending: true,
            includeDocs: true,
            debounceMs: 50,
          ),
          (db) => db.query('c/by_group', descending: true, includeDocs: true),
        ),
        _Case(
          'useView(attachments: true)',
          (db) => db.useView(
            'c/by_group',
            includeDocs: true,
            attachments: true,
            debounceMs: 50,
          ),
          (db) => db.query('c/by_group', includeDocs: true, attachments: true),
        ),
        _Case(
          'useView(reduce view, reduce: false, includeDocs)',
          (db) => db.useView(
            'c/count',
            reduce: false,
            includeDocs: true,
            debounceMs: 50,
          ),
          (db) => db.query('c/count', reduce: false, includeDocs: true),
        ),
        _Case(
          'useView(reduce, group)',
          (db) => db.useView('c/count', group: true, debounceMs: 50),
          (db) => db.query('c/count', group: true),
        ),
      ];

      final subs = [for (final c in cases) c.stream(db).listen(c.emits.add)];
      await _expectSettled(db, cases, 'initial');

      await _putItem(db, 'd1', 'g1', 101);
      await _expectSettled(db, cases, 'update d1');

      await db.remove('d3', await _revOf(db, 'd3'));
      await _expectSettled(db, cases, 'delete d3');

      await _putItem(db, 'd7', 'g1', 7);
      await _expectSettled(db, cases, 'create d7');

      await _putItem(db, 'd2', 'g0', 2); // moves d2 between key ranges
      await _expectSettled(db, cases, 'move d2');

      await db.saveAttachment(
        'd4',
        await _revOf(db, 'd4'),
        'a.bin',
        Uint8List.fromList([1, 2, 3, 4]),
      );
      await _expectSettled(db, cases, 'attachment on d4');

      // Same body content again: a new rev must still be picked up.
      await _putItem(db, 'd0', 'g0', 0);
      await _expectSettled(db, cases, 'rewrite d0');

      for (final s in subs) {
        await s.cancel();
      }
    },
  );

  test('K=3 useAllDocs + 1 useView: one put -> one body fetch; late '
      'subscriber fetches none', () async {
    final last = <int, ViewResult?>{};
    final subs = [
      for (var i = 0; i < 3; i++)
        db.useAllDocs(debounceMs: 100).listen((r) => last[i] = r),
      db
          .useView('c/by_group', includeDocs: true, debounceMs: 100)
          .listen((r) => last[3] = r),
    ];
    expect(await waitForCondition(() async => last.length == 4), isTrue);
    await _expectIdle(db);

    db.useCacheStats.reset();
    final delivered = db.useFeedEvent(
      _nextRevOf('d2', await _revOf(db, 'd2')),
    );
    final rev = await _putItem(db, 'd2', 'g2', 202);
    String? revIn(ViewResult? r) =>
        r?.rows.firstWhere((e) => e.id == 'd2').doc?.rev;
    expect(
      await waitForCondition(
        () async => last.values.every((r) => revIn(r) == rev),
      ),
      isTrue,
    );
    await delivered;
    await _expectIdle(db);
    expect(db.useCacheStats.fetches, 1, reason: '${db.useCacheStats}');
    expect(db.useCacheStats.fetchedDocs, 1);

    db.useCacheStats.reset();
    ViewResult? late;
    final lateSub = db.useAllDocs(debounceMs: 100).listen((r) => late = r);
    expect(await waitForCondition(() async => late != null), isTrue);
    expect(db.useCacheStats.fetches, 0, reason: '${db.useCacheStats}');
    _expectRevConsistent(late, 'late');

    await lateSub.cancel();
    for (final s in subs) {
      await s.cancel();
    }
  });

  if (mode != _Mode.offline) {
    test(
      'conflict winner switch: emitted bodies carry the new winner',
      () async {
        String hx(String tag) => tag.padRight(32, '0');
        Future<String> inject(
          int start,
          List<String> tags, {
          bool deleted = false,
          String? val,
        }) async {
          final ids = tags.map(hx).toList();
          await db.bulkDocsRaw([
            jsonEncode({
              '_id': 'cx',
              '_rev': '$start-${ids.first}',
              '_revisions': {'start': start, 'ids': ids},
              'type': 'item',
              'group': 'g0',
              'val': ?val,
              if (deleted) '_deleted': true,
            }),
          ], newEdits: false);
          return '$start-${ids.first}';
        }

        final loser = await inject(2, ['aaaa', 'ba5e'], val: 'loser');
        final winner = await inject(2, ['bbbb', 'ba5e'], val: 'winner');
        expect(await _revOf(db, 'cx'), winner);

        final allEmits = <ViewResult?>[];
        final keyEmits = <ViewResult?>[];
        final docEmits = <CouchDocumentBase?>[];
        final subs = [
          db.useAllDocs(debounceMs: 50).listen(allEmits.add),
          db.useAllDocs(keys: ['cx'], debounceMs: 50).listen(keyEmits.add),
          db.useDoc('cx', debounceMs: 50).listen(docEmits.add),
        ];
        String? revIn(ViewResult? r) =>
            r?.rows.firstWhere((e) => e.id == 'cx').doc?.rev;
        expect(
          await waitForCondition(
            () async =>
                revIn(allEmits.lastOrNull) == winner &&
                revIn(keyEmits.lastOrNull) == winner &&
                docEmits.lastOrNull?.rev == winner,
          ),
          isTrue,
        );

        // Tombstone the winner branch: the loser becomes the winner.
        await inject(3, ['dddd', 'bbbb', 'ba5e'], deleted: true);
        expect(await _revOf(db, 'cx'), loser);
        expect(
          await waitForCondition(
            () async =>
                revIn(allEmits.last) == loser &&
                revIn(keyEmits.last) == loser &&
                docEmits.last?.rev == loser,
          ),
          isTrue,
        );
        expect(keyEmits.last!.rows.single.doc!.unmappedProps['val'], 'loser');
        for (final e in [...allEmits, ...keyEmits]) {
          _expectRevConsistent(e, 'conflict');
        }
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
  }

  test(
    'delete: useDoc emits null and never a stale document afterwards',
    () async {
      final docs = <CouchDocumentBase?>[];
      final sub = db.useDoc('d5', debounceMs: 30).listen(docs.add);
      expect(await waitForCondition(() async => docs.isNotEmpty), isTrue);
      await _putItem(db, 'd5', 'g2', 55);
      final deleted = db.useFeedEvent(
        (e) => e.id == 'd5' && e.deleted == true,
      );
      await db.remove('d5', await _revOf(db, 'd5'));
      expect(
        await waitForCondition(
          () async => docs.isNotEmpty && docs.last == null,
        ),
        isTrue,
      );
      await deleted;
      await _expectIdle(db);
      final firstNull = docs.indexOf(null);
      expect(
        docs.skip(firstNull).every((d) => d == null),
        isTrue,
        reason: '$docs',
      );
      await sub.cancel();
    },
  );

  test(
    'attachments: true never receives stub bodies from the shared cache',
    () async {
      await db.saveAttachment(
        'd1',
        await _revOf(db, 'd1'),
        'a.bin',
        Uint8List.fromList([9, 8, 7]),
      );
      ViewResult? shared;
      ViewResult? inline;
      final s1 = db.useAllDocs(debounceMs: 50).listen((r) => shared = r);
      expect(await waitForCondition(() async => shared != null), isTrue);
      final s2 = db
          .useAllDocs(attachments: true, debounceMs: 50)
          .listen((r) => inline = r);
      expect(await waitForCondition(() async => inline != null), isTrue);

      AttachmentInfo? att(ViewResult? r) =>
          r!.rows.firstWhere((e) => e.id == 'd1').doc!.attachments!['a.bin'];
      expect(att(shared)!.data, isNull, reason: 'shared: stub');
      expect(att(inline)!.data, isNotNull, reason: 'attachments: inline data');
      await s1.cancel();
      await s2.cancel();
    },
  );

  test(
    'eviction after cancel is bounded by the capacity; 0 evicts all',
    () async {
      db.useCacheCapacity = 3;
      ViewResult? r;
      final sub = db.useAllDocs(debounceMs: 50).listen((v) => r = v);
      expect(await waitForCondition(() async => r != null), isTrue);
      expect(db.useCacheStats.entries, greaterThanOrEqualTo(6));
      await sub.cancel();
      expect(db.useCacheStats.unreferenced, lessThanOrEqualTo(3));
      db.useCacheCapacity = 0;
      expect(db.useCacheStats.entries, 0);
      db.useCacheCapacity = 1000;
    },
  );

  test('direct get/allDocs/query are unaffected by the cache', () async {
    ViewResult? r;
    final sub = db.useAllDocs(debounceMs: 50).listen((v) => r = v);
    expect(await waitForCondition(() async => r != null), isTrue);
    final cached = r!.rows.firstWhere((e) => e.id == 'd1').doc;

    final stats = db.useCacheStats.toString();
    final direct = await db.allDocs(keys: ['d1'], includeDocs: true);
    final got = await db.get('d1');
    final viaView = await db.query('c/by_group', includeDocs: true);
    expect(identical(direct.rows.single.doc, cached), isFalse);
    expect(identical(got, cached), isFalse);
    expect(viaView!.rows.where((e) => identical(e.doc, cached)), isEmpty);
    expect(db.useCacheStats.toString(), stats);
    await sub.cancel();
  });
}
