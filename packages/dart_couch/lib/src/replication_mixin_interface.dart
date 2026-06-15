import 'messages/couch_document_base.dart';

/// All conflicting leaf revisions of one document, passed to a
/// [DocumentConflictResolver].
///
/// [winner] is CouchDB's deterministic winning revision; [conflicts] are the
/// losing leaf revisions with their full bodies. A bodyless `not_found` leaf (a
/// permanently compacted branch recorded via `recordBodylessLeaf`) is
/// **excluded** — it has no body to merge and resolution intentionally does not
/// tombstone it (CouchDB will not collapse a compacted-body leaf via a grafted
/// tombstone, so tombstoning it is useless and causes churn; see
/// `_maybeResolveConflict`).
class ConflictedDocument {
  final String docId;
  final CouchDocumentBase winner;
  final List<CouchDocumentBase> conflicts;

  const ConflictedDocument({
    required this.docId,
    required this.winner,
    required this.conflicts,
  });
}

/// Application hook for resolving a document that has more than one leaf
/// revision (a conflict).
///
/// Resolution is an **opt-in layer on top of faithful replication**. The raw
/// revision transfer never merges or deletes — it preserves conflicts exactly
/// like CouchDB. When a resolver is configured, *after* the conflicting leaves
/// have been transferred the library calls [resolve] for each conflicted
/// document; given a survivor it writes that body as a new child of the winner
/// and tombstones every other leaf. Those are ordinary edits that then
/// replicate like any other change.
///
/// Implementations **MUST be deterministic and stable** — this is the contract:
///  - *Deterministic*: the same inputs yield the same survivor on every device,
///    so two devices resolving the same conflict independently converge
///    (identical content + parent ⇒ identical rev) instead of creating a new
///    conflict.
///  - *Stable*: resolving a partial leaf set in steps must converge to the same
///    result as resolving the whole set at once (conflict leaves can legitimately
///    arrive across separate replication batches). `KeepWinnerResolver` satisfies
///    both (it always lands on the global highest-(gen,hash) winner); custom
///    merges are the app's responsibility, exactly as in CouchDB/PouchDB.
///
/// **Data safety does NOT depend on this contract.** A non-deterministic or buggy
/// resolver — or an unreliable network, or a crash — can only cause *churn*
/// (redundant resolution rounds), never lost or corrupted data: the library only
/// ever tombstones the exact losing rev (a concurrent descendant survives),
/// resolution writes are local-first + resumable, and a failure on one document
/// leaves it conflicted (preserved) and retried later rather than aborting or
/// corrupting anything. Deliberately no threshold-based "stop resolving" breaker
/// (no heuristics); the worst case degrades to a preserved conflict.
abstract class DocumentConflictResolver {
  /// Returns the body to keep as the single surviving revision — one of
  /// [doc.winner] / [doc.conflicts], or a merged document — or `null` to leave
  /// the document in conflict (e.g. to resolve later in the UI). When non-null,
  /// the library writes it as a child of [doc.winner] and tombstones all the
  /// other leaves.
  Future<CouchDocumentBase?> resolve(ConflictedDocument doc);
}

/// Opt-in resolver that keeps CouchDB's deterministic winner and tombstones the
/// other leaves (deterministic last-writer-wins). Provided as a convenience —
/// it is **not** the default. The default (no resolver) preserves conflicts,
/// exactly like CouchDB.
class KeepWinnerResolver implements DocumentConflictResolver {
  const KeepWinnerResolver();

  @override
  Future<CouchDocumentBase?> resolve(ConflictedDocument doc) async => doc.winner;
}

enum ReplicationDirection { push, pull, both }

// TODO: Are all those states really needed?
enum ReplicationState {
  initializing,

  /// Initial one-shot synchronization in progress
  initialSyncInProgress,

  /// Initial sync completed successfully (no live replication requested)
  initialSyncComplete,

  /// Continuous replication is active and processing changes
  inSync,

  /// Replication is paused explicitly by the caller
  paused,

  /// Replication stopped temporarily while waiting for network recovery
  waitingForNetwork,

  /// Replication has been stopped permanently (e.g., controller.stop() or disposal)
  terminated,

  /// Replication encountered an error
  error,
}

class ReplicationProgress {
  final ReplicationState state;
  final bool targetReachable;
  final int transferredDocs;
  final int docsInNeedOfReplication;
  final String? lastSeq;
  final String? message;

  /// Bytes downloaded from source so far (cumulative across entire session).
  /// Updated as HTTP data arrives from the network.
  final int transferredBytes;

  /// Bytes written to the target database so far (cumulative across session).
  /// Updated after each successful write (bulkDocsFromMultipart / bulkDocsRaw).
  final int writtenBytes;

  /// Estimated total bytes to transfer (transferred so far + current batch).
  /// Only set during large batch transfers (≥5 docs). Null for small batches
  /// or when byte-level progress tracking is not meaningful.
  /// UI should only show byte-based progress when non-null.
  final int? totalBytesEstimate;

  /// Current batch number (1-based, 0 = not started)
  final int currentBatchIndex;

  /// Total number of batches (0 = unknown)
  final int totalBatches;

  ReplicationProgress({
    required this.state,
    this.targetReachable = true,
    this.transferredDocs = 0,
    this.docsInNeedOfReplication = 0,
    this.lastSeq,
    this.message,
    this.transferredBytes = 0,
    this.writtenBytes = 0,
    this.totalBytesEstimate,
    this.currentBatchIndex = 0,
    this.totalBatches = 0,
  });

  /// Download progress as a 0.0..1.0 fraction (bytes downloaded / estimate).
  double get downloadFraction {
    if (totalBytesEstimate != null && totalBytesEstimate! > 0) {
      return (transferredBytes / totalBytesEstimate!).clamp(0.0, 1.0);
    }
    return 0.0;
  }

  /// Write progress as a 0.0..1.0 fraction (bytes written / estimate).
  /// This is the more meaningful measure — data is safe once written.
  double get writeFraction {
    if (totalBytesEstimate != null && totalBytesEstimate! > 0) {
      return (writtenBytes / totalBytesEstimate!).clamp(0.0, 1.0);
    }
    final total = transferredDocs + docsInNeedOfReplication;
    if (total > 0) return (transferredDocs / total).clamp(0.0, 1.0);
    return 0.0;
  }

  /// Overall progress fraction. Uses [writeFraction] (write-based) as
  /// the primary measure since data is only safe once persisted.
  double get progressFraction => writeFraction;

  @override
  String toString() {
    final parts = <String>[
      'state=${state.name}',
      'targetReachable=$targetReachable',
      'transferredDocs=$transferredDocs',
      'docsInNeedOfReplication=$docsInNeedOfReplication',
      if (lastSeq != null) 'lastSeq=$lastSeq',
      if (message != null && message!.isNotEmpty) 'message=$message',
      if (transferredBytes > 0) 'transferredBytes=$transferredBytes',
      if (writtenBytes > 0) 'writtenBytes=$writtenBytes',
      if (totalBytesEstimate != null) 'totalBytesEstimate=$totalBytesEstimate',
      if (totalBatches > 0) 'batch=$currentBatchIndex/$totalBatches',
    ];
    return 'ReplicationProgress(${parts.join(', ')})';
  }
}
