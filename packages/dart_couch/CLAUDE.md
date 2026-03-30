# DartCouchDB Project Guidelines

## Project Overview

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

## Recent Fixes

### Sporadic Checkpoint Test Failure (2026-02-20)
**Root causes:**
1. Wrong checkpoint ID (`'bidirectional'` instead of `'both'`) prevented invalidation
2. Unreliable heuristic (`< 10` threshold) caused race conditions
3. Wrong fallback (using `sourceLastSeq` for missing `targetLastSeq`)
4. **Infinite timer resets**: Rapid continuous changes kept cancelling checkpoint timer

**Fixes:**
- `offline_first_server.dart:1653` - Fixed checkpoint ID to `'both'`
- `replication_mixin.dart:_findCommonAncestry()` - Removed heuristic, changed fallback to `null`
- `replication_mixin.dart:_scheduleCheckpoint()` - Added max delay (10s) to prevent infinite timer resets
- Result: Deterministic checkpoint migration + guaranteed periodic saves

**Infinite Timer Reset Issue:**
When continuous changes arrive rapidly, each calls `_scheduleCheckpoint()` which cancels and restarts the 5-second timer. This prevented checkpoint from ever being saved.

**Solution:** Track `_lastCheckpointSaveTime` and force save after `_maxCheckpointDelay` (10s) regardless of new changes. This ensures checkpoints are saved at least every 10 seconds even during high-frequency replication.

### Byte Reporting Progress Tracking (2026-02-20)
**Root causes:**
1. `_transferredBytes` was reset per batch while `_transferredDocs` accumulated across session → semantic mismatch
2. `_totalBytesEstimate` only reflected current batch, not running total → nonsensical ratios like "706KB / 101KB"
3. Estimate used `revs: false` while actual transfer used `revs: true` → missing revision history overhead (~1KB per edited document)

**Fixes:**
- `replication_mixin.dart:862-887` - Changed byte tracking semantics:
  - `_transferredBytes` now accumulates across entire session (like `_transferredDocs`)
  - `_totalBytesEstimate` = already transferred + current batch estimate
  - Small batches (< 5 docs) set estimate to null (UI won't show byte progress)
- `replication_mixin.dart:_estimateDocSizes()` - Changed estimate fetch to use `revs: true` to match actual transfer
- Result: Accurate byte reporting for documents with/without attachments, correct progress ratios

**Why revs matter:**
CouchDB includes `_revisions` field when `revs: true`, containing the full revision tree. For frequently-edited documents, this adds ~1KB+ per document. The estimate must include this overhead to match actual transfer sizes.

### Memory-Efficient Attachment Replication (2026-02-27, updated 2026-03-17)
**Problem:** The replication producer-consumer pipeline used `bulkGetRaw(attachments: true)` which loaded all attachment data for an entire batch as base64-encoded JSON into memory before writing to the target. For documents with large attachments this caused significant memory pressure.

**Fix:** Replaced `bulkGetRaw` + `bulkDocsRaw` with `bulkGetMultipart` + `bulkDocsFromMultipart` in both the batch replication path (`_streamingReplicate`) and the continuous replication path.

**How it works:**
- `bulkGetMultipart` streams one result per doc/rev. For HTTP source, each attachment part is eagerly drained to `Uint8List` before the result is yielded (peak memory = largest single attachment). For local source, results carry lazy file-backed streams.
- `bulkDocsFromMultipart` on `LocalDartCouchDb` pipes each attachment stream directly to the `att/{id}` file — no base64 decode, no large in-memory buffer.
- Size estimate in `_estimateDocSizes` now uses raw `length` (not `length * 4/3`) since multipart transfers raw bytes, not base64.
- Removed dead code: `_AsyncSemaphore`, `_SemaphoreCancelled`, `_handleBulkDocsConflict` (which was already marked dead — `bulkDocs(newEdits: false)` never produces 409).

### Per-Doc Immediate Write + Dual Pipeline (2026-03-17)
**Problem:** `_streamingReplicate` collected all docs in a batch (5) before writing, holding all their attachments in memory simultaneously. Batches were processed strictly sequentially (fetch 5 → write 5 → fetch 5 → write 5), with no overlap between HTTP download and disk write. For initial sync of databases with many large attachments this was very slow.

**Fix (per-doc immediate write):** Both `_streamingReplicate` and the continuous replication path (`_createChangeStream`) now write each document immediately as it arrives from the `bulkGetMultipart` stream, instead of collecting all docs first. Peak memory = one doc's attachments at a time. The `processedKeys` set is updated AFTER successful write so that on stream error the fallback loop can retry unwritten docs.

**Fix (dual pipeline):** `_streamingReplicate` now uses two concurrent HTTP pipelines feeding a merge queue (`StreamController<_PipelineResult>`). Each pipeline takes groups of 3 docs from a shared index, fetches via `bulkGetMultipart`, and forwards results to the merge queue. A single consumer writes each doc immediately. While one pipeline's doc is being written to disk, the other pipeline downloads the next batch — overlapping HTTP I/O with disk I/O.

**Key design decisions:**
- Adaptive batch sizing via `_buildAdaptiveGroups()`: groups are capped at 1 MB / 50 docs. Small docs (no attachments) get batched 50 together for fewer HTTP round trips; large docs (with attachments) naturally form small groups for low peak memory. Size estimates from `_estimateDocSizes()` drive the grouping.
- `processedKeys.add()` moved AFTER `bulkDocsFromMultipart()` succeeds, not before — ensures failed writes are retried in the fallback path
- Continuous replication path does NOT use dual pipelines (processes one change event at a time via pause/resume backpressure)
- The `_PipelineResult` class wraps results with their source group and error state for the consumer
- `http.Client` supports concurrent requests via internal connection pooling; no second client needed
- Per-pipeline byte tracking via `pipelineAccumulatedBytes[]` array. Each pipeline tracks cumulative bytes across all its groups (not just current HTTP response). Avoids concurrent overwrite between pipelines (see "Dual Pipeline Byte Tracking Fix" below).

### Dual Pipeline Byte Tracking, Progress Counters, and Adaptive Batching (2026-03-18)
**Problems:**
1. **Byte tracking race:** Each pipeline captured `bytesBeforeBatch = _transferredBytes` then set `_transferredBytes = bytesBeforeBatch + bytes`. When both pipelines ran concurrently, one pipeline's `onBytesReceived` callback overwrote the other's contribution, causing bytes to jump backward or stall. Additionally, `onBytesReceived(bytes)` reports cumulative bytes per HTTP response (resets to 0 for each new `_bulk_get` call), so when a pipeline moved to its next group, the previous group's bytes were lost.
2. **Counter double-decrement:** `_fetchAndWriteIndividual` did `_docsFetching--; _docsFetchComplete++`, and the outer consumer loop did the same. Fallback paths called `_fetchAndWriteIndividual` then fell through to the outer update — double-decrementing `_docsFetching` into negative values, breaking progress display.
3. **Missing counter in continuous path:** When `_normalizeReplicationDoc` returned null in the continuous path, the code did `continue` without updating `_docsFetching--` / `_docsFetchComplete++`, stalling progress.
4. **Stale `_sourceSeq` after pull:** In bidirectional mode, push one-shot set `_sourceSeq = 1-dummyhash` (local was empty). Pull one-shot then wrote N docs locally. Push continuous started from `1-dummyhash`, re-processing all N just-pulled docs through revsDiff (all returning "nothing to write").
5. **Fixed batch size too small for small docs:** `producerBatchSize = 3` meant ~217 HTTP round trips for 649 small shopping-list docs. The small batch size was chosen for memory with large attachments, but most docs were tiny.

**Fixes:**
- `replication_mixin.dart:_streamingReplicate()` — Replaced per-pipeline `bytesBeforeBatch` with `pipelineAccumulatedBytes[]` array that accumulates across groups. Each pipeline tracks `baseForThisGroup` before starting a new HTTP request, then adds the per-response cumulative bytes on top. `_transferredBytes = bytesBeforeStreaming + sum(pipelineAccumulatedBytes)`. Removed `streamingBytesTracked` from `_PipelineResult`.
- `replication_mixin.dart:_buildAdaptiveGroups()` — New method replaces fixed `producerBatchSize`. Uses per-doc size estimates from `_estimateDocSizes()` to group docs: target 1 MB per group, max 50 docs per group, fallback to 20 docs when no estimates available. Small docs batch together for fewer HTTP round trips; large docs form small groups for low peak memory.
- `replication_mixin.dart:_streamingReplicate()` consumer — Docs without attachments are collected into a write batch and flushed in a single `bulkDocsFromMultipart()` call (up to 50 docs per batch = one SQLite transaction). Docs with attachments are still written immediately to keep peak memory low. This batching applies to both the HTTP fetch grouping (adaptive groups) and the write path (write batches).
- `replication_mixin.dart:_fetchAndWriteIndividual()` — Removed counter updates. Counter updates now happen only in the caller.
- `replication_mixin.dart:_createChangeStream()` — Added `_docsFetching--; _docsFetchComplete++` before `continue` in the malformed doc path.
- `replication_mixin.dart:_run()` — After both one-shot directions complete in bidirectional mode, `_sourceSeq` is updated to `source.info().updateSeq`. Push continuous now starts from the correct position.
- `http_dart_couch_db.dart:_parseRelatedOuterPart()` — Added diagnostic logging for unexpected doc structures in multipart parsing fallback paths (helps diagnose "malformed bulk_get" errors).

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
- **v4** (current): `local_documents.docid` changed from globally UNIQUE to unique per `(fkdatabase, docid)`. Migration: table recreation with `PRAGMA foreign_keys = OFF`.
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

## Open Issues

### Sporadic Blank Screen on App Startup (2026-03-30)

**Symptom:** The example app occasionally shows a completely blank grey screen on startup (no AppBar, no spinner, no progress bar). Possibly related to network quality (poor, broken, or DNS issues). Reported on Android.

**Partial fix applied:** `HttpDartCouchServer.login()` had a generic `catch (e)` that rethrew unexpected exceptions (e.g. `HandshakeException`, `FormatException` from truncated responses). This left `OfflineFirstServer` stuck in `tryingToConnect` state permanently. Fixed by returning `null` (network error) instead of rethrowing, matching the `ClientException` and `TimeoutException` handlers.

**If the problem recurs:** The completely blank screen (not even a spinner) suggests an unhandled exception during `build()` in release mode (Flutter's ErrorWidget renders as `SizedBox.shrink()` in release). The investigation did not definitively identify which build path throws. Next step: add **file logging** to the example app (write logs to a file on disk instead of just `print`) so that when the blank screen appears, the log file can be analyzed to see the exact state transitions, exceptions, and widget lifecycle events. Key areas to instrument:
- `DbStateProxyWidget._handleLogin()` — log before/after each step, especially the `onLogin` callback
- `OfflineFirstServer.loginWithReloginFlag()` — log state transitions and exception details
- `ReplicationStateProxyWidget._loadAndSetupDatabases()` — log whether databases were found
- `MyHomePage.build()` — log whether `di<OfflineFirstDb>()` succeeds

## CouchDB Protocol Compliance
Follow CouchDB's replication protocol - it doesn't use heuristics, neither should we.
