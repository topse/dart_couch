import 'package:http/http.dart' as http;
import 'package:http/browser_client.dart';

/// On web, the browser manages cookies automatically. Manual cookie
/// injection must be skipped (Set-Cookie is a forbidden response header).
const bool kBrowserManagesCookies = true;

http.Client createHttpClient() =>
    BrowserClient()..withCredentials = true;
