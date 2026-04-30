import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'platform/gzip_decode.dart';

import 'value_notifier.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';

import 'dart_couch_connection_state.dart';
import 'dart_couch_db.dart';
import 'http_dart_couch_server.dart';
import 'http_methods.dart';
import 'messages/bulk_docs_result.dart';
import 'messages/bulk_get.dart';
import 'messages/bulk_get_multipart.dart';
import 'messages/index_result.dart';
import 'messages/view_result.dart';
import 'messages/couch_db_status_codes.dart';
import 'messages/couch_document_base.dart';
import 'messages/database_info.dart';
import 'messages/revs_diff_result.dart';
import 'replication_mixin.dart';

final Logger _log = Logger("dart_couch-HttpDartCouchDb");

class HttpDartCouchDb extends DartCouchDb
    with CouchReplicationMixin, HttpMethods {
  @override
  String? get authCookie => parentServer.authCookie;
  @override
  String? get username => parentServer.username;
  @override
  String? get password => parentServer.password;
  @override
  Uri? uri;

  HttpDartCouchServer parentServer;
  @override
  DcValueNotifier<DartCouchConnectionState> get connectionState =>
      parentServer.connectionState;

  bool checkRevsAlgorithmForDebugging = false;

  HttpDartCouchDb({
    required this.parentServer,
    required this.uri,
    required super.dbname,
  });

  @override
  Future<List<BulkDocsResult>> bulkDocsRaw(
    List<String> docs, {
    bool newEdits = true,
  }) async {
    List<Map<String, dynamic>> encodedDocs = docs.map((docJson) {
      final map = jsonDecode(docJson) as Map<String, dynamic>;

      // For replication mode, we may need to preserve _revisions and _revs_info
      // They should already be in the JSON if they were provided
      return map;
    }).toList();

    final payload = {'docs': encodedDocs, 'new_edits': newEdits};

    final response = await httpPost(
      '$dbname/_bulk_docs',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode != CouchDbStatusCodes.created.code &&
        response.statusCode != CouchDbStatusCodes.ok.code) {
      throw CouchDbException(
        CouchDbStatusCodes.fromCode(response.statusCode),
        response.body,
      );
    }

    final List<dynamic> results = jsonDecode(response.body);
    return results.map((r) {
      return BulkDocsResult.fromMap(r);
    }).toList();
  }

  /// fetch a document by its id as raw JSON string
  @override
  Future<Map<String, dynamic>?> getRaw(
    String docid, {
    String? rev,
    bool revs = false,
    bool revsInfo = false,
    bool attachments = false,
  }) async {
    http.Response res = await httpGet(
      "$dbname/$docid",
      queryParameters: {
        'rev': ?rev,
        if (revs == true) 'revs': 'true',
        if (revsInfo == true) 'revs_info': 'true',
        if (attachments == true) 'attachments': 'true',
      },
    );
    if (res.statusCode == CouchDbStatusCodes.notFound.code) {
      return null;
    } else if (res.statusCode != CouchDbStatusCodes.ok.code) {
      throw Exception('Failed to load document $docid: ${res.body}');
    }

    final contentType = res.headers['content-type'] ?? '';

    if (contentType.startsWith("application/json")) {
      return jsonDecode(res.body);
    } else if (contentType.startsWith('multipart/related')) {
      // CouchDB returns multipart/related when attachments=true and the
      // document has attachments. First part is the JSON doc with
      // "follows":true stubs, subsequent parts are the attachment data.
      final boundaryMatch = RegExp('boundary="(.+)"').firstMatch(contentType);
      if (boundaryMatch == null) {
        throw Exception("Missing boundary in multipart/related response");
      }
      final boundary = boundaryMatch.group(1)!;

      List<int> bytes = List.from(res.bodyBytes);
      if (bytes.length >= 2 &&
          (bytes[bytes.length - 2] != 13 || bytes[bytes.length - 1] != 10)) {
        bytes.add(13);
        bytes.add(10);
      }

      final partsStream = MimeMultipartTransformer(
        boundary,
      ).bind(Stream.fromIterable([bytes]));

      Map<String, dynamic>? docMap;
      final attachmentDataQueue = <Uint8List>[];

      await for (MimeMultipart part in partsStream) {
        final partContentType = part.headers['content-type'] ?? '';
        final partBytes = await part.fold<List<int>>(
          [],
          (prev, chunk) => prev..addAll(chunk),
        );

        if (partContentType.startsWith('application/json')) {
          docMap = jsonDecode(utf8.decode(partBytes));
        } else {
          attachmentDataQueue.add(Uint8List.fromList(partBytes));
        }
      }

      if (docMap == null) {
        throw Exception("No JSON document found in multipart/related response");
      }

      // Replace "follows":true stubs with inline base64 data
      final attachments = docMap['_attachments'] as Map<String, dynamic>?;
      if (attachments != null) {
        int dataIndex = 0;
        for (final entry in attachments.entries) {
          final stub = entry.value as Map<String, dynamic>;
          if (stub['follows'] == true &&
              dataIndex < attachmentDataQueue.length) {
            stub.remove('follows');
            stub.remove('length');
            stub['data'] = base64Encode(attachmentDataQueue[dataIndex]);
            dataIndex++;
          }
        }
      }

      return docMap;
    } else {
      _log.severe(res);
      throw Exception("Problem with result: $res");
    }
  }

  @override
  Future<List<OpenRevsResult>?> getOpenRevs(
    String docid, {
    List<String>? revisions,
    bool revs = false,
  }) async {
    String openrevs = "all";
    if (revisions != null && revisions.isNotEmpty) {
      openrevs = "[";
      for (int i = 0; i < revisions.length; ++i) {
        if (i > 0) openrevs += ",";
        openrevs += '"${revisions[i]}"';
      }
      openrevs += "]";
    }

    http.Response res = await httpGet(
      "$dbname/$docid",
      queryParameters: {
        if (revs == true) 'revs': 'true',
        'open_revs': openrevs,
      },
    );
    if (res.statusCode == CouchDbStatusCodes.notFound.code) {
      return null;
    } else if (res.statusCode != CouchDbStatusCodes.ok.code) {
      throw Exception('Failed to load document $docid: ${res.body}');
    }

    if (res.headers['content-type']!.startsWith('multipart/mixed')) {
      // this happens when openRefs=all for example

      // Generate REGEX to get boundary from content-type header
      RegExp boundaryget = RegExp('boundary="(.+)"');
      String contentType = res.headers["content-type"].toString();

      // Get the boundary
      final match = boundaryget.firstMatch(contentType);
      String boundary = match?.group(1) as String;

      // Mime expects multipart body to have a CRLF after the --boundary--
      List<int> bytes = List.from(res.bodyBytes);
      if (bytes[bytes.length - 2] != 13 || bytes[bytes.length - 1] != 10) {
        bytes.add(13);
        bytes.add(10);
      }

      // Parse parts with MimeMultipartTransformer
      final partsStream = MimeMultipartTransformer(
        boundary,
      ).bind(Stream.fromIterable([bytes]));

      List<Map<String, String>> headers = [];
      List<String> content = [];

      await for (MimeMultipart part in partsStream) {
        final h = part.headers;
        final c = await utf8.decoder.bind(part).join();
        assert(
          h.keys.contains('content-type') &&
              h['content-type']!.startsWith("application/json"),
        );
        headers.add(h);
        content.add(c);
      }

      List<OpenRevsResult> results = content.map((e) {
        Map<String, dynamic> m = jsonDecode(e);
        if (m.keys.contains('missing')) {
          return OpenRevsResult(
            missingRev: m['missing'],
            state: OpenRevsState.missing,
            doc: null,
          );
        } else {
          return OpenRevsResult(
            missingRev: null,
            state: OpenRevsState.ok,
            doc: CouchDocumentBase.fromJson(e),
          );
        }
      }).toList();

      return results;
    } else {
      _log.severe(res);
      throw Exception("Problem with result: $res");
    }
  }

  @override
  Future<ViewResult?> query(
    String viewPathShort, {

    bool includeDocs = false,
    bool attachments = false,
    bool attEncodingInfo = false,
    bool conflicts = false,

    String? startkey,
    String? startkeyDocid,
    String? endkey,
    String? endkeyDocid,
    String? key,
    List<String>? keys,

    bool inclusiveEnd = true,

    bool group = false,
    int? groupLevel,

    bool reduce = true,

    int? limit,
    int? skip,
    bool descending = false,
    bool sorted = true,

    bool stable = false,
    UpdateMode updateMode = UpdateMode.modeTrue,
    bool updateSeq = false,
  }) {
    List<String> splitted = viewPathShort.split("/");
    assert(splitted.length == 2);

    String designDocName = splitted[0];
    String viewName = splitted[1];

    return _queryImpl(
      viewPathComplete: "$dbname/_design/$designDocName/_view/$viewName",
      includeDocs: includeDocs,
      attachments: attachments,
      attEncodingInfo: attEncodingInfo,
      conflicts: conflicts,
      startkey: startkey,
      startkeyDocid: startkeyDocid,
      endkey: endkey,
      endkeyDocid: endkeyDocid,
      key: key,
      keys: keys,
      inclusiveEnd: inclusiveEnd,
      group: group,
      groupLevel: groupLevel,
      reduce: reduce,
      limit: limit,
      skip: skip,
      descending: descending,
      sorted: sorted,
      stable: stable,
      updateMode: updateMode,
      updateSeq: updateSeq,
    );
  }

  Future<ViewResult?> _queryImpl({
    required String viewPathComplete,
    bool includeDocs = false,
    bool attachments = false,
    bool attEncodingInfo = false,
    bool conflicts = false,
    String? startkey,
    String? startkeyDocid,
    String? endkey,
    String? endkeyDocid,
    String? key,
    List<String>? keys,
    bool inclusiveEnd = true,
    bool group = false,
    int? groupLevel,
    bool reduce = true,
    int? limit,
    int? skip,
    bool descending = false,
    bool sorted = true,
    bool stable = false,
    UpdateMode updateMode = UpdateMode.modeTrue,
    bool updateSeq = false,
  }) async {
    final queryParameters = <String, dynamic>{
      if (includeDocs == true) 'include_docs': 'true',
      if (includeDocs == true && attachments == true) 'attachments': 'true',
      if (includeDocs == true && attEncodingInfo == true)
        'att_encoding_info': 'true',
      if (includeDocs == true && conflicts == true) 'conflicts': 'true',
      if (startkey != null) 'startkey': _encodeJsonQueryValue(startkey),
      'startkey_docid': ?startkeyDocid,
      if (endkey != null) 'endkey': _encodeJsonQueryValue(endkey),
      'endkey_docid': ?endkeyDocid,
      if (key != null) 'key': _encodeJsonQueryValue(key),
      'inclusive_end': inclusiveEnd == true ? 'true' : 'false',
      if (reduce == false) 'reduce': 'false',
      if (reduce == true && group == true) 'group': 'true',
      if (reduce == true && group == true && groupLevel != null)
        'group_level': '$groupLevel',
      if (limit != null) 'limit': '$limit',
      if (skip != null) 'skip': '$skip',
      'descending': descending == true ? 'true' : 'false',
      if (sorted == false) 'sorted': 'false',
      if (stable == true) 'stable': 'true',
      if (updateMode != UpdateMode.modeTrue) 'update': updateMode.value,
      if (updateSeq == true) 'update_seq': 'true',
    };

    http.Response res;
    final hasKeys = keys != null && keys.isNotEmpty;
    if (hasKeys) {
      res = await httpPost(
        viewPathComplete,
        queryParameters: queryParameters,
        body: jsonEncode({
          'keys': keys.map((k) {
            try {
              return jsonDecode(k);
            } catch (_) {
              return k;
            }
          }).toList(),
        }),
      );
    } else {
      res = await httpGet(viewPathComplete, queryParameters: queryParameters);
    }

    if (res.statusCode == CouchDbStatusCodes.notFound.code) {
      return null;
    } else if (res.statusCode != CouchDbStatusCodes.ok.code) {
      throw CouchDbException(
        CouchDbStatusCodes.fromCode(res.statusCode),
        res.body,
      );
    }

    return ViewResult.fromJson(res.body);
  }

  String _encodeJsonQueryValue(String value) {
    try {
      jsonDecode(value);
      return value;
    } catch (_) {
      return jsonEncode(value);
    }
  }

  @override
  Future<Uint8List?> getAttachment(
    String docId,
    String attachmentName, {
    String? rev,
  }) async {
    final response = await httpGet(
      '$dbname/$docId/$attachmentName',
      queryParameters: {'rev': ?rev},
    );

    if (response.statusCode == CouchDbStatusCodes.ok.code) {
      return response.bodyBytes;
    } else if (response.statusCode != CouchDbStatusCodes.notFound.code) {
      throw CouchDbException(
        CouchDbStatusCodes.fromCode(response.statusCode),
        response.body,
      );
    }
    return null;
  }

  @override
  Future<String?> getAttachmentAsReadonlyFile(
    String docId,
    String attachmentName,
  ) {
    throw UnimplementedError(
      'getAttachmentAsReadonlyFile is not supported for HttpDartCouchDb. '
      'Use getAttachment() to load attachment bytes instead.',
    );
  }

  @override
  Future<String> saveAttachment(
    String docId,
    String rev,
    String attachmentName,
    Uint8List data, {
    String contentType = 'application/octet-stream',
  }) async {
    final response = await httpPut(
      '$dbname/$docId/$attachmentName',
      headers: {'If-Match': rev, 'Content-Type': contentType},
      body: data,
    );

    if (response.statusCode != CouchDbStatusCodes.created.code) {
      throw CouchDbException.fromResponse(response);
    }
    return jsonDecode(response.body)['rev'];
  }

  @override
  Future<String> deleteAttachment(
    String docId,
    String rev,
    String attachmentName,
  ) async {
    final response = await httpDelete(
      '$dbname/$docId/$attachmentName',
      headers: {'If-Match': rev},
    );

    if (response.statusCode != CouchDbStatusCodes.ok.code) {
      throw Exception(
        'Failed to delete attachment $attachmentName: ${response.body}',
      );
    }
    return jsonDecode(response.body)['rev'] as String;
  }

  @override
  Future<Map<String, dynamic>> putRaw(Map<String, dynamic> doc) async {
    final docId = doc['_id'] as String?;

    if (docId == null) {
      throw Exception('Document ID is required for PUT operation');
    }

    final response = await httpPut('$dbname/$docId', body: jsonEncode(doc));

    if (response.statusCode != CouchDbStatusCodes.created.code &&
        response.statusCode != CouchDbStatusCodes.ok.code) {
      throw CouchDbException.fromResponse(response);
    }

    final decodedBody = jsonDecode(response.body);

    // Merge the response (_id, _rev) back into the original document
    doc['_id'] = decodedBody['id'];
    doc['_rev'] = decodedBody['rev'];

    return doc;
  }

  @override
  Future<Map<String, dynamic>> postRaw(Map<String, dynamic> doc) async {
    final response = await httpPost('$dbname/', body: jsonEncode(doc));

    if (response.statusCode != CouchDbStatusCodes.created.code) {
      throw Exception('Failed to create document: ${response.body}');
    }

    final decodedBody = jsonDecode(response.body);

    // Merge the response (_id, _rev) back into the original document
    doc['_id'] = decodedBody['id'];
    doc['_rev'] = decodedBody['rev'];

    return doc;
  }

  @override
  Future<String> remove(String docid, String rev) async {
    final res = await httpDelete("$dbname/$docid", headers: {"If-Match": rev});
    if (res.statusCode != CouchDbStatusCodes.ok.code) {
      throw CouchDbException(
        CouchDbStatusCodes.fromCode(res.statusCode),
        res.body,
      );
    }
    return jsonDecode(res.body)['rev'];
  }

  /// get database information
  @override
  Future<DatabaseInfo?> info() async {
    http.Response res = await httpGet(dbname);
    if (res.statusCode == CouchDbStatusCodes.notFound.code) {
      throw CouchDbException(
        CouchDbStatusCodes.notFound,
        'Database $dbname not found',
      );
    } else if (res.statusCode != CouchDbStatusCodes.ok.code) {
      throw CouchDbException(
        CouchDbStatusCodes.fromCode(res.statusCode),
        res.body,
      );
    }
    return DatabaseInfo.fromJson(res.body);
  }

  @override
  Stream<Map<String, dynamic>> changesRaw({
    List<String>? docIds,
    bool descending = false,
    FeedMode feedmode = FeedMode.normal,
    int heartbeat = 30000,
    bool includeDocs = false,
    bool attachments = false,
    bool attEncodingInfo = false,
    int? lastEventId,
    int limit = 0,
    String? since,
    bool styleAllDocs = false,
    int? timeout,
    int? seqInterval,
  }) {
    // check for unsupported settings
    assert(feedmode != FeedMode.eventsource);

    // Create a dedicated StreamController for this request
    StreamSubscription<String>? subscription;
    final controller = StreamController<Map<String, dynamic>>(
      onCancel: () async {
        // when there is no listeners anymore, the http
        // subscription needs to be canceled!
        await subscription?.cancel();
      },
    );

    unawaited(() async {
      // TODO: check exception handling
      try {
        _log.fine(
          'Requesting changes feed for $dbname with since parameter: ${since ?? "null"}',
        );
        final response = await httpGetStream(
          "$dbname/_changes",
          queryParameters: {
            if (docIds != null && docIds.isNotEmpty) 'filter': '_doc_ids',
            if (docIds != null && docIds.isNotEmpty)
              'doc_ids': jsonEncode(docIds),
            'descending': descending == true ? 'true' : 'false',
            'feed': feedmode.value,
            'heartbeat': '$heartbeat',
            if (includeDocs == true) 'include_docs': 'true',
            if (includeDocs == true && attachments == true)
              'attachments': 'true',
            if (includeDocs == true && attEncodingInfo == true)
              'att_encoding_info': 'true',
            if (lastEventId != null) 'last-event-id': '$lastEventId',
            if (limit > 0) 'limit': "$limit",
            'since': ?since,
            if (styleAllDocs == true) 'style': 'all_docs',
            if (timeout != null) 'timeout': '$timeout',
            if (seqInterval != null) 'seq_interval': "$seqInterval",
          },
        );

        if (response.statusCode != CouchDbStatusCodes.ok.code) {
          controller.addError(
            CouchDbException(
              CouchDbStatusCodes.fromCode(response.statusCode),
              (await http.Response.fromStream(response)).body,
            ),
          );
          await controller.close(); // Important to close when done
          return;
        }

        if (feedmode == FeedMode.normal || feedmode == FeedMode.longpoll) {
          // normal or longpoll feed -- just a single response
          final res = await http.Response.fromStream(response);
          final json = jsonDecode(res.body) as Map<String, dynamic>;
          assert(controller.hasListener);
          controller.add(json);
          await controller.close(); // Important to close when done
          return;
        } else {
          // continuous feed -- multiple responses
          subscription = response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen(
                (line) {
                  if (line.trim().isEmpty) {
                    _log.fine('[$dbname] changes feed heartbeat received');
                    return;
                  }
                  if (controller.isClosed) {
                    return;
                  }

                  // Parse JSON to check if it's a change entry (has 'id' field)
                  // or a status line (has 'last_seq' and 'pending' fields)
                  try {
                    final json = jsonDecode(line) as Map<String, dynamic>;

                    // Skip status/heartbeat lines (they have 'last_seq' but no 'id')
                    if (!json.containsKey('id')) {
                      _log.fine('[$dbname] changes feed status line: $line');
                      return;
                    }

                    controller.add(json);
                  } catch (e) {
                    // Invalid JSON or parse error - skip this line
                    _log.warning(
                      'Failed to parse changes line: $line, error: $e',
                    );
                  }
                },
                onDone: () async {
                  if (!controller.isClosed) await controller.close();
                },
                onError: (error, stack) async {
                  if (!controller.isClosed) {
                    controller.addError(error, stack);
                    await controller.close();
                  }
                },
              );
        }
      } catch (e, s) {
        controller.addError(e, s);
      }
    }());

    return controller.stream;
  }

  @override
  Future<ViewResult> allDocs({
    bool includeDocs = false,
    bool attachments = false,
    String? startkey,
    String? endkey,
    bool inclusiveEnd = true,
    int? limit,
    int? skip,
    bool descending = false,
    String? key,
    List<String>? keys,
  }) async {
    final http.Response res = await httpGet(
      "/$dbname/_all_docs",
      queryParameters: {
        "include_docs": includeDocs == true ? "true" : "false",
        "attachments": attachments == true ? "true" : "false",
        "startkey": ?startkey,
        "endkey": ?endkey,
        "inclusive_end": inclusiveEnd == true ? "true" : "false",
        "limit": ?limit,
        "skip": ?skip,
        "descending": descending == true ? "true" : "false",
        "key": ?key,
        if (keys != null) "keys": jsonEncode(keys),
      },
    );

    return ViewResult.fromJson(res.body);
  }

  @override
  Future<ViewResult> getLocalDocuments({
    bool conflicts = false,
    bool descending = false,
    String? endkey,
    String? endkeyDocid,
    bool includeDocs = false,
    bool inclusiveEnd = true,
    String? key,
    List<String>? keys,
    int? limit,
    int? skip,
    String? startkey,
    String? startkeyDocid,
    bool updateSeq = false,
  }) async {
    final http.Response res = await httpGet(
      "/$dbname/_local_docs",
      queryParameters: {
        if (conflicts) "conflicts": "true",
        if (descending) "descending": "true",
        if (endkey != null) "endkey": jsonEncode(endkey),
        "endkey_docid": ?endkeyDocid,
        if (includeDocs) "include_docs": "true",
        if (!inclusiveEnd) "inclusive_end": "false",
        if (key != null) "key": jsonEncode(key),
        if (keys != null) "keys": jsonEncode(keys),
        if (limit != null) "limit": limit.toString(),
        if (skip != null) "skip": skip.toString(),
        if (startkey != null) "startkey": jsonEncode(startkey),
        "startkey_docid": ?startkeyDocid,
        if (updateSeq) "update_seq": "true",
      },
    );

    if (res.statusCode != CouchDbStatusCodes.ok.code) {
      throw CouchDbException(
        CouchDbStatusCodes.fromCode(res.statusCode),
        'Failed to get local documents: ${res.body}',
      );
    }

    return ViewResult.fromJson(res.body);
  }

  @override
  Future<Map<String, RevsDiffEntry>> revsDiff(
    Map<String, List<String>> revs,
  ) async {
    final response = await httpPost(
      '$dbname/_revs_diff',
      body: jsonEncode(revs),
    );

    if (response.statusCode != CouchDbStatusCodes.ok.code) {
      throw CouchDbException(
        CouchDbStatusCodes.fromCode(response.statusCode),
        response.body,
      );
    }

    final Map<String, dynamic> json = jsonDecode(response.body);
    return json.map(
      (docId, diffMap) => MapEntry(
        docId,
        RevsDiffEntryMapper.fromMap(diffMap as Map<String, dynamic>),
      ),
    );
  }

  @override
  Future<bool?> isCompactionRunning() async {
    try {
      final i = await info();
      return i!.compactRunning;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> startCompaction() async {
    final res = await httpPost(
      '$dbname/_compact',
      headers: {'Content-Type': 'application/json'},
    );

    if (res.statusCode != CouchDbStatusCodes.accepted.code) {
      throw CouchDbException(
        CouchDbStatusCodes.fromCode(res.statusCode),
        res.body,
      );
    }
  }

  @override
  Future<bool> up() async {
    final response = await httpGet('_up');

    if (response.statusCode == CouchDbStatusCodes.ok.code) {
      return true;
    } else {
      return false;
    }
  }

  @override
  Future<String?> createIndex({
    required IndexDefinition index,
    String? ddoc,
    String? name,
    String type = 'json',
    bool? partitioned,
  }) async {
    final indexRequest = IndexRequest(
      ddoc: ddoc,
      name: name ?? '',
      type: type,
      partitioned: partitioned,
      index: index,
    );

    final res = await httpPost('$dbname/_index', body: indexRequest.toJson());

    if (res.statusCode != CouchDbStatusCodes.ok.code &&
        res.statusCode != CouchDbStatusCodes.created.code) {
      throw CouchDbException(
        CouchDbStatusCodes.fromCode(res.statusCode),
        res.body,
      );
    }

    final responseData = jsonDecode(res.body) as Map<String, dynamic>;
    return responseData['name'] as String?;
  }

  @override
  Future<bool> deleteIndex({
    required String designDoc,
    required String name,
    String type = 'json',
  }) async {
    // Strip _design/ prefix if present
    final ddocName = designDoc.startsWith('_design/')
        ? designDoc.substring(8)
        : designDoc;

    final res = await httpDelete(
      '$dbname/_index/_design/$ddocName/$type/$name',
    );

    if (res.statusCode == CouchDbStatusCodes.ok.code) {
      final responseData = jsonDecode(res.body) as Map<String, dynamic>;
      return responseData['ok'] == true;
    } else if (res.statusCode == CouchDbStatusCodes.notFound.code) {
      throw CouchDbException(
        CouchDbStatusCodes.notFound,
        'Index not found: $name',
      );
    } else {
      throw CouchDbException(
        CouchDbStatusCodes.fromCode(res.statusCode),
        res.body,
      );
    }
  }

  @override
  Future<IndexResultList> getIndexes() async {
    final res = await httpGet('$dbname/_index');

    if (res.statusCode != CouchDbStatusCodes.ok.code) {
      throw CouchDbException(
        CouchDbStatusCodes.fromCode(res.statusCode),
        res.body,
      );
    }

    return IndexResultList.fromJson(res.body);
  }

  @override
  Future<Map<String, dynamic>> bulkGetRaw(
    BulkGetRequest request, {
    bool revs = false,
    bool attachments = false,
    void Function(int bytes)? onBytesReceived,
  }) async {
    final payload = {
      'docs': request.docs
          .map(
            (doc) => {
              'id': doc.id,
              if (doc.rev != null) 'rev': doc.rev,
              if (doc.attsSince != null) 'atts_since': doc.attsSince,
            },
          )
          .toList(),
    };

    final queryParameters = {
      if (revs) 'revs': 'true',
      if (attachments) 'attachments': 'true',
    };
    final headers = {
      'Content-Type': 'application/json',
      'Referer': '$uri/$dbname',
    };
    final body = jsonEncode(payload);

    final response = onBytesReceived != null
        ? await httpPostStreaming(
            '$dbname/_bulk_get',
            headers: headers,
            body: body,
            queryParameters: queryParameters,
            onBytesReceived: onBytesReceived,
          )
        : await httpPost(
            '$dbname/_bulk_get',
            headers: headers,
            body: body,
            queryParameters: queryParameters,
          );

    if (response.statusCode != CouchDbStatusCodes.ok.code) {
      throw CouchDbException(
        CouchDbStatusCodes.fromCode(response.statusCode),
        response.body,
      );
    }

    return jsonDecode(response.body);
  }

  @override
  Stream<BulkGetMultipartResult> bulkGetMultipart(
    BulkGetRequest request, {
    bool revs = false,
    void Function(int bytes)? onBytesReceived,
  }) async* {
    final payload = {
      'docs': request.docs
          .map(
            (doc) => {
              'id': doc.id,
              if (doc.rev != null) 'rev': doc.rev,
              if (doc.attsSince != null) 'atts_since': doc.attsSince,
            },
          )
          .toList(),
    };
    final queryParameters = {if (revs) 'revs': 'true', 'attachments': 'true'};
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'multipart/mixed',
      'Referer': '$uri/$dbname',
    };
    final body = jsonEncode(payload);

    final streamedResponse = await httpPostStream(
      '$dbname/_bulk_get',
      headers: headers,
      body: body,
      queryParameters: queryParameters,
    );

    if (streamedResponse.statusCode != CouchDbStatusCodes.ok.code) {
      final errBody = (await http.Response.fromStream(streamedResponse)).body;
      throw CouchDbException(
        CouchDbStatusCodes.fromCode(streamedResponse.statusCode),
        errBody,
      );
    }

    final contentType = streamedResponse.headers['content-type'] ?? '';

    if (!contentType.startsWith('multipart')) {
      final body = (await http.Response.fromStream(streamedResponse)).body;
      throw StateError(
        'bulkGetMultipart: expected multipart/mixed response but got '
        '"$contentType". CouchDB must support multipart _bulk_get. '
        'Response body: $body',
      );
    }

    final outerBoundary =
        RegExp(r'boundary="([^"]+)"').firstMatch(contentType)?.group(1) ??
        RegExp(r'boundary=([^\s;,]+)').firstMatch(contentType)?.group(1);
    if (outerBoundary == null) {
      throw Exception('Missing boundary in multipart/mixed response');
    }

    int bytesReceived = 0;
    final rawStream = onBytesReceived != null
        ? streamedResponse.stream.map((chunk) {
            bytesReceived += chunk.length;
            onBytesReceived(bytesReceived);
            return chunk;
          })
        : streamedResponse.stream;

    final outerParts = MimeMultipartTransformer(outerBoundary).bind(rawStream);

    await for (final outerPart in outerParts) {
      final outerCT = outerPart.headers['content-type'] ?? '';
      if (outerCT.startsWith('multipart/related')) {
        yield* _parseRelatedOuterPart(outerCT, outerPart);
      } else {
        // application/json — doc without attachments
        if (!outerCT.startsWith('application/json') && outerCT.isNotEmpty) {
          _log.warning(
            'bulkGetMultipart: unexpected outer content-type "$outerCT", '
            'treating as application/json',
          );
        }
        final bytes = await _drainMimePart(outerPart);
        final entryMap = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        yield* _yieldJsonBulkGetEntry(entryMap);
      }
    }
  }

  /// Adapts a [MimeMultipart] stream for safe nested use with
  /// [MimeMultipartTransformer].
  ///
  /// Two problems with mime 2.0.0 are solved:
  ///
  /// 1. **Sync re-entrancy**: [MimeMultipart] bodies use a `sync: true`
  ///    [StreamController]. Binding an inner [MimeMultipartTransformer] to it
  ///    causes `_tryPropagateControllerState()` to fire `onDone` before
  ///    `_state = _doneCode` is set → spurious "Bad multipart ending". Because
  ///    this function is `async*`, every `yield` delivers bytes through the
  ///    Dart async scheduler instead of synchronously, breaking the chain.
  ///
  /// 2. **Missing trailing CRLF**: CouchDB often omits `\r\n` after the final
  ///    `--boundary--` terminator. [MimeMultipartTransformer] requires it to
  ///    advance to `_doneCode`. This function tracks the last two bytes and
  ///    appends `\r\n` when they are absent.
  Stream<List<int>> _adaptMimePartStream(Stream<List<int>> source) async* {
    int last1 = -1;
    int last2 = -1;
    await for (final chunk in source) {
      if (chunk.length >= 2) {
        last2 = chunk[chunk.length - 2];
        last1 = chunk[chunk.length - 1];
      } else if (chunk.length == 1) {
        last2 = last1;
        last1 = chunk[0];
      }
      yield chunk;
    }
    if (last1 != 0x0A || last2 != 0x0D) {
      yield [0x0D, 0x0A];
    }
  }

  /// Parses a `multipart/related` outer part (doc with attachments).
  ///
  /// [outerPart] is adapted via [_adaptMimePartStream] before being fed to the
  /// inner [MimeMultipartTransformer]. This makes the inner transformer consume
  /// the live HTTP stream rather than a pre-buffered copy, so attachment parts
  /// are drained one at a time as bytes arrive from the network.
  ///
  /// Binary attachment parts may carry a MIME-level `Content-Encoding: gzip`
  /// header (distinct from the HTTP-level header that Dart's http client
  /// handles automatically). This header is detected and the bytes are
  /// transparently decompressed so that [BulkGetMultipartAttachment.data]
  /// always yields the original uncompressed content.
  ///
  /// Peak memory per call = one decompressed attachment at a time.
  Stream<BulkGetMultipartResult> _parseRelatedOuterPart(
    String contentType,
    MimeMultipart outerPart,
  ) async* {
    final innerBoundary =
        RegExp(r'boundary="([^"]+)"').firstMatch(contentType)?.group(1) ??
        RegExp(r'boundary=([^\s;,]+)').firstMatch(contentType)?.group(1);
    if (innerBoundary == null) {
      throw Exception('Missing inner boundary in multipart/related');
    }

    final innerParts = MimeMultipartTransformer(
      innerBoundary,
    ).bind(_adaptMimePartStream(outerPart));

    Map<String, dynamic>? docMap;
    BulkGetMultipartFailure? docFailure;
    final attachments = <String, BulkGetMultipartAttachment>{};
    int binaryIndex = 0;

    await for (final innerPart in innerParts) {
      final innerCT =
          innerPart.headers['content-type'] ?? 'application/octet-stream';

      if (docMap == null) {
        // First inner part is always the JSON doc.
        final bytes = await _drainMimePart(innerPart);
        final parsed = jsonDecode(utf8.decode(bytes));
        // The inner JSON may be the raw doc or wrapped in {docs:[{ok:...}]}.
        if (parsed is Map<String, dynamic> && parsed.containsKey('docs')) {
          final outerId = parsed['id'] as String?;
          final docs = parsed['docs'] as List<dynamic>;
          if (docs.isEmpty) {
            _log.warning(
              '_parseRelatedOuterPart: empty docs list in bulk_get '
              'entry, id=$outerId — yielding nothing',
            );
          } else if (docs.isNotEmpty) {
            final first = docs.first as Map<String, dynamic>;
            if (first.containsKey('ok')) {
              docMap = Map<String, dynamic>.from(
                first['ok'] as Map<String, dynamic>,
              );
            } else if (first.containsKey('error')) {
              final errorVal = first['error'];
              if (errorVal is Map<String, dynamic>) {
                docFailure = BulkGetMultipartFailure(
                  id: errorVal['id'] as String? ?? outerId ?? '',
                  rev: errorVal['rev'] as String?,
                  error: errorVal['error'] as String? ?? 'unknown',
                  reason: errorVal['reason'] as String? ?? '',
                );
              } else {
                // Flat error: {rev, error, reason} at top level
                docFailure = BulkGetMultipartFailure(
                  id: first['id'] as String? ?? outerId ?? '',
                  rev: first['rev'] as String?,
                  error: errorVal as String? ?? 'unknown',
                  reason: first['reason'] as String? ?? '',
                );
              }
            } else {
              _log.warning(
                '_parseRelatedOuterPart: unexpected doc structure in '
                'docs[0], keys: ${first.keys.toList()}',
              );
              docMap = Map<String, dynamic>.from(first);
            }
          }
        } else {
          final parsedMap = parsed as Map<String, dynamic>;
          if (parsedMap.containsKey('ok')) {
            docMap = Map<String, dynamic>.from(
              parsedMap['ok'] as Map<String, dynamic>,
            );
          } else if (parsedMap.containsKey('error') &&
              !parsedMap.containsKey('_id')) {
            docFailure = BulkGetMultipartFailure(
              id: parsedMap['id'] as String? ?? '',
              rev: parsedMap['rev'] as String?,
              error: parsedMap['error'] as String? ?? 'unknown',
              reason: parsedMap['reason'] as String? ?? '',
            );
          } else {
            _log.fine(
              '_parseRelatedOuterPart: bare doc map, '
              'keys: ${parsedMap.keys.toList()}',
            );
            docMap = parsedMap;
          }
        }
      } else {
        // Binary attachment part — match to nth "follows":true stub.
        final attEntry = _nthFollowsStub(docMap, binaryIndex);
        if (attEntry != null) {
          final stub = attEntry.value as Map<String, dynamic>;
          // Drain eagerly: one attachment in memory at a time.
          final rawBytes = await _drainMimePartToUint8List(innerPart);
          // CouchDB may gzip-compress compressible content types (text/*,
          // application/json, etc.) and signal this with a MIME-level
          // Content-Encoding header. Dart's http client only handles HTTP-level
          // Content-Encoding, so we must decompress MIME parts ourselves.
          final encoding = innerPart.headers['content-encoding'];
          final bytes = (encoding == 'gzip')
              ? Uint8List.fromList(await gzipDecode(rawBytes))
              : rawBytes;
          attachments[attEntry.key] = BulkGetMultipartAttachment(
            contentType:
                stub['content_type'] as String? ??
                stub['content-type'] as String? ??
                innerCT,
            // Digest is MD5 of the *compressed* bytes as stored by CouchDB.
            // The local file will hold decompressed bytes — this mismatch is
            // intentional: replication compares digests with CouchDB, so both
            // sides use the same compressed-bytes digest.
            digest: stub['digest'] as String? ?? '',
            length: bytes.length, // decompressed length
            revpos: (stub['revpos'] as num?)?.toInt() ?? 0,
            data: Stream.value(bytes), // decompressed bytes
            encoding:
                encoding, // non-null when CouchDB compressed the attachment
          );
          binaryIndex++;
        } else {
          // Unknown part — drain to avoid stalling the transformer.
          _log.warning(
            '_parseRelatedOuterPart: no "follows" stub for binary part '
            'index $binaryIndex in doc ${docMap['_id']} — draining '
            'and discarding',
          );
          await _drainMimePart(innerPart);
        }
      }
    }

    if (docFailure != null) {
      yield docFailure;
      return;
    }

    if (docMap == null) {
      _log.warning(
        '_parseRelatedOuterPart: no JSON doc part found in '
        'multipart/related — yielding nothing',
      );
      return;
    }
    yield BulkGetMultipartSuccess(
      BulkGetMultipartOk(doc: docMap, attachments: attachments),
    );
  }

  /// Yields one or more [BulkGetMultipartResult]s from a JSON outer part.
  ///
  /// Within a multipart/mixed response, docs without attachments are sent as
  /// application/json outer parts. These never carry inline attachment data
  /// (stubs only), so [attachments] is always empty.
  Stream<BulkGetMultipartResult> _yieldJsonBulkGetEntry(
    Map<String, dynamic> entryMap,
  ) async* {
    if (entryMap.containsKey('docs')) {
      // Standard {id, docs:[{ok/error}]} wrapper.
      final id = entryMap['id'] as String;
      final docsList = entryMap['docs'] as List<dynamic>;
      if (docsList.isEmpty) {
        _log.warning(
          '_yieldJsonBulkGetEntry: empty docs list for id=$id '
          '— yielding nothing',
        );
        return;
      }
      for (final docEntry in docsList) {
        final docMap = docEntry as Map<String, dynamic>;
        if (docMap.containsKey('ok')) {
          yield BulkGetMultipartSuccess(
            BulkGetMultipartOk(
              doc: docMap['ok'] as Map<String, dynamic>,
              attachments: {},
            ),
          );
        } else {
          final errorVal = docMap['error'];
          if (errorVal is Map<String, dynamic>) {
            yield BulkGetMultipartFailure(
              id: id,
              rev: errorVal['rev'] as String?,
              error: errorVal['error'] as String? ?? 'unknown',
              reason: errorVal['reason'] as String? ?? '',
            );
          } else {
            // Flat error: {rev, error, reason} at top level of docMap
            yield BulkGetMultipartFailure(
              id: docMap['id'] as String? ?? id,
              rev: docMap['rev'] as String?,
              error: errorVal as String? ?? 'unknown',
              reason: docMap['reason'] as String? ?? '',
            );
          }
        }
      }
    } else if (entryMap.containsKey('error') && !entryMap.containsKey('_id')) {
      // Bare error map without the standard {docs:[{error:...}]} wrapper.
      yield BulkGetMultipartFailure(
        id: entryMap['id'] as String? ?? '',
        rev: entryMap['rev'] as String?,
        error: entryMap['error'] as String? ?? 'unknown',
        reason: entryMap['reason'] as String? ?? '',
      );
    } else {
      // Bare doc map (no wrapper).
      _log.finest(
        '_yieldJsonBulkGetEntry: bare doc map (no wrapper), '
        'keys: ${entryMap.keys.toList()}',
      );
      yield BulkGetMultipartSuccess(
        BulkGetMultipartOk(doc: entryMap, attachments: {}),
      );
    }
  }

  /// Returns the nth `"follows":true` stub entry from the `_attachments` map
  /// in insertion order (matches CouchDB's binary part ordering).
  MapEntry<String, dynamic>? _nthFollowsStub(Map<String, dynamic> doc, int n) {
    final atts = doc['_attachments'] as Map<String, dynamic>?;
    if (atts == null) return null;
    int count = 0;
    for (final entry in atts.entries) {
      if ((entry.value as Map<String, dynamic>)['follows'] == true) {
        if (count == n) return entry;
        count++;
      }
    }
    return null;
  }

  Future<List<int>> _drainMimePart(MimeMultipart part) async {
    final chunks = <List<int>>[];
    await for (final chunk in part) {
      chunks.add(chunk);
    }
    return chunks.expand((c) => c).toList();
  }

  Future<Uint8List> _drainMimePartToUint8List(MimeMultipart part) async {
    final chunks = <List<int>>[];
    var totalLength = 0;
    await for (final chunk in part) {
      chunks.add(chunk);
      totalLength += chunk.length;
    }
    final result = Uint8List(totalLength);
    var offset = 0;
    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return result;
  }

  @override
  Future<List<BulkDocsResult>> bulkDocsFromMultipart(
    List<BulkGetMultipartSuccess> docs, {
    bool newEdits = false,
  }) async {
    // CouchDB _bulk_docs does not support multipart upload — collect each
    // attachment stream into memory, base64-encode, and POST as JSON.
    final jsonDocs = <String>[];

    for (final result in docs) {
      final docMap = Map<String, dynamic>.from(result.ok.doc);

      if (result.ok.attachments.isNotEmpty) {
        // Start from existing stubs in the doc (covers stubs from atts_since).
        final attMap = Map<String, dynamic>.from(
          (docMap['_attachments'] as Map<String, dynamic>?) ?? {},
        );
        // Replace "follows" stubs with inline base64 for transferred attachments.
        for (final entry in result.ok.attachments.entries) {
          final att = entry.value;
          final chunks = <List<int>>[];
          var totalLength = 0;
          await for (final chunk in att.data) {
            chunks.add(chunk);
            totalLength += chunk.length;
          }
          final bytes = Uint8List(totalLength);
          var offset = 0;
          for (final chunk in chunks) {
            bytes.setRange(offset, offset + chunk.length, chunk);
            offset += chunk.length;
          }
          attMap[entry.key] = {
            'content_type': att.contentType,
            'data': base64Encode(bytes),
            'digest': att.digest,
            'revpos': att.revpos,
          };
        }
        docMap['_attachments'] = attMap;
      }

      jsonDocs.add(jsonEncode(docMap));
    }

    return bulkDocsRaw(jsonDocs, newEdits: newEdits);
  }

  @override
  void dispose() {
    super.dispose();
    renewHttpClient();
  }
}
