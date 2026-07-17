import 'dart:convert';
import 'dart:typed_data';

import 'value_notifier.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'dart_couch_connection_state.dart';
import 'messages/couch_db_status_codes.dart';
import 'api_result.dart';
import 'platform/http_client_factory.dart';

final Logger _log = Logger("dart_couch-HttpMethods");

mixin HttpMethods {
  String? get authCookie;
  Uri? get uri;
  String? get username;
  String? get password;
  DcValueNotifier<DartCouchConnectionState> get connectionState;

  // Single persistent client — reuses TCP connections and TLS sessions across
  // all requests. Closed and replaced on logout/dispose via _renewHttpClient().
  http.Client _httpClient = createHttpClient();

  /// The underlying HTTP client. On web, this is a BrowserClient with
  /// withCredentials enabled so the browser manages cookies automatically.
  http.Client get httpClient => _httpClient;

  /// Closes the current client (aborting any in-flight requests) and creates
  /// a fresh one ready for the next login. Call this from dispose() / logout().
  void renewHttpClient() {
    _httpClient.close();
    _httpClient = createHttpClient();
  }

  // Generic guard to centralize network exception handling and state flipping
  Future<T> withNetworkGuard<T>(Future<T> Function() op) async {
    try {
      final res = await op();
      if (connectionState.value != DartCouchConnectionState.connected) {
        _log.fine(
          'Connection state changed: ${connectionState.value} -> connected',
        );
        connectionState.value = DartCouchConnectionState.connected;
      }
      return res;
    } on http.ClientException catch (e) {
      _log.info('Network error: $e');
      if (connectionState.value == .connected) {
        _log.fine(
          'Connection state changed: connected -> connectedButNetworkError',
        );
        // TODO: Why not also inform health monitoring about a problem?
        // e.g. by using the networkDegraded Callback here?
        connectionState.value = .connectedButNetworkError;
      }
      throw NetworkFailure(e.message, cause: e);
    } on StateError catch (e) {
      // Connection closed during operation - this is expected during offline transitions
      _log.fine(
        'Operation interrupted due to connection closure: ${e.message}',
      );
      throw NetworkFailure('Connection closed', cause: e);
    } catch (e, st) {
      _log.warning('HTTP operation error: $e\n$st');
      rethrow;
    }
  }

  // Non-throwing guard: converts exceptions to domain failures and returns ApiResult
  // ignore: unused_element
  Future<ApiResult<T>> _guardResult<T>(Future<T> Function() op) async {
    try {
      final v = await withNetworkGuard(op);
      return Ok<T>(v);
    } on CouchDbException catch (e, st) {
      return Err<T>(HttpFailure(e.statusCode, e.message, stackTrace: st));
    } on http.ClientException catch (e, st) {
      return Err<T>(NetworkFailure('Network error', cause: e, stackTrace: st));
    } on DartCouchFailure catch (e) {
      // If any code already throws domain failures, pass through
      return Err<T>(e);
    } catch (e, st) {
      return Err<T>(UnknownFailure(e, stackTrace: st));
    }
  }

  // Centralized URI builder for consistent path/query handling
  Uri _buildUri(String path, {Map<String, dynamic>? queryParameters}) {
    if (uri == null) {
      throw StateError('Cannot build URI: connection has been closed');
    }
    return Uri(
      host: uri!.host,
      port: uri!.port,
      scheme: uri!.scheme,
      path: "${uri!.path}/$path",
      queryParameters: queryParameters,
    );
  }

  Future<http.Response> httpGet(
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    return withNetworkGuard(
      () async => http.Response.fromStream(
        (await _httpGet(
          path,
          headers: headers,
          queryParameters: queryParameters,
        )),
      ),
    );
  }

  Future<http.StreamedResponse> httpGetStream(
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) {
    return withNetworkGuard(
      () => _httpGet(path, headers: headers, queryParameters: queryParameters),
    );
  }

  Future<http.StreamedResponse> _httpGet(
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    http.Request request = http.Request(
      'GET',
      _buildUri(path, queryParameters: queryParameters),
    );
    if (headers != null) request.headers.addAll(headers);
    _addAuthHeader(request.headers);
    http.StreamedResponse response = await _httpClient.send(request);

    if (response.statusCode == CouchDbStatusCodes.ok.code ||
        response.statusCode == CouchDbStatusCodes.notFound.code) {
      return response;
    } else {
      final body = (await http.Response.fromStream(response)).body;
      throw CouchDbException(
        CouchDbStatusCodes.fromCode(response.statusCode),
        body,
      );
    }
  }

  Future<http.StreamedResponse> httpHead(
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) {
    return withNetworkGuard(
      () => _httpHead(path, headers: headers, queryParameters: queryParameters),
    );
  }

  Future<http.StreamedResponse> _httpHead(
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    http.Request request = http.Request(
      'HEAD',
      _buildUri(path, queryParameters: queryParameters),
    );
    if (headers != null) request.headers.addAll(headers);
    _addAuthHeader(request.headers);
    http.StreamedResponse response = await _httpClient.send(request);

    if (response.statusCode == CouchDbStatusCodes.ok.code ||
        response.statusCode == CouchDbStatusCodes.notFound.code) {
      return response;
    } else {
      final body = (await http.Response.fromStream(response)).body;
      throw CouchDbException(
        CouchDbStatusCodes.fromCode(response.statusCode),
        body,
      );
    }
  }

  Future<http.Response> httpPut(
    String path, {
    Object? body,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) {
    return withNetworkGuard(
      () => _httpPut(
        path,
        body: body,
        headers: headers,
        queryParameters: queryParameters,
      ),
    );
  }

  /// [body] sets the body of the request. It can be a String, a List&lt;int&gt; or a Map&lt;String, String&gt;.
  ///
  /// If it's a String, it's encoded using [encoding] and used as the body of the request.
  /// The content-type of the request will default to "text/plain".
  ///
  /// If [body] is a List, it's used as a list of bytes for the body of the request.
  ///
  /// If [body] is a Map, it's encoded as form fields using [encoding]. The content-type of
  /// the request will be set to "application/x-www-form-urlencoded"; this cannot be overridden.
  Future<http.Response> _httpPut(
    String path, {
    Object? body,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    headers = _completeHeaders(headers, body);
    final uri = _buildUri(path, queryParameters: queryParameters);
    final request = http.Request('PUT', uri);
    request.headers.addAll(headers ?? {});
    if (body is String) request.body = body;
    if (body is List<int>) request.bodyBytes = Uint8List.fromList(body);

    final sw = Stopwatch()..start();
    _log.fine(
      'PUT $uri: sending request (${body is String
          ? body.length
          : body is List<int>
          ? body.length
          : 0} bytes)',
    );
    final streamedResponse = await _httpClient.send(request);
    _log.fine(
      'PUT $uri: response headers received in ${sw.elapsedMilliseconds}ms (status ${streamedResponse.statusCode})',
    );
    final response = await http.Response.fromStream(streamedResponse);
    _log.fine(
      'PUT $uri: response body read in ${sw.elapsedMilliseconds}ms total',
    );

    if (response.statusCode != CouchDbStatusCodes.created.code) {
      _log.info('PUT request failed: ${response.body}');
    }
    return response;
  }

  /// POST that returns the raw [StreamedResponse] for caller-controlled streaming.
  /// Unlike [httpPost]/[httpPostStreaming], does NOT buffer the response body.
  /// Error checking is the caller's responsibility.
  Future<http.StreamedResponse> httpPostStream(
    String path, {
    String? body,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) {
    return withNetworkGuard(
      () => _httpPostStream(
        path,
        body: body,
        headers: headers,
        queryParameters: queryParameters,
      ),
    );
  }

  Future<http.StreamedResponse> _httpPostStream(
    String path, {
    String? body,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    final completedHeaders = _completeHeaders(headers, body);
    final request = http.Request(
      'POST',
      _buildUri(path, queryParameters: queryParameters),
    );
    request.headers.addAll(completedHeaders ?? {});
    if (body != null) request.body = body;
    return _httpClient.send(request);
  }

  Future<http.Response> httpPost(
    String path, {
    String? body,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) {
    return withNetworkGuard(
      () => _httpPost(
        path,
        body: body,
        headers: headers,
        queryParameters: queryParameters,
      ),
    );
  }

  Future<http.Response> _httpPost(
    String path, {
    String? body,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    headers = _completeHeaders(headers, body);

    http.Response response = await _httpClient.post(
      _buildUri(path, queryParameters: queryParameters),
      headers: headers,
      body: body,
    );
    if (response.statusCode == CouchDbStatusCodes.ok.code ||
        response.statusCode == CouchDbStatusCodes.created.code ||
        response.statusCode == CouchDbStatusCodes.accepted.code) {
      return response;
    } else {
      _log.info('POST request failed: ${response.body}');
      return response;
    }
  }

  /// POST with streaming response body. Calls [onBytesReceived] with the
  /// running total of bytes received so far as data arrives. Useful for
  /// tracking download progress of large responses (e.g. bulk_get with
  /// inline base64 attachments) without waiting for the full buffer.
  Future<http.Response> httpPostStreaming(
    String path, {
    String? body,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    void Function(int totalBytesReceived)? onBytesReceived,
  }) {
    return withNetworkGuard(
      () => _httpPostStreaming(
        path,
        body: body,
        headers: headers,
        queryParameters: queryParameters,
        onBytesReceived: onBytesReceived,
      ),
    );
  }

  Future<http.Response> _httpPostStreaming(
    String path, {
    String? body,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    void Function(int totalBytesReceived)? onBytesReceived,
  }) async {
    final completedHeaders = _completeHeaders(headers, body);
    final request = http.Request(
      'POST',
      _buildUri(path, queryParameters: queryParameters),
    );
    request.headers.addAll(completedHeaders ?? {});
    if (body != null) request.body = body;

    final streamedResponse = await request.send();

    int bytesReceived = 0;
    final chunks = <List<int>>[];
    var totalLength = 0;
    await for (final chunk in streamedResponse.stream) {
      chunks.add(chunk);
      totalLength += chunk.length;
      bytesReceived += chunk.length;
      onBytesReceived?.call(bytesReceived);
    }

    // Allocate one contiguous buffer — avoids the expand().toList() intermediate copy.
    final combined = Uint8List(totalLength);
    var offset = 0;
    for (final chunk in chunks) {
      combined.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    final responseBody = utf8.decode(combined, allowMalformed: true);
    return http.Response(
      responseBody,
      streamedResponse.statusCode,
      headers: streamedResponse.headers,
    );
  }

  Future<http.Response> httpDelete(
    String path, {
    String? body,
    Map<String, String>? headers,
    Map<String, dynamic /*String?|Iterable<String>*/>? queryParameters,
  }) {
    return withNetworkGuard(
      () => _httpDelete(
        path,
        body: body,
        headers: headers,
        queryParameters: queryParameters,
      ),
    );
  }

  Future<http.Response> _httpDelete(
    String path, {
    String? body,
    Map<String, String>? headers,
    Map<String, dynamic /*String?|Iterable<String>*/>? queryParameters,
  }) async {
    headers = _completeHeaders(headers, body);
    http.Response response = await _httpClient.delete(
      _buildUri(path, queryParameters: queryParameters),
      headers: headers,
      body: body,
    );
    if (response.statusCode == CouchDbStatusCodes.ok.code) {
      return response;
    } else {
      _log.info('DELETE request failed: ${response.body}');
      throw CouchDbException(
        CouchDbStatusCodes.fromCode(response.statusCode),
        response.body,
      );
    }
  }

  /// Injects authentication credentials into [headers].
  ///
  /// **Native platforms**: Uses the CouchDB `AuthSession` cookie obtained
  /// during login. The cookie is sent as a `Cookie` header with every request.
  ///
  /// **Web platform**: Uses HTTP Basic Auth (`Authorization: Basic <base64>`)
  /// instead of cookies. Although `BrowserClient(withCredentials: true)` tells
  /// the browser to send cookies cross-origin, CouchDB's `AuthSession` cookie
  /// is set with `SameSite=Strict` by default, which prevents the browser from
  /// attaching it to cross-origin requests. The `Set-Cookie` header is also a
  /// forbidden response header in the Fetch spec, so JavaScript cannot read it.
  /// Basic Auth works reliably cross-origin and is the same approach PouchDB
  /// uses for web-based CouchDB access.
  void _addAuthHeader(Map<String, String> headers) {
    if (kBrowserManagesCookies) {
      if (username != null && password != null) {
        headers['Authorization'] =
            'Basic ${base64Encode(utf8.encode('$username:$password'))}';
      }
    } else {
      if (authCookie != null) headers['Cookie'] = authCookie!;
    }
  }

  Map<String, String>? _completeHeaders(
    Map<String, String>? headers,
    Object? body,
  ) {
    headers = headers ?? {};
    _addAuthHeader(headers);
    headers['Accept'] ??= 'application/json';

    if (body != null && headers.keys.contains('Content-Type') == false) {
      headers['Content-Type'] = body is String
          ? "application/json"
          : body is List<int>
          ? 'application/octet-stream'
          : 'application/x-www-form-urlencoded';
    }
    return headers;
  }
}
