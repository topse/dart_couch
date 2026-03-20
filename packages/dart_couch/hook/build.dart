import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

const _quickJsSources = <String>[
  'native/quickjs_wrapper.c',
  'third_party/quickjs/quickjs.c',
  'third_party/quickjs/dtoa.c',
  'third_party/quickjs/libregexp.c',
  'third_party/quickjs/libunicode.c',
];

const _quickJsIncludes = <String>['native/', 'third_party/quickjs/'];

const _nonWindowsWarningFlags = <String>[
  '-Wno-sign-compare',
  '-Wno-unused-parameter',
  '-Wno-implicit-fallthrough',
];

const _vsInstallRoots = <String>[
  r'C:\Program Files\Microsoft Visual Studio\2022\Community',
  r'C:\Program Files\Microsoft Visual Studio\2022\BuildTools',
];

void main(List<String> args) async {
  await build(args, (input, output) async {
    // Skip native compilation for web targets (no native code assets needed).
    if (!input.config.buildCodeAssets) return;

    final effectiveInput = await _withWindowsMsvcWorkaround(input);
    final cFlags = Platform.isWindows
        ? const <String>[]
        : _nonWindowsWarningFlags;
    final cLibraries = input.config.code.targetOS == OS.android
        ? const <String>['m']
        : const <String>[];
    final cDefines = <String, String?>{
      'CONFIG_VERSION': '"2026-03-15"',
      '_GNU_SOURCE': null,
      'CONFIG_BIGNUM': null,
      'QUICKJS_WRAPPER_BUILD': null,
      if (Platform.isWindows) '__STDC_NO_ATOMICS__': '1',
    };

    final cBuilder = CBuilder.library(
      name: 'quickjs_wrapper',
      assetName: 'quickjs_wrapper.dart',
      sources: _quickJsSources,
      includes: _quickJsIncludes,
      defines: cDefines,
      flags: cFlags,
      libraries: cLibraries,
    );
    await cBuilder.run(
      input: effectiveInput,
      output: output,
      logger: Logger('')
        ..level = Level.ALL
        // ignore: avoid_print
        ..onRecord.listen((record) => print(record.message)),
    );
  });
}

Future<BuildInput> _withWindowsMsvcWorkaround(BuildInput input) async {
  if (!_needsWindowsCompilerWorkaround(input)) {
    return input;
  }

  final tools = await _findMsvcTools(input.packageRoot);
  if (tools == null) {
    return input;
  }

  // Work around Windows shell invocation splitting unquoted paths with spaces.
  final copiedJson = _cloneInputJson(input);
  final codeAssets = _codeAssetsConfig(copiedJson);
  if (codeAssets == null) {
    return input;
  }

  codeAssets['c_compiler'] = <String, Object?>{
    'cc': tools.compilerPath,
    'ar': tools.archiverPath,
    'ld': tools.linkerPath,
    'windows': <String, Object?>{
      'developer_command_prompt': <String, Object?>{
        'script': tools.vcvarsPath,
        'arguments': <String>[],
      },
    },
  };

  return BuildInput(copiedJson);
}

bool _needsWindowsCompilerWorkaround(BuildInput input) {
  // Always use the Windows workaround so compiler tools are invoked via a
  // no-space junction path. This avoids shell parsing failures in hooks.
  return Platform.isWindows && input.config.code.targetOS == OS.windows;
}

Map<String, Object?> _cloneInputJson(BuildInput input) {
  return jsonDecode(jsonEncode(input.json)) as Map<String, Object?>;
}

Map<String, Object?>? _codeAssetsConfig(Map<String, Object?> inputJson) {
  final config = inputJson['config'] as Map<String, Object?>?;
  if (config == null) {
    return null;
  }
  final extensions =
      (config['extensions'] as Map<String, Object?>?) ?? <String, Object?>{};
  config['extensions'] = extensions;
  return extensions['code_assets'] as Map<String, Object?>?;
}

Future<_MsvcTools?> _findMsvcTools(Uri packageRoot) async {
  for (final install in _vsInstallRoots) {
    final vcvars = File('$install\\VC\\Auxiliary\\Build\\vcvars64.bat');
    final msvcRoot = Directory('$install\\VC\\Tools\\MSVC');
    if (!vcvars.existsSync() || !msvcRoot.existsSync()) {
      continue;
    }

    final versions = msvcRoot.listSync().whereType<Directory>().toList()
      ..sort((a, b) => b.path.compareTo(a.path));

    for (final versionDir in versions) {
      final binDir = '${versionDir.path}\\bin\\Hostx64\\x64';
      final cl = File('$binDir\\cl.exe');
      final lib = File('$binDir\\lib.exe');
      final link = File('$binDir\\link.exe');
      if (!cl.existsSync() || !lib.existsSync() || !link.existsSync()) {
        continue;
      }

      final shimBinDir = await _ensureMsvcBinJunction(packageRoot, binDir);

      return _MsvcTools(
        compilerPath: '$shimBinDir\\cl.exe',
        archiverPath: '$shimBinDir\\lib.exe',
        linkerPath: '$shimBinDir\\link.exe',
        vcvarsPath: vcvars.path,
      );
    }
  }

  return null;
}

Future<String> _ensureMsvcBinJunction(
  Uri packageRoot,
  String sourceBinDir,
) async {
  final shimRoot = Directory.fromUri(
    packageRoot.resolve('.dart_tool/msvc_shims/'),
  );
  if (!shimRoot.existsSync()) {
    shimRoot.createSync(recursive: true);
  }

  final junctionPath = '${shimRoot.path}\\bin';
  final junctionDir = Directory(junctionPath);
  if (junctionDir.existsSync()) {
    return junctionPath;
  }

  final result = await Process.run('cmd', <String>[
    '/c',
    'mklink',
    '/J',
    junctionPath,
    sourceBinDir,
  ]);
  if (result.exitCode != 0) {
    return sourceBinDir;
  }
  return junctionPath;
}

final class _MsvcTools {
  final String compilerPath;
  final String archiverPath;
  final String linkerPath;
  final String vcvarsPath;

  _MsvcTools({
    required this.compilerPath,
    required this.archiverPath,
    required this.linkerPath,
    required this.vcvarsPath,
  });
}
