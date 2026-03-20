/// Platform-adaptive gzip decompression.
library;

export 'gzip_decode_native.dart'
    if (dart.library.js_interop) 'gzip_decode_web.dart';
