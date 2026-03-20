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
class LocalDartCouchDb extends DartCouchDb with CouchReplicationMixin {
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

              // Skip if we already have this exact revision
              if (existingDoc != null && existingDoc.document.rev == docRev) {
                results.add(BulkDocsResult(id: docId, ok: true, rev: docRev));
                continue;
              }

              // CouchDB deterministic conflict resolution for newEdits=false:
              // 1. Higher version number always wins
              // 2. On equal version: non-deleted wins over deleted
              // 3. On equal version + equal deletion status: higher hash wins
              //
              // Rule 2 matters for human-resolved conflicts: when an app
              // resolves a conflict by deleting one of the competing revisions,
              // both the winning (active) leaf and the losing (deleted) leaf
              // appear in the changes feed with style=all_docs. If the deleted
              // leaf happens to have a lexicographically higher hash than the
              // active leaf (e.g. categorie_back_teig: active=2-0b99... vs
              // deleted=2-d077...), a hash-only comparison would wrongly store
              // the document as a tombstone locally.
              //
              // CouchDB stores both leaves in its revision tree; since we store
              // only one, we apply the same winner selection algorithm.
              if (existingDoc != null &&
                  version <= existingDoc.document.version) {
                if (version < existingDoc.document.version) {
                  // Incoming version is strictly older — skip
                  results.add(BulkDocsResult(id: docId, ok: true, rev: docRev));
                  continue;
                }
                // Equal version — prefer non-deleted over deleted first
                final existingDeleted = existingDoc.document.deleted ?? false;
                if (isDeleted && !existingDeleted) {
                  // Existing is active, incoming is deleted — existing wins
                  results.add(BulkDocsResult(id: docId, ok: true, rev: docRev));
                  continue;
                }
                if (isDeleted == existingDeleted) {
                  // Same deletion status — compare revision hashes to pick winner
                  final incomingHash = docRev.substring(
                    docRev.indexOf('-') + 1,
                  );
                  final existingHash = existingDoc.document.rev.substring(
                    existingDoc.document.rev.indexOf('-') + 1,
                  );
                  if (incomingHash.compareTo(existingHash) <= 0) {
                    // Existing hash wins (or identical) — skip
                    results.add(
                      BulkDocsResult(id: docId, ok: true, rev: docRev),
                    );
                    continue;
                  }
                }
                // Incoming wins — fall through to overwrite
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
    assert(attachments == false);
    assert(attEncodingInfo == false);
    assert(lastEventId == null);
    assert(limit == 0);
    //assert(styleAllDocs == false);  // I think the local implementation cannot have branching revisions?
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

    // Create a dedicated StreamController for this request
    StreamSubscription? subscription;
    final controller = StreamController<Map<String, dynamic>>(
      onCancel: () async {
        // when there is no listeners anymore, the http
        // subscription needs to be canceled!
        await subscription?.cancel();
      },
    );

    unawaited(() async {
      if (feedmode == FeedMode.normal || feedmode == FeedMode.longpoll) {
        // normal feed -- just a single response
        // Read documents and updateSeq in a single transaction to get a
        // consistent snapshot. Without this, a concurrent write (e.g.
        // saveAttachment) can update the document between the two queries,
        // causing the changes feed to report a stale revision with a newer
        // lastSeq — which makes replication request a rev that no longer exists.
        final snapshot = await db.getDocumentsAndUpdateSeq(dbid, includeDocs);
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
        assert(controller.hasListener);
        // Build raw JSON map instead of ChangesResult
        final json = <String, dynamic>{
          'pending': 0,
          'last_seq': _makeSeqString(dbRecord.updateSeq),
          'results': ldocs.map((ldoc) {
            final changeEntry = <String, dynamic>{
              'seq': _makeSeqString(ldoc.document.seq),
              'id': ldoc.document.docid,
              'changes': [
                {'rev': ldoc.document.rev},
              ],
            };
            if (ldoc.document.deleted == true) {
              changeEntry['deleted'] = true;
            }
            if (ldoc.data != null) {
              changeEntry['doc'] =
                  jsonDecode(ldoc.data!) as Map<String, dynamic>;
            }
            return changeEntry;
          }).toList(),
        };
        controller.add(json);
        await controller.close();
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
              .watchDocuments(dbid, includeDocs, since: effectiveSince)
              .listen(
                (LocalDocumentWithBlob ldoc) {
                  if (controller.isClosed) {
                    return;
                  }
                  // filter out local documents (_local/*) - they don't appear in changes feed
                  if (ldoc.document.docid.startsWith('_local/')) {
                    return;
                  }
                  // Build raw JSON map for each change
                  final json = <String, dynamic>{
                    'seq': _makeSeqString(ldoc.document.seq),
                    'id': ldoc.document.docid,
                    'changes': [
                      {'rev': ldoc.document.rev},
                    ],
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
    if (ldoc == null) return null;

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

    // Add revisions and revsInfo if requested
    if (revs == true) {
      final revisions = await _getRevs(ldoc.document.id, ldoc.document.version);
      if (revisions != null) {
        docMap['_revisions'] = revisions.toMap();
      }
    }
    if (revsInfo == true) {
      final revsInfoList = await _getRevsInfo(ldoc.document.id);
      docMap['_revs_info'] = revsInfoList.map((e) => e.toMap()).toList();
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
  }) async {
    List<LocalAttachment> attachments = await db.getAttachments(dbdocid);

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

        if (revisions == null || revisions.contains(doc.rev)) {
          res.add(
            OpenRevsResult(missingRev: null, state: OpenRevsState.ok, doc: doc),
          );
        }

        if (revisions != null) {
          List<RevisionHistory> history = (await db.getRevisionHistory(
            dbid: dbid,
            dbdocid: ldoc.document.id,
            sortDesc: false,
          ))!;

          for (int i = 0; i < history.length; ++i) {
            if (history[i].rev != doc.rev &&
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
      LocalDocumentWithBlob? ldoc = await db.getDocument(
        dbid,
        docId,
        false,
        rev: rev,
      );
      if (ldoc == null) return null;
      if (rev != null && ldoc.document.rev != rev) {
        throw CouchDbException.attachmentNotFound();
      }
      LocalAttachment? existingAttachment = await db.getAttachment(
        ldoc.document.id,
        attachmentName,
      );
      if (existingAttachment == null) return null;

      return await attachmentStorage.readAttachment(existingAttachment.id);
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

              if (existingDoc != null && existingDoc.document.rev == docRev) {
                results.add(BulkDocsResult(id: docId, ok: true, rev: docRev));
                continue;
              }

              if (existingDoc != null &&
                  version <= existingDoc.document.version) {
                if (version < existingDoc.document.version) {
                  results.add(BulkDocsResult(id: docId, ok: true, rev: docRev));
                  continue;
                }
                final existingDeleted = existingDoc.document.deleted ?? false;
                if (isDeleted && !existingDeleted) {
                  results.add(BulkDocsResult(id: docId, ok: true, rev: docRev));
                  continue;
                }
                if (isDeleted == existingDeleted) {
                  final incomingHash = docRev.substring(
                    docRev.indexOf('-') + 1,
                  );
                  final existingHash = existingDoc.document.rev.substring(
                    existingDoc.document.rev.indexOf('-') + 1,
                  );
                  if (incomingHash.compareTo(existingHash) <= 0) {
                    results.add(
                      BulkDocsResult(id: docId, ok: true, rev: docRev),
                    );
                    continue;
                  }
                }
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

    // --- Phase 1: Parse all incoming docs (outside transaction) ---
    final parsed = <({
      String docId,
      String docRev,
      int version,
      bool isDeleted,
      Map<String, dynamic> docMap,
    })>[];

    for (final success in docs) {
      final docMap = Map<String, dynamic>.from(success.ok.doc);
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
      ));
    }

    final results = <BulkDocsResult>[];

    // --- Phase 1a: De-duplicate by docId (conflicting revisions) ---
    // When a doc has conflicts, revsDiff returns multiple missing revisions
    // for the same docId. We keep only the winning revision per docId using
    // CouchDB's standard conflict resolution (highest version, then
    // non-deleted beats deleted at same version, then highest rev hash).
    final byDocId = <String, List<int>>{};
    for (var i = 0; i < parsed.length; i++) {
      byDocId.putIfAbsent(parsed[i].docId, () => []).add(i);
    }

    final deduped = <({
      String docId,
      String docRev,
      int version,
      bool isDeleted,
      Map<String, dynamic> docMap,
    })>[];

    for (final entry in byDocId.entries) {
      final indices = entry.value;
      if (indices.length == 1) {
        deduped.add(parsed[indices[0]]);
        continue;
      }
      // Multiple revisions — find the winner.
      var winnerIdx = indices[0];
      for (var j = 1; j < indices.length; j++) {
        final candidate = parsed[indices[j]];
        final current = parsed[winnerIdx];
        if (candidate.version > current.version) {
          winnerIdx = indices[j];
        } else if (candidate.version == current.version) {
          final candidateDeleted = candidate.isDeleted;
          final currentDeleted = current.isDeleted;
          if (!candidateDeleted && currentDeleted) {
            winnerIdx = indices[j];
          } else if (candidateDeleted == currentDeleted) {
            final candidateHash =
                candidate.docRev.substring(candidate.docRev.indexOf('-') + 1);
            final currentHash =
                current.docRev.substring(current.docRev.indexOf('-') + 1);
            if (candidateHash.compareTo(currentHash) > 0) {
              winnerIdx = indices[j];
            }
          }
        }
      }
      deduped.add(parsed[winnerIdx]);
      // Losers get ok:true (accepted but not stored as winner).
      for (final idx in indices) {
        if (idx != winnerIdx) {
          final p = parsed[idx];
          results.add(BulkDocsResult(id: p.docId, ok: true, rev: p.docRev));
        }
      }
    }

    // --- All DB work inside a single transaction ---
    await db.transaction(() async {
      // --- Phase 1b: Batch-fetch all existing docs (1 query) ---
      final docIds = deduped.map((p) => p.docId).toList();
      final existingDocs = await db.getDocumentsByDocIds(dbid, docIds);

      // --- Phase 2: Evaluate skip logic, determine which docs to write ---
      final toWrite = <({
        String docId,
        String docRev,
        int version,
        bool isDeleted,
        Map<String, dynamic> docMap,
        LocalDocumentWithBlob? existing,
      })>[];

      // Collect tombstone attachment IDs for file deletion after transaction.
      final tombstoneAttachmentIds = <int>[];

      for (final p in deduped) {
        final existing = existingDocs[p.docId];

        // Same rev → already replicated, skip.
        if (existing != null && existing.document.rev == p.docRev) {
          results.add(BulkDocsResult(id: p.docId, ok: true, rev: p.docRev));
          continue;
        }

        // Lower or equal version with conflict resolution.
        if (existing != null && p.version <= existing.document.version) {
          if (p.version < existing.document.version) {
            results.add(BulkDocsResult(id: p.docId, ok: true, rev: p.docRev));
            continue;
          }
          final existingDeleted = existing.document.deleted ?? false;
          if (p.isDeleted && !existingDeleted) {
            results.add(BulkDocsResult(id: p.docId, ok: true, rev: p.docRev));
            continue;
          }
          if (p.isDeleted == existingDeleted) {
            final incomingHash =
                p.docRev.substring(p.docRev.indexOf('-') + 1);
            final existingHash = existing.document.rev
                .substring(existing.document.rev.indexOf('-') + 1);
            if (incomingHash.compareTo(existingHash) <= 0) {
              results
                  .add(BulkDocsResult(id: p.docId, ok: true, rev: p.docRev));
              continue;
            }
          }
        }

        toWrite.add((
          docId: p.docId,
          docRev: p.docRev,
          version: p.version,
          isDeleted: p.isDeleted,
          docMap: p.docMap,
          existing: existing,
        ));
      }

      if (toWrite.isEmpty) {
        _log.fine(
          'Batch write (fast path): ${docs.length} docs, '
          '0 written in ${sw.elapsedMilliseconds}ms',
        );
        return;
      }

      // --- Phase 2b: Batch-fetch attachment IDs for docs that need cleanup ---
      // This covers two cases:
      // 1. Tombstoned docs: all attachments must be deleted.
      // 2. Non-deleted docs with existing attachments: attachments removed
      //    from the new revision's _attachments stubs must be deleted.
      //    This happens when an attachment is deleted on the remote and the
      //    new revision arrives with stubs only (no transferred data).
      final docsNeedingAttLookup = toWrite
          .where((w) => w.existing != null)
          .map((w) => w.existing!.document.id)
          .toList();
      final existingAttMap = docsNeedingAttLookup.isNotEmpty
          ? await db.getAttachmentsByDocumentIds(docsNeedingAttLookup)
          : <int, List<LocalAttachment>>{};
      for (final w in toWrite) {
        if (w.isDeleted && w.existing != null) {
          final atts = existingAttMap[w.existing!.document.id] ?? [];
          tombstoneAttachmentIds.addAll(atts.map((a) => a.id));
        }
      }
      // Collect orphaned attachment IDs for non-deleted docs whose new
      // revision has fewer attachments than the existing local version.
      final orphanAttachmentIds = <int>[];
      for (final w in toWrite) {
        if (!w.isDeleted && w.existing != null) {
          final existingAtts = existingAttMap[w.existing!.document.id] ?? [];
          if (existingAtts.isEmpty) continue;
          final newAttNames =
              (w.docMap['_attachments'] as Map<String, dynamic>?)?.keys.toSet()
              ?? <String>{};
          for (final att in existingAtts) {
            if (!newAttNames.contains(att.name)) {
              orphanAttachmentIds.add(att.id);
            }
          }
        }
      }

      // --- Phase 3: Batch-allocate seq numbers (2 queries) ---
      final firstSeq = await db.incrementUpdateSeqBy(dbid, toWrite.length);

      // --- Phase 3b: Write documents ---
      for (var i = 0; i < toWrite.length; i++) {
        final w = toWrite[i];
        final seq = firstSeq + i;
        final filteredDoc = Map<String, dynamic>.from(w.docMap)
          ..remove('_attachments');

        final int documentId = await db
            .into(db.localDocuments)
            .insertOnConflictUpdate(
              LocalDocumentsCompanion(
                id: Value.absentIfNull(w.existing?.document.id),
                docid: Value(w.docId),
                fkdatabase: Value(dbid),
                rev: Value(w.docRev),
                version: Value(w.version),
                deleted: Value(w.isDeleted),
                seq: Value(seq),
              ),
            );

        if (!w.isDeleted) {
          await db
              .into(db.documentBlobs)
              .insertOnConflictUpdate(
                DocumentBlobsCompanion(
                  documentId: Value(w.existing?.document.id ?? documentId),
                  data: Value(jsonEncode(filteredDoc)),
                ),
              );
        }

        results.add(BulkDocsResult(id: w.docId, ok: true, rev: w.docRev));
      }

      // Delete orphaned attachment rows (non-deleted docs with removed atts).
      for (final id in orphanAttachmentIds) {
        await db.deleteAttachment(id);
      }

      // Delete tombstoned attachment files after transaction writes.
      for (final id in tombstoneAttachmentIds) {
        await _deleteAttachmentFile(id);
      }
      // Delete orphaned attachment files after transaction writes.
      for (final id in orphanAttachmentIds) {
        await _deleteAttachmentFile(id);
      }
    });

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
