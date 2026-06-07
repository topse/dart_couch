import 'dart:async';

import 'package:dart_couch/dart_couch.dart';
import 'package:dart_couch_widgets/dart_couch_widgets.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'package:watch_it/watch_it.dart';
import 'package:flutter/services.dart';

import 'current_category_provider.dart';
import 'einkaufslist_item.dart';
import 'new_item_dialog.dart';

final Logger _log = Logger('dart_couch-item_list');

class ItemList extends StatefulWidget {
  const ItemList({super.key});

  @override
  State<ItemList> createState() => _ItemListState();
}

class _ItemListState extends State<ItemList> {
  DartCouchDb? db;

  late final CurrentCategoryProvider _categoryProvider;
  String? _currentCategory;

  StreamSubscription<ViewUpdate>? _viewSub;

  /// All item rows, maintained incrementally from the view.
  final List<ViewEntry> _baseRows = [];

  /// The rows actually shown: filtered by category, unchecked-first then by
  /// name. The source of truth for the alphabet scroll bar's index math.
  List<ViewEntry> _displayRows = [];

  /// Drives the [AnimatedViewList]: a first [ViewSnapshot], then incremental
  /// [ViewChanges] computed from successive display lists via [ViewDiff] — so
  /// only the rows that actually changed animate / rebuild.
  final StreamController<ViewUpdate> _displayUpdates =
      StreamController<ViewUpdate>();
  bool _pushedInitialDisplay = false;

  final ScrollController _scrollController = ScrollController();
  final Map<String, int> _letterIndices = {};
  final List<String> _letters = [];
  int _uncheckedItemsCount = 0;
  final ValueNotifier<String?> _currentLetterGroup = ValueNotifier<String?>(
    null,
  );
  int _totalItemsCount = 0;

  @override
  void initState() {
    super.initState();

    _categoryProvider = di.get<CurrentCategoryProvider>();
    _currentCategory = _categoryProvider.value;
    _categoryProvider.addListener(_onCategoryChanged);

    () async {
      final OfflineFirstServer server = di.get<OfflineFirstServer>();
      final ddb = await server.db(
        DartCouchDb.usernameToDbName(server.username!),
      );
      assert(ddb != null);
      if (!mounted) return;
      setState(() {
        db = ddb;
      });
      _viewSub = ddb!
          .useViewWithChanges('einkaufslistViews/itemsView', includeDocs: true)
          .listen(_onViewUpdate);
    }();
  }

  void _onCategoryChanged() {
    _currentCategory = _categoryProvider.value;
    _recomputeDisplay();
  }

  /// Applies the view's edit script to [_baseRows], then recomputes the display.
  void _onViewUpdate(ViewUpdate update) {
    switch (update) {
      case ViewSnapshot(:final result):
        _baseRows
          ..clear()
          ..addAll(result?.rows ?? const []);
      case ViewChanges(:final changes):
        for (final change in changes) {
          switch (change) {
            case ViewRowInserted(:final index, :final row):
              _baseRows.insert(index, row);
            case ViewRowRemoved(:final index):
              _baseRows.removeAt(index);
            case ViewRowChanged(:final index, :final row):
              _baseRows[index] = row;
          }
        }
    }
    _recomputeDisplay();
  }

  /// Filters by category and re-sorts (unchecked first, then by name), then
  /// emits the *difference* to [_displayUpdates] so the list animates only the
  /// rows that changed.
  void _recomputeDisplay() {
    final filtered = _baseRows.where((e) {
      if (_currentCategory == null) return true;
      return (e.doc as EinkaufslistItem).category == _currentCategory;
    });

    final uncheckedItems =
        filtered
            .where((e) => (e.doc as EinkaufslistItem).erledigt == false)
            .toList()
          ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
    final checkedItems =
        filtered
            .where((e) => (e.doc as EinkaufslistItem).erledigt == true)
            .toList()
          ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));

    final newDisplay = [...uncheckedItems, ...checkedItems];

    // Alphabet scroll bar bookkeeping.
    _uncheckedItemsCount = uncheckedItems.length;
    _totalItemsCount = newDisplay.length;
    _buildLetterIndex(checkedItems);

    if (!_pushedInitialDisplay) {
      _pushedInitialDisplay = true;
      _displayRows = newDisplay;
      _displayUpdates.add(
        ViewSnapshot(
          ViewResult(totalRows: newDisplay.length, offset: 0, rows: newDisplay),
        ),
      );
    } else {
      final changes = ViewDiff.compute(_displayRows, newDisplay);
      _displayRows = newDisplay;
      if (changes.isNotEmpty) _displayUpdates.add(ViewChanges(changes));
    }

    // Rebuild the alphabet scroll bar (its counters/indices may have changed).
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _categoryProvider.removeListener(_onCategoryChanged);
    unawaited(_viewSub?.cancel());
    unawaited(_displayUpdates.close());
    _scrollController.dispose();
    _currentLetterGroup.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (db == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        const _ItemListHeader(),
        // List content
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: AnimatedViewList(
                  updates: _displayUpdates.stream,
                  controller: _scrollController,
                  placeholderBuilder: (_) =>
                      const Center(child: CircularProgressIndicator()),
                  itemBuilder: (context, row, index, animation) =>
                      SizeTransition(
                        sizeFactor: animation,
                        child: ShoppingItemTile(
                          db: db!,
                          item: row.doc as EinkaufslistItem,
                        ),
                      ),
                ),
              ),
              // Alphabet scroll navigation
              LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    onVerticalDragUpdate: (details) {
                      _handleDragUpdate(
                        details.localPosition,
                        constraints.maxHeight,
                      );
                    },
                    onTapDown: (details) {
                      _handleDragUpdate(
                        details.localPosition,
                        constraints.maxHeight,
                      );
                    },
                    child: Container(
                      width: 48,
                      color: Theme.of(context).colorScheme.surface,
                      child: Center(child: _buildAlphabetButtons()),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _buildLetterIndex(List<dynamic> items) {
    _letterIndices.clear();
    _letters.clear();

    for (int i = 0; i < items.length; i++) {
      final item = items[i].doc as EinkaufslistItem;
      final firstLetter = item.name.isNotEmpty
          ? item.name[0].toUpperCase()
          : '#';

      if (!_letterIndices.containsKey(firstLetter)) {
        // Store the index relative to the checked items section
        _letterIndices[firstLetter] = _uncheckedItemsCount + i;
        _letters.add(firstLetter);
      }
    }
  }

  Widget _buildAlphabetButtons() {
    return ValueListenableBuilder<String?>(
      valueListenable: _currentLetterGroup,
      builder: (context, currentGroup, _) {
        final buttons = <Widget>[];

        // Add dot button for scrolling to unchecked items
        final isDotActive = currentGroup == '•';
        buttons.add(
          Container(
            height: 36,
            alignment: Alignment.center,
            decoration: isDotActive
                ? BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                  )
                : null,
            child: const Text(
              '•',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        );

        // Group letters in pairs: ab, cd, ef, etc.
        const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        for (int i = 0; i < alphabet.length; i += 2) {
          final group = alphabet
              .substring(i, (i + 2) > alphabet.length ? alphabet.length : i + 2)
              .toLowerCase();

          final isActive = currentGroup == group;

          buttons.add(
            Container(
              height: 36,
              alignment: Alignment.center,
              decoration: isActive
                  ? BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                    )
                  : null,
              child: Text(
                group,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          );
        }

        return Column(mainAxisSize: MainAxisSize.min, children: buttons);
      },
    );
  }

  void _handleDragUpdate(Offset localPosition, double containerHeight) {
    // Calculate which button was tapped/dragged to
    const buttonHeight = 36.0;
    final totalButtons = 14; // 1 dot + 13 letter groups
    final totalHeight = totalButtons * buttonHeight;

    // Calculate the offset where the buttons start (centered in container)
    final buttonsOffset = (containerHeight - totalHeight) / 2;

    // Adjust local position by the offset
    final adjustedY = localPosition.dy - buttonsOffset;

    // Calculate button index from adjusted position
    final buttonIndex = (adjustedY / buttonHeight).floor();

    if (buttonIndex < 0 || buttonIndex >= totalButtons) return;

    if (buttonIndex == 0) {
      // Dot button - scroll to top
      _currentLetterGroup.value = '•';
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    } else {
      // Letter group button
      const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
      final groupIndex = buttonIndex - 1;
      final letterIndex = groupIndex * 2;

      if (letterIndex < alphabet.length) {
        final group = alphabet
            .substring(
              letterIndex,
              (letterIndex + 2) > alphabet.length
                  ? alphabet.length
                  : letterIndex + 2,
            )
            .toLowerCase();

        // Update marker and scroll without triggering rebuild
        _currentLetterGroup.value = group;
        _scrollToLetterGroup(group);
      }
    }
  }

  void _scrollToLetterGroup(String group) {
    // Find the first item in the checked section that starts with any letter in the group
    for (final letter in group.toUpperCase().split('')) {
      if (_letterIndices.containsKey(letter)) {
        final index = _letterIndices[letter]!;

        // Scroll immediately without waiting
        if (_scrollController.hasClients) {
          // Calculate actual item height from total extent and item count
          // maxScrollExtent = totalContentHeight - viewportHeight
          // So: totalContentHeight = maxScrollExtent + viewportHeight
          final viewportHeight = _scrollController.position.viewportDimension;
          final totalContentHeight =
              _scrollController.position.maxScrollExtent + viewportHeight;
          final actualItemHeight = _totalItemsCount > 0
              ? totalContentHeight / _totalItemsCount
              : 72.0;

          final targetPosition = index * actualItemHeight;
          final clampedPosition = targetPosition.clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          );

          _log.info(
            'Group: $group, Letter: $letter, index: $index, itemHeight: $actualItemHeight, position: $clampedPosition',
          );

          _scrollController.animateTo(
            clampedPosition,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          _log.info('ScrollController has no clients!');
        }
        return;
      }
    }

    _log.info(
      'No items found for group: $group, available letters: ${_letterIndices.keys}',
    );
  }
}

/// Header row above the shopping list (column labels).
class _ItemListHeader extends StatelessWidget {
  const _ItemListHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 56), // Space for checkbox
          Expanded(
            child: Text(
              'Name',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(
              'Anzahl',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              'Einheit',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 48), // Space for alphabet scroll bar
        ],
      ),
    );
  }
}

/// A single shopping-list row: tap to edit, checkbox to toggle done, and an
/// inline quantity ("Anzahl") editor.
class ShoppingItemTile extends StatelessWidget {
  final DartCouchDb db;
  final EinkaufslistItem item;

  const ShoppingItemTile({super.key, required this.db, required this.item});

  Future<void> _edit(BuildContext context) async {
    final updated = await showDialog<EinkaufslistItem?>(
      context: context,
      builder: (context) => NewItemDialogFixed(db: db, item: item),
    );
    if (updated != null) {
      await db.put(updated);
    }
  }

  Future<void> _editAnzahl(BuildContext context) async {
    final result = await showDialog<int>(
      context: context,
      builder: (context) => _AnzahlDialog(initialValue: item.anzahl),
    );
    if (result != null && result != item.anzahl) {
      await db.put(item.copyWith(anzahl: result));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => _edit(context),
      leading: Checkbox(
        value: item.erledigt,
        onChanged: (bool? value) async {
          assert(value != null);
          await db.put(item.copyWith(erledigt: value));
        },
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(item.name, style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 8),
          // Number column (fixed width)
          SizedBox(
            width: 60,
            child: GestureDetector(
              onTap: () => _editAnzahl(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceBright,
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Text(
                  item.anzahl != null ? item.anzahl.toString() : " ",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
          // Einheit column (fixed width)
          SizedBox(
            width: 48,
            child: Text(
              item.einheit ?? "",
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog for editing an item's quantity ("Anzahl"). Owns its text controller
/// and focus node so they are disposed correctly.
class _AnzahlDialog extends StatefulWidget {
  final int? initialValue;

  const _AnzahlDialog({this.initialValue});

  @override
  State<_AnzahlDialog> createState() => _AnzahlDialogState();
}

class _AnzahlDialogState extends State<_AnzahlDialog> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue?.toString() ?? "",
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_focusNode.canRequestFocus) {
        _focusNode.requestFocus();
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(int.tryParse(_controller.text));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Anzahl ändern'),
      content: Focus(
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.of(context).pop();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.enter) {
              _submit();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Neue Anzahl'),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        TextButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }
}
