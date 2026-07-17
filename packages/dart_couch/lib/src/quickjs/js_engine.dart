/// Platform-adaptive JavaScript engine.
///
/// On native platforms (Linux, Windows, Android), uses QuickJS via FFI.
/// On web, uses the browser's native JavaScript engine via dart:js_interop.
library;

export 'js_eval_result.dart';
export 'js_engine_native.dart'
    if (dart.library.js_interop) 'js_engine_web.dart';
