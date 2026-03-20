import 'messages/couch_document_base.dart';

// DEAD CODE: DocumentReplicationConflictResolver and DefaultConflictResolver
// are currently unused. Replication uses newEdits=false (CouchDB protocol),
// which never produces 409 conflicts. Instead, conflicts are resolved
// deterministically by comparing revision hashes (higher hash wins),
// matching CouchDB's built-in behavior. See local_dart_couch_db.dart bulkDocsRaw().
abstract class DocumentReplicationConflictResolver {
  Future<CouchDocumentBase> resolveConflict(
    CouchDocumentBase local,
    CouchDocumentBase remote,
  );
}

class DefaultConflictResolver extends DocumentReplicationConflictResolver {
  static final DefaultConflictResolver instance = DefaultConflictResolver();

  @override
  Future<CouchDocumentBase> resolveConflict(
    CouchDocumentBase local,
    CouchDocumentBase remote,
  ) {
    return Future.value(remote);
  }
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
