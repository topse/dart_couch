import 'dart:async';

import 'package:dart_couch/dart_couch.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

final Logger _healthLog = Logger('dart_couch-health_monitoring');

/// Mixin that provides periodic health monitoring of a CouchDB server by
/// polling the `_session` endpoint.
mixin HealthMonitoring {
  // Dependencies to be provided by the host class.
  DcValueNotifier<OfflineFirstServerState> get state;
  Future<SessionResult> session();
  Future<bool> isCouchDbUp();
  Uri? get uri;
  String? get username;
  String? get password;
  Directory? get localDirectory;

  String? get authCookie;

  Future<LoginResult?> login(
    String url,
    String username,
    String password,
    Directory localDirectory,
  );

  /// Internal method for login with relogin flag.
  /// Do not use directly - use [login] instead.
  /// This method is used internally by health monitoring for reconnection.
  Future<LoginResult?> loginWithReloginFlag(
    String url,
    String username,
    String password,
    Directory localDirectory, {
    required bool isRelogin,
  });

  /// Called when the server transitions back to online state
  Future<void> onBackOnline();

  Timer? _healthTimer;
  Duration _healthInterval = const Duration(seconds: 5);
  bool _healthCheckInProgress = false;

  /// Callbacks to invoke when coming back online
  final List<Future<void> Function()> _recoveryCallbacks = [];

  /// Flag indicating network degradation was detected
  bool _networkDegraded = false;

  /// Whether any component has signalled network degradation since the last
  /// successful recovery. Read by [OfflineFirstServer.resume] to decide
  /// whether it is safe to promote state to [normalOnline].
  bool get isNetworkDegraded => _networkDegraded;

  bool get isHealthMonitoringActive => _healthTimer != null;

  /// Register a callback to be invoked when transitioning back online
  void registerRecoveryCallback(Future<void> Function() callback) {
    _recoveryCallbacks.add(callback);
  }

  /// Unregister a callback that was previously registered
  void unregisterRecoveryCallback(Future<void> Function() callback) {
    _recoveryCallbacks.remove(callback);
  }

  /// Notify health monitoring that network degradation was detected.
  /// This sets a flag to trigger recovery callbacks on the next successful health check.
  void notifyNetworkDegraded() {
    _healthLog.fine('Network degradation detected by component');
    _networkDegraded = true;
  }

  /// Start periodic health monitoring (idempotent).
  void startHealthMonitoring({Duration? interval}) {
    if (_healthTimer != null) return; // already running
    _healthInterval = interval ?? _healthInterval;
    _healthLog.fine('Starting health monitoring every $_healthInterval');
    _healthTimer = Timer.periodic(_healthInterval, (_) async {
      // maybe everything is fine already
      // network error could have been occured
      //    -> login may be required, given credentials have been correct in the past
      //        (however, they could be invalid now)
      if (_healthCheckInProgress) return; // avoid overlapping checks
      _healthCheckInProgress = true;
      try {
        final isUp = await isCouchDbUp();
        if (isUp) {
          if (authCookie == null) {
            assert(username != null && password != null && uri != null);
            // Session lost (no cookie) - try to login again
            await _attemptRelogin();
          } else {
            // Have a cookie - validate it by checking the session
            try {
              final sessionResult = await session();
              // Check if session is valid (name should not be null)
              if (sessionResult.userCtx.name == null) {
                // Session expired - need to re-login
                _healthLog.fine(
                  'Session expired (name is null), re-logging in',
                );
                await _attemptRelogin();
              } else {
                // Session is valid
                _healthLog.fine(
                  'Session valid — state=${state.value}, _networkDegraded=$_networkDegraded',
                );
                if (state.value != .normalOnline || _networkDegraded) {
                  // onBackOnline() already calls invokeRecoveryCallbacks() via
                  // _performBackOnlineWork(). Do NOT call it a second time here
                  // — a double call stops and restarts each replication controller
                  // in rapid succession, which can leave replication in a broken
                  // state on intermittent networks.
                  _healthLog.info(
                    'Session valid + recovery needed (state=${state.value}, _networkDegraded=$_networkDegraded) — calling onBackOnline()',
                  );
                  await onBackOnline();
                  state.value = .normalOnline;
                  _networkDegraded = false;
                } else {
                  _healthLog.fine(
                    'Session valid + already normalOnline + no network degradation — no action needed',
                  );
                }
              }
            } on NetworkFailure catch (e) {
              // getting session failed due to network error
              _healthLog.fine('Session check network error: $e');
              state.value =
                  .normalOffline; // maybe normalTryingToConnect? Then our GUI may change to CircularProgressBar?
            } on CouchDbException catch (e) {
              // Session check failed (401 unauthorized or other error) - need to re-login
              _healthLog.fine('Session check failed: $e, re-logging in');
              await _attemptRelogin();
            } catch (e) {
              _healthLog.severe('Session check error: $e');
              state.value =
                  .normalOffline; // maybe normalTryingToConnect? Then our GUI may change to CircularProgressBar?
            }
          }
        } else {
          _healthLog.fine('CouchDB server is down');
          // Mark network as degraded if we were online so we can trigger recovery
          if (state.value == .normalOnline) {
            _networkDegraded = true;
          }
          state.value = .normalOffline;
        }
      } on http.ClientException catch (e) {
        _healthLog.fine('Health check network error: $e');
        // Mark network as degraded if we were online so we can trigger recovery
        if (state.value == .normalOnline) {
          _networkDegraded = true;
        }
        state.value = .normalOffline;
      } catch (e) {
        _healthLog.fine('Health check error: $e');
        // Mark network as degraded if we were online so we can trigger recovery
        if (state.value == .normalOnline) {
          _networkDegraded = true;
        }
        state.value = .normalOffline;
      } finally {
        _healthCheckInProgress = false;
      }
    });
  }

  /// Stop health monitoring (idempotent).
  void stopHealthMonitoring() {
    _healthLog.fine('Stopping health monitoring - START');
    if (_healthTimer != null) {
      _healthLog.fine('Cancelling health timer');
      _healthTimer?.cancel();
      _healthLog.fine('Health timer cancelled');
    } else {
      _healthLog.fine('No health timer to cancel');
    }
    _healthTimer = null;
    _healthLog.fine(
      'Setting _healthCheckInProgress to false (was: $_healthCheckInProgress)',
    );
    _healthCheckInProgress = false;
    _healthLog.fine('Stopping health monitoring - COMPLETE');
  }

  /// Invoke all registered recovery callbacks
  Future<void> invokeRecoveryCallbacks() async {
    _healthLog.fine('Invoking ${_recoveryCallbacks.length} recovery callbacks');
    var index = 0;
    for (final callback in _recoveryCallbacks) {
      try {
        _healthLog.fine(
          'Invoking recovery callback ${++index}/${_recoveryCallbacks.length}',
        );
        await callback();
        _healthLog.fine('Recovery callback $index completed');
      } catch (e) {
        _healthLog.warning('Recovery callback $index failed: $e');
      }
    }
    _healthLog.fine('All recovery callbacks completed');
  }

  /// Attempt to re-login and update state accordingly
  Future<void> _attemptRelogin() async {
    final prev = state.value;
    _healthLog.info('_attemptRelogin() START — prev state: $prev');
    final loginRes = await loginWithReloginFlag(
      uri.toString(),
      username!,
      password!,
      localDirectory!,
      isRelogin: true,
    );

    if (loginRes == null) {
      // network error -- keep trying
      _healthLog.fine(
        '_attemptRelogin(): loginRes == null (network error), staying normalOffline',
      );
      state.value =
          .normalOffline; // maybe normalTryingToConnect? Then our GUI may change to CircularProgressBar?
    } else if (loginRes.success) {
      // Login successful
      _healthLog.info(
        '_attemptRelogin(): login succeeded, prev=$prev — '
        '${prev != .normalOnline ? 'calling onBackOnline()' : 'SKIPPING onBackOnline (prev==normalOnline)'}',
      );
      if (prev != .normalOnline) {
        // onBackOnline() already calls invokeRecoveryCallbacks() internally via
        // _performBackOnlineWork(). Do NOT call it a second time here.
        await onBackOnline();
      }
      state.value = .normalOnline;
      _healthLog.info('_attemptRelogin() COMPLETE — state set to normalOnline');
    } else if (loginRes.statusCode == .unauthorized) {
      _healthLog.warning('_attemptRelogin(): unauthorized (wrong credentials)');
      state.value = .errorWrongCredentials;
    } else {
      // Server error but credentials might still be valid
      _healthLog.warning(
        '_attemptRelogin(): login failed with statusCode=${loginRes.statusCode}, setting normalOnline',
      );
      state.value =
          .normalOnline; // maybe normalTryingToConnect? Then our GUI may change to CircularProgressBar?
    }
  }
}
