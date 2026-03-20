import 'messages/couch_db_status_codes.dart';

/// Base class for domain-specific failures. Prefer returning/propagating these
/// instead of raw SDK exceptions at API boundaries.
abstract class DartCouchFailure implements Exception {
  final String message;
  final StackTrace? stackTrace;
  DartCouchFailure(this.message, [this.stackTrace]);

  @override
  String toString() => '$runtimeType: $message';
}

class NetworkFailure extends DartCouchFailure {
  final Object? cause;
  NetworkFailure(String message, {this.cause, StackTrace? stackTrace})
    : super(message, stackTrace);
}

class HttpFailure extends DartCouchFailure {
  final CouchDbStatusCodes status;
  final String body;
  HttpFailure(this.status, this.body, {StackTrace? stackTrace})
    : super('${status.code} ${status.name}: $body', stackTrace);
}

class UnknownFailure extends DartCouchFailure {
  final Object cause;
  UnknownFailure(this.cause, {StackTrace? stackTrace})
    : super(cause.toString(), stackTrace);
}

/// Minimal Result type for non-throwing API wrappers.
abstract class ApiResult<T> {
  const ApiResult();

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  T get value => (this as Ok<T>).value;
  DartCouchFailure get error => (this as Err<T>).error;
}

class Ok<T> extends ApiResult<T> {
  @override
  final T value;
  const Ok(this.value);
}

class Err<T> extends ApiResult<T> {
  @override
  final DartCouchFailure error; // typically a DartCouchFailure
  const Err(this.error);
}
