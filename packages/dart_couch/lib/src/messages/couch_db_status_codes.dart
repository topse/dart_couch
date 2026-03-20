import 'package:http/http.dart' as http;

enum CouchDbStatusCodes {
  ok(200),
  created(201),
  accepted(202),
  notModified(304),
  badRequest(400),
  unauthorized(401),
  forbidden(403),
  notFound(404),
  notAllowed(405),
  conflict(409),
  preconditionFailed(412),
  requestEntitiyTooLarge(413),
  unsupportedMediaType(415),
  requestRangeNotSatisfiable(416),
  expectationFailed(417),
  internalServerError(500),
  serviceUnavailable(503);

  final int code;
  const CouchDbStatusCodes(this.code);

  static CouchDbStatusCodes fromCode(int code) {
    return CouchDbStatusCodes.values.firstWhere(
      (e) => e.code == code,
      orElse: () => throw Exception('Unknown status code: $code'),
    );
  }

  @override
  String toString() {
    return '$code $name';
  }
}

class CouchDbException implements Exception {
  final CouchDbStatusCodes statusCode;
  final String message;
  final String? message2;

  CouchDbException(this.statusCode, this.message, [this.message2]);

  factory CouchDbException.fromResponse(http.Response response) {
    final statusCode = CouchDbStatusCodes.fromCode(response.statusCode);
    return CouchDbException(
      statusCode,
      'CouchDB Error',
      response.body.toString(),
    );
  }

  factory CouchDbException.conflictPut(String docid, [String? message2]) {
    return CouchDbException(
      CouchDbStatusCodes.conflict,
      'Document with the specified ID $docid already exists or specified revision is not latest for target document',
      message2,
    );
  }

  factory CouchDbException.conflictPost(String docid) {
    return CouchDbException(
      CouchDbStatusCodes.conflict,
      'A Conflicting Document with same ID $docid already exists',
    );
  }

  factory CouchDbException.conflictRemove(String docid, String rev) {
    return CouchDbException(
      CouchDbStatusCodes.conflict,
      'Specified revision is not the latest for target document $docid - $rev',
    );
  }

  factory CouchDbException.conflictRemoveAttachment(
    String docid,
    String attachmentName,
  ) {
    return CouchDbException(
      CouchDbStatusCodes.conflict,
      'Specified revision is not the latest for target document $docid - $attachmentName',
    );
  }

  factory CouchDbException.badRequest(String jsonBody) {
    return CouchDbException(
      CouchDbStatusCodes.badRequest,
      "Invalid request body or parameters: $jsonBody",
    );
  }

  factory CouchDbException.badRequestAttachmentName(String attachmentName) {
    return CouchDbException(
      CouchDbStatusCodes.badRequest,
      "Attachment name '$attachmentName' can't start with '_'",
    );
  }

  factory CouchDbException.docValidation(String fieldName) {
    return CouchDbException(
      CouchDbStatusCodes.badRequest,
      "Bad special document member: $fieldName",
    );
  }

  factory CouchDbException.notFound(String docid) {
    return CouchDbException(
      CouchDbStatusCodes.notFound,
      "Invalid request body or parameters: $docid",
    );
  }

  factory CouchDbException.attachmentNotFound() {
    return CouchDbException(
      CouchDbStatusCodes.notFound,
      "Specified database, document or attachment was not found",
    );
  }

  factory CouchDbException.notFoundDeleteDb(String dbname) {
    return CouchDbException(
      CouchDbStatusCodes.notFound,
      "Database doesn’t exist or invalid database name $dbname",
    );
  }

  factory CouchDbException.preconditionFailed(String dbname) {
    return CouchDbException(
      CouchDbStatusCodes.preconditionFailed,
      "IDatabase already exists: $dbname",
    );
  }

  @override
  String toString() {
    return 'CouchDbException: ${statusCode.code} (${statusCode.toString()}) :$message';
  }
}
