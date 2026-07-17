import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// Creates a [QueryExecutor] backed by Drift's WASM SQLite on web.
///
/// The [file] parameter is typed as `dynamic` because we cannot import
/// `dart:io` on web — it is actually the io_shim `File` whose `.path` is
/// used to derive the database name. [tempDir] is ignored on web.
QueryExecutor openDatabaseConnection({dynamic file, String? tempDir}) {
  final name = _deriveName(file);
  return LazyDatabase(() async {
    final db = await WasmDatabase.open(
      databaseName: name,
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
    );
    return db.resolvedExecutor;
  });
}

/// Sanitise a file path (or Directory path) into a valid database name.
String _deriveName(dynamic file) {
  if (file == null) return 'dart_couch';
  final path = file.path as String;
  // Strip the filename (db.sqlite) and use the directory part, then sanitise.
  final segments = path
      .replaceAll('\\', '/')
      .split('/')
      .where((s) => s.isNotEmpty && s != 'db.sqlite')
      .toList();
  if (segments.isEmpty) return 'dart_couch';
  return segments.join('_').replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
}
