import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:test/test.dart';

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

import 'package:dart_couch/dart_couch.dart';
import 'package:logging/logging.dart';

import 'package:http/http.dart' as http;

import 'test_document_one.dart';

final String couchDbImage = 'couchdb:latest';

final log = Logger('dart_couch-test');

final bool logCouchDb = false;
final bool couchdbAlreadyRunning = false;

final adminUser = "admin";
final adminPassword = "admin"; //uuid.v4(); // Generate a random password

// test/helpers/native_database.dart
String? dockerid;
HttpDartCouchServer? cc;
Future<DartCouchServer> setUpAllHttpFunction() async {
  cc = HttpDartCouchServer();
  cc!.checkRevsAlgorithmForDebugging = true;
  if (couchdbAlreadyRunning == false) {
    await shutdownAllCouchDbContainers();
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
  final res = await cc.login('http://localhost:5984', adminUser, password);
  expect(res, isNotNull);
  expect(res!.success, isTrue);
  expect(res.statusCode, CouchDbStatusCodes.ok);
}

Future<void> shutdownAllCouchDbContainers() async {
  ProcessResult result = await Process.run('docker', ['ps']);
  if (result.exitCode != 0) {
    throw ('Failed to list containers: ${result.stderr}');
  }
  final containers = result.stdout.toString().trim().split('\n');
  for (int i = 1; i < containers.length; i++) {
    final fields = containers[i].split(RegExp(r'\s+'));
    if (fields[1] == couchDbImage) {
      await shutdownCouchDb(fields[0]);
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
  log.info('Docker container prune completed.');
}

Future<String> getCouchDbContainerId() async {
  ProcessResult result = await Process.run('docker', ['ps']);
  if (result.exitCode != 0) {
    throw ('Failed to list containers: ${result.stderr}');
  }
  final containers = result.stdout.toString().trim().split('\n');
  for (int i = 1; i < containers.length; i++) {
    final fields = containers[i].split(RegExp(r'\s+'));
    if (fields[1] == couchDbImage) {
      return fields[0];
    }
  }
  throw ('No CouchDB container found.');
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
  log.info('Waiting for CouchDB to start...');
  await waitForCouchDb(dockerid);

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
    log.severe('Failed to create _global_changes database: $e');
    rethrow;
  }
  return dockerid;
}

Future<void> waitForCouchDb(String dockerid, [int maxAttempts = 30]) async {
  int attempts = 0;
  while (attempts < maxAttempts) {
    try {
      final response = await http.get(Uri.parse('http://localhost:5984'));

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
      final response = await http.get(Uri.parse('http://localhost:5984'));

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
  result = await Process.run('docker', ['container', 'remove', dockerid]);
  if (result.exitCode != 0) {
    throw ('Failed to remove container: ${result.stderr}');
  }
  log.info('$dockerid removed.');
  result = await Process.run('docker', ['container', 'prune']);
  if (result.exitCode != 0) {
    throw ('Failed to prune container: ${result.stderr}');
  }
  result = await Process.run('docker', ['volume', 'prune']);
  if (result.exitCode != 0) {
    throw ('Failed to prune volume: ${result.stderr}');
  }
  log.info('Docker container prune completed.');
}

Directory prepareSqliteDir() {
  // as we are in Linux, directories can be deleted even if still in use by another process
  final dirPath = path.join(Directory.systemTemp.path, 'dart_couch_test');
  final dir = Directory(dirPath);

  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }

  return dir;
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
  final tempDirPath = path.join(
    Directory.systemTemp.path,
    'dart_couch_${DateTime.now().millisecondsSinceEpoch}',
  );
  final tempDir = Directory(tempDirPath);

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
