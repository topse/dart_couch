import 'dart:convert';

import 'package:dart_couch/dart_couch.dart';
import 'package:test/test.dart';

import 'helper/helper.dart';

/// Incremental view indexing and view-controller caching.
///
/// `LocalDartCouchDb` indexes a view in seq-ordered pages (one page query and
/// at most one write batch per 500 changed docs, unchanged docs are not
/// rewritten) and caches its view controllers, re-validating them against the
/// design document only after a design document changed. These tests guard
///  - semantics (multiple emits, map errors, deletions, `_conflicts`, design
///    doc changes, view removal, several databases) on BOTH backends, so the
///    Local results stay identical to CouchDB,
///  - the query budget (Local only, via [DbQueryStats]),
///  - that an incrementally maintained index equals a freshly built one.

/// Rows as an order-independent multiset of `[id, key, value]` (avoids
/// depending on collation differences between the backends).
List<String> _rowSet(ViewResult r) => [
  for (final row in r.rows) jsonEncode([row.id, row.key, row.value]),
]..sort();

String _row(String id, Object? key, Object? value) =>
    jsonEncode([id, key, value]);

Future<CouchDocumentBase> _put(
  DartCouchDb db,
  String id,
  Map<String, dynamic> props, {
  String? rev,
}) => db.put(CouchDocumentBase(id: id, rev: rev, unmappedProps: props));

void main() {
  DartCouchDb.ensureInitialized();
  configureTestLogging();

  group('HTTP', () {
    _semanticsTests(setUpAllHttpFunction, tearDownAllHttpFunction);
  });

  group('Local', () {
    _semanticsTests(setUpAllLocalFunction, tearDownAllLocalFunction);
  });

  group('Local view index query budget', () {
    const n = 2000;
    late LocalDartCouchServer server;
    late LocalDartCouchDb db;

    setUpAll(() async {
      // Must be enabled before the database connection is opened.
      DbQueryStats.enabled = true;
      server = LocalDartCouchServer(prepareSqliteDir());
      db = (await server.createDatabase('view_budget')) as LocalDartCouchDb;
      for (var i = 0; i < n; i += 500) {
        await db.bulkDocs([
          for (var j = i; j < i + 500 && j < n; j++)
            CouchDocumentBase(
              id: 'doc-${j.toString().padLeft(5, '0')}',
              unmappedProps: {
                // 5 % emitted by the view
                'type': j % 20 == 0 ? 'item' : 'track',
                'parent': 'p${j ~/ 100}',
                'n': j,
              },
            ),
        ]);
      }
      await db.put(
        DesignDocument(
          id: '_design/b',
          views: {
            'items': ViewData(
              map:
                  "function(doc){ if (doc.type === 'item') "
                  'emit([doc.parent, doc.n], doc.n); }',
            ),
          },
        ),
      );
    });

    tearDownAll(() async {
      await server.dispose();
      DbQueryStats.enabled = false;
    });

    Future<(T, int)> counted<T>(Future<T> Function() f) async {
      final before = DbQueryStats.total;
      final r = await f();
      return (r, DbQueryStats.total - before);
    }

    test(
      'initial index, no-op query and single writes stay in budget',
      () async {
        // Initial build: ~2 queries per 500 docs (page + write batch) plus a
        // constant for view lookup / creation and the entry select.
        final (first, q1) = await counted(() => db.query('b/items'));
        expect(first!.rows, hasLength(n ~/ 20));
        expect(
          q1,
          lessThanOrEqualTo(3 * ((n + 499) ~/ 500) + 10),
          reason: '$q1 queries',
        );

        // Unchanged db: design-doc probe + entry select.
        final (second, q2) = await counted(() => db.query('b/items'));
        expect(_rowSet(second!), _rowSet(first));
        expect(q2, lessThanOrEqualTo(3), reason: '$q2 queries');

        // One write the view does not emit for: probe + one page query +
        // entry select; no entry writes.
        await _put(db, 'unrelated', {'type': 'track', 'parent': 'p0', 'n': -1});
        final (third, q3) = await counted(() => db.query('b/items'));
        expect(_rowSet(third!), _rowSet(first));
        expect(q3, lessThanOrEqualTo(4), reason: '$q3 queries');

        // One write the view emits for: + one write batch.
        await _put(db, 'related', {'type': 'item', 'parent': 'p0', 'n': -1});
        final (fourth, q4) = await counted(() => db.query('b/items'));
        expect(fourth!.rows, hasLength(n ~/ 20 + 1));
        expect(q4, lessThanOrEqualTo(6), reason: '$q4 queries');
      },
    );

    test('incrementally maintained index equals a freshly built one', () async {
      // Mutate a mix of docs: retype, change keys, delete, emit-unchanged
      // rewrites.
      for (var j = 0; j < 200; j += 7) {
        final id = 'doc-${j.toString().padLeft(5, '0')}';
        final doc = (await db.get(id))!;
        if (j % 3 == 0) {
          await db.remove(id, doc.rev!);
        } else {
          await _put(db, id, {
            'type': j % 2 == 0 ? 'item' : 'track',
            'parent': 'p${j % 5}',
            'n': j,
          }, rev: doc.rev);
        }
      }
      final incremental = (await db.query('b/items'))!;

      // Same map under a new name → indexed from scratch.
      final ddoc = (await db.get('_design/b'))! as DesignDocument;
      await db.put(
        DesignDocument(
          id: '_design/b',
          rev: ddoc.rev,
          views: {
            'items': ddoc.views!['items']!,
            'fresh': ViewData(map: ddoc.views!['items']!.map),
          },
        ),
      );
      final fresh = (await db.query('b/fresh'))!;
      final incrementalAgain = (await db.query('b/items'))!;
      expect(_rowSet(incremental), _rowSet(fresh));
      expect(_rowSet(incrementalAgain), _rowSet(fresh));
      expect(
        [for (final r in incremental.rows) r.id],
        [for (final r in fresh.rows) r.id],
        reason: 'same row order',
      );
    });
  });
}

void _semanticsTests(
  Future<DartCouchServer> Function() setupAll,
  Future<void> Function()? tearDown,
) {
  late DartCouchServer server;

  setUpAll(() async {
    server = await setupAll();
  });

  tearDownAll(() async {
    if (tearDown != null) await tearDown();
  });

  Future<DartCouchDb> freshDb(String name) async {
    if ((await server.db(name)) != null) await server.deleteDatabase(name);
    return server.createDatabase(name);
  }

  test('multiple emits per doc, changed and unchanged rewrites', () async {
    const name = 'vi_multi';
    final db = await freshDb(name);
    await db.put(
      DesignDocument(
        id: '_design/m',
        views: {
          'tags': ViewData(
            map:
                'function(doc){ if (doc.tags) { for (var i = 0; '
                'i < doc.tags.length; i++) emit(doc.tags[i], doc.n); } }',
          ),
        },
      ),
    );
    final a = await _put(db, 'a', {
      'tags': ['x', 'y'],
      'n': 1,
    });
    await _put(db, 'b', {
      'tags': ['y'],
      'n': 2,
    });
    final c = await _put(db, 'c', {
      // identical rows twice
      'tags': ['z', 'z'],
      'n': 3,
    });
    final d = await _put(db, 'd', {'n': 4});

    expect(_rowSet((await db.query('m/tags'))!), [
      _row('a', 'x', 1),
      _row('a', 'y', 1),
      _row('b', 'y', 2),
      _row('c', 'z', 3),
      _row('c', 'z', 3),
    ]);
    // again, unchanged (cached view)
    expect((await db.query('m/tags'))!.rows, hasLength(5));

    await _put(db, 'a', {
      'tags': ['y'],
      'n': 10,
    }, rev: a.rev);
    // same emitted rows, new rev
    await _put(db, 'c', {
      'tags': ['z', 'z'],
      'n': 3,
    }, rev: c.rev);
    await _put(db, 'd', {
      'tags': ['x'],
      'n': 4,
    }, rev: d.rev);

    final after = (await db.query('m/tags'))!;
    expect(_rowSet(after), [
      _row('a', 'y', 10),
      _row('b', 'y', 2),
      _row('c', 'z', 3),
      _row('c', 'z', 3),
      _row('d', 'x', 4),
    ]);
    expect(after.totalRows, 5);
    final y = (await db.query('m/tags', key: '"y"'))!;
    expect([for (final r in y.rows) r.id], ['a', 'b']);

    await server.deleteDatabase(name);
  });

  test('a map error skips only the failing doc', () async {
    const name = 'vi_maperr';
    final db = await freshDb(name);
    await db.put(
      DesignDocument(
        id: '_design/e',
        views: {
          'k': ViewData(
            map:
                "function(doc){ if (doc.bad) { throw new Error('boom'); } "
                'if (doc.k) emit(doc.k, null); }',
          ),
        },
      ),
    );
    await _put(db, 'ok1', {'k': 'a'});
    final bad1 = await _put(db, 'bad1', {'k': 'b', 'bad': true});
    expect(_rowSet((await db.query('e/k'))!), [_row('ok1', 'a', null)]);

    await _put(db, 'ok2', {'k': 'c'});
    await _put(db, 'bad2', {'bad': true});
    expect(_rowSet((await db.query('e/k'))!), [
      _row('ok1', 'a', null),
      _row('ok2', 'c', null),
    ]);

    // fixing the doc makes it appear
    await _put(db, 'bad1', {'k': 'b'}, rev: bad1.rev);
    expect(_rowSet((await db.query('e/k'))!), [
      _row('bad1', 'b', null),
      _row('ok1', 'a', null),
      _row('ok2', 'c', null),
    ]);

    await server.deleteDatabase(name);
  });

  test('deleted docs leave the view', () async {
    const name = 'vi_deleted';
    final db = await freshDb(name);
    await db.put(
      DesignDocument(
        id: '_design/d',
        views: {
          'v': ViewData(map: 'function(doc){ if (doc.k) emit(doc.k, 1); }'),
        },
      ),
    );
    final a = await _put(db, 'a', {'k': 'a'});
    await _put(db, 'b', {'k': 'b'});
    final silent = await _put(db, 'silent', {'other': true});
    expect((await db.query('d/v'))!.rows, hasLength(2));

    await db.remove('a', a.rev!);
    await db.remove('silent', silent.rev!);
    final after = (await db.query('d/v'))!;
    expect(_rowSet(after), [_row('b', 'b', 1)]);
    expect(after.totalRows, 1);

    await server.deleteDatabase(name);
  });

  test('_conflicts appear in and disappear from a cached view', () async {
    const name = 'vi_conflicts';
    final db = await freshDb(name);
    String hx(String tag) => tag.padRight(32, '0');
    Future<void> inject(int start, List<String> tags, {bool deleted = false}) {
      final ids = tags.map(hx).toList();
      return db.bulkDocsRaw([
        jsonEncode({
          '_id': 'cd',
          '_rev': '$start-${ids.first}',
          '_revisions': {'start': start, 'ids': ids},
          'val': tags.first,
          if (deleted) '_deleted': true,
        }),
      ], newEdits: false);
    }

    await db.putRaw({
      '_id': '_design/cf',
      'views': {
        'c': {
          'map':
              'function(doc){ if (doc._conflicts) '
              'emit(doc._id, doc._conflicts.length); }',
        },
      },
    });
    await db.putRaw({'_id': 'plain', 'val': 'x'});
    await inject(2, ['a', 'ba5e']);
    expect((await db.query('cf/c'))!.rows, isEmpty);

    // sibling with a higher hash → winner 2-b, conflict 2-a
    await inject(2, ['b', 'ba5e']);
    expect(_rowSet((await db.query('cf/c'))!), [_row('cd', 'cd', 1)]);

    // tombstone the losing branch → no live conflict any more
    await inject(3, ['c', 'a', 'ba5e'], deleted: true);
    expect((await db.query('cf/c'))!.rows, isEmpty);

    await server.deleteDatabase(name);
  });

  test('map and reduce changes of a cached view are picked up', () async {
    const name = 'vi_ddoc_change';
    final db = await freshDb(name);
    await _put(db, 'doc1', {'value': 5});
    await _put(db, 'doc2', {'value': 7});
    final v1 =
        await db.put(
              DesignDocument(
                id: '_design/md',
                views: {
                  'v': ViewData(
                    map: "function(doc){ if(doc.value) emit('A', doc.value); }",
                  ),
                },
              ),
            )
            as DesignDocument;
    // build and cache
    expect((await db.query('md/v'))!.rows, hasLength(2));
    expect((await db.query('md/v'))!.rows.first.key, 'A');

    // an unrelated write in between must not hide the later change
    await _put(db, 'doc3', {'other': 1});
    expect((await db.query('md/v'))!.rows, hasLength(2));

    final v2 =
        await db.put(
              DesignDocument(
                id: '_design/md',
                rev: v1.rev,
                views: {
                  'v': ViewData(
                    map: "function(doc){ if(doc.value) emit('B', doc.value); }",
                  ),
                },
              ),
            )
            as DesignDocument;
    final changed = (await db.query('md/v'))!;
    expect(changed.rows, hasLength(2));
    expect(changed.rows.every((r) => r.key == 'B'), isTrue);

    // reduce added
    await db.put(
      DesignDocument(
        id: '_design/md',
        rev: v2.rev,
        views: {
          'v': ViewData(
            map: "function(doc){ if(doc.value) emit('B', doc.value); }",
            reduce: '_sum',
          ),
        },
      ),
    );
    final reduced = (await db.query('md/v'))!;
    expect(reduced.rows, hasLength(1));
    expect(reduced.rows.first.value, 12);
    expect((await db.query('md/v', reduce: false))!.rows, hasLength(2));

    await server.deleteDatabase(name);
  });

  test('view removal and design doc deletion are picked up', () async {
    const name = 'vi_ddoc_remove';
    final db = await freshDb(name);
    final keep = ViewData(
      map: 'function(doc){ if(doc.value) emit(doc._id, 1); }',
    );
    await _put(db, 'doc1', {'value': 5});
    final r1 =
        await db.put(
              DesignDocument(
                id: '_design/rm',
                views: {
                  'keep': keep,
                  'drop': ViewData(
                    map: 'function(doc){ if(doc.value) emit(doc._id, 2); }',
                  ),
                },
              ),
            )
            as DesignDocument;
    expect((await db.query('rm/keep'))!.rows, hasLength(1));
    expect((await db.query('rm/drop'))!.rows, hasLength(1));

    // remove one view
    final r2 =
        await db.put(
              DesignDocument(
                id: '_design/rm',
                rev: r1.rev,
                views: {'keep': keep},
              ),
            )
            as DesignDocument;
    expect(await db.query('rm/drop'), isNull);
    expect((await db.query('rm/keep'))!.rows, hasLength(1));

    // re-add it with another map
    final r3 =
        await db.put(
              DesignDocument(
                id: '_design/rm',
                rev: r2.rev,
                views: {
                  'keep': keep,
                  'drop': ViewData(
                    map: 'function(doc){ if(doc.value) emit(doc._id, 3); }',
                  ),
                },
              ),
            )
            as DesignDocument;
    final readded = (await db.query('rm/drop'))!;
    expect(_rowSet(readded), [_row('doc1', 'doc1', 3)]);

    // delete the whole design doc
    await db.remove('_design/rm', r3.rev!);
    expect(await db.query('rm/keep'), isNull);
    expect(await db.query('rm/drop'), isNull);

    await server.deleteDatabase(name);
  });

  test('two databases with the same view name keep separate indexes', () async {
    const nameA = 'vi_two_a';
    const nameB = 'vi_two_b';
    final dbA = await freshDb(nameA);
    final dbB = await freshDb(nameB);
    for (final db in [dbA, dbB]) {
      await db.put(
        DesignDocument(
          id: '_design/s',
          views: {
            'v': ViewData(
              map: 'function(doc){ if (doc.k) emit(doc.k, null); }',
            ),
          },
        ),
      );
    }
    await _put(dbA, 'a1', {'k': 'a1'});
    await _put(dbB, 'b1', {'k': 'b1'});
    await _put(dbB, 'b2', {'k': 'b2'});

    expect(_rowSet((await dbA.query('s/v'))!), [_row('a1', 'a1', null)]);
    expect(_rowSet((await dbB.query('s/v'))!), [
      _row('b1', 'b1', null),
      _row('b2', 'b2', null),
    ]);

    await _put(dbA, 'a2', {'k': 'a2'});
    expect(_rowSet((await dbB.query('s/v'))!), [
      _row('b1', 'b1', null),
      _row('b2', 'b2', null),
    ]);
    expect(_rowSet((await dbA.query('s/v'))!), [
      _row('a1', 'a1', null),
      _row('a2', 'a2', null),
    ]);

    // changing B's view must not affect A's
    final ddocB = (await dbB.get('_design/s'))!;
    await dbB.put(
      DesignDocument(
        id: '_design/s',
        rev: ddocB.rev,
        views: {
          'v': ViewData(map: 'function(doc){ if (doc.k) emit(doc.k, 1); }'),
        },
      ),
    );
    expect(_rowSet((await dbB.query('s/v'))!), [
      _row('b1', 'b1', 1),
      _row('b2', 'b2', 1),
    ]);
    expect(_rowSet((await dbA.query('s/v'))!), [
      _row('a1', 'a1', null),
      _row('a2', 'a2', null),
    ]);

    await server.deleteDatabase(nameA);
    await server.deleteDatabase(nameB);
  });
}
