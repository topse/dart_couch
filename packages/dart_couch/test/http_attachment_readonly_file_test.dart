import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dart_couch/dart_couch.dart';
import 'package:test/test.dart';

import 'helper/couch_test_manager.dart';
import 'helper/helper.dart';
import 'helper/test_document_one.dart';

// Fixed seed for reproducible test data.
final _random = Random(7);
Uint8List _randomBytes(int length) =>
    Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

void main() {
  DartCouchDb.ensureInitialized();

  configureTestLogging();

  group('HttpDartCouchDb.getAttachmentAsReadonlyFile', () {
    final cm = CouchTestManager();

    setUpAll(() async {
      await cm.init();
    });

    tearDownAll(() async {
      await cm.dispose();
    });

    setUp(() async {
      await cm.prepareNewTest();
    });

    tearDown(() async {
      await cm.cleanupAfterTest();
    });

    test(
      'downloads the attachment to a real file on disk with matching content',
      () async {
        final db = await cm.httpDb();
        final doc = await db.put(TestDocumentOne(id: 'doc1', name: 'test'));
        final content = _randomBytes(200);
        await db.saveAttachment(doc.id!, doc.rev!, 'data.bin', content);

        final path = await db.getAttachmentAsReadonlyFile(doc.id!, 'data.bin');

        expect(path, isNotNull);
        final file = File(path!);
        expect(file.existsSync(), isTrue);
        expect(await file.readAsBytes(), equals(content));

        // Lives in a per-database "dart_couch-<id>_tmp" folder under the OS
        // temp directory, per the documented layout.
        final folderName = file.parent.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last;
        expect(folderName, startsWith('dart_couch-'));
        expect(folderName, endsWith('_tmp'));
        expect(file.parent.parent.path, equals(Directory.systemTemp.path));
      },
    );

    test('preserves the attachment name\'s file extension', () async {
      final db = await cm.httpDb();
      final doc = await db.put(TestDocumentOne(id: 'doc1', name: 'test'));
      await db.saveAttachment(doc.id!, doc.rev!, 'photo.jpg', _randomBytes(50));

      final path = await db.getAttachmentAsReadonlyFile(doc.id!, 'photo.jpg');

      expect(path, endsWith('.jpg'));
    });

    test(
      'returns the identical cached path on repeated calls while the digest is unchanged',
      () async {
        final db = await cm.httpDb();
        final doc = await db.put(TestDocumentOne(id: 'doc1', name: 'test'));
        await db.saveAttachment(
          doc.id!,
          doc.rev!,
          'data.bin',
          _randomBytes(200),
        );

        final path1 = await db.getAttachmentAsReadonlyFile(doc.id!, 'data.bin');
        final path2 = await db.getAttachmentAsReadonlyFile(doc.id!, 'data.bin');

        // A cache miss always mints a fresh uuid filename, so an identical
        // path across two calls is only possible via the cached-digest path
        // — i.e. proof the second call did not re-download.
        expect(path2, equals(path1));
      },
    );

    test(
      'concurrent calls for the same attachment de-dupe to one fetch',
      () async {
        final db = await cm.httpDb();
        final doc = await db.put(TestDocumentOne(id: 'doc1', name: 'test'));
        await db.saveAttachment(
          doc.id!,
          doc.rev!,
          'data.bin',
          _randomBytes(200),
        );

        final paths = await Future.wait([
          db.getAttachmentAsReadonlyFile(doc.id!, 'data.bin'),
          db.getAttachmentAsReadonlyFile(doc.id!, 'data.bin'),
          db.getAttachmentAsReadonlyFile(doc.id!, 'data.bin'),
        ]);

        expect(paths.toSet(), hasLength(1));
      },
    );

    test(
      'a file already handed out survives the attachment being updated to a new revision',
      () async {
        final db = await cm.httpDb();
        final doc = await db.put(TestDocumentOne(id: 'doc1', name: 'test'));
        final contentA = _randomBytes(200);
        final revA = await db.saveAttachment(
          doc.id!,
          doc.rev!,
          'data.bin',
          contentA,
        );

        final pathA = await db.getAttachmentAsReadonlyFile(doc.id!, 'data.bin');
        expect(pathA, isNotNull);

        final contentB = _randomBytes(200);
        await db.saveAttachment(doc.id!, revA, 'data.bin', contentB);

        final pathB = await db.getAttachmentAsReadonlyFile(doc.id!, 'data.bin');

        expect(pathB, isNotNull);
        expect(pathB, isNot(equals(pathA)));

        // The old file must still be present and unchanged — a caller that
        // fetched pathA earlier (e.g. a still-open file handle, or a UI
        // still displaying it) must never have it deleted or overwritten
        // out from under them.
        expect(File(pathA!).existsSync(), isTrue);
        expect(await File(pathA).readAsBytes(), equals(contentA));
        expect(await File(pathB!).readAsBytes(), equals(contentB));
      },
    );

    test('returns null for a non-existent attachment', () async {
      final db = await cm.httpDb();
      final doc = await db.put(TestDocumentOne(id: 'doc1', name: 'test'));

      final path = await db.getAttachmentAsReadonlyFile(
        doc.id!,
        'does-not-exist.bin',
      );

      expect(path, isNull);
    });

    test('returns null for a non-existent document', () async {
      final db = await cm.httpDb();

      final path = await db.getAttachmentAsReadonlyFile(
        'no-such-doc',
        'data.bin',
      );

      expect(path, isNull);
    });

    test('dispose() removes the entire cache directory from disk', () async {
      // Uses its own server/login instead of cm.httpServer(), so that
      // logging out here doesn't interfere with cm's own teardown bookkeeping
      // for the shared container.
      final server = HttpDartCouchServer();
      final loginResult = await server.login(
        cm.uri,
        CouchTestManager.adminUser,
        CouchTestManager.adminPassword,
      );
      expect(loginResult?.success, isTrue);

      final db = await server.createDatabase('testdb_ro_dispose');
      final doc = await db.put(TestDocumentOne(id: 'doc1', name: 'test'));
      await db.saveAttachment(doc.id!, doc.rev!, 'data.bin', _randomBytes(200));

      final path = await db.getAttachmentAsReadonlyFile(doc.id!, 'data.bin');
      final cacheDir = File(path!).parent;
      expect(cacheDir.existsSync(), isTrue);

      // deleteDatabase() disposes the removed instance (see
      // HttpDartCouchServer.deleteDatabase), which triggers (best-effort,
      // fire-and-forget — dispose() is a synchronous API) deletion of its
      // cache directory. Poll rather than assume it has already completed.
      await server.deleteDatabase('testdb_ro_dispose');
      await server.logout();

      final removed = await waitForCondition(
        () async => !cacheDir.existsSync(),
      );
      expect(
        removed,
        isTrue,
        reason: 'cache directory ${cacheDir.path} was not cleaned up',
      );
    });
  });
}
