import 'dart:convert';

import 'package:dart_couch/dart_couch.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'helper/helper.dart';

// Like pause_resume_test.dart this suite asserts on log contents, so it
// registers a second listener that keeps full LogRecord objects.
final List<LogRecord> capturedLogs = [];

bool hasLogMessage(String substring) =>
    capturedLogs.any((log) => log.message.contains(substring));

int countLogMessages(String substring) =>
    capturedLogs.where((log) => log.message.contains(substring)).length;

/// Seconds announced by the most recent "Retrying in Ns" progress message of
/// [db]'s replication controller, or null if there is none.
int? retryDelaySeconds(OfflineFirstDb db) {
  final message = db.replicationController.progress.value.message;
  if (message == null) return null;
  final match = RegExp(r'Retrying in (\d+)s').firstMatch(message);
  return match == null ? null : int.parse(match.group(1)!);
}

bool isInSync(OfflineFirstDb db) {
  final state = db.replicationController.progress.value.state;
  return state == ReplicationState.inSync ||
      state == ReplicationState.initialSyncComplete;
}

void main() {
  configureTestLogging();
  Logger.root.onRecord.listen(capturedLogs.add);

  group('retryNow / checkHealthNow', () {
    late OfflineFirstServer server;
    late Directory localFile;
    String? dockerId;

    setUp(() async {
      capturedLogs.clear();

      // Pin the port: some tests stop and restart the container and the
      // server must find it again at the same address.
      await reserveCouchPort();
      dockerId = await startCouchDb(
        adminUser,
        adminPassword,
        false,
        port: couchPort,
      );
      localFile = prepareSqliteDir();

      // The periodic health timer can never be what recovers in these tests.
      server = OfflineFirstServer(
        conflictResolver: null,
        healthCheckInterval: const Duration(hours: 1),
      );

      final loginResult = await server.login(
        couchUri,
        adminUser,
        adminPassword,
        localFile,
      );
      expect(loginResult, isNotNull);
      expect(loginResult!.success, true);
      expect(
        await waitForServerState(server, OfflineFirstServerState.normalOnline),
        true,
      );
    });

    tearDown(() async {
      await server.dispose();
      if (dockerId != null) {
        await shutdownCouchDb(dockerId!);
        dockerId = null;
      }
    });

    Future<OfflineFirstDb> createSyncedDb(String name) async {
      final db = await server.createDatabase(name) as OfflineFirstDb;
      expect(await waitForCondition(() async => isInSync(db)), true);
      return db;
    }

    test('resume() recovers an expired session without waiting for the '
        'health timer', () async {
      final db = await createSyncedDb('retry_now_expired_session');

      await server.pause();
      expect(
        db.replicationController.progress.value.state,
        ReplicationState.terminated,
      );

      // Invalidate every session cookie server-side: cookies are signed with a
      // key derived from the admin's password salt, and re-setting the (same)
      // password makes CouchDB re-hash it with a fresh salt. Hashing finishes
      // asynchronously, so wait until the new hash is stored. The
      // X-Couch-Persist header keeps the bind-mounted local.ini untouched.
      final admin = http.Client();
      final adminHeaders = {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$adminUser:$adminPassword'))}',
        'Content-Type': 'application/json',
        'X-Couch-Persist': 'false',
      };
      final adminCfg = Uri.parse(
        '$couchUri/_node/_local/_config/admins/$adminUser',
      );
      final oldHash = (await admin.get(adminCfg, headers: adminHeaders)).body;
      final response = await admin.put(
        adminCfg,
        headers: adminHeaders,
        body: jsonEncode(adminPassword),
      );
      expect(response.statusCode, 200, reason: response.body);
      expect(
        await waitForCondition(() async {
          final hash = (await admin.get(adminCfg, headers: adminHeaders)).body;
          // The plaintext is stored first and replaced by the hash.
          return hash != oldHash && hash.contains('-pbkdf2');
        }),
        true,
        reason: 'admin password was not re-hashed',
      );
      admin.close();

      // The session cookie held by the server is now rejected.
      final stale = await server.httpServer.session();
      expect(stale.userCtx.name, isNull);

      await server.resume();

      // The health interval is one hour: only resume()'s immediate re-check
      // can make this succeed.
      expect(
        await waitForServerState(server, OfflineFirstServerState.normalOnline),
        true,
      );
      expect(await waitForCondition(() async => isInSync(db)), true);
      expect(server.isHealthMonitoringActive, true);
    });

    test('retryNow() recovers right after the network is back, not after '
        'the replication backoff', () async {
      final db = await createSyncedDb('retry_now_network');

      await pauseCouchDbContainer(dockerId!); // docker stop
      // Let the server notice the outage (the periodic timer will not).
      await server.checkHealthNow();
      expect(server.state.value, OfflineFirstServerState.normalOffline);

      // Wait until the controller is backing off for at least 16 s, so that
      // without retryNow() recovery would take that long.
      expect(
        await waitForCondition(
          () async => (retryDelaySeconds(db) ?? 0) >= 16,
          maxAttempts: 120,
        ),
        true,
        reason: 'controller never reached a backoff of >= 16s',
      );

      await restartCouchDbContainer(dockerId!);
      await server.retryNow();

      expect(
        await waitForServerState(
          server,
          OfflineFirstServerState.normalOnline,
          timeout: const Duration(seconds: 5),
        ),
        true,
      );
      expect(
        await waitForCondition(() async => isInSync(db), maxAttempts: 10),
        true,
        reason: 'replication did not recover well within the backoff delay',
      );
    });

    test('ReplicationController.retryNow() ends a backoff wait', () async {
      final db = await createSyncedDb('retry_now_controller');

      await pauseCouchDbContainer(dockerId!);
      expect(
        await waitForCondition(
          () async => retryDelaySeconds(db) == 4,
          maxAttempts: 60,
        ),
        true,
        reason: 'controller never reached the 4s backoff step',
      );

      // The 4 s wait has just started; without the hint the next failure (and
      // its "Retrying in 8s" message) only comes after those 4 s.
      db.replicationController.retryNow();
      expect(
        await waitForCondition(
          () async => retryDelaySeconds(db) == 8,
          maxAttempts: 6, // 3 s < 4 s
        ),
        true,
        reason: 'retryNow() did not end the backoff wait',
      );

      await restartCouchDbContainer(dockerId!);
    });

    test('retryNow() is a no-op while paused', () async {
      final db = await createSyncedDb('retry_now_paused');
      await server.pause();
      capturedLogs.clear();

      await server.retryNow();
      await server.checkHealthNow();

      expect(server.isHealthMonitoringActive, false);
      expect(
        db.replicationController.progress.value.state,
        ReplicationState.terminated,
      );
      expect(server.state.value, OfflineFirstServerState.normalOffline);
      expect(hasLogMessage('Invoking recovery callbacks'), false);
      expect(hasLogMessage('Session valid'), false);
    });

    test('retryNow() does not restart a healthy replication', () async {
      final db = await createSyncedDb('retry_now_healthy');
      capturedLogs.clear();

      await server.retryNow();
      await server.retryNow();

      expect(server.state.value, OfflineFirstServerState.normalOnline);
      expect(isInSync(db), true);
      expect(hasLogMessage('Invoking recovery callbacks'), false);
      expect(hasLogMessage('Stopping replication'), false);
      expect(server.isHealthMonitoringActive, true);
    });

    test('checkHealthNow() coalesces concurrent calls and keeps the timer '
        'running', () async {
      capturedLogs.clear();

      await Future.wait([server.checkHealthNow(), server.checkHealthNow()]);

      expect(countLogMessages('Session valid, already normalOnline'), 1);
      expect(server.isHealthMonitoringActive, true);

      // A later call runs a new check.
      await server.checkHealthNow();
      expect(countLogMessages('Session valid, already normalOnline'), 2);
      expect(server.isHealthMonitoringActive, true);
    });
  });
}
