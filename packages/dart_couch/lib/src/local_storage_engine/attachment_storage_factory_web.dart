import 'package:drift/drift.dart';

import 'attachment_storage.dart';
import 'attachment_storage_web.dart';

/// Creates a web-based [AttachmentStorage] backed by a Drift table.
AttachmentStorage createAttachmentStorage(
  dynamic directory,
  GeneratedDatabase db,
) {
  return WebAttachmentStorage(db);
}
