import 'package:http/http.dart' as http;

/// On native platforms, the browser does not manage cookies. Manual cookie
/// injection is required.
const bool kBrowserManagesCookies = false;

http.Client createHttpClient() => http.Client();
