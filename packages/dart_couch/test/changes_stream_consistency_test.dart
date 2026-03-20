import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dart_couch/dart_couch.dart';
import 'package:logging/logging.dart';

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

  group('LocalDartCouchDb changes stream consistency during replication', () {
    late LocalDartCouchServer server;
    late DartCouchDb db;

    setUp(() async {
      server = LocalDartCouchServer(prepareSqliteDir());
      db = await server.createDatabase('changes_test');
    });

    tearDown(() async {
      await server.dispose();
    });

    /// Verifies that replicating a document with multiple attachments via
    /// bulkDocsRaw (newEdits=false) results in exactly ONE change event,
    /// and that at the moment the event fires all attachments are already
    /// written and immediately readable.
    ///
    /// Architecture guarantee being tested:
    ///   All attachment writes happen inside the same db.transaction() as the
    ///   document row update. The changes stream (backed by Drift's
    ///   query.watch()) is only notified after the transaction commits. A
    ///   consumer therefore can never observe a partially-written document.
    test(
      'replicating a document with multiple attachments fires exactly one change event and all attachments are accessible immediately',
      () async {
        const docId = 'doc_with_attachments';
        const att1Content = 'content one';
        const att2Content = 'content two';
        const att3Content = 'content three';

        Uint8List? att1AtChangeTime;
        Uint8List? att2AtChangeTime;
        Uint8List? att3AtChangeTime;
        final changeEvents = <ChangeEntry>[];
        // Completed once all three attachment reads inside the listener finish.
        final readsDone = Completer<void>();

        final sub = db.changes(since: '0', feedmode: FeedMode.continuous).listen(
          (event) async {
            if (event.type != ChangesResultType.continuous) return;
            changeEvents.add(event.continuous!);

            // Read all three attachments at the exact moment the change fires.
            // They must already be present — writes happen before the
            // transaction commits and the watch fires after commit.
            att1AtChangeTime = await db.getAttachment(docId, 'att1.txt');
            att2AtChangeTime = await db.getAttachment(docId, 'att2.txt');
            att3AtChangeTime = await db.getAttachment(docId, 'att3.txt');

            if (!readsDone.isCompleted) readsDone.complete();
          },
        );

        log.info('Replicating document with 3 attachments via bulkDocsRaw');
        await db.bulkDocsRaw([
          jsonEncode({
            '_id': docId,
            '_rev': '1-abc123',
            '_revisions': {
              'start': 1,
              'ids': ['abc123'],
            },
            '_attachments': {
              'att1.txt': {
                'content_type': 'application/octet-stream',
                'revpos': 1,
                'data': base64Encode(utf8.encode(att1Content)),
              },
              'att2.txt': {
                'content_type': 'application/octet-stream',
                'revpos': 1,
                'data': base64Encode(utf8.encode(att2Content)),
              },
              'att3.txt': {
                'content_type': 'application/octet-stream',
                'revpos': 1,
                'data': base64Encode(utf8.encode(att3Content)),
              },
            },
          }),
        ], newEdits: false);

        // Wait until the listener has finished reading all three attachments.
        await readsDone.future.timeout(
          Duration(seconds: 5),
          onTimeout: () => throw TimeoutException(
            'No change event received within 5 seconds',
          ),
        );
        await sub.cancel();

        // Exactly one change event for one replicated document.
        expect(
          changeEvents,
          hasLength(1),
          reason:
              'One replicated document must produce exactly one changes event',
        );
        expect(changeEvents.first.id, equals(docId));

        // All three attachments were accessible at the moment the change fired.
        expect(
          att1AtChangeTime,
          isNotNull,
          reason: 'att1.txt must be accessible when the change event fires',
        );
        expect(utf8.decode(att1AtChangeTime!), equals(att1Content));

        expect(
          att2AtChangeTime,
          isNotNull,
          reason: 'att2.txt must be accessible when the change event fires',
        );
        expect(utf8.decode(att2AtChangeTime!), equals(att2Content));

        expect(
          att3AtChangeTime,
          isNotNull,
          reason: 'att3.txt must be accessible when the change event fires',
        );
        expect(utf8.decode(att3AtChangeTime!), equals(att3Content));
      },
    );

    /// Verifies that replicating a batch of N documents in a single
    /// bulkDocsRaw call fires exactly N change events — one per document —
    /// and that each document's attachment is accessible when its event fires.
    test(
      'replicating a batch of documents fires exactly one change event per document with attachments accessible immediately',
      () async {
        const docCount = 3;
        final contents = List.generate(docCount, (i) => 'batch content $i');

        // Map from docId → attachment data read at change time.
        final attachmentsAtChangeTime = <String, Uint8List?>{};
        final changeEvents = <ChangeEntry>[];
        // Counts how many listener callbacks have fully completed their async
        // getAttachment read. Complete only after ALL reads finish — not after
        // all events are added — because the three async listener callbacks
        // run concurrently and a read from one may complete before the others.
        var readsCompleted = 0;
        final allReadsDone = Completer<void>();

        final sub = db
            .changes(since: '0', feedmode: FeedMode.continuous)
            .listen((event) async {
              if (event.type != ChangesResultType.continuous) return;
              final entry = event.continuous!;
              changeEvents.add(entry);

              // Read the attachment immediately when its change fires.
              attachmentsAtChangeTime[entry.id] = await db.getAttachment(
                entry.id,
                'file.bin',
              );

              readsCompleted++;
              if (readsCompleted >= docCount && !allReadsDone.isCompleted) {
                allReadsDone.complete();
              }
            });

        log.info('Replicating batch of $docCount documents via bulkDocsRaw');
        await db.bulkDocsRaw(
          List.generate(
            docCount,
            (i) => jsonEncode({
              '_id': 'batch_doc_$i',
              '_rev': '1-hash$i',
              '_revisions': {
                'start': 1,
                'ids': ['hash$i'],
              },
              '_attachments': {
                'file.bin': {
                  'content_type': 'application/octet-stream',
                  'revpos': 1,
                  'data': base64Encode(utf8.encode(contents[i])),
                },
              },
            }),
          ),
          newEdits: false,
        );

        await allReadsDone.future.timeout(
          Duration(seconds: 5),
          onTimeout: () => throw TimeoutException(
            'Did not receive $docCount change events within 5 seconds',
          ),
        );
        await sub.cancel();

        // Exactly one change event per document.
        expect(
          changeEvents,
          hasLength(docCount),
          reason:
              'Batch of $docCount documents must produce exactly $docCount changes events',
        );

        // Each document's attachment was accessible at its change time.
        for (int i = 0; i < docCount; i++) {
          final docId = 'batch_doc_$i';
          expect(
            attachmentsAtChangeTime[docId],
            isNotNull,
            reason: 'file.bin for $docId must be accessible at change time',
          );
          expect(
            utf8.decode(attachmentsAtChangeTime[docId]!),
            equals(contents[i]),
          );
        }
      },
    );
  });
}
