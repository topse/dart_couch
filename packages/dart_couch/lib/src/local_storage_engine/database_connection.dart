/// Platform-adaptive database connection factory.
///
/// On native platforms, uses NativeDatabase (SQLite via FFI).
/// On web, uses Drift's WasmDatabase or WebDatabase with IndexedDB storage.
library;

export 'database_connection_native.dart'
    if (dart.library.js_interop) 'database_connection_web.dart';
