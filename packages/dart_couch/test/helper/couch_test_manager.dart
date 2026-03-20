import 'dart:convert';
import 'dart:io';

import 'package:dart_couch/dart_couch.dart';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

final _log = Logger('dart_couch-test-couch_test_manager');

class CouchTestManager {
  final String couchDbImage = 'couchdb:latest';
  static const String uri = 'http://localhost:5984';
  static const String testDbName = 'couch_test_db';
  static const String adminUser = 'admin';
  static const String adminPassword = 'admin';

  String? dockerid;
  Directory? _localPath;

  Directory get localPath => _localPath!;

  DatabaseMigration? migration;

  HttpDartCouchServer? _httpServer;
  HttpDartCouchDb? _httpDb;

  OfflineFirstServer? _offlineFirstServer;
  OfflineFirstDb? _offlineDb;

  LocalDartCouchServer? _localServer;
  LocalDartCouchDb? _localDb;

  bool _isOfflineFirstServerPaused = false;

  bool _isCouchDbPaused = false;

  CouchTestManager({this.migration});

  /// call in setUpAll to initialize resources
  Future<void> init() async {
    _log.info('CouchTestManager.init()');
    await _shutdownAllCouchDbContainers();
    dockerid = await _startCouchDb(adminUser, adminPassword, false);

    _localPath = _prepareSqliteDir();
    _log.info('Prepared SQLite directory at $_localPath');
    _log.info('CouchDB container started with ID: $dockerid');
  }

  /// call in tearDownAll to clean up resources
  Future<void> dispose() async {
    _log.info('CouchTestManager.dispose()');
    await _shutdownCouchDb(dockerid!);
    await _shutdownAllCouchDbContainers();
    dockerid = null;
    _log.info('CouchDB container shutdown and cleaned up');
  }

  /// don't precreate server or database, just ensure we have a clean state for each test
  /// some tests may choose to call httpServer() or offlineServer() to create them as needed,
  /// and this allows for testing different scenarios (e.g. starting with just HTTP server and
  /// no OfflineFirstServer, or starting with both)
  Future<void> prepareNewTest() async {
    _log.info('CouchTestManager.prepareNewTest()');
    // Ensure we have a clean state for each test
    await _cleanupHelper();
  }

  /// Cleans up test resources - disposes server and shuts down container
  Future<void> cleanupAfterTest() async {
    _log.info('CouchTestManager.cleanupAfterTest()');
    await _cleanupHelper();
  }

  Future<void> _cleanupHelper() async {
    await _offlineFirstServer?.dispose();
    await _localServer?.dispose();
    if (_isCouchDbPaused) {
      await resumeContainer();
    }
    try {
      await (await httpServer()).deleteDatabase(testDbName);
    } on CouchDbException catch (_) {
    } on NetworkFailure catch (_) {}
    await _httpServer?.dispose();
    _localPath = _prepareSqliteDir();
    _offlineFirstServer = null;
    _httpServer = null;
    _offlineDb = null;
    _httpDb = null;
    _localServer = null;
    _localDb = null;
    _isOfflineFirstServerPaused = false;
    migration = null;
  }

  /// Stops the Docker container to simulate network outage.
  /// The OfflineFirstServer stays alive and detects the network failure on its own.
  /// The direct HttpDartCouchServer/Db are disposed since they talk to CouchDB directly.
  Future<void> pauseContainer() async {
    _log.info('CouchTestManager.pauseContainer()');

    final result = await Process.run('docker', ['stop', dockerid!]);
    if (result.exitCode != 0) {
      throw ('Failed to stop container: ${result.stderr}');
    }
    await _waitForCouchDbShutdown(dockerid!);
    _log.info('CouchTestManager.pauseContainer() - container stopped');
    _isCouchDbPaused = true;
  }

  /// Restarts the Docker container after a pause.
  /// Connections are recreated lazily on next access.
  Future<void> resumeContainer() async {
    _log.info('CouchTestManager.resumeContainer()');

    try {
      await _httpServer?.dispose();
    } on NetworkFailure catch (_) {}
    _httpServer = null;
    _httpDb = null;

    final result = await Process.run('docker', ['start', dockerid!]);
    if (result.exitCode != 0) {
      throw ('Failed to start container: ${result.stderr}');
    }
    await _waitForCouchDb(dockerid!);
    _log.info('CouchTestManager.resumeContainer() - container started');

    _isCouchDbPaused = false;
  }

  /// keeps sqlite database but disposes the OfflineFirstServer to simulate a scenario
  /// where the server is not available (e.g. app is offline)
  Future<void> pauseOfflineFirstDb() async {
    _log.info('CouchTestManager.pauseOfflineFirstDb()');
    await _offlineFirstServer!.dispose();
    _offlineFirstServer = null;
    _offlineDb = null;
    _httpDb = null;
    _log.info(
      'OfflineFirstServer paused, database is closed but container is still running',
    );
    _isOfflineFirstServerPaused = true;
  }

  Future<void> resumeOfflineFirstDb() async {
    _log.info('CouchTestManager.resumeOfflineFirstDb()');
    _isOfflineFirstServerPaused = false;
  }

  /// httpServer and httpDb are kind of stateless, so its ok to dispose them during pause
  /// since they will be recreated on next access. The OfflineFirstServer is more stateful
  /// and keeps the sqlite database, so we keep it alive during pause and just dispose
  /// it when we need to simulate the server being unavailable.
  Future<HttpDartCouchServer> httpServer() async {
    if (_httpServer == null) {
      _httpServer = HttpDartCouchServer();
      _httpServer!.checkRevsAlgorithmForDebugging = true;
      await _httpServer!.login(uri, adminUser, adminPassword);
    }
    return _httpServer!;
  }

  Future<HttpDartCouchDb> httpDb() async {
    if (_httpDb == null) {
      final server = await httpServer();
      _httpDb = await server.db(testDbName);
      _httpDb ??= await server.createDatabase(testDbName) as HttpDartCouchDb;
    }
    return _httpDb!;
  }

  Future<OfflineFirstServer> offlineServer() async {
    if (_isOfflineFirstServerPaused) {
      throw Exception(
        'Cannot get OfflineFirstServer while it is paused. Please call resumeOfflineFirstDb() first.',
      );
    }
    if (_offlineFirstServer == null) {
      _offlineFirstServer = OfflineFirstServer(migration: migration);
      final loginResult = await _offlineFirstServer!.login(
        uri,
        adminUser,
        adminPassword,
        _localPath!,
      );

      if (loginResult == null || !loginResult.success) {
        throw Exception('Failed to login to OfflineFirstServer');
      }
    }
    return _offlineFirstServer!;
  }

  Future<OfflineFirstDb> offlineDb() async {
    if (_isOfflineFirstServerPaused) {
      throw Exception(
        'Cannot get OfflineFirstServer while it is paused. Please call resumeOfflineFirstDb() first.',
      );
    }
    if (_offlineDb == null) {
      final server = await offlineServer();
      _offlineDb = await server.db(testDbName) as OfflineFirstDb?;
      _offlineDb ??= await server.createDatabase(testDbName) as OfflineFirstDb;
    }
    return _offlineDb!;
  }

  Future<LocalDartCouchServer> localServer() async {
    _localServer ??= LocalDartCouchServer(localPath);
    return _localServer!;
  }

  Future<LocalDartCouchDb> localDb() async {
    if (_localDb == null) {
      final server = await localServer();
      _localDb = await server.db(testDbName);
      _localDb ??= await server.createDatabase(testDbName) as LocalDartCouchDb;
    }
    return _localDb!;
  }

  Future<void> _shutdownAllCouchDbContainers() async {
    ProcessResult result = await Process.run('docker', ['ps']);
    if (result.exitCode != 0) {
      throw ('Failed to list containers: ${result.stderr}');
    }
    final containers = result.stdout.toString().trim().split('\n');
    for (int i = 1; i < containers.length; i++) {
      final fields = containers[i].split(RegExp(r'\s+'));
      if (fields[1] == couchDbImage) {
        await _shutdownCouchDb(fields[0]);
      }
    }

    result = await Process.run('docker', ['container', 'prune']);
    if (result.exitCode != 0) {
      throw ('Failed to prune container: ${result.stderr}');
    }
    result = await Process.run('docker', ['volume', 'prune']);
    if (result.exitCode != 0) {
      throw ('Failed to prune volume: ${result.stderr}');
    }
    _log.info('Docker container prune completed.');
  }

  Future<String> _startCouchDb(
    String adminUser,
    String password,
    bool logCouchDB,
  ) async {
    String dockerid = "";
    ProcessResult result = await Process.run('docker', [
      'run',
      '-e',
      'COUCHDB_USER=$adminUser',
      '-e',
      'COUCHDB_PASSWORD=$password',
      '-d',
      '-p',
      '5984:5984',
      '--mount',
      'type=bind,src=${Directory.current.absolute.path}/couchdb-test-config,dst=/opt/couchdb/etc/local.d/',
      couchDbImage,
    ]);
    if (result.exitCode != 0) {
      throw ('Failed to start container: ${result.stderr}');
    }
    dockerid = result.stdout.toString().trim();
    // Wait for CouchDB to start
    _log.info('Waiting for CouchDB to start...');
    await _waitForCouchDb(dockerid);

    if (logCouchDB) {
      await startCouchLogging(dockerid);
    }

    try {
      // need to create _global_changes database, its not done automatically...??
      final createDbRes = await http.put(
        Uri.parse("http://$adminUser:$password@localhost:5984/_global_changes"),
      );
      if (createDbRes.statusCode != 201) {
        throw ('Failed to create _global_changes database: ${createDbRes.body}');
      }
    } catch (e) {
      _log.severe('Failed to create _global_changes database: $e');
      rethrow;
    }
    return dockerid;
  }

  Future<void> _shutdownCouchDb(String dockerid) async {
    _log.info('Shutting down CouchDB container: $dockerid');
    ProcessResult result = await Process.run('docker', ['stop', dockerid]);
    if (result.exitCode != 0) {
      throw ('Failed to stop container: ${result.stderr}');
    }
    await _waitForCouchDbShutdown(dockerid);
    _log.info('$dockerid stopped.');
    _couchLogProcess?.kill();
    _couchLogProcess = null;
    result = await Process.run('docker', ['container', 'remove', dockerid]);
    if (result.exitCode != 0) {
      throw ('Failed to remove container: ${result.stderr}');
    }
    _log.info('$dockerid removed.');
    result = await Process.run('docker', ['container', 'prune']);
    if (result.exitCode != 0) {
      throw ('Failed to prune container: ${result.stderr}');
    }
    result = await Process.run('docker', ['volume', 'prune']);
    if (result.exitCode != 0) {
      throw ('Failed to prune volume: ${result.stderr}');
    }
    _log.info('Docker container prune completed.');
  }

  Future<void> _waitForCouchDbShutdown(
    String dockerid, [
    int maxAttempts = 30,
  ]) async {
    int attempts = 0;
    while (attempts < maxAttempts) {
      try {
        final response = await http.get(Uri.parse(uri));

        if (response.statusCode == 200) {
          _log.info('CouchDB is up and running.');
          attempts++;
        }
      } catch (e) {
        _log.info('CouchDB is shut down.');
        break;
      }
      await Future.delayed(Duration(milliseconds: 500));
    }
    if (attempts >= maxAttempts) {
      fail('CouchDB did not start in time.');
    }
    _log.info('CouchDB container is shutdown, id: $dockerid');
  }

  Future<void> _waitForCouchDb(String dockerid, [int maxAttempts = 30]) async {
    int attempts = 0;
    while (attempts < maxAttempts) {
      try {
        final response = await http.get(Uri.parse(uri));

        if (response.statusCode == 200) {
          _log.info('CouchDB is up and running.');
          break;
        }
        _log.info('CouchDB is not ready yet, retrying...');
        // ignore: empty_catches
      } catch (e) {}
      attempts++;
      await Future.delayed(Duration(milliseconds: 500));
    }
    if (attempts >= maxAttempts) {
      fail('CouchDB did not start in time.');
    }
    _log.info('CouchDB started with container ID: $dockerid');
  }

  final Logger _couchLogger = Logger('COUCHDB');
  Process? _couchLogProcess;
  Future<void> startCouchLogging(String dockerid) async {
    assert(_couchLogProcess == null, 'Docker log process is already running.');
    _couchLogProcess = await Process.start('docker', ['logs', "-f", dockerid]);

    // All messages seem to come from stderr, so we listen to stderr
    // and filter out the ones we want to _log.
    _couchLogProcess!.stdout.transform(utf8.decoder).listen((data) {
      _couchLogger.info(data);
    });

    _couchLogProcess!.stderr.transform(utf8.decoder).listen((data) {
      if (data.contains("[notice]") ||
          data.contains("[debug]") ||
          data.contains("[info]")) {
        _couchLogger.info(data);
      } else {
        _couchLogger.severe(data);
      }
    });
  }

  Directory _prepareSqliteDir() {
    // as we are in Linux, directories can be deleted even if still in use by another process
    final dirPath = path.join(Directory.systemTemp.path, 'dart_couch');
    final dir = Directory(dirPath);

    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }

    return dir;
  }
}
