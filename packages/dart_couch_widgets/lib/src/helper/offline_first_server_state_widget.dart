import 'package:dart_couch/dart_couch.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import '../value_listenable_builder.dart';

final Logger _log = Logger('dart_couch-widgets-offline_first_server_state');

class OfflineFirstServerStateWidget extends StatelessWidget {
  final OfflineFirstServer server;
  final OfflineFirstDb? db;

  final bool showPercentage;

  const OfflineFirstServerStateWidget({
    super.key,
    required this.server,
    required this.showPercentage,
    this.db,
  });

  @override
  Widget build(BuildContext context) {
    return db != null
        ? DcValueListenableBuilder(
            valueListenable: db!.replicationController.progress,
            builder: (context, replicationProgress, child) {
              _log.info('*** replicationProgress: $replicationProgress');

              return DcValueListenableBuilder(
                valueListenable: server.state,
                builder: (context, state, _) {
                  Color col = state == OfflineFirstServerState.normalOnline
                      ? Colors.green
                      : state == OfflineFirstServerState.normalOffline
                      ? Colors.orange
                      : Colors.red;

                  Icon icon;

                  if (replicationProgress.docsInNeedOfReplication > 0) {
                    icon = Icon(Icons.cloud_sync, color: col);
                    if (!showPercentage) return icon;
                    final percent = (replicationProgress.progressFraction * 100)
                        .round();
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        icon,
                        const SizedBox(width: 2),
                        Text(
                          '$percent%',
                          style: TextStyle(fontSize: 10, color: col),
                        ),
                      ],
                    );
                  } else {
                    icon = state == OfflineFirstServerState.normalOnline
                        ? Icon(Icons.cloud_done, color: col)
                        : state == OfflineFirstServerState.normalOffline
                        ? Icon(Icons.cloud_queue, color: col)
                        : Icon(Icons.cloud_off, color: col);
                  }

                  return icon;
                },
              );
            },
          )
        : DcValueListenableBuilder(
            valueListenable: server.state,
            builder: (context, state, _) {
              switch (state) {
                case .normalOnline:
                  return const Icon(Icons.cloud_done, color: Colors.green);
                case .normalOffline:
                  return const Icon(Icons.cloud_queue, color: Colors.orange);
                case .unititialized:
                case .tryingToConnect:
                case .errorWrongCredentials:
                  return const Icon(Icons.cloud_off, color: Colors.red);
              }
            },
          );
  }
}
