# DartCouchDB

An offline-first database solution for Dart and Flutter that synchronizes with [CouchDB](https://couchdb.apache.org/). Inspired by [PouchDB](https://pouchdb.com/) for the JavaScript world.

DartCouchDB lets your app work fully offline with a local SQLite database and automatically syncs with a remote CouchDB server when connectivity is available. It implements CouchDB's replication protocol for reliable, bidirectional data synchronization.

I started the project "by hand", but at some point I started to use AI pretty hard. While doing so I was thinking, how to achieve some quality of code without the need to read every line of code, the AI creates -- if I would have needed, AI would not have been a lot of help. So I came up with a solution, which seems to work quite nice:

As I already started to implement a lot of tests, I moved my "human" work mainly to that: give silly questions to the AI and think about lots of possible (and impossible) test cases. Now the project contains more than 350 test cases. Having those test cases in the later progress of the project was really a life-saver, as on every change, those tests could run and check if the latest changes or refactoring had unwanted side-effects. And believe me -- there were... especially on big features, like self-healing replication and so on.

The AI always had the task to write helpful comments, so the code itself can be easily understood and all edge cases are hopefully documented. The better my CLAUDE.MD file got, the better was the AI in really doing meaningful stuff. And when having enough logging in all part of the library and the tests, the AI can even really help to find bugs: Just give it the failing test-case and the log which shows the problem (and a description if needed), and the AI has found and fixed most problems in the twinkling of an eye -- even hard ones like race conditions. There were only few problems when the AI had ideas like "lets fix the test case" -- but even then, after telling it that we don't fix inconvenient test cases, it found the correct solutions.

So I can say: Without AI I wouldn't have been so fast in implementing this project, inspite I can confirm, that AI still needs some guidance regarding architecture -- but I fear, this will change within the next one or two years...

Yet there are still only three applications using this lib:
- the "official example" (which is my shopping list we are using in the family)
- a Media Player App for my little one which can be operated by tapping images only
- The companion app to the media player, which is used on desktop to fill the contents for the app to be synced automatically to the mobil phone, so I can easily provide content

So it may very well be that in some edge cases there are still problems. 

The last big refactoring for example was about removing the flutter dependency from the core lib, because with flutter I could not use it in a server environment, and the addition of the platform "web", which needed some refactoring and changes too.

The project is currently not on pub.dev -- They are saying, pub.dev is permanent... For now I want to have a little emergency exit, if there is a unrecoverable problem with the lib, I may have not found yet...

## Supported Platforms

| Platform | Status | Notes |
|---|---|---|
| Windows | Supported | Native SQLite + QuickJS via FFI |
| Linux | Supported | Native SQLite + QuickJS via FFI |
| Android | Supported | Native SQLite + QuickJS via FFI |
| Web | Supported | SQLite WASM + browser JS engine, Basic Auth (see "Web Platform Support") |
| macOS | Not supported | I don't have apple devices...  |
| iOS | Not supported | at hand... :-/ |

## Packages

| Package | Description |
|---|---|
| [dart_couch](packages/dart_couch/) | Core library — pure Dart, no Flutter dependency |
| [dart_couch_widgets](packages/dart_couch_widgets/) | Flutter widgets and helpers (depends on dart_couch) |

## Usage

Since these packages are not yet on pub.dev, depend on them via Git. Choose **one** of the two options below — do not add both. That is a quirk because we currently only on github, not pub.dev:

### Option A: Flutter apps

Use `dart_couch_widgets`, which re-exports the core `dart_couch` library. One dependency gives you everything:

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

### Option B: Pure Dart projects (servers, CLI tools)

Use `dart_couch` directly — no Flutter dependency required:

```yaml
dependencies:
  dart_couch:
    git:
      url: https://github.com/topse/dart_couch
      path: packages/dart_couch
```

```dart
import 'package:dart_couch/dart_couch.dart';
```

## Prerequisites

The core library compiles a small C library (QuickJS) as a native asset. You need a C compiler on your system (GCC/Clang on Linux, Xcode CLI tools on macOS, Visual Studio 2022 on Windows). See the [dart_couch README](packages/dart_couch/README.md#prerequisites) for details.

## Third-Party Code

This project embeds [QuickJS](https://github.com/quickjs-ng/quickjs) (the source is committed directly in `packages/dart_couch/third_party/quickjs/`) for evaluating CouchDB map/reduce view functions locally. QuickJS is licensed under the MIT License — see [its LICENSE](packages/dart_couch/third_party/quickjs/LICENSE) for details.

## License

MIT — see [LICENSE](LICENSE).
