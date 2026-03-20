import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dart_couch/dart_couch.dart';
import 'package:logging/logging.dart';

import 'helper/couch_test_manager.dart';
import 'helper/helper.dart';

/// Fixed-seed random data generator so attachment sizes are reproducible.
Uint8List _generateData(int sizeBytes, {required int seed}) {
  final random = Random(seed);
  return Uint8List.fromList(
    List<int>.generate(sizeBytes, (_) => random.nextInt(256)),
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

void _logMemory(String label) {
  log.info('Memory [$label]: RSS=${_formatBytes(ProcessInfo.currentRss)}');
}

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

  /// Covers four aspects in a single integration test:
  ///
  /// Phase 1 — Large attachment replication under low-memory conditions.
  ///   Creates a document with 12 attachments (10–21 MB each) on the remote
  ///   CouchDB while the OfflineFirstServer is paused (no local replication),
  ///   then restarts the server and verifies that every attachment is correctly
  ///   pulled to the local SQLite store. RSS is sampled before and after to
  ///   give a rough memory-usage picture.
  ///
  /// Phase 2 — Changes-stream notification via HTTP replication.
  ///   Writes a fresh document (with 3 medium attachments) directly to the
  ///   remote HTTP server while the OfflineFirstServer is online. Verifies
  ///   that the local changes stream fires and that all attachments are
  ///   accessible once replication completes.
  ///
  /// Phase 3 — One change event per attachment mutation via replication.
  ///   Applies three sequential mutations to the remote document (replace an
  ///   attachment, delete an attachment, add a new attachment) and asserts
  ///   that each individual mutation propagates as exactly one change event
  ///   in the local changes stream.
  ///
  /// Phase 4 — Same three mutations via the direct OfflineFirstDb API.
  ///   Identical assertions, but the writes go directly to the local database
  ///   rather than through the remote replication path.
  test(
    'large attachment replication memory and changes stream consistency',
    () async {
      const largeDocId = 'large_doc_12_attachments';
      const attCount = 12;

      // Attachment sizes 10 MB … 21 MB (one per index)
      final attSizes = List.generate(attCount, (i) => (10 + i) * 1024 * 1024);

      // ══════════════════════════════════════════════════════════════════════
      // Phase 1 — Write 12 large attachments while offline, then sync.
      //
      //   offlineDb  →  pauseOfflineFirstDb
      //   →  write doc + 12 attachments via direct HTTP
      //   →  resumeOfflineFirstDb  →  offlineDb  →  waitForSync  →  verify
      // ══════════════════════════════════════════════════════════════════════
      log.info('═══ Phase 1: large attachment replication ═══');

      await cm.offlineDb();
      // pauseOfflineFirstDb disposes the OfflineFirstServer so no replication
      // is running while we write the large attachments.
      await cm.pauseOfflineFirstDb();

      log.info(
        'Writing $largeDocId with $attCount large attachments via direct HTTP',
      );
      final httpDbForWrite = await cm.httpDb();

      final largeDocPut = await httpDbForWrite.put(
        CouchDocumentBase(
          id: largeDocId,
          unmappedProps: {
            'description': 'Document with $attCount large attachments',
            'attachmentCount': attCount,
          },
        ),
      );
      var currentRev = largeDocPut.rev!;

      _logMemory('before writing $attCount attachments to HTTP');
      for (int i = 0; i < attCount; i++) {
        final size = attSizes[i];
        log.info('Writing att_$i.bin (${_formatBytes(size)}) to HTTP server');
        currentRev = await httpDbForWrite.saveAttachment(
          largeDocId,
          currentRev,
          'att_$i.bin',
          _generateData(size, seed: i),
          contentType: 'application/octet-stream',
        );
      }
      _logMemory('after writing $attCount attachments to HTTP');

      log.info(
        'Restarting OfflineFirstServer — replication will pull all attachments',
      );
      await cm.resumeOfflineFirstDb();
      final db2 = await cm.offlineDb();

      _logMemory('after restart, before sync');
      final memBeforeSync = ProcessInfo.currentRss;

      // Log replication byte progress (includes RSS) so memory behaviour during
      // large-attachment sync is visible in the test output.
      db2.replicationController.progress.addListener(() {
        final p = db2.replicationController.progress.value;
        if (p.totalBytesEstimate != null) {
          log.info(
            'Replication progress: ${p.transferredDocs} docs '
            '${_formatBytes(p.transferredBytes)} / '
            '${_formatBytes(p.totalBytesEstimate!)} '
            '(${(p.progressFraction * 100).toStringAsFixed(1)}%) '
            'RSS=${_formatBytes(ProcessInfo.currentRss)}',
          );
        }
      });

      // Large attachments can take a long time to replicate.
      log.info('Waiting for large-attachment sync (up to 5 min)');
      await waitForSync(db2, maxSeconds: 300);
      _logMemory('after sync complete');

      final memAfterSync = ProcessInfo.currentRss;
      log.info(
        'RSS change during sync: ${_formatBytes(memAfterSync - memBeforeSync)} '
        '(before=${_formatBytes(memBeforeSync)}, '
        'after=${_formatBytes(memAfterSync)})',
      );

      // Verify every attachment is locally stored and has the correct byte count.
      log.info('Verifying all $attCount attachments locally');
      for (int i = 0; i < attCount; i++) {
        final att = await db2.getAttachment(largeDocId, 'att_$i.bin');
        expect(
          att,
          isNotNull,
          reason: 'att_$i.bin must be replicated to the local store',
        );
        expect(
          att!.length,
          equals(attSizes[i]),
          reason:
              'att_$i.bin: expected ${_formatBytes(attSizes[i])}, '
              'got ${_formatBytes(att.length)}',
        );
        log.info('att_$i.bin verified (${_formatBytes(att.length)}) ✓');
      }
      log.info('═══ Phase 1 complete ═══');

      // ══════════════════════════════════════════════════════════════════════
      // Phase 2 — Changes stream receives notification via replication.
      //
      //   Start a continuous changes stream on the OfflineFirstDb (since the
      //   current local sequence, so Phase 1 events are excluded).  Write a
      //   new document with 3 medium attachments to the remote HTTP server.
      //   After replication, the local changes stream must have fired, and
      //   all three attachments must be accessible locally.
      // ══════════════════════════════════════════════════════════════════════
      log.info('═══ Phase 2: changes stream via HTTP replication ═══');

      // Capture the local update-seq after Phase 1 so the listener only sees
      // changes that happen from this point onward.
      final seqAfterPhase1 = (await db2.info())!.updateSeq;
      log.info('Changes stream starting from local seq: $seqAfterPhase1');

      // Shared collector for Phases 2–4.
      final allChanges = <ChangeEntry>[];
      final changeSub = db2
          .changes(since: seqAfterPhase1, feedmode: FeedMode.continuous)
          .listen((event) {
            if (event.type != ChangesResultType.continuous) return;
            final entry = event.continuous!;
            log.info('Change event: id=${entry.id}  seq=${entry.seq}');
            allChanges.add(entry);
          });

      /// Returns how many change events have been collected for [id].
      int eventsFor(String id) => allChanges.where((e) => e.id == id).length;

      // Write a new document + 3 × 1 MB attachments to the remote server.
      // All writes happen before replication has a chance to pick them up so
      // the replication sees only the final revision and fires a single local
      // change event.
      const changesDocId = 'changes_stream_doc';
      final remoteDb = await cm.httpDb();

      log.info('Writing $changesDocId + 3 attachments to remote HTTP');
      final changesDocPut = await remoteDb.put(
        CouchDocumentBase(id: changesDocId, unmappedProps: {'phase': 2}),
      );
      var changesDocRev = changesDocPut.rev!;
      for (int i = 0; i < 3; i++) {
        changesDocRev = await remoteDb.saveAttachment(
          changesDocId,
          changesDocRev,
          'att_$i.bin',
          _generateData(1 * 1024 * 1024, seed: 100 + i),
          contentType: 'application/octet-stream',
        );
      }

      // Live continuous replication delivers one event per document revision.
      // We wrote 4 revisions (put + 3 × saveAttachment), so replication fires
      // up to 4 change events for changes_stream_doc — one each time a new
      // revision lands on the remote.  First confirm the stream fired at all:
      log.info('Waiting for $changesDocId to arrive in local changes stream');
      final phase2EventArrived = await waitForCondition(
        () async => eventsFor(changesDocId) >= 1,
        maxAttempts: 120,
        interval: Duration(milliseconds: 500),
      );
      expect(
        phase2EventArrived,
        isTrue,
        reason: 'At least one change event for $changesDocId must arrive',
      );

      // Wait until ALL 3 attachments are locally accessible.  This confirms
      // the final revision (att_2.bin) has been fully replicated before we
      // move to Phase 3 and start counting new events.
      for (int i = 0; i < 3; i++) {
        final attAvailable = await waitForCondition(
          () async =>
              await db2.getAttachment(changesDocId, 'att_$i.bin') != null,
          maxAttempts: 120,
          interval: Duration(milliseconds: 500),
        );
        expect(
          attAvailable,
          isTrue,
          reason: 'att_$i.bin must be locally accessible after replication',
        );
        final att = await db2.getAttachment(changesDocId, 'att_$i.bin');
        expect(att!.length, equals(1 * 1024 * 1024));
      }
      log.info('═══ Phase 2 complete ═══');

      // ══════════════════════════════════════════════════════════════════════
      // Phase 3 — One change event per attachment mutation via replication.
      //
      //   Each of the three mutations (replace, delete, add) is applied to the
      //   remote HTTP server.  We wait until a new change event for the
      //   document arrives locally, then verify exactly one event was added
      //   and that the local attachment state reflects the mutation.
      // ══════════════════════════════════════════════════════════════════════
      log.info('═══ Phase 3: attachment mutations via remote HTTP ═══');

      // 3a — Replace att_0.bin with smaller data (same attachment name → update)
      log.info('3a: replacing att_0.bin on $changesDocId via HTTP');
      final beforeReplace = eventsFor(changesDocId);
      changesDocRev = await remoteDb.saveAttachment(
        changesDocId,
        changesDocRev,
        'att_0.bin',
        _generateData(512 * 1024, seed: 200),
        contentType: 'application/octet-stream',
      );
      final replaceArrived = await waitForCondition(
        () async => eventsFor(changesDocId) > beforeReplace,
        maxAttempts: 120,
        interval: Duration(milliseconds: 500),
      );
      expect(replaceArrived, isTrue, reason: 'Replace event must arrive');
      // Allow a brief window so that any spurious second event can land before
      // we check the exact count.
      await Future.delayed(Duration(milliseconds: 300));
      expect(
        eventsFor(changesDocId) - beforeReplace,
        equals(1),
        reason: 'Replacing an attachment via HTTP must produce exactly 1 event',
      );
      final replacedAtt = await db2.getAttachment(changesDocId, 'att_0.bin');
      expect(replacedAtt, isNotNull);
      expect(
        replacedAtt!.length,
        equals(512 * 1024),
        reason: 'Replaced att_0.bin must have the new byte size locally',
      );

      // 3b — Delete att_1.bin
      log.info('3b: deleting att_1.bin from $changesDocId via HTTP');
      final beforeDelete = eventsFor(changesDocId);
      await remoteDb.deleteAttachment(changesDocId, changesDocRev, 'att_1.bin');
      changesDocRev = (await remoteDb.get(changesDocId))!.rev!;
      final deleteArrived = await waitForCondition(
        () async => eventsFor(changesDocId) > beforeDelete,
        maxAttempts: 120,
        interval: Duration(milliseconds: 500),
      );
      expect(deleteArrived, isTrue, reason: 'Delete event must arrive');
      await waitForCondition(
        () async => false,
        maxAttempts: 1,
        interval: Duration(milliseconds: 300),
      );
      expect(
        eventsFor(changesDocId) - beforeDelete,
        equals(1),
        reason: 'Deleting an attachment via HTTP must produce exactly 1 event',
      );
      expect(
        await db2.getAttachment(changesDocId, 'att_1.bin'),
        isNull,
        reason: 'att_1.bin must be absent locally after remote deletion',
      );

      // 3c — Add a brand-new attachment
      log.info('3c: adding new_att.bin to $changesDocId via HTTP');
      final beforeAdd = eventsFor(changesDocId);
      changesDocRev = await remoteDb.saveAttachment(
        changesDocId,
        changesDocRev,
        'new_att.bin',
        _generateData(256 * 1024, seed: 300),
        contentType: 'application/octet-stream',
      );
      final addArrived = await waitForCondition(
        () async => eventsFor(changesDocId) > beforeAdd,
        maxAttempts: 120,
        interval: Duration(milliseconds: 500),
      );
      expect(addArrived, isTrue, reason: 'Add event must arrive');
      await waitForCondition(
        () async => false,
        maxAttempts: 1,
        interval: Duration(milliseconds: 300),
      );
      expect(
        eventsFor(changesDocId) - beforeAdd,
        equals(1),
        reason: 'Adding a new attachment via HTTP must produce exactly 1 event',
      );
      final addedAtt = await db2.getAttachment(changesDocId, 'new_att.bin');
      expect(addedAtt, isNotNull);
      expect(addedAtt!.length, equals(256 * 1024));

      log.info(
        '═══ Phase 3 complete: each remote mutation → 1 change event ═══',
      );

      // ══════════════════════════════════════════════════════════════════════
      // Phase 4 — Same three mutations via direct OfflineFirstDb API.
      //
      //   Writes go directly to the local SQLite store (bypassing replication).
      //   Change events must fire immediately after the local write commits.
      // ══════════════════════════════════════════════════════════════════════
      log.info(
        '═══ Phase 4: attachment mutations via direct OfflineFirstDb API ═══',
      );

      // Create a fresh document for Phase 4 so Phase 3 events don't interfere.
      const directDocId = 'direct_api_doc';
      final directDocPut = await db2.put(
        CouchDocumentBase(id: directDocId, unmappedProps: {'phase': 4}),
      );
      var directRev = directDocPut.rev!;

      // Seed the document with two attachments to mirror the starting state
      // used in Phase 3 (doc has att_0 and att_1, so 4a/4b/4c are symmetric).
      directRev = await db2.saveAttachment(
        directDocId,
        directRev,
        'direct_att_0.bin',
        _generateData(256 * 1024, seed: 400),
        contentType: 'application/octet-stream',
      );
      directRev = await db2.saveAttachment(
        directDocId,
        directRev,
        'direct_att_1.bin',
        _generateData(256 * 1024, seed: 401),
        contentType: 'application/octet-stream',
      );

      // Wait until all three setup events (put + 2 × saveAttachment) have
      // arrived in the changes stream before starting the Phase 4 checks.
      await waitForCondition(
        () async => eventsFor(directDocId) >= 3,
        maxAttempts: 40,
        interval: Duration(milliseconds: 100),
      );

      // 4a — Replace direct_att_0.bin via direct API
      log.info('4a: replacing direct_att_0.bin via direct API');
      final beforeDirectReplace = eventsFor(directDocId);
      directRev = await db2.saveAttachment(
        directDocId,
        directRev,
        'direct_att_0.bin',
        _generateData(128 * 1024, seed: 500),
        contentType: 'application/octet-stream',
      );
      final directReplaceArrived = await waitForCondition(
        () async => eventsFor(directDocId) > beforeDirectReplace,
        maxAttempts: 40,
        interval: Duration(milliseconds: 100),
      );
      expect(
        directReplaceArrived,
        isTrue,
        reason: 'Direct API replace event must arrive',
      );
      await Future.delayed(Duration(milliseconds: 200));
      expect(
        eventsFor(directDocId) - beforeDirectReplace,
        equals(1),
        reason:
            'Direct API replacement of an attachment must produce exactly '
            '1 change event',
      );

      // 4b — Delete direct_att_1.bin via direct API
      log.info('4b: deleting direct_att_1.bin via direct API');
      final beforeDirectDelete = eventsFor(directDocId);
      await db2.deleteAttachment(directDocId, directRev, 'direct_att_1.bin');
      directRev = (await db2.get(directDocId))!.rev!;
      final directDeleteArrived = await waitForCondition(
        () async => eventsFor(directDocId) > beforeDirectDelete,
        maxAttempts: 40,
        interval: Duration(milliseconds: 100),
      );
      expect(
        directDeleteArrived,
        isTrue,
        reason: 'Direct API delete event must arrive',
      );
      await Future.delayed(Duration(milliseconds: 200));
      expect(
        eventsFor(directDocId) - beforeDirectDelete,
        equals(1),
        reason:
            'Direct API deletion of an attachment must produce exactly '
            '1 change event',
      );
      expect(
        await db2.getAttachment(directDocId, 'direct_att_1.bin'),
        isNull,
        reason: 'direct_att_1.bin must be absent after direct API deletion',
      );

      // 4c — Add a new attachment via direct API
      log.info('4c: adding direct_new_att.bin via direct API');
      final beforeDirectAdd = eventsFor(directDocId);
      await db2.saveAttachment(
        directDocId,
        directRev,
        'direct_new_att.bin',
        _generateData(128 * 1024, seed: 600),
        contentType: 'application/octet-stream',
      );
      final directAddArrived = await waitForCondition(
        () async => eventsFor(directDocId) > beforeDirectAdd,
        maxAttempts: 40,
        interval: Duration(milliseconds: 100),
      );
      expect(
        directAddArrived,
        isTrue,
        reason: 'Direct API add event must arrive',
      );
      await Future.delayed(Duration(milliseconds: 200));
      expect(
        eventsFor(directDocId) - beforeDirectAdd,
        equals(1),
        reason:
            'Direct API addition of a new attachment must produce exactly '
            '1 change event',
      );
      final directAddedAtt = await db2.getAttachment(
        directDocId,
        'direct_new_att.bin',
      );
      expect(directAddedAtt, isNotNull);
      expect(directAddedAtt!.length, equals(128 * 1024));

      log.info(
        '═══ Phase 4 complete: each direct API mutation → 1 change event ═══',
      );

      await changeSub.cancel();
      log.info('═══ Test complete ═══');
    },
    timeout: Timeout(Duration(minutes: 20)),
  );
}
