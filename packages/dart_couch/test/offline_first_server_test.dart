import 'dart:convert';

import 'package:test/test.dart';
import 'package:logging/logging.dart';

import 'package:dart_couch/dart_couch.dart';

import 'helper/helper.dart';

void main() {

  Logger.root.level = Level.FINEST; // defaults to Level.INFO
  Logger.root.onRecord.listen((record) {
    LineSplitter ls = LineSplitter();
    for (final line in ls.convert(record.message)) {
      // ignore: avoid_print
      print('${record.loggerName} ${record.level.name}: ${record.time}: $line');
    }
  });

  test('try connect to offline server (should fail)', () async {
    // Test first-time login attempt when server is offline
    final localPath = prepareSqliteDir();

    final ofs = OfflineFirstServer();

    await shutdownAllCouchDbContainers();

    // Try to login to an offline/unreachable server
    final loginResult = await ofs.login(
      'http://localhost:5984',
      'testuser',
      'testpass',
      localPath,
    );

    // Should return null because of network error and no previous login
    expect(loginResult, isNull);
    expect(ofs.state.value, OfflineFirstServerState.unititialized);

    await ofs.dispose();
  });

  test(
    'try to connect to offline server that has been logged in before (should succeed)',
    () async {
      // Test login when server is offline but credentials were previously validated
      final localPath = prepareSqliteDir();

      HttpDartCouchServer httpServer =
          await setUpAllHttpFunction() as HttpDartCouchServer;

      final ofs = OfflineFirstServer();

      // First login when server is online
      final firstLogin = await ofs.login(
        httpServer.uri.toString(),
        adminUser,
        adminPassword,
        localPath,
      );
      expect(firstLogin, isNotNull);
      expect(firstLogin!.success, isTrue);
      expect(ofs.state.value, OfflineFirstServerState.normalOnline);

      // Logout
      await ofs.logout();

      // Stop the CouchDB container to simulate offline
      await pauseCouchDbContainer(dockerid!);

      // Try to login again - should succeed with cached credentials
      final offlineLogin = await ofs.login(
        httpServer.uri.toString(),
        adminUser,
        adminPassword,
        localPath,
      );

      expect(offlineLogin, isNotNull);
      expect(offlineLogin!.success, isTrue);
      expect(ofs.state.value, OfflineFirstServerState.normalOffline);

      // Verify health monitoring is active
      expect(ofs.isHealthMonitoringActive, isTrue);

      // Restart the container
      await restartCouchDbContainer(dockerid!);

      // Wait for health monitoring to detect the server is back online
      await expectLater(
        waitForServerState(ofs, OfflineFirstServerState.normalOnline),
        completion(isTrue),
      );

      await ofs.dispose();
      await tearDownAllHttpFunction();
    },
  );

  test('check correct use of state normalTryingToReconnect', () async {
    // Test that normalTryingToConnect state is used when we have valid credentials
    // from before but cannot connect due to network/server issues
    final localPath = prepareSqliteDir();

    HttpDartCouchServer httpServer =
        await setUpAllHttpFunction() as HttpDartCouchServer;

    final ofs = OfflineFirstServer();

    // Step 1: Login successfully to establish valid credentials
    final firstLogin = await ofs.login(
      httpServer.uri.toString(),
      adminUser,
      adminPassword,
      localPath,
    );
    expect(firstLogin, isNotNull);
    expect(firstLogin!.success, isTrue);
    expect(ofs.state.value, OfflineFirstServerState.normalOnline);

    // Step 2: Logout (but credentials are still stored locally)
    await ofs.logout();
    expect(ofs.state.value, OfflineFirstServerState.unititialized);

    // Step 3: Take server offline
    await pauseCouchDbContainer(dockerid!);

    // Step 4: Try to login with same credentials while server is offline
    // Credentials were valid before, but can't login due to network failure
    // This should result in normalTryingToConnect state
    final offlineLoginAttempt = await ofs.login(
      httpServer.uri.toString(),
      adminUser,
      adminPassword,
      localPath,
    );

    // Login should succeed with cached credentials
    expect(offlineLoginAttempt, isNotNull);
    expect(offlineLoginAttempt!.success, isTrue);
    expect(ofs.state.value, OfflineFirstServerState.normalOffline);

    // Health monitoring should be active and trying to reconnect
    expect(ofs.isHealthMonitoringActive, isTrue);

    // Bring server back online
    await restartCouchDbContainer(dockerid!);

    // Wait for health monitoring to reconnect
    // During reconnection attempts, state should transition through normalTryingToConnect
    // when attempting to reconnect, but may settle on normalOffline or normalOnline
    await expectLater(
      waitForServerState(ofs, OfflineFirstServerState.normalOnline),
      completion(isTrue),
      reason: 'Server should eventually come back online',
    );

    // Final state should be normalOnline after successful reconnection
    expect(ofs.state.value, OfflineFirstServerState.normalOnline);

    await ofs.dispose();
    await tearDownAllHttpFunction();
  });

  test('database syncs documents when coming back online', () async {
    // Test: Login with OfflineFirstServer, create a DB with data via HTTP client
    // (simulating another client), then server goes offline. The local DB should
    // be empty (documents not yet synced). When server comes back, it should sync
    // the documents automatically.
    final localPath = prepareSqliteDir();

    HttpDartCouchServer httpServer =
        await setUpAllHttpFunction() as HttpDartCouchServer;

    final ofs = OfflineFirstServer();

    // Step 1: Login with OfflineFirstServer (no databases exist yet)
    final loginResult = await ofs.login(
      httpServer.uri.toString(),
      adminUser,
      adminPassword,
      localPath,
    );
    expect(loginResult, isNotNull);
    expect(loginResult!.success, isTrue);
    expect(ofs.state.value, OfflineFirstServerState.normalOnline);

    // Step 2: Create database with a test document using HTTP client
    // (simulating another client creating data)
    const dbName = 'testdb_offline_sync';
    await httpServer.createDatabase(dbName);

    final httpDb = await httpServer.db(dbName);
    await httpDb!.put(
      CouchDocumentBase(
        id: 'test-doc-1',
        unmappedProps: {'name': 'Test Document', 'value': 42},
      ),
    );

    // Step 3: Wait for _db_updates stream to create the local database
    // (without syncing document data yet)
    await expectLater(
      waitForCondition(() async {
        return (await ofs.allDatabasesNames).contains(dbName);
      }, maxAttempts: 10),
      completion(isTrue),
      reason: 'Database was not created locally after _db_updates event',
    );

    // Step 5: Server goes offline (before document replication completes)
    await pauseCouchDbContainer(dockerid!);
    OfflineFirstDb? offlineDb = await ofs.db(dbName) as OfflineFirstDb?;

    // Wait for health monitoring to detect offline state
    await expectLater(
      waitForServerState(
        ofs,
        OfflineFirstServerState.normalOffline,
        timeout: const Duration(seconds: 6),
      ),
      completion(isTrue),
      reason: 'Server state should change to normalOffline',
    );

    // Step 6: Verify database is empty (document not yet synced)
    var doc = await offlineDb!.get('test-doc-1');
    expect(
      doc,
      isNull,
      reason: 'Document should not be synced yet while offline',
    );

    // Step 7: Verify replication state shows it's not synced
    final replicationState =
        offlineDb.replicationController.progress.value.state;
    log.info('Replication state while offline: $replicationState');
    expect(
      replicationState,
      isNot(equals(ReplicationState.inSync)),
      reason: 'Replication should not be in sync while offline',
    );

    // Step 8: Bring server back online
    log.info('Restarting CouchDB container...');
    await restartCouchDbContainer(dockerid!);

    // If health monitoring was stopped, we can't proceed with the test
    expect(ofs.isHealthMonitoringActive, isTrue);

    // Health monitoring should detect server is back up
    // Wait for server to come back online (health check runs every 5 seconds)
    await expectLater(
      waitForServerState(ofs, OfflineFirstServerState.normalOnline),
      completion(isTrue),
      reason: 'Server did not come back online',
    );
    log.info('Server is back online');

    // Step 9: Wait for sync to complete
    await waitForReplicationState(offlineDb, ReplicationState.inSync);

    // Step 10: Verify document is now available after sync
    final syncedDoc = await offlineDb.get('test-doc-1');
    expect(syncedDoc, isNotNull, reason: 'Document should exist after sync');
    expect(syncedDoc!.unmappedProps['name'], equals('Test Document'));
    expect(syncedDoc.unmappedProps['value'], equals(42));

    // Cleanup
    await httpServer.deleteDatabase(dbName);

    await ofs.dispose();
    await tearDownAllHttpFunction();
  });

  test(
    'try to get a database from a offline server that has been synchronized before (should succeed)',
    () async {
      // Test getting a database when it was previously synced
      final localPath = prepareSqliteDir();

      HttpDartCouchServer httpServer =
          await setUpAllHttpFunction() as HttpDartCouchServer;

      OfflineFirstServer ofs = OfflineFirstServer();

      // Login when server is online
      final loginResult = await ofs.login(
        httpServer.uri.toString(),
        adminUser,
        adminPassword,
        localPath,
      );
      expect(loginResult, isNotNull);
      expect(loginResult!.success, isTrue);

      // Create a test database on the server
      const dbName = 'testdb1';
      await httpServer.createDatabase(dbName);

      // Add a test document
      final httpDb = await httpServer.db(dbName);
      await httpDb!.put(
        CouchDocumentBase(
          id: 'test-doc-1',
          unmappedProps: {'name': 'Test Document', 'value': 42},
        ),
      );

      OfflineFirstDb? offlineDb;
      await expectLater(
        waitForCondition(() async {
          offlineDb = await ofs.db(dbName) as OfflineFirstDb?;
          return offlineDb != null;
        }, maxAttempts: 10),
        completion(isTrue),
        reason: 'Database was not created locally after _db_updates event',
      );

      // Get the database through OfflineFirstServer (this will sync)
      expect(offlineDb, isNotNull);

      // Wait for initial sync
      await waitForReplicationState(
        offlineDb!,
        ReplicationState.inSync,
        timeout: const Duration(seconds: 10),
      );

      // Verify document was synced
      final doc = await offlineDb!.get('test-doc-1');
      expect(doc, isNotNull);
      expect(doc!.unmappedProps['name'], equals('Test Document'));

      // Logout and stop the server
      await ofs.logout();
      await pauseCouchDbContainer(dockerid!);

      // Login again in offline mode
      await ofs.dispose();
      ofs = OfflineFirstServer();
      final offlineLogin = await ofs.login(
        httpServer.uri.toString(),
        adminUser,
        adminPassword,
        localPath,
      );
      expect(offlineLogin, isNotNull);
      expect(offlineLogin!.success, isTrue);
      expect(ofs.state.value, OfflineFirstServerState.normalOffline);

      // Get the database again - should succeed from local cache
      final offlineDb2 = await ofs.db(dbName);
      expect(offlineDb2, isNotNull);

      // Verify we can still read the document
      final docOffline = await offlineDb2!.get('test-doc-1');
      expect(docOffline, isNotNull);
      expect(docOffline!.unmappedProps['name'], equals('Test Document'));
      expect(docOffline.unmappedProps['value'], equals(42));

      // Restart the container for cleanup
      await restartCouchDbContainer(dockerid!);

      // Wait for ofs to come back online
      await expectLater(
        waitForServerState(ofs, OfflineFirstServerState.normalOnline),
        completion(isTrue),
      );

      // Cleanup the database using ofs (handles network issues gracefully)
      await ofs.deleteDatabase(dbName);
      log.info('Deleted test database $dbName');
      await ofs.dispose();
      log.info('Disposed OfflineFirstServer');
      await tearDownAllHttpFunction();
      log.info('Teared down HTTP function');
    },
  );

  test(
    'create and delete database when online and check that it gets synchronized',
    () async {
      // Test database creation and deletion while online
      final localPath = prepareSqliteDir();

      HttpDartCouchServer httpServer =
          await setUpAllHttpFunction() as HttpDartCouchServer;

      final ofs = OfflineFirstServer();

      // Login when server is online
      final loginResult = await ofs.login(
        httpServer.uri.toString(),
        adminUser,
        adminPassword,
        localPath,
      );
      expect(loginResult, isNotNull);
      expect(loginResult!.success, isTrue);
      expect(ofs.state.value, OfflineFirstServerState.normalOnline);

      // Create a test database
      const dbName = 'testdb_online_create';
      final db = await ofs.createDatabase(dbName) as OfflineFirstDb;
      expect(db, isNotNull);

      // Verify database exists on server
      final httpDb = await httpServer.db(dbName);
      expect(httpDb, isNotNull);

      // Add a document through offline-first db
      log.info('Adding document to online database...');
      await db.put(
        CouchDocumentBase(
          id: 'test-doc-1',
          unmappedProps: {'created': 'online', 'value': 123},
        ),
      );

      // Expect replication to be active
      expect(
        db.replicationController.progress.value.state,
        isIn([ReplicationState.initialSyncInProgress, ReplicationState.inSync]),
      );

      // Wait for document to appear on server (this proves sync happened)
      log.info('Waiting for document to sync to server...');
      final docExists = await waitForCondition(
        () async => await httpDb!.get('test-doc-1') != null,
        maxAttempts: 20,
        interval: Duration(milliseconds: 500),
      );
      expect(docExists, isTrue, reason: 'Document should sync to server');

      // After successful sync, replication should be in sync state
      expect(
        db.replicationController.progress.value.state,
        ReplicationState.inSync,
      );

      // Verify document exists on server with correct data
      final serverDoc = await httpDb!.get('test-doc-1');
      expect(serverDoc, isNotNull);
      expect(serverDoc!.unmappedProps['created'], equals('online'));

      // Delete the database
      await ofs.deleteDatabase(dbName);

      // Verify database no longer exists on server
      final deletedDb = await httpServer.db(dbName);
      expect(deletedDb, isNull);

      await ofs.dispose();
      await tearDownAllHttpFunction();
    },
  );

  test(
    'create database when offline and check that it gets synchronized',
    () async {
      // Test database creation while offline - should sync when coming back online
      final localPath = prepareSqliteDir();

      HttpDartCouchServer httpServer =
          await setUpAllHttpFunction() as HttpDartCouchServer;

      final ofs = OfflineFirstServer();

      // First login when server is online to cache credentials
      final firstLogin = await ofs.login(
        httpServer.uri.toString(),
        adminUser,
        adminPassword,
        localPath,
      );
      expect(firstLogin, isNotNull);
      expect(firstLogin!.success, isTrue);

      // Go offline
      await pauseCouchDbContainer(dockerid!);

      // Wait for health monitoring to detect offline state
      await expectLater(
        waitForServerState(
          ofs,
          OfflineFirstServerState.normalOffline,
          timeout: const Duration(seconds: 6),
        ),
        completion(isTrue),
      );

      // Create database while offline - should only create locally
      const dbName = 'testdb_offline_create';
      final db = await ofs.createDatabase(dbName) as OfflineFirstDb?;
      expect(db, isNotNull);

      // Add a document
      await db!.put(
        CouchDocumentBase(
          id: 'test-doc-1',
          unmappedProps: {'created': 'offline', 'value': 456},
        ),
      );

      // Verify document is in local database
      final localDoc = await db.get('test-doc-1');
      expect(localDoc, isNotNull);
      expect(localDoc!.unmappedProps['created'], equals('offline'));

      // Bring server back online
      await restartCouchDbContainer(dockerid!);

      // Wait for server to come back online
      await expectLater(
        waitForServerState(ofs, OfflineFirstServerState.normalOnline),
        completion(isTrue),
      );

      // Wait for sync to complete
      await waitForReplicationState(db, ReplicationState.inSync);

      // Verify database and document now exist on server
      final httpDb = await httpServer.db(dbName);
      expect(httpDb, isNotNull);

      final serverDoc = await httpDb!.get('test-doc-1');
      expect(serverDoc, isNotNull);
      expect(serverDoc!.unmappedProps['created'], equals('offline'));

      // Cleanup
      await httpServer.deleteDatabase(dbName);

      await ofs.dispose();
      await tearDownAllHttpFunction();
    },
  );

  test(
    'delete database when offline and check that it gets synchronized',
    () async {
      // Test database deletion while offline - should sync when coming back online
      final localPath = prepareSqliteDir();

      HttpDartCouchServer httpServer =
          await setUpAllHttpFunction() as HttpDartCouchServer;

      final ofs = OfflineFirstServer();

      // Login when server is online
      final loginResult = await ofs.login(
        httpServer.uri.toString(),
        adminUser,
        adminPassword,
        localPath,
      );
      expect(loginResult, isNotNull);
      expect(loginResult!.success, isTrue);

      // Create a test database while online
      const dbName = 'testdb_offline_delete';
      await ofs.createDatabase(dbName);

      // Add a test document
      final db = (await ofs.db(dbName) as OfflineFirstDb?)!;
      expect(db, isNotNull);
      await db.put(
        CouchDocumentBase(
          id: 'test-doc-1',
          unmappedProps: {'will': 'be deleted', 'value': 789},
        ),
      );

      // Wait for initial sync
      await waitForReplicationState(
        db,
        ReplicationState.inSync,
        timeout: const Duration(seconds: 10),
      );

      // Verify database exists on server
      var httpDb = await httpServer.db(dbName);
      expect(httpDb, isNotNull);
      var serverDoc = await httpDb!.get('test-doc-1');
      expect(serverDoc, isNotNull);

      // Go offline
      await pauseCouchDbContainer(dockerid!);

      // Wait for health monitoring to detect offline state
      await expectLater(
        waitForServerState(
          ofs,
          OfflineFirstServerState.normalOffline,
          timeout: const Duration(seconds: 6),
        ),
        completion(isTrue),
      );

      // Delete database while offline
      await ofs.deleteDatabase(dbName);

      // Verify database is deleted locally
      final deletedLocalDb = await ofs.db(dbName);
      expect(deletedLocalDb, isNull);

      // Bring server back online
      await restartCouchDbContainer(dockerid!);

      // Wait for server to come back online
      await expectLater(
        waitForServerState(ofs, OfflineFirstServerState.normalOnline),
        completion(isTrue),
      );

      // Wait for database to be deleted on server
      // Database deletions while offline should sync when coming back online
      await expectLater(
        waitForCondition(() async {
          httpDb = await httpServer.db(dbName);
          return httpDb == null;
        }, maxAttempts: 10),
        completion(isTrue),
        reason: 'Database should be deleted on server after coming back online',
      );

      await ofs.dispose();
      await tearDownAllHttpFunction();
    },
  );

  test('conflict resolution: serverAlwaysWins mode', () async {
    final localPath = prepareSqliteDir();
    HttpDartCouchServer httpServer =
        await setUpAllHttpFunction() as HttpDartCouchServer;

    final ofs = OfflineFirstServer(
      existingDatabaseSyncingStrategy:
          ExistingDatabasesSyncStrategie.serverAlwaysWins,
    );

    await ofs.login(
      httpServer.uri.toString(),
      adminUser,
      adminPassword,
      localPath,
    );

    const dbName = 'conflict_test_server_wins';

    // Step 1: Create database locally
    await ofs.createDatabase(dbName);
    final db1 = (await ofs.db(dbName) as OfflineFirstDb?)!;
    await db1.put(
      CouchDocumentBase(
        id: 'local-doc-1',
        unmappedProps: {'source': 'local-created', 'value': 100},
      ),
    );

    // Read local marker UUID
    //final localMarker1 = await db1.localDb.get('_local/db_sync_marker');
    //final localUuid1 =
    //    (localMarker1 as CouchDocumentBase).unmappedProps['databaseUuid'];

    // Step 2: Dispose OfflineFirstServer (simulating going offline)
    await ofs.dispose();

    // Step 3: While OfflineFirstServer is "offline", recreate database on server
    // with different UUID (simulating another client recreating the database)
    // Check if database still exists before trying to delete (may have been cleaned up)
    if ((await httpServer.allDatabasesNames).contains(dbName)) {
      await httpServer.deleteDatabase(dbName);
    }
    await httpServer.createDatabase(dbName);
    final serverDb1 = (await httpServer.db(dbName))!;
    await serverDb1.put(
      CouchDocumentBase(
        id: 'server-doc-1',
        unmappedProps: {'source': 'server-created', 'value': 300},
      ),
    );
    // Write marker manually with different UUID to simulate conflict
    final remoteMarker = DatabaseSyncMarker(
      instanceUuid: 'remote-instance',
      databaseUuid: 'remote-db-uuid-different',
      createdAt: DateTime.now(),
      createdBy: 'remote',
      activeInstances: ['remote-instance'],
      tombstone: false,
    );
    await serverDb1.put(remoteMarker);

    // Step 4: Recreate OfflineFirstServer and login - serverAlwaysWins should kick in
    final ofs2 = OfflineFirstServer(
      existingDatabaseSyncingStrategy:
          ExistingDatabasesSyncStrategie.serverAlwaysWins,
    );
    await ofs2.login(
      httpServer.uri.toString(),
      adminUser,
      adminPassword,
      localPath,
    );

    // Wait for sync to detect and resolve conflict
    await Future.delayed(Duration(seconds: 3));

    // Step 5: Verify server version won
    final db2 = (await ofs2.db(dbName) as OfflineFirstDb?)!;
    await waitForSync(db2, maxSeconds: 5);

    final localMarker2 =
        await db2.localDb.get('_local/db_sync_marker') as DatabaseSyncMarker?;
    final localUuid2 = localMarker2?.databaseUuid;
    expect(
      localUuid2,
      equals('remote-db-uuid-different'),
      reason: 'Local should adopt remote UUID',
    );

    // Verify server document exists locally
    final serverDoc = await db2.localDb.get('server-doc-1');
    expect(
      serverDoc,
      isNotNull,
      reason: 'Server document should be synced locally',
    );
    expect(
      (serverDoc as CouchDocumentBase).unmappedProps['value'],
      equals(300),
    );

    // Verify local document is gone (replaced by server version)
    final localDoc = await db2.localDb.get('local-doc-1');
    expect(
      localDoc,
      isNull,
      reason: 'Local document should be deleted when server wins',
    );

    await ofs2.dispose();
    await tearDownAllHttpFunction();
  });

  test('conflict resolution: localAlwaysWins mode', () async {
    final localPath = prepareSqliteDir();
    HttpDartCouchServer httpServer =
        await setUpAllHttpFunction() as HttpDartCouchServer;

    final ofs = OfflineFirstServer(
      existingDatabaseSyncingStrategy:
          ExistingDatabasesSyncStrategie.localAlwaysWins,
    );

    await ofs.login(
      httpServer.uri.toString(),
      adminUser,
      adminPassword,
      localPath,
    );

    const dbName = 'conflict_test_local_wins';

    // Step 1: Create database locally
    await ofs.createDatabase(dbName);
    final db1 = (await ofs.db(dbName) as OfflineFirstDb?)!;
    await db1.put(
      CouchDocumentBase(
        id: 'local-doc-1',
        unmappedProps: {'source': 'local-created', 'value': 400},
      ),
    );

    final localMarker1 =
        await db1.localDb.get('_local/db_sync_marker') as DatabaseSyncMarker?;
    final localUuid1 = localMarker1?.databaseUuid;

    // Step 2: Dispose OfflineFirstServer (simulating going offline)
    await ofs.dispose();

    // Step 3: While OfflineFirstServer is "offline", recreate database on server
    // with different UUID (simulating another client)
    // Check if database still exists before trying to delete
    if ((await httpServer.allDatabasesNames).contains(dbName)) {
      await httpServer.deleteDatabase(dbName);
    }
    await httpServer.createDatabase(dbName);
    final serverDb1 = (await httpServer.db(dbName))!;
    await serverDb1.put(
      CouchDocumentBase(
        id: 'server-doc-1',
        unmappedProps: {'source': 'server-created', 'value': 600},
      ),
    );
    final remoteMarker = DatabaseSyncMarker(
      instanceUuid: 'remote-instance',
      databaseUuid: 'remote-db-uuid-different-2',
      createdAt: DateTime.now(),
      createdBy: 'remote',
      activeInstances: ['remote-instance'],
      tombstone: false,
    );
    await serverDb1.put(remoteMarker);

    // Step 4: Recreate OfflineFirstServer and login - localAlwaysWins should kick in
    final ofs2 = OfflineFirstServer(
      existingDatabaseSyncingStrategy:
          ExistingDatabasesSyncStrategie.localAlwaysWins,
    );
    await ofs2.login(
      httpServer.uri.toString(),
      adminUser,
      adminPassword,
      localPath,
    );

    await Future.delayed(Duration(seconds: 3));

    // Step 5: Verify local version won
    final db2 = (await ofs2.db(dbName) as OfflineFirstDb?)!;
    await waitForSync(db2, maxSeconds: 5);

    // Check remote marker adopted local UUID
    final serverDb2 = (await httpServer.db(dbName))!;
    final remoteMarkerAfter =
        await serverDb2.get('_local/db_sync_marker') as DatabaseSyncMarker?;
    final remoteUuid = remoteMarkerAfter?.databaseUuid;
    expect(
      remoteUuid,
      equals(localUuid1),
      reason: 'Remote should adopt local UUID',
    );

    // Verify local document exists on server
    final localDocOnServer = await serverDb2.get('local-doc-1');
    expect(
      localDocOnServer,
      isNotNull,
      reason: 'Local document should be on server',
    );
    expect(
      (localDocOnServer as CouchDocumentBase).unmappedProps['value'],
      equals(400),
    );

    // Verify server document is gone (replaced by local version)
    final serverDoc = await serverDb2.get('server-doc-1');
    expect(
      serverDoc,
      isNull,
      reason: 'Server document should be deleted when local wins',
    );

    await ofs2.dispose();
    await tearDownAllHttpFunction();
  });

  test('conflict resolution: merge mode preserves all documents', () async {
    final localPath = prepareSqliteDir();
    HttpDartCouchServer httpServer =
        await setUpAllHttpFunction() as HttpDartCouchServer;

    final ofs = OfflineFirstServer(
      existingDatabaseSyncingStrategy: ExistingDatabasesSyncStrategie.merge,
    );

    await ofs.login(
      httpServer.uri.toString(),
      adminUser,
      adminPassword,
      localPath,
    );

    const dbName = 'conflict_test_merge';

    // Step 1: Create database locally with multiple documents
    await ofs.createDatabase(dbName);
    final db1 = (await ofs.db(dbName) as OfflineFirstDb?)!;

    // Add multiple local documents
    await db1.put(
      CouchDocumentBase(
        id: 'local-doc-1',
        unmappedProps: {'source': 'local-created', 'value': 800},
      ),
    );
    await db1.put(
      CouchDocumentBase(
        id: 'local-doc-2',
        unmappedProps: {'source': 'local-created', 'value': 850},
      ),
    );

    //final localMarker1 =
    //    await db1.localDb.get('_local/db_sync_marker') as DatabaseSyncMarker?;
    //final localUuid1 = localMarker1?.databaseUuid;

    // Step 2: Dispose OfflineFirstServer (simulating going offline)
    await ofs.dispose();

    // Step 3: While OfflineFirstServer is "offline", recreate database on server
    // with different documents (simulating another client)
    // Check if database still exists before trying to delete
    if ((await httpServer.allDatabasesNames).contains(dbName)) {
      await httpServer.deleteDatabase(dbName);
    }
    await httpServer.createDatabase(dbName);
    final serverDb1 = (await httpServer.db(dbName))!;

    // Add multiple server documents
    await serverDb1.put(
      CouchDocumentBase(
        id: 'server-doc-1',
        unmappedProps: {'source': 'server-created', 'value': 900},
      ),
    );
    await serverDb1.put(
      CouchDocumentBase(
        id: 'server-doc-2',
        unmappedProps: {'source': 'server-created', 'value': 950},
      ),
    );

    // Write marker with different UUID
    final remoteUuid = 'remote-db-uuid-merge-test';
    final remoteMarker = DatabaseSyncMarker(
      instanceUuid: 'remote-instance',
      databaseUuid: remoteUuid,
      createdAt: DateTime.now(),
      createdBy: 'remote',
      activeInstances: ['remote-instance'],
      tombstone: false,
    );
    await serverDb1.put(remoteMarker);

    // Step 4: Recreate OfflineFirstServer and login - merge should preserve ALL documents
    final ofs2 = OfflineFirstServer(
      existingDatabaseSyncingStrategy: ExistingDatabasesSyncStrategie.merge,
    );
    await ofs2.login(
      httpServer.uri.toString(),
      adminUser,
      adminPassword,
      localPath,
    );

    // Wait for merge conflict resolution
    await Future.delayed(Duration(seconds: 4));

    // Step 5: Verify merge happened - remote UUID adopted
    final db2 = (await ofs2.db(dbName) as OfflineFirstDb?)!;
    await waitForSync(db2, maxSeconds: 10);

    final localMarker2 =
        await db2.localDb.get('_local/db_sync_marker') as DatabaseSyncMarker?;
    final localUuid2 = localMarker2?.databaseUuid;
    expect(
      localUuid2,
      equals(remoteUuid),
      reason: 'Merge should adopt remote UUID',
    );

    // Step 6: Verify ALL documents from both incarnations exist
    // Local documents should exist locally
    final localDoc1Local = await db2.localDb.get('local-doc-1');
    expect(
      localDoc1Local,
      isNotNull,
      reason: 'Local doc 1 should exist locally',
    );
    expect(
      (localDoc1Local as CouchDocumentBase).unmappedProps['value'],
      equals(800),
    );

    final localDoc2Local = await db2.localDb.get('local-doc-2');
    expect(
      localDoc2Local,
      isNotNull,
      reason: 'Local doc 2 should exist locally',
    );
    expect(
      (localDoc2Local as CouchDocumentBase).unmappedProps['value'],
      equals(850),
    );

    // Server documents should exist locally
    final serverDoc1Local = await db2.localDb.get('server-doc-1');
    expect(
      serverDoc1Local,
      isNotNull,
      reason: 'Server doc 1 should be synced locally',
    );
    expect(
      (serverDoc1Local as CouchDocumentBase).unmappedProps['value'],
      equals(900),
    );

    final serverDoc2Local = await db2.localDb.get('server-doc-2');
    expect(
      serverDoc2Local,
      isNotNull,
      reason: 'Server doc 2 should be synced locally',
    );
    expect(
      (serverDoc2Local as CouchDocumentBase).unmappedProps['value'],
      equals(950),
    );

    // Verify ALL documents also exist on server
    final serverDb2 = (await httpServer.db(dbName))!;

    final localDoc1Server = await serverDb2.get('local-doc-1');
    expect(
      localDoc1Server,
      isNotNull,
      reason: 'Local doc 1 should be replicated to server',
    );
    expect(
      (localDoc1Server as CouchDocumentBase).unmappedProps['value'],
      equals(800),
    );

    final localDoc2Server = await serverDb2.get('local-doc-2');
    expect(
      localDoc2Server,
      isNotNull,
      reason: 'Local doc 2 should be replicated to server',
    );
    expect(
      (localDoc2Server as CouchDocumentBase).unmappedProps['value'],
      equals(850),
    );

    final serverDoc1Server = await serverDb2.get('server-doc-1');
    expect(
      serverDoc1Server,
      isNotNull,
      reason: 'Server doc 1 should remain on server',
    );
    expect(
      (serverDoc1Server as CouchDocumentBase).unmappedProps['value'],
      equals(900),
    );

    final serverDoc2Server = await serverDb2.get('server-doc-2');
    expect(
      serverDoc2Server,
      isNotNull,
      reason: 'Server doc 2 should remain on server',
    );
    expect(
      (serverDoc2Server as CouchDocumentBase).unmappedProps['value'],
      equals(950),
    );

    log.info(
      'Merge mode test: All 4 documents preserved on both local and server!',
    );

    await ofs2.dispose();
    await tearDownAllHttpFunction();
  });

  test(
    'conflict resolution: merge mode with same document IDs (real conflict)',
    () async {
      // This test verifies CouchDB's deterministic conflict resolution algorithm:
      // When two documents with the same ID but different content are created
      // independently on local and server, both have version 1 but different
      // revision hashes. CouchDB resolves this deterministically:
      //   1. Higher version number wins
      //   2. On equal version, the lexicographically higher revision hash wins
      // This ensures all peers converge to the same winner without coordination.

      final localPath = prepareSqliteDir();
      HttpDartCouchServer httpServer =
          await setUpAllHttpFunction() as HttpDartCouchServer;

      final ofs = OfflineFirstServer(
        existingDatabaseSyncingStrategy: ExistingDatabasesSyncStrategie.merge,
      );

      await ofs.login(
        httpServer.uri.toString(),
        adminUser,
        adminPassword,
        localPath,
      );

      const dbName = 'conflict_test_merge_same_ids';

      // Step 1: Create database locally with documents and capture their revisions
      await ofs.createDatabase(dbName);
      final db1 = (await ofs.db(dbName) as OfflineFirstDb?)!;

      final localDoc1 = await db1.put(
        CouchDocumentBase(
          id: 'conflict-doc-1',
          unmappedProps: {
            'source': 'local',
            'value': 100,
            'modified_by': 'local_client',
          },
        ),
      );
      final localRev1 = localDoc1.rev!;

      final localDoc2 = await db1.put(
        CouchDocumentBase(
          id: 'conflict-doc-2',
          unmappedProps: {
            'source': 'local',
            'value': 200,
            'modified_by': 'local_client',
          },
        ),
      );
      final localRev2 = localDoc2.rev!;

      // Step 2: Dispose OfflineFirstServer (simulating going offline)
      await ofs.dispose();

      // Step 3: While OfflineFirstServer is "offline", recreate database on server
      // with SAME document IDs but different content (simulating real conflicts)
      if ((await httpServer.allDatabasesNames).contains(dbName)) {
        await httpServer.deleteDatabase(dbName);
      }
      await httpServer.createDatabase(dbName);
      final serverDb1 = (await httpServer.db(dbName))!;

      // Add documents with SAME IDs as local but different content,
      // capture server revisions
      final serverDoc1 = await serverDb1.put(
        CouchDocumentBase(
          id: 'conflict-doc-1',
          unmappedProps: {
            'source': 'server',
            'value': 999,
            'modified_by': 'server_client',
          },
        ),
      );
      final serverRev1 = serverDoc1.rev!;

      final serverDoc2 = await serverDb1.put(
        CouchDocumentBase(
          id: 'conflict-doc-2',
          unmappedProps: {
            'source': 'server',
            'value': 888,
            'modified_by': 'server_client',
          },
        ),
      );
      final serverRev2 = serverDoc2.rev!;

      // Both documents should be version 1 (created independently)
      expect(localRev1, startsWith('1-'));
      expect(localRev2, startsWith('1-'));
      expect(serverRev1, startsWith('1-'));
      expect(serverRev2, startsWith('1-'));

      // Determine expected winners using CouchDB's deterministic algorithm:
      // Same version → lexicographically higher revision hash wins
      final localHash1 = localRev1.substring(localRev1.indexOf('-') + 1);
      final serverHash1 = serverRev1.substring(serverRev1.indexOf('-') + 1);
      final expectedSource1 = localHash1.compareTo(serverHash1) > 0
          ? 'local'
          : 'server';
      final expectedRev1 = localHash1.compareTo(serverHash1) > 0
          ? localRev1
          : serverRev1;

      final localHash2 = localRev2.substring(localRev2.indexOf('-') + 1);
      final serverHash2 = serverRev2.substring(serverRev2.indexOf('-') + 1);
      final expectedSource2 = localHash2.compareTo(serverHash2) > 0
          ? 'local'
          : 'server';
      final expectedRev2 = localHash2.compareTo(serverHash2) > 0
          ? localRev2
          : serverRev2;

      log.info(
        'conflict-doc-1: localRev=$localRev1, serverRev=$serverRev1 '
        '→ expected winner: $expectedSource1 (higher hash wins)',
      );
      log.info(
        'conflict-doc-2: localRev=$localRev2, serverRev=$serverRev2 '
        '→ expected winner: $expectedSource2 (higher hash wins)',
      );

      // Write marker with different UUID to trigger database recreation detection
      final remoteUuid = 'remote-db-uuid-real-conflict';
      final remoteMarker = DatabaseSyncMarker(
        instanceUuid: 'remote-instance',
        databaseUuid: remoteUuid,
        createdAt: DateTime.now(),
        createdBy: 'remote',
        activeInstances: ['remote-instance'],
        tombstone: false,
      );
      await serverDb1.put(remoteMarker);

      // Step 4: Recreate OfflineFirstServer and login — merge reconciles
      // database existence (adopts remote marker), then replication syncs data
      final ofs2 = OfflineFirstServer(
        existingDatabaseSyncingStrategy: ExistingDatabasesSyncStrategie.merge,
      );
      await ofs2.login(
        httpServer.uri.toString(),
        adminUser,
        adminPassword,
        localPath,
      );

      // Step 5: Get database and wait for replication to complete
      final db2 = (await ofs2.db(dbName) as OfflineFirstDb?)!;
      await waitForSync(db2, maxSeconds: 10);

      // Verify merge adopted remote marker
      final localMarker2 =
          await db2.localDb.get('_local/db_sync_marker') as DatabaseSyncMarker?;
      expect(
        localMarker2?.databaseUuid,
        equals(remoteUuid),
        reason: 'Merge should adopt remote UUID',
      );

      // Step 6: Verify CouchDB deterministic conflict resolution
      // The winner is NOT "server always wins" or "local always wins" — it's
      // determined purely by comparing revision hashes lexicographically.

      final result1Local = await db2.localDb.get('conflict-doc-1');
      expect(
        result1Local,
        isNotNull,
        reason: 'conflict-doc-1 should exist locally',
      );

      final result2Local = await db2.localDb.get('conflict-doc-2');
      expect(
        result2Local,
        isNotNull,
        reason: 'conflict-doc-2 should exist locally',
      );

      final serverDb2 = (await httpServer.db(dbName))!;

      final result1Server = await serverDb2.get('conflict-doc-1');
      expect(
        result1Server,
        isNotNull,
        reason: 'conflict-doc-1 should exist on server',
      );

      final result2Server = await serverDb2.get('conflict-doc-2');
      expect(
        result2Server,
        isNotNull,
        reason: 'conflict-doc-2 should exist on server',
      );

      // Verify the winning document matches the CouchDB deterministic algorithm
      expect(
        (result1Local as CouchDocumentBase).unmappedProps['source'],
        equals(expectedSource1),
        reason:
            'conflict-doc-1: revision with higher hash should win '
            '(local=$localHash1, server=$serverHash1)',
      );
      expect(
        (result2Local as CouchDocumentBase).unmappedProps['source'],
        equals(expectedSource2),
        reason:
            'conflict-doc-2: revision with higher hash should win '
            '(local=$localHash2, server=$serverHash2)',
      );

      // Verify the winning revision matches the expected one
      expect(
        result1Local.rev,
        equals(expectedRev1),
        reason: 'conflict-doc-1 should have the winning revision',
      );
      expect(
        result2Local.rev,
        equals(expectedRev2),
        reason: 'conflict-doc-2 should have the winning revision',
      );

      // Verify both sides converged to the same document (consistency)
      expect(
        (result1Local).unmappedProps['source'],
        equals((result1Server as CouchDocumentBase).unmappedProps['source']),
        reason: 'conflict-doc-1: local and server should agree on the winner',
      );
      expect(
        (result2Local).unmappedProps['source'],
        equals((result2Server as CouchDocumentBase).unmappedProps['source']),
        reason: 'conflict-doc-2: local and server should agree on the winner',
      );

      log.info(
        'Deterministic conflict resolution verified: '
        'doc1 won by $expectedSource1, doc2 won by $expectedSource2',
      );

      await ofs2.dispose();
      await tearDownAllHttpFunction();
    },
  );

  test(
    'create user as admin, login with OfflineFirstServer without admin, create document and verify replication',
    () async {
      // Start CouchDB
      await shutdownAllCouchDbContainers();
      dockerid = await startCouchDb(adminUser, adminPassword, false);

      // Login as admin
      final adminServer = HttpDartCouchServer();
      final adminLogin = await adminServer.login(
        "http://localhost:5984",
        adminUser,
        adminPassword,
      );
      expect(adminLogin!.success, isTrue);

      // Create a user
      final user = "testuser";
      final password = "testpassword";
      await adminServer.createUser(user, password);

      // Wait for user database to be available
      final userDbName = DartCouchDb.usernameToDbName(user);
      await waitForCondition(() async {
        return (await adminServer.allDatabasesNames).contains(userDbName);
      });

      // Login with OfflineFirstServer as the created user
      final localPath = prepareSqliteDir();
      final ofs = OfflineFirstServer();
      final userLogin = await ofs.login(
        "http://localhost:5984",
        user,
        password,
        localPath,
      );
      expect(userLogin!.success, isTrue);

      // Get the user database - should now adopt it automatically
      final db = await ofs.db(userDbName) as OfflineFirstDb?;
      expect(db, isNotNull);

      // Create a document
      log.info('Creating test document in user database');
      final testDoc = CouchDocumentBase(
        id: 'user_doc_1',
        unmappedProps: {
          'name': 'User Document 1',
          'value': 42,
          'category': 'test',
        },
      );
      final putResult = await db!.put(testDoc);
      expect(putResult.id, 'user_doc_1');
      expect(putResult.rev, isNotNull);

      // Wait for replication to complete
      log.info('Waiting for document to sync to server');
      await waitForSync(db, maxSeconds: 5);

      // Verify document is in local db
      final localDoc = await db.localDb.get('user_doc_1');
      expect(localDoc, isNotNull);
      expect(
        (localDoc as CouchDocumentBase).unmappedProps['name'],
        'User Document 1',
      );
      expect(localDoc.unmappedProps['value'], 42);

      // Verify document is replicated to server
      log.info('Verifying document synced to server');
      final serverDb = await adminServer.db(userDbName);
      final serverDoc = await serverDb!.get('user_doc_1');
      expect(serverDoc, isNotNull);
      expect(
        (serverDoc as CouchDocumentBase).unmappedProps['name'],
        'User Document 1',
      );
      expect(serverDoc.unmappedProps['value'], 42);
      log.info('Document successfully replicated to server');

      // Cleanup
      await ofs.dispose();
      await adminServer.logout();
      await shutdownCouchDb(dockerid!);
      await shutdownAllCouchDbContainers();
      dockerid = null;
    },
  );
}
