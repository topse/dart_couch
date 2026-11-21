import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:dart_couch/dart_couch.dart';

import 'helper/couch_test_manager.dart';
import 'helper/helper.dart';

const String testDbName = CouchTestManager.testDbName;

/// Conflict resolver used as a deterministic "brake" for the initial
/// replication phase: the caught-up conflict sweep runs at the very end of
/// the initial phase (after all one-shot transfers, before the phase is
/// reported complete). While [gate] is open-ended, the initial phase of an
/// OfflineFirstDb whose remote holds a conflicted document is blocked exactly
/// there — no timing assumptions needed. Returns `null` (preserve conflict).
class GatedResolver implements DocumentConflictResolver {
  Completer<void> entered = Completer<void>();
  Completer<void> gate = Completer<void>();

  GatedResolver({bool open = false}) {
    if (open) gate.complete();
  }

  void release() {
    if (!gate.isCompleted) gate.complete();
  }

  @override
  Future<CouchDocumentBase?> resolve(ConflictedDocument doc) async {
    if (!entered.isCompleted) entered.complete();
    await gate.future;
    return null;
  }
}

String _hx(String tag) => tag.padRight(32, '0');

/// Injects a 2-leaf conflict on [db] via the replication path
/// (newEdits:false). Rev hashes must be hex.
Future<void> injectConflict(DartCouchDb db, String docId) async {
  for (final tag in ['aaaa', 'bbbb']) {
    final ids = [_hx(tag), _hx('ba5e')];
    await db.bulkDocsRaw([
      jsonEncode({
        '_id': docId,
        '_rev': '2-${ids.first}',
        '_revisions': {'start': 2, 'ids': ids},
        'val': tag,
      }),
    ], newEdits: false);
  }
}

Future<void> putPlainDocs(DartCouchDb db, String prefix, int n) async {
  for (var i = 0; i < n; i++) {
    await db.put(CouchDocumentBase(id: '$prefix$i', unmappedProps: {'i': i}));
  }
}

/// Waits (event-driven) until [listenable] holds a value satisfying [test].
/// The timeout is only a safety net against hanging tests.
Future<void> waitForValue<T>(
  DcValueListenable<T> listenable,
  bool Function(T) test, {
  Duration timeout = const Duration(seconds: 60),
  String? what,
}) async {
  if (test(listenable.value)) return;
  final completer = Completer<void>();
  void listener() {
    if (test(listenable.value) && !completer.isCompleted) completer.complete();
  }

  listenable.addListener(listener);
  try {
    await completer.future.timeout(
      timeout,
      onTimeout: () => throw TimeoutException(
        'Timed out waiting for ${what ?? 'value'}; current: ${listenable.value}',
      ),
    );
  } finally {
    listenable.removeListener(listener);
  }
}

Future<void> waitForFlag(OfflineFirstDb db, bool expected) => waitForValue(
  db.initialSyncCompleted,
  (v) => v == expected,
  what: 'initialSyncCompleted == $expected',
);

/// Records every violation of "replication reports inSync/initialSyncComplete
/// ⇒ initialSyncCompleted is already true".
List<String> watchInvariant(OfflineFirstDb db) {
  final violations = <String>[];
  db.replicationController.progress.addListener(() {
    final s = db.replicationController.progress.value.state;
    if ((s == ReplicationState.inSync ||
            s == ReplicationState.initialSyncComplete) &&
        !db.initialSyncCompleted.value) {
      violations.add('state $s while initialSyncCompleted == false');
    }
  });
  return violations;
}

/// Releases [resolver]'s gate synchronously from within the log call that
/// `_CouchReplicationController.stop()` emits right before it sets its
/// `_stopped` flag. The resolver continues in a later microtask, i.e. after
/// `_stopped` is set — so the interrupted run deterministically observes the
/// stop, and `stop()` (awaiting the run) returns promptly.
StreamSubscription<LogRecord> releaseGateOnStop(GatedResolver resolver) {
  return Logger.root.onRecord.listen((r) {
    if (r.message.startsWith('Stopping replication:')) resolver.release();
  });
}

void main() {
  DartCouchDb.ensureInitialized();
  configureTestLogging();

  final cm = CouchTestManager();

  setUpAll(() async {
    await cm.init();
  });
  tearDownAll(() async {
    await cm.dispose();
  });
  setUp(() async {
    await cm.prepareNewTest();
  });
  tearDown(() async {
    await cm.cleanupAfterTest();
  });

  test('fresh DB: flag false during initial sync, true after inSync, '
      'persisted and valid immediately when reopened offline', () async {
    final remote = await cm.httpDb();
    await putPlainDocs(remote, 'doc', 5);
    await injectConflict(remote, 'conflicted');

    final resolver = GatedResolver();
    cm.conflictResolver = resolver;
    final db = await cm.offlineDb();
    final violations = watchInvariant(db);

    // Initial phase is blocked in the caught-up conflict sweep.
    await resolver.entered.future;
    expect(db.initialSyncCompleted.value, isFalse);
    expect(
      db.replicationController.progress.value.state,
      ReplicationState.initialSyncInProgress,
    );

    resolver.release();
    await waitForFlag(db, true);
    await waitForReplicationState(db, ReplicationState.inSync);
    expect(violations, isEmpty);

    // The flag means "complete": every remote doc is local.
    for (var i = 0; i < 5; i++) {
      expect(await db.localDb.get('doc$i'), isNotNull);
    }
    expect(await db.localDb.get('conflicted'), isNotNull);

    // Re-open with an unreachable server: flag is loaded during init(), so
    // it is already true on the instance returned by db().
    await cm.pauseOfflineFirstDb();
    final offline = OfflineFirstServer(conflictResolver: null);
    final loginResult = await offline.login(
      await deadCouchUri(),
      CouchTestManager.adminUser,
      CouchTestManager.adminPassword,
      cm.localPath,
    );
    // Network error; cached credentials → offline mode.
    expect(loginResult?.success, isTrue);
    expect(offline.state.value, OfflineFirstServerState.normalOffline);
    final reopened = (await offline.db(testDbName)) as OfflineFirstDb;
    expect(reopened.initialSyncCompleted.value, isTrue);
    expect(
      reopened.replicationController.progress.value.state,
      isNot(ReplicationState.inSync),
    );
    await offline.dispose();
  });

  test('pause()/resume() of the controller during the initial phase does not '
      'report inSync and does not set the flag', () async {
    final remote = await cm.httpDb();
    await putPlainDocs(remote, 'doc', 3);
    await injectConflict(remote, 'conflicted');

    final resolver = GatedResolver();
    cm.conflictResolver = resolver;
    final db = await cm.offlineDb();
    final violations = watchInvariant(db);

    await resolver.entered.future;
    db.replicationController.pause();
    expect(
      db.replicationController.progress.value.state,
      ReplicationState.paused,
    );
    db.replicationController.resume();
    expect(
      db.replicationController.progress.value.state,
      ReplicationState.initialSyncInProgress,
    );
    expect(db.initialSyncCompleted.value, isFalse);

    resolver.release();
    await waitForFlag(db, true);
    await waitForReplicationState(db, ReplicationState.inSync);
    expect(violations, isEmpty);

    // After the initial phase, pause/resume restores inSync.
    db.replicationController.pause();
    db.replicationController.resume();
    expect(
      db.replicationController.progress.value.state,
      ReplicationState.inSync,
    );
  });

  test('server pause() (app backgrounded → terminated) during the initial '
      'phase keeps the flag false; resume() completes it', () async {
    final remote = await cm.httpDb();
    await putPlainDocs(remote, 'doc', 3);
    await injectConflict(remote, 'conflicted');

    final resolver = GatedResolver();
    cm.conflictResolver = resolver;
    final server = await cm.offlineServer();
    final db = await cm.offlineDb();
    final violations = watchInvariant(db);

    await resolver.entered.future;
    final sub = releaseGateOnStop(resolver);
    await server.pause();
    await sub.cancel();

    // The interrupted run has finished (stop() awaited it) without
    // completing the initial phase.
    expect(
      db.replicationController.progress.value.state,
      ReplicationState.terminated,
    );
    expect(db.initialSyncCompleted.value, isFalse);
    expect(await OfflineFirstDb.readInitialSyncFlag(db.localDb), isFalse);

    await server.resume();
    await waitForFlag(db, true);
    await waitForReplicationState(db, ReplicationState.inSync);
    expect(await OfflineFirstDb.readInitialSyncFlag(db.localDb), isTrue);
    expect(violations, isEmpty);
  });

  test('network loss + app restart during the initial phase: flag stays '
      'false offline, becomes true after reconnect', () async {
    final remote = await cm.httpDb();
    await putPlainDocs(remote, 'doc', 3);
    await injectConflict(remote, 'conflicted');

    final resolver = GatedResolver();
    cm.conflictResolver = resolver;
    await cm.offlineDb();
    await resolver.entered.future;

    // Network goes away, then the app is killed while the initial phase is
    // still running.
    await cm.pauseContainer();
    final sub = releaseGateOnStop(resolver);
    await cm.pauseOfflineFirstDb();
    await sub.cancel();

    // App restart while still offline (cached credentials).
    final server2 = OfflineFirstServer(
      conflictResolver: GatedResolver(open: true),
    );
    final login = await server2.login(
      cm.uri,
      CouchTestManager.adminUser,
      CouchTestManager.adminPassword,
      cm.localPath,
    );
    expect(login?.success, isTrue);
    expect(server2.state.value, OfflineFirstServerState.normalOffline);

    final db2 = (await server2.db(testDbName)) as OfflineFirstDb;
    final violations = watchInvariant(db2);
    expect(db2.initialSyncCompleted.value, isFalse);
    expect(
      db2.replicationController.progress.value.state,
      isNot(
        anyOf(ReplicationState.inSync, ReplicationState.initialSyncComplete),
      ),
    );

    // Network returns → health monitoring re-logs in → replication restarts
    // and genuinely completes.
    await cm.resumeContainer();
    await waitForFlag(db2, true);
    expect(violations, isEmpty);
    for (var i = 0; i < 3; i++) {
      expect(await db2.localDb.get('doc$i'), isNotNull);
    }
    await server2.dispose();
  });

  test('remote recreated while app was closed (marker mismatch): flag reset '
      'on login, true again after resync', () async {
    final remote = await cm.httpDb();
    await putPlainDocs(remote, 'old', 2);

    final db = await cm.offlineDb();
    await waitForFlag(db, true);
    await cm.pauseOfflineFirstDb();

    // Another client deletes and recreates the remote database (new UUID).
    final http = await cm.httpServer();
    await http.deleteDatabase(testDbName);
    await http.createDatabase(testDbName);
    final newRemote = (await http.db(testDbName))!;
    await putPlainDocs(newRemote, 'new', 2);
    await injectConflict(newRemote, 'conflicted');
    await newRemote.put(
      DatabaseSyncMarker(
        instanceUuid: 'other-instance',
        databaseUuid: 'recreated-remote-uuid',
        createdAt: DateTime.now(),
        createdBy: 'remote',
        activeInstances: ['other-instance'],
        tombstone: false,
      ),
    );

    final resolver = GatedResolver();
    final server2 = OfflineFirstServer(conflictResolver: resolver);
    final login = await server2.login(
      cm.uri,
      CouchTestManager.adminUser,
      CouchTestManager.adminPassword,
      cm.localPath,
    );
    expect(login?.success, isTrue);

    final db2 = (await server2.db(testDbName)) as OfflineFirstDb;
    final violations = watchInvariant(db2);
    // Reset was persisted during login's marker sync; the resync is blocked.
    expect(db2.initialSyncCompleted.value, isFalse);
    await resolver.entered.future;
    expect(db2.initialSyncCompleted.value, isFalse);

    resolver.release();
    await waitForFlag(db2, true);
    expect(violations, isEmpty);
    expect(await db2.localDb.get('new0'), isNotNull);
    expect(await db2.localDb.get('new1'), isNotNull);
    await server2.dispose();
  });

  test('remote recreated while the DB is open (detected on resume): flag '
      'resets and becomes true again after the restarted resync', () async {
    final remote = await cm.httpDb();
    await putPlainDocs(remote, 'old', 2);

    final server = await cm.offlineServer();
    final db = await cm.offlineDb();
    await waitForFlag(db, true);

    final seen = <bool>[];
    db.initialSyncCompleted.addListener(
      () => seen.add(db.initialSyncCompleted.value),
    );

    await server.pause();

    final http = await cm.httpServer();
    await http.deleteDatabase(testDbName);
    await http.createDatabase(testDbName);
    final newRemote = (await http.db(testDbName))!;
    await putPlainDocs(newRemote, 'new', 2);
    await newRemote.put(
      DatabaseSyncMarker(
        instanceUuid: 'other-instance',
        databaseUuid: 'recreated-remote-uuid-2',
        createdAt: DateTime.now(),
        createdBy: 'remote',
        activeInstances: ['other-instance'],
        tombstone: false,
      ),
    );

    await server.resume();
    // The mismatch was handled inside resume(): the flag was reset.
    expect(seen, isNotEmpty);
    expect(seen.first, isFalse);

    await waitForFlag(db, true);
    expect(seen.last, isTrue);
    expect(await db.localDb.get('new0'), isNotNull);
    expect(await db.localDb.get('new1'), isNotNull);
    expect(await OfflineFirstDb.readInitialSyncFlag(db.localDb), isTrue);
  });

  group('controller-level (local → local)', () {
    test('resume() during the initial phase restores initialSyncInProgress, '
        'not inSync; onInitialSyncComplete precedes inSync', () async {
      final server = await cm.localServer();
      final src = (await server.createDatabase('flag_src')) as LocalDartCouchDb;
      final dst = (await server.createDatabase('flag_dst')) as LocalDartCouchDb;
      await putPlainDocs(src, 'd', 3);

      final inCallback = Completer<void>();
      final gate = Completer<void>();
      final controller = src.syncTo(
        dst,
        live: true,
        resolver: null,
        onInitialSyncComplete: () async {
          inCallback.complete();
          await gate.future;
        },
      );
      final states = <ReplicationState>[];
      controller.progress.addListener(
        () => states.add(controller.progress.value.state),
      );

      await inCallback.future;
      expect(
        controller.progress.value.state,
        ReplicationState.initialSyncInProgress,
      );

      controller.pause();
      expect(controller.progress.value.state, ReplicationState.paused);
      controller.resume();
      expect(
        controller.progress.value.state,
        ReplicationState.initialSyncInProgress,
      );
      expect(states, isNot(contains(ReplicationState.inSync)));

      gate.complete();
      await waitForValue(
        controller.progress,
        (p) => p.state == ReplicationState.inSync,
        what: 'inSync',
      );

      // After the initial phase, pause/resume restores inSync.
      controller.pause();
      controller.resume();
      expect(controller.progress.value.state, ReplicationState.inSync);

      await controller.stop();
      controller.resume();
      expect(controller.progress.value.state, ReplicationState.terminated);
      for (var i = 0; i < 3; i++) {
        expect(await dst.get('d$i'), isNotNull);
      }
    });

    test(
      'stop() during the initial phase never invokes onInitialSyncComplete',
      () async {
        final server = await cm.localServer();
        final src =
            (await server.createDatabase('flag_src2')) as LocalDartCouchDb;
        final dst =
            (await server.createDatabase('flag_dst2')) as LocalDartCouchDb;
        await putPlainDocs(src, 'd', 2);

        var called = false;
        final controller = src.syncTo(
          dst,
          live: true,
          resolver: null,
          onInitialSyncComplete: () async => called = true,
        );
        // Stop synchronously right after start: the run observes _stopped at
        // its first check after the initial awaits.
        await controller.stop();
        expect(called, isFalse);
        expect(controller.progress.value.state, ReplicationState.terminated);
      },
    );
  });
}
