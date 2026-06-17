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
