import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../messages/couch_document_base.dart';
import 'term_to_binary.dart';

/// Simulate CouchDB-style _rev generation
/// doc has to be a "cloned" map -- it will be altered here!!!
/// Approximates CouchDB's revision hash logic in Dart.
/// Not bit-for-bit identical to CouchDB, but structurally close.
/// couch_util:md5(term_to_binary([Deleted, OldStart, OldRev, Body, Atts2]))
/// https://www.erlang.org/doc/apps/erts/erl_ext_dist.html
String calculateCouchDbNewRev(Map<String, dynamic> doc, String? previousRev) {
  // Check if this is a local document (format: 0-N)
  // Local documents use simplified revisions and shouldn't go through hash calculation
  if (previousRev != null && previousRev.startsWith('0-')) {
    // This is a local document - use simplified revision format
    final parts = previousRev.split('-');
    if (parts.length == 2 && int.tryParse(parts[1]) != null) {
      final nextVersion = int.parse(parts[1]) + 1;
      return '0-$nextVersion';
    }
  }

  // Parse generation from previousRev, or start at 0
  bool isDeleted = doc.keys.contains('_deleted') ? doc['_deleted'] : false;

  int oldStart = 0;
  if (previousRev != null && previousRev.contains('-')) {
    oldStart = int.tryParse(previousRev.split('-')[0]) ?? 0;
  }

  // Clean document (remove _rev, _revisions)
  Map<String, dynamic> body = Map<String, dynamic>.from(doc)
    ..remove('_id')
    ..remove('_rev')
    //..remove('_deleted')
    ..remove('_revisions')
    ..remove('_revs_info');

  assert(body.containsKey('_deleted') == false || body['_deleted'] == true);
  if (body.containsKey('_deleted') && body['_deleted'] == true) {
    // In case we have a deleted document, the body must be empty
    body = {};
  }

  // Extract and normalize attachments (if any)
  List<Set> atts2 = [];
  if (body.containsKey('_attachments')) {
    final rawAtts = Map<String, dynamic>.from(body['_attachments']);

    for (final key in rawAtts.keys) {
      final meta = rawAtts[key] as Map<String, dynamic>;
      final Uint8List digestBytes;
      if (meta['digest'] != null) {
        digestBytes = AttachmentInfo.calculateCouchDbAttachmentDigestFromString(
          meta['digest'] as String,
        );
      } else if (meta['data'] != null) {
        // Inline attachment: compute digest from the base64 payload
        final raw = base64Decode(meta['data'] as String);
        final digestStr = AttachmentInfo.calculateCouchDbAttachmentDigest(
          Uint8List.fromList(raw),
        );
        digestBytes = AttachmentInfo.calculateCouchDbAttachmentDigestFromString(
          digestStr,
        );
      } else {
        continue; // stub without digest – nothing to hash
      }
      atts2.add({key, meta['content_type'], digestBytes});
    }
    body.remove('_attachments');
  }

  final composite = [
    isDeleted,
    oldStart,
    previousRev != null ? getHashBytesFromRev(previousRev) : 0,
    body,
    atts2,
  ];

  final binary = termToBinary(composite);

  final hash = md5.convert(binary).toString();
  final newGen = oldStart + 1;

  return '$newGen-$hash';
}

Uint8List getHashBytesFromRev(String rev) {
  var parts = rev.split('-');
  if (parts.length != 2) {
    throw Exception('Invalid _rev format: $rev');
  }

  String hexHash = parts[1];

  // Step 2: Convert hex string to bytes
  Uint8List md5Bytes = Uint8List(16);

  for (int i = 0; i < hexHash.length; i += 2) {
    String byteStr = hexHash.substring(i, i + 2);
    int byte = int.parse(byteStr, radix: 16);
    md5Bytes[(i / 2).toInt()] = byte;
  }
  return md5Bytes;
}
