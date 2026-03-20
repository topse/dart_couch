import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dart_couch/dart_couch.dart';
import 'package:logging/logging.dart';

import 'helper/helper.dart';

/// Generates random binary data of the specified size in bytes.
Uint8List _generateAttachment(int sizeInBytes, [int seed = 42]) {
  final random = Random(seed);
  return Uint8List.fromList(
    List<int>.generate(sizeInBytes, (_) => random.nextInt(256)),
  );
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}

String _formatDuration(Duration d) {
  if (d.inMilliseconds < 1000) return '${d.inMilliseconds}ms';
  return '${(d.inMilliseconds / 1000).toStringAsFixed(2)}s';
}

void main() {

  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    final ls = LineSplitter();
    for (final line in ls.convert(record.message)) {
      // ignore: avoid_print
      print('${record.loggerName} ${record.level.name}: ${record.time}: $line');
    }
  });

  late LocalDartCouchServer server;
  late DartCouchDb db;

  setUp(() async {
    final sqliteDir = prepareSqliteDir();
    server = LocalDartCouchServer(sqliteDir);
    db = await server.createDatabase('perf_test');
  });

  tearDown(() async {
    await server.dispose();
  });

  test('saveAttachment performance at various sizes', () async {
    final sizes = [
      1 * 1024 * 1024, //  1 MB
      5 * 1024 * 1024, //  5 MB
      10 * 1024 * 1024, // 10 MB
      20 * 1024 * 1024, // 20 MB
      30 * 1024 * 1024, // 30 MB
    ];

    log.info('=== saveAttachment performance ===');

    for (final size in sizes) {
      final data = _generateAttachment(size);

      // Create doc first
      final docId = 'save_test_$size';
      final doc = CouchDocumentBase(id: docId, unmappedProps: {'size': size});
      final created = await db.put(doc);

      // Measure saveAttachment
      final sw = Stopwatch()..start();
      await db.saveAttachment(
        docId,
        created.rev!,
        'file.bin',
        data,
        contentType: 'application/octet-stream',
      );
      sw.stop();

      final mbPerSec = (size / (1024 * 1024)) / (sw.elapsedMilliseconds / 1000);
      log.info(
        'SAVE ${_formatBytes(size).padLeft(6)}: '
        '${_formatDuration(sw.elapsed).padLeft(8)}  '
        '(${mbPerSec.toStringAsFixed(1)} MB/s)',
      );
    }
  });

  test('getAttachment performance at various sizes', () async {
    final sizes = [
      1 * 1024 * 1024, //  1 MB
      5 * 1024 * 1024, //  5 MB
      10 * 1024 * 1024, // 10 MB
      20 * 1024 * 1024, // 20 MB
      30 * 1024 * 1024, // 30 MB
    ];

    log.info('=== getAttachment performance ===');

    // Setup: create docs with attachments
    for (final size in sizes) {
      final docId = 'read_test_$size';
      final doc = CouchDocumentBase(id: docId, unmappedProps: {'size': size});
      final created = await db.put(doc);
      await db.saveAttachment(
        docId,
        created.rev!,
        'file.bin',
        _generateAttachment(size),
        contentType: 'application/octet-stream',
      );
    }

    // Measure reads
    for (final size in sizes) {
      final docId = 'read_test_$size';

      final sw = Stopwatch()..start();
      final data = await db.getAttachment(docId, 'file.bin');
      sw.stop();

      expect(data, isNotNull);
      expect(data!.length, size);

      final mbPerSec = (size / (1024 * 1024)) / (sw.elapsedMilliseconds / 1000);
      log.info(
        'READ ${_formatBytes(size).padLeft(6)}: '
        '${_formatDuration(sw.elapsed).padLeft(8)}  '
        '(${mbPerSec.toStringAsFixed(1)} MB/s)',
      );
    }
  });

  test('bulkDocsRaw write performance with inline attachments', () async {
    final sizes = [
      1 * 1024 * 1024, //  1 MB
      5 * 1024 * 1024, //  5 MB
      10 * 1024 * 1024, // 10 MB
      20 * 1024 * 1024, // 20 MB
      30 * 1024 * 1024, // 30 MB
    ];

    log.info('=== bulkDocsRaw (replication path) write performance ===');

    for (final size in sizes) {
      final docId = 'bulk_test_$size';
      final data = _generateAttachment(size);
      final b64 = base64Encode(data);

      // Build a JSON doc like the replication pipeline produces
      final docJson = jsonEncode({
        '_id': docId,
        '_rev': '1-abc$size',
        '_revisions': {
          'start': 1,
          'ids': ['abc$size'],
        },
        'size': size,
        '_attachments': {
          'file.bin': {
            'content_type': 'application/octet-stream',
            'revpos': 1,
            'data': b64,
          },
        },
      });

      log.info(
        'bulkDocsRaw doc for ${_formatBytes(size)}: '
        '${_formatBytes(docJson.length)} JSON payload',
      );

      final sw = Stopwatch()..start();
      await db.bulkDocsRaw([docJson], newEdits: false);
      sw.stop();

      final mbPerSec = (size / (1024 * 1024)) / (sw.elapsedMilliseconds / 1000);
      log.info(
        'BULK ${_formatBytes(size).padLeft(6)}: '
        '${_formatDuration(sw.elapsed).padLeft(8)}  '
        '(${mbPerSec.toStringAsFixed(1)} MB/s)',
      );
    }
  });

  test('getRaw with attachments (replication read path)', () async {
    final sizes = [
      1 * 1024 * 1024, //  1 MB
      5 * 1024 * 1024, //  5 MB
      10 * 1024 * 1024, // 10 MB
      20 * 1024 * 1024, // 20 MB
      30 * 1024 * 1024, // 30 MB
    ];

    log.info('=== getRaw with attachments (replication read path) ===');

    // Setup: write docs via bulkDocsRaw (replication path)
    for (final size in sizes) {
      final docId = 'getraw_test_$size';
      final data = _generateAttachment(size);
      final b64 = base64Encode(data);

      final docJson = jsonEncode({
        '_id': docId,
        '_rev': '1-raw$size',
        '_revisions': {
          'start': 1,
          'ids': ['raw$size'],
        },
        'size': size,
        '_attachments': {
          'file.bin': {
            'content_type': 'application/octet-stream',
            'revpos': 1,
            'data': b64,
          },
        },
      });

      await db.bulkDocsRaw([docJson], newEdits: false);
    }

    // Measure reads
    for (final size in sizes) {
      final docId = 'getraw_test_$size';

      final sw = Stopwatch()..start();
      final doc = await db.getRaw(docId, attachments: true);
      sw.stop();

      expect(doc, isNotNull);

      final mbPerSec = (size / (1024 * 1024)) / (sw.elapsedMilliseconds / 1000);
      log.info(
        'RRAW ${_formatBytes(size).padLeft(6)}: '
        '${_formatDuration(sw.elapsed).padLeft(8)}  '
        '(${mbPerSec.toStringAsFixed(1)} MB/s)',
      );
    }
  });
}
