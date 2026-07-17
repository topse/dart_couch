// All imports must be at the top

import 'dart:async';
import 'package:dart_couch/dart_couch.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('dart_couch-wigets-lifecycle_observer');

/// Observes the Flutter app lifecycle and pauses/resumes [OfflineFirstServer]
/// accordingly.
///
/// **Why only `paused` and `resumed`?**
/// Android emits several intermediate states (`hidden`, `inactive`) as part of
/// every foreground↔background transition. If we called `server.resume()` for
/// every non-paused state, we would fire two or three concurrent async resume
/// calls on every wakeup. Because `resume()` holds `_lifecycleMutex`, the
/// second and third calls queue up and each runs the full back-online recovery
/// procedure (marker sync, db-updates stream, replication restart) in rapid
/// succession — stopping and immediately restarting each replication controller.
/// On intermittent networks this left replication permanently broken.
///
/// `paused` is the only state that definitively means "app is in the background";
/// `resumed` is the only state that definitively means "app is in the foreground".
/// All other states (`hidden`, `inactive`, `detached`) are transient and must be
/// ignored.
class OfflineFirstServerLifecycleObserver with WidgetsBindingObserver {
  final OfflineFirstServer server;

  OfflineFirstServerLifecycleObserver({required this.server});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _log.info(
      "OfflineFirstServerLifecycleObserver: Switching to lifecycle state: $state",
    );

    if (state == AppLifecycleState.paused) {
      scheduleMicrotask(() async {
        _log.info("OfflineFirstServerLifecycleObserver: Pausing server");
        await server.pause();
      });
    } else if (state == AppLifecycleState.resumed) {
      scheduleMicrotask(() async {
        _log.info("OfflineFirstServerLifecycleObserver: Resuming server");
        await server.resume();
      });
    } else {
      _log.info(
        "OfflineFirstServerLifecycleObserver: Ignoring intermediate state: $state",
      );
    }
  }
}
