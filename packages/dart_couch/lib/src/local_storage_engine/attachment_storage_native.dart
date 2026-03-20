import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'attachment_storage.dart';

final Logger _log = Logger('dart_couch-attachment_storage_native');

/// File-based attachment storage for native platforms (Linux, Windows, Android).
///
/// Attachments are stored as individual files in `{rootDir}/att/{id}`, where
/// `id` is the integer primary key of the `local_attachments` row.
///
/// This implementation preserves the exact same behavior as the original
/// inline code in LocalDartCouchDb and LocalDartCouchServer:
/// - READ: File.readAsBytes / File.openRead
/// - WRITE: File.writeAsBytes with flush
/// - UPDATE: .tmp file → DB update → atomic rename
/// - PERMISSIONS: chmod/attrib for read-only protection
/// - RECOVERY: delete stale .tmp files and orphan attachment files
class NativeAttachmentStorage implements AttachmentStorage {
  final Directory _attDir;

  NativeAttachmentStorage(Directory rootDir)
      : _attDir = Directory('${rootDir.path}/att');

  File _file(int id) => File('${_attDir.path}/$id');
  File _tmpFile(int id) => File('${_attDir.path}/$id.tmp');

  @override
  Future<void> initialize() async {
    // No-op on native — directories are created in the constructor.
  }

  @override
  Future<Uint8List?> readAttachment(int id) async {
    final f = _file(id);
    if (!await f.exists()) return null;
    return await f.readAsBytes();
  }

  @override
  Stream<List<int>> readAttachmentAsStream(int id) {
    return _file(id).openRead();
  }

  @override
  Future<void> writeAttachment(int id, Uint8List data) async {
    await _file(id).writeAsBytes(data, flush: true);
  }

  @override
  Future<void> writeAttachmentFromStream(
    int id,
    Stream<List<int>> stream,
  ) async {
    final sink = _file(id).openWrite();
    await sink.addStream(stream);
    await sink.flush();
    await sink.close();
  }

  @override
  Future<void> writeTmpAttachment(int id, Uint8List data) async {
    await _tmpFile(id).writeAsBytes(data, flush: true);
  }

  @override
  Future<void> writeTmpAttachmentFromStream(
    int id,
    Stream<List<int>> stream,
  ) async {
    final sink = _tmpFile(id).openWrite();
    await sink.addStream(stream);
    await sink.flush();
    await sink.close();
  }

  @override
  Future<void> promoteTmp(int id) async {
    await _tmpFile(id).rename(_file(id).path);
  }

  @override
  Future<void> deleteAttachment(int id) async {
    // Remove readonly flag first so deletion works on all platforms.
    await _setWritable(_file(id));
    try {
      await _file(id).delete();
    } catch (_) {
      _log.fine('Could not delete attachment file $id');
    }
    try {
      await _tmpFile(id).delete();
    } catch (_) {}
  }

  @override
  Future<void> prepareForUpdate(int id) async {
    await _setWritable(_file(id));
  }

  @override
  Future<void> finalizeWrite(int id) async {
    await _setReadonly(_file(id));
  }

  @override
  Future<void> recover(Set<int> knownIds) async {
    if (!_attDir.existsSync()) return;

    // Phase 1: delete all stale *.tmp files.
    final tmpFiles = _attDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.tmp'))
        .toList();
    for (final tmp in tmpFiles) {
      _log.fine('Recovery: deleting stale .tmp file ${tmp.path}');
      await tmp.delete();
    }

    // Phase 2: orphan files (file exists, no DB row).
    final allFiles = _attDir.listSync().whereType<File>();
    for (final file in allFiles) {
      final name = file.uri.pathSegments.last;
      final id = int.tryParse(name);
      if (id != null && !knownIds.contains(id)) {
        _log.warning(
          'Recovery: deleting orphan attachment file $name (no DB row found)',
        );
        await file.delete();
      }
    }
  }

  @override
  Future<String?> getAttachmentPath(int id) async {
    final f = _file(id);
    if (!await f.exists()) return null;
    return f.path;
  }

  /// Marks [f] as read-only for all users.
  Future<void> _setReadonly(File f) async {
    if (Platform.isWindows) {
      await Process.run('attrib', ['+R', f.path]);
    } else {
      await Process.run('chmod', ['a-w', f.path]);
    }
  }

  /// Restores owner-write permission on [f].
  Future<void> _setWritable(File f) async {
    if (!f.existsSync()) return;
    if (Platform.isWindows) {
      await Process.run('attrib', ['-R', f.path]);
    } else {
      await Process.run('chmod', ['u+w', f.path]);
    }
  }
}
