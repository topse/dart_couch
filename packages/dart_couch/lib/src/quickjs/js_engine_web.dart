import 'dart:js_interop';

import 'js_eval_result.dart';

/// JavaScript engine for web platforms.
///
/// Uses the browser's native JavaScript engine via [dart:js_interop].
/// State persists between [evaluate] calls because [eval] executes at
/// global scope — `var` declarations and assignments survive across calls,
/// matching QuickJS behaviour.
class JsEngine {
  JsEngine();

  /// Evaluate JavaScript code and return the result.
  JsEvalResult evaluate(String code) {
    try {
      final result = _jsEval(code.toJS);
      // Convert JS value to string matching QuickJS conventions:
      // null/undefined → 'null'/'undefined', objects → their String() form.
      final str = _jsString(result).toDart;

      return JsEvalResult(
        stringResult: str,
        rawResult: null,
        isError: false,
      );
    } catch (e) {
      return JsEvalResult(
        stringResult: e.toString(),
        rawResult: e.toString(),
        isError: true,
      );
    }
  }

  /// Dispose the engine. No-op on web.
  void dispose() {}
}

@JS('eval')
external JSAny? _jsEval(JSString code);

/// JavaScript's `String()` function — converts any value (including null and
/// undefined) to its string representation, matching QuickJS's `JS_ToCString`.
@JS('String')
external JSString _jsString(JSAny? value);
