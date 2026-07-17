# DartCouchDB Widgets

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](../dart_couch/LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-%3E%3D3.38-blue)](https://flutter.dev)

Flutter widgets and helpers for [dart_couch](../dart_couch/) — the offline-first CouchDB library for Dart.

This package provides ready-made UI components for authentication flows, replication progress, lifecycle management, and connection state display. It depends on the pure-Dart `dart_couch` core library.

## Supported Platforms

| Platform | Status | Notes |
|---|---|---|
| Windows | Supported | Native SQLite + QuickJS via FFI |
| Linux | Supported | Native SQLite + QuickJS via FFI |
| Android | Supported | Native SQLite + QuickJS via FFI |
| Web | Supported | SQLite WASM + browser JS engine, Basic Auth (see "Web Platform Support") |
| macOS | Not supported | |
| iOS | Not supported | |

## Getting Started

Add only `dart_couch_widgets` to your `pubspec.yaml` — it re-exports the core `dart_couch` library, so you do **not** need to add `dart_couch` as a separate dependency. That is a quirk because we currently only on github, not pub.dev:

```yaml
dependencies:
  dart_couch_widgets:
    git:
      url: https://github.com/topse/dart_couch
      path: packages/dart_couch_widgets
```

```dart
import 'package:dart_couch_widgets/dart_couch.dart';         // core library
import 'package:dart_couch_widgets/dart_couch_widgets.dart'; // widgets
```

## Widgets

### DbStateProxyWidget

Gates your UI behind authentication. Shows a login dialog when the server is disconnected or has wrong credentials, a loading screen while connecting, and renders the `child` once authenticated. Works with all three server types (`LocalDartCouchServer`, `HttpDartCouchServer`, `OfflineFirstServer`).

```dart
DbStateProxyWidget(
  server: server,
  localFilePath: appDocDir.path,
  databaseFileNamePrefix: 'myapp',
  onLogin: () async { /* post-login setup */ },
  credentialsManager: myCredentialsManager, // optional: persist credentials
  child: MyApp(),
)
```

### ReplicationStateProxyWidget

Gates your UI until initial replication completes for the specified databases. Shows sync progress (documents transferred, bytes, percentage) and enables a wakelock to prevent the device from sleeping during the initial sync.

```dart
ReplicationStateProxyWidget(
  server: server,
  databaseNames: ['products', 'orders'],
  waitForUsersDatabase: true, // also wait for the per-user database
  keepScreenOn: true,
  child: MyApp(),
)
```

### OfflineFirstServerLifecycleObserver

A `WidgetsBindingObserver` that automatically calls `pause()` when the app goes to background and `resume()` when it returns to foreground. Handles Android's intermediate lifecycle states correctly (ignores `hidden`, `inactive`, `detached` to avoid spurious resume calls).

```dart
WidgetsBinding.instance.addObserver(
  OfflineFirstServerLifecycleObserver(server: server),
);
```

### OfflineFirstServerStateWidget

A stateless widget that displays the current connection and sync state as a cloud icon. Optionally pass a specific `db` to show per-database replication progress.

```dart
OfflineFirstServerStateWidget(
  server: server,
  db: myDatabase,       // optional: show per-DB sync status
  showPercentage: true, // show sync % when replicating
)
```

| State | Icon | Color |
|---|---|---|
| Online, synced | Cloud with checkmark | Green |
| Online, syncing | Cloud with sync arrows | Green |
| Offline | Cloud with queue | Orange |
| Error | Cloud off | Red |

### DcValueListenableBuilder

Bridges `dart_couch`'s pure-Dart `DcValueListenable` into Flutter's widget tree, similar to Flutter's `ValueListenableBuilder`.

```dart
DcValueListenableBuilder<MyState>(
  valueListenable: myDcValueNotifier,
  builder: (context, value, child) {
    return Text('Current value: $value');
  },
)
```

## License

MIT — see [LICENSE](../dart_couch/LICENSE) for details.
