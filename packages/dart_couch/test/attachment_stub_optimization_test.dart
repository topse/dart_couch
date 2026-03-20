import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dart_couch/dart_couch.dart';
import 'package:logging/logging.dart';

import 'helper/couch_test_manager.dart';
import 'helper/helper.dart';

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

  /// Verifies that unchanged attachments are transmitted as lightweight stubs
  /// (no blob data) during replication, while modified attachments are
  /// re-transferred in full.
  ///
  /// Setup:
  ///   - Create a document with three attachments and push to CouchDB.
  ///   - Directly on the server: delete one attachment, modify another,
  ///     leave the third untouched.
  ///   - Wait for the pull replication.
  ///
  /// Expected:
  ///   - `att_keep.txt` (unchanged) is NEVER written — its blob is never
  ///     re-transferred regardless of how many intermediate revisions are pulled.
  ///   - `att_modify.txt` (changed) IS written at least once — blob transferred
  ///     when the revision containing the new content is pulled.
  ///   - `att_delete.txt` produces neither a write nor a skip log — it is simply
  ///     absent from all pulled revisions and cleaned up by orphan-delete logic.
  test('unchanged attachments are skipped as stubs during pull replication', () async {
    const docId = 'attach_opt1';

    final db = await cm.offlineDb();

    // ── Step 1: create document with three attachments locally ──────────
    log.info('Step 1: Creating document with three attachments');

    final doc = CouchDocumentBase(
      id: docId,
      unmappedProps: {'name': 'Attachment Stub Optimization Test'},
    );
    final putResult = await db.put(doc);

    // Save attachments sequentially; each call returns the new rev.
    final rev1 = await db.saveAttachment(
      docId,
      putResult.rev!,
      'att_delete.txt',
      Uint8List.fromList(utf8.encode('will be deleted')),
      contentType: 'text/plain',
    );
    final rev2 = await db.saveAttachment(
      docId,
      rev1,
      'att_modify.txt',
      Uint8List.fromList(utf8.encode('original content')),
      contentType: 'text/plain',
    );
    await db.saveAttachment(
      docId,
      rev2,
      'att_keep.txt',
      Uint8List.fromList(utf8.encode('unchanged content')),
      contentType: 'text/plain',
    );

    // ── Step 2: wait for the initial push sync (all 3 attachments → CouchDB)
    log.info('Step 2: Waiting for initial push sync');
    await waitForSync(db, maxSeconds: 15);

    // Sanity-check: all three attachments must be on the server.
    final serverDb = await cm.httpDb();
    final serverDocBefore = await serverDb.get(docId);
    expect(serverDocBefore, isNotNull);
    expect(
      serverDocBefore!.attachments?.containsKey('att_delete.txt'),
      isTrue,
      reason: 'att_delete.txt should be on the server after initial push',
    );
    expect(
      serverDocBefore.attachments?.containsKey('att_modify.txt'),
      isTrue,
      reason: 'att_modify.txt should be on the server after initial push',
    );
    expect(
      serverDocBefore.attachments?.containsKey('att_keep.txt'),
      isTrue,
      reason: 'att_keep.txt should be on the server after initial push',
    );

    // ── Step 3: start log capture ────────────────────────────────────────
    // Start BEFORE server changes so we don't miss a fast pull triggered by
    // the continuous replication listener.
    log.info('Step 3: Starting log capture');
    final writeLogs = <String>[];
    final skipLogs = <String>[];
    final logSub = Logger.root.onRecord.listen((record) {
      final msg = record.message;
      if (msg.contains('Replication: writing attachment') &&
          msg.contains(docId)) {
        writeLogs.add(msg);
      }
      if (msg.contains('Replication: skipping stub attachment') &&
          msg.contains(docId)) {
        skipLogs.add(msg);
      }
    });

    // ── Step 4: make server-side modifications ───────────────────────────
    log.info('Step 4: Modifying attachments directly on CouchDB server');

    // Delete att_delete.txt.
    await serverDb.deleteAttachment(
      docId,
      serverDocBefore.rev!,
      'att_delete.txt',
    );

    // Fetch updated doc to get the new rev after the delete.
    final serverDocAfterDelete = await serverDb.get(docId);
    expect(serverDocAfterDelete, isNotNull);

    // Overwrite att_modify.txt with new content (att_keep.txt untouched).
    await serverDb.saveAttachment(
      docId,
      serverDocAfterDelete!.rev!,
      'att_modify.txt',
      Uint8List.fromList(utf8.encode('modified content')),
      contentType: 'text/plain',
    );

    // ── Step 5: wait for the pull sync ───────────────────────────────────
    // Wait directly for the observable outcome: att_modify.txt has the new
    // content locally. This handles any number of replication passes without
    // relying on intermediate state signals like "inSync".
    log.info('Step 5: Waiting for pull sync');
    final synced = await waitForCondition(
      () async {
        final data = await db.localDb.getAttachment(docId, 'att_modify.txt');
        return data != null && utf8.decode(data) == 'modified content';
      },
      maxAttempts: 75, // 75 × 200 ms = 15 s
      interval: Duration(milliseconds: 200),
    );
    expect(synced, isTrue, reason: 'att_modify.txt never reached new content');

    await logSub.cancel();

    // ── Step 6: assert log messages ──────────────────────────────────────
    // Note: the server-side delete and modify are two separate CouchDB
    // revisions that continuous replication may pull independently.
    // Because of that, the exact skip/write count is non-deterministic:
    //   • The delete revision pulls att_modify.txt and att_keep.txt as stubs
    //     (neither changed in that revision).
    //   • The modify revision pulls att_modify.txt with blob data (changed)
    //     and att_keep.txt again as a stub.
    // We therefore assert the invariants that matter for the optimization:
    //   1. att_keep.txt is NEVER written (its blob is never re-transferred).
    //   2. att_modify.txt IS written at least once (blob transferred when
    //      content actually changed).
    //   3. att_delete.txt appears in neither list (absent from all revisions).
    log.info(
      'Step 6: Checking logs — writes: ${writeLogs.length}, skips: ${skipLogs.length}',
    );
    log.info('Write logs: $writeLogs');
    log.info('Skip logs:  $skipLogs');

    // att_keep.txt must never be written — its blob must not be re-transferred.
    expect(
      writeLogs.any((msg) => msg.contains('att_keep.txt')),
      isFalse,
      reason:
          'att_keep.txt is unchanged and must never appear in write logs, '
          'but got: $writeLogs',
    );

    // att_modify.txt must be written at least once — its content changed.
    expect(
      writeLogs.any((msg) => msg.contains('att_modify.txt')),
      isTrue,
      reason:
          'att_modify.txt content changed on the server and must appear in '
          'write logs at least once, but got: $writeLogs',
    );

    // att_keep.txt must appear in skip logs (the optimization fired).
    expect(
      skipLogs.any((msg) => msg.contains('att_keep.txt')),
      isTrue,
      reason:
          'att_keep.txt is unchanged and must appear in skip logs at least '
          'once, but got: $skipLogs',
    );

    // att_delete.txt must appear in neither list.
    final allLogs = [...writeLogs, ...skipLogs];
    expect(
      allLogs.any((msg) => msg.contains('att_delete.txt')),
      isFalse,
      reason:
          'att_delete.txt was deleted and should not appear in write or skip logs',
    );

    // ── Step 7: verify final local document state ─────────────────────────
    log.info('Step 7: Verifying final local document state');

    final localDoc = await db.localDb.get(docId);
    expect(localDoc, isNotNull);
    expect(
      localDoc!.attachments?.containsKey('att_delete.txt'),
      isFalse,
      reason: 'att_delete.txt should have been removed from the local doc',
    );
    expect(
      localDoc.attachments?.containsKey('att_modify.txt'),
      isTrue,
      reason: 'att_modify.txt should still be present in the local doc',
    );
    expect(
      localDoc.attachments?.containsKey('att_keep.txt'),
      isTrue,
      reason: 'att_keep.txt should still be present in the local doc',
    );

    final modifiedContent = await db.localDb.getAttachment(
      docId,
      'att_modify.txt',
    );
    expect(
      utf8.decode(modifiedContent!),
      equals('modified content'),
      reason: 'att_modify.txt should contain the server-side modification',
    );

    final keptContent = await db.localDb.getAttachment(docId, 'att_keep.txt');
    expect(
      utf8.decode(keptContent!),
      equals('unchanged content'),
      reason: 'att_keep.txt content must be unchanged',
    );

    log.info('Test passed — stub optimization working correctly');
  });
}
