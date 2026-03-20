import 'package:dart_mappable/dart_mappable.dart';
import 'package:meta/meta.dart';

import 'dart_couch_db.dart';
import 'messages/couch_document_base.dart';

part 'database_migration.mapper.dart';

enum MigrationStatus { tooOld, matched, tooNew }

@MappableClass(discriminatorValue: '!migration_document')
class MigrationDocument extends CouchDocumentBase
    with MigrationDocumentMappable {
  @MappableField()
  final int version;

  MigrationDocument({
    required this.version,
    required super.id,
    super.rev,
    super.attachments,
    super.revisions,
    super.revsInfo,
    super.deleted,
    super.unmappedProps,
  });

  static final fromMap = MigrationDocumentMapper.fromMap;
  static final fromJson = MigrationDocumentMapper.fromJson;
}

abstract class DatabaseMigration {
  final String migrationDocumentId = '!migration_document';

  Future<void> migrate(DartCouchDb db);
  int get targetVersion;

  Future<MigrationStatus> checkMigrationState(DartCouchDb db) async {
    final currentVersion = await getCurrentDbVersion(db);
    if (currentVersion < targetVersion) {
      return MigrationStatus.tooOld;
    } else if (currentVersion == targetVersion) {
      return MigrationStatus.matched;
    } else {
      return MigrationStatus.tooNew;
    }
  }

  Future<int> getCurrentDbVersion(DartCouchDb db) async {
    final migrationDoc = await getMigrationDocument(db);
    return migrationDoc?.version ?? 0;
  }

  Future<void> updateMigrationVersion(DartCouchDb db, int newVersion) async {
    final migrationDoc = await getMigrationDocument(db);
    final updatedDoc = migrationDoc != null
        ? migrationDoc.copyWith(version: newVersion)
        : MigrationDocument(version: newVersion, id: '!migration_document');
    await saveMigrationDocument(db, updatedDoc);
  }

  @visibleForTesting
  Future<MigrationDocument?> getMigrationDocument(DartCouchDb db) async {
    final doc = await db.get('!migration_document') as MigrationDocument?;
    return doc;
  }

  @visibleForTesting
  Future<void> saveMigrationDocument(
    DartCouchDb db,
    MigrationDocument migrationDocument,
  ) async {
    await db.put(migrationDocument);
  }
}
