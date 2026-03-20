/// Platform-adaptive factory for creating [AttachmentStorage] instances.
library;

export 'attachment_storage_factory_native.dart'
    if (dart.library.js_interop) 'attachment_storage_factory_web.dart';
