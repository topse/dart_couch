# PLAN — Faithful conflict handling in `dart_couch`

Status legend: `[ ]` todo · `[~]` in progress · `[x]` done · `[!]` blocked/needs decision

---

## 0. CONTINUATION STATE

### ⏩ LATEST handoff (2026-06-15): bodyless-leaf churn FIXED end-to-end; cleanup pass done
**Read this and the 2026-06-14 handoff below.** All changes uncommitted;
`dart analyze lib/ test/` clean.
- **Bodyless-leaf flicker root cause RESOLVED.** Live-app toggle log (2026-06-15)
  confirms it: `7d1c403d` now syncs with `revsDiff returned nothing missing`, NO
  `Skipping unrecoverable revision`, NO resolver spam, one view re-index per
  toggle. See the Phase 1 "Optional polish" item (the 2026-06-15 CORRECTION):
  `recordBodylessLeaf` records permanently-gone leaves (parity + silences
  revsDiff); the resolver SKIPS them (`fetchableRevs`) because CouchDB will not
  collapse a compacted-body leaf via a grafted tombstone (proven on the live
  server) — so they are inherently permanent but now inert. Any residual *visual*
  flicker is GUI (view re-animation), deferred by the user.
- **This session's cleanup:** new `test/orphan_cleanup_test.dart` (att-FILE orphan
  cleanup, the acceptance-criterion gap); health-check interval now configurable
  via `OfflineFirstServer(healthCheckInterval:)` (example app set to 15 s; default
  unchanged 5 s) + the two per-tick "Session valid" logs combined into one; Phase
  5 settled (keep `conflictResolver` nullable, default `null` = preserve); Phases
  1 & 3 marked DONE; acceptance criteria checked off.
- **Tests:** `bodyless_leaf` 4, `conflict_resolution` **10** (incl. resolver-skips-
  bodyless + partial-write recovery), `orphan_cleanup` 1, `all_test` 158,
  `local_storage_engine` 13 — green. `offline_first_db` 65/66 (1 pre-existing load
  flake, passes in isolation).
- **Partial-write recovery test added (2026-06-15)** via raw-SQLite manipulation
  (no fault-injection hook needed — reproduce the crash half-state directly on the
  offline replica's `AppDatabase`). The remaining §Phase 2 fault-injection items
  (network-drop, non-convergent churn) are now annotated as low-value / awkward-by-
  nature rather than tooling-blocked.
- **Phase 6a DONE (2026-06-15, this fresh context):** full CouchDB-spec compliance
  review vs `REPLICATION_AND_CONFLICT_MODEL.md`. Compliant on every conflict clause
  except ONE, now fixed: **view map functions did not receive `_conflicts`** (so the
  spec's conflict-locating view worked on Http but not Local — a parity break). Fix
  = `liveConflictRevsByDoc` + `_conflicts` injection in `view_ctrl._updateViewEntries`;
  parity test green on both impls; `use_view_test` 96/96 green. See the Phase 6
  section for the per-clause findings. `dart analyze lib/ test/all_test.dart` clean.
- **NEXT:** Phase 7 (CLAUDE.md + comment-coverage pass) + one clean from-scratch
  full regression sweep.

### ⏩ handoff (2026-06-14): Phase 2 TESTED + GREEN; Stage 3 forwarding IMPLEMENTED (was a hidden prerequisite)

**Read this first.** All changes are **uncommitted**. `dart analyze lib/ test/`
is **clean**. New test file `test/conflict_resolution_test.dart` — **7/7 green**
(serial, `TMPDIR=/var/tmp/dctest`, `--concurrency=1`). **Full regression sweep
DONE 2026-06-14: 31/32 PASS** (see `/var/tmp/dctest/sweep_results.txt`). The only
non-pass is `multi_inheritance_test` rc=79 "+0" — the documented no-tests artifact
(file body commented out; `dart test` exits 79 with 0 tests), NOT a regression.
Notable greens: `all_test` +158, `changes_stream_consistency` +2 (the feed I
rewrote), `offline_first_db_test` +66 (live repl / default-null-resolver = T6;
the old delete-during-repl flake passed this run too), `pause_resume` +10,
`use_view` +96, `large_sync`/`large_attach_changes_consistency` (push perf +
orphan cleanup) green. **No regressions from the seq-bump / Stage 3 changes.**

**What testing revealed (the important bit):** Phase 2 resolution did NOT actually
reach the remote, because two prerequisites in `LocalDartCouchDb` were missing —
both now **FIXED** (these are real CouchDB-faithfulness fixes, not test hacks):
1. **Seq not bumped on conflict-leaf-only changes.** When a write changed only the
   leaf set (added / superseded / **tombstoned** a *losing* leaf) but not the
   winner row, the document's `update_seq` was not advanced, so the changes feed
   never re-emitted it and the resolution tombstone never pushed. CouchDB bumps
   update_seq for ANY tree change. Fix: `_applyIncomingLeaf` now returns
   `leafSetChanged`; all three write paths (`bulkDocsRaw`, multipart main, no-att
   fast path) call new `AppDatabase.updateDocumentSeq(docRowId, seq)` when it is
   set and the winner row is untouched.
2. **Changes feed (`style=all_docs`) advertised only the winner rev** (Stage 3
   forwarding was unimplemented — old `//assert(styleAllDocs==false)` comment said
   "Local can't branch", no longer true). So push's `revsDiff` never saw the
   conflict/tombstone leaves → couldn't transfer them. Fixes:
   - feed now advertises ALL leaves (winner + conflict leaves, deleted included):
     `_changesArrayForDoc` (continuous, via `.asyncMap` to preserve order) +
     `_changesArrayFromMap` (normal/longpoll, one batch query
     `AppDatabase.conflictRevsByDoc(dbid)`). Only runs the per-doc/batch conflict
     query when `styleAllDocs` (replication) — app feeds pay nothing.
   - `bulkGetMultipart` now SERVES a requested conflict-leaf rev (incl. a deleted
     tombstone leaf, with its stored `_revisions` + own attachments) via new
     `_conflictLeafMultipart`, mirroring `_internalGetRaw`'s conflict-leaf path.
     Push fetches missing leaves per-rev (revs:true), so this completes the loop.

   Net: **Local is now a faithful replication SOURCE for conflicted docs** — this
   is Stage 3 (was "lowest priority"), but Phase 2 cannot converge the remote
   without it. End-to-end verified by the new tests (both sides converge).

**Phase 2 tests (test/conflict_resolution_test.dart, all green):** T5 initial
(pre-existing remote conflict → KeepWinnerResolver collapses both sides), T5
continuous (conflict appearing after live sync), T6 (no resolver ⇒ preserved both
sides), throwing-resolver isolation (one doc throws → left conflicted, others
resolve), merge-survivor attachment guard (plain doc → merged survivor written;
attachment-winner → skipped+preserved), two-replica deterministic convergence
(idempotent tombstone, no divergence), loser-extended-elsewhere survives (tombstone
hits only the exact rev → the live descendant becomes the new winner, no data
loss). `CouchTestManager` gained an optional `conflictResolver` field.

**Test-writing gotchas worth keeping:** (a) rev-hash tags MUST be hex
(`'ba5e'`, not `'base'`) or CouchDB rejects them ("RevId isn't a valid
hexadecimal"). (b) "no conflicts" is trivially true for an **absent** doc — wait
on a `converged()` predicate that requires the doc PRESENT *and* `_conflicts`
empty, else `waitForCondition` returns before replication delivered anything.

**Added 2026-06-14 (the two Stage-2 follow-up test items, now DONE):**
`conflict_resolution_test.dart` 8/8 green (serial, `TMPDIR=/var/tmp/dctest`,
`--concurrency=1`; the new race test re-run 5× hitting both branches).
1. **Post-resolution TREE-state checks** — new `treeState(db,docId)` helper reads
   `getRaw(conflicts:true, deletedConflicts:true)`; T5 initial/continuous + the
   two-replica determinism test now assert the tree is *clean* (winner live,
   `_conflicts` empty, loser collapsed into exactly one gen-3 deleted tombstone,
   Local↔remote agree). Not just `_conflicts`-empty.
2. **Two replicas with DIFFERENT resolvers** (KeepWinner vs merge) — asserts the
   race-agnostic integrity invariants (single clean leaf, loser tombstoned, all
   three agree, survivor is a valid no-loss outcome) WITHOUT pinning the winner.
   See the §"data safety: two replicas with DIFFERENT resolvers" checklist entry.

**Still remaining Phase 2/3 test ideas not yet written** (lower value / need
fault injection): partial-write recovery, network-drop-mid-push,
non-convergent-churn bound. The data-safety design covers them; add if time
permits.

(2026-06-10/11/12 notes below remain valid history.)

**Done since 2026-06-12:**
- **Phase 1 Stage 2 (conflict-leaf attachments) — DONE + verified** (full sweep,
  `all_test` +158, no regression). See the "Stage 2" section.
- **Phase 2 (opt-in resolution) — IMPLEMENTED; design SETTLED after a long
  review; do NOT re-litigate it:**
  - **Resolver API (Decision B):** `DocumentConflictResolver.resolve(
    ConflictedDocument) → CouchDocumentBase?`; default **no resolver = preserve**;
    opt-in **`KeepWinnerResolver`**. In `replication_mixin_interface.dart`. Dead
    `DocumentReplicationConflictResolver`/`DefaultConflictResolver` removed.
    Threaded `syncTo(resolver:)` → controller → `OfflineFirstDb` /
    `OfflineFirstServer` (nullable, default null).
  - **Resolution (Decision C):** a **post-replication, caught-up-only,
    local-data-only** sweep in `replication_mixin.dart`
    (`_resolveCaughtUpConflicts` + per-doc `_maybeResolveConflict`). Triggered
    (1) after the initial bidirectional one-shot, and (2) when continuous settles
    to `pending == 0` — never per-change mid-stream (local replica then holds the
    COMPLETE leaf set). Discovery = **cheap LOCAL conflict index**:
    `LocalConflictSource.conflictedDocIds()` (`conflict_resolution_internal.dart`,
    **non-exported / NOT public API**; backed by `AppDatabase.conflictedDocIds`
    side-table query — ids only, indexed, NO Http impl, NO full scan), so the
    optimized per-doc transfer loop is untouched. Per doc: `putRaw(survivor)` as a
    child of the winner + a deterministic `newEdits:false` tombstone per losing
    leaf; **`KeepWinnerResolver` skips the put** (just tombstones losers → winner
    + attachments preserved); a merged survivor on an attachment-carrying doc is
    **skipped+warned**. Results replicate back out via normal push.
  - **Data-safety strategy (integrity independent of resolver correctness):**
    per-document isolation + **preserve-on-failure** (resolver throw / write error
    / crash → that doc left conflicted, retried next sweep, never aborts/corrupts);
    tombstone hits only the exact losing rev (concurrent descendant survives);
    writes local-first + resumable; **no heuristic circuit-breaker** (CLAUDE.md).
    Worst case of a bad resolver = churn, never lost/corrupt data. Contract on
    `DocumentConflictResolver`: resolvers MUST be **deterministic AND stable**.

**NEXT (Phase 2 testing — NOT started):**
1. Write + run **T5** (register `KeepWinnerResolver`; conflicted doc converges to
   a single leaf, `_conflicts` empty on **both** sides; idempotent), **T6** (no
   resolver ⇒ conflicts preserved), and the **concurrency/data-safety tests**
   under "### Phase 2" (remote-changed-during-resolution; loser-extended-elsewhere
   survives; double-resolution idempotence; partial-write recovery; resolver-throws
   isolation; network-drop; non-convergent-churn-not-corruption).
   - T5 harness tip: `OfflineFirstServer(conflictResolver: KeepWinnerResolver())`
     + `login(...)` (like `database_sync_test`); inject a conflict on the remote
     via `httpDb.bulkDocsRaw([sibA, sibB], newEdits:false)`; then
     `waitForCondition(...)` until `_conflicts` empty both sides.
     `CouchTestManager.offlineServer()` does NOT pass a resolver yet — add an
     optional param or build the server inline.
2. Full regression sweep (serial, `TMPDIR=/var/tmp/dctest`, `--concurrency=1`, one
   container at a time — see TEST ENVIRONMENT GOTCHA below + the
   `test-env-tmpfs-and-serial-couchdb` memory). Esp. `offline_first_db_test`
   (live replication, default null resolver = T6). `/var/tmp/dctest/run_sweep.sh`
   exists.
3. Then update PLAN/TODO; consider Phase 4 (example app uses `KeepWinnerResolver`;
   verify toggle-flicker hypothesis).

**Phase 2 files touched:** `replication_mixin_interface.dart`,
`replication_mixin.dart`, `conflict_resolution_internal.dart` (NEW),
`local_dart_couch_db.dart`, `local_storage_engine/database.dart`,
`http_dart_couch_db.dart`, `dart_couch_db.dart`, `offline_first_db.dart`,
`offline_first_server.dart`.

---

## 0b. CONTINUATION STATE (handoff 2026-06-10)

**Stage 1 (faithful conflict storage) is implemented.** Changes are uncommitted
in the working tree. `dart analyze lib/ test/` is clean.

Implemented (all in `local_dart_couch_db.dart` + `local_storage_engine/database.dart`):
- Schema **v5**: `local_conflict_revisions` table (`fkdocument, rev, version,
  deleted, body`) + `delete_conflict_revisions_before_delete_document` cascade
  trigger; `onCreate` + `onUpgrade(from<5)`. Drift codegen regenerated.
- `_applyIncomingLeaf(...)` — shared leaf-set maintenance (ancestry via incoming
  `_revisions`; dedup / skip-ancestor / supersede / store-losing-sibling /
  demote-old-winner). Used by **all three** write paths: `bulkDocsRaw`,
  multipart main path, and `_bulkWriteNoAttachments` (partitioned: new+unique →
  fast batch insert to keep large-sync perf; conflict-relevant → per-doc).
- Guard: conflict-creation/demote only when `incomingRevisions != null` (so a
  tombstone delivered without `_revisions` does a normal linear delete).
- Reads: `get(conflicts/deletedConflicts/meta)`, `get(rev:X)` serves a conflict
  leaf, `getOpenRevs` returns winner+conflict leaves, `revsDiff` unions conflict
  revs (deterministic).
- `_promoteAfterTombstone(...)` — deleting the winning leaf promotes the best
  surviving leaf (non-deleted → highest gen → highest hash); wired into
  `_internalRemove` and the batch deletion path.
- `getRaw`/`get` gained `conflicts`/`deletedConflicts`/`meta` params across the
  chain (`use_dart_couch.dart`, `dart_couch_db.dart`, http/local/offline impls).

Tests added: `test/all_test.dart` group **"conflict leaf set (Http vs Local)"**
(~32 parity assertions incl. multipart + delete/tombstone) and
`test/local_storage_engine_test.dart` (drift cascade/no-orphan + existing
regression). Verified PASSING in a clean env: `all_test`,
`local_storage_engine`, `large_sync`, `large_attach_changes_consistency`,
`tombstone_cleanup`, `local_documents`.

**⚠️ TEST ENVIRONMENT GOTCHA (root cause of this session's crashes):** `/tmp` is
RAM-backed tmpfs (5.9G). Test scratch dirs `/tmp/dart_couch_*` (from
`Directory.systemTemp` in `CouchTestManager`/`prepareSqliteDir`) accumulate on
crashed/killed runs, fill tmpfs, **starve RAM**, and cause spurious failures
(compile errors, timing-test failures). Mitigation when running tests:
`TMPDIR=/var/tmp/dctest dart test --concurrency=1 test/<file>.dart` (one file at
a time — each spins a CouchDB container; >2 at once OOMs), and between files
`docker ps -aq --filter label=dart_couch_test | xargs -r docker rm -fv` and
`rm -rf /var/tmp/dctest/dart_couch_* /tmp/dart_couch_*`. NOTE: spawned subagents
are permission-blocked from running `dart`/`mkdir`, so run tests in the MAIN
session, not via subagents.

**Known PRE-EXISTING flake (NOT a regression):** `offline_first_db_test.dart` →
"remote documents deleted while initial replication is running still settle to
inSync and produce tombstones" fails on the ORIGINAL code too in a clean env
(different `small_during_repl_N` each run = timing race). The conflict logic
handles these deletions correctly (verified: each classified linear-delete →
tombstone written). Do not chase it as a regression.

**DONE THIS SESSION (2026-06-10):**
1. ✅ Full-suite regression sweep (MAIN session, serial, `TMPDIR=/var/tmp/dctest`,
   `--concurrency=1`, all 31 files). Result: 29 PASS, 2 FAIL — **both
   pre-existing, neither a regression**:
   - `multi_inheritance_test` rc=79 "No tests were found" (the file's body is
     commented out — defines 0 `test()`; committed in that state, unrelated).
   - `offline_first_db_test` +65 −1 — the documented timing flake ("remote
     documents deleted while initial replication is running still settle to
     inSync", different `small_during_repl_N` each run).
   Suspects all GREEN in isolation: `database_sync_test`,
   `large_attachment_sync_test`, `changes_stream_consistency_test`,
   `checkpoint_persistence_test`, `pause_resume_test`, `use_view_test` (+96, the
   earlier transient-network test passed).
2. ✅ Re-added the 14 deferred edge-case parity cases to the "conflict leaf set"
   group (idempotent re-delivery; four-way; default get() = winner / no
   `_conflicts` leak; `meta:true`; revsDiff reports unknown rev missing; winner
   advances linearly while conflict preserved; conflict branch grows past winner →
   new winner; get(rev:X) winner vs conflict bodies; getOpenRevs with explicit
   revisions; non-deleted beats deleted ×2 orders; delete-winner-only-deleted-
   leaves stays tombstone; promotion picks highest non-deleted; promoted conflict
   then advances). **all_test.dart 144/144 green on BOTH impls.**
3. ✅ These edge cases surfaced **two real Local divergences from CouchDB**
   (Http was the reference; both now fixed):
   - **Winner selection** (`_applyIncomingLeaf` step (d)): compared *generation
     first*, so a deleted higher-gen sibling leaf wrongly beat a non-deleted
     lower-gen winner. Fixed to CouchDB's rule — **between SIBLING leaves**
     non-deleted beats deleted regardless of generation, then gen, then hash;
     a **linear descendant** (incl. a tombstone child of a live winner) still
     supersedes unconditionally. Sibling-vs-descendant is decided by the incoming
     `_revisions` ancestry; without ancestry it keeps the legacy gen-first path.
   - **Tombstone-promotion** (`_promoteAfterTombstone`): the append-only
     `revision_histories` (version-desc) kept the tombstone's higher-version row
     at the head after a lower-version leaf was promoted, so the next write hit
     `assert(history[0].version == rev)` in `_getRevs` and aborted the linear
     advance. Fixed with `AppDatabase.clearRevisionHistory(docRowId)` — clear the
     doc's history on promotion; the winner-row write re-seeds the head via the
     trigger (now identical in shape to a freshly-written doc).

**FAILING-TEST INVESTIGATION (2026-06-10/11) — RESOLVED:**
The user flagged that the suite was 100% green before this branch, so the
§-top failures must be taken seriously, not dismissed. Verified read-only:
`offline_first_db_test.dart` and `use_view_test.dart` are UNCHANGED from the
committed baseline (not in the uncommitted diff); only *lib* changed. Findings:
- `offline_first_db_test.dart` "remote documents deleted while initial
  replication is running still settle to inSync and produce tombstones" — **NOT
  data loss; the library converges.** The failing run's own log proves the
  deletions ARE pulled (continuous `_bulk_get` returns `_deleted` docs) and
  applied (`Batch write: 1 written`), but the test had already asserted+failed
  while the continuous feed was still draining them: `waitForSync`
  (`test/helper/helper.dart`) returns at the *first* inSync — the initial
  one-shot checkpoint (e.g. seq 70) — while the 50 deletes landed mid-init at
  seqs ~61–110 and the late ones drain afterward. The `replication_mixin.dart`
  feed/checkpoint/inSync code is UNCHANGED by this work; the conflict work's
  per-doc overhead at most widened the window. `waitForSync` also leans on
  `Future.delayed` (CLAUDE.md forbids it). **Fix:** the test now waits for the
  converged state via `waitForCondition` (poll until all 50 deleted docs are
  gone locally and all 10 large docs present) before asserting — deterministic,
  no engine change. A timeout there = genuine data loss and still fails loudly.
- `use_view_test.dart` "HTTP streams emit error on transient network failure" —
  passed in BOTH full sweeps (+96). Currently green; re-verify.
- `multi_inheritance_test` rc=79 is a per-file-sweep artifact (file's tests
  commented out since v0.9.14), not a code issue. Out of scope.

**OPEN / NEXT:**
1. ✅ **Stage 2 (conflict-leaf attachment bodies) — DONE 2026-06-11/12.** Schema
   v6 (`local_attachments.fkconflict`); store/read/promote conflict-leaf
   attachments with full Http↔Local parity; full sweep shows no regression. See
   "Phase 1 → Stage 2" below for details + deferred follow-ups.
2. **Phase 2 (resolver API) — NEXT.** N-way `DocumentConflictResolver` (Decision
   B); default no-op preserve; opt-in `KeepWinnerResolver`; wire opt-in
   resolution into `OfflineFirstDb` (Decision C). This is what actually collapses
   the unbounded conflict trees (the original shopping-list pain) and builds on
   the now-faithful conflict storage (bodies + attachments).
3. Lower priority: Stage 3 (forwarding fidelity) + the Stage 2 deferred follow-ups.

---

This plan tracks the work to make `dart_couch` handle CouchDB replication
conflicts *faithfully* (like CouchDB) and to give the **application** a proper,
non-lossy way to resolve them. Progress is tracked with the checkboxes below.

---

## 1. Background / why

Discovered 2026-06-08 against a live CouchDB (shopping-list app): a single
"erledigt" toggle item had accumulated a 21-leaf conflict tree (two devices
editing the same item offline). This surfaced two distinct problems:

1. **Crash + stuck checkpoint (FIXED 2026-06-08).** CouchDB's multipart
   `_bulk_get` error part carries no `id`; the empty id poisoned the retry
   (`getRaw('')` → db-info map → `bulkDocsRaw` "must have a _rev") and the failed
   write blocked the pull checkpoint forever. Fixed in `replication_mixin.dart`
   via `_recoverFailureId()` + `_isRevisionGone()` (skip permanently-gone revs,
   matching CouchDB's replicator). See `replication_mixin.dart` and the TODO.md
   "FIXED 2026-06-08" note. **This phase is already shipped** and is the baseline
   for the work below.

2. **Conflict-visibility divergence (THIS PLAN).**
   `LocalDartCouchDb` keeps **only the winning revision's body** per doc
   (`local_documents` = one row per `(fkdatabase, docid)`). Consequences:
   - `HttpDartCouchDb.get(conflicts:true)` returns the conflict revs (it proxies
     CouchDB); `LocalDartCouchDb.get(conflicts:true)` cannot, because it never
     exposes `_conflicts`. Same API, different answers online vs offline — a
     direct breach of *"LocalDartCouchDb must behave identically to
     HttpDartCouchDb from the API perspective."* **This is the real gap**
     (Phase 0 test P2 is RED on Local for exactly this reason).
   - Conflicts are never resolved (the `DocumentReplicationConflictResolver`
     interface is dead code), so trees grow unboundedly.

   **Churn — corrected by Phase 0 (P3 GREEN on both):** the earlier assumption
   that `revsDiff` re-requests *fetchable* conflict leaves forever was **wrong**.
   Local *does* record conflict-leaf revs in `revision_histories` (verified:
   `revsDiff` reports a known loser rev as NOT missing, while fabricated revs
   ARE missing), so it does not re-fetch them. The churn in the original report
   was specifically the **bodyless `not_found` leaves**: they failed to write
   (the empty-id bug) → were never recorded → re-requested every cycle. After
   the shipped fix they are *skipped* but still not recorded, so they may still
   be re-requested when the doc changes. Optional Phase-1 polish: record skipped
   `not_found` revs as known so `revsDiff` stops requesting them (CouchDB-faithful
   — a rev present in the tree, even bodyless, is "known"). Lower priority than
   the visibility gap.

   **Caveat surfaced by Phase 0:** because Local acknowledges (via `revsDiff`) a
   conflict-leaf rev whose body it did not keep, it cannot *forward* that branch
   if it later acts as a replication source. That is the faithfulness gap
   Decision A weighs (A1 keeps winner body only; A2 keeps all leaf bodies).

### Design principles (must hold)
- **The library must NOT auto-resolve conflicts.** CouchDB preserves conflicts
  and leaves resolution to the app; so do we. Auto-deleting losers = silent data
  loss + app policy baked into a library. (CLAUDE.md: "no silent data loss",
  "must not use app-specific heuristics … or behavior that diverges from
  CouchDB's revision-tree rules".)
- **Replication stays a faithful, deterministic transfer.** Resolution is a
  separate, opt-in layer on top — never mixed into the raw transfer path.
- **Winner selection is unchanged** (already CouchDB-correct:
  `local_dart_couch_db.dart` — highest generation → non-deleted beats deleted →
  highest rev hash).

---

## 2. Key design decisions (confirm before Phase 1)

### Decision A — How faithful must the *local* replica be? `[x]` (confirmed: A2)

**Revised after Phase 0.** A1 (track conflict leaf rev-ids, keep only the winner
body) was the earlier pick on the assumption it "stopped the churn". Phase 0
showed Local already records conflict-leaf revs (no fetchable-leaf churn), so
A1's main remaining benefit was just lighter storage — while it *forces*
online-only resolution and leaves two parity holes: Local acknowledges (via
`revsDiff`) conflict revs whose body it didn't keep, so `get(rev:X)` /
`getOpenRevs` / offline merge all diverge from Http, and Local can't forward
those branches if it acts as a source. That contradicts *"behave identically to
HttpDartCouchDb"*. So we go **A2**.

**A2: Local stores all leaf revisions (with bodies) — a faithful replica.**
- Pros: full offline parity (`get(rev:X)`, `getOpenRevs`, `get(conflicts:true)`
  all match Http), offline conflict resolution, and Local can forward conflict
  branches. Honors the contract.
- Cons: storage change touching `bulkDocsRaw`, `get`/`getOpenRevs`, winner
  promotion, attachments, and (for forwarding) `changes(styleAllDocs)`.

**Additive strategy (contain the blast radius):** keep `local_documents` as the
**winner** row per `(db, docid)` — so view indexing, the changes feed, seq, and
fast winner reads are UNCHANGED. Add a side table (e.g. `local_conflict_revisions`:
`fkdatabase, docid, rev, version, deleted, body`) for non-winner leaf bodies.
Reads consult the winner first, then the side table. Writes recompute the winner
across {winner ∪ side-table ∪ incoming}; if the winner changes, move bodies
between the winner row and the side table and re-index views. Conflict leaves are
NOT view-indexed (matches CouchDB — views see only the winner).

**Staging within Phase 1 (so it ships incrementally):**
1. Store conflict-leaf **bodies** (no attachments yet) → `get(conflicts:true)`,
   `get(rev:X)`, `getOpenRevs` parity; winner promotion on delete. (Makes P2
   green; keeps P1/P3 green.)
2. Conflict-leaf **attachments** — sub-decision below; can land later.
3. **Forwarding fidelity** — `changes(styleAllDocs)` advertises all local leaves
   so Local-as-source pushes conflict branches (only needed beyond the
   Local↔single-CouchDB topology; lowest priority).

**Sub-decision (attachments on conflict leaves) — CONFIRMED: full bodies.**
"Do it right": Local stores conflict-leaf attachment bodies too, for complete
offline parity. Empirically verified (throwaway CouchDB, 2026-06-08) that this
is achievable: a non-winning conflict leaf's attachment is retrievable by that
leaf's rev (`GET /db/X/att?rev=<loser>`) and **survives compaction** — so the
remote will provide conflict-leaf attachment bodies during replication
(`_bulk_get?attachments=true` / `getAttachment(rev:…)`). Each leaf carries its
own `_attachments`. The only unrecoverable case is the bodyless `not_found`
leaf (whole revision body gone → nothing to fetch → skipped by the shipped fix).

This is the heaviest part of A2, so it gets a thorough test matrix (Stage 2).

### Decision B — Resolver API shape `[x]` (confirmed)

Replace the binary, replication-framed
`DocumentReplicationConflictResolver.resolveConflict(local, remote)` with an
N-way, document-centric API. **Resolving always reduces the doc to a single
surviving leaf, so the library always tombstones the other leaves** — the app's
only decision is the *content* of the survivor (pick one existing rev, or merge
several). The app never manages the delete list. (Names below are FINAL — shipped
as written in `replication_mixin_interface.dart`.)

```dart
/// All conflicting leaf revisions of one document.
class ConflictedDocument {
  final String docId;
  final CouchDocumentBase winner;            // CouchDB's deterministic winner
  final List<CouchDocumentBase> conflicts;   // the losing leaves (bodies)
}

abstract class DocumentConflictResolver {
  /// Called when a doc has >1 leaf. Return the body to keep as the single
  /// surviving revision (pick one of [doc.winner]/[doc.conflicts], or a merged
  /// body). The library writes it and tombstones ALL other leaves.
  /// Return null to leave the document in conflict (e.g. resolve later in UI).
  Future<CouchDocumentBase?> resolve(ConflictedDocument doc);
}
```

- **Default = preserve (no-op).** The default resolver returns `null` (keep all
  conflicts, exactly like CouchDB). The current `DefaultConflictResolver`
  (returns `remote`) is removed — "remote wins" is an arbitrary policy, not a
  faithful default.
- A ready-made `KeepWinnerResolver` (`resolve => doc.winner`; library deletes the
  rest = deterministic last-writer-wins) is provided as an **opt-in**
  convenience, not the default. The example app can use it.
- **Resolvers MUST be deterministic AND stable** (same inputs → same survivor on
  every device, and resolving a partial leaf set in steps converges to the same
  result as resolving the whole set — leaves can arrive across replication
  batches); otherwise two devices resolving independently can create new
  conflicts / churn. `KeepWinnerResolver` satisfies both; custom merges are the
  app's responsibility. NOTE: data integrity does NOT depend on this — a bad
  resolver can only churn, never lose/corrupt data (see §5 Decision C).
- Deleting a loser leaf needs only its rev id, so **bodyless leaves (the
  not_found ones) are tombstoned cleanly too** — resolution also clears the
  branches that caused the original churn.

### Decision C — Where/when resolution runs `[x]` (confirmed)

The resolver **stays a `syncTo` parameter** (it already is). Because replication
is a mixin, any `DartCouchDb` (Http/Local) calling `syncTo` may pass one;
`OfflineFirstDb` is the main caller and simply forwards the app's resolver.

The architectural rule is about *separation of phases*, not about moving the
parameter:
- **Raw revision transfer stays faithful** — `revsDiff` + `bulk_get` + writing
  leaves only moves revisions and creates the same conflicts CouchDB would. It
  MUST NOT merge/delete during transfer (preserves the "no heuristics" contract).
- **Resolution is a separate, opt-in phase** triggered by the sync *after* the
  conflicting leaves are transferred, using the `syncTo` resolver. It performs
  `put`(survivor) + tombstone(other leaves) edits that then replicate like any
  other change. Default (no resolver) = does nothing.
- Resolution must be deterministic and idempotent so concurrent resolution on
  multiple devices converges.
- **RESOLVED in Phase 2 (2026-06-13) — see §5 Decision C + §0 LATEST handoff for
  the full record:** trigger = **caught-up sweep** (never per-change mid-stream);
  discovery = **cheap local conflict index** (no remote scan, no public API);
  mechanism = `putRaw(survivor child of winner)` + `newEdits:false` tombstones
  (`KeepWinnerResolver` skips the put → attachment-safe); **data safety is
  independent of resolver correctness** (per-doc preserve-on-failure, surgical
  tombstones, local-first+resumable writes, no heuristic breaker).

---

## 3. Phases

### Phase 0 — Reproduce deterministically (tests first) `[x]` DONE
Lock the desired behavior in tests *before* changing storage. Outcome below
also **corrected the churn model** (see Background #2).
- [x] **Added the `meta`-family params to `getRaw`/`get`** (interface + Http +
      Local `_internalGetRaw` + `OfflineFirstDb`): `conflicts` (`_conflicts`),
      `deletedConflicts` (`_deleted_conflicts`), `meta` (= conflicts +
      deletedConflicts + revsInfo). Http expands `meta` and passes the query
      params (works now); Local accepts them, `revsInfo` already supported,
      `conflicts`/`deletedConflicts` return nothing until Phase 1 (the P2 RED).
- [x] **Parity tests added to `all_test.dart` `doTest`** (runs against BOTH Http
      and Local). Conflict injected within one impl via `bulkDocsRaw(newEdits:
      false)` — two same-generation leaves sharing an ancestor; higher hash wins.
  - [x] **P1 winner parity** — `getRaw(id)['_rev']` == higher-hash winner.
        **GREEN on both** (confirms Local's winner rule matches CouchDB).
  - [x] **P2 conflict-listing parity** — `getRaw(id, conflicts:true)['_conflicts']`
        == `[loser]`. **Http GREEN, Local RED.** ← the genuine Phase 1 gap.
  - [x] **P3 revsDiff parity** — `revsDiff({id:[winner,loser]})` reports nothing
        missing. **GREEN on both** — Local records conflict-leaf revs, so it does
        NOT re-fetch them. Disproves the "fetchable-leaf churn" assumption.
- [ ] **End-to-end replication conflict (separate integration test,
      `CouchTestManager`) — OPTIONAL/LATER:** offline scenario (`pauseContainer`
      → local edit → `pauseOfflineFirstDb` → `resumeContainer` → remote edit via
      `httpDb` → reopen → sync). Now mainly verifies conflict *convergence* +
      that Local exposes `_conflicts` after Phase 1 (the no-churn assertion is
      already covered by P3). Slower; lower priority.
- [ ] **not_found-leaf robustness (deferred / separate):** test-double source
      yielding `BulkGetMultipartFailure(id:'', rev:…, error:'not_found')`; assert
      replication doesn't corrupt and the checkpoint advances. (GREEN with the
      shipped fix; a true bodyless leaf can't be made via the public API.)

### Phase 1 — Faithful conflict storage (Decision A2) `[x]` DONE
Goal: Local becomes a faithful replica for conflicts (full Http parity). Uses
the additive strategy from Decision A: winner stays in `local_documents`;
non-winner leaf bodies live in a new side table. Staged so it ships in pieces.

**Key correctness note — leaf-set maintenance:** doing this right is NOT "store
the loser in a side table". The current write path only compares version/hash
and CANNOT tell a *linear supersede* (incoming is a child of the current rev →
old rev is just history) from a *sibling branch* (conflict → both are leaves).
Faithful storage requires maintaining the **leaf set** using each incoming doc's
`_revisions` ancestry (replication sends `revs:true`): when adding rev R, any
existing leaf that appears in R's ancestor chain stops being a leaf (R descends
from it); R is a new leaf unless an existing leaf descends from R. NOTE: the
write path currently strips `_revisions` early (local_dart_couch_db.dart:216) —
must capture it first.

**Stage 1 — conflict-leaf bodies (no attachments):**
- [x] Investigated current write paths (per-doc `bulkDocsRaw` 191+ and the
      `bulkDocsFromMultipart` fast path 3047+). Found: losers are written-then-
      overwritten (order-dependent), so `revsDiff` knowing a loser is an
      artifact of arrival order, not real storage. Both paths need updating.
- [x] **Schema v4 → v5 migration** (`schemaVersion` bumped + `onUpgrade from < 5`
      raw-SQL `createTable` + indexes + trigger; mirrored in `onCreate`). Side
      table `local_conflict_revisions` (`id, fkdocument → local_documents.id,
      rev, version, deleted, body`), unique `(fkdocument, rev)`. Drift codegen
      regenerated; lib analyzes clean.
- [x] **Cascades / NO ORPHANS (hard requirement) — schema level done + tested:**
  - `delete_conflict_revisions_before_delete_document` (`BEFORE DELETE ON
    local_documents`) deletes the doc's conflict rows, so document-delete AND
    database-delete (cascades via `delete_documents_before_db`) both clean them.
    Body is inline → removed with the row. Verified by
    `test/local_storage_engine_test.dart` (doc-delete, db-delete, cross-doc
    isolation, unique constraint) + existing-trigger regression; existing
    local-storage suite still green.
  - [x] Stage-2 conflict-leaf attachment *files*: Dart-layer cleanup + the startup
    orphan scan (SQL triggers can't touch files; tombstone-caveat pattern).
    End-to-end file cleanup verified by `test/orphan_cleanup_test.dart`
    (conflict-leaf attachments → delete db → restart → zero `att/` files).
  - [x] Tombstoning the winner must NOT blindly drop conflict leaves (a live
    conflict may become the new winner) — handled by promotion (`_promoteAfterTombstone`).
- [x] `bulkDocsRaw(newEdits:false)` (per-doc path): captures `_revisions`;
      maintains the leaf set via ancestry (dedup; skip ancestor-of-existing;
      supersede conflicts in the incoming chain; store losing sibling as a
      conflict leaf; demote old winner to conflict when incoming wins and the
      old winner is a sibling). Helpers `_expandRevisions` / `_getConflictRevs`
      / `_putConflictLeaf`; drift queries in `AppDatabase`
      (`getConflictRevisions` / `putConflictRevision` / `deleteConflictRevision`).
- [x] `get(rev:X)`: serves a conflict-leaf body from the side table.
- [x] `get(conflicts:true)` / `deletedConflicts`: populate `_conflicts` /
      `_deleted_conflicts` from the side table → **P2 GREEN on Local**.
- [x] `revsDiff`: unions side-table revs → deterministic regardless of arrival
      order. **P3 green for real.** Full `all_test.dart` (91) + drift tests pass,
      no regression.
- [x] `getOpenRevs`: returns winner + all conflict leaves as docs (Http parity).
- [x] **Leaf-set algorithm test matrix** — `all_test.dart` group "conflict leaf
      set (Http vs Local)", **30 cases × both impls = 60 green**: linear-update
      (no conflict), two/three/four siblings, order independence, higher-gen wins,
      supersession, deleted→`_deleted_conflicts`, non-deleted-beats-deleted (both
      arrival orders), `get(rev:X)` (winner vs conflict bodies), `revsDiff`
      determinism + unknown-rev-missing, `getOpenRevs` (all + explicit revisions),
      idempotent re-delivery, default-get-no-`_conflicts`-leak, `meta:true`,
      winner-advances-while-conflict-preserved, conflict-branch-grows-past-winner,
      multipart (separate + in-batch), tombstone/promotion variants. Extended
      2026-06-10 (the "double the edge cases" request) by 14 cases, which exposed
      and fixed two real Local winner/promotion divergences (see §0). Full
      `all_test.dart` (**144**) + drift tests green on both impls.
- [x] Winner promotion: `_promoteAfterTombstone` — deleting the winning leaf
      promotes the best surviving leaf (CouchDB rule: non-deleted → highest
      generation → highest hash), demoting the old winner to a (deleted) conflict
      leaf and re-indexing via a new seq. Wired into `_internalRemove`; parity
      test "deleting the winner promotes the surviving conflict leaf" green on
      both impls.
- [x] **Fast path `bulkDocsFromMultipart` / `_bulkWriteNoAttachments`** — DONE.
      Extracted the per-doc decision into a shared `_applyIncomingLeaf` helper
      (in-transaction) now used by `bulkDocsRaw`, the main multipart path, AND
      the batch path. The batch path partitions: truly-new + unique docs stay on
      the fast batch insert (large-sync perf preserved); conflict-relevant docs
      (existing winner, or duplicated in the batch) go per-doc through
      `_applyIncomingLeaf` with full attachment orphan/tombstone cleanup +
      promotion. Multipart conflict tests (separate-call + in-batch) green on
      both impls. Regression: `all_test` (113) + drift + `large_sync` (perf) +
      `large_attach_changes_consistency` (orphan cleanup) all pass.
      **Live multipart replication now populates conflicts.**
- [x] **Orphan-check tests** at the API level (2026-06-15). Drift-layer ROW
      cascade was already covered by `local_storage_engine_test.dart`; the new
      `test/orphan_cleanup_test.dart` adds the FILE half against a real on-disk
      `att/` dir: create a conflicted doc whose winner + conflict leaf each carry
      an attachment → delete the database → restart → assert the startup orphan
      scan left ZERO `att/` files (the acceptance-criterion "zero conflict-leaf
      attachment files").

**Stage 2 — conflict-leaf attachments — DONE 2026-06-11/12 (getOpenRevs-attachments deferred):**
Design: extended `local_attachments` with a nullable **`fkconflict`** (schema
**v6**) — winner attachments keep `fkconflict NULL`; a conflict leaf's
attachments reference its `local_conflict_revisions` row. Files stay `att/{PK}`
(one PK space → no collisions; Phase 2 orphan scan reused). One file per
(leaf, attachment) — no refcounted dedup (correctness over storage). Winner
queries `getAttachments`/`getAttachment` scoped to `fkconflict IS NULL`; new
`getConflictAttachment(s)` + `promoteConflictAttachments`/`demoteWinnerAttachments`
re-point helpers. `cleanup_attachments_on_tombstone` scoped to winner only (a
surviving leaf keeps its attachments for promotion); new
`delete_conflict_attachments_before_conflict_revision` trigger drops a leaf's
rows on delete (files via Dart + orphan-scan backstop).
- [x] Store conflict-leaf attachments — inline (`bulkDocsRaw`) and streamed
      (`bulkDocsFromMultipart`) via `_storeInlineConflictAttachments` /
      `_storeStreamConflictAttachments`; `_applyIncomingLeaf` returns the leaf's
      conflict-row id, does the old-winner demote re-point, and collects
      superseded-leaf attachment file ids for deletion.
- [x] `get(rev:loser, attachments:true)` + `getAttachment(rev:loser)` serve the
      leaf's own attachments (`_recreateAttachmentMapFromDatabase` gained
      `conflictRowId`); `getAttachment` unknown-rev → null (Http parity).
- [x] Two conflict leaves sharing identical bytes — each returns them (parity).
- [x] Winner promotion (`_promoteAfterTombstone`) re-points the promoted leaf's
      attachments to the winner BEFORE deleting its conflict row — parity test
      "promotion keeps the promoted conflict leaf's attachment" green.
- [x] Deleting/​superseding a conflict leaf removes its own attachment rows
      (trigger) + files (Dart collects ids in `_applyIncomingLeaf` step (c));
      drift-level cascade/scoping/promote-demote tests in
      `local_storage_engine_test.dart` (schema v6).
- [x] Crash safety: reuses the crash-safe write helpers + Phase 2 orphan scan
      (file with no `local_attachments` row → deleted), which already covers
      conflict-leaf files (shared `att/{PK}` namespace).
- [x] Bodyless `not_found` / tombstone leaf → no attachments stored (skipped).
- [x] **Multipart write-path parity** — `injectMultipartWithAtt` exercises a
      losing conflict leaf with a streamed attachment via `bulkDocsFromMultipart`
      (`_storeStreamConflictAttachments`); green on both impls. Plus stub parity
      (`get(rev:loser)` without attachments → stub) and `getAttachment(unknown
      rev)` → null parity. `all_test` now **+158** (37 conflict-leaf-set cases
      ×2 impls = 74).
- Regression: full sweep 29/31 (the 2 non-passes are the known `_db_updates`
  flake + the no-tests `multi_inheritance` file, see §0); all
  attachment/tombstone/replication suites green.
- [ ] **Deferred follow-ups (low priority):** `getOpenRevs(attachments:)` parity
      (needs Http multipart open_revs support check; byte parity already covered
      by `getAttachment(rev)` + `get(rev,attachments)`); an `att/` file-count
      orphan assertion in an API test (drift row-cascade + Phase 2 orphan scan
      already cover it).
- [x] **Tests now check the post-resolution revision TREE state, not just
      `_conflicts`** (2026-06-14). New `treeState(db, docId)` helper in
      `conflict_resolution_test.dart` reads `getRaw(conflicts:true,
      deletedConflicts:true)` → `(winner, _conflicts, _deleted_conflicts)`. T5
      initial + T5 continuous + the two-replica determinism test now assert the
      tree is *clean*: winner live, `_conflicts` empty, the loser collapsed into
      EXACTLY ONE gen-3 deleted tombstone leaf, and Local↔remote agree on the
      whole tree (winner + tombstone rev). Catches leftover losers, duplicated
      conflict rows, or half-collapsed branches an `_conflicts`-only check misses.
- [x] **Two instances with DIFFERENT (disagreeing) resolvers** — new test "two
      replicas with DIFFERENT (disagreeing) resolvers still converge to one
      clean leaf" (2026-06-14). Replica A = `KeepWinnerResolver`, replica B = a
      merge resolver. WHICH rev wins is a genuine RACE (if A's loser-tombstone
      reaches B before B's caught-up sweep, B never merges → original winner
      stays; otherwise B's merge child wins) — verified by 5 repeat runs hitting
      both branches. The test does NOT pin the winner; it asserts the integrity
      invariants (Decision C: data safety is independent of resolver agreement):
      the conflict ALWAYS collapses to a single clean leaf, the loser is
      tombstoned (one gen-3 deleted leaf, not silently dropped), all three
      replicas agree on winner + tombstone + surviving body, and the survivor is
      one of the two valid outcomes ('winner'/gen-2 or 'merged'/gen-3 → no data
      loss). Convergence is guaranteed because A never *puts* (only B does), so
      there is at most one leaf-creating edit. (Two *put*-ting resolvers with
      different bodies would churn — perf, not integrity — intentionally out of
      scope.)

**Stage 3 — forwarding fidelity — DONE 2026-06-14 (turned out to be a Phase 2 prerequisite, NOT optional):**
- [x] `changes(styleAllDocs)` advertises all local leaves (winner + conflict
      leaves, deleted included) so Local-as-source pushes conflict branches:
      `_changesArrayForDoc` (continuous, order-preserving `.asyncMap`) +
      `_changesArrayFromMap` (normal/longpoll, batch `conflictRevsByDoc`).
- [x] `bulkGetMultipart` serves a requested conflict-leaf rev (incl. deleted
      tombstone leaf, with `_revisions` + own attachments) via
      `_conflictLeafMultipart` — push fetches missing leaves per-rev (revs:true).
- [x] `_applyIncomingLeaf` bumps `update_seq` (`updateDocumentSeq`) on a
      conflict-leaf-only change so the feed re-emits the doc (CouchDB-faithful).
      Without this AND the feed change, Phase 2 resolution never reached the
      remote. Verified end-to-end by `conflict_resolution_test.dart`.

**Optional polish — PROMOTED to load-bearing (2026-06-14), confirmed against the live server, then IMPLEMENTED + TESTED:**
- [x] Record skipped `not_found` revs as known so `revsDiff` stops re-requesting
      bodyless leaves (the residual churn from the shipped fix). **This was the
      remaining root cause of the example-app checkbox flicker (Phase 4).**

  **DONE 2026-06-14.** New `DartCouchDb.recordBodylessLeaf(docId, rev)` (default
  no-op; no-op on Http — a remote already knows its leaves). `LocalDartCouchDb`
  records it as a `body == null`, non-deleted conflict leaf via
  `putConflictRevision`, guarding against the winner / a winner-chain ancestor /
  an existing leaf / an absent doc (idempotent). The pull path calls it at BOTH
  `_isRevisionGone` skip sites (`_createChangeStream` continuous +
  `_streamingReplicate`). Safety guards added: `_promoteAfterTombstone` skips
  non-deleted bodyless leaves (no body to promote); `get(rev:)` returns
  `not_found` for a non-deleted bodyless leaf (Http parity, was a stray
  `_deleted` doc); `_conflictLeafMultipart` serves `not_found` for one (so a
  third partner records it as bodyless instead of receiving a spurious
  tombstone). `revsDiff` already unions conflict revs, so recording alone
  silences it. Net: Local's `_conflicts` now matches Http and the re-pull churn
  stops. Test: `test/bodyless_leaf_test.dart` (4/4, Docker-free Local).

  **CORRECTION + REFINEMENT (2026-06-15) — the resolver must NOT tombstone
  bodyless leaves.** The earlier note assumed an opt-in resolver could *collapse*
  bodyless leaves by tombstoning them. A post-deploy live-server check
  DISPROVED this: the resolver's 6 tombstones reached the remote WITH correct
  ancestry (each a deleted child of its bodyless parent, e.g. `296→295`, deep
  chains reconstructed by CouchDB), yet the 6 bodyless leaves REMAIN non-deleted
  leaves in `_conflicts` and the tombstones just piled up as extra
  `_deleted_conflicts` (14→20). **CouchDB does not collapse a compacted-body leaf
  when a tombstone child is grafted onto it.** Worse, tombstoning *removes the
  leaf's local record*, so revsDiff re-requests it on the next remote re-emit →
  re-record → re-tombstone churn (per-edit local seq bumps that re-emit the doc
  to the view = the flicker got *worse*). True removal needs `_purge`, which does
  not replicate (multi-partner-unsafe) — so bodyless leaves are inherently
  PERMANENT (CouchDB keeps them too). **Fix:** `_maybeResolveConflict` now
  resolves/tombstones only FETCHABLE (`body != null`) losing leaves and SKIPS
  bodyless ones (`fetchableRevs`; early-returns if only bodyless remain). They
  stay preserved (faithful) and inert (recording silences revsDiff; no seq
  churn). `OfflineFirstDb.recordBodylessLeaf` now forwards to its `localDb` (API
  completeness + lets a test inject a bodyless leaf into the offline replica).
  New test `conflict_resolution_test.dart` "the resolver SKIPS a bodyless leaf"
  (9th case): record a bodyless leaf, drive a sweep via an unrelated conflict,
  assert it survives un-tombstoned + winner unchanged + reads `not_found`.
  Regression: `all_test` 158, `bodyless_leaf` 4, `conflict_resolution` 9,
  `local_storage_engine` 13; `offline_first_db` 65/66 (the 1 passes in isolation
  — documented load flake). Also combined the two per-tick health-monitoring
  `FINE` "Session valid" log lines into one (`health_monitoring_mixin.dart`).

  **Live-server evidence (doc `7d1c403d`, db `userdb-4d6f6e61546f6269`):** 23
  leaves — winner `327-…` (erledigt=True), 8 non-deleted conflicts
  (`325,324,295,251,191,180,153,149`), 14 deleted conflicts. Six conflicts
  (`295,251,191,180,153,149`) are GENUINELY bodyless: `_bulk_get?rev=`,
  `GET ?rev=`, and `open_revs=[rev]` ALL return `not_found/missing` (verified per
  rev). They are advertised as leaves by `style=all_docs` on every change, so
  pull re-requests them forever → churn; and because Local never records them,
  Local's `get(conflicts:true)` DIVERGES from Http (server lists them in
  `_conflicts`) — a real A2 parity break, not just a perf issue. The resolver
  can't collapse them (not in local `_conflicts`), so the doc stays perpetually
  conflicted and its winner keeps flipping as the two devices add leaves → the
  flicker.

  **Fix design (3 benefits — parity, churn-stop, collapse):** when pull hits
  `_isRevisionGone`, record the rev as a known **bodyless** conflict leaf
  (`local_conflict_revisions`, `body=null`) instead of silently skipping.
  `revsDiff` already unions conflict revs → stops re-requesting; `_conflicts` then
  matches Http; the resolver tombstones it (tombstone needs only the rev id) →
  pushed → remote leaf set shrinks → `style=all_docs` stops advertising →
  flicker gone. Default (no resolver) still gets parity + churn-stop.
  **Safety to implement:** record strictly non-winning; `_promoteAfterTombstone`
  + winner-selection MUST skip null-body leaves (can't promote a body we don't
  have); `get(rev:bodylessRev)` → `not_found` (Http parity). Plus a regression
  test (test-double source yields `not_found` for a leaf → assert recorded,
  `revsDiff` quiet, resolver tombstones, no bodyless winner). Touches the pull
  path (`replication_mixin.dart:_isRevisionGone` site), `LocalDartCouchDb`
  conflict storage + promotion, and a new interface method.

### Phase 2 — Conflict API + opt-in resolution (Decisions B, C) `[x]` core DONE (impl + core tests GREEN; required + delivered the Stage 3 forwarding fix; full regression sweep 31/32 = no regressions). A few low-value fault-injection tests remain deferred (see checklist).
- [x] **Resolver interface (Decision B)** — `DocumentConflictResolver.resolve(
      ConflictedDocument) → CouchDocumentBase?`; `ConflictedDocument {docId,
      winner, conflicts}`. Default = **no resolver = preserve** (faithful).
      Opt-in `KeepWinnerResolver`. Dead `DocumentReplicationConflictResolver` /
      `DefaultConflictResolver(return-remote)` removed. Threaded through
      `syncTo(resolver:)` → controller → `OfflineFirstDb`/`OfflineFirstServer`
      (nullable, default null). `replication_mixin_interface.dart`.
- [x] **Resolution mechanism (Decision C)** — runs in the replication controller
      (`replication_mixin.dart`) as a **post-replication step on local data only**,
      gated on **caught up** so the local replica holds the COMPLETE leaf set:
      `_resolveCaughtUpConflicts()` after the initial bidirectional one-shot AND
      when continuous settles to `pending == 0`. Discovery via a **cheap LOCAL
      conflict index** (`LocalConflictSource.conflictedDocIds()` — indexed,
      ids-only, non-exported; NOT on the public API, no Http scan), so the
      optimized per-doc transfer loop is untouched. Per doc: `putRaw(survivor)`
      as a child of the winner + a deterministic `newEdits:false` tombstone per
      losing leaf (`_maybeResolveConflict`). `KeepWinnerResolver` skips the
      put (just tombstones losers → winner + attachments preserved); a merged
      survivor on an attachment-carrying doc is skipped+warned (putRaw carries no
      attachment bodies). Results replicate back out via normal push.
- [x] **Data-safety strategy (integrity independent of resolver correctness).**
      Even with a buggy / non-deterministic resolver, an unreliable network, or a
      crash, the library must not lose/corrupt data:
      - Tombstone affects only the **exact** losing rev — a concurrent descendant
        of it survives as a live leaf (never destroys a branch).
      - Resolution writes are **local-first**; the push is **resumable** — network
        loss only delays propagation, deterministic revs re-push idempotently.
      - **Per-document isolation + preserve-on-failure**: a resolver throw / write
        error / crash leaves THAT doc conflicted (preserved, like the default) and
        is retried next caught-up sweep; never aborts the sweep or corrupts state.
        Partial write (survivor put, tombstones not yet) → doc stays conflicted →
        next sweep finishes it.
      - Concurrent remote change during resolution is safe — `newEdits:false`
        never rejects; it just creates a transient new conflict resolved next
        sweep (see test plan).
      - **No threshold/heuristic circuit-breaker** (CLAUDE.md: no heuristics).
        The only failure mode of a non-convergent resolver is **churn** (perf, not
        integrity). Convergence is the resolver's contract; `KeepWinnerResolver`
        satisfies it (global highest-(gen,hash) winner → order-independent,
        bounded by leaf count). Requirement to document prominently: **resolvers
        MUST be deterministic and stable** (same inputs → same survivor, and
        resolving partial sets in steps converges to the same result).
- [x] **T5 resolution** (`conflict_resolution_test.dart`): `KeepWinnerResolver`;
      a conflicted doc converges to a single leaf on **both** sides;
      `get(conflicts:true)` empty afterward. Covered for BOTH the initial one-shot
      path and the continuous-settle path. (Idempotence is exercised by the
      two-replica test below — same deterministic tombstone re-applies as a no-op.)
- [x] **T6 default preserves:** with no resolver, the conflict is preserved on
      both sides (explicit assertion, not just suite-green).
- [~] **TESTS for concurrency / data-safety:**
  - [ ] Remote gains a NEW conflicting leaf while/after local resolves →
        transient new conflict → next caught-up sweep converges. (Not written; the
        loser-extended test covers the same surgical-tombstone safety.)
  - [ ] Remote winner advances (`W→W2`) concurrently with local resolution.
        (Not written; subsumed by determinism + loser-extended.)
  - [x] A "loser" leaf `Ci` extended elsewhere to `Ci'` while local tombstones
        `Ci` → `Ci'` SURVIVES as a live leaf (NO data loss) → re-resolved (becomes
        the new winner, data preserved). **Green.**
  - [x] Double-resolution: two independent replicas tombstone the same `Ci` →
        identical deterministic tombstone rev → idempotent, no divergence. **Green.**
  - [x] Partial-write recovery: a half-written resolution (loser left
        un-tombstoned) is completed by the next sweep. **Green (2026-06-15).** No
        fault-injection hook needed — the test reproduces the exact crash
        half-state by editing the offline replica's SQLite directly (raw
        `AppDatabase`: `deleteConflictRevision(tombstone)` +
        `putConflictRevision(loser, deleted:false)`), then drives a sweep and
        asserts deterministic recovery (winner intact, loser re-tombstoned to the
        SAME rev, single clean leaf, no corruption).
  - [x] Resolver throws on one doc → that doc left conflicted, OTHER docs still
        resolved; sweep not aborted. **Green.**
  - [ ] Network drop during push of resolution data → resumes, no loss. **Not
        written — low marginal value:** resolution data is ordinary changes pushed
        through the same checkpointed feed, so this is already covered by the
        general offline-first resumability tests (`offline_first_db_test`). Doable
        via `cm.pauseContainer()`/`resumeContainer()` if a resolution-specific
        version is ever wanted.
  - [ ] Non-convergent resolver → may churn but data stays valid. **Not written —
        awkward by nature, not a tooling gap:** a single replica always converges
        in one sweep (it tombstones all losers), so there is nothing to churn;
        true non-convergence needs two *put-ting* replicas disagreeing forever,
        which has no deterministic stopping point to assert on. §C already
        classifies this as perf-not-integrity, out of scope. The two-replica
        DIFFERENT-resolvers test covers the bounded/integrity case.
  - [x] Conflict resolution works in initial replication (T5 initial). **Green.**
  - [x] Merge-survivor attachment guard: a merged survivor is written for a plain
        doc but SKIPPED (conflict preserved, attachment intact) for an
        attachment-carrying winner. **Green.**
  - [ ] When initial replication races a fresh remote change, a just-resolved
        conflict re-converges next run. (Partially covered by loser-extended;
        explicit race test deferred.)

### Phase 3 — (folded into Phase 1 Stage 3) `[x]` DONE (cross-reference only)
Push/forwarding fidelity (`changes(styleAllDocs)` advertising all local leaves)
is now tracked under Phase 1 Stage 3. Kept here only as a cross-reference.

### Phase 4 — Example app + UI flicker `[x]` DONE (2026-06-15)
- [x] Got log data from the user (2026-06-15). The per-tap + per-display-delta
      logs (added then removed once diagnosed) proved the flicker is view-layer,
      not the changes/updates stream — see the toggle-flicker entry below.
- [x] Use the new resolution API in the example app (2026-06-14). The example's
      `OfflineFirstServer` (`example/lib/main.dart`) now passes
      `conflictResolver: const KeepWinnerResolver()` — the only resolver actually
      shipped (the plan's earlier `DeterministicWinnerResolver` name was never
      implemented; `KeepWinnerResolver` is the deterministic last-writer-wins
      collapse). `dart analyze` clean. Resolution runs as the caught-up sweep
      (Phase 2 / Decision C): the "erledigt" toggle's conflict tree collapses to
      CouchDB's winner, losers tombstoned, results pushed back out.
- [x] **Checkbox toggle-flicker — ROOT CAUSE FOUND + FIXED (2026-06-15).** The
      earlier hypothesis (re-pull churn re-emitting the winner) was **disproven**.
      With the server unreachable (no push/pull, no resolver sweep) the toggle
      STILL flickered, and per-emission logs showed the view emitting exactly once
      per toggle with `erledigt` flipping a SINGLE time (rev 336→337) — no value
      bounce in the data. So replication/conflict is exonerated; the flicker is a
      pure **view-layer** artifact. Mechanism: a checkbox toggle re-sorts the row,
      so it MOVES, which `ViewDiff` (correctly — it has no "move" primitive by
      design) expresses as remove+insert. `AnimatedViewList` animated the removal,
      so the row's *old* (pre-toggle) content lingered fading out at its old slot
      for `removeDuration` (300 ms). Asymmetric (only on *check*) because on check
      the stale slot sits at the top where the user is looking; on uncheck it is
      lower/off-screen. **Fix:** `_ViewListSync._apply`
      (`dart_couch_widgets/lib/src/animated_view_list.dart`) detects a move (same
      identity removed AND inserted in one batch) and removes it with
      `Duration.zero`, so only the insertion at the new slot animates. Confirmed
      gone by the user in the running app (online + offline). Regression test:
      `animated_view_list_test.dart` "removes the old row instantly when a row
      moves". NOTE: this fix lives in `dart_couch_widgets`, not core `dart_couch`.

**Slow-initial-sync observation (2026-06-14, from the runtime log):** the first
post-resolver startup took ~19 s (initialSync→inSync), dominated by ~14 s of local
SQLite writes (50-doc batch 5.9 s + 15-doc batch 1.6 s + 6.3 s resolution sweep),
~5 s network. ROOT CAUSE = one-time **conflict-backlog drain** (20 changed docs
carried 76 leaf-revs; the toggle doc was at generation 295 with 10+ leaves),
written through the per-doc conflict path (`_applyIncomingLeaf` — many sequential
SQLite queries per leaf, the deliberate A2 correctness-over-speed tradeoff) PLUS
the resolution sweep, all in **debug mode**. NOT steady state: the resolver cleared
the backlog + pushed tombstones, so subsequent syncs pull from the advanced
checkpoint with no leaf fan-out. **Action: re-measure a normal startup in
release/profile mode AFTER the backlog is cleared before optimizing the per-doc
conflict-write path.** Only chase it as a regression if release-mode steady-state
sync is still slow.

### Phase 5 — Check if the parameter 'conflictResolver' is allowed to be nullable `[x]` DONE
Otherwise we could wire in a default Value. **Decision (2026-06-15): KEEP it
nullable, default `null`.** `null` = no resolver = preserve conflicts, which is
the faithful CouchDB default (Decision B). Wiring in a non-null default (e.g.
`KeepWinnerResolver`) would impose a last-writer-wins policy on every app — a
library-imposed heuristic, exactly what the design forbids. The nullable is
handled everywhere (`_maybeResolveConflict` early-returns when null), so there is
no NPE risk. No code change.

### Phase 6 — Check our implementation with the specs of CouchDB `[~]` REVIEW DONE; one gap found + FIXED
The Specs are in REPLICATION_AND_CONFLICT_MODEL.md. We need to check, if we handle
conflicts in a CouchDB compliant way. That includes but is not restricted to using
API functions and the process itself.

**Review done 2026-06-15 (fresh context).** Walked every conflict-relevant clause
of `REPLICATION_AND_CONFLICT_MODEL.md` against `LocalDartCouchDb` (Http proxies
CouchDB = the reference). Result: **compliant on all points except one** (views),
now fixed. Per-clause findings:

- [x] **Both versions survive replication (no data loss).** A2 stores every leaf
      body; `bulkDocsRaw(newEdits:false)` + `_applyIncomingLeaf` maintain the full
      leaf set via incoming `_revisions` ancestry. ✅
- [x] **Deterministic winner (same on all peers).** `_applyIncomingLeaf` step (d)
      + `_promoteAfterTombstone`: linear descendant supersedes; between siblings
      non-deleted beats deleted → higher generation → higher rev hash. Matches
      CouchDB; parity-tested (`all_test` "conflict leaf set", 158). ✅
- [x] **409 conflict avoidance on a single node.** `bulkDocsRaw` newEdits=true path
      (`local_dart_couch_db.dart:251-267`): PUT to an existing non-deleted doc with
      a stale `_rev` → `CouchDbException.conflictPut` (409); a new doc carrying a
      `_rev` → 409. Conflicts only ever enter via newEdits=false (replication),
      exactly as the spec's "Conflict avoidance" section describes. ✅
- [x] **Revision tree / tombstones.** Resolving deletes losing leaves; a deleted
      leaf is retained as a `"_deleted":true` tombstone leaf (kept in the conflict
      side-table, surfaced via `_deleted_conflicts`); deleting the winner promotes
      the best surviving leaf. ✅
- [x] **`GET /{db}/{docid}`** = winner only, no conflict info. `_internalGetRaw`
      adds `_conflicts`/`_deleted_conflicts` only when explicitly requested. ✅
- [x] **`GET …?conflicts=true`** = winner + `_conflicts` array (omitted when empty,
      like CouchDB). ✅ (Phase 0 P2.)
- [x] **`GET …?rev=xxx`** serves an individual conflict-leaf body; a compacted /
      bodyless leaf → `not_found`; a deleted tombstone leaf → minimal `_deleted`
      doc. ✅
- [x] **`GET …?open_revs=all` / `open_revs=[…]`** returns every leaf (winner +
      conflict leaves, deleted tombstones included) wrapped as `{ok}`; explicit
      missing/compacted revs reported as `missing`. Order is unspecified by the
      spec, so returning winner-first is fine. ✅
- [x] **`revs_info=true`** lists the history with head `available`, intermediates
      `missing` (we keep only the head blob — equivalent to a compacted CouchDB),
      tombstones `deleted`. ✅
- [x] **Resolution process matches the spec's suggested algorithm** (§"Working with
      conflicting documents" / "View map functions"): (1) `get(conflicts:true)`,
      (2) `get(rev:xxx)` per conflict, (3) app merge via `DocumentConflictResolver`,
      (4) write survivor + delete the other leaves. We split step 4 into
      `putRaw(survivor)` + `bulkDocsRaw(tombstones, newEdits:false)` rather than one
      `_bulk_docs` — a **deliberate, documented deviation**: (a) local-first +
      resumable (partial-write recovery, Phase 2), and (b) `newEdits:false` with a
      **deterministic** tombstone rev so two devices resolving the same conflict
      converge instead of minting different random revs (the spec's `new_edits=true`
      example does not, which is fine for its single-node illustration but would
      churn in our offline-first multi-master case). End state is identical to the
      spec. ✅
- [x] **`_all_docs?include_docs=true&conflicts=true`** — the spec says `conflicts`
      is *ignored* here (the returned doc never gets `_conflicts`). We don't inject
      it on the `_all_docs`/view query path (`view_ctrl.dart` asserts
      `conflicts == false`), so we match. ✅
- [!] **GAP — View map functions did NOT receive `_conflicts`.** The spec
      ("View map functions"): *"Views only get the winning revision … However, they
      do also get a `_conflicts` member if there are any conflicting revisions,"* so
      the canonical conflict-locating view `function(doc){ if(doc._conflicts) emit(…)}`
      finds conflicted docs. Our local indexer fed the map function only the stored
      winner blob (`view_ctrl.dart:_updateViewEntries`, `mapFunction(${doc.data})`),
      which never carries `_conflicts` — so that view returned rows on
      `HttpDartCouchDb` but **nothing** on `LocalDartCouchDb`. A direct breach of
      the "behave identically" prime directive + Decision A2. **FIXED 2026-06-15:**
      `AppDatabase.liveConflictRevsByDoc(dbid)` (one batched, non-deleted-only query
      per index pass, mirroring `conflictRevsByDoc`) drives a `_conflicts` injection
      into the doc fed to the map function for conflicted docs; non-conflicted docs
      (the common case) are fed their blob verbatim (no extra cost). Incremental
      re-indexing already tracks conflict add/resolve because any leaf-set change
      bumps the doc's `seq` (Stage 3 `updateDocumentSeq`). New parity test in
      `all_test.dart` "conflict leaf set" group: *"a view map function sees
      `_conflicts` for a conflicted doc"* — **green on BOTH impls** (Http confirms
      the live-CouchDB behaviour, Local now matches).
- Out of scope: **Mango `_find`** for conflicts (`{"selector":{"_conflicts":…}}`)
      and a Mango secondary index on `_conflicts` — the library implements Mango
      *index management* only (`createIndex`/`getIndexes`/`deleteIndex`); there is
      no `_find` query path at all, so it is a general "Mango query unimplemented"
      item, not a conflict-handling divergence.

**Files touched (Phase 6 fix):** `local_storage_engine/database.dart`
(`liveConflictRevsByDoc`), `local_storage_engine/view_mgr/view_ctrl.dart`
(`_conflicts` injection in `_updateViewEntries`), `test/all_test.dart` (parity test).
`dart analyze lib/ test/all_test.dart` clean.

**Regression (2026-06-15, serial, `TMPDIR=/var/tmp/dctest`, `--concurrency=1`):** the
indexer change is additive (a non-conflicted doc — the common case — is fed its blob
verbatim), so every view-exercising suite is green: `all_test` **160** (incl. the new
parity test ×2 impls), `use_view` **96**, `reduce` 16, `index` 4, `tree_view` 2. No
regressions.

### Phase 7 — Check if CLAUDE.md needs an update and source code has enough comments `[x]` DONE (2026-06-15)
**CLAUDE.md updated:**
- **Schema History** was stale ("v4 (current)"); added **v5** (`local_conflict_revisions`
  side-table + cascade trigger) and **v6** (`local_attachments.fkconflict` +
  trigger scoping), marked v6 current.
- Added a new **"Conflict Handling"** top-level section (the whole Phase 1–6 model
  was previously undocumented in CLAUDE.md): A2 additive storage (winner row +
  `local_conflict_revisions` / `fkconflict`), `_applyIncomingLeaf` leaf-set
  maintenance, CouchDB-faithful winner selection, read parity (`conflicts`,
  `rev:X`, `getOpenRevs`, `revsDiff`, **views get `_conflicts`** — Phase 6),
  `seq`-bump-on-tree-change + promotion + forwarding, bodyless `not_found` leaves,
  and the opt-in resolver (API, caught-up sweep, mechanism, resolver-independent
  data safety). Pointed the "CouchDB Protocol Compliance" footer at
  `REPLICATION_AND_CONFLICT_MODEL.md`.

**Source comments:** the conflict code (`local_dart_couch_db.dart`,
`replication_mixin.dart`, `view_ctrl.dart`, `database.dart`,
`replication_mixin_interface.dart`) is already densely documented. Fixed **two
comments the conflict work had made factually wrong** (the kind of thing this phase
exists to catch):
- `conflict_resolution_internal.dart` claimed "view map functions and Mango never
  see `_conflicts`" — false (and contradicted by the Phase 6 fix). Rewritten to
  state the real reason there's no remote impl (no cheap indexed enumeration on a
  remote; no `_find`/conflicts-view query path implemented).
- `ConflictedDocument` doc comment claimed resolution "still tombstones" a bodyless
  `not_found` leaf — superseded by the 2026-06-15 correction (resolver SKIPS
  bodyless leaves). Rewritten to say they are excluded and why.

`dart analyze lib/ test/` clean.


---

## 4. Acceptance criteria (whole effort)
- [x] No replication crash / stuck checkpoint on conflicted/high-rev docs.
      (Fixed 2026-06-08 + bodyless-leaf handling; the 21-leaf `7d1c403d` syncs
      cleanly in the live app.)
- [x] `get(conflicts:true)`, `revsDiff`, and winner selection are identical
      between `HttpDartCouchDb` and `LocalDartCouchDb` for conflicted docs.
      (`all_test` "conflict leaf set" parity 158; bodyless leaves now recorded so
      `_conflicts` matches the server too.)
- [x] No re-pull churn for a settled conflicted doc. (Proven by the 2026-06-15
      live-app toggle log: `revsDiff returned nothing missing`, no `Skipping
      unrecoverable revision`, no resolver spam.)
- [x] App can resolve conflicts losslessly via an opt-in resolver; default
      behavior preserves conflicts (no library-imposed policy, no data loss).
      (`conflict_resolution_test` 9/9; default `null` resolver = preserve.)
- [x] New tests above + full existing suite pass (Linux + Docker). (Touched
      suites green; `offline_first_db` has one pre-existing load flake that passes
      in isolation. A clean from-scratch full sweep is still worth a final run.)
- [x] **No orphaned data:** deleting a document or a database leaves zero rows
      in `local_conflict_revisions` and zero conflict-leaf attachment files;
      promotion/resolution/tombstone/crash-recovery never leave the file/metadata
      state inconsistent. (Drift row cascade: `local_storage_engine_test`; att
      FILE cleanup: `orphan_cleanup_test`.)
- [x] **Correct schema migration** v4 → v6; fresh `onCreate` and `onUpgrade`
      paths both produce the same schema + triggers. (`local_storage_engine_test`
      "schema v6".)
- [x] No `Future.delayed`-based timing in tests; no try/catch wrapping of whole
      tests (per CLAUDE.md). (New tests use `waitForCondition`/direct assertions.)

**Remaining before calling the whole effort done:** one clean from-scratch full
regression sweep. Phase 4 visual-flicker is **DONE 2026-06-15** — confirmed in the
running app to be a view-layer move-animation artifact (NOT replication), fixed in
`dart_couch_widgets` `AnimatedViewList` + regression-tested. Phase 6a (CouchDB-spec
compliance review vs `REPLICATION_AND_CONFLICT_MODEL.md`) is **DONE 2026-06-15** —
one gap found and fixed (views now receive `_conflicts`). The deferred
fault-injection tests (§Phase 2) remain optional.

---

## 5. Decisions
- **A2** (revised from A1 after Phase 0) — Local stores **all leaf bodies** (a
  faithful replica), via the additive winner-row + `local_conflict_revisions`
  side-table strategy. Attachments on conflict leaves: **full bodies** (verified
  achievable — CouchDB retains conflict-leaf attachments through compaction).
  Confirmed 2026-06-08.
- **B** — N-way `DocumentConflictResolver.resolve(ConflictedDocument) ->
  CouchDocumentBase?`; app returns the survivor's content, library always
  tombstones the other leaves; default = no-op preserve; `KeepWinnerResolver`
  opt-in. Confirmed 2026-06-08. **Refined 2026-06-13:** resolvers MUST be
  **deterministic AND stable** (resolving a partial leaf set in steps must
  converge to the same result as resolving the whole set — leaves can arrive
  across batches). Data integrity does NOT depend on this (see C).
- **C** — resolver stays a `syncTo` parameter (forwarded by `OfflineFirstDb`);
  raw transfer stays faithful; resolution is a separate opt-in deterministic
  phase on top. Confirmed 2026-06-08. **Refined 2026-06-13 (trigger + safety
  now decided, were "TBD in Phase 2"):**
  - **Trigger = caught-up sweep, never per-change.** Runs after the initial
    bidirectional one-shot and whenever continuous settles to `pending == 0`, so
    the local replica holds the COMPLETE leaf set (resolving a partial set
    mid-stream would pick a wrong survivor and diverge).
  - **Local-data-only + cheap local conflict index.** Discovery is
    `LocalConflictSource.conflictedDocIds()` — an indexed, ids-only local query
    (`conflict_resolution_internal.dart`, **non-exported / not public API**); NO
    remote scan, NO `_all_docs` download, and the optimized per-doc transfer loop
    is untouched. (Rejected: a public `getConflictedDocuments` + Http scan — a
    remote can't index conflicts, so it would download the whole DB.)
  - **Mechanism:** `putRaw(survivor)` as a child of the winner + a deterministic
    `newEdits:false` tombstone per losing leaf (CouchDB has no "delete a specific
    conflict leaf" primitive, so tombstones go via the faithful transfer path).
    `KeepWinnerResolver` skips the put entirely (tombstones losers only →
    winner + its attachments preserved); a merged survivor on an
    attachment-carrying doc is skipped+warned (putRaw carries no attachment
    bodies).
  - **Data safety is independent of resolver correctness.** Per-document
    isolation + preserve-on-failure (a resolver throw / write error / crash leaves
    that doc conflicted and retried, never aborts/corrupts); a tombstone hits only
    the exact losing rev (a concurrent descendant survives → no branch loss);
    writes are local-first + resumable. NO heuristic circuit-breaker (CLAUDE.md);
    the worst case of a bad/non-deterministic resolver is churn, never lost or
    corrupted data.

Phases 0 + 1 complete; Phase 2 implemented (untested). See §0 LATEST handoff.
