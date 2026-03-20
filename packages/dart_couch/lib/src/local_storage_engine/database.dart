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

  LocalDocumentWithBlob({required this.document, this.data});
}

@DriftDatabase(
  tables: [
    LocalDatabases,
    LocalDocuments,
    DocumentBlobs,
    RevisionHistories,
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

  @override
  int get schemaVersion => 4;

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
        await customStatement('''
          CREATE TRIGGER cleanup_attachments_on_tombstone
          AFTER UPDATE ON local_documents
          WHEN NEW.deleted = 1 AND COALESCE(OLD.deleted, 0) = 0
          BEGIN
            DELETE FROM local_attachments WHERE fkdocument = NEW.id;
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

      final row = await query.getSingleOrNull();

      if (row == null) return null;
      final doc = row.readTable(localDocuments);
      final blob = loadBlob ? row.readTableOrNull(documentBlobs) : null;
      res = LocalDocumentWithBlob(document: doc, data: blob?.data);
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

  /// finds all attachments for a document
  /// can be filtered for document names
  /// gets only metadata, not the blob data
  Future<List<LocalAttachment>> getAttachments(int dbdocid) {
    return (select(localAttachments)
          ..where((tbl) => tbl.fkdocument.equals(dbdocid))
          ..orderBy([(tbl) => OrderingTerm(expression: tbl.ordering)]))
        .get();
  }

  Future<LocalAttachment?> getAttachment(int dbdocid, String name) {
    return (select(localAttachments)
          ..where(
            (tbl) => tbl.fkdocument.equals(dbdocid) & tbl.name.equals(name),
          )
          ..orderBy([(tbl) => OrderingTerm(expression: tbl.ordering)]))
        .getSingleOrNull();
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
          ])
          ..where(
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
        i + chunkSize > documentIds.length
            ? documentIds.length
            : i + chunkSize,
      );

      final rows = await (select(localAttachments)
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

  /// Watch for new or updated documents in the given database.
  ///
  /// The returned stream emits a `LocalDocumentWithBlob` for every document
  /// whose `seq` becomes greater than the latest seen sequence at the time
  /// the watcher is started. The stream stops when the database query watch
  /// closes or when the caller cancels the subscription.
  ///
  /// If [since] is provided, existing documents with `since < seq <= currentSeq`
  /// are replayed first before watching for future changes. This is necessary
  /// for the continuous changes feed to not miss documents that were already
  /// written to the database before the watcher subscribed.
  Stream<LocalDocumentWithBlob> watchDocuments(
    int dbId,
    bool loadBlob, {
    int? since,
  }) {
    // single-subscription stream is fine for the current usage pattern
    final controller = StreamController<LocalDocumentWithBlob>();

    // start an async task to set up the watcher
    unawaited(() async {
      int lastSeq;
      if (since != null) {
        // When resuming from a known position, we need the current updateSeq
        // to replay any documents between 'since' and now before subscribing
        // to the live watch.
        try {
          lastSeq = await getCurrentUpdateSeq(dbId);
        } catch (e, s) {
          controller.addError(e, s);
          await controller.close();
          return;
        }
      } else {
        // When no 'since' is given the caller wants ALL changes from the
        // beginning.  Setting lastSeq = 0 lets the watch's initial query
        // fire emit every existing document (all have seq > 0).  Reading
        // getCurrentUpdateSeq here would introduce a race: if writes commit
        // between this read and the watch subscription, those documents
        // would have seq <= lastSeq and be silently dropped.
        lastSeq = 0;
      }

      // Replay existing documents between 'since' and 'lastSeq' before watching
      // future changes. This ensures that docs already in the DB when the
      // continuous feed starts are not missed.
      if (since != null && since < lastSeq) {
        try {
          final existing =
              await (select(localDocuments)
                    ..where(
                      (t) =>
                          t.fkdatabase.equals(dbId) &
                          t.seq.isBiggerThanValue(since) &
                          t.seq.isSmallerOrEqualValue(lastSeq),
                    )
                    ..orderBy([(t) => OrderingTerm(expression: t.seq)]))
                  .get();
          for (final doc in existing) {
            if (controller.isClosed) return;
            final ldoc = await getDocument(
              dbId,
              doc.docid,
              loadBlob,
              ignoreDeleted: true,
            );
            if (ldoc != null && !controller.isClosed) {
              controller.add(ldoc);
            }
          }
        } catch (e, s) {
          if (!controller.isClosed) controller.addError(e, s);
          await controller.close();
          return;
        }
      }

      // Query that returns all documents for this database ordered by seq
      final query = (select(localDocuments)
        ..where((t) => t.fkdatabase.equals(dbId))
        ..orderBy([(t) => OrderingTerm(expression: t.seq)]));

      // Listen for changes to the query. When rows arrive, emit only those
      // with seq > lastSeq.
      final subscription = query.watch().listen(
        (rows) {
          for (final doc in rows) {
            if (doc.seq > lastSeq) {
              // advance lastSeq immediately to avoid duplicates when handling
              // asynchronous blob loading
              final seq = doc.seq;
              lastSeq = seq;

              // load blob data asynchronously and emit when ready
              unawaited(
                getDocument(dbId, doc.docid, loadBlob, ignoreDeleted: true)
                    .then((ldoc) {
                      if (ldoc != null && !controller.isClosed) {
                        controller.add(ldoc);
                      }
                    })
                    .catchError((e, s) {
                      if (!controller.isClosed) controller.addError(e, s);
                    }),
              );
            }
          }
        },
        onError: (e, s) {
          if (!controller.isClosed) controller.addError(e, s);
        },
        onDone: () async {
          try {
            if (!controller.isClosed) await controller.close();
          } catch (_) {}
        },
      );

      // Wire controller cancellation to cancel the subscription
      controller.onCancel = () async {
        try {
          await subscription.cancel();
        } catch (_) {}
      };
    }());

    return controller.stream;
  }
}
