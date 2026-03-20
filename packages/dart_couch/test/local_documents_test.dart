import 'dart:convert';

import 'package:dart_couch/dart_couch.dart';
import 'package:test/test.dart';
import 'package:logging/logging.dart';

import 'helper/helper.dart';

void main() {

  Logger.root.level = Level.FINEST;
  Logger.root.onRecord.listen((record) {
    LineSplitter ls = LineSplitter();
    for (final line in ls.convert(record.message)) {
      // ignore: avoid_print
      print('${record.loggerName} ${record.level.name}: ${record.time}: $line');
    }
  });

  group('HTTP', () {
    doTest(setUpAllHttpFunction, tearDownAllHttpFunction);
  });

  group('Local', () {
    doTest(setUpAllLocalFunction, null);
  });
}

void doTest(
  Future<DartCouchServer> Function() setupAll,
  Future<void> Function()? tearDownFunction,
) {
  late DartCouchServer cl;

  setUpAll(() async {
    cl = await setupAll();
  });

  tearDownAll(() async {
    if (tearDownFunction != null) await tearDownFunction();
  });

  group('Basic CRUD Operations', () {
    test('create, retrieve and delete local documents', () async {
      final db = await cl.createDatabase('local_crud_test');

      final doc = CouchDocumentBase(
        id: '_local/test1',
        unmappedProps: {'data': 'value1'},
      );
      final created = await db.put(doc);

      expect(created.id, '_local/test1');
      expect(created.rev, startsWith('0-'));
      expect(created.unmappedProps['data'], 'value1');

      final retrieved = await db.get('_local/test1');
      expect(retrieved, isNotNull);
      expect(retrieved!.id, '_local/test1');
      expect(retrieved.rev, created.rev);

      final deletedRev = await db.remove('_local/test1', created.rev!);
      expect(deletedRev, startsWith('0-'));

      final afterDelete = await db.get('_local/test1');
      expect(afterDelete, isNull);

      await cl.deleteDatabase('local_crud_test');
    });

    test('update local document', () async {
      final db = await cl.createDatabase('local_update_test');

      final doc = CouchDocumentBase(
        id: '_local/test2',
        unmappedProps: {'counter': 1},
      );
      final created = await db.put(doc);
      expect(created.rev, '0-1');

      final updated = await db.put(
        created.copyWith(unmappedProps: {'counter': 2}),
      );
      expect(updated.rev, '0-2');
      expect(updated.unmappedProps['counter'], 2);

      await cl.deleteDatabase('local_update_test');
    });

    test('POST without _local/ prefix uses hash revisions', () async {
      final db = await cl.createDatabase('regular_post_test');

      final doc = CouchDocumentBase(
        id: 'regular_doc',
        unmappedProps: {'type': 'regular'},
      );
      final created = await db.post(doc);

      expect(created.rev, matches(r'^\d+-[a-f0-9]{32}$'));
      expect(created.rev, isNot(startsWith('0-')));

      await cl.deleteDatabase('regular_post_test');
    });

    test('POST with _local/ prefix uses simplified revisions', () async {
      final db = await cl.createDatabase('local_post_test');

      final doc = CouchDocumentBase(
        id: '_local/test3',
        unmappedProps: {'type': 'local'},
      );
      final created = await db.post(doc);

      expect(created.rev, '0-1');

      await cl.deleteDatabase('local_post_test');
    });
  });

  group('Revision Format', () {
    test('uses 0-N format', () async {
      final db = await cl.createDatabase('rev_format_test');

      final doc = CouchDocumentBase(
        id: '_local/revtest1',
        unmappedProps: {'test': 'data'},
      );
      final created = await db.put(doc);

      expect(created.rev, matches(r'^0-\d+$'));
      expect(created.rev, isNot(matches(r'^\d+-[a-f0-9]{32}$')));

      await cl.deleteDatabase('rev_format_test');
    });

    test('increments correctly', () async {
      final db = await cl.createDatabase('rev_incr_test');

      final doc = CouchDocumentBase(
        id: '_local/revtest2',
        unmappedProps: {'version': 1},
      );

      final v1 = await db.put(doc);
      expect(v1.rev, '0-1');

      final v2 = await db.put(v1.copyWith(unmappedProps: {'version': 2}));
      expect(v2.rev, '0-2');

      final v3 = await db.put(v2.copyWith(unmappedProps: {'version': 3}));
      expect(v3.rev, '0-3');

      await cl.deleteDatabase('rev_incr_test');
    });
  });

  group('Conflicts', () {
    test('POST with existing ID succeeds (upsert behavior)', () async {
      final db = await cl.createDatabase('conflict_post_test');

      final doc = CouchDocumentBase(
        id: '_local/conflict1',
        unmappedProps: {'data': 'first'},
      );
      final first = await db.post(doc);
      expect(first.rev, '0-1');

      // Posting again with same ID succeeds (overwrites)
      final doc2 = CouchDocumentBase(
        id: '_local/conflict1',
        unmappedProps: {'data': 'second'},
      );
      final second = await db.post(doc2);
      // CouchDB returns 0-1 for POST overwrite (doesn't increment)
      expect(second.rev, '0-1');
      expect(second.unmappedProps['data'], 'second');

      await cl.deleteDatabase('conflict_post_test');
    });

    test('PUT with wrong revision succeeds (permissive)', () async {
      final db = await cl.createDatabase('conflict_put_test');

      final doc = CouchDocumentBase(
        id: '_local/conflict2',
        unmappedProps: {'data': 'value'},
      );
      final created = await db.put(doc);
      expect(created.rev, '0-1');

      // PUT with wrong revision still succeeds for local documents
      final updated = await db.put(
        created.copyWith(rev: '0-999', unmappedProps: {'data': 'updated'}),
      );
      expect(updated.rev, '0-1000');

      await cl.deleteDatabase('conflict_put_test');
    });

    test('DELETE with wrong revision succeeds (permissive)', () async {
      final db = await cl.createDatabase('conflict_del_test');

      final doc = CouchDocumentBase(
        id: '_local/conflict3',
        unmappedProps: {'data': 'value'},
      );
      final created = await db.put(doc);
      expect(created.rev, '0-1');

      // DELETE with wrong revision still succeeds for local documents
      // CouchDB returns 0-0 (resets counter)
      final deletedRev = await db.remove('_local/conflict3', '0-999');
      expect(deletedRev, '0-0');

      await cl.deleteDatabase('conflict_del_test');
    });
  });

  group('Error Cases', () {
    test('PUT with deleted: true creates deleted document', () async {
      final db = await cl.createDatabase('error_put_del_test');

      final doc = CouchDocumentBase(
        id: '_local/error2',
        deleted: true,
        unmappedProps: {'data': 'value'},
      );

      // CouchDB accepts this and creates a deleted document with rev 0-0
      final result = await db.put(doc);
      expect(result.rev, '0-0');
      expect(result.deleted, isTrue);

      // Document should not be retrievable (it's deleted)
      final retrieved = await db.get('_local/error2');
      expect(retrieved, isNull);

      await cl.deleteDatabase('error_put_del_test');
    });

    test('DELETE non-existent fails', () async {
      final db = await cl.createDatabase('error_del_nonexist_test');

      await expectLater(
        db.remove('_local/nonexistent', '0-1'),
        throwsA(isA<CouchDbException>()),
      );

      await cl.deleteDatabase('error_del_nonexist_test');
    });

    test('GET non-existent returns null', () async {
      final db = await cl.createDatabase('error_get_nonexist_test');

      final result = await db.get('_local/nonexistent');
      expect(result, isNull);

      await cl.deleteDatabase('error_get_nonexist_test');
    });
  });

  group('Filtering', () {
    test('_local_docs returns only local documents', () async {
      final db = await cl.createDatabase('filter_localdocs_test');

      await db.put(
        CouchDocumentBase(
          id: '_local/local1',
          unmappedProps: {'type': 'local'},
        ),
      );
      await db.put(
        CouchDocumentBase(
          id: '_local/local2',
          unmappedProps: {'type': 'local'},
        ),
      );
      await db.put(
        CouchDocumentBase(id: 'regular1', unmappedProps: {'type': 'regular'}),
      );

      final localDocs = await db.getLocalDocuments();

      expect(localDocs.rows.length, 2);
      expect(localDocs.rows.every((r) => r.id!.startsWith('_local/')), isTrue);

      await cl.deleteDatabase('filter_localdocs_test');
    });

    test('_local_docs filtering by keys works', () async {
      final db = await cl.createDatabase('filter_keys_test');

      await db.put(
        CouchDocumentBase(id: '_local/key1', unmappedProps: {'data': '1'}),
      );
      await db.put(
        CouchDocumentBase(id: '_local/key2', unmappedProps: {'data': '2'}),
      );
      await db.put(
        CouchDocumentBase(id: '_local/key3', unmappedProps: {'data': '3'}),
      );

      final filtered = await db.getLocalDocuments(
        keys: ['_local/key1', '_local/key3'],
      );

      expect(filtered.rows.length, 2);
      expect(
        filtered.rows.map((r) => r.id),
        containsAll(['_local/key1', '_local/key3']),
      );

      await cl.deleteDatabase('filter_keys_test');
    });

    test('local documents excluded from changes', () async {
      final db = await cl.createDatabase('filter_changes_test');

      await db.put(
        CouchDocumentBase(
          id: '_local/changes_test',
          unmappedProps: {'data': 'value'},
        ),
      );
      await db.put(
        CouchDocumentBase(
          id: 'regular_changes_test',
          unmappedProps: {'data': 'value'},
        ),
      );

      final changesStream = db.changes();
      final changesList = await changesStream.toList();

      final ids = changesList
          .map((r) => r.normal!.results.map((res) => res.id))
          .expand((x) => x)
          .toList();

      expect(ids.contains('_local/changes_test'), isFalse);
      expect(ids.contains('regular_changes_test'), isTrue);

      await cl.deleteDatabase('filter_changes_test');
    });

    test('local documents excluded from all_docs', () async {
      final db = await cl.createDatabase('filter_alldocs_test');

      await db.put(
        CouchDocumentBase(
          id: '_local/alldocs_test',
          unmappedProps: {'data': 'value'},
        ),
      );
      await db.put(
        CouchDocumentBase(
          id: 'regular_alldocs_test',
          unmappedProps: {'data': 'value'},
        ),
      );

      final allDocs = await db.allDocs();

      expect(allDocs.rows.any((r) => r.id == '_local/alldocs_test'), isFalse);
      expect(allDocs.rows.any((r) => r.id == 'regular_alldocs_test'), isTrue);

      await cl.deleteDatabase('filter_alldocs_test');
    });
  });

  group('Comparison', () {
    test('different revision formats for local vs regular', () async {
      final db = await cl.createDatabase('compare_revs_test');

      final localDoc = await db.put(
        CouchDocumentBase(
          id: '_local/testdoc',
          unmappedProps: {'type': 'local'},
        ),
      );

      final regularDoc = await db.put(
        CouchDocumentBase(id: 'testdoc', unmappedProps: {'type': 'regular'}),
      );

      expect(localDoc.rev, matches(r'^0-\d+$'));
      expect(regularDoc.rev, matches(r'^\d+-[a-f0-9]{32}$'));
      expect(regularDoc.rev, isNot(startsWith('0-')));

      await cl.deleteDatabase('compare_revs_test');
    });
  });
}
