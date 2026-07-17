import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'js_eval_result.dart';
import 'quickjs_bindings.dart' as bindings;

/// A lightweight JavaScript engine backed by QuickJS (native platforms).
///
/// Usage matches the flutter_js API pattern:
/// ```dart
/// final engine = JsEngine();
/// engine.evaluate('var x = 1 + 2;');
/// final result = engine.evaluate('JSON.stringify(x)');
/// print(result.stringResult); // "3"
/// engine.dispose();
/// ```
class JsEngine {
  final Pointer<Void> _engine;

  JsEngine() : _engine = bindings.qjsNew() {
    if (_engine == nullptr) {
      throw StateError('Failed to create QuickJS engine');
    }
  }

  /// Evaluate JavaScript code and return the result.
  JsEvalResult evaluate(String code) {
    final codeUtf8 = code.toNativeUtf8();
    final codeLen = utf8.encode(code).length;
    final outValue = calloc<Pointer<Char>>();
    final outError = calloc<Pointer<Char>>();

    try {
      final rc = bindings.qjsEval(
        _engine,
        codeUtf8.cast<Char>(),
        codeLen,
        outValue,
        outError,
      );

      if (rc != 0) {
        final errorMsg = outError.value != nullptr
            ? outError.value.cast<Utf8>().toDartString()
            : 'Unknown error';
        _freeIfNotNull(outError.value);
        _freeIfNotNull(outValue.value);
        return JsEvalResult(
          stringResult: errorMsg,
          rawResult: errorMsg,
          isError: true,
        );
      }

      final value = outValue.value != nullptr
          ? outValue.value.cast<Utf8>().toDartString()
          : '';
      _freeIfNotNull(outValue.value);
      _freeIfNotNull(outError.value);
      return JsEvalResult(
        stringResult: value,
        rawResult: null,
        isError: false,
      );
    } finally {
      calloc.free(outValue);
      calloc.free(outError);
      malloc.free(codeUtf8);
    }
  }

  static void _freeIfNotNull(Pointer<Char> ptr) {
    if (ptr != nullptr) malloc.free(ptr);
  }

  /// Dispose the engine and free all associated resources.
  void dispose() {
    bindings.qjsDispose(_engine);
  }
}
