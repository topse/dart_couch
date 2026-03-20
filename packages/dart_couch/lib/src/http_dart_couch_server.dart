import 'dart:convert' as convert;
import 'dart:async';
import 'package:http/http.dart' as http;
import 'value_notifier.dart';
import 'package:logging/logging.dart';

import 'api_result.dart';
import 'dart_couch_connection_state.dart';
import 'dart_couch_server.dart';
import 'database_migration.dart';
import 'platform/http_client_factory.dart';
import 'dart_couch_db.dart';
import 'http_dart_couch_db.dart';
import 'http_methods.dart';
import 'messages/couch_db_status_codes.dart';
import 'messages/db_updates_result.dart';
import 'messages/login_result.dart';
import 'messages/session_result.dart';
import 'messages/user_result.dart';

final Logger _log = Logger("HttpDartCouchServer");

class HttpDartCouchServer extends DartCouchServer with HttpMethods {
  // CouchDB default session timeout is 600 s; we ping at half that by default.
  static const Duration _defaultKeepAliveInterval = Duration(seconds: 300);

  final Duration _sessionKeepAliveInterval;
  Timer? _keepAliveTimer;

  HttpDartCouchServer({this.migration, Duration? sessionKeepAliveInterval})
    : _sessionKeepAliveInterval =
          sessionKeepAliveInterval ?? _defaultKeepAliveInterval;

  /// last at login used URL of the CouchDB server or null after logout
  @override
  Uri? uri;

  /// Stored after successful login, cleared on logout/failure.
  /// On web, used by [HttpMethods._addAuthHeader] for Basic Auth on every
  /// request (see that method's doc comment for why cookies don't work).
  @override
  String? username;

  /// Stored after successful login, cleared on logout/failure.
  /// On web, used by [HttpMethods._addAuthHeader] for Basic Auth on every
  /// request (see that method's doc comment for why cookies don't work).
  @override
  String? password;

  /// On native: the `AuthSession=...` cookie from CouchDB's `/_session` response.
  /// On web: set to the sentinel value `'browser-managed'` after a successful
  /// login — actual auth uses Basic Auth via [HttpMethods._addAuthHeader], but
  /// this field being non-null signals to health monitoring that a session exists.
  @override
  String? authCookie;

  LoginResult? lastLoginResult;

  bool checkRevsAlgorithmForDebugging = false;

  final DatabaseMigration? migration;

  /// This is used to track the connection state to the CouchDB server.
  /// It also reflects the login state and if the server is currently reachable.
  /// It is not used for Health Monitoring, which is done separately.
  @override
  final DcValueNotifier<DartCouchConnectionState> connectionState =
      DcValueNotifier<DartCouchConnectionState>(
        DartCouchConnectionState.disconnected,
      );

  void _startKeepAliveTimer() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(_sessionKeepAliveInterval, (_) async {
      if (authCookie == null || uri == null) return;
      _log.fine('Session keep-alive: pinging /_session');
      try {
        await session();
        _log.fine('Session keep-alive: ok');
      } catch (e) {
        _log.fine('Session keep-alive ping failed: $e');
      }
    });
    _log.fine(
      'Session keep-alive timer started (interval: $_sessionKeepAliveInterval)',
    );
  }

  void _stopKeepAliveTimer() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  /// Suspend the session keep-alive timer while the app is in the background.
  ///
  /// The keep-alive timer pings `GET /_session` every [_sessionKeepAliveInterval]
  /// to prevent the CouchDB auth cookie from expiring silently. While the app
  /// is paused (Android Doze / screen-off), the pings will fail because the
  /// network is unavailable. Each failed ping goes through [withNetworkGuard]
  /// which sets `connectionState = connectedButNetworkError`. That stale state
  /// then interferes with the recovery path in `_startContinuousReplication`
  /// when the app wakes up. Suspending the timer during background avoids
  /// both the pointless network traffic and the spurious state transition.
  ///
  /// Call [resumeKeepAlive] when the app returns to the foreground.
  void suspendKeepAlive() {
    _log.fine('Suspending session keep-alive timer');
    _stopKeepAliveTimer();
  }

  /// Resume the session keep-alive timer after a [suspendKeepAlive] call.
  ///
  /// Only restarts the timer if the user is actually logged in (cookie + URI
  /// are present). If the session expired while the app was in the background,
  /// health monitoring will handle re-login and the timer will be restarted
  /// once the first successful `login` call is made.
  void resumeKeepAlive() {
    if (authCookie != null && uri != null) {
      _log.fine('Resuming session keep-alive timer');
      _startKeepAliveTimer();
    } else {
      _log.fine('resumeKeepAlive: not logged in, keep-alive not restarted');
    }
  }

  /// tries to login to the CouchDB server
  ///
  /// Automatically starts a session keep-alive timer (default every 300 s) that
  /// pings GET /_session to prevent the CouchDB cookie from expiring silently.
  /// The timer runs until [logout] (or [dispose]) is called.
  ///
  /// Current connection state can be read via [connectionState].
  ///
  /// returns null on network error
  Future<LoginResult?> login(
    String url,
    String username,
    String password,
  ) async {
    if (connectionState.value != .disconnected &&
        connectionState.value != .wrongCredentials &&
        connectionState.value != .loginFailedWithNetworkError) {
      throw Exception('Already logged in or logging in');
    }
    try {
      _log.fine('Attempting login to $url as $username');
      connectionState.value = .loggingIn;
      uri = Uri.parse(url);
      this.username = username;
      this.password = password;

      final response = await httpClient
          .post(
            Uri.parse('$url/_session'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: convert.jsonEncode({'name': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 &&
          (kBrowserManagesCookies ||
              response.headers.containsKey('set-cookie'))) {
        // On native, extract the AuthSession cookie from the response.
        // On web, Set-Cookie is a forbidden response header (Fetch spec) and
        // never appears in JavaScript. We set a sentinel value so that
        // health monitoring and other code that checks `authCookie != null`
        // knows a session exists. Actual web auth uses Basic Auth — see
        // HttpMethods._addAuthHeader.
        if (!kBrowserManagesCookies) {
          // "set-cookie" -> "AuthSession=YWRtaW46Njg4REMyRTE6K7SaSB_oQmeIpFq-G4NuAYoVLaxxEzNeSoNeehdTNLk; Version=1; Expires=Sat, 02-Aug-2025 07:58:49 GMT; M…"
          authCookie = response.headers['set-cookie']!
              .split(';')
              .firstWhere((element) => element.startsWith('AuthSession='));
        } else {
          authCookie = 'browser-managed';
        }
        _log.info(
          'Login as $username success. AuthCookie: ${authCookie != null ? "SET" : "NULL"}',
        );
        _log.fine('Connection state: ${connectionState.value}');

        final loginResult = LoginResult(
          statusCode: CouchDbStatusCodes.fromCode(response.statusCode),
          errorMsg: null,
          success: true,
          body: LoginResultBody.fromJson(response.body),
        );

        if (loginResult.body!.roles.contains('_admin')) {
          await _checkOrCreateGlobalChangesDatabase();
        }

        connectionState.value = DartCouchConnectionState.connected;
        lastLoginResult = loginResult;
        _startKeepAliveTimer();

        return lastLoginResult!;
      } else {
        _log.warning('Login failed for $username: ${response.body}');
        _log.fine('AuthCookie: NULL, Connection state: wrongCredentials');
        lastLoginResult = LoginResult(
          statusCode: CouchDbStatusCodes.fromCode(response.statusCode),
          errorMsg: 'Login failed',
          success: false,
          body: null,
        );
        connectionState.value = DartCouchConnectionState.wrongCredentials;
        this.username = null;
        this.password = null;
        return lastLoginResult!;
      }
    } on http.ClientException catch (e) {
      // Timeout may occur when trying to post the login request
      _log.warning('Login failed due to network error: $e');
      _log.fine(
        'AuthCookie: NULL, Connection state: loginFailedWithNetworkError',
      );
      connectionState.value =
          DartCouchConnectionState.loginFailedWithNetworkError;
      lastLoginResult = null;
      this.username = null;
      this.password = null;
      return null;
    } on TimeoutException catch (e) {
      // Timeout may occur when trying to post the login request
      _log.warning('Login failed due to timeout: $e');
      _log.fine(
        'AuthCookie: NULL, Connection state: loginFailedWithNetworkError',
      );
      connectionState.value =
          DartCouchConnectionState.loginFailedWithNetworkError;
      lastLoginResult = null;
      this.username = null;
      this.password = null;
      return null;
    } catch (e) {
      _log.severe(e);
      lastLoginResult = null;
      connectionState.value = DartCouchConnectionState.disconnected;
      this.username = null;
      this.password = null;
      rethrow;
    }
  }

  Future<void> logout() async {
    _stopKeepAliveTimer();
    // Dispose all databases first (cancels changes streams, closes controllers)
    for (final db in databases.values) {
      db.dispose();
    }
    databases.clear();
    // Best-effort server-side session deletion
    if (uri != null) {
      try {
        await httpDelete('_session');
      } on NetworkFailure {
        // ignore — server session will expire on its own
      }
    }
    authCookie = null;
    lastLoginResult = null;
    uri = null;
    connectionState.value = DartCouchConnectionState.disconnected;
    _log.info('Logged out. AuthCookie: NULL, Connection state: disconnected');
    renewHttpClient();
  }

  Future<void> _checkOrCreateGlobalChangesDatabase() async {
    List<String> dbs = await allDatabasesNames;
    if (dbs.contains('_global_changes') == false) {
      _log.warning('Global changes database not found. Creating it...');
      await createDatabase('_global_changes');
    }
  }

  @override
  Future<List<DartCouchDb>> get allDatabases async {
    final response = await httpGet("_all_dbs");

    if (response.statusCode == 200) {
      List<dynamic> l = convert.json.decode(response.body);
      List<String> objects = l.map((e) => e.toString()).toList();
      objects.sort();

      final dbs = objects
          .map((e) => HttpDartCouchDb(parentServer: this, uri: uri!, dbname: e))
          .toList();

      for (final db in dbs) {
        if (databases.containsKey(db.dbname) == false) {
          databases[db.dbname] = db;
        }
      }
      return dbs;
    } else {
      _log.info('_all_dbs request failed: ${response.body}');
      throw Exception('_all_dbs request failed: ${response.body}');
    }
  }

  @override
  Future<List<String>> get allDatabasesNames async {
    final response = await httpGet("_all_dbs");

    if (response.statusCode == 200) {
      List<dynamic> l = convert.json.decode(response.body);
      List<String> objects = l.map((e) => e.toString()).toList();
      objects.sort();
      return objects;
    } else {
      _log.info('Session request failed: ${response.body}');
      throw Exception('Session request failed: ${response.body}');
    }
  }

  @override
  Future<DartCouchDb> createDatabase(String name) async {
    _log.info('Request to create remote database: $name');
    final String putPath = name;
    final response = await httpPut(putPath);

    if (response.statusCode != 201) {
      throw CouchDbException(
        .preconditionFailed,
        'Failed to create object $putPath: ${response.body}',
      );
    }

    final newDb = (await db(name))!;
    if (databases.containsKey(newDb.dbname) == false) {
      databases[newDb.dbname] = newDb;
    }
    _log.info('Create Remote Database successful: $name');
    return newDb;
  }

  @override
  Future<void> deleteDatabase(String name) async {
    _log.info('Request to delete remote database: $name');
    final response = await httpDelete(name);

    if (response.statusCode != CouchDbStatusCodes.ok.code) {
      throw Exception('Failed to delete object $name: ${response.body}');
    }

    databases.remove(name);
    _log.info('Remote database deleted: $name');
  }

  Future<SessionResult> session() async {
    final response = await httpGet("_session");

    final String body = response.body;
    if (response.statusCode == 200) {
      // Capture a refreshed session cookie if CouchDB returned one.
      final setCookie = response.headers['set-cookie'];
      if (setCookie != null) {
        final refreshed = setCookie
            .split(';')
            .firstWhere(
              (s) => s.trim().startsWith('AuthSession='),
              orElse: () => '',
            );
        if (refreshed.isNotEmpty) {
          authCookie = refreshed.trim();
          _log.fine('Session cookie refreshed');
        }
      }
      try {
        return SessionResult.fromJson(body);
      } catch (e) {
        _log.severe(e);
        _log.severe(body);
        rethrow;
      }
    } else {
      _log.info('Session request failed: $body');
      throw CouchDbException(
        CouchDbStatusCodes.fromCode(response.statusCode),
        response.body,
      );
    }
  }

  // Simple check without authentication
  Future<bool> isCouchDbUp() async {
    if (uri == null) return false;

    try {
      // Use a simple HTTP client without authentication to check if server is up
      final response = await http.get(uri!).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200 && response.statusCode != 401) {
        return false;
      }
      // Verify the body looks like a CouchDB response, not a proxy error page.
      // 200: {"couchdb":"Welcome",...}  401: {"error":"unauthorized",...}
      final body = convert.jsonDecode(response.body);
      if (body is! Map) return false;
      if (response.statusCode == 200) return body['couchdb'] == 'Welcome';
      return body.containsKey('error'); // CouchDB 401 always has "error" key
    } catch (e) {
      _log.fine('isCouchDbUp() failed: ${e.runtimeType}: $e');
      return false;
    }
  }

  /// Stream of database creation/deletion events from the server.
  /// Returns a stream that emits events when databases are created or deleted.
  ///
  /// [since] - Optional sequence number to start from (for resuming after disconnect)
  /// [heartbeat] - Milliseconds between heartbeat signals (default 30000)
  Stream<Map<String, dynamic>> dbUpdatesStream({
    String? since,
    int heartbeat = 30000,
  }) {
    StreamSubscription<String>? responseSubscription;
    late final StreamController<Map<String, dynamic>> controller;

    Future<void> startListening() async {
      if (uri == null) {
        controller.addError(Exception('Not logged in'));
        await controller.close();
        return;
      }

      final queryParams = <String, dynamic>{
        'feed': 'continuous',
        'heartbeat': heartbeat.toString(),
      };
      if (since != null) {
        queryParams['since'] = since;
      }

      http.StreamedResponse response;
      try {
        response = await httpGetStream(
          '_db_updates',
          queryParameters: queryParams,
        );
      } on NetworkFailure catch (e) {
        _log.info('_db_updates stream network failure: $e');
        controller.addError(e);
        await controller.close();
        return;
      } catch (e, st) {
        _log.warning('_db_updates stream connection failed: $e');
        controller.addError(e, st);
        await controller.close();
        return;
      }

      if (response.statusCode != 200) {
        _log.warning('_db_updates returned status ${response.statusCode}');
        await controller.close();
        return;
      }

      responseSubscription = response.stream
          .transform(convert.utf8.decoder)
          .transform(const convert.LineSplitter())
          .listen(
            (line) {
              final trimmed = line.trim();
              if (trimmed.isEmpty || controller.isClosed) {
                return;
              }
              try {
                final json = convert.jsonDecode(trimmed);
                controller.add(json as Map<String, dynamic>);
              } catch (_) {
                // Skip invalid JSON (e.g., heartbeat signals)
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!controller.isClosed) {
                controller.addError(error, stackTrace);
              }
              unawaited(controller.close());
            },
            onDone: () {
              if (!controller.isClosed) {
                unawaited(controller.close());
              }
            },
            cancelOnError: false,
          );
    }

    controller = StreamController<Map<String, dynamic>>(
      onListen: () {
        unawaited(startListening());
      },
      onPause: () => responseSubscription?.pause(),
      onResume: () => responseSubscription?.resume(),
      onCancel: () async {
        await responseSubscription?.cancel();
        responseSubscription = null;
      },
    );

    return controller.stream;
  }

  Future<DbUpdatesResult> dbUpdates({
    String? since,
    int heartbeat = 30000,
  }) async {
    final queryParams = <String, dynamic>{
      'feed': 'normal',
      'heartbeat': heartbeat.toString(),
    };
    if (since != null) {
      queryParams['since'] = since;
    }

    final response = await httpGetStream(
      '_db_updates',
      queryParameters: queryParams,
    );

    if (response.statusCode != 200) {
      throw CouchDbException.fromResponse(
        (await http.Response.fromStream(response)),
      );
    }

    String json = await convert.utf8.decoder.bind(response.stream).join();

    return DbUpdatesResult.fromJson(json);
  }

  Future<bool> dbExists(String name) async {
    final response = await httpHead(name);

    if (response.statusCode == CouchDbStatusCodes.ok.code) {
      return true;
    } else if (response.statusCode == CouchDbStatusCodes.notFound.code) {
      return false;
    } else {
      final String body = (await http.Response.fromStream(response)).body;
      _log.info('db error in dbExists($name) request failed: $body');
      throw Exception('db error in dbExists($name) request failed: $body');
    }
  }

  /// this is needed to have only one db object per CouchdB-Database
  Map<String, HttpDartCouchDb> databases = {};

  @override
  Future<void> dispose() async {
    return logout();
  }

  @override
  Future<HttpDartCouchDb?> db(String name) async {
    // Check if Database exists
    if (await dbExists(name) == false) {
      databases.remove(name);
      return null;
    }

    HttpDartCouchDb? existingDb = databases[name];
    final wasInCache = existingDb != null;

    if (existingDb == null) {
      existingDb = HttpDartCouchDb(parentServer: this, uri: uri!, dbname: name);
      existingDb.checkRevsAlgorithmForDebugging =
          checkRevsAlgorithmForDebugging;
      databases[name] = existingDb;
    }

    // Execute migration on first access (idempotent - safe to call multiple times)
    if (!wasInCache && migration != null) {
      await migration!.migrate(existingDb);
    }

    return existingDb;
  }

  // ===== User Management Methods =====

  /// Creates a new user in the _users database.
  ///
  /// [username] - The username for the new user
  /// [password] - The password for the new user
  /// [roles] - Optional list of roles to assign (defaults to empty list)
  ///
  /// Returns the created UserResult on success.
  /// Throws an exception if the user already exists or creation fails.
  Future<UserResult> createUser(
    String username,
    String password, {
    List<String> roles = const [],
  }) async {
    final userId = 'org.couchdb.user:$username';

    final userDoc = {
      '_id': userId,
      'name': username,
      'password': password,
      'type': 'user',
      'roles': roles,
    };

    final response = await httpPut(
      '_users/$userId',
      body: convert.jsonEncode(userDoc),
    );

    if (response.statusCode != 201) {
      throw CouchDbException(
        CouchDbStatusCodes.fromCode(response.statusCode),
        response.body,
      );
    }

    // Fetch the created user to return complete data
    return (await getUser(username))!;
  }

  /// Retrieves a user from the _users database.
  ///
  /// [username] - The username to retrieve
  ///
  /// Returns the UserResult if found.
  /// Throws an exception if the user doesn't exist.
  Future<UserResult?> getUser(String username) async {
    final userId = 'org.couchdb.user:$username';
    final response = await httpGet('_users/$userId');

    if (response.statusCode == 200) {
      return UserResult.fromJson(response.body);
    } else if (response.statusCode == 404) {
      return null;
    } else {
      throw CouchDbException(
        CouchDbStatusCodes.fromCode(response.statusCode),
        response.body,
      );
    }
  }

  /// Deletes a user from the _users database.
  ///
  /// [username] - The username to delete
  ///
  /// Throws an exception if the user doesn't exist or deletion fails.
  Future<void> deleteUser(String username) async {
    // First get the user to obtain the current revision
    final user = await getUser(username);
    final userId = 'org.couchdb.user:$username';

    if (user != null) {
      final response = await httpDelete(
        '_users/$userId',
        queryParameters: {'rev': user.rev},
      );

      if (response.statusCode != CouchDbStatusCodes.ok.code) {
        throw CouchDbException(
          CouchDbStatusCodes.fromCode(response.statusCode),
          response.body,
        );
      }
    }
  }

  /// Lists all users in the _users database.
  ///
  /// Returns a list of UserResult objects for all users.
  /// Note: This returns all user documents, which may be large for servers with many users.
  Future<List<UserResult>> listUsers() async {
    final response = await httpGet(
      '_users/_all_docs',
      queryParameters: {'include_docs': 'true'},
    );

    if (response.statusCode == 200) {
      final json = convert.jsonDecode(response.body) as Map<String, dynamic>;
      final rows = json['rows'] as List<dynamic>;

      final users = <UserResult>[];
      for (final row in rows) {
        final doc = row['doc'] as Map<String, dynamic>?;
        if (doc != null && doc['type'] == 'user') {
          users.add(UserResult.fromMap(doc));
        }
      }

      return users;
    } else {
      throw Exception('Failed to list users: ${response.body}');
    }
  }
}
