/// Platform-adaptive backend for [HttpDartCouchDb]'s on-disk read-only
/// attachment cache (see `getAttachmentAsReadonlyFile`).
library;

export 'attachment_cache_native.dart'
    if (dart.library.js_interop) 'attachment_cache_web.dart';
