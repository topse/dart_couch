import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';

import 'package:dart_couch/dart_couch.dart';
import 'package:test/test.dart';
import 'package:logging/logging.dart';

import 'helper/helper.dart';
import 'helper/test_document_one.dart';

// 100 random bytes used as application/octet-stream attachment data.
// Using a fixed seed ensures reproducible tests.
final _random = Random(42);
final Uint8List _binaryData = Uint8List.fromList(
  List.generate(100, (_) => _random.nextInt(256)),
);

// Large enough for CouchDB to compress (text/plain is compressible).
final Uint8List _textContent = Uint8List.fromList(
  utf8.encode('The quick brown fox jumps over the lazy dog.\n' * 50),
);

void main() {
  DartCouchDb.ensureInitialized();

  Logger.root.level = Level.FINEST;
  Logger.root.onRecord.listen((record) {
    final ls = LineSplitter();
    for (final line in ls.convert(record.message)) {
      // ignore: avoid_print
      print('${record.loggerName} ${record.level.name}: ${record.time}: $line');
    }
  });

  // ---------------------------------------------------------------------------
  // HTTP-to-local replication: encoding field is preserved after sync
  // ---------------------------------------------------------------------------
  group('attachment encoding (HTTP-to-local replication)', () {
    late HttpDartCouchServer httpServer;
    late LocalDartCouchServer localServer;
    late String dockerContainerId;

    setUp(() async {
      await shutdownAllCouchDbContainers();
      dockerContainerId = await startCouchDb(adminUser, adminPassword, false);
      httpServer = HttpDartCouchServer();
      await doLogin(httpServer, adminUser, adminPassword);
      localServer = LocalDartCouchServer(prepareSqliteDir());
    });

    tearDown(() async {
      await localServer.dispose();
      await httpServer.logout();
      await shutdownCouchDb(dockerContainerId);
      await shutdownAllCouchDbContainers();
    });

    // Replicate one doc/rev from [httpDb] to [localDb] via
    // bulkGetMultipart → bulkDocsFromMultipart.
    Future<BulkGetMultipartSuccess> replicate(
      DartCouchDb httpDb,
      DartCouchDb localDb,
      String docId,
      String rev,
    ) async {
      final request = BulkGetRequest(
        docs: [BulkGetRequestDoc(id: docId, rev: rev)],
      );
      final successes = <BulkGetMultipartSuccess>[];
      await for (final r in httpDb.bulkGetMultipart(request, revs: true)) {
        successes.add(r as BulkGetMultipartSuccess);
      }
      await localDb.bulkDocsFromMultipart(successes);
      return successes.single;
    }

    test(
      'text/plain replicated from CouchDB has encoding gzip in local DB',
      () async {
        final dbName = 'testdb_enc_text';
        final httpDb = await httpServer.createDatabase(dbName);
        final localDb = await localServer.createDatabase(dbName);

        final doc = await httpDb.put(TestDocumentOne(id: 'doc1', name: 'test'));
        final attRev = await httpDb.saveAttachment(
          doc.id!,
          doc.rev!,
          'readme.txt',
          _textContent,
          contentType: 'text/plain',
        );

        // Replicate from HTTP to local.
        final multipartResult = await replicate(
          httpDb,
          localDb,
          doc.id!,
          attRev,
        );

        // Source (HTTP): CouchDB compressed text/plain → encoding == 'gzip'.
        final httpAtt = multipartResult.ok.attachments['readme.txt']!;
        expect(httpAtt.encoding, equals('gzip'));

        // Target (local): encoding preserved in DB and surfaced by bulkGetMultipart.
        final localRequest = BulkGetRequest(
          docs: [BulkGetRequestDoc(id: doc.id!, rev: attRev)],
        );
        BulkGetMultipartSuccess? localResult;
        await for (final r in localDb.bulkGetMultipart(
          localRequest,
          revs: false,
        )) {
          localResult = r as BulkGetMultipartSuccess;
        }
        expect(localResult, isNotNull);
        final localAtt = localResult!.ok.attachments['readme.txt']!;
        expect(localAtt.encoding, equals('gzip'));

        // getAttachment always returns decompressed bytes regardless of encoding.
        final bytes = await localDb.getAttachment(doc.id!, 'readme.txt');
        expect(bytes, equals(_textContent));

        // get() stub: encoding accessible via AttachmentInfo.encoding.
        // toMap() must NOT include 'encoding' (hook strips it).
        final localDoc = (await localDb.get(doc.id!))!;
        final attInfo = localDoc.attachments!['readme.txt']!;
        expect(attInfo.encoding, equals('gzip'));
        expect(attInfo.toMap(), isNot(contains('encoding')));
      },
    );

    test(
      'binary attachment replicated from CouchDB has encoding null in local DB',
      () async {
        final dbName = 'testdb_enc_bin';
        final httpDb = await httpServer.createDatabase(dbName);
        final localDb = await localServer.createDatabase(dbName);

        final doc = await httpDb.put(TestDocumentOne(id: 'doc1', name: 'test'));
        final attRev = await httpDb.saveAttachment(
          doc.id!,
          doc.rev!,
          'data.bin',
          _binaryData, // application/octet-stream — not compressed by CouchDB
        );

        await replicate(httpDb, localDb, doc.id!, attRev);

        // Binary content type is not compressed by CouchDB → encoding null.
        final localDoc = (await localDb.get(doc.id!))!;
        expect(localDoc.attachments!['data.bin']!.encoding, isNull);

        // Decompressed content still matches original bytes.
        final bytes = await localDb.getAttachment(doc.id!, 'data.bin');
        expect(bytes, equals(_binaryData));
      },
    );
  });
}
