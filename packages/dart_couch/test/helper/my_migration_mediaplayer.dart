import 'package:dart_couch/dart_couch.dart';

class MyMigration extends DatabaseMigration {
  @override
  int get targetVersion => 1;

  @override
  Future<void> migrate(DartCouchDb db) async {
    final curVersion = await getCurrentDbVersion(db);
    if (curVersion < 1) {
      DesignDocument d = DesignDocument(
        id: '_design/mediatree',
        views: {
          'by_parent': ViewData(
            map: '''
          function (doc) {
            if (doc['!doc_type'].startsWith('media_')) emit([doc['parent'], doc['sortHint']]);
          }
          ''',
          ),
        },
      );

      await db.put(d);

      await updateMigrationVersion(db, 1);
    }
  }
}
