import 'dart:convert';

import 'package:dart_couch/dart_couch.dart';
import 'package:test/test.dart';

import 'helper/helper.dart';

/// Regression tests for `recordBodylessLeaf` (PLAN.md Phase 1 "optional polish",
/// promoted to load-bearing after the live-server investigation of doc
/// `7d1c403d`): a conflict leaf the source advertises but whose body is
/// permanently unrecoverable (`_bulk_get`/`GET ?rev=`/`open_revs=[rev]` all
/// return `not_found`). The puller records such a leaf locally as a known but
/// **bodyless** (`body == null`), non-deleted conflict leaf so that:
///
///  - `revsDiff` reports it as known → the puller stops re-requesting it on
///    every change (the residual re-pull churn that caused the example app's
///    checkbox flicker);
///  - `get(conflicts: true)` lists it → Local matches Http (a real A2 parity
///    gap: the server lists these revs in `_conflicts`, Local used to drop them);
///  - an opt-in resolver can tombstone it (a tombstone needs only the rev id),
///    collapsing the branch on every sync partner.
///
/// And, critically for safety, a bodyless leaf must never become the winner
/// (there is no body to serve) and must read back as `not_found`.
///
/// A genuine bodyless leaf cannot be created through CouchDB's public API
/// (compaction is not API-triggerable), so these run Local-only against a
/// Docker-free [LocalDartCouchServer]; the bodyless leaf is recorded directly
/// via the new API, exactly as the pull path does on a `not_found` skip.
void main() {
  configureTestLogging();

  const dbName = 'bodyless_db';
  const docId = 'd';

  late LocalDartCouchServer cl;
  late DartCouchDb db;

  // 32-hex-char hash from a short hex tag (CouchDB rev hashes are 32 hex; tags
  // MUST be hex — see PLAN.md test gotchas).
  String hx(String tag) => tag.padRight(32, '0');
  String rv(int gen, String tag) => '$gen-${hx(tag)}';

  // Inject one real leaf via the replication path (newEdits=false with an
  // explicit `_revisions` chain). [idTags] is the rev-hash chain newest-first.
  Future<void> inject(int start, List<String> idTags, {bool deleted = false}) {
    final ids = idTags.map(hx).toList();
    final doc = <String, dynamic>{
      '_id': docId,
      '_rev': '$start-${ids.first}',
      '_revisions': {'start': start, 'ids': ids},
      'val': idTags.first,
    };
    if (deleted) doc['_deleted'] = true;
    return db.bulkDocsRaw([jsonEncode(doc)], newEdits: false);
  }

  Future<String?> winner() async => (await db.getRaw(docId))?['_rev'];
  Future<List<String>> liveConflicts() async =>
      ((await db.getRaw(docId, conflicts: true))?['_conflicts'] as List?)
          ?.cast<String>()
          .toList() ??
      <String>[];
  Future<List<String>> deletedConflicts() async =>
      ((await db.getRaw(docId, deletedConflicts: true))?['_deleted_conflicts']
              as List?)
          ?.cast<String>()
          .toList() ??
      <String>[];

  setUp(() async {
    cl = LocalDartCouchServer(prepareSqliteDir());
    db = await cl.createDatabase(dbName);
  });

  tearDown(() async {
    await cl.dispose();
  });

  test('recorded bodyless leaf is known: listed, revsDiff-quiet, but not_found '
      'on read', () async {
    // Winner 2-bb, real (body-bearing) sibling conflict 2-aa.
    await inject(2, ['aa', 'a1']);
    await inject(2, ['bb', 'a1']);
    expect(await winner(), rv(2, 'bb'), reason: 'higher hash wins');
    expect(await liveConflicts(), [rv(2, 'aa')]);

    // Record a permanently-gone sibling leaf (no body).
    await db.recordBodylessLeaf(docId, rv(3, 'ff'));

    // (a) Parity: it now appears in _conflicts alongside the real loser.
    expect(
      (await liveConflicts()).toSet(),
      {rv(2, 'aa'), rv(3, 'ff')},
      reason: 'bodyless leaf listed in _conflicts like the source does',
    );

    // (b) revsDiff treats it as KNOWN (no more re-requesting), while a genuinely
    //     unknown rev is still reported missing.
    final diff = await db.revsDiff({
      docId: [rv(3, 'ff'), rv(9, 'dead')],
    });
    expect(diff[docId]?.missing, [rv(9, 'dead')]);
    expect(diff[docId]?.missing, isNot(contains(rv(3, 'ff'))));

    // (c) Reading the bodyless rev → not_found (Http parity), while the real
    //     loser still serves its body.
    expect(await db.getRaw(docId, rev: rv(3, 'ff')), isNull);
    expect((await db.getRaw(docId, rev: rv(2, 'aa')))?['val'], 'aa');

    // The winner is untouched by recording.
    expect(await winner(), rv(2, 'bb'));
  });

  test('recordBodylessLeaf is idempotent and ignores already-known revs',
      () async {
    await inject(2, ['aa', 'a1']);
    await inject(2, ['bb', 'a1']); // winner 2-bb

    await db.recordBodylessLeaf(docId, rv(3, 'ff'));
    await db.recordBodylessLeaf(docId, rv(3, 'ff')); // duplicate → no-op
    expect(
      (await liveConflicts()).where((r) => r == rv(3, 'ff')).length,
      1,
      reason: 'recording the same bodyless rev twice stores it once',
    );

    // The winner and an existing real conflict are ignored (they must never be
    // turned into a duplicate bodyless leaf). (Ancestors are pre-filtered in
    // production: the puller only records revs revsDiff already reported
    // missing, and revsDiff treats known ancestors as not-missing.)
    await db.recordBodylessLeaf(docId, rv(2, 'bb')); // winner
    await db.recordBodylessLeaf(docId, rv(2, 'aa')); // existing real conflict
    expect((await liveConflicts()).toSet(), {rv(2, 'aa'), rv(3, 'ff')});
    expect(await winner(), rv(2, 'bb'));

    // An absent document is ignored (no throw, nothing recorded).
    await db.recordBodylessLeaf('does-not-exist', rv(2, 'zz'));
    expect(await db.getRaw('does-not-exist'), isNull);
  });

  test('a bodyless leaf is never promoted to winner when the winner is deleted',
      () async {
    // Winner 2-bb, real loser 2-aa, plus a HIGHER-generation bodyless leaf 3-ff.
    // If promotion did not skip bodyless leaves, 3-ff (highest gen, non-deleted)
    // would be picked — yielding a winner with no body.
    await inject(2, ['aa', 'a1']);
    await inject(2, ['bb', 'a1']);
    await db.recordBodylessLeaf(docId, rv(3, 'ff'));
    expect(await winner(), rv(2, 'bb'));

    // Delete the winner → promotion runs.
    await db.remove(docId, rv(2, 'bb'));

    expect(
      await winner(),
      rv(2, 'aa'),
      reason: 'promotion picks the real loser, never the bodyless 3-ff',
    );
    // The promoted winner is a usable, body-bearing revision.
    final promoted = await db.getRaw(docId);
    expect(promoted?['_deleted'], isNot(true));
    expect(promoted?['val'], 'aa');
    // The bodyless leaf survives as a (still bodyless) conflict leaf.
    expect(await liveConflicts(), contains(rv(3, 'ff')));
  });

  test('a tombstone arriving for a bodyless leaf supersedes it locally',
      () async {
    await inject(1, ['w1']); // sole winner 1-w1
    await db.recordBodylessLeaf(docId, rv(3, 'ff'));
    expect(await liveConflicts(), [rv(3, 'ff')]);

    // Storage invariant: if a deleted child of the bodyless rev ever arrives via
    // replication (e.g. another replica that DID hold the body tombstoned it),
    // the local leaf set collapses it correctly. NOTE: the opt-in resolver does
    // NOT itself generate such a tombstone for a bodyless leaf — CouchDB will not
    // collapse a compacted-body leaf when a tombstone child is grafted onto it,
    // so the resolver skips bodyless leaves (covered in conflict_resolution_test).
    // The exact hash is irrelevant; what matters is it is a deleted child of the
    // bodyless rev.
    final tomb = jsonEncode({
      '_id': docId,
      '_rev': rv(4, 'de'),
      '_deleted': true,
      '_revisions': {
        'start': 4,
        'ids': [hx('de'), hx('ff')],
      },
    });
    await db.bulkDocsRaw([tomb], newEdits: false);

    // The bodyless leaf is collapsed: no longer a LIVE conflict, now a deleted
    // tombstone leaf. With no live conflicts left, the doc is no longer in
    // conflict (the `conflictedDocIds` index keys off exactly this), so opt-in
    // resolution would stop re-processing it — and the source feed stops being
    // re-requested.
    expect(await liveConflicts(), isEmpty);
    expect(await deletedConflicts(), contains(rv(4, 'de')));
    expect(await winner(), rv(1, 'w1'), reason: 'winner untouched');
  });
}
