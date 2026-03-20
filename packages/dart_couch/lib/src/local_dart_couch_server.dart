import 'dart:async';

import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:drift/drift.dart' show Value;
import 'package:mutex/mutex.dart';

import 'platform/io_shim.dart';
import 'dart_couch_server.dart';
import 'database_migration.dart';
import 'dart_couch_db.dart';
import 'local_dart_couch_db.dart';
import 'local_storage_engine/attachment_storage.dart';
import 'local_storage_engine/attachment_storage_factory.dart';
import 'local_storage_engine/database.dart';
import 'local_storage_engine/database_connection.dart';
import 'messages/couch_db_status_codes.dart';

final Logger _log = Logger('dart_couch-local_server');

class LocalDartCouchServer extends DartCouchServer {
  /// Root directory that contains `db.sqlite` and the `att/` subfolder.
  final Directory directory;
  late final AppDatabase _db;
  late final AttachmentStorage _attachmentStorage;
  List<LocalDartCouchDb>? _allDbs;
  Completer<void>? _initCompleter;
  final m = Mutex();
  final DatabaseMigration? migration;

  /// Cache of LocalDartCouchDb instances, keyed by database name.
  /// Only one LocalDartCouchDb object should exist per database to avoid race
  /// conditions. Migration is executed once when an object is first added
  /// to this cache — the cache itself tracks whether migration has run.
  /// This mirrors HttpDartCouchServer.databases / wasInCache pattern.
  final Map<String, LocalDartCouchDb> _dbCache = {};

  LocalDartCouchDb? _findDbByName(String name) {
    return _allDbs?.firstWhereOrNull((element) => element.dbname == name);
  }

  LocalDartCouchServer(this.directory, {String? tempDir, this.migration}) {
    _log.fine('Initializing LocalDartCouchServer with dir: ${directory.path}');
    directory.createSync(recursive: true);
    Directory('${directory.path}/att').createSync(recursive: true);
    _db = AppDatabase(
      openDatabaseConnection(
        file: File('${directory.path}/db.sqlite'),
        tempDir: tempDir,
      ),
    );
    _attachmentStorage = createAttachmentStorage(directory, _db);
  }

  @override
  Future<void> dispose() async {
    _log.fine('Disposing LocalDartCouchServer, closing database connection');
    await m.protect(() async {
      _allDbs?.forEach((db) {
        db.dispose();
      });
      await _db.close();
      _allDbs = null;
      _dbCache.clear();
      _initCompleter = null;
    });
    _log.fine('LocalDartCouchServer disposed');
  }

  Future<void> _ensureInitialized() async {
    if (_allDbs != null) return;

    if (_initCompleter != null) {
      await _initCompleter!.future;
      return;
    }

    _initCompleter = Completer<void>();
    try {
      await _attachmentStorage.initialize();
      await _recoverAttachmentFiles();
      await _updateAllDbs();
      _initCompleter!.complete();
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  /// Recovers from incomplete attachment writes that occurred before a crash.
  ///
  /// **Phase 1 — stale `.tmp` files**: A `.tmp` file is written at the start
  /// of an UPDATE before the DB row is touched. Both the DB update and the
  /// subsequent rename live inside the same outer `db.transaction()`, which
  /// only commits when its callback returns (i.e. after the rename). Therefore,
  /// if a `.tmp` survives a crash the transaction was rolled back and the DB is
  /// already in the old, consistent state. Completing the rename would produce
  /// a file whose content disagrees with the DB row's digest/length.
  /// Correct action: **always delete** stale `.tmp` files.
  ///
  /// **Phase 2 — orphan files**: If a plain integer file exists in `att/` but
  /// has no DB row, the process crashed during an INSERT after the file was
  /// written but before the transaction committed (rolling back the DB row).
  /// Delete the orphan file.
  Future<void> _recoverAttachmentFiles() async {
    final allAttachments = await _db.getAllAttachments();
    final knownIds = allAttachments.map((a) => a.id).toSet();
    await _attachmentStorage.recover(knownIds);
  }

  Future<void> _updateAllDbs() async {
    _allDbs = (await _db.allDatabases)
        .map(
          (e) => LocalDartCouchDb(
            db: _db,
            dbid: e.id,
            dbname: e.name,
            attachmentStorage: _attachmentStorage,
          ),
        )
        .toList();
  }

  @override
  Future<DartCouchDb> createDatabase(String name) async {
    return await m.protect<DartCouchDb>(() async {
      await _ensureInitialized();

      if (_allDbs!.any((element) => element.dbname == name)) {
        throw CouchDbException.preconditionFailed(name);
      }

      _log.info('Creating local database: $name');
      final dbEntry = LocalDatabasesCompanion(name: Value(name));
      await _db.addDatabase(dbEntry);
      await _updateAllDbs();

      // Use the helper method instead of calling db()
      final createdDb = _findDbByName(name);
      return createdDb!;
    });
  }

  @override
  Future<List<LocalDartCouchDb>> get allDatabases async {
    return await m.protect<List<LocalDartCouchDb>>(() async {
      await _ensureInitialized();
      return _allDbs!;
    });
  }

  @override
  Future<List<String>> get allDatabasesNames async {
    return await m.protect<List<String>>(() async {
      await _ensureInitialized();
      return _allDbs!.map((e) => e.dbname).toList();
    });
  }

  @override
  Future<void> deleteDatabase(String name) async {
    await m.protect(() async {
      await _ensureInitialized();

      _log.fine('Deleting local database: $name');
      await _db.deleteDatabase(name);
      _dbCache.remove(name);
      await _updateAllDbs();
      _log.info('Local database deleted: $name');
    });
  }

  @override
  Future<LocalDartCouchDb?> db(final String name) async {
    final (LocalDartCouchDb? foundDb, bool wasInCache) = await m
        .protect<(LocalDartCouchDb?, bool)>(() async {
          await _ensureInitialized();
          final cached = _dbCache[name];
          if (cached != null) return (cached, true);

          final freshDb = _findDbByName(name);
          if (freshDb != null) {
            // _findDbByName returns instances already constructed with attachmentStorage
            _dbCache[name] = freshDb;
          }
          return (freshDb, false);
        });

    // Run migration only when the object is newly added to the cache,
    // matching the HttpDartCouchServer.db() wasInCache pattern.
    if (foundDb != null && !wasInCache && migration != null) {
      await migration!.migrate(foundDb);
    }

    return foundDb;
  }
}
