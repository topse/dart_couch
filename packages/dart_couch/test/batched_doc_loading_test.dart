import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_couch/dart_couch.dart';
import 'package:test/test.dart';

import 'helper/helper.dart';

/// Batched `include_docs` loading for views / `_all_docs`.
///
/// `LocalDartCouchDb` resolves `include_docs` with one batched document query
/// (plus at most one batched attachment query) per 500 rows instead of ~2
/// queries per row. These tests guard
///  - the query budget (Local only, via [DbQueryStats]),
///  - parity: a doc delivered through `allDocs`/`query(includeDocs: true)` is
///    identical to `get()` of the same doc (attachments true/false, stubs,
///    revpos, ordering, `encoding`) — on BOTH backends,
///  - chunk boundaries (> 500 keys), duplicate keys and row order.
const int _chunk = 500;

Uint8List _bytes(int seed, int len) =>
    Uint8List.fromList(List<int>.generate(len, (i) => (seed + i * 7) % 256));

String _docId(int i) => 'doc-${i.toString().padLeft(5, '0')}';

/// Creates [n] docs; every 10th doc gets attachments (every 20th two, saved
/// in the order b → a so that `ordering` differs from name order).
Future<void> _populate(DartCouchDb db, int n) async {
  const batch = 500;
  for (var i = 0; i < n; i += batch) {
    final docs = [
      for (var j = i; j < i + batch && j < n; j++)
        CouchDocumentBase(
          id: _docId(j),
          unmappedProps: {'n': j, 'group': j % 3},
        ),
    ];
    await db.bulkDocs(docs);
  }
  for (var i = 0; i < n; i += 10) {
    var doc = (await db.get(_docId(i)))!;
    var rev = await db.saveAttachment(
      doc.id!,
      doc.rev!,
      'b.bin',
      _bytes(i, 64),
    );
    if (i % 20 == 0) {
      rev = await db.saveAttachment(
        doc.id!,
        rev,
        'a.txt',
        Uint8List.fromList(utf8.encode('text of ${doc.id} ' * 20)),
        contentType: 'text/plain',
      );
    }
  }
  await db.put(
    DesignDocument(
      id: '_design/batch',
      views: {
        // Two rows per doc → duplicate docids across rows.
        'twice': ViewData(
          map:
              'function(doc){ if (doc.n !== undefined) {'
              ' emit([doc.group, doc.n, 0], null);'
              ' emit([doc.group, doc.n, 1], null); } }',
        ),
      },
    ),
  );
}

/// Asserts every row's doc equals `get()` of that doc with the same
/// [attachments] flag (deep map equality + `encoding`).
Future<void> _expectParity(
  DartCouchDb db,
  List<ViewEntry> rows, {
  required bool attachments,
}) async {
  for (final row in rows) {
    if (row.id == null) {
      expect(row.doc, isNull);
      continue;
    }
    final single = await db.get(row.id!, attachments: attachments);
    expect(row.doc, isNotNull, reason: 'doc of row ${row.id}');
    expect(row.doc!.toMap(), equals(single!.toMap()), reason: row.id);
    final a = row.doc!.attachments;
    final b = single.attachments;
    expect(a?.keys.toList(), b?.keys.toList(), reason: 'order ${row.id}');
    if (a != null) {
      for (final name in a.keys) {
        expect(a[name]!.encoding, b![name]!.encoding, reason: '$name enc');
        expect(a[name]!.revpos, b[name]!.revpos);
        expect(a[name]!.stub, b[name]!.stub);
        expect(a[name]!.data, b[name]!.data);
        expect(a[name]!.length, b[name]!.length);
      }
    }
  }
}

void main() {
  DartCouchDb.ensureInitialized();
  configureTestLogging();

  group('HTTP', () {
    _parityTests(setUpAllHttpFunction, tearDownAllHttpFunction);
  });

  group('Local', () {
    _parityTests(setUpAllLocalFunction, tearDownAllLocalFunction);
  });

  group('Local query budget', () {
    const n = 2000;
    late LocalDartCouchServer server;
    late LocalDartCouchDb db;

    setUpAll(() async {
      // Must be enabled before the database connection is opened.
      DbQueryStats.enabled = true;
      server = LocalDartCouchServer(prepareSqliteDir());
      db = (await server.createDatabase('batch_budget')) as LocalDartCouchDb;
      await _populate(db, n);
      // Build the indices once so the measured calls only read.
      await db.allDocs();
      await db.query('batch/twice', limit: 1);
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

    // view lookup + update-seq check + entry select + small slack
    const overhead = 10;
    int budget(int rows) => 2 * ((rows + _chunk - 1) ~/ _chunk) + overhead;

    for (final attachments in [false, true]) {
      test(
        'allDocs(includeDocs, attachments: $attachments) is batched',
        () async {
          final (res, q) = await counted(
            () => db.allDocs(includeDocs: true, attachments: attachments),
          );
          // + 1 for the design doc
          expect(res.rows.length, n + 1);
          expect(res.rows.every((r) => r.doc != null), isTrue);
          expect(q, lessThanOrEqualTo(budget(n + 1)), reason: '$q queries');
        },
      );
    }

    test('query(includeDocs) on a 2-rows-per-doc view is batched', () async {
      final (res, q) = await counted(
        () => db.query('batch/twice', includeDocs: true),
      );
      expect(res!.rows.length, 2 * n);
      expect(q, lessThanOrEqualTo(budget(2 * n)), reason: '$q queries');
    });

    test('get() of an attachment-less doc costs a single query', () async {
      final (doc, q) = await counted(() => db.get(_docId(1)));
      expect(doc, isNotNull);
      expect(doc!.attachments, isNull);
      expect(q, 1);
    });

    test('get() of a doc with attachments costs two queries', () async {
      final (doc, q) = await counted(() => db.get(_docId(20)));
      expect(doc!.attachments!.keys, ['b.bin', 'a.txt']);
      expect(q, 2);
    });

    test('batched docs carry the stored attachment encoding', () async {
      // Simulate a CouchDB-compressed attachment (only replication from
      // CouchDB sets `encoding`; patch the column directly).
      await db.db.customStatement(
        "UPDATE local_attachments SET encoding = 'gzip' WHERE name = 'a.txt'",
      );
      final res = await db.allDocs(
        includeDocs: true,
        keys: [_docId(20), _docId(40), _docId(10)],
      );
      expect(res.rows[0].doc!.attachments!['a.txt']!.encoding, 'gzip');
      expect(res.rows[0].doc!.attachments!['b.bin']!.encoding, isNull);
      expect(res.rows[2].doc!.attachments!.keys, ['b.bin']);
      await _expectParity(db, res.rows, attachments: false);
      final withData = await db.allDocs(
        includeDocs: true,
        attachments: true,
        keys: [_docId(20), _docId(40), _docId(10)],
      );
      expect(withData.rows[1].doc!.attachments!['a.txt']!.encoding, 'gzip');
      await _expectParity(db, withData.rows, attachments: true);
    });
  });
}

void _parityTests(
  Future<DartCouchServer> Function() setupAll,
  Future<void> Function()? tearDown,
) {
  const n = 1203; // > 2 chunks, last chunk partial
  const dbName = 'batch_parity_db';
  late DartCouchServer server;
  late DartCouchDb db;

  setUpAll(() async {
    server = await setupAll();
    if ((await server.db(dbName)) != null) await server.deleteDatabase(dbName);
    db = await server.createDatabase(dbName);
    await _populate(db, n);
    // A deleted doc must not deliver a body through include_docs.
    final gone = (await db.get(_docId(n - 1)))!;
    await db.remove(gone.id!, gone.rev!);
  });

  tearDownAll(() async {
    await server.deleteDatabase(dbName);
    if (tearDown != null) await tearDown();
  });

  for (final attachments in [false, true]) {
    test('allDocs(includeDocs) docs equal get() '
        '(attachments: $attachments)', () async {
      final res = await db.allDocs(includeDocs: true, attachments: attachments);
      // n - 1 live docs + the design doc
      expect(res.rows.length, n);
      expect(res.rows.any((r) => r.id == _docId(n - 1)), isFalse);
      await _expectParity(db, res.rows, attachments: attachments);
    });
  }

  test('query(includeDocs) on a 2-rows-per-doc view equals get()', () async {
    final res = (await db.query(
      'batch/twice',
      includeDocs: true,
      attachments: true,
    ))!;
    expect(res.rows.length, 2 * (n - 1));
    // Rows are emitted twice per doc in key order [group, n, 0|1]: the two
    // rows of a doc are adjacent and carry the same document.
    for (var i = 0; i < res.rows.length; i += 2) {
      expect(res.rows[i].id, res.rows[i + 1].id);
      expect(res.rows[i].doc!.toMap(), equals(res.rows[i + 1].doc!.toMap()));
    }
    await _expectParity(db, res.rows.take(60).toList(), attachments: true);
  });

  test('keys > 500 across chunk boundaries keep order, duplicates and '
      'missing keys', () async {
    // Reverse order, every 7th key duplicated, plus a missing key at a chunk
    // edge and the deleted doc.
    final keys = <String>[];
    var missingAdded = false;
    for (var i = n - 2; i >= 0; i--) {
      keys.add(_docId(i));
      if (i % 7 == 0) keys.add(_docId(i));
      if (!missingAdded && keys.length >= _chunk - 1) {
        keys.add('does-not-exist');
        missingAdded = true;
      }
    }
    keys.add(_docId(n - 1)); // deleted
    expect(keys.length, greaterThan(2 * _chunk));

    final res = await db.allDocs(includeDocs: true, keys: keys);
    expect(res.rows.length, keys.length);
    for (var i = 0; i < keys.length; i++) {
      final row = res.rows[i];
      final k = keys[i];
      if (k == 'does-not-exist') {
        expect(row.error, 'not_found');
        expect(row.doc, isNull);
      } else if (k == _docId(n - 1)) {
        // Deleted: no body; both backends report the tombstone row with
        // value.deleted (see test/all_docs_test.dart).
        expect(row.doc, isNull);
      } else {
        expect(row.id, k, reason: 'row $i');
        expect(row.doc?.id, k, reason: 'doc of row $i');
      }
    }
    await _expectParity(
      db,
      res.rows.where((r) => r.id != null && r.doc != null).take(80).toList(),
      attachments: false,
    );
  });
}
