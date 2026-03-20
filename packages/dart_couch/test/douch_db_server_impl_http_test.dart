import 'package:test/test.dart';

import 'package:dart_couch/dart_couch.dart';
import 'dart:convert';

import 'package:logging/logging.dart';

import 'helper/helper.dart';

// ignore: non_constant_identifier_names
final bool LOG_COUCH_DB = false;

void main() {
  //hierarchicalLoggingEnabled = true;
  Logger.root.level = Level.FINEST; // defaults to Level.INFO
  Logger.root.onRecord.listen((record) {
    LineSplitter ls = LineSplitter();
    for (final line in ls.convert(record.message)) {
      // ignore: avoid_print
      print('${record.loggerName} ${record.level.name}: ${record.time}: $line');
    }
  });

  group('A group of tests', () {
    late HttpDartCouchServer cc;

    setUpAll(() async {
      cc = await setUpAllHttpFunction() as HttpDartCouchServer;
    });
    tearDownAll(() async {
      await tearDownAllHttpFunction();
    });

    test('login with wrong credentials', () async {
      final c1 = HttpDartCouchServer();
      final res = await c1.login(
        'http://localhost:5984',
        adminUser,
        "wrongpassword",
      );
      expect(res, isNotNull);
      expect(res!.success, false);
      expect(res.statusCode, CouchDbStatusCodes.unauthorized);
    });

    test('query database information', () async {
      DatabaseInfo? dbInfo = await (await (cc.db('_users')))!.info();
      expect(dbInfo, isNotNull);
      expect(dbInfo!.docCount, greaterThanOrEqualTo(0));
    });

    test('get _session', () async {
      final res = await cc.session();
      expect(res, isNotNull);
      expect(res.ok, isTrue);
      expect(res.userCtx.name, adminUser);
    });

    test('create and delete a database', () async {
      final dbName = 'testdb_${DateTime.now().millisecondsSinceEpoch}';
      await cc.createDatabase(dbName);
      final exists = await cc.dbExists(dbName);
      expect(exists, isTrue);

      expect((await cc.allDatabasesNames).contains(dbName), isTrue);

      await cc.deleteDatabase(dbName);
      final existsAfterDelete = await cc.dbExists(dbName);
      expect(existsAfterDelete, isFalse);

      expect((await cc.allDatabasesNames).contains(dbName), isFalse);
    });
  });
}
