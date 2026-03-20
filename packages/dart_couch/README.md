# DartCouchDB

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Dart](https://img.shields.io/badge/Dart-%3E%3D3.10-blue)](https://dart.dev)

A pure Dart offline-first database library that synchronizes with [CouchDB](https://couchdb.apache.org/). Inspired by [PouchDB](https://pouchdb.com/) for the JavaScript world.

DartCouchDB lets your app work fully offline with a local SQLite database and automatically syncs with a remote CouchDB server when connectivity is available. It implements CouchDB's replication protocol for reliable, bidirectional data synchronization.

This package has **no Flutter dependency** and can be used in CLI tools, servers, or any Dart application.

> **Flutter users:** For ready-made widgets (lifecycle observer, state proxy widgets, login dialogs), see the companion package [dart_couch_widgets](../dart_couch_widgets/).

## Supported Platforms

| Platform | Status | Notes |
|---|---|---|
| Windows | Supported | Native SQLite + QuickJS via FFI |
| Linux | Supported | Native SQLite + QuickJS via FFI |
| Android | Supported | Native SQLite + QuickJS via FFI |
| Web | Supported | SQLite WASM + browser JS engine, Basic Auth (see "Web Platform Support") |
| macOS | Not supported | |
| iOS | Not supported | |

## Features

- **Offline-first** - Read and write data at any time, even without a network connection
- **Automatic bidirectional sync** - Changes are synchronized in both directions when online
- **Reactive APIs** - PouchDB-inspired `useDoc`, `useView`, and `useAllDocs` streams for real-time UI updates
- **Multi-instance safe** - Multiple app instances or clients can share the same databases
- **Database recreation detection** - Marker-based system reliably detects when a remote database was recreated
- **Coordinated deletion** - Tombstone protocol ensures databases are only deleted when all instances have disconnected
- **Conflict resolution** - Configurable strategies (`merge`, `serverAlwaysWins`, `localAlwaysWins`) for database recreation conflicts
- **Lifecycle management** - `pause()` and `resume()` to stop and restart all background activity
- **Attachment support** - Memory-efficient streaming attachment replication with on-disk storage
- **Database migrations** - Built-in support for schema migrations
- **Local view engine** - Evaluates CouchDB map/reduce view functions locally via an embedded [QuickJS](https://github.com/quickjs-ng/quickjs) JavaScript engine

## Prerequisites

DartCouchDB compiles a small C library (QuickJS) as a native asset. This requires:

- **Dart SDK >= 3.10** (with native assets support)
- **A C compiler** on your system:
  - Linux: `gcc` or `clang` (e.g. `sudo apt install build-essential`)
  - macOS: Xcode Command Line Tools (`xcode-select --install`)
  - Windows: Visual Studio 2022 with C++ workload

The native library is compiled automatically by the Dart build hook — no manual steps required.

## Getting Started

Add DartCouchDB to your `pubspec.yaml`:

```yaml
dependencies:
  dart_couch:
    git:
      url: https://github.com/topse/dart_couch
      path: packages/dart_couch
```

DartCouchDB uses [dart_mappable](https://pub.dev/packages/dart_mappable) for data classes. If you define custom document classes extending `CouchDocumentBase`, you also need:

```yaml
dependencies:
  dart_mappable: ^4.7.0

dev_dependencies:
  build_runner: ^2.7.1
  dart_mappable_builder: ^4.7.0
```

After defining or changing your document classes (see CouchDocumentBase), run code generation:

```bash
dart run build_runner build
```

## Quick Start

```dart
import 'package:dart_couch/dart_couch.dart';

// Initialize mappers (call once at startup)
DartCouchDb.ensureInitialized();

// Create the offline-first server
final server = OfflineFirstServer(
  conflictResolution: DatabaseConflictResolution.merge,
);

// Connect to CouchDB
await server.login(
  url: 'https://your-couchdb-server.com',
  username: 'your_username',
  password: 'your_password',
);

// Get a database (created locally if it doesn't exist yet)
final db = await server.db('my_database');

// Save a document
await db.putRaw({
  '_id': 'doc1',
  'name': 'Jane Doe',
  'age': 30,
});

// Read a document
final doc = await db.get('doc1');

// Delete a document
await db.delete('doc1');
```

## Reactive APIs

Watch documents and views for real-time changes:

```dart
// Watch a single document
final subscription = db.useDoc('user-123').listen((doc) {
  if (doc != null) {
    print('Updated: ${doc.id} rev ${doc.rev}');
  }
});

// Watch a view
final viewSubscription = db.useView('mydesign/myview').listen((result) {
  print('View has ${result.rows.length} rows');
});

// Watch multiple documents
final multiSubscription = db.useAllDocs(['doc1', 'doc2', 'doc3']).listen((result) {
  print('Got ${result.rows.length} documents');
});

// Don't forget to cancel when done
await subscription.cancel();
```

## Lifecycle Management

The core library provides `pause()` and `resume()` on `OfflineFirstServer` to stop and restart all background activity (timers, streams, network requests). This is useful for conserving resources when your application goes idle or to the background.

For Flutter apps, the companion package [dart_couch_widgets](../dart_couch_widgets/) provides `OfflineFirstServerLifecycleObserver`, which automatically calls `pause()` and `resume()` based on the app lifecycle.

## Conflict Resolution

When a remote database is recreated (detected via UUID markers), DartCouchDB resolves the conflict based on your chosen strategy:

| Strategy | Behavior |
|---|---|
| `merge` (default) | Preserves documents from both incarnations |
| `serverAlwaysWins` | Replaces local data with the remote version |
| `localAlwaysWins` | Replaces remote data with the local version |

> **Note:** These strategies handle *database recreation* conflicts, not individual document conflicts. Document conflicts follow CouchDB's standard revision tree model.

## API Overview

### OfflineFirstServer

| Method | Description |
|---|---|
| `login(url, username, password)` | Connect to a CouchDB server |
| `logout()` | Disconnect and unregister from all databases |
| `db(name)` | Get a database instance (creates locally if needed) |
| `createDatabase(name)` | Create a new database (works offline) |
| `deleteDatabase(name)` | Delete with coordinated tombstone protocol |
| `pause()` | Stop all background activity |
| `resume()` | Resume activity and sync missed changes |
| `state` | Stream of connection state changes |

### OfflineFirstDb

| Method | Description |
|---|---|
| `get(id)` | Get a document by ID |
| `put(document)` / `putRaw(map)` | Save or update a document |
| `delete(id)` | Delete a document |
| `allDocs()` | Get all documents |
| `useDoc(id)` | Reactive stream for a single document |
| `useView(path, ...)` | Reactive stream for a view |
| `useAllDocs(keys)` | Reactive stream for multiple documents |

### CouchDocumentBase

All documents extend `CouchDocumentBase`, which maps CouchDB's standard fields:

```dart
@MappableClass(discriminatorValue: 'my_document')
class MyDocument extends CouchDocumentBase with MyDocumentMappable {
  final String name;
  final int age;

  MyDocument({
    required this.name,
    required this.age,
    super.id,
    super.rev,
    super.deleted,
    super.attachments,
    super.revisions,
    super.revsInfo,
    super.unmappedProps,
  });

  static final fromMap = MyDocumentMapper.fromMap;
  static final fromJson = MyDocumentMapper.fromJson;
}
```

Built-in fields: `id` (`_id`), `rev` (`_rev`), `deleted` (`_deleted`), `attachments` (`_attachments`), `revisions`, `revsInfo`. Any extra JSON fields not explicitly mapped are preserved in `unmappedProps`.

Be careful: dart_mappable has problems with unknown discriminatorValue's. If you are dealing with such, use the getRaw, putRaw functions, otherwise you may have to deal with dataloss, as the !doc_type-field will get lost!

**AttachmentInfo** provides attachment metadata (`contentType`, `digest`, `length`) and helpers like `dataDecoded` for base64-decoded content and `calculateCouchDbAttachmentDigest()` for computing CouchDB-compatible digests.

## Permissions

Database discovery and creation on the server requires:
- Access to the `_all_dbs` endpoint
- Permission to create databases on the CouchDB server

Databases that already exist (e.g., per-user databases) can be accessed without creation permissions.

## Architecture

DartCouchDB has three database implementations sharing a common `DartCouchDb` interface:

- **`HttpDartCouchDb`** - Talks directly to CouchDB via HTTP (reference implementation)
- **`LocalDartCouchDb`** - Stores data locally using SQLite via [Drift](https://drift.simonbinder.eu/)

`OfflineFirstDb` combines both, routing reads/writes to the local database and synchronizing with the remote in the background. Attachments are stored as individual files on disk (not as BLOBs in SQLite) for memory efficiency.

CouchDB map/reduce view functions are evaluated locally using an embedded [QuickJS](https://github.com/quickjs-ng/quickjs) JavaScript engine, compiled as a native asset via `dart:ffi`.

## Testing

Tests require **Linux with Docker** installed. Most tests spin up a CouchDB container and cannot run on Windows or without Docker.

## Example

See the [example/](example/) directory for a full Flutter shopping list app demonstrating offline-first usage with DartCouchDB (uses the companion [dart_couch_widgets](../dart_couch_widgets/) package for Flutter UI components).

## License

MIT - see [LICENSE](LICENSE) for details.
