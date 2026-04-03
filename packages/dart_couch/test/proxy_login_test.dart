import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;

import 'package:dart_couch/dart_couch.dart';

import 'helper/helper.dart';

final _log = Logger('proxy_login_test');

const String _nginxImage = 'nginx:alpine';

/// Finds and kills ALL nginx:alpine containers, regardless of how they were
/// started. Safe to call even when no nginx container is running.
Future<void> shutdownAllNginxContainers() async {
  final result = await Process.run('docker', ['ps', '-a', '-q', '--filter', 'ancestor=$_nginxImage']);
  if (result.exitCode != 0) return;
  final ids = result.stdout.toString().trim();
  if (ids.isEmpty) return;

  for (final id in ids.split('\n')) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) continue;
    _log.info('Cleaning up nginx container: $trimmed');
    await Process.run('docker', ['stop', trimmed]);
    await Process.run('docker', ['rm', trimmed]);
  }
  _log.info('All nginx containers cleaned up.');
}

/// Starts an nginx container on port 5984 that returns a 404 HTML page
/// for all requests, simulating a misconfigured proxy/router.
Future<String> startNginx() async {
  final configDir = '${Directory.current.absolute.path}/nginx-test-config';
  final result = await Process.run('docker', [
    'run',
    '-d',
    '-p',
    '5984:5984',
    '--mount',
    'type=bind,src=$configDir,dst=/etc/nginx/conf.d/',
    _nginxImage,
  ]);
  if (result.exitCode != 0) {
    throw 'Failed to start nginx container: ${result.stderr}';
  }
  final containerId = result.stdout.toString().trim();
  _log.info('Nginx container started: $containerId');

  // Wait for nginx to be ready (accepting connections)
  int attempts = 0;
  while (attempts < 30) {
    try {
      final response = await http.get(Uri.parse('http://localhost:5984'));
      if (response.statusCode == 404) {
        _log.info('Nginx is up and returning 404.');
        break;
      }
    } catch (_) {}
    attempts++;
    await Future.delayed(Duration(milliseconds: 500));
  }
  if (attempts >= 30) {
    throw 'Nginx did not start in time.';
  }

  return containerId;
}

void main() {
  Logger.root.level = Level.FINEST;
  Logger.root.onRecord.listen((record) {
    final ls = LineSplitter();
    for (final line in ls.convert(record.message)) {
      // ignore: avoid_print
      print(
        '${record.loggerName} ${record.level.name}: ${record.time}: $line',
      );
    }
  });

  // Always clean up nginx containers, even if the test fails or throws.
  tearDown(() async {
    await shutdownAllNginxContainers();
  });

  test(
    'login with non-CouchDB response (proxy/nginx) goes to normalOffline',
    () async {
      // --- Phase 1: Start CouchDB, login, create DB, sync documents ---
      final localPath = prepareSqliteDir();

      HttpDartCouchServer httpServer =
          await setUpAllHttpFunction() as HttpDartCouchServer;

      final ofs = OfflineFirstServer();

      // Login to OfflineFirstServer while CouchDB is online
      final loginResult = await ofs.login(
        'http://localhost:5984',
        adminUser,
        adminPassword,
        localPath,
      );
      expect(loginResult, isNotNull);
      expect(loginResult!.success, isTrue);
      expect(ofs.state.value, OfflineFirstServerState.normalOnline);

      // Create a database and put some documents via HTTP (simulating another client)
      const dbName = 'testdb_proxy_login';
      await httpServer.createDatabase(dbName);

      final httpDb = await httpServer.db(dbName);
      for (int i = 1; i <= 3; i++) {
        await httpDb!.put(
          CouchDocumentBase(
            id: 'doc-$i',
            unmappedProps: {'name': 'Document $i', 'value': i * 10},
          ),
        );
      }

      // Wait for OfflineFirstServer to discover and sync the database
      await expectLater(
        waitForCondition(() async {
          return (await ofs.allDatabasesNames).contains(dbName);
        }, maxAttempts: 20),
        completion(isTrue),
        reason: 'Database was not created locally after _db_updates event',
      );

      final offlineDb = await ofs.db(dbName) as OfflineFirstDb;
      expect(offlineDb, isNotNull);

      // Wait for documents to sync
      await waitForSync(offlineDb, maxSeconds: 30);

      // Verify documents are synced locally
      for (int i = 1; i <= 3; i++) {
        final doc = await offlineDb.get('doc-$i');
        expect(doc, isNotNull, reason: 'doc-$i should be synced');
        expect(doc!.unmappedProps['name'], equals('Document $i'));
      }

      _log.info('Phase 1 complete: CouchDB online, DB synced with 3 docs.');

      // --- Phase 2: Dispose OfflineFirstServer and shut down CouchDB ---
      await ofs.dispose();
      await tearDownAllHttpFunction();

      _log.info('Phase 2 complete: OfflineFirstServer disposed, CouchDB down.');

      // --- Phase 3: Start nginx on port 5984 returning 404 HTML ---
      final nginxId = await startNginx();
      _log.info('Nginx container ID: $nginxId');

      // Verify nginx is responding with HTML 404 (not CouchDB JSON)
      final probeResponse = await http.post(
        Uri.parse('http://localhost:5984/_session'),
        headers: {'Content-Type': 'application/json'},
        body: '{"name":"admin","password":"admin"}',
      );
      expect(probeResponse.statusCode, 404);
      expect(
        probeResponse.body,
        contains('<html>'),
        reason: 'Nginx should return HTML, not CouchDB JSON',
      );

      _log.info(
        'Phase 3 complete: Nginx running on port 5984 returning HTML 404.',
      );

      // --- Phase 4: Restart OfflineFirstServer with nginx answering ---
      final ofs2 = OfflineFirstServer();

      final loginResult2 = await ofs2.login(
        'http://localhost:5984',
        adminUser,
        adminPassword,
        localPath,
      );

      // The login should succeed using cached credentials because a previous
      // login was successful. The non-CouchDB response from nginx must be
      // treated as a network error (not wrongCredentials), so
      // OfflineFirstServer falls back to cached credentials.
      expect(
        loginResult2,
        isNotNull,
        reason: 'Login should succeed with cached credentials',
      );
      expect(loginResult2!.success, isTrue);
      expect(
        ofs2.state.value,
        OfflineFirstServerState.normalOffline,
        reason:
            'Should be normalOffline (non-CouchDB response treated as network error)',
      );

      // Health monitoring should be active (trying to reconnect)
      expect(ofs2.isHealthMonitoringActive, isTrue);

      _log.info('Phase 4 complete: OfflineFirstServer in normalOffline state.');

      // --- Phase 5: Verify database is accessible and replication did NOT start ---
      final offlineDb2 = await ofs2.db(dbName) as OfflineFirstDb?;
      expect(
        offlineDb2,
        isNotNull,
        reason: 'Database should be available locally',
      );

      // Replication must NOT have started — nginx is not CouchDB, so the
      // connection state is loginFailedWithNetworkError and replication is
      // skipped entirely. The controller stays at its initial state.
      final replicationProgress =
          offlineDb2!.replicationController.progress.value;
      _log.info(
        'Replication state while nginx is answering: ${replicationProgress.state}',
      );
      expect(
        replicationProgress.state,
        ReplicationState.initializing,
        reason:
            'Replication should stay at initializing — never started against nginx',
      );
      expect(
        replicationProgress.state,
        isNot(ReplicationState.inSync),
        reason: 'Replication must not be in sync when nginx is answering',
      );
      expect(
        replicationProgress.state,
        isNot(ReplicationState.initialSyncInProgress),
        reason: 'Replication must not have started syncing against nginx',
      );

      // Verify all 3 documents are accessible from the local database
      for (int i = 1; i <= 3; i++) {
        final doc = await offlineDb2.get('doc-$i');
        expect(doc, isNotNull, reason: 'doc-$i should exist locally');
        expect(doc!.unmappedProps['name'], equals('Document $i'));
        expect(doc.unmappedProps['value'], equals(i * 10));
      }

      // Verify we can also write locally while "offline" with nginx blocking
      await offlineDb2.put(
        CouchDocumentBase(
          id: 'local-doc',
          unmappedProps: {'created': 'offline', 'source': 'proxy_test'},
        ),
      );
      final localDoc = await offlineDb2.get('local-doc');
      expect(localDoc, isNotNull, reason: 'Local write should succeed offline');
      expect(localDoc!.unmappedProps['created'], equals('offline'));

      _log.info(
        'Phase 5 complete: Local database accessible, '
        'replication not started, local write works.',
      );

      // --- Cleanup ---
      await ofs2.dispose();
      // nginx cleanup happens in tearDown
    },
    timeout: Timeout(Duration(minutes: 3)),
  );
}
