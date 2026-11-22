import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:logging/logging.dart';
import 'package:sqlite3/sqlite3.dart';

import 'db_query_stats.dart';

final _sqliteLog = Logger('dart_couch-sqlite');

/// Creates a [QueryExecutor] backed by native SQLite.
///
/// If [file] is provided, the database is stored on disk (using a background
/// isolate for I/O). If [file] is null, an in-memory database is created.
QueryExecutor openDatabaseConnection({File? file, String? tempDir}) {
  return DbQueryStats.wrap(LazyDatabase(() async {
    try {
      final v = sqlite3.version;
      _sqliteLog.info(
          'SQLite in use: libVersion=${v.libVersion} '
          'versionNumber=${v.versionNumber} sourceId=${v.sourceId}');
    } catch (e) {
      _sqliteLog.warning('Could not determine SQLite version: $e');
    }

    if (tempDir != null) {
      // We can't access /tmp on Android, which sqlite3 would try by default.
      sqlite3.tempDirectory = tempDir;
    }

    if (file != null) {
      return NativeDatabase.createInBackground(file);
    } else {
      return NativeDatabase.memory();
    }
  }));
}
