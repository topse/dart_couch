import 'dart:io';

import 'package:drift/drift.dart';

import 'attachment_storage.dart';
import 'attachment_storage_native.dart';

/// Creates a native file-based [AttachmentStorage].
AttachmentStorage createAttachmentStorage(
  Directory directory,
  GeneratedDatabase db,
) {
  return NativeAttachmentStorage(directory);
}
