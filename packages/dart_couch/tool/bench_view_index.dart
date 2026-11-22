// Standalone benchmark for local view indexing and query overhead.
//
// Runs against a LocalDartCouchServer in a temp directory (no CouchDB, no
// Docker) and prints wall time plus the number of drift queries
// ([DbQueryStats.total] delta) per step.
//
//   dart run tool/bench_view_index.dart [docCount]
//
// docCount defaults to 5000. About 5 % of the docs are `media_folder` /
// `media_item` docs (emitted by the view), the rest `media_track` docs (not
// emitted).
import 'dart:io';

import 'package:dart_couch/dart_couch.dart';

const _mapFunction =
    "function (doc) { if (doc['!doc_type'].startsWith('media_') && "
    "doc['!doc_type'] !== 'media_track') "
    "emit([doc['parent'], doc['sortHint']], doc.name); }";

Future<void> main(List<String> args) async {
  final n = args.isNotEmpty ? int.parse(args.first) : 5000;

  DartCouchDb.ensureInitialized();
  // Must be set before the database connection is opened.
  DbQueryStats.enabled = true;

  final dir = Directory.systemTemp.createTempSync('dart_couch_bench_');
  final server = LocalDartCouchServer(dir);
  try {
    final db = await server.createDatabase('bench');

    var folderCount = 0;
    Map<String, dynamic> body(int i) {
      // every 20th doc is a folder/item (5 %)
      if (i % 20 == 0) {
        final type = (folderCount++).isEven ? 'media_folder' : 'media_item';
        return {
          '!doc_type': type,
          'parent': 'folder-${(i ~/ 400).toString().padLeft(4, '0')}',
          'sortHint': i,
          'name': 'Name $i',
        };
      }
      return {
        '!doc_type': 'media_track',
        'parent': 'item-${(i ~/ 20).toString().padLeft(5, '0')}',
        'sortHint': i % 20,
        'name': 'Track $i',
        'durationMs': 1000 * i,
      };
    }

    final insertWatch = Stopwatch()..start();
    const batch = 500;
    for (var i = 0; i < n; i += batch) {
      await db.bulkDocs([
        for (var j = i; j < i + batch && j < n; j++)
          CouchDocumentBase(
            id: 'doc-${j.toString().padLeft(6, '0')}',
            unmappedProps: body(j),
          ),
      ]);
    }
    await db.put(
      DesignDocument(
        id: '_design/mediatree',
        views: {'by_parent': ViewData(map: _mapFunction)},
      ),
    );
    insertWatch.stop();
    stdout.writeln(
      'inserted $n docs + design doc in ${insertWatch.elapsedMilliseconds} ms',
    );

    final results = <(String, int, int, int)>[];
    Future<void> measure(String label, Future<int> Function() f) async {
      final before = DbQueryStats.total;
      final sw = Stopwatch()..start();
      final rows = await f();
      sw.stop();
      results.add((
        label,
        sw.elapsedMilliseconds,
        DbQueryStats.total - before,
        rows,
      ));
    }

    Future<int> queryView() async =>
        (await db.query('mediatree/by_parent', includeDocs: true))!.rows.length;

    await measure('1 first query (initial index)', queryView);
    await measure('2 second query (no changes)', queryView);
    await measure('3a put media_track', () async {
      await db.put(
        CouchDocumentBase(
          id: 'bench-track',
          unmappedProps: {
            '!doc_type': 'media_track',
            'parent': 'item-00000',
            'sortHint': 99,
            'name': 'new track',
          },
        ),
      );
      return 0;
    });
    await measure('3b query after 3a', queryView);
    await measure('4a put media_item', () async {
      await db.put(
        CouchDocumentBase(
          id: 'bench-item',
          unmappedProps: {
            '!doc_type': 'media_item',
            'parent': 'folder-0000',
            'sortHint': 99,
            'name': 'new item',
          },
        ),
      );
      return 0;
    });
    await measure('4b query after 4a', queryView);
    await measure(
      '5 allDocs(includeDocs: true)',
      () async => (await db.allDocs(includeDocs: true)).rows.length,
    );

    stdout.writeln('');
    stdout.writeln(
      '${'step'.padRight(34)}${'ms'.padLeft(8)}'
      '${'queries'.padLeft(10)}${'rows'.padLeft(8)}',
    );
    for (final (label, ms, queries, rows) in results) {
      stdout.writeln(
        '${label.padRight(34)}${ms.toString().padLeft(8)}'
        '${queries.toString().padLeft(10)}${rows.toString().padLeft(8)}',
      );
    }
  } finally {
    await server.dispose();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}
