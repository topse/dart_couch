import 'dart:async';
import 'dart:convert';

import 'platform/io_shim.dart';

import 'package:async_queue/async_queue.dart';
import 'package:logging/logging.dart';
import 'package:mutex/mutex.dart';

import 'dart_couch_connection_state.dart';
import 'dart_couch_server.dart';
import 'database_migration.dart';
import 'dart_couch_db.dart';
import 'http_dart_couch_server.dart';

import 'value_notifier.dart';

import 'package:crypto/crypto.dart';

import 'package:dart_mappable/dart_mappable.dart';

import 'api_result.dart';
import 'health_monitoring_mixin.dart';
import 'local_dart_couch_db.dart';
import 'local_dart_couch_server.dart';
import 'messages/couch_db_status_codes.dart';
import 'messages/couch_document_base.dart';
import 'messages/login_result.dart';
import 'messages/session_result.dart';
import 'offline_first_db.dart';
import 'offline_first_server_state.dart';
import 'replication_mixin_interface.dart';

part 'offline_first_server.mapper.dart';

final Logger _log = Logger('dart_couch-offline_server');

String _credentialHash(String input) {
  return sha256.convert(utf8.encode(input)).toString();
}

@MappableClass(discriminatorValue: '!offline_first_server_db_updates_state')
class OfflineFirstServerDbUpdatesState extends CouchDocumentBase
    with OfflineFirstServerDbUpdatesStateMappable {
  @MappableField()
  final String lastSeq;

  OfflineFirstServerDbUpdatesState({
    required this.lastSeq,
    required super.id,
    super.rev,
    super.attachments,
    super.revisions,
    super.revsInfo,
    super.deleted,
    super.unmappedProps,
  });

  static final fromMap = OfflineFirstServerDbUpdatesStateMapper.fromMap;
  static final fromJson = OfflineFirstServerDbUpdatesStateMapper.fromJson;

  static String makeId(Uri url) {
    final serverpath =
        '${url.host}${url.path.replaceAll('/', '_').replaceAll('\\', '_')}';

    return 'db_updates_state_$serverpath';
  }
}

@MappableClass(discriminatorValue: '!offline_first_server_login_state')
class OfflineFirstServerLoginState extends CouchDocumentBase
    with OfflineFirstServerLoginStateMappable {
  @MappableField()
  final String hashedUsername;
  @MappableField()
  final String hashedPassword;

  @MappableField()
  final bool canAllDbs;

  OfflineFirstServerLoginState({
    required this.hashedUsername,
    required this.hashedPassword,
    required this.canAllDbs,
    required super.id,
    super.rev,
    super.attachments,
    super.revisions,
    super.revsInfo,
    super.deleted,
    super.unmappedProps,
  });

  factory OfflineFirstServerLoginState.make(
    String httpDbUrl,
    String username,
    String password,
    bool canAllDbs,
    String? oldRev,
  ) {
    return OfflineFirstServerLoginState(
      id: makeId(httpDbUrl, username, password),
      rev: oldRev,
      hashedUsername: _credentialHash(username),
      hashedPassword: _credentialHash(password),
      canAllDbs: canAllDbs,
    );
  }
  static final fromMap = OfflineFirstServerLoginStateMapper.fromMap;
  static final fromJson = OfflineFirstServerLoginStateMapper.fromJson;

  static String makeId(String httpDbUrl, String username, String password) {
    final url = Uri.parse(httpDbUrl);
    final serverpath =
        "$username${url.host}${url.path.replaceAll('/', '_').replaceAll('\\', '_')}";

    return 'loginstate_$serverpath';
  }
}

/// **Database Recreation Detection via Markers (Deterministic)**
///
/// Each database has a marker document (`_local/db_sync_marker`) containing
/// a unique `databaseUuid`. When a database is deleted and recreated, it gets
/// a NEW UUID. By comparing UUIDs, we can RELIABLY detect recreation.
///
/// **Why markers instead of heuristics:**
/// - ✅ Deterministic: UUID mismatch = recreation detected (100% reliable)
/// - ✅ No race conditions: UUIDs don't change during normal operation
/// - ✅ No arbitrary thresholds: No "if seq < 10" guessing logic
/// - ✅ CouchDB-style: Follows replication protocol principles
///
/// **CRITICAL: NO HEURISTICS**
/// This project must NEVER use heuristics (thresholds, "likely" logic) for
/// database state detection. All checks must be deterministic. Heuristics
/// cause sporadic failures and are unreliable in production.
///
/// See: MEMORY.md for project guidelines on deterministic behavior
@MappableClass(discriminatorValue: '!db_sync_marker')
class DatabaseSyncMarker extends CouchDocumentBase
    with DatabaseSyncMarkerMappable {
  /// UUID of the application instance that created this database
  @MappableField()
  final String instanceUuid;

  /// UUID unique to THIS incarnation of the database.
  /// Changes every time database is deleted and recreated.
  /// Comparing this across local/remote detects recreation deterministically.
  @MappableField()
  final String databaseUuid;

  /// When this database incarnation was created
  @MappableField()
  final DateTime createdAt;

  /// Was it created locally or remotely?
  @MappableField()
  final String createdBy; // 'local' | 'remote' | 'discovered' | 'recovered'

  /// List of all instance UUIDs that have ever opened this database
  /// Used for coordinated deletion - database is only truly deleted when empty
  @MappableField()
  final List<String> activeInstances;

  /// If true, database is marked for deletion
  /// Instances should unregister themselves and delete their local copy
  @MappableField()
  final bool tombstone;

  DatabaseSyncMarker({
    required this.instanceUuid,
    required this.databaseUuid,
    required this.createdAt,
    required this.createdBy,
    List<String>? activeInstances,
    this.tombstone = false,
    super.id = '_local/db_sync_marker',
    super.rev,
    super.attachments,
    super.revisions,
    super.revsInfo,
    super.deleted,
    super.unmappedProps,
  }) : activeInstances = activeInstances ?? [];

  static final fromMap = DatabaseSyncMarkerMapper.fromMap;
  static final fromJson = DatabaseSyncMarkerMapper.fromJson;
}

@MappableClass(discriminatorValue: '!instance_state')
class InstanceState extends CouchDocumentBase with InstanceStateMappable {
  @MappableField()
  final String instanceUuid;

  /// Track databases with pending marker repairs (dbName -> databaseUuid)
  /// Only contains DBs with failed marker writes - cleared once successful
  @MappableField()
  final Map<String, String> pendingMarkerRepairs;

  InstanceState({
    required this.instanceUuid,
    required this.pendingMarkerRepairs,
    required super.id,
    super.rev,
    super.attachments,
    super.revisions,
    super.revsInfo,
    super.deleted,
    super.unmappedProps,
  });

  static final fromMap = InstanceStateMapper.fromMap;
  static final fromJson = InstanceStateMapper.fromJson;

  static String makeId(String httpDbUrl, String username, String password) {
    final url = Uri.parse(httpDbUrl);
    final serverpath =
        "$username${url.host}${url.path.replaceAll('/', '_').replaceAll('\\', '_')}";

    return 'instance_state_$serverpath';
  }
}

/// Conflict resolution strategy when database recreations are detected
/// (different UUIDs for same database name)
enum ExistingDatabasesSyncStrategie {
  /// Remote/server version always wins - local is deleted and recreated. Only remote documents are preserved.
  serverAlwaysWins,

  /// Local version always wins - remote is deleted and recreated. Only local documents are preserved.
  localAlwaysWins,

  /// Merge both versions: replicate local→remote first, then adopt remote metadata
  /// This preserves all documents from both incarnations
  merge,
}

/// Offline-first façade that combines a [LocalDartCouchServer] (SQLite) with an
/// [HttpDartCouchServer] (CouchDB) into a single server with two-tier synchronisation.
///
/// ## Two separate sync concerns
///
/// **1. Database-existence sync** (`_syncLocalAndRemoteDatabases` / `_syncSingleDatabase`)
/// Reconciles which databases *exist* on both sides using [DatabaseSyncMarker]
/// documents stored at `_local/db_sync_marker` inside each database.  This is
/// NOT document replication — it does not transfer user data.  It handles:
/// - Databases created offline that must be propagated to the server.
/// - Databases deleted offline (tombstoned) that must be cleaned up everywhere.
/// - Databases deleted/recreated on the server (detected via UUID mismatch).
///
/// **2. Document-content replication** (started by [OfflineFirstDb.init])
/// Each database pair runs a bidirectional CouchDB replication via
/// [CouchReplicationMixin].  This is started by the recovery callbacks
/// registered at `db()` time and restarted after every reconnect.
///
/// ## Lifecycle
///
/// ```
/// login()
///   │
///   ├─ authenticate with CouchDB
///   ├─ load / create local SQLite file
///   ├─ _syncLocalAndRemoteDatabases()   ← existence sync
///   ├─ _startDbUpdatesStream()          ← watch future existence changes
///   └─ invokeRecoveryCallbacks()        ← start content replication per DB
/// ```
///
/// On network loss the health monitor calls [notifyNetworkDegraded]; on
/// recovery it calls [onBackOnline] which repeats the last three steps.
///
/// ## Tombstone mechanism for offline deletion
///
/// Calling [deleteDatabase] while offline does NOT delete the local database
/// immediately.  Instead it sets `tombstone: true` in the local marker.  On
/// reconnect, `_syncSingleDatabase` detects the local tombstone, unregisters
/// this instance from the remote marker, and — if no other instances remain —
/// deletes the remote database and then the local database.
///
/// ## Instance tracking
///
/// Every [OfflineFirstServer] has a unique [_instanceUuid] (stored in the
/// local SQLite file).  When a database is opened via [db], the instance
/// registers itself in the remote marker's `activeInstances` list.  The
/// database is only deleted from the server when the last instance unregisters.
class OfflineFirstServer extends DartCouchServer with HealthMonitoring {
  String? url;
  String? _username;
  String? _password;

  @override
  Directory? localDirectory;

  HttpDartCouchServer httpServer = HttpDartCouchServer();
  LocalDartCouchServer? localServer;

  /// UUID unique to this instance (local database file)
  String? _instanceUuid;

  /// Strategy for resolving database recreation conflicts
  final ExistingDatabasesSyncStrategie existingDatabaseSyncingStrategy;

  @override
  DcValueNotifier<OfflineFirstServerState> state =
      DcValueNotifier<OfflineFirstServerState>(.unititialized);

  /// Stream subscription for _db_updates
  StreamSubscription<Map<String, dynamic>>? _dbUpdatesSubscription;

  /// Completer that signals when replay is complete
  Completer<void>? _replayCompleter;

  /// Flag to indicate disposal is in progress
  bool _isDisposing = false;

  /// Flag to indicate app is paused (in background/standby)
  bool _isPaused = false;

  /// Counter for pending _handleDbUpdate callbacks
  int _pendingDbUpdateCallbacks = 0;

  /// Completer that signals when all pending _handleDbUpdate callbacks are done
  Completer<void>? _pendingDbUpdateCompleter;

  /// Mutex to serialize login, logout, and dispose operations
  final Mutex _lifecycleMutex = Mutex();

  /// Mutex to serialize database access and creation
  final Mutex _dbAccessMutex = Mutex();

  final Mutex _m = Mutex();

  DatabaseMigration? migration;

  final DocumentReplicationConflictResolver documentReplicationConflictResolver;

  // TODO: it seems the DocumentReplicationConflictResolver is never used, maybe remove it?
  OfflineFirstServer({
    this.migration,
    this.existingDatabaseSyncingStrategy = ExistingDatabasesSyncStrategie.merge,
    DocumentReplicationConflictResolver? documentReplicationConflictResolver,
  }) : documentReplicationConflictResolver =
           documentReplicationConflictResolver ??
           DefaultConflictResolver.instance;

  bool? _canAllDbs;

  /// Gets the allDbs permission from cache or persisted login state.
  /// Returns null if no login state exists.
  Future<bool?> _getCanAllDbs() async {
    if (_canAllDbs != null) {
      return _canAllDbs;
    }

    if (url == null || _username == null || _password == null) {
      return null;
    }

    final loginState = await _loginStateGet(url!, _username!, _password!);
    if (loginState != null) {
      _canAllDbs = loginState.canAllDbs;
      return _canAllDbs;
    }

    return null;
  }

  /// Checks if the current user has permission to query all databases.
  /// Stores the result in _canAllDbs and returns it.
  Future<bool> _checkAndStoreAllDbsPermission() async {
    try {
      await httpServer.allDatabasesNames;
      _canAllDbs = true;
      _log.fine('User has permission to query all databases');
      return true;
    } on CouchDbException catch (e) {
      if (e.statusCode == CouchDbStatusCodes.unauthorized) {
        _canAllDbs = false;
        _log.fine('User does NOT have permission to query all databases');
        return false;
      }
      rethrow;
    } catch (e) {
      // Network or other errors - assume no permission to be safe
      _log.warning('Error checking allDbs permission: $e');
      _canAllDbs = false;
      return false;
    }
  }

  Future<OfflineFirstServerLoginState?> _loginStateGet(
    String url,
    String username,
    String password,
  ) async {
    final docid = OfflineFirstServerLoginState.makeId(url, username, password);

    final localDb = (await localServer!.db('_server_state'))!;
    return (await localDb.get(docid)) as OfflineFirstServerLoginState?;
  }

  Future<void> _loginStateRemove(
    final OfflineFirstServerLoginState loginState,
  ) async {
    final localDb = (await localServer!.db('_server_state'))!;
    await localDb.remove(loginState.id!, loginState.rev!);
  }

  Future<void> _loginStatePut(
    final OfflineFirstServerLoginState loginState,
  ) async {
    final localDb = (await localServer!.db('_server_state'))!;
    await localDb.put(loginState);
  }

  Future<OfflineFirstServerDbUpdatesState?> _dbUpdatesStateGet(Uri uri) async {
    final docid = OfflineFirstServerDbUpdatesState.makeId(uri);
    final localDb = (await localServer!.db('_server_state'))!;
    return (await localDb.get(docid)) as OfflineFirstServerDbUpdatesState?;
  }

  Future<void> _dbUpdatesStateRemove() async {
    // Capture uri synchronously before any await so logout cannot race it.
    final uri = httpServer.uri;
    if (uri == null) return;
    final updatesState = await _dbUpdatesStateGet(uri);
    if (updatesState != null) {
      final localDb = (await localServer!.db('_server_state'))!;
      await localDb.remove(updatesState.id!, updatesState.rev!);
    }
  }

  Future<void> _dbUpdatesStatePut(
    final OfflineFirstServerDbUpdatesState updatesState,
  ) async {
    final localDb = (await localServer!.db('_server_state'))!;
    await localDb.put(updatesState);
  }

  Future<String?> _getLastDbUpdateSeq() {
    // Capture uri synchronously before entering the mutex so logout cannot
    // race between the mutex wait and the first use of uri.
    final uri = httpServer.uri;
    if (uri == null) return Future.value(null);
    return _m.protect<String?>(() async {
      final updatesState = await _dbUpdatesStateGet(uri);
      if (updatesState != null) {
        return updatesState.lastSeq;
      } else {
        return null;
      }
    });
  }

  Future<void> _setLastDbUpdateSeq(final String seq) {
    // Capture uri synchronously before entering the mutex so logout cannot
    // race between the mutex wait (a yield point) and the first use of uri.
    final uri = httpServer.uri;
    if (uri == null) return Future.value();
    return _m.protect(() async {
      _log.info('Setting last _db_updates seq to: $seq');
      final updatesState = await _dbUpdatesStateGet(uri);
      final newState = updatesState != null
          ? updatesState.copyWith(lastSeq: seq.toString())
          : OfflineFirstServerDbUpdatesState(
              id: OfflineFirstServerDbUpdatesState.makeId(uri),
              lastSeq: seq.toString(),
            );
      await _dbUpdatesStatePut(newState);
    });
  }

  // ========== Instance State Management ==========

  Future<InstanceState?> _instanceStateGet() async {
    if (url == null || _username == null || _password == null) return null;

    final docid = InstanceState.makeId(url!, _username!, _password!);
    final localDb = (await localServer!.db('_server_state'))!;
    return (await localDb.get(docid)) as InstanceState?;
  }

  Future<void> _instanceStatePut(InstanceState instanceState) async {
    final localDb = (await localServer!.db('_server_state'))!;
    await localDb.put(instanceState);
  }

  /// Get or create the instance UUID for this local database file
  Future<String> _getOrCreateInstanceUuid() async {
    if (_instanceUuid != null) return _instanceUuid!;

    var instanceState = await _instanceStateGet();
    if (instanceState != null) {
      _instanceUuid = instanceState.instanceUuid;
      _log.info('Loaded existing instance UUID: $_instanceUuid');
    } else {
      // Generate new instance UUID
      _instanceUuid = _generateUuid();
      instanceState = InstanceState(
        instanceUuid: _instanceUuid!,
        pendingMarkerRepairs: {},
        id: InstanceState.makeId(url!, _username!, _password!),
      );
      await _instanceStatePut(instanceState);
      _log.info('Generated new instance UUID: $_instanceUuid');
    }
    return _instanceUuid!;
  }

  /// Simple UUID generation (v4-like)
  String _generateUuid() {
    final random =
        DateTime.now().millisecondsSinceEpoch.toString() +
        DateTime.now().microsecondsSinceEpoch.toString();
    return sha256.convert(utf8.encode(random)).toString().substring(0, 32);
  }

  /// Scan all local databases at startup and repair missing markers
  Future<void> _scanAndRepairLocalMarkers() async {
    if (localServer == null) return;

    _log.info('Scanning local databases for missing markers');

    try {
      final allLocalDbs = await localServer!.allDatabasesNames;

      for (final dbName in allLocalDbs) {
        // Skip _server_state and other system databases
        if (dbName.startsWith('_')) continue;

        final localDb = await localServer!.db(dbName);
        if (localDb == null) continue;

        // Check if local marker exists
        final localMarker = await _readMarker(localDb);

        if (localMarker == null) {
          // No local marker - attempt repair
          _log.warning(
            'Database $dbName has no local marker - attempting repair',
          );

          // Try to get from remote if online
          if (state.value == .normalOnline) {
            try {
              final remoteDb = await httpServer.db(dbName);
              final remoteMarker = await _readMarker(remoteDb);

              if (remoteMarker != null) {
                // Copy remote marker to local
                final success = await _tryWriteMarker(
                  localDb,
                  remoteMarker.databaseUuid,
                  'remote',
                );

                if (success) {
                  _log.info('Repaired local marker for $dbName from remote');
                } else {
                  // Failed to write - add to pending repairs
                  await _addToPendingMarkerRepairs(
                    dbName,
                    remoteMarker.databaseUuid,
                  );
                  _log.warning(
                    'Failed to repair marker for $dbName - added to pending',
                  );
                }
              } else {
                // No remote marker either - generate new UUID and add to pending
                final newUuid = _generateUuid();
                await _addToPendingMarkerRepairs(dbName, newUuid);
                _log.warning(
                  'No markers found for $dbName - added to pending with new UUID',
                );
              }
            } catch (e) {
              _log.warning('Error checking remote marker for $dbName: $e');
              // Offline or error - generate new UUID and add to pending
              final newUuid = _generateUuid();
              await _addToPendingMarkerRepairs(dbName, newUuid);
            }
          } else {
            // Offline - generate new UUID and add to pending
            final newUuid = _generateUuid();
            await _addToPendingMarkerRepairs(dbName, newUuid);
            _log.info(
              'Offline: added $dbName to pending repairs with new UUID',
            );
          }
        } else {
          // Has local marker - check if it's in pending repairs
          final pendingUuid = await _getPendingMarkerRepair(dbName);
          if (pendingUuid != null && localMarker.databaseUuid == pendingUuid) {
            // Marker matches pending - remove from pending
            await _removeFromPendingMarkerRepairs(dbName);
            _log.fine('Removed $dbName from pending - marker now exists');
          }
        }
      }

      _log.info('Completed local database marker scan');
    } catch (e) {
      _log.severe('Error during marker scan: $e');
    }
  }

  // ========== Pending Marker Repairs Management ==========

  /// Add database to pending marker repairs
  Future<void> _addToPendingMarkerRepairs(
    String dbName,
    String databaseUuid,
  ) async {
    final instanceState = await _instanceStateGet();
    if (instanceState == null) {
      _log.warning('Cannot add to pending repairs - no instance state');
      return;
    }

    final updated = instanceState.copyWith(
      pendingMarkerRepairs: {
        ...instanceState.pendingMarkerRepairs,
        dbName: databaseUuid,
      },
    );
    await _instanceStatePut(updated);
  }

  /// Get databaseUuid for a pending repair, or null if not pending
  Future<String?> _getPendingMarkerRepair(String dbName) async {
    final instanceState = await _instanceStateGet();
    return instanceState?.pendingMarkerRepairs[dbName];
  }

  /// Remove database from pending marker repairs
  Future<void> _removeFromPendingMarkerRepairs(String dbName) async {
    final instanceState = await _instanceStateGet();
    if (instanceState == null) return;

    final updated = Map<String, String>.from(
      instanceState.pendingMarkerRepairs,
    );
    updated.remove(dbName);

    await _instanceStatePut(
      instanceState.copyWith(pendingMarkerRepairs: updated),
    );
  }

  // ========== Marker Management ==========

  /// Try to write a marker document (returns success status)
  ///
  /// For remote markers, initializes activeInstances with this instance.
  /// For local markers, activeInstances is empty (not used locally).
  Future<bool> _tryWriteMarker(
    DartCouchDb? db,
    String databaseUuid,
    String createdBy, {
    bool isRemote = false,
  }) async {
    if (db == null) return false;

    try {
      final marker = DatabaseSyncMarker(
        instanceUuid: _instanceUuid!,
        databaseUuid: databaseUuid,
        createdAt: DateTime.now(),
        createdBy: createdBy,
        activeInstances: isRemote ? [_instanceUuid!] : [],
        tombstone: false,
      );
      await db.put(marker);
      _log.fine('Wrote marker to ${db.dbname}');
      return true;
    } catch (e) {
      _log.warning('Failed to write marker to ${db.dbname}: $e');
      return false;
    }
  }

  /// Read marker from a database
  Future<DatabaseSyncMarker?> _readMarker(DartCouchDb? db) async {
    if (db == null) return null;

    try {
      final doc = await db.get('_local/db_sync_marker');
      return doc as DatabaseSyncMarker?;
    } on NetworkFailure {
      rethrow;
    } catch (e) {
      return null;
    }
  }

  /// Check if a database has a valid marker (from any instance)
  Future<bool> _hasValidMarker(String dbName) async {
    try {
      final localDb = await localServer?.db(dbName);
      final localMarker = await _readMarker(localDb);
      if (localMarker != null) return true;

      final remoteDb = await httpServer.db(dbName);
      final remoteMarker = await _readMarker(remoteDb);
      return remoteMarker != null;
    } catch (e) {
      return false;
    }
  }

  /// Update remote marker document with retry logic to handle concurrent updates
  ///
  /// Multiple instances may try to update the shared marker simultaneously,
  /// causing 409 conflicts. This method retries with exponential backoff.
  ///
  /// The modifier function receives the current marker and should return the updated marker.
  Future<DatabaseSyncMarker?> _updateRemoteMarker(
    String dbName,
    DatabaseSyncMarker Function(DatabaseSyncMarker marker) modify,
  ) async {
    const maxRetries = 5;

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        // Always get fresh copy with current _rev
        final remoteDb = await httpServer.db(dbName);
        if (remoteDb == null) {
          _log.warning('Remote database $dbName not found for marker update');
          return null;
        }

        final marker = await _readMarker(remoteDb);
        if (marker == null) {
          _log.warning('Remote marker not found for database $dbName');
          return null;
        }

        // Apply modification to get new marker
        final updated = modify(marker);

        // Try to save with current _rev from original marker
        final updatedWithRev = updated.copyWith(rev: marker.rev);
        await remoteDb.put(updatedWithRev);

        _log.fine('Updated remote marker for $dbName');
        return updatedWithRev;
      } catch (e) {
        // Check if it's a conflict (409) and we can retry
        if (e.toString().contains('409') && attempt < maxRetries - 1) {
          // Conflict: another instance updated it concurrently
          final backoff = Duration(milliseconds: 100 * (attempt + 1));
          _log.fine(
            'Marker update conflict for $dbName, retrying in ${backoff.inMilliseconds}ms... (attempt ${attempt + 1})',
          );
          await Future.delayed(backoff);
          continue;
        }

        // Give up or different error
        _log.warning('Failed to update remote marker for $dbName: $e');
        rethrow;
      }
    }

    throw Exception(
      'Failed to update marker for $dbName after $maxRetries retries',
    );
  }

  /// Register this instance as an active user of a database
  ///
  /// Only updates remote marker - local marker doesn't track active instances
  Future<void> _registerInstance(String dbName) async {
    if (state.value != .normalOnline) {
      // Can't register when offline
      return;
    }

    try {
      await _updateRemoteMarker(dbName, (marker) {
        final instances = List<String>.from(marker.activeInstances);
        if (!instances.contains(_instanceUuid)) {
          instances.add(_instanceUuid!);
          return marker.copyWith(activeInstances: instances);
        }
        return marker;
      });
      _log.fine('Registered instance $_instanceUuid for database $dbName');
    } catch (e) {
      _log.warning('Failed to register instance for $dbName: $e');
      // Non-critical - will work without registration, just affects deletion coordination
    }
  }

  /// Unregister this instance from a database and check if we should delete it
  ///
  /// Returns true if the database was deleted (this was the last instance)
  Future<bool> _unregisterInstance(String dbName) async {
    if (state.value != .normalOnline) {
      // Can't unregister when offline
      return false;
    }

    try {
      final updatedMarker = await _updateRemoteMarker(dbName, (marker) {
        final instances = List<String>.from(marker.activeInstances);
        instances.remove(_instanceUuid);
        return marker.copyWith(activeInstances: instances);
      });

      if (updatedMarker != null &&
          updatedMarker.tombstone &&
          updatedMarker.activeInstances.isEmpty) {
        _log.info(
          'Last instance unregistered from tombstoned database $dbName - deleting',
        );
        try {
          await httpServer.deleteDatabase(dbName);
          return true;
        } catch (e) {
          _log.warning('Failed to delete database $dbName: $e');
        }
      }

      return false;
    } catch (e) {
      _log.warning('Failed to unregister instance from database $dbName: $e');
      return false;
    }
  }

  /// Write missing remote markers for databases that need them
  Future<void> _writeAllMissingRemoteMarkers(
    InstanceState instanceState,
  ) async {
    for (final entry in instanceState.pendingMarkerRepairs.entries) {
      final dbName = entry.key;
      final databaseUuid = entry.value;

      try {
        // Check if remote database exists
        final remoteDb = await httpServer.db(dbName);
        if (remoteDb == null) {
          // Remote DB doesn't exist - will be created during sync
          continue;
        }

        // Check if marker already exists
        final existingMarker = await _readMarker(remoteDb);
        if (existingMarker != null) {
          // Marker exists - check local too
          final localDb = await localServer?.db(dbName);
          final localMarker = await _readMarker(localDb);
          if (localMarker != null) {
            // Both markers exist - remove from pending
            await _removeFromPendingMarkerRepairs(dbName);
          }
          _log.fine('Remote marker already exists for $dbName');
          continue;
        }

        // Write the marker
        final success = await _tryWriteMarker(remoteDb, databaseUuid, 'local');

        if (success) {
          // Check if local marker also exists now
          final localDb = await localServer?.db(dbName);
          final localMarker = await _readMarker(localDb);
          if (localMarker != null) {
            // Both markers present - remove from pending
            await _removeFromPendingMarkerRepairs(dbName);
          }
          _log.info('Successfully wrote missing remote marker for $dbName');
        }
      } catch (e) {
        _log.warning('Failed to write remote marker for $dbName: $e');
        // Continue with other databases
      }
    }
  }

  @override
  Future<LoginResult?> login(
    String url,
    String username,
    String password,
    Directory localDirectory,
  ) {
    return loginWithReloginFlag(
      url,
      username,
      password,
      localDirectory,
      isRelogin: false,
    );
  }

  @override
  Future<LoginResult?> loginWithReloginFlag(
    String url,
    String username,
    String password,
    Directory localDirectory, {
    required bool isRelogin,
  }) {
    return _lifecycleMutex.protect(() async {
      // State transition rule: tryingToConnect is ONLY used for initial login attempts
      // - From unititialized: First-time login
      // - From errorWrongCredentials: Retry with different credentials
      // Health monitoring reconnections use normalOffline -> normalOnline transitions
      if (state.value == .unititialized ||
          state.value == .errorWrongCredentials) {
        state.value = .tryingToConnect;
      }

      this.url = url;
      _username = username;
      _password = password;

      this.localDirectory = localDirectory;

      if (localServer == null ||
          localServer!.directory.path != localDirectory.path) {
        await localServer?.dispose();
        localServer = LocalDartCouchServer(this.localDirectory!);
      }
      assert(localServer != null);

      try {
        await localServer!.createDatabase('_server_state');
      } catch (e) {
        // database already exists
      }

      // Get or create instance UUID
      await _getOrCreateInstanceUuid();

      // Scan and repair missing markers at startup
      await _scanAndRepairLocalMarkers();

      // During relogin, only logout from HTTP server without changing state
      // During normal login, do full logout including state reset
      if (httpServer.connectionState.value ==
          DartCouchConnectionState.connected) {
        if (isRelogin) {
          // Just logout from HTTP server, preserve OfflineFirstServer state
          try {
            await httpServer.logout();
          } catch (e) {
            _log.warning('Error during relogin logout: $e');
          }
        } else {
          await _logoutInternal();
        }
      }

      // Question: under what circumstances do we use lastLoginResult vs. calling login again?
      LoginResult? res =
          httpServer.lastLoginResult != null &&
              httpServer.lastLoginResult?.statusCode == .ok
          ? httpServer.lastLoginResult
          : await httpServer.login(url, username, password);

      final loginStateDoc = await _loginStateGet(url, username, password);

      if (res == null) {
        // network error
        // check if a previous login was successful with given credentials
        if (loginStateDoc != null) {
          // previous login was successful
          // check credentials
          if (loginStateDoc.hashedUsername == _credentialHash(username) &&
              loginStateDoc.hashedPassword == _credentialHash(password)) {
            // credentials match
            // credentials were valid before, but not yet logged in due to network failure
            res = LoginResult(success: true, statusCode: CouchDbStatusCodes.ok);
            // State transition:
            // Since we have cached credentials, this is not a first-time login
            // Always transition to normalOffline when using cached credentials
            state.value = OfflineFirstServerState.normalOffline;
            startHealthMonitoring();
            return res;
          } else {
            // different credentials than last at successful login
            // take it as error, dont start retrying login
            state.value = OfflineFirstServerState.errorWrongCredentials;
            return LoginResult(statusCode: .unauthorized, success: false);
          }
        } else {
          // no previous successful login
          // report network error by returning null
          state.value =
              .unititialized; // Network error cant login. How to show this in GUI?
          return null;
        }
      } else if (res.success == false) {
        // login failed with HttpError

        if (res.statusCode == CouchDbStatusCodes.unauthorized) {
          // wrong credentials
          // report error
          state.value = OfflineFirstServerState.errorWrongCredentials;
          if (loginStateDoc != null) {
            // delete stored login state with wrong credentials
            await _loginStateRemove(loginStateDoc);
          }
          return res;
        }
        // Server error (not auth related) - if we had valid credentials before, keep trying
        if (loginStateDoc != null &&
            loginStateDoc.hashedUsername == _credentialHash(username) &&
            loginStateDoc.hashedPassword == _credentialHash(password)) {
          state.value =
              .normalOffline; // maybe normalTryingToConnect? Then our GUI may change to CircularProgressBar?
          startHealthMonitoring();
        } else {
          // First time login with these credentials failed with server error
          state.value = .unititialized;
        }
        return res;
      } else {
        // successful login
        // Check allDbs permission
        final canAllDbs = await _checkAndStoreAllDbsPermission();

        // store successful login result in local database "_server_state/..."
        await _loginStatePut(
          OfflineFirstServerLoginState.make(
            url,
            username,
            password,
            canAllDbs,
            loginStateDoc?.rev,
          ),
        );

        // Start health monitoring (but don't set normalOnline yet)
        startHealthMonitoring();

        // Only sync databases and start _db_updates stream if user has allDbs permission
        if (canAllDbs) {
          // Get Single _db_updates and merge result with replay log (server has last word!)
          // execute compacted log to create/delete databases as needed
          await _syncLocalAndRemoteDatabases();

          // Start listening to _db_updates stream first (to catch any events during replay/sync)
          await _startDbUpdatesStream();
        } else {
          _log.info(
            'User does not have allDbs permission - skipping database synchronization and _db_updates stream',
          );
        }

        // Only NOW set the state to normalOnline after all database setup is complete
        state.value = .normalOnline;

        return res;
      }
    });
  }

  /// Internal logout implementation without mutex (for use within mutex-protected methods)
  Future<void> _logoutInternal() async {
    // Unregister this instance from all databases
    if (state.value == OfflineFirstServerState.normalOnline) {
      _log.fine('Unregistering instance from ${_dbCache.length} databases');
      for (final dbName in _dbCache.keys.toList()) {
        try {
          await _unregisterInstance(dbName);
        } catch (e) {
          _log.warning('Error unregistering from database $dbName: $e');
        }
      }
    }

    stopHealthMonitoring();
    await _stopDbUpdatesStream();
    try {
      await httpServer.logout();
    } catch (e) {
      _log.warning('Error during logout: $e');
    }
    state.value = .unititialized;
    _canAllDbs = null; // Reset cached permission
    // Don't dispose localServer - keep it for reuse after logout
  }

  /// Logout from the server. The OfflineFirstServer object can be reused with login() afterwards.
  Future<void> logout() async {
    await _lifecycleMutex.protect(() async {
      await _logoutInternal();
    });
  }

  /// Permanently dispose of the OfflineFirstServer. Cannot be reused after calling this.
  @override
  Future<void> dispose() async {
    await _lifecycleMutex.protect(() async {
      _log.fine('OfflineFirstServer.dispose() START');
      _isDisposing = true;

      // Stop health monitoring and db_updates stream first, but keep HTTP connection alive
      stopHealthMonitoring();
      await _stopDbUpdatesStream();

      // Wait for any ongoing replay operations to complete
      if (_replayCompleter != null && !_replayCompleter!.isCompleted) {
        _log.fine('Waiting for replay operations to complete');
        await _replayCompleter!.future;
        _log.fine('Replay operations completed');
      }

      // Wait for any pending _handleDbUpdate callbacks to complete
      if (_pendingDbUpdateCallbacks > 0) {
        _log.fine(
          'Waiting for $_pendingDbUpdateCallbacks pending db update callbacks',
        );
        _pendingDbUpdateCompleter ??= Completer<void>();
        await _pendingDbUpdateCompleter!.future;
        _log.fine('All pending db update callbacks completed');
      }

      // Unregister this instance from all databases (needs HTTP connection)
      if (state.value == OfflineFirstServerState.normalOnline) {
        _log.fine('Unregistering instance from ${_dbCache.length} databases');
        for (final dbName in _dbCache.keys.toList()) {
          try {
            await _unregisterInstance(dbName);
          } catch (e) {
            _log.warning('Error unregistering from database $dbName: $e');
          }
        }
      }

      // Dispose all cached databases - this saves checkpoints
      _log.fine('Disposing ${_dbCache.length} cached databases');
      for (final db in _dbCache.values) {
        try {
          _log.fine('Disposing database ${db.dbname}');
          await db.dispose();
        } catch (e) {
          // Ignore errors disposing databases
          _log.warning("Error disposing database ${db.dbname}: $e");
        }
      }

      // Now logout and dispose HTTP server
      _log.fine('Logging out from HTTP server');
      try {
        await httpServer.logout();
        await httpServer.dispose();
      } catch (e) {
        _log.warning('Error during logout: $e');
      }
      state.value = OfflineFirstServerState.unititialized;
      _canAllDbs = null; // Reset cached permission

      // Dispose local server
      if (localServer != null) {
        _log.fine('Disposing LocalDartCouchServer');
        try {
          await localServer!.dispose();
        } catch (e) {
          _log.warning("Error during local server disposal in dispose: $e");
        }
        localServer = null;
      }

      _dbCache.clear();
      _log.fine('OfflineFirstServer.dispose() COMPLETE');
    });
  }

  /// Pause all activity when the app goes to background/standby.
  /// This stops health monitoring, database updates stream, and all replications
  /// to conserve battery on mobile devices.
  ///
  /// Call this when your app detects it's going to background (e.g., screen off on Android).
  /// The server preserves all state and can be resumed later with [resume()].
  ///
  /// **What gets stopped (completely, not just paused):**
  /// - Health monitoring timer (Timer.periodic cancelled)
  /// - _db_updates stream subscription (StreamSubscription cancelled)
  /// - All database replication controllers, which stops their:
  ///   - Changes feed streams (both local and remote)
  ///   - Heartbeat timers
  ///   - Retry timers
  ///   - Checkpoint writers
  ///   - Document processing
  /// - Migration change listeners (part of replication)
  ///
  /// **Result:** Zero background CPU/network activity = maximum battery savings
  Future<void> pause() async {
    await _lifecycleMutex.protect(() async {
      _log.info('OfflineFirstServer.pause() START');

      if (_isPaused) {
        _log.fine('Already paused, skipping');
        return;
      }

      _isPaused = true;

      // Transition to normalOffline state (health monitoring stopped = offline)
      if (state.value == OfflineFirstServerState.normalOnline) {
        state.value = OfflineFirstServerState.normalOffline;
        _log.fine('State transitioned to normalOffline');
      }

      // Stop health monitoring timer to prevent background network activity
      _log.fine('Stopping health monitoring');
      stopHealthMonitoring();

      // Suspend the HTTP session keep-alive timer for the duration of the
      // background period. While Doze is active, every ping attempt fails with
      // a SocketException, and withNetworkGuard() responds by setting
      // connectionState = connectedButNetworkError. That stale flag would then
      // interfere with _startContinuousReplication() when resume() runs:
      // the path for connectedButNetworkError causes a live network attempt
      // that immediately throws NetworkFailure, notifyNetworkDegraded() is
      // called unnecessarily, and the app stays in the offline state longer
      // than needed. Suspending keeps the connection state clean for wakeup.
      _log.fine('Suspending HTTP keep-alive timer');
      httpServer.suspendKeepAlive();

      // Stop _db_updates stream subscription to prevent background processing
      _log.fine('Stopping _db_updates stream');
      await _stopDbUpdatesStream();

      // STOP (not pause) all database replications to completely stop all timers/streams
      // The replications will be restarted via recovery callbacks when resume() is called
      _log.fine('Stopping ${_dbCache.length} database replications');
      for (final db in _dbCache.values) {
        try {
          _log.fine('Stopping replication for ${db.dbname}');
          // Stop the replication completely (stops all timers, streams, and background activity)
          await db.replicationController.stop();
        } catch (e) {
          _log.warning('Error stopping replication for ${db.dbname}: $e');
        }
      }

      _log.info(
        'OfflineFirstServer.pause() COMPLETE - all background activity stopped',
      );
    });
  }

  /// Resume all activity when the app comes back to foreground.
  /// This restarts health monitoring, database updates stream, and all replications.
  ///
  /// Call this when your app detects it's coming to foreground (e.g., screen on on Android).
  ///
  /// **Recovery procedure (same as network failure recovery):**
  /// 1. Clears paused flag (so _performBackOnlineWork can run)
  /// 2. Restarts health monitoring timer (new Timer.periodic created)
  /// 3. Re-checks allDbs permissions (network call if online)
  /// 4. Writes missing remote markers for databases created/modified while paused
  /// 5. Syncs all databases using marker-based synchronization
  /// 6. Restarts _db_updates stream (new subscription from last sequence)
  /// 7. Invokes recovery callbacks on all OfflineFirstDb instances, which:
  ///    - Check and execute pending migrations
  ///    - Call _startContinuousReplication() to restart bidirectional sync
  ///    - Create new replication controllers with fresh timers/streams
  ///
  /// **Result:** Full activity restored, all data synced, replications running
  Future<void> resume() async {
    await _lifecycleMutex.protect(() async {
      _log.info(
        'OfflineFirstServer.resume() START — state=${state.value}, '
        'connectionState=${httpServer.connectionState.value}, _isPaused=$_isPaused',
      );

      if (!_isPaused) {
        _log.fine('Not paused, skipping');
        return;
      }

      // Only resume if we were in a normal state (not uninitialized or error)
      if (state.value != .normalOnline && state.value != .normalOffline) {
        _log.warning('Cannot resume from state ${state.value}');
        return;
      }

      // Clear paused flag BEFORE running recovery work
      // This is important so _performBackOnlineWork doesn't skip execution
      _isPaused = false;

      // Restart health monitoring timer
      _log.fine('Restarting health monitoring');
      startHealthMonitoring();

      // Restart the HTTP session keep-alive timer that was suspended in
      // pause(). Only has effect if the user is still logged in; if the
      // session expired while backgrounded, health monitoring will re-login
      // and the keep-alive will be restarted by HttpDartCouchServer.login().
      _log.fine('Resuming HTTP keep-alive timer');
      httpServer.resumeKeepAlive();

      // Use the same recovery procedure as network recovery
      // This will:
      // - Re-check permissions if online
      // - Write missing remote markers for databases created while paused
      // - Sync databases (marker-based synchronization)
      // - Restart _db_updates stream
      // - Invoke recovery callbacks (which call _startContinuousReplication() on each OfflineFirstDb)
      _log.fine('Running back-online recovery procedure');
      await _performBackOnlineWork();

      // Only transition to normalOnline if ALL of the following hold:
      //   1. The HTTP connection is confirmed established (not in a failed-login
      //      or network-error state).
      //   2. No recovery callback signalled a problem via notifyNetworkDegraded()
      //      — e.g. _startContinuousReplication() returns a 401 when the CouchDB
      //      session expired while the app was backgrounded for longer than the
      //      server's session timeout (default 10 min).
      //
      // If we set normalOnline prematurely:
      //   • _attemptRelogin() checks `if (prev != normalOnline)` before calling
      //     onBackOnline(). If prev is already normalOnline it skips onBackOnline,
      //     meaning invokeRecoveryCallbacks() is never called and replication
      //     stays permanently stuck at 'initializing'.
      //
      // Leaving state as normalOffline lets health monitoring drive the full
      // recovery sequence: re-login → onBackOnline() → invokeRecoveryCallbacks()
      // → _startContinuousReplication() → replication running.
      // If connectionState is loginFailedWithNetworkError (or any non-connected state),
      // _startContinuousReplication() will have silently skipped inside the recovery
      // callbacks above. In that case we must leave state as normalOffline so that
      // health monitoring can finish the login and then call invokeRecoveryCallbacks()
      // via _attemptRelogin(). Prematurely setting normalOnline here causes
      // _attemptRelogin to see prev==normalOnline and skip recovery callbacks entirely.
      // Similarly, if a recovery callback called notifyNetworkDegraded() (e.g. due to
      // a 401 from an expired session), don't promote to normalOnline — health monitoring
      // must re-login and call onBackOnline() first.
      final isConnected =
          httpServer.connectionState.value ==
          DartCouchConnectionState.connected;
      if (state.value == OfflineFirstServerState.normalOffline &&
          isConnected &&
          !isNetworkDegraded) {
        state.value = OfflineFirstServerState.normalOnline;
        _log.fine('State transitioned to normalOnline');
      } else if (!isConnected) {
        _log.fine(
          'Not transitioning to normalOnline — connectionState is ${httpServer.connectionState.value}, '
          'health monitoring will complete recovery after login',
        );
      } else if (isNetworkDegraded) {
        _log.fine(
          'Not transitioning to normalOnline — isNetworkDegraded=true (e.g. session expired during pause), '
          'health monitoring will re-login and restart replication',
        );
      }

      _log.info(
        'OfflineFirstServer.resume() COMPLETE - all activity resumed via recovery callbacks',
      );
    });
  }

  @override
  Future<List<DartCouchDb>> get allDatabases {
    return _getAllDatabases();
  }

  Future<List<DartCouchDb>> _getAllDatabases() async {
    final canAllDbs = await _getCanAllDbs();
    if (canAllDbs == false) {
      throw CouchDbException(
        CouchDbStatusCodes.unauthorized,
        'User does not have permission to list all databases',
      );
    }
    return localServer!.allDatabases;
  }

  @override
  Future<List<String>> get allDatabasesNames {
    return _getAllDatabasesNames();
  }

  Future<List<String>> _getAllDatabasesNames() async {
    final canAllDbs = await _getCanAllDbs();
    if (canAllDbs == false) {
      throw CouchDbException(
        CouchDbStatusCodes.unauthorized,
        'User does not have permission to list all databases',
      );
    }

    // Get all local databases
    final localDbs = await localServer!.allDatabasesNames;

    // Filter to only include:
    // 1. Databases we created
    // 2. Databases with valid markers (from any instance)
    // 3. System databases (starting with '_')
    final validDatabases = <String>[];

    for (final name in localDbs) {
      // Always include system databases
      if (name.startsWith('_')) {
        validDatabases.add(name);
        continue;
      }

      // Include if it has pending marker repair or valid marker
      final pendingUuid = await _getPendingMarkerRepair(name);
      final hasMarker = await _hasValidMarker(name);
      if (pendingUuid != null || hasMarker) {
        validDatabases.add(name);
      } else {
        _log.fine('Excluding unmarked database from list: $name');
      }
    }

    return validDatabases;
  }

  final Map<String, OfflineFirstDb> _dbCache = {};

  @override
  Future<DartCouchDb> createDatabase(String name) async {
    return await _dbAccessMutex.protect(() async {
      OfflineFirstDb? result = _dbCache[name];
      if (result != null) {
        return result;
      }

      // Check if database exists with tombstone marker
      final existingLocalDb = await localServer!.db(name);
      if (existingLocalDb != null) {
        final existingMarker = await _readMarker(existingLocalDb);
        if (existingMarker != null && existingMarker.tombstone) {
          throw CouchDbException.preconditionFailed(
            'Database $name already exists (tombstoned - was deleted)',
          );
        }
      }

      // Generate a UUID for this database incarnation
      final databaseUuid = _generateUuid();

      _log.info('Creating OfflineFirstDb: $name with UUID: $databaseUuid');

      // Step 1: Create local database
      final localdb =
          await localServer!.createDatabase(name) as LocalDartCouchDb;

      // Step 2: Try to write local marker - MUST succeed
      final localMarkerOk = await _tryWriteMarker(
        localdb,
        databaseUuid,
        'local',
      );

      if (!localMarkerOk) {
        // Critical failure - rollback and abort
        _log.severe('Failed to write local marker for $name - rolling back');
        await localServer!.deleteDatabase(name);
        throw Exception('Failed to create database $name: marker write failed');
      }

      // Step 3: Create remote database if online
      bool remoteMarkerOk = false;
      try {
        if (state.value == OfflineFirstServerState.normalOnline) {
          if ((await httpServer.allDatabasesNames).contains(name) == false) {
            await httpServer.createDatabase(name);
            final remoteDb = await httpServer.db(name);
            remoteMarkerOk = await _tryWriteMarker(
              remoteDb,
              databaseUuid,
              'local',
              isRemote: true,
            );
          }
        }
      } catch (e) {
        _log.warning('Failed to create/mark remote database $name: $e');
        // Continue - we'll create it later during sync
      }

      // Step 4: If remote marker failed, track for repair
      if (!remoteMarkerOk) {
        await _addToPendingMarkerRepairs(name, databaseUuid);
      }

      // Step 5: Create OfflineFirstDb wrapper
      final offline = OfflineFirstDb(
        serverDb: httpServer,
        localDb: localdb,
        dbname: name,
        notifyNetworkDegraded: notifyNetworkDegraded,
        registerRecoveryCallback: registerRecoveryCallback,
        unregisterRecoveryCallback: unregisterRecoveryCallback,
        migration: migration,
        conflictResolver: documentReplicationConflictResolver,
      );
      await offline.init();
      _dbCache[name] = offline;

      return offline;
    });
  }

  @override
  Future<DartCouchDb?> db(String name) async {
    _log.info('OfflineFirstServer.db(): $name');

    // Protect database creation with mutex to prevent race conditions
    return await _dbAccessMutex.protect(() async {
      // Check cache inside mutex
      DartCouchDb? result = _dbCache[name];
      if (result != null) {
        return result;
      }

      if (localServer == null) {
        return null;
      }

      LocalDartCouchDb? localdb = await localServer!.db(name);

      if (localdb == null) {
        _log.info(
          'OfflineFirstServer.db(): Local database $name does not exist locally, checking server',
        );

        // Check if database exists remotely (only if online)
        if (state.value == OfflineFirstServerState.normalOnline) {
          try {
            final serverDb = await httpServer.db(name);
            if (serverDb != null) {
              // Check if it has a valid marker
              final remoteMarker = await _readMarker(serverDb);
              if (remoteMarker != null) {
                // Valid foreign database - adopt it by creating local copy
                _log.info(
                  'OfflineFirstServer.db(): Database $name exists on server with valid marker, creating local copy',
                );
                localdb =
                    await localServer!.createDatabase(name) as LocalDartCouchDb;

                // Write same marker locally
                await _tryWriteMarker(
                  localdb,
                  remoteMarker.databaseUuid,
                  'remote',
                );
              } else {
                // No marker - adopt the database by creating marker
                _log.info(
                  'OfflineFirstServer.db(): Database $name exists on server but has no marker - adopting it',
                );

                // Generate a new UUID for this database
                final databaseUuid = _generateUuid();

                // Create local database
                localdb =
                    await localServer!.createDatabase(name) as LocalDartCouchDb;

                // Write marker locally
                await _tryWriteMarker(localdb, databaseUuid, 'local');

                // Try to write marker remotely (may fail due to permissions, that's ok)
                await _tryWriteMarker(serverDb, databaseUuid, 'remote');

                // Add to pending repairs in case remote marker write failed
                await _addToPendingMarkerRepairs(name, databaseUuid);
              }
            } else {
              _log.info(
                'OfflineFirstServer.db(): Database $name does not exist on server either - returning null',
              );
              return null;
            }
          } catch (e) {
            _log.warning('Failed to check remote database $name: $e');
            return null;
          }
        } else {
          // Offline and database doesn't exist locally
          _log.info(
            'OfflineFirstServer.db(): Database $name does not exist locally and we are offline - returning null',
          );
          return null;
        }
      }

      // We have a local database - check if it needs marker repair
      final pendingUuid = await _getPendingMarkerRepair(name);

      if (pendingUuid != null) {
        // This database has a pending marker repair
        _log.fine('Database $name has pending marker repair - attempting now');

        // Try to write missing markers
        final localMarker = await _readMarker(localdb);
        if (localMarker == null) {
          final ok = await _tryWriteMarker(localdb, pendingUuid, 'local');
          if (!ok) {
            _log.warning('Failed to repair local marker for $name');
            // Database is broken - refuse to open
            return null;
          }
        }

        // Try remote marker if online
        final remoteDb = await httpServer.db(name);
        if (remoteDb != null) {
          final remoteMarker = await _readMarker(remoteDb);
          if (remoteMarker == null) {
            await _tryWriteMarker(remoteDb, pendingUuid, 'local');
          }
        }

        // Check if all repairs are complete
        final localMarkerNow = await _readMarker(localdb);
        final remoteMarkerNow = await _readMarker(remoteDb);
        if (localMarkerNow != null &&
            (remoteDb == null || remoteMarkerNow != null)) {
          // All markers present - remove from pending
          await _removeFromPendingMarkerRepairs(name);
        }
      } else {
        // Not in pending list - verify it has a valid marker
        final localMarker = await _readMarker(localdb);

        if (localMarker == null) {
          // No local marker and not in pending - this is an unmarked database
          _log.warning(
            'Database $name has no local marker and is not tracked - ignoring',
          );
          return null;
        }

        // Check if LOCAL marker has tombstone flag (deleted offline)
        if (localMarker.tombstone) {
          _log.info(
            'Database $name has local tombstone marker - was deleted offline, returning null',
          );
          return null;
        }

        // Check if marker is from our instance
        if (localMarker.instanceUuid != _instanceUuid) {
          _log.fine(
            'Database $name created by another instance: ${localMarker.instanceUuid}',
          );
        } else {
          _log.fine('Database $name created by us');
        }

        // Check if database is tombstoned on REMOTE (marked for deletion)
        // If so, unregister ourselves and delete local copy
        if (state.value == OfflineFirstServerState.normalOnline) {
          try {
            final remoteDb = await httpServer.db(name);
            if (remoteDb != null) {
              final remoteMarker = await _readMarker(remoteDb);
              if (remoteMarker != null && remoteMarker.tombstone) {
                _log.info(
                  'Database $name is tombstoned on remote - unregistering and deleting local copy',
                );
                await _unregisterInstance(name);
                await localServer!.deleteDatabase(name);
                return null;
              }
            }
          } catch (e) {
            _log.fine('Could not check tombstone for $name: $e');
            // Continue - we'll check again when network is restored
          }
        }
      }

      // Register this instance as active user (if online and remote exists)
      if (state.value == OfflineFirstServerState.normalOnline) {
        await _registerInstance(name);
      }

      // Create OfflineFirstDb wrapper
      final offline = OfflineFirstDb(
        serverDb: httpServer,
        localDb: localdb,
        dbname: name,
        notifyNetworkDegraded: notifyNetworkDegraded,
        registerRecoveryCallback: registerRecoveryCallback,
        unregisterRecoveryCallback: unregisterRecoveryCallback,
        migration: migration,
        conflictResolver: documentReplicationConflictResolver,
      );
      await offline.init();
      _dbCache[name] = offline;
      result = offline;

      return result;
    });
  }

  @override
  Future<void> deleteDatabase(String name) async {
    return await _dbAccessMutex.protect(() async {
      // Dispose and remove database from cache first
      final db = _dbCache.remove(name);
      if (db != null) {
        await db.dispose();
      }

      // Remove from pending repairs if present
      await _removeFromPendingMarkerRepairs(name);

      // If online, set tombstone and unregister on remote, then delete local
      // '_tombstone_${name}_${uuid}' to immediately free up the name
      if (state.value == OfflineFirstServerState.normalOnline) {
        try {
          // Set tombstone flag and unregister this instance on remote
          final updatedMarker = await _updateRemoteMarker(name, (marker) {
            final instances = List<String>.from(marker.activeInstances);
            instances.remove(_instanceUuid);

            return marker.copyWith(tombstone: true, activeInstances: instances);
          });

          if (updatedMarker != null && updatedMarker.activeInstances.isEmpty) {
            _log.info('Last instance of database $name - deleting from server');
            await httpServer.deleteDatabase(name);
          } else {
            _log.info(
              'Database $name marked as tombstone, ${updatedMarker?.activeInstances.length ?? 0} other instance(s) still registered',
            );
          }
        } catch (e) {
          _log.warning('Failed to set tombstone for database $name: $e');
          // Try direct deletion as fallback
          try {
            await httpServer.deleteDatabase(name);
          } catch (e2) {
            _log.warning('Failed to delete database $name from server: $e2');
          }
        }

        // Delete local database after remote tombstone is set
        if (localServer != null) {
          await localServer!.deleteDatabase(name);
        }
      } else {
        // Offline path — set tombstone in LOCAL marker and keep the local
        // database intact.  On reconnect, _syncSingleDatabase() will detect
        // the tombstone, unregister this instance from the remote marker, and
        // delete both the remote and local databases (if this instance is the
        // last registered one).
        _log.info(
          'Offline deletion of $name - setting local tombstone marker for later sync',
        );

        final localDb = await localServer?.db(name);
        if (localDb != null) {
          try {
            // Read existing marker
            final existingMarker = await _readMarker(localDb);
            if (existingMarker != null) {
              // Update marker to set tombstone flag
              final tombstonedMarker = existingMarker.copyWith(tombstone: true);
              await localDb.put(tombstonedMarker);
              _log.info('Set tombstone flag in local marker for $name');
            } else {
              _log.warning(
                'Cannot set tombstone for $name - no local marker found',
              );
              // No marker means unmarked database, just delete it locally
              await localServer!.deleteDatabase(name);
            }
          } catch (e) {
            _log.warning('Failed to set local tombstone for $name: $e');
            // On error, delete locally as fallback
            await localServer!.deleteDatabase(name);
          }
        }
      }
    });
  }

  /// Invalidate replication checkpoints for a database
  /// Invalidates replication checkpoints when database recreation is detected.
  ///
  /// This is called when marker UUIDs don't match (deterministic recreation detection).
  /// Forces a full resync to avoid using stale checkpoints with the new database.
  ///
  /// **IMPORTANT:** Must include ALL ReplicationDirection enum values:
  /// - 'push' (ReplicationDirection.push)
  /// - 'pull' (ReplicationDirection.pull)
  /// - 'both' (ReplicationDirection.both) ← Note: it's "both" NOT "bidirectional"
  ///
  /// Missing any direction will cause sporadic test failures where checkpoints
  /// aren't properly invalidated and old sequences are reused incorrectly.
  Future<void> _invalidateCheckpoints(String dbName) async {
    _log.info('Invalidating replication checkpoints for database: $dbName');

    try {
      final localDb = await localServer?.db(dbName);
      if (localDb == null) return;

      // Checkpoint IDs follow the pattern: _local/{sourceDbName}::{targetDbName}::{direction}
      // MUST match ReplicationDirection enum: push, pull, both
      final checkpointIds = [
        '_local/$dbName::$dbName::push',
        '_local/$dbName::$dbName::pull',
        '_local/$dbName::$dbName::both', // Enum value is 'both', not 'bidirectional'
      ];

      for (final checkpointId in checkpointIds) {
        try {
          final doc = await localDb.get(checkpointId);
          if (doc != null && doc.rev != null) {
            await localDb.remove(checkpointId, doc.rev!);
            _log.fine('Deleted checkpoint: $checkpointId');
          }
        } catch (e) {
          // Checkpoint doesn't exist or already deleted - this is fine
          _log.fine(
            'Checkpoint $checkpointId not found or already deleted: $e',
          );
        }
      }
    } catch (e) {
      _log.warning('Error invalidating checkpoints for $dbName: $e');
      // Non-fatal - replication validation will also catch recreation
    }
  }

  /// Resolves database recreation conflict based on configured strategy
  Future<void> _resolveRecreationConflict(
    String dbName,
    DartCouchDb? localDb,
    DartCouchDb? remoteDb,
    DatabaseSyncMarker localMarker,
    DatabaseSyncMarker remoteMarker,
  ) async {
    // Both databases must exist for a conflict
    assert(localDb != null && remoteDb != null);

    // Invalidate checkpoints before resolving conflict to force fresh sync
    await _invalidateCheckpoints(dbName);

    switch (existingDatabaseSyncingStrategy) {
      case ExistingDatabasesSyncStrategie.serverAlwaysWins:
        _log.info('Conflict resolution: serverAlwaysWins - recreating locally');
        await _dbCache.remove(dbName)?.dispose();
        await localServer!.deleteDatabase(dbName);
        final newLocalDb =
            await localServer!.createDatabase(dbName) as LocalDartCouchDb;
        await _tryWriteMarker(newLocalDb, remoteMarker.databaseUuid, 'remote');
        break;

      case ExistingDatabasesSyncStrategie.localAlwaysWins:
        _log.info('Conflict resolution: localAlwaysWins - recreating remotely');
        await httpServer.deleteDatabase(dbName);
        await httpServer.createDatabase(dbName);
        final newRemoteDb = await httpServer.db(dbName);
        await _tryWriteMarker(
          newRemoteDb,
          localMarker.databaseUuid,
          'local',
          isRemote: true,
        );
        break;

      case ExistingDatabasesSyncStrategie.merge:
        // Merge strategy: adopt remote marker on the local database, keeping
        // all local data intact. Checkpoints have already been invalidated
        // (see _invalidateCheckpoints call above), so when replication starts
        // later via db() → OfflineFirstDb.init(), it will perform a full
        // bidirectional sync from scratch — pushing local docs to the server
        // and pulling server docs to local.
        _log.info(
          'Conflict resolution: merge - adopting remote metadata, '
          'replication will handle data sync later',
        );
        await _tryWriteMarker(localDb, remoteMarker.databaseUuid, 'remote');
        _log.info('Merge complete - local marker updated to remote identity');
        break;
    }
  }

  /// Reconciles one database's *existence* between local and remote using markers.
  ///
  /// Called from [_syncLocalAndRemoteDatabases] (bulk pass on reconnect) and
  /// from [_handleDbUpdate] (reactive, triggered by a `_db_updates` event).
  ///
  /// This method only manages database creation/deletion — document content is
  /// replicated separately by [OfflineFirstDb] once the database exists on both
  /// sides.
  ///
  /// Decision matrix:
  ///
  /// | local | remote | condition                          | action                                    |
  /// |-------|--------|------------------------------------|-------------------------------------------|
  /// | no    | no     | —                                  | both gone — clean up pending-repair entry |
  /// | yes   | no     | local tombstone                    | was deleted offline → delete local        |
  /// | yes   | no     | no tombstone, no marker            | unmarked legacy DB → delete local         |
  /// | yes   | no     | has marker (not tombstone)         | remote went missing → recreate remote     |
  /// | no    | yes    | remote has marker                  | new remote DB → create local              |
  /// | no    | yes    | remote has no marker               | discovered DB → create marker + local     |
  /// | yes   | yes    | local tombstone                    | offline delete — propagate to remote †    |
  /// | yes   | yes    | UUIDs differ                       | recreation detected → conflict strategy   |
  /// | yes   | yes    | UUIDs match, no tombstone          | in sync → no-op                           |
  ///
  /// † The `localMarker.tombstone` check intentionally does NOT require
  /// `!remoteMarker.tombstone`.  When another instance already tombstoned the
  /// remote marker, this instance may still be listed in `activeInstances` and
  /// must unregister itself (and delete the server DB if it is the last one).
  Future<void> _syncSingleDatabase(String dbName) async {
    _log.fine('Syncing single database: $dbName');

    // Check local and remote existence
    final localDb = await localServer!.db(dbName);
    final localExists = localDb != null;

    final remoteDb = await httpServer.db(dbName);
    final remoteExists = remoteDb != null;

    // Read markers
    DatabaseSyncMarker? localMarker;
    DatabaseSyncMarker? remoteMarker;
    bool remoteMarkerReadFailed = false;

    if (localExists) {
      localMarker = await _readMarker(localDb);
    }

    if (remoteExists) {
      try {
        remoteMarker = await _readMarker(remoteDb);
      } on NetworkFailure {
        _log.warning(
          'Could not read remote marker for $dbName due to network error',
        );
        remoteMarkerReadFailed = true;
      }
    }

    // Check if this database has pending marker repairs
    final pendingUuid = await _getPendingMarkerRepair(dbName);

    // Decision matrix
    if (!localExists && !remoteExists) {
      // Both deleted - clean up if we had it pending
      if (pendingUuid != null) {
        await _removeFromPendingMarkerRepairs(dbName);
        await _dbCache.remove(dbName)?.dispose();
      }
      _log.fine('Database $dbName deleted on both sides');
    } else if (localExists && !remoteExists) {
      // Local exists, remote deleted OR local created offline

      // Check if local marker has tombstone flag (deleted while offline)
      if (localMarker != null && localMarker.tombstone) {
        _log.info(
          'Found local tombstone for $dbName - was deleted while offline, cleaning up locally',
        );
        // Database was deleted offline, just clean up locally now
        await localServer!.deleteDatabase(dbName);
        await _dbCache.remove(dbName)?.dispose();
        await _removeFromPendingMarkerRepairs(dbName);
      } else if (localMarker == null && pendingUuid == null) {
        // No marker, not pending - unmarked database, delete locally
        _log.info('Deleting unmarked local database: $dbName');
        await localServer!.deleteDatabase(dbName);
        await _dbCache.remove(dbName)?.dispose();
      } else if (localMarker != null || pendingUuid != null) {
        // Has marker or pending - recreate on remote (preserve local data)
        final uuidToUse = pendingUuid ?? localMarker?.databaseUuid ?? '';
        _log.info(
          'Remote database $dbName missing - recreating on server with UUID: $uuidToUse',
        );
        try {
          await httpServer.createDatabase(dbName);
          final newRemoteDb = await httpServer.db(dbName);
          if (newRemoteDb != null) {
            // Write marker to remote
            await _tryWriteMarker(
              newRemoteDb,
              uuidToUse,
              'recovered',
              isRemote: true,
            );
            // Remove from pending repairs if it was pending
            if (pendingUuid != null) {
              await _removeFromPendingMarkerRepairs(dbName);
            }
          }
        } catch (e) {
          _log.warning('Failed to recreate remote database $dbName: $e');
        }
      }
    } else if (!localExists && remoteExists) {
      // Remote exists, local deleted
      if (remoteMarker != null) {
        // Valid remote database - create locally
        _log.info('Creating local database $dbName from remote with marker');
        final newLocalDb =
            await localServer!.createDatabase(dbName) as LocalDartCouchDb;

        // Copy marker
        await _tryWriteMarker(newLocalDb, remoteMarker.databaseUuid, 'remote');
      } else {
        // No marker - database was created by another client/instance
        // Create a new marker for it and sync locally
        _log.info(
          'Remote database $dbName has no marker - creating marker and syncing locally',
        );
        final newUuid = _generateUuid();

        // Write marker to remote - but don't register ourselves yet
        // Registration happens when the database is actually opened via db()
        await _tryWriteMarker(remoteDb, newUuid, 'discovered', isRemote: false);

        // Create local database
        final newLocalDb =
            await localServer!.createDatabase(dbName) as LocalDartCouchDb;

        // Copy marker locally
        await _tryWriteMarker(newLocalDb, newUuid, 'discovered');
      }
    } else {
      // Both exist - check for tombstone or recreation
      if (localMarker != null && remoteMarker != null) {
        // Check if local was deleted offline (has tombstone).
        // This covers two sub-cases:
        //   1. Remote is not yet tombstoned → propagate deletion to remote.
        //   2. Remote is also tombstoned (e.g. another instance already called
        //      deleteDatabase) → this instance is still in activeInstances and
        //      must unregister itself; if it is the last, delete the remote DB.
        if (localMarker.tombstone) {
          _log.info(
            'Database $dbName has local tombstone - propagating deletion to remote',
          );
          try {
            // Set tombstone on remote and unregister this instance
            final updatedMarker = await _updateRemoteMarker(dbName, (marker) {
              final instances = List<String>.from(marker.activeInstances);
              instances.remove(_instanceUuid);
              return marker.copyWith(
                tombstone: true,
                activeInstances: instances,
              );
            });

            if (updatedMarker != null &&
                updatedMarker.activeInstances.isEmpty) {
              _log.info('Last instance of $dbName - deleting from server');
              await httpServer.deleteDatabase(dbName);
            } else {
              _log.info(
                'Database $dbName tombstoned on server, ${updatedMarker?.activeInstances.length ?? 0} other instance(s) still registered',
              );
            }

            // Now delete locally
            await localServer!.deleteDatabase(dbName);
            await _dbCache.remove(dbName)?.dispose();
          } catch (e) {
            _log.warning('Failed to propagate tombstone for $dbName: $e');
            // Try direct deletion as fallback
            try {
              await httpServer.deleteDatabase(dbName);
              await localServer!.deleteDatabase(dbName);
              await _dbCache.remove(dbName)?.dispose();
            } catch (e2) {
              _log.severe('Failed to delete $dbName: $e2');
            }
          }
        } else if (localMarker.databaseUuid != remoteMarker.databaseUuid) {
          // RECREATION DETECTED - UUIDs differ
          _log.warning(
            'Database $dbName recreated - local UUID: ${localMarker.databaseUuid}, remote UUID: ${remoteMarker.databaseUuid}',
          );

          // Apply conflict resolution strategy
          await _resolveRecreationConflict(
            dbName,
            localDb,
            remoteDb,
            localMarker,
            remoteMarker,
          );

          // Remove from pending if present
          await _removeFromPendingMarkerRepairs(dbName);
        } else {
          // Same UUID - markers match, remove from pending if present
          if (pendingUuid != null && pendingUuid == localMarker.databaseUuid) {
            await _removeFromPendingMarkerRepairs(dbName);
          }
        }
      } else if (localMarker == null && remoteMarker != null) {
        // Remote has marker, local doesn't - write marker locally
        _log.fine('Writing missing local marker for $dbName');
        final success = await _tryWriteMarker(
          localDb,
          remoteMarker.databaseUuid,
          'remote',
        );
        if (!success && pendingUuid == null) {
          // Failed to write and not tracking - add to pending
          await _addToPendingMarkerRepairs(dbName, remoteMarker.databaseUuid);
        } else if (success && pendingUuid != null) {
          // Successfully wrote - remove from pending
          await _removeFromPendingMarkerRepairs(dbName);
        }
      } else if (localMarker != null && remoteMarker == null) {
        if (remoteMarkerReadFailed) {
          // Remote marker could not be read due to a network error -
          // don't assume recreation, the next sync cycle will retry
          _log.fine(
            'Database $dbName: remote marker unreadable due to network error - skipping recreation check',
          );
        } else {
          // Local has marker, remote genuinely doesn't - database was recreated
          _log.warning(
            'Database $dbName: local has marker but remote does not - assuming remote was recreated',
          );

          // Generate a new UUID for the recreated remote database
          final newRemoteUuid = _generateUuid();

          // Create a marker representing the recreated remote database
          final recreatedRemoteMarker = DatabaseSyncMarker(
            instanceUuid: _instanceUuid!,
            databaseUuid: newRemoteUuid,
            createdAt: DateTime.now(),
            createdBy: 'detected_recreation',
            activeInstances: [],
            tombstone: false,
          );

          // Apply conflict resolution strategy
          await _resolveRecreationConflict(
            dbName,
            localDb,
            remoteDb,
            localMarker,
            recreatedRemoteMarker,
          );

          // Remove from pending if present
          await _removeFromPendingMarkerRepairs(dbName);
        }
      } else if (localMarker == null && remoteMarker == null) {
        // Neither has marker
        if (pendingUuid != null) {
          // We're tracking this - try to write markers
          _log.fine('Attempting to write pending markers for $dbName');
          final localSuccess = await _tryWriteMarker(
            localDb,
            pendingUuid,
            'local',
          );
          final remoteSuccess = await _tryWriteMarker(
            remoteDb,
            pendingUuid,
            'local',
            isRemote: true,
          );

          if (localSuccess && remoteSuccess) {
            await _removeFromPendingMarkerRepairs(dbName);
          }
        } else {
          // Not tracking - unmarked legacy database, ignore
          _log.fine('Both sides unmarked for $dbName - ignoring');
        }
      }
    }
  }

  // _loadDbChangesStream removed - now using marker-based sync triggered by _db_updates events

  /// Reconciles which databases *exist* between local and remote.
  ///
  /// This is a database-existence pass — it does NOT transfer document content.
  /// Content replication is started separately by [invokeRecoveryCallbacks].
  ///
  /// Called during login and on every reconnect ([_performBackOnlineWork]).
  /// Each database is processed by [_syncSingleDatabase], which handles
  /// tombstone propagation, remote recreation, and UUID-mismatch conflicts.
  Future<void> _syncLocalAndRemoteDatabases() async {
    _log.info('Starting marker-based synchronization of all databases');

    // Get all database names (raw, unfiltered)
    final allLocalDbs = (await localServer!.allDatabasesNames)
        .where((e) => !e.startsWith('_'))
        .toSet();
    final allRemoteDbs = (await httpServer.allDatabasesNames)
        .where((e) => !e.startsWith('_'))
        .toSet();

    // Combine to get full set
    final allDbNames = {...allLocalDbs, ...allRemoteDbs};

    _log.info(
      'Found ${allLocalDbs.length} local and ${allRemoteDbs.length} remote databases',
    );

    // Sync each database individually
    for (final dbName in allDbNames) {
      try {
        await _syncSingleDatabase(dbName);
      } catch (e, stackTrace) {
        _log.severe('Error syncing database $dbName: $e', e, stackTrace);
        // Continue with other databases
      }
    }

    _log.info('Marker-based synchronization complete');
  }

  /// Starts listening to the _db_updates stream from the server.
  /// This keeps our local database list synchronized with the server.
  ///
  /// Should only be called during valid state transitions (login, onBackOnline).
  /// Network failures are handled gracefully - the stream will just fail to start
  /// and will be retried when the connection is restored.
  Future<void> _startDbUpdatesStream() async {
    _log.info('_startDbUpdatesStream - START');
    // Abort existing subscription immediately without waiting for cancel
    final oldSubscription = _dbUpdatesSubscription;
    _dbUpdatesSubscription = null;

    // Cancel in background - don't wait for it to complete
    if (oldSubscription != null) {
      unawaited(
        oldSubscription.cancel().catchError((e) {
          _log.fine('Error cancelling old _db_updates subscription: $e');
        }),
      );
    }

    try {
      // Start listening to the stream (from last known position if available)
      final stream = httpServer.dbUpdatesStream(
        since: await _getLastDbUpdateSeq(),
      );
      _dbUpdatesSubscription = stream.listen(
        (event) => _handleDbUpdateQueue.addJob((_) => _handleDbUpdate(event)),
        onError: (error) {
          _log.fine('_db_updates stream error: $error');

          // If it's a ClientException, network is likely down
          // Connection lost - notify health monitoring for coordinated recovery
          notifyNetworkDegraded();
          unawaited(_dbUpdatesSubscription?.cancel() ?? Future.value());
          _dbUpdatesSubscription = null;
        },
        cancelOnError: false,
      );
      _log.info(
        '_db_updates subscription started (since: ${await _getLastDbUpdateSeq()})',
      );
    } catch (e) {
      // Silently handle connection issues - network may not be fully recovered yet
      _log.info('Failed to start _db_updates stream: $e');
    }
    _log.info('_startDbUpdatesStream - COMPLETE');
  }

  final _handleDbUpdateQueue = AsyncQueue.autoStart();

  /// Handles a database update event from the _db_updates stream
  void _handleDbUpdate(Map<String, dynamic> event) async {
    // Track pending callback
    _pendingDbUpdateCallbacks++;

    try {
      // Skip processing if disposal or pause is in progress, or if already
      // logged out (uri is null). The latter can happen because
      // _logoutInternal() first calls _unregisterInstance() (which writes
      // to the remote marker and triggers a CouchDB _db_updates event), then
      // cancels the subscription, then calls httpServer.logout() which sets
      // uri = null. The async_queue job for that marker-write event may still
      // be in flight when uri becomes null, causing a null-check crash.
      if (_isDisposing || _isPaused || httpServer.uri == null) return;

      final type = event['type'] as String?;
      final dbName = event['db_name'] as String?;
      final seq = event['seq'];

      _log.info(
        '_handleDbUpdate: Received _db_updates event: type=$type, db_name=$dbName, seq=$seq',
      );

      if (seq != null) {
        await _setLastDbUpdateSeq(seq);
      } else {
        await _dbUpdatesStateRemove();
      }

      if (dbName == null || type == null) return;

      // Only process create/delete events for non-system databases
      if (dbName.startsWith('_') || type == 'updated') {
        _log.fine(
          '_handleDbUpdate: Ignoring _db_updates event for system database or update type: $dbName, $type',
        );
        return;
      }

      // Use event as trigger to sync this specific database
      _log.info('_handleDbUpdate: Syncing database $dbName due to $type event');

      try {
        await _syncSingleDatabase(dbName);
      } catch (e) {
        _log.warning('_handleDbUpdate: Failed to sync database $dbName: $e');
      }
    } finally {
      // Decrement counter and complete if this was the last pending callback
      _pendingDbUpdateCallbacks--;
      if (_pendingDbUpdateCallbacks == 0 &&
          _pendingDbUpdateCompleter != null &&
          !_pendingDbUpdateCompleter!.isCompleted) {
        _pendingDbUpdateCompleter!.complete();
      }
    }
  }

  /// Stops the _db_updates stream
  Future<void> _stopDbUpdatesStream() async {
    _log.fine('Stopping _db_updates stream - START');
    if (_dbUpdatesSubscription != null) {
      _log.fine('Cancelling _db_updates subscription');
      try {
        await _dbUpdatesSubscription!.cancel();
        _log.fine('_db_updates subscription cancelled successfully');
      } catch (e) {
        _log.fine('Error cancelling _db_updates subscription: $e');
      }
    } else {
      _log.fine('No _db_updates subscription to cancel');
    }
    _log.fine('Setting _dbUpdatesSubscription to null');
    _dbUpdatesSubscription = null;
    _log.fine('Stopping _db_updates stream - COMPLETE');
  }

  DcValueNotifier<DartCouchConnectionState> get connectionState =>
      httpServer.connectionState;

  @override
  Future<SessionResult> session() => httpServer.session();

  @override
  Uri? get uri => httpServer.uri;

  @override
  String? get authCookie => httpServer.authCookie;

  @override
  String? get username => _username;

  @override
  String? get password => _password;

  @override
  Future<bool> isCouchDbUp() => httpServer.isCouchDbUp();

  /// Performs all work needed when connectivity is established or restored.
  ///
  /// Called from [onBackOnline] (network recovery) and from the login path.
  /// Must NOT be called while holding [_lifecycleMutex] to avoid deadlocks.
  ///
  /// Step order matters:
  /// 1. **Write missing markers** — flushes any remote marker writes that
  ///    failed while offline, so that step 2 sees complete marker state.
  /// 2. **Database-existence sync** ([_syncLocalAndRemoteDatabases]) —
  ///    propagates offline tombstones, detects recreations, creates missing
  ///    local/remote databases.  Must run before step 4 so that databases
  ///    exist on both sides before replication tries to use them.
  /// 3. **Start `_db_updates` stream** — begins watching future remote
  ///    create/delete events so they are handled reactively.
  /// 4. **Invoke recovery callbacks** — restarts the bidirectional document
  ///    replication in each open [OfflineFirstDb].  Must run after step 2.
  Future<void> _performBackOnlineWork() async {
    _log.fine('_performBackOnlineWork() called');

    // Early return if we're disposing or paused
    if (_isDisposing) {
      _log.fine('_performBackOnlineWork() skipped - server is disposing');
      return;
    }

    if (_isPaused) {
      _log.fine('_performBackOnlineWork() skipped - server is paused');
      return;
    }

    // Re-check allDbs permission after network recovery
    // First try to use cached value, otherwise check with server
    bool? canAllDbs;
    try {
      canAllDbs = await _checkAndStoreAllDbsPermission();

      // Update persisted login state with current permission
      if (url != null && _username != null && _password != null) {
        final loginState = await _loginStateGet(url!, _username!, _password!);
        if (loginState != null && loginState.canAllDbs != canAllDbs) {
          await _loginStatePut(
            OfflineFirstServerLoginState.make(
              url!,
              _username!,
              _password!,
              canAllDbs,
              loginState.rev,
            ),
          );
        }
      }
    } catch (e) {
      _log.warning('Failed to re-check allDbs permission: $e');
    }

    // Only sync databases and start _db_updates stream if user has allDbs permission
    if (canAllDbs == true) {
      // Proactively write missing remote markers for databases we created
      try {
        final instanceState = await _instanceStateGet();
        if (instanceState != null) {
          await _writeAllMissingRemoteMarkers(instanceState);
        }
      } catch (e) {
        _log.warning('Failed to write missing remote markers: $e');
      }

      // Replay any pending database creation/deletion operations
      try {
        await _syncLocalAndRemoteDatabases();
      } catch (e) {
        _log.warning('_oneShotProcessDbUpdatesAndReplay failed: $e');
      }

      // Restart the _db_updates stream (it will use the last seq we stored)
      try {
        await _startDbUpdatesStream();
      } catch (e) {
        _log.warning('Failed to start _db_updates stream: $e');
      }
    } else {
      _log.info(
        'User does not have allDbs permission - skipping database synchronization and _db_updates stream on recovery',
      );
    }

    // Invoke recovery callbacks to restart database replications
    // Each OfflineFirstDb has registered a callback that calls _startContinuousReplication()
    _log.fine('Invoking recovery callbacks to restart replications');
    await invokeRecoveryCallbacks();

    _log.info('_performBackOnlineWork() completed');
  }

  @override
  Future<void> onBackOnline() async {
    await _lifecycleMutex.protect(() async {
      await _performBackOnlineWork();
    });
  }
}

enum OfflineFirstDBState {
  /// login has never been done and valid credentials are missing
  loginInvalid(1),

  /// credentials which were valid last try are known
  /// but because of missing internet connection
  /// sync is currently not possible
  disconnectedAndOutOfSync(2),

  /// LocalDartCouchDb is in live sync with HttpDartCouchDb
  connectedAndSynced(3);

  // Field to store the integer value
  final int value;

  // Constructor
  const OfflineFirstDBState(this.value);
}
