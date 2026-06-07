import 'dart:convert';
import 'dart:math';

import 'package:dart_couch/dart_couch.dart';
import 'package:test/test.dart';

/// Applies an edit script to a copy of [old] using the documented semantics:
/// insert at index, remove from index, replace at index — in order.
List<ViewEntry> applyChanges(List<ViewEntry> old, List<ViewRowChange> changes) {
  final list = List<ViewEntry>.of(old);
  for (final c in changes) {
    switch (c) {
      case ViewRowInserted(:final index, :final row):
        list.insert(index, row);
      case ViewRowRemoved(:final index):
        list.removeAt(index);
      case ViewRowChanged(:final index, :final row):
        list[index] = row;
    }
  }
  return list;
}

/// Positional equivalence by identity + content: same length and, at each
/// position, the same id, emit key, emit value and document revision.
void expectEquivalent(List<ViewEntry> actual, List<ViewEntry> expected) {
  expect(actual.length, expected.length, reason: 'length mismatch');
  for (var i = 0; i < actual.length; i++) {
    expect(actual[i].id, expected[i].id, reason: 'id at $i');
    expect(
      jsonEncode(actual[i].key),
      jsonEncode(expected[i].key),
      reason: 'key at $i',
    );
    expect(
      jsonEncode(actual[i].value),
      jsonEncode(expected[i].value),
      reason: 'value at $i',
    );
    expect(actual[i].doc?.rev, expected[i].doc?.rev, reason: 'rev at $i');
  }
}

ViewEntry row(String id, Object? key, Object? value, {String? rev}) => ViewEntry(
  id: id,
  key: key,
  value: value,
  doc: rev == null ? null : CouchDocumentBase(id: id, rev: rev),
);

void main() {
  group('ViewDiff.compute', () {
    test('empty -> empty produces no changes', () {
      expect(ViewDiff.compute([], []), isEmpty);
    });

    test('identical lists produce no changes', () {
      final a = [row('d0', 'a', 1), row('d1', 'b', 2)];
      final b = [row('d0', 'a', 1), row('d1', 'b', 2)];
      expect(ViewDiff.compute(a, b), isEmpty);
    });

    test('a value change is a single ViewRowChanged in place', () {
      final a = [row('d0', 'a', 1), row('d1', 'b', 2)];
      final b = [row('d0', 'a', 1), row('d1', 'b', 99)];
      final changes = ViewDiff.compute(a, b);
      expect(changes, hasLength(1));
      expect(changes.single, isA<ViewRowChanged>());
      expect((changes.single as ViewRowChanged).index, 1);
      expectEquivalent(applyChanges(a, changes), b);
    });

    test('a body (rev) change with unchanged value is a ViewRowChanged', () {
      final a = [row('d0', 'a', 1, rev: '1-x')];
      final b = [row('d0', 'a', 1, rev: '2-y')];
      final changes = ViewDiff.compute(a, b);
      expect(changes, hasLength(1));
      expect(changes.single, isA<ViewRowChanged>());
      expectEquivalent(applyChanges(a, changes), b);
    });

    test('insertion in the middle', () {
      final a = [row('d0', 'a', 1), row('d2', 'c', 3)];
      final b = [row('d0', 'a', 1), row('d1', 'b', 2), row('d2', 'c', 3)];
      final changes = ViewDiff.compute(a, b);
      expect(changes.whereType<ViewRowInserted>(), hasLength(1));
      expect(changes.whereType<ViewRowRemoved>(), isEmpty);
      expectEquivalent(applyChanges(a, changes), b);
    });

    test('removal from the middle', () {
      final a = [row('d0', 'a', 1), row('d1', 'b', 2), row('d2', 'c', 3)];
      final b = [row('d0', 'a', 1), row('d2', 'c', 3)];
      final changes = ViewDiff.compute(a, b);
      expect(changes.whereType<ViewRowRemoved>(), hasLength(1));
      expect(changes.whereType<ViewRowInserted>(), isEmpty);
      expectEquivalent(applyChanges(a, changes), b);
    });

    test('reorder is expressed as remove + insert and still applies', () {
      final a = [row('d0', 'a', 1), row('d1', 'b', 2)];
      final b = [row('d1', 'b', 2), row('d0', 'a', 1)];
      final changes = ViewDiff.compute(a, b);
      expectEquivalent(applyChanges(a, changes), b);
    });

    test('a single move is one remove + one insert of the moved row, not '
        'churn of the rows it passes (both directions)', () {
      // [A B C D E] -> [A C D E B]: B is "checked" (content also changes) and
      // sorts to the end. Only B should move; A C D E stay put.
      final down0 = [
        row('a', 'A', 1),
        row('b', 'B', 1),
        row('c', 'C', 1),
        row('d', 'D', 1),
        row('e', 'E', 1),
      ];
      final down1 = [
        row('a', 'A', 1),
        row('c', 'C', 1),
        row('d', 'D', 1),
        row('e', 'E', 1),
        row('b', 'B', 2),
      ];

      final down = ViewDiff.compute(down0, down1);
      expect(down.whereType<ViewRowRemoved>(), hasLength(1));
      expect(down.whereType<ViewRowInserted>(), hasLength(1));
      expect(down.whereType<ViewRowRemoved>().first.row.id, 'b');
      expect(down.whereType<ViewRowInserted>().first.row.id, 'b');
      expectEquivalent(applyChanges(down0, down), down1);

      // The reverse (move up) is likewise a single move of B.
      final up = ViewDiff.compute(down1, down0);
      expect(up.whereType<ViewRowRemoved>(), hasLength(1));
      expect(up.whereType<ViewRowInserted>(), hasLength(1));
      expect(up.whereType<ViewRowRemoved>().first.row.id, 'b');
      expectEquivalent(applyChanges(down1, up), down0);
    });

    test('duplicate (id, key) rows are matched by occurrence', () {
      final a = [row('d0', 'a', 1), row('d0', 'a', 1)];
      final b = [row('d0', 'a', 1)];
      final changes = ViewDiff.compute(a, b);
      expect(changes.whereType<ViewRowRemoved>(), hasLength(1));
      expectEquivalent(applyChanges(a, changes), b);
    });

    test('non-string keys (lists/numbers) are handled', () {
      final a = [
        row('d0', [2009, 1], 'x'),
        row('d1', 42, 'y'),
      ];
      final b = [
        row('d1', 42, 'y'),
        row('d0', [2009, 1], 'z'),
      ];
      final changes = ViewDiff.compute(a, b);
      expectEquivalent(applyChanges(a, changes), b);
    });

    test('property: apply(old, compute(old, new)) == new for random inputs', () {
      final rng = Random(20260606);

      List<ViewEntry> randomRows() {
        final n = rng.nextInt(8); // 0..7
        return [
          for (var i = 0; i < n; i++)
            row(
              'd${rng.nextInt(4)}',
              'k${rng.nextInt(3)}',
              rng.nextInt(3),
              rev: rng.nextBool() ? null : '${rng.nextInt(3)}-x',
            ),
        ];
      }

      for (var iter = 0; iter < 10000; iter++) {
        final old = randomRows();
        final neu = randomRows();
        final changes = ViewDiff.compute(old, neu);
        final result = applyChanges(old, changes);
        expectEquivalent(result, neu);
      }
    });
  });
}
