/// Platform-agnostic re-exports of dart:io types used by dart_couch.
///
/// On native platforms (Linux, Windows, Android) this re-exports the real
/// dart:io classes. On web, lightweight stubs are provided so that the same
/// application code compiles on all platforms.
library;

export 'io_shim_native.dart'
    if (dart.library.js_interop) 'io_shim_web.dart';
