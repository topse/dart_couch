import 'dart:async';
import 'dart:typed_data';

import 'package:dart_mappable/dart_mappable.dart';
import 'value_notifier.dart';
import 'package:logging/logging.dart';

import 'api_result.dart';
import 'dart_couch_connection_state.dart';
import 'dart_couch_db.dart';
import 'database_migration.dart';
import 'http_dart_couch_db.dart';
import 'http_dart_couch_server.dart';
import 'local_dart_couch_db.dart';
import 'messages/bulk_docs_result.dart';
import 'messages/bulk_get.dart';
import 'messages/bulk_get_multipart.dart';
import 'messages/changes_result.dart';
import 'messages/couch_db_status_codes.dart';
import 'messages/couch_document_base.dart';
import 'messages/database_info.dart';
import 'messages/index_result.dart';
import 'messages/revs_diff_result.dart';
import 'messages/view_result.dart';
import 'replication_mixin.dart';
import 'replication_mixin_interface.dart';

part 'offline_first_db.mapper.dart';

final Logger _log = Logger('dart_couch-offline_db');

@MappableClass(discriminatorValue: '!local_migration_state')
class LocalMigrationDocument extends CouchDocumentBase
    with LocalMigrationDocumentMappable {
  static const String docId = '_local/migration_state';

  @MappableField(key: 'last_seq')
  final int lastSeq;

  LocalMigrationDocument({
    required this.lastSeq,
    super.id = '_local/migration_state',
    super.rev,
    super.attachments,
    super.revisions,
    super.revsInfo,
    super.deleted,
    super.unmappedProps,
  });

  static final fromMap = LocalMigrationDocumentMapper.fromMap;
  static final fromJson = LocalMigrationDocumentMapper.fromJson;
}

class OfflineFirstDb extends DartCouchDb {
  final HttpDartCouchServer serverDb;
  final LocalDartCouchDb localDb;
  final void Function() notifyNetworkDegraded;
  final void Function(Future<void> Function()) registerRecoveryCallback;
  final void Function(Future<void> Function()) unregisterRecoveryCallback;
  final DocumentReplicationConflictResolver conflictResolver;

  final _ProxyReplicationController _proxyController =
      _ProxyReplicationController();
  ReplicationController get replicationController => _proxyController;
  bool _isDisposed = false;
  void Function()? _migrationReplicationListener;
  StreamSubscription? _migrationChangeSubscription;

  DatabaseMigration? migration;
  final DcValueNotifier<MigrationStatus> migrationState;

  OfflineFirstDb({
    required this.serverDb,
    required this.localDb,
    required super.dbname,
    required this.notifyNetworkDegraded,
    required this.registerRecoveryCallback,
    required this.unregisterRecoveryCallback,
    this.migration,
    required this.conflictResolver,
  }) : migrationState = DcValueNotifier(migration == null ? .matched : .tooOld);

  Future<void> _myRecoveryCallback() async {
    if (!_isDisposed) {
      // Check and execute migration when coming back online
      if (migration != null &&
          serverDb.connectionState.value ==
              DartCouchConnectionState.connected) {
        await _checkAndExecuteMigration();
      }
      await _startContinuousReplication();
    }
  }

  Future<void> init() async {
    registerRecoveryCallback(_myRecoveryCallback);

    if (migration != null) {
      // Check local migration state immediately (regardless of online/offline status)
      final localStatus = await migration!.checkMigrationState(localDb);
      migrationState.value = localStatus;
      _log.info('$dbname: Initial migration state set to $localStatus');

      // Start migration change listener immediately after initial check
      await _startMigrationChangeListener();

      // Check and execute migration if online before starting replication
      if (serverDb.connectionState.value ==
          DartCouchConnectionState.connected) {
        await _checkAndExecuteMigration();
      }
    } else {
      // If no migration is provided, start the migration change listener anyway
      // to ensure we catch any future migration documents
      await _startMigrationChangeListener();
    }

    await _startContinuousReplication();
  }

  /// Starts a continuous listener for migration document changes on localDb
  Future<void> _startMigrationChangeListener() async {
    // <-- Mark as async
    _log.info('$dbname: Starting migration change listener');

    // Cancel any existing subscription
    await _migrationChangeSubscription?.cancel();

    // Helper function to start the changes stream with the given sequence
    Future<void> startChangesStream(String since) async {
      _log.fine('$dbname: Starting changes stream from sequence: $since');

      // Start listening to localDb changes for migration document
      final changesStream = localDb.changes(
        includeDocs: false,
        feedmode: FeedMode.continuous,
        heartbeat: 30000,
        since: since,
      );

      _migrationChangeSubscription = changesStream.listen(
        (change) async {
          final entry = change.type == ChangesResultType.continuous
              ? change.continuous
              : null;

          if (entry == null) return;

          if (entry.id == '!migration_document') {
            _log.fine(
              '$dbname: Migration document change detected, checking state',
            );

            try {
              if (_isDisposed) return;

              final newStatus = await migration!.checkMigrationState(localDb);
              if (newStatus != migrationState.value) {
                _log.info('$dbname: Migration state updated to $newStatus');
                migrationState.value = newStatus;

                // Update the last sequence number in _local/migration_state
                try {
                  final localDoc = LocalMigrationDocument(
                    lastSeq: int.parse(entry.seq),
                  );
                  await put(localDoc);
                  _log.fine('$dbname: Updated last sequence to ${entry.seq}');
                } catch (e, stackTrace) {
                  _log.severe(
                    '$dbname: Error updating last sequence: $e',
                    e,
                    stackTrace,
                  );
                }
              }
            } catch (e, stackTrace) {
              _log.severe(
                '$dbname: Error checking migration state after change: $e',
                e,
                stackTrace,
              );
            }
          }
        },
        onError: (e, stackTrace) {
          _log.severe(
            '$dbname: Error in migration changes stream: $e',
            e,
            stackTrace,
          );
        },
        cancelOnError: true,
      );
    }

    // Read the last sequence number from _local/migration_state
    try {
      final localDoc =
          await localDb.get(LocalMigrationDocument.docId)
              as LocalMigrationDocument?;
      if (localDoc != null) {
        _log.fine(
          '$dbname: Found existing _local/migration_state with lastSeq: ${localDoc.lastSeq}',
        );
        await startChangesStream(localDoc.lastSeq.toString());
        return;
      }
    } catch (e) {
      _log.fine(
        '$dbname: No existing _local/migration_state document found, starting from 0',
      );
    }

    // If no _local/migration_state document exists, start from 0
    await startChangesStream('0');
  }

  @override
  Future<void> dispose() async {
    _log.fine('Disposing $dbname');
    _isDisposed = true;

    // Unregister recovery callback
    unregisterRecoveryCallback(_myRecoveryCallback);

    // Cancel any pending migration checks
    if (_migrationReplicationListener != null) {
      _proxyController.progress.removeListener(_migrationReplicationListener!);
      _migrationReplicationListener = null;
    }

    // Cancel any pending migration change stream subscriptions
    await _migrationChangeSubscription?.cancel();
    _migrationChangeSubscription = null;

    await _proxyController.stop();
    super.dispose();
    _log.fine('$dbname disposed');
  }

  Future<void> _startContinuousReplication() async {
    if (_isDisposed) {
      _log.fine('$dbname is disposed, skipping replication start');
      return;
    }

    _log.fine('Request to start continuous replication for $dbname');
    try {
      // Attempt replication when connected OR when in connectedButNetworkError.
      // The connectedButNetworkError state means a previous network call failed
      // but the session may still be valid. If we silently skip here, health
      // monitoring never gets notified (notifyNetworkDegraded is not called) and
      // replication stays permanently broken after a standby/wake cycle.
      // Attempting the network call lets NetworkFailure propagate normally,
      // which calls notifyNetworkDegraded() and triggers health-monitoring retry.
      final cs = serverDb.connectionState.value;
      if (cs == DartCouchConnectionState.connected ||
          cs == DartCouchConnectionState.connectedButNetworkError) {
        _log.fine('$dbname: connectionState=$cs, attempting replication');
        HttpDartCouchDb db;
        try {
          _log.fine(
            'Attempting to ensure remote DB exists for $dbname before starting replication',
          );
          // try to create the database on the server
          db = await serverDb.createDatabase(dbname) as HttpDartCouchDb;
          _log.info('$dbname created on serverDb by replication');
        } on CouchDbException catch (e) {
          // Database might have been created by another process (e.g., replay log)
          // check if exeption is precondition failed which indicates that the database already exists
          if (e.statusCode == .preconditionFailed) {
            db = (await serverDb.db(dbname)) as HttpDartCouchDb;
            _log.fine('Replication is using existing database $dbname');
          } else if (e.statusCode == .unauthorized) {
            // fallback: non-admin users cannot list databases, try to access directly
            final tempdb = await serverDb.db(dbname);
            if (tempdb == null) {
              throw StateError('Cannot access database $dbname on server');
            }
            db = tempdb;
          } else {
            rethrow;
          }
        }

        if (_isDisposed) return;

        final controller = localDb.syncTo(
          db,
          live: true,
          onConflict: conflictResolver,
        );
        _log.fine('Starting sync controller for $dbname (local -> remote)');
        await _proxyController.setDelegate(controller);
        _log.fine('Sync controller set for $dbname');

        // Check migration state after initial replication if migration was executed
        if (!_isDisposed &&
            migration != null &&
            migrationState.value == MigrationStatus.tooOld) {
          await _checkMigrationAfterReplication();
        }
      } else {
        _log.info(
          '$dbname: Skipping replication start — connectionState=$cs '
          '(not connected or connectedButNetworkError)',
        );
      }
    } on NetworkFailure catch (e) {
      // Connection closed or network failure during replication start
      _log.fine('Network failure during replication start: $e');

      // Notify health monitoring about network degradation
      notifyNetworkDegraded.call();

      // No previous replication found - just stay in offline mode without rethrowing
      _proxyController.setRetryState(
        "Network failure. No previous replication found. Will sync when connection is restored.",
      );
    } on CouchDbException catch (e) {
      if (e.statusCode == .unauthorized) {
        // A 401 here means the CouchDB session cookie expired while the app
        // was backgrounded (CouchDB default session timeout is 10 minutes).
        //
        // Recovery strategy:
        //   1. Call notifyNetworkDegraded() so health monitoring knows it must
        //      act on the next tick (within 5 s).
        //   2. Leave _proxyController in the 'waitingForNetwork' state so the
        //      UI shows the correct indicator.
        //   3. In OfflineFirstServer.resume(), the _networkDegraded flag that
        //      notifyNetworkDegraded() sets prevents the premature transition
        //      to normalOnline — state stays normalOffline.
        //   4. Health monitoring fires, detects the expired session
        //      (userCtx.name == null), calls _attemptRelogin().
        //   5. _attemptRelogin() sees prev == normalOffline → calls onBackOnline()
        //      → invokeRecoveryCallbacks() → _startContinuousReplication() again
        //      → this time with a fresh session cookie → replication starts.
        //
        // Without this catch the exception propagated to invokeRecoveryCallbacks
        // which silently swallowed it ("Recovery callback N failed"), health
        // monitoring was never informed, and replication stayed broken until the
        // user manually paused and resumed the app a second time.
        _log.info(
          '$dbname: Got 401 during replication start — session likely expired. '
          'Notifying health monitoring to re-login.',
        );
        notifyNetworkDegraded.call();
        _proxyController.setRetryState(
          "Session expired. Will sync after re-login.",
        );
      } else {
        _log.warning('$dbname: CouchDbException during replication start: $e');
        rethrow;
      }
    }
  }

  @override
  Future<DatabaseInfo?> info() {
    return localDb.info();
  }

  @override
  Stream<ChangesResult> changes({
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
    return localDb.changes(
      docIds: docIds,
      descending: descending,
      feedmode: feedmode,
      heartbeat: heartbeat,
      includeDocs: includeDocs,
      attachments: attachments,
      attEncodingInfo: attEncodingInfo,
      lastEventId: lastEventId,
      limit: limit,
      since: since,
      styleAllDocs: styleAllDocs,
      timeout: timeout,
      seqInterval: seqInterval,
    );
  }

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
    return localDb.changesRaw(
      docIds: docIds,
      descending: descending,
      feedmode: feedmode,
      heartbeat: heartbeat,
      includeDocs: includeDocs,
      attachments: attachments,
      attEncodingInfo: attEncodingInfo,
      lastEventId: lastEventId,
      limit: limit,
      since: since,
      styleAllDocs: styleAllDocs,
      timeout: timeout,
      seqInterval: seqInterval,
    );
  }

  @override
  Future<Map<String, dynamic>?> getRaw(
    String docid, {
    String? rev,
    bool revs = false,
    bool revsInfo = false,
    bool attachments = false,
  }) {
    return localDb.getRaw(
      docid,
      rev: rev,
      revs: revs,
      revsInfo: revsInfo,
      attachments: attachments,
    );
  }

  @override
  Future<List<OpenRevsResult>?> getOpenRevs(
    String docid, {
    List<String>? revisions,
    bool revs = false,
  }) {
    return localDb.getOpenRevs(docid, revisions: revisions, revs: revs);
  }

  @override
  Future<Map<String, dynamic>> putRaw(Map<String, dynamic> doc) {
    return localDb.putRaw(doc);
  }

  @override
  Future<Map<String, dynamic>> postRaw(Map<String, dynamic> doc) {
    return localDb.postRaw(doc);
  }

  @override
  Future<String> remove(String docid, String rev) {
    return localDb.remove(docid, rev);
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
  }) {
    return localDb.allDocs(
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
  }) {
    return localDb.query(
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
  }

  @override
  Future<String> saveAttachment(
    String docId,
    String rev,
    String attachmentName,
    Uint8List data, {
    String contentType = 'application/octet-stream',
  }) {
    return localDb.saveAttachment(
      docId,
      rev,
      attachmentName,
      data,
      contentType: contentType,
    );
  }

  @override
  Future<Uint8List?> getAttachment(
    String docId,
    String attachmentName, {
    String? rev,
  }) {
    return localDb.getAttachment(docId, attachmentName, rev: rev);
  }

  @override
  Future<String?> getAttachmentAsReadonlyFile(
    String docId,
    String attachmentName,
  ) {
    return localDb.getAttachmentAsReadonlyFile(docId, attachmentName);
  }

  @override
  Future<String> deleteAttachment(
    String docId,
    String rev,
    String attachmentName,
  ) {
    return localDb.deleteAttachment(docId, rev, attachmentName);
  }

  @override
  Future<void> startCompaction() {
    return localDb.startCompaction();
  }

  @override
  Future<bool?> isCompactionRunning() {
    return localDb.isCompactionRunning();
  }

  @override
  Future<Map<String, RevsDiffEntry>> revsDiff(Map<String, List<String>> revs) {
    return localDb.revsDiff(revs);
  }

  @override
  Future<List<BulkDocsResult>> bulkDocsRaw(
    List<String> docs, {
    bool newEdits = true,
  }) {
    return localDb.bulkDocsRaw(docs, newEdits: newEdits);
  }

  @override
  Future<bool> up() {
    return Future.value(true);
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
  }) {
    return localDb.getLocalDocuments(
      conflicts: conflicts,
      descending: descending,
      endkey: endkey,
      endkeyDocid: endkeyDocid,
      includeDocs: includeDocs,
      inclusiveEnd: inclusiveEnd,
      key: key,
      keys: keys,
      limit: limit,
      skip: skip,
      startkey: startkey,
      startkeyDocid: startkeyDocid,
      updateSeq: updateSeq,
    );
  }

  @override
  Future<String?> createIndex({
    required IndexDefinition index,
    String? ddoc,
    String? name,
    String type = 'json',
    bool? partitioned,
  }) {
    return localDb.createIndex(
      index: index,
      ddoc: ddoc,
      name: name,
      type: type,
      partitioned: partitioned,
    );
  }

  @override
  Future<bool> deleteIndex({
    required String designDoc,
    required String name,
    String type = 'json',
  }) {
    return localDb.deleteIndex(designDoc: designDoc, name: name, type: type);
  }

  @override
  Future<IndexResultList> getIndexes() {
    return localDb.getIndexes();
  }

  /// Checks migration state and executes migration if needed (only on serverDb when online)
  Future<void> _checkAndExecuteMigration() async {
    if (migration == null) {
      return;
    }

    if (serverDb.connectionState.value != DartCouchConnectionState.connected) {
      _log.fine('$dbname: Cannot check migration, server is offline');
      return;
    }

    try {
      // Get or create the server database
      // Note: We try to access the database directly instead of listing all databases
      // because non-admin users don't have permission to list all databases
      HttpDartCouchDb db;
      try {
        // Try to get the database first (works for non-admin users)
        final existingDb = await serverDb.db(dbname);
        if (existingDb != null) {
          db = existingDb;
        } else {
          // Database doesn't exist, try to create it
          db = await serverDb.createDatabase(dbname) as HttpDartCouchDb;
        }
      } on Exception catch (e) {
        // Database might have been created by another process
        if (e.toString().contains('file_exists') ||
            e.toString().contains('precondition')) {
          _log.fine(
            '$dbname already exists on server, using existing database',
          );
          db = (await serverDb.db(dbname))!;
        } else {
          rethrow;
        }
      }

      // Check migration state on serverDb
      final status = await migration!.checkMigrationState(db);

      switch (status) {
        case MigrationStatus.tooOld:
          _log.info(
            '$dbname: Migration needed, executing migration on serverDb',
          );
          migrationState.value = MigrationStatus.tooOld;
          try {
            // Check if disposed before running migration
            if (_isDisposed) {
              _log.fine(
                '$dbname: Database disposed before migration execution',
              );
              return;
            }

            await migration!.migrate(db);
            _log.info('$dbname: Migration completed successfully');

            // Migration succeeded, state will be verified after replication
          } catch (e) {
            _log.severe(
              '$dbname: Migration execution failed: $e, will retry when connection is restored',
            );
            // Don't mark as executed - allow retry on next connection
            // State remains tooOld so migration will be retried
          }
          // Note: migrationState will be set to matched after replication verifies
          break;
        case MigrationStatus.matched:
          _log.fine('$dbname: Migration state matched, no migration needed');
          migrationState.value = MigrationStatus.matched;
          break;
        case MigrationStatus.tooNew:
          _log.warning(
            '$dbname: Migration state too new, software needs update',
          );
          migrationState.value = MigrationStatus.tooNew;
          break;
      }
    } catch (e, stackTrace) {
      _log.severe('$dbname: Error during migration check: $e', e, stackTrace);
      // Don't rethrow - allow replication to proceed
    }
  }

  /// Checks migration state after replication to update migrationState to matched
  Future<void> _checkMigrationAfterReplication() async {
    if (migration == null) {
      return;
    }

    _log.info(
      '$dbname: Replication reached sync state, checking migration on localDb',
    );
    if (_isDisposed) {
      _log.fine('$dbname: Database disposed, skipping migration state check');
      return;
    }

    try {
      final status = await migration!.checkMigrationState(localDb);
      if (status != migrationState.value) {
        _log.info('$dbname: Migration state updated to $status');
        migrationState.value = status;
      }
    } catch (e, stackTrace) {
      _log.severe('$dbname: Error checking migration state: $e', e, stackTrace);
    }
  }

  @override
  Future<Map<String, dynamic>> bulkGetRaw(
    BulkGetRequest request, {
    bool revs = false,
    bool attachments = false,
    void Function(int bytes)? onBytesReceived,
  }) {
    return localDb.bulkGetRaw(
      request,
      revs: revs,
      attachments: attachments,
      onBytesReceived: onBytesReceived,
    );
  }

  @override
  Stream<BulkGetMultipartResult> bulkGetMultipart(
    BulkGetRequest request, {
    bool revs = false,
    void Function(int bytes)? onBytesReceived,
  }) {
    return localDb.bulkGetMultipart(
      request,
      revs: revs,
      onBytesReceived: onBytesReceived,
    );
  }

  @override
  Future<List<BulkDocsResult>> bulkDocsFromMultipart(
    List<BulkGetMultipartSuccess> docs, {
    bool newEdits = false,
  }) {
    return localDb.bulkDocsFromMultipart(docs, newEdits: newEdits);
  }
}

class _ProxyReplicationController implements ReplicationController {
  ReplicationController? _delegate;
  final DcValueNotifier<ReplicationProgress> _progressNotifier = DcValueNotifier(
    ReplicationProgress(
      state: ReplicationState.initializing,
      docsInNeedOfReplication: 0,
    ),
  );

  @override
  DcValueListenable<ReplicationProgress> get progress => _progressNotifier;

  Future<void> setDelegate(ReplicationController controller) async {
    await _stopDelegate();
    if (_delegate != null) {
      _delegate!.progress.removeListener(_onDelegateProgress);
    }
    _delegate = controller;
    _delegate!.progress.addListener(_onDelegateProgress);
    _onDelegateProgress();
  }

  Future<void> clearDelegate() async {
    await _stopDelegate(updateState: true);
  }

  Future<void> _stopDelegate({bool updateState = false}) async {
    final delegate = _delegate;
    if (delegate == null) {
      if (updateState) {
        _progressNotifier.value = ReplicationProgress(
          state: ReplicationState.terminated,
          targetReachable: false,
          docsInNeedOfReplication: 0,
        );
      }
      return;
    }

    delegate.progress.removeListener(_onDelegateProgress);
    _delegate = null;
    await delegate.stop();

    if (updateState) {
      _progressNotifier.value = ReplicationProgress(
        state: ReplicationState.terminated,
        targetReachable: false,
      );
    }
  }

  void _onDelegateProgress() {
    if (_delegate != null) {
      _progressNotifier.value = _delegate!.progress.value;
    }
  }

  void setRetryState(String message) {
    _progressNotifier.value = ReplicationProgress(
      state: ReplicationState.waitingForNetwork,
      targetReachable: false,
      docsInNeedOfReplication: 0,
      message: message,
    );
  }

  @override
  void pause() => _delegate?.pause();

  @override
  void resume() => _delegate?.resume();

  @override
  Future<void> stop() async {
    await _stopDelegate();
    _progressNotifier.value = ReplicationProgress(
      state: ReplicationState.terminated,
      docsInNeedOfReplication: 0,
    );
  }
}
