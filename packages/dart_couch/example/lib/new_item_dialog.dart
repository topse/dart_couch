import 'package:flutter/material.dart';
import 'package:dart_couch/dart_couch.dart';

import 'einkaufslist_item.dart';

class NewItemDialogFixed extends StatefulWidget {
  final DartCouchDb db;
  final EinkaufslistItem? item;

  const NewItemDialogFixed({super.key, required this.db, this.item});

  @override
  State<NewItemDialogFixed> createState() => _NewItemDialogFixedState();
}

class _NewItemDialogFixedState extends State<NewItemDialogFixed> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _anzahlController = TextEditingController(
    text: '',
  );
  List<EinkaufslistCategory> _categories = [];
  late String _selectedCategory;
  String _selectedEinheit = '';
  String? _errorText;
  bool _erledigt = false;

  @override
  void initState() {
    super.initState();
    if (widget.item != null) {
      final it = widget.item!;
      _nameController.text = it.name;
      _anzahlController.text = it.anzahl.toString();
      _selectedCategory = it.category;
      _selectedEinheit = it.einheit ?? '';
      _erledigt = it.erledigt;
    } else {
      _selectedCategory = '';
    }
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final viewResult = await widget.db.query(
        'einkaufslistViews/categoryView',
        includeDocs: true,
      );
      if (viewResult != null) {
        final cats = viewResult.rows
            .map((r) => r.doc as EinkaufslistCategory)
            .toList();
        setState(() {
          _categories = cats;
        });
      }
    } catch (_) {
      // ignore errors for now
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.item != null;
    return AlertDialog(
      title: Text(editing ? 'Element Bearbeiten' : 'Neues Element erstellen'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Bezeichnung'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory.isNotEmpty
                  ? _selectedCategory
                  : null,
              decoration: const InputDecoration(labelText: 'Kategorie'),
              items: _categories
                  .map(
                    (c) => DropdownMenuItem<String>(
                      value: c.id,
                      child: Text(c.name),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _selectedCategory = v ?? ''),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _anzahlController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Anzahl/Menge (optional)',
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedEinheit.isNotEmpty
                  ? _selectedEinheit
                  : null,
              decoration: const InputDecoration(
                labelText: 'Einheit (optional)',
              ),
              items: <String>['', 'g', 'kg', 'Liter', 'Stück']
                  .map(
                    (u) => DropdownMenuItem<String>(
                      value: u,
                      child: Text(u.isEmpty ? '' : u),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _selectedEinheit = v ?? ''),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Erledigt'),
              value: _erledigt,
              onChanged: (v) => setState(() => _erledigt = v ?? false),
            ),
            const SizedBox(height: 8),
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(_errorText!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.delete),
          color: Colors.red,
          onPressed: editing
              ? () {
                  widget.db.remove(widget.item!.id!, widget.item!.rev!);
                  Navigator.of(context).pop();
                }
              : null,
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
        IconButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) {
              setState(() => _errorText = 'Bezeichnung darf nicht leer sein.');
              return;
            }
            if (_selectedCategory.isEmpty) {
              setState(() => _errorText = 'Kategorie darf nicht leer sein.');
              return;
            }

            final anzahlText = _anzahlController.text.trim();
            final int? anzahl = anzahlText.isEmpty
                ? null
                : int.tryParse(anzahlText);
            if (editing) {
              final orig = widget.item!;
              final updated = orig.copyWith(
                name: name,
                erledigt: _erledigt,
                anzahl: anzahl ?? orig.anzahl,
                einheit: _selectedEinheit == "" ? null : _selectedEinheit,
                category: _selectedCategory,
              );
              Navigator.of(context).pop(updated);
            } else {
              final newItem = EinkaufslistItem(
                name: name,
                erledigt: _erledigt,
                anzahl: anzahl ?? 0,
                einheit: _selectedEinheit == "" ? null : _selectedEinheit,
                category: _selectedCategory,
              );
              Navigator.of(context).pop(newItem);
            }
          },
          icon: Icon(Icons.save),
          color: Colors.blue,
        ),
      ],
    );
  }
}
