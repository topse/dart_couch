import 'dart_couch_db.dart';

abstract class DartCouchServer {
  Future<DartCouchDb> createDatabase(String name);

  Future<void> deleteDatabase(String name);

  Future<List<DartCouchDb>> get allDatabases;
  Future<List<String>> get allDatabasesNames;

  Future<DartCouchDb?> db(String name);

  Future<void> dispose();
}
