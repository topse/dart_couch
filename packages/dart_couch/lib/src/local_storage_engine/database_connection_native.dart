import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';

/// Creates a [QueryExecutor] backed by native SQLite.
///
/// If [file] is provided, the database is stored on disk (using a background
/// isolate for I/O). If [file] is null, an in-memory database is created.
QueryExecutor openDatabaseConnection({File? file, String? tempDir}) {
  return LazyDatabase(() async {
    if (tempDir != null) {
      // We can't access /tmp on Android, which sqlite3 would try by default.
      sqlite3.tempDirectory = tempDir;
    }

    if (file != null) {
      return NativeDatabase.createInBackground(file);
    } else {
      return NativeDatabase.memory();
    }
  });
}
