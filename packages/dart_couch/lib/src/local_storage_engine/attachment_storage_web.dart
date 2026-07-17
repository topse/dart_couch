import 'package:drift/drift.dart';

import 'attachment_storage.dart';

/// Web-based attachment storage using a raw SQL table in the Drift database.
///
/// On web, there is no filesystem. Attachment binary data is stored in the
/// same SQLite database (backed by Drift WASM / IndexedDB) in a dedicated
/// `attachment_blobs_web` table, accessed via raw SQL.
///
/// The .tmp pattern used on native for crash safety is unnecessary here
/// because SQLite transactions on web are fully atomic — partial writes
/// cannot occur.
class WebAttachmentStorage implements AttachmentStorage {
  final GeneratedDatabase db;

  WebAttachmentStorage(this.db);

  @override
  Future<void> initialize() async {
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS attachment_blobs_web (
        attachment_id INTEGER PRIMARY KEY,
        data BLOB NOT NULL
      )
    ''');
  }

  @override
  Future<Uint8List?> readAttachment(int id) async {
    final result = await db.customSelect(
      'SELECT data FROM attachment_blobs_web WHERE attachment_id = ?',
      variables: [Variable.withInt(id)],
    ).getSingleOrNull();
    if (result == null) return null;
    return result.read<Uint8List>('data');
  }

  @override
  Stream<List<int>> readAttachmentAsStream(int id) {
    // On web, read the full blob and emit as a single-element stream.
    return Stream.fromFuture(readAttachment(id))
        .where((data) => data != null)
        .cast<Uint8List>();
  }

  @override
  Future<void> writeAttachment(int id, Uint8List data) async {
    await db.customStatement(
      'INSERT OR REPLACE INTO attachment_blobs_web (attachment_id, data) VALUES (?, ?)',
      [id, data],
    );
  }

  @override
  Future<void> writeAttachmentFromStream(
    int id,
    Stream<List<int>> stream,
  ) async {
    final chunks = <int>[];
    await for (final chunk in stream) {
      chunks.addAll(chunk);
    }
    await writeAttachment(id, Uint8List.fromList(chunks));
  }

  @override
  Future<void> writeTmpAttachment(int id, Uint8List data) async {
    // On web, writes are atomic within SQLite transactions.
    // Write directly to the final location.
    await writeAttachment(id, data);
  }

  @override
  Future<void> writeTmpAttachmentFromStream(
    int id,
    Stream<List<int>> stream,
  ) async {
    await writeAttachmentFromStream(id, stream);
  }

  @override
  Future<void> promoteTmp(int id) async {
    // No-op on web — writeTmp already wrote to the final location.
  }

  @override
  Future<void> deleteAttachment(int id) async {
    await db.customStatement(
      'DELETE FROM attachment_blobs_web WHERE attachment_id = ?',
      [id],
    );
  }

  @override
  Future<void> prepareForUpdate(int id) async {
    // No-op on web — no file permissions to manage.
  }

  @override
  Future<void> finalizeWrite(int id) async {
    // No-op on web — no file permissions to manage.
  }

  @override
  Future<void> recover(Set<int> knownIds) async {
    if (knownIds.isEmpty) {
      // Delete all blobs if no known attachments
      await db.customStatement('DELETE FROM attachment_blobs_web');
      return;
    }
    // Delete any blob rows whose ID is not in the known set.
    final placeholders = knownIds.map((_) => '?').join(', ');
    await db.customStatement(
      'DELETE FROM attachment_blobs_web WHERE attachment_id NOT IN ($placeholders)',
      knownIds.toList(),
    );
  }

  @override
  Future<String?> getAttachmentPath(int id) async {
    // No file paths on web.
    return null;
  }
}
