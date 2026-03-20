import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dart_couch/dart_couch.dart';
import 'package:logging/logging.dart';

import 'helper/couch_test_manager.dart';
import 'helper/helper.dart';

/// Generates random binary data of the specified size in bytes.
Uint8List _generateLargeAttachment(int sizeInBytes) {
  final random = Random(42); // Fixed seed for reproducibility
  return Uint8List.fromList(
    List<int>.generate(sizeInBytes, (_) => random.nextInt(256)),
  );
}

void main() {

  Logger.root.level = Level.FINEST;
  Logger.root.onRecord.listen((record) {
    final ls = LineSplitter();
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

  /// Tests that replication of documents with large attachments (20-30MB)
  /// produces meaningful progress updates (byte-level tracking).
  test(
    'replication progress with large attachments',
    () async {
      // 1. Create database and add documents with large attachments
      log.info('Step 1: Creating database with large attachments');
      final httpDb = await cm.httpDb();

      // Create 5 documents with 20-30MB attachments each
      final attachmentSizes = [
        20 * 1024 * 1024, // 20 MB
        25 * 1024 * 1024, // 25 MB
        30 * 1024 * 1024, // 30 MB
        22 * 1024 * 1024, // 22 MB
        28 * 1024 * 1024, // 28 MB
      ];

      for (int i = 0; i < attachmentSizes.length; i++) {
        final docId = 'doc_with_large_attachment_$i';
        final doc = CouchDocumentBase(
          id: docId,
          unmappedProps: {
            'name': 'Document $i',
            'description':
                'Document with ${attachmentSizes[i] ~/ (1024 * 1024)}MB attachment',
          },
        );
        final putResult = await httpDb.put(doc);
        log.info('Created document $docId');

        // Add large attachment
        final attachmentData = _generateLargeAttachment(attachmentSizes[i]);
        await httpDb.saveAttachment(
          docId,
          putResult.rev!,
          'large_file_$i.bin',
          attachmentData,
          contentType: 'application/octet-stream',
        );
        log.info(
          'Added ${attachmentSizes[i] ~/ (1024 * 1024)}MB attachment to $docId',
        );
      }

      // Also add some small documents without attachments
      for (int i = 0; i < 10; i++) {
        final doc = CouchDocumentBase(
          id: 'small_doc_$i',
          unmappedProps: {'name': 'Small Document $i', 'value': i},
        );
        await httpDb.put(doc);
      }

      final totalDocs = (await httpDb.allDocs()).rows.length;
      log.info('Database has $totalDocs documents total');

      // 2. Get OfflineFirstDb
      log.info('Step 2: Getting OfflineFirstDb');
      final offlineDb = await cm.offlineDb();

      // 3. Monitor replication progress
      log.info('Step 3: Monitoring replication progress');

      final progressSnapshots = <ReplicationProgress>[];
      bool sawByteProgress = false;
      int maxTransferredBytes = 0;

      offlineDb.replicationController.progress.addListener(() {
        final progress = offlineDb.replicationController.progress.value;
        progressSnapshots.add(progress);

        if (progress.transferredBytes > 0) {
          sawByteProgress = true;
          if (progress.transferredBytes > maxTransferredBytes) {
            maxTransferredBytes = progress.transferredBytes;
          }
        }

        if (progress.totalBytesEstimate != null) {
          log.info(
            'Progress: ${progress.transferredDocs} docs, '
            '${_formatBytes(progress.transferredBytes)} / '
            '${_formatBytes(progress.totalBytesEstimate!)} '
            '(${(progress.progressFraction * 100).toStringAsFixed(1)}%)',
          );
        } else if (progress.transferredDocs > 0 ||
            progress.docsInNeedOfReplication > 0) {
          log.info(
            'Progress: ${progress.transferredDocs} docs transferred, '
            '${progress.docsInNeedOfReplication} remaining',
          );
        }
      });

      // 4. Wait for sync (longer timeout for large attachments)
      log.info('Step 4: Waiting for sync to complete');
      await waitForSync(offlineDb, maxSeconds: 300);

      final finalProgress = offlineDb.replicationController.progress.value;
      log.info('Sync completed. Final state: ${finalProgress.state}');
      log.info(
        'Total transferred: ${finalProgress.transferredDocs} docs, '
        '${_formatBytes(finalProgress.transferredBytes)}',
      );
      log.info(
        'Total byte estimate was: ${finalProgress.totalBytesEstimate != null ? _formatBytes(finalProgress.totalBytesEstimate!) : 'N/A'}',
      );
      log.info('Progress snapshots recorded: ${progressSnapshots.length}');

      // Verify sync completed
      expect(
        finalProgress.state,
        anyOf(ReplicationState.inSync, ReplicationState.initialSyncComplete),
      );

      // Verify all documents synced
      final localDocCount = (await offlineDb.allDocs()).rows.length;
      expect(localDocCount, equals(totalDocs));

      // Verify we got byte-level progress
      expect(
        sawByteProgress,
        isTrue,
        reason: 'Should have seen byte-level progress updates',
      );

      // Verify the byte estimate was reasonable (at least 100MB for 5 large attachments)
      expect(
        finalProgress.totalBytesEstimate,
        isNotNull,
        reason: 'Should have a total bytes estimate',
      );
      expect(
        finalProgress.totalBytesEstimate!,
        greaterThan(100 * 1024 * 1024),
        reason: 'Total byte estimate should be >100MB for 5 large attachments',
      );

      // Verify we got multiple progress updates (not just start and end)
      final progressUpdateCount = progressSnapshots
          .where(
            (p) =>
                p.state == ReplicationState.initialSyncInProgress &&
                p.transferredBytes > 0,
          )
          .length;
      log.info(
        'Number of progress updates with byte info: $progressUpdateCount',
      );
      expect(
        progressUpdateCount,
        greaterThan(3),
        reason:
            'Should get multiple progress updates during large attachment sync, '
            'got $progressUpdateCount',
      );

      // Verify attachments were correctly synced
      for (int i = 0; i < attachmentSizes.length; i++) {
        final docId = 'doc_with_large_attachment_$i';
        final attachment = await offlineDb.getAttachment(
          docId,
          'large_file_$i.bin',
        );
        expect(
          attachment,
          isNotNull,
          reason: 'Attachment for $docId should exist',
        );
        expect(
          attachment!.length,
          equals(attachmentSizes[i]),
          reason: 'Attachment size for $docId should be ${attachmentSizes[i]}',
        );
      }
      log.info('All attachments verified');
      log.info('Test completed successfully');
    },
    timeout: Timeout(Duration(minutes: 10)),
  );
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
}
