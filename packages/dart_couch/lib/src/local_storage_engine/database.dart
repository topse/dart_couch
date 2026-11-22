import 'package:dart_couch/dart_couch.dart';
import 'package:drift/drift.dart';

import 'dart:async';

import 'database_connection.dart';

part 'database.g.dart';

class LocalDatabases extends Table {
  late final IntColumn id = integer().autoIncrement()();
  late final TextColumn name = text().unique()();

  /// when a database is created, this starts with zero,
  /// first document added gets seq 1, next seq 2, ...
  late final IntColumn updateSeq = integer().withDefault(const Constant(0))();
}

@TableIndex(name: 'local_documents_docid', columns: {#docid})
@TableIndex(name: 'local_documents_version', columns: {#version})
@TableIndex(name: 'local_documents_seq', columns: {#seq})
// v7: incremental view indexing / changes scan `fkdatabase = ? AND seq > ?`.
@TableIndex(
  name: 'local_documents_fkdatabase_seq',
  columns: {#fkdatabase, #seq},
)
@TableIndex(
  name: 'local_documents_fkdatabase_docid',
  columns: {#fkdatabase, #docid},
  unique: true,
)
class LocalDocuments extends Table {
  late final IntColumn id = integer().autoIncrement()();
  late final fkdatabase = integer().references(LocalDatabases, #id)();

  late final TextColumn docid = text()();

  /// rev is the revision identifier, e.g. "1-abcdef1234567890"
  late final TextColumn rev = text()();

  /// version is part of the revision identifier, e.g. "1" in "1-abcdef1234567890"
  /// it is incremented with each new revision and additionally stored as
  /// integer for easy sorting
  late final IntColumn version = integer()();

  late final BoolColumn deleted = boolean().nullable()();

  /// The sequence number when this revision was added, last updated or last deleted
  /// when updating a document:
  ///   first get updateSeq from LocalDatabases
  ///   then increment it by one
  ///   then set this field to that value
  ///   then update updateSeq in LocalDatabases to that value
  /// So the document updated last has the same seq as the database updateSeq
  late final seq = integer()();
}

class DocumentBlobs extends Table {
  IntColumn get documentId => integer().references(LocalDocuments, #id)();
  TextColumn get data => text()();

  @override
  Set<Column> get primaryKey => {documentId};
}

@TableIndex(name: 'revision_histories_rev_index', columns: {#rev})
@TableIndex(name: 'revision_histories_version_index', columns: {#version})
@TableIndex(name: 'revision_histories_seq', columns: {#seq})
class RevisionHistories extends Table {
  late final IntColumn id = integer().autoIncrement()();
  late final fkdocument = integer().references(LocalDocuments, #id)();

  /// rev is the complete rev lik2 '3-12baafe552...'
  late final TextColumn rev = text()();

  /// version is only the first part of the ref -- for simpler sorting
  late final IntColumn version = integer()();
  late final seq = integer()();

  late final BoolColumn deleted = boolean().nullable()();
}

/// Non-winning conflict **leaf** revisions of a document (Decision A2 —
/// faithful conflict replica, see CLAUDE.md "Conflict Handling"). The single *winning* leaf lives in [LocalDocuments] /
/// [DocumentBlobs] as before; every other live leaf of the same document is
/// stored here with its body, so `LocalDartCouchDb` is a faithful replica:
/// `get(conflicts:true)`, `get(rev:X)` and `getOpenRevs` match CouchDB.
///
/// **Cascade / no-orphans:** [fkdocument] points at the document's stable
/// [LocalDocuments] row id (unchanged across winner promotion, since the winner
/// row is updated in place). A `BEFORE DELETE ON local_documents` trigger
/// deletes the matching rows here, so deleting a document — or a database, which
/// cascades to its documents — leaves no orphaned conflict rows. The body is an
/// inline column, so it is removed together with the row (no separate blob
/// table to clean up). Conflict-leaf *attachment files* (Stage 2) are NOT
/// covered by SQL triggers and must be cleaned by the Dart layer.
@TableIndex(
  name: 'local_conflict_revisions_fkdocument_index',
  columns: {#fkdocument},
)
@TableIndex(
  name: 'local_conflict_revisions_fkdocument_rev',
  columns: {#fkdocument, #rev},
  unique: true,
)
class LocalConflictRevisions extends Table {
  late final IntColumn id = integer().autoIncrement()();

  /// The (stable) [LocalDocuments] row id this conflict leaf belongs to.
  late final IntColumn fkdocument = integer().references(LocalDocuments, #id)();

  /// Full revision id of this leaf, e.g. "2-abcdef…".
  late final TextColumn rev = text()();

  /// Generation number (the "N" in "N-hash"), stored for sorting/winner calc.
  late final IntColumn version = integer()();

  late final BoolColumn deleted = boolean().nullable()();

  /// Stored document body (JSON, with `_attachments` stripped — handled like
  /// the winner blob). Null for a deleted (tombstone) conflict leaf.
  late final TextColumn body = text().nullable()();
}

/// Attachment metadata table.
///
/// **Binary data is NOT stored here.** Each row records only the metadata for
/// one named attachment on one document revision. The actual bytes live on the
/// filesystem as `{rootDir}/att/{id}`, where `id` is the integer primary key
/// of this row (auto-increment). This keeps SQLite small and fast.
///
/// Schema evolution:
/// - v1: a separate `attachment_blobs` table stored the binary data inline.
/// - v2 (current): `attachment_blobs` was dropped; data moved to files.
///   The v1→v2 [MigrationStrategy.onUpgrade] drops the old table and its
///   `delete_attachment_blob_before_attachment` trigger.
///
/// **Tombstone caveat:** the `cleanup_attachments_on_tombstone` SQLite trigger
/// deletes rows from this table when a document is tombstoned. However, SQLite
/// triggers cannot touch the filesystem, so attachment *files* are not removed
/// by the trigger. The Dart layer must collect attachment IDs **before** the
/// tombstone write and delete the files **after** the transaction commits.
/// See [LocalDartCouchDb._internalRemove] and the `deleted=true` path in
/// [LocalDartCouchDb.bulkDocsRaw].
@TableIndex(name: 'local_attachments_name_index', columns: {#name})
@TableIndex(name: 'local_attachments_revpos_index', columns: {#revpos})
@TableIndex(name: 'local_attachments_fkdocument_index', columns: {#fkdocument})
@TableIndex(name: 'local_attachments_fkconflict_index', columns: {#fkconflict})
class LocalAttachments extends Table {
  /// Integer primary key — also used as the filename in `att/`.
  late final IntColumn id = integer().autoIncrement()();

  late final IntColumn fkdocument = integer().references(LocalDocuments, #id)();

  late final IntColumn ordering = integer()();

  /// revpos when the attachment was added or last updated
  /// corresponds to the documents version number
  late final IntColumn revpos = integer()();

  late final TextColumn name = text()();

  /// Byte length of the uncompressed attachment data.
  late final IntColumn length = integer()();
  late final TextColumn contentType = text()();

  /// CouchDB-style MD5 digest, e.g. `md5-<base64>`.
  ///
  /// The value depends on the write path:
  /// - **Local write** ([LocalDartCouchDb.saveAttachment]): computed from the raw
  ///   (uncompressed) bytes. File content matches digest.
  /// - **Replicated from CouchDB** ([LocalDartCouchDb.bulkDocsFromMultipart]):
  ///   copied verbatim from the CouchDB attachment stub. When [encoding] is
  ///   non-null (e.g. `'gzip'`), this is MD5 of the **compressed** bytes —
  ///   even though the `att/{id}` file holds the **decompressed** content.
  ///   See [encoding] and "CouchDB Attachment Compression" in CLAUDE.md.
  late final TextColumn digest = text()();

  /// Content-encoding applied by CouchDB before storage, e.g. `'gzip'`.
  ///
  /// `null` for locally-created attachments ([LocalDartCouchDb.saveAttachment]),
  /// where [digest] = MD5(raw bytes) and the file content matches the digest.
  ///
  /// `'gzip'` (or another codec) when replicated from CouchDB and CouchDB
  /// compressed the attachment: [digest] = MD5(compressed bytes), but the
  /// `att/{id}` file holds the decompressed content. This matches CouchDB's
  /// `encoding` field returned with `att_encoding_info=true`.
  late final TextColumn encoding = text().nullable()();

  /// When non-null, this attachment belongs to a **non-winning conflict leaf**
  /// (the referenced [LocalConflictRevisions] row id) rather than to the
  /// winning revision. Winner attachments have `fkconflict == null` and behave
  /// exactly as before (conflict-leaf attachments, Decision A2 — see CLAUDE.md
  /// "Conflict Handling").
  ///
  /// [fkdocument] is still set on conflict-leaf attachments (to the owning
  /// document row), so the `delete_attachments_before_document` BEFORE-DELETE
  /// trigger cleans them on document/database hard-delete. The
  /// `cleanup_attachments_on_tombstone` trigger is scoped to `fkconflict IS
  /// NULL` so tombstoning the winner does NOT drop conflict-leaf attachments —
  /// a surviving leaf may be promoted to winner and needs them. Deleting a
  /// conflict-leaf row drops its attachment rows via
  /// `delete_conflict_attachments_before_conflict_revision`; the Dart layer
  /// deletes the files (triggers cannot touch the filesystem).
  late final IntColumn fkconflict = integer().nullable().references(
    LocalConflictRevisions,
    #id,
  )();
}

@TableIndex(name: 'local_view_view_path_short_index', columns: {#viewPathShort})
@TableIndex(
  name: 'local_views_unique',
  columns: {#database, #viewPathShort},
  unique: true,
)
class LocalViews extends Table {
  late final IntColumn id = integer().autoIncrement()();
  late final IntColumn database = integer().references(LocalDatabases, #id)();

  /// Shortname of the view, e.g. _all_docs or design_doc_name/view_name
  late final TextColumn viewPathShort = text()();

  /// update sequence number, when the view was last updated
  late final IntColumn updateSeq = integer().withDefault(const Constant(0))();

  late final TextColumn mapFunction = text()();
  late final TextColumn reduceFunction = text().nullable()();
}

/// There can be multiple entries in a view
/// with identical docid, key and value
@TableIndex(name: 'local_view_entries_docid_index', columns: {#docid})
// v7: view queries filter by `fkview` and sort by `key` (docid as tiebreak).
@TableIndex(
  name: 'local_view_entries_fkview_key_docid',
  columns: {#fkview, #key, #docid},
)
class LocalViewEntries extends Table {
  late final IntColumn id = integer().autoIncrement()();
  late final fkview = integer().references(LocalViews, #id)();

  late final TextColumn docid = text()();
  late final TextColumn key = text()();
  late final TextColumn value = text()();
}

class LocalDocumentWithBlob {
  final LocalDocument document;
  final String? data; // null if blob not loaded

  /// Whether the document row has at least one **winner** attachment
  /// (`fkconflict IS NULL`). `null` = not determined by the loading query;
  /// callers must then look the attachments up themselves. Lets read paths
  /// skip the attachment query for the (common) attachment-less document.
  final bool? hasAttachments;

  LocalDocumentWithBlob({
    required this.document,
    this.data,
    this.hasAttachments,
  });
}

/// One row of [AppDatabase.getViewIndexPage].
class ViewIndexSourceDoc {
  final LocalDocument document;

  /// JSON body of the winner; null for tombstones.
  final String? data;

  /// The doc has at least one non-deleted conflict leaf.
  final bool hasLiveConflicts;

  /// The view being indexed holds at least one entry for this doc.
  final bool hasViewEntries;

  ViewIndexSourceDoc({
    required this.document,
    required this.data,
    required this.hasLiveConflicts,
    required this.hasViewEntries,
  });
}

@DriftDatabase(
  tables: [
    LocalDatabases,
    LocalDocuments,
    DocumentBlobs,
    RevisionHistories,
    LocalConflictRevisions,
    LocalAttachments,
    LocalViews,
    LocalViewEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Create a database backed by the given [QueryExecutor].
  ///
  /// Use [openDatabaseConnection] from `database_connection.dart` to obtain a
  /// platform-appropriate executor.
  AppDatabase(super.executor);

  /// Set as soon as [close] starts, so long-lived watchers
  /// ([watchDocumentBatches]) stop issuing queries and treat in-flight
  /// failures as expected.
  bool _closing = false;

  @override
  Future<void> close() {
    _closing = true;
    return super.close();
  }

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        await customStatement('''CREATE TRIGGER delete_documents_before_db 
                                 BEFORE DELETE ON local_databases
                                 FOR EACH ROW
                                 BEGIN
                                   DELETE FROM local_documents WHERE fkdatabase = OLD.id;
                                 END;''');

        await customStatement(
          '''CREATE TRIGGER delete_documents_blob_before_document
                                 BEFORE DELETE ON local_documents
                                 FOR EACH ROW
                                 BEGIN
                                   DELETE FROM document_blobs WHERE document_id = OLD.id;
                                 END;''',
        );

        await customStatement(
          '''CREATE TRIGGER delete_attachments_before_document
              BEFORE DELETE ON local_documents
              FOR EACH ROW
              BEGIN
                DELETE FROM local_attachments WHERE fkdocument = OLD.id;
              END;''',
        );

        // Cleanup triggers for tombstoned documents.
        //
        // When a document is tombstoned (deleted flag set to true via UPDATE),
        // the BEFORE DELETE triggers above don't fire because the row isn't
        // deleted — only the `deleted` column changes. These AFTER UPDATE
        // triggers clean up the associated metadata rows.
        //
        // IMPORTANT: these triggers cannot delete attachment *files* (SQLite has
        // no filesystem access). File deletion is the responsibility of the Dart
        // layer. See the tombstone caveat in the [LocalAttachments] class doc.
        // Only the WINNER's attachments (fkconflict IS NULL) are removed on
        // tombstone. Conflict-leaf attachments (fkconflict NOT NULL) must
        // survive — a surviving leaf may be promoted to winner. See
        // [LocalAttachments.fkconflict] (conflict-leaf attachments).
        await customStatement('''
          CREATE TRIGGER cleanup_attachments_on_tombstone
          AFTER UPDATE ON local_documents
          WHEN NEW.deleted = 1 AND COALESCE(OLD.deleted, 0) = 0
          BEGIN
            DELETE FROM local_attachments
            WHERE fkdocument = NEW.id AND fkconflict IS NULL;
          END;
        ''');

        // Drop a conflict leaf's attachment rows when the leaf row is deleted
        // (supersession, promotion, or document delete). Files are removed by
        // the Dart layer (triggers cannot touch the filesystem).
        await customStatement('''
          CREATE TRIGGER delete_conflict_attachments_before_conflict_revision
          BEFORE DELETE ON local_conflict_revisions
          FOR EACH ROW
          BEGIN
            DELETE FROM local_attachments WHERE fkconflict = OLD.id;
          END;
        ''');

        await customStatement('''
          CREATE TRIGGER cleanup_document_blob_on_tombstone
          AFTER UPDATE ON local_documents
          WHEN NEW.deleted = 1 AND COALESCE(OLD.deleted, 0) = 0
          BEGIN
            DELETE FROM document_blobs WHERE document_id = NEW.id;
          END;
        ''');

        // Triggers to manage RevisionHistories
        await customStatement('''
          CREATE TRIGGER update_revision_history_after_insert_document
          AFTER INSERT ON local_documents
          FOR EACH ROW
          BEGIN
            INSERT INTO revision_histories (fkdocument, rev, version, seq, deleted)
            VALUES (NEW.id, NEW.rev, NEW.version, NEW.seq, NEW.deleted);
          END;
        ''');

        await customStatement('''
          CREATE TRIGGER update_revision_history_after_update_document
          AFTER UPDATE ON local_documents
          FOR EACH ROW
          BEGIN
            INSERT INTO revision_histories (fkdocument, rev, version, seq, deleted)
            VALUES (NEW.id, NEW.rev, NEW.version, NEW.seq, NEW.deleted);
          END;
        ''');

        await customStatement('''
          CREATE TRIGGER delete_revision_history_before_delete_document
          BEFORE DELETE ON local_documents
          FOR EACH ROW
          BEGIN
            DELETE FROM revision_histories WHERE fkdocument = OLD.id;
          END;
        ''');

        // Cascade conflict-leaf rows when their owning document row is deleted
        // (directly, or via the database-delete cascade). Prevents orphaned
        // local_conflict_revisions rows. See [LocalConflictRevisions].
        await customStatement('''
          CREATE TRIGGER delete_conflict_revisions_before_delete_document
          BEFORE DELETE ON local_documents
          FOR EACH ROW
          BEGIN
            DELETE FROM local_conflict_revisions WHERE fkdocument = OLD.id;
          END;
        ''');

        await customStatement('''
        CREATE TRIGGER delete_local_view_before_dtabase
          BEFORE DELETE ON local_databases
          FOR EACH ROW
          BEGIN
            DELETE FROM local_views WHERE database = OLD.id;
          END
        ''');

        await customStatement('''
        CREATE TRIGGER delete_local_view_entries_before_view
          BEFORE DELETE ON local_views
          FOR EACH ROW
          BEGIN
            DELETE FROM local_view_entries WHERE fkview = OLD.id;
          END
      ''');
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // v1 → v2: attachment binary data moved from the `attachment_blobs`
        // inline table to individual files on disk (see LocalAttachments docs).
        // Any existing blob data is intentionally discarded here; the local DB
        // is a cache and will re-sync from CouchDB on next replication.
        if (from < 2) {
          await customStatement(
            'DROP TRIGGER IF EXISTS delete_attachment_blob_before_attachment',
          );
          await customStatement('DROP TABLE IF EXISTS attachment_blobs');
        }
        if (from < 3) {
          await customStatement(
            'ALTER TABLE local_attachments ADD COLUMN encoding TEXT',
          );
        }
        if (from < 4) {
          // v3 → v4: change local_documents.docid from globally UNIQUE to
          // unique per (fkdatabase, docid). SQLite cannot drop a column-level
          // UNIQUE constraint in-place, so we recreate the table.
          await customStatement('PRAGMA foreign_keys = OFF');

          await customStatement('''
            CREATE TABLE local_documents_new (
              id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
              fkdatabase INTEGER NOT NULL REFERENCES local_databases(id),
              docid TEXT NOT NULL,
              rev TEXT NOT NULL,
              version INTEGER NOT NULL,
              deleted INTEGER,
              seq INTEGER NOT NULL
            )
          ''');
          await customStatement(
            'INSERT INTO local_documents_new SELECT * FROM local_documents',
          );
          await customStatement('DROP TABLE local_documents');
          await customStatement(
            'ALTER TABLE local_documents_new RENAME TO local_documents',
          );

          // Recreate indexes.
          await customStatement(
            'CREATE INDEX local_documents_docid ON local_documents (docid)',
          );
          await customStatement(
            'CREATE INDEX local_documents_version ON local_documents (version)',
          );
          await customStatement(
            'CREATE INDEX local_documents_seq ON local_documents (seq)',
          );
          await customStatement(
            'CREATE UNIQUE INDEX local_documents_fkdatabase_docid ON local_documents (fkdatabase, docid)',
          );

          // Recreate triggers that were on local_documents (dropped with the table).
          await customStatement('''
            CREATE TRIGGER delete_documents_blob_before_document
            BEFORE DELETE ON local_documents
            FOR EACH ROW
            BEGIN
              DELETE FROM document_blobs WHERE document_id = OLD.id;
            END
          ''');
          await customStatement('''
            CREATE TRIGGER delete_attachments_before_document
            BEFORE DELETE ON local_documents
            FOR EACH ROW
            BEGIN
              DELETE FROM local_attachments WHERE fkdocument = OLD.id;
            END
          ''');
          await customStatement('''
            CREATE TRIGGER cleanup_attachments_on_tombstone
            AFTER UPDATE ON local_documents
            WHEN NEW.deleted = 1 AND COALESCE(OLD.deleted, 0) = 0
            BEGIN
              DELETE FROM local_attachments WHERE fkdocument = NEW.id;
            END
          ''');
          await customStatement('''
            CREATE TRIGGER cleanup_document_blob_on_tombstone
            AFTER UPDATE ON local_documents
            WHEN NEW.deleted = 1 AND COALESCE(OLD.deleted, 0) = 0
            BEGIN
              DELETE FROM document_blobs WHERE document_id = NEW.id;
            END
          ''');
          await customStatement('''
            CREATE TRIGGER update_revision_history_after_insert_document
            AFTER INSERT ON local_documents
            FOR EACH ROW
            BEGIN
              INSERT INTO revision_histories (fkdocument, rev, version, seq, deleted)
              VALUES (NEW.id, NEW.rev, NEW.version, NEW.seq, NEW.deleted);
            END
          ''');
          await customStatement('''
            CREATE TRIGGER update_revision_history_after_update_document
            AFTER UPDATE ON local_documents
            FOR EACH ROW
            BEGIN
              INSERT INTO revision_histories (fkdocument, rev, version, seq, deleted)
              VALUES (NEW.id, NEW.rev, NEW.version, NEW.seq, NEW.deleted);
            END
          ''');
          await customStatement('''
            CREATE TRIGGER delete_revision_history_before_delete_document
            BEFORE DELETE ON local_documents
            FOR EACH ROW
            BEGIN
              DELETE FROM revision_histories WHERE fkdocument = OLD.id;
            END
          ''');

          await customStatement('PRAGMA foreign_keys = ON');
        }
        if (from < 5) {
          // v4 → v5: add local_conflict_revisions (non-winning conflict leaf
          // bodies, Decision A2) and its cascade trigger so deleting a
          // document/database leaves no orphaned conflict rows.
          await customStatement('''
            CREATE TABLE local_conflict_revisions (
              id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
              fkdocument INTEGER NOT NULL REFERENCES local_documents(id),
              rev TEXT NOT NULL,
              version INTEGER NOT NULL,
              deleted INTEGER,
              body TEXT
            )
          ''');
          await customStatement(
            'CREATE INDEX local_conflict_revisions_fkdocument_index '
            'ON local_conflict_revisions (fkdocument)',
          );
          await customStatement(
            'CREATE UNIQUE INDEX local_conflict_revisions_fkdocument_rev '
            'ON local_conflict_revisions (fkdocument, rev)',
          );
          await customStatement('''
            CREATE TRIGGER delete_conflict_revisions_before_delete_document
            BEFORE DELETE ON local_documents
            FOR EACH ROW
            BEGIN
              DELETE FROM local_conflict_revisions WHERE fkdocument = OLD.id;
            END
          ''');
        }
        if (from < 6) {
          // v5 → v6: conflict-leaf attachment bodies.
          // Add local_attachments.fkconflict (NULL = winner attachment), scope
          // the tombstone-cleanup trigger to winner attachments only, and add a
          // BEFORE-DELETE trigger that drops a conflict leaf's attachment rows.
          await customStatement(
            'ALTER TABLE local_attachments ADD COLUMN fkconflict INTEGER '
            'REFERENCES local_conflict_revisions(id)',
          );
          await customStatement(
            'CREATE INDEX local_attachments_fkconflict_index '
            'ON local_attachments (fkconflict)',
          );
          await customStatement(
            'DROP TRIGGER IF EXISTS cleanup_attachments_on_tombstone',
          );
          await customStatement('''
            CREATE TRIGGER cleanup_attachments_on_tombstone
            AFTER UPDATE ON local_documents
            WHEN NEW.deleted = 1 AND COALESCE(OLD.deleted, 0) = 0
            BEGIN
              DELETE FROM local_attachments
              WHERE fkdocument = NEW.id AND fkconflict IS NULL;
            END;
          ''');
          await customStatement('''
            CREATE TRIGGER delete_conflict_attachments_before_conflict_revision
            BEFORE DELETE ON local_conflict_revisions
            FOR EACH ROW
            BEGIN
              DELETE FROM local_attachments WHERE fkconflict = OLD.id;
            END;
          ''');
        }
        if (from < 7) {
          // v6 -> v7: read-path indices. View queries filter by fkview and
          // order by key; incremental view updates scan by (fkdatabase, seq).
          await customStatement(
            'CREATE INDEX IF NOT EXISTS local_view_entries_fkview_key_docid '
            'ON local_view_entries (fkview, "key", docid)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS local_documents_fkdatabase_seq '
            'ON local_documents (fkdatabase, seq)',
          );
        }
        if (from < 8) {
          // v7 -> v8: `_all_docs` is served directly from local_documents
          // (see LocalDartCouchDb._internalAllDocs); the materialised
          // `_all_docs` view is no longer maintained or read. Drop its rows.
          // Entries are deleted explicitly (not only via the
          // delete_local_view_entries_before_view trigger) so the cleanup is
          // complete even on databases whose trigger set predates it.
          await customStatement(
            'DELETE FROM local_view_entries WHERE fkview IN '
            "(SELECT id FROM local_views WHERE view_path_short = '_all_docs')",
          );
          await customStatement(
            "DELETE FROM local_views WHERE view_path_short = '_all_docs'",
          );
        }
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
        // WAL mode significantly speeds up writes by avoiding full fsync per
        // transaction. synchronous=NORMAL with WAL is crash-safe (only risk
        // is losing the last transaction on an OS crash, matching CouchDB's
        // default durability). These PRAGMAs are no-ops on web/WASM.
        await customStatement('PRAGMA journal_mode = WAL');
        await customStatement('PRAGMA synchronous = NORMAL');
      },
    );
  }

  Future<List<LocalDatabase>> get allDatabases => select(localDatabases).get();
  Future<int> addDatabase(LocalDatabasesCompanion entry) {
    return into(localDatabases).insert(entry);
  }

  Future<int> deleteDatabase(String name) async {
    final db = await getDatabase(name);
    if (db == null) {
      throw CouchDbException.notFoundDeleteDb(name);
    }

    return (delete(localDatabases)..where((tbl) => tbl.id.equals(db.id))).go();
  }

  // --- Conflict leaf accessors (Decision A2, see CLAUDE.md) --------------------
  // Live in AppDatabase because compound `where` uses drift's `&` operator,
  // which is only in scope where `package:drift/drift.dart` is fully imported
  // (local_dart_couch_db.dart imports it with `show Value`).

  /// All non-winning conflict leaf rows for the document row [docRowId].
  Future<List<LocalConflictRevision>> getConflictRevisions(int docRowId) {
    return (select(
      localConflictRevisions,
    )..where((t) => t.fkdocument.equals(docRowId))).get();
  }

  /// Ids of documents in [dbid] that currently have at least one **live**
  /// (non-deleted) conflict leaf — i.e. are in conflict (CouchDB's `_conflicts`).
  ///
  /// Indexed, memory-light (ids only, no bodies, no full-table scan): joins the
  /// conflict side-table to its documents. Used by opt-in resolution to do a
  /// "complete run" after the initial sync without downloading or scanning the
  /// whole database (see CLAUDE.md "Conflict Handling" / Resolution).
  Future<List<String>> conflictedDocIds(int dbid) async {
    final rows = await customSelect(
      'SELECT DISTINCT d.docid AS docid '
      'FROM local_conflict_revisions c '
      'JOIN local_documents d ON d.id = c.fkdocument '
      'WHERE d.fkdatabase = ? AND COALESCE(c.deleted, 0) = 0',
      variables: [Variable.withInt(dbid)],
      readsFrom: {localConflictRevisions, localDocuments},
    ).get();
    return rows.map((r) => r.read<String>('docid')).toList();
  }

  /// All conflict-leaf revs in [dbid], grouped by document row id.
  ///
  /// One query for the whole changes-feed batch so a `style=all_docs` feed can
  /// advertise every leaf (winner + conflict leaves) without a per-document
  /// round trip (forwarding — lets Local act as a faithful
  /// replication *source* for conflicted documents). The conflict side-table
  /// only holds losing leaves (rare), so fetching it whole is cheap and avoids
  /// SQLite's bound-variable limit that an `IN (...)` over many doc ids would
  /// hit on a large feed.
  Future<Map<int, List<String>>> conflictRevsByDoc(int dbid) async {
    final rows = await customSelect(
      'SELECT c.fkdocument AS fkdocument, c.rev AS rev '
      'FROM local_conflict_revisions c '
      'JOIN local_documents d ON d.id = c.fkdocument '
      'WHERE d.fkdatabase = ?',
      variables: [Variable.withInt(dbid)],
      readsFrom: {localConflictRevisions, localDocuments},
    ).get();
    final map = <int, List<String>>{};
    for (final r in rows) {
      (map[r.read<int>('fkdocument')] ??= <String>[]).add(
        r.read<String>('rev'),
      );
    }
    return map;
  }

  /// All conflict-leaf revs (deleted ones included) of the given document row
  /// ids, grouped by document row id; documents without conflict leaves are
  /// absent. One query per [batchReadChunkSize] ids via
  /// `local_conflict_revisions_fkdocument_index`; per document the leaves are
  /// in row-id order, like [getConflictRevisions]. Used by the continuous
  /// `style=all_docs` changes feed, one call per emitted page.
  Future<Map<int, List<String>>> conflictRevsForDocs(
    List<int> docRowIds,
  ) async {
    final map = <int, List<String>>{};
    if (docRowIds.isEmpty) return map;
    final unique = docRowIds.toSet().toList(growable: false);
    for (var i = 0; i < unique.length; i += batchReadChunkSize) {
      final chunk = unique.sublist(
        i,
        i + batchReadChunkSize > unique.length
            ? unique.length
            : i + batchReadChunkSize,
      );
      final rows =
          await (select(localConflictRevisions)
                ..where((t) => t.fkdocument.isIn(chunk))
                ..orderBy([(t) => OrderingTerm.asc(t.id)]))
              .get();
      for (final r in rows) {
        (map[r.fkdocument] ??= <String>[]).add(r.rev);
      }
    }
    return map;
  }

  /// **Live** (non-deleted) conflict-leaf revs in [dbid], grouped by document
  /// row id — i.e. the exact contents of each conflicted document's
  /// `_conflicts` member.
  ///
  /// Used by view indexing to feed the winner doc **plus a `_conflicts` member**
  /// to the map function for conflicted documents, matching CouchDB ("Views only
  /// get the winning revision … However, they do also get a `_conflicts` member
  /// if there are any conflicting revisions"). One batch query for the whole
  /// index pass; the side-table only holds losing leaves (rare), so it is cheap
  /// (same reasoning as [conflictRevsByDoc]). Deleted leaves are excluded — they
  /// belong to `_deleted_conflicts`, which views do not receive.
  Future<Map<int, List<String>>> liveConflictRevsByDoc(int dbid) async {
    final rows = await customSelect(
      'SELECT c.fkdocument AS fkdocument, c.rev AS rev '
      'FROM local_conflict_revisions c '
      'JOIN local_documents d ON d.id = c.fkdocument '
      'WHERE d.fkdatabase = ? AND COALESCE(c.deleted, 0) = 0',
      variables: [Variable.withInt(dbid)],
      readsFrom: {localConflictRevisions, localDocuments},
    ).get();
    final map = <int, List<String>>{};
    for (final r in rows) {
      (map[r.read<int>('fkdocument')] ??= <String>[]).add(
        r.read<String>('rev'),
      );
    }
    return map;
  }

  /// Inserts a conflict leaf, replacing any existing row for the same
  /// (document, rev) — idempotent. Returns the new row id (used as the
  /// `fkconflict` for that leaf's attachments in Stage 2). The replace deletes
  /// any prior row, which (via `delete_conflict_attachments_before_conflict_revision`)
  /// drops its stale attachment rows; the caller deletes the files.
  Future<int> putConflictRevision({
    required int docRowId,
    required String rev,
    required int version,
    required bool deleted,
    required String? body,
  }) async {
    await (delete(
      localConflictRevisions,
    )..where((t) => t.fkdocument.equals(docRowId) & t.rev.equals(rev))).go();
    return into(localConflictRevisions).insert(
      LocalConflictRevisionsCompanion.insert(
        fkdocument: docRowId,
        rev: rev,
        version: version,
        deleted: Value(deleted),
        body: Value(body),
      ),
    );
  }

  /// Bumps only the update [seq] of an existing document row, leaving its
  /// winner rev / body / deleted flag untouched.
  ///
  /// Used when the revision tree changed via a conflict-leaf add / supersede /
  /// tombstone while the **winner row stayed the same**.
  /// CouchDB advances a document's update_seq for ANY tree change so the changes
  /// feed re-emits it; mirroring that here is what lets opt-in conflict
  /// resolution (which tombstones a *losing* leaf) propagate to the remote via
  /// the normal push changes feed. Must run inside a `db.transaction()`.
  Future<void> updateDocumentSeq(int docRowId, int seq) async {
    await (update(localDocuments)..where((t) => t.id.equals(docRowId))).write(
      LocalDocumentsCompanion(seq: Value(seq)),
    );
  }

  /// Removes the conflict leaf [rev] of document row [docRowId] (e.g. when an
  /// incoming revision supersedes it, or it is promoted to winner).
  Future<void> deleteConflictRevision(int docRowId, String rev) async {
    await (delete(
      localConflictRevisions,
    )..where((t) => t.fkdocument.equals(docRowId) & t.rev.equals(rev))).go();
  }

  /// Deletes every [RevisionHistories] row of document row [docRowId].
  ///
  /// The history table is an append-only log fed by the
  /// `update_revision_history_after_*_document` triggers, so it always grows
  /// toward higher generations. Winner *promotion* (after the winning leaf is
  /// tombstoned) breaks that monotonicity: the new winner is a surviving leaf
  /// whose generation may be *below* the tombstone's, leaving a stale
  /// higher-version row at the head of the version-sorted history that no longer
  /// matches the winner. Clearing the rows here (the next winner-row write
  /// re-seeds the head via the trigger) keeps the promoted document's history
  /// consistent — identical in shape to a freshly written document. Must run
  /// inside a `db.transaction()`.
  Future<void> clearRevisionHistory(int docRowId) async {
    await (delete(
      revisionHistories,
    )..where((t) => t.fkdocument.equals(docRowId))).go();
  }

  Future<LocalDocumentWithBlob?> getDocument(
    int dbId,
    String docId,
    bool loadBlob, {
    String? rev,
    bool ignoreDeleted = false,
  }) async {
    // wenn keine rev angegeben wurde, dann wird ein deletetes
    // document nicht zurückgegeben!

    LocalDocumentWithBlob? res;

    if (loadBlob == false) {
      final query = select(localDocuments)
        ..where((tbl) => tbl.fkdatabase.equals(dbId) & tbl.docid.equals(docId));
      LocalDocument? doc = await query.getSingleOrNull();

      if (doc != null) {
        res = LocalDocumentWithBlob(document: doc, data: null);
      }
    } else {
      final query =
          select(localDocuments).join([
              leftOuterJoin(
                documentBlobs,
                documentBlobs.documentId.equalsExp(localDocuments.id),
              ),
            ])
            ..where(localDocuments.docid.equals(docId))
            ..where(localDocuments.fkdatabase.equals(dbId));
      // Same round trip: does the doc have winner attachments? Lets callers
      // skip the attachment query for attachment-less documents.
      final hasAtt = _hasWinnerAttachmentsExpr();
      query.addColumns([hasAtt]);

      final row = await query.getSingleOrNull();

      if (row == null) return null;
      final doc = row.readTable(localDocuments);
      final blob = loadBlob ? row.readTableOrNull(documentBlobs) : null;
      res = LocalDocumentWithBlob(
        document: doc,
        data: blob?.data,
        hasAttachments: row.read(hasAtt),
      );
    }

    // check if the document is deleted
    if (rev == null &&
        res?.document.deleted == true &&
        ignoreDeleted == false) {
      return null;
    }

    // false revision requested
    if (rev != null && rev != res?.document.rev) return null;

    return res;
  }

  /// Correlated `EXISTS` over the **winner** attachments (`fkconflict IS
  /// NULL`) of the current `local_documents` row. Served by
  /// `local_attachments_fkdocument_index`.
  Expression<bool> _hasWinnerAttachmentsExpr() => existsQuery(
    selectOnly(localAttachments)
      ..addColumns([localAttachments.id])
      ..where(
        localAttachments.fkdocument.equalsExp(localDocuments.id) &
            localAttachments.fkconflict.isNull(),
      ),
  );

  /// Maximum number of bound `IN (...)` parameters per batched read. Well
  /// below SQLite's historical 999-variable limit; plain `IN` (not
  /// `json_each`) so it works with system SQLite builds lacking JSON1.
  static const int batchReadChunkSize = 500;

  /// Batch-loads the **current winner rows** of [docids] in database [dbid]
  /// (one query per [batchReadChunkSize] distinct ids, via the unique
  /// `(fkdatabase, docid)` index). Returns a map keyed by docid; ids that do
  /// not exist are absent. Deleted (tombstoned) rows ARE included - the
  /// caller applies its own visibility rule (cf. [getDocument]).
  ///
  /// [withBlob] additionally joins the JSON body. Every returned row carries
  /// [LocalDocumentWithBlob.hasAttachments], computed in the same query.
  Future<Map<String, LocalDocumentWithBlob>> getDocumentsByIds(
    int dbid,
    List<String> docids, {
    bool withBlob = true,
  }) async {
    final result = <String, LocalDocumentWithBlob>{};
    if (docids.isEmpty) return result;
    final unique = docids.toSet().toList(growable: false);
    final hasAtt = _hasWinnerAttachmentsExpr();

    for (var i = 0; i < unique.length; i += batchReadChunkSize) {
      final chunk = unique.sublist(
        i,
        i + batchReadChunkSize > unique.length
            ? unique.length
            : i + batchReadChunkSize,
      );
      final query =
          select(localDocuments).join([
              if (withBlob)
                leftOuterJoin(
                  documentBlobs,
                  documentBlobs.documentId.equalsExp(localDocuments.id),
                ),
            ])
            ..addColumns([hasAtt])
            ..where(
              localDocuments.fkdatabase.equals(dbid) &
                  localDocuments.docid.isIn(chunk),
            );
      for (final row in await query.get()) {
        final doc = row.readTable(localDocuments);
        result[doc.docid] = LocalDocumentWithBlob(
          document: doc,
          data: withBlob ? row.readTableOrNull(documentBlobs)?.data : null,
          hasAttachments: row.read(hasAtt),
        );
      }
    }
    return result;
  }

  /// Batch-loads the **winner** attachment metadata (`fkconflict IS NULL`)
  /// of the given `local_documents` row ids, one query per
  /// [batchReadChunkSize] distinct ids. Each list has the same order as
  /// [getAttachments] (`ordering`); documents without attachments are absent.
  Future<Map<int, List<LocalAttachment>>> getAttachmentsForDocs(
    List<int> documentRowIds,
  ) async {
    final result = <int, List<LocalAttachment>>{};
    if (documentRowIds.isEmpty) return result;
    final unique = documentRowIds.toSet().toList(growable: false);

    for (var i = 0; i < unique.length; i += batchReadChunkSize) {
      final chunk = unique.sublist(
        i,
        i + batchReadChunkSize > unique.length
            ? unique.length
            : i + batchReadChunkSize,
      );
      final rows =
          await (select(localAttachments)
                ..where(
                  (tbl) => tbl.fkdocument.isIn(chunk) & tbl.fkconflict.isNull(),
                )
                ..orderBy([
                  (tbl) => OrderingTerm(expression: tbl.fkdocument),
                  (tbl) => OrderingTerm(expression: tbl.ordering),
                ]))
              .get();
      for (final row in rows) {
        result.putIfAbsent(row.fkdocument, () => []).add(row);
      }
    }
    return result;
  }

  /// The rows `_all_docs` lists in range mode: current winner rows of [dbid]
  /// that are not deleted and not `_local/` documents (design documents ARE
  /// included, like CouchDB).
  ///
  /// The `_local/` exclusion is a half-open docid range (`'_local0'` is the
  /// successor prefix of `'_local/'`) rather than `LIKE`, so it is evaluated
  /// with the BINARY collation of the `(fkdatabase, docid)` index and is
  /// independent of `PRAGMA case_sensitive_like`.
  Expression<bool> _allDocsVisible(int dbid) =>
      localDocuments.fkdatabase.equals(dbid) &
      (localDocuments.deleted.isNull() | localDocuments.deleted.equals(false)) &
      (localDocuments.docid.isBiggerOrEqualValue('_local/') &
              localDocuments.docid.isSmallerThanValue('_local0'))
          .not();

  /// `total_rows` of `_all_docs`: the number of rows [_allDocsVisible]
  /// selects. One `SELECT COUNT(*)` over the `(fkdatabase, docid)` index.
  Future<int> countAllDocs(int dbid) async {
    final count = countAll();
    final row =
        await (selectOnly(localDocuments)
              ..addColumns([count])
              ..where(_allDocsVisible(dbid)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// Number of `_all_docs` rows ([_allDocsVisible]) that precede [startId] in
  /// iteration order: `docid < startId` ascending, `docid > startId`
  /// [descending]. Basis of CouchDB's `offset` for a range starting there.
  Future<int> countAllDocsBefore(
    int dbid,
    String startId, {
    bool descending = false,
  }) async {
    final count = countAll();
    final docid = localDocuments.docid;
    final row =
        await (selectOnly(localDocuments)
              ..addColumns([count])
              ..where(
                _allDocsVisible(dbid) &
                    (descending
                        ? docid.isBiggerThanValue(startId)
                        : docid.isSmallerThanValue(startId)),
              ))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// One page of `_all_docs` range mode: rows selected by [_allDocsVisible],
  /// restricted to `docid` in the given bounds (each optional; inclusive or
  /// exclusive), ordered by `docid` (BINARY = code point order) ascending or
  /// [descending], `LIMIT limit OFFSET offset`. Callers page with keyset
  /// pagination by tightening a bound to the last docid of the previous page.
  ///
  /// [equals] additionally restricts to one exact docid (`key=`).
  ///
  /// With [withBlob] the JSON body is joined and
  /// [LocalDocumentWithBlob.hasAttachments] computed in the same query.
  Future<List<LocalDocumentWithBlob>> getAllDocsPage(
    int dbid, {
    String? lower,
    bool lowerInclusive = true,
    String? upper,
    bool upperInclusive = true,
    String? equals,
    bool descending = false,
    required int limit,
    int offset = 0,
    bool withBlob = false,
  }) async {
    final docid = localDocuments.docid;
    var where = _allDocsVisible(dbid);
    if (lower != null) {
      where &= lowerInclusive
          ? docid.isBiggerOrEqualValue(lower)
          : docid.isBiggerThanValue(lower);
    }
    if (upper != null) {
      where &= upperInclusive
          ? docid.isSmallerOrEqualValue(upper)
          : docid.isSmallerThanValue(upper);
    }
    if (equals != null) where &= docid.equals(equals);

    final hasAtt = withBlob ? _hasWinnerAttachmentsExpr() : null;
    final query =
        select(localDocuments).join([
            if (withBlob)
              leftOuterJoin(
                documentBlobs,
                documentBlobs.documentId.equalsExp(localDocuments.id),
              ),
          ])
          ..where(where)
          ..orderBy([
            OrderingTerm(
              expression: docid,
              mode: descending ? OrderingMode.desc : OrderingMode.asc,
            ),
          ])
          ..limit(limit, offset: offset > 0 ? offset : null);
    if (hasAtt != null) query.addColumns([hasAtt]);
    final rows = await query.get();
    return [
      for (final row in rows)
        LocalDocumentWithBlob(
          document: row.readTable(localDocuments),
          data: withBlob ? row.readTableOrNull(documentBlobs)?.data : null,
          hasAttachments: hasAtt != null ? row.read(hasAtt) : null,
        ),
    ];
  }

  /// get all documents with seq number higher than given
  Future<List<LocalDocumentWithBlob>> getDocuments(
    int dbId,
    bool loadBlobs, {
    int seqNumber = 0,
  }) async {
    List<LocalDocumentWithBlob> res = [];

    if (loadBlobs == false) {
      final query = select(localDocuments)
        ..where(
          (tbl) =>
              tbl.fkdatabase.equals(dbId) &
              tbl.seq.isBiggerThanValue(seqNumber),
        );
      List<LocalDocument> docs = await query.get();

      res = docs.map((d) => LocalDocumentWithBlob(document: d)).toList();
    } else {
      final query =
          select(localDocuments).join([
            leftOuterJoin(
              documentBlobs,
              documentBlobs.documentId.equalsExp(localDocuments.id),
            ),
          ])..where(
            localDocuments.fkdatabase.equals(dbId) &
                localDocuments.seq.isBiggerThanValue(seqNumber),
          );

      final rows = await query.get();

      res = rows.map((row) {
        final doc = row.readTable(localDocuments);
        final blob = row.readTableOrNull(documentBlobs);

        return LocalDocumentWithBlob(document: doc, data: blob?.data);
      }).toList();
    }

    return res;
  }

  /// sorted by version descending
  Future<List<RevisionHistory>?> getRevisionHistory({
    int? dbdocid,
    int? dbid,
    String? docid,
    bool sortDesc = true,
  }) async {
    if (dbdocid == null && dbid != null && docid != null) {
      final doc = await getDocument(dbid, docid, false, ignoreDeleted: true);
      if (doc != null) {
        dbdocid = doc.document.id;
      }
    } else if (dbdocid == null) {
      throw Exception("INVALID PARAMETERS");
    }
    if (dbdocid != null) {
      return (select(revisionHistories)
            ..where((tbl) => tbl.fkdocument.equals(dbdocid!))
            ..orderBy([
              (tbl) => OrderingTerm(
                expression: tbl.version,
                mode: sortDesc == true ? OrderingMode.desc : OrderingMode.asc,
              ),
            ]))
          .get();
    }
    return null;
  }

  Future<LocalDatabase?> getDatabase(String name) {
    return (select(
      localDatabases,
    )..where((tbl) => tbl.name.equals(name))).getSingleOrNull();
  }

  Future<LocalDatabase?> getDatabaseById(int id) {
    return (select(
      localDatabases,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  /// Returns documents and the database updateSeq in a single transaction,
  /// ensuring a consistent snapshot. Without this, a write can land between
  /// the two queries, causing the changes feed to report a stale revision
  /// with a newer lastSeq.
  Future<({List<LocalDocumentWithBlob> docs, LocalDatabase? dbRecord})>
  getDocumentsAndUpdateSeq(int dbId, bool loadBlobs) {
    return transaction(() async {
      final docs = await getDocuments(dbId, loadBlobs);
      final dbRecord = await getDatabaseById(dbId);
      return (docs: docs, dbRecord: dbRecord);
    });
  }

  /// Saves attachment metadata only. The binary data must already be on disk
  /// before (INSERT) or after (UPDATE) this call returns — see
  /// [LocalDartCouchDb._saveAttachmentWithFileIO] for the exact ordering.
  ///
  /// - **INSERT** (`entry.id` absent): inserts a new row and returns the new
  ///   auto-increment ID. The caller writes the file to `att/{id}` after this
  ///   returns, rolling back by deleting the row if the file write fails.
  /// - **UPDATE** (`entry.id` present): updates the existing row in place and
  ///   returns the same ID. The caller must have already written `att/{id}.tmp`
  ///   before this call so the old file is never lost on a crash.
  Future<int> saveAttachment(LocalAttachmentsCompanion entry) async {
    final existingId = entry.id.present ? entry.id.value : null;
    if (existingId != null) {
      await (update(
        localAttachments,
      )..where((t) => t.id.equals(existingId))).write(entry);
      return existingId;
    } else {
      return into(localAttachments).insert(entry);
    }
  }

  /// finds all **winner** attachments for a document (`fkconflict IS NULL`).
  /// can be filtered for document names
  /// gets only metadata, not the blob data
  ///
  /// Conflict-leaf attachments (`fkconflict NOT NULL`) are excluded — use
  /// [getConflictAttachments]. Scoping to the winner is required now that a
  /// conflict leaf can carry an attachment with the same name as the winner.
  Future<List<LocalAttachment>> getAttachments(int dbdocid) {
    return (select(localAttachments)
          ..where(
            (tbl) => tbl.fkdocument.equals(dbdocid) & tbl.fkconflict.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm(expression: tbl.ordering)]))
        .get();
  }

  Future<LocalAttachment?> getAttachment(int dbdocid, String name) {
    return (select(localAttachments)
          ..where(
            (tbl) =>
                tbl.fkdocument.equals(dbdocid) &
                tbl.name.equals(name) &
                tbl.fkconflict.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm(expression: tbl.ordering)]))
        .getSingleOrNull();
  }

  /// All attachment metadata rows of one **conflict leaf** (Stage 2).
  Future<List<LocalAttachment>> getConflictAttachments(int conflictRowId) {
    return (select(localAttachments)
          ..where((tbl) => tbl.fkconflict.equals(conflictRowId))
          ..orderBy([(tbl) => OrderingTerm(expression: tbl.ordering)]))
        .get();
  }

  /// One named attachment of a conflict leaf, or null (Stage 2).
  Future<LocalAttachment?> getConflictAttachment(
    int conflictRowId,
    String name,
  ) {
    return (select(localAttachments)
          ..where(
            (tbl) =>
                tbl.fkconflict.equals(conflictRowId) & tbl.name.equals(name),
          )
          ..orderBy([(tbl) => OrderingTerm(expression: tbl.ordering)]))
        .getSingleOrNull();
  }

  /// Promotes a conflict leaf's attachments to the winner: clears `fkconflict`
  /// on all rows pointing at [conflictRowId]. Files keep their `att/{PK}` name,
  /// so this is metadata-only. Used by winner promotion (Stage 2).
  Future<void> promoteConflictAttachments(int conflictRowId) async {
    await (update(localAttachments)
          ..where((tbl) => tbl.fkconflict.equals(conflictRowId)))
        .write(const LocalAttachmentsCompanion(fkconflict: Value(null)));
  }

  /// Demotes the current winner's attachments of document [dbdocid] to the
  /// conflict leaf [toConflictId]: sets `fkconflict = toConflictId` on the
  /// winner rows (`fkconflict IS NULL`). Metadata-only. Used when an incoming
  /// sibling wins and the old (live) winner becomes a conflict leaf (Stage 2).
  Future<void> demoteWinnerAttachments(int dbdocid, int toConflictId) async {
    await (update(localAttachments)..where(
          (tbl) => tbl.fkdocument.equals(dbdocid) & tbl.fkconflict.isNull(),
        ))
        .write(LocalAttachmentsCompanion(fkconflict: Value(toConflictId)));
  }

  /// Returns all attachment metadata rows across all databases.
  ///
  /// Used by [LocalDartCouchServer._recoverAttachmentFiles] during startup to find
  /// rows whose file is missing (Phase 2 of crash recovery).
  Future<List<LocalAttachment>> getAllAttachments() {
    return select(localAttachments).get();
  }

  Future<void> updateAttachmentOrdering(int attachmentId, int newOrdering) {
    return (update(localAttachments)
          ..where((tbl) => tbl.id.equals(attachmentId)))
        .write(LocalAttachmentsCompanion(ordering: Value(newOrdering)));
  }

  Future<void> deleteAttachment(int attachmentId) async {
    await (delete(
      localAttachments,
    )..where((tbl) => tbl.id.equals(attachmentId))).go();
  }

  Future<List<LocalViewEntry>> getViewEntries(
    int viewid, {
    int? page,
    int pageSize = 100,
  }) {
    var q = select(localViewEntries)
      ..where((tbl) => tbl.fkview.equals(viewid))
      ..orderBy([(t) => OrderingTerm(expression: t.id)]);

    if (page != null) q.limit(pageSize, offset: page * pageSize);

    return q.get();
  }

  Future<int> incrementAndGetUpdateSeq(int dbId) {
    return transaction(() async {
      // Step 1: Get the current updateSeq
      final row = await (select(
        localDatabases,
      )..where((tbl) => tbl.id.equals(dbId))).getSingleOrNull();

      if (row == null) {
        throw Exception('Database with id $dbId not found.');
      }

      final newSeq = row.updateSeq + 1;

      // Step 2: Write back the incremented value
      await (update(localDatabases)..where((tbl) => tbl.id.equals(dbId))).write(
        LocalDatabasesCompanion(updateSeq: Value(newSeq)),
      );

      // Step 3: Return the new value
      return newSeq;
    });
  }

  /// Allocate [count] sequential sequence numbers in a single transaction.
  ///
  /// Returns the first new seq (oldSeq + 1). The caller should assign
  /// firstSeq + 0, firstSeq + 1, ..., firstSeq + (count - 1) to written docs.
  Future<int> incrementUpdateSeqBy(int dbId, int count) {
    assert(count > 0);
    return transaction(() async {
      final row = await (select(
        localDatabases,
      )..where((tbl) => tbl.id.equals(dbId))).getSingleOrNull();

      if (row == null) {
        throw Exception('Database with id $dbId not found.');
      }

      final firstSeq = row.updateSeq + 1;
      final newSeq = row.updateSeq + count;

      await (update(localDatabases)..where((tbl) => tbl.id.equals(dbId))).write(
        LocalDatabasesCompanion(updateSeq: Value(newSeq)),
      );

      return firstSeq;
    });
  }

  /// Batch-fetch existing documents by their docids in a single query.
  ///
  /// Returns a map keyed by docid. Always includes deleted documents
  /// (the caller needs them for conflict resolution).
  Future<Map<String, LocalDocumentWithBlob>> getDocumentsByDocIds(
    int dbId,
    List<String> docIds,
  ) async {
    if (docIds.isEmpty) return {};

    final result = <String, LocalDocumentWithBlob>{};

    // Chunk to stay within SQLite's variable limit (999).
    const chunkSize = 900;
    for (var i = 0; i < docIds.length; i += chunkSize) {
      final chunk = docIds.sublist(
        i,
        i + chunkSize > docIds.length ? docIds.length : i + chunkSize,
      );

      final query =
          select(localDocuments).join([
            leftOuterJoin(
              documentBlobs,
              documentBlobs.documentId.equalsExp(localDocuments.id),
            ),
          ])..where(
            localDocuments.fkdatabase.equals(dbId) &
                localDocuments.docid.isIn(chunk),
          );

      final rows = await query.get();
      for (final row in rows) {
        final doc = row.readTable(localDocuments);
        final blob = row.readTableOrNull(documentBlobs);
        result[doc.docid] = LocalDocumentWithBlob(
          document: doc,
          data: blob?.data,
        );
      }
    }

    return result;
  }

  /// Batch-fetch attachment metadata for multiple document row IDs.
  ///
  /// Returns a map keyed by document row ID. Only call this when the batch
  /// contains tombstones overwriting existing docs that may have attachments.
  Future<Map<int, List<LocalAttachment>>> getAttachmentsByDocumentIds(
    List<int> documentIds,
  ) async {
    if (documentIds.isEmpty) return {};

    final result = <int, List<LocalAttachment>>{};

    const chunkSize = 900;
    for (var i = 0; i < documentIds.length; i += chunkSize) {
      final chunk = documentIds.sublist(
        i,
        i + chunkSize > documentIds.length ? documentIds.length : i + chunkSize,
      );

      final rows =
          await (select(localAttachments)
                ..where((tbl) => tbl.fkdocument.isIn(chunk))
                ..orderBy([(tbl) => OrderingTerm(expression: tbl.ordering)]))
              .get();

      for (final row in rows) {
        result.putIfAbsent(row.fkdocument, () => []).add(row);
      }
    }

    return result;
  }

  Future<int> getCurrentUpdateSeq(int dbId) async {
    final row = await (select(
      localDatabases,
    )..where((tbl) => tbl.id.equals(dbId))).getSingleOrNull();

    if (row == null) {
      throw Exception('Database with id $dbId not found.');
    }

    return row.updateSeq;
  }

  int _activeWatchers = 0;
  int _runningWatchScans = 0;

  /// Diagnostics / tests: number of live [watchDocumentBatches] streams.
  int get activeWatchers => _activeWatchers;

  /// Diagnostics / tests: no [watchDocumentBatches] scan is running. Table
  /// updates reach the watchers synchronously when a write's transaction
  /// completes, so right after an awaited write every affected watcher is
  /// already scanning: waiting for this state is waiting for "every watcher
  /// has processed every completed write".
  bool get watchScansIdle => _runningWatchScans == 0;

  /// Page size of the seq-ordered scans behind [watchDocumentBatches].
  static const int watchPageSize = 500;

  /// Documents of [dbId] with `seq > afterSeq`, ascending by `seq`, at most
  /// [limit] rows — one query, served by `local_documents_fkdatabase_seq`.
  ///
  /// Deleted (tombstoned) rows ARE included. With [loadBlob] the JSON body is
  /// joined (null for tombstones) and [LocalDocumentWithBlob.hasAttachments]
  /// is computed in the same query; without it both stay null (same shape as
  /// [getDocument] with `loadBlob: false`).
  Future<List<LocalDocumentWithBlob>> getDocumentsAfterSeq(
    int dbId,
    int afterSeq,
    bool loadBlob, {
    int limit = watchPageSize,
  }) async {
    final hasAtt = loadBlob ? _hasWinnerAttachmentsExpr() : null;
    final query =
        select(localDocuments).join([
            if (loadBlob)
              leftOuterJoin(
                documentBlobs,
                documentBlobs.documentId.equalsExp(localDocuments.id),
              ),
          ])
          ..where(
            localDocuments.fkdatabase.equals(dbId) &
                localDocuments.seq.isBiggerThanValue(afterSeq),
          )
          ..orderBy([OrderingTerm.asc(localDocuments.seq)])
          ..limit(limit);
    if (hasAtt != null) query.addColumns([hasAtt]);
    final rows = await query.get();
    return [
      for (final row in rows)
        LocalDocumentWithBlob(
          document: row.readTable(localDocuments),
          data: loadBlob ? row.readTableOrNull(documentBlobs)?.data : null,
          hasAttachments: hasAtt != null ? row.read(hasAtt) : null,
        ),
    ];
  }

  /// One page of view-indexing input: the documents of [dbId] with
  /// `seq > afterSeq`, ascending by `seq`, at most [limit] rows, with their
  /// JSON body (null for tombstones) — one query, served by
  /// `local_documents_fkdatabase_seq`. Deleted rows ARE included.
  ///
  /// Each row also carries, computed in the same query,
  /// - [ViewIndexSourceDoc.hasLiveConflicts]: the doc has at least one
  ///   non-deleted conflict leaf (its `_conflicts` must be loaded via
  ///   [liveConflictRevsForDocs]);
  /// - [ViewIndexSourceDoc.hasViewEntries]: view [viewId] currently holds at
  ///   least one entry for the doc (its old entries must be read via
  ///   [viewEntriesForDocs] / deleted).
  ///
  /// Both flags let incremental indexing skip the follow-up queries for the
  /// common case (no conflicts; a doc the view never emitted).
  Future<List<ViewIndexSourceDoc>> getViewIndexPage(
    int dbId,
    int viewId,
    int afterSeq, {
    int limit = watchPageSize,
  }) async {
    final hasConflicts = existsQuery(
      selectOnly(localConflictRevisions)
        ..addColumns([localConflictRevisions.id])
        ..where(
          localConflictRevisions.fkdocument.equalsExp(localDocuments.id) &
              (localConflictRevisions.deleted.isNull() |
                  localConflictRevisions.deleted.equals(false)),
        ),
    );
    // `+fkview` keeps SQLite on `local_view_entries_docid_index` (a few rows
    // per docid) instead of range-scanning the whole view via the
    // `(fkview, key, docid)` index for every document. [viewId] is an int,
    // so inlining it is safe.
    final hasEntries = CustomExpression<bool>(
      'EXISTS (SELECT 1 FROM local_view_entries ve '
      'WHERE ve.docid = local_documents.docid AND +ve.fkview = $viewId)',
    );
    final query =
        select(localDocuments).join([
            leftOuterJoin(
              documentBlobs,
              documentBlobs.documentId.equalsExp(localDocuments.id),
            ),
          ])
          ..addColumns([hasConflicts, hasEntries])
          ..where(
            localDocuments.fkdatabase.equals(dbId) &
                localDocuments.seq.isBiggerThanValue(afterSeq),
          )
          ..orderBy([OrderingTerm.asc(localDocuments.seq)])
          ..limit(limit);
    final rows = await query.get();
    return [
      for (final row in rows)
        ViewIndexSourceDoc(
          document: row.readTable(localDocuments),
          data: row.readTableOrNull(documentBlobs)?.data,
          hasLiveConflicts: row.read(hasConflicts) ?? false,
          hasViewEntries: row.read(hasEntries) ?? false,
        ),
    ];
  }

  /// **Live** (non-deleted) conflict-leaf revs of the given document row ids,
  /// grouped by row id, per document in row-id order — the per-page form of
  /// [liveConflictRevsByDoc] (same contents for those documents). One query
  /// per [batchReadChunkSize] ids.
  Future<Map<int, List<String>>> liveConflictRevsForDocs(
    List<int> docRowIds,
  ) async {
    final map = <int, List<String>>{};
    if (docRowIds.isEmpty) return map;
    final unique = docRowIds.toSet().toList(growable: false);
    for (var i = 0; i < unique.length; i += batchReadChunkSize) {
      final chunk = unique.sublist(
        i,
        i + batchReadChunkSize > unique.length
            ? unique.length
            : i + batchReadChunkSize,
      );
      final rows =
          await (select(localConflictRevisions)
                ..where(
                  (t) =>
                      t.fkdocument.isIn(chunk) &
                      (t.deleted.isNull() | t.deleted.equals(false)),
                )
                ..orderBy([(t) => OrderingTerm.asc(t.id)]))
              .get();
      for (final r in rows) {
        (map[r.fkdocument] ??= <String>[]).add(r.rev);
      }
    }
    return map;
  }

  /// The entries of view [viewId] for [docids], grouped by docid, per doc in
  /// insertion (row id) order. One query per [batchReadChunkSize] ids.
  Future<Map<String, List<LocalViewEntry>>> viewEntriesForDocs(
    int viewId,
    List<String> docids,
  ) async {
    final map = <String, List<LocalViewEntry>>{};
    if (docids.isEmpty) return map;
    final unique = docids.toSet().toList(growable: false);
    for (var i = 0; i < unique.length; i += batchReadChunkSize) {
      final chunk = unique.sublist(
        i,
        i + batchReadChunkSize > unique.length
            ? unique.length
            : i + batchReadChunkSize,
      );
      final rows =
          await (select(localViewEntries)
                // `+fkview`: look the docids up via
                // `local_view_entries_docid_index` rather than scanning the
                // whole view (see getViewIndexPage).
                ..where(
                  (t) =>
                      t.docid.isIn(chunk) &
                      CustomExpression<bool>('+fkview = $viewId'),
                )
                ..orderBy([(t) => OrderingTerm.asc(t.id)]))
              .get();
      for (final r in rows) {
        (map[r.docid] ??= <LocalViewEntry>[]).add(r);
      }
    }
    return map;
  }

  /// Cheap validation signal for cached view definitions, in one query:
  /// the current update seq of database [dbId], and whether any design
  /// document (`_design/…`, deleted ones included) of it was written with a
  /// `seq > sinceSeq`.
  ///
  /// Every write of a document — create, update, tombstone, conflict-leaf
  /// change — gives its row the new database seq, and rows are never
  /// hard-deleted except with the whole database, so "no design row with
  /// seq > S" means no design document changed since seq S. Served by the
  /// unique `(fkdatabase, docid)` index (prefix range over `_design/`).
  Future<({int updateSeq, bool designDocsChanged})> designDocChangeProbe(
    int dbId,
    int sinceSeq,
  ) async {
    final changed = existsQuery(
      selectOnly(localDocuments)
        ..addColumns([localDocuments.id])
        ..where(
          localDocuments.fkdatabase.equalsExp(localDatabases.id) &
              localDocuments.docid.isBiggerOrEqualValue('_design/') &
              // '0' is the code point after '/': an exact `_design/` prefix
              // range (LIKE would treat `_` as a wildcard).
              localDocuments.docid.isSmallerThanValue('_design0') &
              localDocuments.seq.isBiggerThanValue(sinceSeq),
        ),
    );
    final row =
        await (selectOnly(localDatabases)
              ..addColumns([localDatabases.updateSeq, changed])
              ..where(localDatabases.id.equals(dbId)))
            .getSingleOrNull();
    if (row == null) {
      throw Exception('Database with id $dbId not found.');
    }
    return (
      updateSeq: row.read(localDatabases.updateSeq)!,
      designDocsChanged: row.read(changed) ?? false,
    );
  }

  /// Watch for new or updated documents in the given database, one row per
  /// changed document, in strict `seq` order. See [watchDocumentBatches] for
  /// the semantics; this is its flattened form.
  Stream<LocalDocumentWithBlob> watchDocuments(
    int dbId,
    bool loadBlob, {
    int? since,
  }) => watchDocumentBatches(
    dbId,
    loadBlob,
    since: since,
  ).expand((batch) => batch);

  /// Watch for new or updated documents in the given database, emitted as
  /// seq-ordered batches of at most [watchPageSize] rows.
  ///
  /// Start position:
  /// - [since] == null: every existing document is replayed (all have
  ///   `seq > 0`), then future changes follow.
  /// - [since] given: documents with `seq > since` are replayed, then future
  ///   changes follow. If [since] is beyond the database's current update seq
  ///   (stale checkpoint), the start is clamped to the current update seq, so
  ///   every document written from now on is emitted. A missing database is
  ///   reported as an error, after which the stream closes.
  ///
  /// Every document row appears at most once per `seq` it reaches; a document
  /// updated again later is emitted again with its new `seq` (CouchDB changes
  /// semantics). Rows are read in one query per page, never per document.
  ///
  /// **No gap between replay and live phase:** the table-update listener is
  /// attached *before* the first query, and replay and live updates share one
  /// single-flight loop over `seq > lastSeq`. Seqs are allocated and committed
  /// inside the writer's transaction, so they become visible in increasing
  /// order; any write committed after a scan started either has a seq above
  /// that scan's results or triggers a notification that schedules another
  /// scan. Bursts of notifications coalesce into one rerun.
  ///
  /// Respects pause (back-pressure): while the listener is paused no further
  /// page is loaded, which bounds memory on large replays. The stream ends
  /// when the subscription is cancelled, when the database is deleted, or
  /// when this [AppDatabase] closes; no query is issued afterwards.
  Stream<List<LocalDocumentWithBlob>> watchDocumentBatches(
    int dbId,
    bool loadBlob, {
    int? since,
  }) {
    var counted = false;
    late final StreamController<List<LocalDocumentWithBlob>> controller;
    StreamSubscription<Set<TableUpdate>>? docUpdates;
    StreamSubscription<Set<TableUpdate>>? dbDeletes;
    Completer<void>? resumed;

    var lastSeq = 0;
    var initialized = false;
    var running = false;
    // Set by a notification that may not be covered by the scan in flight.
    var dirty = false;
    var stopped = false;

    void stop() {
      if (stopped) return;
      stopped = true;
      if (counted) _activeWatchers--;
      resumed?.complete();
      resumed = null;
      unawaited(docUpdates?.cancel());
      unawaited(dbDeletes?.cancel());
      // Not awaited: close() only completes once a paused listener resumes.
      if (!controller.isClosed) unawaited(controller.close());
    }

    bool halted() => stopped || _closing;

    Future<void> pump() async {
      if (running) {
        dirty = true;
        return;
      }
      running = true;
      _runningWatchScans++;
      try {
        if (!initialized) {
          if (since != null) {
            final current = await getCurrentUpdateSeq(dbId);
            if (halted()) return;
            lastSeq = since < current ? since : current;
          }
          initialized = true;
        }
        do {
          List<LocalDocumentWithBlob> page;
          do {
            if (halted()) return;
            if (controller.isPaused) {
              resumed = Completer<void>();
              await resumed!.future;
              if (halted()) return;
            }
            // Notifications received up to here are covered by this scan.
            dirty = false;
            page = await getDocumentsAfterSeq(dbId, lastSeq, loadBlob);
            if (halted()) return;
            if (page.isNotEmpty) {
              lastSeq = page.last.document.seq;
              controller.add(page);
            }
          } while (page.length >= watchPageSize);
        } while (dirty);
      } catch (e, s) {
        // Errors caused by cancel / close are expected and swallowed.
        if (!halted()) {
          controller.addError(e, s);
          stop();
        }
      } finally {
        running = false;
        _runningWatchScans--;
      }
    }

    controller = StreamController<List<LocalDocumentWithBlob>>(
      onListen: () {
        counted = true;
        _activeWatchers++;
        if (_closing) {
          stop();
          return;
        }
        // Subscribe BEFORE the first scan so no commit can slip through.
        docUpdates = tableUpdates(
          TableUpdateQuery.onTable(localDocuments),
        ).listen((_) => unawaited(pump()), onDone: stop, onError: (_) {});
        dbDeletes =
            tableUpdates(
              TableUpdateQuery.onTable(
                localDatabases,
                limitUpdateKind: UpdateKind.delete,
              ),
            ).listen(
              (_) async {
                if (halted()) return;
                try {
                  final row = await getDatabaseById(dbId);
                  if (row == null) stop();
                } catch (_) {
                  // Closing / closed: the docUpdates onDone stops the watcher.
                }
              },
              onDone: stop,
              onError: (_) {},
            );
        unawaited(pump());
      },
      onResume: () {
        resumed?.complete();
        resumed = null;
      },
      onCancel: stop,
    );
    return controller.stream;
  }
}
