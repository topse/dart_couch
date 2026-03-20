import 'package:dart_couch/dart_couch.dart';

class EinkaufslisteMigration extends DatabaseMigration {
  @override
  int get targetVersion => 3;

  @override
  Future<void> migrate(DartCouchDb db) async {
    final fromVersion = await getCurrentDbVersion(db);

    if (fromVersion < 3) {
      await db.createIndex(
        index: IndexDefinition(
          fields: [
            {'!doc_type': SortOrder.asc},
            {'sorthint': SortOrder.asc},
          ],
        ),
      );
      await db.createIndex(
        index: IndexDefinition(
          fields: [
            {'!doc_type': SortOrder.asc},
            {'name': SortOrder.asc},
          ],
        ),
      );

      DesignDocument ddoc = DesignDocument(
        id: '_design/einkaufslistViews',
        views: {
          'itemsView': ViewData(
            map:
                "function (doc) { if (doc['!doc_type'] !== undefined && doc['!doc_type'] === 'item') emit(doc.name); }",
          ),
          'categoryView': ViewData(
            map:
                "function (doc) { if (doc['!doc_type'] !== undefined && doc['!doc_type'] === 'category') emit(doc.name); }",
          ),
        },
      );
      await db.put(ddoc);

      await updateMigrationVersion(db, 3);
    }
  }
}
