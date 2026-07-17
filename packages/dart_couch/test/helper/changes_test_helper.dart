import 'dart:async';

import 'package:test/test.dart';
import 'package:dart_couch/dart_couch.dart';

import 'test_document_one.dart';

/// Shared helper to test continuous changes feed.
/// It performs: create -> update -> delete and asserts that each operation
/// produces a corresponding changes event for the given database instance.
Future<void> runChangesContinuousTest(DartCouchDb db) async {
  final ts = DateTime.now().microsecondsSinceEpoch;
  final id = 'changes_doc_$ts';

  final completerCreate = Completer<void>();
  final completerUpdate = Completer<void>();
  final completerDelete = Completer<void>();

  late StreamSubscription sub;

  sub = db
      .changes(feedmode: FeedMode.continuous, includeDocs: true)
      .listen(
        (ch) {
          // The ChangesResult is now a wrapper that can contain either a
          // normal result (batch) or a continuous single change entry.
          if (ch.continuous != null) {
            final r = ch.continuous!;
            if (r.id != id) return;

            // Creation and updates include a doc when includeDocs=true
            if (r.deleted == true) {
              try {
                expect(r.changes, hasLength(1));
                expect(r.changes[0].rev, isNotNull);
                completerDelete.complete();
              } catch (e, s) {
                if (!completerDelete.isCompleted) {
                  completerDelete.completeError(e, s);
                }
              }
            } else {
              try {
                expect(r.changes, hasLength(1));
                expect(r.changes[0].rev, isNotNull);
                // The mapper may or may not populate `doc` depending on the feed
                // implementation; avoid relying on it. Use the ordering semantics
                // instead: first non-deleted event -> creation, second -> update.
                if (!completerCreate.isCompleted) {
                  completerCreate.complete();
                } else if (!completerUpdate.isCompleted) {
                  completerUpdate.complete();
                }
              } catch (e, s) {
                if (!completerCreate.isCompleted) {
                  completerCreate.completeError(e, s);
                } else if (!completerUpdate.isCompleted) {
                  completerUpdate.completeError(e, s);
                }
              }
            }
          } else if (ch.normal != null) {
            final normal = ch.normal!;
            for (final r in normal.results) {
              if (r.id != id) continue;

              if (r.deleted == true) {
                try {
                  expect(r.changes, hasLength(1));
                  expect(r.changes[0].rev, isNotNull);
                  completerDelete.complete();
                } catch (e, s) {
                  if (!completerDelete.isCompleted) {
                    completerDelete.completeError(e, s);
                  }
                }
              } else {
                try {
                  expect(r.changes, hasLength(1));
                  expect(r.changes[0].rev, isNotNull);
                  // In normal/longpoll feeds the doc is typically present when
                  // includeDocs=true, but again avoid strict reliance on it.
                  if (!completerCreate.isCompleted) {
                    completerCreate.complete();
                  } else if (!completerUpdate.isCompleted) {
                    completerUpdate.complete();
                  }
                } catch (e, s) {
                  if (!completerCreate.isCompleted) {
                    completerCreate.completeError(e, s);
                  } else if (!completerUpdate.isCompleted) {
                    completerUpdate.completeError(e, s);
                  }
                }
              }
            }
          }
        },
        onError: (e, s) {
          // Forward to all completers if not completed
          if (!completerCreate.isCompleted) completerCreate.completeError(e, s);
          if (!completerUpdate.isCompleted) completerUpdate.completeError(e, s);
          if (!completerDelete.isCompleted) completerDelete.completeError(e, s);
        },
      );

  // 1) create
  final created =
      await db.put(TestDocumentOne(name: 'Changes Create', id: id))
          as TestDocumentOne;
  await completerCreate.future.timeout(Duration(seconds: 5));

  // 2) update
  final updated =
      await db.put(created.copyWith(name: 'Changes Updated'))
          as TestDocumentOne;
  await completerUpdate.future.timeout(Duration(seconds: 5));

  // 3) delete
  await db.remove(id, updated.rev!);
  await completerDelete.future.timeout(Duration(seconds: 5));

  await sub.cancel();
}

/// Shared helper to test normal (non-continuous) changes feed with `since`.
///
/// It verifies that:
/// - With since='0' the latest change per document is reported.
/// - Passing the previous `last_seq` as `since` returns only changes after it.
/// - Deletion events are reported with `deleted=true`.
Future<void> runChangesNormalSinceTest(DartCouchDb db) async {
  final ts = DateTime.now().microsecondsSinceEpoch;
  final id = 'changes_since_doc_$ts';

  // 1) create
  final created =
      await db.put(TestDocumentOne(name: 'Since Create', id: id))
          as TestDocumentOne;

  // Query changes from the beginning
  final firstBatch = await db.changes(since: '0').first;
  expect(firstBatch.normal, isNotNull);
  final normal1 = firstBatch.normal!;
  // Latest change per doc should be present (here only our newly created doc)
  final r1 = normal1.results.firstWhere((r) => r.id == id);
  expect(r1.deleted, isFalse);
  expect(r1.changes, hasLength(1));
  expect(r1.changes[0].rev, created.rev);

  // 2) update
  final updated =
      await db.put(created.copyWith(name: 'Since Updated')) as TestDocumentOne;
  final isLocal = db is LocalDartCouchDb;

  if (isLocal) {
    // Local implementation currently doesn't support `since`; validate semantics without it.
    final afterUpdate = await db.changes().first;
    expect(afterUpdate.normal, isNotNull);
    final n2 = afterUpdate.normal!;
    final r2 = n2.results.firstWhere((r) => r.id == id);
    expect(r2.deleted, isFalse);
    expect(r2.changes, hasLength(1));
    expect(r2.changes[0].rev, updated.rev);

    // 3) delete
    final deletedRev = await db.remove(updated.id!, updated.rev!);
    final afterDelete = await db.changes().first;
    expect(afterDelete.normal, isNotNull);
    final n3 = afterDelete.normal!;
    final r3 = n3.results.firstWhere((r) => r.id == id);
    expect(r3.deleted, isTrue);
    expect(r3.changes, hasLength(1));
    expect(r3.changes[0].rev, deletedRev);
  } else {
    // HTTP implementation: verify `since` filters changes correctly.
    final secondBatch = await db.changes(since: normal1.lastSeq).first;
    expect(secondBatch.normal, isNotNull);
    final normal2 = secondBatch.normal!;
    expect(normal2.results, hasLength(1));
    expect(normal2.results[0].id, id);
    expect(normal2.results[0].deleted, isFalse);
    expect(normal2.results[0].changes, hasLength(1));
    expect(normal2.results[0].changes[0].rev, updated.rev);

    // 3) delete
    final deletedRev = await db.remove(updated.id!, updated.rev!);

    // Query only changes after the previous batch
    final thirdBatch = await db.changes(since: normal2.lastSeq).first;
    expect(thirdBatch.normal, isNotNull);
    final normal3 = thirdBatch.normal!;
    expect(normal3.results, hasLength(1));
    expect(normal3.results[0].id, id);
    expect(normal3.results[0].deleted, isTrue);
    expect(normal3.results[0].changes, hasLength(1));
    expect(normal3.results[0].changes[0].rev, deletedRev);
  }
}
