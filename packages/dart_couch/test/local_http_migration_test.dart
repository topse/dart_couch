import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'dart:convert';

import 'package:dart_couch/dart_couch.dart';

import 'helper/helper.dart';

void main() {
  Logger.root.level = Level.FINEST;
  Logger.root.onRecord.listen((record) {
    LineSplitter ls = LineSplitter();
    for (final line in ls.convert(record.message)) {
      // ignore: avoid_print
      print('${record.loggerName} ${record.level.name}: ${record.time}: $line');
    }
  });

  group('Local', () {
    late Directory lastCreatedDir;

    doMigrationTests(
      createFreshServer: ({DatabaseMigration? migration}) async {
        lastCreatedDir = prepareSqliteDir();
        return LocalDartCouchServer(lastCreatedDir, migration: migration);
      },
      reopenServer: ({DatabaseMigration? migration}) async {
        return LocalDartCouchServer(lastCreatedDir, migration: migration);
      },
      disposeServer: (server) => (server as LocalDartCouchServer).dispose(),
    );
  });

  group('HTTP', () {
    late String? containerId;

    setUpAll(() async {
      await shutdownAllCouchDbContainers();
      containerId = await startCouchDb(adminUser, adminPassword, false);
    });

    tearDownAll(() async {
      if (containerId != null) {
        await shutdownCouchDb(containerId!);
        await shutdownAllCouchDbContainers();
        containerId = null;
      }
    });

    doMigrationTests(
      createFreshServer: ({DatabaseMigration? migration}) async {
        // Clean up any existing testdb from previous test
        final temp = HttpDartCouchServer();
        await temp.login('http://localhost:5984', adminUser, adminPassword);
        try {
          await temp.deleteDatabase('testdb');
        } catch (_) {}
        await temp.logout();

        final server = HttpDartCouchServer(migration: migration);
        await server.login('http://localhost:5984', adminUser, adminPassword);
        return server;
      },
      reopenServer: ({DatabaseMigration? migration}) async {
        final server = HttpDartCouchServer(migration: migration);
        await server.login('http://localhost:5984', adminUser, adminPassword);
        return server;
      },
      disposeServer: (server) => (server as HttpDartCouchServer).logout(),
    );

    test('cache invalidation triggers migration on next access', () async {
      final migration = SimpleMigration(targetVersion: 1);
      final server = HttpDartCouchServer(migration: migration);
      await server.login('http://localhost:5984', adminUser, adminPassword);

      try {
        // Clean up from previous tests
        try {
          await server.deleteDatabase('testdb');
        } catch (_) {}
        await server.createDatabase('testdb');

        // First access - migration executes
        await server.db('testdb');
        expect(migration.executeCount, 1);

        // Manually clear cache (simulates server restart or cache eviction)
        server.databases.clear();

        // Next access should execute migration again (because wasInCache = false)
        migration.reset();
        final db2 = await server.db('testdb');
        expect(
          migration.migrateCalled,
          isTrue,
          reason: 'Migration should execute on cache miss',
        );

        // But the migration is idempotent, so version should still be 1
        final version = await migration.getCurrentDbVersion(db2!);
        expect(version, 1);
      } finally {
        await server.logout();
      }
    });
  });

  group(
    'LocalDartCouchServer and HttpDartCouchServer Migration Comparison',
    () {
      late String? dockerid;

      setUp(() async {
        await shutdownAllCouchDbContainers();
        dockerid = await startCouchDb(adminUser, adminPassword, false);
      });

      tearDown(() async {
        if (dockerid != null) {
          await shutdownCouchDb(dockerid!);
          await shutdownAllCouchDbContainers();
          dockerid = null;
        }
      });

      test('both servers handle migration consistently', () async {
        final localMigration = SimpleMigration(targetVersion: 1);
        final httpMigration = SimpleMigration(targetVersion: 1);

        // Setup LocalDartCouchServer
        final sqliteDir = prepareSqliteDir();
        final localServer = LocalDartCouchServer(
          sqliteDir,
          migration: localMigration,
        );

        // Setup HttpDartCouchServer
        final httpServer = HttpDartCouchServer(migration: httpMigration);
        await httpServer.login(
          'http://localhost:5984',
          adminUser,
          adminPassword,
        );

        try {
          // Create databases with same name
          await localServer.createDatabase('testdb');
          await httpServer.createDatabase('testdb');

          // Open databases
          final localDb = await localServer.db('testdb');
          final httpDb = await httpServer.db('testdb');

          // Both should have executed migration
          expect(localMigration.migrateCalled, isTrue);
          expect(httpMigration.migrateCalled, isTrue);

          // Both should have same version
          final localVersion = await localMigration.getCurrentDbVersion(
            localDb!,
          );
          final httpVersion = await httpMigration.getCurrentDbVersion(httpDb!);

          expect(localVersion, 1);
          expect(httpVersion, 1);
          expect(localVersion, equals(httpVersion));

          // Both should have migration documents
          final localDoc = await localMigration.getMigrationDocument(localDb);
          final httpDoc = await httpMigration.getMigrationDocument(httpDb);

          expect(localDoc, isNotNull);
          expect(httpDoc, isNotNull);
          expect(localDoc!.version, equals(httpDoc!.version));
        } finally {
          await localServer.dispose();
          await httpServer.logout();
        }
      });
    },
  );
}

/// Simple test migration that just updates the version
class SimpleMigration extends DatabaseMigration {
  @override
  final int targetVersion;
  int executeCount = 0;
  bool migrateCalled = false;

  SimpleMigration({required this.targetVersion});

  @override
  Future<void> migrate(DartCouchDb db) async {
    executeCount++;
    migrateCalled = true;
    log.info('SimpleMigration: Executing migration to version $targetVersion');

    final fromVersion = await getCurrentDbVersion(db);
    if (fromVersion < targetVersion) {
      log.info(
        'SimpleMigration: Migrating from version $fromVersion to $targetVersion',
      );
      await updateMigrationVersion(db, targetVersion);
    } else {
      log.info(
        'SimpleMigration: No migration needed (version already at $fromVersion)',
      );
    }
  }

  void reset() {
    executeCount = 0;
    migrateCalled = false;
  }
}

void doMigrationTests({
  /// Creates a server with a fresh (empty) database storage
  required Future<DartCouchServer> Function({DatabaseMigration? migration})
  createFreshServer,

  /// Creates a server connected to the same storage as the previously disposed server
  required Future<DartCouchServer> Function({DatabaseMigration? migration})
  reopenServer,

  /// Disposes the server without destroying storage
  required Future<void> Function(DartCouchServer server) disposeServer,
}) {
  test('executes migration on first database open', () async {
    final migration = SimpleMigration(targetVersion: 1);
    final server = await createFreshServer(migration: migration);

    try {
      await server.createDatabase('testdb');

      final db = await server.db('testdb');
      expect(db, isNotNull);

      expect(migration.migrateCalled, isTrue);
      expect(migration.executeCount, 1);

      final version = await migration.getCurrentDbVersion(db!);
      expect(version, 1);

      final migDoc = await migration.getMigrationDocument(db);
      expect(migDoc, isNotNull);
      expect(migDoc!.version, 1);
    } finally {
      await disposeServer(server);
    }
  });

  test('migration is idempotent - does not execute multiple times', () async {
    final migration = SimpleMigration(targetVersion: 1);
    final server = await createFreshServer(migration: migration);

    try {
      await server.createDatabase('testdb');

      final db1 = await server.db('testdb');
      expect(migration.executeCount, 1);

      final db2 = await server.db('testdb');
      expect(
        migration.executeCount,
        1,
        reason: 'Migration should only execute once',
      );

      expect(db1, equals(db2), reason: 'Should return same database instance');

      final version = await migration.getCurrentDbVersion(db1!);
      expect(version, 1);
    } finally {
      await disposeServer(server);
    }
  });

  test('migrates existing database without migration document', () async {
    // Create database without migration
    final server1 = await createFreshServer();
    await server1.createDatabase('testdb');
    final db1 = await server1.db('testdb');

    final doc = CouchDocumentBase(id: 'test_doc');
    await db1!.put(doc);
    await disposeServer(server1);

    // Re-open with migration
    final migration = SimpleMigration(targetVersion: 2);
    final server2 = await reopenServer(migration: migration);

    try {
      final db2 = await server2.db('testdb');
      expect(db2, isNotNull);

      expect(migration.migrateCalled, isTrue);

      final version = await migration.getCurrentDbVersion(db2!);
      expect(version, 2);

      final existingDoc = await db2.get('test_doc');
      expect(existingDoc, isNotNull);
    } finally {
      await disposeServer(server2);
    }
  });

  test('no migration when migration parameter is null', () async {
    final server = await createFreshServer();

    try {
      await server.createDatabase('testdb');
      final db = await server.db('testdb');

      expect(db, isNotNull);

      final tempMigration = SimpleMigration(targetVersion: 1);
      final version = await tempMigration.getCurrentDbVersion(db!);
      expect(version, 0, reason: 'No migration document should exist');
    } finally {
      await disposeServer(server);
    }
  });

  test('upgrades from version 1 to version 2', () async {
    // Create with version 1
    final migration1 = SimpleMigration(targetVersion: 1);
    final server1 = await createFreshServer(migration: migration1);
    await server1.createDatabase('testdb');
    await server1.db('testdb');
    await disposeServer(server1);

    // Re-open with version 2
    final migration2 = SimpleMigration(targetVersion: 2);
    final server2 = await reopenServer(migration: migration2);

    try {
      final db = await server2.db('testdb');
      expect(db, isNotNull);

      expect(migration2.migrateCalled, isTrue);

      final version = await migration2.getCurrentDbVersion(db!);
      expect(version, 2);
    } finally {
      await disposeServer(server2);
    }
  });
}
