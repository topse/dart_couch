import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dart_couch/dart_couch.dart';
import 'package:test/test.dart';

import 'helper/couch_test_manager.dart';
import 'helper/helper.dart';

// Fixed seed for reproducible test data.
final _random = Random(11);
Uint8List _randomBytes(int length) =>
    Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

void main() {
  DartCouchDb.ensureInitialized();

  configureTestLogging();

  group('HttpDartCouchServer attachment cache sweep', () {
    final cm = CouchTestManager();

    setUpAll(() async {
      await cm.init();
    });

    tearDownAll(() async {
      await cm.dispose();
    });

    test(
      'login() sweeps a cache directory orphaned by a crashed process',
      () async {
        final dbName = 'testdb_sweep_crash';
        final scriptPath =
            '${Directory.current.path}/test/helper/attachment_cache_lock_holder.dart';
        final proc = await Process.start('dart', [
          'run',
          scriptPath,
          cm.uri,
          CouchTestManager.adminUser,
          CouchTestManager.adminPassword,
          dbName,
        ]);

        String? cacheDirLine;
        await for (final line
            in proc.stdout.transform(utf8.decoder).transform(LineSplitter())) {
          if (line.startsWith('CACHE_DIR:')) {
            cacheDirLine = line;
            break;
          }
        }
        expect(
          cacheDirLine,
          isNotNull,
          reason: 'helper process did not report a cache dir',
        );
        final cacheDir = Directory(
          cacheDirLine!.substring('CACHE_DIR:'.length),
        );
        expect(cacheDir.existsSync(), isTrue);

        // Simulate a crash: SIGKILL, no chance to dispose()/logout().
        proc.kill(ProcessSignal.sigkill);
        await proc.exitCode;

        // The OS releases the helper's advisory lock the instant it dies. A
        // fresh login() should now find and sweep the orphaned directory.
        final server = HttpDartCouchServer();
        final loginResult = await server.login(
          cm.uri,
          CouchTestManager.adminUser,
          CouchTestManager.adminPassword,
        );
        expect(loginResult?.success, isTrue);

        expect(cacheDir.existsSync(), isFalse);

        await server.deleteDatabase(dbName);
        await server.logout();
      },
    );

    test(
      "login()'s sweep does not touch a cache directory this process is still using",
      () async {
        final dbName = 'testdb_sweep_self';
        final server1 = HttpDartCouchServer();
        final loginResult1 = await server1.login(
          cm.uri,
          CouchTestManager.adminUser,
          CouchTestManager.adminPassword,
        );
        expect(loginResult1?.success, isTrue);

        final db1 = await server1.createDatabase(dbName);
        final doc = await db1.put(CouchDocumentBase(id: 'doc1'));
        await db1.saveAttachment(
          doc.id!,
          doc.rev!,
          'data.bin',
          _randomBytes(50),
        );
        final path = await db1.getAttachmentAsReadonlyFile(doc.id!, 'data.bin');
        final cacheDir = File(path!).parent;
        expect(cacheDir.existsSync(), isTrue);

        // A second, independent login — still within this same process —
        // triggers its own sweep. db1 above is still alive/undisposed, so
        // its lock is still held; the sweep must leave it alone.
        final server2 = HttpDartCouchServer();
        final loginResult2 = await server2.login(
          cm.uri,
          CouchTestManager.adminUser,
          CouchTestManager.adminPassword,
        );
        expect(loginResult2?.success, isTrue);

        expect(cacheDir.existsSync(), isTrue);

        await server1.deleteDatabase(dbName);
        await server1.logout();
        await server2.logout();
      },
    );
  });
}
