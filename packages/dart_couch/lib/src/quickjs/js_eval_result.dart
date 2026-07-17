/// Result of evaluating JavaScript code.
class JsEvalResult {
  /// The string representation of the result.
  final String stringResult;

  /// Non-null on errors (contains the error message).
  final dynamic rawResult;

  /// Whether the evaluation resulted in an error.
  final bool isError;

  JsEvalResult({
    required this.stringResult,
    this.rawResult,
    required this.isError,
  });
}
