/// Web stubs for dart:io types used by dart_couch.
///
/// The Dart analyzer validates code against ALL branches of a conditional
/// import, not just the current platform. Therefore these stubs must declare
/// every method that the codebase calls on dart:io types. On web, these
/// methods throw [UnsupportedError] — actual I/O is handled by
/// platform-specific backends (Drift WASM, browser JS engine).
library;

import 'dart:async';
import 'dart:typed_data';

/// Stub [Directory] for web.
///
/// Carries a [path] string that is sanitised into a database name.
/// Filesystem operations are no-ops.
class Directory {
  final String path;

  Directory(this.path);

  void createSync({bool recursive = false}) {
    // no-op on web
  }

  bool existsSync() => false;

  List<FileSystemEntity> listSync() => const [];
}

/// Stub [File] for web.
///
/// Declares every method the codebase uses so the analyzer is satisfied.
/// On web, actual attachment I/O goes through the AttachmentStorage
/// abstraction — these methods are never called at runtime on web.
class File implements FileSystemEntity {
  @override
  final String path;

  File(this.path);

  @override
  Uri get uri => Uri.parse(path);

  bool existsSync() => false;

  Future<bool> exists() async => false;

  Future<File> delete({bool recursive = false}) async => this;

  Future<Uint8List> readAsBytes() async =>
      throw UnsupportedError('File.readAsBytes is not supported on web');

  Future<File> writeAsBytes(List<int> bytes, {bool flush = false}) async =>
      throw UnsupportedError('File.writeAsBytes is not supported on web');

  Future<File> rename(String newPath) async =>
      throw UnsupportedError('File.rename is not supported on web');

  Stream<List<int>> openRead([int? start, int? end]) =>
      throw UnsupportedError('File.openRead is not supported on web');

  IOSink openWrite({
    FileMode mode = FileMode.write,
    // ignore: avoid_unused_constructor_parameters
  }) =>
      throw UnsupportedError('File.openWrite is not supported on web');
}

/// Minimal [FileSystemEntity] stub for web.
abstract class FileSystemEntity {
  String get path;
  Uri get uri;
}

/// Stub [FileMode] for web.
class FileMode {
  static const FileMode write = FileMode._('write');
  static const FileMode append = FileMode._('append');
  static const FileMode read = FileMode._('read');
  final String _name;
  const FileMode._(this._name);
  @override
  String toString() => 'FileMode.$_name';
}

/// Stub [IOSink] for web — satisfies type references but throws on use.
class IOSink implements StreamSink<List<int>> {
  @override
  void add(List<int> data) =>
      throw UnsupportedError('IOSink is not supported on web');

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      throw UnsupportedError('IOSink is not supported on web');

  @override
  Future addStream(Stream<List<int>> stream) =>
      throw UnsupportedError('IOSink is not supported on web');

  @override
  Future close() =>
      throw UnsupportedError('IOSink is not supported on web');

  @override
  Future get done =>
      throw UnsupportedError('IOSink is not supported on web');

  Future flush() =>
      throw UnsupportedError('IOSink is not supported on web');
}

/// Stub [Platform] for web — reports no native platform flags.
class Platform {
  static const bool isWindows = false;
  static const bool isAndroid = false;
  static const bool isLinux = false;
  static const bool isMacOS = false;
  static const bool isIOS = false;
  static const bool isFuchsia = false;
}

/// Stub [Process] for web — all operations throw.
class Process {
  static Future<ProcessResult> run(
    String executable,
    List<String> arguments,
  ) async =>
      throw UnsupportedError('Process.run is not supported on web');
}

/// Stub [ProcessResult] for web.
class ProcessResult {
  final int exitCode;
  final dynamic stdout;
  final dynamic stderr;
  final int pid;

  ProcessResult(this.pid, this.exitCode, this.stdout, this.stderr);
}

/// Stub gzip codec for web.
///
/// The real gzip decode on web is handled by a separate conditional import
/// in gzip_decode.dart. This stub exists only to satisfy import references.
final GZipCodecStub gzip = GZipCodecStub();

class GZipCodecStub {
  List<int> decode(List<int> data) =>
      throw UnsupportedError('gzip.decode is not supported on web — use the '
          'platform gzip_decode utility instead');
}
