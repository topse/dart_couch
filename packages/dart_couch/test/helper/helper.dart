import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:test/test.dart';
// ignore: implementation_imports
import 'package:test_api/src/backend/invoker.dart';

import 'dart:convert';
import 'dart:io';

import 'package:dart_couch/dart_couch.dart';
import 'package:logging/logging.dart';

import 'package:http/http.dart' as http;

import 'couch_test_manager.dart';
import 'test_document_one.dart';

final String couchDbImage = 'couchdb:latest';

final log = Logger('dart_couch-test');

/// Whether to stream all log output live during tests.
///
/// By default logging is buffered and only printed for tests that fail, so a
/// passing run stays quiet. Enable live streaming of every log record with
/// either of:
///
///     flutter test --dart-define=ENABLE_LOGGING=true   # compile-time define
///     ENABLE_LOGGING=1 dart test                        # runtime env var
///
/// Both are supported because `dart test` does not forward `--dart-define`,
/// while `flutter test` does.
final bool enableLogging =
    const bool.fromEnvironment('ENABLE_LOGGING') || _envLoggingEnabled();

bool _envLoggingEnabled() {
  final v = Platform.environment['ENABLE_LOGGING']?.toLowerCase();
  return v != null && v.isNotEmpty && v != 'false' && v != '0';
}

bool _loggingConfigured = false;
final List<String> _logBuffer = [];

/// Configures logging for a test suite. Call once at the top of `main()`.
///
/// - With `--dart-define=ENABLE_LOGGING`, every log record is printed live
///   (the previous behaviour).
/// - Without it, records are buffered per test and only flushed to stdout when
///   that test fails, keeping the console clean for passing runs.
void configureTestLogging() {
  if (_loggingConfigured) return;
  _loggingConfigured = true;

  Logger.root.level = Level.FINEST;
  Logger.root.onRecord.listen((record) {
    final ls = LineSplitter();
    for (final line in ls.convert(record.message)) {
      final formatted =
          '${record.loggerName} ${record.level.name}: ${record.time}: $line';
      if (enableLogging) {
        // ignore: avoid_print
        print(formatted);
      } else {
        _logBuffer.add(formatted);
      }
    }
  });

  if (enableLogging) return;

  // Buffer logs per test; flush only on failure. The buffer is cleared at the
  // end of each test (below), so each test starts clean without a setUp hook —
  // this also keeps any setUpAll output attached to the first test in a group.
  tearDown(() {
    final failing = Invoker.current?.liveTest.state.result.isFailing ?? false;
    if (failing && _logBuffer.isNotEmpty) {
      // ignore: avoid_print
      print('\n--- captured logs for failed test ---');
      for (final line in _logBuffer) {
        // ignore: avoid_print
        print(line);
      }
      // ignore: avoid_print
      print('--- end captured logs ---\n');
    }
    _logBuffer.clear();
  });
}

final bool logCouchDb = false;
final bool couchdbAlreadyRunning = false;

final adminUser = "admin";
final adminPassword = "admin"; //uuid.v4(); // Generate a random password

// test/helpers/native_database.dart
String? dockerid;
HttpDartCouchServer? cc;

/// Label applied to every CouchDB container started by the test suite so that
/// leftover containers from crashed runs can be cleaned up selectively (see
/// `tool/clean_test_containers.sh`) without touching unrelated containers.
const String testContainerLabel = 'dart_couch_test';

/// Host port that Docker assigned to this suite's CouchDB container.
///
/// Each test *suite* runs in its own isolate, so this top-level variable is
/// effectively per-suite. It is set by [startCouchDb] (via a self-allocated
/// free port) and lets multiple suites run in parallel, each with its own
/// container/port.
int? couchPort;

/// Base URI of this suite's CouchDB container. Use this instead of a hardcoded
/// `http://localhost:5984` so parallel suites don't collide.
String get couchUri {
  final port = couchPort;
  if (port == null) {
    throw StateError(
      'couchUri accessed before startCouchDb() assigned a port. '
      'Did you forget to start a CouchDB container for this suite?',
    );
  }
  return 'http://localhost:$port';
}

/// Returns a `http://localhost:<port>` URI on a port where nothing is
/// listening, for simulating a permanently unreachable CouchDB server in
/// "offline" tests that never bring a container up.
///
/// We bind to an OS-assigned ephemeral port and immediately release it, so a
/// subsequent connection attempt is refused quickly. This replaces the old
/// "kill every container so port 5984 is dead" trick, which is incompatible
/// with parallel suites (it would kill siblings' live containers).
///
/// For *relogin* tests — where the server must come back up at the **same**
/// address — use [reserveCouchPort] instead so the dead and alive phases share
/// one URI ([couchUri]).
Future<String> deadCouchUri() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return 'http://localhost:$port';
}

/// Reserves this suite's host port and points [couchUri] at it **without**
/// starting a container. Nothing listens on the port yet, so [couchUri] is a
/// dead address — a login attempt fails with a network error. A subsequent
/// `startCouchDb(..., port: couchPort)` binds a container to this exact port,
/// so the *same* [couchUri] transitions dead → alive. That is the scenario a
/// relogin test needs: the server reconnects at the address it first failed on,
/// not at a different one.
Future<void> reserveCouchPort() async {
  couchPort = await CouchTestManager.findFreePort();
}
Future<DartCouchServer> setUpAllHttpFunction() async {
  cc = HttpDartCouchServer();
  cc!.checkRevsAlgorithmForDebugging = true;
  if (couchdbAlreadyRunning == false) {
    dockerid = await startCouchDb(adminUser, adminPassword, logCouchDb);
  }
  await doLogin(cc!, adminUser, adminPassword);
  return cc!;
}

Future<void> tearDownAllHttpFunction() async {
  // This is called after all tests in the group have run.
  // You can use it to clean up resources or perform final checks.

  // why wait here? if we shutdown the container immediately, we might not see the logs in case of test failures. We should probably wait until all logs are flushed before shutting down the container?
  //await Future.delayed(Duration(seconds: 1));
  await cc!.logout();
  if (couchdbAlreadyRunning == false) {
    await shutdownCouchDb(dockerid!);
    cc = null;
    dockerid = null;
  }
  return Future.value();
}

Future<DartCouchServer> setUpAllLocalFunction() async {
  final sqliteDir = prepareSqliteDir();
  final cl = LocalDartCouchServer(sqliteDir);
  log.info('Using local database at $sqliteDir');
  return cl;
}

Future<void> doLogin(
  HttpDartCouchServer cc,
  String adminUser,
  String password,
) async {
  final res = await cc.login(couchUri, adminUser, password);
  expect(res, isNotNull);
  expect(res!.success, isTrue);
  expect(res.statusCode, CouchDbStatusCodes.ok);
}


Logger couchLogger = Logger('COUCHDB');
Process? couchLogProcess;
Future<void> startCouchLogging(String dockerid) async {
  assert(couchLogProcess == null, 'Docker log process is already running.');
  couchLogProcess = await Process.start('docker', ['logs', "-f", dockerid]);

  // All messages seem to come from stderr, so we listen to stderr
  // and filter out the ones we want to log.
  couchLogProcess!.stdout.transform(utf8.decoder).listen((data) {
    couchLogger.info(data);
  });

  couchLogProcess!.stderr.transform(utf8.decoder).listen((data) {
    if (data.contains("[notice]") ||
        data.contains("[debug]") ||
        data.contains("[info]")) {
      couchLogger.info(data);
    } else {
      couchLogger.severe(data);
    }
  });
}

Future<void> pauseCouchDbContainer(String dockerid) async {
  if (couchLogProcess != null) {
    couchLogProcess!.kill();
    couchLogProcess = null;
  }

  ProcessResult result = await Process.run('docker', [
    'container',
    'stop',
    dockerid,
  ]);
  if (result.exitCode != 0) {
    throw ('Failed to stop container: ${result.stderr}');
  }
  await waitForCouchDbShutdown(dockerid);
}

Future<void> restartCouchDbContainer(String dockerid) async {
  if (couchLogProcess != null) {
    couchLogProcess!.kill();
    couchLogProcess = null;
  }

  ProcessResult result = await Process.run('docker', [
    'container',
    'start',
    dockerid,
  ]);
  if (result.exitCode != 0) {
    throw ('Failed to start container: ${result.stderr}');
  }
  await waitForCouchDb(dockerid);
}

Future<String> startCouchDb(
  String adminUser,
  String password,
  bool logCouchDB, {
  int? port,
}) async {
  // Self-allocate an explicit host port instead of Docker's `-p 0:5984`. A
  // `0:5984` mapping is re-randomized on every `docker start`, which breaks the
  // pause/restart tests (pauseCouchDbContainer/restartCouchDbContainer): the
  // long-lived OfflineFirstServer would point at the old, now-dead port. An
  // explicit `-p <port>:5984` mapping is preserved across stop/start.
  //
  // [port] pins a specific host port — pass the [reserveCouchPort]-reserved
  // [couchPort] so a relogin test brings the server up at the exact address it
  // first failed on. When null we allocate a fresh free port via
  // CouchTestManager.findFreePort, which leaves a tiny window where another
  // suite/process could grab it before `docker run` binds it. On that rare
  // collision Docker fails with "port is already allocated"; we re-allocate and
  // retry. A pinned port must not change, so a collision there fails loudly.
  String dockerid = "";
  ProcessResult result;
  const maxPortAttempts = 5;
  for (var attempt = 1; ; attempt++) {
    couchPort = port ?? await CouchTestManager.findFreePort();
    result = await Process.run('docker', [
      'run',
      '-e',
      'COUCHDB_USER=$adminUser',
      '-e',
      'COUCHDB_PASSWORD=$password',
      '-d',
      '--label',
      testContainerLabel,
      '-p',
      '$couchPort:5984',
      '--mount',
      'type=bind,src=${Directory.current.absolute.path}/couchdb-test-config,dst=/opt/couchdb/etc/local.d/',
      couchDbImage,
    ]);
    if (result.exitCode == 0) break;
    final stderr = result.stderr.toString();
    final portTaken =
        stderr.contains('port is already allocated') ||
        stderr.contains('address already in use');
    // Only retry with a NEW port when we're free to choose one. A pinned port
    // (relogin test) must stay fixed, so a collision there is a hard failure.
    if (!portTaken || port != null || attempt >= maxPortAttempts) {
      throw ('Failed to start container: $stderr');
    }
    log.info(
      'Port $couchPort was taken before docker could bind it '
      '(attempt $attempt/$maxPortAttempts), retrying with a new port...',
    );
  }
  dockerid = result.stdout.toString().trim();
  // Wait for CouchDB to start
  log.info('Waiting for CouchDB to start on $couchUri ...');
  await waitForCouchDb(dockerid);

  if (logCouchDB) {
    await startCouchLogging(dockerid);
  }

  try {
    // need to create _global_changes database, its not done automatically...??
    final createDbRes = await http.put(
      Uri.parse("http://$adminUser:$password@localhost:$couchPort/_global_changes"),
    );
    if (createDbRes.statusCode != 201) {
      throw ('Failed to create _global_changes database: ${createDbRes.body}');
    }
  } catch (e) {
    log.severe('Failed to create _global_changes database: $e');
    rethrow;
  }
  return dockerid;
}

Future<void> waitForCouchDb(String dockerid, [int maxAttempts = 30]) async {
  int attempts = 0;
  while (attempts < maxAttempts) {
    try {
      final response = await http.get(Uri.parse(couchUri));

      if (response.statusCode == 200) {
        log.info('CouchDB is up and running.');
        break;
      }
      log.info('CouchDB is not ready yet, retrying...');
      // ignore: empty_catches
    } catch (e) {}
    attempts++;
    await Future.delayed(Duration(milliseconds: 500));
  }
  if (attempts >= maxAttempts) {
    fail('CouchDB did not start in time.');
  }
  log.info('CouchDB started with container ID: $dockerid');
}

Future<void> waitForCouchDbShutdown(
  String dockerid, [
  int maxAttempts = 30,
]) async {
  int attempts = 0;
  while (attempts < maxAttempts) {
    try {
      final response = await http.get(Uri.parse(couchUri));

      if (response.statusCode == 200) {
        log.info('CouchDB is up and running.');
        attempts++;
      }
    } catch (e) {
      log.info('CouchDB is shut down.');
      break;
    }
    await Future.delayed(Duration(milliseconds: 500));
  }
  if (attempts >= maxAttempts) {
    fail('CouchDB did not start in time.');
  }
  log.info('CouchDB container is shutdown, id: $dockerid');
}

Future<void> shutdownCouchDb(String dockerid) async {
  log.info('Shutting down CouchDB container: $dockerid');
  ProcessResult result = await Process.run('docker', ['stop', dockerid]);
  if (result.exitCode != 0) {
    throw ('Failed to stop container: ${result.stderr}');
  }
  await waitForCouchDbShutdown(dockerid);
  log.info('$dockerid stopped.');
  couchLogProcess?.kill();
  couchLogProcess = null;
  // Remove only this container and its anonymous volumes (-v). No global
  // `docker container/volume prune`, which would clobber parallel suites.
  result = await Process.run('docker', ['rm', '-fv', dockerid]);
  if (result.exitCode != 0) {
    throw ('Failed to remove container: ${result.stderr}');
  }
  log.info('$dockerid removed.');
}

Directory prepareSqliteDir() {
  // Each call returns a fresh, uniquely-named temp directory. Unique paths are
  // required for parallel suites (and even concurrent isolates in one process):
  // drift/sqlite only conflicts when two opens hit the *same* file, so distinct
  // directories keep suites fully isolated. createTempSync guarantees a unique
  // name with no race, replacing the old fixed `dart_couch_test` dir.
  return Directory.systemTemp.createTempSync('dart_couch_test_');
}

Future<bool> waitForServerState(
  OfflineFirstServer ofs,
  OfflineFirstServerState expectedState, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  if (ofs.state.value == expectedState) {
    return true;
  }

  final completer = Completer<void>();
  void listener() {
    if (ofs.state.value == expectedState) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  ofs.state.addListener(listener);
  try {
    await completer.future.timeout(timeout, onTimeout: () => null);
    if (ofs.state.value != expectedState) {
      log.warning(
        'Timeout waiting for server state to change to $expectedState. '
        'Current state: ${ofs.state.value}',
      );
      return false;
    }
    return true;
  } finally {
    ofs.state.removeListener(listener);
  }
}

Future<void> waitForReplicationState(
  OfflineFirstDb db,
  ReplicationState expectedState, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final controller = db.replicationController;
  if (controller.progress.value.state == expectedState) {
    return;
  }

  final completer = Completer<void>();
  void listener() {
    if (controller.progress.value.state == expectedState) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  controller.progress.addListener(listener);
  try {
    await completer.future.timeout(
      timeout,
      onTimeout: () {
        throw TimeoutException(
          'Replication state did not change to $expectedState within ${timeout.inSeconds}s. '
          'Current state: ${controller.progress.value.state}',
        );
      },
    );
  } finally {
    controller.progress.removeListener(listener);
  }
}

Future<bool> waitForCondition(
  Future<bool> Function() testCondition, {
  int maxAttempts = 20,
  Duration interval = const Duration(milliseconds: 500),
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    if (await testCondition()) {
      return true;
    }
    await Future.delayed(interval);
  }

  return false;
}

Future<void> waitForSync(OfflineFirstDb db, {int maxSeconds = 10}) async {
  final startTime = DateTime.now();
  final initialProgress = db.replicationController.progress.value;
  final initialTransferCount = initialProgress.transferredDocs;
  final initialLastSeq = initialProgress.lastSeq;

  // First, wait for replication to start processing (not inSync immediately)
  bool sawSyncing =
      initialProgress.state == ReplicationState.initialSyncInProgress;
  if (!sawSyncing &&
      initialProgress.state == ReplicationState.inSync &&
      initialProgress.targetReachable) {
    // Replication already completed before we started waiting; treat this as
    // having seen the syncing phase to avoid missing the state transition.
    sawSyncing = true;
  }
  while (DateTime.now().difference(startTime).inSeconds < maxSeconds) {
    final progress = db.replicationController.progress.value;
    log.fine("waitForSync progress: $progress");

    if (progress.state == ReplicationState.initialSyncInProgress) {
      sawSyncing = true;
    }

    final hasNewTransfer = progress.transferredDocs > initialTransferCount;
    final lastSeqAdvanced = progress.lastSeq != initialLastSeq;
    final hasReplicationWork = hasNewTransfer || lastSeqAdvanced;

    // Only accept inSync/syncSuccess after we've seen it actually syncing
    if ((sawSyncing || hasReplicationWork) &&
        (progress.state == ReplicationState.inSync ||
            progress.state == ReplicationState.initialSyncComplete)) {
      // Give it a bit more time to ensure server write completes
      await Future.delayed(Duration(milliseconds: 500));
      return;
    }

    await Future.delayed(Duration(milliseconds: 100));
  }

  throw TimeoutException(
    'Replication did not reach sync state within $maxSeconds seconds. '
    'Last progress: ${db.replicationController.progress.value}',
  );
}

final List vegetables = ["Apfel", "Banane", "Erdbeeren", "Granatapfel", "Kiwi"];

Future<List<TestDocumentOne>> createTestDocuments(
  DartCouchDb db,
  int num,
) async {
  assert(num <= 5, 'Can only create up to 5 test documents.');
  List<TestDocumentOne> fiveDocs = [];

  for (int i = 0; i < num; ++i) {
    final doc = TestDocumentOne(
      id: vegetables[i],
      name: "About ${vegetables[i]}",
    );
    fiveDocs.add((await db.put(doc)) as TestDocumentOne);
  }

  return fiveDocs;
}

Future<List<TestDocumentOne>> createFiveDocuments(DartCouchDb db) {
  return createTestDocuments(db, 5);
}

/// Simulates database deletion by another app instance using the tombstone mechanism.
///
/// This creates a temporary OfflineFirstServer instance, deletes the database
/// (which creates proper tombstone markers), and disposes the instance.
/// This is the correct way to test database deletion in a multi-instance scenario.
Future<void> deleteDatabaseViaAnotherInstance({
  required String serverUrl,
  required String username,
  required String password,
  required String dbName,
}) async {
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  log.info('Simulating database deletion by another app instance: $dbName');

  // Create a temporary OfflineFirstServer instance (simulating another app)
  final tempServer = OfflineFirstServer();

  // Use a different temporary SQLite directory for this instance
  final tempDir = Directory.systemTemp.createTempSync('dart_couch_other_');

  try {
    // Login with the temporary instance
    await tempServer.login(serverUrl, username, password, tempDir);

    log.info('Temporary instance logged in, deleting database $dbName');

    // Delete the database - this will create proper tombstone markers
    await tempServer.deleteDatabase(dbName);

    log.info('Database $dbName deleted by temporary instance');
  } finally {
    // Clean up the temporary instance
    await tempServer.dispose();

    // Clean up the temporary SQLite directory
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  }
}
