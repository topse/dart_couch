import 'package:drift/drift.dart';
import 'package:test/test.dart';

import 'package:dart_couch/src/local_storage_engine/database.dart';
import 'package:dart_couch/src/local_storage_engine/database_connection.dart';

import 'helper/helper.dart';

/// Direct tests of the Drift data layer (the SQLite storage engine), exercising
/// the `local_conflict_revisions` table (PLAN.md Decision A2), conflict-leaf
/// attachments (`local_attachments.fkconflict`, Stage 2) and the EXISTING
/// tables/triggers. Runs against a fresh in-memory database (schema v6 via
/// `onCreate`), so it doubles as the regression check for the schema adds.
///
/// Focus per the cascade/no-orphan requirement: deleting a document or a whole
/// database must leave ZERO orphaned rows in any child table — including the new
/// conflict table.
void main() {
  configureTestLogging();

  late AppDatabase db;

  setUp(() {
    // file: null → in-memory NativeDatabase, opened at the current schemaVersion
    // through onCreate (so all v5 tables + triggers exist).
    db = AppDatabase(openDatabaseConnection());
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertDb(String name) => db
      .into(db.localDatabases)
      .insert(LocalDatabasesCompanion(name: Value(name)));

  Future<int> insertWinnerDoc(
    int dbId,
    String docid,
    String rev,
    int version,
  ) => db
      .into(db.localDocuments)
      .insert(
        LocalDocumentsCompanion(
          fkdatabase: Value(dbId),
          docid: Value(docid),
          rev: Value(rev),
          version: Value(version),
          deleted: const Value(false),
          seq: Value(version),
        ),
      );

  Future<int> insertConflict(int docRowId, String rev, int version) => db
      .into(db.localConflictRevisions)
      .insert(
        LocalConflictRevisionsCompanion(
          fkdocument: Value(docRowId),
          rev: Value(rev),
          version: Value(version),
          deleted: const Value(false),
          body: Value('{"_id":"doc","_rev":"$rev"}'),
        ),
      );

  Future<int> count(TableInfo table) async =>
      (await db.select(table).get()).length;

  Future<int> insertWinnerAttachment(int docRowId, String name) => db
      .into(db.localAttachments)
      .insert(
        LocalAttachmentsCompanion(
          fkdocument: Value(docRowId),
          ordering: const Value(1),
          revpos: const Value(1),
          name: Value(name),
          length: const Value(3),
          contentType: const Value('text/plain'),
          digest: const Value('md5-w'),
        ),
      );

  Future<int> insertConflictAttachment(
    int docRowId,
    int conflictRowId,
    String name,
  ) => db
      .into(db.localAttachments)
      .insert(
        LocalAttachmentsCompanion(
          fkdocument: Value(docRowId),
          fkconflict: Value(conflictRowId),
          ordering: const Value(1),
          revpos: const Value(2),
          name: Value(name),
          length: const Value(3),
          contentType: const Value('text/plain'),
          digest: const Value('md5-c'),
        ),
      );

  group('schema v6', () {
    test('schemaVersion is 6', () {
      expect(db.schemaVersion, 6);
    });

    test('local_conflict_revisions exists and starts empty', () async {
      expect(await db.select(db.localConflictRevisions).get(), isEmpty);
    });
  });

  group('existing cascade triggers (v5 regression)', () {
    test('deleting a document cascades blob, attachment and history', () async {
      final dbId = await insertDb('db1');
      final docRow = await insertWinnerDoc(dbId, 'doc', '1-a', 1);
      await db
          .into(db.documentBlobs)
          .insert(
            DocumentBlobsCompanion(
              documentId: Value(docRow),
              data: const Value('{}'),
            ),
          );
      await db
          .into(db.localAttachments)
          .insert(
            LocalAttachmentsCompanion(
              fkdocument: Value(docRow),
              ordering: const Value(1),
              revpos: const Value(1),
              name: const Value('a.txt'),
              length: const Value(3),
              contentType: const Value('text/plain'),
              digest: const Value('md5-x'),
            ),
          );

      // The after-insert trigger already recorded one revision_history row.
      expect(await count(db.revisionHistories), 1);

      await (db.delete(db.localDocuments)
            ..where((t) => t.id.equals(docRow)))
          .go();

      expect(await count(db.documentBlobs), 0);
      expect(await count(db.localAttachments), 0);
      expect(await count(db.revisionHistories), 0);
    });
  });

  group('local_conflict_revisions cascade — no orphans', () {
    test('deleting a document removes its conflict revisions', () async {
      final dbId = await insertDb('db1');
      final docRow = await insertWinnerDoc(dbId, 'doc', '2-bbbb', 2);
      await insertConflict(docRow, '2-aaaa', 2);
      await insertConflict(docRow, '2-cccc', 2);
      expect(await count(db.localConflictRevisions), 2);

      await (db.delete(db.localDocuments)
            ..where((t) => t.id.equals(docRow)))
          .go();

      expect(
        await count(db.localConflictRevisions),
        0,
        reason: 'conflict revisions orphaned after document delete',
      );
    });

    test('deleting a database cascades down to conflict revisions', () async {
      final dbId = await insertDb('db1');
      final docRow = await insertWinnerDoc(dbId, 'doc', '2-bbbb', 2);
      await insertConflict(docRow, '2-aaaa', 2);
      expect(await count(db.localConflictRevisions), 1);

      await db.deleteDatabase('db1');

      expect(await count(db.localDocuments), 0);
      expect(
        await count(db.localConflictRevisions),
        0,
        reason: 'conflict revisions orphaned after database delete',
      );
    });

    test('conflict revisions of OTHER docs are not affected by a delete', () async {
      final dbId = await insertDb('db1');
      final docA = await insertWinnerDoc(dbId, 'docA', '2-bbbb', 2);
      final docB = await insertWinnerDoc(dbId, 'docB', '2-bbbb', 2);
      await insertConflict(docA, '2-aaaa', 2);
      await insertConflict(docB, '2-aaaa', 2);
      expect(await count(db.localConflictRevisions), 2);

      await (db.delete(db.localDocuments)..where((t) => t.id.equals(docA))).go();

      final remaining = await db.select(db.localConflictRevisions).get();
      expect(remaining, hasLength(1));
      expect(remaining.single.fkdocument, docB);
    });

    test('(fkdocument, rev) is unique', () async {
      final dbId = await insertDb('db1');
      final docRow = await insertWinnerDoc(dbId, 'doc', '2-bbbb', 2);
      await insertConflict(docRow, '2-aaaa', 2);
      await expectLater(
        insertConflict(docRow, '2-aaaa', 2),
        throwsA(anything),
      );
    });
  });

  group('conflict-leaf attachments (v6) — cascade & scoping', () {
    test('deleting a conflict revision removes only its attachment rows', () async {
      final dbId = await insertDb('db1');
      final docRow = await insertWinnerDoc(dbId, 'doc', '2-bbbb', 2);
      final conflictRow = await insertConflict(docRow, '2-aaaa', 2);
      await insertWinnerAttachment(docRow, 'shared.txt'); // winner
      await insertConflictAttachment(docRow, conflictRow, 'shared.txt'); // leaf
      expect(await count(db.localAttachments), 2);

      await db.deleteConflictRevision(docRow, '2-aaaa');

      final rows = await db.select(db.localAttachments).get();
      expect(rows, hasLength(1), reason: 'only the conflict-leaf row removed');
      expect(rows.single.fkconflict, null, reason: 'winner row survives');
    });

    test('tombstoning the winner keeps conflict-leaf attachments', () async {
      final dbId = await insertDb('db1');
      final docRow = await insertWinnerDoc(dbId, 'doc', '2-bbbb', 2);
      final conflictRow = await insertConflict(docRow, '2-aaaa', 2);
      await insertWinnerAttachment(docRow, 'w.txt');
      await insertConflictAttachment(docRow, conflictRow, 'c.txt');

      // Tombstone the winner (UPDATE deleted=1) → cleanup_attachments_on_tombstone.
      await (db.update(db.localDocuments)..where((t) => t.id.equals(docRow)))
          .write(const LocalDocumentsCompanion(deleted: Value(true)));

      final rows = await db.select(db.localAttachments).get();
      expect(
        rows,
        hasLength(1),
        reason: 'winner attachment dropped on tombstone, conflict leaf survives',
      );
      expect(rows.single.fkconflict, conflictRow);
    });

    test('deleting the document removes BOTH winner and conflict-leaf attachments', () async {
      final dbId = await insertDb('db1');
      final docRow = await insertWinnerDoc(dbId, 'doc', '2-bbbb', 2);
      final conflictRow = await insertConflict(docRow, '2-aaaa', 2);
      await insertWinnerAttachment(docRow, 'w.txt');
      await insertConflictAttachment(docRow, conflictRow, 'c.txt');
      expect(await count(db.localAttachments), 2);

      await (db.delete(db.localDocuments)..where((t) => t.id.equals(docRow)))
          .go();

      expect(
        await count(db.localAttachments),
        0,
        reason: 'hard document delete must leave no orphaned attachment rows',
      );
    });

    test('deleting the database cascades to conflict-leaf attachments', () async {
      final dbId = await insertDb('db1');
      final docRow = await insertWinnerDoc(dbId, 'doc', '2-bbbb', 2);
      final conflictRow = await insertConflict(docRow, '2-aaaa', 2);
      await insertConflictAttachment(docRow, conflictRow, 'c.txt');

      await db.deleteDatabase('db1');

      expect(await count(db.localAttachments), 0);
    });

    test('getAttachments(winner) excludes conflict-leaf rows; conflict queries are scoped', () async {
      final dbId = await insertDb('db1');
      final docRow = await insertWinnerDoc(dbId, 'doc', '2-bbbb', 2);
      final conflictRow = await insertConflict(docRow, '2-aaaa', 2);
      await insertWinnerAttachment(docRow, 'shared.txt');
      await insertConflictAttachment(docRow, conflictRow, 'shared.txt');

      final winnerAtts = await db.getAttachments(docRow);
      expect(winnerAtts, hasLength(1));
      expect(winnerAtts.single.fkconflict, null);
      // Same name across winner+leaf must not break the single-row winner query.
      expect((await db.getAttachment(docRow, 'shared.txt'))?.fkconflict, null);

      final leafAtts = await db.getConflictAttachments(conflictRow);
      expect(leafAtts, hasLength(1));
      expect(leafAtts.single.fkconflict, conflictRow);
      expect(
        (await db.getConflictAttachment(conflictRow, 'shared.txt'))?.fkconflict,
        conflictRow,
      );
    });

    test('promoteConflictAttachments clears fkconflict; demoteWinnerAttachments sets it', () async {
      final dbId = await insertDb('db1');
      final docRow = await insertWinnerDoc(dbId, 'doc', '2-bbbb', 2);
      final conflictRow = await insertConflict(docRow, '2-aaaa', 2);
      await insertWinnerAttachment(docRow, 'w.txt');
      final leafAttId = await insertConflictAttachment(docRow, conflictRow, 'c.txt');

      // Promote the leaf's attachments to the winner.
      await db.promoteConflictAttachments(conflictRow);
      expect((await db.getConflictAttachments(conflictRow)), isEmpty);
      expect(await db.getAttachments(docRow), hasLength(2)); // both now winner

      // Demote the (now two) winner attachments to a new conflict row.
      final newConflict = await insertConflict(docRow, '2-dddd', 2);
      await db.demoteWinnerAttachments(docRow, newConflict);
      expect(await db.getAttachments(docRow), isEmpty);
      expect(await db.getConflictAttachments(newConflict), hasLength(2));
      // The originally-promoted leaf file id is unchanged (metadata-only repoint).
      final repointed = await db.getConflictAttachments(newConflict);
      expect(repointed.map((a) => a.id), contains(leafAttId));
    });
  });
}
