// All imports must be at the top

import 'package:dart_couch/dart_couch.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

import 'current_category_provider.dart';
import 'einkaufslist_item.dart';

class CategoryDropdown extends StatelessWidget {
  final OfflineFirstServer server;
  const CategoryDropdown({super.key, required this.server});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DartCouchDb?>(
      future: server.db(DartCouchDb.usernameToDbName(server.username!)),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        final db = snapshot.data;
        if (db == null) return const SizedBox.shrink();
        return StreamBuilder<ViewResult?>(
          stream: db.useView(
            'einkaufslistViews/categoryView',
            includeDocs: true,
          ),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox.shrink();
            }
            // Static 'ALLE' item
            final alleCategory = EinkaufslistCategory(
              name: 'ALLE',
              sorthint: -1,
              id: '_alle',
            );
            List<EinkaufslistCategory> categories = [alleCategory];
            categories.addAll(
              snapshot.data!.rows
                  .map((row) => row.doc as EinkaufslistCategory)
                  .toList(),
            );

            final provider = di.get<CurrentCategoryProvider>();
            return ValueListenableBuilder<String?>(
              valueListenable: provider,
              builder: (context, currentId, _) {
                final selected = currentId == null
                    ? alleCategory
                    : categories.firstWhere(
                        (c) => c.id == currentId,
                        orElse: () => alleCategory,
                      );
                return DropdownButton<EinkaufslistCategory>(
                  value: selected,
                  onChanged: (cat) {
                    provider.value = cat!.id == '_alle' ? null : cat.id;
                  },
                  items: categories
                      .map(
                        (cat) => DropdownMenuItem<EinkaufslistCategory>(
                          value: cat,
                          child: Text(cat.name),
                        ),
                      )
                      .toList(),
                );
              },
            );
          },
        );
      },
    );
  }
}
