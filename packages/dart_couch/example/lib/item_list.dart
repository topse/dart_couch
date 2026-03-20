import 'package:dart_couch/dart_couch.dart';
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

    () async {
      final OfflineFirstServer server = di.get<OfflineFirstServer>();
      final ddb = await server.db(
        DartCouchDb.usernameToDbName(server.username!),
      );
      assert(ddb != null);
      setState(() {
        db = ddb;
      });
    }();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _currentLetterGroup.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (db == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final Stream<ViewResult?> itemsStream = db!.useView(
      'einkaufslistViews/itemsView',
      includeDocs: true,
    );

    return StreamBuilder<ViewResult?>(
      stream: itemsStream,
      builder: (context, snapshot) {
        _log.info("ItemList: ${snapshot.connectionState}");
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: \\${snapshot.error}'));
        }
        final items = snapshot.data?.rows ?? [];
        final provider = di.get<CurrentCategoryProvider>();

        return ValueListenableBuilder<String?>(
          valueListenable: provider,
          builder: (context, currentCategoryId, _) {
            final filteredItems = items.where((e) {
              if (currentCategoryId == null) return true;
              final item = e.doc as EinkaufslistItem;
              return item.category == currentCategoryId;
            }).toList();

            // Resort: unchecked first (erledigt == false), then checked, both sorted by key
            final uncheckedItems =
                filteredItems
                    .where(
                      (item) =>
                          (item.doc as EinkaufslistItem).erledigt == false,
                    )
                    .toList()
                  ..sort(
                    (a, b) => a.key.toString().compareTo(b.key.toString()),
                  );

            final checkedItems =
                filteredItems
                    .where(
                      (item) => (item.doc as EinkaufslistItem).erledigt == true,
                    )
                    .toList()
                  ..sort(
                    (a, b) => a.key.toString().compareTo(b.key.toString()),
                  );

            _uncheckedItemsCount = uncheckedItems.length;
            final sortedItems = [...uncheckedItems, ...checkedItems];
            _totalItemsCount = sortedItems.length;

            // Build letter index only for checked items
            _buildLetterIndex(checkedItems);

            return Column(
              children: [
                // Header row
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
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
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 60,
                        child: Text(
                          'Anzahl',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text(
                          'Einheit',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(
                        width: 48,
                      ), // Space for alphabet scroll bar
                    ],
                  ),
                ),
                // List content
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          controller: _scrollController,
                          itemCount: sortedItems.length,
                          itemBuilder: (context, index) {
                            final row = sortedItems[index];
                            final einkaufslistItem =
                                row.doc as EinkaufslistItem;
                            return ListTile(
                              onTap: () async {
                                // fetch categories for dialog
                                final viewResult = await db!.query(
                                  'einkaufslistViews/categoryView',
                                  includeDocs: true,
                                );
                                final categories = <EinkaufslistCategory>[];
                                if (viewResult != null) {
                                  categories.addAll(
                                    viewResult.rows.map(
                                      (r) => r.doc as EinkaufslistCategory,
                                    ),
                                  );
                                }

                                if (context.mounted == false) return;

                                final updated =
                                    await showDialog<EinkaufslistItem?>(
                                      context: context,
                                      builder: (context) => NewItemDialogFixed(
                                        db: db!,
                                        item: einkaufslistItem,
                                      ),
                                    );
                                if (updated != null) {
                                  await db!.put(updated);
                                }
                              },
                              leading: Checkbox(
                                value: einkaufslistItem.erledigt,
                                onChanged: (bool? value) async {
                                  assert(value != null);
                                  final updatedItem = einkaufslistItem.copyWith(
                                    erledigt: value,
                                  );
                                  await db!.put(updatedItem);
                                },
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      row.key.toString(),
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Number column (fixed width)
                                  SizedBox(
                                    width: 60,
                                    child: GestureDetector(
                                      onTap: () async {
                                        final controller =
                                            TextEditingController(
                                              text:
                                                  einkaufslistItem.anzahl ==
                                                      null
                                                  ? ""
                                                  : einkaufslistItem.anzahl
                                                        .toString(),
                                            );
                                        final focusNode = FocusNode();
                                        final result = await showDialog<int>(
                                          context: context,
                                          builder: (context) {
                                            return AlertDialog(
                                              title: const Text(
                                                'Anzahl ändern',
                                              ),
                                              content: Focus(
                                                autofocus: true,
                                                child: Builder(
                                                  builder: (context) {
                                                    WidgetsBinding.instance
                                                        .addPostFrameCallback((
                                                          _,
                                                        ) {
                                                          if (focusNode
                                                              .canRequestFocus) {
                                                            focusNode
                                                                .requestFocus();
                                                            controller
                                                                    .selection =
                                                                TextSelection(
                                                                  baseOffset: 0,
                                                                  extentOffset:
                                                                      controller
                                                                          .text
                                                                          .length,
                                                                );
                                                          }
                                                        });
                                                    return TextField(
                                                      controller: controller,
                                                      focusNode: focusNode,
                                                      keyboardType:
                                                          TextInputType.number,
                                                      decoration:
                                                          const InputDecoration(
                                                            labelText:
                                                                'Neue Anzahl',
                                                          ),
                                                      onSubmitted: (value) {
                                                        final intValue =
                                                            int.tryParse(value);
                                                        final newItem =
                                                            einkaufslistItem.copyWith(
                                                              anzahl:
                                                                  intValue ??
                                                                  einkaufslistItem
                                                                      .anzahl,
                                                            );
                                                        db!.put(newItem);
                                                        Navigator.of(
                                                          context,
                                                        ).pop(intValue);
                                                      },
                                                    );
                                                  },
                                                ),
                                                onKeyEvent:
                                                    (
                                                      FocusNode node,
                                                      KeyEvent event,
                                                    ) {
                                                      if (event
                                                          is KeyDownEvent) {
                                                        if (event.logicalKey ==
                                                            LogicalKeyboardKey
                                                                .escape) {
                                                          Navigator.of(
                                                            context,
                                                          ).pop();
                                                          return KeyEventResult
                                                              .handled;
                                                        } else if (event
                                                                .logicalKey ==
                                                            LogicalKeyboardKey
                                                                .enter) {
                                                          final value =
                                                              int.tryParse(
                                                                controller.text,
                                                              );
                                                          final newItem =
                                                              einkaufslistItem.copyWith(
                                                                anzahl:
                                                                    value ??
                                                                    einkaufslistItem
                                                                        .anzahl,
                                                              );
                                                          db!.put(newItem);
                                                          Navigator.of(
                                                            context,
                                                          ).pop(value);
                                                          return KeyEventResult
                                                              .handled;
                                                        }
                                                      }
                                                      return KeyEventResult
                                                          .ignored;
                                                    },
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.of(
                                                    context,
                                                  ).pop(),
                                                  child: const Text(
                                                    'Abbrechen',
                                                  ),
                                                ),
                                                TextButton(
                                                  onPressed: () {
                                                    final value = int.tryParse(
                                                      controller.text,
                                                    );
                                                    final newItem =
                                                        einkaufslistItem.copyWith(
                                                          anzahl:
                                                              value ??
                                                              einkaufslistItem
                                                                  .anzahl,
                                                        );
                                                    db!.put(newItem);
                                                    Navigator.of(
                                                      context,
                                                    ).pop(value);
                                                  },
                                                  child: const Text('OK'),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                        if (result != null &&
                                            result != einkaufslistItem.anzahl) {
                                          final updatedItem = einkaufslistItem
                                              .copyWith(anzahl: result);
                                          await db!.put(updatedItem);
                                        }
                                      },
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.surfaceBright,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          einkaufslistItem.anzahl != null
                                              ? einkaufslistItem.anzahl
                                                    .toString()
                                              : " ",
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
                                      einkaufslistItem.einheit ?? "",
                                      style: const TextStyle(fontSize: 16),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
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
          },
        );
      },
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
