import 'package:test/test.dart';
import 'package:dart_couch/dart_couch.dart';

import 'helper/helper.dart';

void main() {

  test('connection state offline', () async {
    await shutdownAllCouchDbContainers();

    final httpServer = HttpDartCouchServer();
    expect(
      httpServer.connectionState.value,
      DartCouchConnectionState.disconnected,
    );

    final loginResult = await httpServer.login(
      'http://localhost:5984',
      adminUser,
      adminPassword,
    );
    expect(loginResult, isNull);
    expect(
      httpServer.connectionState.value,
      DartCouchConnectionState.loginFailedWithNetworkError,
    );

    await httpServer.logout();
    expect(
      httpServer.connectionState.value,
      DartCouchConnectionState.disconnected,
    );
  });

  test('connection state online', () async {
    await shutdownAllCouchDbContainers();
    HttpDartCouchServer httpServer =
        await setUpAllHttpFunction() as HttpDartCouchServer;

    expect(
      httpServer.connectionState.value,
      DartCouchConnectionState.connected,
    );

    await httpServer.logout();
    expect(
      httpServer.connectionState.value,
      DartCouchConnectionState.disconnected,
    );

    await tearDownAllHttpFunction();
  });

  test('connection state changing synchronous', () async {
    await shutdownAllCouchDbContainers();

    final httpServer = HttpDartCouchServer();
    expect(
      httpServer.connectionState.value,
      DartCouchConnectionState.disconnected,
    );

    LoginResult? loginResult = await httpServer.login(
      'http://localhost:5984',
      adminUser,
      adminPassword,
    );
    expect(loginResult, isNull);
    expect(
      httpServer.connectionState.value,
      DartCouchConnectionState.loginFailedWithNetworkError,
    );

    dockerid = await startCouchDb(adminUser, adminPassword, false);

    loginResult = await httpServer.login(
      'http://localhost:5984',
      adminUser,
      "jjj",
    );
    expect(loginResult, isNotNull);
    expect(loginResult!.success, isFalse);
    expect(loginResult.statusCode, CouchDbStatusCodes.unauthorized);
    expect(
      httpServer.connectionState.value,
      DartCouchConnectionState.wrongCredentials,
    );

    loginResult = await httpServer.login(
      'http://localhost:5984',
      adminUser,
      adminPassword,
    );
    expect(loginResult, isNotNull);
    expect(loginResult!.success, isTrue);
    expect(loginResult.body!.username, equals("admin"));
    expect(loginResult.body!.roles, hasLength(1));
    expect(loginResult.body!.roles.first, equals("_admin"));
    expect(loginResult.statusCode, CouchDbStatusCodes.ok);
    expect(
      httpServer.connectionState.value,
      DartCouchConnectionState.connected,
    );

    await expectLater(httpServer.allDatabasesNames, completion(hasLength(3)));

    await pauseCouchDbContainer(dockerid!);

    await expectLater(
      httpServer.allDatabasesNames,
      throwsA(isA<NetworkFailure>()),
    );
    expect(
      httpServer.connectionState.value,
      DartCouchConnectionState.connectedButNetworkError,
    );

    await restartCouchDbContainer(dockerid!);

    await expectLater(httpServer.allDatabasesNames, completion(hasLength(3)));
    expect(
      httpServer.connectionState.value,
      DartCouchConnectionState.connected,
    );

    await httpServer.logout();
    expect(
      httpServer.connectionState.value,
      DartCouchConnectionState.disconnected,
    );
    await pauseCouchDbContainer(dockerid!);
  });

  test('User management', () async {
    final httpServer = await setUpAllHttpFunction() as HttpDartCouchServer;

    // Test creating a user
    final testUsername = 'testuser';
    final testPassword = 'testpassword123';
    final testRoles = ['developer', 'tester'];

    // Get initial database list
    //final initialDbs = await httpServer.allDatabasesNames;

    // Verify user database naming algorithm
    final expectedUserDbName = DartCouchDb.usernameToDbName(testUsername);
    expect(expectedUserDbName, equals('userdb-7465737475736572'));

    // Verify the algorithm is reversible
    final decodedUsername = DartCouchDb.dbNameToUsername(expectedUserDbName);
    expect(decodedUsername, equals(testUsername));

    // Create the user
    final createdUser = await httpServer.createUser(
      testUsername,
      testPassword,
      roles: testRoles,
    );

    expect(createdUser.name, equals(testUsername));
    expect(createdUser.type, equals('user'));
    expect(createdUser.roles, equals(testRoles));
    expect(createdUser.id, equals('org.couchdb.user:$testUsername'));

    // CouchDB automatically creates a user database when a user is created
    // Wait for database creation
    final userDbCreated = await waitForCondition(() async {
      final dbs = await httpServer.allDatabasesNames;
      return dbs.contains(expectedUserDbName);
    });
    expect(
      userDbCreated,
      isTrue,
      reason: 'User database should be created automatically',
    );

    // Verify user database was created
    final dbsAfterUserCreation = await httpServer.allDatabasesNames;
    expect(
      dbsAfterUserCreation,
      contains(expectedUserDbName),
      reason: 'User database should be created automatically',
    );

    // Verify the database exists using our helper
    final userDbExists = await httpServer.dbExists(expectedUserDbName);
    expect(userDbExists, isTrue);

    // Test getting a user
    final retrievedUser = await httpServer.getUser(testUsername);
    expect(retrievedUser!.name, equals(testUsername));
    expect(retrievedUser.id, equals('org.couchdb.user:$testUsername'));
    expect(retrievedUser.roles, equals(testRoles));

    // Test listing users
    final users = await httpServer.listUsers();
    expect(users, isNotEmpty);
    final foundUser = users.firstWhere((u) => u.name == testUsername);
    expect(foundUser.name, equals(testUsername));

    // Test deleting a user
    await httpServer.deleteUser(testUsername);

    // Verify user is deleted
    await expectLater(httpServer.getUser(testUsername), completion(isNull));

    // Verify user is not in list anymore
    final usersAfterDelete = await httpServer.listUsers();
    expect(usersAfterDelete.where((u) => u.name == testUsername), isEmpty);

    // CouchDB automatically deletes the user database when user is deleted
    // Wait for database deletion
    final userDbDeleted = await waitForCondition(() async {
      final dbs = await httpServer.allDatabasesNames;
      return !dbs.contains(expectedUserDbName);
    });
    expect(
      userDbDeleted,
      isTrue,
      reason: 'User database should be deleted automatically',
    );

    // Verify user database was deleted
    final dbsAfterUserDeletion = await httpServer.allDatabasesNames;
    expect(
      dbsAfterUserDeletion,
      isNot(contains(expectedUserDbName)),
      reason: 'User database should be deleted automatically',
    );

    // Double-check with dbExists
    final userDbExistsAfterDeletion = await httpServer.dbExists(
      expectedUserDbName,
    );
    expect(userDbExistsAfterDeletion, isFalse);

    await tearDownAllHttpFunction();
  });

  test('db updates', () async {
    await shutdownAllCouchDbContainers();
    HttpDartCouchServer httpServer =
        await setUpAllHttpFunction() as HttpDartCouchServer;

    await httpServer.createDatabase('testdb1');
    await httpServer.createDatabase('testdb2');
    await httpServer.deleteDatabase('testdb1');

    await waitForCondition(() async {
      final updates = await httpServer.dbUpdates();
      return updates.results.length >= 3;
    });

    final updates = await httpServer.dbUpdates();

    int findIndex(final String dbName, final DbUpdateType type) {
      for (int i = 0; i < updates.results.length; i++) {
        final entry = updates.results[i];
        if (entry.dbName == dbName && entry.type == type) {
          return i;
        }
      }
      return -1;
    }

    expect(findIndex('testdb1', DbUpdateType.created), isNot(-1));
    expect(findIndex('testdb2', DbUpdateType.created), isNot(-1));
    expect(findIndex('testdb1', DbUpdateType.deleted), isNot(-1));
    expect(
      findIndex('testdb1', DbUpdateType.deleted) >
          findIndex('testdb1', DbUpdateType.created),
      isTrue,
    );

    await tearDownAllHttpFunction();
  });
}
