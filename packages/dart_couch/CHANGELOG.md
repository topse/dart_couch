# Changelog

## 1.0.26
* performance: batched document loading in local `allDocs`/`query`/`get`
* performance: local changes feed reads changes in pages
* performance: local `allDocs` reads the documents table directly
* performance: shared document cache for `use*` streams
* performance: faster local view indexing and view lookup
* behaviour change: local `allDocs(keys)` reports deleted documents like CouchDB
* behaviour change: documents emitted by `use*` streams may be shared, treat them as immutable
* behaviour change: `query()` throws `ArgumentError` for a path that is not `designdoc/view`; local `query('_all_docs')` is gone, use `allDocs()`
* bugfix: views of several local databases interfered with each other
* bugfix: `useDoc` could emit a stale document after a deletion
* bugfix: `use*` streams could postpone updates indefinitely under continuous writes
* bugfix: http `get(attachments: true)` returned gzip-compressed data for compressible attachments
* bugfix: http `allDocs` failed with `limit`/`skip`
* bugfix: http `allDocs`/`query` with attachments did not report `encoding`
* bugfix: local `allDocs` reported a wrong `offset`
* bugfix: local replication of a tombstone on the winning branch did not promote the surviving conflict leaf
* bugfix: keyed `useAllDocs` did not update `total_rows` on changes of other documents
* add `useCacheCapacity`, `useCacheStats` and `DbQueryStats` diagnostics
* fix QuickJS build with MSVC on Windows

## 1.0.24
* update libs

## 1.0.18
* add `OfflineFirstDb.initialSyncCompleted`: persisted flag "initial sync completed"
* add optional `onInitialSyncComplete` callback to `syncTo`
* bugfix: `resume()` reported `inSync` during the initial sync
* bugfix: concurrent replication restarts could leave an unobserved replication running
* restart replication after a detected database recreation
* add `OfflineFirstServer.retryNow()`: one-shot shortcut to retry connecting/replicating immediately (e.g. on connectivity change)
* bugfix: `resume()` now recovers an expired session / failed first attempt immediately instead of after the next health tick

## 1.0.16
* cleanup work
* update quickjs
* implement HttpDartCouch::getAttachmentAsReadonlyFile

## 1.0.14
* update dart_mappable dependencies

## 1.0.12
* change API for clearer handling of conflict resolvement: parameter for conflict resolver is now required, but can be null

## 1.0.10
* more bugfix: url too long

## 1.0.8
* bugfix: url too long

##  1.0.6
* add helper SaveDocWriter, LiveDocHandle

## 1.0.4
* comments for code generation: dont forget to run on version update

## 1.0.2
* log dart_couch version on startup

## 1.0.0
* add conflict resolver

## 0.9.26
* Add diff API: useViewWithChanges and useAllDocsWithChanges to enable better ui updates

## 0.9.24
* bugfix for view querying with json keys

## 0.9.22
* bugfix: not all documents written to offline were replicated if initial replication was in progress

## 0.9.20
* bugfix for grey screen in example app: If can connect to server but not couchdb answers but some proxy with a 404, this was a problem until now

## 0.9.16
* bugfix: don't rethrow in HttpServer.login

## 0.9.14
* regenerate dart_mappable code

## 0.9.10
* optimize replication performance part II: Writing locally
* add support for double values in local documents (term_to_binary)

## 0.9.8
* optimize replication performance

## 0.9.6
* bugfix for replicating a lot of documents

## 0.9.4
* add support for platform web

## 0.9.2
* big refactoring to remove flutter dependency from dart_couch core

## 0.9.0

* Initial public release.
