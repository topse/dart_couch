import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:dart_couch/dart_couch.dart';

import 'helper/couch_test_manager.dart';
import 'helper/helper.dart';
import 'helper/test_document_one.dart';

/// Test migration that tracks version in a migration document
class TestMigration extends DatabaseMigration {
  @override
  final int targetVersion;
  bool migrateCalled = false;
  int migrateCallCount = 0;

  TestMigration({required this.targetVersion});

  @override
  Future<void> migrate(DartCouchDb db) async {
    migrateCalled = true;
    migrateCallCount++;
    log.info(
      'Executing migration to version $targetVersion (call #$migrateCallCount)',
    );

    await updateMigrationVersion(db, targetVersion);
    log.info('Migration completed - saved version $targetVersion');
  }

  void reset() {
    migrateCalled = false;
    migrateCallCount = 0;
  }
}

/// Migration that always fails for error handling tests
class _FailingMigration extends TestMigration {
  _FailingMigration({required super.targetVersion});

  @override
  Future<void> migrate(DartCouchDb db) async {
    migrateCalled = true;
    migrateCallCount++;
    log.info('FailingMigration: Simulating migration failure');
    throw Exception('Migration failed intentionally for testing');
  }
}

/// Migration that fails only on first attempt, succeeds on retry
class _RetryableMigration extends TestMigration {
  bool _firstAttempt = true;

  _RetryableMigration({required super.targetVersion});

  @override
  Future<void> migrate(DartCouchDb db) async {
    migrateCalled = true;
    migrateCallCount++;

    if (_firstAttempt) {
      _firstAttempt = false;
      log.info('RetryableMigration: First attempt - simulating failure');
      throw Exception('Migration failed on first attempt');
    }

    log.info('RetryableMigration: Retry succeeded');
    await super.migrate(db);
  }
}

void main() {

  Logger.root.level = Level.FINEST;
  Logger.root.onRecord.listen((record) {
    LineSplitter ls = LineSplitter();
    for (final line in ls.convert(record.message)) {
      // ignore: avoid_print
      print('${record.loggerName} ${record.level.name}: ${record.time}: $line');
    }
  });

  CouchTestManager cm = CouchTestManager();

  setUpAll(() async {
    await cm.init();
  });

  tearDownAll(() async {
    await cm.dispose();
  });

  setUp(() async {
    await cm.prepareNewTest();
  });

  tearDown(() async {
    await cm.cleanupAfterTest();
  });

  group('Database Migration - Basic Functionality', () {
    test('migration executes on initial setup when online', () async {
      final migration = TestMigration(targetVersion: 1);

      cm.migration = migration;
      final db = await cm.offlineDb();

      // Wait for migration to complete
      await waitForCondition(() async {
        return migration.migrateCalled;
      }, maxAttempts: 30);

      expect(
        migration.migrateCalled,
        isTrue,
        reason: 'Migration should have been called',
      );

      // Wait for replication to complete
      await waitForSync(db, maxSeconds: 10);

      // Debug: Check if migration document was replicated
      final localDocBeforeWait = await migration.getMigrationDocument(
        db.localDb,
      );
      log.info(
        'Local migration doc after sync: ${localDocBeforeWait?.version}, current state: ${db.migrationState.value}',
      );

      // Wait for the migration state check callback to fire and update state to matched
      await waitForCondition(() async {
        return db.migrationState.value == MigrationStatus.matched;
      }, maxAttempts: 30);

      // Debug: Check again
      final localDocAfterWait = await migration.getMigrationDocument(
        db.localDb,
      );
      log.info(
        'Local migration doc after wait: ${localDocAfterWait?.version}, current state: ${db.migrationState.value}',
      );

      // Wait for migration state to update to matched
      await waitForCondition(() async {
        return db.migrationState.value == MigrationStatus.matched;
      }, maxAttempts: 30);

      expect(db.migrationState.value, equals(MigrationStatus.matched));

      // Verify migration document exists on server
      final serverDb = await cm.httpDb();
      final serverDoc = await migration.getMigrationDocument(serverDb);
      expect(serverDoc, isNotNull);
      expect(serverDoc!.version, equals(1));

      // Verify migration document was replicated to local
      final localDoc = await migration.getMigrationDocument(db.localDb);
      expect(localDoc, isNotNull);
      expect(localDoc!.version, equals(1));

      await cm.pauseOfflineFirstDb();
      await cm.resumeOfflineFirstDb();

      // test if inital migration state is correctly determined
      cm.migration = TestMigration(targetVersion: 1);
      var newServer = await cm.offlineServer();
      var newDb = await cm.offlineDb();
      expect(newDb.migrationState.value, equals(MigrationStatus.matched));
      expect((newServer.migration as TestMigration).migrateCalled, isFalse);

      await cm.pauseOfflineFirstDb();
      await cm.resumeOfflineFirstDb();

      await cm.pauseContainer();

      // test if inital migration state is correctly determined when server is offline
      cm.migration = TestMigration(targetVersion: 1);
      newServer = await cm.offlineServer();
      newDb = await cm.offlineDb();
      expect(newDb.migrationState.value, equals(MigrationStatus.matched));
      expect((newServer.migration as TestMigration).migrateCalled, isFalse);
    });

    test('no migration when database state matches target', () async {
      final migration = TestMigration(targetVersion: 1);

      // Create database without migration first
      final db = await cm.offlineDb();

      // Pre-create migration document on server with matching version
      final httpDb = await cm.httpDb();
      final migrationDoc = MigrationDocument(
        id: migration.migrationDocumentId,
        version: 1,
      );
      await httpDb.put(migrationDoc);

      // Wait for document to replicate to local
      await waitForSync(db, maxSeconds: 5);

      // Dispose server but keep CouchDB and local DB
      await cm.pauseOfflineFirstDb();

      // Recreate server with migration - database already has matching version
      cm.migration = migration;
      await cm.resumeOfflineFirstDb();
      final newDb = await cm.offlineDb();

      // Wait for sync
      await waitForSync(newDb, maxSeconds: 10);

      // Wait for migration state check to complete (should already be matched)
      await waitForCondition(() async {
        return newDb.migrationState.value == MigrationStatus.matched;
      }, maxAttempts: 30);

      expect(
        migration.migrateCalled,
        isFalse,
        reason: 'Migration should not be called when state already matches',
      );
      expect(newDb.migrationState.value, equals(MigrationStatus.matched));
    });

    test(
      'migration state set to tooNew when database version is newer',
      () async {
        final migration = TestMigration(targetVersion: 1);

        // Create database without migration first
        final db = await cm.offlineDb();

        // Pre-create migration document on server with NEWER version
        final httpDb = await cm.httpDb();
        final migrationDoc = MigrationDocument(
          id: migration.migrationDocumentId,
          version: 5, // Much newer than our target version 1
        );
        await httpDb.put(migrationDoc);

        // Wait for document to replicate to local
        await waitForSync(db, maxSeconds: 5);

        // Dispose server but keep CouchDB and local DB
        await cm.pauseOfflineFirstDb();

        // Recreate server with migration - database has newer version
        cm.migration = migration;
        await cm.resumeOfflineFirstDb();
        final newDb = await cm.offlineDb();

        // Wait for sync
        await waitForSync(newDb, maxSeconds: 10);

        // Wait for migration state to be set
        await waitForCondition(() async {
          return newDb.migrationState.value == MigrationStatus.tooNew;
        }, maxAttempts: 30);

        expect(
          migration.migrateCalled,
          isFalse,
          reason: 'Migration should not be called when database is too new',
        );
        expect(newDb.migrationState.value, equals(MigrationStatus.tooNew));
      },
    );
  });

  group('Database Migration - Offline/Online Scenarios', () {
    test('migration executes when coming back online', () async {
      final migration = TestMigration(targetVersion: 2);

      cm.migration = migration;
      final db = await cm.offlineDb();
      final server = await cm.offlineServer();

      await waitForSync(db, maxSeconds: 10);

      // Verify initial migration executed
      expect(migration.migrateCalled, isTrue);
      migration.reset();

      // Pause CouchDB to simulate offline
      await cm.pauseContainer();

      // Wait for connection to be detected as lost
      await waitForCondition(() async {
        return server.connectionState.value ==
                DartCouchConnectionState.connectedButNetworkError ||
            server.connectionState.value ==
                DartCouchConnectionState.disconnected;
      }, maxAttempts: 30);

      // Restart CouchDB to come back online
      await cm.resumeContainer();

      // Wait for health monitoring to detect the server is back up and reconnect
      await waitForCondition(() async {
        return server.connectionState.value ==
            DartCouchConnectionState.connected;
      }, maxAttempts: 40);

      // Wait for replication to sync
      await waitForSync(db, maxSeconds: 10);

      // Migration should not execute again since state is already matched
      expect(
        migration.migrateCalled,
        isFalse,
        reason:
            'Migration should not execute again when state is already matched',
      );

      expect(db.migrationState.value, equals(MigrationStatus.matched));
    });

    test('migration state updates after replication completes', () async {
      final migration = TestMigration(targetVersion: 3);

      cm.migration = migration;
      final db = await cm.offlineDb();

      // Wait for migration to execute
      await waitForCondition(() async {
        return migration.migrateCalled;
      }, maxAttempts: 30);

      expect(migration.migrateCalled, isTrue);

      // Wait for replication to complete
      await waitForSync(db, maxSeconds: 10);

      // Wait for migration state to update to matched after replication
      await waitForCondition(() async {
        return db.migrationState.value == MigrationStatus.matched;
      }, maxAttempts: 30);

      expect(
        db.migrationState.value,
        equals(MigrationStatus.matched),
        reason: 'Migration state should update to matched after replication',
      );

      // Verify migration document exists in both server and local
      final serverDb = await cm.httpDb();
      final serverDoc = await migration.getMigrationDocument(serverDb);
      expect(serverDoc, isNotNull);
      expect(serverDoc!.version, equals(3));

      final localDoc = await migration.getMigrationDocument(db.localDb);
      expect(localDoc, isNotNull);
      expect(localDoc!.version, equals(3));
    });
  });

  group('Database Migration - Edge Cases', () {
    test(
      'migration after app update with server offline: migration runs after server restored',
      () async {
        // Step 1: Create OfflineFirstServer and complete initial migration (v1)
        final migrationV1 = TestMigration(targetVersion: 1);
        cm.migration = migrationV1;
        final db1 = await cm.offlineDb();

        await waitForCondition(() async {
          return migrationV1.migrateCalled;
        }, maxAttempts: 30);
        await waitForSync(db1, maxSeconds: 10);
        await waitForCondition(() async {
          return db1.migrationState.value == MigrationStatus.matched;
        }, maxAttempts: 30);
        expect(db1.migrationState.value, equals(MigrationStatus.matched));

        // Step 2: Dispose the server (simulate app shutdown)
        await cm.pauseOfflineFirstDb();

        // Step 3: Pause CouchDB (simulate server offline)
        await cm.pauseContainer();

        // Step 4: App update - new migration version (v2)
        final migrationV2 = TestMigration(targetVersion: 2);
        cm.migration = migrationV2;
        await cm.resumeOfflineFirstDb();
        final newServer = await cm.offlineServer();
        final db2 = await cm.offlineDb();

        // Step 5: State should be tooOld (cannot migrate while server is offline)
        expect(
          db2.migrationState.value,
          equals(MigrationStatus.tooOld),
          reason:
              'Should be tooOld after app update, before server is restored',
        );
        expect(migrationV2.migrateCalled, isFalse);

        // Step 6: Restore CouchDB (server online)
        await cm.resumeContainer();
        await waitForCondition(() async {
          return newServer.connectionState.value ==
              DartCouchConnectionState.connected;
        }, maxAttempts: 40);
        await waitForSync(db2, maxSeconds: 10);

        // Step 7: Migration should run, state becomes matched
        await waitForCondition(() async {
          return db2.migrationState.value == MigrationStatus.matched;
        }, maxAttempts: 30);
        expect(db2.migrationState.value, equals(MigrationStatus.matched));
        expect(migrationV2.migrateCalled, isTrue);
      },
    );

    test('migration only executes on serverDb, not localDb', () async {
      final migration = TestMigration(targetVersion: 1);

      cm.migration = migration;
      final db = await cm.offlineDb();

      // Wait for migration
      await waitForCondition(() async {
        return migration.migrateCalled;
      }, maxAttempts: 30);

      // Verify migration document was created on server first
      final serverDb = await cm.httpDb();
      final serverDoc = await migration.getMigrationDocument(serverDb);
      expect(
        serverDoc,
        isNotNull,
        reason: 'Migration document should exist on server',
      );

      // Wait for replication
      await waitForSync(db, maxSeconds: 10);

      // Now it should also exist on local due to replication
      final localDoc = await migration.getMigrationDocument(db.localDb);
      expect(
        localDoc,
        isNotNull,
        reason: 'Migration document should be replicated to local',
      );

      // Both should have same version
      expect(serverDoc!.version, equals(localDoc!.version));
    });

    test('migration not called multiple times on repeated reconnections', () async {
      final migration = TestMigration(targetVersion: 1);

      cm.migration = migration;
      final db = await cm.offlineDb();
      final server = await cm.offlineServer();

      // First connection - migration should execute
      await waitForCondition(() async {
        return migration.migrateCalled;
      }, maxAttempts: 30);

      final firstCallCount = migration.migrateCallCount;
      expect(firstCallCount, greaterThanOrEqualTo(1));

      // Wait for migration to complete
      await waitForSync(db, maxSeconds: 10);
      await waitForCondition(() async {
        return db.migrationState.value == MigrationStatus.matched;
      }, maxAttempts: 30);

      // Disconnect and reconnect
      await cm.pauseContainer();

      // Wait for connection to be detected as lost
      await waitForCondition(() async {
        return server.connectionState.value ==
                DartCouchConnectionState.connectedButNetworkError ||
            server.connectionState.value ==
                DartCouchConnectionState.disconnected;
      }, maxAttempts: 30);

      await cm.resumeContainer();

      // Wait for health monitoring to detect the server is back up and reconnect
      await waitForCondition(() async {
        return server.connectionState.value ==
            DartCouchConnectionState.connected;
      }, maxAttempts: 40);

      // Wait for migration state check to complete
      await waitForCondition(() async {
        return db.migrationState.value == MigrationStatus.matched;
      }, maxAttempts: 30);

      // Migration should not be called again since state is matched
      expect(
        migration.migrateCallCount,
        equals(firstCallCount),
        reason:
            'Migration should not be called again when state is already matched',
      );
    });

    test('no migration when migration is null', () async {
      final db = await cm.offlineDb();

      // Migration state should be matched when no migration is set
      expect(db.migrationState.value, equals(MigrationStatus.matched));

      await waitForSync(db, maxSeconds: 5);

      // State should remain matched
      expect(db.migrationState.value, equals(MigrationStatus.matched));
    });

    test('migration with database already existing on server', () async {
      final migration = TestMigration(targetVersion: 2);

      // First create database without migration and add some data
      final db = await cm.offlineDb();

      // Add some pre-existing data (but no migration document)
      final doc = CouchDocumentBase(id: 'test_doc_1');
      await db.put(doc);
      await waitForSync(db, maxSeconds: 5);

      // Dispose only the OfflineFirstServer but keep CouchDB running
      // to preserve the data on CouchDB
      await cm.pauseOfflineFirstDb();

      // Create a new OfflineFirstServer with migration
      cm.migration = migration;
      await cm.resumeOfflineFirstDb();
      final newDb = await cm.offlineDb();

      // Wait for migration to execute
      await waitForCondition(() async {
        return migration.migrateCalled;
      }, maxAttempts: 30);

      expect(migration.migrateCalled, isTrue);

      // Wait for sync
      await waitForSync(newDb, maxSeconds: 10);

      // Verify migration document was created
      final serverDb = await cm.httpDb();
      final migDoc = await migration.getMigrationDocument(serverDb);
      expect(migDoc, isNotNull);
      expect(migDoc!.version, equals(2));

      // Verify pre-existing data still exists
      final preExistingDoc = await newDb.get('test_doc_1');
      expect(preExistingDoc, isNotNull);
    });

    test('migration state listener properly removed after update', () async {
      final migration = TestMigration(targetVersion: 1);

      cm.migration = migration;
      final db = await cm.offlineDb();

      // Wait for migration and replication
      await waitForCondition(() async {
        return migration.migrateCalled;
      }, maxAttempts: 30);

      await waitForSync(db, maxSeconds: 10);

      // Wait for migration state to update
      await waitForCondition(() async {
        return db.migrationState.value == MigrationStatus.matched;
      }, maxAttempts: 30);

      expect(db.migrationState.value, equals(MigrationStatus.matched));

      // The listener should have been removed internally
      // We can't directly verify listener count, but we can verify
      // that migration state doesn't change incorrectly on subsequent syncs

      // Trigger another replication cycle by adding a document
      final testDoc = CouchDocumentBase(id: 'listener_test_doc');
      await db.put(testDoc);
      await waitForSync(db, maxSeconds: 5);

      // State should still be matched
      expect(
        db.migrationState.value,
        equals(MigrationStatus.matched),
        reason: 'Migration state should remain matched',
      );
    });
  });

  group('Database Migration - Error Handling', () {
    test('migration failure does not prevent replication', () async {
      // Create a migration that fails
      final migration = _FailingMigration(targetVersion: 1);

      cm.migration = migration;
      final db = await cm.offlineDb();

      // Wait for migration attempt
      await waitForCondition(() async {
        return migration.migrateCalled;
      }, maxAttempts: 30);

      // Even though migration failed, replication should still work
      final testDoc = CouchDocumentBase(id: 'replication_test_doc');
      await db.put(testDoc);

      await waitForSync(db, maxSeconds: 10);

      // Verify document was replicated
      final serverDb = await cm.httpDb();
      final serverDoc = await serverDb.get('replication_test_doc');
      expect(
        serverDoc,
        isNotNull,
        reason: 'Replication should work even if migration fails',
      );
    });

    test(
      'migration retries after failure when connection is restored',
      () async {
        final migration = _RetryableMigration(targetVersion: 1);

        cm.migration = migration;
        final db = await cm.offlineDb();
        final server = await cm.offlineServer();

        // Wait for first migration attempt (which will fail)
        await waitForCondition(() async {
          return migration.migrateCallCount >= 1;
        }, maxAttempts: 30);

        final firstCallCount = migration.migrateCallCount;
        expect(firstCallCount, greaterThanOrEqualTo(1));
        expect(
          db.migrationState.value,
          equals(MigrationStatus.tooOld),
          reason: 'Migration state should remain tooOld after failure',
        );

        // Wait for replication to complete and stabilize
        await waitForSync(db, maxSeconds: 5);

        // Disconnect to trigger retry
        await cm.pauseContainer();

        // Wait for connection state to reflect the disconnection
        await waitForCondition(() async {
          final state = server.connectionState.value;
          return state == DartCouchConnectionState.connectedButNetworkError ||
              state == DartCouchConnectionState.disconnected;
        }, maxAttempts: 30);

        // Restart CouchDB
        await cm.resumeContainer();

        // Wait for health monitoring to detect server is back and reconnect
        await waitForCondition(() async {
          return server.connectionState.value ==
              DartCouchConnectionState.connected;
        }, maxAttempts: 40);

        // Wait for migration retry (should have one more call than before)
        final targetCallCount = firstCallCount + 1;
        await waitForCondition(() async {
          return migration.migrateCallCount >= targetCallCount;
        }, maxAttempts: 30);

        expect(
          migration.migrateCallCount,
          greaterThanOrEqualTo(targetCallCount),
          reason: 'Migration should be retried after reconnection',
        );

        // Wait for migration state to update to matched
        await waitForCondition(() async {
          return db.migrationState.value == MigrationStatus.matched;
        }, maxAttempts: 30);

        expect(
          db.migrationState.value,
          equals(MigrationStatus.matched),
          reason: 'Migration state should be matched after successful retry',
        );
      },
    );

    test('dispose during migration state check cleans up properly', () async {
      final migration = TestMigration(targetVersion: 1);

      cm.migration = migration;
      await cm.offlineDb();

      // Wait for migration to execute
      await waitForCondition(() async {
        return migration.migrateCalled;
      }, maxAttempts: 30);

      // Dispose should not throw any errors even if migration state check is in progress
      // This tests that dispose properly cancels the change subscription
      await cm.pauseOfflineFirstDb();
      await waitForCondition(() async => true, maxAttempts: 5);
      expect(true, isTrue, reason: 'Dispose should complete without errors');
    });

    test('migration state check uses event-based waiting', () async {
      final migration = TestMigration(targetVersion: 1);

      cm.migration = migration;
      final db = await cm.offlineDb();

      // Wait for migration to execute on server
      await waitForCondition(() async {
        return migration.migrateCalled;
      }, maxAttempts: 30);

      // Migration state should eventually become matched via change events
      // This should happen relatively quickly (not relying on delays)
      final startTime = DateTime.now();

      await waitForCondition(() async {
        return db.migrationState.value == MigrationStatus.matched;
      }, maxAttempts: 50); // Max ~5 seconds

      final elapsed = DateTime.now().difference(startTime);

      expect(db.migrationState.value, equals(MigrationStatus.matched));
      expect(
        elapsed.inSeconds,
        lessThan(10),
        reason: 'Event-based waiting should be fast (< 10 seconds)',
      );
    });

    test(
      'migration state updates to tooNew after external migration version increase',
      () async {
        final migration = TestMigration(targetVersion: 1);

        // Step 1: Create OfflineFirstServer and complete initial migration
        cm.migration = migration;
        final db1 = await cm.offlineDb();

        // Wait for initial migration to complete
        await waitForCondition(() async {
          return migration.migrateCalled;
        }, maxAttempts: 30);

        await waitForSync(db1, maxSeconds: 10);

        await waitForCondition(() async {
          return db1.migrationState.value == MigrationStatus.matched;
        }, maxAttempts: 30);

        expect(db1.migrationState.value, equals(MigrationStatus.matched));

        // Step 2: Dispose the server (simulates app shutdown)
        // Keep local database and CouchDB running
        await cm.pauseOfflineFirstDb();

        // Step 3: Simulate external user updating migration version on HTTP server
        // Update the migration document directly on CouchDB to version 2
        final httpDb = await cm.httpDb();
        final migrationDoc = await migration.getMigrationDocument(httpDb);
        expect(migrationDoc, isNotNull);
        expect(migrationDoc!.version, equals(1));

        // Update to version 2 (simulating external migration)
        final updatedDoc = migrationDoc.copyWith(version: 2);
        await httpDb.put(updatedDoc);

        // Verify the update
        final verifyDoc = await migration.getMigrationDocument(httpDb);
        expect(verifyDoc!.version, equals(2));

        // Step 4: Pause CouchDB (server goes offline)
        await cm.pauseContainer();

        // Step 5: Our OfflineFirstServer comes back online
        // It can login because we've seen the server before
        final migration2 = TestMigration(targetVersion: 1);
        cm.migration = migration2;
        await cm.resumeOfflineFirstDb();
        final newServer = await cm.offlineServer();
        final db2 = await cm.offlineDb();

        // Step 6: At this point, migration state should be matched
        // (based on local knowledge, we don't know server has version 2 yet)
        // The state is initially tooOld (because we have a migration)
        // but since we can't connect to verify, it stays tooOld
        expect(
          db2.migrationState.value,
          equals(MigrationStatus.matched),
          reason:
              'Migration state should be matched when offline (use last known state)',
        );

        // Step 7: Restart CouchDB (server comes back online)
        await cm.resumeContainer();

        // Wait for connection to be restored
        await waitForCondition(() async {
          return newServer.connectionState.value ==
              DartCouchConnectionState.connected;
        }, maxAttempts: 40);

        // Wait for replication to sync
        await waitForSync(db2, maxSeconds: 10);

        // Step 8: As soon as we discover server availability, migration state should become tooNew
        await waitForCondition(() async {
          return db2.migrationState.value == MigrationStatus.tooNew;
        }, maxAttempts: 30);

        expect(
          db2.migrationState.value,
          equals(MigrationStatus.tooNew),
          reason:
              'Migration state should be tooNew after discovering server has version 2',
        );

        // Verify the migration was not called (because we're tooNew, not tooOld)
        expect(
          migration2.migrateCalled,
          isFalse,
          reason: 'Migration should not execute when server version is newer',
        );
      },
    );
  });

  test('login while offline having state matched', () async {
    final migration = TestMigration(targetVersion: 1);

    // Step 1: Create OfflineFirstServer and complete initial migration
    cm.migration = migration;
    final db1 = await cm.offlineDb();

    log.info('Initial setup done, waiting for migration to complete');
    await waitForCondition(() async {
      return db1.migrationState.value == MigrationStatus.matched;
    }, maxAttempts: 30);
    log.info('Migration completed');
    expect(db1.migrationState.value, equals(MigrationStatus.matched));

    log.info('Adding initial document');
    TestDocumentOne doc1 = TestDocumentOne(id: 'doc_1', name: 'Initial');
    await db1.put(doc1);

    await waitForSync(db1, maxSeconds: 10);

    // Step 2: Dispose the server (simulates app shutdown)
    // Keep local database and CouchDB running
    log.info('Disposing server to simulate app shutdown');
    await cm.pauseOfflineFirstDb();

    // Step 3: Pause CouchDB (server goes offline)
    await cm.pauseContainer();

    // Step 4: Our OfflineFirstServer comes back online
    // It can login because we've seen the server before
    log.info('Re-creating server to login while offline');
    final migration2 = TestMigration(targetVersion: 1);
    cm.migration = migration2;
    await cm.resumeOfflineFirstDb();
    final db2 = await cm.offlineDb();

    // Step 5: At this point, migration state should be matched
    expect(
      db2.migrationState.value,
      equals(MigrationStatus.matched),
      reason:
          'Migration state should be matched when offline with prior knowledge',
    );
    // Verify we can access existing data
    final fetchedDoc = await db2.get('doc_1') as TestDocumentOne?;
    expect(fetchedDoc, isNotNull);
    expect(fetchedDoc!.name, equals('Initial'));
  });
}
