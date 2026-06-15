import 'dart:async';
import 'dart:convert';

import 'package:dart_couch/dart_couch.dart';
import 'package:flutter/widgets.dart';

/// Builds a live row of an [AnimatedViewList] / [SliverAnimatedViewList].
/// [animation] drives the insert/remove transition; [index] is the row's
/// current position.
typedef AnimatedViewItemBuilder =
    Widget Function(
      BuildContext context,
      ViewEntry row,
      int index,
      Animation<double> animation,
    );

/// Builds a row that is animating out. [row] is the removed row (it is no
/// longer in the list, so there is no live index).
typedef RemovedViewItemBuilder =
    Widget Function(
      BuildContext context,
      ViewEntry row,
      Animation<double> animation,
    );

/// Widget-agnostic glue between a `useViewWithChanges` stream and an animated
/// list. It keeps the row list in lockstep with the list widget's internal item
/// count and turns each [ViewUpdate] into insert/remove/rebuild callbacks.
///
/// A [ViewSnapshot] either initialises the list (first event → [onInitialBuild],
/// which builds with `initialItemCount`) or, for a later reset, is applied as an
/// animated diff against the current rows — so the underlying list's
/// `GlobalKey`/state never has to be swapped (avoids desync). A [ViewChanges]
/// batch is applied directly.
class _ViewListSync {
  _ViewListSync({
    required this.onInitialBuild,
    required this.onInsert,
    required this.onRemove,
    required this.onChange,
  });

  final List<ViewEntry> rows = <ViewEntry>[];
  bool _hasSnapshot = false;

  /// First snapshot arrived: (re)build so the list is created with the right
  /// `initialItemCount`.
  final VoidCallback onInitialBuild;

  /// Animate a row in at [index] (already inserted into [rows]).
  final void Function(int index) onInsert;

  /// Animate a row out from [index] (already removed from [rows]); [removed] is
  /// the row to render while it fades. [isMove] is true when this removal is one
  /// half of a move (the same row is re-inserted elsewhere in the same batch) —
  /// the caller should then skip the exit animation so the stale row does not
  /// linger at its old slot (see [_apply]).
  final void Function(int index, ViewEntry removed, bool isMove) onRemove;

  /// A row changed in place: rebuild to pick up the new content.
  final VoidCallback onChange;

  bool get hasSnapshot => _hasSnapshot;

  void handle(ViewUpdate update) {
    switch (update) {
      case ViewSnapshot(:final result):
        final newRows = result?.rows ?? const <ViewEntry>[];
        if (!_hasSnapshot) {
          rows
            ..clear()
            ..addAll(newRows);
          _hasSnapshot = true;
          onInitialBuild();
        } else {
          // A later snapshot is a reset: animate the difference instead of
          // swapping the list out, so the animated-list state stays valid.
          _apply(ViewDiff.compute(rows, List<ViewEntry>.of(newRows)));
        }
      case ViewChanges(:final changes):
        _apply(changes);
    }
  }

  void _apply(List<ViewRowChange> changes) {
    // A row that is both removed and inserted in the same batch is a *move*
    // (it was re-sorted to a new position — e.g. a list item that was checked
    // off and now sorts below the unchecked ones). AnimatedList has no move
    // primitive, so ViewDiff expresses it as remove + insert. Animating the
    // removal would leave the row's *old* content (the pre-edit value) visibly
    // fading out at its previous slot for the whole remove duration, which
    // reads as a flicker — most noticeably when the old slot is the one the
    // user is looking at. So for moves we remove instantly and animate only the
    // insertion at the new slot.
    final movedIds = _movedIdentities(changes);
    for (final change in changes) {
      switch (change) {
        case ViewRowInserted(:final index, :final row):
          rows.insert(index, row);
          onInsert(index);
        case ViewRowRemoved(:final index, :final row):
          rows.removeAt(index);
          onRemove(index, row, movedIds.contains(_identity(row)));
        case ViewRowChanged(:final index, :final row):
          rows[index] = row;
          onChange();
      }
    }
  }

  /// Identities (id + emit key) that appear as both a removal and an insertion
  /// in [changes] — i.e. rows that moved rather than genuinely came/went.
  static Set<String> _movedIdentities(List<ViewRowChange> changes) {
    final removed = <String>{};
    final inserted = <String>{};
    for (final c in changes) {
      switch (c) {
        case ViewRowRemoved(:final row):
          removed.add(_identity(row));
        case ViewRowInserted(:final row):
          inserted.add(_identity(row));
        case ViewRowChanged():
          break;
      }
    }
    return removed.intersection(inserted);
  }

  static String _identity(ViewEntry row) => jsonEncode([row.id, row.key]);

  /// Drop all state so a new stream starts from a fresh snapshot.
  void reset() {
    rows.clear();
    _hasSnapshot = false;
  }
}

/// A Flutter [AnimatedList] driven by a `useViewWithChanges` stream.
///
/// Pass a [Stream] of [ViewUpdate] (typically
/// `db.useViewWithChanges('design/view', includeDocs: true)`) and this widget
/// animates rows in and out as the view changes, rebuilding only the rows that
/// actually changed. A [ViewSnapshot] (re)initialises the list; a [ViewChanges]
/// batch is applied as inserts/removes (animated) and in-place updates.
///
/// Create the stream **once** (e.g. in your `State.initState`) and pass the same
/// instance — don't build it inline in `build`, or each rebuild would
/// resubscribe and reset the list (mirrors the `StreamBuilder` rule).
///
/// For composition inside a `CustomScrollView`, use [SliverAnimatedViewList].
class AnimatedViewList extends StatefulWidget {
  /// The view-update stream, e.g. `db.useViewWithChanges(...)`.
  final Stream<ViewUpdate> updates;

  /// Builds a present row.
  final AnimatedViewItemBuilder itemBuilder;

  /// Builds a row that is animating out. Defaults to [itemBuilder] (with the
  /// removed row and index `-1`).
  final RemovedViewItemBuilder? removedItemBuilder;

  /// Shown before the first [ViewSnapshot] arrives. Defaults to an empty box.
  final WidgetBuilder? placeholderBuilder;

  final Duration insertDuration;
  final Duration removeDuration;

  // Passthroughs to the underlying [AnimatedList].
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;
  final Axis scrollDirection;
  final bool reverse;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  const AnimatedViewList({
    super.key,
    required this.updates,
    required this.itemBuilder,
    this.removedItemBuilder,
    this.placeholderBuilder,
    this.insertDuration = const Duration(milliseconds: 300),
    this.removeDuration = const Duration(milliseconds: 300),
    this.padding,
    this.controller,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.shrinkWrap = false,
    this.physics,
  });

  @override
  State<AnimatedViewList> createState() => _AnimatedViewListState();
}

class _AnimatedViewListState extends State<AnimatedViewList> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late final _ViewListSync _sync = _ViewListSync(
    onInitialBuild: () {
      if (mounted) setState(() {});
    },
    onInsert: (index) => _listKey.currentState?.insertItem(
      index,
      duration: widget.insertDuration,
    ),
    onRemove: (index, removed, isMove) => _listKey.currentState?.removeItem(
      index,
      (context, animation) => _buildRemoved(context, removed, animation),
      duration: isMove ? Duration.zero : widget.removeDuration,
    ),
    onChange: () {
      if (mounted) setState(() {});
    },
  );
  StreamSubscription<ViewUpdate>? _sub;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant AnimatedViewList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.updates != widget.updates) {
      unawaited(_sub?.cancel());
      _sync.reset(); // the new stream emits a fresh snapshot first
      _subscribe();
    }
  }

  void _subscribe() {
    _sub = widget.updates.listen((update) {
      if (mounted) _sync.handle(update);
    });
  }

  Widget _buildRemoved(
    BuildContext context,
    ViewEntry row,
    Animation<double> animation,
  ) {
    final builder = widget.removedItemBuilder;
    if (builder != null) return builder(context, row, animation);
    return widget.itemBuilder(context, row, -1, animation);
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_sync.hasSnapshot) {
      return widget.placeholderBuilder?.call(context) ??
          const SizedBox.shrink();
    }
    return AnimatedList(
      key: _listKey,
      initialItemCount: _sync.rows.length,
      padding: widget.padding,
      controller: widget.controller,
      scrollDirection: widget.scrollDirection,
      reverse: widget.reverse,
      shrinkWrap: widget.shrinkWrap,
      physics: widget.physics,
      itemBuilder: (context, index, animation) =>
          widget.itemBuilder(context, _sync.rows[index], index, animation),
    );
  }
}

/// The sliver form of [AnimatedViewList], for composition inside a
/// `CustomScrollView` (alongside other slivers such as a `SliverAppBar`).
///
/// Behaves exactly like [AnimatedViewList] but renders a `SliverAnimatedList`.
class SliverAnimatedViewList extends StatefulWidget {
  /// The view-update stream, e.g. `db.useViewWithChanges(...)`.
  final Stream<ViewUpdate> updates;

  /// Builds a present row.
  final AnimatedViewItemBuilder itemBuilder;

  /// Builds a row that is animating out. Defaults to [itemBuilder] (with the
  /// removed row and index `-1`).
  final RemovedViewItemBuilder? removedItemBuilder;

  /// Shown (as a sliver) before the first [ViewSnapshot] arrives. Defaults to an
  /// empty box.
  final WidgetBuilder? placeholderBuilder;

  final Duration insertDuration;
  final Duration removeDuration;

  const SliverAnimatedViewList({
    super.key,
    required this.updates,
    required this.itemBuilder,
    this.removedItemBuilder,
    this.placeholderBuilder,
    this.insertDuration = const Duration(milliseconds: 300),
    this.removeDuration = const Duration(milliseconds: 300),
  });

  @override
  State<SliverAnimatedViewList> createState() => _SliverAnimatedViewListState();
}

class _SliverAnimatedViewListState extends State<SliverAnimatedViewList> {
  final GlobalKey<SliverAnimatedListState> _listKey =
      GlobalKey<SliverAnimatedListState>();
  late final _ViewListSync _sync = _ViewListSync(
    onInitialBuild: () {
      if (mounted) setState(() {});
    },
    onInsert: (index) => _listKey.currentState?.insertItem(
      index,
      duration: widget.insertDuration,
    ),
    onRemove: (index, removed, isMove) => _listKey.currentState?.removeItem(
      index,
      (context, animation) => _buildRemoved(context, removed, animation),
      duration: isMove ? Duration.zero : widget.removeDuration,
    ),
    onChange: () {
      if (mounted) setState(() {});
    },
  );
  StreamSubscription<ViewUpdate>? _sub;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant SliverAnimatedViewList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.updates != widget.updates) {
      unawaited(_sub?.cancel());
      _sync.reset();
      _subscribe();
    }
  }

  void _subscribe() {
    _sub = widget.updates.listen((update) {
      if (mounted) _sync.handle(update);
    });
  }

  Widget _buildRemoved(
    BuildContext context,
    ViewEntry row,
    Animation<double> animation,
  ) {
    final builder = widget.removedItemBuilder;
    if (builder != null) return builder(context, row, animation);
    return widget.itemBuilder(context, row, -1, animation);
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_sync.hasSnapshot) {
      return SliverToBoxAdapter(
        child:
            widget.placeholderBuilder?.call(context) ??
            const SizedBox.shrink(),
      );
    }
    return SliverAnimatedList(
      key: _listKey,
      initialItemCount: _sync.rows.length,
      itemBuilder: (context, index, animation) =>
          widget.itemBuilder(context, _sync.rows[index], index, animation),
    );
  }
}
