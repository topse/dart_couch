import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dart_couch/dart_couch.dart';
import 'package:logging/logging.dart';
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;

import 'helper/helper.dart';
import 'helper/test_document_one.dart';

void main() {
  DartCouchDb.ensureInitialized();

  Logger.root.level = Level.FINEST;
  Logger.root.onRecord.listen((record) {
    final ls = LineSplitter();
    for (final line in ls.convert(record.message)) {
      // ignore: avoid_print
      print('${record.loggerName} ${record.level.name}: ${record.time}: $line');
    }
  });

  group('Tombstone cleanup', () {
    late LocalDartCouchServer server;
    late DartCouchDb db;
    late String sqlitePath;
    late Directory serverDir;

    setUp(() async {
      serverDir = prepareSqliteDir();
      sqlitePath = '${serverDir.path}/db.sqlite';
      server = LocalDartCouchServer(serverDir);
      db = await server.createDatabase('testdb');
    });

    tearDown(() async {
      await server.dispose();
    });

    /// Opens the raw SQLite file and runs a query, returning the result rows.
    List<Map<String, dynamic>> rawQuery(String sql) {
      final rawDb = raw_sqlite.sqlite3.open(sqlitePath);
      try {
        final result = rawDb.select(sql);
        return result.map((row) {
          final map = <String, dynamic>{};
          for (final col in row.keys) {
            map[col] = row[col];
          }
          return map;
        }).toList();
      } finally {
        rawDb.close();
      }
    }

    test(
      'attachments are cleaned up when document is tombstoned via remove()',
      () async {
        // 1. Create a document
        final doc = TestDocumentOne(id: 'doc-with-att', name: 'Test Doc');
        final putResult = await db.put(doc) as TestDocumentOne;

        // 2. Add an attachment
        final attachmentData = Uint8List.fromList(
          utf8.encode('Hello, this is test attachment data!'),
        );
        final revAfterAttachment = await db.saveAttachment(
          putResult.id!,
          putResult.rev!,
          'test-file.txt',
          attachmentData,
          contentType: 'text/plain',
        );

        // 3. Verify attachment exists in raw database
        var attachmentRows = rawQuery(
          "SELECT * FROM local_attachments WHERE name = 'test-file.txt'",
        );
        expect(
          attachmentRows.length,
          equals(1),
          reason: 'Attachment row should exist before deletion',
        );

        final attachmentId = attachmentRows.first['id'];
        expect(
          File('${serverDir.path}/att/$attachmentId').existsSync(),
          isTrue,
          reason: 'Attachment file should exist before deletion',
        );

        // 4. Verify document blob exists
        var docBlobRows = rawQuery(
          "SELECT * FROM document_blobs db "
          "INNER JOIN local_documents ld ON db.document_id = ld.id "
          "WHERE ld.docid = 'doc-with-att'",
        );
        expect(
          docBlobRows.length,
          equals(1),
          reason: 'Document blob should exist before deletion',
        );

        // 5. Delete (tombstone) the document
        await db.remove('doc-with-att', revAfterAttachment);

        // 6. Verify attachments are cleaned up
        attachmentRows = rawQuery(
          "SELECT * FROM local_attachments WHERE name = 'test-file.txt'",
        );
        expect(
          attachmentRows.length,
          equals(0),
          reason:
              'Attachment row should be deleted after tombstoning the document',
        );

        // 7. Verify attachment file is cleaned up
        expect(
          File('${serverDir.path}/att/$attachmentId').existsSync(),
          isFalse,
          reason:
              'Attachment file should be deleted after tombstoning the document',
        );

        // 8. Verify document blob is cleaned up
        docBlobRows = rawQuery(
          "SELECT * FROM document_blobs db "
          "INNER JOIN local_documents ld ON db.document_id = ld.id "
          "WHERE ld.docid = 'doc-with-att'",
        );
        expect(
          docBlobRows.length,
          equals(0),
          reason:
              'Document blob should be deleted after tombstoning the document',
        );

        // 9. Verify the document row still exists as tombstone
        var docRows = rawQuery(
          "SELECT * FROM local_documents WHERE docid = 'doc-with-att'",
        );
        expect(
          docRows.length,
          equals(1),
          reason: 'Document row should still exist as tombstone',
        );
        expect(
          docRows.first['deleted'],
          equals(1),
          reason: 'Document should be marked as deleted',
        );
      },
    );

    test(
      'multiple attachments and their files are all cleaned up on tombstone',
      () async {
        // 1. Create a document
        final doc = TestDocumentOne(id: 'doc-multi-att', name: 'Multi Att Doc');
        final putResult = await db.put(doc) as TestDocumentOne;

        // 2. Add multiple attachments
        final rev1 = await db.saveAttachment(
          putResult.id!,
          putResult.rev!,
          'file1.txt',
          Uint8List.fromList(utf8.encode('Content of file 1')),
          contentType: 'text/plain',
        );
        final rev2 = await db.saveAttachment(
          putResult.id!,
          rev1,
          'file2.bin',
          Uint8List.fromList([0, 1, 2, 3, 4, 5]),
          contentType: 'application/octet-stream',
        );
        final rev3 = await db.saveAttachment(
          putResult.id!,
          rev2,
          'file3.json',
          Uint8List.fromList(utf8.encode('{"key": "value"}')),
          contentType: 'application/json',
        );

        // 3. Verify all attachments exist
        var attachmentRows = rawQuery(
          "SELECT * FROM local_attachments la "
          "INNER JOIN local_documents ld ON la.fkdocument = ld.id "
          "WHERE ld.docid = 'doc-multi-att'",
        );
        expect(
          attachmentRows.length,
          equals(3),
          reason: 'All 3 attachments should exist before deletion',
        );

        var attFileCount = Directory('${serverDir.path}/att')
            .listSync()
            .whereType<File>()
            .where((f) => !f.path.endsWith('.tmp'))
            .length;
        expect(
          attFileCount,
          equals(3),
          reason: 'All 3 attachment files should exist before deletion',
        );

        // 4. Delete the document
        await db.remove('doc-multi-att', rev3);

        // 5. Verify all attachments are cleaned up
        attachmentRows = rawQuery(
          "SELECT * FROM local_attachments la "
          "INNER JOIN local_documents ld ON la.fkdocument = ld.id "
          "WHERE ld.docid = 'doc-multi-att'",
        );
        expect(
          attachmentRows.length,
          equals(0),
          reason: 'All attachments should be deleted after tombstoning',
        );

        // 6. Verify no attachment files remain
        attFileCount = Directory('${serverDir.path}/att')
            .listSync()
            .whereType<File>()
            .where((f) => !f.path.endsWith('.tmp'))
            .length;
        expect(
          attFileCount,
          equals(0),
          reason: 'No attachment files should remain',
        );
      },
    );

    test(
      'document blob is cleaned up when deleted via bulkDocs (newEdits=true)',
      () async {
        // 1. Create a document with some body data
        final doc = TestDocumentOne(
          id: 'bulk-del-doc',
          name: 'Bulk Delete Test',
        );
        final putResult = await db.put(doc) as TestDocumentOne;

        // 2. Verify document blob has body data
        var docBlobRows = rawQuery(
          "SELECT db.data FROM document_blobs db "
          "INNER JOIN local_documents ld ON db.document_id = ld.id "
          "WHERE ld.docid = 'bulk-del-doc'",
        );
        expect(docBlobRows.length, equals(1));
        final blobData = jsonDecode(docBlobRows.first['data'] as String);
        expect(blobData['name'], equals('Bulk Delete Test'));

        // 3. Delete via bulkDocs with newEdits=true
        final deleteDoc = jsonEncode({
          '_id': 'bulk-del-doc',
          '_rev': putResult.rev,
          '_deleted': true,
        });
        await db.bulkDocsRaw([deleteDoc], newEdits: true);

        // 4. Verify document blob is cleaned up
        docBlobRows = rawQuery(
          "SELECT * FROM document_blobs db "
          "INNER JOIN local_documents ld ON db.document_id = ld.id "
          "WHERE ld.docid = 'bulk-del-doc'",
        );
        expect(
          docBlobRows.length,
          equals(0),
          reason:
              'Document blob should be deleted after tombstoning via bulkDocs',
        );

        // 5. Verify tombstone row exists
        var docRows = rawQuery(
          "SELECT * FROM local_documents WHERE docid = 'bulk-del-doc'",
        );
        expect(docRows.length, equals(1));
        expect(docRows.first['deleted'], equals(1));
      },
    );

    test(
      'document blob is cleaned up when deleted via bulkDocs (newEdits=false, replication)',
      () async {
        // 1. Create a document
        final doc = TestDocumentOne(
          id: 'repl-del-doc',
          name: 'Replication Delete Test',
        );
        await db.put(doc);

        // 2. Add an attachment
        final getResult = await db.get('repl-del-doc');
        await db.saveAttachment(
          getResult!.id!,
          getResult.rev!,
          'attachment.txt',
          Uint8List.fromList(utf8.encode('attachment content')),
          contentType: 'text/plain',
        );

        // 3. Verify blob and attachment exist
        var docBlobRows = rawQuery(
          "SELECT * FROM document_blobs db "
          "INNER JOIN local_documents ld ON db.document_id = ld.id "
          "WHERE ld.docid = 'repl-del-doc'",
        );
        expect(docBlobRows.length, equals(1));

        var attachmentRows = rawQuery(
          "SELECT * FROM local_attachments la "
          "INNER JOIN local_documents ld ON la.fkdocument = ld.id "
          "WHERE ld.docid = 'repl-del-doc'",
        );
        expect(attachmentRows.length, equals(1));

        // 4. Simulate replication of a tombstone with higher version (newEdits=false)
        final deleteDoc = jsonEncode({
          '_id': 'repl-del-doc',
          '_rev': '99-replicated_tombstone_hash',
          '_deleted': true,
        });
        await db.bulkDocsRaw([deleteDoc], newEdits: false);

        // 5. Verify document blob is cleaned up
        docBlobRows = rawQuery(
          "SELECT * FROM document_blobs db "
          "INNER JOIN local_documents ld ON db.document_id = ld.id "
          "WHERE ld.docid = 'repl-del-doc'",
        );
        expect(
          docBlobRows.length,
          equals(0),
          reason: 'Document blob should be deleted after replication tombstone',
        );

        // 6. Verify attachments are cleaned up
        attachmentRows = rawQuery(
          "SELECT * FROM local_attachments la "
          "INNER JOIN local_documents ld ON la.fkdocument = ld.id "
          "WHERE ld.docid = 'repl-del-doc'",
        );
        expect(
          attachmentRows.length,
          equals(0),
          reason: 'Attachments should be deleted after replication tombstone',
        );

        // 7. Verify tombstone exists
        var docRows = rawQuery(
          "SELECT * FROM local_documents WHERE docid = 'repl-del-doc'",
        );
        expect(docRows.length, equals(1));
        expect(docRows.first['deleted'], equals(1));
        expect(docRows.first['rev'], equals('99-replicated_tombstone_hash'));
      },
    );

    test(
      'tombstoned document can still be read with correct metadata via API',
      () async {
        // 1. Create and delete a document
        final doc = TestDocumentOne(id: 'api-test-doc', name: 'API Test');
        final putResult = await db.put(doc) as TestDocumentOne;
        await db.remove('api-test-doc', putResult.rev!);

        // 2. Normal get should return null (document is deleted)
        final normalGet = await db.get('api-test-doc');
        expect(normalGet, isNull);

        // 3. The changes feed should still report the deletion
        final changes = await db.changes(feedmode: FeedMode.normal).first;
        final deletedEntry = changes.normal!.results.firstWhere(
          (r) => r.id == 'api-test-doc',
        );
        expect(deletedEntry.deleted, isTrue);

        // 4. Verify revision history is intact
        var revHistoryRows = rawQuery(
          "SELECT rh.id, rh.fkdocument, rh.rev, rh.version AS rh_version, "
          "rh.seq, rh.deleted AS rh_deleted "
          "FROM revision_histories rh "
          "INNER JOIN local_documents ld ON rh.fkdocument = ld.id "
          "WHERE ld.docid = 'api-test-doc' "
          "ORDER BY rh.version ASC",
        );
        expect(
          revHistoryRows.length,
          equals(2),
          reason: 'Should have 2 revision entries (create + delete)',
        );
        expect(revHistoryRows.first['rh_version'], equals(1));
        expect(
          revHistoryRows.last['rh_deleted'],
          equals(1),
          reason: 'Last revision should be marked as deleted',
        );
      },
    );

    test(
      'no orphaned data remains in database after multiple create-delete cycles',
      () async {
        // 1. Create a document with attachment, delete it, repeat
        for (int i = 0; i < 3; i++) {
          final docId = 'cycle-doc';

          final doc = TestDocumentOne(id: docId, name: 'Cycle $i');
          final putResult = await db.put(doc) as TestDocumentOne;

          final rev = await db.saveAttachment(
            putResult.id!,
            putResult.rev!,
            'cycle-attachment.txt',
            Uint8List.fromList(utf8.encode('Cycle $i data')),
            contentType: 'text/plain',
          );

          await db.remove(docId, rev);
        }

        // 2. Verify no attachments remain
        var attachmentRows = rawQuery(
          "SELECT * FROM local_attachments la "
          "INNER JOIN local_documents ld ON la.fkdocument = ld.id "
          "WHERE ld.docid = 'cycle-doc'",
        );
        expect(
          attachmentRows.length,
          equals(0),
          reason: 'No attachments should remain after create-delete cycles',
        );

        // 3. Verify no attachment files remain
        final attFileCount = Directory('${serverDir.path}/att')
            .listSync()
            .whereType<File>()
            .where((f) => !f.path.endsWith('.tmp'))
            .length;
        expect(
          attFileCount,
          equals(0),
          reason: 'No attachment files should remain',
        );

        // 4. Verify no document blob remains for the tombstoned doc
        var docBlobRows = rawQuery(
          "SELECT * FROM document_blobs db "
          "INNER JOIN local_documents ld ON db.document_id = ld.id "
          "WHERE ld.docid = 'cycle-doc'",
        );
        expect(
          docBlobRows.length,
          equals(0),
          reason: 'No document blob should remain for tombstoned document',
        );
      },
    );
  });
}
