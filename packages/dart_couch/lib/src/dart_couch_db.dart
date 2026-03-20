import 'dart:convert';
import 'dart:typed_data';

import '../dart_couch.init.dart';
import 'messages/bulk_docs_result.dart';
import 'messages/bulk_get.dart';
import 'messages/bulk_get_multipart.dart';
import 'messages/changes_result.dart';
import 'messages/couch_document_base.dart';
import 'messages/database_info.dart';
import 'messages/index_result.dart';
import 'messages/revs_diff_result.dart';
import 'messages/view_result.dart';
import 'use_dart_couch.dart';

abstract class DartCouchDb with UseDartCouchMixin {
  String dbname;

  DartCouchDb({required this.dbname});

  static void ensureInitialized() {
    initializeMappers();
  }

  /// Converts a username to the corresponding CouchDB per-user database name.
  ///
  /// CouchDB uses the convention `userdb-{hex}` where `{hex}` is the lowercase
  /// hex encoding of the UTF-8 bytes of the username (the username itself is
  /// NOT lowercased before encoding).
  ///
  /// Example:
  ///   'Alice' -> 'userdb-416c696365'
  ///   'bob@example.com' -> 'userdb-626f62406578616d706c652e636f6d'
  static String usernameToDbName(String username) {
    final bytes = utf8.encode(username);
    final sb = StringBuffer('userdb-');
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// Converts a CouchDB per-user database name back to the original username.
  ///
  /// Expects names in the form `userdb-{hex}` where `{hex}` is the lowercase
  /// hex encoding of the UTF-8 bytes of the username.
  ///
  /// If decoding fails (e.g., invalid hex), the original [dbName] is returned.
  static String dbNameToUsername(String dbName) {
    const prefix = 'userdb-';
    final hex = dbName.startsWith(prefix)
        ? dbName.substring(prefix.length)
        : dbName;

    // Must be even-length and only hex chars.
    if (hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(hex)) {
      return dbName;
    }

    try {
      final bytes = <int>[];
      for (var i = 0; i < hex.length; i += 2) {
        final byte = int.parse(hex.substring(i, i + 2), radix: 16);
        bytes.add(byte);
      }
      return utf8.decode(bytes);
    } catch (_) {
      return dbName;
    }
  }

  /// Create a new Mango index on this database.
  ///
  /// Mirrors the CouchDB API endpoint: POST /{db}/_index
  ///
  /// Parameters:
  /// - `index` (required): JSON object describing the index to create. For a
  ///   JSON index this typically contains a `fields` array and optionally
  ///   `partial_filter_selector`, etc.
  /// - `ddoc` (optional): Name of the design document to create the index in.
  ///   If omitted, CouchDB will create a dedicated design doc for the index.
  /// - `name` (optional): Name of the index. If omitted, CouchDB will generate
  ///   a name automatically.
  /// - `type` (optional, defaults to `json`): Type of index. Can be `json`,
  ///   `text`, or `nouveau` depending on server capabilities.
  /// - `partitioned` (optional): Whether to create a partitioned index. By
  ///   default this follows the database partitioning configuration.
  ///
  /// Returns the name of the created index.
  ///
  /// Throws an exception on network errors or non-OK status codes.
  Future<String?> createIndex({
    required IndexDefinition index,
    String? ddoc,
    String? name,
    String type = 'json',
    bool? partitioned,
  });

  /// Retrieve a list of all Mango indexes defined on this database.
  ///
  /// Mirrors the CouchDB API endpoint: GET /{db}/_index
  ///
  /// Returns an array of index definition maps as returned by CouchDB.
  ///
  /// Throws on network or server errors.
  Future<IndexResultList> getIndexes();

  /// Delete a Mango index from this database.
  ///
  /// Mirrors the CouchDB API endpoint: DELETE /{db}/_index/{design_doc}/{type}/{name}
  ///
  /// Parameters:
  /// - `designDoc` (required): Name of the design document that contains the
  ///   index. The `_design/` prefix is optional; implementations should accept
  ///   either form.
  /// - `name` (required): Name of the index to delete.
  /// - `type` (optional): Index type (commonly `json`). Defaults to `json`.
  ///
  /// Returns `true` when CouchDB replies with `{ "ok": true }`.
  /// Throws on network/server errors or if the index is not found.
  Future<bool> deleteIndex({
    required String designDoc,
    required String name,
    String type = 'json',
  });

  /// Returns null if the database does not exist.
  Future<DatabaseInfo?> info();

  /// It is guaranteed, that every document appears in the result with its latest
  /// change.
  /// The results are sorted by the sequence ID of each change.
  ///
  /// If you not using continuous feed, the stream will close itself after
  /// first Result. You can query that with:
  /// ```final res = await changes(...).first;```
  ///

  /// Streams changes from the CouchDB database.
  ///
  /// This function connects to the `_changes` feed of the database and emits
  /// updates as `ChangesResult` objects. It supports filtering, controlling
  /// feed behavior, and resuming from a specific point using `since` or
  /// `lastEventId`.
  ///
  /// Each emitted `ChangesResult` represents a single change in the database,
  /// including document ID, revision info, deletion status, and optionally
  /// the full document or attachments.
  ///
  /// Parameters:
  /// - `docIds`: Optional list of document IDs to filter changes for specific documents.
  /// - `descending`: If true, returns changes in descending order of sequence.
  /// - `feedmode`: Mode of the feed (`normal`, `continuous`, `longpoll`). Determines how changes are streamed.
  ///               in Normal:  It is guaranteed, that every document appears in the result with its latest
  ///                           change. The results are sorted by the sequence ID of each change.
  /// - `heartbeat`: Interval (in ms) to send a heartbeat to keep the connection alive in continuous feeds.
  /// - `includeDocs`: If true, includes the full document in each change event.
  /// - `attachments`: If true, includes attachments with documents (requires `includeDocs`).
  /// - `attEncodingInfo`: If true, includes attachment encoding info (requires `attachments`).
  /// - `lastEventId`: Optional last sequence ID received, used to resume the feed without missing changes.
  /// - `limit`: Maximum number of changes to return. `0` means no limit.
  /// - `since`: Sequence ID or “now” to start listening from. Used for resuming from a specific point.
  /// - `styleAllDocs`: If true, returns changes in “all_docs” style rather than per-document style.
  /// - `timeout`: Maximum time (in ms) for the request to wait for changes (useful for longpoll/continuous feeds).
  /// - `seqInterval`: Interval at which the `seq` property is included in the response for efficiency.
  ///
  /// Returns:
  /// A `Stream<ChangesResult>` that emits change events from CouchDB as they occur.
  /// If you not using continuous feed, the stream will close itself after
  /// first Result. You can query that with: `final res = await changes(...).first;`
  ///
  /// Example usage:
  /// ```dart
  /// final stream = changes(feedmode: FeedMode.continuous, since: '100');
  /// await for (final change in stream) {
  ///   print('Document changed: ${change.id}');
  /// }
  /// ```
  ///
  /// ATTENTION:
  /// When using complex startkey or endkeys, make sure to use double-quotes in the JSON strings.
  /// ```dart
  /// res = await db.query(
  ///   'tree_view/by_parent',
  ///   startkey: '["parent"]',
  ///   endkey: '["parent", {}]',
  /// );
  /// ```
  @override
  Stream<ChangesResult> changes({
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
    // Concrete implementation that calls changesRaw() and parses results
    return changesRaw(
      docIds: docIds,
      descending: descending,
      feedmode: feedmode,
      heartbeat: heartbeat,
      includeDocs: includeDocs,
      attachments: attachments,
      attEncodingInfo: attEncodingInfo,
      lastEventId: lastEventId,
      limit: limit,
      since: since,
      styleAllDocs: styleAllDocs,
      timeout: timeout,
      seqInterval: seqInterval,
    ).map((json) {
      // Parse raw JSON into ChangesResult
      if (feedmode == FeedMode.normal || feedmode == FeedMode.longpoll) {
        // Normal/longpoll mode: entire response is a ChangesResultNormal
        return ChangesResult.normal(ChangesResultNormal.fromMap(json));
      } else {
        // Continuous mode: each JSON object is a single ChangeEntry
        return ChangesResult.continuous(ChangeEntry.fromMap(json));
      }
    });
  }

  /// Raw version of changes() that returns unparsed JSON.
  ///
  /// This method provides the same functionality as changes() but returns
  /// raw Map&lt;String, dynamic&gt; objects instead of parsed ChangesResult objects.
  /// This is useful for replication code that needs to avoid dart_mappable
  /// parsing issues with CouchDocumentBase.
  ///
  /// Implementations should provide the HTTP or local database logic to
  /// fetch the _changes feed and return the raw JSON response.
  ///
  /// The returned stream emits:
  /// - For normal/longpoll feeds: A single Map containing the entire response
  ///   with 'results', 'last_seq', etc.
  /// - For continuous feeds: Individual Maps for each change entry with
  ///   'id', 'seq', 'changes', 'doc', etc.
  ///
  /// Parameters are identical to changes().
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
  });

  /// get a document by its id
  ///
  /// rev             -> can load a special rev, even of a deleted document revision
  /// revs = true     -> includes a list of all known document revisions
  /// refsInfo = true -> includes detailed information for all known document revisions
  ///                    ignored if openRefs is "all"
  /// openRefs = {array} | "all" ->
  ///        Retrieves documents of specified leaf revisions, even from deleted revisions.
  ///        Additionally, it accepts value as all to return all leaf revisions.
  ///        refsInfo is ignored if openRefs is used.
  ///        "all" seems to make sens in combination with revs=true
  ///
  /// Returns:
  /// It seems, if a deleted revision is loaded, in general a CouchDocumentBase
  /// is returned.
  /// Otherwise the received JSON-Document gets parsed with dart_mappable to
  /// a subtype of CouchDocumentBase.
  /// If the document has bee deleted and a new document with same ID created,
  /// the revision list gets longer when openRefs=all and revs=true.

  /// Raw version of get that returns the document as JSON string.
  /// This preserves all fields including unknown !doc_type discriminators.
  Future<Map<String, dynamic>?> getRaw(
    String docid, {
    String? rev,
    bool revs = false,
    bool revsInfo = false,
    bool attachments = false,
  });

  /// Get a document by ID. Uses getRaw() internally and deserializes the result.
  @override
  Future<CouchDocumentBase?> get(
    String docid, {
    String? rev,
    bool revs = false,
    bool revsInfo = false,
    bool attachments = false,
  }) async {
    final map = await getRaw(
      docid,
      rev: rev,
      revs: revs,
      revsInfo: revsInfo,
      attachments: attachments,
    );
    if (map == null) return null;
    return CouchDocumentBase.fromMap(map);
  }

  /// if leafRevisions is null, "all" will be used!
  Future<List<OpenRevsResult>?> getOpenRevs(
    String docid, {
    List<String>? revisions,
    bool revs = false,
  });

  /// The PUT method creates a new named document, or creates a new revision of the existing document.
  /// Unlike the POST /{db}, you must specify the document ID in the request URL.
  ///
  /// When updating an existing document, the current document revision must be included
  /// in the document (i.e. the request body), as the rev query parameter,
  /// or in the If-Match request header.
  ///
  /// SAVING INLINE ATTACHMENTS IS NOT SUPPORTED!
  ///
  /// Returns the document as JSON string with updated _id and _rev.
  Future<Map<String, dynamic>> putRaw(Map<String, dynamic> doc);

  /// PUT method that accepts a CouchDocumentBase and returns the updated document.
  /// Uses putRaw() internally and converts the result.
  Future<CouchDocumentBase> put(CouchDocumentBase doc) async {
    final resultMap = await putRaw(doc.toMap());
    return doc.copyWith(
      id: resultMap['_id'] as String?,
      rev: resultMap['_rev'] as String?,
    );
  }

  /// Creates a new document in the specified database, using the supplied JSON document structure.
  ///
  /// If the JSON structure includes the _id field, then the document will be created
  /// with the specified document ID.
  ///
  /// If the _id field is not specified, a new unique ID will be generated,
  /// following whatever UUID algorithm is configured for that server.
  ///
  /// SAVING INLINE ATTACHMENTS IS NOT SUPPORTED!
  ///
  /// Updating existing documents with POST is not allowed. To update an existing document,
  /// use the PUT method with the document ID in the URL and the current revision in the body or headers.
  ///
  /// Returns the document as JSON string with _id and _rev.
  Future<Map<String, dynamic>> postRaw(Map<String, dynamic> doc);

  /// POST method that accepts a CouchDocumentBase and returns the created document.
  /// Uses postRaw() internally and converts the result.
  Future<CouchDocumentBase> post(CouchDocumentBase doc) async {
    final resultMap = await postRaw(doc.toMap());
    return doc.copyWith(
      id: resultMap['_id'] as String?,
      rev: resultMap['_rev'] as String?,
    );
  }

  /// removes a document by its id and rev.
  /// returns the new revision id of the deletion
  Future<String> remove(String docid, String rev);

  /// [includeDocs] Include the document itself in each row in the doc field. Otherwise by default you only get the _id and _rev properties.
  /// [attachments] Include attachment data as base64-encoded string.
  /// [startKey] & [endKey] Get documents with IDs in a certain range (inclusive/inclusive).
  /// [inclusiveEnd] Include documents having an ID equal to the given options.endkey. Default: true.
  /// [limit] Maximum number of documents to return.
  /// [skip] Number of docs to skip before returning (warning: poor performance on IndexedDB/LevelDB!).
  /// [descending] Reverse the order of the output documents. Note that the order of startkey and endkey is reversed when descending:true.
  /// [key] Only return documents with IDs matching this string key.
  /// [keys] Array of string keys to fetch in a single shot.
  ///     - Neither startkey nor endkey can be specified with this option.
  ///     - The rows are returned in the same order as the supplied keys array.
  ///     - The row for a deleted document will have the revision ID of the deletion,
  ///       and an extra key "deleted":true in the value property.
  ///     - The row for a nonexistent document will just contain an "error" property
  ///       with the value "not_found".
  /// For details, see the [CouchDB query options documentation|https://docs.couchdb.org/en/stable/api/ddoc/views.html#db-design-design-doc-view-view-name].
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
  });

  /// GET /{db}/_local_docs
  ///
  /// Returns a JSON structure of all local documents in a given database.
  /// Local documents are special documents with IDs starting with "_local/"
  /// that are not replicated between databases.
  ///
  /// Parameters:
  /// - [conflicts]: Include conflicts information in response (requires includeDocs). Default is false.
  /// - [descending]: Return documents in descending key order. Default is false.
  /// - [endkey]: Stop returning records when the specified key is reached.
  /// - [endkeyDocid]: Stop returning records when the specified document ID is reached.
  /// - [includeDocs]: Include full document content. Default is false.
  /// - [inclusiveEnd]: Include the endkey in results. Default is true.
  /// - [key]: Return only documents matching this key.
  /// - [keys]: Return only documents matching these keys.
  /// - [limit]: Maximum number of documents to return.
  /// - [skip]: Skip this number of records before returning results. Default is 0.
  /// - [startkey]: Return records starting with this key.
  /// - [startkeyDocid]: Return records starting with this document ID.
  /// - [updateSeq]: Include update_seq in response. Default is false.
  ///
  /// Returns a ViewResult containing:
  /// - offset: Offset where the list started
  /// - rows: Array of local document entries (id, key, value with rev)
  /// - totalRows: Number of local documents in database (may be null)
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
  });

  /// Queries a view.
  ///
  /// This method translates the provided parameters into a CouchDB query, utilizing
  /// `limit` to specify the maximum number of results to return and `skip` to indicate
  /// how many documents to exclude from the beginning of the result set (for pagination).
  /// In CouchDB views, 'skip' is used for pagination instead of 'offset'.
  ///
  /// [viewPathShort] is the short name of the view to query, e.g.
  /// name_of_design_document/name_of_view.
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
  });

  /// saveAttachment is only allowed on the latest revision of a document.
  /// The Attachment name is not allowed to start with _ (underline) and must not contain a slash.
  ///
  /// SAVING INLINE ATTACHMENTS IS NOT SUPPORTED!
  ///
  /// returns the new revision of the document
  Future<String> saveAttachment(
    String docId,
    String rev,
    String attachmentName,
    Uint8List data, {
    String contentType = 'application/octet-stream',
  });

  /// rev is the revision of the document
  Future<Uint8List?> getAttachment(
    String docId,
    String attachmentName, {
    String? rev,
  });

  /// Returns the absolute filesystem path to the attachment file.
  ///
  /// The file is guaranteed to be read-only on disk. It must not be written to;
  /// use [saveAttachment] to update the attachment content.
  ///
  /// Returns `null` if the document or the named attachment does not exist.
  ///
  /// Only [LocalDartCouchDb] has a real implementation. [HttpDartCouchDb] throws
  /// [UnimplementedError]; use [getAttachment] to load bytes instead.
  /// [OfflineFirstDb] delegates to its local instance.
  Future<String?> getAttachmentAsReadonlyFile(
    String docId,
    String attachmentName,
  );

  /// Deletes the named attachment from the document at [rev].
  /// Returns the new revision of the document after the deletion.
  Future<String> deleteAttachment(
    String docId,
    String rev,
    String attachmentName,
  );

  Future<void> startCompaction();
  Future<bool?> isCompactionRunning();

  /// Fetches the revision differences between the provided client revisions
  /// and the server's current revisions for one or more documents in a CouchDB database.
  ///
  /// This function interacts with the CouchDB `/_revs_diff` endpoint. It compares
  /// the document revisions that the client has (provided in the `revs` map)
  /// with the revisions stored on the server. The response helps identify
  /// which revisions are missing from the server (i.e., revisions that the client has
  /// but the server doesn't) and which revisions might be possible ancestors
  /// of the client's revisions.
  ///
  /// This is useful for synchronization tasks, as it allows clients to determine
  /// what changes need to be synced with the server, either by uploading missing revisions
  /// or resolving potential conflicts.
  ///
  /// Example Usage:
  /// ```dart
  /// Map<String, List<String>> revs = {
  ///   "doc1": ["rev1", "rev2"],
  ///   "doc2": ["rev3", "rev4"]
  /// };
  /// fetchRevsDiff(revs);
  /// ```
  ///
  /// This function uses the Dart `http` package to send a POST request to the CouchDB
  /// `/_revs_diff` endpoint with the given document revisions, and it handles the
  /// response to print the revision differences.
  ///
  /// **Parameters:**
  /// - `revs`: A map where the key is the document ID (String), and the value is a list
  ///           of revision IDs (List&lt;String&gt;) to compare with the server.
  ///
  /// **Response:**
  /// The response contains information on which revisions are missing and which
  /// might be possible ancestors of the provided revisions.
  ///
  /// **Note:**
  /// Ensure that CouchDB is properly configured and accessible at the specified URL.
  Future<Map<String, RevsDiffEntry>> revsDiff(Map<String, List<String>> revs);

  /// POST /{db}/_bulk_docs
  ///
  /// Uploads multiple documents in a single request.
  /// If [newEdits] is false, CouchDB treats the supplied documents as already-constructed
  /// revision history and will accept the provided `_rev` values instead of creating new
  /// revision IDs. This mode is intended for replication/restore scenarios where the
  /// client is replaying existing revisions into the target database.
  ///
  /// Behavior summary:
  /// - newEdits = true (default): CouchDB will treat the operation like normal user
  ///   updates — it will generate new revision IDs for the incoming documents (unless
  ///   you are updating an existing document and provide a matching `_rev`), and it
  ///   enforces the usual conflict checks.
  /// - newEdits = false: CouchDB will attempt to insert the provided revisions as-is
  ///   into the document's revision tree. The server will not create new revision IDs
  ///   for these documents. This is useful when you want to replicate revision history
  ///   from another server. When using `newEdits=false` you must supply valid `_rev`
  ///   values; the server will merge the revisions into the database's revision tree
  ///   where possible. Missing or malformed revision IDs can lead to rejected entries
  ///   or errors from the server. Note that conflict resolution is not performed by
  ///   generating new revisions in this mode — you are responsible for supplying the
  ///   correct history to be inserted.
  ///
  /// Returns if [newEdits] is true, a list of results, one for each document.
  ///         if [newEdits] is false, result is either an empty list or an exception.
  /// Each result contains either:
  /// - ok: true and id/rev for successful operations
  /// - error: true with reason for failed operations
  /// Raw version of bulkDocs that accepts documents as JSON strings.
  /// This preserves all fields including unknown !doc_type discriminators.
  Future<List<BulkDocsResult>> bulkDocsRaw(
    List<String> docs, {
    bool newEdits = true,
  });

  /// Bulk insert/update documents. Uses bulkDocsRaw() internally.
  Future<List<BulkDocsResult>> bulkDocs(
    List<CouchDocumentBase> docs, {
    bool newEdits = true,
  }) async {
    final jsonDocs = docs.map((doc) => jsonEncode(doc.toMap())).toList();
    return bulkDocsRaw(jsonDocs, newEdits: newEdits);
  }

  Future<Map<String, dynamic>> bulkGetRaw(
    BulkGetRequest request, {
    bool revs = false,
    bool attachments = false,
    void Function(int bytes)? onBytesReceived,
  });

  /// Memory-efficient bulk fetch using the CouchDB multipart/mixed protocol.
  ///
  /// Streams one [BulkGetMultipartResult] per requested doc/rev. Each
  /// attachment carries a [Stream<List<int>>] for its binary data instead of
  /// base64-encoded inline JSON, so data can be piped directly to disk.
  ///
  /// HTTP source: [onBytesReceived] reports raw wire bytes received.
  /// **HTTP constraint:** each attachment's [BulkGetMultipartAttachment.data]
  /// stream MUST be fully consumed before requesting the next result from this
  /// stream — CouchDB MIME parts must be drained in order.
  ///
  /// Local source: attachment streams are backed by permanent files and can be
  /// consumed at any time without ordering constraints.
  Stream<BulkGetMultipartResult> bulkGetMultipart(
    BulkGetRequest request, {
    bool revs = false,
    void Function(int bytes)? onBytesReceived,
  });

  /// Writes a batch of documents whose attachment data arrives as streams
  /// (from [bulkGetMultipart]).
  ///
  /// [LocalDartCouchDb]: drains each attachment stream directly to the `att/{id}`
  /// file on disk — no base64 decode, no in-memory buffering.
  ///
  /// [HttpDartCouchDb]: collects each attachment stream into memory, base64-encodes
  /// it, and POSTs JSON via `_bulk_docs` (CouchDB does not support multipart
  /// uploads on that endpoint).
  Future<List<BulkDocsResult>> bulkDocsFromMultipart(
    List<BulkGetMultipartSuccess> docs, {
    bool newEdits = false,
  });

  Future<bool> up();
}

enum UpdateMode {
  modeTrue('true'),
  modeFalse('false'),
  modeLazy('lazy');

  final String value;

  const UpdateMode(this.value);
}

/// Feed mode for the _changes feed.
///
/// Matches CouchDB feed modes: normal, longpoll, continuous and eventsource.
enum FeedMode {
  normal('normal'),
  longpoll('longpoll'),
  continuous('continuous'),
  eventsource('eventsource');

  final String value;
  const FeedMode(this.value);
}

class OpenRevsResult {
  final OpenRevsState state;
  final String? missingRev;

  final CouchDocumentBase? doc;

  OpenRevsResult({required this.state, this.doc, this.missingRev});
}

enum OpenRevsState {
  ok('ok'),
  missing('missing');

  final String value;
  const OpenRevsState(this.value);
}
