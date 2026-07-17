/// FFI bindings for the quickjs_wrapper C library.
///
/// Uses @Native annotations with @DefaultAsset to bind to the
/// shared library compiled by hook/build.dart.
@DefaultAsset('package:dart_couch/quickjs_wrapper.dart')
library;

import 'dart:ffi';

// QjsEngine *qjs_new(void);
@Native<Pointer<Void> Function()>(symbol: 'qjs_new')
external Pointer<Void> qjsNew();

// int qjs_eval(QjsEngine *engine, const char *code, size_t code_len,
//              char **out_value, char **out_error);
@Native<Int Function(Pointer<Void>, Pointer<Char>, Size, Pointer<Pointer<Char>>, Pointer<Pointer<Char>>)>(symbol: 'qjs_eval')
external int qjsEval(
  Pointer<Void> engine,
  Pointer<Char> code,
  int codeLen,
  Pointer<Pointer<Char>> outValue,
  Pointer<Pointer<Char>> outError,
);

// void qjs_dispose(QjsEngine *engine);
@Native<Void Function(Pointer<Void>)>(symbol: 'qjs_dispose')
external void qjsDispose(Pointer<Void> engine);
