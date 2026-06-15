import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:dart_couch/dart_couch.dart';
import 'dart:convert';

import 'helper/bulk_docs_test_helper.dart';
import 'helper/helper.dart';
import 'helper/test_document_one.dart';
import 'helper/changes_test_helper.dart';

void main() {
  DartCouchDb.ensureInitialized();

  configureTestLogging();

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

  // PLAN.md Phase 0 — conflict handling parity. doTest runs each case against
  // BOTH the Http and Local server, so these verify the two implementations
  // answer identically for a conflicted document. The conflict is injected
  // directly via bulkDocsRaw(newEdits:false) (the replication-protocol path):
  // two leaf revisions at the same generation sharing one ancestor. CouchDB's
  // winner rule at equal generation is "higher rev hash wins", so revB ('b…')
  // beats revA ('a…'); revA is the conflicting (losing) leaf.
  //
  // Empirically (Phase 0):
  //  - P1 winner parity: GREEN on both.
  //  - P3 revsDiff parity: GREEN on both — Local DOES record the conflict leaf
  //    rev in its revision history, so it does NOT re-request it. This corrects
  //    the earlier "re-pull churn for fetchable leaves" assumption: that churn
  //    does not occur. (Bodyless not_found leaves are a separate matter.)
  //  - P2 conflict-listing parity: RED on Local — it keeps only the winner's
  //    body and exposes no `_conflicts`. This is the genuine Phase 1 gap
  //    (conflict visibility so the app/resolver can see and resolve conflicts).
  group('conflict handling parity (Http vs Local)', () {
    const dbName = 'conflict_parity_db';
    const docId = 'conflictdoc';
    const ancestor = 'cccccccccccccccccccccccccccccccc';
    const hashA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const hashB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const revA = '2-$hashA';
    const revB = '2-$hashB';
    const winnerRev = revB;
    const loserRev = revA;

    Future<DartCouchDb> setupConflict() async {
      // Fresh DB each time, robust against a prior failed test leaving it.
      if ((await cl.db(dbName)) != null) await cl.deleteDatabase(dbName);
      final db = await cl.createDatabase(dbName);
      final docA = jsonEncode({
        '_id': docId,
        '_rev': revA,
        'branch': 'A',
        '_revisions': {
          'start': 2,
          'ids': [hashA, ancestor],
        },
      });
      final docB = jsonEncode({
        '_id': docId,
        '_rev': revB,
        'branch': 'B',
        '_revisions': {
          'start': 2,
          'ids': [hashB, ancestor],
        },
      });
      await db.bulkDocsRaw([docA, docB], newEdits: false);
      return db;
    }

    test('P1 winning revision is deterministic (higher hash wins)', () async {
      final db = await setupConflict();
      final doc = await db.getRaw(docId);
      expect(doc, isNotNull);
      expect(doc!['_rev'], winnerRev);
      await cl.deleteDatabase(dbName);
    });

    test('P2 get(conflicts:true) lists the conflicting leaf', () async {
      final db = await setupConflict();
      final doc = await db.getRaw(docId, conflicts: true);
      expect(doc, isNotNull);
      expect(doc!['_rev'], winnerRev);
      expect(
        doc['_conflicts'],
        isNotNull,
        reason: 'conflicts:true must surface the losing leaf revision',
      );
      expect((doc['_conflicts'] as List).cast<String>(), [loserRev]);
      await cl.deleteDatabase(dbName);
    });

    test('P3 revsDiff does not report known conflict leaves as missing', () async {
      final db = await setupConflict();
      final diff = await db.revsDiff({
        docId: [winnerRev, loserRev],
      });
      final missing = diff[docId]?.missing ?? const <String>[];
      expect(
        missing,
        isEmpty,
        reason:
            'both leaf revs are known to the DB; revsDiff must not report them '
            'missing (otherwise the puller would re-fetch on every change). '
            'GREEN on both: Local records conflict leaf revs even though it '
            'keeps only the winner body — so no re-pull churn for fetchable '
            'leaves.',
      );
      await cl.deleteDatabase(dbName);
    });
  });

  // PLAN.md Phase 1 — leaf-set algorithm parity. Stress-tests the conflict
  // leaf-set maintenance against the many cases the simple P1/P2/P3 group does
  // not: linear updates (must NOT conflict), demote-on-win, supersession,
  // 3-way conflicts, lower-generation siblings, deleted conflicts, order
  // independence, and get(rev:X). Every case runs against BOTH Http and Local
  // (newEdits=false injection with explicit `_revisions` chains), so any Local
  // divergence from CouchDB fails the test.
  group('conflict leaf set (Http vs Local)', () {
    const dbName = 'conflict_leafset_db';
    const docId = 'd';

    // 32-hex-char hash from a short hex tag (CouchDB rev hashes are 32 hex).
    String hx(String tag) => tag.padRight(32, '0');
    String rv(int gen, String tag) => '$gen-${hx(tag)}';

    Future<DartCouchDb> freshDb() async {
      if ((await cl.db(dbName)) != null) await cl.deleteDatabase(dbName);
      return cl.createDatabase(dbName);
    }

    // Inject one leaf via the replication path. [idTags] is the rev-hash chain
    // newest-first (this rev's tag first, then its ancestors).
    Future<void> inject(
      DartCouchDb db,
      int start,
      List<String> idTags, {
      bool deleted = false,
    }) async {
      final ids = idTags.map(hx).toList();
      final doc = <String, dynamic>{
        '_id': docId,
        '_rev': '$start-${ids.first}',
        '_revisions': {'start': start, 'ids': ids},
        'val': idTags.first,
      };
      if (deleted) doc['_deleted'] = true;
      await db.bulkDocsRaw([jsonEncode(doc)], newEdits: false);
    }

    // Inject one leaf carrying a single inline (base64) attachment via the
    // replication path — exercises conflict-leaf attachment storage (Stage 2).
    // application/octet-stream avoids CouchDB gzip so the stored bytes are exact.
    Future<void> injectWithAtt(
      DartCouchDb db,
      int start,
      List<String> idTags, {
      required String attName,
      required List<int> attData,
    }) async {
      final ids = idTags.map(hx).toList();
      final doc = <String, dynamic>{
        '_id': docId,
        '_rev': '$start-${ids.first}',
        '_revisions': {'start': start, 'ids': ids},
        'val': idTags.first,
        '_attachments': {
          attName: {
            'content_type': 'application/octet-stream',
            'data': base64Encode(attData),
          },
        },
      };
      await db.bulkDocsRaw([jsonEncode(doc)], newEdits: false);
    }

    Future<String?> winner(DartCouchDb db) async =>
        (await db.getRaw(docId))?['_rev'];
    Future<List<String>> conflictsOf(DartCouchDb db) async =>
        ((await db.getRaw(docId, conflicts: true))?['_conflicts'] as List?)
            ?.cast<String>()
            .toList() ??
        <String>[];

    // Inject one or more leaves through the multipart replication write path
    // (bulkDocsFromMultipart → the no-attachment fast path on Local). Passing
    // several leaves in one call exercises the in-batch duplicate case.
    Future<void> injectMultipart(
      DartCouchDb db,
      List<({int start, List<String> idTags})> leaves,
    ) async {
      final docs = leaves.map((l) {
        final ids = l.idTags.map(hx).toList();
        return BulkGetMultipartSuccess(
          BulkGetMultipartOk(
            doc: {
              '_id': docId,
              '_rev': '${l.start}-${ids.first}',
              '_revisions': {'start': l.start, 'ids': ids},
              'val': l.idTags.first,
            },
            attachments: const {},
          ),
        );
      }).toList();
      await db.bulkDocsFromMultipart(docs, newEdits: false);
    }

    // Inject ONE leaf carrying a single attachment through the multipart
    // streaming write path (bulkDocsFromMultipart → the attachment main path on
    // Local; base64+POST on Http). Exercises _storeStreamConflictAttachments
    // when the leaf loses, i.e. the real replication path for conflict-leaf
    // attachments (Stage 2). digest is CouchDB-format md5-<base64> of the raw
    // bytes (application/octet-stream → no gzip).
    Future<void> injectMultipartWithAtt(
      DartCouchDb db,
      int start,
      List<String> idTags, {
      required String attName,
      required Uint8List attData,
    }) async {
      final ids = idTags.map(hx).toList();
      await db.bulkDocsFromMultipart([
        BulkGetMultipartSuccess(
          BulkGetMultipartOk(
            doc: {
              '_id': docId,
              '_rev': '$start-${ids.first}',
              '_revisions': {'start': start, 'ids': ids},
              'val': idTags.first,
            },
            attachments: {
              attName: BulkGetMultipartAttachment(
                contentType: 'application/octet-stream',
                digest: 'md5-${base64Encode(md5.convert(attData).bytes)}',
                length: attData.length,
                revpos: start,
                data: Stream<List<int>>.fromIterable([attData]),
              ),
            },
          ),
        ),
      ], newEdits: false);
    }

    // REPLICATION_AND_CONFLICT_MODEL.md "View map functions": a view map
    // function receives the winning revision PLUS a `_conflicts` member when the
    // document is in conflict, so a view can locate conflicted docs. Must behave
    // identically on Http (CouchDB) and Local (Phase 6 compliance).
    test('a view map function sees _conflicts for a conflicted doc', () async {
      final db = await freshDb();
      // The canonical conflict-locating view from the spec.
      await db.putRaw({
        '_id': '_design/cf',
        'views': {
          'conflicts': {
            'map':
                'function(doc){ if(doc._conflicts){ '
                'emit(doc._id, [doc._rev].concat(doc._conflicts)); } }',
          },
        },
      });

      // A plain, non-conflicted doc — must NOT appear in the view.
      await db.putRaw({'_id': 'plain', 'val': 'x'});

      // Conflict on doc 'd': two same-gen siblings sharing an ancestor.
      await inject(db, 2, ['a', 'ba5e']);
      await inject(db, 2, ['b', 'ba5e']); // higher hash → winner
      expect(await winner(db), rv(2, 'b'));
      expect(await conflictsOf(db), [rv(2, 'a')]);

      final result = (await db.query('cf/conflicts'))!;
      final dRows = result.rows.where((r) => r.key == docId).toList();
      expect(dRows, hasLength(1), reason: 'conflicted doc must emit');
      expect(
        result.rows.any((r) => r.key == 'plain'),
        isFalse,
        reason: 'non-conflicted doc must not emit',
      );
      // Value = [winnerRev, ...conflictRevs] per the map function.
      final value = (dRows.first.value as List).cast<String>();
      expect(value, containsAll([rv(2, 'b'), rv(2, 'a')]));

      await cl.deleteDatabase(dbName);
    });

    test('linear update does NOT create a conflict', () async {
      final db = await freshDb();
      await inject(db, 2, ['b', 'ba5e']);
      await inject(db, 3, ['c', 'b', 'ba5e']); // child of 2-b
      expect(await winner(db), rv(3, 'c'));
      expect(await conflictsOf(db), isEmpty);
      await cl.deleteDatabase(dbName);
    });

    test('two siblings → one conflict; higher hash wins', () async {
      final db = await freshDb();
      await inject(db, 2, ['a', 'ba5e']);
      await inject(db, 2, ['b', 'ba5e']); // sibling, higher hash → wins
      expect(await winner(db), rv(2, 'b'));
      expect(await conflictsOf(db), [rv(2, 'a')]);
      await cl.deleteDatabase(dbName);
    });

    test('order independence: loser-first vs winner-first converge', () async {
      final db1 = await freshDb();
      await inject(db1, 2, ['a', 'ba5e']); // becomes winner first
      await inject(db1, 2, ['b', 'ba5e']); // wins, demotes 2-a
      final w1 = await winner(db1);
      final c1 = await conflictsOf(db1);
      await cl.deleteDatabase(dbName);

      final db2 = await freshDb();
      await inject(db2, 2, ['b', 'ba5e']); // winner first
      await inject(db2, 2, ['a', 'ba5e']); // loses → stored as conflict
      expect(await winner(db2), w1);
      expect(await conflictsOf(db2), c1);
      expect(w1, rv(2, 'b'));
      expect(c1, [rv(2, 'a')]);
      await cl.deleteDatabase(dbName);
    });

    test('three-way conflict → two conflicts listed', () async {
      final db = await freshDb();
      await inject(db, 2, ['a', 'ba5e']);
      await inject(db, 2, ['b', 'ba5e']);
      await inject(db, 2, ['c', 'ba5e']); // 2-c highest hash → winner
      expect(await winner(db), rv(2, 'c'));
      expect(
        (await conflictsOf(db))..sort(),
        [rv(2, 'a'), rv(2, 'b')]..sort(),
      );
      await cl.deleteDatabase(dbName);
    });

    test('higher-generation sibling wins; lower-gen sibling is the conflict', () async {
      final db = await freshDb();
      await inject(db, 3, ['e', 'd', 'ba5e']); // gen 3 branch
      await inject(db, 2, ['f', 'ba5e']); // gen 2 sibling branch
      expect(await winner(db), rv(3, 'e')); // higher generation wins
      expect(await conflictsOf(db), [rv(2, 'f')]);
      await cl.deleteDatabase(dbName);
    });

    test('incoming child supersedes an existing conflict leaf', () async {
      final db = await freshDb();
      await inject(db, 3, ['e', 'd', 'ba5e']); // winner gen 3 (hash e)
      await inject(db, 2, ['f', 'ba5e']); // conflict leaf 2-f
      expect(await conflictsOf(db), [rv(2, 'f')]);
      await inject(db, 3, ['a', 'f', 'ba5e']); // child of 2-f; loses to 3-e (e>a)
      // 2-f superseded by 3-a; 3-a is the conflict now (3-e still winner).
      expect(await winner(db), rv(3, 'e'));
      expect(await conflictsOf(db), [rv(3, 'a')]);
      await cl.deleteDatabase(dbName);
    });

    test('deleted sibling appears in _deleted_conflicts, not _conflicts', () async {
      final db = await freshDb();
      await inject(db, 2, ['b', 'ba5e']); // active winner
      await inject(db, 2, ['a', 'ba5e'], deleted: true); // deleted sibling
      expect(await winner(db), rv(2, 'b'));
      expect(await conflictsOf(db), isEmpty);
      final withDel = await db.getRaw(docId, deletedConflicts: true);
      expect(
        (withDel?['_deleted_conflicts'] as List?)?.cast<String>(),
        [rv(2, 'a')],
      );
      await cl.deleteDatabase(dbName);
    });

    test('get(rev:X) returns a conflict leaf body', () async {
      final db = await freshDb();
      await inject(db, 2, ['b', 'ba5e']);
      await inject(db, 2, ['a', 'ba5e']); // conflict leaf 2-a
      final leaf = await db.getRaw(docId, rev: rv(2, 'a'));
      expect(leaf, isNotNull);
      expect(leaf!['_rev'], rv(2, 'a'));
      expect(leaf['val'], 'a');
      await cl.deleteDatabase(dbName);
    });

    test('revsDiff knows all leaves regardless of arrival order', () async {
      final db = await freshDb();
      await inject(db, 2, ['b', 'ba5e']); // winner first
      await inject(db, 2, ['a', 'ba5e']); // conflict
      final diff = await db.revsDiff({
        docId: [rv(2, 'a'), rv(2, 'b')],
      });
      expect(diff[docId]?.missing ?? const <String>[], isEmpty);
      await cl.deleteDatabase(dbName);
    });

    test('getOpenRevs returns the full leaf set (winner + conflicts)', () async {
      final db = await freshDb();
      await inject(db, 2, ['b', 'ba5e']); // winner
      await inject(db, 2, ['a', 'ba5e']); // conflict
      final open = await db.getOpenRevs(docId); // null revisions → "all"
      final revsReturned = (open ?? [])
          .map((o) => o.doc?.rev)
          .whereType<String>()
          .toSet();
      expect(revsReturned, {rv(2, 'a'), rv(2, 'b')});
      await cl.deleteDatabase(dbName);
    });

    test('deleting the winner promotes the surviving conflict leaf', () async {
      final db = await freshDb();
      await inject(db, 2, ['a', 'ba5e']); // conflict-to-be
      await inject(db, 2, ['b', 'ba5e']); // winner 2-b (higher hash)
      expect(await winner(db), rv(2, 'b'));
      expect(await conflictsOf(db), [rv(2, 'a')]);

      // Delete the current winner; CouchDB promotes 2-a to winner.
      await db.remove(docId, rv(2, 'b'));
      expect(await winner(db), rv(2, 'a'));
      expect(await conflictsOf(db), isEmpty);
      await cl.deleteDatabase(dbName);
    });

    test('multipart write path stores conflicts (separate calls)', () async {
      final db = await freshDb();
      await injectMultipart(db, [
        (start: 2, idTags: ['b', 'ba5e']),
      ]); // new → winner
      await injectMultipart(db, [
        (start: 2, idTags: ['a', 'ba5e']),
      ]); // existing → conflict
      expect(await winner(db), rv(2, 'b'));
      expect(await conflictsOf(db), [rv(2, 'a')]);
      await cl.deleteDatabase(dbName);
    });

    test('multipart write path stores in-batch conflicts (one call)', () async {
      final db = await freshDb();
      // Both conflicting leaves of one doc in a single bulkDocsFromMultipart
      // call — exercises the duplicate-docId (per-doc) partition.
      await injectMultipart(db, [
        (start: 2, idTags: ['a', 'ba5e']),
        (start: 2, idTags: ['b', 'ba5e']),
      ]);
      expect(await winner(db), rv(2, 'b'));
      expect(await conflictsOf(db), [rv(2, 'a')]);
      await cl.deleteDatabase(dbName);
    });

    test('linear delete (bulkDocsRaw) tombstones the document', () async {
      final db = await freshDb();
      await inject(db, 1, ['a']); // create 1-a
      await inject(db, 2, ['d', 'a'], deleted: true); // delete (child of 1-a)
      expect(await db.getRaw(docId), isNull);
      expect(await conflictsOf(db), isEmpty);
      await cl.deleteDatabase(dbName);
    });

    test('delete-only doc (deletion arrives first/alone) is a tombstone', () async {
      final db = await freshDb();
      await inject(db, 2, ['d', 'a'], deleted: true); // only the deletion
      expect(await db.getRaw(docId), isNull);
      await cl.deleteDatabase(dbName);
    });

    test('deletion arriving after the doc was already created tombstones it', () async {
      final db = await freshDb();
      await injectMultipart(db, [
        (start: 1, idTags: ['a']),
      ]); // create via multipart fast path
      // delete via multipart fast path (child of 1-a)
      await db.bulkDocsFromMultipart([
        BulkGetMultipartSuccess(
          BulkGetMultipartOk(
            doc: {
              '_id': docId,
              '_rev': '2-${hx('d')}',
              '_deleted': true,
              '_revisions': {
                'start': 2,
                'ids': [hx('d'), hx('a')],
              },
            },
            attachments: const {},
          ),
        ),
      ], newEdits: false);
      expect(await db.getRaw(docId), isNull);
      expect(await conflictsOf(db), isEmpty);
      await cl.deleteDatabase(dbName);
    });

    // ── Deferred edge cases (PLAN.md §0.2) ──────────────────────────────────
    // A second, harder batch of leaf-set parity cases. Same injection model
    // (newEdits=false with explicit `_revisions` chains); every case runs
    // against BOTH Http and Local so any Local divergence from CouchDB fails.

    Future<List<String>> deletedConflictsOf(DartCouchDb db) async =>
        ((await db.getRaw(docId, deletedConflicts: true))?['_deleted_conflicts']
                    as List?)
                ?.cast<String>()
                .toList() ??
            <String>[];

    test('re-delivering the same leaves is idempotent', () async {
      final db = await freshDb();
      await inject(db, 2, ['a', 'ba5e']);
      await inject(db, 2, ['b', 'ba5e']);
      expect(await winner(db), rv(2, 'b'));
      expect(await conflictsOf(db), [rv(2, 'a')]);
      // Re-deliver both leaves: the leaf set must not grow (no duplicate rows).
      await inject(db, 2, ['a', 'ba5e']);
      await inject(db, 2, ['b', 'ba5e']);
      expect(await winner(db), rv(2, 'b'));
      expect(await conflictsOf(db), [rv(2, 'a')]);
      await cl.deleteDatabase(dbName);
    });

    test('four-way conflict → three conflicts listed', () async {
      final db = await freshDb();
      await inject(db, 2, ['a', 'ba5e']);
      await inject(db, 2, ['b', 'ba5e']);
      await inject(db, 2, ['c', 'ba5e']);
      await inject(db, 2, ['d', 'ba5e']); // 2-d highest hash → winner
      expect(await winner(db), rv(2, 'd'));
      expect(
        (await conflictsOf(db))..sort(),
        [rv(2, 'a'), rv(2, 'b'), rv(2, 'c')]..sort(),
      );
      await cl.deleteDatabase(dbName);
    });

    test('default get() returns the winner only; no _conflicts leak', () async {
      final db = await freshDb();
      await inject(db, 2, ['a', 'ba5e']);
      await inject(db, 2, ['b', 'ba5e']);
      final doc = (await db.getRaw(docId))!; // no conflicts/meta flags
      expect(doc['_rev'], rv(2, 'b'));
      expect(
        doc.containsKey('_conflicts'),
        isFalse,
        reason: 'a plain get must not expose _conflicts (CouchDB parity)',
      );
      await cl.deleteDatabase(dbName);
    });

    test('meta:true surfaces _conflicts and _revs_info', () async {
      final db = await freshDb();
      await inject(db, 2, ['a', 'ba5e']);
      await inject(db, 2, ['b', 'ba5e']);
      final doc = (await db.getRaw(docId, meta: true))!;
      expect(doc['_rev'], rv(2, 'b'));
      expect((doc['_conflicts'] as List?)?.cast<String>(), [rv(2, 'a')]);
      expect(
        doc['_revs_info'],
        isNotNull,
        reason: 'meta is shorthand for conflicts + deleted_conflicts + revs_info',
      );
      await cl.deleteDatabase(dbName);
    });

    test('revsDiff reports an unknown rev missing while known leaves are not', () async {
      final db = await freshDb();
      await inject(db, 2, ['a', 'ba5e']);
      await inject(db, 2, ['b', 'ba5e']);
      final diff = await db.revsDiff({
        docId: [rv(2, 'a'), rv(2, 'b'), rv(2, 'f')], // 2-f was never delivered
      });
      expect(diff[docId]?.missing ?? const <String>[], [rv(2, 'f')]);
      await cl.deleteDatabase(dbName);
    });

    test('winner advances linearly; existing conflict leaf is preserved', () async {
      final db = await freshDb();
      await inject(db, 2, ['a', 'ba5e']); // conflict-to-be
      await inject(db, 2, ['b', 'ba5e']); // winner
      expect(await conflictsOf(db), [rv(2, 'a')]);
      await inject(db, 3, ['c', 'b', 'ba5e']); // child of winner 2-b
      expect(await winner(db), rv(3, 'c'));
      expect(
        await conflictsOf(db),
        [rv(2, 'a')],
        reason: 'a linear advance of the winner must not disturb the conflict',
      );
      await cl.deleteDatabase(dbName);
    });

    test('conflict branch grows past the winner and becomes the new winner', () async {
      final db = await freshDb();
      await inject(db, 2, ['a', 'ba5e']); // loser leaf
      await inject(db, 2, ['b', 'ba5e']); // winner
      expect(await winner(db), rv(2, 'b'));
      // Extend the losing branch to gen 3 → outranks 2-b by generation.
      await inject(db, 3, ['c', 'a', 'ba5e']); // child of 2-a
      expect(await winner(db), rv(3, 'c'));
      expect(
        await conflictsOf(db),
        [rv(2, 'b')],
        reason: 'the old winner 2-b is demoted to a conflict leaf',
      );
      await cl.deleteDatabase(dbName);
    });

    test('get(rev:X) serves the correct body for winner and conflict', () async {
      final db = await freshDb();
      await inject(db, 2, ['a', 'ba5e']); // val 'a'
      await inject(db, 2, ['b', 'ba5e']); // val 'b' (winner)
      expect((await db.getRaw(docId, rev: rv(2, 'b')))!['val'], 'b');
      expect((await db.getRaw(docId, rev: rv(2, 'a')))!['val'], 'a');
      expect(
        (await db.getRaw(docId))!['val'],
        'b',
        reason: 'a plain get returns the winner body',
      );
      await cl.deleteDatabase(dbName);
    });

    test('getOpenRevs with explicit revisions returns each requested leaf', () async {
      final db = await freshDb();
      await inject(db, 2, ['a', 'ba5e']);
      await inject(db, 2, ['b', 'ba5e']);
      final open = await db.getOpenRevs(
        docId,
        revisions: [rv(2, 'a'), rv(2, 'b')],
      );
      final revsReturned = (open ?? [])
          .where((o) => o.state == OpenRevsState.ok)
          .map((o) => o.doc?.rev)
          .whereType<String>()
          .toSet();
      expect(revsReturned, {rv(2, 'a'), rv(2, 'b')});
      await cl.deleteDatabase(dbName);
    });

    test('non-deleted leaf beats a higher-gen deleted leaf (deleted first)', () async {
      final db = await freshDb();
      // Branch 1: 1-ba5e → 2-d → 3-e (deleted leaf, gen 3).
      await inject(db, 3, ['e', 'd', 'ba5e'], deleted: true);
      // Branch 2: 1-ba5e → 2-f (non-deleted leaf, gen 2).
      await inject(db, 2, ['f', 'ba5e']);
      expect(
        await winner(db),
        rv(2, 'f'),
        reason: 'a non-deleted leaf wins over a deleted one regardless of gen',
      );
      expect(await conflictsOf(db), isEmpty);
      expect(await deletedConflictsOf(db), [rv(3, 'e')]);
      await cl.deleteDatabase(dbName);
    });

    test('non-deleted leaf beats a higher-gen deleted leaf (non-deleted first)', () async {
      final db = await freshDb();
      await inject(db, 2, ['f', 'ba5e']); // non-deleted gen-2 first
      await inject(db, 3, ['e', 'd', 'ba5e'], deleted: true); // deleted gen-3
      expect(await winner(db), rv(2, 'f'));
      expect(await conflictsOf(db), isEmpty);
      expect(
        await deletedConflictsOf(db),
        [rv(3, 'e')],
        reason: 'arrival order must not change the converged leaf set',
      );
      await cl.deleteDatabase(dbName);
    });

    test('deleting the winner with only deleted leaves remaining stays a tombstone', () async {
      final db = await freshDb();
      await inject(db, 2, ['a', 'ba5e']); // non-deleted winner
      await inject(db, 2, ['b', 'ba5e'], deleted: true); // deleted sibling
      expect(await winner(db), rv(2, 'a'));
      // Delete the winner → its branch tombstones; every remaining leaf is now
      // deleted, so the document must stay deleted (no live leaf to promote).
      await db.remove(docId, rv(2, 'a'));
      expect(await db.getRaw(docId), isNull);
      await cl.deleteDatabase(dbName);
    });

    test('promotion after deleting the winner picks the highest surviving non-deleted leaf', () async {
      final db = await freshDb();
      await inject(db, 2, ['a', 'ba5e']);
      await inject(db, 2, ['b', 'ba5e']);
      await inject(db, 2, ['c', 'ba5e']); // 2-c winner
      expect(await winner(db), rv(2, 'c'));
      await db.remove(docId, rv(2, 'c')); // delete the winner
      expect(
        await winner(db),
        rv(2, 'b'),
        reason: 'promotion picks the highest-hash surviving non-deleted leaf',
      );
      expect(await conflictsOf(db), [rv(2, 'a')]);
      await cl.deleteDatabase(dbName);
    });

    test('a promoted conflict leaf can then advance linearly', () async {
      final db = await freshDb();
      await inject(db, 2, ['a', 'ba5e']);
      await inject(db, 2, ['b', 'ba5e']); // winner
      await db.remove(docId, rv(2, 'b')); // promotes 2-a
      expect(await winner(db), rv(2, 'a'));
      await inject(db, 3, ['c', 'a', 'ba5e']); // child of the promoted 2-a
      expect(await winner(db), rv(3, 'c'));
      expect(await conflictsOf(db), isEmpty);
      await cl.deleteDatabase(dbName);
    });

    // ── Conflict-leaf attachments (PLAN.md Phase 1 Stage 2) ─────────────────
    test('conflict-leaf attachment: getAttachment by winner vs loser rev', () async {
      final db = await freshDb();
      final winnerBytes = Uint8List.fromList(utf8.encode('winner-payload-1'));
      final loserBytes = Uint8List.fromList(utf8.encode('loser-payload-22'));
      // 2-a (loser) and 2-b (winner) are siblings, each with their own f.bin.
      await injectWithAtt(db, 2, ['a', 'ba5e'],
          attName: 'f.bin', attData: loserBytes);
      await injectWithAtt(db, 2, ['b', 'ba5e'],
          attName: 'f.bin', attData: winnerBytes);
      expect(await winner(db), rv(2, 'b'));
      expect(await db.getAttachment(docId, 'f.bin'), winnerBytes); // default
      expect(
        await db.getAttachment(docId, 'f.bin', rev: rv(2, 'b')),
        winnerBytes,
      );
      expect(
        await db.getAttachment(docId, 'f.bin', rev: rv(2, 'a')),
        loserBytes,
        reason: 'the losing leaf\'s own attachment must be retrievable',
      );
      await cl.deleteDatabase(dbName);
    });

    test('conflict-leaf attachment: get(rev:loser, attachments:true) inlines the loser body', () async {
      final db = await freshDb();
      final loserBytes = Uint8List.fromList(utf8.encode('inline-loser-bytes'));
      await injectWithAtt(db, 2, ['a', 'ba5e'],
          attName: 'f.bin', attData: loserBytes);
      await inject(db, 2, ['b', 'ba5e']); // winner without attachment
      expect(await winner(db), rv(2, 'b'));
      final leaf = await db.getRaw(docId, rev: rv(2, 'a'), attachments: true);
      final att = (leaf!['_attachments'] as Map)['f.bin'] as Map;
      expect(base64Decode(att['data'] as String), loserBytes);
      await cl.deleteDatabase(dbName);
    });

    test('conflict-leaf attachment: two leaves sharing identical bytes each return them', () async {
      final db = await freshDb();
      final shared = Uint8List.fromList(utf8.encode('shared-identical-bytes!'));
      await injectWithAtt(db, 2, ['a', 'ba5e'],
          attName: 'f.bin', attData: shared); // loser
      await injectWithAtt(db, 2, ['b', 'ba5e'],
          attName: 'f.bin', attData: shared); // winner (identical bytes)
      expect(await db.getAttachment(docId, 'f.bin', rev: rv(2, 'b')), shared);
      expect(await db.getAttachment(docId, 'f.bin', rev: rv(2, 'a')), shared);
      await cl.deleteDatabase(dbName);
    });

    test('promotion keeps the promoted conflict leaf\'s attachment', () async {
      final db = await freshDb();
      final loserBytes = Uint8List.fromList(utf8.encode('promote-me-payload'));
      await injectWithAtt(db, 2, ['a', 'ba5e'],
          attName: 'f.bin', attData: loserBytes); // loser with attachment
      await inject(db, 2, ['b', 'ba5e']); // winner without attachment
      expect(await winner(db), rv(2, 'b'));
      // Delete the winner → CouchDB promotes the surviving leaf 2-a to winner.
      await db.remove(docId, rv(2, 'b'));
      expect(await winner(db), rv(2, 'a'));
      // The promoted leaf's attachment is now the winner's and still readable.
      expect(
        await db.getAttachment(docId, 'f.bin'),
        loserBytes,
        reason: 'promotion must carry the promoted leaf\'s attachment forward',
      );
      await cl.deleteDatabase(dbName);
    });

    test('conflict-leaf attachment via the MULTIPART write path', () async {
      final db = await freshDb();
      final loserBytes = Uint8List.fromList(utf8.encode('multipart-loser-pl'));
      // winner 2-b (no attachment) then loser 2-a WITH attachment, both via the
      // multipart streaming write path (the real replication path).
      await injectMultipart(db, [
        (start: 2, idTags: ['b', 'ba5e']),
      ]);
      await injectMultipartWithAtt(db, 2, ['a', 'ba5e'],
          attName: 'm.bin', attData: loserBytes);
      expect(await winner(db), rv(2, 'b'));
      expect(
        await db.getAttachment(docId, 'm.bin', rev: rv(2, 'a')),
        loserBytes,
        reason: 'the losing leaf\'s streamed attachment must be retrievable',
      );
      final leaf = await db.getRaw(docId, rev: rv(2, 'a'), attachments: true);
      final att = (leaf!['_attachments'] as Map)['m.bin'] as Map;
      expect(base64Decode(att['data'] as String), loserBytes);
      await cl.deleteDatabase(dbName);
    });

    test('conflict-leaf attachment: get(rev:loser) without attachments → stub', () async {
      final db = await freshDb();
      final loserBytes = Uint8List.fromList(utf8.encode('stub-parity-bytes'));
      await injectWithAtt(db, 2, ['a', 'ba5e'],
          attName: 'f.bin', attData: loserBytes);
      await inject(db, 2, ['b', 'ba5e']); // winner
      final leaf = await db.getRaw(docId, rev: rv(2, 'a')); // no attachments:true
      final att = (leaf!['_attachments'] as Map)['f.bin'] as Map;
      expect(
        att.containsKey('data'),
        isFalse,
        reason: 'without attachments:true the leaf attachment must be a stub',
      );
      expect(att['stub'], isTrue);
      expect(att['length'], loserBytes.length);
      await cl.deleteDatabase(dbName);
    });

    test('getAttachment with an unknown rev returns null (Http parity)', () async {
      final db = await freshDb();
      await injectWithAtt(db, 2, ['a', 'ba5e'],
          attName: 'f.bin', attData: Uint8List.fromList([1, 2, 3]));
      await inject(db, 2, ['b', 'ba5e']);
      expect(
        await db.getAttachment(docId, 'f.bin', rev: rv(9, 'deadbeef')),
        isNull,
        reason: 'an unknown rev must yield null (CouchDB 404), not throw',
      );
      await cl.deleteDatabase(dbName);
    });
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

  // Updating a design document's map function mid-session must change
  // subsequent query results. CouchDB (HTTP) rebuilds the view on the new view
  // signature; the Local engine rebuilds via
  // _checkViewsAfterDesignDocumentChange -> ViewMgr.reconcileDesignDocViews,
  // which invalidates the cached view so the next getView re-indexes with the
  // new map. Runs for both engines, so it also asserts HTTP↔Local parity.
  test('design document map change is reflected in queries', () async {
    final dbName = 'testdb_mapupdate';
    final db = await cl.createDatabase(dbName);

    // a single document the view will index
    await db.put(CouchDocumentBase(id: 'doc1', unmappedProps: {'value': 5}));

    // version 1 of the design doc: map emits key 'A'
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

    // build the index with map version 1 (pins the map on the Local engine)
    final before = (await db.query('md/v'))!;
    expect(before.rows, hasLength(1));
    expect(before.rows[0].key, 'A');

    // update the design doc: same view name, map now emits key 'B'
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
    );

    // The query must reflect the updated map (key 'B'): HTTP rebuilds on the
    // new signature, Local rebuilds via reconcileDesignDocViews.
    final after = (await db.query('md/v'))!;
    expect(after.rows, hasLength(1));
    expect(
      after.rows[0].key,
      'B',
      reason: 'view should reflect the updated map function',
    );

    await cl.deleteDatabase(dbName);
  });

  // Same as above, but the design document is written via bulkDocs — the path
  // used by replication. The lazy getView rebuild must cover bulk writes too,
  // otherwise a view-definition change synced from the remote would not take
  // effect locally. Runs for both engines (parity).
  test('design document map change via bulkDocs is reflected in queries', () async {
    final dbName = 'testdb_mapupdate_bulk';
    final db = await cl.createDatabase(dbName);

    await db.put(CouchDocumentBase(id: 'doc1', unmappedProps: {'value': 5}));

    // write the design doc (map emits 'A') via bulkDocs
    final r1 = await db.bulkDocs([
      DesignDocument(
        id: '_design/mdb',
        views: {
          'v': ViewData(
            map: "function(doc){ if(doc.value) emit('A', doc.value); }",
          ),
        },
      ),
    ]);
    expect(r1, hasLength(1));
    expect(r1[0].ok, isTrue);

    final before = (await db.query('mdb/v'))!;
    expect(before.rows, hasLength(1));
    expect(before.rows[0].key, 'A');

    // update the design doc (map now emits 'B') via bulkDocs, reusing the rev
    final r2 = await db.bulkDocs([
      DesignDocument(
        id: '_design/mdb',
        rev: r1[0].rev,
        views: {
          'v': ViewData(
            map: "function(doc){ if(doc.value) emit('B', doc.value); }",
          ),
        },
      ),
    ]);
    expect(r2, hasLength(1));
    expect(r2[0].ok, isTrue);

    final after = (await db.query('mdb/v'))!;
    expect(after.rows, hasLength(1));
    expect(after.rows[0].key, 'B');

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

  // The _view changes filter (filter=_view) runs the view's map function over
  // each candidate document; a change is emitted only if the map emits ≥1 row.
  // These tests run for both HTTP and Local, so they also assert parity.
  // NOTE: they intentionally never mutate the design document mid-session,
  // because map-definition changes do not propagate live within a session
  // (see _checkViewsAfterDesignDocumentChange) — that is a separate concern.
  group('changes filter=_view', () {
    test('emits only documents the view map matches (normal feed)', () async {
      final dbName = 'testdb_viewfilter';
      final db = await cl.createDatabase(dbName);

      await createView(db); // view1 emits iff doc.date && doc.title
      final matching = await createViewDocuments(db); // 3 docs, all match

      // a document that does NOT satisfy the map (no date/title)
      await db.put(
        CouchDocumentBase(id: 'no-match', unmappedProps: {'foo': 'bar'}),
      );

      final filtered = (await db
              .changes(filter: ChangesFilter.view, view: 'viewtest/view1')
              .first)
          .normal!;
      final ids = filtered.results.map((r) => r.id).toSet();

      // every matching document is reported ...
      for (final d in matching) {
        expect(ids, contains(d.id));
      }
      // ... the non-matching doc and the design document are filtered out
      expect(ids, isNot(contains('no-match')));
      expect(ids, isNot(contains('_design/viewtest')));

      await cl.deleteDatabase(dbName);
    });

    test('includeDocs returns bodies for matching documents', () async {
      final dbName = 'testdb_viewfilter_docs';
      final db = await cl.createDatabase(dbName);

      await createView(db);
      await createViewDocuments(db);

      final res = (await db
              .changes(
                filter: ChangesFilter.view,
                view: 'viewtest/view1',
                includeDocs: true,
              )
              .first)
          .normal!;
      expect(res.results, isNotEmpty);
      for (final r in res.results) {
        expect(r.doc, isNotNull);
        expect(r.doc!.unmappedProps['title'], isNotNull);
      }

      await cl.deleteDatabase(dbName);
    });

    test('excludes deletions of matching documents (tombstone emits '
        'nothing)', () async {
      final dbName = 'testdb_viewfilter_del';
      final db = await cl.createDatabase(dbName);

      await createView(db);
      final docs = await createViewDocuments(db);
      final target = docs.firstWhere((d) => d.id == 'biking');

      // sanity: before deletion the document passes the filter
      final before = (await db
              .changes(filter: ChangesFilter.view, view: 'viewtest/view1')
              .first)
          .normal!;
      expect(before.results.map((r) => r.id), contains('biking'));

      await db.remove(target.id!, target.rev!);

      // After deletion the tombstone no longer emits, so it drops out of the
      // filtered feed (matches CouchDB; documented filter=_view caveat).
      final after = (await db
              .changes(filter: ChangesFilter.view, view: 'viewtest/view1')
              .first)
          .normal!;
      expect(after.results.map((r) => r.id), isNot(contains('biking')));
      // the other matching documents remain
      expect(after.results.map((r) => r.id), contains('bought-a-cat'));

      await cl.deleteDatabase(dbName);
    });

    test('continuous feed emits only matching documents', () async {
      final dbName = 'testdb_viewfilter_cont';
      final db = await cl.createDatabase(dbName);
      await createView(db);

      final received = <String>[];
      final gotM2 = Completer<void>();
      late StreamSubscription sub;
      sub = db
          .changes(
            feedmode: FeedMode.continuous,
            filter: ChangesFilter.view,
            view: 'viewtest/view1',
          )
          .listen(
            (ch) {
              final id = ch.continuous?.id;
              if (id == null) return;
              received.add(id);
              if (id == 'm2' && !gotM2.isCompleted) gotM2.complete();
            },
            onError: (e, s) {
              if (!gotM2.isCompleted) gotM2.completeError(e, s);
            },
          );

      // matching, non-matching, matching — written in seq order so that once
      // m2 arrives we know n1's sequence was already processed (and filtered).
      await db.put(
        CouchDocumentBase(
          id: 'm1',
          unmappedProps: {'date': '2009/01/01', 'title': 'A'},
        ),
      );
      await db.put(
        CouchDocumentBase(id: 'n1', unmappedProps: {'foo': 'bar'}),
      );
      await db.put(
        CouchDocumentBase(
          id: 'm2',
          unmappedProps: {'date': '2009/01/02', 'title': 'B'},
        ),
      );

      await gotM2.future.timeout(const Duration(seconds: 10));

      expect(received, contains('m1'));
      expect(received, contains('m2'));
      expect(received, isNot(contains('n1')));
      expect(received, isNot(contains('_design/viewtest')));

      await sub.cancel();
      await cl.deleteDatabase(dbName);
    });
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

  test('views and keys', () async {
    final dbName = 'testdb1';
    final db = await cl.createDatabase(dbName);

    // prepare test data
    await db.put(
      DesignDocument(
        id: '_design/d',
        views: {
          'byGroup': ViewData(
            map: "function(doc) { if (doc.group) emit(doc.group, null); }",
          ),
        },
      ),
    );
    await db.putRaw({'_id': 'a', 'group': 'g-X'});
    await db.putRaw({'_id': 'b', 'group': 'g-X'});
    await db.putRaw({'_id': 'c', 'group': 'g-Y'});

    // unfiltered query indexes all rows (sanity)
    {
      final all = await db.query('d/byGroup');
      expect(all!.rows, hasLength(3));
    }

    // single-string key filter returns the matching rows
    {
      final hit = await db.query('d/byGroup', key: '"g-X"');
      expect(hit!.rows.map((r) => r.id), containsAll(['a', 'b']));
      expect(hit.rows, hasLength(2));
    }

    // 'multi-key with the same string works (control)'
    {
      final hit = await db.query('d/byGroup', keys: ['"g-X"']);
      expect(hit!.rows.map((r) => r.id), containsAll(['a', 'b']));
    }

    // list-wrapping the same key works (control)
    {
      // Control: wrapping the key in a 1-element list uses the jsonEncode
      // branch and matches correctly.
      await db.put(
        DesignDocument(
          id: '_design/d2',
          views: {
            'byGroupList': ViewData(
              map: "function(doc) { if (doc.group) emit([doc.group], null); }",
            ),
          },
        ),
      );
      final hit = await db.query('d2/byGroupList', key: '["g-X"]');
      expect(hit!.rows, hasLength(2));
    }

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
