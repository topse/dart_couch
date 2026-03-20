// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element

import 'src/database_migration.dart' as p0;
import 'src/messages/bulk_docs_result.dart' as p1;
import 'src/messages/bulk_get.dart' as p2;
import 'src/messages/changes_result.dart' as p3;
import 'src/messages/couch_document_base.dart' as p4;
import 'src/messages/database_info.dart' as p5;
import 'src/messages/db_updates_result.dart' as p6;
import 'src/messages/deleted_document.dart' as p7;
import 'src/messages/design_document.dart' as p8;
import 'src/messages/index_result.dart' as p9;
import 'src/messages/login_result.dart' as p10;
import 'src/messages/revs_diff_result.dart' as p11;
import 'src/messages/session_result.dart' as p12;
import 'src/messages/user_result.dart' as p13;
import 'src/messages/view_result.dart' as p14;
import 'src/offline_first_db.dart' as p15;
import 'src/offline_first_server.dart' as p16;
import 'src/offline_first_server_db_creation_log.dart' as p17;

void initializeMappers() {
  p0.MigrationDocumentMapper.ensureInitialized();
  p1.BulkDocsResultMapper.ensureInitialized();
  p2.BulkGetRequestMapper.ensureInitialized();
  p2.BulkGetRequestDocMapper.ensureInitialized();
  p3.ChangesResultNormalMapper.ensureInitialized();
  p3.ChangeEntryMapper.ensureInitialized();
  p3.RevisionListEntryMapper.ensureInitialized();
  p4.CouchDocumentBaseMapper.ensureInitialized();
  p4.AttachmentInfoMapper.ensureInitialized();
  p4.RevisionsMapper.ensureInitialized();
  p4.RevsInfoMapper.ensureInitialized();
  p4.RevsInfoStatusMapper.ensureInitialized();
  p5.DatabaseInfoMapper.ensureInitialized();
  p6.DbUpdatesResultMapper.ensureInitialized();
  p6.DbUpdateEntryMapper.ensureInitialized();
  p6.DbUpdateTypeMapper.ensureInitialized();
  p7.DeletedDocumentMapper.ensureInitialized();
  p8.DesignDocumentMapper.ensureInitialized();
  p8.ViewDataMapper.ensureInitialized();
  p9.IndexResultListMapper.ensureInitialized();
  p9.IndexResultMapper.ensureInitialized();
  p9.IndexRequestMapper.ensureInitialized();
  p9.IndexDefinitionMapper.ensureInitialized();
  p9.IndexDocumentMapper.ensureInitialized();
  p9.IndexViewMapper.ensureInitialized();
  p9.IndexMapMapper.ensureInitialized();
  p9.IndexOptionsMapper.ensureInitialized();
  p9.SortOrderMapper.ensureInitialized();
  p10.LoginResultBodyMapper.ensureInitialized();
  p11.RevsDiffEntryMapper.ensureInitialized();
  p12.SessionResultMapper.ensureInitialized();
  p12.UserCtxMapper.ensureInitialized();
  p12.InfoOfSessionMapper.ensureInitialized();
  p13.UserResultMapper.ensureInitialized();
  p14.ViewResultMapper.ensureInitialized();
  p14.ViewEntryMapper.ensureInitialized();
  p15.LocalMigrationDocumentMapper.ensureInitialized();
  p16.OfflineFirstServerDbUpdatesStateMapper.ensureInitialized();
  p16.OfflineFirstServerLoginStateMapper.ensureInitialized();
  p16.DatabaseSyncMarkerMapper.ensureInitialized();
  p16.InstanceStateMapper.ensureInitialized();
  p17.OfflineFirstServerDbCreationLogMapper.ensureInitialized();
  p17.OfflineFirstServerDbCreationLogEntryMapper.ensureInitialized();
  p17.EntryModeMapper.ensureInitialized();
}

