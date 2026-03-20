import 'package:dart_couch/dart_couch.dart';
import 'package:test/test.dart';
import 'package:logging/logging.dart';

import 'helper/helper.dart';

// Capture log messages for verification
final List<LogRecord> capturedLogs = [];

void setupLogging() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    capturedLogs.add(record);
    // Optionally print for debugging
    // ignore: avoid_print
    print('${record.level.name}: ${record.time}: ${record.message}');
  });
}

void clearLogs() {
  capturedLogs.clear();
}

bool hasLogMessage(String substring) {
  return capturedLogs.any((log) => log.message.contains(substring));
}

int countLogMessages(String substring) {
  return capturedLogs.where((log) => log.message.contains(substring)).length;
}

List<LogRecord> getLogsSince(DateTime since) {
  return capturedLogs.where((log) => log.time.isAfter(since)).toList();
}

void main() {
  setupLogging();

  group('OfflineFirstServer pause/resume', () {
    late OfflineFirstServer server;
    late Directory localFile;
    late String? dockerId;

    setUp(() async {
      clearLogs();

      // Start fresh CouchDB container
      await shutdownAllCouchDbContainers();
      dockerId = await startCouchDb(adminUser, adminPassword, false);

      // Create fresh SQLite file
      localFile = prepareSqliteDir();

      // Create server
      server = OfflineFirstServer();
    });

    tearDown(() async {
      try {
        await server.dispose();
      } catch (e) {
        // Ignore errors during cleanup
      }
      if (dockerId != null) {
        await shutdownCouchDb(dockerId!);
        dockerId = null;
      }
    });

    test('pause() should be idempotent', () async {
      // Login first to initialize the server
      final loginResult = await server.login(
        'http://localhost:5984',
        adminUser,
        adminPassword,
        localFile,
      );
      expect(loginResult, isNotNull);
      expect(loginResult!.success, true);

      // Wait for normal online state
      await waitForServerState(server, OfflineFirstServerState.normalOnline);

      // Pause multiple times - should be idempotent
      await server.pause();
      await server.pause();
      await server.pause();

      // Verify health monitoring is stopped
      expect(server.isHealthMonitoringActive, false);
    });

    test('resume() should be idempotent', () async {
      // Login first to initialize the server
      final loginResult = await server.login(
        'http://localhost:5984',
        adminUser,
        adminPassword,
        localFile,
      );
      expect(loginResult, isNotNull);
      expect(loginResult!.success, true);

      // Wait for normal online state
      await waitForServerState(server, OfflineFirstServerState.normalOnline);

      // Pause first
      await server.pause();
      expect(server.isHealthMonitoringActive, false);

      // Resume multiple times - should be idempotent
      await server.resume();
      await server.resume();
      await server.resume();

      // Verify health monitoring is restarted
      expect(server.isHealthMonitoringActive, true);
    });

    test('pause() stops health monitoring', () async {
      // Login first to initialize the server
      final loginResult = await server.login(
        'http://localhost:5984',
        adminUser,
        adminPassword,
        localFile,
      );
      expect(loginResult, isNotNull);
      expect(loginResult!.success, true);

      // Wait for normal online state
      await waitForServerState(server, OfflineFirstServerState.normalOnline);

      // Verify health monitoring is active
      expect(server.isHealthMonitoringActive, true);

      // Clear logs before pause
      clearLogs();

      // Pause - operation completes when await returns
      await server.pause();

      // Verify pause actions in logs
      expect(hasLogMessage('OfflineFirstServer.pause() START'), true);
      expect(hasLogMessage('Stopping health monitoring'), true);
      expect(hasLogMessage('Stopping _db_updates stream'), true);
      expect(hasLogMessage('all background activity stopped'), true);
      expect(hasLogMessage('OfflineFirstServer.pause() COMPLETE'), true);

      // Verify health monitoring is stopped
      expect(server.isHealthMonitoringActive, false);

      // Wait sufficient time to ensure no background activity
      // (health monitoring runs every 5 seconds, so wait at least 15 seconds to be sure)
      final beforeSilence = DateTime.now();
      await Future.delayed(Duration(seconds: 15));

      // Get logs generated during silence period (should be minimal/none from server)
      final silenceLogs = getLogsSince(beforeSilence);
      final serverLogs = silenceLogs
          .where(
            (log) =>
                log.loggerName.startsWith('OfflineFirstServer') ||
                log.loggerName.startsWith('HealthMonitoring'),
          )
          .toList();

      // Should have no health monitoring activity during pause
      expect(
        serverLogs.any(
          (log) =>
              log.message.contains('health check') ||
              log.message.contains('Session check'),
        ),
        false,
        reason: 'No health monitoring activity should occur while paused',
      );

      // Verify no _db_updates processing
      expect(
        serverLogs.any((log) => log.message.contains('_db_updates')),
        false,
        reason: 'No _db_updates processing should occur while paused',
      );
    });

    test('resume() restarts health monitoring', () async {
      // Login first to initialize the server
      final loginResult = await server.login(
        'http://localhost:5984',
        adminUser,
        adminPassword,
        localFile,
      );
      expect(loginResult, isNotNull);
      expect(loginResult!.success, true);

      // Wait for normal online state
      await waitForServerState(server, OfflineFirstServerState.normalOnline);

      // Pause
      await server.pause();
      expect(server.isHealthMonitoringActive, false);

      // Clear logs before resume
      clearLogs();

      // Resume - operation completes when await returns
      await server.resume();

      // Verify resume actions in logs
      expect(hasLogMessage('OfflineFirstServer.resume() START'), true);
      expect(hasLogMessage('Restarting health monitoring'), true);
      expect(hasLogMessage('Running back-online recovery procedure'), true);
      expect(hasLogMessage('_performBackOnlineWork() called'), true);
      expect(hasLogMessage('Invoking recovery callbacks'), true);
      expect(hasLogMessage('_performBackOnlineWork() completed'), true);
      expect(hasLogMessage('OfflineFirstServer.resume() COMPLETE'), true);

      // Verify health monitoring is restarted
      expect(server.isHealthMonitoringActive, true);

      // Wait for at least two health monitoring cycles to occur (5 seconds each + buffer)
      clearLogs();
      await Future.delayed(Duration(seconds: 12));

      // Should have health check activity or _db_updates activity now
      expect(
        capturedLogs.any(
          (log) =>
              (log.loggerName.contains('HealthMonitoring') &&
                  (log.message.contains('CouchDB is up') ||
                      log.message.contains('Session'))) ||
              log.message.contains('_db_updates'),
        ),
        true,
        reason:
            'Health monitoring or _db_updates should be active after resume',
      );
    });

    test('pause/resume cycle preserves state', () async {
      // Login first to initialize the server
      final loginResult = await server.login(
        'http://localhost:5984',
        adminUser,
        adminPassword,
        localFile,
      );
      expect(loginResult, isNotNull);
      expect(loginResult!.success, true);

      // Wait for normal online state
      await waitForServerState(server, OfflineFirstServerState.normalOnline);

      // Pause and resume - operations complete when await returns
      await server.pause();
      await server.resume();

      // State should be preserved (online or offline, not uninitialized)
      expect(
        server.state.value,
        isIn([
          OfflineFirstServerState.normalOnline,
          OfflineFirstServerState.normalOffline,
        ]),
      );
    });

    test(
      'pause transitions to normalOffline and resume transitions back to normalOnline',
      () async {
        // Login first to initialize the server
        final loginResult = await server.login(
          'http://localhost:5984',
          adminUser,
          adminPassword,
          localFile,
        );
        expect(loginResult, isNotNull);
        expect(loginResult!.success, true);

        // Wait for normal online state
        await waitForServerState(server, OfflineFirstServerState.normalOnline);

        // Verify we start in normalOnline
        expect(server.state.value, OfflineFirstServerState.normalOnline);

        // Pause - should transition to normalOffline (health monitoring stopped = offline)
        await server.pause();

        // Verify state is normalOffline after pause
        expect(server.state.value, OfflineFirstServerState.normalOffline);

        // Wait a while to ensure state stays stable during pause
        await Future.delayed(Duration(seconds: 10));

        // Verify state is still normalOffline
        expect(
          server.state.value,
          OfflineFirstServerState.normalOffline,
          reason: 'State should remain normalOffline while paused',
        );

        // Resume - should transition back to normalOnline
        await server.resume();

        // State might transition through normalOffline briefly, but should end up normalOnline
        // Wait for it to stabilize
        final transitioned = await waitForServerState(
          server,
          OfflineFirstServerState.normalOnline,
          timeout: Duration(seconds: 10),
        );

        expect(
          transitioned,
          true,
          reason: 'Should transition back to normalOnline after resume',
        );
        expect(server.state.value, OfflineFirstServerState.normalOnline);
      },
    );

    test('cannot resume from uninitialized state', () async {
      // Try to resume without logging in - operation completes when await returns
      await server.resume();

      // Should remain in uninitialized state
      expect(server.state.value, OfflineFirstServerState.unititialized);
    });

    test('pause() stops all database replications', () async {
      // Login first to initialize the server
      final loginResult = await server.login(
        'http://localhost:5984',
        adminUser,
        adminPassword,
        localFile,
      );
      expect(loginResult, isNotNull);
      expect(loginResult!.success, true);

      // Wait for normal online state
      await waitForServerState(server, OfflineFirstServerState.normalOnline);

      // Create a test database
      final db = await server.createDatabase('test_pause_db') as OfflineFirstDb;
      expect(db, isNotNull);

      // Wait for replication to reach a stable state
      await waitForCondition(() async {
        final state = db.replicationController.progress.value.state;
        return state == ReplicationState.inSync ||
            state == ReplicationState.initialSyncComplete;
      });

      // Clear logs before pause
      clearLogs();

      // Pause - stops all replications (operation completes when await returns)
      await server.pause();

      // Verify pause logs mention stopping replications
      expect(hasLogMessage('Stopping 1 database replications'), true);
      expect(hasLogMessage('Stopping replication for test_pause_db'), true);

      // Verify replication is terminated
      expect(
        db.replicationController.progress.value.state,
        ReplicationState.terminated,
      );

      // Cleanup
      await server.deleteDatabase('test_pause_db');
    });

    test('resume() restarts all database replications', () async {
      // Login first to initialize the server
      final loginResult = await server.login(
        'http://localhost:5984',
        adminUser,
        adminPassword,
        localFile,
      );
      expect(loginResult, isNotNull);
      expect(loginResult!.success, true);

      // Wait for normal online state
      await waitForServerState(server, OfflineFirstServerState.normalOnline);

      // Create a test database
      final db =
          await server.createDatabase('test_resume_db') as OfflineFirstDb;
      expect(db, isNotNull);

      // Wait for replication to reach a stable state
      await waitForCondition(() async {
        final state = db.replicationController.progress.value.state;
        return state == ReplicationState.inSync ||
            state == ReplicationState.initialSyncComplete;
      });

      // Pause
      await server.pause();
      expect(
        db.replicationController.progress.value.state,
        ReplicationState.terminated,
      );

      // Clear logs before resume
      clearLogs();

      // Resume - restarts all replications (operation completes when await returns)
      await server.resume();

      // Verify recovery callbacks were invoked (which restart replications)
      expect(hasLogMessage('Invoking recovery callbacks'), true);
      expect(
        capturedLogs.any(
          (log) =>
              log.loggerName.startsWith('dart_couch-offline_db') &&
              log.message.contains('test_resume_db'),
        ),
        true,
        reason: 'OfflineFirstDb should log during replication restart',
      );

      // Wait for replication to restart and reach a stable state
      await waitForCondition(() async {
        final state = db.replicationController.progress.value.state;
        return state == ReplicationState.inSync ||
            state == ReplicationState.initialSyncComplete;
      });

      // Verify replication is active again
      expect(
        db.replicationController.progress.value.state,
        isIn([ReplicationState.inSync, ReplicationState.initialSyncComplete]),
      );

      // Cleanup
      await server.deleteDatabase('test_resume_db');
    });

    test('pause/resume cycle syncs data correctly', () async {
      // Login first to initialize the server
      final loginResult = await server.login(
        'http://localhost:5984',
        adminUser,
        adminPassword,
        localFile,
      );
      expect(loginResult, isNotNull);
      expect(loginResult!.success, true);

      // Wait for normal online state
      await waitForServerState(server, OfflineFirstServerState.normalOnline);

      // Create a test database
      final db = await server.createDatabase('test_sync_db') as OfflineFirstDb;

      // Wait for replication to reach a stable state
      await waitForCondition(() async {
        final state = db.replicationController.progress.value.state;
        return state == ReplicationState.inSync ||
            state == ReplicationState.initialSyncComplete;
      });

      // Add a document before pause
      final doc1 = {'_id': 'doc1', 'value': 'before_pause'};
      await db.putRaw(doc1);

      // Pause
      await server.pause();

      // Add a document while paused (only in local)
      final doc2 = {'_id': 'doc2', 'value': 'during_pause'};
      await db.putRaw(doc2);

      // Resume - should sync the document created during pause
      await server.resume();

      // Wait for replication to reach a stable state
      await waitForCondition(() async {
        final state = db.replicationController.progress.value.state;
        return state == ReplicationState.inSync ||
            state == ReplicationState.initialSyncComplete;
      });

      // Verify both documents exist locally
      final localDoc1 = await db.getRaw('doc1');
      final localDoc2 = await db.getRaw('doc2');
      expect(localDoc1, isNotNull);
      expect(localDoc2, isNotNull);
      expect(localDoc1!['value'], 'before_pause');
      expect(localDoc2!['value'], 'during_pause');

      // Verify both documents exist remotely (via http server)
      final httpDb = await server.httpServer.db('test_sync_db');
      final remoteDoc1 = await httpDb?.getRaw('doc1');
      final remoteDoc2 = await httpDb?.getRaw('doc2');
      expect(remoteDoc1, isNotNull);
      expect(remoteDoc2, isNotNull);

      // Cleanup
      await server.deleteDatabase('test_sync_db');
    });
  });
}
