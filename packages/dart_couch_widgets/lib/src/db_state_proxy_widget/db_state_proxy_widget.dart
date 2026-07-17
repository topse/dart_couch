import 'dart:async';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'package:flutter/material.dart';
import 'package:dart_couch/dart_couch.dart';
import '../value_listenable_builder.dart';
import 'server_login_dialog.dart';
import 'network_retry_dialog.dart';

final Logger _log = Logger('dart_couch-widgets-db_state_proxy');

abstract class CredentialsManagerBase {
  LoginCredentials? getCredentials();

  /// saving a null object means: delete stored data!
  void saveCredentials(LoginCredentials? credentials);
}

/// A widget that proxies the UI based on the state of the DartCouchServer.
///
/// This widget handles three different server types with different login behaviors:
///
/// - **LocalDartCouchServer**: No login needed at all. Immediately renders child widget
///   and calls the onLogin callback if provided.
///
/// - **HttpDartCouchServer**: Shows login dialog only when:
///   - No stored credentials are available (disconnected state)
///   - Wrong credentials error from database (wrongCredentials state)
///   For network errors, shows a retry dialog instead of the login dialog.
///
/// - **OfflineFirstServer**: Maintains current behavior with full offline-first
///   synchronization and login state management.
///
/// The local storage directory (for OfflineFirstServer) is created as:
///
/// p.join(
///         widget.localFilePath,
///          '${widget.databaseFileNamePrefix}_${uri.host}_${uri.path.replaceAll('/', '_')}_${credentials.username}',
///          ),
///
class DbStateProxyWidget extends StatefulWidget {
  final DartCouchServer server;
  final Widget child;
  final String localFilePath;
  final String databaseFileNamePrefix;
  final Future<void> Function()? onLogin;

  final CredentialsManagerBase? credentialsManager;

  /// If set, pre-fills the server URL field in the login dialog and takes
  /// precedence over stored credentials.
  final Uri? serverUrl;

  /// If true and [serverUrl] is set, the server URL input field is hidden
  /// entirely in the login dialog.
  final bool dontAskForServer;

  const DbStateProxyWidget({
    super.key,
    required this.server,
    required this.child,
    required this.localFilePath,
    required this.databaseFileNamePrefix,
    this.onLogin,
    this.credentialsManager,
    this.serverUrl,
    this.dontAskForServer = false,
  });

  @override
  State<DbStateProxyWidget> createState() => _DbStateProxyWidgetState();
}

class _DbStateProxyWidgetState extends State<DbStateProxyWidget> {
  String? _errorMessage;
  LoginCredentials? _lastLoginCredentials;

  /// this is needed because onLogin-Callback might take some time, during which
  /// the server state might already be normalOnline, but we still want to
  /// show a loading indicator
  bool _isProcessingLogin = false;

  @override
  void initState() {
    super.initState();

    // Handle LocalDartCouchServer - no login needed
    if (widget.server is LocalDartCouchServer) {
      unawaited(_handleLocalServerInit());
      return;
    }

    // load last credentials if any for HttpDartCouchServer or OfflineFirstServer
    final credentials = widget.credentialsManager?.getCredentials();
    if (credentials != null) {
      unawaited(_handleLogin(credentials));
    }
  }

  Future<void> _handleLocalServerInit() async {
    setState(() {
      _isProcessingLogin = true;
    });

    // No login needed, just call the callback if provided
    await widget.onLogin?.call();

    setState(() {
      _isProcessingLogin = false;
    });
  }

  Future<void> _handleLogin(LoginCredentials credentials) async {
    setState(() {
      _errorMessage = null;
      _lastLoginCredentials = credentials;
      _isProcessingLogin = true;
    });
    try {
      LoginResult? result;

      if (widget.server is OfflineFirstServer) {
        final uri = Uri.parse(credentials.url);
        result = await (widget.server as OfflineFirstServer).login(
          credentials.url,
          credentials.username,
          credentials.password,
          Directory(
            p.join(
              widget.localFilePath,
              '${widget.databaseFileNamePrefix}_${uri.host}_${uri.path.replaceAll('/', '_')}_${credentials.username}',
            ),
          ),
        );
      } else if (widget.server is HttpDartCouchServer) {
        result = await (widget.server as HttpDartCouchServer).login(
          credentials.url,
          credentials.username,
          credentials.password,
        );
      }

      if (result == null) {
        // Network error
        setState(() {
          _errorMessage = 'Network error. Please check your connection.';
          _lastLoginCredentials = credentials;
          _isProcessingLogin = false;
        });
      } else if (result.success == false) {
        // Login failed (wrong credentials)
        setState(() {
          _errorMessage = 'Login failed. Please check your credentials.';
          _lastLoginCredentials = credentials;
          _isProcessingLogin = false;
        });
      } else {
        // login successful
        setState(() {
          _errorMessage = null;
        });

        // persist credentials if needed, or delete them if not
        if (credentials.storeCredentials) {
          widget.credentialsManager?.saveCredentials(credentials);
        } else {
          widget.credentialsManager?.saveCredentials(null);
        }
        await widget.onLogin?.call();

        // Only after onLogin completes, mark processing as done
        setState(() {
          _isProcessingLogin = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Login error: ${e.toString()}';
        _lastLoginCredentials = credentials;
        _isProcessingLogin = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Handle LocalDartCouchServer - no login needed, just show child
    if (widget.server is LocalDartCouchServer) {
      return _buildLocalServerWidget(context);
    }

    // Handle OfflineFirstServer with its state
    if (widget.server is OfflineFirstServer) {
      return _buildOfflineFirstServerWidget(context);
    }

    // Handle HttpDartCouchServer with its connectionState
    if (widget.server is HttpDartCouchServer) {
      return _buildHttpServerWidget(context);
    }

    // Fallback - should not happen
    return widget.child;
  }

  Widget _buildLocalServerWidget(BuildContext context) {
    // If we're still processing login callback, show loading
    if (_isProcessingLogin) {
      return _buildLoadingScaffold(context);
    }

    // LocalDartCouchServer needs no login, just render child
    return widget.child;
  }

  Widget _buildOfflineFirstServerWidget(BuildContext context) {
    final server = widget.server as OfflineFirstServer;

    return DcValueListenableBuilder<OfflineFirstServerState>(
      valueListenable: server.state,
      builder: (context, state, _) {
        _log.info(
          "DbStateProxyWidget (OfflineFirstServer) switched to: $state",
        );

        // If we're still processing login callback, show loading
        if (_isProcessingLogin) {
          return _buildLoadingScaffold(context);
        }

        switch (state) {
          case .unititialized:
          case .errorWrongCredentials:
            return _buildLoginScaffold(context);
          case .tryingToConnect:
            return _buildLoadingScaffold(context);
          case .normalOnline:
          case .normalOffline:
            return widget.child;
        }
      },
    );
  }

  Widget _buildHttpServerWidget(BuildContext context) {
    final server = widget.server as HttpDartCouchServer;

    return DcValueListenableBuilder<DartCouchConnectionState>(
      valueListenable: server.connectionState,
      builder: (context, state, _) {
        _log.info(
          "DbStateProxyWidget (HttpDartCouchServer) switched to: $state",
        );

        // If we're still processing login callback, show loading
        if (_isProcessingLogin) {
          return _buildLoadingScaffold(context);
        }

        switch (state) {
          case .disconnected:
          case .wrongCredentials:
            // Show login dialog if no credentials or wrong credentials
            return _buildLoginScaffold(context);

          case .loginFailedWithNetworkError:
          case .connectedButNetworkError:
            // Show network retry dialog for HttpDartCouchServer
            return _buildNetworkRetryScaffold(context);

          case .loggingIn:
            return _buildLoadingScaffold(context);

          case .connected:
            return widget.child;
        }
      },
    );
  }

  Widget _buildLoadingScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(
            Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildLoginScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: ServerLoginDialog(
          key: const ValueKey('server_login_dialog'),
          errorMessage: _errorMessage,
          initialCredentials: _lastLoginCredentials,
          onLogin: _handleLogin,
          isSaveCredentialsAvailable: widget.credentialsManager != null,
          serverUrl: widget.serverUrl,
          dontAskForServer: widget.dontAskForServer,
        ),
      ),
    );
  }

  Widget _buildNetworkRetryScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: NetworkRetryDialog(
          key: const ValueKey('network_retry_dialog'),
          onRetry: () {
            if (_lastLoginCredentials != null) {
              unawaited(_handleLogin(_lastLoginCredentials!));
            }
          },
          onChangeCredentials: () {
            // Reset to show login dialog
            setState(() {
              _errorMessage = null;
            });
            if (widget.server is HttpDartCouchServer) {
              (widget.server as HttpDartCouchServer).connectionState.value =
                  DartCouchConnectionState.disconnected;
            }
          },
        ),
      ),
    );
  }
}
