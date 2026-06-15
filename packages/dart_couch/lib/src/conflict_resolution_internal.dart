/// Package-internal capability for opt-in conflict resolution (PLAN.md Phase 2).
///
/// This is deliberately **not exported** from `dart_couch.dart` — it is not part
/// of the public API. A conflict-storing local replica (`LocalDartCouchDb`)
/// implements it so the replication controller can enumerate the documents that
/// are currently in conflict **cheaply**: an indexed, ids-only lookup against the
/// conflict side-table — no document-body downloads and no full-database scan.
///
/// On a remote CouchDB, enumerating every conflicted document would require a
/// dedicated conflicts view or a Mango `_find` on `_conflicts` (this library
/// implements neither query path) or an `_all_docs` + per-doc `conflicts=true`
/// full scan — none of which is the cheap, indexed, ids-only lookup the local
/// side-table gives. So there is intentionally no remote implementation;
/// resolution runs against the local replica, which is where conflicts live.
abstract class LocalConflictSource {
  /// Ids of documents that currently have at least one **live** (non-deleted)
  /// losing leaf — i.e. are in conflict. Ids only (memory-light); resolution
  /// then loads each conflicted document one at a time.
  Future<List<String>> conflictedDocIds();
}
