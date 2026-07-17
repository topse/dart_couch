// Standalone helper process for attachment_cache_sweep_test.dart.
//
// Logs in, creates (or reuses) a database, downloads one attachment via
// getAttachmentAsReadonlyFile() — which creates and locks its cache
// directory — prints that directory's path, then hangs until killed. The
// parent test SIGKILLs this process to simulate a crash (no clean
// dispose()/logout()), then verifies a fresh login() elsewhere sweeps the
// now-orphaned, now-unlocked cache directory away.
//
// Args: <couchUri> <adminUser> <adminPassword> <dbName>
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_couch/dart_couch.dart';

Future<void> main(List<String> args) async {
  final uri = args[0];
  final user = args[1];
  final password = args[2];
  final dbName = args[3];

  DartCouchDb.ensureInitialized();
  final server = HttpDartCouchServer();
  final result = await server.login(uri, user, password);
  if (result == null || !result.success) {
    stderr.writeln('LOGIN_FAILED');
    exitCode = 1;
    return;
  }

  DartCouchDb db;
  if (await server.dbExists(dbName)) {
    db = (await server.db(dbName))!;
  } else {
    db = await server.createDatabase(dbName);
  }

  final doc = await db.put(CouchDocumentBase(id: 'doc1'));
  await db.saveAttachment(
    doc.id!,
    doc.rev!,
    'data.bin',
    Uint8List.fromList([1, 2, 3]),
  );
  final path = await db.getAttachmentAsReadonlyFile(doc.id!, 'data.bin');

  // ignore: avoid_print
  print('CACHE_DIR:${File(path!).parent.path}');
  await Future.delayed(const Duration(hours: 1));
}
