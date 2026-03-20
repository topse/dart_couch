import 'dart:convert';

import 'package:test/test.dart';
import 'package:dart_couch/dart_couch.dart';
import 'package:logging/logging.dart';

import 'helper/couch_test_manager.dart';
import 'helper/helper.dart';
import 'helper/load_einkaufsliste_dump_into_db.dart';

void main() {

  Logger.root.level = Level.FINEST;
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

  /// Real-Application Tests have shown two potential problems:
  /// 1. Replication takes suspicous long
  ///    When starting the application, also no data or just lets say 5 of 400 documents
  ///    have been changed, the ReplicationStateProxyWidget shows that 400 or more documents
  ///    are checked for changes. This is ok for the very first start of the application
  ///    and the initial replication, but when just restarting and checking for
  ///    last changes by seq number, my feeling is, this is too much. Is there a problem
  ///    in the replication procedure, maybe in handling of the seq number?
  /// 2. At least once I had a instance of a application that had a wrong database state,
  ///    means: not all documents were synced correctly. But the OfflineFirstServerStateWidget shows
  ///    a green cloud_done symbol, so everything should be ok. Even when restarting the application
  ///    on that device and the ReplicationStateProxyWidget shows the potentially too long sync process
  ///    it kept out of sync. Only deleting all app data (it was on a android phone) and relogin solved
  ///    the problem, so assumption is, that local database had a erronous state.
  test('large sync test', () async {
    // 1. Create database and load einkaufsliste dump
    log.info('Step 1: Creating database and loading einkaufsliste dump');
    final httpDb = await cm.httpDb();
    await loadEinkaufslisteDumpIntoDb(httpDb);

    final httpDocCount = (await httpDb.allDocs()).rows.length;
    log.info('HTTP database loaded with $httpDocCount documents');
    expect(httpDocCount, equals(218), reason: 'Should have loaded test data');

    // 2. Get OfflineFirstDb and wait for initial sync
    log.info('Step 2: Getting OfflineFirstDb and waiting for initial sync');
    final offlineDb = await cm.offlineDb();
    await waitForSync(offlineDb, maxSeconds: 60);

    final initialProgress = offlineDb.replicationController.progress.value;
    log.info(
      'Initial sync completed. Transferred docs: ${initialProgress.transferredDocs}',
    );
    expect(
      initialProgress.state,
      anyOf(ReplicationState.inSync, ReplicationState.initialSyncComplete),
      reason: 'Should be in sync state',
    );

    final localDocCount = (await offlineDb.allDocs()).rows.length;
    expect(
      localDocCount,
      equals(httpDocCount),
      reason:
          'Local and remote document counts should match after initial sync',
    );

    final initialTransferredDocs = initialProgress.transferredDocs;
    log.info('Initial sync transferred $initialTransferredDocs documents');

    // 3. Pause OfflineFirstServer (simulating app restart)
    log.info('Step 3: Pausing OfflineFirstServer (simulating app restart)');
    await cm.pauseOfflineFirstDb();

    // 4. Restart OfflineFirstServer with existing local database
    log.info(
      'Step 4: Restarting OfflineFirstServer with existing local database',
    );
    await cm.resumeOfflineFirstDb();
    final restartedDb = await cm.offlineDb();

    // Capture initial replication progress before sync starts
    final restartInitialTransferred =
        restartedDb.replicationController.progress.value.transferredDocs;

    log.info('Restarted. Initial transferred docs: $restartInitialTransferred');
    log.info('Waiting for restart sync to complete');
    await waitForSync(restartedDb, maxSeconds: 60);

    final restartProgress = restartedDb.replicationController.progress.value;
    final restartTransferredDocs = restartProgress.transferredDocs;

    log.info(
      'Restart sync completed. Total transferred docs: $restartTransferredDocs',
    );
    log.info(
      'New docs transferred on restart: ${restartTransferredDocs - restartInitialTransferred}',
    );

    // Verify sync state
    expect(
      restartProgress.state,
      anyOf(ReplicationState.inSync, ReplicationState.initialSyncComplete),
      reason: 'Should be in sync state after restart',
    );

    // Verify document count is still correct
    final restartLocalDocCount = (await restartedDb.allDocs()).rows.length;
    expect(
      restartLocalDocCount,
      equals(httpDocCount),
      reason: 'Document count should remain the same after restart',
    );

    // KEY TEST: Verify that minimal sync occurred on restart
    // Since no documents changed, we should not transfer many documents again
    // Allow for some overhead (markers, checkpoints, etc.) but shouldn't re-sync everything
    final newDocsTransferred =
        restartTransferredDocs - restartInitialTransferred;
    log.info('Documents transferred during restart sync: $newDocsTransferred');

    // The restart should transfer very few or zero documents since nothing changed
    // We allow up to 5% of original count as tolerance for markers and metadata
    final maxExpectedTransfer = (httpDocCount * 0.05).ceil();
    expect(
      newDocsTransferred,
      lessThanOrEqualTo(maxExpectedTransfer),
      reason:
          'Restart should not re-transfer all documents when nothing changed. '
          'Expected <= $maxExpectedTransfer, but got $newDocsTransferred. '
          'This suggests inefficient seq number handling.',
    );

    log.info('✓ Test passed: Restart sync was efficient');
    log.info('Test completed successfully');
  });

  /// Test that verifies replication correctly syncs server-side changes
  /// that occurred while the app was offline/paused.
  ///
  /// This simulates the real-world scenario where:
  /// - User closes the app
  /// - Another device/user makes changes to the server
  /// - User reopens the app
  /// - Changes should sync down efficiently
  test(
    'large sync test with server changes during pause',
    () async {
      // 1. Create database and load einkaufsliste dump
      log.info('Step 1: Creating database and loading einkaufsliste dump');
      final httpDb = await cm.httpDb();
      await loadEinkaufslisteDumpIntoDb(httpDb);

      final httpDocCount = (await httpDb.allDocs()).rows.length;
      log.info('HTTP database loaded with $httpDocCount documents');
      expect(httpDocCount, equals(218), reason: 'Should have loaded test data');

      // 2. Get OfflineFirstDb and wait for initial sync
      log.info('Step 2: Getting OfflineFirstDb and waiting for initial sync');
      final offlineDb = await cm.offlineDb();
      await waitForSync(offlineDb, maxSeconds: 60);

      final initialProgress = offlineDb.replicationController.progress.value;
      log.info(
        'Initial sync completed. Transferred docs: ${initialProgress.transferredDocs}',
      );
      expect(
        initialProgress.state,
        anyOf(ReplicationState.inSync, ReplicationState.initialSyncComplete),
        reason: 'Should be in sync state',
      );

      final initialLocalDocCount = (await offlineDb.allDocs()).rows.length;
      expect(
        initialLocalDocCount,
        equals(httpDocCount),
        reason:
            'Local and remote document counts should match after initial sync',
      );

      // 3. Pause OfflineFirstServer (simulating app closing)
      log.info('Step 3: Pausing OfflineFirstServer (simulating app close)');
      await cm.pauseOfflineFirstDb();

      // 4. Make changes on the server while app is "offline"
      log.info('Step 4: Making changes on server while app is offline');
      final httpDbForChanges = await cm.httpDb();

      // Get a list of existing document IDs
      final allDocsResult = await httpDbForChanges.allDocs();
      final existingDocIds = allDocsResult.rows
          .map((row) => row.id)
          .where((id) => id != null)
          .cast<String>()
          .take(3)
          .toList();
      expect(
        existingDocIds.length,
        greaterThanOrEqualTo(3),
        reason: 'Should have at least 3 documents',
      );

      final docIdToModify = existingDocIds[0];
      final docIdToDelete = existingDocIds[1];

      // 4a. Modify an existing document
      final docToModify = await httpDbForChanges.get(docIdToModify);
      expect(docToModify, isNotNull, reason: 'Document should exist');
      final modifiedDoc = CouchDocumentBase(
        id: docToModify!.id,
        rev: docToModify.rev,
        unmappedProps: {
          ...docToModify.toMap(),
          'modified_while_offline': true,
          'modification_timestamp': DateTime.now().toIso8601String(),
        },
      );
      await httpDbForChanges.put(modifiedDoc);
      log.info('Modified document: ${modifiedDoc.id}');

      // 4b. Add a new document
      final newDoc = CouchDocumentBase(
        id: 'new_item_created_while_offline',
        unmappedProps: {
          'name': 'New Item',
          'created_while_offline': true,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      await httpDbForChanges.put(newDoc);
      log.info('Created new document: ${newDoc.id}');

      // 4c. Delete a document
      final docToDelete = await httpDbForChanges.get(docIdToDelete);
      expect(docToDelete, isNotNull, reason: 'Document should exist');
      final docId = docToDelete!.id;
      final docRev = docToDelete.rev;
      expect(docId, isNotNull, reason: 'Document should have an id');
      expect(docRev, isNotNull, reason: 'Document should have a rev');
      await httpDbForChanges.remove(docId!, docRev!);
      log.info('Deleted document: $docId');

      // Verify server changes
      final updatedHttpDocCount =
          (await httpDbForChanges.allDocs()).rows.length;
      log.info('Server now has $updatedHttpDocCount documents');
      expect(
        updatedHttpDocCount,
        equals(httpDocCount),
        reason: 'Added 1, deleted 1 = same count',
      );

      // 5. Restart OfflineFirstServer
      log.info('Step 5: Restarting OfflineFirstServer');
      await cm.resumeOfflineFirstDb();
      final restartedDb = await cm.offlineDb();

      // 6. Wait for sync to pull server changes
      log.info('Step 6: Waiting for restart sync to complete');
      final restartInitialTransferred =
          restartedDb.replicationController.progress.value.transferredDocs;

      await waitForSync(restartedDb, maxSeconds: 60);

      final restartProgress = restartedDb.replicationController.progress.value;
      final newDocsTransferred =
          restartProgress.transferredDocs - restartInitialTransferred;

      log.info(
        'Restart sync completed. Documents transferred: $newDocsTransferred',
      );

      // 7. Verify the changes were synced correctly
      log.info('Step 7: Verifying server changes were synced to local');

      // 7a. Verify modified document
      final localModifiedDoc = await restartedDb.get(docIdToModify);
      expect(
        localModifiedDoc,
        isNotNull,
        reason: 'Modified document should exist locally',
      );
      expect(
        localModifiedDoc!.toMap()['modified_while_offline'],
        isTrue,
        reason: 'Document should have the server modification',
      );
      log.info('✓ Modified document synced correctly');

      // 7b. Verify new document
      final localNewDoc = await restartedDb.get(
        'new_item_created_while_offline',
      );
      expect(
        localNewDoc,
        isNotNull,
        reason: 'New document should be synced to local',
      );
      expect(
        localNewDoc!.toMap()['created_while_offline'],
        isTrue,
        reason: 'New document should have correct data',
      );
      log.info('✓ New document synced correctly');

      // 7c. Verify deleted document
      final localDeletedDoc = await restartedDb.get(docIdToDelete);
      expect(
        localDeletedDoc,
        isNull,
        reason: 'Deleted document should not exist locally',
      );
      log.info('✓ Deleted document synced correctly');

      // 7d. Verify document counts match
      final finalLocalDocCount = (await restartedDb.allDocs()).rows.length;
      expect(
        finalLocalDocCount,
        equals(updatedHttpDocCount),
        reason: 'Local and remote counts should match after sync',
      );
      log.info('✓ Document counts match: $finalLocalDocCount');

      // 8. Verify efficient sync (only changed documents transferred)
      log.info('Step 8: Verifying sync efficiency');
      // We expect:
      // - 1 modified document
      // - 1 new document
      // - 1 deleted document (deletion marker)
      // Plus some overhead for markers, but should be much less than all 218 docs
      final maxExpectedTransfer = 10; // Conservative estimate
      expect(
        newDocsTransferred,
        lessThanOrEqualTo(maxExpectedTransfer),
        reason:
            'Should only transfer changed documents (~3), not all documents. '
            'Got $newDocsTransferred transferred.',
      );
      log.info(
        '✓ Sync was efficient: only $newDocsTransferred docs transferred',
      );

      log.info('✓ Test completed successfully');
    },
    timeout: Timeout(Duration(minutes: 3)),
  );
}
