# DartCouchDB Project Guidelines

This file shall contain:
- requirements
- decisions
- open issues
- Whatever is needed, to understand the principles of this library

Especially it shall not contain:
- History
- Implementation details (use comments in source code for that)

## Project Overview

In subfolder example we find an example App using this library. It is used for first line of user tests but one a single application using this general lib.

**DartCouchDB** (`dart_couch`) is a **pure Dart** library (no Flutter SDK dependency) providing a CouchDB-compatible API interface with two implementations:

1. **HttpDartCouchDb** (Reference Implementation)
   - Speaks directly to CouchDB via HTTP
   - Acts as the reference for correct behavior
   - Handles CouchDB's native sequence formats, replication protocol, etc.

2. **LocalDartCouchDb**
   - Imitates DartCouchDB behavior locally (using SQLite)
   - Must behave identically to HttpDartCouchDb from the API perspective
   - Uses local sequence formats (e.g., "N-dummyhash" vs CouchDB's opaque sequences)

Both implementations share the same `DartCouchDb` interface, enabling:
- Offline-first architecture (local + remote sync)
- Bidirectional replication between local and remote
- Transparent failover and data persistence

The library is a pure Dart package and can be used in CLI tools, servers, or any Dart application. Flutter-specific widgets (login dialogs, state proxy widgets, lifecycle observer) live in the companion package **`dart_couch_widgets`**.

## Core Principles

### NO HEURISTICS
**CRITICAL**: This project must NEVER use heuristics for replication, synchronization, or database state detection. All behavior must be deterministic and reliable, in implementation and tests.

- ❌ NO arbitrary thresholds (e.g., "if count < 10")
- ❌ NO "likely" or "probably" logic
- ❌ Future.delay is not to be used as it is not deterministic
- ✅ USE deterministic checks (sequence regression, UUID mismatches)
- ✅ USE marker documents for state tracking

### REPLICATION CONSISTENCY
**CRITICAL**: The replication algorithm must recover from any error and maintain a consistent replication state at all times. The local database must never get permanently out of sync with the remote.

- Every document that exists on the source MUST eventually be replicated to the target — no silent data loss
- If a bulk fetch or write fails, every doc in the failed batch MUST be retried individually before the checkpoint advances
- If an individual retry also fails, it is logged as a warning. The checkpoint may still advance (pre-existing CouchDB protocol behavior), but `revsDiff` on next replication will detect the missing doc and re-transfer it
- Performance optimizations (parallelism, pipelining, batching) must NEVER compromise consistency — if in doubt, choose the slower but correct path
- Offline operation is a first-class feature: the local database must be fully functional offline. When connectivity returns, replication MUST bring both sides into sync without data loss

### REPLICATION REQUIREMENTS
**CRITICAL**: The following requirements apply equally to initial replication and continuous replication. Continuous mode is not allowed to weaken correctness guarantees in exchange for liveness or throughput.

- Replication MUST keep the database in a consistent state at all times. Partial failures are allowed, but replication state, checkpoints, metadata, and attachment storage must remain recoverable and internally consistent.
- Replication MUST recover from arbitrary errors, including network loss during continuous replication. Temporary failures must not leave the local database permanently out of sync with the remote.
- Replication MUST remain deterministic and MUST follow CouchDB-compatible replication semantics. Conflict handling and winner selection must not use app-specific heuristics, random tie-breaking, or behavior that diverges from CouchDB's revision-tree rules.
- Replication MUST preserve eventual convergence: every source revision that should exist on the target must eventually be transferred, even if a bulk operation fails and recovery has to fall back to per-document retries.
- Checkpoints MUST be correct before they are fast. Sequence values from different namespaces or database implementations must never be mixed, and checkpoint invalidation on recreation must invalidate all relevant directions.
- Replication MUST optimize for low memory usage, especially for attachments, by preferring streaming transfer paths. Large attachment payloads must not be materialized for an entire replication batch when a streaming path exists.
- Replication SHOULD still use bulk fetch and bulk write operations for documents when this improves throughput, but batching, pipelining, or parallelism must never break correctness, retryability, or crash safety.
- `ReplicationProgress` updates MUST be coalesced or rate-limited so listeners receive meaningful progress changes without being flooded by high-frequency byte or document updates.
- Attachment files and stored attachment metadata MUST remain consistent with each other. Crash recovery, tombstones, retries, and replication writes must not leave a permanently inconsistent file/metadata state.
- If a design choice trades off consistency vs performance, choose consistency. Performance work is valid only when it preserves deterministic recovery and CouchDB-compatible results.

**CRITICAL**: In test implementations we shall not use try catch (only if a special exception behaviour is tested). For example embedding a complete test function in a try-catch block may mask out problems.

## Testing

Tests require **Linux with Docker** installed. Most tests spin up a CouchDB container via Docker and cannot run on Windows or without Docker. Do not attempt to run tests in a Windows environment.

### Test Logging

Every test file's `main()` calls **`configureTestLogging()`** (in `test/helper/helper.dart`) once, before any `group`/`test`. Do not re-add per-file `Logger.root.onRecord` boilerplate.

- **Default (quiet):** log records are buffered in memory and flushed to stdout **only for tests that fail**, under a `--- captured logs for failed test ---` banner. Passing runs stay silent. Failure detection covers both `expect()` mismatches (`Result.failure`) and uncaught/propagating exceptions (`Result.error`) via `Invoker.current.liveTest.state.result.isFailing` — consistent with the "don't catch exceptions in tests" rule (a propagating exception is reported as a failure and triggers the flush).
- **Live (verbose):** prints every record as it happens. Enable with either:
  - `flutter test --dart-define=ENABLE_LOGGING=true` (compile-time define)
  - `ENABLE_LOGGING=1 dart test` (runtime env var)

  Both are wired because `dart test` does **not** forward `--dart-define`, while `flutter test` does.

Implementation notes: the flush runs in a global `tearDown` registered at the top of `main()` (outermost scope → runs last, after all other teardowns and after the pass/fail state is finalized). `tearDown` registrations stack, so tests/groups can still add their own. Accessing the result uses `package:test_api`'s internal `Invoker` (a direct `dev_dependency`, imported with `// ignore: implementation_imports`).

### Parallel Test Execution

Tests run in parallel (`dart_test.yaml` sets `concurrency: 4`). `dart test` runs each test *file* (suite) in its own isolate, so suites must not share mutable global resources. Isolation is achieved by:

- **Self-allocated explicit ports.** `startCouchDb` (helper.dart) and `CouchTestManager._startCouchDb` pick a free host port themselves via `CouchTestManager.findFreePort()` and run the container with an **explicit** `-p <port>:5984` mapping. This is deliberate: Docker's `-p 0:5984` re-randomizes the host port on every `docker start`, which breaks pause/resume — a stopped-then-started container comes back on a *different* port while the long-lived `OfflineFirstServer` (and the URI polled by `_waitForCouchDb`) still point at the old, now-dead port. An explicit mapping is preserved across stop/start, so the port is stable for the container's lifetime. The port is stored in the per-suite top-level `couchPort`; use the `couchUri` getter (helper.dart) or `cm.uri` (CouchTestManager) instead of a hardcoded `http://localhost:5984`.
  - `findFreePort()` binds an ephemeral socket (`bind(0)`) to get an OS-free port, **and** excludes every host port already claimed by any existing Docker container — running *or stopped* — read from each container's `HostConfig.PortBindings` via `docker ps -aq` + `docker inspect` (`_dockerReservedHostPorts`). `bind(0)` alone only proves a port is free *now*; a stopped container's mapping is invisible at the socket level, so without the exclusion a reused port would collide once both containers are (re)started. Excluding them keeps all test containers mutually restartable.
  - A tiny window remains between releasing the socket and `docker run` binding the port (a concurrently-starting sibling's container doesn't exist yet, so it isn't in the reserved set). On that rare collision `docker run` fails loudly with "port is already allocated"; the start loop re-allocates a fresh port and retries (up to 5 times). A **pinned** port (see relogin below) must not move, so a collision there is a hard failure instead.
- **Unique SQLite dirs.** `prepareSqliteDir()` / `CouchTestManager` use `Directory.systemTemp.createTempSync(...)` so every call gets a unique path. Drift/sqlite only conflicts when two opens hit the *same* file, so distinct paths keep suites isolated even within one process.
- **Targeted cleanup only.** Each suite removes **only its own** container via `shutdownCouchDb` / `_shutdownCouchDb` (`docker stop` then `docker rm -fv <id>`), called from `tearDownAll` (`cm.dispose()`), `tearDownAllHttpFunction`, or a direct call. There is **no** global `docker container/volume prune` and **no** "kill all CouchDB containers" step — those destroy sibling suites' live containers. All test containers carry the `dart_couch_test` label; leftovers from crashed runs are cleaned by `tool/clean_test_containers.sh` (run manually, never from inside a suite).
- **Offline / relogin tests.** Tests that simulate a *permanently* unreachable server (one that never comes back up) use `deadCouchUri()` — an OS-assigned free port with nothing listening. Tests that simulate **relogin** (server goes down then comes back at the *same* address) instead call `reserveCouchPort()`, which reserves the suite's port and points `couchUri` at it without starting a container (so `couchUri` is dead), then later `startCouchDb(..., port: couchPort)` brings the container up on that exact port — the same `couchUri` transitions dead → alive. Using two *different* URIs for the dead and alive phases would not actually exercise relogin. `proxy_login_test` reuses the freed CouchDB port for its nginx container so the server reconnects to the same address.

**Rule:** never hardcode `http://localhost:5984` or a fixed SQLite path in a test, and never add a "stop all containers" call — both break parallel runs.

## Database Recreation Detection

### Marker-Based System
The project uses **database markers** (`_local/db_sync_marker`) for reliable recreation detection:

- Each database has a unique `databaseUuid` stored in its marker
- Markers track which instance created the database
- UUID mismatch = database was recreated (deterministic, no guessing)
- See `lib/src/offline_first_server.dart` for implementation

### Checkpoint Management
Replication checkpoints store progress for resuming sync:

- **Dual checkpoints** for bidirectional replication:
  - `sourceLastSeq`: Position in source changes feed (push direction)
  - `targetLastSeq`: Position in target changes feed (pull direction)
- Different databases use different sequence formats (local vs HTTP)
- Never mix sequences across namespaces (causes "Malformed sequence" errors)

When recreation is detected via markers, ALL checkpoint types must be invalidated:
- `'_local/{db}::{db}::push'`
- `'_local/{db}::{db}::pull'`
- `'_local/{db}::{db}::both'` ← Note: it's "both" not "bidirectional"

## Conflict Handling

`LocalDartCouchDb` is a **faithful conflict replica** (Decision A2): it stores every
leaf revision so it behaves identically to `HttpDartCouchDb` (= CouchDB) for
conflicted documents. The reference spec is **`REPLICATION_AND_CONFLICT_MODEL.md`**
(CouchDB's own "Replication and conflict model"); a per-clause compliance review
lives in `PLAN.md` Phase 6. **Never resolve conflicts automatically inside the
library** — CouchDB preserves conflicts and leaves resolution to the app, so the
default behaviour is preserve (see NO HEURISTICS).

### Storage model (additive side table)
- The **winner** stays one row per `(fkdatabase, docid)` in `local_documents` — so
  views, the changes feed, `seq`, and fast winner reads are unchanged.
- **Non-winning leaf bodies** live in `local_conflict_revisions` (schema v5);
  conflict-leaf **attachments** reference their leaf via `local_attachments.fkconflict`
  (v6). One file per (leaf, attachment) in the shared `att/{PK}` namespace.
- `_applyIncomingLeaf` (`local_dart_couch_db.dart`) does **leaf-set maintenance** for
  every `newEdits:false` write (the three write paths — `bulkDocsRaw`, the multipart
  main path, and the no-attachment batch path — all funnel through it). It uses the
  incoming `_revisions` ancestry to distinguish a **linear supersede** (incoming is a
  descendant → old rev becomes history) from a **sibling branch** (→ both are leaves
  = a conflict). The write path strips `_revisions` early, so it is captured first.

### Winner selection (CouchDB-faithful, deterministic — same on all peers)
A **linear descendant** supersedes unconditionally. Between **sibling** leaves:
non-deleted beats deleted → higher generation → higher rev hash. Implemented in
`_applyIncomingLeaf` step (d) and mirrored in `_promoteAfterTombstone`. Winner
selection must NOT use app heuristics or random tie-breaking.

### Reads (full Http parity)
- `get(conflicts:true)` / `deletedConflicts:true` / `meta:true` populate
  `_conflicts` / `_deleted_conflicts` from the side table (omitted when empty).
- `get(rev:X)` serves a conflict-leaf body; a compacted/bodyless leaf → `not_found`;
  a deleted tombstone leaf → minimal `_deleted` doc.
- `getOpenRevs` returns the full leaf set (winner + conflict leaves, deleted included)
  as `{ok}` results; explicit missing revs → `missing`.
- `revsDiff` unions side-table revs, so it is order-independent and does not
  re-request known conflict leaves.
- **Views** receive the winner **plus a `_conflicts` member** when the doc is in
  conflict (Phase 6 — matches CouchDB; lets `function(doc){ if(doc._conflicts) … }`
  locate conflicts). Injected in `view_ctrl._updateViewEntries` via
  `AppDatabase.liveConflictRevsByDoc`. `_all_docs?conflicts=true` is ignored, as in
  CouchDB.

### Tree changes bump `seq`; promotion; forwarding
- ANY leaf-set change (add / supersede / tombstone a *losing* leaf) bumps the
  document's `update_seq` via `AppDatabase.updateDocumentSeq`, even when the winner
  row is untouched — CouchDB does this so the changes feed re-emits the doc (required
  for resolution tombstones to push out, and for incremental view re-indexing).
- Deleting the winning leaf promotes the best surviving leaf
  (`_promoteAfterTombstone`).
- **Local-as-source forwarding:** `changes(styleAllDocs)` advertises every leaf, and
  `bulkGetMultipart` serves a requested conflict-leaf rev (with `_revisions` + its own
  attachments) — so Local can push conflict branches to a remote.

### Bodyless (`not_found`) leaves
A permanently compacted leaf (no body on the source) is recorded via
`recordBodylessLeaf` as a `body == null` conflict leaf so `revsDiff` stops
re-requesting it and `_conflicts` matches Http. Such leaves are **inherently
permanent** (CouchDB keeps them too; only `_purge`, which does not replicate, removes
them) — winner-selection / promotion skip them, `get(rev:)` returns `not_found`, and
**the resolver must NOT tombstone them** (grafting a tombstone child does not collapse
a compacted-body leaf and just causes churn).

### Resolution (opt-in, separate phase — never mixed into raw transfer)
- API in `replication_mixin_interface.dart`: `DocumentConflictResolver.resolve(
  ConflictedDocument) → CouchDocumentBase?`. Default **no resolver = preserve**;
  opt-in `KeepWinnerResolver` (deterministic last-writer-wins). Threaded through
  `syncTo(resolver:)` → controller → `OfflineFirstDb`/`OfflineFirstServer` (nullable,
  default `null` — wiring a non-null default would impose a library policy).
  **Resolvers MUST be deterministic AND stable** (same inputs → same survivor, and
  resolving a partial leaf set converges to the same result as the whole set).
- Runs as a **caught-up sweep** (`_resolveCaughtUpConflicts` / `_maybeResolveConflict`
  in `replication_mixin.dart`): after the initial bidirectional one-shot and whenever
  continuous settles to `pending == 0`, so the replica holds the COMPLETE leaf set —
  **never per-change mid-stream**. Discovery is a cheap LOCAL conflict index
  (`LocalConflictSource.conflictedDocIds`, in `conflict_resolution_internal.dart` —
  **non-exported / not public API**, no remote scan).
- Mechanism: `putRaw(survivor)` as a child of the winner + a deterministic
  `newEdits:false` tombstone per *fetchable* losing leaf. `KeepWinnerResolver` skips
  the put (tombstones losers only → winner + its attachments preserved); a merged
  survivor on an attachment-carrying doc is skipped+warned (putRaw carries no
  attachment bodies). Results replicate out via normal push.
- **Data safety is independent of resolver correctness:** per-document isolation +
  preserve-on-failure (a throw / write error / crash leaves THAT doc conflicted and
  retried — never aborts the sweep or corrupts state), a tombstone hits only the exact
  losing rev (a concurrent descendant survives), writes are local-first + resumable,
  and there is **no heuristic circuit-breaker**. Worst case of a bad/non-deterministic
  resolver is churn, never lost/corrupt data.

## Local Attachment Storage

### Overview

Attachment binary data is managed by the `AttachmentStorage` abstraction (`lib/src/local_storage_engine/attachment_storage.dart`). Platform-specific implementations are selected via conditional import in `attachment_storage_factory.dart`:

- **Native** (`NativeAttachmentStorage`): Files on disk in `att/{id}` — see below.
- **Web** (`WebAttachmentStorage`): BLOBs in a `attachment_blobs_web` SQLite table — see "Web Attachment Storage" above.

On native, attachment binary data is stored as individual files on disk, **not** as BLOBs in SQLite. This keeps the SQLite file small and prevents memory issues when replicating documents with large attachments.

**Directory layout** (one `LocalDartCouchServer`)
```
{rootDir}/
  db.sqlite          ← all Drift/SQLite tables (metadata only)
  att/
    1                ← binary data for local_attachments row id=1
    2                ← binary data for local_attachments row id=2
    42.tmp           ← in-progress UPDATE for row id=42 (normally transient)
    ...
```

The filename is the integer primary key of the `local_attachments` row. All databases in a server share one `att/` directory; files are unique because the PK sequence is global.

### Failsafe Write Order

All attachment writes happen inside `db.transaction()`. The ordering differs for INSERT vs UPDATE to protect against crashes:

**UPDATE** (attachment already exists, `entry.id` is present) — DELETE-old + INSERT-new:
1. Delete old DB row (`db.deleteAttachment(existingId)`)
2. Insert new DB row (gets fresh auto-increment `newId`)
3. Write data to `att/{newId}` directly
4. After transaction commits: delete old file `att/{existingId}`

The old file is never overwritten inside the transaction. If a crash occurs before the transaction commits, the DB rolls back (old row restored, new row gone), `att/{existingId}` is intact, and `att/{newId}` is an orphan cleaned up by Phase 2 recovery. If a crash occurs after commit but before the old file is deleted, `att/{existingId}` is an orphan (no DB row) cleaned up by Phase 2 recovery.

Old IDs are collected in a `deferredFileDeletes` list passed to `_saveAttachmentWithFileIO` / `_saveAttachmentFromStream` and cleaned up by the caller after `db.transaction()` returns.

**INSERT** (new attachment, no `entry.id`):
1. Insert DB row to get the auto-increment ID
2. Write `att/{id}` directly (no old file to protect)
3. On file-write failure: delete the DB row (prevent orphan metadata)

If the process crashes between steps 1 and 2, the enclosing `db.transaction()` was never committed — SQLite rolls it back on next open. No orphan DB row survives.

### Startup Crash Recovery (`LocalDartCouchServer._recoverAttachmentFiles`)

Runs once during `_ensureInitialized()`, before any database is opened.

**Phase 1 — stale `.tmp` files**: delete every `att/*.tmp`.

These are leftovers from the legacy UPDATE path (pre-2026-03-19) which used `.tmp` files and atomic rename. The current UPDATE path no longer creates `.tmp` files, but Phase 1 is retained for forward compatibility and to clean up any `.tmp` files from older versions.

**Phase 2 — orphan files**: for every file in `att/` whose integer name has no matching `local_attachments` row, delete the file. This handles:
- INSERT crash: file was written but transaction rolled back (DB row gone).
- UPDATE crash before commit: new file `att/{newId}` was written but transaction rolled back. Old file `att/{existingId}` is intact (DB row restored).
- UPDATE crash after commit: old file `att/{existingId}` survives but its DB row was deleted (committed). Cleaned up as orphan.

Note: there is intentionally **no** orphan-DB-row cleanup (checking for DB rows without files). Both INSERT and UPDATE happen inside `db.transaction()`, so a crash always rolls back the DB row — orphan rows from crashes are impossible. The only scenario where a DB row exists without a file is external file deletion (e.g. OS clearing cache), and deleting those rows would destroy metadata that replication cannot recover.

### Tombstone File Cleanup

The `cleanup_attachments_on_tombstone` SQLite trigger (in `database.dart`) removes `local_attachments` rows when a document is tombstoned. SQLite triggers cannot delete files. The Dart layer must:

1. Collect attachment IDs **before** the tombstone write (inside the transaction).
2. Delete the attachment files **after** the transaction commits.

This pattern is applied in `LocalDartCouchDb._internalRemove` and the `deleted=true` path in `LocalDartCouchDb.bulkDocsRaw`.

### Schema History

- **v1**: `attachment_blobs` table stored binary data inline in SQLite.
- **v2**: `attachment_blobs` dropped; data stored as files. The v1→v2 migration drops the table and its `delete_attachment_blob_before_attachment` trigger. Existing blob data is intentionally discarded (local DB is a cache).
- **v3**: `local_attachments.encoding` nullable text column added. Stores the CouchDB content-encoding (e.g. `'gzip'`) when an attachment was compressed by CouchDB. `null` for locally-created attachments. Migration: `ALTER TABLE local_attachments ADD COLUMN encoding TEXT`.
- **v4**: `local_documents.docid` changed from globally UNIQUE to unique per `(fkdatabase, docid)`. Migration: table recreation with `PRAGMA foreign_keys = OFF`.
- **v5**: `local_conflict_revisions` table added (`id, fkdocument → local_documents(id), rev, version, deleted, body`) to store **non-winning conflict-leaf bodies** (faithful conflict storage — Decision A2; see "Conflict Handling" below). Indexes on `fkdocument` and unique `(fkdocument, rev)`; a `delete_conflict_revisions_before_delete_document` BEFORE-DELETE trigger cascades row cleanup so deleting a document/database leaves no orphaned conflict rows. Migration: `CREATE TABLE` + indexes + trigger.
- **v6** (current): `local_attachments.fkconflict` nullable column added (`REFERENCES local_conflict_revisions(id)`) for **conflict-leaf attachment bodies**. `null` = a winner attachment (unchanged behaviour); non-null points at the owning conflict leaf. The `cleanup_attachments_on_tombstone` trigger is scoped to winner attachments (`fkconflict IS NULL`) so a surviving leaf keeps its attachments for promotion, and a new `delete_conflict_attachments_before_conflict_revision` trigger drops a leaf's attachment rows when its conflict row is deleted (files cleaned by the Dart layer + the Phase-2 orphan scan). Migration: `ALTER TABLE … ADD COLUMN fkconflict` + index + trigger changes.
- **Web-only**: `attachment_blobs_web` table created at runtime by `WebAttachmentStorage.initialize()` — not part of the Drift schema or migration versioning.

## CouchDB Attachment Compression

CouchDB automatically gzip-compresses attachments whose `Content-Type` matches `compressible_types` (default: `text/*, application/javascript, application/json, application/xml`).

### Decompression layers

Two distinct layers handle `Content-Encoding: gzip`:

1. **HTTP-level** (`GET /db/doc/attachment`): Dart's `http` package / `dart:io` HttpClient decompresses transparently. `HttpDartCouchDb.getAttachment` always returns the original uncompressed bytes.

2. **MIME-level** (`_bulk_get` multipart): Binary attachment parts inside a `multipart/related` response can carry their own `Content-Encoding: gzip` header. Dart's http client does **not** handle MIME-level headers. `HttpDartCouchDb._parseRelatedOuterPart` detects this header and decompresses via the platform-adaptive `gzipDecode()` function (`platform/gzip_decode.dart`) — `dart:io`'s `gzip.decode()` on native, browser's `DecompressionStream` API on web.

**Result:** `getAttachment` and `BulkGetMultipartAttachment.data` always return decompressed bytes in both `HttpDartCouchDb` and `LocalDartCouchDb`. `LocalDartCouchDb` stores decompressed bytes in `att/` files and applies no compression of its own.

### Digest invariant and `encoding` field

When CouchDB compresses an attachment, `digest` in the attachment stub is MD5 of the **compressed** bytes. The `att/{id}` file holds decompressed bytes. **File content ≠ digest.** This is intentional:

- `revsDiff` / `atts_since` compare `local_attachments.digest` with CouchDB's digest — both are `MD5(compressed)` for remote-origin attachments, so they agree and no spurious re-transfers occur.
- For locally-created attachments (`saveAttachment`), digest is `MD5(raw bytes)`. When pushed to CouchDB, CouchDB re-compresses and derives `MD5(compressed)`. This pre-existing mismatch does not cause replication loops because `bulkDocs(newEdits: false)` stores the revision as-is.

```
CouchDB digest  → MD5(gzip(content))   ← both sides store and compare this
local att/ file → original content     ← what getAttachment returns
```

The `local_attachments.encoding` column (v3) makes the digest semantics self-describing:

| `encoding` | Digest is… | `att/{id}` file holds… |
|---|---|---|
| `null` | MD5(raw bytes) | raw bytes — digest verifiable |
| `'gzip'` | MD5(compressed bytes) | decompressed bytes — digest NOT directly verifiable against file |

`AttachmentInfo.encoding` surfaces this to application code via `get()` / `getRaw()`. It is **not** serialized to JSON (`AttachmentInfoRawHook.afterEncode` strips it) so it never appears in CouchDB protocol messages. `_internalGetRaw()` re-injects it into the raw stub map after `toMap()` so it survives the JSON→Dart parse in `get()`.

**Rule for tests:** use `contentType: 'application/octet-stream'` when testing **digest or length metadata** specifically, to avoid compression and keep `MD5(file) == digest`. Tests that only verify returned content (not digest) can safely use `text/plain` — decompression is now transparent end-to-end.

## Web Platform Support

The library runs on web (Chrome, Firefox, Safari) in addition to Linux, Windows, and Android. No public API changes — application code compiles and runs identically on all platforms.

### Conditional Import Pattern

All platform-specific code uses the same conditional import pattern:

```dart
export 'thing_native.dart'
    if (dart.library.js_interop) 'thing_web.dart';
```

The native implementation is always the **default** branch. This is critical because the Dart analyzer resolves conditional imports to the default branch for static analysis.

| Hub file | Native | Web | Purpose |
|---|---|---|---|
| `platform/io_shim.dart` | Re-exports `dart:io` | Stub classes (`Directory`, `File`, `Platform`, etc.) | Avoid `dart:io` import on web |
| `platform/http_client_factory.dart` | `http.Client()` | `BrowserClient(withCredentials: true)` | Platform HTTP client |
| `platform/gzip_decode.dart` | `dart:io` `gzip.decode()` | Browser `DecompressionStream` API | MIME-level gzip in multipart |
| `quickjs/js_engine.dart` | QuickJS via FFI | Browser `eval()` via `dart:js_interop` | CouchDB map/reduce views |
| `local_storage_engine/database_connection.dart` | `NativeDatabase` (SQLite FFI) | `WasmDatabase` (SQLite WASM + IndexedDB) | Drift database backend |
| `local_storage_engine/attachment_storage_factory.dart` | File-based (`att/{id}`) | BLOB table in SQLite | Attachment binary storage |

### Web Authentication (Basic Auth)

On native platforms, CouchDB login works via cookie-based sessions: `POST /_session` returns a `Set-Cookie: AuthSession=...` header, and the cookie is sent with every subsequent request.

On web, this approach fails for two reasons:
1. **`Set-Cookie` is a forbidden response header** in the Fetch spec — JavaScript cannot read it.
2. **`SameSite=Strict`** on CouchDB's `AuthSession` cookie prevents the browser from attaching it to cross-origin requests.

**Solution:** On web, every request uses HTTP Basic Auth (`Authorization: Basic <base64(user:pass)>`) instead of cookies. This is the same approach PouchDB uses. The `username` and `password` are stored after login and injected by `HttpMethods._addAuthHeader()`.

After a successful web login, `authCookie` is set to the sentinel value `'browser-managed'` so that health monitoring and other code checking `authCookie != null` knows a session exists. The sentinel is never sent as an actual cookie.

See `http_methods.dart:_addAuthHeader()` and `http_dart_couch_server.dart:login()`.

### Web JavaScript Engine

On native, CouchDB map/reduce view functions are evaluated by QuickJS (embedded C engine via FFI). On web, the browser's native JavaScript engine is used via `dart:js_interop`'s `eval()`.

Key details:
- State persists between `evaluate()` calls because `eval()` executes at global scope — `var` declarations survive across calls, matching QuickJS behaviour.
- `String()` (JavaScript's built-in) converts return values to strings, matching QuickJS's `JS_ToCString` (e.g. `null` → `'null'`, not empty string).
- The build hook (`hook/build.dart`) skips native compilation for web targets via `if (!input.config.buildCodeAssets) return;`.

### Web Attachment Storage

On native, attachment binaries live as files in `att/{id}` (see "Local Attachment Storage" below). On web, there is no filesystem — attachments are stored as BLOBs in a `attachment_blobs_web` table created at runtime via raw SQL.

The `.tmp` write pattern used on native for crash safety is unnecessary on web because SQLite transactions are fully atomic — `writeTmpAttachment` writes directly to the final location and `promoteTmp` is a no-op.

### Web Database (Drift WASM)

On web, Drift uses SQLite compiled to WASM with IndexedDB-backed persistence. The example app requires two files in `web/`:
- `sqlite3.wasm` — from the `sqlite3` package release matching `pubspec.lock`
- `drift_worker.js` — from the `drift` package release matching `pubspec.lock`

The database name is derived from the `Directory` path by sanitising non-alphanumeric characters: `Directory('/data/myapp')` → DB name `"data_myapp"`. This way application code passes `Directory('some/path')` on all platforms.

### Web io_shim Stubs

`platform/io_shim_web.dart` provides stub classes for `dart:io` types (`Directory`, `File`, `Platform`, `Process`, etc.) so that code referencing these types compiles on web. The stubs are never used at runtime on web — actual I/O goes through the platform-specific abstractions above. Methods on stub classes throw `UnsupportedError` to catch accidental runtime use.

## QuickJS Native Build

The library embeds [QuickJS](https://github.com/quickjs-ng/quickjs) (source committed directly in `third_party/quickjs/`) to evaluate CouchDB map/reduce view functions locally. A custom C wrapper (`native/quickjs_wrapper.c` / `quickjs_wrapper.h`) exposes a minimal FFI API:

- `qjs_new()` — create a QuickJS runtime+context
- `qjs_eval()` — evaluate JavaScript code, returning result or error as a malloc'd string
- `qjs_dispose()` — destroy the engine and free resources

The Dart side (`lib/src/quickjs/quickjs_bindings.dart`) uses `dart:ffi` to call the C wrapper. `JsEngine` (`lib/src/quickjs/js_engine.dart`) provides the high-level API via conditional import — on web, the browser's native `eval()` is used instead (see "Web JavaScript Engine" above).

### Build Hook

Native compilation is handled by a **Dart native assets build hook** in `hook/build.dart`. It uses `package:native_toolchain_c` to compile:

- `native/quickjs_wrapper.c`
- `third_party/quickjs/quickjs.c`, `dtoa.c`, `libregexp.c`, `libunicode.c`

Includes: `native/`, `third_party/quickjs/`

Defines: `CONFIG_VERSION`, `_GNU_SOURCE`, `CONFIG_BIGNUM`, `QUICKJS_WRAPPER_BUILD`

The hook runs automatically when `dart run`, `dart test`, or `dart compile` is invoked — no manual compilation step is needed. On web targets, the hook exits early (`if (!input.config.buildCodeAssets) return;`) since there is no native code to compile. On Windows, the hook includes a workaround to find MSVC tools when the VS install path contains spaces.

## Package Structure

This is a monorepo with two packages:

| Package | Path | Description |
|---|---|---|
| `dart_couch` | `packages/dart_couch/` | Core library — pure Dart, no Flutter dependency. Runs on Linux, Windows, Android, and web. |
| `dart_couch_widgets` | `packages/dart_couch_widgets/` | Flutter widgets and helpers (depends on `dart_couch`) |

The core package uses `DcValueNotifier` / `DcValueListenable` (in `lib/src/value_notifier.dart`) as pure-Dart replacements for Flutter's `ValueNotifier` / `ValueListenable`. The widget package provides `DcValueListenableBuilder` to bridge these into Flutter's widget tree.

## Login error classification (requirement)
`HttpDartCouchServer.login()` MUST classify a non-JSON / non-CouchDB response
(e.g. a reverse proxy returning an HTML error page, or a truncated/garbled body)
as a **network error** (`loginFailedWithNetworkError`, returns `null`) — NOT as
`wrongCredentials`. Treating it as wrong credentials makes `OfflineFirstServer`
skip the `onLogin` callback even though cached credentials exist, which can leave
an offline-capable app stuck (historically a blank screen). Network-error
classification lets `loginWithReloginFlag()` fall back to cached credentials and
fire `onLogin`.

## CouchDB Protocol Compliance
Follow CouchDB's replication protocol - it doesn't use heuristics, neither should we.
The conflict model we mirror is documented in **`REPLICATION_AND_CONFLICT_MODEL.md`**
(CouchDB's own spec); see the "Conflict Handling" section above and `PLAN.md` Phase 6
for the per-clause compliance review.
