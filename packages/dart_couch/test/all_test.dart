import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:dart_couch/dart_couch.dart';
import 'dart:convert';
import 'package:logging/logging.dart';

import 'helper/bulk_docs_test_helper.dart';
import 'helper/helper.dart';
import 'helper/test_document_one.dart';
import 'helper/changes_test_helper.dart';

void main() {
  DartCouchDb.ensureInitialized();

  Logger.root.level = Level.FINEST; // defaults to Level.INFO
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
  Future<void> Function()? tearDown,
) {
  late DartCouchServer cl;

  setUpAll(() async {
    cl = await setupAll();
  });
  tearDownAll(() async {
    if (tearDown != null) await tearDown();
  });

  test('create/delete database', () async {
    final databases = (await cl.allDatabases).where(
      (e) => e.dbname.startsWith("_") == false,
    );
    expect(databases, isEmpty);

    await cl.createDatabase("testdb1");

    Iterable<DartCouchDb> databasesAfter = (await cl.allDatabases).where(
      (e) => e.dbname.startsWith("_") == false,
    );
    expect(databasesAfter.length, 1);
    expect(databasesAfter.first.dbname, 'testdb1');

    await cl.deleteDatabase("testdb1");
    databasesAfter = (await cl.allDatabases).where(
      (e) => e.dbname.startsWith("_") == false,
    );
    expect(databasesAfter, isEmpty);
  });

  test('check correct calculation of rev', () async {
    final dbName = 'testdb1';
    final db = await cl.createDatabase(dbName);

    CouchDocumentBase d = CouchDocumentBase(
      id: "testdoc",
      unmappedProps: {
        'z': 1,
        'a': 8823176421893746,
        'f': '3',
        'b': {'y': 10000000, 'b': '2', 'g': '3'},
      },
    );
    //print(d.toJson());

    CouchDocumentBase rev1 = await db.put(d);
    expect(rev1.attachments, isNull);
    expect(rev1.deleted, isFalse);
    expect(rev1.id, equals("testdoc"));
    expect(rev1.revisions, isNull);
    expect(rev1.revsInfo, isNull);
    expect(rev1.unmappedProps, hasLength(4));
    expect(rev1.rev, equals("1-604affef1c7bbac5cf806fbad1331a93"));

    // also check if the attachments order is relevant
    expect(
      await db.saveAttachment(d.id!, rev1.rev!, "g", attachmentData),
      equals("2-7a0271a9e5ff056b2a84ecd2c7ce96d4"),
    );

    CouchDocumentBase rev2 = (await db.get("testdoc"))!;
    expect(rev2.rev, equals("2-7a0271a9e5ff056b2a84ecd2c7ce96d4"));

    expect(
      await db.saveAttachment(rev2.id!, rev2.rev!, "a", attachmentData),
      equals("3-fd277fe3c890419e49c8cf205c79916f"),
    );

    CouchDocumentBase rev3 = (await db.get("testdoc"))!;
    expect(rev3.rev, equals("3-fd277fe3c890419e49c8cf205c79916f"));

    expect(
      await db.saveAttachment(rev3.id!, rev3.rev!, "z", attachmentData),
      equals("4-817293dd3c85a9fa488afd088723394f"),
    );

    CouchDocumentBase rev4 = (await db.get("testdoc"))!;
    expect(rev4.rev, equals("4-817293dd3c85a9fa488afd088723394f"));

    // delete attachment from mid and check rev
    await db.deleteAttachment(rev4.id!, rev4.rev!, "a");
    CouchDocumentBase rev4a = (await db.get("testdoc"))!;
    expect(rev4a.rev, equals("5-9137d198dd751a71ffd5ba2789738ce5"));

    // recreate deleted attachment and check rev
    await db.saveAttachment(rev4a.id!, rev4a.rev!, "a", attachmentData);
    CouchDocumentBase rev4b = (await db.get("testdoc"))!;
    expect(rev4b.rev, equals("6-6e7f45aad9231d1efdafaf0fd0002827"));

    // delete doc and check rev and then recreate doc and check rev
    // rev should be 7... then!
    String rev5 = await db.remove(rev4b.id!, rev4b.rev!);
    expect(rev5, equals("7-312b4b9f95a3919ddae435be72938e04"));

    CouchDocumentBase? f = (await db.get("testdoc", rev: rev5));
    expect(f, isNotNull);

    CouchDocumentBase rev6 = await db.put(d);
    expect(rev6.rev, equals("8-340093478a323bb35a18a5ad314e6ffa"));

    await cl.deleteDatabase(dbName);
  });

  test('create document with double id', () async {
    final dbName = 'testdb1';
    await cl.createDatabase(dbName);

    final db = await cl.db(dbName);
    expect(db, isNotNull);

    final String docId = "testdoc1";
    TestDocumentOne doc = TestDocumentOne(name: 'Test Document', id: docId);

    final rev1 = (await db!.put(doc)) as TestDocumentOne;
    expect(rev1.rev, isNotNull);
    expect(rev1.id, docId);
    expect(rev1.name, 'Test Document');

    // Try to create the same document again
    try {
      await db.put(doc);
      fail('Expected an exception due to revision conflict');
    } catch (e) {
      expect(e, isA<CouchDbException>());
      expect((e as CouchDbException).statusCode, CouchDbStatusCodes.conflict);
    }

    // Update the document with the correct revision
    final updatedDocContent = rev1.copyWith(name: 'Updated Document');
    final rev2 = (await db.put(updatedDocContent)) as TestDocumentOne;
    expect(rev2.rev, isNotNull);
    expect(rev2.id, docId);
    expect(rev2.name, 'Updated Document');

    final stayAliveDoc = TestDocumentOne(name: 'Staying Alive', id: 'doc2');
    await db.put(stayAliveDoc) as TestDocumentOne;

    await db.remove(rev2.id!, rev2.rev!);

    // Verify the document is deleted
    await expectLater(db.get(docId), completion(isNull));
    await expectLater(db.get('doc2'), completion(isNotNull));
    expect(
      ((await db.get('doc2')) as TestDocumentOne).name,
      equals('Staying Alive'),
    );

    // Clean up
    await cl.deleteDatabase(dbName);

    final databases = (await cl.allDatabases).where(
      (e) => e.dbname.startsWith("_") == false,
    );
    expect(databases, isEmpty);
  });

  test('api test openrevs', () async {
    final dbName = 'testdb1';
    final db = await cl.createDatabase(dbName);

    final documentRevisions = await createThreeRevisions(db, "testdoc1");

    // one Document returned, with version 3
    // no revisions, no revsInfo
    List<OpenRevsResult> openRevs1 = (await db.getOpenRevs("testdoc1"))!;
    expect(openRevs1, hasLength(1));
    expect(openRevs1[0].state, equals(OpenRevsState.ok));
    expect(openRevs1[0].doc!, isA<TestDocumentOne>());
    expect(openRevs1[0].doc!.revisions, null);
    expect(openRevs1[0].doc!.revsInfo, null);
    expect(openRevs1[0].doc!.getVersionFromRev(), 3);

    // one Document returned, with version 3
    // revisions will be shown, no revsInfo
    List<OpenRevsResult> openRevs2 = (await db.getOpenRevs(
      "testdoc1",
      revs: true,
    ))!;
    expect(openRevs2, hasLength(1));
    expect(openRevs2[0].state, equals(OpenRevsState.ok));
    expect(openRevs2[0].doc!, isA<TestDocumentOne>());
    expect(openRevs2[0].doc!.revsInfo, null);
    expect(openRevs2[0].doc!.getVersionFromRev(), 3);
    expect(openRevs2[0].doc!.revisions!.ids, hasLength(3));
    expect(openRevs2[0].doc!.revisions!.start, 3);

    await db.remove("testdoc1", documentRevisions[0].rev!);
    // one Document returned, with version 3
    // revisions will be shown, no revsInfo
    await doCompaction(db);
    List<OpenRevsResult> openRevs3 = (await db.getOpenRevs(
      "testdoc1",
      revs: true,
    ))!;
    expect(openRevs3, hasLength(1));
    expect(openRevs3[0].state, equals(OpenRevsState.ok));
    expect(openRevs3[0].doc! is TestDocumentOne, false);
    expect(openRevs3[0].doc!, isA<CouchDocumentBase>());
    expect(openRevs3[0].doc!.revsInfo, null);
    expect(openRevs3[0].doc!.getVersionFromRev(), 4);
    expect(openRevs3[0].doc!.deleted, true);
    expect(openRevs3[0].doc!.revisions!.ids, hasLength(4));
    expect(openRevs3[0].doc!.revisions!.start, 4);
    for (int i = 0; i < openRevs3[0].doc!.revisions!.ids.length; ++i) {
      final CouchDocumentBase? doc = (await db.get(
        "testdoc1",
        rev: openRevs3[0].doc!.revisions!.getRev(i),
      ));
      if (i == 0) {
        expect(doc, isNotNull);
        expect(doc!.deleted, isTrue);
        expect(doc is TestDocumentOne, false);
        expect(doc, isA<CouchDocumentBase>());
      } else {
        expect(doc, isNull);
      }
    }

    final documentRevisions2 = await createThreeRevisions(db, "testdoc1");

    List<OpenRevsResult> openRevs4 = (await db.getOpenRevs(
      "testdoc1",
      revs: true,
    ))!;
    expect(openRevs4, hasLength(1));
    expect(openRevs4[0].state, equals(OpenRevsState.ok));
    expect(openRevs4[0].doc, isA<TestDocumentOne>());
    expect(openRevs4[0].doc!.revsInfo, null);
    expect(openRevs4[0].doc!.getVersionFromRev(), 7);
    expect(openRevs4[0].doc!.revisions!.ids, hasLength(7));
    expect(openRevs4[0].doc!.revisions!.start, 7);

    await db.remove("testdoc1", documentRevisions2[0].rev!);
    // one Document returned, with version 3
    // revisions will be shown, no revsInfo

    await doCompaction(db);

    List<OpenRevsResult> openRevs5 = (await db.getOpenRevs(
      "testdoc1",
      revs: true,
    ))!;
    expect(openRevs5, hasLength(1));
    expect(openRevs5[0].doc is TestDocumentOne, false);
    expect(openRevs5[0].doc, isA<CouchDocumentBase>());
    expect(openRevs5[0].doc!.revsInfo, null);
    expect(openRevs5[0].doc!.getVersionFromRev(), 8);
    expect(openRevs5[0].doc!.deleted, true);
    expect(openRevs5[0].doc!.revisions!.ids, hasLength(8));
    expect(openRevs5[0].doc!.revisions!.start, 8);
    for (int i = 0; i < openRevs5[0].doc!.revisions!.ids.length; ++i) {
      final CouchDocumentBase? doc = (await db.get(
        "testdoc1",
        rev: openRevs5[0].doc!.revisions!.getRev(i),
        revs: true,
      ));
      if (i == 0) {
        expect(doc, isNotNull);
        expect(doc!.revisions!.ids, hasLength(8 - i));
        expect(doc.revisions!.start, 8 - i);
        expect(doc.deleted, isTrue);
        expect(doc is TestDocumentOne, false);
        expect(doc, isA<CouchDocumentBase>());
      } else {
        expect(doc, isNull);
      }
    }

    await cl.deleteDatabase(dbName);
  });

  test('api-test save and delete and get documents', () async {
    final dbName = 'testdb1';
    final db = await cl.createDatabase(dbName);

    final documentRevisions = await createRevisions(db, "testdoc", 5);

    final TestDocumentOne testRev =
        await db.get("testdoc", revsInfo: true, revs: true) as TestDocumentOne;
    expect(testRev.revsInfo!.length, 5);
    expect(testRev.revisions!.ids.length, 5);
    int c = 5;
    for (int i = 0; i < 5; ++i) {
      expect(documentRevisions[i].rev, equals(testRev.revsInfo![i].rev));
      expect(
        documentRevisions[i].rev,
        equals("${c--}-${testRev.revisions!.ids[i]}"),
      );
    }

    for (int i = 0; i < testRev.revisions!.ids.length; ++i) {
      String curRev = testRev.revisions!.getRev(i);
      final d = await db.get("testdoc", rev: curRev);
      if (i == 0) {
        expect(d, isNotNull);
        expect(d, isA<TestDocumentOne>());
        expect(d!.deleted != true, isTrue);
      } else {
        expect(d, isNull);
      }
    }

    List<OpenRevsResult> openRevsTest = (await db.getOpenRevs(
      "testdoc",
      revs: true,
    ))!;
    expect(openRevsTest, isNotNull);
    expect(openRevsTest[0].state, equals(OpenRevsState.ok));
    expect(openRevsTest[0].doc, isA<TestDocumentOne>());
    expect(openRevsTest[0].doc!.rev, equals(documentRevisions[0].rev));
    {
      List<OpenRevsResult> openRevsTest2 = (await db.getOpenRevs(
        "testdoc",
        revisions: [
          documentRevisions[1].rev!,
          documentRevisions[0].rev!,
          documentRevisions[2].rev!,
        ],
        revs: true,
      ))!;
      expect(openRevsTest2, isNotNull);
      expect(openRevsTest2, hasLength(3));
      expect(openRevsTest2[0].state, equals(OpenRevsState.ok));
      expect(openRevsTest2[0].doc, isNotNull);
      expect(
        (openRevsTest2[0].doc as TestDocumentOne).copyWith(revisions: null),
        equals(documentRevisions[0]),
      );
      expect(openRevsTest2[0].doc!.revisions!.ids, hasLength(5));
      expect(openRevsTest2[0].doc!.revisions!.start, equals(5));
      expect(
        openRevsTest2[0].doc!.revisions!.getRev(0),
        equals(documentRevisions[0].rev),
      );
      expect(
        openRevsTest2[0].doc!.revisions!.getRev(1),
        equals(documentRevisions[1].rev),
      );
      expect(
        openRevsTest2[0].doc!.revisions!.getRev(2),
        equals(documentRevisions[2].rev),
      );
      expect(openRevsTest2[1].state, equals(OpenRevsState.missing));
      expect(openRevsTest2[1].doc, isNull);
      expect(openRevsTest2[1].missingRev, equals(documentRevisions[2].rev));
      expect(openRevsTest2[2].state, equals(OpenRevsState.missing));
      expect(openRevsTest2[2].doc, isNull);
      expect(openRevsTest2[2].missingRev, equals(documentRevisions[1].rev));
    }
    {
      List<OpenRevsResult> openRevsTest2b = (await db.getOpenRevs(
        "testdoc",
        revisions: [
          documentRevisions[1].rev!,
          documentRevisions[3].rev!,
          documentRevisions[2].rev!,
        ],
        revs: true,
      ))!;
      expect(openRevsTest2b, isNotNull);
      expect(openRevsTest2b, hasLength(3));
      expect(openRevsTest2b[2].state, equals(OpenRevsState.missing));
      expect(openRevsTest2b[2].doc, isNull);
      expect(openRevsTest2b[2].missingRev, equals(documentRevisions[1].rev));
      expect(openRevsTest2b[1].state, equals(OpenRevsState.missing));
      expect(openRevsTest2b[1].doc, isNull);
      expect(openRevsTest2b[1].missingRev, equals(documentRevisions[2].rev));
      expect(openRevsTest2b[0].state, equals(OpenRevsState.missing));
      expect(openRevsTest2b[0].doc, isNull);
      expect(openRevsTest2b[0].missingRev, equals(documentRevisions[3].rev));
    }
    final String deletedRev = await db.remove("testdoc", testRev.rev!);

    await doCompaction(db);

    final CouchDocumentBase? testRev2 = await db.get("testdoc");
    expect(testRev2, isNull);

    final CouchDocumentBase? testRev3 = await db.get("testdoc", revs: true);
    expect(testRev3, isNull);

    final CouchDocumentBase? testRev4 = await db.get(
      "testdoc",
      revs: true,
      revsInfo: true,
    );
    expect(testRev4, isNull);

    final List<OpenRevsResult> testRev5 = (await db.getOpenRevs(
      "testdoc",
      revs: true,
    ))!;
    expect(testRev5, isNotNull);
    expect(testRev5, hasLength(1));
    expect(testRev5[0].doc!.revisions!.ids, hasLength(6));

    c = 0;
    for (int i = 0; i < testRev5[0].doc!.revisions!.ids.length; ++i) {
      String curRev = testRev5[0].doc!.revisions!.getRev(i);
      final d = await db.get("testdoc", rev: curRev);
      if (i == 0) {
        expect(d is TestDocumentOne, false);
        expect(d, isA<CouchDocumentBase>());
        expect(d!.deleted, isTrue);
        expect(d.rev, equals(deletedRev));
      } else {
        expect(d, isNull);
        expect(curRev, equals(documentRevisions[i - 1].rev));
      }
    }

    final testRev6 = (await db.getOpenRevs("testdoc", revs: true))!;
    expect(testRev6, isNotNull);
    expect(testRev6, hasLength(1));
    expect(testRev6[0].state, equals(OpenRevsState.ok));
    expect(testRev6[0].doc!, isA<CouchDocumentBase>());
    expect(testRev6[0].doc! is TestDocumentOne, false);
    expect(testRev6[0].doc!.revisions, isNotNull);
    expect(testRev6[0].doc!.revisions!.ids, hasLength(6));
    expect(testRev6[0].doc!.revsInfo, isNull);

    // openRevs sucht die letzte Revision raus, egal, was bei rev eingetragen wird.
    final testRev7 = (await db.getOpenRevs("testdoc", revs: true))!;
    expect(testRev7, hasLength(1));
    expect(testRev6[0].state, equals(OpenRevsState.ok));
    expect(testRev7[0].doc!, isA<CouchDocumentBase>());
    expect(testRev6[0].doc! is TestDocumentOne, false);
    expect(testRev7[0].doc!.deleted, isTrue);
    expect(testRev7[0].doc!.rev, equals(testRev5[0].doc!.revisions!.getRev(0)));
    expect(testRev7[0].doc!.revisions!.ids, hasLength(6));

    await cl.deleteDatabase(dbName);
  });

  test('revisions, revs and revision infos', () async {
    final dbName = 'testdb1';
    final db = await cl.createDatabase(dbName);

    final revs = await createThreeRevisions(db, "testdoc");

    final TestDocumentOne res =
        await db.get("testdoc", revsInfo: true, revs: true) as TestDocumentOne;
    expect(res.revsInfo!.length, 3);
    expect(res.revisions!.ids.length, 3);
    int c = 3;
    for (int i = 0; i < 3; ++i) {
      expect(revs[i].rev, equals(res.revsInfo![i].rev));
      expect(revs[i].rev, equals("${c--}-${res.revisions!.ids[i]}"));
    }

    await db.remove(revs[0].id!, revs[0].rev!);

    await doCompaction(db);

    List<OpenRevsResult> openrevs1 = (await db.getOpenRevs(
      "testdoc",
      revs: true,
    ))!;
    expect(openrevs1, hasLength(1));
    expect(openrevs1[0].state, equals(OpenRevsState.ok));
    expect(openrevs1[0].doc!.deleted, isTrue);
    expect(openrevs1[0].doc!.revisions!.ids.length, equals(4));

    for (int i = 0; i < openrevs1[0].doc!.revisions!.ids.length; ++i) {
      final r = (await db.get(
        "testdoc",
        rev: openrevs1[0].doc!.revisions!.getRev(i),
      ));

      if (i == 0) {
        expect(r, isNotNull);
        expect(r!.deleted, isTrue);
        expect(r.id, equals("testdoc"));
        expect(r.rev, startsWith(openrevs1[0].doc!.revisions!.getRev(0)));
      } else {
        expect(r, isNull);
      }

      /*if (i % 4 == 0) {
        expect(r.deleted, isTrue);
        expect(r.id, equals("testdoc"));
        expect(
          r.rev,
          startsWith("${openrevs1[0].doc!.revisions!.start - i % 4}"),
        );
      } else {
        expect(r.deleted, isFalse);
        expect(r, equals(revs[i % 4 - 1]));
      }*/
    }

    final revs2 = await createThreeRevisions(db, "testdoc");
    List<OpenRevsResult> openrevs2 = (await db.getOpenRevs(
      "testdoc",
      revs: true,
    ))!;
    expect(openrevs2, hasLength(1));
    expect(openrevs2[0].state, equals(OpenRevsState.ok));
    expect(openrevs2[0].doc!, isA<TestDocumentOne>());
    expect(openrevs2[0].doc!.revisions!.ids, hasLength(7));

    await db.remove(revs2[0].id!, revs2[0].rev!);

    await doCompaction(db);

    List<OpenRevsResult> openrevs3 = (await db.getOpenRevs(
      "testdoc",
      revs: true,
    ))!;
    expect(openrevs3, hasLength(1));
    expect(openrevs3[0].state, equals(OpenRevsState.ok));
    expect(openrevs3[0].doc!, isA<CouchDocumentBase>());
    expect(openrevs3[0].doc! is TestDocumentOne, false);
    expect(openrevs3[0].doc!.revisions!.ids, hasLength(8));

    await cl.deleteDatabase(dbName);
  });

  test('saveAttachment', () async {
    final dbName = 'testdb1';
    final db = await cl.createDatabase(dbName);

    TestDocumentOne doc1 = TestDocumentOne(
      id: 'doc1',
      name: 'Test Document One',
    );

    doc1 = await db.put(doc1) as TestDocumentOne;

    await db.saveAttachment(
      doc1.id!,
      doc1.rev!,
      "test_attachment.bin",
      attachmentData,
    );

    TestDocumentOne saved = await db.get(doc1.id!) as TestDocumentOne;
    final loadedDoc = await db.get(doc1.id!) as TestDocumentOne;
    expect(loadedDoc, isNotNull);
    expect(loadedDoc.id, doc1.id);
    expect(loadedDoc.name, doc1.name);
    expect(loadedDoc.attachments, isNotNull);
    expect(loadedDoc.attachments!.length, 1);
    expect(loadedDoc.attachments!['test_attachment.bin'], isNotNull);
    expect(
      loadedDoc.attachments!['test_attachment.bin']!,
      hasLength(attachmentData.length),
    );
    expect(
      loadedDoc.attachments!['test_attachment.bin']!.digestDecoded,
      md5.convert(attachmentData).toString(),
    );
    expect(
      loadedDoc.attachments!['test_attachment.bin']!.contentType,
      "application/octet-stream",
    );
    expect(saved.rev, loadedDoc.rev);

    Uint8List loadedAttachmentData = (await db.getAttachment(
      doc1.id!,
      "test_attachment.bin",
    ))!;
    expect(loadedAttachmentData, isNotNull);
    expect(loadedAttachmentData, hasLength(attachmentData.length));
    expect(loadedAttachmentData, equals(attachmentData));

    await db.deleteAttachment(
      doc1.id!,
      saved.rev!,
      loadedDoc.attachments!.keys.first,
    );

    saved = await db.get(doc1.id!) as TestDocumentOne;
    expect(saved.attachments, isNull);
    await cl.deleteDatabase(dbName);
  });

  test('put rejects document fields starting with underscore', () async {
    final dbName = 'testdb1';
    final db = await cl.createDatabase(dbName);

    await expectLater(
      () => db.putRaw({'_id': 'testdoc', '_badfield': 'value'}),
      throwsA(
        isA<CouchDbException>().having(
          (e) => e.statusCode,
          'statusCode',
          CouchDbStatusCodes.badRequest,
        ),
      ),
    );

    await cl.deleteDatabase(dbName);
  });

  test('saveAttachment rejects names starting with underscore', () async {
    final dbName = 'testdb1';
    final db = await cl.createDatabase(dbName);

    final doc = await db.put(TestDocumentOne(id: 'doc1', name: 'Test'));

    await expectLater(
      () => db.saveAttachment(doc.id!, doc.rev!, '_hidden.bin', attachmentData),
      throwsA(
        isA<CouchDbException>().having(
          (e) => e.statusCode,
          'statusCode',
          CouchDbStatusCodes.badRequest,
        ),
      ),
    );

    await cl.deleteDatabase(dbName);
  });

  test('overwrite attachment with new data', () async {
    final dbName = 'testdb1';
    final db = await cl.createDatabase(dbName);

    final doc = await db.put(TestDocumentOne(id: 'doc1', name: 'Test'));

    final originalData = Uint8List.fromList(utf8.encode('original content'));
    final newData = Uint8List.fromList(utf8.encode('overwritten content'));

    // Save original attachment.
    // Use application/octet-stream to avoid CouchDB's automatic gzip compression
    // of text/* types, which would cause digestDecoded to reflect the compressed
    // bytes rather than the original content.
    final rev2 = await db.saveAttachment(
      doc.id!,
      doc.rev!,
      'overwrite.txt',
      originalData,
      contentType: 'application/octet-stream',
    );

    // Overwrite with new data using same name
    await db.saveAttachment(
      doc.id!,
      rev2,
      'overwrite.txt',
      newData,
      contentType: 'application/octet-stream',
    );

    // Verify new data is returned
    final loaded = await db.getAttachment(doc.id!, 'overwrite.txt');
    expect(loaded, isNotNull);
    expect(loaded, equals(newData));

    // Verify metadata reflects new size and digest
    final loadedDoc = await db.get(doc.id!);
    expect(loadedDoc, isNotNull);
    expect(loadedDoc!.attachments, isNotNull);
    expect(
      loadedDoc.attachments!['overwrite.txt']!.digestDecoded,
      equals(md5.convert(newData).toString()),
    );
    expect(loadedDoc.attachments!['overwrite.txt']!, hasLength(newData.length));

    await cl.deleteDatabase(dbName);
  });

  test('delete attachment', () async {
    final dbName = 'testdb1';
    final db = await cl.createDatabase(dbName);

    final attData1 = utf8.encode("Eins");
    final attData2 = utf8.encode("Zwei");
    final attData3 = utf8.encode("Drei");

    // 1. Document mit Attachment erzeugen
    // 2. Attachment löschen
    // 3. Attachment abrufen mit und ohne Angabe der revision abrufen
    TestDocumentOne doc1 = TestDocumentOne(
      id: 'doc1',
      name: 'Test Document One',
    );

    final saved1 = await db.put(doc1) as TestDocumentOne;

    await db.saveAttachment(saved1.id!, saved1.rev!, "att.bin", attData1);

    TestDocumentOne saved2 = await db.get(doc1.id!) as TestDocumentOne;

    await db.deleteAttachment(saved2.id!, saved2.rev!, "att.bin");

    TestDocumentOne saved3 = await db.get(doc1.id!) as TestDocumentOne;

    await db.saveAttachment(saved3.id!, saved3.rev!, "att.bin", attData2);

    TestDocumentOne saved4 = await db.get(doc1.id!) as TestDocumentOne;

    await db.deleteAttachment(saved4.id!, saved4.rev!, "att.bin");

    TestDocumentOne saved5 = await db.get(doc1.id!) as TestDocumentOne;

    await db.saveAttachment(saved5.id!, saved5.rev!, "att.bin", attData3);

    TestDocumentOne saved6 = await db.get(doc1.id!) as TestDocumentOne;

    await doCompaction(db);

    expect(
      await db.getAttachment(doc1.id!, "att.bin", rev: saved1.rev),
      isNull,
    );
    expect(await db.getAttachment(doc1.id!, "att.bin"), equals(attData3));

    await expectLater(
      db.getAttachment(doc1.id!, "att.bin", rev: saved1.rev),
      completion(isNull),
    );

    await expectLater(
      db.getAttachment(doc1.id!, "att.bin", rev: saved2.rev),
      completion(isNull),
    );

    await expectLater(
      db.getAttachment(doc1.id!, "att.bin", rev: saved3.rev),
      completion(isNull),
    );

    await expectLater(
      db.getAttachment(doc1.id!, "att.bin", rev: saved4.rev),
      completion(isNull),
    );

    await expectLater(
      db.getAttachment(doc1.id!, "att.bin", rev: saved5.rev),
      completion(isNull),
    );

    final att3 = await db.getAttachment(doc1.id!, "att.bin", rev: saved6.rev);
    expect(att3, equals(attData3));

    final att3b = await db.getAttachment(doc1.id!, "att.bin");
    expect(att3b, equals(attData3));

    await cl.deleteDatabase(dbName);
  });

  test('sequence numbers', () async {
    final dbName = 'testdb1';
    final db = await cl.createDatabase(dbName);

    expect((await db.info())!.updateSeqNumber, 0);

    TestDocumentOne doc1 = TestDocumentOne(
      id: 'doc1',
      name: 'Test Document One',
    );

    final saved1 = await db.put(doc1) as TestDocumentOne;

    expect((await db.info())!.updateSeqNumber, 1);

    final changes1 = await db.changes().first;
    final normal1 = changes1.normal!;
    expect(normal1.lastSeqNumber, 1);
    expect(normal1.results, hasLength(1));
    expect(normal1.results[0].id, saved1.id);
    expect(normal1.results[0].seqNumber, 1);
    expect(normal1.results[0].changes, hasLength(1));
    expect(normal1.results[0].changes[0].rev, saved1.rev);

    final saved2 =
        await db.put(saved1.copyWith(name: "Changed")) as TestDocumentOne;
    expect((await db.info())!.updateSeqNumber, 2);
    final changes2 = await db.changes().first;
    final normal2 = changes2.normal!;
    expect(normal2.lastSeqNumber, 2);
    expect(normal2.results, hasLength(1));
    expect(normal2.results[0].id, saved2.id);
    expect(normal2.results[0].seqNumber, 2);
    expect(normal2.results[0].changes, hasLength(1));
    expect(normal2.results[0].changes[0].rev, saved2.rev);

    final changes2b = await db.changes(includeDocs: true).first;
    final normal2b = changes2b.normal!;
    expect(normal2b.results[0].doc, equals(saved2));

    String deletedRev = await db.remove(saved2.id!, saved2.rev!);
    expect((await db.info())!.updateSeqNumber, 3);

    final changes3 = await db.changes().first;
    final normal3 = changes3.normal!;
    expect(normal3.lastSeqNumber, 3);
    expect(normal3.results, hasLength(1));
    expect(normal3.results[0].id, saved2.id);
    expect(normal3.results[0].seqNumber, 3);
    expect(normal3.results[0].changes, hasLength(1));
    expect(normal3.results[0].changes[0].rev, deletedRev);

    await cl.deleteDatabase(dbName);
  });

  test('view api', () async {
    final dbName = 'testdb1';
    final db = await cl.createDatabase(dbName);
    final List<CouchDocumentBase> docs = await createViewDocuments(db);
    await createView(db);
    {
      final ViewResult res = (await db.query("viewtest/view1"))!;
      expect(res.totalRows, 3);
      expect(res.offset, 0);
      expect(res.rows, hasLength(3));
      for (int i = 0; i < res.rows.length; ++i) {
        expect(res.rows[i].doc, isNull);
        expect(res.rows[i].id, equals(docs[i].id));
        expect(res.rows[i].key, equals(docs[i].unmappedProps['date']));
        expect(res.rows[i].value, equals(docs[i].unmappedProps['title']));
      }
    }
    {
      final ViewResult res = (await db.query("viewtest/view2"))!;
      expect(res.totalRows, 6);
      expect(res.offset, 0);
      expect(res.rows, hasLength(6));
      for (int i = 0; i < res.rows.length; ++i) {
        expect(res.rows[i].doc, isNull);
        expect(res.rows[i].id, equals(docs[(i / 2).floor()].id));
        expect(
          res.rows[i].key,
          equals(docs[(i / 2).floor()].unmappedProps['date']),
        );
        expect(
          res.rows[i].value,
          equals(docs[(i / 2).floor()].unmappedProps['title']),
        );
      }
    }
    {
      final ViewResult res = (await db.query(
        "viewtest/view1",
        includeDocs: true,
      ))!;
      expect(res.totalRows, 3);
      expect(res.offset, 0);
      expect(res.rows, hasLength(3));
      expect(res.rows[0].doc!.attachments, isNotNull);
      expect(res.rows[0].doc!.attachments!.length, 1);
      expect(res.rows[0].doc!.attachments!.containsKey("testatt1"), isTrue);
      expect(res.rows[0].doc!.attachments!['testatt1']!.revpos, equals(2));
      expect(res.rows[0].doc!.attachments!['testatt1']!.length, equals(100));
      expect(res.rows[0].doc!.attachments!['testatt1']!.stub, isTrue);
      expect(
        res.rows[0].doc!.attachments!['testatt1']!.contentType,
        equals("application/octet-stream"),
      );

      for (int i = 0; i < res.rows.length; ++i) {
        expect(res.rows[i].doc, isNotNull);
        expect(res.rows[i].id, equals(docs[i].id));
        expect(res.rows[i].key, equals(docs[i].unmappedProps['date']));
        expect(res.rows[i].value, equals(docs[i].unmappedProps['title']));

        expect(res.rows[i].doc, isNotNull);
        Map d = res.rows[i].doc!.toMap();
        for (int b = 0; b < d.keys.length; ++b) {
          String key = d.keys.toList()[b];
          dynamic value = d[key];

          expect(value, equals(docs[i].toMap()[key]));
        }
        if (i != 0) {
          expect(res.rows[i].doc!.attachments, isNull);
        }
      }
    }
    {
      final ViewResult res = (await db.query(
        "viewtest/view1",
        includeDocs: true,
        attachments: true,
      ))!;
      expect(res.totalRows, 3);
      expect(res.offset, 0);
      expect(res.rows, hasLength(3));
      expect(res.rows[0].doc!.attachments, isNotNull);
      expect(res.rows[0].doc!.attachments!.length, 1);
      expect(res.rows[0].doc!.attachments!.containsKey("testatt1"), isTrue);
      expect(res.rows[0].doc!.attachments!['testatt1']!.revpos, equals(2));
      expect(res.rows[0].doc!.attachments!['testatt1']!.length, isNull);
      expect(res.rows[0].doc!.attachments!['testatt1']!.stub, isNull);
      expect(
        res.rows[0].doc!.attachments!['testatt1']!.contentType,
        equals("application/octet-stream"),
      );
      expect(
        res.rows[0].doc!.attachments!['testatt1']!.contentType,
        equals("application/octet-stream"),
      );
      expect(
        res.rows[0].doc!.attachments!['testatt1']!.dataDecoded,
        equals(attachmentData),
      );
      expect(
        res.rows[0].doc!.attachments!['testatt1']!.digestDecoded,
        md5.convert(attachmentData).toString(),
      );

      for (int i = 0; i < res.rows.length; ++i) {
        expect(res.rows[i].doc, isNotNull);
        expect(res.rows[i].id, equals(docs[i].id));
        expect(res.rows[i].key, equals(docs[i].unmappedProps['date']));
        expect(res.rows[i].value, equals(docs[i].unmappedProps['title']));

        if (i != 0) {
          expect(res.rows[i].doc!.attachments, isNull);
        }

        expect(res.rows[i].doc, isNotNull);
        Map d = res.rows[i].doc!.toMap();
        for (int b = 0; b < d.keys.length; ++b) {
          String key = d.keys.toList()[b];
          dynamic value = d[key];

          if (key == "_attachments") {
            // the expected value doc was queried without attachment, so it has a length instead of a data field
            // for the test, this has to be changed
            Map<String, dynamic> expected = jsonDecode(
              jsonEncode(docs[i].toMap()[key]),
            );
            expected['testatt1'].remove('length');
            expected['testatt1'].remove('stub');
            expected['testatt1']['data'] = base64Encode(attachmentData);
            Map<String, dynamic> actual = value;
            expect(actual, equals(expected));
          } else {
            expect(value, equals(docs[i].toMap()[key]));
          }
        }
      }
    }
    await cl.deleteDatabase(dbName);
  });

  test('getAllDocs', () async {
    final dbName = 'testdb1';
    final db = await cl.createDatabase(dbName);

    final fiveDocs = await createFiveDocuments(db);

    ViewResult res = await db.allDocs();
    expect(res.offset, 0);
    expect(res.totalRows, 5);
    expect(res.rows, hasLength(5));
    for (int i = 0; i < fiveDocs.length; ++i) {
      expect(res.rows[i].id, equals(fiveDocs[i].id));
      expect(res.rows[i].key, equals(fiveDocs[i].id));
      expect(res.rows[i].doc, isNull);
      expect(res.rows[i].value["rev"], fiveDocs[i].rev);
    }

    res = await db.allDocs(includeDocs: true);
    expect(res.offset, 0);
    expect(res.totalRows, 5);
    expect(res.rows, hasLength(5));
    for (int i = 0; i < fiveDocs.length; ++i) {
      expect(res.rows[i].id, equals(fiveDocs[i].id));
      expect(res.rows[i].key, equals(fiveDocs[i].id));
      expect(res.rows[i].doc, equals(fiveDocs[i]));
      expect(res.rows[i].value["rev"], fiveDocs[i].rev);
    }

    await cl.deleteDatabase(dbName);
  });

  test('getLocalDocuments', () async {
    final dbName = 'testdb1';
    final db = await cl.createDatabase(dbName);

    // Create some local documents
    final localDoc1 = CouchDocumentBase(
      id: '_local/doc1',
      unmappedProps: {'data': 'first local doc'},
    );
    final localDoc3 = CouchDocumentBase(
      id: '_local/abc',
      unmappedProps: {'data': 'third local doc'},
    );
    final localDoc2 = CouchDocumentBase(
      id: '_local/doc2',
      unmappedProps: {'data': 'second local doc'},
    );

    await db.put(localDoc1);
    await db.put(localDoc2);
    await db.put(localDoc3);

    // Also create a regular document to ensure it's not included
    final regularDoc = CouchDocumentBase(
      id: 'regular_doc',
      unmappedProps: {'data': 'not a local doc'},
    );
    await db.put(regularDoc);

    // Test basic getLocalDocuments without filters
    ViewResult res = await db.getLocalDocuments();
    expect(res.offset, null);
    expect(res.totalRows, null);
    expect(res.rows, hasLength(3));

    // Verify documents are sorted by id (ascending by default)
    expect(res.rows[0].id, equals('_local/abc'));
    expect(res.rows[1].id, equals('_local/doc1'));
    expect(res.rows[2].id, equals('_local/doc2'));

    // Verify structure of rows
    for (final row in res.rows) {
      expect(row.id, startsWith('_local/'));
      expect(row.key, equals(row.id));
      expect(row.value, isA<Map>());
      expect(row.value['rev'], isNotNull);
      expect(row.doc, isNull); // No doc by default
    }

    // Test with includeDocs
    res = await db.getLocalDocuments(includeDocs: true);
    expect(res.totalRows, null);
    expect(res.rows, hasLength(3));
    expect(res.rows[0].doc, isNotNull);
    expect(res.rows[0].doc!.id, equals('_local/abc'));
    expect(res.rows[0].doc!.unmappedProps['data'], equals('third local doc'));

    // Test descending order
    res = await db.getLocalDocuments(descending: true);
    expect(res.totalRows, null);
    expect(res.rows, hasLength(3));
    expect(res.rows[0].id, equals('_local/doc2'));
    expect(res.rows[1].id, equals('_local/doc1'));
    expect(res.rows[2].id, equals('_local/abc'));

    // Test skip and limit
    res = await db.getLocalDocuments(skip: 1, limit: 1);
    expect(res.offset, null);
    expect(res.totalRows, null);
    expect(res.rows, hasLength(1));
    expect(res.rows[0].id, equals('_local/doc1'));

    // Test key filter
    res = await db.getLocalDocuments(key: '_local/doc1');
    expect(res.totalRows, null);
    expect(res.rows, hasLength(1));
    expect(res.rows[0].id, equals('_local/doc1'));

    // Test keys filter
    res = await db.getLocalDocuments(keys: ['_local/doc1', '_local/abc']);
    expect(res.totalRows, null);
    expect(res.rows, hasLength(2));
    expect(res.rows[0].id, equals('_local/doc1'));
    expect(res.rows[1].id, equals('_local/abc'));

    // Test startkey and endkey
    res = await db.getLocalDocuments(
      startkey: '_local/doc1',
      endkey: '_local/doc2',
    );
    expect(res.totalRows, null);
    expect(res.rows, hasLength(2));
    expect(res.rows[0].id, equals('_local/doc1'));
    expect(res.rows[1].id, equals('_local/doc2'));

    // Test endkey with inclusiveEnd false
    res = await db.getLocalDocuments(
      startkey: '_local/doc1',
      endkey: '_local/doc2',
      inclusiveEnd: false,
    );
    expect(res.totalRows, null);
    expect(res.rows, hasLength(1));
    expect(res.rows[0].id, equals('_local/doc1'));

    await cl.deleteDatabase(dbName);
  });

  test('bulkDocs', () async {
    final dbName = 'testdb1';
    final db = await cl.createDatabase(dbName);

    await runBulkDocsTest(db);

    await cl.deleteDatabase(dbName);
  });

  test(
    'bulkDocs when the bulkDocs contain an update of an existing document',
    () async {
      final dbName = 'testdb1';
      final db = await cl.createDatabase(dbName);

      // First create a document normally
      final doc = TestDocumentOne(name: 'Original Name', id: 'update_test_doc');
      final created = await db.put(doc) as TestDocumentOne;
      expect(created.rev, isNotNull);
      expect(created.rev, startsWith('1-'));

      // Now simulate replication scenario: bulkDocs with newEdits=false
      // with a document that already exists and we're providing a new revision
      final newRev = '2-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      final updatedDoc = TestDocumentOne(
        name: 'Updated Name',
        id: 'update_test_doc',
        rev: newRev,
        revisions: Revisions(
          start: 2,
          ids: [
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            created.rev!.split('-')[1], // Include previous revision hash
          ],
        ),
      );

      // bulkDocs with newEdits=false should succeed (returns empty list on success)
      final result = await db.bulkDocs([updatedDoc], newEdits: false);
      expect(result, hasLength(0));

      // Verify the document was updated
      final fetched = await db.get('update_test_doc') as TestDocumentOne?;
      expect(fetched, isNotNull);
      expect(fetched!.name, equals('Updated Name'));
      expect(fetched.rev, equals(newRev));

      // Verify revision history - CouchDB only stores what was provided in _revisions
      final withRevs =
          await db.get('update_test_doc', revs: true) as TestDocumentOne?;
      expect(withRevs, isNotNull);
      expect(withRevs!.revisions, isNotNull);
      expect(withRevs.revisions!.start, equals(2));
      // CouchDB stores only the revision IDs we provided in _revisions
      // Note: CouchDB behavior may vary - it stores what it knows about
      expect(withRevs.revisions!.ids, isNotEmpty);

      await cl.deleteDatabase(dbName);
    },
  );

  test(
    'bulkDocs newEdits=false: non-deleted revision wins over deleted at equal generation',
    () async {
      // Real-world bug: some documents had a human-resolved conflict where the
      // app deleted one competing revision. Both the active leaf and the deleted
      // leaf then appear in the changes feed (style=all_docs). If the deleted
      // leaf's hash happens to be lexicographically higher than the active one
      // (e.g. categorie_back_teig: active=2-0b99... vs deleted=2-d077...), a
      // hash-only comparison wrongly treated the document as a tombstone locally.
      //
      // CouchDB rule: at equal generation, non-deleted beats deleted first;
      // only when both have the same deletion status does the higher hash win.
      //
      // We test both arrival orderings since replication can send them in either
      // order within the same bulkDocs call.

      // active hash starts with '0' (low); deleted hash starts with 'f' (high)
      // → deleted would win under the old hash-only comparison
      const activeHash = '0aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1';
      const deletedHash = 'ffffffffffffffffffffffffffffff01';

      // Sub-test A: active revision arrives before deleted
      {
        final dbName = 'test_bulk_conflict_active_first';
        final db = await cl.createDatabase(dbName);

        final rev1 = await db.put(
          CouchDocumentBase(id: 'doc', unmappedProps: {'name': 'Base'}),
        );
        final rev1Hash = rev1.rev!.split('-')[1];

        await db.bulkDocsRaw([
          jsonEncode({
            '_id': 'doc',
            '_rev': '2-$activeHash',
            'name': 'Active',
            '_revisions': {
              'start': 2,
              'ids': [activeHash, rev1Hash],
            },
          }),
          jsonEncode({
            '_id': 'doc',
            '_rev': '2-$deletedHash',
            '_deleted': true,
            '_revisions': {
              'start': 2,
              'ids': [deletedHash, rev1Hash],
            },
          }),
        ], newEdits: false);

        final current = await db.get('doc');
        expect(current, isNotNull, reason: 'document must not be a tombstone');
        expect(current!.deleted, isNot(true));
        expect(current.rev, equals('2-$activeHash'));

        await cl.deleteDatabase(dbName);
      }

      // Sub-test B: deleted revision arrives before active (the actual bug scenario)
      {
        final dbName = 'test_bulk_conflict_deleted_first';
        final db = await cl.createDatabase(dbName);

        final rev1 = await db.put(
          CouchDocumentBase(id: 'doc', unmappedProps: {'name': 'Base'}),
        );
        final rev1Hash = rev1.rev!.split('-')[1];

        await db.bulkDocsRaw([
          jsonEncode({
            '_id': 'doc',
            '_rev': '2-$deletedHash',
            '_deleted': true,
            '_revisions': {
              'start': 2,
              'ids': [deletedHash, rev1Hash],
            },
          }),
          jsonEncode({
            '_id': 'doc',
            '_rev': '2-$activeHash',
            'name': 'Active',
            '_revisions': {
              'start': 2,
              'ids': [activeHash, rev1Hash],
            },
          }),
        ], newEdits: false);

        final current = await db.get('doc');
        expect(current, isNotNull, reason: 'document must not be a tombstone');
        expect(current!.deleted, isNot(true));
        expect(current.rev, equals('2-$activeHash'));

        await cl.deleteDatabase(dbName);
      }
    },
  );

  test('changes with continuous', () async {
    final dbName = 'testdb1';
    final db = await cl.createDatabase(dbName);

    await runChangesContinuousTest(db);

    await cl.deleteDatabase(dbName);
  });

  test('changes normal with since', () async {
    final dbName = 'testdb1';
    final db = await cl.createDatabase(dbName);

    await runChangesNormalSinceTest(db);

    await cl.deleteDatabase(dbName);
  });

  test('revsDiff correctly handles deleted documents', () async {
    final dbName = 'testdb1';
    final db = await cl.createDatabase(dbName);

    // Create a document
    TestDocumentOne doc = TestDocumentOne(name: 'Test Doc', id: 'testdoc');
    final rev1 = await db.put(doc) as TestDocumentOne;
    expect(rev1.rev, isNotNull);
    expect(rev1.rev, startsWith('1-'));

    // Update the document
    final rev2 =
        await db.put(rev1.copyWith(name: 'Updated Doc')) as TestDocumentOne;
    expect(rev2.rev, isNotNull);
    expect(rev2.rev, startsWith('2-'));

    // Delete the document
    final deleteRev = await db.remove('testdoc', rev2.rev!);
    expect(deleteRev, startsWith('3-'));

    // BEFORE compaction: Test that revsDiff works with the deleted document
    // The bug we fixed was that revsDiff would fail/crash when trying to
    // look up revision history for deleted documents
    final revsDiffBeforeCompaction = await db.revsDiff({
      'testdoc': [deleteRev],
    });

    // Should complete without error - this validates our fix
    expect(revsDiffBeforeCompaction, isNotNull);

    // After compaction, only the current (deleted) revision should be available
    await doCompaction(db);

    // Test that revsDiff still works after compaction
    // CouchDB behavior: For completely deleted documents (deleted + compacted),
    // revsDiff returns an empty map (document is not tracked anymore)
    final revsDiffAfterCompaction = await db.revsDiff({
      'testdoc': [rev1.rev!, rev2.rev!, deleteRev],
    });

    // Should complete without error - the key fix is that revsDiff
    // can handle deleted documents without crashing
    expect(revsDiffAfterCompaction, isNotNull);

    // CouchDB doesn't track deleted documents after compaction,
    // so the result is an empty map
    expect(revsDiffAfterCompaction.isEmpty, isTrue);

    // Most importantly: Verify we can still get the deleted document
    // This proves the document exists and can be retrieved for replication
    final deletedDoc = await db.get('testdoc', rev: deleteRev);
    expect(deletedDoc, isNotNull);
    expect(deletedDoc!.deleted, isTrue);
    expect(deletedDoc.rev, equals(deleteRev));

    // Also verify that get() without rev returns null for deleted documents
    final deletedDocNoRev = await db.get('testdoc');
    expect(deletedDocNoRev, isNull);

    await cl.deleteDatabase(dbName);
  });

  /// Test group for UseDartCouchMixin lifecycle behavior
  group('UseDartCouchMixin lifecycle', () {
    test('useDoc should emit null when document is deleted', () async {
      final db = await cl.createDatabase('usecase_test_db');

      // Create a document
      final doc = CouchDocumentBase(
        id: 'test_doc',
        unmappedProps: {'name': 'test'},
      );
      final createdDoc = await db.put(doc);
      expect(createdDoc.id, 'test_doc');
      expect(createdDoc.rev, isNotNull);

      // Create a stream to watch the document
      final stream = (db as dynamic).useDoc('test_doc');
      final results = <CouchDocumentBase?>[];
      final subscription = stream.listen(results.add);

      // Wait for initial emission
      await waitForCondition(() async => results.isNotEmpty);

      // Verify initial state
      expect(results.length, 1);
      expect(results[0]?.id, 'test_doc');
      expect(results[0]?.rev, createdDoc.rev);

      // Delete the document
      final deleteRev = await db.remove('test_doc', createdDoc.rev!);
      expect(deleteRev, isNotNull);

      // Wait for deletion to be processed
      await waitForCondition(() async => results.length >= 2);

      // Verify null was emitted for deletion
      expect(results.length, 2);
      expect(results[1], null);

      await subscription.cancel();
      await cl.deleteDatabase('usecase_test_db');
    });

    test(
      'useDoc should emit document when created after not existing',
      () async {
        final db = await cl.createDatabase('usecase_test_db2');

        // Create a stream to watch a non-existent document
        final stream = (db as dynamic).useDoc('new_doc');
        final results = <CouchDocumentBase?>[];
        final subscription = stream.listen(results.add);

        // Wait for initial emission
        await waitForCondition(() async => results.isNotEmpty);

        // Verify initial state (null - document doesn't exist)
        expect(results.length, 1);
        expect(results[0], null);

        // Create the document
        final newDoc = CouchDocumentBase(
          id: 'new_doc',
          unmappedProps: {'name': 'new'},
        );
        final createdDoc = await db.put(newDoc);

        // Wait for creation to be processed
        await waitForCondition(() async => results.length >= 2);

        // Verify document was emitted after creation
        expect(results.length, 2);
        expect(results[1]?.id, 'new_doc');
        expect(results[1]?.rev, createdDoc.rev);

        await subscription.cancel();
        await cl.deleteDatabase('usecase_test_db2');
      },
    );

    test('useDoc should handle document updates correctly', () async {
      final db = await cl.createDatabase('usecase_test_db3');

      // Create a document
      final doc = CouchDocumentBase(
        id: 'update_doc',
        unmappedProps: {'version': 1},
      );
      final createdDoc = await db.put(doc);

      // Create a stream to watch the document
      final stream = (db as dynamic).useDoc('update_doc');
      final results = <CouchDocumentBase?>[];
      final subscription = stream.listen(results.add);

      // Wait for initial emission
      await waitForCondition(() async => results.isNotEmpty);

      // Verify initial state
      expect(results.length, 1);
      expect(results[0]?.unmappedProps['version'], 1);

      // Update the document
      final updatedDoc = createdDoc.copyWith(unmappedProps: {'version': 2});
      final savedUpdate = await db.put(updatedDoc);

      // Wait for update to be processed
      await waitForCondition(() async => results.length >= 2);

      // Verify updated document was emitted
      expect(results.length, 2);
      expect(results[1]?.unmappedProps['version'], 2);
      expect(results[1]?.rev, savedUpdate.rev);

      await subscription.cancel();
      await cl.deleteDatabase('usecase_test_db3');
    });
  });

  test('Check if views return design documents', () async {
    final db = await cl.createDatabase('usecase_test_db3');

    // 1. Create 3 test documents
    await createTestDocuments(db, 3);

    // 2. Create initial view on server and sync it
    var designDoc = {
      "_id": "_design/inventory",
      "views": {
        "old_view": {"map": "function(doc){ emit(doc._id, doc.name); }"},
      },
    };
    await db.putRaw(designDoc);

    // 3. Query the view
    final result = await db.query('inventory/old_view');

    expect(result!.rows, hasLength(3));
    expect(result.totalRows, 3);
    expect(result.rows.any((r) => r.key == vegetables[0]), isTrue);
    expect(result.rows.any((r) => r.key == vegetables[1]), isTrue);
    expect(result.rows.any((r) => r.key == vegetables[2]), isTrue);

    final res2 = await db.allDocs();
    expect(res2.totalRows, 4);
    expect(res2.rows, hasLength(4));
    expect(res2.rows.any((r) => r.key == vegetables[0]), isTrue);
    expect(res2.rows.any((r) => r.key == vegetables[1]), isTrue);
    expect(res2.rows.any((r) => r.key == vegetables[2]), isTrue);
    expect(res2.rows.any((r) => r.key == '_design/inventory'), isTrue);

    await cl.deleteDatabase('usecase_test_db3');
  });

  test(
    'create 3 docs and a view and check all items are in, then delete one doc and check it disappears from the view',
    () async {
      final dbName = 'testdb1';
      final db = await cl.createDatabase(dbName);

      // 1. Create 3 test documents
      final doc1 = CouchDocumentBase(
        id: 'doc1',
        unmappedProps: {'name': 'Document 1', 'category': 'test'},
      );
      final doc2 = CouchDocumentBase(
        id: 'doc2',
        unmappedProps: {'name': 'Document 2', 'category': 'test'},
      );
      final doc3 = CouchDocumentBase(
        id: 'doc3',
        unmappedProps: {'name': 'Document 3', 'category': 'test'},
      );

      await db.put(doc1);
      final createdDoc2 = await db.put(doc2);
      await db.put(doc3);

      // 2. Create a view that includes all documents
      final view = ViewData(
        map: '''function(doc) {
          if(doc.category === 'test') {
            emit(doc._id, doc.name);
          }
        }''',
      );
      final designDoc = DesignDocument(
        id: '_design/test_views',
        views: {'all_test_docs': view},
      );
      await db.put(designDoc);

      // 3. Query the view and verify all 3 documents are present
      final viewResult1 = await db.query('test_views/all_test_docs');
      expect(viewResult1, isNotNull);
      expect(viewResult1!.totalRows, 3);
      expect(viewResult1.rows, hasLength(3));

      // Check that all documents are in the view
      final docIdsInView = viewResult1.rows.map((row) => row.id).toList();
      expect(docIdsInView, containsAll(['doc1', 'doc2', 'doc3']));

      // 4. Delete one document
      await db.remove('doc2', createdDoc2.rev!);

      // 5. Query the view again and verify the deleted document is gone
      final viewResult2 = await db.query('test_views/all_test_docs');
      expect(viewResult2, isNotNull);
      expect(viewResult2!.totalRows, 2);
      expect(viewResult2.rows, hasLength(2));

      // Check that only the remaining documents are in the view
      final remainingDocIds = viewResult2.rows.map((row) => row.id).toList();
      expect(remainingDocIds, containsAll(['doc1', 'doc3']));
      expect(remainingDocIds, isNot(contains('doc2')));

      // 6. Verify the deleted document is actually deleted
      final deletedDoc = await db.get('doc2');
      expect(deletedDoc, isNull);

      // 7. Clean up
      await cl.deleteDatabase(dbName);
    },
  );

  test(
    'create 2 docs and a view, then create a new doc and check it appears in the view',
    () async {
      final dbName = 'testdb2';
      final db = await cl.createDatabase(dbName);

      // 1. Create 2 initial test documents
      final doc1 = CouchDocumentBase(
        id: 'doc1',
        unmappedProps: {'name': 'Document 1', 'category': 'test'},
      );
      final doc2 = CouchDocumentBase(
        id: 'doc2',
        unmappedProps: {'name': 'Document 2', 'category': 'test'},
      );

      await db.put(doc1);
      await db.put(doc2);

      // 2. Create a view that includes all documents with test category
      final view = ViewData(
        map: '''function(doc) {
          if(doc.category === 'test') {
            emit(doc._id, doc.name);
          }
        }''',
      );
      final designDoc = DesignDocument(
        id: '_design/test_views_creation',
        views: {'all_test_docs': view},
      );
      await db.put(designDoc);

      // 3. Query the view and verify initial 2 documents are present
      final viewResult1 = await db.query('test_views_creation/all_test_docs');
      expect(viewResult1, isNotNull);
      expect(viewResult1!.totalRows, 2);
      expect(viewResult1.rows, hasLength(2));

      // Check that initial documents are in the view
      final initialDocIds = viewResult1.rows.map((row) => row.id).toList();
      expect(initialDocIds, containsAll(['doc1', 'doc2']));

      // 4. Create a new document
      final doc3 = CouchDocumentBase(
        id: 'doc3',
        unmappedProps: {'name': 'Document 3', 'category': 'test'},
      );
      await db.put(doc3);

      // 5. Query the view again and verify the new document appears
      final viewResult2 = await db.query('test_views_creation/all_test_docs');
      expect(viewResult2, isNotNull);
      expect(viewResult2!.totalRows, 3);
      expect(viewResult2.rows, hasLength(3));

      // Check that all documents including the new one are in the view
      final allDocIds = viewResult2.rows.map((row) => row.id).toList();
      expect(allDocIds, containsAll(['doc1', 'doc2', 'doc3']));

      // 6. Verify the new document exists in the database
      final newDoc = await db.get('doc3');
      expect(newDoc, isNotNull);
      expect(newDoc!.unmappedProps['name'], equals('Document 3'));
      expect(newDoc.unmappedProps['category'], equals('test'));

      // 7. Clean up
      await cl.deleteDatabase(dbName);
    },
  );

  test('inline attachments via putRaw', () async {
    final dbName = 'testdb1';
    final db = await cl.createDatabase(dbName);

    final content1 = Uint8List.fromList(utf8.encode('first attachment'));
    final content2 = Uint8List.fromList(utf8.encode('second attachment'));

    // --- Stage 1: create document with one inline attachment ---
    await db.putRaw({
      '_id': 'doc1',
      '_attachments': {
        'one.txt': {
          'content_type': 'text/plain',
          'data': base64Encode(content1),
        },
      },
    });

    final rev1 = await db.get('doc1');
    expect(rev1, isNotNull);
    expect(rev1!.rev, startsWith('1-'));
    expect(rev1.attachments!, hasLength(1));
    expect(rev1.attachments!.containsKey('one.txt'), isTrue);
    final meta1 = rev1.attachments!['one.txt']!;
    expect(meta1.contentType, equals('text/plain'));
    expect(meta1.length, equals(content1.length));
    expect(meta1.stub, isTrue);
    expect(await db.getAttachment('doc1', 'one.txt'), equals(content1));

    // --- Stage 2: add a second inline attachment in the same PUT ---
    // Existing attachment is passed as a stub to be retained without re-uploading.
    // New attachment is passed with inline data.
    await db.putRaw({
      '_id': 'doc1',
      '_rev': rev1.rev,
      '_attachments': {
        'one.txt': {
          'content_type': 'text/plain',
          'stub': true,
          'revpos': meta1.revpos,
          'digest': meta1.digest,
        },
        'two.txt': {
          'content_type': 'text/plain',
          'data': base64Encode(content2),
        },
      },
    });

    final rev2 = await db.get('doc1');
    expect(rev2, isNotNull);
    expect(rev2!.rev, startsWith('2-'));
    expect(rev2.attachments!, hasLength(2));
    expect(rev2.attachments!.containsKey('one.txt'), isTrue);
    expect(rev2.attachments!.containsKey('two.txt'), isTrue);
    expect(await db.getAttachment('doc1', 'one.txt'), equals(content1));
    expect(await db.getAttachment('doc1', 'two.txt'), equals(content2));

    // --- Stage 3: drop two.txt by omitting it, keep one.txt as stub ---
    await db.putRaw({
      '_id': 'doc1',
      '_rev': rev2.rev,
      '_attachments': {
        'one.txt': {
          'content_type': 'text/plain',
          'stub': true,
          'revpos': rev2.attachments!['one.txt']!.revpos,
          'digest': rev2.attachments!['one.txt']!.digest,
        },
      },
    });

    final rev3 = await db.get('doc1');
    expect(rev3, isNotNull);
    expect(rev3!.rev, startsWith('3-'));
    expect(rev3.attachments!, hasLength(1));
    expect(rev3.attachments!.containsKey('one.txt'), isTrue);
    expect(rev3.attachments!.containsKey('two.txt'), isFalse);
    expect(await db.getAttachment('doc1', 'one.txt'), equals(content1));
    expect(await db.getAttachment('doc1', 'two.txt'), isNull);

    // --- Stage 4: drop all attachments by omitting _attachments entirely ---
    await db.putRaw({'_id': 'doc1', '_rev': rev3.rev});

    final rev4 = await db.get('doc1');
    expect(rev4, isNotNull);
    expect(rev4!.rev, startsWith('4-'));
    expect(rev4.attachments, isNull);
    expect(await db.getAttachment('doc1', 'one.txt'), isNull);

    await cl.deleteDatabase(dbName);
  });

  test('bulkGet retrieves multiple documents', () async {
    final dbName = 'testdb_bulkget';
    final db = await cl.createDatabase(dbName);

    // Create test documents with multiple revisions
    final doc1Revisions = await createRevisions(db, 'doc1', 3);
    final doc2Revisions = await createRevisions(db, 'doc2', 2);

    // Test 1: Retrieve multiple documents without specifying revisions
    final bulkGetRequest1 = BulkGetRequest(
      docs: [
        BulkGetRequestDoc(id: 'doc1'),
        BulkGetRequestDoc(id: 'doc2'),
      ],
    );

    final result1 = await db.bulkGetRaw(bulkGetRequest1);
    expect(result1, isNotNull);
    expect(result1['results'], isNotNull);
    expect(result1['results'], hasLength(2));

    // Verify doc1 result
    final doc1Result = result1['results'][0];
    expect(doc1Result['id'], equals('doc1'));
    expect(doc1Result['docs'], hasLength(1));
    expect(doc1Result['docs'][0]['ok'], isNotNull);
    expect(doc1Result['docs'][0]['ok']['_id'], equals('doc1'));
    expect(doc1Result['docs'][0]['ok']['_rev'], equals(doc1Revisions[0].rev));
    expect(
      (doc1Result['docs'][0]['ok'] as Map)['name'],
      equals(doc1Revisions[0].name),
    );

    // Verify doc2 result
    final doc2Result = result1['results'][1];
    expect(doc2Result['id'], equals('doc2'));
    expect(doc2Result['docs'], hasLength(1));
    expect(doc2Result['docs'][0]['ok'], isNotNull);
    expect(doc2Result['docs'][0]['ok']['_id'], equals('doc2'));
    expect(doc2Result['docs'][0]['ok']['_rev'], equals(doc2Revisions[0].rev));

    // Test 2: Retrieve specific revisions
    final bulkGetRequest2 = BulkGetRequest(
      docs: [
        BulkGetRequestDoc(id: 'doc1', rev: doc1Revisions[1].rev),
        BulkGetRequestDoc(id: 'doc2', rev: doc2Revisions[0].rev),
      ],
    );

    final result2 = await db.bulkGetRaw(bulkGetRequest2);
    expect(result2['results'], hasLength(2));

    // Note: After compaction, old revisions might not be available
    // The behavior depends on whether compaction has run

    // Test 3: Request non-existent document
    final bulkGetRequest3 = BulkGetRequest(
      docs: [
        BulkGetRequestDoc(id: 'doc1'),
        BulkGetRequestDoc(id: 'nonexistent'),
        BulkGetRequestDoc(id: 'doc2'),
      ],
    );

    final result3 = await db.bulkGetRaw(bulkGetRequest3);
    expect(result3['results'], hasLength(3));

    // First document should succeed
    expect(result3['results'][0]['docs'][0]['ok'], isNotNull);

    // Second document should return error
    final nonexistentResult = result3['results'][1];
    expect(nonexistentResult['id'], equals('nonexistent'));
    expect(nonexistentResult['docs'], hasLength(1));
    expect(nonexistentResult['docs'][0]['error'], isNotNull);
    expect(nonexistentResult['docs'][0]['error']['error'], equals('not_found'));

    // Third document should succeed
    expect(result3['results'][2]['docs'][0]['ok'], isNotNull);

    // Test 4: Delete a document and request it
    await db.remove(doc1Revisions[0].id!, doc1Revisions[0].rev!);

    final bulkGetRequest4 = BulkGetRequest(
      docs: [BulkGetRequestDoc(id: 'doc1')],
    );

    final result4 = await db.bulkGetRaw(bulkGetRequest4);
    expect(result4['results'], hasLength(1));
    // After deletion, _bulk_get returns the deleted document with _deleted: true
    expect(result4['results'][0]['docs'][0]['ok'], isNotNull);
    expect(result4['results'][0]['docs'][0]['ok']['_deleted'], equals(true));

    await cl.deleteDatabase(dbName);
  });

  test('bulkGetMultipart returns attachment data', () async {
    final dbName = 'testdb_bulkget_multipart';
    final db = await cl.createDatabase(dbName);

    // Use application/octet-stream to prevent CouchDB gzip compression
    // (compression changes the digest to MD5 of compressed bytes).
    final attData = Uint8List.fromList(List.generate(4096, (i) => i & 0xFF));
    final attName = 'test.bin';
    final attContentType = 'application/octet-stream';

    final doc = await db.put(TestDocumentOne(id: 'doc1', name: 'test'));
    final attRev = await db.saveAttachment(
      doc.id!,
      doc.rev!,
      attName,
      attData,
      contentType: attContentType,
    );

    final request = BulkGetRequest(
      docs: [BulkGetRequestDoc(id: doc.id!, rev: attRev)],
    );

    final results = <BulkGetMultipartResult>[];
    await for (final result in db.bulkGetMultipart(request, revs: true)) {
      results.add(result);
    }

    expect(results, hasLength(1));
    final success = results.first as BulkGetMultipartSuccess;
    expect(success.ok.doc['_id'], equals(doc.id));
    expect(success.ok.attachments, hasLength(1));
    expect(success.ok.attachments, contains(attName));

    final att = success.ok.attachments[attName]!;
    expect(att.contentType, equals(attContentType));
    expect(att.length, equals(attData.length));

    final chunks = <int>[];
    await for (final chunk in att.data) {
      chunks.addAll(chunk);
    }
    expect(Uint8List.fromList(chunks), equals(attData));

    await cl.deleteDatabase(dbName);
  });

  test(
    'bulkDocs emits one change event per document on continuous feed',
    () async {
      final dbName = 'testdb1';
      final db = await cl.createDatabase(dbName);

      final ts = DateTime.now().microsecondsSinceEpoch;
      const numDocs = 5;
      final prefix = 'bulk_ch_$ts';

      final receivedIds = <String>[];
      var listenerInvocations = 0;

      final sub = db.changes(feedmode: FeedMode.continuous).listen((ch) {
        listenerInvocations++;
        final entry = ch.continuous;
        if (entry == null) return;
        if (!entry.id.startsWith(prefix)) return;
        receivedIds.add(entry.id);
      });

      final docs = List.generate(
        numDocs,
        (i) => TestDocumentOne(name: 'Bulk $i', id: '${prefix}_$i'),
      );
      await db.bulkDocs(docs);

      await waitForCondition(
        () async => receivedIds.length >= numDocs,
        maxAttempts: 50,
        interval: Duration(milliseconds: 200),
      );

      log.info(
        'bulkDocs changes: $numDocs docs → $listenerInvocations listener '
        'invocations, ${receivedIds.length} matching events',
      );
      expect(listenerInvocations, equals(numDocs));
      expect(receivedIds.length, numDocs);
      for (var i = 0; i < numDocs; i++) {
        expect(receivedIds, contains('${prefix}_$i'));
      }

      await sub.cancel();
      await cl.deleteDatabase(dbName);
    },
  );

  test('Test rev calculation', () async {
    final dbName = 'testdb1';
    final db = await cl.createDatabase(dbName);

    final map = json.decode(revTestData);
    final res = await db.putRaw(map);
    expect(res['_rev'], equals('1-3208dfb4d365664d4429b6adc43ef0b1'));

    await cl.deleteDatabase(dbName);
  });
}

Future<List<TestDocumentOne>> createThreeRevisions(
  DartCouchDb db,
  String docid,
) {
  return createRevisions(db, docid, 3);
}

Future<List<TestDocumentOne>> createRevisions(
  DartCouchDb db,
  String docid,
  int numOfRevisions,
) async {
  List<TestDocumentOne?> revs = List.filled(numOfRevisions, null);

  TestDocumentOne doc = TestDocumentOne(name: 'Hallo 1', id: docid);
  revs[numOfRevisions - 1] = await db.put(doc) as TestDocumentOne;

  int num = 2;
  for (int i = numOfRevisions - 2; i >= 0; --i) {
    revs[i] =
        await db.put(revs[i + 1]!.copyWith(name: "Hallo ${num++}"))
            as TestDocumentOne;
  }

  await doCompaction(db);

  return List<TestDocumentOne>.from(revs);
}

Future<void> doCompaction(DartCouchDb db) async {
  await db.startCompaction();
  while (await db.isCompactionRunning() == true) {
    await Future.delayed(Duration(milliseconds: 1000));
  }
}

final List<Map<String, dynamic>> viewDocuments = [
  {
    "_id": "biking",

    "title": "Biking",
    "body": "My biggest hobby is mountainbiking. The other day...",
    "date": "2009/01/30 18:04:11",
  },
  {
    "_id": "bought-a-cat",

    "title": "Bought a Cat",
    "body":
        "I went to the pet store earlier and brought home a little kitty...",
    "date": "2009/02/17 21:13:39",
  },
  {
    "_id": "hello-world",

    "title": "Hello World",
    "body": "Well hello and welcome to my new blog...",
    "date": "2009/01/15 15:52:20",
  },
];

Random random = Random(42);
Uint8List attachmentData = Uint8List.fromList(
  List.generate(100, (_) => random.nextInt(256)),
);

Future<List<CouchDocumentBase>> createViewDocuments(DartCouchDb db) async {
  List<CouchDocumentBase> res = [];
  for (int i = 0; i < viewDocuments.length; ++i) {
    res.add(await db.put(CouchDocumentBase.fromMap(viewDocuments[i])));
  }
  res.sort(
    (a, b) => a.unmappedProps['date'].compareTo(b.unmappedProps['date']),
  );
  await db.saveAttachment(res[0].id!, res[0].rev!, "testatt1", attachmentData);
  res[0] = await db.get(res[0].id!) as CouchDocumentBase;
  return res;
}

Future<DesignDocument> createView(DartCouchDb db) async {
  final ViewData view1 = ViewData(
    map: '''function(doc) {
    if(doc.date && doc.title) {
        emit(doc.date, doc.title);
    }
}''',
  );
  final ViewData view2 = ViewData(
    map: '''function(doc) {
    if(doc.date && doc.title) {
        emit(doc.date, doc.title);
        emit(doc.date, doc.title);
    }
}''',
  );
  final DesignDocument d = DesignDocument(
    id: "_design/viewtest",
    views: {"view1": view1, "view2": view2},
  );
  return await db.put(d) as DesignDocument;
}

final String revTestData = '''{
  "_id": "rev_test_document",
  "parent": "771162fe5c2640e1b88ef08511200e91",
  "sortHint": 7,
  "name": "Folge 07 Tick Tock",
  "media": [
    {
      "fileName": "01. LEGO Ninjago - Kapitel 01 Tick Tock (Folge 07).m4a",
      "title": "Kapitel 01: Tick Tock (Folge 07)",
      "attachment_id": "b17e9fad62657c3b1842eae4ce05d474",
      "artist": "LEGO Ninjago",
      "album": "Folge 07: Tick Tock",
      "lufs": -16.3,
      "lra": 6.2,
      "true_peak": -0.4,
      "duration_ms": 98550
    },
    {
      "fileName": "02. LEGO Ninjago - Kapitel 02 Tick Tock (Folge 07).m4a",
      "title": "Kapitel 02: Tick Tock (Folge 07)",
      "attachment_id": "b17e9fad62657c3b1842eae4ce05d9f4",
      "artist": "LEGO Ninjago",
      "album": "Folge 07: Tick Tock",
      "lufs": -17.8,
      "lra": 3.9,
      "true_peak": -1,
      "duration_ms": 93160
    },
    {
      "fileName": "03. LEGO Ninjago - Kapitel 03 Tick Tock (Folge 07).m4a",
      "title": "Kapitel 03: Tick Tock (Folge 07)",
      "attachment_id": "b17e9fad62657c3b1842eae4ce05e010",
      "artist": "LEGO Ninjago",
      "album": "Folge 07: Tick Tock",
      "lufs": -19.2,
      "lra": 5.1,
      "true_peak": -1.3,
      "duration_ms": 99270
    },
    {
      "fileName": "04. LEGO Ninjago - Kapitel 04 Tick Tock (Folge 07).m4a",
      "title": "Kapitel 04: Tick Tock (Folge 07)",
      "attachment_id": "b17e9fad62657c3b1842eae4ce05e51d",
      "artist": "LEGO Ninjago",
      "album": "Folge 07: Tick Tock",
      "lufs": -18.9,
      "lra": 5.1,
      "true_peak": -1,
      "duration_ms": 102270
    },
    {
      "fileName": "05. LEGO Ninjago - Kapitel 05 Tick Tock (Folge 07).m4a",
      "title": "Kapitel 05: Tick Tock (Folge 07)",
      "attachment_id": "b17e9fad62657c3b1842eae4ce05f1ff",
      "artist": "LEGO Ninjago",
      "album": "Folge 07: Tick Tock",
      "lufs": -18.8,
      "lra": 4.9,
      "true_peak": -1,
      "duration_ms": 90830
    },
    {
      "fileName": "06. LEGO Ninjago - Kapitel 06 Tick Tock (Folge 07).m4a",
      "title": "Kapitel 06: Tick Tock (Folge 07)",
      "attachment_id": "b17e9fad62657c3b1842eae4ce05f45c",
      "artist": "LEGO Ninjago",
      "album": "Folge 07: Tick Tock",
      "lufs": -18.3,
      "lra": 4.1,
      "true_peak": -1.4,
      "duration_ms": 108210
    },
    {
      "fileName": "07. LEGO Ninjago - Kapitel 07 Tick Tock (Folge 07).m4a",
      "title": "Kapitel 07: Tick Tock (Folge 07)",
      "attachment_id": "b17e9fad62657c3b1842eae4ce0603ba",
      "artist": "LEGO Ninjago",
      "album": "Folge 07: Tick Tock",
      "lufs": -18.4,
      "lra": 3.9,
      "true_peak": -1.2,
      "duration_ms": 97150
    },
    {
      "fileName": "08. LEGO Ninjago - Kapitel 08 Tick Tock (Folge 07).m4a",
      "title": "Kapitel 08: Tick Tock (Folge 07)",
      "attachment_id": "b17e9fad62657c3b1842eae4ce06053c",
      "artist": "LEGO Ninjago",
      "album": "Folge 07: Tick Tock",
      "lufs": -18.5,
      "lra": 4.3,
      "true_peak": -1.2,
      "duration_ms": 97610
    },
    {
      "fileName": "09. LEGO Ninjago - Kapitel 09 Tick Tock (Folge 07).m4a",
      "title": "Kapitel 09: Tick Tock (Folge 07)",
      "attachment_id": "b17e9fad62657c3b1842eae4ce060588",
      "artist": "LEGO Ninjago",
      "album": "Folge 07: Tick Tock",
      "lufs": -17.6,
      "lra": 3.4,
      "true_peak": -1,
      "duration_ms": 103090
    },
    {
      "fileName": "10. LEGO Ninjago - Kapitel 10 Tick Tock (Folge 07).m4a",
      "title": "Kapitel 10: Tick Tock (Folge 07)",
      "attachment_id": "b17e9fad62657c3b1842eae4ce061456",
      "artist": "LEGO Ninjago",
      "album": "Folge 07: Tick Tock",
      "lufs": -19.5,
      "lra": 5.1,
      "true_peak": -1.2,
      "duration_ms": 93510
    },
    {
      "fileName": "11. LEGO Ninjago - Kapitel 11 Tick Tock (Folge 07).m4a",
      "title": "Kapitel 11: Tick Tock (Folge 07)",
      "attachment_id": "b17e9fad62657c3b1842eae4ce061c68",
      "artist": "LEGO Ninjago",
      "album": "Folge 07: Tick Tock",
      "lufs": -18.3,
      "lra": 5.9,
      "true_peak": -1.5,
      "duration_ms": 93470
    },
    {
      "fileName": "12. LEGO Ninjago - Kapitel 12 Tick Tock (Folge 07).m4a",
      "title": "Kapitel 12: Tick Tock (Folge 07)",
      "attachment_id": "b17e9fad62657c3b1842eae4ce062b9a",
      "artist": "LEGO Ninjago",
      "album": "Folge 07: Tick Tock",
      "lufs": -18.6,
      "lra": 5.3,
      "true_peak": -1.5,
      "duration_ms": 94270
    },
    {
      "fileName": "13. LEGO Ninjago - Kapitel 13 Tick Tock (Folge 07).m4a",
      "title": "Kapitel 13: Tick Tock (Folge 07)",
      "attachment_id": "b17e9fad62657c3b1842eae4ce062e44",
      "artist": "LEGO Ninjago",
      "album": "Folge 07: Tick Tock",
      "lufs": -17.9,
      "lra": 5.8,
      "true_peak": -1,
      "duration_ms": 107760
    },
    {
      "fileName": "14. LEGO Ninjago - Kapitel 14 Tick Tock (Folge 07).m4a",
      "title": "Kapitel 14: Tick Tock (Folge 07)",
      "attachment_id": "b17e9fad62657c3b1842eae4ce063db8",
      "artist": "LEGO Ninjago",
      "album": "Folge 07: Tick Tock",
      "lufs": -18.8,
      "lra": 7.8,
      "true_peak": -1,
      "duration_ms": 94630
    },
    {
      "fileName": "15. LEGO Ninjago - Kapitel 15 Tick Tock (Folge 07).m4a",
      "title": "Kapitel 15: Tick Tock (Folge 07)",
      "attachment_id": "b17e9fad62657c3b1842eae4ce064293",
      "artist": "LEGO Ninjago",
      "album": "Folge 07: Tick Tock",
      "lufs": -17,
      "lra": 3.1,
      "true_peak": -1,
      "duration_ms": 100920
    },
    {
      "fileName": "16. LEGO Ninjago - Kapitel 16 Tick Tock (Folge 07).m4a",
      "title": "Kapitel 16: Tick Tock (Folge 07)",
      "attachment_id": "b17e9fad62657c3b1842eae4ce06489a",
      "artist": "LEGO Ninjago",
      "album": "Folge 07: Tick Tock",
      "lufs": -18.1,
      "lra": 5.5,
      "true_peak": -1.4,
      "duration_ms": 103440
    },
    {
      "fileName": "17. LEGO Ninjago - Kapitel 17 Tick Tock (Folge 07).m4a",
      "title": "Kapitel 17: Tick Tock (Folge 07)",
      "attachment_id": "b17e9fad62657c3b1842eae4ce0650f2",
      "artist": "LEGO Ninjago",
      "album": "Folge 07: Tick Tock",
      "lufs": -18.1,
      "lra": 5.9,
      "true_peak": -1.5,
      "duration_ms": 71670
    }
  ],
  "repeat": false,
  "shuffle": false,
  "show_track_cover_rather_than_item_cover": false,
  "is_audio_book": false,
  "is_new": false,
  "from_date_time": "2026-03-14T00:00:00.000",
  "!doc_type": "media_item"
}''';
