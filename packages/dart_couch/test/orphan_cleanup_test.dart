import 'dart:convert';
import 'dart:io';

import 'package:dart_couch/dart_couch.dart';
import 'package:test/test.dart';

import 'helper/helper.dart';

/// API-level orphan-cleanup test (PLAN.md acceptance criterion: "deleting a
/// document or a database leaves zero rows in `local_conflict_revisions` and
/// zero conflict-leaf attachment FILES").
///
/// The drift-level ROW cascade (triggers) is covered by
/// `local_storage_engine_test.dart`. SQL triggers, however, cannot touch the
/// filesystem, so conflict-leaf attachment *files* (`att/{id}`) are removed by
/// the Dart layer: immediately for in-session deletes, and by the startup orphan
/// scan (`LocalDartCouchServer._recoverAttachmentFiles`) for anything a database
/// delete leaves behind (the triggers drop the rows, the files become orphans).
/// This exercises that end-to-end against a real on-disk `att/` directory — the
/// file half the drift tests cannot reach.
void main() {
  configureTestLogging();

  const dbName = 'orphan_db';
  String hx(String tag) => tag.padRight(32, '0');

  // Count the real `att/{integer}` data files on disk (ignores `.tmp` and any
  // non-numeric names).
  int attFileCount(Directory root) {
    final attDir = Directory('${root.path}/att');
    if (!attDir.existsSync()) return 0;
    return attDir
        .listSync()
        .whereType<File>()
        .where((f) => int.tryParse(f.uri.pathSegments.last) != null)
        .length;
  }

  test(
    'deleting the database + restart removes conflict-leaf attachment FILES '
    '(no orphans)',
    () async {
      final dir = prepareSqliteDir();
      var server = LocalDartCouchServer(dir);
      final db = await server.createDatabase(dbName);

      // Inject a gen-2 sibling leaf carrying its own inline attachment via the
      // replication path. application/octet-stream avoids CouchDB-style gzip so
      // the bytes (hence the file) are written verbatim.
      Future<void> inject(String tag, String attName) async {
        await db.bulkDocsRaw([
          jsonEncode({
            '_id': 'd',
            '_rev': '2-${hx(tag)}',
            '_revisions': {
              'start': 2,
              'ids': [hx(tag), hx('a1')],
            },
            'val': tag,
            '_attachments': {
              attName: {
                'content_type': 'application/octet-stream',
                'data': base64Encode([1, 2, 3, 4]),
              },
            },
          }),
        ], newEdits: false);
      }

      // Loser first (becomes winner momentarily), then the higher-hash winner —
      // 'aaaa' is demoted to a conflict leaf and its attachment re-points to that
      // leaf (fkconflict set). Net: one winner file + one conflict-leaf file.
      await inject('aaaa', 'loser.bin');
      await inject('bbbb', 'winner.bin');

      // Sanity: the winner really won and the loser is a stored conflict leaf
      // (so we are genuinely exercising the conflict-leaf attachment path, not a
      // trivially-empty tree).
      expect((await db.getRaw('d'))?['_rev'], '2-${hx('bbbb')}');
      expect(
        (await db.getRaw('d', conflicts: true))?['_conflicts'],
        ['2-${hx('aaaa')}'],
      );
      expect(
        attFileCount(dir),
        2,
        reason: 'winner + conflict-leaf attachments each produced an att/ file',
      );

      // Delete the database: the SQL cascade drops every row (documents, conflict
      // revisions, attachments). The att/ files are now orphans (no matching
      // local_attachments row) — triggers cannot delete files.
      await server.deleteDatabase(dbName);

      // Restart the server on the same directory → _ensureInitialized() runs the
      // orphan scan, which deletes every att/ file with no matching row.
      await server.dispose();
      server = LocalDartCouchServer(dir);
      await server.db(dbName); // triggers _ensureInitialized() → orphan scan

      expect(
        attFileCount(dir),
        0,
        reason: 'orphan scan removed all winner + conflict-leaf att files',
      );

      await server.dispose();
    },
  );
}
