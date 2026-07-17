/// Platform-adaptive HTTP client factory.
///
/// On web, creates a BrowserClient with withCredentials enabled so the
/// browser automatically manages cookies (including CouchDB AuthSession).
/// On native, creates a standard http.Client().
library;

export 'http_client_factory_native.dart'
    if (dart.library.js_interop) 'http_client_factory_web.dart';
