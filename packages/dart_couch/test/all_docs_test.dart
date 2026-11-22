import 'dart:convert';

import 'package:dart_couch/dart_couch.dart';
import 'package:test/test.dart';

import 'helper/helper.dart';

/// `_all_docs` served directly from `local_documents` (no view index).
///
/// Guards, on BOTH backends (Local must stay interchangeable with Http):
///  - keys mode: deleted docs → `{id, key, value: {rev, deleted: true}, doc:
///    null}`, missing ids → `not_found`, raw doc-id keys ("123"/"true"),
///    duplicates, > 500 keys;
///  - range mode: code point order (mixed case, `_design/`, underscore),
///    startkey/endkey/descending/inclusiveEnd/skip/limit/key across the 500
///    row page boundary;
///  - `total_rows` excludes deleted (and `_local/`) documents.
/// Local only: the query budget (via [DbQueryStats]), "a write does not cause
/// an `_all_docs` reindex", `_local/` keys, and views/`_all_docs` of two
/// databases in one SQLite file staying separate.
const int _page = 500;

String _pid(int i) => 'p-${i.toString().padLeft(5, '0')}';

void main() {
  DartCouchDb.ensureInitialized();
  configureTestLogging();

  group('HTTP', () {
    _parityTests(setUpAllHttpFunction, tearDownAllHttpFunction);
  });

  group('Local', () {
    _parityTests(setUpAllLocalFunction, tearDownAllLocalFunction);
  });

  // Own group: these tests open their own servers, which must not overlap
  // with the (still open) parity server of the 'Local' group.
  group('Local only', _localOnlyTests);

  group('Local query budget', () {
    const n = 2000;
    late LocalDartCouchServer server;
    late LocalDartCouchDb db;

    setUpAll(() async {
      // Must be enabled before the database connection is opened.
      DbQueryStats.enabled = true;
      server = LocalDartCouchServer(prepareSqliteDir());
      db = (await server.createDatabase('all_docs_budget')) as LocalDartCouchDb;
      for (var i = 0; i < n; i += _page) {
        await db.bulkDocs([
          for (var j = i; j < i + _page && j < n; j++)
            CouchDocumentBase(id: _pid(j), unmappedProps: {'n': j}),
        ]);
      }
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

    int pages(int rows) => (rows + _page - 1) ~/ _page;

    test('allDocs(includeDocs) over $n docs stays within '
        '2·ceil(N/500)+5 queries', () async {
      final (res, q) = await counted(() => db.allDocs(includeDocs: true));
      expect(res.rows.length, n);
      expect(res.totalRows, n);
      expect(res.rows.every((r) => r.doc != null), isTrue);
      expect(q, lessThanOrEqualTo(2 * pages(n) + 5), reason: '$q queries');
    });

    test('allDocs(keys > 500, includeDocs) is batched', () async {
      final keys = [for (var i = n - 1; i >= 0; i -= 2) _pid(i)];
      final (res, q) = await counted(
        () => db.allDocs(keys: keys, includeDocs: true),
      );
      expect(res.rows.map((r) => r.id), keys);
      expect(q, lessThanOrEqualTo(2 * pages(keys.length) + 5));
    });

    test('allDocs after a single write does not reindex a view', () async {
      await db.allDocs();
      final doc = (await db.get(_pid(7)))!;
      await db.put(doc.copyWith(unmappedProps: {'n': 7, 'changed': true}));

      final (res, q) = await counted(() => db.allDocs());
      expect(res.rows.length, n);
      // count + one page query per 500 rows; a view reindex would add the
      // update-seq check, the changed-docs scan, the conflict lookup and the
      // view-entry deletes/inserts/updates.
      expect(q, lessThanOrEqualTo(pages(n) + 4), reason: '$q queries');

      // No materialised `_all_docs` view exists any more.
      final views = await db.db
          .customSelect(
            "SELECT COUNT(*) AS c FROM local_views "
            "WHERE view_path_short = '_all_docs'",
          )
          .getSingle();
      expect(views.read<int>('c'), 0);
      final entries = await db.db
          .customSelect('SELECT COUNT(*) AS c FROM local_view_entries')
          .getSingle();
      expect(entries.read<int>('c'), 0);
    });
  });
}

void _parityTests(
  Future<DartCouchServer> Function() setupAll,
  Future<void> Function()? tearDown,
) {
  const dbName = 'all_docs_parity_db';
  const n = 1203; // > 2 pages, last page partial
  late DartCouchServer server;
  late DartCouchDb db;
  late String deletedRev;
  // All live ids in code point order (CouchDB raw collation for _all_docs).
  late List<String> liveIds;

  setUpAll(() async {
    server = await setupAll();
    if ((await server.db(dbName)) != null) await server.deleteDatabase(dbName);
    db = await server.createDatabase(dbName);
    for (var i = 0; i < n; i += _page) {
      await db.bulkDocs([
        for (var j = i; j < i + _page && j < n; j++)
          CouchDocumentBase(id: _pid(j), unmappedProps: {'n': j}),
      ]);
    }
    for (final id in ['B', 'a', 'Z1', '123', 'true', 'gone']) {
      await db.put(CouchDocumentBase(id: id, unmappedProps: {'v': id}));
    }
    await db.putRaw({
      '_id': '_design/x',
      'views': {
        'v': {'map': 'function(doc){ emit(doc._id, null); }'},
      },
    });
    await db.put(
      CouchDocumentBase(id: '_local/hidden', unmappedProps: {'v': 1}),
    );
    final gone = (await db.get('gone'))!;
    deletedRev = await db.remove(gone.id!, gone.rev!);

    liveIds = [
      for (var i = 0; i < n; i++) _pid(i),
      'B',
      'a',
      'Z1',
      '123',
      'true',
      '_design/x',
    ]..sort();
  });

  tearDownAll(() async {
    await server.deleteDatabase(dbName);
    if (tearDown != null) await tearDown();
  });

  List<String?> ids(ViewResult r) => r.rows.map((e) => e.id).toList();

  test('range: code point order, design docs included, deleted and '
      '_local excluded, totalRows', () async {
    final res = await db.allDocs();
    expect(ids(res), liveIds);
    expect(res.totalRows, liveIds.length);
    expect(res.offset, 0);
    // Mixed case / underscore order as CouchDB raw collation.
    final some = ids(
      res,
    ).where((id) => ['B', 'a', 'Z1', '_design/x', '123'].contains(id));
    expect(some, ['123', 'B', 'Z1', '_design/x', 'a']);
    for (final row in res.rows) {
      expect(row.key, row.id);
      expect((row.value as Map)['rev'], isA<String>());
      expect(row.doc, isNull);
    }
  });

  test('range: descending reverses the order', () async {
    final res = await db.allDocs(descending: true);
    expect(ids(res), liveIds.reversed.toList());
    expect(res.totalRows, liveIds.length);
  });

  test(
    'range: startkey/endkey/inclusiveEnd across the page boundary',
    () async {
      final s = jsonEncode(_pid(100));
      final e = jsonEncode(_pid(800));
      final incl = await db.allDocs(startkey: s, endkey: e);
      expect(ids(incl), [for (var i = 100; i <= 800; i++) _pid(i)]);
      expect(incl.totalRows, liveIds.length);

      final excl = await db.allDocs(
        startkey: s,
        endkey: e,
        inclusiveEnd: false,
      );
      expect(ids(excl), [for (var i = 100; i < 800; i++) _pid(i)]);
    },
  );

  test('range: descending swaps startkey/endkey roles', () async {
    final s = jsonEncode(_pid(800));
    final e = jsonEncode(_pid(100));
    final incl = await db.allDocs(startkey: s, endkey: e, descending: true);
    expect(ids(incl), [for (var i = 800; i >= 100; i--) _pid(i)]);

    final excl = await db.allDocs(
      startkey: s,
      endkey: e,
      descending: true,
      inclusiveEnd: false,
    );
    expect(ids(excl), [for (var i = 800; i > 100; i--) _pid(i)]);
  });

  test('range: skip/limit across the page boundary', () async {
    final start = jsonEncode(_pid(0));
    final r1 = await db.allDocs(startkey: start, skip: 450, limit: 100);
    expect(ids(r1), [for (var i = 450; i < 550; i++) _pid(i)]);
    // CouchDB: offset = rows before the start key + skip.
    expect(r1.offset, liveIds.indexOf(_pid(0)) + 450);

    final r2 = await db.allDocs(startkey: start, limit: 600);
    expect(ids(r2), [for (var i = 0; i < 600; i++) _pid(i)]);

    final r3 = await db.allDocs(
      startkey: jsonEncode(_pid(n - 1)),
      descending: true,
      skip: 10,
      limit: 520,
      includeDocs: true,
    );
    expect(ids(r3), [for (var i = n - 11; i > n - 11 - 520; i--) _pid(i)]);
    // Descending: the rows above the start key precede it.
    expect(r3.offset, liveIds.length - 1 - liveIds.indexOf(_pid(n - 1)) + 10);
    expect(r3.rows.every((r) => r.doc?.id == r.id), isTrue);
    expect(r3.rows.first.doc!.unmappedProps['n'], n - 11);

    final r4 = await db.allDocs(skip: liveIds.length + 5);
    expect(r4.rows, isEmpty);
    expect(r4.totalRows, liveIds.length);
    expect(r4.offset, liveIds.length); // capped at total_rows
  });

  test('range: key selects one doc id', () async {
    final r = await db.allDocs(key: jsonEncode('Z1'), includeDocs: true);
    expect(ids(r), ['Z1']);
    expect(r.rows.single.doc!.unmappedProps['v'], 'Z1');
    expect((await db.allDocs(key: jsonEncode('gone'))).rows, isEmpty);
  });

  test('range: design-doc prefix range', () async {
    final r = await db.allDocs(
      startkey: jsonEncode('_design/'),
      endkey: jsonEncode('_design0'),
    );
    expect(ids(r), ['_design/x']);
  });

  test('keys: deleted doc reports value.deleted and doc null', () async {
    final r = await db.allDocs(keys: ['gone', 'B'], includeDocs: true);
    expect(r.rows, hasLength(2));
    final del = r.rows[0];
    expect(del.id, 'gone');
    expect(del.key, 'gone');
    expect(del.error, isNull);
    expect((del.value as Map)['deleted'], isTrue);
    expect((del.value as Map)['rev'], deletedRev);
    expect(del.doc, isNull);
    expect(r.rows[1].doc!.unmappedProps['v'], 'B');
    expect(r.totalRows, liveIds.length);

    final noDocs = await db.allDocs(keys: ['gone']);
    expect((noDocs.rows.single.value as Map)['deleted'], isTrue);
  });

  test('keys: raw doc ids "123"/"true", duplicates, missing', () async {
    final keys = ['123', 'true', 'B', '123', 'missing', 'B'];
    final r = await db.allDocs(keys: keys, includeDocs: true);
    expect(r.rows, hasLength(keys.length));
    for (var i = 0; i < keys.length; i++) {
      final row = r.rows[i];
      if (keys[i] == 'missing') {
        expect(row.id, isNull);
        expect(row.key, 'missing');
        expect(row.error, 'not_found');
        expect(row.doc, isNull);
      } else {
        expect(row.id, keys[i]);
        expect(row.key, keys[i]); // a string, not 123 / true
        expect(row.doc!.id, keys[i]);
        expect(row.doc!.unmappedProps['v'], keys[i]);
      }
    }
  });

  test('keys: more than 500 keys keep request order', () async {
    final keys = [
      for (var i = n - 1; i >= 0; i--) _pid(i),
      'gone',
      'missing',
      _pid(3),
    ];
    expect(keys.length, greaterThan(2 * _page));
    final r = await db.allDocs(keys: keys);
    expect(r.rows.map((e) => e.key), keys);
    expect(r.rows[n].id, 'gone');
    expect((r.rows[n].value as Map)['deleted'], isTrue);
    expect(r.rows[n + 1].error, 'not_found');
    expect(r.rows.last.id, _pid(3));
  });

  test('query() rejects paths that are not "designdoc/view" (e.g. '
      '"_all_docs")', () async {
    // HttpDartCouchDb is the reference: `_all_docs` is not a view in
    // CouchDB, only its own endpoint (allDocs()).
    for (final path in ['_all_docs', 'nodesign', 'a/b/c']) {
      await expectLater(
        db.query(path, includeDocs: true),
        throwsArgumentError,
        reason: path,
      );
    }
  });
}

/// Behaviour that is defined by this library for Local only (CouchDB's
/// `_local/` handling in `_all_docs` keys is not relied upon) and the
/// multi-database ViewMgr scoping, which only exists in the SQLite engine.
void _localOnlyTests() {
  test('keys: a _local/ id is not_found', () async {
    final server = LocalDartCouchServer(prepareSqliteDir());
    final db = await server.createDatabase('all_docs_local_key');
    await db.put(CouchDocumentBase(id: '_local/x', unmappedProps: {'v': 1}));
    await db.put(CouchDocumentBase(id: 'y', unmappedProps: {'v': 2}));

    final r = await db.allDocs(keys: ['_local/x', 'y'], includeDocs: true);
    expect(r.rows[0].id, isNull);
    expect(r.rows[0].key, '_local/x');
    expect(r.rows[0].error, 'not_found');
    expect(r.rows[1].id, 'y');
    expect(r.totalRows, 1);
    expect((await db.allDocs()).rows.map((e) => e.id), ['y']);
    await server.dispose();
  });

  test('two databases in one SQLite file keep views and _all_docs '
      'separate', () async {
    final server = LocalDartCouchServer(prepareSqliteDir());
    final a = await server.createDatabase('viewmgr_scope_a');
    final b = await server.createDatabase('viewmgr_scope_b');

    await a.put(CouchDocumentBase(id: 'a1', unmappedProps: {'v': 'A'}));
    await b.put(CouchDocumentBase(id: 'b1', unmappedProps: {'v': 'B'}));
    await b.put(CouchDocumentBase(id: 'b2', unmappedProps: {'v': 'B'}));

    // Same view path in both databases, different map functions, plus a
    // view that exists only in A.
    await a.putRaw({
      '_id': '_design/same',
      'views': {
        'v': {'map': "function(doc){ if (doc.v) emit('A:' + doc._id, 1); }"},
      },
    });
    await a.putRaw({
      '_id': '_design/onlya',
      'views': {
        'v': {'map': 'function(doc){ if (doc.v) emit(doc._id, 1); }'},
      },
    });
    await b.putRaw({
      '_id': '_design/same',
      'views': {
        'v': {'map': "function(doc){ if (doc.v) emit('B:' + doc._id, 2); }"},
      },
    });

    // A first: creates A's index rows; B's ViewMgr must not see them.
    expect((await a.query('same/v'))!.rows.map((r) => r.key), ['A:a1']);
    expect((await a.query('onlya/v'))!.rows.map((r) => r.key), ['a1']);
    expect((await b.query('same/v'))!.rows.map((r) => r.key), ['B:b1', 'B:b2']);
    // The view of A does not exist in B.
    expect(await b.query('onlya/v'), isNull);
    // A's views survived B's initialisation.
    expect((await a.query('same/v'))!.rows.map((r) => r.key), ['A:a1']);
    expect((await a.query('onlya/v'))!.rows.map((r) => r.key), ['a1']);

    final allA = await a.allDocs();
    final allB = await b.allDocs();
    expect(allA.rows.map((r) => r.id), ['_design/onlya', '_design/same', 'a1']);
    expect(allA.totalRows, 3);
    expect(allB.rows.map((r) => r.id), ['_design/same', 'b1', 'b2']);
    expect(allB.totalRows, 3);

    await server.dispose();
  });
}
