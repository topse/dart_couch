import 'dart:typed_data';

/// Platform-agnostic interface for attachment binary data storage.
///
/// On native platforms, attachments are stored as files in `att/{id}`.
/// On web, attachments are stored as BLOBs in a Drift table.
///
/// This interface abstracts over the platform-specific storage mechanism
/// so that [LocalDartCouchDb] and [LocalDartCouchServer] can work on
/// all platforms with identical logic.
abstract class AttachmentStorage {
  /// Initialize the storage backend.
  /// On native: no-op (directories are created in the constructor).
  /// On web: creates the `attachment_blobs_web` table if it doesn't exist.
  Future<void> initialize() async {}

  /// Read the attachment data for [id].
  /// Returns null if the attachment does not exist.
  Future<Uint8List?> readAttachment(int id);

  /// Get a read stream for the attachment [id].
  /// Used by bulkGetMultipart for streaming attachment data.
  Stream<List<int>> readAttachmentAsStream(int id);

  /// Write attachment [data] for [id].
  Future<void> writeAttachment(int id, Uint8List data);

  /// Write attachment data from a [stream] for [id].
  Future<void> writeAttachmentFromStream(int id, Stream<List<int>> stream);

  /// Write temporary attachment data for [id] (used during UPDATE).
  /// On native: writes to `att/{id}.tmp`.
  /// On web: no-op or writes to a temporary key (transactions are atomic).
  Future<void> writeTmpAttachment(int id, Uint8List data);

  /// Write temporary attachment data from a [stream] for [id].
  Future<void> writeTmpAttachmentFromStream(
    int id,
    Stream<List<int>> stream,
  );

  /// Promote the temporary attachment to final for [id].
  /// On native: renames `att/{id}.tmp` → `att/{id}`.
  /// On web: copies tmp to final (or no-op if writeTmp already wrote final).
  Future<void> promoteTmp(int id);

  /// Delete the attachment file/blob for [id].
  /// Silently ignores missing attachments.
  Future<void> deleteAttachment(int id);

  /// Prepare an attachment for update by making it writable.
  /// On native: restores write permission. On web: no-op.
  Future<void> prepareForUpdate(int id);

  /// Finalize an attachment after write by making it read-only.
  /// On native: sets read-only flag. On web: no-op.
  Future<void> finalizeWrite(int id);

  /// Delete stale temporary files and orphan attachment data.
  ///
  /// [knownIds] is the set of attachment IDs that have corresponding DB rows.
  /// Any stored attachment not in this set is an orphan and should be deleted.
  Future<void> recover(Set<int> knownIds);

  /// Returns the file path for the attachment [id], if applicable.
  /// Returns null on platforms that don't use file-based storage (web).
  Future<String?> getAttachmentPath(int id);
}
