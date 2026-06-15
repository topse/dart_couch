import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:test/test.dart';

import 'package:dart_couch/dart_couch.dart';
// ignore: implementation_imports — the partial-write-recovery test reaches into
// the offline db's local SQLite (AppDatabase) to construct a crash-half-state.
import 'package:dart_couch/src/local_storage_engine/database.dart';

import 'helper/couch_test_manager.dart';
import 'helper/helper.dart';

const String testDbName = 'couch_test_db';

/// Phase 2 (PLAN.md) — opt-in conflict resolution.
///
/// These tests exercise the resolver API ([DocumentConflictResolver],
/// [KeepWinnerResolver]) and the post-replication, caught-up-only resolution
/// sweep wired through `OfflineFirstServer(conflictResolver:)`. Conflicts are
/// injected on the *remote* via the faithful replication path
/// (`bulkDocsRaw(newEdits:false)` with explicit `_revisions` chains), pulled to
/// the local replica, resolved there, and pushed back — then we assert
/// convergence on **both** sides (the local replica and the remote CouchDB).
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

  // ---- helpers --------------------------------------------------------------

  // 32-hex-char rev hash from a short hex tag (CouchDB rev hashes are 32 hex).
  String hx(String tag) => tag.padRight(32, '0');
  String rv(int gen, String tag) => '$gen-${hx(tag)}';

  /// Injects one leaf via the replication protocol path (newEdits:false).
  /// [idTags] is the rev-hash chain newest-first (this rev's tag, then its
  /// ancestors). Returns the leaf rev string.
  Future<String> injectLeaf(
    DartCouchDb db,
    String docId,
    int start,
    List<String> idTags, {
    bool deleted = false,
    Object? val,
    ({String name, List<int> data})? attachment,
  }) async {
    final ids = idTags.map(hx).toList();
    final doc = <String, dynamic>{
      '_id': docId,
      '_rev': '$start-${ids.first}',
      '_revisions': {'start': start, 'ids': ids},
      'val': ?val,
    };
    if (deleted) doc['_deleted'] = true;
    if (attachment != null) {
      doc['_attachments'] = {
        attachment.name: {
          // application/octet-stream avoids CouchDB gzip so bytes stay exact.
          'content_type': 'application/octet-stream',
          'data': base64Encode(attachment.data),
        },
      };
    }
    await db.bulkDocsRaw([jsonEncode(doc)], newEdits: false);
    return '$start-${ids.first}';
  }

  /// Injects a simple 2-leaf conflict (two gen-2 siblings sharing a gen-1
  /// ancestor). Winner = higher hash ('bbbb' > 'aaaa'). Returns (winner, loser).
  Future<({String winner, String loser})> injectConflict(
    DartCouchDb db,
    String docId, {
    Object winnerVal = 'winner',
    Object loserVal = 'loser',
    ({String name, List<int> data})? winnerAttachment,
  }) async {
    // NOTE: rev hashes must be valid hexadecimal (CouchDB rejects others), so
    // the shared ancestor tag is 'ba5e', not 'base'.
    final loser = await injectLeaf(
      db,
      docId,
      2,
      ['aaaa', 'ba5e'],
      val: loserVal,
    );
    final winner = await injectLeaf(
      db,
      docId,
      2,
      ['bbbb', 'ba5e'],
      val: winnerVal,
      attachment: winnerAttachment,
    );
    return (winner: winner, loser: loser);
  }

  Future<List<String>> conflictsOf(DartCouchDb db, String docId) async {
    final m = await db.getRaw(docId, conflicts: true);
    return ((m?['_conflicts'] as List?)?.cast<String>().toList()) ??
        <String>[];
  }

  Future<String?> winnerRev(DartCouchDb db, String docId) async =>
      (await db.getRaw(docId))?['_rev'] as String?;

  /// A document is "converged" once it is PRESENT and has no live conflicts.
  /// Requiring presence is essential: a not-yet-pulled doc reads back as null,
  /// whose `_conflicts` is trivially empty — so "no conflicts" alone would be
  /// satisfied before replication even delivered the document.
  Future<bool> converged(DartCouchDb db, String docId) async {
    final m = await db.getRaw(docId, conflicts: true);
    if (m == null) return false;
    return ((m['_conflicts'] as List?)?.isEmpty ?? true);
  }

  /// The full leaf set of a document, read via the public meta API: the live
  /// winner rev, the live conflict leaves (`_conflicts`) and the deleted
  /// (tombstoned) conflict leaves (`_deleted_conflicts`), sorted for stable
  /// comparison.
  ///
  /// This is the "is the revision tree clean?" probe (PLAN.md Phase 1 Stage 2
  /// follow-up): it lets a test assert that after resolution ONLY the expected
  /// revisions remain — not merely that `_conflicts` is empty. A leftover
  /// loser, a duplicated conflict row, or a half-collapsed branch would all show
  /// up here. Because the API mirrors the stored conflict side-table directly
  /// (and the tombstone revs are computed locally then pushed verbatim), the
  /// returned tree is identical on `LocalDartCouchDb` and `HttpDartCouchDb`.
  Future<({String? winner, List<String> conflicts, List<String> deletedConflicts})>
  treeState(DartCouchDb db, String docId) async {
    final m = await db.getRaw(docId, conflicts: true, deletedConflicts: true);
    if (m == null) {
      return (winner: null, conflicts: <String>[], deletedConflicts: <String>[]);
    }
    List<String> sorted(String key) =>
        ((m[key] as List?)?.cast<String>() ?? const <String>[]).toList()..sort();
    return (
      winner: m['_rev'] as String?,
      conflicts: sorted('_conflicts'),
      deletedConflicts: sorted('_deleted_conflicts'),
    );
  }

  // ---- T5: KeepWinnerResolver converges -------------------------------------

  test(
    'T5 (initial): KeepWinnerResolver collapses a pre-existing remote conflict '
    'on both sides',
    () async {
      cm.conflictResolver = const KeepWinnerResolver();

      final httpDb = await cm.httpDb();
      final c = await injectConflict(httpDb, 'doc1');
      // sanity: the remote really is conflicted before we start.
      expect(await conflictsOf(httpDb, 'doc1'), [c.loser]);
      expect(await winnerRev(httpDb, 'doc1'), c.winner);

      // Creating the offline db logs in with the resolver wired and runs the
      // initial bidirectional one-shot → caught-up resolution sweep.
      final db = await cm.offlineDb();

      final ok = await waitForCondition(
        () async =>
            (await converged(db, 'doc1')) && (await converged(httpDb, 'doc1')),
        maxAttempts: 60,
      );
      expect(
        ok,
        isTrue,
        reason: 'conflict should be resolved away on both sides',
      );

      // KeepWinnerResolver keeps the winning rev unchanged (only tombstones the
      // loser) → the winner rev is exactly the original winner, no churn.
      expect(await winnerRev(db, 'doc1'), c.winner);
      expect(await winnerRev(httpDb, 'doc1'), c.winner);

      // The revision TREE is clean — not just "_conflicts empty". The loser
      // branch collapsed into EXACTLY ONE deleted tombstone leaf (a gen-3
      // deleted child of the gen-2 loser); the winner stays live; no leftover
      // live conflicts and no extra leaves. Local and remote agree on the whole
      // tree (same winner + same single tombstone rev).
      final tLocal = await treeState(db, 'doc1');
      final tRemote = await treeState(httpDb, 'doc1');
      expect(tLocal.winner, c.winner);
      expect(tLocal.conflicts, isEmpty);
      expect(tLocal.deletedConflicts, hasLength(1));
      expect(tLocal.deletedConflicts.single, startsWith('3-'));
      expect(tRemote.winner, tLocal.winner);
      expect(tRemote.conflicts, isEmpty);
      expect(tRemote.deletedConflicts, tLocal.deletedConflicts);
    },
  );

  test(
    'T5 (continuous): a conflict that appears after live sync is resolved',
    () async {
      cm.conflictResolver = const KeepWinnerResolver();

      final db = await cm.offlineDb();
      await waitForReplicationState(db, ReplicationState.inSync);

      final httpDb = await cm.httpDb();
      final c = await injectConflict(httpDb, 'doc2');

      final ok = await waitForCondition(
        () async =>
            (await converged(db, 'doc2')) && (await converged(httpDb, 'doc2')),
        maxAttempts: 60,
      );
      expect(ok, isTrue, reason: 'continuous resolution should converge');
      expect(await winnerRev(db, 'doc2'), c.winner);
      expect(await winnerRev(httpDb, 'doc2'), c.winner);

      // Same clean-tree check as the initial-replication path: one deleted
      // tombstone leaf, no live conflicts, identical tree on both sides.
      final tLocal = await treeState(db, 'doc2');
      final tRemote = await treeState(httpDb, 'doc2');
      expect(tLocal.conflicts, isEmpty);
      expect(tLocal.deletedConflicts, hasLength(1));
      expect(tLocal.deletedConflicts.single, startsWith('3-'));
      expect(tRemote.winner, tLocal.winner);
      expect(tRemote.conflicts, isEmpty);
      expect(tRemote.deletedConflicts, tLocal.deletedConflicts);
    },
  );

  // ---- T6: default (no resolver) preserves ----------------------------------

  test(
    'T6: with no resolver, a conflict is preserved on both sides',
    () async {
      // cm.conflictResolver stays null (the faithful default).
      final httpDb = await cm.httpDb();
      final c = await injectConflict(httpDb, 'doc3');

      final db = await cm.offlineDb();

      // The local replica must faithfully *store* the conflict (Phase 1)...
      final pulled = await waitForCondition(
        () async => (await conflictsOf(db, 'doc3')).contains(c.loser),
        maxAttempts: 40,
      );
      expect(
        pulled,
        isTrue,
        reason: 'local replica should faithfully pull/store the conflict',
      );

      // ...and with no resolver it must NOT be collapsed — on either side.
      expect(await conflictsOf(db, 'doc3'), [c.loser]);
      expect(await conflictsOf(httpDb, 'doc3'), [c.loser]);
      expect(await winnerRev(db, 'doc3'), c.winner);
      expect(await winnerRev(httpDb, 'doc3'), c.winner);
    },
  );

  // ---- per-document isolation: a throwing resolver -------------------------

  test(
    'a resolver that throws on one document leaves THAT document conflicted but '
    'still resolves the others',
    () async {
      cm.conflictResolver = const _ThrowingResolver('docBoom');

      final httpDb = await cm.httpDb();
      final ok = await injectConflict(httpDb, 'docOk');
      final boom = await injectConflict(httpDb, 'docBoom');

      final db = await cm.offlineDb();

      // Settle to the isolated end-state: docOk resolved (present, no conflict)
      // AND docBoom pulled but still conflicted (the resolver threw on it).
      final settled = await waitForCondition(
        () async =>
            (await converged(db, 'docOk')) &&
            (await conflictsOf(db, 'docBoom')).contains(boom.loser),
        maxAttempts: 60,
      );
      expect(
        settled,
        isTrue,
        reason: 'a throw on one doc must not abort the whole sweep',
      );
      expect(await winnerRev(db, 'docOk'), ok.winner);

      // ...while the throwing document is preserved (left conflicted), not
      // corrupted. Data integrity does not depend on resolver correctness.
      expect(await conflictsOf(db, 'docBoom'), [boom.loser]);
      expect(await winnerRev(db, 'docBoom'), boom.winner);
    },
  );

  // ---- merged-survivor attachment-safety guard ------------------------------

  test(
    'a merged survivor resolves a plain doc but is SKIPPED for an '
    'attachment-carrying winner (no attachment data loss)',
    () async {
      cm.conflictResolver = const _MergeResolver();

      final httpDb = await cm.httpDb();
      // Plain conflict — the merge survivor (a child of the winner) can be
      // written via putRaw, so this one resolves.
      final plain = await injectConflict(httpDb, 'docPlain');
      // Winner carries an attachment — a merged survivor would drop it
      // (putRaw carries no attachment bodies), so resolution must SKIP it.
      final att = await injectConflict(
        httpDb,
        'docAtt',
        winnerAttachment: (name: 'blob', data: utf8.encode('hello-attachment')),
      );

      final db = await cm.offlineDb();

      // Wait for the plain doc to resolve (present + no conflict) AND the
      // attachment doc to be pulled but left conflicted (merge skipped).
      final settled = await waitForCondition(
        () async =>
            (await converged(db, 'docPlain')) &&
            (await conflictsOf(db, 'docAtt')).contains(att.loser),
        maxAttempts: 60,
      );
      expect(settled, isTrue, reason: 'plain doc resolves; attachment doc skipped');

      // Plain doc: resolved into a single MERGED survivor (a new child of the
      // winner) → no conflicts, and the winner rev advanced past the original.
      expect(await conflictsOf(db, 'docPlain'), isEmpty);
      final mergedRev = await winnerRev(db, 'docPlain');
      expect(mergedRev, isNot(plain.winner));
      expect(mergedRev, startsWith('3-'));

      // Attachment doc: the merge was skipped → conflict intact, winner (with
      // its attachment) preserved unchanged.
      expect(await conflictsOf(db, 'docAtt'), [att.loser]);
      expect(await winnerRev(db, 'docAtt'), att.winner);
      final blob = await db.getAttachment('docAtt', 'blob');
      expect(blob, isNotNull);
      expect(utf8.decode(blob!), 'hello-attachment');
    },
  );

  // ---- determinism: concurrent resolution on two replicas converges ---------

  test(
    'two replicas resolving the same conflict independently converge to the '
    'same deterministic result (no divergence, no new conflict)',
    () async {
      final httpDb = await cm.httpDb();
      final c = await injectConflict(httpDb, 'docDual');

      // Replica A — managed by the test manager.
      cm.conflictResolver = const KeepWinnerResolver();
      final dbA = await cm.offlineDb();

      // Replica B — a second, independent OfflineFirstServer (own SQLite dir)
      // pointed at the SAME remote, with the same resolver. Both pull the
      // conflict and resolve it independently; the tombstone rev is
      // deterministic, so the two resolutions are idempotent. Two AppDatabases
      // in one isolate (distinct files) is intentional here — silence drift's
      // shared-executor race warning, which does not apply.
      drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
      );
      final dirB = Directory.systemTemp.createTempSync('dctest_replicaB_');
      final serverB = OfflineFirstServer(
        conflictResolver: const KeepWinnerResolver(),
      );
      addTearDown(() async {
        await serverB.dispose();
        if (dirB.existsSync()) dirB.deleteSync(recursive: true);
      });
      final loginB = await serverB.login(cm.uri, 'admin', 'admin', dirB);
      expect(loginB?.success, isTrue);
      final dbB =
          (await serverB.db(testDbName) as OfflineFirstDb?) ??
          (await serverB.createDatabase(testDbName) as OfflineFirstDb);

      final ok = await waitForCondition(
        () async =>
            (await converged(dbA, 'docDual')) &&
            (await converged(dbB, 'docDual')) &&
            (await converged(httpDb, 'docDual')),
        maxAttempts: 80,
      );
      expect(ok, isTrue, reason: 'both replicas must converge');

      // Identical deterministic winner everywhere; no new conflict created.
      expect(await winnerRev(dbA, 'docDual'), c.winner);
      expect(await winnerRev(dbB, 'docDual'), c.winner);
      expect(await winnerRev(httpDb, 'docDual'), c.winner);

      // Both replicas computed the SAME deterministic tombstone for the loser,
      // so the trees are byte-for-byte identical — no divergence, exactly one
      // deleted leaf, no leftover live conflicts.
      final tA = await treeState(dbA, 'docDual');
      final tB = await treeState(dbB, 'docDual');
      final tR = await treeState(httpDb, 'docDual');
      expect(tA.conflicts, isEmpty);
      expect(tA.deletedConflicts, hasLength(1));
      expect(tB.winner, tA.winner);
      expect(tB.deletedConflicts, tA.deletedConflicts);
      expect(tR.winner, tA.winner);
      expect(tR.deletedConflicts, tA.deletedConflicts);
    },
  );

  // ---- data safety: two replicas with DIFFERENT resolvers ------------------

  test(
    'two replicas with DIFFERENT (disagreeing) resolvers still converge to one '
    'clean leaf — the database is never corrupted and the loser is tombstoned',
    () async {
      final httpDb = await cm.httpDb();
      final c = await injectConflict(httpDb, 'docMix');

      // Replica A keeps CouchDB's deterministic winner (KeepWinnerResolver:
      // tombstone the loser, never rewrite the winner). Replica B writes a
      // MERGED survivor (a new child of that same winner). The two policies
      // DISAGREE on the survivor, so WHICH revision ends up the winner is a
      // genuine race:
      //   - if A's tombstone of the loser reaches B before B's caught-up sweep
      //     runs, B sees no conflict and never merges → the winner stays the
      //     original winner (gen 2, body 'winner');
      //   - if B merges first, its survivor (a child of the winner) descends
      //     from A's kept winner → linear, not a sibling → the merge child wins
      //     (gen 3, body 'merged').
      // Either way the loser is tombstoned by both with the SAME deterministic
      // tombstone rev, so the conflict ALWAYS collapses to a single clean leaf
      // and the three replicas agree. The integrity guarantee (Decision C: data
      // safety does NOT depend on resolver agreement) is what we assert below —
      // NOT a particular winner. Because A never *puts* (only B does), there is
      // at most one leaf-creating edit, so convergence is guaranteed. (Two
      // resolvers that each *put* a DIFFERENT child would instead churn — perf,
      // not integrity; that case is intentionally out of scope, see PLAN.md.)
      cm.conflictResolver = const KeepWinnerResolver();
      final dbA = await cm.offlineDb();

      drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
      );
      final dirB = Directory.systemTemp.createTempSync('dctest_replicaB_');
      final serverB = OfflineFirstServer(
        conflictResolver: const _MergeResolver(),
      );
      addTearDown(() async {
        await serverB.dispose();
        if (dirB.existsSync()) dirB.deleteSync(recursive: true);
      });
      final loginB = await serverB.login(cm.uri, 'admin', 'admin', dirB);
      expect(loginB?.success, isTrue);
      final dbB =
          (await serverB.db(testDbName) as OfflineFirstDb?) ??
          (await serverB.createDatabase(testDbName) as OfflineFirstDb);

      // Converged = present + no LIVE conflicts on all three.
      final ok = await waitForCondition(
        () async =>
            (await converged(dbA, 'docMix')) &&
            (await converged(dbB, 'docMix')) &&
            (await converged(httpDb, 'docMix')),
        maxAttempts: 100,
      );
      expect(ok, isTrue, reason: 'mismatched resolvers must still converge');

      // The DATABASE is not messed up: an identical, clean tree on all three —
      // exactly one live winner, NO live conflicts, and the loser collapsed
      // into a single deleted tombstone leaf. We deliberately do NOT pin which
      // rev is the winner (that is the inherent race); the invariant is that
      // all three AGREE on the entire tree.
      final tA = await treeState(dbA, 'docMix');
      final tB = await treeState(dbB, 'docMix');
      final tR = await treeState(httpDb, 'docMix');
      expect(tA.conflicts, isEmpty);
      expect(tB.conflicts, isEmpty);
      expect(tR.conflicts, isEmpty);
      // The original loser branch was DELETED (tombstoned), not silently
      // dropped — and there is exactly one tombstone (no duplicates / orphans).
      expect(tA.deletedConflicts, hasLength(1));
      expect(tA.deletedConflicts.single, startsWith('3-'));
      // All three agree on winner + tombstone → no divergence, no corruption.
      expect(tB.winner, tA.winner);
      expect(tR.winner, tA.winner);
      expect(tB.deletedConflicts, tA.deletedConflicts);
      expect(tR.deletedConflicts, tA.deletedConflicts);

      // No data loss: the surviving winner is exactly ONE of the two policies'
      // valid outcomes — A's kept original winner (gen 2, body 'winner') or B's
      // merge child (gen 3, body 'merged'). We assert it is a valid outcome and
      // that all three replicas carry the SAME body — we do NOT pin which one
      // won (that is the race).
      final winRev = tA.winner!;
      final bodyA = (await dbA.getRaw('docMix'))?['val'];
      final bodyR = (await httpDb.getRaw('docMix'))?['val'];
      expect(bodyR, bodyA); // remote and local agree on the surviving body
      if (winRev == c.winner) {
        expect(bodyA, 'winner'); // A's KeepWinner outcome
      } else {
        expect(winRev, startsWith('3-')); // B's merge child outcome
        expect(bodyA, 'merged');
      }
    },
  );

  // ---- data safety: a tombstoned loser, extended elsewhere, survives --------

  test(
    'a loser leaf that was extended elsewhere SURVIVES the tombstone '
    '(resolution never destroys a branch — no data loss)',
    () async {
      cm.conflictResolver = const KeepWinnerResolver();

      final httpDb = await cm.httpDb();
      // Phase 1: a plain 2-leaf conflict; winner 2-bbbb, loser 2-aaaa.
      final c = await injectConflict(httpDb, 'docExt');
      expect(c.winner, rv(2, 'bbbb'));
      expect(c.loser, rv(2, 'aaaa'));

      final db = await cm.offlineDb();

      // Phase 1 resolves: the loser (2-aaaa) is tombstoned, winner 2-bbbb kept.
      final phase1 = await waitForCondition(
        () async =>
            (await converged(db, 'docExt')) &&
            (await converged(httpDb, 'docExt')),
        maxAttempts: 60,
      );
      expect(phase1, isTrue, reason: 'phase 1 conflict should resolve');
      expect(await winnerRev(httpDb, 'docExt'), rv(2, 'bbbb'));

      // Phase 2: simulate "another replica had already extended the loser
      // branch before it was tombstoned, and that extension arrives late": a
      // LIVE child of 2-aaaa (3-cccc) is delivered to the remote. Because the
      // Phase-1 tombstone hit only the exact rev 2-aaaa, 3-cccc is a NEW live
      // leaf — its data must not be lost.
      await injectLeaf(
        httpDb,
        'docExt',
        3,
        ['cccc', 'aaaa', 'ba5e'],
        val: 'extended-loser',
      );

      // The extension (gen 3) becomes the deterministic winner over 2-bbbb and
      // is re-resolved against it → converges to 3-cccc on both sides, with the
      // extended-loser data preserved.
      final phase2 = await waitForCondition(
        () async =>
            (await winnerRev(db, 'docExt')) == rv(3, 'cccc') &&
            (await conflictsOf(db, 'docExt')).isEmpty &&
            (await winnerRev(httpDb, 'docExt')) == rv(3, 'cccc') &&
            (await conflictsOf(httpDb, 'docExt')).isEmpty,
        maxAttempts: 80,
      );
      expect(
        phase2,
        isTrue,
        reason: 'the extended loser branch must survive and converge',
      );

      // The data carried on the extended branch survived the earlier tombstone.
      expect((await db.getRaw('docExt'))?['val'], 'extended-loser');
      expect((await httpDb.getRaw('docExt'))?['val'], 'extended-loser');
    },
  );

  // ---- resolver skips bodyless leaves --------------------------------------

  test(
    'the resolver SKIPS a bodyless leaf — it is preserved (not tombstoned), no '
    'churn',
    () async {
      // A permanently-gone ("not_found") conflict leaf — recorded by the pull
      // path via recordBodylessLeaf — must NOT be tombstoned by the resolver:
      // CouchDB will not collapse a compacted-body leaf when a tombstone child
      // is grafted onto it (verified on a live server), so tombstoning is
      // useless and only churns (re-record → re-tombstone). The leaf is left
      // preserved, exactly as CouchDB keeps it; recording alone stops the churn.
      cm.conflictResolver = const KeepWinnerResolver();

      final httpDb = await cm.httpDb();
      final c = await injectConflict(httpDb, 'docBL');
      final db = await cm.offlineDb();

      // Initial sync resolves the *real* conflict on docBL.
      final ok1 = await waitForCondition(
        () async =>
            (await converged(db, 'docBL')) && (await converged(httpDb, 'docBL')),
        maxAttempts: 60,
      );
      expect(ok1, isTrue, reason: 'the real conflict resolves first');

      // Simulate the pull hitting a permanently-gone leaf: record a bodyless
      // (body == null) non-winning gen-2 sibling (lower hash than the winner
      // 2-bbbb). This is exactly what the pull path does on a not_found fetch.
      const bodyless = '2-aaad0000000000000000000000000000';
      await db.recordBodylessLeaf('docBL', bodyless);
      expect(
        await conflictsOf(db, 'docBL'),
        [bodyless],
        reason: 'the recorded bodyless leaf is a live conflict locally',
      );

      // Drive a caught-up resolution sweep by injecting + resolving an unrelated
      // conflict; when docTrigger converges, a sweep has run (and it also
      // processed docBL).
      await injectConflict(httpDb, 'docTrigger');
      final ok2 = await waitForCondition(
        () async => await converged(db, 'docTrigger'),
        maxAttempts: 60,
      );
      expect(ok2, isTrue, reason: 'the trigger conflict resolves (a sweep ran)');

      // The bodyless leaf is PRESERVED: still a live conflict, never tombstoned;
      // the winner is unchanged; and it still reads back as not_found.
      expect(
        await conflictsOf(db, 'docBL'),
        [bodyless],
        reason: 'the bodyless leaf must survive the sweep, not be tombstoned',
      );
      expect(await winnerRev(db, 'docBL'), c.winner);
      expect(
        await db.getRaw('docBL', rev: bodyless),
        isNull,
        reason: 'a bodyless leaf reads back as not_found (Http parity)',
      );
    },
  );

  // ---- partial-write recovery (resumability) -------------------------------

  test(
    'a half-written resolution (tombstone lost) is completed by the next sweep '
    '— recovery from a crashed/partial write',
    () async {
      // Resolution writes the survivor/keeps the winner, THEN tombstones the
      // losers. If it dies (or a write is lost) in between, the doc is left with
      // the winner intact but a loser still un-tombstoned. The next caught-up
      // sweep must complete it — deterministically, no corruption (PLAN.md §C
      // "local-first + resumable; preserve-on-failure"). We reproduce the exact
      // half-state by directly editing the offline replica's SQLite: remove the
      // loser's tombstone row and re-add the loser as a live conflict leaf.
      cm.conflictResolver = const KeepWinnerResolver();

      final httpDb = await cm.httpDb();
      final c = await injectConflict(httpDb, 'docPartial');
      final db = await cm.offlineDb();

      // First sync resolves it cleanly on both sides.
      final ok1 = await waitForCondition(
        () async =>
            (await converged(db, 'docPartial')) &&
            (await converged(httpDb, 'docPartial')),
        maxAttempts: 60,
      );
      expect(ok1, isTrue, reason: 'the conflict resolves on first sync');
      final tomb = (await treeState(db, 'docPartial')).deletedConflicts.single;

      // --- inject the crash half-state via raw SQLite ---
      final AppDatabase raw = db.localDb.db;
      final docRow = await raw.getDocument(
        db.localDb.dbid,
        'docPartial',
        false,
        ignoreDeleted: true,
      );
      expect(docRow, isNotNull);
      // Remove the loser's tombstone (the write that "was lost") ...
      await raw.deleteConflictRevision(docRow!.document.id, tomb);
      // ... and restore the loser as a live (body-bearing) conflict leaf.
      await raw.putConflictRevision(
        docRowId: docRow.document.id,
        rev: c.loser,
        version: int.parse(c.loser.split('-').first),
        deleted: false,
        body: jsonEncode({'_id': 'docPartial', '_rev': c.loser, 'val': 'loser'}),
      );
      expect(
        await conflictsOf(db, 'docPartial'),
        [c.loser],
        reason: 'the doc is back in the un-tombstoned half-state',
      );

      // Drive a caught-up sweep (resolve an unrelated conflict); the same sweep
      // re-processes docPartial and finishes what the "crash" interrupted.
      await injectConflict(httpDb, 'docPartialTrigger');
      final ok2 = await waitForCondition(
        () async =>
            (await converged(db, 'docPartial')) &&
            (await converged(db, 'docPartialTrigger')),
        maxAttempts: 60,
      );
      expect(ok2, isTrue, reason: 'the next sweep completes the partial write');

      // Recovered to a single clean leaf; winner intact; loser deterministically
      // re-tombstoned to the SAME rev (idempotent, no divergence, no data loss).
      expect(await winnerRev(db, 'docPartial'), c.winner);
      expect((await db.getRaw('docPartial'))?['val'], 'winner');
      final t = await treeState(db, 'docPartial');
      expect(t.conflicts, isEmpty);
      expect(t.deletedConflicts, [tomb]);
    },
  );
}

/// Throws for one specific document id, returns the winner for the rest.
/// Verifies per-document isolation (a throw must not abort the sweep).
class _ThrowingResolver implements DocumentConflictResolver {
  final String throwForDocId;
  const _ThrowingResolver(this.throwForDocId);

  @override
  Future<CouchDocumentBase?> resolve(ConflictedDocument doc) async {
    if (doc.docId == throwForDocId) {
      throw StateError('resolver deliberately failing for ${doc.docId}');
    }
    return doc.winner;
  }
}

/// Returns a merged body (NOT the winning rev) so the library takes the
/// `putRaw(survivor)` path — except for attachment-carrying winners, which the
/// library skips to avoid dropping attachment data.
class _MergeResolver implements DocumentConflictResolver {
  const _MergeResolver();

  @override
  Future<CouchDocumentBase?> resolve(ConflictedDocument doc) async {
    return CouchDocumentBase(
      id: doc.docId,
      unmappedProps: {'val': 'merged', 'mergedBy': 'test'},
    );
  }
}
