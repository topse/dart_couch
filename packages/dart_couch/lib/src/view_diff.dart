import 'dart:convert';

import 'messages/view_result.dart';

/// A single change between two consecutive ordered view snapshots.
///
/// Changes form an ordered **edit script**: applying them in order to a mutable
/// copy of the previous `rows` reproduces the new `rows` exactly. Each change's
/// [index] is the position in that working list at the moment the change is
/// applied (insert at [index], remove from [index], replace at [index]).
///
/// The vocabulary is intentionally minimal and rendering-agnostic —
/// [ViewRowInserted], [ViewRowRemoved], [ViewRowChanged]. There is deliberately
/// no dedicated "move" event: a row that moves (because its emit key changed, or
/// because surrounding rows were inserted/removed) is expressed as a
/// [ViewRowRemoved] followed by a [ViewRowInserted]. This keeps the contract
/// stable and maps directly onto consumers such as Flutter's `AnimatedList`,
/// which only offer insert/remove primitives. {Inserted, Removed, Changed} is a
/// complete vocabulary for any list transformation, so this set is final.
sealed class ViewRowChange {
  /// Position in the working list at the moment this change is applied.
  final int index;

  const ViewRowChange(this.index);
}

/// A new row was inserted at [index]. [row] is the inserted row.
final class ViewRowInserted extends ViewRowChange {
  final ViewEntry row;

  const ViewRowInserted(super.index, this.row);

  @override
  String toString() => 'ViewRowInserted(index: $index, id: ${row.id})';
}

/// The row previously at [index] was removed. [row] is the removed row (kept so
/// consumers can render/animate the outgoing item).
final class ViewRowRemoved extends ViewRowChange {
  final ViewEntry row;

  const ViewRowRemoved(super.index, this.row);

  @override
  String toString() => 'ViewRowRemoved(index: $index, id: ${row.id})';
}

/// The row at [index] kept its identity but its content changed. [row] is the
/// new row. Content is the emit value together with the document revision, so a
/// body edit is reported even when the emit value is unchanged.
final class ViewRowChanged extends ViewRowChange {
  final ViewEntry row;

  const ViewRowChanged(super.index, this.row);

  @override
  String toString() => 'ViewRowChanged(index: $index, id: ${row.id})';
}

/// Computes the [ViewRowChange] edit script between two ordered view snapshots.
///
/// Pure, rendering-agnostic, and dependency-free so it can live in the core
/// package and be unit-tested without Flutter or a database.
abstract final class ViewDiff {
  /// Returns the ordered edit script transforming [oldRows] into [newRows].
  ///
  /// Rows are matched by **identity** = (document id, emit key, occurrence),
  /// where `occurrence` disambiguates rows that share the same (id, key) — a
  /// map function may emit the same key for the same document more than once.
  /// Matching by identity means a content edit to a row is reported as
  /// [ViewRowChanged] (so the consumer can update the row in place) rather than
  /// a remove + insert.
  ///
  /// Two rows with the same identity are **content-equal** when their emit
  /// value and their document revision are both unchanged.
  ///
  /// The script is built from the **longest common subsequence** of the two
  /// identity sequences: rows on the LCS stay in place, and only rows off it are
  /// removed/inserted. So when a single row moves (e.g. an item is checked off
  /// and sorts to a new position) the result is exactly one remove + one insert
  /// of *that* row — the rows it moved past stay put and simply slide. Runs in
  /// O(n·m) time/space in the row counts.
  ///
  /// Invariant: applying the returned changes in order to a mutable copy of
  /// [oldRows] yields a list equal — by identity and content — to [newRows].
  static List<ViewRowChange> compute(
    List<ViewEntry> oldRows,
    List<ViewEntry> newRows,
  ) {
    final List<String> oldIds = _identities(oldRows);
    final List<String> newIds = _identities(newRows);
    final int n = oldIds.length;
    final int m = newIds.length;

    // dp[i][j] = LCS length of oldIds[i..] and newIds[j..].
    final dp = List.generate(
      n + 1,
      (_) => List<int>.filled(m + 1, 0),
      growable: false,
    );
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        dp[i][j] = oldIds[i] == newIds[j]
            ? dp[i + 1][j + 1] + 1
            : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
      }
    }

    // Backtrack to mark which rows lie on the LCS, and pair each kept new row
    // with its old row (so we can detect content changes).
    final oldInLcs = List<bool>.filled(n, false);
    final newInLcs = List<bool>.filled(m, false);
    final lcsOldForNew = List<int>.filled(m, -1);
    for (var i = 0, j = 0; i < n && j < m;) {
      if (oldIds[i] == newIds[j]) {
        oldInLcs[i] = true;
        newInLcs[j] = true;
        lcsOldForNew[j] = i;
        i++;
        j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        i++;
      } else {
        j++;
      }
    }

    final changes = <ViewRowChange>[];

    // Removals first, highest index first so earlier indices stay valid as the
    // edits are applied in order.
    for (var i = n - 1; i >= 0; i--) {
      if (!oldInLcs[i]) changes.add(ViewRowRemoved(i, oldRows[i]));
    }

    // Then insertions and in-place changes, walking the new order.
    for (var j = 0; j < m; j++) {
      if (!newInLcs[j]) {
        changes.add(ViewRowInserted(j, newRows[j]));
      } else if (_content(oldRows[lcsOldForNew[j]]) != _content(newRows[j])) {
        changes.add(ViewRowChanged(j, newRows[j]));
      }
    }

    return changes;
  }

  /// Per-row identity strings (`[id, key]` plus a 0-based occurrence counter to
  /// disambiguate duplicate (id, key) pairs), in row order.
  static List<String> _identities(List<ViewEntry> rows) {
    final counts = <String, int>{};
    final ids = <String>[];
    for (final r in rows) {
      final base = jsonEncode([r.id, r.key]);
      final occ = counts.update(base, (v) => v + 1, ifAbsent: () => 0);
      ids.add('$base#$occ');
    }
    return ids;
  }

  /// Content fingerprint used to detect [ViewRowChanged]: the emit value and the
  /// document revision (so a body edit is detected even if the value is equal).
  static String _content(ViewEntry r) => jsonEncode([r.value, r.doc?.rev]);
}

/// What `useViewWithChanges` emits: either a full [ViewSnapshot] or an
/// incremental [ViewChanges] batch.
///
/// A consumer maintains a list of rows: on [ViewSnapshot] it replaces the whole
/// list; on [ViewChanges] it applies the edit script. The first event is always
/// a [ViewSnapshot], so a consumer can render the initial state exactly like
/// `useView` and only animate subsequent deltas.
sealed class ViewUpdate {
  const ViewUpdate();
}

/// A complete view snapshot, in the same shape `useView` emits.
///
/// Emitted as the first event, and whenever the previous or current state is
/// absent (the view appeared or disappeared) — so the consumer rebuilds from
/// scratch instead of diffing across a null boundary. [result] is null when the
/// view does not exist.
final class ViewSnapshot extends ViewUpdate {
  final ViewResult? result;

  const ViewSnapshot(this.result);
}

/// An incremental, ordered edit script to apply to the rows the consumer is
/// already holding. Never empty (an empty diff is simply not emitted).
final class ViewChanges extends ViewUpdate {
  final List<ViewRowChange> changes;

  const ViewChanges(this.changes);
}
