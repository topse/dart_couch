import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dart_couch/dart_couch.dart';
import 'package:logging/logging.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

final Logger _log = Logger('dart_couch-widgets-replication_state_proxy');

/// A widget that shows a progress screen while databases are performing initial synchronization.
/// Once all databases have completed their initial sync, it shows the child widget.
///
/// The widget can wait for:
/// - Specific databases by name (via [databaseNames] parameter)
/// - The user's personal database (via [waitForUsersDatabase] = true)
/// - Both specific databases and the user's database
/// - If neither is specified, the child is shown immediately
///
/// The progress screen distinguishes between two phases of replication:
/// - **Checking for changes**: CouchDB compares document revisions to determine what needs syncing.
///   This phase may show "Checking X documents..." even though most documents won't be transferred.
/// - **Transferring documents**: Only documents that actually differ are transferred.
///   Shows "Y documents transferred" to indicate actual data transfer.
///
/// This distinction helps users understand that checking 400 documents doesn't mean transferring
/// 400 documents - most are already in sync and only their revision IDs are compared.
///
/// Example usage:
/// ```dart
/// // Wait for specific databases
/// ReplicationStateProxyWidget(
///   server: server,
///   databaseNames: ['app_data', 'settings'],
///   child: HomeScreen(),
/// )
///
/// // Wait for user's personal database
/// ReplicationStateProxyWidget(
///   server: server,
///   waitForUsersDatabase: true,
///   child: HomeScreen(),
/// )
///
/// // Wait for both
/// ReplicationStateProxyWidget(
///   server: server,
///   databaseNames: ['app_data'],
///   waitForUsersDatabase: true,
///   child: HomeScreen(),
/// )
/// ```
class ReplicationStateProxyWidget extends StatefulWidget {
  final OfflineFirstServer server;
  final List<String>? databaseNames;
  final bool waitForUsersDatabase;
  final Widget child;
  final Widget? progressWidget;
  final String? progressMessage;

  final bool keepScreenOn;

  const ReplicationStateProxyWidget({
    super.key,
    required this.server,
    this.databaseNames,
    this.waitForUsersDatabase = false,
    required this.child,
    this.progressWidget,
    this.progressMessage,
    required this.keepScreenOn,
  });

  @override
  State<ReplicationStateProxyWidget> createState() =>
      _ReplicationStateProxyWidgetState();
}

class _ReplicationStateProxyWidgetState
    extends State<ReplicationStateProxyWidget> {
  final List<OfflineFirstDb> _listeningDatabases = [];
  final Map<String, VoidCallback> _listeners = {};
  final Map<String, ReplicationProgress> _replicationProgress = {};
  bool _allDatabasesSynced = false;
  bool _isLoadingDatabases = true;

  // no setState needed for this one:
  ReplicationState? lastState;

  @override
  void initState() {
    super.initState();
    if (widget.keepScreenOn) unawaited(WakelockPlus.enable());
    unawaited(_loadAndSetupDatabases());
  }

  @override
  void dispose() {
    _cleanupSubscriptions();
    if (widget.keepScreenOn) unawaited(WakelockPlus.disable());
    super.dispose();
  }

  Future<void> _loadAndSetupDatabases() async {
    try {
      // Resolve database names to actual OfflineFirstDb instances
      final databases = <OfflineFirstDb>[];

      // Add databases from databaseNames list if provided
      if (widget.databaseNames != null && widget.databaseNames!.isNotEmpty) {
        for (final dbName in widget.databaseNames!) {
          final db = await widget.server.db(dbName);
          if (db != null && db is OfflineFirstDb) {
            databases.add(db);
          } else {
            _log.warning('Database $dbName not found or not an OfflineFirstDb');
          }
        }
      }

      // Add user's personal database if requested
      if (widget.waitForUsersDatabase) {
        // Get the username from the server
        final username = widget.server.username;
        if (username != null && username.isNotEmpty) {
          final userDbName = DartCouchDb.usernameToDbName(username);
          final userDb = await widget.server.db(userDbName);
          if (userDb != null && userDb is OfflineFirstDb) {
            databases.add(userDb);
            _log.info('Added user database: $userDbName');
          } else {
            _log.warning(
              'User database $userDbName not found or not an OfflineFirstDb',
            );
          }
        } else {
          _log.warning(
            'Cannot wait for user database - username is not available',
          );
        }
      }

      // If no databases were specified and no user database was requested,
      // consider it as "already synced"
      if (databases.isEmpty &&
          !widget.waitForUsersDatabase &&
          (widget.databaseNames == null || widget.databaseNames!.isEmpty)) {
        _log.info(
          'No databases specified to wait for, showing child immediately',
        );
        setState(() {
          _isLoadingDatabases = false;
          _allDatabasesSynced = true;
        });
        if (widget.keepScreenOn) unawaited(WakelockPlus.disable());
        return;
      }

      setState(() {
        _isLoadingDatabases = false;
      });

      _setupReplicationListeners(databases);
    } catch (e, stackTrace) {
      _log.severe('Error loading databases: $e', e, stackTrace);
      setState(() {
        _isLoadingDatabases = false;
      });
    }
  }

  void _setupReplicationListeners(List<OfflineFirstDb> databases) {
    _cleanupSubscriptions();

    if (databases.isEmpty) {
      _log.info('No databases to sync, showing child immediately');
      setState(() {
        _allDatabasesSynced = true;
      });
      if (widget.keepScreenOn) unawaited(WakelockPlus.disable());
      return;
    }

    // Check if all databases are already synced
    _allDatabasesSynced = databases.every((db) {
      final progress = db.replicationController.progress.value;
      return progress.state != ReplicationState.initialSyncInProgress;
    });

    if (_allDatabasesSynced) {
      _log.info('All databases already synced, showing child immediately');
      if (widget.keepScreenOn) unawaited(WakelockPlus.disable());
      return;
    }

    // Listen to replication progress for each database
    for (final db in databases) {
      // Get initial progress value
      final initialProgress = db.replicationController.progress.value;
      _replicationProgress[db.dbname] = initialProgress;

      // Add listener for changes
      void listener() {
        final progress = db.replicationController.progress.value;

        if (progress.state != lastState) {
          _log.fine('Replication progress for ${db.dbname}: ${progress.state}');
          lastState = progress.state;
        }

        // Once all databases have completed initial sync, the gate is latched.
        // Subsequent replication restarts (e.g. after pause/resume) must not
        // flip the widget back to showing the progress screen.
        if (_allDatabasesSynced) return;

        setState(() {
          _replicationProgress[db.dbname] = progress;

          // Check if all databases have completed initial sync
          _allDatabasesSynced = databases.every((db) {
            final currentProgress = _replicationProgress[db.dbname];
            return currentProgress?.state !=
                ReplicationState.initialSyncInProgress;
          });

          // No further listener updates needed once synced
          if (_allDatabasesSynced) {
            _cleanupSubscriptions();
            if (widget.keepScreenOn) unawaited(WakelockPlus.disable());
          }
        });
      }

      db.replicationController.progress.addListener(listener);
      _listeners[db.dbname] = listener;

      _listeningDatabases.add(db);
    }
  }

  void _cleanupSubscriptions() {
    for (final db in _listeningDatabases) {
      final listener = _listeners[db.dbname];
      if (listener != null) {
        db.replicationController.progress.removeListener(listener);
      }
    }
    _listeners.clear();
    _listeningDatabases.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingDatabases) {
      _log.info('Loading databases, showing loading screen');
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator.adaptive(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Loading databases...',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_allDatabasesSynced) {
      _log.info('All databases synced, showing child widget');
      return widget.child;
    }

    // Show progress screen
    _log.info('Showing replication progress screen $_replicationProgress');

    if (widget.progressWidget != null) {
      return widget.progressWidget!;
    }

    // Calculate overall progress
    int totalDocsTransferred = 0;
    int totalDocsToGo = 0;
    int totalDownloadedBytes = 0;
    int totalWrittenBytes = 0;
    int totalBytesEstimate = 0;
    bool hasByteInfo = false;

    for (final progress in _replicationProgress.values) {
      totalDocsTransferred += progress.transferredDocs;
      totalDocsToGo += progress.docsInNeedOfReplication;
      totalDownloadedBytes += progress.transferredBytes;
      totalWrittenBytes += progress.writtenBytes;
      if (progress.totalBytesEstimate != null) {
        totalBytesEstimate += progress.totalBytesEstimate!;
        hasByteInfo = true;
      }
    }

    // Use write-based progress (data is safe once written)
    final int totalDocs = totalDocsTransferred + totalDocsToGo;
    double downloadProgress = 0.0;
    double writeProgress = 0.0;
    if (hasByteInfo && totalBytesEstimate > 0) {
      downloadProgress =
          (totalDownloadedBytes / totalBytesEstimate).clamp(0.0, 1.0);
      writeProgress =
          (totalWrittenBytes / totalBytesEstimate).clamp(0.0, 1.0);
    } else if (totalDocs > 0) {
      downloadProgress = (totalDocsTransferred / totalDocs).clamp(0.0, 1.0);
      writeProgress = downloadProgress;
    }

    // Ensure proper theme inheritance with Scaffold for correct background
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Use themed progress indicator
            CircularProgressIndicator.adaptive(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.progressMessage ?? 'Synchronizing data...',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            if (totalDocs > 0 || hasByteInfo) ...[
              Text(
                _getOverallStatusText(
                  totalDocsTransferred,
                  totalDocsToGo,
                  bytes: hasByteInfo ? totalWrittenBytes : null,
                  totalBytes: hasByteInfo ? totalBytesEstimate : null,
                ),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (hasByteInfo && totalBytesEstimate > 0) ...[
                const SizedBox(height: 10),
                // Download progress bar
                Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        'Download',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: downloadProgress,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Write progress bar
                Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        'Storing',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: writeProgress,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: writeProgress,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ],
            const SizedBox(height: 20),
            // Show individual database progress
            ..._replicationProgress.entries.map((entry) {
              final dbName = entry.key;
              final progress = entry.value;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        dbName,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      _getProgressText(progress),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _getOverallStatusText(
    int transferred,
    int toGo, {
    int? bytes,
    int? totalBytes,
  }) {
    final bytesSuffix = (totalBytes != null && totalBytes > 0)
        ? ' (${_formatBytes(bytes ?? 0)} / ${_formatBytes(totalBytes)})'
        : '';

    if (transferred == 0 && toGo > 0) {
      return 'Checking $toGo documents for changes...$bytesSuffix';
    } else if (transferred > 0 && toGo > 0) {
      return '$transferred documents transferred, checking $toGo more...$bytesSuffix';
    } else if (transferred > 0 && toGo == 0) {
      return '$transferred documents transferred$bytesSuffix';
    } else {
      return 'Synchronizing...';
    }
  }

  String _getProgressText(ReplicationProgress progress) {
    switch (progress.state) {
      case ReplicationState.initializing:
        return 'Initializing...';
      case ReplicationState.initialSyncInProgress:
        final byteInfo =
            (progress.totalBytesEstimate != null &&
                progress.totalBytesEstimate! > 0)
            ? ' (${_formatBytes(progress.transferredBytes)} / ${_formatBytes(progress.totalBytesEstimate!)})'
            : '';
        if (progress.transferredDocs == 0 &&
            progress.docsInNeedOfReplication > 0) {
          return 'Checking ${progress.docsInNeedOfReplication} documents...$byteInfo';
        } else if (progress.transferredDocs > 0) {
          return '${progress.transferredDocs} transferred / ${progress.docsInNeedOfReplication} remaining$byteInfo';
        } else {
          return 'In progress...$byteInfo';
        }
      case ReplicationState.initialSyncComplete:
        return 'Sync complete';
      case ReplicationState.inSync:
        return 'In sync';
      case ReplicationState.paused:
        return 'Paused';
      case ReplicationState.waitingForNetwork:
        return 'Waiting for network';
      case ReplicationState.terminated:
        return 'Terminated';
      case ReplicationState.error:
        return 'Error: ${progress.message ?? 'Unknown error'}';
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
}
