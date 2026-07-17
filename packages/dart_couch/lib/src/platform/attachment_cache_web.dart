/// Web stub: there is no filesystem, so [HttpDartCouchDb.getAttachmentAsReadonlyFile]
/// always returns null on web without calling any of the write helpers below.
library;

Future<String?> prepareAttachmentCacheDir(String folderName) async => null;

Future<void> deleteAttachmentCacheDir(String dirPath) async {}

Future<bool> attachmentCacheFileExists(String path) async => false;

Future<void> sweepOrphanedAttachmentCacheDirs() async {}

Future<String> writeAttachmentCacheFile(
  String dirPath,
  String id,
  String ext,
  List<int> bytes,
) async =>
    throw UnsupportedError('writeAttachmentCacheFile is not supported on web');
