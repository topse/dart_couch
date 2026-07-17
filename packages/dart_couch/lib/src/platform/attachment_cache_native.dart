import 'io_shim.dart';

const String _lockFileName = '.lock';
const String _folderPrefix = 'dart_couch-';
const String _folderSuffix = '_tmp';

/// Cache dirs this process currently holds an open advisory lock on, keyed
/// by directory path. Consulted by [sweepOrphanedAttachmentCacheDirs] so it
/// never tries to lock (and thus never mistakes as orphaned) a folder this
/// same process already owns — POSIX advisory locks don't conflict with a
/// second lock from the *same* process, so without this guard a sweep could
/// "successfully" lock and delete a folder that's actually still in active
/// use by this process.
final Map<String, RandomAccessFile> _heldLocks = {};

/// Prepares the on-disk cache directory named [folderName] under the OS temp
/// directory: deletes any stale contents left over from a prior run that
/// never reached a clean [deleteAttachmentCacheDir] call, then recreates it
/// empty. Opens and locks a `.lock` file inside it, held for as long as this
/// process keeps the directory registered (see [_heldLocks]) — released only
/// by [deleteAttachmentCacheDir], or automatically by the OS if this process
/// dies without a clean shutdown. Returns the directory's absolute path.
///
/// This cache is purely disposable (the remote database is always the
/// source of truth), so starting from a known-empty directory on every first
/// use — rather than trying to validate and resurrect leftover files — is
/// the simplest failsafe option: worst case is a redundant re-download,
/// never stale or inconsistent data.
///
/// Relies on `dart:io`'s `Directory.systemTemp` resolution. On Android this
/// requires the Flutter engine (which sets `TMPDIR`) — the expected
/// deployment context for this package, which has no Flutter dependency of
/// its own but is normally used via the companion `dart_couch_widgets`
/// package.
Future<String?> prepareAttachmentCacheDir(String folderName) async {
  final dir = Directory('${Directory.systemTemp.path}/$folderName');
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
  await dir.create(recursive: true);
  await _acquireLock(dir.path);
  return dir.path;
}

Future<void> _acquireLock(String dirPath) async {
  final raf = await File('$dirPath/$_lockFileName').open(mode: FileMode.write);
  await raf.lock(FileLock.exclusive);
  _heldLocks[dirPath] = raf;
}

/// Best-effort recursive delete of a cache directory previously returned by
/// [prepareAttachmentCacheDir]. Releases this process's own lock on it first
/// (deleting a still-open-and-locked file can fail on Windows), then removes
/// the directory. Silently ignores a missing directory.
Future<void> deleteAttachmentCacheDir(String dirPath) async {
  await _releaseLock(dirPath);
  final dir = Directory(dirPath);
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
}

Future<void> _releaseLock(String dirPath) async {
  final raf = _heldLocks.remove(dirPath);
  if (raf == null) return;
  try {
    await raf.unlock();
  } catch (_) {
    // Best-effort — closing below still releases it at the OS level.
  }
  await raf.close();
}

/// Best-effort startup housekeeping: deletes every `dart_couch-*_tmp` cache
/// directory under the OS temp dir that nothing currently holds a lock on —
/// i.e. leftovers from a process that terminated without a clean
/// [deleteAttachmentCacheDir] (crash, force-kill, OS-initiated app kill).
///
/// Safety: a directory is only ever deleted after this function itself
/// successfully acquires its `.lock` file, which only succeeds if no other
/// live process (including this one, via [_heldLocks]) currently holds it.
/// A directory whose owning process is still alive is left untouched. Any
/// unexpected error for an individual directory (permissions, an
/// unsupported locking primitive on some platform/filesystem, ...) is
/// swallowed and just leaves that directory alone — this is pure disk
/// hygiene, never load-bearing for correctness.
Future<void> sweepOrphanedAttachmentCacheDirs() async {
  final root = Directory.systemTemp;
  if (!await root.exists()) return;
  await for (final entry in root.list()) {
    if (entry is! Directory) continue;
    final name = entry.uri.pathSegments.lastWhere(
      (s) => s.isNotEmpty,
      orElse: () => '',
    );
    if (!name.startsWith(_folderPrefix) || !name.endsWith(_folderSuffix)) {
      continue;
    }
    await _deleteIfUnlocked(entry.path);
  }
}

Future<void> _deleteIfUnlocked(String dirPath) async {
  if (_heldLocks.containsKey(dirPath)) return;
  RandomAccessFile? raf;
  try {
    raf = await File('$dirPath/$_lockFileName').open(mode: FileMode.write);
    await raf.lock(FileLock.exclusive); // throws if a live process holds it
    await raf.unlock();
    await raf.close();
    raf = null;
    await Directory(dirPath).delete(recursive: true);
  } catch (_) {
    // Held by a live process, or a transient filesystem error — leave it.
  } finally {
    try {
      await raf?.close();
    } catch (_) {}
  }
}

/// Returns whether the cache file at [path] still exists on disk.
Future<bool> attachmentCacheFileExists(String path) => File(path).exists();

/// Writes [bytes] into a new cache file named `$id$ext` inside [dirPath],
/// via write-to-temp-name-then-rename so a crash mid-write never leaves a
/// partially-written file at the final path. Returns the final path.
Future<String> writeAttachmentCacheFile(
  String dirPath,
  String id,
  String ext,
  List<int> bytes,
) async {
  final tmp = File('$dirPath/$id.tmp');
  await tmp.writeAsBytes(bytes, flush: true);
  final finalPath = '$dirPath/$id$ext';
  await tmp.rename(finalPath);
  return finalPath;
}
