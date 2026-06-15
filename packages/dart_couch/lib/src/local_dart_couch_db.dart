import 'dart:async';

import 'package:collection/collection.dart';

import 'local_storage_engine/attachment_storage.dart';
import 'package:mutex/mutex.dart';

import 'dart_couch_db.dart';
import 'local_storage_engine/calculate_couch_db_new_rev.dart';
import 'local_storage_engine/database.dart';
import 'local_storage_engine/view_mgr/view_ctrl.dart';
import 'local_storage_engine/view_mgr/view_mgr.dart';
import 'messages/bulk_docs_result.dart';
import 'messages/bulk_get.dart';
import 'messages/couch_db_status_codes.dart';
import 'messages/design_document.dart';
import 'conflict_resolution_internal.dart';
import 'messages/index_result.dart';
import 'package:drift/drift.dart' show Value;

import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';

import 'messages/bulk_get_multipart.dart';
import 'messages/couch_document_base.dart';
import 'messages/database_info.dart';
import 'messages/view_result.dart';
import 'messages/revs_diff_result.dart';
import 'replication_mixin.dart';
import 'package:logging/logging.dart';

final uuid = const Uuid();
final Logger _log = Logger('dart_couch-local_db');

/// A [Mutex] subclass that logs every acquire/release with the call site.
/// Useful for diagnosing lock contention during development; swap the field
/// in [LocalDartCouchDb] back to a plain [Mutex] for production.
class MyDebugMutex extends Mutex {
  @override
  Future<T> protect<T>(Future<T> Function() criticalSection) async {
    // Log only the direct caller (first stack frame outside this file/method)
    final stLines = StackTrace.current.toString().split('\n');
    _log.fine('Mutex try acquire called by: ${stLines[1]}');
    if (isLocked) {
      _log.severe(
        'Mutex already locked. This can be , but must not be a problem. Called by: ${stLines[1]}',
      );
    }
    await acquire();
    try {
      return await criticalSection();
    } finally {
      _log.fine('Mutex released called by: ${stLines[1]}');
      release();
    }
  }
}

/// SQLite-backed implementation of [DartCouchDb].
///
/// Stores documents, revisions, attachments, and view indexes in a local
/// Drift/SQLite database ([AppDatabase]). Implements the same API as
/// [HttpDartCouchDb] so that replication and offline-first logic can treat both
/// interchangeably.
///
/// A [Mutex] serialises all write operations to prevent race conditions from
/// concurrent replication and user-initiated writes sharing the same SQLite
/// file. Read-only operations also run inside the mutex so they observe a
/// consistent snapshot.
///
/// Documents are stored with only their user-defined fields in the blob table;
/// CouchDB transport fields (`_revisions`, `_revs_info`, `_conflicts`,
/// `_deleted_conflicts`, `_local_seq`) are stripped on write and re-added on
/// read. Attachments are stored in a dedicated table and injected back into
/// the document map by [_recreateAttachmentMapFromDatabase].
class LocalDartCouchDb extends DartCouchDb
    with CouchReplicationMixin
    implements LocalConflictSource {
  /// The internal database-row ID that identifies this logical database inside
  /// the shared [AppDatabase] (one SQLite file can host multiple databases).
  final int dbid;

  final AppDatabase db;

  /// Platform-specific attachment binary storage.
  final AttachmentStorage attachmentStorage;

  late ViewMgr viewMgr;

  //final m = MyDebugMutex();
  final m = Mutex();

  bool _disposed = false;

  /// Marks this instance as disposed.  After disposal, all API calls throw
  /// [CouchDbException] with [CouchDbStatusCodes.internalServerError].
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  LocalDartCouchDb({
    required this.dbid,
    required super.dbname,
    required this.db,
    required this.attachmentStorage,
  }) {
    viewMgr = ViewMgr(db: db, dbGetFunction: _internalGet, dbid: dbid);
  }

  /// Deletes the attachment data and any leftover temporary data for [id].
  /// Silently ignores missing attachments — deletion is always best-effort
  /// because the DB row is removed first and a failed delete leaves no orphan
  /// metadata (the DB row is gone).
  Future<void> _deleteAttachmentFile(int id) async {
    await attachmentStorage.deleteAttachment(id);
  }

  /// Saves the attachment [data] and writes/updates the metadata row in [db].
  /// Must be called inside a `db.transaction()` callback.
  ///
  /// **UPDATE** (`entry.id` is present — attachment already exists):
  /// 1. Delete old DB row.
  /// 2. Insert new DB row (gets fresh auto-increment ID).
  /// 3. Write data to `att/{newId}`.
  /// 4. Old file `att/{oldId}` is added to [deferredFileDeletes] for cleanup
  ///    after the transaction commits.
  ///
  /// This avoids overwriting the old file inside the transaction. If a crash
  /// occurs before commit, the DB rolls back (old row restored) and the orphan
  /// `att/{newId}` is cleaned up by startup recovery Phase 2.
  ///
  /// **INSERT** (`entry.id` absent — new attachment):
  /// 1. Insert DB row to get the auto-increment ID.
  /// 2. Write data directly.
  /// 3. On write failure, delete the DB row to avoid an orphan metadata row.
  Future<int> _saveAttachmentWithFileIO(
    LocalAttachmentsCompanion entry,
    Uint8List data, {
    List<int>? deferredFileDeletes,
  }) async {
    final digest = AttachmentInfo.calculateCouchDbAttachmentDigest(data);
    entry = entry.copyWith(digest: Value(digest), length: Value(data.length));
    final existingId = entry.id.present ? entry.id.value : null;

    if (existingId != null) {
      // DELETE-old + INSERT-new: never overwrite old file inside transaction.
      await db.deleteAttachment(existingId);
      entry = entry.copyWith(id: Value.absent());
      final newId = await db.saveAttachment(entry);
      try {
        await attachmentStorage.writeAttachment(newId, data);
        await attachmentStorage.finalizeWrite(newId);
      } catch (e) {
        await db.deleteAttachment(newId);
        rethrow;
      }
      deferredFileDeletes?.add(existingId);
      return newId;
    } else {
      final newId = await db.saveAttachment(entry);
      try {
        await attachmentStorage.writeAttachment(newId, data);
        await attachmentStorage.finalizeWrite(newId);
      } catch (e) {
        await db.deleteAttachment(newId);
        rethrow;
      }
      return newId;
    }
  }

  /// Writes a batch of documents.
  ///
  /// **`newEdits=true`** (default, normal write path):
  /// - Behaves like a sequence of PUT/DELETE operations.
  /// - Generates a new revision hash for every document.
  /// - Enforces revision-conflict checking (incoming `_rev` must match the
  ///   stored head revision, otherwise 409 is thrown).
  /// - Returns the newly assigned revisions in [BulkDocsResult].
  ///
  /// **`newEdits=false`** (replication write path):
  /// - Stores the revision exactly as received; no new hash is generated.
  /// - Never produces 409 — conflicts are resolved deterministically by
  ///   picking the "winning" revision (see the conflict resolution comment
  ///   inline below).
  /// - Returns an empty list (CouchDB protocol: callers ignore the body).
  ///
  /// Both modes run inside a transaction and the mutex so that interleaved
  /// reads from the changes feed observe a consistent state.
  @override
  Future<List<BulkDocsResult>> bulkDocsRaw(
    List<String> docs, {
    bool newEdits = true,
  }) async {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    return await m.protect<List<BulkDocsResult>>(() async {
      final List<BulkDocsResult> results = [];
      final deferredFileDeletes = <int>[];

      // Process each document in a transaction to ensure atomicity
      await db.transaction(() async {
        for (var docJson in docs) {
          String? docId;
          String? docRev;
          try {
            // Parse the JSON string to get document data
            final Map<String, dynamic> docMap = jsonDecode(docJson);

            // Capture the revision chain BEFORE stripping transport fields:
            // replication (newEdits=false) needs it to maintain the conflict
            // leaf set (distinguish a linear supersede from a sibling branch).
            final Map<String, dynamic>? incomingRevisions =
                (docMap['_revisions'] as Map<String, dynamic>?);

            // Remove transport-only fields before processing
            docMap.remove('_revisions');
            docMap.remove('_revs_info');
            docMap.remove('_conflicts');
            docMap.remove('_deleted_conflicts');
            docMap.remove('_local_seq');

            // Extract basic fields directly from JSON without full deserialization
            docId = docMap['_id'] as String?;
            docRev = docMap['_rev'] as String?;
            final bool isDeleted = (docMap['_deleted'] as bool?) ?? false;

            if (newEdits) {
              // For new edits mode: generate new revision and validate conflicts
              // Generate ID if missing
              docId = docId ?? uuid.v4();
              docMap['_id'] = docId;

              // Check for existing document
              final existingDoc = await db.getDocument(
                dbid,
                docId,
                true,
                ignoreDeleted: true,
              );

              // Validate revision conflicts
              if (existingDoc != null) {
                if (existingDoc.document.deleted == false) {
                  // Document exists and is not deleted - must provide matching rev
                  if (docRev != existingDoc.document.rev) {
                    throw CouchDbException.conflictPut(docId);
                  }
                }
                // Calculate new revision
                docRev = _calculateNewRev(
                  docRev ?? existingDoc.document.rev,
                  docMap,
                );
              } else {
                // New document - cannot have a revision
                if (docRev != null) {
                  throw CouchDbException.conflictPut(docId);
                }
                docRev = _calculateNewRev(null, docMap);
              }

              docMap['_rev'] = docRev;

              // Collect attachment IDs before tombstone trigger fires.
              final newEditsTombstoneIds = (isDeleted && existingDoc != null)
                  ? (await db.getAttachments(
                      existingDoc.document.id,
                    )).map((a) => a.id).toList()
                  : <int>[];

              // Store the document
              int seq = await db.incrementAndGetUpdateSeq(dbid);
              final int version = int.parse(docRev.split('-')[0]);

              // Remove _attachments for storage
              Map<String, dynamic> filteredDoc = Map.from(docMap);
              filteredDoc.remove('_attachments');

              int documentId = await db
                  .into(db.localDocuments)
                  .insertOnConflictUpdate(
                    LocalDocumentsCompanion(
                      id: Value.absentIfNull(existingDoc?.document.id),
                      docid: Value(docId),
                      fkdatabase: Value(dbid),
                      rev: Value(docRev),
                      version: Value(version),
                      deleted: Value(isDeleted),
                      seq: Value(seq),
                    ),
                  );

              // CouchDB does not keep document bodies for tombstoned documents.
              // The cleanup_document_blob_on_tombstone trigger deletes the blob
              // when an existing doc is tombstoned. For new deleted docs (INSERT),
              // no blob is needed either.
              if (!isDeleted) {
                await db
                    .into(db.documentBlobs)
                    .insertOnConflictUpdate(
                      DocumentBlobsCompanion(
                        documentId: Value(
                          existingDoc?.document.id ?? documentId,
                        ),
                        data: Value(jsonEncode(filteredDoc)),
                      ),
                    );
              }

              results.add(BulkDocsResult(id: docId, ok: true, rev: docRev));
              for (final id in newEditsTombstoneIds) {
                await _deleteAttachmentFile(id);
              }
            } else {
              // Replication mode (newEdits=false) - preserve exact revisions
              if (docRev == null) {
                throw CouchDbException(
                  CouchDbStatusCodes.badRequest,
                  'Document must have a _rev for new_edits=false',
                );
              }

              // Generate ID if missing
              docId = docId ?? uuid.v4();

              // Check if document exists to get its internal ID for update
              final existingDoc = await db.getDocument(
                dbid,
                docId,
                true,
                ignoreDeleted: true,
              );

              // Extract version number from revision string (format: "N-hash")
              final int version = int.parse(docRev.split('-')[0]);

              // Conflict leaf maintenance (Decision A2) — shared with the
              // multipart paths. writeAsWinner is false when the incoming was
              // already handled (deduped / ancestor / stored as a conflict
              // leaf). When stored as a (non-deleted) conflict leaf, persist
              // that leaf's inline attachments under its fkconflict (Stage 2).
              final leaf = await _applyIncomingLeaf(
                docId: docId,
                docRev: docRev,
                version: version,
                isDeleted: isDeleted,
                docMap: docMap,
                incomingRevisions: incomingRevisions,
                existingDoc: existingDoc,
                deferredFileDeletes: deferredFileDeletes,
              );
              if (!leaf.writeAsWinner) {
                if (leaf.incomingConflictRowId != null) {
                  await _storeInlineConflictAttachments(
                    docRowId: existingDoc!.document.id,
                    conflictRowId: leaf.incomingConflictRowId!,
                    attachmentsMap:
                        docMap['_attachments'] as Map<String, dynamic>?,
                    deferredFileDeletes: deferredFileDeletes,
                  );
                }
                // The revision tree changed (a conflict leaf was added /
                // superseded / tombstoned) while the winner row stayed the same.
                // Bump the doc's seq so the changes feed re-emits it and the
                // change replicates out (CouchDB-faithful — see updateDocumentSeq
                // / _applyIncomingLeaf.leafSetChanged).
                if (leaf.leafSetChanged) {
                  final seq = await db.incrementAndGetUpdateSeq(dbid);
                  await db.updateDocumentSeq(existingDoc!.document.id, seq);
                }
                results.add(BulkDocsResult(id: docId, ok: true, rev: docRev));
                continue;
              }

              // Collect attachment IDs before tombstone trigger fires.
              // cleanup_attachments_on_tombstone fires during insertOnConflictUpdate
              // and deletes DB rows, so we must query before the insert.
              final tombstoneAttachmentIds = (isDeleted && existingDoc != null)
                  ? (await db.getAttachments(
                      existingDoc.document.id,
                    )).map((a) => a.id).toList()
                  : <int>[];

              int seq = await db.incrementAndGetUpdateSeq(dbid);

              // Extract inline attachment data before removing _attachments
              final attachmentsMap =
                  docMap['_attachments'] as Map<String, dynamic>?;

              // Remove _attachments for storage (transport-only fields already removed above)
              Map<String, dynamic> filteredDoc = Map.from(docMap);
              filteredDoc.remove('_attachments');

              // Use insertOnConflictUpdate with existing ID if document exists
              int documentId = await db
                  .into(db.localDocuments)
                  .insertOnConflictUpdate(
                    LocalDocumentsCompanion(
                      id: Value.absentIfNull(existingDoc?.document.id),
                      docid: Value(docId),
                      fkdatabase: Value(dbid),
                      rev: Value(docRev),
                      version: Value(version),
                      deleted: Value(isDeleted),
                      seq: Value(seq),
                    ),
                  );

              // CouchDB does not keep document bodies for tombstoned documents.
              // The cleanup_document_blob_on_tombstone trigger deletes the blob
              // when an existing doc is tombstoned. For new deleted docs (INSERT),
              // no blob is needed either.
              if (!isDeleted) {
                await db
                    .into(db.documentBlobs)
                    .insertOnConflictUpdate(
                      DocumentBlobsCompanion(
                        documentId: Value(
                          existingDoc?.document.id ?? documentId,
                        ),
                        data: Value(jsonEncode(filteredDoc)),
                      ),
                    );
              }

              // Store inline attachment data from replication.
              // Also remove any existing attachments that are absent from the
              // incoming revision: when an attachment is deleted on the remote
              // and that revision is replicated here, _attachments is either
              // null or missing the deleted name. The DB triggers only fire on
              // row DELETE or tombstone, so orphaned attachment rows must be
              // cleaned up explicitly here.
              final actualDocId = existingDoc?.document.id ?? documentId;
              final existingAttachments = existingDoc != null
                  ? await db.getAttachments(actualDocId)
                  : <LocalAttachment>[];

              if (attachmentsMap != null) {
                int ordering = 0;
                for (final entry in attachmentsMap.entries) {
                  final attName = entry.key;
                  final attMeta = entry.value as Map<String, dynamic>;
                  final base64Data = attMeta['data'] as String?;
                  if (base64Data == null) {
                    _log.fine(
                      'Replication: skipping stub attachment "$attName" for $docId (already on target)',
                    );
                    continue;
                  }

                  final data = base64Decode(base64Data);
                  _log.fine(
                    'Replication: writing attachment "$attName" for $docId (${data.length} bytes)',
                  );
                  ordering++;
                  final existingId = existingAttachments
                      .firstWhereOrNull((e) => e.name == attName)
                      ?.id;
                  await _saveAttachmentWithFileIO(
                    LocalAttachmentsCompanion(
                      id: existingId != null
                          ? Value(existingId)
                          : Value.absent(),
                      fkdocument: Value(actualDocId),
                      name: Value(attName),
                      revpos: Value(attMeta['revpos'] as int? ?? 1),
                      contentType: Value(
                        attMeta['content_type'] as String? ??
                            'application/octet-stream',
                      ),
                      ordering: Value(ordering),
                    ),
                    Uint8List.fromList(data),
                    deferredFileDeletes: deferredFileDeletes,
                  );
                }
              }

              // Delete orphaned attachment rows — those present locally but
              // absent from the incoming revision's _attachments map.
              // Skip when the whole document is being tombstoned: the
              // cleanup_attachments_on_tombstone DB trigger handles that case.
              if (!isDeleted) {
                final newAttachmentNames =
                    attachmentsMap?.keys.toSet() ?? <String>{};
                for (final existing in existingAttachments) {
                  if (!newAttachmentNames.contains(existing.name)) {
                    await db.deleteAttachment(existing.id);
                    await _deleteAttachmentFile(existing.id);
                  }
                }
              }

              results.add(BulkDocsResult(id: docId, ok: true, rev: docRev));
              for (final id in tombstoneAttachmentIds) {
                await _deleteAttachmentFile(id);
              }
            }
          } catch (e, stackTrace) {
            // If the error is already a CouchDbException, propagate it so callers
            // that expect a thrown CouchDbException (some test cases) will receive it.
            if (e is CouchDbException) rethrow;

            // Log unexpected errors for debugging
            _log.warning(
              'Unexpected error during bulkDocs for document $docId: $e',
              e,
              stackTrace,
            );

            results.add(
              BulkDocsResult(
                id: docId ?? '',
                ok: false,
                error: "unknown_error",
                reason: e.toString(),
              ),
            );
          }
        }
      });

      // Clean up old attachment files after transaction committed successfully.
      for (final oldId in deferredFileDeletes) {
        await _deleteAttachmentFile(oldId);
      }

      return newEdits ? results : [];
    });
  }

  // --- Conflict leaf helpers (Decision A2 in PLAN.md) ----------------------

  /// Expands a CouchDB `_revisions` object (`{start, ids}`) into the list of
  /// full rev strings ("N-hash"), newest-first. Falls back to [fallbackRev]
  /// when the object is absent or malformed.
  List<String> _expandRevisions(
    Map<String, dynamic>? revisions,
    String fallbackRev,
  ) {
    if (revisions == null) return [fallbackRev];
    final start = (revisions['start'] as num?)?.toInt();
    final ids = (revisions['ids'] as List?)?.cast<String>();
    if (start == null || ids == null || ids.isEmpty) return [fallbackRev];
    return [for (var i = 0; i < ids.length; i++) '${start - i}-${ids[i]}'];
  }

  /// All non-winning conflict leaf rows stored for the document row [docRowId].
  Future<List<LocalConflictRevision>> _getConflictRevs(int docRowId) =>
      db.getConflictRevisions(docRowId);

  /// The `changes` array (leaf rev list) for one changes-feed entry.
  ///
  /// With [styleAllDocs] (replication's `style=all_docs`) this advertises EVERY
  /// leaf of the document — the winner plus all stored conflict leaves, deleted
  /// ones included — so Local can act as a faithful replication *source* for
  /// conflicted documents: the puller's `revsDiff` then sees the conflict and
  /// tombstone leaves and transfers the ones the target lacks (PLAN.md Phase 1
  /// Stage 3; required by Phase 2 so a resolution tombstone reaches the remote).
  /// Without [styleAllDocs] only the winning rev is advertised. The per-doc
  /// query is only run when [styleAllDocs] is set (replication), so the common
  /// app-level changes feed pays nothing.
  Future<List<Map<String, String>>> _changesArrayForDoc(
    LocalDocumentWithBlob ldoc,
    bool styleAllDocs,
  ) async {
    if (!styleAllDocs) {
      return [
        {'rev': ldoc.document.rev},
      ];
    }
    final conflicts = await _getConflictRevs(ldoc.document.id);
    return [
      {'rev': ldoc.document.rev},
      for (final c in conflicts) {'rev': c.rev},
    ];
  }

  /// Synchronous variant of [_changesArrayForDoc] for the normal/long-poll feed,
  /// using a [conflictMap] (doc row id → conflict revs) fetched once for the
  /// whole batch via [AppDatabase.conflictRevsByDoc].
  List<Map<String, String>> _changesArrayFromMap(
    LocalDocumentWithBlob ldoc,
    bool styleAllDocs,
    Map<int, List<String>> conflictMap,
  ) {
    final winner = {'rev': ldoc.document.rev};
    if (!styleAllDocs) return [winner];
    final extra = conflictMap[ldoc.document.id];
    if (extra == null || extra.isEmpty) return [winner];
    return [
      winner,
      for (final r in extra) {'rev': r},
    ];
  }

  /// Stores a non-winning conflict leaf for [docRowId], replacing any existing
  /// row for the same rev (idempotent). The body is stored with `_attachments`
  /// stripped (the leaf's attachment *bytes* are stored separately in
  /// `local_attachments` keyed by `fkconflict`, Stage 2) and `_revisions` kept
  /// (needed for ancestry checks and `revs:true` reads). Returns the
  /// `local_conflict_revisions` row id, used as the `fkconflict` when persisting
  /// this leaf's attachments.
  Future<int> _putConflictLeaf({
    required int docRowId,
    required String rev,
    required int version,
    required bool deleted,
    required Map<String, dynamic> bodyMap,
    Map<String, dynamic>? revisions,
  }) async {
    final body = Map<String, dynamic>.from(bodyMap)
      ..remove('_attachments')
      ..remove('_revs_info')
      ..remove('_conflicts')
      ..remove('_deleted_conflicts')
      ..remove('_local_seq');
    if (revisions != null) {
      body['_revisions'] = revisions;
    } else {
      body.remove('_revisions');
    }
    return db.putConflictRevision(
      docRowId: docRowId,
      rev: rev,
      version: version,
      deleted: deleted,
      body: jsonEncode(body),
    );
  }

  /// Persists a non-winning conflict leaf's **inline (base64)** attachments,
  /// keyed by [conflictRowId] (`fkconflict`). Stub entries (no `data`) are
  /// skipped. Mirrors the winner inline loop but with `fkconflict` set, so the
  /// leaf's bytes are retrievable via `get(rev:leaf, attachments:true)` /
  /// `getAttachment(rev:leaf)` (PLAN.md Phase 1 Stage 2). Must run in a txn.
  Future<void> _storeInlineConflictAttachments({
    required int docRowId,
    required int conflictRowId,
    required Map<String, dynamic>? attachmentsMap,
    List<int>? deferredFileDeletes,
  }) async {
    if (attachmentsMap == null) return;
    int ordering = 0;
    for (final entry in attachmentsMap.entries) {
      final attMeta = entry.value as Map<String, dynamic>;
      final base64Data = attMeta['data'] as String?;
      if (base64Data == null) continue; // stub (atts_since) — nothing to store
      ordering++;
      await _saveAttachmentWithFileIO(
        LocalAttachmentsCompanion(
          fkdocument: Value(docRowId),
          fkconflict: Value(conflictRowId),
          name: Value(entry.key),
          revpos: Value(attMeta['revpos'] as int? ?? 1),
          contentType: Value(
            attMeta['content_type'] as String? ?? 'application/octet-stream',
          ),
          ordering: Value(ordering),
        ),
        Uint8List.fromList(base64Decode(base64Data)),
        deferredFileDeletes: deferredFileDeletes,
      );
    }
  }

  /// Persists a non-winning conflict leaf's **streamed** attachments (multipart
  /// replication), keyed by [conflictRowId] (`fkconflict`). Mirrors the winner
  /// multipart loop with `fkconflict` set; streams to disk (no base64).
  /// Must run in a txn.
  Future<void> _storeStreamConflictAttachments({
    required int docRowId,
    required int conflictRowId,
    required Map<String, BulkGetMultipartAttachment> attachments,
    List<int>? deferredFileDeletes,
  }) async {
    int ordering = 0;
    for (final entry in attachments.entries) {
      final att = entry.value;
      ordering++;
      await _saveAttachmentFromStream(
        LocalAttachmentsCompanion(
          fkdocument: Value(docRowId),
          fkconflict: Value(conflictRowId),
          name: Value(entry.key),
          revpos: Value(att.revpos),
          contentType: Value(att.contentType),
          ordering: Value(ordering),
        ),
        att.digest,
        att.length,
        att.data,
        encoding: att.encoding,
        deferredFileDeletes: deferredFileDeletes,
      );
    }
  }

  /// After the winning leaf of [docRowId]/[docid] has been tombstoned, promote
  /// the best surviving leaf to winner per CouchDB's rule (non-deleted preferred
  /// → highest generation → highest rev hash). The demoted old winner is kept as
  /// a (deleted) conflict leaf. No-op when there are no conflict leaves or the
  /// current winner is still the best leaf. Must run inside a `db.transaction()`.
  Future<void> _promoteAfterTombstone(int docRowId, String docid) async {
    final conflicts = await db.getConflictRevisions(docRowId);
    if (conflicts.isEmpty) return;
    final winnerRow = await db.getDocument(
      dbid,
      docid,
      true,
      ignoreDeleted: true,
    );
    if (winnerRow == null) return;

    final String curRev = winnerRow.document.rev;
    final int curVer = winnerRow.document.version;
    final bool curDel = winnerRow.document.deleted ?? false;

    String hashOf(String rev) => rev.substring(rev.indexOf('-') + 1);

    String bestRev = curRev;
    int bestVer = curVer;
    bool bestDel = curDel;
    LocalConflictRevision? bestConflict;
    for (final c in conflicts) {
      final cd = c.deleted ?? false;
      // A non-deleted but bodyless leaf (a recorded permanently-gone /
      // `not_found` leaf) cannot be promoted — there is no body to serve as the
      // winner. Skip it as a candidate (it stays a conflict leaf). A deleted
      // bodyless leaf is a normal tombstone and remains promotable.
      if (!cd && c.body == null) continue;
      final bool better;
      if (cd != bestDel) {
        better = !cd; // non-deleted preferred
      } else if (c.version != bestVer) {
        better = c.version > bestVer;
      } else {
        better = hashOf(c.rev).compareTo(hashOf(bestRev)) > 0;
      }
      if (better) {
        bestRev = c.rev;
        bestVer = c.version;
        bestDel = cd;
        bestConflict = c;
      }
    }
    if (bestConflict == null) return; // current winner is still the best leaf

    // Demote the old winner to a conflict leaf (its body is gone if it was
    // tombstoned; store a minimal deleted body in that case).
    final Map<String, dynamic> oldBody = (!curDel && winnerRow.data != null)
        ? (jsonDecode(winnerRow.data!) as Map<String, dynamic>)
        : <String, dynamic>{'_id': docid, '_rev': curRev, '_deleted': true};
    final demotedRowId = await _putConflictLeaf(
      docRowId: docRowId,
      rev: curRev,
      version: curVer,
      deleted: curDel,
      bodyMap: oldBody,
      revisions: (await _getRevs(docRowId, curVer))?.toMap(),
    );
    // If the old winner was still live (not the post-tombstone case), move its
    // attachments onto the demoted conflict leaf. When it was tombstoned, the
    // cleanup_attachments_on_tombstone trigger already removed them.
    if (!curDel) {
      await db.demoteWinnerAttachments(docRowId, demotedRowId);
    }

    // Promote the chosen leaf into the winner row. Re-point its attachments to
    // the winner (fkconflict → NULL) BEFORE deleting its conflict row —
    // otherwise delete_conflict_attachments_before_conflict_revision would drop
    // the promoted leaf's attachment rows (Stage 2).
    await db.promoteConflictAttachments(bestConflict.id);
    await db.deleteConflictRevision(docRowId, bestConflict.rev);
    // The promoted leaf's generation may be below the tombstoned old winner's,
    // so the append-only revision history would keep a stale higher-version row
    // at its (version-sorted) head — mismatching the new winner and tripping the
    // `history[0].version == rev` invariant in [_getRevs] on the next write.
    // Clear it; the winner-row insert below re-seeds the head via the trigger.
    await db.clearRevisionHistory(docRowId);
    final int seq = await db.incrementAndGetUpdateSeq(dbid);
    await db
        .into(db.localDocuments)
        .insertOnConflictUpdate(
          LocalDocumentsCompanion(
            id: Value(docRowId),
            docid: Value(docid),
            fkdatabase: Value(dbid),
            rev: Value(bestConflict.rev),
            version: Value(bestConflict.version),
            deleted: Value(bestConflict.deleted ?? false),
            seq: Value(seq),
          ),
        );
    if (!(bestConflict.deleted ?? false) && bestConflict.body != null) {
      final m = jsonDecode(bestConflict.body!) as Map<String, dynamic>
        ..remove('_revisions')
        ..remove('_attachments');
      await db
          .into(db.documentBlobs)
          .insertOnConflictUpdate(
            DocumentBlobsCompanion(
              documentId: Value(docRowId),
              data: Value(jsonEncode(m)),
            ),
          );
    }
  }

  /// Applies conflict-leaf maintenance (Decision A2) for one incoming
  /// newEdits=false revision against the current stored state, using the
  /// incoming `_revisions` ancestry to tell a linear supersede from a sibling
  /// branch (CouchDB's revision tree).
  ///
  /// Outcome of [_applyIncomingLeaf].
  ///
  /// - [writeAsWinner]: the caller should write [docMap] as the **winner**
  ///   (local_documents + blob + winner attachments), as before.
  /// - [incomingConflictRowId]: when the incoming was stored as a non-winning
  ///   **conflict leaf**, the `local_conflict_revisions` row id, so the caller
  ///   can persist *that leaf's* attachment bytes with `fkconflict` set
  ///   (Stage 2). Null when there is nothing for the caller to store
  ///   (winner write, dedup, ancestor, or a leaf without attachments).
  ///
  /// The old-winner **demote** attachment re-point (when an incoming sibling
  /// wins) is done here (metadata-only), so the caller never has to.
  /// Shared by [bulkDocsRaw] and [bulkDocsFromMultipart] so all replication
  /// write paths maintain the conflict leaf set identically. Must run inside a
  /// `db.transaction()`.
  Future<({bool writeAsWinner, int? incomingConflictRowId, bool leafSetChanged})>
  _applyIncomingLeaf({
    required String docId,
    required String docRev,
    required int version,
    required bool isDeleted,
    required Map<String, dynamic> docMap,
    required Map<String, dynamic>? incomingRevisions,
    required LocalDocumentWithBlob? existingDoc,
    required List<int> deferredFileDeletes,
  }) async {
    // True when the revision tree changed but the winner row did NOT — i.e. a
    // conflict leaf was added, superseded, or tombstoned. CouchDB bumps a
    // document's update_seq for ANY tree change (so the changes feed re-emits it
    // and replication propagates it); the caller uses this flag to do the same
    // even when it isn't rewriting the winner row (PLAN.md Phase 2 — required
    // for opt-in conflict resolution to reach the remote).
    bool leafSetChanged = false;
    if (existingDoc == null) {
      return (
        writeAsWinner: true,
        incomingConflictRowId: null,
        leafSetChanged: leafSetChanged,
      );
    }
    // Already have this exact revision as the winner.
    if (existingDoc.document.rev == docRev) {
      return (
        writeAsWinner: false,
        incomingConflictRowId: null,
        leafSetChanged: leafSetChanged,
      );
    }

    final List<String> incomingChain = _expandRevisions(
      incomingRevisions,
      docRev,
    );
    final Set<String> incomingAncestors = incomingChain.toSet();

    final int docRowId = existingDoc.document.id;
    final String winnerRev = existingDoc.document.rev;
    final int winnerVersion = existingDoc.document.version;
    final bool winnerDeleted = existingDoc.document.deleted ?? false;
    final conflicts = await _getConflictRevs(docRowId);

    // (a) Already stored as a conflict leaf.
    if (conflicts.any((c) => c.rev == docRev)) {
      return (
        writeAsWinner: false,
        incomingConflictRowId: null,
        leafSetChanged: leafSetChanged,
      );
    }

    // (b) Incoming is an ancestor of an existing leaf → already represented.
    // An ancestor has a lower generation than the leaf it precedes, so this can
    // only apply when the incoming version is below the winner's, or when there
    // are conflict leaves to check. Skipping it for the common linear
    // update/delete (incoming newer, no conflicts) avoids the expensive winner
    // revision-history reconstruction.
    bool incomingIsAncestor = false;
    if (conflicts.isNotEmpty || version < winnerVersion) {
      final Set<String> winnerChain = _expandRevisions(
        (await _getRevs(docRowId, winnerVersion))?.toMap(),
        winnerRev,
      ).toSet();
      incomingIsAncestor = docRev != winnerRev && winnerChain.contains(docRev);
      if (!incomingIsAncestor) {
        for (final c in conflicts) {
          final cChain = _expandRevisions(
            (jsonDecode(c.body ?? '{}') as Map<String, dynamic>)['_revisions']
                as Map<String, dynamic>?,
            c.rev,
          );
          if (c.rev != docRev && cChain.contains(docRev)) {
            incomingIsAncestor = true;
            break;
          }
        }
      }
    }
    if (incomingIsAncestor) {
      return (
        writeAsWinner: false,
        incomingConflictRowId: null,
        leafSetChanged: leafSetChanged,
      );
    }

    // (c) Incoming supersedes any conflict leaf found in its chain. Collect that
    // leaf's attachment file ids before the delete (the BEFORE-DELETE trigger
    // drops the rows; files are the Dart layer's responsibility) so the caller
    // removes them after the transaction commits.
    for (final c in conflicts) {
      if (c.rev != docRev && incomingAncestors.contains(c.rev)) {
        deferredFileDeletes.addAll(
          (await db.getConflictAttachments(c.id)).map((a) => a.id),
        );
        await db.deleteConflictRevision(docRowId, c.rev);
        leafSetChanged = true; // a leaf was removed from the tree
      }
    }

    // (d) Does incoming beat the current winner?
    //
    // Two distinct cases, and conflating them is wrong:
    //  - **Linear descendant**: incoming descends from the current winner
    //    (winnerRev is in incoming's ancestry). The winner stops being a leaf,
    //    so incoming always supersedes it — even a tombstone child of a live
    //    winner (a normal delete). Generation/deleted comparisons do NOT apply.
    //  - **Sibling branches**: incoming does not descend from the winner. Then
    //    CouchDB's leaf rule decides: a non-deleted leaf beats a deleted one
    //    regardless of generation, then higher generation, then higher hash.
    //    (This is the same ordering [_promoteAfterTombstone] uses.)
    //
    // We can only trust the descendant/sibling distinction when the incoming
    // `_revisions` chain is present; without it (haveAncestry == false) we fall
    // back to the legacy generation-first comparison so a tombstone delivered
    // without `_revisions` still performs a normal linear delete.
    final bool haveAncestry = incomingRevisions != null;
    final ih = docRev.substring(docRev.indexOf('-') + 1);
    final eh = winnerRev.substring(winnerRev.indexOf('-') + 1);
    bool incomingWins;
    if (haveAncestry && incomingAncestors.contains(winnerRev)) {
      incomingWins = true; // linear supersede — winner is an ancestor
    } else if (haveAncestry && isDeleted != winnerDeleted) {
      incomingWins = !isDeleted; // sibling leaves: non-deleted preferred
    } else if (version != winnerVersion) {
      incomingWins = version > winnerVersion;
    } else if (isDeleted != winnerDeleted) {
      incomingWins = !isDeleted;
    } else {
      incomingWins = ih.compareTo(eh) > 0;
    }

    // Conflict bookkeeping (storing a losing sibling, or demoting the old
    // winner) is only safe when we actually have the incoming `_revisions`
    // chain (haveAncestry, above) to prove a sibling branch. Without it we fall
    // back to the historical winner-only behaviour: a losing rev is skipped, and
    // a winning rev simply overwrites — so e.g. a tombstone delivered without
    // `_revisions` performs a normal linear delete instead of being
    // misclassified as a sibling (which promotion would then undo).
    if (!incomingWins) {
      if (haveAncestry) {
        // Sibling that loses → store as a conflict leaf; winner stays. The
        // returned row id lets the caller persist this leaf's attachments
        // (fkconflict). A tombstone leaf has no attachments to store.
        final conflictRowId = await _putConflictLeaf(
          docRowId: docRowId,
          rev: docRev,
          version: version,
          deleted: isDeleted,
          bodyMap: docMap,
          revisions: incomingRevisions,
        );
        leafSetChanged = true; // a new (losing) leaf was added to the tree
        return (
          writeAsWinner: false,
          incomingConflictRowId: isDeleted ? null : conflictRowId,
          leafSetChanged: leafSetChanged,
        );
      }
      return (
        writeAsWinner: false,
        incomingConflictRowId: null,
        leafSetChanged: leafSetChanged,
      );
    }

    // Incoming wins. If we have ancestry and the old winner is a sibling (not an
    // ancestor of incoming) demote it to a conflict leaf to preserve it — and
    // re-point its attachments onto that conflict leaf (metadata-only; files
    // keep their `att/{PK}` name). The caller then writes the incoming winner's
    // own attachments as fkconflict=NULL.
    if (haveAncestry && !incomingAncestors.contains(winnerRev)) {
      final Map<String, dynamic> oldBody = existingDoc.data != null
          ? (jsonDecode(existingDoc.data!) as Map<String, dynamic>)
          : <String, dynamic>{
              '_id': docId,
              '_rev': winnerRev,
              '_deleted': true,
            };
      final demotedRowId = await _putConflictLeaf(
        docRowId: docRowId,
        rev: winnerRev,
        version: winnerVersion,
        deleted: winnerDeleted,
        bodyMap: oldBody,
        revisions: (await _getRevs(docRowId, winnerVersion))?.toMap(),
      );
      if (!winnerDeleted) {
        await db.demoteWinnerAttachments(docRowId, demotedRowId);
      }
    }
    return (
      writeAsWinner: true,
      incomingConflictRowId: null,
      leafSetChanged: leafSetChanged,
    );
  }

  @override
  Future<DatabaseInfo?> info() async {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    return await m.protect(() async {
      LocalDatabase? ldb = await db.getDatabase(dbname);

      if (ldb == null) {
        return null;
      }

      DatabaseInfo info = DatabaseInfo(
        dbName: dbname,
        docCount: -1,
        docDelCount: 0,
        updateSeq: _makeSeqString(ldb.updateSeq),
        instanceStartTime: '',
        purgeSeq: '',
        sizes: {},
        props: {},
        diskFormatVersion: -1,
        compactRunning: false,
        cluster: {},
      );

      return info;
    });
  }

  /// Returns the changes feed as a stream of raw JSON maps, mirroring the
  /// CouchDB `_changes` endpoint.
  ///
  /// **Normal / long-poll mode**: emits one map (the full response) and closes.
  /// The documents and `last_seq` are read atomically so that a concurrent
  /// [saveAttachment] cannot produce a stale revision with a newer sequence
  /// number (which would cause the replication layer to request a non-existent
  /// revision).
  ///
  /// **Continuous mode**: emits one map per document change and stays open.
  /// Replays documents already stored with `seq > since` before switching to
  /// watching future writes — without this replay, documents written between
  /// the initial checkpoint save and the subscription setup would be silently
  /// lost across restarts.
  ///
  /// `_local/*` documents are filtered out in both modes because they are
  /// checkpoints and must not appear in the replication feed.
  @override
  Stream<Map<String, dynamic>> changesRaw({
    List<String>? docIds,
    bool descending = false,
    FeedMode feedmode = FeedMode.normal,
    int heartbeat = 30000,
    bool includeDocs = false,
    bool attachments = false,
    bool attEncodingInfo = false,
    int? lastEventId,
    int limit = 0,
    String? since,
    bool styleAllDocs = false,
    int? timeout,
    int? seqInterval,
    ChangesFilter? filter,
    String? view,
  }) {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    // check for unsupported settings
    assert(docIds == null);
    assert(descending == false);
    assert(feedmode != FeedMode.eventsource);
    assert(
      filter != ChangesFilter.view || view != null,
      'filter: ChangesFilter.view requires a view path',
    );
    assert(attachments == false);
    assert(attEncodingInfo == false);
    assert(lastEventId == null);
    assert(limit == 0);
    // styleAllDocs is now supported: Local stores conflict leaves (Decision A2)
    // and advertises them all in the feed so it can forward conflict branches
    // as a replication source (Stage 3) — see _changesArrayForDoc.
    assert(timeout == null);
    assert(seqInterval == null);

    // helper to parse the numeric seq from a Couch-like seq string (e.g. "12-dummyhash")
    int? parseSinceSeq(String? s) {
      if (s == null) return null;
      final dash = s.indexOf('-');
      final head = dash == -1 ? s : s.substring(0, dash);
      return int.tryParse(head);
    }

    final bool sinceIsNow = since == 'now';
    int? sinceSeq = sinceIsNow ? null : parseSinceSeq(since);

    // When the _view filter is active we run the view's map function over each
    // candidate document; the engine is reused for the whole subscription.
    final bool filterActive = filter == ChangesFilter.view;
    // The filter needs the document body even if the caller didn't request it.
    final bool loadDocs = includeDocs || filterActive;
    ViewMapFilter? viewFilter;

    // Create a dedicated StreamController for this request
    StreamSubscription? subscription;
    final controller = StreamController<Map<String, dynamic>>(
      onCancel: () async {
        // when there is no listeners anymore, the http
        // subscription needs to be canceled!
        await subscription?.cancel();
        viewFilter?.dispose();
      },
    );

    unawaited(() async {
      if (filterActive) {
        final ViewCtrl? ctrl = await viewMgr.getView(view!);
        if (ctrl == null) {
          controller.addError(
            CouchDbException(
              CouchDbStatusCodes.notFound,
              'view "$view" not found for _view filter',
            ),
          );
          await controller.close();
          return;
        }
        viewFilter = ctrl.createMapFilter();
      }

      // Runs the active _view filter over a change candidate. Tombstones (no
      // blob) are passed as {_id,_rev,_deleted:true}; per the _view deletion
      // caveat these usually emit nothing and are therefore excluded.
      bool passesFilter(LocalDocumentWithBlob ldoc) {
        final f = viewFilter;
        if (f == null) return true;
        final Map<String, dynamic> docJson = ldoc.data != null
            ? jsonDecode(ldoc.data!) as Map<String, dynamic>
            : <String, dynamic>{
                '_id': ldoc.document.docid,
                '_rev': ldoc.document.rev,
                '_deleted': true,
              };
        return f.emits(docJson);
      }

      if (feedmode == FeedMode.normal || feedmode == FeedMode.longpoll) {
        // normal feed -- just a single response
        // Read documents and updateSeq in a single transaction to get a
        // consistent snapshot. Without this, a concurrent write (e.g.
        // saveAttachment) can update the document between the two queries,
        // causing the changes feed to report a stale revision with a newer
        // lastSeq — which makes replication request a rev that no longer exists.
        final snapshot = await db.getDocumentsAndUpdateSeq(dbid, loadDocs);
        var ldocs = snapshot.docs;
        final dbRecord = snapshot.dbRecord;
        if (dbRecord == null) {
          // Database record no longer exists - stop the stream
          await controller.close();
          return;
        }
        // filter out local documents (_local/*) - they don't appear in changes feed
        ldocs = ldocs
            .where((e) => !e.document.docid.startsWith('_local/'))
            .toList(growable: false);
        // filter by since (only return changes with seq strictly greater than since)
        if (sinceIsNow) {
          // since=now means "no historical changes, just the current last_seq"
          ldocs = [];
        } else if (sinceSeq != null) {
          ldocs = ldocs
              .where((e) => e.document.seq > sinceSeq)
              .toList(growable: false);
        }
        // apply the _view filter (runs the view's map over each candidate)
        if (viewFilter != null) {
          ldocs = ldocs.where(passesFilter).toList(growable: false);
        }
        assert(controller.hasListener);
        // For style=all_docs, advertise every leaf (winner + conflict leaves)
        // so Local can forward conflict branches as a replication source
        // (Stage 3). Fetched once for the whole batch; empty otherwise.
        final Map<int, List<String>> conflictMap = styleAllDocs
            ? await db.conflictRevsByDoc(dbid)
            : const <int, List<String>>{};
        // Build raw JSON map instead of ChangesResult
        final json = <String, dynamic>{
          'pending': 0,
          'last_seq': _makeSeqString(dbRecord.updateSeq),
          'results': ldocs.map((ldoc) {
            final changeEntry = <String, dynamic>{
              'seq': _makeSeqString(ldoc.document.seq),
              'id': ldoc.document.docid,
              'changes': _changesArrayFromMap(ldoc, styleAllDocs, conflictMap),
            };
            if (ldoc.document.deleted == true) {
              changeEntry['deleted'] = true;
            }
            if (includeDocs && ldoc.data != null) {
              changeEntry['doc'] =
                  jsonDecode(ldoc.data!) as Map<String, dynamic>;
            }
            return changeEntry;
          }).toList(),
        };
        controller.add(json);
        await controller.close();
        viewFilter?.dispose();
      } else {
        // continuous feed -- stream changes as they occur
        try {
          // Pass sinceSeq so watchDocuments first replays any documents already
          // in the DB with seq > sinceSeq before watching future changes.
          // Without this, docs written between the one-shot push (which saves
          // the initial checkpoint) and this subscription would be silently
          // skipped, leaving the checkpoint permanently stale after a restart.
          //
          // For 'now', resolve to the current updateSeq so only future changes
          // are emitted (matching CouchDB's since=now semantics).
          final int? effectiveSince = sinceIsNow
              ? await db.getCurrentUpdateSeq(dbid)
              : sinceSeq;
          subscription = db
              .watchDocuments(dbid, loadDocs, since: effectiveSince)
              // Compute the (possibly multi-leaf) changes array off the listener
              // via asyncMap, which preserves emission order — needed because
              // style=all_docs forwarding (Stage 3) requires a per-doc conflict
              // query. For the common app feed (styleAllDocs=false) this does no
              // DB work.
              .asyncMap(
                (LocalDocumentWithBlob ldoc) async => (
                  ldoc,
                  await _changesArrayForDoc(ldoc, styleAllDocs),
                ),
              )
              .listen(
                ((LocalDocumentWithBlob, List<Map<String, String>>) entry) {
                  final ldoc = entry.$1;
                  if (controller.isClosed) {
                    return;
                  }
                  // filter out local documents (_local/*) - they don't appear in changes feed
                  if (ldoc.document.docid.startsWith('_local/')) {
                    return;
                  }
                  // apply the _view filter (runs the view's map over the doc)
                  if (!passesFilter(ldoc)) {
                    return;
                  }
                  // Build raw JSON map for each change
                  final json = <String, dynamic>{
                    'seq': _makeSeqString(ldoc.document.seq),
                    'id': ldoc.document.docid,
                    'changes': entry.$2,
                  };
                  if (ldoc.document.deleted == true) {
                    json['deleted'] = true;
                  }
                  if (includeDocs && ldoc.data != null) {
                    json['doc'] =
                        jsonDecode(ldoc.data!) as Map<String, dynamic>;
                  }
                  controller.add(json);
                },
                onError: (e) {
                  // Database may have been deleted - close the stream gracefully
                  _log.fine(
                    'Changes stream error (database may have been deleted): $e',
                  );
                  if (!controller.isClosed) {
                    unawaited(controller.close());
                  }
                },
              );
        } catch (e) {
          // Database may have been deleted before we could start watching
          _log.fine(
            'Failed to start changes stream (database may have been deleted): $e',
          );
          if (!controller.isClosed) {
            await controller.close();
          }
        }
      }
    }());

    return controller.stream;
  }

  @override
  Future<Map<String, dynamic>?> getRaw(
    String docid, {
    String? rev,
    bool revs = false,
    bool revsInfo = false,
    bool attachments = false,
    bool conflicts = false,
    bool deletedConflicts = false,
    bool meta = false,
  }) async {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    return await m.protect(() async {
      return await _internalGetRaw(
        docid,
        rev: rev,
        revs: revs,
        revsInfo: revsInfo,
        attachments: attachments,
        conflicts: conflicts,
        deletedConflicts: deletedConflicts,
        meta: meta,
      );
    });
  }

  /// Internal (mutex-free) document fetch returning a raw JSON map.
  ///
  /// Tombstoned documents have no blob row — the map is reconstructed from
  /// the metadata columns (`_id`, `_rev`, `_deleted: true`).
  ///
  /// [maxAttsSinceVersion]: when non-null, any attachment whose `revpos` is
  /// ≤ this value is returned as a stub (no `data` field) rather than
  /// inline base64.  This implements the `atts_since` optimisation: the
  /// caller already has a revision that contains those attachments, so there
  /// is no need to re-transfer the blobs.
  Future<Map<String, dynamic>?> _internalGetRaw(
    String docid, {
    String? rev,
    bool revs = false,
    bool revsInfo = false,
    bool attachments = false,
    bool conflicts = false,
    bool deletedConflicts = false,
    bool meta = false,
    bool ignoreDeleted = false,
    int? maxAttsSinceVersion,
  }) async {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    if (docid == "_local_docs") {
      ViewResult res = await getLocalDocuments();
      return jsonDecode(res.toJson());
    }

    LocalDocumentWithBlob? ldoc = await db.getDocument(
      dbid,
      docid,
      true,
      rev: rev,
      ignoreDeleted: ignoreDeleted,
    );
    if (ldoc == null) {
      // The winner doesn't match. If a specific rev was requested, it may be a
      // stored non-winning conflict leaf (Decision A2) — serve its body.
      if (rev != null) {
        final winnerRow = await db.getDocument(
          dbid,
          docid,
          false,
          ignoreDeleted: true,
        );
        if (winnerRow != null) {
          final leaf = (await db.getConflictRevisions(
            winnerRow.document.id,
          )).firstWhereOrNull((c) => c.rev == rev);
          if (leaf != null) {
            if (leaf.body == null) {
              // A deleted tombstone leaf serves a minimal deleted doc; a
              // non-deleted bodyless leaf (a recorded permanently-gone leaf) has
              // no retrievable body → not_found, exactly like the source.
              if (leaf.deleted ?? false) {
                return {'_id': docid, '_rev': rev, '_deleted': true};
              }
              return null;
            }
            final m = jsonDecode(leaf.body!) as Map<String, dynamic>;
            // Conflict bodies are stored with `_revisions` kept; strip it when
            // the caller didn't ask for it.
            if (revs != true) m.remove('_revisions');
            // Stage 2: reconstruct this leaf's own attachments (inline base64
            // when attachments:true, else stubs) from its fkconflict rows, so
            // get(rev:leaf) matches Http.
            final attMap = await _recreateAttachmentMapFromDatabase(
              winnerRow.document.id,
              attachments,
              conflictRowId: leaf.id,
            );
            if (attMap != null) {
              m['_attachments'] = attMap.map((key, value) {
                final stub = value.toMap();
                if (value.encoding != null) stub['encoding'] = value.encoding;
                return MapEntry(key, stub);
              });
            }
            return m;
          }
        }
      }
      return null;
    }

    // Tombstoned documents have no blob - reconstruct minimal doc from metadata
    Map<String, dynamic> docMap;
    if (ldoc.data == null) {
      docMap = {
        '_id': ldoc.document.docid,
        '_rev': ldoc.document.rev,
        '_deleted': true,
      };
    } else {
      // Parse the JSON data as Map
      docMap = jsonDecode(ldoc.data!);
    }

    // `meta` is shorthand for conflicts + deleted_conflicts + revs_info.
    final wantRevsInfo = revsInfo || meta;
    final wantConflicts = conflicts || meta;
    final wantDeletedConflicts = deletedConflicts || meta;

    // Add revisions and revsInfo if requested
    if (revs == true) {
      final revisions = await _getRevs(ldoc.document.id, ldoc.document.version);
      if (revisions != null) {
        docMap['_revisions'] = revisions.toMap();
      }
    }
    if (wantRevsInfo) {
      final revsInfoList = await _getRevsInfo(ldoc.document.id);
      docMap['_revs_info'] = revsInfoList.map((e) => e.toMap()).toList();
    }
    // Populate `_conflicts` / `_deleted_conflicts` from the stored non-winning
    // conflict leaves (Decision A2) so Local matches Http (Phase 0 test P2).
    if (wantConflicts || wantDeletedConflicts) {
      final conflictLeaves = await db.getConflictRevisions(ldoc.document.id);
      if (wantConflicts) {
        final live = conflictLeaves
            .where((c) => !(c.deleted ?? false))
            .map((c) => c.rev)
            .toList();
        if (live.isNotEmpty) docMap['_conflicts'] = live;
      }
      if (wantDeletedConflicts) {
        final del = conflictLeaves
            .where((c) => c.deleted ?? false)
            .map((c) => c.rev)
            .toList();
        if (del.isNotEmpty) docMap['_deleted_conflicts'] = del;
      }
    }

    if (ldoc.data != null) {
      final attachmentsMap = await _recreateAttachmentMapFromDatabase(
        ldoc.document.id,
        attachments,
        maxAttsSinceVersion: maxAttsSinceVersion,
      );
      if (attachmentsMap != null) {
        // value.toMap() strips `encoding` via AttachmentInfoRawHook so that
        // CouchDB protocol messages never carry it. Re-insert it here so that
        // callers of getRaw() / get() can still read AttachmentInfo.encoding.
        docMap['_attachments'] = attachmentsMap.map((key, value) {
          final stub = value.toMap();
          if (value.encoding != null) stub['encoding'] = value.encoding;
          return MapEntry(key, stub);
        });
      }
    }

    return docMap;
  }

  Future<CouchDocumentBase?> _internalGet(
    String docid, {
    String? rev,
    bool revs = false,
    bool revsInfo = false,
    bool attachments = false,
  }) async {
    final map = await _internalGetRaw(
      docid,
      rev: rev,
      revs: revs,
      revsInfo: revsInfo,
      attachments: attachments,
    );
    if (map == null) return null;

    return CouchDocumentBase.fromMap(map);
  }

  @override
  Future<ViewResult> getLocalDocuments({
    bool conflicts = false,
    bool descending = false,
    String? endkey,
    String? endkeyDocid,
    bool includeDocs = false,
    bool inclusiveEnd = true,
    String? key,
    List<String>? keys,
    int? limit,
    int? skip,
    String? startkey,
    String? startkeyDocid,
    bool updateSeq = false,
  }) async {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    return await m.protect(() async {
      // Get all documents with blob data if needed
      List<LocalDocumentWithBlob> allDocs = await db.getDocuments(
        dbid,
        includeDocs,
      );

      // Filter to only include local documents (those with "_local/" prefix)
      List<LocalDocumentWithBlob> localDocs = allDocs
          .where((ldoc) => ldoc.document.docid.startsWith('_local/'))
          .toList();

      // Apply key filters
      if (key != null) {
        localDocs = localDocs
            .where((ldoc) => ldoc.document.docid == key)
            .toList();
      }
      if (keys != null) {
        // When keys are specified, filter and sort in the order requested
        final docsMap = {for (var ldoc in localDocs) ldoc.document.docid: ldoc};
        localDocs = keys
            .where((k) => docsMap.containsKey(k))
            .map((k) => docsMap[k]!)
            .toList();
      }
      if (startkey != null) {
        localDocs = localDocs.where((ldoc) {
          final comparison = ldoc.document.docid.compareTo(startkey);
          return descending ? comparison <= 0 : comparison >= 0;
        }).toList();
      }
      if (endkey != null) {
        localDocs = localDocs.where((ldoc) {
          final comparison = ldoc.document.docid.compareTo(endkey);
          if (inclusiveEnd) {
            return descending ? comparison >= 0 : comparison <= 0;
          } else {
            return descending ? comparison > 0 : comparison < 0;
          }
        }).toList();
      }

      // Sort the documents (unless keys was specified, which already defines the order)
      if (keys == null) {
        localDocs.sort((a, b) {
          final comparison = a.document.docid.compareTo(b.document.docid);
          return descending ? -comparison : comparison;
        });
      }

      // Remember total before pagination
      //final totalRows = localDocs.length;
      final effectiveSkip = skip ?? 0;

      // Apply skip and limit
      if (effectiveSkip > 0) {
        localDocs = localDocs.skip(effectiveSkip).toList();
      }
      if (limit != null && limit > 0) {
        localDocs = localDocs.take(limit).toList();
      }

      // Transform to ViewEntry format
      List<ViewEntry> entries = [];
      for (final ldoc in localDocs) {
        CouchDocumentBase? docData;
        if (includeDocs && ldoc.data != null) {
          docData = CouchDocumentBase.fromJson(ldoc.data!);
        }

        entries.add(
          ViewEntry(
            id: ldoc.document.docid,
            key: ldoc.document.docid,
            value: {'rev': ldoc.document.rev},
            doc: docData,
          ),
        );
      }

      return ViewResult(totalRows: null, offset: null, rows: entries);
    });
  }

  /// Attachments are not stored in the document
  /// After loading they have to be recreated from the attachments table
  Future<Map<String, AttachmentInfo>?> _recreateAttachmentMapFromDatabase(
    int dbdocid,
    bool includeData, {
    // When non-null, attachments with revpos <= this value are returned as
    // stubs rather than inline data (atts_since optimisation: the caller
    // already holds a revision that contains those attachments).
    int? maxAttsSinceVersion,
    // When non-null, build the attachment map for the **conflict leaf** with
    // this `local_conflict_revisions` row id instead of the winner's (Stage 2).
    int? conflictRowId,
  }) async {
    List<LocalAttachment> attachments = conflictRowId != null
        ? await db.getConflictAttachments(conflictRowId)
        : await db.getAttachments(dbdocid);

    Map<String, AttachmentInfo> map = {};
    for (int i = 0; i < attachments.length; ++i) {
      final a = attachments[i];

      // Include blob data only when the attachment changed after the revisions
      // the caller already has (revpos > maxAttsSinceVersion).
      final shouldIncludeData =
          includeData &&
          (maxAttsSinceVersion == null || a.revpos > maxAttsSinceVersion);

      assert(map.containsKey(a.name) == false);
      map[a.name] = AttachmentInfo(
        contentType: a.contentType,
        revpos: a.revpos,
        digest: a.digest,
        data: shouldIncludeData
            ? base64Encode((await attachmentStorage.readAttachment(a.id))!)
            : null,
        length: shouldIncludeData ? null : a.length,
        stub: shouldIncludeData ? null : true,
        encoding: a.encoding,
      );
    }

    return map.isEmpty ? null : map;
  }

  /// Returns the document(s) matching the requested open revisions.
  ///
  /// Used by the replication protocol source (push) to satisfy a
  /// `_bulk_get` or `_open_revs` request from the target.  The caller
  /// passes the list of revisions it needs; this method returns each one
  /// as either `{ok: doc}` or `{missing: rev}`.
  ///
  /// We store only one (winning) revision per document, so any requested
  /// revision that is not the current head is reported as `missing`.
  @override
  Future<List<OpenRevsResult>?> getOpenRevs(
    String docid, {
    List<String>? revisions,
    bool revs = false,
  }) async {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    return await m.protect(() async {
      List<OpenRevsResult> res = [];

      LocalDocumentWithBlob? ldoc = await db.getDocument(
        dbid,
        docid,
        true,
        ignoreDeleted: true,
      );
      if (ldoc != null) {
        CouchDocumentBase doc;
        // Tombstoned documents have no blob - reconstruct minimal doc from metadata
        if (ldoc.data == null) {
          doc = CouchDocumentBase(
            id: ldoc.document.docid,
            rev: ldoc.document.rev,
            deleted: true,
          );
        } else {
          doc = CouchDocumentBase.fromJson(ldoc.data!);
        }

        if (revs == true) {
          doc = await _addRevs(ldoc.document.id, doc);
        }

        final Set<String> addedRevs = {};
        if (revisions == null || revisions.contains(doc.rev)) {
          res.add(
            OpenRevsResult(missingRev: null, state: OpenRevsState.ok, doc: doc),
          );
          if (doc.rev != null) addedRevs.add(doc.rev!);
        }

        // Add non-winning conflict leaves (Decision A2) so open_revs returns the
        // full leaf set, matching CouchDB. Each leaf carries its own body (and
        // `_revisions` when revs:true).
        for (final c in await db.getConflictRevisions(ldoc.document.id)) {
          if (revisions != null && !revisions.contains(c.rev)) continue;
          CouchDocumentBase cdoc;
          if (c.body == null) {
            cdoc = CouchDocumentBase(id: docid, rev: c.rev, deleted: true);
          } else {
            final m = jsonDecode(c.body!) as Map<String, dynamic>;
            if (revs != true) m.remove('_revisions');
            cdoc = CouchDocumentBase.fromMap(m);
          }
          res.add(
            OpenRevsResult(missingRev: null, state: OpenRevsState.ok, doc: cdoc),
          );
          addedRevs.add(c.rev);
        }

        if (revisions != null) {
          List<RevisionHistory> history = (await db.getRevisionHistory(
            dbid: dbid,
            dbdocid: ldoc.document.id,
            sortDesc: false,
          ))!;

          for (int i = 0; i < history.length; ++i) {
            if (!addedRevs.contains(history[i].rev) &&
                revisions.contains(history[i].rev)) {
              res.add(
                OpenRevsResult(
                  state: OpenRevsState.missing,
                  missingRev: history[i].rev,
                ),
              );
            }
          }
        }
      }

      // currently its unclear under what circumstances CouchDb returns multiple documents
      return res.isEmpty ? null : res;
    });
  }

  /// Builds the `_revisions` object (`{start, ids}`) for a document.
  ///
  /// CouchDB encodes the full revision history as a starting generation number
  /// (`start`) and a list of hash-only parts (`ids`), newest-first.
  /// `start` equals the generation of the most recent revision; each entry in
  /// `ids` corresponds to `start`, `start-1`, `start-2`, … respectively.
  Future<Revisions?> _getRevs(int dbdocid, int rev) async {
    List<RevisionHistory>? history = await db.getRevisionHistory(
      dbdocid: dbdocid,
    );
    assert(history != null);
    if (history == null || history.isEmpty) return null;

    List<String> ids = [];
    for (RevisionHistory h in history) {
      ids.add(h.rev.split('-')[1]);
    }
    assert(history[0].version == rev);
    Revisions revs = Revisions(start: history[0].version, ids: ids);
    return revs;
  }

  Future<CouchDocumentBase> _addRevs(
    int docid,
    final CouchDocumentBase doc,
  ) async {
    return doc.copyWith(
      revisions: await _getRevs(docid, doc.getVersionFromRev()),
    );
  }

  /// Builds the `_revs_info` list for a document.
  ///
  /// Each entry reports the status of one revision in history:
  /// - `available` — the head revision (blob present).
  /// - `missing`   — an intermediate revision (we keep only the head blob).
  /// - `deleted`   — a tombstone revision.
  Future<List<RevsInfo>> _getRevsInfo(int dbdocid) async {
    List<RevisionHistory>? history = await db.getRevisionHistory(
      dbdocid: dbdocid,
    );
    assert(history != null);

    List<RevsInfo> infos = [];
    for (int i = 0; i < history!.length; ++i) {
      RevisionHistory h = history[i];
      infos.add(
        RevsInfo(
          rev: h.rev,
          status: h.deleted == true
              ? RevsInfoStatus.deleted
              : i == 0
              ? RevsInfoStatus.available
              : RevsInfoStatus.missing,
        ),
      );
    }
    return infos;
  }

  Future<String?> _getRevFromDoc(String docid) async {
    final LocalDocumentWithBlob? doc = await db.getDocument(
      dbid,
      docid,
      true,
      ignoreDeleted: true,
    );
    if (doc == null) return null;
    // Tombstoned documents have no blob - use rev from document metadata
    if (doc.data == null) return doc.document.rev;
    return jsonDecode(doc.data!)['_rev'] as String;
  }

  /// Reacting to design-document changes (rebuilding views when a map/reduce
  /// function changes) is handled lazily and centrally by [ViewMgr.getView],
  /// which compares each cached view against the current design document on
  /// every query and rebuilds on a change — covering all write paths (put,
  /// remove, bulkDocs, replication). This hook is kept as an extension point
  /// and intentionally does nothing.
  Future<void> _checkViewsAfterDesignDocumentChange(DesignDocument doc) async {}

  /// Updates revision for local documents using simplified format "0-N"
  /// Local documents don't use hash-based revisions like regular documents
  /// Returns "0-0" for new deleted documents, otherwise "0-N" where N increments
  CouchDocumentBase _updateLocalDocRev(CouchDocumentBase doc, String? prevRev) {
    // CouchDB returns 0-0 for new documents created with deleted: true
    if (prevRev == null && doc.deleted == true) {
      return doc.copyWith(rev: '0-0');
    }

    int nextVersion = 1;
    if (prevRev != null && prevRev.startsWith('0-')) {
      nextVersion = int.parse(prevRev.substring(2)) + 1;
    }
    return doc.copyWith(rev: '0-$nextVersion');
  }

  /// Handles POST for _local documents with simplified revision logic
  Future<CouchDocumentBase> _postLocalDocument(CouchDocumentBase doc) async {
    if (doc.id == null) {
      throw CouchDbException.badRequest(
        'Local document must have an _id starting with _local/',
      );
    }

    // CouchDB rejects creating new documents with deleted: true
    final String? existingRev = await _getRevFromDoc(doc.id!);
    if (existingRev == null && doc.deleted == true) {
      throw CouchDbException.conflictPost(doc.id!);
    }

    // CouchDB POST on local documents: if exists, returns same rev (no increment)
    // If new, starts at 0-1
    if (existingRev != null) {
      doc = doc.copyWith(rev: existingRev);
    } else {
      doc = _updateLocalDocRev(doc, null);
    }
    assert(doc.rev != null);

    await db.transaction(() async {
      int seq = await db.incrementAndGetUpdateSeq(dbid);

      final LocalDocumentWithBlob? existing = await db.getDocument(
        dbid,
        doc.id!,
        true,
        ignoreDeleted: true,
      );

      LocalDocumentsCompanion entry = LocalDocumentsCompanion(
        id: Value.absentIfNull(existing?.document.id),
        docid: Value(doc.id!),
        fkdatabase: Value(dbid),
        rev: Value(doc.rev!),
        version: Value(doc.getVersionFromRev()),
        deleted: Value(doc.deleted == true),
        seq: Value(seq),
      );

      int newid = await db
          .into(db.localDocuments)
          .insertOnConflictUpdate(entry);

      await db
          .into(db.documentBlobs)
          .insertOnConflictUpdate(
            DocumentBlobsCompanion(
              documentId: Value(existing?.document.id ?? newid),
              data: Value(doc.toJson()),
            ),
          );
    });

    return doc;
  }

  /// Handles PUT for _local documents with simplified revision logic
  Future<CouchDocumentBase> _putLocalDocument(CouchDocumentBase doc) async {
    final LocalDocumentWithBlob? existingDoc = await db.getDocument(
      dbid,
      doc.id!,
      true,
      ignoreDeleted: true,
    );

    // CouchDB accepts PUT with deleted: true for local documents
    // It creates a deleted document with revision 0-0
    int? existingId = existingDoc?.document.id;
    // CouchDB allows PUT on local documents without strict revision checking
    // Use the provided revision or generate new one
    doc = _updateLocalDocRev(doc, doc.rev ?? existingDoc?.document.rev);

    assert(doc.rev != null);

    await db.transaction(() async {
      int seq = await db.incrementAndGetUpdateSeq(dbid);

      int newid = await db
          .into(db.localDocuments)
          .insertOnConflictUpdate(
            LocalDocumentsCompanion(
              id: Value.absentIfNull(existingId),
              docid: Value(doc.id!),
              fkdatabase: Value(dbid),
              rev: Value(doc.rev!),
              version: Value(doc.getVersionFromRev()),
              deleted: Value(doc.deleted == true),
              seq: Value(seq),
            ),
          );

      await db
          .into(db.documentBlobs)
          .insertOnConflictUpdate(
            DocumentBlobsCompanion(
              documentId: Value(existingId ?? newid),
              data: Value(jsonEncode(doc.toMap())),
            ),
          );
    });

    return doc;
  }

  @override
  Future<Map<String, dynamic>> putRaw(Map<String, dynamic> doc) async {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    return await m.protect(() async {
      return await _internalPutRaw(doc);
    });
  }

  /// Core write path for PUT, shared by the public [putRaw] and internal callers.
  ///
  /// Strips transport-only fields, rejects reserved `_`-prefixed user fields,
  /// routes `_local/` documents to [_putLocalDocument], and refuses `_deleted`
  /// on non-local documents (use [remove] for that).
  ///
  /// Computes a new CouchDB-style revision hash and writes both the document
  /// metadata row and the blob row inside a single transaction.  `_attachments`
  /// is removed from the blob — attachment data lives in its own table and is
  /// injected back on read.
  Future<Map<String, dynamic>> _internalPutRaw(Map<String, dynamic> doc) async {
    final docId = doc['_id'] as String?;

    if (docId == null) {
      throw CouchDbException.badRequest(jsonEncode(doc));
    }

    // Remove transport-only fields before processing
    doc.remove('_revisions');
    doc.remove('_revs_info');
    doc.remove('_conflicts');
    doc.remove('_deleted_conflicts');
    doc.remove('_local_seq');

    // Reject user-defined fields starting with '_' (reserved for CouchDB)
    const allowedUnderscoreFields = {'_id', '_rev', '_deleted', '_attachments'};
    for (final key in doc.keys) {
      if (key.startsWith('_') && !allowedUnderscoreFields.contains(key)) {
        throw CouchDbException.docValidation(key);
      }
    }

    // Local documents use simplified revision handling
    if (docId.startsWith("_local/")) {
      final cdoc = CouchDocumentBase.fromMap(doc);
      final result = await _putLocalDocument(cdoc);
      return result.toMap();
    }

    final isDeleted = (doc['_deleted'] as bool?) ?? false;
    if (isDeleted) {
      throw CouchDbException.badRequest(
        "its not allowed to delete a document like this...",
      );
    }

    if (docId.startsWith("_design")) {
      await _checkViewsAfterDesignDocumentChange(DesignDocument.fromMap(doc));
    }

    final LocalDocumentWithBlob? existingDoc = await db.getDocument(
      dbid,
      docId,
      true,
      ignoreDeleted: true,
    );

    int? existingId = existingDoc?.document.id;
    String? newRev;
    final String? inputRev = doc['_rev'] as String?;

    if (existingDoc != null) {
      if (existingDoc.document.deleted == true) {
        // Creating new document but with continued version
        if (inputRev != null) {
          // in diesem Fall darf keine rev angefordert werden!
          throw CouchDbException.conflictPut(docId);
        }
        newRev = _calculateNewRev(existingDoc.document.rev, doc);
      } else {
        // Updating existing document
        if (inputRev != existingDoc.document.rev) {
          throw CouchDbException.conflictPut(docId);
        }
        newRev = _calculateNewRev(inputRev, doc);
      }
    } else {
      // Brand new document
      newRev = _calculateNewRev(null, doc);
    }

    // Update the document with new revision
    doc['_rev'] = newRev;

    // Extract inline attachment data before the transaction
    final attachmentsMap = doc['_attachments'] as Map<String, dynamic>?;
    final existingAttachments = existingId != null
        ? await db.getAttachments(existingId)
        : <LocalAttachment>[];
    final deferredFileDeletes = <int>[];

    await db.transaction(() async {
      // Remove _attachments for storage
      Map<String, dynamic> filteredDoc = Map.from(doc);
      filteredDoc.remove('_attachments');

      int seq = await db.incrementAndGetUpdateSeq(dbid);
      final int version = int.parse(newRev!.split('-')[0]);

      int newid = await db
          .into(db.localDocuments)
          .insertOnConflictUpdate(
            LocalDocumentsCompanion(
              id: Value.absentIfNull(existingId),
              docid: Value(docId),
              fkdatabase: Value(dbid),
              rev: Value(newRev),
              version: Value(version),
              deleted: Value(isDeleted),
              seq: Value(seq),
            ),
          );

      await db
          .into(db.documentBlobs)
          .insertOnConflictUpdate(
            DocumentBlobsCompanion(
              documentId: Value(existingId ?? newid),
              data: Value(jsonEncode(filteredDoc)),
            ),
          );

      final actualDocId = existingId ?? newid;

      // Store inline attachments (entries that carry a 'data' field).
      // Stub entries (no 'data') are left as-is; their rows already exist.
      if (attachmentsMap != null) {
        int ordering = 0;
        for (final entry in attachmentsMap.entries) {
          final attName = entry.key;
          final attMeta = entry.value as Map<String, dynamic>;
          final base64Data = attMeta['data'] as String?;
          if (base64Data == null) continue; // stub – keep existing row

          final data = base64Decode(base64Data);
          ordering++;
          final existingAttId = existingAttachments
              .firstWhereOrNull((e) => e.name == attName)
              ?.id;
          await _saveAttachmentWithFileIO(
            LocalAttachmentsCompanion(
              id: existingAttId != null ? Value(existingAttId) : Value.absent(),
              fkdocument: Value(actualDocId),
              name: Value(attName),
              revpos: Value(version),
              contentType: Value(
                attMeta['content_type'] as String? ??
                    'application/octet-stream',
              ),
              ordering: Value(ordering),
            ),
            Uint8List.fromList(data),
            deferredFileDeletes: deferredFileDeletes,
          );
        }
      }

      // Delete attachment rows whose names are absent from _attachments
      // (the caller omitted them → they are to be removed).
      final keptNames = attachmentsMap?.keys.toSet() ?? <String>{};
      for (final att in existingAttachments) {
        if (!keptNames.contains(att.name)) {
          await db.deleteAttachment(att.id);
          await _deleteAttachmentFile(att.id);
        }
      }
    });

    // Clean up old attachment files after transaction committed successfully.
    for (final oldId in deferredFileDeletes) {
      await _deleteAttachmentFile(oldId);
    }

    return doc;
  }

  Future<CouchDocumentBase> _internalPut(CouchDocumentBase doc) async {
    // Use putRaw internally
    final docJson = doc.toMap();
    final resultMap = await _internalPutRaw(docJson);
    return CouchDocumentBase.fromMap(resultMap);
  }

  @override
  Future<Map<String, dynamic>> postRaw(Map<String, dynamic> doc) async {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    return await m.protect(() async {
      return await _internalPostRaw(doc);
    });
  }

  /// Core write path for POST.
  ///
  /// - `_local/` documents are forwarded to [_postLocalDocument] which uses
  ///   idempotent upsert semantics (returns the existing rev on collision).
  /// - Documents without an `_id` get a freshly generated UUID that is
  ///   guaranteed not to collide with any existing document.
  /// - Documents with an explicit `_id` behave like POST-with-ID: they must
  ///   not already exist (409 if they do).
  /// - All other writes are delegated to [_internalPutRaw].
  Future<Map<String, dynamic>> _internalPostRaw(
    Map<String, dynamic> doc,
  ) async {
    String? docId = doc['_id'] as String?;

    // Local documents have special POST handling
    if (docId?.startsWith("_local/") == true) {
      // Remove transport-only fields before processing local document
      doc.remove('_revisions');
      doc.remove('_revs_info');
      doc.remove('_conflicts');
      doc.remove('_deleted_conflicts');
      doc.remove('_local_seq');
      return (await _postLocalDocument(CouchDocumentBase.fromMap(doc))).toMap();
    }

    // Generate unique ID if missing
    if (docId == null) {
      String newId = uuid.v4();
      while (await _internalGet(newId) != null) {
        newId = uuid.v4();
      }
      doc['_id'] = newId;
    } else {
      // POST with an ID requires that the document doesn't exist yet
      final String? existingRev = await _getRevFromDoc(docId);
      if (existingRev != null) {
        throw CouchDbException.conflictPost(docId);
      }
    }

    // Delegate to PUT for the actual storage (handles transport fields, _design docs, etc.)
    return await _internalPutRaw(doc);
  }

  /// Handles DELETE for _local documents with simplified revision logic
  Future<String> _removeLocalDocument(String docid, String rev) async {
    LocalDocumentWithBlob? existingDoc = await db.getDocument(
      dbid,
      docid,
      true,
    );
    if (existingDoc == null) {
      throw CouchDbException.notFound(docid);
    }
    // CouchDB DELETE on local documents: returns 0-0 (resets counter)
    CouchDocumentBase newRev = CouchDocumentBase(
      id: docid,
      rev: '0-0',
      deleted: true,
    );

    await db.transaction(() async {
      int seq = await db.incrementAndGetUpdateSeq(dbid);

      await db
          .into(db.localDocuments)
          .insertOnConflictUpdate(
            LocalDocumentsCompanion(
              id: Value(existingDoc.document.id),
              docid: Value(docid),
              fkdatabase: Value(dbid),
              rev: Value(newRev.rev!),
              version: Value(newRev.getVersionFromRev()),
              deleted: const Value(true),
              seq: Value(seq),
            ),
          );

      // No blob write needed: the cleanup_document_blob_on_tombstone trigger
      // deletes the blob when deleted changes to true.
    });

    return newRev.rev!;
  }

  @override
  Future<String> remove(String docid, String rev) async {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    return await m.protect(() async {
      return _internalRemove(docid, rev);
    });
  }

  /// Core delete path — creates a tombstone revision for the document.
  ///
  /// Routes `_local/` and `_design/` documents to their respective helpers.
  /// For regular documents, verifies the provided [rev] matches the stored
  /// head revision (409 otherwise), then writes a tombstone row (`deleted=true`)
  /// with an incremented revision hash.  The blob is removed automatically by
  /// the `cleanup_document_blob_on_tombstone` SQLite trigger, mirroring
  /// CouchDB's behaviour of discarding body data for deleted documents.
  Future<String> _internalRemove(String docid, String rev) async {
    // Local documents use simplified revision handling
    if (docid.startsWith("_local/")) {
      return _removeLocalDocument(docid, rev);
    }

    if (docid.startsWith("_design") == true) {
      // Get the design document before removing it
      final doc = await _internalGet(docid);
      if (doc != null && doc is DesignDocument) {
        await _checkViewsAfterDesignDocumentChange(doc);
      }
    }

    LocalDocumentWithBlob? existingDoc = await db.getDocument(
      dbid,
      docid,
      true,
    );
    if (existingDoc == null) {
      throw CouchDbException.notFound(docid);
    }
    final existingJson = jsonDecode(existingDoc.data!);
    if (existingJson['_rev'] != rev) {
      throw CouchDbException.conflictRemove(docid, rev);
    }

    CouchDocumentBase newRev = CouchDocumentBase(id: docid, deleted: true);
    newRev = _updateRevInDoc(newRev, rev);

    // Collect attachment IDs before tombstone so we can delete their files
    // after the trigger fires (cleanup_attachments_on_tombstone deletes DB rows
    // but cannot delete files).
    final tombstoneAttachmentIds = (await db.getAttachments(
      existingDoc.document.id,
    )).map((a) => a.id).toList();

    await db.transaction(() async {
      int seq = await db.incrementAndGetUpdateSeq(dbid);

      LocalDocumentsCompanion dbrev = LocalDocumentsCompanion(
        id: Value(existingDoc.document.id),
        docid: Value(docid),
        fkdatabase: Value(dbid),
        rev: Value(newRev.rev!),
        version: Value(newRev.getVersionFromRev()),
        deleted: Value(newRev.deleted == true ? true : false),
        seq: Value(seq),
      );
      await db.into(db.localDocuments).insertOnConflictUpdate(dbrev);

      // No blob write needed: the cleanup_document_blob_on_tombstone trigger
      // deletes the blob when deleted changes to true. CouchDB does not keep
      // document bodies for tombstoned documents.

      // If the deleted winner had conflict leaves, promote the best surviving
      // leaf (CouchDB rule), so deleting a conflicted doc converges like CouchDB.
      await _promoteAfterTombstone(existingDoc.document.id, docid);
    });

    for (final id in tombstoneAttachmentIds) {
      await _deleteAttachmentFile(id);
    }

    return newRev.rev!;
  }

  @override
  Future<ViewResult?> query(
    String viewPathShort, {

    bool includeDocs = false,
    bool attachments = false,
    bool attEncodingInfo = false,
    bool conflicts = false,

    String? startkey,
    String? startkeyDocid,
    String? endkey,
    String? endkeyDocid,
    String? key,
    List<String>? keys,

    bool inclusiveEnd = true,

    bool group = false,
    int? groupLevel,

    bool reduce = true,

    int? limit,
    int? skip,
    bool descending = false,
    bool sorted = true,

    bool stable = false,
    UpdateMode updateMode = UpdateMode.modeTrue,
    bool updateSeq = false,
  }) async {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    return await m.protect(() async {
      return _internalQuery(
        viewPathShort,
        includeDocs: includeDocs,
        attachments: attachments,
        attEncodingInfo: attEncodingInfo,
        conflicts: conflicts,
        startkey: startkey,
        startkeyDocid: startkeyDocid,
        endkey: endkey,
        endkeyDocid: endkeyDocid,
        key: key,
        keys: keys,
        inclusiveEnd: inclusiveEnd,
        group: group,
        groupLevel: groupLevel,
        reduce: reduce,
        limit: limit,
        skip: skip,
        descending: descending,
        sorted: sorted,
        stable: stable,
        updateMode: updateMode,
        updateSeq: updateSeq,
      );
    });
  }

  Future<ViewResult?> _internalQuery(
    String viewPathShort, {

    bool includeDocs = false,
    bool attachments = false,
    bool attEncodingInfo = false,
    bool conflicts = false,

    String? startkey,
    String? startkeyDocid,
    String? endkey,
    String? endkeyDocid,
    String? key,
    List<String>? keys,

    bool inclusiveEnd = true,

    bool group = false,
    int? groupLevel,

    bool reduce = true,

    int? limit,
    int? skip,
    bool descending = false,
    bool sorted = true,

    bool stable = false,
    UpdateMode updateMode = UpdateMode.modeTrue,
    bool updateSeq = false,
  }) async {
    ViewCtrl? ctrl = await viewMgr.getView(viewPathShort);
    if (ctrl == null) return null;
    return ctrl.query(
      includeDocs: includeDocs,
      attachments: attachments,
      attEncodingInfo: attEncodingInfo,
      conflicts: conflicts,
      startkey: startkey,
      startkeyDocid: startkeyDocid,
      endkey: endkey,
      endkeyDocid: endkeyDocid,
      key: key,
      keys: keys,
      inclusiveEnd: inclusiveEnd,
      group: group,
      groupLevel: groupLevel,
      reduce: reduce,
      limit: limit,
      skip: skip,
      descending: descending,
      sorted: sorted,
      stable: stable,
      updateMode: updateMode,
      updateSeq: updateSeq,
    );
  }

  @override
  Future<ViewResult> allDocs({
    bool includeDocs = false,
    bool attachments = false,
    String? startkey,
    String? endkey,
    bool inclusiveEnd = true,
    int? limit,
    int? skip,
    bool descending = false,
    String? key,
    List<String>? keys,
  }) async {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    return await m.protect(() async {
      return _internalAllDocs(
        includeDocs: includeDocs,
        attachments: attachments,
        startkey: startkey,
        endkey: endkey,
        inclusiveEnd: inclusiveEnd,
        limit: limit,
        skip: skip,
        descending: descending,
        key: key,
        keys: keys,
      );
    });
  }

  Future<ViewResult> _internalAllDocs({
    bool includeDocs = false,
    bool attachments = false,
    String? startkey,
    String? endkey,
    bool inclusiveEnd = true,
    int? limit,
    int? skip,
    bool descending = false,
    String? key,
    List<String>? keys,
  }) async {
    return _internalQuery(
      '_all_docs',
      includeDocs: includeDocs,
      attachments: attachments,
      startkey: startkey,
      endkey: endkey,
      inclusiveEnd: inclusiveEnd,
      limit: limit,
      skip: skip,
      descending: descending,
      key: key,
      keys: keys,
    ).then((value) => value!);
  }

  /// Deletes a single attachment and bumps the document revision.
  ///
  /// Removes the attachment row from the DB, then calls [_internalPut] to
  /// produce a new document revision whose `_attachments` map no longer
  /// includes the deleted attachment.  Both operations run in a single
  /// transaction so the document and its attachments are always consistent.
  @override
  Future<String> deleteAttachment(
    String docId,
    String rev,
    String attachmentName,
  ) async {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    return await m.protect(() async {
      // only work on latest revision of document
      LocalDocumentWithBlob? ldoc = await db.getDocument(dbid, docId, true);
      if (ldoc == null) throw CouchDbException.attachmentNotFound();
      if (ldoc.document.rev != rev) {
        throw CouchDbException.conflictRemoveAttachment(docId, attachmentName);
      }
      LocalAttachment? existingAttachment = await db.getAttachment(
        ldoc.document.id,
        attachmentName,
      );
      if (existingAttachment == null) {
        throw CouchDbException.attachmentNotFound();
      }

      final newRev = await db.transaction(() async {
        await db.deleteAttachment(existingAttachment.id);
        // jetzt muss noch eine neue Revision vom Document erzeugt werden
        CouchDocumentBase oldDoc = CouchDocumentBase.fromJson(ldoc.data!);
        oldDoc = oldDoc.copyWith(
          attachments: await _recreateAttachmentMapFromDatabase(
            ldoc.document.id,
            false,
          ),
        );
        final updated = await _internalPut(oldDoc);
        return updated.rev!;
      });
      await _deleteAttachmentFile(existingAttachment.id);
      return newRev;
    });
  }

  @override
  Future<Uint8List?> getAttachment(
    String docId,
    String attachmentName, {
    String? rev,
  }) async {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    return await m.protect(() async {
      // Fetch the winner row (even if tombstoned) to get the document row id;
      // conflict leaves hang off it.
      final winnerRow = await db.getDocument(
        dbid,
        docId,
        false,
        ignoreDeleted: true,
      );
      if (winnerRow == null) return null;

      // No rev, or the winner's rev → the winner's attachment.
      if (rev == null || rev == winnerRow.document.rev) {
        final att = await db.getAttachment(winnerRow.document.id, attachmentName);
        return att == null
            ? null
            : await attachmentStorage.readAttachment(att.id);
      }

      // A specific non-winner rev → a stored conflict leaf's own attachment
      // (Decision A2 / Stage 2). Read via the leaf's fkconflict rows.
      final leaf = (await db.getConflictRevisions(
        winnerRow.document.id,
      )).firstWhereOrNull((c) => c.rev == rev);
      if (leaf != null) {
        final att = await db.getConflictAttachment(leaf.id, attachmentName);
        return att == null
            ? null
            : await attachmentStorage.readAttachment(att.id);
      }

      // Unknown rev for this document → null, matching Http (CouchDB 404).
      return null;
    });
  }

  @override
  Future<String?> getAttachmentAsReadonlyFile(
    String docId,
    String attachmentName,
  ) {
    return m.protect(() async {
      final docData = await db.getDocument(
        dbid,
        docId,
        false,
        ignoreDeleted: false,
      );
      if (docData == null) return null;
      final att = await db.getAttachment(docData.document.id, attachmentName);
      if (att == null) return null;
      return await attachmentStorage.getAttachmentPath(att.id);
    });
  }

  /// Saves a binary attachment and bumps the document revision.
  ///
  /// Writes the attachment blob to the dedicated attachment table, then calls
  /// [_internalPut] to produce a new document revision whose `_attachments`
  /// map reflects the updated set.  Both operations run in a single transaction.
  ///
  /// `revpos` is set to `version(rev) + 1` so that the `atts_since`
  /// optimisation can later determine which revision introduced each attachment
  /// and skip re-sending unchanged blobs during replication.
  @override
  Future<String> saveAttachment(
    String docId,
    String rev,
    String attachmentName,
    Uint8List data, {
    String contentType = 'application/octet-stream',
  }) async {
    _log.info(
      'Saving attachment for document $docId, attachment name: $attachmentName',
    );
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    if (attachmentName.startsWith('_')) {
      throw CouchDbException.badRequestAttachmentName(attachmentName);
    }

    return await m.protect(() async {
      int nextRevPos = _getNextVersionFromRev(rev);
      LocalDocumentWithBlob? dbDoc = await db.getDocument(dbid, docId, true);

      if (dbDoc == null) throw CouchDbException.attachmentNotFound();
      // ensure we are working on the latest revision
      if (dbDoc.document.rev != rev) {
        throw CouchDbException.conflictRemoveAttachment(docId, attachmentName);
      }

      // get existing attachments for ordering and checking
      // if this is new or an update
      List<LocalAttachment> existingAttachments = await db.getAttachments(
        dbDoc.document.id,
      );

      int? existingId = existingAttachments
          .firstWhereOrNull((e) => e.name == attachmentName)
          ?.id;

      // new Attachments are added as last in the list
      String? newRev;
      final deferredFileDeletes = <int>[];
      await db.transaction(() async {
        int newOrdering = 0;
        for (final a in existingAttachments) {
          if (a.ordering > newOrdering) newOrdering = a.ordering;
        }

        LocalAttachmentsCompanion att = LocalAttachmentsCompanion(
          id: existingId != null ? Value(existingId) : Value.absent(),
          fkdocument: Value(dbDoc.document.id),
          name: Value(attachmentName),
          revpos: Value(nextRevPos),
          contentType: Value(contentType),
          ordering: Value(newOrdering + 1),
        );

        await _saveAttachmentWithFileIO(
          att,
          data,
          deferredFileDeletes: deferredFileDeletes,
        );

        // jetzt muss noch eine neue Revision vom Document erzeugt werden
        CouchDocumentBase oldDoc = CouchDocumentBase.fromJson(dbDoc.data!);
        oldDoc = oldDoc.copyWith(
          attachments: await _recreateAttachmentMapFromDatabase(
            dbDoc.document.id,
            false,
          ),
        );
        CouchDocumentBase newRevisionDoc = await _internalPut(oldDoc);
        newRev = newRevisionDoc.rev!;
      });

      // Clean up old attachment files after transaction committed successfully.
      for (final oldId in deferredFileDeletes) {
        await _deleteAttachmentFile(oldId);
      }

      return newRev!;
    });
  }

  @override
  Future<bool?> isCompactionRunning() {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    return Future.value(false);
  }

  @override
  Future<void> startCompaction() {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    return Future.value();
  }

  /// Computes which of the requested revisions are missing locally.
  ///
  /// For each document, also returns `possible_ancestors` — the locally known
  /// revision with the highest generation that is still lower than the missing
  /// Ids of documents currently in conflict (≥1 live losing leaf) — an indexed,
  /// ids-only lookup against the conflict side-table (no body loads, no full
  /// scan). Package-internal ([LocalConflictSource]); used by opt-in resolution
  /// to do a "complete run" when replication is caught up, without downloading
  /// or scanning the whole database (PLAN.md Phase 2).
  @override
  Future<List<String>> conflictedDocIds() async {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }
    return db.conflictedDocIds(dbid);
  }

  /// Records [rev] as a known but **bodyless** (body == null), non-deleted
  /// conflict leaf of [docId] — see [DartCouchDb.recordBodylessLeaf].
  ///
  /// After this, [revsDiff] reports [rev] as known (it unions the conflict
  /// side-table), so the puller stops re-requesting a permanently-gone leaf on
  /// every change, and `get(conflicts: true)` lists it (Http parity). The leaf
  /// carries no body, so it is never promoted to winner ([_promoteAfterTombstone]
  /// skips it) and `get(rev:)` / `bulkGetMultipart` serve it as `not_found`
  /// (mirroring the source). Idempotent: an already-known rev (the winner, a
  /// known ancestor in the linear history, or an existing conflict leaf) or an
  /// absent document is ignored. No `update_seq` bump — opt-in resolution finds
  /// the doc via [conflictedDocIds], and bumping would re-emit the doc need-
  /// lessly.
  @override
  Future<void> recordBodylessLeaf(String docId, String rev) async {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }
    final int version = int.tryParse(rev.split('-').first) ?? 0;
    if (version == 0) return; // malformed rev — ignore
    await m.protect(() async {
      await db.transaction(() async {
        final winnerRow = await db.getDocument(
          dbid,
          docId,
          false,
          ignoreDeleted: true,
        );
        if (winnerRow == null) return; // doc unknown locally — nothing to anchor
        if (winnerRow.document.rev == rev) return; // it's the winner
        // An ancestor of the winner (anywhere in its `_revisions` chain) is
        // already represented in the tree, not a new leaf — don't record it
        // (mirrors the ancestry check in [_applyIncomingLeaf]). In practice the
        // puller only calls this for source-advertised LEAVES that revsDiff
        // reported missing, so this is a defensive guard.
        final winnerChain = _expandRevisions(
          (await _getRevs(winnerRow.document.id, winnerRow.document.version))
              ?.toMap(),
          winnerRow.document.rev,
        ).toSet();
        if (winnerChain.contains(rev)) return;
        final existing = await db.getConflictRevisions(winnerRow.document.id);
        if (existing.any((c) => c.rev == rev)) return; // already a known leaf
        await db.putConflictRevision(
          docRowId: winnerRow.document.id,
          rev: rev,
          version: version,
          deleted: false,
          body: null,
        );
      });
    });
  }

  /// revision's generation.  The replication source uses these ancestors to
  /// populate `atts_since` when fetching the document, enabling stub
  /// (metadata-only) transfer for attachments that the target already holds.
  @override
  Future<Map<String, RevsDiffEntry>> revsDiff(
    Map<String, List<String>> revs,
  ) async {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    return await m.protect(() async {
      final Map<String, RevsDiffEntry> out = {};

      for (final entry in revs.entries) {
        final String docid = entry.key;
        final List<String> requestedRevs = entry.value;

        // get revision history for the document (all known revisions)
        List<RevisionHistory>? history = await db.getRevisionHistory(
          dbid: dbid,
          docid: docid,
          sortDesc: false,
        );

        if (history == null || history.isEmpty) {
          // Document unknown -> all requested revs are missing
          out[docid] = RevsDiffEntry(missing: requestedRevs);
          continue;
        }

        final Set<String> knownRevs = history.map((h) => h.rev).toSet();
        // Also treat stored non-winning conflict leaves (Decision A2) as known,
        // so revsDiff is deterministic regardless of the order in which leaves
        // arrived — otherwise a conflict leaf would be re-requested every cycle
        // (the re-pull churn). Keeps Phase 0 test P3 green for real.
        final int docRowId = history.first.fkdocument;
        for (final c in await db.getConflictRevisions(docRowId)) {
          knownRevs.add(c.rev);
        }
        final List<String> missing = [];
        for (final r in requestedRevs) {
          if (!knownRevs.contains(r)) missing.add(r);
        }

        if (missing.isNotEmpty) {
          // compute possible ancestors: for each missing revision, find the known
          // revision with the highest generation less than the missing revision's generation
          final List<String> possibleAncestors = [];
          for (final missingRev in missing) {
            try {
              final int missingGen = int.parse(missingRev.split('-').first);
              // find known revisions with generation < missingGen
              final candidates = history
                  .where((h) => int.parse(h.rev.split('-').first) < missingGen)
                  .toList();
              if (candidates.isNotEmpty) {
                candidates.sort(
                  (a, b) => int.parse(
                    b.rev.split('-').first,
                  ).compareTo(int.parse(a.rev.split('-').first)),
                );
                final String best = candidates.first.rev;
                if (!possibleAncestors.contains(best)) {
                  possibleAncestors.add(best);
                }
              }
            } catch (_) {
              // ignore parse errors and continue
            }
          }

          out[docid] = RevsDiffEntry(
            missing: missing,
            possibleAncestors: possibleAncestors.isEmpty
                ? null
                : possibleAncestors,
          );
        }
      }

      return out;
    });
  }

  @override
  Future<bool> up() {
    return Future.value(!_disposed);
  }

  @override
  Future<String?> createIndex({
    required IndexDefinition index,
    String? ddoc,
    String? name,
    String type = 'json',
    bool? partitioned,
  }) async {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    return await m.protect(() async {
      // Generate index name if not provided
      final indexName = name ?? 'idx_${uuid.v4().replaceAll('-', '')}';

      // Generate design doc name if not provided
      final designDocName = ddoc ?? 'idx-${uuid.v4().replaceAll('-', '')}';

      // Ensure design doc has _design/ prefix
      final fullDesignDocId = designDocName.startsWith('_design/')
          ? designDocName
          : '_design/$designDocName';

      // Check if design document already exists
      final existingDoc = await _internalGet(fullDesignDocId);

      Map<String, IndexView> views;
      String? existingRev;

      if (existingDoc != null) {
        // Try to parse as IndexDocument
        try {
          final indexDoc = IndexDocument.fromMap(existingDoc.toMap());
          views = Map<String, IndexView>.from(indexDoc.views);
          existingRev = indexDoc.rev;

          // Check if index with same name already exists
          if (views.containsKey(indexName)) {
            return indexName;
          }
        } catch (e) {
          // Not a valid index document, create new views map
          views = {};
        }
      } else {
        views = {};
      }

      // Add the new index
      views[indexName] = _createIndexView(index);

      // Create the document map with IndexDocument-compatible structure
      final viewsMap = views.map((k, v) => MapEntry(k, jsonDecode(v.toJson())));
      final docMap = {
        '_id': fullDesignDocId,
        '_rev': ?existingRev,
        'language': 'query',
        'views': viewsMap,
      };

      // Store using database functions
      // Use CouchDocumentBase to avoid the DesignDocument format issue
      final doc = CouchDocumentBase.fromMap(docMap);
      await _internalPut(doc);

      return indexName;
    });
  }

  IndexView _createIndexView(IndexDefinition index) {
    // Convert IndexDefinition fields to map format
    final fieldsMap = <String, SortOrder>{};
    for (final fieldEntry in index.fields) {
      fieldEntry.forEach((fieldName, sortOrder) {
        fieldsMap[fieldName] = sortOrder;
      });
    }

    return IndexView(
      map: IndexMap(fields: fieldsMap),
      reduce: '_count',
      options: IndexOptions(def: index),
    );
  }

  @override
  Future<bool> deleteIndex({
    required String designDoc,
    required String name,
    String type = 'json',
  }) async {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    return await m.protect(() async {
      // Ensure design doc has _design/ prefix
      final fullDesignDocId = designDoc.startsWith('_design/')
          ? designDoc
          : '_design/$designDoc';

      // Get the design document
      final doc = await _internalGet(fullDesignDocId);

      if (doc == null) {
        throw CouchDbException(
          CouchDbStatusCodes.notFound,
          'Index not found: $name',
        );
      }

      // Parse as IndexDocument
      IndexDocument indexDoc;
      try {
        indexDoc = IndexDocument.fromMap(doc.toMap());
      } catch (e) {
        throw CouchDbException(
          CouchDbStatusCodes.notFound,
          'Index not found: $name',
        );
      }

      // Check if the index exists in this design document
      if (!indexDoc.views.containsKey(name)) {
        throw CouchDbException(
          CouchDbStatusCodes.notFound,
          'Index not found: $name',
        );
      }

      // If this is the only index in the design document, delete the entire document
      if (indexDoc.views.length == 1) {
        await _internalRemove(fullDesignDocId, indexDoc.rev!);
        return true;
      }

      // Otherwise, remove just this index from the design document
      final updatedViews = Map<String, IndexView>.from(indexDoc.views);
      updatedViews.remove(name);

      // Create the document map
      final docMap = {
        '_id': fullDesignDocId,
        '_rev': indexDoc.rev,
        'language': 'query',
        'views': updatedViews.map(
          (k, v) => MapEntry(k, jsonDecode(v.toJson())),
        ),
      };

      // Store using database functions
      final updatedDoc = CouchDocumentBase.fromMap(docMap);
      await _internalPut(updatedDoc);

      return true;
    });
  }

  @override
  Future<IndexResultList> getIndexes() async {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    return await m.protect(() async {
      // Query all design documents
      final allDocsResult = await _internalAllDocs(
        startkey: '_design/',
        endkey: '_design0',
        includeDocs: true,
      );

      final indexResults = <IndexResult>[];

      for (final row in allDocsResult.rows) {
        if (row.doc == null) continue;

        // Try to parse as IndexDocument
        try {
          final indexDoc = IndexDocument.fromMap(row.doc!.toMap());

          if (indexDoc.language != 'query') continue;

          // Extract all indexes from this design document
          for (final entry in indexDoc.views.entries) {
            final indexName = entry.key;
            final indexView = entry.value;

            if (indexView.options?.def != null) {
              indexResults.add(
                IndexResult(
                  ddoc: indexDoc.id,
                  name: indexName,
                  type: 'json',
                  partitioned: null,
                  def: indexView.options!.def,
                ),
              );
            }
          }
        } catch (e) {
          // Not a valid index document, skip
          continue;
        }
      }

      // Add the special all_docs index (always present)
      indexResults.insert(
        0,
        IndexResult(
          ddoc: null,
          name: '_all_docs',
          type: 'special',
          partitioned: null,
          def: IndexDefinition(fields: []),
        ),
      );

      return IndexResultList(
        totalRows: indexResults.length,
        indexes: indexResults,
      );
    });
  }

  /// Fetches multiple documents in one call, mirroring CouchDB's `_bulk_get`.
  ///
  /// Each entry in the request may carry an `atts_since` list of revision
  /// strings the caller already holds.  When present and [attachments] is
  /// `true`, [_internalGetRaw] will return unchanged attachments as stubs
  /// (no `data` field) instead of re-sending the full blob — this is the
  /// core of the attachment stub optimisation during pull replication.
  ///
  /// [onBytesReceived] is accepted for interface compatibility but is not
  /// invoked — SQLite reads are synchronous and fast enough that streaming
  /// byte tracking is not meaningful.
  @override
  Future<Map<String, dynamic>> bulkGetRaw(
    BulkGetRequest request, {
    bool revs = false,
    bool attachments = false,
    void Function(int bytes)? onBytesReceived,
    // onBytesReceived is not used for local reads — SQLite access is
    // synchronous and fast, so streaming byte tracking is not meaningful.
  }) async {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    return await m.protect(() async {
      final results = <Map<String, dynamic>>[];

      for (final docRequest in request.docs) {
        final docId = docRequest.id;
        final rev = docRequest.rev;
        // When atts_since is provided and we are fetching attachment data,
        // compute the max revision version the caller already holds so we can
        // return stubs for unchanged attachments instead of re-sending blobs.
        final maxAttsSinceVersion =
            attachments && (docRequest.attsSince?.isNotEmpty == true)
            ? _parseMaxRevVersion(docRequest.attsSince!)
            : null;

        try {
          // Fetch the document with the specified revision (if provided)
          // Pass ignoreDeleted: true to match CouchDB behavior where deleted
          // documents are returned with _deleted: true
          final docMap = await _internalGetRaw(
            docId,
            rev: rev,
            revs: revs,
            revsInfo: false,
            attachments: attachments,
            ignoreDeleted: true,
            maxAttsSinceVersion: maxAttsSinceVersion,
          );

          if (docMap != null) {
            // Document found - return in "ok" format
            results.add({
              'id': docId,
              'docs': [
                {'ok': docMap},
              ],
            });
          } else {
            // Document not found - return error
            results.add({
              'id': docId,
              'docs': [
                {
                  'error': {
                    'id': docId,
                    'rev': rev ?? 'undefined',
                    'error': 'not_found',
                    'reason': rev != null ? 'missing' : 'deleted',
                  },
                },
              ],
            });
          }
        } catch (e) {
          // Error fetching document - return error
          results.add({
            'id': docId,
            'docs': [
              {
                'error': {
                  'id': docId,
                  'rev': rev ?? 'undefined',
                  'error': 'unknown_error',
                  'reason': e.toString(),
                },
              },
            ],
          });
        }
      }

      return {'results': results};
    });
  }

  // ---------------------------------------------------------------------------
  // Multipart streaming API
  // ---------------------------------------------------------------------------

  /// Builds a [BulkGetMultipartResult] for a stored non-winning conflict leaf
  /// (Stage 3 forwarding — lets Local push conflict branches as a source).
  ///
  /// The leaf body is kept with its `_revisions` chain, served when [revs] is
  /// set so the target can graft the branch onto its tree (a bodyless leaf is
  /// served as a minimal tombstone). The leaf's own attachments (keyed by
  /// `fkconflict`) are advertised as stubs in the doc and streamed alongside,
  /// honouring `atts_since` ([maxAttsSinceVersion]) exactly like the winner path.
  Future<BulkGetMultipartResult> _conflictLeafMultipart({
    required String docId,
    required int winnerDocRowId,
    required LocalConflictRevision leaf,
    required bool revs,
    required int? maxAttsSinceVersion,
  }) async {
    // A non-deleted bodyless leaf (a recorded permanently-gone leaf) has no
    // body to forward; serve it as not_found, exactly like the source CouchDB
    // does — so a third sync partner records it as bodyless too rather than
    // receiving a spurious tombstone. A deleted bodyless leaf is a real
    // tombstone and is forwarded as a minimal deleted doc.
    if (leaf.body == null && !(leaf.deleted ?? false)) {
      return BulkGetMultipartFailure(
        id: docId,
        rev: leaf.rev,
        error: 'not_found',
        reason: 'missing',
      );
    }
    final Map<String, dynamic> docMap;
    if (leaf.body == null) {
      docMap = {'_id': docId, '_rev': leaf.rev, '_deleted': true};
    } else {
      docMap = jsonDecode(leaf.body!) as Map<String, dynamic>;
      docMap['_id'] = docId;
      docMap['_rev'] = leaf.rev;
      // Conflict bodies are stored with `_revisions` kept; strip when not asked.
      if (!revs) docMap.remove('_revisions');
    }

    // Stub-only _attachments in the doc map (mirrors the winner path), then the
    // actual attachment streams for those exceeding atts_since.
    final stubsMap = await _recreateAttachmentMapFromDatabase(
      winnerDocRowId,
      false, // stubs only
      conflictRowId: leaf.id,
    );
    if (stubsMap != null && stubsMap.isNotEmpty) {
      docMap['_attachments'] = stubsMap.map((k, v) => MapEntry(k, v.toMap()));
    }

    final attachments = <String, BulkGetMultipartAttachment>{};
    for (final att in await db.getConflictAttachments(leaf.id)) {
      final shouldTransfer =
          maxAttsSinceVersion == null || att.revpos > maxAttsSinceVersion;
      if (!shouldTransfer) continue;
      attachments[att.name] = BulkGetMultipartAttachment(
        contentType: att.contentType,
        digest: att.digest,
        length: att.length,
        revpos: att.revpos,
        data: attachmentStorage.readAttachmentAsStream(att.id),
        encoding: att.encoding,
      );
    }

    return BulkGetMultipartSuccess(
      BulkGetMultipartOk(doc: docMap, attachments: attachments),
    );
  }

  @override
  Stream<BulkGetMultipartResult> bulkGetMultipart(
    BulkGetRequest request, {
    bool revs = false,
    void Function(int bytes)? onBytesReceived,
    // onBytesReceived is ignored — local reads are fast synchronous SQLite.
  }) async* {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    for (final docRequest in request.docs) {
      final docId = docRequest.id;
      final maxAttsSinceVersion = docRequest.attsSince?.isNotEmpty == true
          ? _parseMaxRevVersion(docRequest.attsSince!)
          : null;

      // Hold the mutex only for the SQLite queries; yield outside it.
      final result = await m.protect(() async {
        final ldoc = await db.getDocument(
          dbid,
          docId,
          true,
          rev: docRequest.rev,
          ignoreDeleted: true,
        );

        if (ldoc == null) {
          // The winner doesn't match. If a specific rev was requested it may be
          // a stored non-winning conflict leaf (Decision A2) — serve it so Local
          // can forward conflict branches as a replication source (Stage 3;
          // required for Phase 2 resolution tombstones to reach the remote).
          if (docRequest.rev != null) {
            final winnerRow = await db.getDocument(
              dbid,
              docId,
              false,
              ignoreDeleted: true,
            );
            if (winnerRow != null) {
              final leaf = (await db.getConflictRevisions(
                winnerRow.document.id,
              )).firstWhereOrNull((c) => c.rev == docRequest.rev);
              if (leaf != null) {
                return _conflictLeafMultipart(
                  docId: docId,
                  winnerDocRowId: winnerRow.document.id,
                  leaf: leaf,
                  revs: revs,
                  maxAttsSinceVersion: maxAttsSinceVersion,
                );
              }
            }
          }
          return BulkGetMultipartFailure(
            id: docId,
            rev: docRequest.rev,
            error: 'not_found',
            reason: 'missing',
          );
        }

        // Build doc map (mirrors _internalGetRaw).
        final Map<String, dynamic> docMap;
        if (ldoc.data == null) {
          docMap = {
            '_id': ldoc.document.docid,
            '_rev': ldoc.document.rev,
            '_deleted': true,
          };
        } else {
          docMap = jsonDecode(ldoc.data!);
          // Stored JSON omits transport metadata; re-inject CouchDB fields so
          // replication writes with new_edits=false always has _id/_rev.
          docMap['_id'] = ldoc.document.docid;
          docMap['_rev'] = ldoc.document.rev;
        }

        if (revs) {
          final revisions = await _getRevs(
            ldoc.document.id,
            ldoc.document.version,
          );
          if (revisions != null) {
            docMap['_revisions'] = revisions.toMap();
          }
        }

        // Add stub-only _attachments to the doc map.
        if (ldoc.data != null) {
          final stubsMap = await _recreateAttachmentMapFromDatabase(
            ldoc.document.id,
            false, // no inline data — stubs only
          );
          if (stubsMap != null) {
            docMap['_attachments'] = stubsMap.map(
              (k, v) => MapEntry(k, v.toMap()),
            );
          }
        }

        // Build the attachments map: only those that exceed atts_since.
        final attRows = await db.getAttachments(ldoc.document.id);
        final attachments = <String, BulkGetMultipartAttachment>{};
        for (final att in attRows) {
          final shouldTransfer =
              maxAttsSinceVersion == null || att.revpos > maxAttsSinceVersion;
          if (!shouldTransfer) continue;

          attachments[att.name] = BulkGetMultipartAttachment(
            contentType: att.contentType,
            digest: att.digest,
            length: att.length,
            revpos: att.revpos,
            data: attachmentStorage.readAttachmentAsStream(att.id),
            encoding: att.encoding,
          );
        }

        return BulkGetMultipartSuccess(
          BulkGetMultipartOk(doc: docMap, attachments: attachments),
        );
      });

      yield result;
    }
  }

  @override
  Future<List<BulkDocsResult>> bulkDocsFromMultipart(
    List<BulkGetMultipartSuccess> docs, {
    bool newEdits = false,
  }) async {
    if (_disposed) {
      throw CouchDbException(
        CouchDbStatusCodes.internalServerError,
        'Database $dbname has been disposed',
      );
    }

    return await m.protect<List<BulkDocsResult>>(() async {
      // Fast path: replication batch with no attachments.
      if (!newEdits && docs.every((s) => s.ok.attachments.isEmpty)) {
        return _bulkWriteNoAttachments(docs);
      }

      final List<BulkDocsResult> results = [];
      final deferredFileDeletes = <int>[];

      await db.transaction(() async {
        for (final success in docs) {
          String? docId;
          String? docRev;
          try {
            final docMap = Map<String, dynamic>.from(success.ok.doc);

            // Capture the revision chain before stripping (for conflict leaf
            // maintenance), mirroring bulkDocsRaw.
            final Map<String, dynamic>? incomingRevisions =
                (docMap['_revisions'] as Map<String, dynamic>?);

            // Remove transport-only fields (mirrors bulkDocsRaw).
            docMap.remove('_revisions');
            docMap.remove('_revs_info');
            docMap.remove('_conflicts');
            docMap.remove('_deleted_conflicts');
            docMap.remove('_local_seq');

            docId = docMap['_id'] as String?;
            docRev = docMap['_rev'] as String?;
            final bool isDeleted = (docMap['_deleted'] as bool?) ?? false;

            if (newEdits) {
              // newEdits=true path — identical to bulkDocsRaw.
              docId = docId ?? uuid.v4();
              docMap['_id'] = docId;
              final existingDoc = await db.getDocument(
                dbid,
                docId,
                true,
                ignoreDeleted: true,
              );

              if (existingDoc != null) {
                if (existingDoc.document.deleted == false) {
                  if (docRev != existingDoc.document.rev) {
                    throw CouchDbException.conflictPut(docId);
                  }
                }
                docRev = _calculateNewRev(
                  docRev ?? existingDoc.document.rev,
                  docMap,
                );
              } else {
                if (docRev != null) {
                  throw CouchDbException.conflictPut(docId);
                }
                docRev = _calculateNewRev(null, docMap);
              }
              docMap['_rev'] = docRev;

              final newEditsTombstoneIds = (isDeleted && existingDoc != null)
                  ? (await db.getAttachments(
                      existingDoc.document.id,
                    )).map((a) => a.id).toList()
                  : <int>[];

              int seq = await db.incrementAndGetUpdateSeq(dbid);
              final int version = int.parse(docRev.split('-')[0]);
              final filteredDoc = Map<String, dynamic>.from(docMap)
                ..remove('_attachments');

              int documentId = await db
                  .into(db.localDocuments)
                  .insertOnConflictUpdate(
                    LocalDocumentsCompanion(
                      id: Value.absentIfNull(existingDoc?.document.id),
                      docid: Value(docId),
                      fkdatabase: Value(dbid),
                      rev: Value(docRev),
                      version: Value(version),
                      deleted: Value(isDeleted),
                      seq: Value(seq),
                    ),
                  );

              if (!isDeleted) {
                await db
                    .into(db.documentBlobs)
                    .insertOnConflictUpdate(
                      DocumentBlobsCompanion(
                        documentId: Value(
                          existingDoc?.document.id ?? documentId,
                        ),
                        data: Value(jsonEncode(filteredDoc)),
                      ),
                    );
              }

              results.add(BulkDocsResult(id: docId, ok: true, rev: docRev));
              for (final id in newEditsTombstoneIds) {
                await _deleteAttachmentFile(id);
              }
            } else {
              // Replication path (newEdits=false) — mirrors bulkDocsRaw.
              if (docRev == null) {
                throw CouchDbException(
                  CouchDbStatusCodes.badRequest,
                  'Document must have a _rev for new_edits=false',
                );
              }
              docId = docId ?? uuid.v4();

              final existingDoc = await db.getDocument(
                dbid,
                docId,
                true,
                ignoreDeleted: true,
              );
              final int version = int.parse(docRev.split('-')[0]);

              // Conflict leaf maintenance (Decision A2) — shared with bulkDocsRaw.
              // When the incoming is stored as a (non-deleted) conflict leaf,
              // stream that leaf's attachments to disk under its fkconflict
              // (Stage 2).
              final leaf = await _applyIncomingLeaf(
                docId: docId,
                docRev: docRev,
                version: version,
                isDeleted: isDeleted,
                docMap: docMap,
                incomingRevisions: incomingRevisions,
                existingDoc: existingDoc,
                deferredFileDeletes: deferredFileDeletes,
              );
              if (!leaf.writeAsWinner) {
                if (leaf.incomingConflictRowId != null) {
                  await _storeStreamConflictAttachments(
                    docRowId: existingDoc!.document.id,
                    conflictRowId: leaf.incomingConflictRowId!,
                    attachments: success.ok.attachments,
                    deferredFileDeletes: deferredFileDeletes,
                  );
                }
                // Tree changed but winner row unchanged → bump seq so the change
                // replicates out (see the bulkDocsRaw path above).
                if (leaf.leafSetChanged) {
                  final seq = await db.incrementAndGetUpdateSeq(dbid);
                  await db.updateDocumentSeq(existingDoc!.document.id, seq);
                }
                results.add(BulkDocsResult(id: docId, ok: true, rev: docRev));
                continue;
              }

              final tombstoneAttachmentIds = (isDeleted && existingDoc != null)
                  ? (await db.getAttachments(
                      existingDoc.document.id,
                    )).map((a) => a.id).toList()
                  : <int>[];

              int seq = await db.incrementAndGetUpdateSeq(dbid);
              final filteredDoc = Map<String, dynamic>.from(docMap)
                ..remove('_attachments');

              int documentId = await db
                  .into(db.localDocuments)
                  .insertOnConflictUpdate(
                    LocalDocumentsCompanion(
                      id: Value.absentIfNull(existingDoc?.document.id),
                      docid: Value(docId),
                      fkdatabase: Value(dbid),
                      rev: Value(docRev),
                      version: Value(version),
                      deleted: Value(isDeleted),
                      seq: Value(seq),
                    ),
                  );

              if (!isDeleted) {
                await db
                    .into(db.documentBlobs)
                    .insertOnConflictUpdate(
                      DocumentBlobsCompanion(
                        documentId: Value(
                          existingDoc?.document.id ?? documentId,
                        ),
                        data: Value(jsonEncode(filteredDoc)),
                      ),
                    );
              }

              final actualDocId = existingDoc?.document.id ?? documentId;
              final existingAttachments = existingDoc != null
                  ? await db.getAttachments(actualDocId)
                  : <LocalAttachment>[];

              // Write transferred attachments via stream (no base64 decode).
              int ordering = 0;
              for (final entry in success.ok.attachments.entries) {
                final attName = entry.key;
                final att = entry.value;
                _log.fine(
                  'Replication: writing attachment "$attName" for $docId'
                  ' (${att.length} bytes, stream)',
                );
                ordering++;
                final existingId = existingAttachments
                    .firstWhereOrNull((e) => e.name == attName)
                    ?.id;
                await _saveAttachmentFromStream(
                  LocalAttachmentsCompanion(
                    id: existingId != null ? Value(existingId) : Value.absent(),
                    fkdocument: Value(actualDocId),
                    name: Value(attName),
                    revpos: Value(att.revpos),
                    contentType: Value(att.contentType),
                    ordering: Value(ordering),
                  ),
                  att.digest,
                  att.length,
                  att.data,
                  encoding: att.encoding,
                  deferredFileDeletes: deferredFileDeletes,
                );
              }

              // Log stubs skipped via atts_since optimisation — attachments
              // present in the document but not transferred because the target
              // already has them.
              final attachmentsStubs =
                  docMap['_attachments'] as Map<String, dynamic>?;
              if (attachmentsStubs != null) {
                for (final stubName in attachmentsStubs.keys) {
                  if (!success.ok.attachments.containsKey(stubName)) {
                    _log.fine(
                      'Replication: skipping stub attachment "$stubName"'
                      ' for $docId (already on target)',
                    );
                  }
                }
              }

              // Delete orphaned attachment rows not in the incoming revision.
              if (!isDeleted) {
                final newAttachmentNames = {
                  ...(docMap['_attachments'] as Map<String, dynamic>?)?.keys ??
                      <String>{},
                  ...success.ok.attachments.keys,
                };
                for (final existing in existingAttachments) {
                  if (!newAttachmentNames.contains(existing.name)) {
                    await db.deleteAttachment(existing.id);
                    await _deleteAttachmentFile(existing.id);
                  }
                }
              }

              results.add(BulkDocsResult(id: docId, ok: true, rev: docRev));
              for (final id in tombstoneAttachmentIds) {
                await _deleteAttachmentFile(id);
              }
            }
          } catch (e, stackTrace) {
            if (e is CouchDbException) rethrow;
            _log.warning(
              'Unexpected error during bulkDocsFromMultipart for $docId: $e',
              e,
              stackTrace,
            );
            results.add(
              BulkDocsResult(
                id: docId ?? '',
                ok: false,
                error: 'unknown_error',
                reason: e.toString(),
              ),
            );
          }
        }
      });

      // Clean up old attachment files after transaction committed successfully.
      for (final oldId in deferredFileDeletes) {
        await _deleteAttachmentFile(oldId);
      }

      return newEdits ? results : [];
    });
  }

  /// Writes an attachment from a byte stream directly to disk, mirroring the
  /// crash-safe ordering of [_saveAttachmentWithFileIO] but without loading
  /// the full attachment into memory (no base64 decode).
  ///
  /// [digest] and [length] are trusted from the caller (e.g. from CouchDB
  /// multipart headers) — no re-hashing is performed.
  ///
  /// [encoding] is the CouchDB content-encoding (e.g. `'gzip'`) if the
  /// attachment was compressed by CouchDB, or `null` for uncompressed data.
  /// Fast path for bulkDocsFromMultipart when all docs lack attachments
  /// and newEdits=false (replication). Reduces ~5 SQL ops/doc to ~2 by
  /// batch-fetching existing docs and batch-allocating seq numbers.
  ///
  /// Handles duplicate docIds (conflicting revisions) by keeping only the
  /// winning revision per docId using CouchDB's standard conflict resolution.
  Future<List<BulkDocsResult>> _bulkWriteNoAttachments(
    List<BulkGetMultipartSuccess> docs,
  ) async {
    final sw = Stopwatch()..start();

    // --- Phase 1: Parse all incoming docs (capture _revisions for conflict
    // leaf maintenance) ---
    final parsed = <({
      String docId,
      String docRev,
      int version,
      bool isDeleted,
      Map<String, dynamic> docMap,
      Map<String, dynamic>? revisions,
    })>[];

    for (final success in docs) {
      final docMap = Map<String, dynamic>.from(success.ok.doc);
      final revisions = docMap['_revisions'] as Map<String, dynamic>?;
      docMap.remove('_revisions');
      docMap.remove('_revs_info');
      docMap.remove('_conflicts');
      docMap.remove('_deleted_conflicts');
      docMap.remove('_local_seq');

      final docId = (docMap['_id'] as String?) ?? uuid.v4();
      final docRev = docMap['_rev'] as String?;
      if (docRev == null) {
        throw CouchDbException(
          CouchDbStatusCodes.badRequest,
          'Document must have a _rev for new_edits=false',
        );
      }
      docMap['_id'] = docId;

      parsed.add((
        docId: docId,
        docRev: docRev,
        version: int.parse(docRev.split('-')[0]),
        isDeleted: (docMap['_deleted'] as bool?) ?? false,
        docMap: docMap,
        revisions: revisions,
      ));
    }

    final results = <BulkDocsResult>[];
    final deferredFileDeletes = <int>[];

    await db.transaction(() async {
      // Batch-fetch existing winners and count docId occurrences, to partition
      // docs into a fast batch path (truly new + unique → cannot be a conflict)
      // and a per-doc conflict-aware path (existing winner, or duplicated in
      // this same batch — e.g. revsDiff returned several missing revs of one
      // conflicted doc).
      final docIds = parsed.map((p) => p.docId).toList();
      final existingDocs = await db.getDocumentsByDocIds(dbid, docIds);
      final counts = <String, int>{};
      for (final p in parsed) {
        counts[p.docId] = (counts[p.docId] ?? 0) + 1;
      }

      final simple = <int>[];
      final complex = <int>[];
      for (var i = 0; i < parsed.length; i++) {
        final p = parsed[i];
        if (existingDocs[p.docId] == null && counts[p.docId] == 1) {
          simple.add(i);
        } else {
          complex.add(i);
        }
      }

      // --- Fast batch path: new, unique documents (pure inserts) ---
      // This is the common case for initial sync and keeps it batched/fast.
      if (simple.isNotEmpty) {
        final firstSeq = await db.incrementUpdateSeqBy(dbid, simple.length);
        for (var k = 0; k < simple.length; k++) {
          final p = parsed[simple[k]];
          final seq = firstSeq + k;
          final filteredDoc = Map<String, dynamic>.from(p.docMap)
            ..remove('_attachments');
          final int documentId = await db
              .into(db.localDocuments)
              .insertOnConflictUpdate(
                LocalDocumentsCompanion(
                  docid: Value(p.docId),
                  fkdatabase: Value(dbid),
                  rev: Value(p.docRev),
                  version: Value(p.version),
                  deleted: Value(p.isDeleted),
                  seq: Value(seq),
                ),
              );
          if (!p.isDeleted) {
            await db
                .into(db.documentBlobs)
                .insertOnConflictUpdate(
                  DocumentBlobsCompanion(
                    documentId: Value(documentId),
                    data: Value(jsonEncode(filteredDoc)),
                  ),
                );
          }
          results.add(BulkDocsResult(id: p.docId, ok: true, rev: p.docRev));
        }
      }

      // --- Per-doc conflict-aware path: existing or duplicated docs ---
      for (final idx in complex) {
        final p = parsed[idx];
        // Re-fetch fresh: an earlier doc in this batch may have changed state
        // (e.g. two conflicting revs of the same new doc in one batch).
        final existingDoc = await db.getDocument(
          dbid,
          p.docId,
          true,
          ignoreDeleted: true,
        );

        // Tombstone attachment files to delete after the write (the trigger
        // removes the rows; files are the Dart layer's responsibility).
        final List<int> tombstoneIds = (p.isDeleted && existingDoc != null)
            ? (await db.getAttachments(
                existingDoc.document.id,
              )).map((a) => a.id).toList()
            : <int>[];

        // These docs carry no attachments (partitioned into the no-attachment
        // fast path), so a conflict leaf here has nothing to store; the old
        // winner's attachment re-point on demote is handled inside the helper.
        final leaf = await _applyIncomingLeaf(
          docId: p.docId,
          docRev: p.docRev,
          version: p.version,
          isDeleted: p.isDeleted,
          docMap: p.docMap,
          incomingRevisions: p.revisions,
          existingDoc: existingDoc,
          deferredFileDeletes: deferredFileDeletes,
        );
        if (!leaf.writeAsWinner) {
          // Tree changed but winner row unchanged → bump seq so the change
          // replicates out (see the bulkDocsRaw path above).
          if (leaf.leafSetChanged) {
            final seq = await db.incrementAndGetUpdateSeq(dbid);
            await db.updateDocumentSeq(existingDoc!.document.id, seq);
          }
          results.add(BulkDocsResult(id: p.docId, ok: true, rev: p.docRev));
          continue;
        }

        // Orphaned attachments: existing atts absent from the new revision.
        final List<int> orphanIds = [];
        if (!p.isDeleted && existingDoc != null) {
          final existingAtts = await db.getAttachments(existingDoc.document.id);
          final newNames =
              (p.docMap['_attachments'] as Map<String, dynamic>?)?.keys
                  .toSet() ??
              <String>{};
          for (final a in existingAtts) {
            if (!newNames.contains(a.name)) orphanIds.add(a.id);
          }
        }

        final seq = await db.incrementAndGetUpdateSeq(dbid);
        final filteredDoc = Map<String, dynamic>.from(p.docMap)
          ..remove('_attachments');
        final int documentId = await db
            .into(db.localDocuments)
            .insertOnConflictUpdate(
              LocalDocumentsCompanion(
                id: Value.absentIfNull(existingDoc?.document.id),
                docid: Value(p.docId),
                fkdatabase: Value(dbid),
                rev: Value(p.docRev),
                version: Value(p.version),
                deleted: Value(p.isDeleted),
                seq: Value(seq),
              ),
            );
        if (!p.isDeleted) {
          await db
              .into(db.documentBlobs)
              .insertOnConflictUpdate(
                DocumentBlobsCompanion(
                  documentId: Value(existingDoc?.document.id ?? documentId),
                  data: Value(jsonEncode(filteredDoc)),
                ),
              );
        }
        for (final id in orphanIds) {
          await db.deleteAttachment(id);
        }
        deferredFileDeletes
          ..addAll(tombstoneIds)
          ..addAll(orphanIds);

        // If this write tombstoned the winner, promote a surviving leaf.
        if (p.isDeleted) {
          await _promoteAfterTombstone(
            existingDoc?.document.id ?? documentId,
            p.docId,
          );
        }

        results.add(BulkDocsResult(id: p.docId, ok: true, rev: p.docRev));
      }
    });

    for (final id in deferredFileDeletes) {
      await _deleteAttachmentFile(id);
    }

    sw.stop();
    _log.fine(
      'Batch write (fast path): ${docs.length} docs, '
      '${results.length} written in ${sw.elapsedMilliseconds}ms',
    );
    return results;
  }

  Future<int> _saveAttachmentFromStream(
    LocalAttachmentsCompanion entry,
    String digest,
    int length,
    Stream<List<int>> stream, {
    String? encoding,
    List<int>? deferredFileDeletes,
  }) async {
    entry = entry.copyWith(
      digest: Value(digest),
      length: Value(length),
      encoding: Value(encoding),
    );
    final existingId = entry.id.present ? entry.id.value : null;

    if (existingId != null) {
      // DELETE-old + INSERT-new: never overwrite old file inside transaction.
      await db.deleteAttachment(existingId);
      entry = entry.copyWith(id: Value.absent());
      final newId = await db.saveAttachment(entry);
      try {
        await attachmentStorage.writeAttachmentFromStream(newId, stream);
        await attachmentStorage.finalizeWrite(newId);
      } catch (e) {
        await db.deleteAttachment(newId);
        rethrow;
      }
      deferredFileDeletes?.add(existingId);
      return newId;
    } else {
      // INSERT: insert DB row to get ID, write directly, finalize.
      // On write failure, delete the orphan DB row.
      final newId = await db.saveAttachment(entry);
      try {
        await attachmentStorage.writeAttachmentFromStream(newId, stream);
        await attachmentStorage.finalizeWrite(newId);
      } catch (e) {
        await db.deleteAttachment(newId);
        rethrow;
      }
      return newId;
    }
  }
}

/// Computes a new CouchDB revision for [doc] given the previous revision
/// string [prevRev] and returns a copy of the document with the updated `_rev`.
CouchDocumentBase _updateRevInDoc(CouchDocumentBase doc, String? prevRev) {
  final rev = calculateCouchDbNewRev(doc.toMap(), prevRev);
  return doc.copyWith(rev: rev);
}

/// Computes a new CouchDB-style revision string for a document map.
/// Increments the generation counter and hashes the document content.
String _calculateNewRev(String? prevRev, Map<String, dynamic> docMap) {
  return calculateCouchDbNewRev(docMap, prevRev);
}

/// Extracts the generation number from a revision string (`"N-hash"`)
/// and returns `N + 1`.  Used to set `revpos` when saving a new attachment.
int _getNextVersionFromRev(String? rev) {
  if (rev == null) return 1;
  return int.parse(rev.split('-').first) + 1;
}

/// Recursively sort map keys
// ignore: unused_element
dynamic _sortKeys(dynamic value) {
  if (value is Map) {
    final sortedMap = Map<String, dynamic>.fromEntries(
      (value as Map<String, dynamic>).entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key)),
    );
    return sortedMap.map((k, v) => MapEntry(k, _sortKeys(v)));
  } else if (value is List) {
    return value.map(_sortKeys).toList();
  } else {
    return value;
  }
}

/// Converts the internal integer sequence to a CouchDB-style sequence string.
///
/// CouchDB uses opaque, server-generated sequence tokens; locally we use plain
/// integers.  Appending `-dummyhash` produces the same `"N-hash"` format so
/// that sequence strings can be compared and parsed uniformly across both
/// implementations.
String _makeSeqString(int seq) {
  return '$seq-dummyhash';
}

/// Returns the highest version number found in a list of CouchDB revision
/// strings (e.g. ["3-abc", "5-xyz"] → 5), or null if the list is empty or
/// no valid revision strings are found. Used for atts_since optimisation.
int? _parseMaxRevVersion(List<String> revs) {
  int maxVersion = 0;
  for (final rev in revs) {
    final dash = rev.indexOf('-');
    if (dash > 0) {
      final version = int.tryParse(rev.substring(0, dash));
      if (version != null && version > maxVersion) {
        maxVersion = version;
      }
    }
  }
  return maxVersion > 0 ? maxVersion : null;
}
