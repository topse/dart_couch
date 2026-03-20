import 'dart:convert';

import 'package:test/test.dart';
import 'package:dart_couch/dart_couch.dart';
import 'package:logging/logging.dart';

import 'helper/couch_test_manager.dart';
import 'helper/helper.dart';

void main() {

  Logger.root.level = Level.INFO;
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

  /// This test verifies that replication checkpoints are properly persisted
  /// to local storage during normal operation (not just during dispose).
  ///
  /// The test ensures that:
  /// 1. Checkpoints are saved during replication (every 5 seconds)
  /// 2. Checkpoints persist across app restarts
  /// 3. Replication resumes from the last checkpoint after restart
  test('Checkpoint persistence verification', () async {
    // 1. Setup: Create OfflineFirstServer with a database
    log.info('Step 1: Setting up OfflineFirstServer');
    final offlineDb = await cm.offlineDb();

    // 2. Add some documents and sync
    log.info('Step 2: Adding documents to trigger replication');
    for (int i = 0; i < 10; i++) {
      await offlineDb.put(
        CouchDocumentBase(
          id: 'doc_$i',
          unmappedProps: {'name': 'Document $i', 'value': i},
        ),
      );
    }

    // 3. Wait for initial sync to complete
    log.info('Step 3: Waiting for initial sync');
    await waitForSync(offlineDb, maxSeconds: 30);

    // Get the checkpoint sequence after initial sync
    final progress1 = offlineDb.replicationController.progress.value;
    final checkpoint1 = progress1.lastSeq;
    log.info('Initial sync complete. Checkpoint: $checkpoint1');
    expect(checkpoint1, isNotNull, reason: 'Checkpoint should be set');

    // 4. Wait for checkpoint timer to fire (5+ seconds)
    log.info('Step 4: Waiting for checkpoint to be persisted (6 seconds)');
    await Future.delayed(Duration(seconds: 6));

    // 5. Verify checkpoint was saved by checking local document
    log.info('Step 5: Verifying checkpoint was saved to local storage');
    final localDb = offlineDb.localDb;
    final replId =
        '${CouchTestManager.testDbName}::${CouchTestManager.testDbName}::${ReplicationDirection.both.name}';
    final checkpointDoc = await localDb.get('_local/$replId');
    expect(
      checkpointDoc,
      isNotNull,
      reason: 'Checkpoint document should exist in local storage',
    );
    final checkpointMap = checkpointDoc?.toMap();
    log.info(
      'Checkpoint document found: source_last_seq=${checkpointMap?['source_last_seq']}, target_last_seq=${checkpointMap?['target_last_seq']}',
    );

    // 6. Dispose and restart OfflineFirstServer
    log.info('Step 6: Disposing OfflineFirstServer (simulating app restart)');
    await cm.pauseOfflineFirstDb();

    log.info('Step 7: Restarting OfflineFirstServer');
    await cm.resumeOfflineFirstDb();
    final restartedDb = await cm.offlineDb();

    // 7. Wait for restart sync to complete
    log.info('Step 8: Waiting for restart sync');
    await waitForSync(restartedDb, maxSeconds: 30);

    // 8. Verify checkpoint was loaded correctly
    final progress2 = restartedDb.replicationController.progress.value;
    final checkpoint2 = progress2.lastSeq;
    log.info('Restart sync complete. Checkpoint: $checkpoint2');

    // 9. Verify efficient restart (should transfer 0 documents)
    expect(
      progress2.transferredDocs,
      equals(0),
      reason:
          'Should not transfer documents on restart when nothing changed. '
          'This indicates checkpoint was loaded correctly.',
    );

    log.info('✓ Checkpoint persistence verified successfully');

    // 10. Add more documents and verify checkpoint updates
    log.info('Step 9: Adding more documents to test checkpoint updates');
    for (int i = 10; i < 15; i++) {
      await restartedDb.put(
        CouchDocumentBase(
          id: 'doc_$i',
          unmappedProps: {'name': 'Document $i', 'value': i},
        ),
      );
    }

    await waitForSync(restartedDb, maxSeconds: 30);

    // Wait for checkpoint to be saved
    await Future.delayed(Duration(seconds: 6));

    // Verify checkpoint was updated
    final updatedCheckpointDoc = await restartedDb.localDb.get(
      '_local/$replId',
    );
    expect(
      updatedCheckpointDoc,
      isNotNull,
      reason: 'Updated checkpoint document should exist',
    );
    final updatedCheckpointMap = updatedCheckpointDoc?.toMap();
    log.info('Updated checkpoint: ${updatedCheckpointMap?['source_last_seq']}');

    log.info('Test completed successfully');
  }, timeout: Timeout(Duration(minutes: 3)));
}
