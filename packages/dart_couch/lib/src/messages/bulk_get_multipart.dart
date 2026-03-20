/// Metadata and binary data for one attachment in a multipart result.
///
/// [data] always yields the **decompressed** original content regardless of
/// whether CouchDB stored the attachment in compressed form.
///
/// **Digest note**: [digest] is CouchDB's stored digest — for content types
/// that CouchDB compresses (`text/*, application/json`, etc.) this is the MD5
/// of the *compressed* bytes, not of the bytes in [data]. The mismatch is
/// intentional: replication compares digests with CouchDB, and both sides use
/// the same compressed-bytes digest, so no spurious re-transfers occur.
class BulkGetMultipartAttachment {
  /// CouchDB content-type, e.g. `image/png`.
  final String contentType;

  /// CouchDB-format digest, e.g. `md5-<base64>`.
  ///
  /// For compressible content types this is MD5 of the **compressed** bytes as
  /// stored by CouchDB, not of the decompressed bytes in [data].
  final String digest;

  /// Byte count of the **decompressed** content in [data].
  final int length;

  /// Revision position at which this attachment was introduced.
  final int revpos;

  /// Decompressed attachment bytes. MIME-level `Content-Encoding: gzip` is
  /// handled transparently by [HttpDartCouchDb.bulkGetMultipart]; callers always
  /// receive the original uncompressed content.
  final Stream<List<int>> data;

  /// Content-encoding that CouchDB applied before storing the attachment,
  /// e.g. `'gzip'`. `null` for uncompressed or locally-created attachments.
  ///
  /// When non-null, [digest] is MD5 of the **compressed** bytes (as CouchDB
  /// stored them), while [data] and [length] reflect the decompressed content.
  final String? encoding;

  const BulkGetMultipartAttachment({
    required this.contentType,
    required this.digest,
    required this.length,
    required this.revpos,
    required this.data,
    this.encoding,
  });
}

/// A successfully fetched document with its attachment streams.
///
/// [doc] is the document map WITHOUT inline attachment data — the
/// `_attachments` field contains stubs (digest, length, revpos) only.
/// Binary data is in [attachments].
class BulkGetMultipartOk {
  /// Document map with attachment stubs (no inline `data` fields).
  final Map<String, dynamic> doc;

  /// Maps attachment name → metadata + byte stream.
  /// Only attachments that are being transferred are included; attachments
  /// already present on the target (atts_since optimisation) are omitted.
  final Map<String, BulkGetMultipartAttachment> attachments;

  const BulkGetMultipartOk({required this.doc, required this.attachments});
}

/// Result for one doc/rev combination in a [bulkGetMultipart] stream.
sealed class BulkGetMultipartResult {
  const BulkGetMultipartResult();
}

/// Successful result containing the document and its attachment streams.
class BulkGetMultipartSuccess extends BulkGetMultipartResult {
  final BulkGetMultipartOk ok;
  const BulkGetMultipartSuccess(this.ok);
}

/// Error result for one doc/rev — the document could not be fetched.
class BulkGetMultipartFailure extends BulkGetMultipartResult {
  final String id;
  final String? rev;
  final String error;
  final String reason;

  const BulkGetMultipartFailure({
    required this.id,
    this.rev,
    required this.error,
    required this.reason,
  });
}
