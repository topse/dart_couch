import 'package:dart_mappable/dart_mappable.dart';

import 'package:dart_couch/dart_couch.dart';

part 'offline_first_server_db_creation_log.mapper.dart';

@MappableClass(discriminatorValue: 'offline_first_server_db_creation_log')
class OfflineFirstServerDbCreationLog extends CouchDocumentBase
    with OfflineFirstServerDbCreationLogMappable {
  @MappableField()
  List<OfflineFirstServerDbCreationLogEntry> entries;

  OfflineFirstServerDbCreationLog({
    required this.entries,
    required super.id,
    super.rev,
    super.attachments,
    super.revisions,
    super.revsInfo,
    super.deleted,
    super.unmappedProps,
  });

  static final fromMap = OfflineFirstServerDbCreationLogMapper.fromMap;
  static final fromJson = OfflineFirstServerDbCreationLogMapper.fromJson;
}

@MappableEnum()
enum EntryMode { created, deleted, recreated }

@MappableClass()
class OfflineFirstServerDbCreationLogEntry
    with OfflineFirstServerDbCreationLogEntryMappable {
  @MappableField()
  String name;

  @MappableField()
  EntryMode mode;

  OfflineFirstServerDbCreationLogEntry({
    required this.name,
    required this.mode,
  });

  static final fromMap = OfflineFirstServerDbCreationLogEntryMapper.fromMap;
  static final fromJson = OfflineFirstServerDbCreationLogEntryMapper.fromJson;
}
