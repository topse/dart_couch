import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'value_notifier.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'api_result.dart';
import 'dart_couch_db.dart';
import 'messages/bulk_get.dart';
import 'messages/bulk_get_multipart.dart';
import 'messages/couch_db_status_codes.dart';
import 'messages/couch_document_base.dart';
import 'replication_mixin_interface.dart';

final Logger _repLog = Logger('dart_couch-replication');

/// Replication log entry representing one replication session
class _ReplicationHistoryEntry {
  final int docsRead;
  final int docsWritten;
  final int docWriteFailures;
  final int missingChecked;
  final int missingFound;
  final String startTime;
  final String endTime;
  final String startLastSeq;
  final String endLastSeq;
  final String recordedSeq;
  final String sessionId;

  _ReplicationHistoryEntry({
    required this.docsRead,
    required this.docsWritten,
    required this.docWriteFailures,
    required this.missingChecked,
    required this.missingFound,
    required this.startTime,
    required this.endTime,
    required this.startLastSeq,
    required this.endLastSeq,
    required this.recordedSeq,
    required this.sessionId,
  });

  Map<String, dynamic> toMap() => {
    'docs_read': docsRead,
    'docs_written': docsWritten,
    'doc_write_failures': docWriteFailures,
    'missing_checked': missingChecked,
    'missing_found': missingFound,
    'start_time': startTime,
    'end_time': endTime,
    'start_last_seq': startLastSeq,
    'end_last_seq': endLastSeq,
    'recorded_seq': recordedSeq,
    'session_id': sessionId,
  };

  factory _ReplicationHistoryEntry.fromMap(Map<String, dynamic> map) =>
      _ReplicationHistoryEntry(
        docsRead: map['docs_read'] ?? 0,
        docsWritten: map['docs_written'] ?? 0,
        docWriteFailures: map['doc_write_failures'] ?? 0,
        missingChecked: map['missing_checked'] ?? 0,
        missingFound: map['missing_found'] ?? 0,
        startTime: map['start_time'] ?? '',
        endTime: map['end_time'] ?? '',
        startLastSeq: map['start_last_seq']?.toString() ?? '0',
        endLastSeq: map['end_last_seq']?.toString() ?? '0',
        recordedSeq: map['recorded_seq']?.toString() ?? '0',
        sessionId: map['session_id'] ?? '',
      );
}

/// Replication log document structure (CouchDB _local/{replication-id})
/// Replication checkpoint stored in the source database's _local namespace.
/// Tracks the last successfully replicated positions for both directions.
///
/// For bidirectional replication, we need TWO checkpoint values because:
/// - sourceLastSeq: Last position in source database's changes feed (for push)
/// - targetLastSeq: Last position in target database's changes feed (for pull)
///
/// These sequences live in different namespaces:
/// - LocalDartCouchDb: "6-dummyhash" (SQLite row ID)
/// - HttpDartCouchDb: "3-g1AAAACLeJzL..." (CouchDB opaque sequence)
///
/// Example: After bidirectional sync between local and remote:
/// - sourceLastSeq = "12-dummyhash" (local at position 12)
/// - targetLastSeq = "5-g1AAAA..." (remote at position 5)
///
/// On restart, push uses sourceLastSeq, pull uses targetLastSeq.
class _ReplicationLog {
  final String id;
  final String? rev;
  final List<_ReplicationHistoryEntry> history;
  final int replicationIdVersion;
  final String sessionId;

  /// Last sequence from source database (used for push direction).
  /// Always present for backward compatibility.
  final String sourceLastSeq;

  /// Last sequence from target database (used for pull direction).
  /// Added in later version - may be null for old checkpoints.
  final String? targetLastSeq;

  _ReplicationLog({
    required this.id,
    this.rev,
    required this.history,
    this.replicationIdVersion = 3,
    required this.sessionId,
    required this.sourceLastSeq,
    this.targetLastSeq,
  });

  Map<String, dynamic> toMap() => {
    '_id': id,
    if (rev != null) '_rev': rev,
    'history': history.map((e) => e.toMap()).toList(),
    'replication_id_version': replicationIdVersion,
    'session_id': sessionId,
    'source_last_seq': sourceLastSeq,
    if (targetLastSeq != null) 'target_last_seq': targetLastSeq,
  };

  factory _ReplicationLog.fromMap(Map<String, dynamic> map) {
    final historyList = (map['history'] as List?) ?? [];
    return _ReplicationLog(
      id: map['_id'] ?? '',
      rev: map['_rev'],
      history: historyList
          .map(
            (e) => _ReplicationHistoryEntry.fromMap(e as Map<String, dynamic>),
          )
          .toList(),
      replicationIdVersion: map['replication_id_version'] ?? 3,
      sessionId: map['session_id'] ?? '',
      sourceLastSeq: map['source_last_seq']?.toString() ?? '0',
      targetLastSeq: map['target_last_seq']?.toString(),
    );
  }
}

abstract class ReplicationController {
  void pause();
  void resume();
  Future<void> stop();

  /// Subscribe to replication progress updates.
  DcValueListenable<ReplicationProgress> get progress;
}

mixin CouchReplicationMixin on DartCouchDb {
  ReplicationController syncTo(
    DartCouchDb target, {
    bool live = false,
    ReplicationDirection direction = ReplicationDirection.both,
    required DocumentReplicationConflictResolver onConflict,
  }) {
    final controller = _CouchReplicationController(
      source: this,
      target: target,
      live: live,
      direction: direction,
      conflictResolver: onConflict,
    );

    controller._start();
    return controller;
  }
}

class _CouchReplicationController implements ReplicationController {
  final DartCouchDb source;
  final DartCouchDb target;
  final bool live;
  final ReplicationDirection direction;
  final DocumentReplicationConflictResolver conflictResolver;

  bool _paused = false;
  bool _stopped = false;
  ReplicationState _state = ReplicationState.initializing;
  bool _targetReachable = true;
  String? _checkpointSeq;
  String? _sourceSeq; // Last sequence from source database
  String? _targetSeq; // Last sequence from target database
  int _transferredDocs = 0;
  int _pendingPushDocs = 0;
  int _pendingPullDocs = 0;
  int _docsFetching =
      0; // Documents currently being fetched (getRaw in progress)
  int _docsFetchComplete = 0; // Documents successfully written to target

  // Byte-level progress tracking
  int _transferredBytes = 0; // bytes downloaded from source
  int _writtenBytes = 0; // bytes written to target
  int? _totalBytesEstimate;
  DateTime? _lastByteNotifyTime;
  static const Duration _notifyBytesInterval = Duration(seconds: 2);
  static const Duration _initialRetryDelay = Duration(seconds: 2);
  static const Duration _maxRetryDelay = Duration(minutes: 1);
  Duration _currentRetryDelay = _initialRetryDelay;

  // Session tracking
  late final String _sessionId;
  int _docsRead = 0;
  int _docsWritten = 0;
  int _docWriteFailures = 0;
  int _missingChecked = 0;
  int _missingFound = 0;
  String _startTime = '';
  String _startLastSeq = '0';

  StreamSubscription<Map<String, dynamic>>? _livePushSub;
  StreamSubscription<Map<String, dynamic>>? _livePullSub;

  // Checkpoint batching
  Timer? _checkpointTimer;
  static const Duration _checkpointInterval = Duration(seconds: 5);
  DateTime? _lastCheckpointSaveTime;
  static const Duration _maxCheckpointDelay = Duration(seconds: 10);

  /// Normalizes a sequence string for use with a specific database's changes feed.
  ///
  /// **Cross-namespace incompatibility handling:**
  /// Different database types use different sequence formats:
  /// - LocalDartCouchDb: "N-dummyhash" (SQLite row ID with dummy hash)
  /// - HttpDartCouchDb: "N-g1AAAACLeJzL..." (CouchDB opaque sequence)
  ///
  /// When querying a database's changes feed, we must pass a sequence that
  /// belongs to THAT database's namespace. If we try to use a local seq
  /// (e.g., "6-dummyhash") as a `since` parameter on an HTTP database,
  /// CouchDB will return "Malformed sequence" error.
  ///
  /// This method detects cross-namespace usage and returns null to force
  /// starting from the beginning (safe fallback).
  ///
  /// **Why this differs from recreation detection in _findCommonAncestry:**
  /// - Recreation detection: Compares seq against update_seq (same database)
  /// - This method: Validates seq before passing to changes feed (query param)
  ///
  /// Example scenarios:
  /// - Push (Local → HTTP): sourceSeq="6-dummyhash" used on local.changesRaw() ✓
  /// - Pull (HTTP → Local): targetSeq="3-g1AAA..." used on http.changesRaw() ✓
  /// - Edge case: Old checkpoint with only sourceSeq, used for pull → null ✓
  String? _normalizeSeqForDb(DartCouchDb db, String? seq) {
    if (seq == null) return null;

    // Detect cross-namespace usage: local seq on HTTP database
    if (seq.endsWith('-dummyhash')) {
      if (db.runtimeType.toString().contains('HttpDartCouch')) {
        // HTTP databases cannot understand local sequence tokens.
        // Return null to force starting from beginning (safe fallback).
        return null;
      }
    }

    // Same namespace or Local→Local: pass sequence through as-is
    return seq;
  }

  bool _pendingCheckpoint = false;

  /// Tracks the currently running replication loop so callers can await
  /// completion when shutting down.
  Future<void>? _runFuture;

  // Progress notifier
  late final DcValueNotifier<ReplicationProgress> _progressNotifier;

  _CouchReplicationController({
    required this.source,
    required this.target,
    required this.live,
    required this.direction,
    required this.conflictResolver,
  }) {
    // Generate a unique session ID for this replication session
    _sessionId = _generateSessionId();

    // Initialize progress notifier
    _progressNotifier = DcValueNotifier(_currentProgress());
  }

  /// Generate a random session ID (UUID-like)
  String _generateSessionId() {
    final random = Random();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void _start() {
    _runFuture ??= _run();
  }

  Future<void> _run() async {
    _repLog.info(
      'Starting replication: ${source.dbname} -> ${target.dbname}, direction: $direction, live: $live',
    );
    while (!_stopped) {
      try {
        _state = ReplicationState.initialSyncInProgress;
        _targetReachable = true;
        _startTime = DateTime.now().toUtc().toIso8601String();
        _repLog.fine('Replication state: syncing');
        _notify();

        await _checkPeer(source);
        await _checkPeer(target);

        // Load checkpoint with separate sequences for each direction
        final checkpoint = await _findCommonAncestry();
        _sourceSeq = checkpoint.sourceSeq ?? '0';
        _targetSeq = checkpoint.targetSeq ?? '0';
        _checkpointSeq = checkpoint.sourceSeq;
        _startLastSeq = _checkpointSeq ?? '0';
        _notify();

        // **Dual-Checkpoint Bidirectional Replication:**
        //
        // For bidirectional replication, we maintain TWO independent checkpoint
        // sequences to avoid re-fetching data on restart:
        //
        // Push direction:  source.changesRaw(since: sourceSeq)
        // Pull direction:  target.changesRaw(since: targetSeq)
        //
        // These sequences are in different namespaces (e.g., local "6-dummyhash"
        // vs remote "3-g1AAA..."), so each direction needs its own checkpoint.
        //
        // Without this, on restart the pull direction would try to use the local
        // seq against the remote changes feed, which would fail validation in
        // _normalizeSeqForDb and force a full re-fetch of all remote data.
        //
        // **Continuous replication timing:**
        // Continuous feeds are started AFTER one-shot completes, using the
        // lastSeq from each one-shot direction. This avoids duplicate fetches
        // (which would double network traffic for large attachments) while
        // still not missing any changes: CouchDB's continuous changes feed
        // with since=lastSeq replays any changes that occurred during one-shot
        // (their sequences are newer than the initial checkpoint).

        if (direction == ReplicationDirection.push ||
            direction == ReplicationDirection.both) {
          final lastSeq = await _replicateOnce(
            source,
            target,
            sinceSeq: _sourceSeq, // Use source seq for push
            saveCheckpoint: false,
          );
          if (lastSeq != null) _sourceSeq = lastSeq;
        }
        if (direction == ReplicationDirection.pull ||
            direction == ReplicationDirection.both) {
          final lastSeq = await _replicateOnce(
            target,
            source,
            sinceSeq: _targetSeq, // Use target seq for pull
            saveCheckpoint: false,
          );
          if (lastSeq != null) _targetSeq = lastSeq;
        }

        // After pull one-shot populated the local DB with remote docs,
        // update _sourceSeq to the current local sequence so push
        // continuous doesn't re-process all just-pulled docs through
        // revsDiff (which would all return "nothing to write").
        if (direction == ReplicationDirection.both) {
          final sourceInfo = await source.info();
          if (sourceInfo != null) {
            final currentSourceSeq = sourceInfo.updateSeq;
            _repLog.fine(
              'Updating _sourceSeq from $_sourceSeq to $currentSourceSeq '
              'after pull one-shot populated local DB',
            );
            _sourceSeq = currentSourceSeq;
          }
        }

        // Save checkpoint after both directions complete. One-shot uses
        // saveCheckpoint: false to avoid saving between push and pull, but
        // now that both are done we record the position so continuous
        // replication (and restarts) can resume from here.
        if (!_stopped) {
          _scheduleCheckpoint();
        }

        if (live && !_stopped) {
          _startContinuousReplication();
          _state = ReplicationState.inSync;
          _repLog.info(
            'Transitioning to continuous replication. '
            'Push from sourceSeq=$_sourceSeq, Pull from targetSeq=$_targetSeq',
          );
          _repLog.info(
            'Replication in sync: ${source.dbname} -> ${target.dbname}',
          );
          _markReachable();
          _notify();
        } else if (!_stopped) {
          // one-shot replication finished successfully
          _state = ReplicationState.initialSyncComplete;
          _repLog.info(
            'Replication completed successfully: ${source.dbname} -> ${target.dbname}',
          );
          _markReachable();
          _notify();
        }
        return;
      } catch (e, st) {
        final shouldRetry = _processFailure(e, st);
        if (!shouldRetry) {
          return;
        }
        await _waitForRetry();
      }
    }
  }

  Future<void> _checkPeer(DartCouchDb db) async {
    if (await db.info() == null) {
      throw CouchDbException(
        CouchDbStatusCodes.notFound,
        'Database not found: ${db.dbname}',
      );
    }
  }

  /// Load the last checkpoint sequences from the local database.
  /// Returns both the source (push) and target (pull) sequences so each
  /// direction can resume from its own position.
  ///
  /// Checkpoints are only stored locally since they are instance-specific
  /// (sequence numbers and session IDs are meaningless to other instances).
  ///
  /// **Recreation Detection (Deterministic - NO HEURISTICS)**
  /// Detects if the target database was deleted and recreated by comparing
  /// the target's checkpoint seq against its current update_seq. If the current
  /// update_seq is LOWER than the checkpoint (regression), the database was
  /// recreated and we invalidate the checkpoint to force a full resync.
  ///
  /// This check is DETERMINISTIC (sequence regression = recreation). It works
  /// for all database type combinations:
  /// - HTTP → HTTP: CouchDB seq "5-g1AAA..." vs updateSeqNumber 1 → detected ✓
  /// - Local → Local: Local seq "10-dummyhash" vs updateSeqNumber 0 → detected ✓
  /// - HTTP → Local: Local seq "10-dummyhash" vs updateSeqNumber 0 → detected ✓
  /// - Local → HTTP: CouchDB seq "5-g1AAA..." vs updateSeqNumber 1 → detected ✓
  ///
  /// The key insight: we're comparing targetLastSeq (from checkpoint) against
  /// target.info().updateSeqNumber (current), always staying within the same
  /// database's namespace, so the comparison is always valid regardless of
  /// whether the database is HTTP or Local.
  ///
  /// **CRITICAL: NO HEURISTICS**
  /// Do NOT add arbitrary threshold checks like "if seq < 10". These cause
  /// race conditions and sporadic failures. All detection must be deterministic.
  /// See MEMORY.md for project guidelines.
  Future<({String? sourceSeq, String? targetSeq})> _findCommonAncestry() async {
    const nullResult = (sourceSeq: null, targetSeq: null);
    final replId = _replicationId();

    try {
      // Get target database info to check if it's been recreated
      final targetInfo = await target.info();
      if (targetInfo == null) {
        return nullResult;
      }

      final doc = await source.get("_local/$replId");
      if (doc != null) {
        final log = _ReplicationLog.fromMap(doc.toMap());

        // Check for update_seq regression (indicates database recreation).
        // This works for all database types (HTTP, Local) because we're comparing
        // the target's checkpoint seq against its current seq.
        if (log.targetLastSeq != null) {
          try {
            final currentSeqNum = targetInfo.updateSeqNumber;
            final checkpointSeqNum = int.parse(
              log.targetLastSeq!.split('-')[0],
            );

            if (currentSeqNum < checkpointSeqNum) {
              _repLog.info(
                'Target database appears to have been recreated (update_seq regressed from '
                '$checkpointSeqNum to $currentSeqNum). '
                'Invalidating checkpoint and starting fresh sync.',
              );
              // Delete the old checkpoint document
              try {
                await source.remove(doc.id!, doc.rev!);
              } catch (e) {
                _repLog.fine('Failed to delete old checkpoint: $e');
              }
              return nullResult;
            }
          } catch (e) {
            // Failed to parse sequences - continue with checkpoint
            _repLog.fine(
              'Could not parse sequences for recreation detection: $e',
            );
          }
        }

        // Old checkpoint format (before targetLastSeq was added) or new format.
        // For old checkpoints, targetLastSeq will be null.
        // Don't fall back to sourceLastSeq - it's in the wrong namespace for pull direction.
        // Better to do a one-time full pull sync and save the correct dual checkpoint.
        return (sourceSeq: log.sourceLastSeq, targetSeq: log.targetLastSeq);
      }
    } catch (_) {
      // No checkpoint exists - this is first replication
    }

    return nullResult;
  }

  /// Schedule a checkpoint save (batched to avoid excessive writes).
  /// Saves both `_sourceSeq` and `_targetSeq` so each direction can resume
  /// from its own position after restart.
  ///
  /// **Prevents infinite timer resets:** If continuous changes arrive rapidly,
  /// each would normally cancel and restart the timer, preventing checkpoint
  /// from ever being saved. To prevent this, we force a save after
  /// `_maxCheckpointDelay` (10s) regardless of new changes.
  void _scheduleCheckpoint() {
    // Update in-memory checkpoint immediately so progress reports current position
    _checkpointSeq = _sourceSeq;
    _pendingCheckpoint = true;
    _notify();

    final now = DateTime.now();
    final timeSinceLastSave = _lastCheckpointSaveTime == null
        ? _maxCheckpointDelay
        : now.difference(_lastCheckpointSaveTime!);

    // Force save if too much time has elapsed since last save
    if (timeSinceLastSave >= _maxCheckpointDelay) {
      _repLog.fine(
        'Forcing checkpoint save after ${timeSinceLastSave.inSeconds}s delay',
      );
      _checkpointTimer?.cancel();
      unawaited(_saveCheckpointNow());
      return;
    }

    // Batch checkpoint saves to avoid excessive disk writes
    _checkpointTimer?.cancel();
    _checkpointTimer = Timer(_checkpointInterval, () async {
      if (_pendingCheckpoint && !_stopped) {
        await _saveCheckpointNow();
      }
    });
  }

  /// Internal helper to save checkpoint and update tracking
  Future<void> _saveCheckpointNow() async {
    try {
      await _saveCheckpoint();
      _pendingCheckpoint = false;
      _lastCheckpointSaveTime = DateTime.now();
    } catch (e) {
      // Checkpoint save failed (likely network error). This is non-fatal.
      // The in-memory seqs are already updated, and we'll retry on next interval.
      _repLog.fine('Failed to save checkpoint: $e');
    }
  }

  /// Save checkpoint to local database only.
  ///
  /// Checkpoints are instance-specific - storing them on the remote server
  /// would cause conflicts when multiple app instances sync the same databases.
  ///
  /// **Dual-checkpoint storage:**
  /// For bidirectional replication, we save BOTH sequences:
  /// - sourceLastSeq: Position in source changes feed (for push direction)
  /// - targetLastSeq: Position in target changes feed (for pull direction)
  ///
  /// This prevents re-fetching all data on restart when the sequences are in
  /// different namespaces (e.g., local "12-dummyhash" vs remote "5-g1AAA...").
  ///
  /// Example: After syncing local↔remote with 12 local and 5 remote changes:
  /// - sourceLastSeq = "12-dummyhash" → push resumes from local position 12
  /// - targetLastSeq = "5-g1AAA..." → pull resumes from remote position 5
  Future<void> _saveCheckpoint() async {
    final sourceSeq = _sourceSeq ?? '0';
    final endTime = DateTime.now().toUtc().toIso8601String();
    final replId = _replicationId();

    // Create history entry for this session
    final historyEntry = _ReplicationHistoryEntry(
      docsRead: _docsRead,
      docsWritten: _docsWritten,
      docWriteFailures: _docWriteFailures,
      missingChecked: _missingChecked,
      missingFound: _missingFound,
      startTime: _startTime,
      endTime: endTime,
      startLastSeq: _startLastSeq,
      endLastSeq: sourceSeq,
      recordedSeq: sourceSeq,
      sessionId: _sessionId,
    );

    // Load existing log to preserve history
    _ReplicationLog? existingLog;
    try {
      final doc = await source.get("_local/$replId");
      if (doc != null) {
        existingLog = _ReplicationLog.fromMap(doc.toMap());
      }
    } catch (_) {}

    // Build new log with updated history (keep last 50 entries)
    final List<_ReplicationHistoryEntry> history = [
      historyEntry,
      ...(existingLog?.history ?? <_ReplicationHistoryEntry>[]),
    ].take(50).toList();

    // Save both checkpoint sequences for bidirectional replication
    final newLog = _ReplicationLog(
      id: "_local/$replId",
      rev: existingLog?.rev,
      history: history,
      sessionId: _sessionId,
      sourceLastSeq: sourceSeq,
      targetLastSeq: _targetSeq, // Added for dual-checkpoint support
    );

    // Save to local database only
    final logMap = newLog.toMap();

    final logDoc = CouchDocumentBase(
      id: newLog.id,
      rev: newLog.rev,
      unmappedProps: logMap,
    );
    await source.put(logDoc);

    _checkpointSeq = sourceSeq;
    _notify();
  }

  String _replicationId() =>
      "${source.dbname}::${target.dbname}::${direction.name}";

  /// Update the correct in-memory seq field based on replication direction.
  ///
  /// Used by continuous replication to track progress independently for each
  /// direction. The 'label' parameter identifies which changes feed produced
  /// this seq:
  /// - 'push': seq from source.changesRaw() → update _sourceSeq
  /// - 'pull': seq from target.changesRaw() → update _targetSeq
  ///
  /// This ensures that when _scheduleCheckpoint() is called, both seq values
  /// are current and will be saved to the checkpoint document.
  void _updateSeqForDirection(String label, String seq) {
    if (label == 'push') {
      _sourceSeq = seq;
    } else {
      _targetSeq = seq;
    }
  }

  /// Normalize doc shapes returned by bulk_get implementations so replication
  /// always writes a plain CouchDB doc map with `_id` and `_rev`.
  Map<String, dynamic>? _normalizeReplicationDoc(Map<String, dynamic> raw) {
    if (raw['_id'] is String && raw['_rev'] is String) {
      return raw;
    }

    final ok = raw['ok'];
    if (ok is Map<String, dynamic>) {
      if (ok['_id'] is String && ok['_rev'] is String) {
        return Map<String, dynamic>.from(ok);
      }
    }

    final docs = raw['docs'];
    if (docs is List && docs.isNotEmpty) {
      final first = docs.first;
      if (first is Map<String, dynamic>) {
        final nestedOk = first['ok'];
        if (nestedOk is Map<String, dynamic> &&
            nestedOk['_id'] is String &&
            nestedOk['_rev'] is String) {
          return Map<String, dynamic>.from(nestedOk);
        }
      }
    }

    return null;
  }

  Future<String?> _replicateOnce(
    DartCouchDb from,
    DartCouchDb to, {
    String? sinceSeq,
    bool saveCheckpoint = true,
  }) async {
    final replicateOnceStopwatch = Stopwatch()..start();
    final normalizedSeq = _normalizeSeqForDb(from, sinceSeq ?? _checkpointSeq);
    _repLog.fine(
      'Replicating from ${from.dbname} to ${to.dbname}, using since: $normalizedSeq, saveCheckpoint: $saveCheckpoint',
    );
    var phaseStopwatch = Stopwatch()..start();
    final changesJson = await from
        .changesRaw(since: normalizedSeq, styleAllDocs: true)
        .first;

    final results = changesJson['results'] as List<dynamic>;
    final lastSeq = changesJson['last_seq'] as String?;

    _repLog.info(
      'Changes feed: ${results.length} changes from ${from.dbname} '
      'in ${phaseStopwatch.elapsedMilliseconds}ms',
    );
    if (results.isEmpty) return lastSeq!;

    // Build revsMap from the changes response
    final Map<String, List<String>> revsMap = {};

    for (final changeEntry in results) {
      final changeMap = changeEntry as Map<String, dynamic>;
      final id = changeMap['id'] as String;
      final changesArray = changeMap['changes'] as List<dynamic>;
      final revs = changesArray
          .map((c) => (c as Map<String, dynamic>)['rev'] as String)
          .toList();
      revsMap[id] = revs;
    }

    _missingChecked += revsMap.length;
    phaseStopwatch = Stopwatch()..start();
    final missing = await to.revsDiff(revsMap);
    _missingFound += missing.length;
    _repLog.info(
      'revsDiff: ${revsMap.length} checked, ${missing.length} missing '
      'in ${phaseStopwatch.elapsedMilliseconds}ms',
    );

    // Count total revisions to fetch for progress tracking
    int totalRevsToFetch = 0;
    for (final entry in missing.entries) {
      if (!entry.key.startsWith('_local/')) {
        totalRevsToFetch += (entry.value.missing?.length ?? 0);
      }
    }
    _docsFetching = totalRevsToFetch;
    _docsFetchComplete = 0;
    if (totalRevsToFetch > 0) {
      _notify('Fetching $totalRevsToFetch document revisions...');
    }

    // Build bulk request for all missing documents/revisions
    final List<BulkGetRequestDoc> bulkGetDocs = [];

    // Filter out local documents (_local/*) as per CouchDB replication protocol
    for (final entry in missing.entries) {
      final docId = entry.key;

      _repLog.finest('Processing document $docId for replication');

      // Skip local documents - they should not be replicated
      if (docId.startsWith('_local/')) {
        _repLog.fine('Skipping local document $docId');
        continue;
      }

      final missingRevs = List<String>.from(entry.value.missing ?? []);
      // Pass possible_ancestors as atts_since so the source only sends
      // attachment data that has changed since a revision the target already
      // holds. Unchanged attachments are returned as lightweight stubs.
      final attsSince = entry.value.possibleAncestors?.isNotEmpty == true
          ? entry.value.possibleAncestors
          : null;
      for (final rev in missingRevs) {
        bulkGetDocs.add(
          BulkGetRequestDoc(id: docId, rev: rev, attsSince: attsSince),
        );
      }
    }

    // Fetch and write documents using memory-efficient multipart streaming.
    //
    // Docs are fetched via bulkGetMultipart() and written via
    // bulkDocsFromMultipart(). For a local target this pipes attachment bytes
    // directly to the att/{id} files on disk — no base64 decode, no large
    // in-memory buffers. For an HTTP target the HTTP bulkGetMultipart()
    // implementation eagerly drains each attachment part before yielding, so
    // peak memory equals the largest single attachment in the batch rather
    // than the whole batch combined.
    //
    // The approach:
    //   - First, a lightweight stub fetch (attachments=false) estimates the
    //     total download size from attachment metadata (length fields).
    //   - Then _streamingReplicate() uses two concurrent HTTP pipelines that
    //     each fetch docs in small groups, writing each doc immediately as it
    //     arrives. This overlaps HTTP download with local disk write.
    //   - Progress is updated after each fetched document with both document
    //     count and byte-level information.
    if (bulkGetDocs.isNotEmpty) {
      if (_stopped) return lastSeq!;
      if (_paused) await _waitWhilePaused();

      // Phase 1: Estimate total download size via a lightweight stub fetch.
      // This calls bulkGetRaw(attachments: false) which returns only JSON
      // metadata (no binary data), including attachment stubs with 'length'
      // fields. From these we compute the expected raw transfer size.
      // Skipped for small sets (<5 docs) where the overhead isn't worth it.
      //
      // Note: _transferredBytes accumulates across the entire session (like
      // _transferredDocs), while _totalBytesEstimate is only meaningful during
      // large batch transfers. The UI should only show byte-based progress when
      // estimate is non-null.
      Map<String, int>? sizeEstimates;
      if (bulkGetDocs.length >= 5) {
        _notify('Estimating download size...');
        phaseStopwatch = Stopwatch()..start();
        sizeEstimates = await _estimateDocSizes(from, bulkGetDocs);
        final batchEstimate = sizeEstimates.values.fold<int>(
          0,
          (sum, v) => sum + v,
        );
        // Add batch estimate to running total for this batch only
        _totalBytesEstimate = _transferredBytes + batchEstimate;
        _repLog.info(
          'Size estimation: ${_formatBytes(batchEstimate)} for '
          '${bulkGetDocs.length} docs in ${phaseStopwatch.elapsedMilliseconds}ms',
        );
      } else {
        // For small batches, clear estimate - byte progress not meaningful
        // for small transfers. _transferredBytes continues to accumulate.
        _totalBytesEstimate = null;
      }

      _notify('Downloading ${bulkGetDocs.length} documents...');

      phaseStopwatch = Stopwatch()..start();
      await _streamingReplicate(
        from,
        to,
        bulkGetDocs,
        totalRevsToFetch,
        sizeEstimates: sizeEstimates,
      );
      _repLog.info(
        'Streaming replicate: ${bulkGetDocs.length} docs in '
        '${phaseStopwatch.elapsedMilliseconds}ms '
        '(${_transferredBytes > 0 ? '${_formatBytes((_transferredBytes * 1000 / phaseStopwatch.elapsedMilliseconds).round())}/s' : 'n/a'})',
      );

      _docsFetchComplete = 0;
      _notify();
    }

    _repLog.info(
      'One-shot replication complete: ${from.dbname} -> ${to.dbname} '
      'in ${replicateOnceStopwatch.elapsedMilliseconds}ms',
    );

    if (saveCheckpoint && lastSeq != null) {
      try {
        // Update the appropriate seq field before saving
        _sourceSeq = lastSeq;
        await _saveCheckpoint();
      } catch (e) {
        // Checkpoint save failed (likely network error). This is non-fatal.
        // Replication completed successfully, checkpoint is just for optimization.
        _repLog.fine(
          'Failed to save checkpoint after one-shot replication: $e',
        );
      }
    }
    _notify();
    _markReachable();
    return lastSeq!;
  }

  /// Call _ensure_full_commit endpoint (CouchDB protocol recommendation)
  Future<void> _ensureFullCommit(DartCouchDb db) async {
    // This would require adding an ensureFullCommit method to DartCouchDb interface
    // For now, we skip this as it's optional
    // In a full implementation: POST /{db}/_ensure_full_commit
  }

  /// Starts continuous changes feed listeners based on replication direction.
  ///
  /// Uses DartCouchDb.changesFeed() with continuous=true, mirroring CouchDB's
  /// `_changes?feed=continuous` semantics.
  void _startContinuousReplication() {
    unawaited(_livePushSub?.cancel() ?? Future.value());
    unawaited(_livePullSub?.cancel() ?? Future.value());

    if (direction == ReplicationDirection.push ||
        direction == ReplicationDirection.both) {
      _livePushSub = _createChangeStream(source, target, 'push', _sourceSeq);
    }

    if (direction == ReplicationDirection.pull ||
        direction == ReplicationDirection.both) {
      _livePullSub = _createChangeStream(target, source, 'pull', _targetSeq);
    }
  }

  /// Creates a continuous changes stream from [from] to [to].
  StreamSubscription<Map<String, dynamic>> _createChangeStream(
    DartCouchDb from,
    DartCouchDb to,
    String label,
    String? sinceSeq,
  ) {
    // Use the sequence from the initial replication of this specific database
    final normalizedSeq = _normalizeSeqForDb(from, sinceSeq);
    _repLog.fine(
      'Creating $label change stream from ${from.dbname} with since: $normalizedSeq (original: $sinceSeq)',
    );
    // -------------------------------------------------------------------------
    // Algorithm: serialised-pause backpressure
    // -------------------------------------------------------------------------
    // Dart's StreamSubscription.listen() does NOT await async callbacks.
    // Without countermeasures every change event from the continuous feed is
    // dispatched immediately, even while the previous one is still being
    // processed. When the companion app uploads many tracks in rapid
    // succession this creates dozens of concurrent bulkGetMultipart calls,
    // each eagerly buffering a full audio attachment (~50–100 MB) as a
    // Uint8List before the result is yielded. The accumulated allocations
    // exhaust the device heap → Out-of-Memory crash.
    //
    // Fix: call sub.pause() at the very start of the callback so the stream
    // stops delivering the next event. The CouchDB continuous changes feed
    // (and Dart's HTTP stream buffer) holds pending events safely. After the
    // current document's attachment has been written to disk, sub.resume() is
    // called in a `finally` block, unconditionally allowing the next event
    // to be delivered.
    //
    // Result: at most ONE document and its attachments is in memory at a time,
    // regardless of how fast the companion app pushes changes.
    //
    // TODO: replace this pause/resume approach with a true streaming pipeline
    //   that pipes each attachment's byte stream directly from the HTTP
    //   response into the local SQLite/file store without ever materialising
    //   the full Uint8List in heap memory. This would eliminate the per-
    //   attachment peak and allow pipelining multiple documents while keeping
    //   memory consumption proportional to a single read buffer rather than a
    //   single complete attachment.
    // -------------------------------------------------------------------------

    // Use a late variable so the async callback can safely reference `sub`.
    // Dart event delivery is deferred to the next microtask/event so the
    // assignment always completes before the first callback fires.
    late final StreamSubscription<Map<String, dynamic>> sub;
    sub = from
        .changesRaw(
          since: normalizedSeq,
          feedmode: FeedMode.continuous,
          styleAllDocs: true,
          // 30 s heartbeat keeps the connection alive well within the
          // typical 60-second proxy_read_timeout of reverse proxies such
          // as the Synology nginx gateway.
          heartbeat: 30000,
        )
        .listen(
          (changeJson) async {
            if (_stopped || _paused) return;
            // Serialise processing: pause delivery of the next change until
            // this one's attachment bytes have been fully written to disk.
            // Resumed unconditionally in the `finally` block below.
            sub.pause();
            try {
              final Map<String, List<String>> revsMap = {};

              // Parse the raw JSON change entry
              final id = changeJson['id'] as String;
              final changesArray = changeJson['changes'] as List<dynamic>;
              final revs = changesArray
                  .map((c) => (c as Map<String, dynamic>)['rev'] as String)
                  .toList();
              revsMap[id] = revs;

              if (revsMap.isEmpty) return;

              _missingChecked += revsMap.length;
              final missing = await to.revsDiff(revsMap);
              _missingFound += missing.length;

              if (missing.isEmpty) {
                _repLog.fine(
                  'Continuous [$label]: change for $id already in sync '
                  '(revsDiff returned nothing missing)',
                );
              }

              // Count total revisions to fetch for progress tracking
              int totalRevsToFetch = 0;
              for (final entry in missing.entries) {
                if (!entry.key.startsWith('_local/')) {
                  totalRevsToFetch += (entry.value.missing?.length ?? 0);
                }
              }
              if (totalRevsToFetch > 0) {
                _docsFetching += totalRevsToFetch;
                _notify('Fetching $totalRevsToFetch new changes...');
              }

              // Count of docs written immediately via multipart streaming.
              int multipartDocsWritten = 0;
              // Docs fetched individually as fallback (JSON strings).
              final rawFallbacks = <String>[];

              // Build bulk request for all missing documents/revisions
              final List<BulkGetRequestDoc> bulkGetDocs = [];

              // Filter out local documents (_local/*) as per CouchDB replication protocol
              for (final entry in missing.entries) {
                final docId = entry.key;

                _repLog.fine(
                  'Processing document $docId for continuous replication',
                );

                // Skip local documents - they should not be replicated
                if (docId.startsWith('_local/')) {
                  _repLog.fine(
                    'Skipping local document $docId in continuous replication',
                  );
                  continue;
                }

                // Log design documents
                if (docId.startsWith('_design/')) {
                  _repLog.fine(
                    'Replicating design document $docId in continuous replication',
                  );
                }

                final missingRevs = List<String>.from(
                  entry.value.missing ?? [],
                );
                // Pass possible_ancestors as atts_since so unchanged
                // attachments are returned as stubs instead of re-downloading.
                final attsSince =
                    entry.value.possibleAncestors?.isNotEmpty == true
                    ? entry.value.possibleAncestors
                    : null;
                for (final rev in missingRevs) {
                  bulkGetDocs.add(
                    BulkGetRequestDoc(
                      id: docId,
                      rev: rev,
                      attsSince: attsSince,
                    ),
                  );
                }
              }

              // Fetch all documents via multipart streaming
              if (bulkGetDocs.isNotEmpty) {
                if (_stopped) return;
                if (_paused) return;

                final processedKeys = <String>{};
                final failedDocs = <BulkGetRequestDoc>[];

                try {
                  final bulkGetRequest = BulkGetRequest(docs: bulkGetDocs);

                  await for (final result in from.bulkGetMultipart(
                    bulkGetRequest,
                    revs: true,
                  )) {
                    if (_stopped) break;

                    if (result is BulkGetMultipartSuccess) {
                      final normalizedDoc = _normalizeReplicationDoc(
                        Map<String, dynamic>.from(result.ok.doc),
                      );
                      if (normalizedDoc == null) {
                        _repLog.warning(
                          'Continuous [$label]: received malformed bulk_get success doc '
                          'without required _id/_rev. Keys: ${result.ok.doc.keys.toList()}, '
                          'meta: ${result.ok.doc.entries.where((e) => e.key.startsWith("_")).map((e) => "${e.key}: ${e.value}").toList()}',
                        );
                        _docsFetching--;
                        _docsFetchComplete++;
                        _notify('Syncing changes...');
                        continue;
                      }

                      final docId = normalizedDoc['_id'] as String;
                      final docRev = normalizedDoc['_rev'] as String;
                      _docsRead++;
                      _transferredBytes += jsonEncode(normalizedDoc).length;

                      // Write each doc immediately as it arrives from the
                      // stream to keep peak memory at one doc's attachments.
                      final success = BulkGetMultipartSuccess(
                        BulkGetMultipartOk(
                          doc: normalizedDoc,
                          attachments: result.ok.attachments,
                        ),
                      );
                      await to.bulkDocsFromMultipart(
                        [success],
                        newEdits: false,
                      );
                      // Mark as processed AFTER successful write so that on
                      // stream error the fallback loop can retry this doc.
                      processedKeys.add('$docId:$docRev');
                      multipartDocsWritten++;
                      _docsWritten++;
                      _transferredDocs++;
                      _writtenBytes += jsonEncode(normalizedDoc).length;
                    } else if (result is BulkGetMultipartFailure) {
                      processedKeys.add('${result.id}:${result.rev ?? ""}');
                      final rev = result.rev;
                      _repLog.warning(
                        'Bulk fetch failed for document ${result.id} rev $rev: '
                        '${result.error} - ${result.reason}',
                      );
                      if (rev != null) {
                        failedDocs.add(
                          BulkGetRequestDoc(id: result.id, rev: rev),
                        );
                      }
                    }

                    _docsFetching--;
                    _docsFetchComplete++;
                    _notify('Syncing changes...');
                  }

                  // Retry failed documents individually
                  if (failedDocs.isNotEmpty) {
                    _repLog.info(
                      'Retrying ${failedDocs.length} failed documents individually',
                    );
                    for (final bulkDoc in failedDocs) {
                      if (_stopped) break;
                      if (_paused) continue;

                      try {
                        var doc = await from.getRaw(
                          bulkDoc.id,
                          rev: bulkDoc.rev,
                          revs: true,
                          attachments: true,
                        );
                        if (doc == null) {
                          _repLog.fine(
                            'Rev ${bulkDoc.rev} gone for ${bulkDoc.id}, fetching current rev',
                          );
                          doc = await from.getRaw(
                            bulkDoc.id,
                            revs: true,
                            attachments: true,
                          );
                        }
                        if (doc != null) {
                          final encoded = jsonEncode(doc);
                          rawFallbacks.add(encoded);
                          _docsRead++;
                          _transferredBytes += encoded.length;
                        } else {
                          _repLog.warning(
                            'Continuous: document ${bulkDoc.id} rev '
                            '${bulkDoc.rev} not found (both specific '
                            'and current rev returned null) — skipping',
                          );
                        }
                      } catch (e) {
                        _repLog.warning(
                          'Individual fetch also failed for document ${bulkDoc.id} rev ${bulkDoc.rev}: $e',
                        );
                      }
                    }
                  }
                } catch (e) {
                  _repLog.warning('Failed to bulk fetch documents: $e');
                  // Fall back to individual fetches for unprocessed docs
                  for (final bulkDoc in bulkGetDocs) {
                    if (_stopped) break;
                    if (_paused) continue;
                    final key = '${bulkDoc.id}:${bulkDoc.rev ?? ""}';
                    if (processedKeys.contains(key)) continue;

                    try {
                      var doc = await from.getRaw(
                        bulkDoc.id,
                        rev: bulkDoc.rev,
                        revs: true,
                        attachments: true,
                      );
                      doc ??= await from.getRaw(
                        bulkDoc.id,
                        revs: true,
                        attachments: true,
                      );
                      if (doc != null) {
                        final encoded = jsonEncode(doc);
                        rawFallbacks.add(encoded);
                        _docsRead++;
                        _transferredBytes += encoded.length;
                      } else {
                        _repLog.warning(
                          'Continuous: document ${bulkDoc.id} rev '
                          '${bulkDoc.rev} not found (both specific '
                          'and current rev returned null) — skipping',
                        );
                      }
                    } catch (e) {
                      _repLog.warning(
                        'Failed to fetch document ${bulkDoc.id} rev ${bulkDoc.rev}: $e',
                      );
                    }

                    _docsFetching--;
                    _docsFetchComplete++;
                    _notify('Syncing changes...');
                  }
                }
              }

              // If replication was stopped while we were mid-stream (e.g.
              // setDelegate called stop() during recovery), do NOT advance the
              // checkpoint. The doc(s) we fetched but didn't write will be
              // re-processed by the next replication from the old checkpoint.
              if (_stopped) return;

              // Extract sequence number before attempting replication
              final seq = changeJson['seq'] as String?;

              // Multipart docs were already written inline above.
              // Only raw fallbacks remain to be written in a batch.
              final totalToWrite =
                  multipartDocsWritten + rawFallbacks.length;

              if (totalToWrite > 0) {
                if (label == 'push') {
                  _pendingPushDocs += totalToWrite;
                } else {
                  _pendingPullDocs += totalToWrite;
                }
                _notify();

                try {
                  if (rawFallbacks.isNotEmpty) {
                    await to.bulkDocsRaw(rawFallbacks, newEdits: false);
                    _docsWritten += rawFallbacks.length;
                    _transferredDocs += rawFallbacks.length;
                    for (final raw in rawFallbacks) {
                      _writtenBytes += raw.length;
                    }
                  }
                  _docsFetchComplete = 0; // Reset after successful send
                  _repLog.info(
                    'Continuous [$label]: wrote $totalToWrite doc(s) '
                    'to ${to.dbname} for change $id',
                  );

                  if (label == 'push') {
                    _pendingPushDocs -= totalToWrite;
                  } else {
                    _pendingPullDocs -= totalToWrite;
                  }
                  _notify();

                  // Only save checkpoint after successful replication
                  if (seq != null) {
                    _updateSeqForDirection(label, seq);
                    _scheduleCheckpoint();
                  }
                } catch (e) {
                  _repLog.warning(
                    'Failed to replicate ${rawFallbacks.length} fallback documents in continuous mode: $e',
                  );
                  _docWriteFailures += rawFallbacks.length;
                  _docsFetchComplete = 0; // Reset even on failure
                  if (label == 'push') {
                    _pendingPushDocs -= totalToWrite;
                  } else {
                    _pendingPullDocs -= totalToWrite;
                  }
                  _notify();
                  // Don't save checkpoint on failure - will retry from last successful position
                }
              } else {
                // No documents to replicate, but still update checkpoint
                // to mark this change as processed
                _repLog.fine(
                  'Continuous [$label]: nothing to write for change $id '
                  '(missing=${missing.length}, bulkGetDocs=${bulkGetDocs.length})',
                );
                if (seq != null) {
                  _updateSeqForDirection(label, seq);
                  _scheduleCheckpoint();
                }
              }

              _markReachable();
            } catch (e, st) {
              await _handleLiveStreamError(e, st, label);
            } finally {
              // Resume the subscription so the next change can be delivered.
              // If _handleLiveStreamError restarted continuous replication,
              // `sub` is already cancelled; resume() is a no-op on cancelled
              // subscriptions in Dart, so this is always safe.
              if (!_stopped) sub.resume();
            }
          },
          onError: (Object error, StackTrace stackTrace) async {
            await _handleLiveStreamError(error, stackTrace, label);
          },
          cancelOnError: true,
        );
    return sub;
  }

  Future<void> _handleLiveStreamError(
    Object error,
    StackTrace stackTrace,
    String label,
  ) async {
    if (_stopped) return;
    final shouldRetry = _processFailure(error, stackTrace);
    if (!shouldRetry) return;
    await _waitForRetry();
    if (!_stopped) {
      // Reload checkpoint before restarting continuous replication
      // to ensure we continue from the correct sequence
      final checkpoint = await _findCommonAncestry();
      _sourceSeq = checkpoint.sourceSeq ?? _sourceSeq;
      _targetSeq = checkpoint.targetSeq ?? _targetSeq;
      _checkpointSeq = checkpoint.sourceSeq ?? _checkpointSeq;
      _notify();
      _startContinuousReplication();
    }
  }

  void _markReachable() {
    if (!_targetReachable) {
      _targetReachable = true;
    }
    if (live && !_paused && _state == ReplicationState.waitingForNetwork) {
      _state = ReplicationState.inSync;
    }
    _resetRetryDelay();
  }

  Future<void> _waitForRetry() async {
    final delay = _currentRetryDelay;
    var elapsed = Duration.zero;
    const tick = Duration(milliseconds: 250);
    while (!_stopped && elapsed < delay) {
      final remaining = delay - elapsed;
      if (remaining <= Duration.zero) break;
      final step = remaining < tick ? remaining : tick;
      await Future.delayed(step);
      elapsed += step;
    }

    final nextMillis = min(
      _currentRetryDelay.inMilliseconds * 2,
      _maxRetryDelay.inMilliseconds,
    );
    _currentRetryDelay = Duration(milliseconds: nextMillis);
  }

  void _resetRetryDelay() {
    _currentRetryDelay = _initialRetryDelay;
  }

  bool _processFailure(Object error, StackTrace stackTrace) {
    if (_stopped) {
      return false;
    }

    final shouldRetry = _shouldRetry(error);
    if (!shouldRetry) {
      _state = ReplicationState.error;
      _targetReachable = false;
      _notify(error.toString());
      return false;
    }

    _targetReachable = false;
    if (!_paused) {
      _state = ReplicationState.waitingForNetwork;
    }

    final secondsRaw = _currentRetryDelay.inSeconds;
    final seconds = secondsRaw <= 0 ? 1 : secondsRaw;
    final message =
        'Waiting for network (${error.runtimeType}): $error. Retrying in ${seconds}s';
    _notify(message);
    return true;
  }

  bool _shouldRetry(Object error) {
    if (error is TimeoutException) return true;
    if (error is http.ClientException) return true;
    if (error is NetworkFailure) return true;
    if (error is CouchDbException) {
      return error.statusCode == CouchDbStatusCodes.internalServerError ||
          error.statusCode == CouchDbStatusCodes.serviceUnavailable;
    }
    return false;
  }

  Future<void> _waitWhilePaused() async {
    await Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 300));
      return _paused && !_stopped;
    });
  }

  @override
  void pause() {
    _repLog.fine('Pausing replication: ${source.dbname} -> ${target.dbname}');
    _paused = true;
    _state = ReplicationState.paused;
    _notify();
  }

  @override
  void resume() {
    _repLog.fine('Resuming replication: ${source.dbname} -> ${target.dbname}');
    _paused = false;
    _state = live
        ? ReplicationState.inSync
        : ReplicationState.initialSyncComplete;
    _notify();
  }

  /// Stops the replication loop and waits for it to finish.
  ///
  /// **Background / Doze deadlock fix:**
  /// When the app is paused while a large initial sync is in progress,
  /// the replication loop (`_runFuture`) may be blocked inside an HTTP
  /// `receive()` call waiting for bytes that Android's Doze mode will never
  /// deliver. The OS-level TCP timeout on Android can be 20–60 minutes, so
  /// `await _runFuture` would hang indefinitely. `OfflineFirstServer.pause()`
  /// holds `_lifecycleMutex` for the entire duration of `stop()`, so a hanging
  /// `stop()` permanently blocks `resume()` — the app appears stuck in the
  /// error/offline state until it is force-killed.
  ///
  /// The 10-second timeout allows `stop()` to give up waiting and release
  /// the mutex. The orphaned `_runFuture` will eventually throw a
  /// `NetworkFailure` when the socket is torn down, which is harmless because
  /// `_stopped == true` at that point. `_runFuture` is nulled after the
  /// timeout so a second `stop()` call (e.g. from `setDelegate` during the
  /// subsequent `resume()`) does not incur another wait.
  @override
  Future<void> stop() async {
    _repLog.fine('Stopping replication: ${source.dbname} -> ${target.dbname}');
    _stopped = true;

    final pushCancel = _livePushSub?.cancel();
    final pullCancel = _livePullSub?.cancel();
    _livePushSub = null;
    _livePullSub = null;

    _checkpointTimer?.cancel();

    // Flush any pending checkpoint before stopping
    if (_pendingCheckpoint) {
      _pendingCheckpoint = false;
      try {
        await _saveCheckpoint();
      } catch (e) {
        _repLog.fine('Failed to save checkpoint during stop: $e');
      }
    }

    _state = ReplicationState.terminated;
    _notify();

    if (pushCancel != null) {
      try {
        await pushCancel;
      } catch (e) {
        _repLog.fine('Error cancelling push subscription: $e');
      }
    }
    if (pullCancel != null) {
      try {
        await pullCancel;
      } catch (e) {
        _repLog.fine('Error cancelling pull subscription: $e');
      }
    }

    if (_runFuture != null) {
      try {
        // Use a timeout: the replication loop may be blocked mid-download on
        // a network request that will never complete (e.g. Android killed the
        // socket during Doze / standby). Without a timeout, stop() hangs
        // forever, holding _lifecycleMutex and preventing resume() from running.
        await _runFuture!.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            _repLog.warning(
              'Replication loop ${source.dbname} -> ${target.dbname} did not '
              'stop within 10 s — likely blocked on network I/O. '
              'Abandoning wait so lifecycle mutex can be released.',
            );
          },
        );
      } catch (e) {
        _repLog.fine('Replication loop ended with error after stop: $e');
      }
      // Null out so a second stop() call (e.g. via setDelegate during resume)
      // does not wait another 10 s on the same already-abandoned future.
      _runFuture = null;
    }
  }

  /// Estimates the total download size for a list of documents by fetching
  /// them without attachment data (stubs only). CouchDB returns attachment
  /// metadata including the 'length' field when attachments=false.
  ///
  /// The estimate accounts for:
  /// - Full document JSON (with revs=true to include _revisions tree)
  /// - Raw attachment bytes (the 'length' field in each stub)
  ///
  /// Uses revs=true to match actual fetch parameters - revision history can
  /// add significant size (~1KB+ per frequently-edited document).
  ///
  /// Returns a map of "docId:rev" -> estimated byte size (JSON + attachments).
  /// Non-fatal: returns an empty map on failure so replication continues
  /// without size estimates.
  Future<Map<String, int>> _estimateDocSizes(
    DartCouchDb from,
    List<BulkGetRequestDoc> docs,
  ) async {
    final sizes = <String, int>{};
    if (docs.isEmpty) return sizes;

    // Batch the estimation requests to avoid sending a single huge _bulk_get
    // that can stall CouchDB (especially on low-power servers like a NAS).
    const estimateBatchSize = 100;

    try {
      for (int i = 0; i < docs.length; i += estimateBatchSize) {
        if (_stopped) break;

        final end = (i + estimateBatchSize).clamp(0, docs.length);
        final batch = docs.sublist(i, end);

        _notify(
          'Estimating download size... '
          '(${i ~/ estimateBatchSize + 1}/${(docs.length + estimateBatchSize - 1) ~/ estimateBatchSize})',
        );

        final stubRequest = BulkGetRequest(docs: batch);
        final stubResult = await from.bulkGetRaw(
          stubRequest,
          revs: true, // Must match actual fetch to get accurate size estimate
          attachments: false,
        );

        final results = stubResult['results'] as List<dynamic>;
        for (final resultEntry in results) {
          final resultMap = resultEntry as Map<String, dynamic>;
          final docsList = resultMap['docs'] as List<dynamic>;

          for (final docEntry in docsList) {
            final docMap = docEntry as Map<String, dynamic>;
            if (docMap.containsKey('ok')) {
              final doc = docMap['ok'] as Map<String, dynamic>;
              final docId = doc['_id'] as String? ?? '';
              final rev = doc['_rev'] as String? ?? '';
              int docSize = jsonEncode(doc).length;

              // Add attachment sizes from stubs
              final attachments =
                  doc['_attachments'] as Map<String, dynamic>?;
              if (attachments != null) {
                for (final attEntry in attachments.entries) {
                  final attMeta = attEntry.value as Map<String, dynamic>;
                  final length = attMeta['length'] as int? ?? 0;
                  // Multipart transfers raw bytes — no base64 inflation
                  docSize += length;
                }
              }

              // Account for multipart MIME framing overhead per document:
              // boundary markers, Content-Type headers, and CRLF separators
              // (~80 bytes per doc, plus ~100 per attachment part).
              docSize += 80;
              if (attachments != null) {
                docSize += attachments.length * 100;
              }

              sizes['$docId:$rev'] = docSize;
            }
          }
        }
      }
    } catch (e) {
      _repLog.fine('Size estimation failed, proceeding without: $e');
    }

    return sizes;
  }

  /// Replicates [docs] from [from] to [to] using [concurrentPipelines]
  /// concurrent HTTP pipelines, each fetching groups of [producerBatchSize]
  /// documents via multipart streaming.
  ///
  /// Each document is written immediately as it arrives from the stream (not
  /// batched), keeping peak memory at one attachment per pipeline. The two
  /// Splits [docs] into groups sized by estimated byte cost.
  ///
  /// Small docs are batched together (up to [_maxDocsPerGroup]) for fewer
  /// HTTP round trips. Groups are capped at [_targetGroupBytes] so that
  /// large docs (with attachments) naturally form small groups, keeping peak
  /// memory low.
  ///
  /// When [sizeEstimates] is null (e.g. small initial set), falls back to
  /// a fixed batch size of [_fallbackBatchSize].
  static const int _targetGroupBytes = 1024 * 1024; // 1 MB
  static const int _maxDocsPerGroup = 50;
  static const int _fallbackBatchSize = 20;
  static const int _defaultDocSizeEstimate = 1024; // 1 KB

  List<List<BulkGetRequestDoc>> _buildAdaptiveGroups(
    List<BulkGetRequestDoc> docs,
    Map<String, int>? sizeEstimates,
  ) {
    if (sizeEstimates == null || sizeEstimates.isEmpty) {
      // No size info — use fixed batch size.
      final groups = <List<BulkGetRequestDoc>>[];
      for (int i = 0; i < docs.length; i += _fallbackBatchSize) {
        final end = (i + _fallbackBatchSize).clamp(0, docs.length);
        groups.add(docs.sublist(i, end));
      }
      return groups;
    }

    final groups = <List<BulkGetRequestDoc>>[];
    var currentGroup = <BulkGetRequestDoc>[];
    int currentGroupBytes = 0;

    for (final doc in docs) {
      final key = '${doc.id}:${doc.rev ?? ""}';
      final docBytes =
          sizeEstimates[key] ?? _defaultDocSizeEstimate;

      // Start a new group if adding this doc would exceed the byte target
      // or doc count limit (but always allow at least one doc per group).
      if (currentGroup.isNotEmpty &&
          (currentGroupBytes + docBytes > _targetGroupBytes ||
              currentGroup.length >= _maxDocsPerGroup)) {
        groups.add(currentGroup);
        currentGroup = <BulkGetRequestDoc>[];
        currentGroupBytes = 0;
      }

      currentGroup.add(doc);
      currentGroupBytes += docBytes;
    }

    if (currentGroup.isNotEmpty) {
      groups.add(currentGroup);
    }

    _repLog.fine(
      'Adaptive grouping: ${docs.length} docs into ${groups.length} groups '
      '(sizes: ${groups.map((g) => g.length).toList()})',
    );

    return groups;
  }

  /// pipelines overlap HTTP download with local disk write: while one
  /// pipeline's document is being written, the other downloads the next batch.
  ///
  /// Error handling: if an entire group fails, falls back to individual
  /// [DartCouchDb.getRaw] calls for unprocessed docs in that group. Within a
  /// successful group, doc-level errors are retried individually.
  Future<void> _streamingReplicate(
    DartCouchDb from,
    DartCouchDb to,
    List<BulkGetRequestDoc> docs,
    int totalRevsToFetch, {
    Map<String, int>? sizeEstimates,
    int concurrentPipelines = 2,
  }) async {
    // Split docs into groups sized by estimated byte cost.
    // Small docs are batched together (up to 50 per group) for fewer HTTP
    // round trips. Large docs get their own small groups to keep peak memory
    // at one doc's attachments.
    final groups = _buildAdaptiveGroups(docs, sizeEstimates);

    // Merge queue: both pipelines feed results here, single consumer writes.
    final mergeController = StreamController<_PipelineResult>();
    // Track processed keys globally for error fallback.
    final processedKeys = <String>{};

    // Backpressure: limit buffered bytes before pipelines must wait.
    // 5 MB allows thousands of small docs (plenty for write batching at 50)
    // while naturally capping large attachment docs to 1-2 buffered.
    const maxBufferedBytes = 5 * 1024 * 1024; // 5 MB
    int bufferedBytes = 0;
    Completer<void>? bufferDrain;

    Future<void> waitForBuffer() async {
      while (bufferedBytes >= maxBufferedBytes && !_stopped) {
        bufferDrain ??= Completer<void>();
        await bufferDrain!.future;
      }
    }

    int estimateResultSize(_PipelineResult pr) {
      final result = pr.result;
      if (result is BulkGetMultipartSuccess) {
        int size = jsonEncode(result.ok.doc).length;
        for (final att in result.ok.attachments.values) {
          size += att.length;
        }
        return size;
      }
      return 256; // errors / failures: negligible
    }

    void bufferAdd(_PipelineResult result) {
      result.bufferedSize = estimateResultSize(result);
      bufferedBytes += result.bufferedSize;
      mergeController.add(result);
    }

    void bufferConsumed(_PipelineResult result) {
      bufferedBytes -= result.bufferedSize;
      if (bufferedBytes < maxBufferedBytes && bufferDrain != null) {
        bufferDrain!.complete();
        bufferDrain = null;
      }
    }

    // Each pipeline takes the next unprocessed group, fetches via
    // bulkGetMultipart, and forwards results to the merge queue.
    int nextGroupIndex = 0;

    // Per-pipeline byte counters for correct concurrent tracking.
    // onBytesReceived reports cumulative bytes per HTTP response (resets
    // to 0 for each new _bulk_get call). We track accumulated bytes from
    // completed groups per pipeline, then add the current group's bytes.
    final int bytesBeforeStreaming = _transferredBytes;
    final pipelineAccumulatedBytes =
        List<int>.filled(concurrentPipelines, 0);

    Future<void> runPipeline(int pipelineId) async {
      int pipelineDocsTotal = 0;
      int pipelineGroupsTotal = 0;
      final pipelineSw = Stopwatch()..start();

      while (!_stopped) {
        // Take next group (safe: single-threaded Dart, no lock needed).
        final groupIdx = nextGroupIndex;
        if (groupIdx >= groups.length) break;
        nextGroupIndex++;

        if (_paused) await _waitWhilePaused();
        await waitForBuffer();

        final group = groups[groupIdx];
        // Bytes accumulated from all previous groups for this pipeline.
        final baseForThisGroup = pipelineAccumulatedBytes[pipelineId];

        try {
          final bulkGetRequest = BulkGetRequest(docs: group);
          final fetchSw = Stopwatch()..start();
          int groupDocCount = 0;

          await for (final result in from.bulkGetMultipart(
            bulkGetRequest,
            revs: true,
            onBytesReceived: (bytes) {
              // bytes is cumulative within this HTTP response.
              // Add to base from previous groups to get total for pipeline.
              pipelineAccumulatedBytes[pipelineId] =
                  baseForThisGroup + bytes;
              _transferredBytes = bytesBeforeStreaming +
                  pipelineAccumulatedBytes.fold(0, (a, b) => a + b);
              _notifyBytesProgress(
                'Syncing $_docsFetchComplete/$totalRevsToFetch'
                '${_totalBytesEstimate != null ? ' (${_formatBytes(_transferredBytes)}/${_formatBytes(_totalBytesEstimate!)})' : ''}',
              );
            },
          )) {
            if (_stopped) break;
            groupDocCount++;

            bufferAdd(_PipelineResult(
              result: result,
              group: group,
            ));
          }

          pipelineDocsTotal += groupDocCount;
          pipelineGroupsTotal++;
          _repLog.fine(
            'Pipeline $pipelineId: fetched group $groupIdx '
            '($groupDocCount docs) in ${fetchSw.elapsedMilliseconds}ms',
          );
        } catch (e) {
          _repLog.warning(
            'Pipeline $pipelineId: bulk multipart fetch failed for '
            'group $groupIdx: $e',
          );
          // Signal the consumer to do individual fallback for this group.
          bufferAdd(_PipelineResult(
            result: null,
            group: group,
            error: e,
          ));
        }
      }

      _repLog.info(
        'Pipeline $pipelineId finished: $pipelineDocsTotal docs in '
        '$pipelineGroupsTotal groups, ${pipelineSw.elapsedMilliseconds}ms total',
      );
    }

    // Launch pipelines concurrently, close merge queue when all finish.
    final pipelineFutures = <Future<void>>[];
    for (int p = 0; p < concurrentPipelines; p++) {
      pipelineFutures.add(runPipeline(p));
    }
    // When all pipelines complete, close the stream so the consumer exits.
    unawaited(
      Future.wait(pipelineFutures).whenComplete(mergeController.close),
    );

    // Single consumer: collect small docs (no attachments) into write
    // batches for a single bulkDocsFromMultipart call. Docs with
    // attachments are written immediately to keep peak memory low.
    final writeBatch = <BulkGetMultipartSuccess>[];
    final writeBatchKeys = <String>[];

    Future<void> flushWriteBatch() async {
      if (writeBatch.isEmpty) return;
      final batch = List<BulkGetMultipartSuccess>.of(writeBatch);
      final keys = List<String>.of(writeBatchKeys);
      writeBatch.clear();
      writeBatchKeys.clear();

      final writeSw = Stopwatch()..start();
      try {
        await to.bulkDocsFromMultipart(batch, newEdits: false);
        _repLog.info(
          'Write batch: ${batch.length} docs in '
          '${writeSw.elapsedMilliseconds}ms',
        );
        for (final key in keys) {
          processedKeys.add(key);
        }
        _docsWritten += batch.length;
        _transferredDocs += batch.length;
        _docsFetching -= batch.length;
        _docsFetchComplete += batch.length;
        for (final item in batch) {
          _writtenBytes += jsonEncode(item.ok.doc).length;
        }
      } catch (e) {
        _repLog.warning(
          'Batch write of ${batch.length} docs failed, '
          'retrying individually: $e',
        );
        for (int i = 0; i < batch.length; i++) {
          final doc = batch[i].ok.doc;
          final docId = doc['_id'] as String;
          final docRev = doc['_rev'] as String;
          await _fetchAndWriteIndividual(
            from,
            to,
            BulkGetRequestDoc(id: docId, rev: docRev),
            totalRevsToFetch,
          );
          processedKeys.add(keys[i]);
          _docsFetching--;
          _docsFetchComplete++;
        }
      }
      _notifyBytesProgress(
        'Syncing $_docsFetchComplete/$totalRevsToFetch'
        '${_totalBytesEstimate != null ? ' (${_formatBytes(_transferredBytes)}/${_formatBytes(_totalBytesEstimate!)})' : ''}',
      );
    }

    await for (final pipelineResult in mergeController.stream) {
      bufferConsumed(pipelineResult);
      if (_stopped) break;

      // Group-level error: flush pending batch, then fall back to
      // individual fetches for this group.
      if (pipelineResult.error != null) {
        await flushWriteBatch();
        for (final bulkDoc in pipelineResult.group) {
          if (_stopped) break;
          final key = '${bulkDoc.id}:${bulkDoc.rev ?? ""}';
          if (processedKeys.contains(key)) continue;
          if (_paused) await _waitWhilePaused();
          await _fetchAndWriteIndividual(from, to, bulkDoc, totalRevsToFetch);
          _docsFetching--;
          _docsFetchComplete++;
          _notifyBytesProgress(
            'Syncing $_docsFetchComplete/$totalRevsToFetch'
            '${_totalBytesEstimate != null ? ' (${_formatBytes(_transferredBytes)}/${_formatBytes(_totalBytesEstimate!)})' : ''}',
          );
        }
        continue;
      }

      final result = pipelineResult.result!;

      if (result is BulkGetMultipartSuccess) {
        final normalizedDoc = _normalizeReplicationDoc(
          Map<String, dynamic>.from(result.ok.doc),
        );
        if (normalizedDoc == null) {
          _repLog.warning(
            'One-shot: received malformed bulk_get success doc without '
            'required _id/_rev. Keys: ${result.ok.doc.keys.toList()}, '
            'meta: ${result.ok.doc.entries.where((e) => e.key.startsWith("_")).map((e) => "${e.key}: ${e.value}").toList()}',
          );
          _docsFetching--;
          _docsFetchComplete++;
          continue;
        }
        _docsRead++;

        final success = BulkGetMultipartSuccess(
          BulkGetMultipartOk(
            doc: normalizedDoc,
            attachments: result.ok.attachments,
          ),
        );

        final hasAttachments = result.ok.attachments.isNotEmpty;

        if (hasAttachments) {
          // Docs with attachments: flush any pending batch first, then
          // write immediately to avoid holding attachment data in memory.
          await flushWriteBatch();
          final attWriteSw = Stopwatch()..start();
          try {
            await to.bulkDocsFromMultipart([success], newEdits: false);
            _repLog.info(
              'Write attachment doc ${normalizedDoc['_id']}: '
              '${result.ok.attachments.length} attachment(s) in '
              '${attWriteSw.elapsedMilliseconds}ms',
            );
            processedKeys.add(
              '${normalizedDoc['_id'] as String}:${normalizedDoc['_rev'] as String}',
            );
            _docsWritten++;
            _transferredDocs++;
            _writtenBytes += jsonEncode(normalizedDoc).length;
            for (final att in result.ok.attachments.values) {
              _writtenBytes += att.length;
            }
          } catch (e) {
            _repLog.warning(
              'Failed to write document ${normalizedDoc['_id']} via '
              'multipart, retrying individually: $e',
            );
            final docId = normalizedDoc['_id'] as String;
            final docRev = normalizedDoc['_rev'] as String;
            await _fetchAndWriteIndividual(
              from,
              to,
              BulkGetRequestDoc(id: docId, rev: docRev),
              totalRevsToFetch,
            );
            processedKeys.add('$docId:$docRev');
          }
          _docsFetching--;
          _docsFetchComplete++;
          _notifyBytesProgress(
            'Syncing $_docsFetchComplete/$totalRevsToFetch'
            '${_totalBytesEstimate != null ? ' (${_formatBytes(_transferredBytes)}/${_formatBytes(_totalBytesEstimate!)})' : ''}',
          );
        } else {
          // Small docs without attachments: collect into a write batch.
          // Counter updates happen in flushWriteBatch after write succeeds.
          writeBatch.add(success);
          writeBatchKeys.add(
            '${normalizedDoc['_id'] as String}:${normalizedDoc['_rev'] as String}',
          );
          // Flush when batch reaches a reasonable size.
          if (writeBatch.length >= _maxDocsPerGroup) {
            await flushWriteBatch();
          }
        }
      } else if (result is BulkGetMultipartFailure) {
        _repLog.warning(
          'Bulk fetch failed for document ${result.id} rev ${result.rev}: '
          '${result.error} - ${result.reason}',
        );
        if (result.rev != null) {
          await _fetchAndWriteIndividual(
            from,
            to,
            BulkGetRequestDoc(id: result.id, rev: result.rev!),
            totalRevsToFetch,
          );
          processedKeys.add('${result.id}:${result.rev}');
        } else {
          _repLog.warning(
            'Bulk fetch failure for ${result.id} has no rev '
            '— cannot retry individually, skipping',
          );
          processedKeys.add('${result.id}:');
        }
        _docsFetching--;
        _docsFetchComplete++;
        _notifyBytesProgress(
          'Syncing $_docsFetchComplete/$totalRevsToFetch'
          '${_totalBytesEstimate != null ? ' (${_formatBytes(_transferredBytes)}/${_formatBytes(_totalBytesEstimate!)})' : ''}',
        );
      }
    }

    // Flush any remaining docs in the write batch.
    await flushWriteBatch();

    try {
      await _ensureFullCommit(to);
    } catch (e) {
      _repLog.warning('_ensureFullCommit failed: $e');
    }
  }

  /// Fetches a single document individually and writes it to [to].
  /// Used as fallback when bulk multipart fetch fails for a document.
  Future<void> _fetchAndWriteIndividual(
    DartCouchDb from,
    DartCouchDb to,
    BulkGetRequestDoc bulkDoc,
    int totalRevsToFetch,
  ) async {
    try {
      var doc = await from.getRaw(
        bulkDoc.id,
        rev: bulkDoc.rev,
        revs: true,
        attachments: true,
      );
      if (doc == null) {
        _repLog.fine(
          'Rev ${bulkDoc.rev} gone for ${bulkDoc.id}, fetching current rev',
        );
        doc = await from.getRaw(
          bulkDoc.id,
          revs: true,
          attachments: true,
        );
      }
      if (doc != null) {
        final encoded = jsonEncode(doc);
        await to.bulkDocsRaw([encoded], newEdits: false);
        _docsRead++;
        _docsWritten++;
        _transferredDocs++;
        _transferredBytes += encoded.length;
        _writtenBytes += encoded.length;
      } else {
        _repLog.warning(
          'Individual fetch: document ${bulkDoc.id} not found '
          '(rev ${bulkDoc.rev} gone and current rev also missing) '
          '— skipping',
        );
      }
    } catch (e) {
      _repLog.warning(
        'Individual fetch failed for document ${bulkDoc.id} rev ${bulkDoc.rev}: $e',
      );
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  ReplicationProgress _currentProgress([String? message]) =>
      ReplicationProgress(
        state: _state,
        targetReachable: _targetReachable,
        transferredDocs: _transferredDocs,
        docsInNeedOfReplication:
            _pendingPushDocs + _pendingPullDocs + _docsFetching,
        lastSeq: _checkpointSeq,
        message: message,
        transferredBytes: _transferredBytes,
        writtenBytes: _writtenBytes,
        totalBytesEstimate: _totalBytesEstimate,
      );

  void _notify([String? message]) {
    // Null out the timer so the next byte-progress notification fires promptly
    // after any state change, rather than waiting for the next interval.
    _lastByteNotifyTime = null;
    _progressNotifier.value = _currentProgress(message);
  }

  /// Like [_notify] but rate-limited to at most once per [_notifyBytesInterval].
  /// Use for high-frequency byte-tracking callbacks (e.g. streaming chunks,
  /// per-doc completions) to avoid flooding listeners.
  void _notifyBytesProgress(String message) {
    final now = DateTime.now();
    final last = _lastByteNotifyTime;
    if (last == null || now.difference(last) >= _notifyBytesInterval) {
      _lastByteNotifyTime = now;
      _progressNotifier.value = _currentProgress(message);
    }
  }

  @override
  DcValueListenable<ReplicationProgress> get progress => _progressNotifier;
}

/// Internal result type for the dual-pipeline merge queue in
/// [ReplicationMixin._streamingReplicate].
class _PipelineResult {
  final BulkGetMultipartResult? result;
  final List<BulkGetRequestDoc> group;
  final Object? error;

  /// Estimated byte size of this result, set by the backpressure logic.
  int bufferedSize = 0;

  _PipelineResult({
    required this.result,
    required this.group,
    this.error,
  });
}
