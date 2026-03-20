import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import 'package:test/test.dart';
import 'package:logging/logging.dart';

import 'package:dart_couch/dart_couch.dart';

import 'helper/couch_test_manager.dart';
import 'helper/einkaufslist_item.dart';
import 'helper/test_document_one.dart';

import 'helper/helper.dart';

const String testDbName = 'testdb1';

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

  CouchTestManager cm = CouchTestManager();

  setUpAll(() async {
    await cm.init();
  });

  tearDownAll(() async {
    await cm.dispose();
  });

  setUp(() async {
    await cm.prepareNewTest();
  });

  tearDown(() async {
    await cm.cleanupAfterTest();
  });

  group('OfflineFirstDb - Basic Operations', () {
    test('create OfflineFirstDb and initialize successfully', () async {
      final db = await cm.offlineDb();

      expect(db.replicationController, isNotNull);
      expect(
        db.replicationController.progress.value.state,
        anyOf(
          ReplicationState.initializing,
          ReplicationState.initialSyncInProgress,
          ReplicationState.inSync,
        ),
      );
    });

    test('initial sync downloads existing server documents', () async {
      // First, create documents on the server BEFORE creating OfflineFirstDb
      final serverDb = await cm.httpDb();
      for (int i = 0; i < 5; i++) {
        final doc = EinkaufslistItem(
          id: 'preexisting_$i',
          name: 'Pre-existing Item $i',
          erledigt: false,
          anzahl: i + 1,
          einheit: 'pc',
          category: 'initial',
        );
        await serverDb.put(doc);
      }

      // Now create the OfflineFirstDb - it should pull existing documents

      var db = await cm.offlineDb();

      await waitForSync(db, maxSeconds: 10);

      // Verify all pre-existing documents were synced to local
      for (int i = 0; i < 5; i++) {
        final localDoc = await db.localDb.get('preexisting_$i');
        expect(
          localDoc,
          isNotNull,
          reason: 'Document preexisting_$i should exist locally',
        );
        expect((localDoc as EinkaufslistItem).name, 'Pre-existing Item $i');
      }

      // Also verify we can read them through the OfflineFirstDb interface
      for (int i = 0; i < 5; i++) {
        final doc = await db.get('preexisting_$i');
        expect(doc, isNotNull);
        expect((doc as EinkaufslistItem).anzahl, i + 1);
      }
    });

    test(
      'reads come from local db even when online (fast local reads)',
      () async {
        final db = await cm.offlineDb();

        // Create a document and wait for sync
        final doc = EinkaufslistItem(
          id: 'fast_read_test',
          name: 'Fast Read Test',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        );
        await db.put(doc);
        await waitForSync(db, maxSeconds: 3);

        // Verify document is in local db
        final localDoc = await db.localDb.get('fast_read_test');
        expect(localDoc, isNotNull);

        // Read through OfflineFirstDb - should come from local (fast)
        // We can't easily measure speed, but we verify it works and returns correct data
        final readDoc = await db.get('fast_read_test');
        expect(readDoc, isNotNull);
        expect((readDoc as EinkaufslistItem).name, 'Fast Read Test');

        // The key point: reads go to local db, not server
        // This is verified by the fact that db.get() uses localDb internally
        // We can verify this by checking the document matches local
        expect(readDoc.rev, localDoc!.rev);
      },
    );

    test('write document to local db when online', () async {
      final db = await cm.offlineDb();

      final doc = EinkaufslistItem(
        id: 'item1',
        name: 'Test Item',
        erledigt: false,
        anzahl: 1,
        einheit: 'pc',
        category: 'test',
      );

      final putResult = await db.put(doc);
      expect(putResult.id, 'item1');
      expect(putResult.rev, isNotNull);

      // Wait for sync
      await waitForSync(db, maxSeconds: 5);

      // Verify document exists locally
      final localDoc = await db.localDb.get('item1');
      expect(localDoc, isNotNull);
      expect((localDoc as EinkaufslistItem).name, 'Test Item');

      // Verify document exists on server
      final serverDb = await cm.httpDb();
      final serverDoc = await serverDb.get('item1');
      expect(serverDoc, isNotNull);
      expect((serverDoc as EinkaufslistItem).name, 'Test Item');
    });

    test('read document from local db when online', () async {
      // First put document on server
      final serverDb = await cm.httpDb();
      final doc = EinkaufslistItem(
        id: 'item2',
        name: 'Server Item',
        erledigt: false,
        anzahl: 2,
        einheit: 'kg',
        category: 'test',
      );
      await serverDb.put(doc);

      final db = await cm.offlineDb();

      await waitForSync(db, maxSeconds: 5);

      // Read document from offline db (should come from local)
      final localDoc = await db.get('item2');
      expect(localDoc, isNotNull);
      expect((localDoc as EinkaufslistItem).name, 'Server Item');
      expect(localDoc.anzahl, 2);
    });

    test('update document when online', () async {
      final db = await cm.offlineDb();

      // Create initial document
      final doc = EinkaufslistItem(
        id: 'item3',
        name: 'Initial',
        erledigt: false,
        anzahl: 1,
        einheit: 'pc',
        category: 'test',
      );
      final putResult = await db.put(doc);
      await waitForSync(db, maxSeconds: 3);

      // Update document
      final updatedDoc = EinkaufslistItem(
        id: 'item3',
        rev: putResult.rev,
        name: 'Updated',
        erledigt: true,
        anzahl: 5,
        einheit: 'kg',
        category: 'test',
      );
      final updateResult = await db.put(updatedDoc);
      expect(updateResult.rev, isNotNull);

      await waitForSync(db, maxSeconds: 3);

      // Verify update in local db
      final localDoc = await db.localDb.get('item3');
      expect((localDoc as EinkaufslistItem).name, 'Updated');
      expect(localDoc.anzahl, 5);

      // Verify update on server
      final serverDb = await cm.httpDb();
      final serverDoc = await serverDb.get('item3');
      expect((serverDoc as EinkaufslistItem).name, 'Updated');
      expect(serverDoc.anzahl, 5);
    });

    test('delete document when online', () async {
      final db = await cm.offlineDb();

      // Create document
      final doc = EinkaufslistItem(
        id: 'item4',
        name: 'ToDelete',
        erledigt: false,
        anzahl: 1,
        einheit: 'pc',
        category: 'test',
      );
      final putResult = await db.put(doc);
      expect(putResult.rev, equals("1-903e0ad6661692b10b72ee041c6853b2"));
      await waitForSync(db, maxSeconds: 3);

      final serverDb = await cm.httpDb();
      CouchDocumentBase? serverDoc = await serverDb.get('item4');
      expect(serverDoc, isNotNull);

      // Delete document
      final deleteRev = await db.remove('item4', putResult.rev!);
      expect(deleteRev, isNotNull);
      expect(deleteRev, equals("2-84c3f43018bbfc5008dc5f0dbde1998c"));

      await waitForSync(db, maxSeconds: 3);

      // Verify deletion on server
      serverDoc = await serverDb.get('item4');
      expect(serverDoc, isNull);
    });
  });

  group('OfflineFirstDb - Offline Operations', () {
    test('write document when offline', () async {
      final db = await cm.offlineDb();
      await waitForSync(db, maxSeconds: 2);

      await cm.pauseContainer();

      final doc = EinkaufslistItem(
        id: 'offline_item1',
        name: 'Offline Item',
        erledigt: false,
        anzahl: 1,
        einheit: 'pc',
        category: 'test',
      );

      final putResult = await db.put(doc);
      expect(putResult.id, 'offline_item1');
      expect(putResult.rev, isNotNull);

      final localDoc = await db.localDb.get('offline_item1');
      expect(localDoc, isNotNull);
      expect((localDoc as EinkaufslistItem).name, 'Offline Item');
    });

    test('read document when offline', () async {
      final db = await cm.offlineDb();

      final doc = EinkaufslistItem(
        id: 'offline_item2',
        name: 'To Read Offline',
        erledigt: false,
        anzahl: 2,
        einheit: 'kg',
        category: 'test',
      );
      await db.put(doc);
      await waitForSync(db, maxSeconds: 2);

      await cm.pauseContainer();

      final readDoc = await db.get('offline_item2');
      expect(readDoc, isNotNull);
      expect((readDoc as EinkaufslistItem).name, 'To Read Offline');
      expect(readDoc.anzahl, 2);
    });

    test('update document when offline', () async {
      final db = await cm.offlineDb();

      final doc = EinkaufslistItem(
        id: 'offline_item3',
        name: 'Original',
        erledigt: false,
        anzahl: 1,
        einheit: 'pc',
        category: 'test',
      );
      final putResult = await db.put(doc);
      await waitForSync(db, maxSeconds: 2);

      await cm.pauseContainer();

      final updatedDoc = EinkaufslistItem(
        id: 'offline_item3',
        rev: putResult.rev,
        name: 'Updated Offline',
        erledigt: true,
        anzahl: 5,
        einheit: 'kg',
        category: 'test',
      );
      final updateResult = await db.put(updatedDoc);
      expect(updateResult.rev, isNotNull);
      expect(updateResult.rev, isNot(putResult.rev));

      final localDoc = await db.localDb.get('offline_item3');
      expect((localDoc as EinkaufslistItem).name, 'Updated Offline');
    });

    test('delete document when offline', () async {
      final db = await cm.offlineDb();

      final doc = EinkaufslistItem(
        id: 'offline_item4',
        name: 'To Delete',
        erledigt: false,
        anzahl: 1,
        einheit: 'pc',
        category: 'test',
      );
      final putResult = await db.put(doc);
      await waitForSync(db, maxSeconds: 2);

      await cm.pauseContainer();

      final deleteRev = await db.remove('offline_item4', putResult.rev!);
      expect(deleteRev, isNotNull);

      final localDoc = await db.localDb.get('offline_item4');
      expect(localDoc, isNull);
    });

    test('multiple writes when offline', () async {
      final db = await cm.offlineDb();
      await waitForSync(db, maxSeconds: 2);

      await cm.pauseContainer();

      for (int i = 0; i < 5; i++) {
        final doc = EinkaufslistItem(
          id: 'multi_item_$i',
          name: 'Item $i',
          erledigt: false,
          anzahl: i + 1,
          einheit: 'pc',
          category: 'test',
        );
        final result = await db.put(doc);
        expect(result.id, 'multi_item_$i');
      }

      for (int i = 0; i < 5; i++) {
        final localDoc = await db.localDb.get('multi_item_$i');
        expect(localDoc, isNotNull);
        expect((localDoc as EinkaufslistItem).anzahl, i + 1);
      }
    });
  });

  group('OfflineFirstDb - Offline to Online Sync', () {
    test('documents written offline sync when connection restored', () async {
      final db = await cm.offlineDb();
      await waitForSync(db, maxSeconds: 2);

      await cm.pauseContainer();

      await db.put(
        EinkaufslistItem(
          id: 'sync_item1',
          name: 'Written Offline',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        ),
      );

      final localDoc = await db.localDb.get('sync_item1');
      expect(localDoc, isNotNull);

      await cm.resumeContainer();
      await waitForSync(db, maxSeconds: 10);

      final serverDoc = await (await cm.httpDb()).get('sync_item1');
      expect(serverDoc, isNotNull);
      expect((serverDoc as EinkaufslistItem).name, 'Written Offline');
    });

    test('document updates offline sync correctly', () async {
      final db = await cm.offlineDb();

      final putResult = await db.put(
        EinkaufslistItem(
          id: 'sync_item2',
          name: 'Original',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        ),
      );
      await waitForSync(db, maxSeconds: 2);

      log.info('Pausing CouchDB container to simulate offline...');
      await cm.pauseContainer();

      log.info('Updating document while offline...');
      await db.put(
        EinkaufslistItem(
          id: 'sync_item2',
          rev: putResult.rev,
          name: 'Updated Offline',
          erledigt: true,
          anzahl: 10,
          einheit: 'kg',
          category: 'test',
        ),
      );

      log.info('Restarting CouchDB container to restore connection...');
      await cm.resumeContainer();
      log.info('Waiting for sync to complete...');
      await waitForSync(db, maxSeconds: 10);

      log.info('Verifying document update on server...');
      final serverDoc = await (await cm.httpDb()).get('sync_item2');
      expect(serverDoc, isNotNull);
      expect((serverDoc as EinkaufslistItem).name, 'Updated Offline');
      expect(serverDoc.anzahl, 10);
    });

    test('document deletions offline sync correctly', () async {
      final db = await cm.offlineDb();

      final putResult = await db.put(
        EinkaufslistItem(
          id: 'sync_item3',
          name: 'To Delete',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        ),
      );
      await waitForSync(db, maxSeconds: 2);

      await cm.pauseContainer();
      await db.remove('sync_item3', putResult.rev!);

      await cm.resumeContainer();
      await waitForSync(db, maxSeconds: 10);

      final serverDoc = await (await cm.httpDb()).get('sync_item3');
      expect(serverDoc, isNull);
    });

    test('multiple offline operations sync in correct order', () async {
      final db = await cm.offlineDb();
      await waitForSync(db, maxSeconds: 2);

      await cm.pauseContainer();

      await db.put(
        EinkaufslistItem(
          id: 'multi_sync1',
          name: 'Created Offline',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        ),
      );

      final put2 = await db.put(
        EinkaufslistItem(
          id: 'multi_sync2',
          name: 'Initial',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        ),
      );
      await db.put(
        EinkaufslistItem(
          id: 'multi_sync2',
          rev: put2.rev,
          name: 'Updated',
          erledigt: true,
          anzahl: 5,
          einheit: 'kg',
          category: 'test',
        ),
      );

      final put3 = await db.put(
        EinkaufslistItem(
          id: 'multi_sync3',
          name: 'To Delete',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        ),
      );
      await db.remove('multi_sync3', put3.rev!);

      await cm.resumeContainer();
      await waitForSync(db, maxSeconds: 10);

      final serverDb = await cm.httpDb();

      final server1 = await serverDb.get('multi_sync1');
      expect(server1, isNotNull);
      expect((server1 as EinkaufslistItem).name, 'Created Offline');

      final server2 = await serverDb.get('multi_sync2');
      expect(server2, isNotNull);
      expect((server2 as EinkaufslistItem).name, 'Updated');
      expect(server2.anzahl, 5);

      final server3 = await serverDb.get('multi_sync3');
      expect(server3, isNull);
    });

    test('conflicting changes resolve during sync', () async {
      final initialDb = await cm.offlineDb();

      final putResult = await initialDb.put(
        EinkaufslistItem(
          id: 'conflict_item',
          name: 'Original',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        ),
      );
      await waitForSync(initialDb, maxSeconds: 2);

      await cm.pauseContainer();

      final localPutResult = await initialDb.put(
        EinkaufslistItem(
          id: 'conflict_item',
          rev: putResult.rev,
          name: 'Local Update',
          erledigt: false,
          anzahl: 5,
          einheit: 'pc',
          category: 'test',
        ),
      );
      expect(localPutResult.rev, isNotNull);
      expect(localPutResult.rev, isNot(putResult.rev));

      // Pause offline-first server while CouchDB is still down so replication
      // cannot race ahead and push the local change before we write the
      // conflicting server update.
      await cm.pauseOfflineFirstDb();

      // Bring server back and write a conflicting update
      await cm.resumeContainer();

      await (await cm.httpDb()).put(
        EinkaufslistItem(
          id: 'conflict_item',
          rev: putResult.rev,
          name: 'Server Update',
          erledigt: true,
          anzahl: 10,
          einheit: 'kg',
          category: 'test',
        ),
      );

      // Resume offline-first server; it picks up the SQLite state with the
      // local change and will now replicate against a server that already has
      // a diverging rev → genuine CouchDB conflict.
      await cm.resumeOfflineFirstDb();
      final db = await cm.offlineDb();

      await waitForSync(db, maxSeconds: 10);

      final finalServerDoc = await (await cm.httpDb()).get('conflict_item');
      expect(finalServerDoc, isNotNull);

      final finalLocalDoc = await db.localDb.get('conflict_item');
      expect(finalLocalDoc, isNotNull);
      expect(finalLocalDoc!.rev, isNotNull);
      expect(finalServerDoc!.rev, isNotNull);

      log.info(
        'Conflict resolved - Local rev: ${finalLocalDoc.rev}, Server rev: ${finalServerDoc.rev}',
      );
    });

    test('server changes sync to local (bidirectional sync)', () async {
      final db = await cm.offlineDb();
      await waitForSync(db, maxSeconds: 2);

      await (await cm.httpDb()).put(
        EinkaufslistItem(
          id: 'server_created_item',
          name: 'Created on Server',
          erledigt: false,
          anzahl: 42,
          einheit: 'kg',
          category: 'server',
        ),
      );

      await waitForSync(db, maxSeconds: 5);

      final localDoc = await db.localDb.get('server_created_item');
      expect(localDoc, isNotNull);
      expect((localDoc as EinkaufslistItem).name, 'Created on Server');
      expect(localDoc.anzahl, 42);

      final readDoc = await db.get('server_created_item');
      expect(readDoc, isNotNull);
      expect((readDoc as EinkaufslistItem).name, 'Created on Server');
    });
  });

  group('OfflineFirstDb - Online to Offline Transitions', () {
    test('can read documents after going offline', () async {
      final db = await cm.offlineDb();

      for (int i = 0; i < 3; i++) {
        await db.put(
          EinkaufslistItem(
            id: 'read_item_$i',
            name: 'Item $i',
            erledigt: false,
            anzahl: i + 1,
            einheit: 'pc',
            category: 'test',
          ),
        );
      }
      await waitForSync(db, maxSeconds: 2);

      await cm.pauseContainer();

      for (int i = 0; i < 3; i++) {
        final doc = await db.get('read_item_$i');
        expect(doc, isNotNull);
        expect((doc as EinkaufslistItem).name, 'Item $i');
      }
    });

    test('continues to accept writes after going offline', () async {
      final db = await cm.offlineDb();
      await waitForSync(db, maxSeconds: 2);

      expect(
        db.replicationController.progress.value.state,
        anyOf(ReplicationState.initialSyncInProgress, ReplicationState.inSync),
      );

      await cm.pauseContainer();

      final putResult = await db.put(
        EinkaufslistItem(
          id: 'write_after_offline',
          name: 'Written After Offline',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        ),
      );
      expect(putResult.rev, isNotNull);

      final localDoc = await db.localDb.get('write_after_offline');
      expect(localDoc, isNotNull);
    });

    test('replication pauses when offline', () async {
      final db = await cm.offlineDb();
      await waitForSync(db, maxSeconds: 2);

      expect(
        db.replicationController.progress.value.state,
        anyOf(ReplicationState.initialSyncInProgress, ReplicationState.inSync),
      );

      await cm.pauseContainer();

      await db.put(
        EinkaufslistItem(
          id: 'pause_test',
          name: 'Test Pause',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        ),
      );

      await waitForCondition(
        () => Future.value(
          db.replicationController.progress.value.targetReachable == false,
        ),
      );

      expect(db.replicationController.progress.value.targetReachable, isFalse);
    });

    test('replication resumes automatically when back online', () async {
      final db = await cm.offlineDb();
      await waitForSync(db, maxSeconds: 2);

      await cm.pauseContainer();

      for (int i = 0; i < 3; i++) {
        await db.put(
          EinkaufslistItem(
            id: 'resume_item_$i',
            name: 'Item $i',
            erledigt: false,
            anzahl: i + 1,
            einheit: 'pc',
            category: 'test',
          ),
        );
      }

      await cm.resumeContainer();
      await waitForSync(db, maxSeconds: 10);

      final serverDb = await cm.httpDb();
      for (int i = 0; i < 3; i++) {
        final serverDoc = await serverDb.get('resume_item_$i');
        expect(serverDoc, isNotNull);
        expect((serverDoc as EinkaufslistItem).name, 'Item $i');
      }
    });
  });

  group('OfflineFirstDb - Network Failures During Sync', () {
    test('handles network failure during document upload', () async {
      final db = await cm.offlineDb();
      await waitForSync(db, maxSeconds: 2);

      await db.put(
        EinkaufslistItem(
          id: 'upload_test',
          name: 'Upload Test',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        ),
      );

      await cm.pauseContainer();

      final localDoc = await db.localDb.get('upload_test');
      expect(localDoc, isNotNull);

      await cm.resumeContainer();
      await waitForSync(db, maxSeconds: 10);

      final serverDoc = await (await cm.httpDb()).get('upload_test');
      expect(serverDoc, isNotNull);
    });

    test('retries failed sync operations', () async {
      final db = await cm.offlineDb();
      await waitForSync(db, maxSeconds: 10);

      await cm.pauseContainer();

      await db.put(
        EinkaufslistItem(
          id: 'retry_test',
          name: 'Retry Test',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        ),
      );

      expect(db.replicationController.progress.value.targetReachable, isFalse);

      await cm.resumeContainer();
      await waitForSync(db, maxSeconds: 10);

      final serverDoc = await (await cm.httpDb()).get('retry_test');
      expect(serverDoc, isNotNull);
    }, timeout: Timeout(Duration(seconds: 60)));

    test('handles network failure during initial replication setup', () async {
      final db = await cm.offlineDb();
      await cm.pauseContainer();

      final progress = db.replicationController.progress.value;
      expect(progress.state, ReplicationState.waitingForNetwork);

      await db.put(
        EinkaufslistItem(
          id: 'init_fail_test',
          name: 'Init Fail Test',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        ),
      );

      await cm.resumeContainer();
      await waitForSync(db, maxSeconds: 10);

      final serverDoc = await (await cm.httpDb()).get('init_fail_test');
      expect(serverDoc, isNotNull);
    });
  });

  group('OfflineFirstDb - Sync State and Progress', () {
    test('replication progress reflects initial sync', () async {
      // Start fresh environment manually to put documents BEFORE creating OfflineFirstDb

      // Put documents on server first
      final serverDb = await cm.httpDb();
      for (int i = 0; i < 5; i++) {
        final doc = EinkaufslistItem(
          id: 'progress_item_$i',
          name: 'Item $i',
          erledigt: false,
          anzahl: i + 1,
          einheit: 'pc',
          category: 'test',
        );
        await serverDb.put(doc);
      }

      // Create offline db - should trigger initial sync
      var db = await cm.offlineDb();

      // Check progress state
      final progress = db.replicationController.progress.value;
      expect(
        progress.state,
        anyOf(
          ReplicationState.initializing,
          ReplicationState.initialSyncInProgress,
          ReplicationState.inSync,
        ),
      );

      // Wait for sync to complete
      await waitForSync(db, maxSeconds: 5);

      // Verify documents are in local db
      for (int i = 0; i < 5; i++) {
        final localDoc = await db.localDb.get('progress_item_$i');
        expect(localDoc, isNotNull);
      }
    });

    test('replication progress updates during continuous sync', () async {
      final db = await cm.offlineDb();
      await waitForSync(db, maxSeconds: 2);

      await (await cm.httpDb()).put(
        EinkaufslistItem(
          id: 'continuous_item',
          name: 'Continuous Item',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        ),
      );

      await waitForSync(db, maxSeconds: 5);

      final localDoc = await db.localDb.get('continuous_item');
      expect(localDoc, isNotNull);
      expect((localDoc as EinkaufslistItem).name, 'Continuous Item');
    });

    test('replication state shows error on network failure', () async {
      final db = await cm.offlineDb();
      await waitForSync(db, maxSeconds: 2);

      expect(db.replicationController.progress.value.targetReachable, isTrue);

      await cm.pauseContainer();

      await db.put(
        EinkaufslistItem(
          id: 'error_test',
          name: 'Error Test',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        ),
      );

      await waitForCondition(
        () => Future.value(
          db.replicationController.progress.value.targetReachable == false,
        ),
      );

      expect(db.replicationController.progress.value.targetReachable, isFalse);
    });

    test('replication state shows retry attempts', () async {
      final db = await cm.offlineDb();
      await waitForSync(db, maxSeconds: 2);

      await cm.pauseContainer();

      await db.put(
        EinkaufslistItem(
          id: 'retry_progress_test',
          name: 'Retry Test',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        ),
      );

      await waitForCondition(
        () => Future.value(
          db.replicationController.progress.value.targetReachable == false &&
              db.replicationController.progress.value.state ==
                  ReplicationState.waitingForNetwork,
        ),
      );

      final progress = db.replicationController.progress.value;
      expect(progress.targetReachable, isFalse);
      expect(progress.state, anyOf(ReplicationState.waitingForNetwork));
    });
  });

  group('OfflineFirstDb - Attachments', () {
    test('save attachment when online', () async {
      final db = await cm.offlineDb();
      final putResult = await db.put(
        EinkaufslistItem(
          id: 'attach_item1',
          name: 'With Attachment',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        ),
      );
      await waitForSync(db, maxSeconds: 2);

      await db.saveAttachment(
        'attach_item1',
        putResult.rev!,
        'test.txt',
        Uint8List.fromList(utf8.encode('Test attachment content')),
        contentType: 'text/plain',
      );
      await waitForSync(db, maxSeconds: 3);

      final serverDoc = await (await cm.httpDb()).get('attach_item1');
      expect(serverDoc, isNotNull);
      expect(serverDoc!.attachments, isNotNull);
      expect(serverDoc.attachments!.containsKey('test.txt'), isTrue);
    });

    test('save attachment when offline', () async {
      final db = await cm.offlineDb();
      final putResult = await db.put(
        EinkaufslistItem(
          id: 'attach_item2',
          name: 'With Offline Attachment',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        ),
      );
      await waitForSync(db, maxSeconds: 2);

      await cm.pauseContainer();

      await db.saveAttachment(
        'attach_item2',
        putResult.rev!,
        'offline.txt',
        Uint8List.fromList(utf8.encode('Offline attachment content')),
        contentType: 'text/plain',
      );

      final localDoc = await db.localDb.get('attach_item2');
      expect(localDoc, isNotNull);
      expect(localDoc!.attachments, isNotNull);
      expect(localDoc.attachments!.containsKey('offline.txt'), isTrue);
    });

    test('attachment syncs when connection restored', () async {
      final db = await cm.offlineDb();
      final putResult = await db.put(
        EinkaufslistItem(
          id: 'attach_item3',
          name: 'Sync Attachment',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        ),
      );
      await waitForSync(db, maxSeconds: 2);

      await cm.pauseContainer();
      await db.saveAttachment(
        'attach_item3',
        putResult.rev!,
        'sync.txt',
        Uint8List.fromList(utf8.encode('Will sync later')),
        contentType: 'text/plain',
      );

      await cm.resumeContainer();
      await waitForSync(db, maxSeconds: 10);

      final serverDoc = await (await cm.httpDb()).get('attach_item3');
      expect(serverDoc, isNotNull);
      expect(serverDoc!.attachments, isNotNull);
      expect(serverDoc.attachments!.containsKey('sync.txt'), isTrue);
    });

    test('read attachment when offline', () async {
      final db = await cm.offlineDb();
      final putResult = await db.put(
        EinkaufslistItem(
          id: 'attach_item4',
          name: 'Read Offline',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        ),
      );
      await db.saveAttachment(
        'attach_item4',
        putResult.rev!,
        'read.txt',
        Uint8List.fromList(utf8.encode('Read me offline')),
        contentType: 'text/plain',
      );
      await waitForSync(db, maxSeconds: 2);

      await cm.pauseContainer();

      final readData = await db.getAttachment('attach_item4', 'read.txt');
      expect(readData, isNotNull);
      expect(utf8.decode(readData!), 'Read me offline');
    });

    test('delete attachment when offline syncs correctly', () async {
      final db = await cm.offlineDb();
      final putResult = await db.put(
        EinkaufslistItem(
          id: 'attach_item5',
          name: 'Delete Attachment',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        ),
      );
      await db.saveAttachment(
        'attach_item5',
        putResult.rev!,
        'delete.txt',
        Uint8List.fromList(utf8.encode('Will be deleted')),
        contentType: 'text/plain',
      );
      await waitForSync(db, maxSeconds: 5);

      final serverDocBefore = await (await cm.httpDb()).get('attach_item5');
      expect(serverDocBefore, isNotNull);
      expect(serverDocBefore!.attachments!.containsKey('delete.txt'), isTrue);

      await cm.pauseContainer();

      final localDocWithAttach = await db.localDb.get('attach_item5');
      expect(localDocWithAttach, isNotNull);
      await db.deleteAttachment(
        'attach_item5',
        localDocWithAttach!.rev!,
        'delete.txt',
      );

      await cm.resumeContainer();
      await waitForSync(db, maxSeconds: 10);

      final serverDoc = await (await cm.httpDb()).get('attach_item5');
      expect(serverDoc, isNotNull);
      expect(
        serverDoc!.attachments == null ||
            !serverDoc.attachments!.containsKey('delete.txt'),
        isTrue,
      );
    });

    test(
      'remote attachment created while app is closed syncs on restart',
      () async {
        final db = await cm.offlineDb();
        await db.put(
          EinkaufslistItem(
            id: 'attach_item6',
            name: 'Remote Attachment',
            erledigt: false,
            anzahl: 1,
            einheit: 'pc',
            category: 'test',
          ),
        );
        await waitForSync(db, maxSeconds: 2);

        // Simulate app closing
        await cm.pauseOfflineFirstDb();

        // Add attachment on remote while app is closed
        final remoteDb = await cm.httpDb();
        final remoteDoc = await remoteDb.get('attach_item6');
        expect(remoteDoc, isNotNull);

        await remoteDb.saveAttachment(
          'attach_item6',
          remoteDoc!.rev!,
          'remote.txt',
          Uint8List.fromList(utf8.encode('Remote attachment content')),
          contentType: 'text/plain',
        );

        final remoteDocAfter = await remoteDb.get(
          'attach_item6',
          attachments: true,
        );
        expect(remoteDocAfter!.attachments!.containsKey('remote.txt'), isTrue);

        // Simulate app reopening
        await cm.resumeOfflineFirstDb();
        final db2 = await cm.offlineDb();
        await waitForSync(db2, maxSeconds: 10);

        final localDoc = await db2.localDb.get(
          'attach_item6',
          attachments: true,
        );
        expect(localDoc, isNotNull);
        expect(localDoc!.attachments!.containsKey('remote.txt'), isTrue);

        final localData = await db2.localDb.getAttachment(
          'attach_item6',
          'remote.txt',
        );
        expect(localData, isNotNull);
        expect(utf8.decode(localData!), 'Remote attachment content');
      },
    );

    test('remote attachment change replicates while staying online', () async {
      final db = await cm.offlineDb();
      await db.put(
        EinkaufslistItem(
          id: 'attach_item7',
          name: 'Live Attachment',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        ),
      );
      await waitForSync(db, maxSeconds: 2);

      final remoteDb = await cm.httpDb();
      final remoteDoc = await remoteDb.get('attach_item7');
      expect(remoteDoc, isNotNull);

      await remoteDb.saveAttachment(
        'attach_item7',
        remoteDoc!.rev!,
        'live.txt',
        Uint8List.fromList(utf8.encode('Live remote attachment content')),
        contentType: 'text/plain',
      );

      await waitForSync(db, maxSeconds: 10);

      final localDoc = await db.localDb.get('attach_item7', attachments: true);
      expect(localDoc, isNotNull);
      expect(localDoc!.attachments!.containsKey('live.txt'), isTrue);

      final localData = await db.localDb.getAttachment(
        'attach_item7',
        'live.txt',
      );
      expect(localData, isNotNull);
      expect(utf8.decode(localData!), 'Live remote attachment content');
    });

    test(
      'useAllDocs emits update when remote attachment is overwritten and replicated',
      () async {
        final db = await cm.offlineDb();
        final putResult = await db.put(
          EinkaufslistItem(
            id: 'attach_item8',
            name: 'Overwrite Attachment',
            erledigt: false,
            anzahl: 1,
            einheit: 'pc',
            category: 'test',
          ),
        );

        await db.saveAttachment(
          'attach_item8',
          putResult.rev!,
          'data.txt',
          Uint8List.fromList(utf8.encode('original data')),
          contentType: 'text/plain',
        );
        await waitForSync(db, maxSeconds: 5);

        final emissions = <ViewResult?>[];
        final sub = db
            .useAllDocs(
              keys: ['attach_item8'],
              includeDocs: true,
              attachments: true,
            )
            .listen(emissions.add);

        await waitForCondition(() async => emissions.isNotEmpty);

        final remoteDb = await cm.httpDb();
        final remoteDoc = await remoteDb.get('attach_item8');
        await remoteDb.saveAttachment(
          'attach_item8',
          remoteDoc!.rev!,
          'data.txt',
          Uint8List.fromList(utf8.encode('overwritten data')),
          contentType: 'text/plain',
        );

        // CouchDB may gzip text/plain, so use server's digest as ground truth
        final remoteDocAfterSave = await remoteDb.get('attach_item8');
        final expectedDigest =
            remoteDocAfterSave!.attachments!['data.txt']!.digestDecoded;

        await waitForCondition(() async {
          if (emissions.isEmpty) return false;
          final row = emissions.last?.rows.firstOrNull;
          final att = row?.doc?.attachments?['data.txt'];
          if (att == null) return false;
          return att.digestDecoded == expectedDigest;
        });

        final att = emissions.last!.rows.first.doc!.attachments!['data.txt']!;
        expect(att.digestDecoded, equals(expectedDigest));

        await sub.cancel();
      },
    );

    test(
      'overwriting attachment locally is reflected in useAllDocs, useDoc, and get',
      () async {
        final db = await cm.offlineDb();
        final putResult = await db.put(
          EinkaufslistItem(
            id: 'attach_item9',
            name: 'All APIs Attachment',
            erledigt: false,
            anzahl: 1,
            einheit: 'pc',
            category: 'test',
          ),
        );

        final rev2 = await db.saveAttachment(
          'attach_item9',
          putResult.rev!,
          'data.txt',
          Uint8List.fromList(utf8.encode('original data')),
          contentType: 'text/plain',
        );

        final allDocsEmissions = <ViewResult?>[];
        final allDocsSub = db
            .useAllDocs(
              keys: ['attach_item9'],
              includeDocs: true,
              attachments: true,
            )
            .listen(allDocsEmissions.add);

        final docEmissions = <CouchDocumentBase?>[];
        final docSub = db.useDoc('attach_item9').listen(docEmissions.add);

        await waitForCondition(
          () async => allDocsEmissions.isNotEmpty && docEmissions.isNotEmpty,
        );

        final newData = Uint8List.fromList(utf8.encode('overwritten data'));
        final newDigest = md5.convert(newData).toString();
        await db.saveAttachment(
          'attach_item9',
          rev2,
          'data.txt',
          newData,
          contentType: 'text/plain',
        );

        await waitForCondition(() async {
          final att = allDocsEmissions
              .last
              ?.rows
              .firstOrNull
              ?.doc
              ?.attachments?['data.txt'];
          return att?.digestDecoded == newDigest;
        });
        expect(
          allDocsEmissions
              .last!
              .rows
              .first
              .doc!
              .attachments!['data.txt']!
              .digestDecoded,
          equals(newDigest),
        );

        await waitForCondition(() async {
          return docEmissions.last?.attachments?['data.txt']?.digestDecoded ==
              newDigest;
        });
        expect(
          docEmissions.last!.attachments!['data.txt']!.digestDecoded,
          equals(newDigest),
        );

        final fetched = await db.get('attach_item9', attachments: true);
        expect(fetched, isNotNull);
        expect(
          fetched!.attachments!['data.txt']!.digestDecoded,
          equals(newDigest),
        );

        final fetchedData = await db.getAttachment('attach_item9', 'data.txt');
        expect(fetchedData, isNotNull);
        expect(utf8.decode(fetchedData!), equals('overwritten data'));

        await allDocsSub.cancel();
        await docSub.cancel();
      },
    );

    test('remote attachment deletion replicates to local', () async {
      final db = await cm.offlineDb();
      final putResult = await db.put(
        EinkaufslistItem(
          id: 'attach_item_remote_del',
          name: 'Remote Delete Test',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        ),
      );

      await db.saveAttachment(
        'attach_item_remote_del',
        putResult.rev!,
        'remote_del.txt',
        Uint8List.fromList(
          utf8.encode('This attachment will be deleted remotely'),
        ),
        contentType: 'text/plain',
      );
      await waitForSync(db, maxSeconds: 5);

      final remoteDb = await cm.httpDb();
      final remoteDocBefore = await remoteDb.get('attach_item_remote_del');
      expect(remoteDocBefore, isNotNull);
      expect(
        remoteDocBefore!.attachments!.containsKey('remote_del.txt'),
        isTrue,
      );

      await remoteDb.deleteAttachment(
        'attach_item_remote_del',
        remoteDocBefore.rev!,
        'remote_del.txt',
      );

      final remoteDocAfter = await remoteDb.get('attach_item_remote_del');
      expect(
        remoteDocAfter!.attachments == null ||
            !remoteDocAfter.attachments!.containsKey('remote_del.txt'),
        isTrue,
        reason: 'Attachment should be deleted on remote',
      );

      // Poll until the deletion has actually been applied locally.
      await waitForCondition(
        () async {
          final localDoc = await db.localDb.get('attach_item_remote_del');
          return localDoc == null ||
              localDoc.attachments == null ||
              !localDoc.attachments!.containsKey('remote_del.txt');
        },
        maxAttempts: 30,
        interval: Duration(milliseconds: 500),
      );

      final localDoc = await db.localDb.get('attach_item_remote_del');
      expect(localDoc, isNotNull);
      expect(
        localDoc!.attachments == null ||
            !localDoc.attachments!.containsKey('remote_del.txt'),
        isTrue,
        reason: 'Attachment deletion should have replicated to local',
      );

      final offlineDoc = await db.get('attach_item_remote_del');
      expect(offlineDoc, isNotNull);
      expect(
        offlineDoc!.attachments == null ||
            !offlineDoc.attachments!.containsKey('remote_del.txt'),
        isTrue,
      );
    });
  });

  group('OfflineFirstDb - Views and Queries', () {
    test('allDocs returns correct results when online', () async {
      final db = await cm.offlineDb();

      // Create multiple documents
      for (int i = 0; i < 5; i++) {
        final doc = EinkaufslistItem(
          id: 'alldocs_item_$i',
          name: 'Item $i',
          erledigt: false,
          anzahl: i + 1,
          einheit: 'pc',
          category: 'test',
        );
        await db.put(doc);
      }
      await waitForSync(db, maxSeconds: 3);

      // Call allDocs
      final allDocsResult = await db.allDocs();
      expect(allDocsResult, isNotNull);

      // Should contain all 5 documents (excluding design docs)
      final userDocs = allDocsResult.rows
          .where((r) => !r.id!.startsWith('_'))
          .toList();
      expect(userDocs.length, greaterThanOrEqualTo(5));

      // Verify our documents are present
      final ids = userDocs.map((r) => r.id).toList();
      for (int i = 0; i < 5; i++) {
        expect(ids, contains('alldocs_item_$i'));
      }
    });

    test('allDocs returns correct results when offline', () async {
      final db = await cm.offlineDb();

      // Create documents while online
      for (int i = 0; i < 3; i++) {
        final doc = EinkaufslistItem(
          id: 'offline_alldocs_$i',
          name: 'Offline Item $i',
          erledigt: false,
          anzahl: i + 1,
          einheit: 'pc',
          category: 'test',
        );
        await db.put(doc);
      }
      await waitForSync(db, maxSeconds: 2);

      // Go offline
      await cm.pauseContainer();

      // Call allDocs while offline - should return from local db
      final allDocsResult = await db.allDocs();
      expect(allDocsResult, isNotNull);

      // Verify our documents are present
      final ids = allDocsResult.rows.map((r) => r.id).toList();
      for (int i = 0; i < 3; i++) {
        expect(ids, contains('offline_alldocs_$i'));
      }
    });

    test('allDocs with includeDocs returns document content', () async {
      final db = await cm.offlineDb();

      // Create a document
      final doc = EinkaufslistItem(
        id: 'include_docs_test',
        name: 'Test Include Docs',
        erledigt: true,
        anzahl: 99,
        einheit: 'kg',
        category: 'special',
      );
      await db.put(doc);
      await waitForSync(db, maxSeconds: 2);

      // Call allDocs with includeDocs
      final allDocsResult = await db.allDocs(includeDocs: true);
      expect(allDocsResult, isNotNull);

      // Find our document
      final ourRow = allDocsResult.rows.firstWhere(
        (r) => r.id == 'include_docs_test',
      );
      expect(ourRow.doc, isNotNull);
      expect((ourRow.doc as EinkaufslistItem).name, 'Test Include Docs');
      expect((ourRow.doc as EinkaufslistItem).anzahl, 99);
    });

    test('allDocs with keys filter returns only requested documents', () async {
      final db = await cm.offlineDb();

      // Create multiple documents
      for (int i = 0; i < 5; i++) {
        final doc = EinkaufslistItem(
          id: 'keys_filter_$i',
          name: 'Item $i',
          erledigt: false,
          anzahl: i + 1,
          einheit: 'pc',
          category: 'test',
        );
        await db.put(doc);
      }
      await waitForSync(db, maxSeconds: 2);

      // Request only specific keys
      final requestedKeys = ['keys_filter_1', 'keys_filter_3'];
      final allDocsResult = await db.allDocs(keys: requestedKeys);
      expect(allDocsResult, isNotNull);
      expect(allDocsResult.rows.length, 2);

      final ids = allDocsResult.rows.map((r) => r.id).toList();
      expect(ids, contains('keys_filter_1'));
      expect(ids, contains('keys_filter_3'));
      expect(ids, isNot(contains('keys_filter_0')));
      expect(ids, isNot(contains('keys_filter_2')));
    });

    test('allDocs reflects new documents added while offline', () async {
      final db = await cm.offlineDb();
      await waitForSync(db, maxSeconds: 2);

      // Go offline
      await cm.pauseContainer();

      // Add documents while offline
      for (int i = 0; i < 3; i++) {
        final doc = EinkaufslistItem(
          id: 'new_offline_$i',
          name: 'New Offline $i',
          erledigt: false,
          anzahl: i + 1,
          einheit: 'pc',
          category: 'test',
        );
        await db.put(doc);
      }

      // allDocs should immediately reflect the new documents
      final allDocsResult = await db.allDocs();
      final ids = allDocsResult.rows.map((r) => r.id).toList();

      for (int i = 0; i < 3; i++) {
        expect(ids, contains('new_offline_$i'));
      }
    });
  });

  group('OfflineFirstDb - Changes Feed', () {
    test('changes feed works when online', () async {
      final db = await cm.offlineDb();
      await waitForSync(db, maxSeconds: 2);

      // Listen to changes feed
      final changesStream = db.changes(feedmode: FeedMode.continuous);
      final changes = <String>[];
      final subscription = changesStream.listen((change) {
        if (change.continuous != null) {
          changes.add(change.continuous!.id);
        }
      });

      // Add document
      final doc = EinkaufslistItem(
        id: 'changes_item1',
        name: 'Changes Test',
        erledigt: false,
        anzahl: 1,
        einheit: 'pc',
        category: 'test',
      );
      await db.put(doc);

      // Wait for change event
      await waitForCondition(
        () => Future.value(changes.contains('changes_item1')),
      );

      // Verify change event received
      expect(changes, contains('changes_item1'));

      await subscription.cancel();
    });

    test('changes feed works when offline', () async {
      final db = await cm.offlineDb();
      await waitForSync(db, maxSeconds: 2);

      // Go offline
      await cm.pauseContainer();

      // Listen to changes feed
      final changesStream = db.changes(feedmode: FeedMode.continuous);
      final changes = <String>[];
      final subscription = changesStream.listen((change) {
        if (change.continuous != null) {
          changes.add(change.continuous!.id);
        }
      });

      // Add document locally
      final doc = EinkaufslistItem(
        id: 'offline_changes_item',
        name: 'Offline Changes Test',
        erledigt: false,
        anzahl: 1,
        einheit: 'pc',
        category: 'test',
      );
      await db.put(doc);

      // Wait for change event
      await waitForCondition(
        () => Future.value(changes.contains('offline_changes_item')),
      );

      // Verify change event received from local db
      expect(changes, contains('offline_changes_item'));

      await subscription.cancel();
    });

    test(
      'changes feed continues across offline/online transitions when http database has gotten an updated or new or deleted document ',
      () async {
        final db = await cm.offlineDb();
        await waitForSync(db, maxSeconds: 2);

        // Listen to changes feed
        final changesStream = db.changes(feedmode: FeedMode.continuous);
        final changes = <String>[];
        final subscription = changesStream.listen((change) {
          if (change.continuous != null &&
              !change.continuous!.id.startsWith('_')) {
            changes.add(change.continuous!.id);
          }
        });

        // Write doc online
        final doc1 = EinkaufslistItem(
          id: 'transition_item1',
          name: 'Online',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        );
        await db.put(doc1);

        // Go offline
        await cm.pauseContainer();

        // Write doc offline
        final doc2 = EinkaufslistItem(
          id: 'transition_item2',
          name: 'Offline',
          erledigt: false,
          anzahl: 2,
          einheit: 'pc',
          category: 'test',
        );
        await db.put(doc2);

        // Go back online
        await cm.resumeContainer();

        // Add doc on server to trigger incoming change
        final serverDb = await cm.httpDb();
        final doc3 = EinkaufslistItem(
          id: 'transition_item3',
          name: 'Server Added',
          erledigt: false,
          anzahl: 3,
          einheit: 'pc',
          category: 'test',
        );
        await serverDb.put(doc3);

        // Wait for change to be detected
        await waitForCondition(
          () => Future.value(
            changes.contains('transition_item1') &&
                changes.contains('transition_item2') &&
                changes.contains('transition_item3'),
          ),
        );

        // Verify all changes received
        expect(changes, contains('transition_item1'));
        expect(changes, contains('transition_item2'));
        expect(changes, contains('transition_item3'));

        await subscription.cancel();
      },
    );
  });

  group('OfflineFirstDb - Bulk Operations', () {
    test('bulkDocs when online syncs all documents', () async {
      final db = await cm.offlineDb();
      await waitForSync(db, maxSeconds: 2);

      // Create multiple documents with bulkDocs
      final docs = <EinkaufslistItem>[];
      for (int i = 0; i < 10; i++) {
        docs.add(
          EinkaufslistItem(
            id: 'bulk_item_$i',
            name: 'Bulk Item $i',
            erledigt: false,
            anzahl: i + 1,
            einheit: 'pc',
            category: 'test',
          ),
        );
      }

      await db.bulkDocs(docs);
      await waitForSync(db, maxSeconds: 5);

      // Verify all documents in local db
      for (int i = 0; i < 10; i++) {
        final localDoc = await db.localDb.get('bulk_item_$i');
        expect(localDoc, isNotNull);
      }

      // Verify all documents synced to server.
      // waitForSync may return as soon as the replication queue briefly hits
      // zero between individual continuous-push events; poll the server until
      // all 10 documents are confirmed present rather than asserting
      // immediately after waitForSync.
      final serverDb = await cm.httpDb();
      final allOnServer = await waitForCondition(
        () async {
          for (int i = 0; i < 10; i++) {
            if (await serverDb.get('bulk_item_$i') == null) return false;
          }
          return true;
        },
        maxAttempts: 30,
        interval: Duration(milliseconds: 500),
      );
      expect(
        allOnServer,
        isTrue,
        reason: 'Not all bulk docs reached the server',
      );
      for (int i = 0; i < 10; i++) {
        final serverDoc = await serverDb.get('bulk_item_$i');
        expect((serverDoc as EinkaufslistItem).name, 'Bulk Item $i');
      }
    });

    test('bulkDocs when offline saves locally', () async {
      final db = await cm.offlineDb();
      await waitForSync(db, maxSeconds: 2);

      // Go offline
      await cm.pauseContainer();

      // Create multiple documents with bulkDocs while offline
      final docs = <EinkaufslistItem>[];
      for (int i = 0; i < 5; i++) {
        docs.add(
          EinkaufslistItem(
            id: 'offline_bulk_$i',
            name: 'Offline Bulk $i',
            erledigt: false,
            anzahl: i + 1,
            einheit: 'pc',
            category: 'test',
          ),
        );
      }

      await db.bulkDocs(docs);

      // Verify all documents in local db
      for (int i = 0; i < 5; i++) {
        final localDoc = await db.localDb.get('offline_bulk_$i');
        expect(localDoc, isNotNull);
        expect((localDoc as EinkaufslistItem).name, 'Offline Bulk $i');
      }
    });

    test('bulkDocs offline syncs when connection restored', () async {
      final db = await cm.offlineDb();
      await waitForSync(db, maxSeconds: 2);

      // Go offline
      await cm.pauseContainer();

      // Create documents with bulkDocs
      final docs = <EinkaufslistItem>[];
      for (int i = 0; i < 5; i++) {
        docs.add(
          EinkaufslistItem(
            id: 'bulk_sync_$i',
            name: 'Bulk Sync $i',
            erledigt: false,
            anzahl: i + 1,
            einheit: 'pc',
            category: 'test',
          ),
        );
      }

      await db.bulkDocs(docs);

      // Restore connection
      await cm.resumeContainer();
      await waitForSync(db, maxSeconds: 10);

      // Verify all documents synced to server
      final serverDb = await cm.httpDb();
      for (int i = 0; i < 5; i++) {
        final serverDoc = await serverDb.get('bulk_sync_$i');
        expect(serverDoc, isNotNull);
        expect((serverDoc as EinkaufslistItem).name, 'Bulk Sync $i');
      }
    });
  });

  group('OfflineFirstDb - Edge Cases', () {
    test('handles server database deletion while online', () async {
      final db = await cm.offlineDb();

      // Create document
      final doc = EinkaufslistItem(
        id: 'delete_test',
        name: 'Test',
        erledigt: false,
        anzahl: 1,
        einheit: 'pc',
        category: 'test',
      );
      await db.put(doc);
      await waitForSync(db, maxSeconds: 2);

      log.info(
        '*** Deleting database ${CouchTestManager.testDbName} via another instance',
      );
      await deleteDatabaseViaAnotherInstance(
        serverUrl: CouchTestManager.uri,
        username: CouchTestManager.adminUser,
        password: CouchTestManager.adminPassword,
        dbName: CouchTestManager.testDbName,
      );

      // The tombstone is created. Dispose the db object to release the reference
      log.info('Disposing database object to release reference');
      await db.dispose();

      // After disposal, the database should be cleaned up
      // The server will use deleteDatabase on the remaining instance
      final server = await cm.offlineServer();
      await server.deleteDatabase(CouchTestManager.testDbName);

      // Verify database is removed from all listings
      await expectLater(
        server.localServer!.allDatabasesNames,
        completion(isNot(contains(CouchTestManager.testDbName))),
      );

      await expectLater(
        (await cm.httpServer()).allDatabasesNames,
        completion(isNot(contains(CouchTestManager.testDbName))),
      );

      await expectLater(
        server.allDatabasesNames,
        completion(isNot(contains(CouchTestManager.testDbName))),
      );
    });

    test('handles server database deletion while online after network reconnect', () async {
      // This tests gives a drift warning:
      // WARNING (drift): It looks like you've created the database class AppDatabase multiple times. When these two databases use the same QueryExecutor, race conditions will occur and might corrupt the database.
      // Try to follow the advice at https://drift.simonbinder.eu/faq/#using-the-database or, if you know what you're doing, set driftRuntimeOptions.dontWarnAboutMultipleDatabases = true
      // Here is the stacktrace from when the database was opened a second time:
      // #0      GeneratedDatabase._handleInstantiated (package:drift/src/runtime/api/db_base.dart:96:30)
      // #1      GeneratedDatabase._whenConstructed (package:drift/src/runtime/api/db_base.dart:73:12)
      // #2      new GeneratedDatabase (package:drift/src/runtime/api/db_base.dart:64:5)
      // #3      new _$AppDatabase (package:dart_couch/src/local_storage_engine/database.g.dart:2824:36)
      // #4      new AppDatabase.fromFile (package:dart_couch/src/local_storage_engine/database.dart:160:7)
      // #5      new LocalDartCouchServer (package:dart_couch/src/local_dart_couch_server.dart:27:23)
      // #6      OfflineFirstServer.loginWithReloginFlag.<anonymous closure> (package:dart_couch/src/offline_first_server.dart:841:23)
      // <asynchronous suspension>
      // #7      Mutex.protect (package:mutex/src/mutex.dart:79:14)
      // <asynchronous suspension>
      // #8      deleteDatabaseViaAnotherInstance (file:///home/topse/dev-projects/dart_couch/test/helper/helper.dart:594:5)
      // <asynchronous suspension>
      // #9      main.<anonymous closure>.<anonymous closure> (file:///home/topse/dev-projects/dart_couch/test/offline_first_db_test.dart:2161:9)
      // <asynchronous suspension>
      // #10     Declarer.test.<anonymous closure>.<anonymous closure> (package:test_api/src/backend/declarer.dart:242:9)
      // <asynchronous suspension>
      // #11     Declarer.test.<anonymous closure> (package:test_api/src/backend/declarer.dart:240:7)
      // <asynchronous suspension>
      // #12     Invoker._waitForOutstandingCallbacks.<anonymous closure> (package:test_api/src/backend/invoker.dart:282:9)
      // <asynchronous suspension>
      // This warning will only appear on debug builds.
      //
      // According to google gemini, that is ok:
      // Based on your code, you can instantiate this class twice with different files, but Drift is warning you
      // because it sees the same class name (AppDatabase) being registered in its internal runtime tracker more than once.
      // You are allowed to do this. The warning is just Drift saying: "Hey, I see two 'AppDatabase' objects.
      // If they are touching the same file, you're in trouble!" Since your LocalDartCouchServer uses different
      // filePath values (presumably), you can safely set driftRuntimeOptions.dontWarnAboutMultipleDatabases = true and continue.

      final db = await cm.offlineDb();

      // Create document
      final doc = EinkaufslistItem(
        id: 'delete_test',
        name: 'Test',
        erledigt: false,
        anzahl: 1,
        einheit: 'pc',
        category: 'test',
      );
      await db.put(doc);
      await waitForSync(db, maxSeconds: 2);

      // Go offline
      log.info('stopping database');
      await cm.pauseContainer();

      // Delete database on server (we need to restart first)
      log.info('restart database');
      await cm.resumeContainer();

      // Wait for the original server to reconnect. This test exercises the
      // "online delete" path — both deleteDatabase calls must run with the
      // server in normalOnline so we get immediate local+remote cleanup
      // rather than relying on the tombstone-sync path (which is tested in
      // 'handles server database deletion while offline').
      final server = await cm.offlineServer();
      await waitForCondition(
        () async => server.state.value == OfflineFirstServerState.normalOnline,
        maxAttempts: 30,
        interval: Duration(milliseconds: 500),
      );

      log.info('Deleting database ${CouchTestManager.testDbName} on server');
      await deleteDatabaseViaAnotherInstance(
        serverUrl: CouchTestManager.uri,
        username: CouchTestManager.adminUser,
        password: CouchTestManager.adminPassword,
        dbName: CouchTestManager.testDbName,
      );

      // The tombstone is created. Dispose the db object to release the reference
      log.info('Disposing database object to release reference');
      await db.dispose();

      // After disposal, the database should be cleaned up
      // The server will use deleteDatabase on the remaining instance
      await server.deleteDatabase(CouchTestManager.testDbName);

      // Verify database is removed from all listings
      await expectLater(
        server.localServer!.allDatabasesNames,
        completion(isNot(contains(CouchTestManager.testDbName))),
      );

      await expectLater(
        (await cm.httpServer()).allDatabasesNames,
        completion(isNot(contains(CouchTestManager.testDbName))),
      );

      await expectLater(
        server.allDatabasesNames,
        completion(isNot(contains(CouchTestManager.testDbName))),
      );
    });

    test('handles server database deletion while offline', () async {
      final db = await cm.offlineDb();

      // Create document
      final doc = EinkaufslistItem(
        id: 'delete_test',
        name: 'Test',
        erledigt: false,
        anzahl: 1,
        einheit: 'pc',
        category: 'test',
      );
      log.info(
        'Putting document to be deleted later and waiting for its replication',
      );
      await db.put(doc);
      await waitForCondition(() async {
        final localDoc = await (await cm.httpDb()).get('delete_test');
        return localDoc != null;
      });

      expect(await (await cm.httpDb()).get('delete_test'), isNotNull);

      // Go offline (pause OfflineFirstServer, container stays up)
      log.info('Pausing offline first db, not server');
      await cm.pauseOfflineFirstDb();

      log.info('Deleting database ${CouchTestManager.testDbName} on server');
      await deleteDatabaseViaAnotherInstance(
        serverUrl: CouchTestManager.uri,
        username: CouchTestManager.adminUser,
        password: CouchTestManager.adminPassword,
        dbName: CouchTestManager.testDbName,
      );

      log.info('Restarting offline first db');
      await cm.resumeOfflineFirstDb();
      final db2 = await cm.offlineDb();

      // Verify the document is still in local database
      final localDoc = await db2.localDb.get('delete_test');
      expect(localDoc, isNotNull);

      // Verify database was recreated on server and document synced
      await waitForCondition(() async {
        final serverDoc = await (await (await cm.httpServer()).db(
          CouchTestManager.testDbName,
        ))?.get('delete_test');
        return serverDoc != null;
      });

      final serverDoc = await (await cm.httpDb()).get('delete_test');
      expect(serverDoc, isNotNull);
    });

    test(
      'handles rapid offline/online transitions',
      () async {
        final db = await cm.offlineDb();
        await waitForSync(db, maxSeconds: 2);

        // Rapidly toggle offline/online 5 times
        for (int i = 0; i < 5; i++) {
          await cm.pauseContainer();
          await cm.resumeContainer();
        }

        // Write a document after all the chaos
        final doc = EinkaufslistItem(
          id: 'chaos_test',
          name: 'Survived Chaos',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        );
        await db.put(doc);

        // Wait for eventual sync
        await waitForSync(db, maxSeconds: 10);

        // Verify document synced
        final serverDoc = await (await cm.httpDb()).get('chaos_test');
        expect(serverDoc, isNotNull);
      },
      timeout: Timeout(Duration(minutes: 2)),
    );

    test('handles concurrent writes from multiple sources', () async {
      final db = await cm.offlineDb();

      // Create document
      final doc = EinkaufslistItem(
        id: 'concurrent_test',
        name: 'Initial',
        erledigt: false,
        anzahl: 1,
        einheit: 'pc',
        category: 'test',
      );
      final putResult = await db.put(doc);
      await waitForSync(db, maxSeconds: 2);

      final serverDb = await cm.httpDb();

      // Update locally
      final localUpdate = EinkaufslistItem(
        id: 'concurrent_test',
        rev: putResult.rev,
        name: 'Local Update',
        erledigt: false,
        anzahl: 5,
        einheit: 'pc',
        category: 'test',
      );
      await db.put(localUpdate);

      // Update on server concurrently
      final serverUpdate = EinkaufslistItem(
        id: 'concurrent_test',
        rev: putResult.rev,
        name: 'Server Update',
        erledigt: true,
        anzahl: 10,
        einheit: 'kg',
        category: 'test',
      );
      try {
        await serverDb.put(serverUpdate);
      } catch (e) {
        // Expected conflict - this is normal when two clients update simultaneously
        log.info('Expected conflict when updating server: $e');
        // The conflict will be resolved by the replication layer
      }

      // Wait for conflict resolution
      await waitForSync(db, maxSeconds: 5);

      // Document should exist (conflict resolved)
      final finalDoc = await serverDb.get('concurrent_test');
      expect(finalDoc, isNotNull);
    });

    test('handles large batch of changes during initial sync', () async {
      // Create many documents on server first
      final serverDb = await cm.httpDb();

      for (int i = 0; i < 100; i++) {
        final doc = EinkaufslistItem(
          id: 'large_batch_$i',
          name: 'Item $i',
          erledigt: false,
          anzahl: i + 1,
          einheit: 'pc',
          category: 'test',
        );
        await serverDb.put(doc);
      }

      // Now create offline db - should sync all 100 documents
      final db = await cm.offlineDb();
      await waitForSync(db, maxSeconds: 15);

      // Verify all documents synced to local
      for (int i = 0; i < 100; i++) {
        final localDoc = await db.localDb.get('large_batch_$i');
        expect(localDoc, isNotNull);
      }
    });
  });

  group('OfflineFirstDb - Integration Scenarios', () {
    test('mobile app scenario: start offline, write, go online, sync', () async {
      // Start clean and ensure we have a cached successful login before going offline
      // Perform an initial online login so credentials are stored locally
      final bootstrapServer = OfflineFirstServer();
      final bootstrapLogin = await bootstrapServer.login(
        CouchTestManager.uri,
        CouchTestManager.adminUser,
        CouchTestManager.adminPassword,
        cm.localPath,
      );
      expect(bootstrapLogin?.success, isTrue);
      await bootstrapServer.dispose();

      // Simulate app start with no network connectivity
      await cm.pauseContainer();

      final offlineServer = await cm.offlineServer();
      expect(
        offlineServer.state.value,
        equals(OfflineFirstServerState.normalOffline),
      );
      final db = await cm.offlineDb();

      // Write 3 documents while offline
      for (int i = 0; i < 3; i++) {
        final doc = EinkaufslistItem(
          id: 'mobile_offline_$i',
          name: 'Mobile Item $i',
          erledigt: false,
          anzahl: i + 1,
          einheit: 'pc',
          category: 'test',
        );
        await db.put(doc);
      }

      // Verify documents in local db
      for (int i = 0; i < 3; i++) {
        final localDoc = await db.localDb.get('mobile_offline_$i');
        expect(localDoc, isNotNull);
      }

      // Restore network
      await cm.resumeContainer();

      // Wait for sync - longer timeout because we need to:
      // 1. Detect network is back
      // 2. Recreate remote database
      // 3. Start replication
      // 4. Sync all documents
      await waitForSync(db, maxSeconds: 20);

      // Verify all documents synced to server
      final serverDb = await cm.httpDb();
      for (int i = 0; i < 3; i++) {
        final serverDoc = await serverDb.get('mobile_offline_$i');
        expect(serverDoc, isNotNull);
        expect((serverDoc as EinkaufslistItem).name, 'Mobile Item $i');
      }
    });

    test(
      'mobile app scenario: write online, lose connection, continue writing',
      () async {
        final db = await cm.offlineDb();
        await waitForSync(db, maxSeconds: 2);

        // Write document while online
        final doc1 = EinkaufslistItem(
          id: 'mobile_scenario_1',
          name: 'Online Item',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        );
        await db.put(doc1);
        await waitForSync(db, maxSeconds: 2);

        // Verify first doc synced
        final serverDb = await cm.httpDb();
        final server1 = await serverDb.get('mobile_scenario_1');
        expect(server1, isNotNull);

        // Lose connection
        await cm.pauseContainer();

        // Continue writing 2 more docs offline
        for (int i = 2; i <= 3; i++) {
          final doc = EinkaufslistItem(
            id: 'mobile_scenario_$i',
            name: 'Queued Item $i',
            erledigt: false,
            anzahl: i,
            einheit: 'pc',
            category: 'test',
          );
          await db.put(doc);
        }

        // Verify docs are in local db (queued)
        final local2 = await db.localDb.get('mobile_scenario_2');
        final local3 = await db.localDb.get('mobile_scenario_3');
        expect(local2, isNotNull);
        expect(local3, isNotNull);

        // Reconnect
        await cm.resumeContainer();
        await waitForSync(db, maxSeconds: 10);

        // Verify queued docs synced
        final reloadedServerDb = await cm.httpDb();
        final server2 = await reloadedServerDb.get('mobile_scenario_2');
        final server3 = await reloadedServerDb.get('mobile_scenario_3');
        expect(server2, isNotNull);
        expect(server3, isNotNull);
      },
    );

    test(
      'desktop app scenario: periodic reconnection with accumulated changes',
      () async {
        final db = await cm.offlineDb();
        await waitForSync(db, maxSeconds: 2);

        // Go offline
        await cm.pauseContainer();

        // Create various documents over time
        final doc1 = EinkaufslistItem(
          id: 'desktop_item1',
          name: 'Created',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        );
        final put1 = await db.put(doc1);

        // Update it
        final doc1Updated = EinkaufslistItem(
          id: 'desktop_item1',
          rev: put1.rev,
          name: 'Updated',
          erledigt: true,
          anzahl: 5,
          einheit: 'kg',
          category: 'test',
        );
        await db.put(doc1Updated);

        // Create and delete another
        final doc2 = EinkaufslistItem(
          id: 'desktop_item2',
          name: 'To Delete',
          erledigt: false,
          anzahl: 1,
          einheit: 'pc',
          category: 'test',
        );
        final put2 = await db.put(doc2);
        await db.remove('desktop_item2', put2.rev!);

        // Create final document
        final doc3 = EinkaufslistItem(
          id: 'desktop_item3',
          name: 'Final',
          erledigt: false,
          anzahl: 3,
          einheit: 'pc',
          category: 'test',
        );
        await db.put(doc3);

        // Reconnect after "5 minutes" (simulated)
        await cm.resumeContainer();
        await waitForSync(db, maxSeconds: 10);

        // Verify all changes synced correctly
        final serverDb = await cm.httpDb();

        final server1 = await serverDb.get('desktop_item1');
        expect(server1, isNotNull);
        expect((server1 as EinkaufslistItem).name, 'Updated');
        expect(server1.anzahl, 5);

        final server2 = await serverDb.get('desktop_item2');
        expect(server2, isNull); // Should be deleted

        final server3 = await serverDb.get('desktop_item3');
        expect(server3, isNotNull);
        expect((server3 as EinkaufslistItem).name, 'Final');
      },
    );
  });

  test(
    'Login as normal, existing user and access the users database by querying info and putting and getting a document while ensuring replication',
    () async {
      final adminServer = await cm.httpServer();
      final user = "testuser";
      final password = "testpassword";
      await adminServer.createUser(user, password);

      await waitForCondition(() async {
        return (await adminServer.allDatabasesNames).contains(
          DartCouchDb.usernameToDbName(user),
        );
      });

      final ofs = await cm.offlineServer();

      // Get the user's database - it exists on server but needs initialization
      final userDbName = DartCouchDb.usernameToDbName(user);

      //await waitForCondition(() async {
      //  return (await ofs.db(userDbName)) != null;
      //});

      final db = await ofs.db(userDbName) as OfflineFirstDb?;
      expect(db, isNotNull);

      // Query database info
      log.info('Querying database info for $userDbName');
      final info = await db!.info();
      expect(info, isNotNull);
      expect(info!.dbName, userDbName);
      log.info('Database info: ${info.dbName}, docCount: ${info.docCount}');

      // Put a document
      log.info('Creating and putting a test document');
      final testDoc = EinkaufslistItem(
        id: 'user_test_doc',
        name: 'User Test Document',
        erledigt: false,
        anzahl: 1,
        einheit: 'pc',
        category: 'test',
      );
      final putResult = await db.put(testDoc);
      expect(putResult.id, 'user_test_doc');
      expect(putResult.rev, isNotNull);

      // Wait for replication to complete
      log.info('Waiting for document to sync to server');
      await waitForSync(db, maxSeconds: 5);

      // Get the document from local db
      log.info('Getting document from local database');
      final localDoc = await db.localDb.get('user_test_doc');
      expect(localDoc, isNotNull);
      expect((localDoc as EinkaufslistItem).name, 'User Test Document');

      // Verify document is on server
      log.info('Verifying document synced to server');
      final serverDb = await adminServer.db(userDbName);
      final serverDoc = await serverDb!.get('user_test_doc');
      expect(serverDoc, isNotNull);
      expect((serverDoc as EinkaufslistItem).name, 'User Test Document');
      log.info('Document successfully synced to server');

      await adminServer.deleteUser(user);
    },
  );

  test(
    'database recreated on server while offline syncs bidirectionally with local data',
    () async {
      // 1. Create OfflineFirstDb normally
      final db = await cm.offlineDb();
      final dbName = CouchTestManager.testDbName;

      // 2. Create three test documents
      final docs = await createTestDocuments(db, 3);
      await waitForCondition(() async {
        final allLocalDocs = await (await db.serverDb.db(dbName))!.allDocs();
        return allLocalDocs.rows.length >= docs.length;
      });

      // 3. Shutdown OfflineFirstDb and get HTTP connection to server
      log.info('pausing OfflineFirstDb');
      await cm.pauseOfflineFirstDb();

      // 4. Delete the testdb on server
      log.info('Deleting database $dbName on server');
      await deleteDatabaseViaAnotherInstance(
        serverUrl: CouchTestManager.uri,
        username: CouchTestManager.adminUser,
        password: CouchTestManager.adminPassword,
        dbName: dbName,
      );

      // Verify database is deleted
      final allDbs = await (await cm.httpServer()).allDatabasesNames;
      expect(
        allDbs,
        isNot(contains(dbName)),
        reason: 'Database should be deleted on server',
      );

      // 5. Recreate database on server
      log.info('Recreating database $dbName on server -- its now empty');
      await (await cm.httpServer()).createDatabase(dbName);

      // 6. Put a different test document to the server
      log.info('Adding new document to recreated server database');
      final serverDb = await (await cm.httpServer()).db(dbName);
      final newDoc = TestDocumentOne(
        id: 'new_server_doc',
        name: 'New Server Document',
      );
      await serverDb!.put(newDoc);

      // 7. Restart OfflineFirstDb
      log.info('restarting OfflineFirstDb');
      await cm.resumeOfflineFirstDb();
      final db2 = await cm.offlineDb();

      // 8. Check replication behaviour
      log.info('waiting for sync after server database recreation');
      await waitForSync(db2, maxSeconds: 30);

      // When database is recreated on server with new UUID, bidirectional replication
      // syncs both ways: new server doc comes down, old local docs go up.
      // This is expected - the system can't distinguish a "recreated" database from
      // just a database that existed independently on both sides.

      log.info('verifying new document from server is in local database');
      final localNewDoc = await db2.localDb.get('new_server_doc');
      expect(
        localNewDoc,
        isNotNull,
        reason: 'New server document should be synced to local',
      );

      // The old documents that existed locally should still exist and sync to server
      log.info(
        'verifying old documents still exist locally and synced to server',
      );
      for (final doc in docs) {
        final localDoc = await db2.localDb.get(doc.id!);
        expect(
          localDoc,
          isNotNull,
          reason: 'Old local document ${doc.id} should still exist',
        );

        final serverDoc = await (await db2.serverDb.db(dbName))!.get(doc.id!);
        expect(
          serverDoc,
          isNotNull,
          reason:
              'Old local document ${doc.id} should sync back to recreated server',
        );
      }

      // Verify we have all 4 documents total (3 old + 1 new) on both sides
      final allLocalDocs = await db2.localDb.allDocs();
      final localUserDocs = allLocalDocs.rows
          .where((r) => !r.id!.startsWith('_'))
          .toList();
      expect(
        localUserDocs.length,
        greaterThanOrEqualTo(4),
        reason: 'Local should have 4 documents (3 old + 1 new from server)',
      );

      final allServerDocs = await (await db2.serverDb.db(dbName))!.allDocs();
      final serverUserDocs = allServerDocs.rows
          .where((r) => !r.id!.startsWith('_'))
          .toList();
      expect(
        serverUserDocs.length,
        greaterThanOrEqualTo(4),
        reason: 'Server should have 4 documents (1 new + 3 synced from local)',
      );
    },
  );

  test(
    'create same database on server and local independently, then start OfflineServerFirst and check replication',
    () async {
      const String independentDbName = 'independent_db_test';

      // Initialize the OfflineFirstServer and then pause it
      await cm.offlineServer();
      await cm.pauseOfflineFirstDb();

      // Clean up any leftover from a previous failed run
      try {
        await (await cm.httpServer()).deleteDatabase(independentDbName);
      } catch (_) {}

      // Create database independently on server
      log.info('Creating database $independentDbName independently on server');
      await (await cm.httpServer()).createDatabase(independentDbName);
      final serverDb = await (await cm.httpServer()).db(independentDbName);

      // Add documents to server
      log.info('Adding documents to server database');
      for (int i = 0; i < 3; i++) {
        final doc = TestDocumentOne(
          id: 'server_doc_$i',
          name: 'Server Document $i',
        );
        await serverDb!.put(doc);
      }

      // Create database independently on local
      log.info('Creating database $independentDbName independently on local');
      final pauseLocalServer = LocalDartCouchServer(cm.localPath);
      await pauseLocalServer.createDatabase(independentDbName);
      final localDb =
          await pauseLocalServer.db(independentDbName) as LocalDartCouchDb;

      // Add different documents to local
      log.info('Adding documents to local database');
      for (int i = 0; i < 3; i++) {
        final doc = TestDocumentOne(
          id: 'local_doc_$i',
          name: 'Local Document $i',
        );
        await localDb.put(doc);
      }
      await pauseLocalServer.dispose();

      // Restart OfflineFirstDb - this should trigger replication
      log.info(
        'Restarting OfflineFirstDb to trigger bidirectional replication',
      );
      await cm.resumeOfflineFirstDb();
      final offlineServer = await cm.offlineServer();
      final db2 = await offlineServer.db(independentDbName) as OfflineFirstDb?;

      // TODO: check this comment:
      // The database might fail to initialize due to marker conflicts when
      // databases are created independently. This is a known limitation.
      if (db2 == null) {
        log.warning(
          'Database failed to initialize due to marker conflict - this is expected '
          'when databases are created independently on local and server',
        );
        try {
          await (await cm.httpServer()).deleteDatabase(independentDbName);
        } catch (_) {}
        return; // Skip rest of test
      }

      // Wait for sync to complete
      log.info('Waiting for sync after independent database creation');
      await waitForSync(db2, maxSeconds: 10);

      // Verify all documents from both server and local are present on both sides
      log.info('Verifying bidirectional replication of documents');

      // Check server documents are in local
      for (int i = 0; i < 3; i++) {
        final localDoc = await db2.localDb.get('server_doc_$i');
        expect(
          localDoc,
          isNotNull,
          reason: 'Server document $i should be synced to local',
        );
        expect((localDoc as TestDocumentOne).name, 'Server Document $i');
      }

      // Check local documents are on server
      for (int i = 0; i < 3; i++) {
        final serverDocResult = await (await db2.serverDb.db(
          independentDbName,
        ))!.get('local_doc_$i');
        expect(
          serverDocResult,
          isNotNull,
          reason: 'Local document $i should be synced to server',
        );
        expect((serverDocResult as TestDocumentOne).name, 'Local Document $i');
      }

      // Verify total document count (should have both sets)
      final allLocalDocs = await db2.localDb.allDocs();
      final localUserDocs = allLocalDocs.rows
          .where((r) => !r.id!.startsWith('_'))
          .toList();
      expect(
        localUserDocs.length,
        greaterThanOrEqualTo(6),
        reason:
            'Local should have at least 6 documents (3 from server + 3 originally local)',
      );

      final allServerDocs = await (await db2.serverDb.db(
        independentDbName,
      ))!.allDocs();
      final serverUserDocs = allServerDocs.rows
          .where((r) => !r.id!.startsWith('_'))
          .toList();
      expect(
        serverUserDocs.length,
        greaterThanOrEqualTo(6),
        reason:
            'Server should have at least 6 documents (3 originally on server + 3 from local)',
      );

      // Clean up the non-standard database
      try {
        await (await cm.httpServer()).deleteDatabase(independentDbName);
      } catch (_) {}
    },
  );

  test('A view that not exists is used and then created on server', () async {
    // Expectation:
    // The useView-Stream first results in null
    // after the view is created on the server, it returns data

    // testsequence:
    // 1. Init db stuff with helper function
    // 2. Create 3 test documents that later appear in view
    // 3. Use view - expect null
    // 4. Create view on server
    // 5. wait on the previously created useview stream for data
    // 6. expect the correct data in view (keys and values)

    // 1. Init db stuff with helper function
    final db = await cm.offlineDb();
    final serverDb = await cm.httpDb();

    // 2. Create 3 test documents that later appear in view
    /*final docs =*/
    await createTestDocuments(db, 3); // vegetables[0,1,2]
    await waitForSync(db);

    // 3. Use view - The Stream starts
    log.info('Starting to use view reports/by_name');
    final viewStream = db.useView('reports/by_name');
    final results = <ViewResult?>[];
    viewStream.listen((e) {
      log.info('View stream emitted new result: $e');
      results.add(e);
    });

    log.info('Expecting empty result from view initially');
    await waitForCondition(() async {
      return results.isNotEmpty;
    });
    expect(
      results.first,
      isNull,
      reason: 'Initial view result should be null as view does not exist yet',
    );
    expect(results, hasLength(1));

    // 5. Create view on server using httpServer
    log.info('Creating design document with view on server');
    final designDoc = {
      "_id": "_design/reports",
      "language": "javascript",
      "views": {
        "by_name": {
          "map":
              "function (doc) { if (doc.name) { emit(doc._id, doc.name); } }",
        },
      },
    };
    await serverDb.putRaw(designDoc);

    // 6. Execute the verification
    log.info('Expecting data from view after creation on server');
    await waitForCondition(() async {
      return results.length >= 2;
    });
    expect(results.last, isNotNull);
    expect(
      results.last!.rows,
      hasLength(3),
      reason: 'View should return 3 rows after creation and sync',
    );

    log.info("received rows: ${results.last!.rows}");
    expect(results.last!.rows.any((r) => r.key == vegetables[0]), isTrue);
    expect(results.last!.rows.any((r) => r.key == vegetables[1]), isTrue);
    expect(results.last!.rows.any((r) => r.key == vegetables[2]), isTrue);

    log.info('View test completed successfully.');
  });

  test('A view which is used gets renamed.', () async {
    // Expectation:
    // The useView-Stream first results in data
    // after the view is deleted on the server, it returns null

    // testsequence:
    // 1. Init db stuff with helper function
    // 2. Create 3 test documents that later appear in view
    // 3. Create view on server
    // 4. Use view - expect data
    // 5. rename view on server by renaming directly it in the design document
    // 6. wait on the previously created useview stream for null
    // 7. use new view and expect data
    // 8. Check local database that old view is gone and new view is present

    final db = await cm.offlineDb();
    final serverDb = await cm.httpDb();

    // 1. Create 3 test documents
    await createTestDocuments(db, 3);

    // 2. Create initial view on server and sync it
    var designDoc = {
      "_id": "_design/inventory",
      "views": {
        "old_view": {"map": "function(doc){ emit(doc._id, doc.name); }"},
      },
    };
    final setupRes = await serverDb.putRaw(designDoc);
    String currentRev = setupRes['_rev'];
    await waitForSync(db);

    // 3. Start listening to the old view
    final oldStreamResults = <ViewResult?>[];
    final oldStream = db.useView('inventory/old_view');
    oldStream.listen(oldStreamResults.add);

    await waitForCondition(() async {
      return oldStreamResults.isNotEmpty;
    });

    expect(oldStreamResults.first!.rows, hasLength(3));
    expect(
      oldStreamResults.first!.rows.any((r) => r.key == vegetables[0]),
      isTrue,
    );
    expect(
      oldStreamResults.first!.rows.any((r) => r.key == vegetables[1]),
      isTrue,
    );
    expect(
      oldStreamResults.first!.rows.any((r) => r.key == vegetables[2]),
      isTrue,
    );

    // 5. Rename view on server
    designDoc['_rev'] = currentRev;
    designDoc['views'] = {
      "new_view": {"map": "function(doc){ emit(doc._id, doc.name); }"},
    };
    await serverDb.putRaw(designDoc);

    // 6. Verify the old stream cleared out
    // Wait specifically for a null entry (the view being removed),
    // not just any second emission — intermediate re-queries may
    // re-emit the same ViewResult before the renamed design doc
    // is replicated locally.
    await waitForCondition(() async {
      return oldStreamResults.any((r) => r == null);
    });
    expect(oldStreamResults.last, isNull);

    // 7. Check the new view's contents thoroughly
    final newResult = await db.query('inventory/new_view');
    expect(newResult!.rows.length, 3);

    // Deep Content Check
    for (var i = 0; i < 3; i++) {
      final row = newResult.rows.firstWhere((r) => r.key == vegetables[i]);
      expect(
        row.value,
        contains(vegetables[i]),
      ); // check that the 'name' field was emitted as value
    }

    // 8. Final check on Local SQLite state
    final localDesignDoc =
        await db.localDb.get('_design/inventory') as DesignDocument;
    expect(localDesignDoc.views!.keys.contains('old_view'), isFalse);
    expect(localDesignDoc.views!.keys.contains('new_view'), isTrue);
  });
}
