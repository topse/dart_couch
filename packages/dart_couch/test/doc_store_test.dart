import 'dart:async';
import 'dart:convert';

import 'package:dart_couch/dart_couch.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:test/test.dart';

part 'doc_store_test.mapper.dart';

/// In-memory fake of the [DocDb] port — the whole point of the port is that the
/// document primitives can be exercised with *this*, no real CouchDB, no
/// changes feed, no debounce timing. Models CouchDB's optimistic-concurrency
/// `put` (409 on a stale `_rev`) and lets a test simulate external writers.
///
/// This is deliberately a small reusable harness; the full contract suite
/// (W1–W7, H1–H5) can be built on top of it.
class FakeDocDb implements DocDb {
  final Map<String, CouchDocumentBase> store = {};
  final Map<String, StreamController<CouchDocumentBase?>> _watchers = {};
  int _rev = 0;
  int putCount = 0;

  /// Number of upcoming [put]s to fail with a forced conflict (to exercise the
  /// conflict-retry path without staging a real rev race).
  int failNextPutsWithConflict = 0;

  /// Number of upcoming [put]s to fail with a non-conflict error (to exercise
  /// the transient-error backoff path).
  int failNextPutsWithError = 0;

  /// When set, every [put] awaits this before completing — lets a test hold a
  /// write "in flight" and act (e.g. inject an external change) while it is
  /// suspended. Complete it to release.
  Completer<void>? putGate;

  /// Highest number of [put]s ever in flight at once — should stay 1 (W1).
  int maxConcurrentPuts = 0;
  int _concurrentPuts = 0;

  @override
  Future<CouchDocumentBase?> get(String docId) async => store[docId];

  @override
  Future<CouchDocumentBase> put(CouchDocumentBase doc) async {
    _concurrentPuts++;
    if (_concurrentPuts > maxConcurrentPuts) {
      maxConcurrentPuts = _concurrentPuts;
    }
    try {
      final gate = putGate;
      if (gate != null) await gate.future;
      putCount++;
      if (failNextPutsWithConflict > 0) {
        failNextPutsWithConflict--;
        throw CouchDbException(CouchDbStatusCodes.conflict, 'forced');
      }
      if (failNextPutsWithError > 0) {
        failNextPutsWithError--;
        throw Exception('forced non-conflict error');
      }
      final existing = store[doc.id];
      if (existing?.rev != doc.rev) {
        throw CouchDbException(CouchDbStatusCodes.conflict, 'rev mismatch');
      }
      final saved = doc.copyWith(rev: 'r${++_rev}');
      store[doc.id!] = saved;
      _emit(doc.id!, saved);
      return saved;
    } finally {
      _concurrentPuts--;
    }
  }

  @override
  Stream<CouchDocumentBase?> watch(String docId) => _watchers
      .putIfAbsent(
        docId,
        () => StreamController<CouchDocumentBase?>.broadcast(),
      )
      .stream;

  /// Simulate an external writer (e.g. the companion) updating the document.
  void externalPut(CouchDocumentBase doc) {
    final saved = doc.copyWith(rev: 'r${++_rev}');
    store[doc.id!] = saved;
    _emit(doc.id!, saved);
  }

  void externalDelete(String docId) {
    store.remove(docId);
    _emit(docId, null);
  }

  void _emit(String docId, CouchDocumentBase? doc) {
    final controller = _watchers[docId];
    if (controller == null) return;
    // Deliver on a later event-loop turn, like CouchDB's change feed — never
    // synchronously inside put(), so the writer has already recorded the new
    // rev before its own echo arrives (otherwise the echo races the rev update
    // and looks external — see W4).
    Timer.run(() => controller.add(doc));
  }
}

PlayPosition _pos(
  String id, {
  String? rev,
  Map<String, PlayPositionItem> items = const {},
}) => PlayPosition(deviceId: 'd', id: id, rev: rev, items: items);

PlayPositionItem _item(String title) => PlayPositionItem(title: title);

/// Flush pending microtasks so broadcast-stream emissions are delivered.
Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('LiveDocHandle', () {
    test(
      'optimistic read + coalesces rapid updates into ≤2 puts (H1/H2/W2)',
      () async {
        final db = FakeDocDb();
        final handle = DocStore(
          db,
        ).handle<PlayPosition>('pp', emptyValue: _pos('pp'));
        await handle.start();

        handle.update((d) => d.copyWith(items: {...d.items, 'a': _item('A')}));
        // H1: visible immediately, before any put resolves.
        expect(handle.current.items.keys, contains('a'));

        handle.update((d) => d.copyWith(items: {...d.items, 'b': _item('B')}));
        handle.update((d) => d.copyWith(items: {...d.items, 'c': _item('C')}));

        await handle.settle();

        final stored = db.store['pp'] as PlayPosition;
        expect(stored.items.keys, containsAll(['a', 'b', 'c']));
        // Three updates, but the last two coalesced behind the in-flight first.
        expect(db.putCount, lessThanOrEqualTo(2));
      },
    );

    test('adopts an external change and the next write does not clobber it '
        '(H4/W5)', () async {
      final db = FakeDocDb();
      final handle = DocStore(
        db,
      ).handle<PlayPosition>('pp', emptyValue: _pos('pp'));
      await handle.start();

      handle.update((d) => d.copyWith(items: {...d.items, 'a': _item('A')}));
      await handle.settle();

      // Companion adds 'b' out-of-band.
      final current = db.store['pp'] as PlayPosition;
      db.externalPut(
        current.copyWith(items: {...current.items, 'b': _item('B')}),
      );
      await _pump();
      expect(handle.current.items.keys, containsAll(['a', 'b']));

      // Our next delta must merge on top of the external 'b', not drop it.
      handle.update((d) => d.copyWith(items: {...d.items, 'c': _item('C')}));
      await handle.settle();

      final stored = db.store['pp'] as PlayPosition;
      expect(stored.items.keys, containsAll(['a', 'b', 'c']));
    });

    test(
      'external delete resets to emptyValue; a later write re-creates (H5)',
      () async {
        final db = FakeDocDb();
        final handle = DocStore(
          db,
        ).handle<PlayPosition>('pp', emptyValue: _pos('pp'));
        await handle.start();

        handle.update((d) => d.copyWith(items: {...d.items, 'a': _item('A')}));
        await handle.settle();

        db.externalDelete('pp');
        await _pump();
        expect(handle.current.items, isEmpty);

        handle.update((d) => d.copyWith(items: {...d.items, 'z': _item('Z')}));
        await handle.settle();
        expect((db.store['pp'] as PlayPosition).items.keys, contains('z'));
      },
    );

    test(
      'serialises writes — one put in flight despite rapid updates (W1)',
      () async {
        final db = FakeDocDb()..putGate = Completer<void>();
        final handle = DocStore(
          db,
        ).handle<PlayPosition>('pp', emptyValue: _pos('pp'));
        await handle.start();

        handle.update((d) => d.copyWith(items: {...d.items, 'a': _item('A')}));
        handle.update((d) => d.copyWith(items: {...d.items, 'b': _item('B')}));
        handle.update((d) => d.copyWith(items: {...d.items, 'c': _item('C')}));
        await _pump(); // first put reaches the held gate

        expect(db.maxConcurrentPuts, 1); // single-flight despite three updates

        db.putGate!.complete(); // release
        await handle.settle();
        expect(
          (db.store['pp'] as PlayPosition).items.keys,
          containsAll(['a', 'b', 'c']),
        );
        expect(db.maxConcurrentPuts, 1);
      },
    );

    test('merges an external change that lands while a local write is in flight '
        '(H3)', () async {
      final db = FakeDocDb();
      final handle = DocStore(
        db,
      ).handle<PlayPosition>('pp', emptyValue: _pos('pp'));
      await handle.start();

      handle.update((d) => d.copyWith(items: {...d.items, 'a': _item('A')}));
      await handle.settle(); // base = {a}

      // Hold the next write in flight, then have the companion add 'c'.
      db.putGate = Completer<void>();
      handle.update((d) => d.copyWith(items: {...d.items, 'b': _item('B')}));
      await _pump(); // the {a,b} put is now suspended at the gate

      final base = db.store['pp'] as PlayPosition;
      db.externalPut(base.copyWith(items: {...base.items, 'c': _item('C')}));
      await _pump();
      // Optimistic state already reflects external 'c' + unconfirmed 'b'.
      expect(handle.current.items.keys, containsAll(['a', 'b', 'c']));

      // Release: the stale {a,b} put 409s and retries against the merged base.
      db.putGate!.complete();
      await handle.settle();
      expect(
        (db.store['pp'] as PlayPosition).items.keys,
        containsAll(['a', 'b', 'c']),
      );
    });

    test('start() adopts a pre-existing stored document', () async {
      final db = FakeDocDb()
        ..store['pp'] = _pos('pp', rev: 'r1', items: {'x': _item('X')});
      final handle = DocStore(
        db,
      ).handle<PlayPosition>('pp', emptyValue: _pos('pp'));
      await handle.start();
      expect(handle.current.items.keys, contains('x'));
    });
  });

  group('SaveDocWriter', () {
    test(
      'builds from the latest state and retries on conflict (W3/W6)',
      () async {
        final db = FakeDocDb();
        final writer = SaveDocWriter(db: db, docId: 'pl');
        await writer.start();

        db.failNextPutsWithConflict = 1; // first put 409s
        writer.save((rev) => _pos('pl', rev: rev, items: {'x': _item('X')}));
        await writer.settle();

        expect((db.store['pl'] as PlayPosition).items.keys, contains('x'));
        expect(db.putCount, 2); // one forced conflict + one success
      },
    );

    test('ignores our own write echo, fires onExternalChange only for real '
        'external changes (W4/W5)', () async {
      final db = FakeDocDb();
      final writer = SaveDocWriter(db: db, docId: 'pl');
      var externalCalls = 0;
      writer.onExternalChange = (_) => externalCalls++;
      await writer.start();

      writer.save((rev) => _pos('pl', rev: rev, items: {'x': _item('X')}));
      await writer.settle();
      await _pump(); // deliver the own-write echo on the watch stream
      expect(externalCalls, 0); // W4: own echo ignored

      final base = db.store['pl'] as PlayPosition;
      db.externalPut(base.copyWith(items: {...base.items, 'y': _item('Y')}));
      await _pump();
      expect(externalCalls, 1); // W5: real external change observed
    });

    test(
      'gives up after maxAttempts conflicts, no infinite loop (W6)',
      () async {
        final db = FakeDocDb()..failNextPutsWithConflict = 3;
        final writer = SaveDocWriter(db: db, docId: 'pl', maxAttempts: 2);
        await writer.start();

        writer.save((rev) => _pos('pl', rev: rev, items: {'x': _item('X')}));
        await writer.settle();

        expect(db.putCount, 3); // 2 retries allowed → 3 attempts, then dropped
        expect(db.store['pl'], isNull); // never persisted
      },
    );

    test(
      'retries a transient non-conflict error, then succeeds (W6)',
      () async {
        final db = FakeDocDb()..failNextPutsWithError = 1;
        final writer = SaveDocWriter(db: db, docId: 'pl');
        await writer.start();

        writer.save((rev) => _pos('pl', rev: rev, items: {'x': _item('X')}));
        await writer.settle();

        expect(db.putCount, 2); // one transient failure + one success
        expect((db.store['pl'] as PlayPosition).items.keys, contains('x'));
      },
    );
  });

  group('updateDoc (one-shot)', () {
    test('reads, mutates, retries on conflict', () async {
      final db = FakeDocDb()
        ..store['k'] = _pos('k', rev: 'r0', items: {'a': _item('A')})
        ..failNextPutsWithConflict = 1;

      final saved = await updateDoc<PlayPosition>(
        db,
        'k',
        (cur) => cur!.copyWith(items: {...cur.items, 'b': _item('B')}),
      );

      expect(saved, isNotNull);
      expect(
        (db.store['k'] as PlayPosition).items.keys,
        containsAll(['a', 'b']),
      );
    });

    test('aborts (no put) when build returns null', () async {
      final db = FakeDocDb();
      final saved = await updateDoc<PlayPosition>(
        db,
        'missing',
        (cur) => cur?.copyWith(items: {}), // absent → null → abort
      );
      expect(saved, isNull);
      expect(db.putCount, 0);
    });

    test('returns null on an unexpected document type (R11)', () async {
      final db = FakeDocDb()
        ..store['k'] = CouchDocumentBase(
          id: 'k',
          rev: 'r1',
        ); // not a PlayPosition
      final saved = await updateDoc<PlayPosition>(
        db,
        'k',
        (cur) => cur!.copyWith(items: {}),
      );
      expect(saved, isNull); // bailed before building
      expect(db.putCount, 0);
    });
  });

  group('DocStore', () {
    test('caches one writer / handle per document id', () {
      final store = DocStore(FakeDocDb());
      expect(identical(store.writer('a'), store.writer('a')), isTrue);
      expect(identical(store.writer('a'), store.writer('b')), isFalse);

      final h1 = store.handle<PlayPosition>('h', emptyValue: _pos('h'));
      final h2 = store.handle<PlayPosition>('h', emptyValue: _pos('h'));
      expect(identical(h1, h2), isTrue);
    });
  });
}

/// Per-device audiobook resume points and "done" markers.
///
/// Document ID: `playposition-<deviceUuid>`
///
/// Replicated (unlike the previous `_local/playposition` storage) so the
/// companion can list and clean up entries, and so positions survive an app
/// reinstall via replication.
@MappableClass(discriminatorValue: 'play_position', ignoreNull: true)
class PlayPosition extends CouchDocumentBase with PlayPositionMappable {
  static String docIdFor(String deviceUuid) => 'playposition-$deviceUuid';

  @MappableField(key: 'device_id')
  final String deviceId;

  /// Position/done entries keyed by MediaItem ID.
  final Map<String, PlayPositionItem> items;

  PlayPosition({
    required this.deviceId,
    this.items = const {},
    super.id,
    super.rev,
    super.attachments,
    super.deleted,
    super.revisions,
    super.revsInfo,
    super.unmappedProps,
  });

  /// Removes every entry keyed by one of [itemIds] from all replicated
  /// `playposition-<deviceUuid>` documents (one per device). Lists the
  /// per-device documents and rewrites only those that actually referenced a
  /// removed item. Idempotent; a no-op when [itemIds] is empty.
  ///
  /// Used by the catalog cascade delete ([MediaBase.delete]) to honour the
  /// companion contract that deleting an item must drop its resume position
  /// immediately, rather than waiting for the startup repair sweep.
  static Future<void> purgeItems(DartCouchDb db, Set<String> itemIds) async {
    if (itemIds.isEmpty) return;
    final result = await db.allDocs(
      startkey: jsonEncode('playposition-'),
      endkey: jsonEncode('playposition-\u{ffff}'),
      includeDocs: true,
    );
    for (final row in result.rows) {
      final doc = row.doc;
      if (doc is! PlayPosition) continue;
      final filtered = <String, PlayPositionItem>{
        for (final e in doc.items.entries)
          if (!itemIds.contains(e.key)) e.key: e.value,
      };
      if (filtered.length == doc.items.length) continue;
      await db.put(doc.copyWith(items: filtered));
    }
  }
}

/// Per-item entry in [PlayPosition]. Carries the item title so the document
/// stays readable when inspected manually and survives the original item's
/// rename or deletion.
@MappableClass(ignoreNull: true)
class PlayPositionItem with PlayPositionItemMappable {
  final String title;

  /// In-progress resume point. Null when the item is finished or hasn't been
  /// started yet.
  final PlayPositionPoint? position;

  /// True once the item has been heard to its natural end.
  final bool done;

  const PlayPositionItem({this.title = '', this.position, this.done = false});
}

@MappableClass()
class PlayPositionPoint with PlayPositionPointMappable {
  final int track;
  final int seconds;

  const PlayPositionPoint({required this.track, required this.seconds});
}
