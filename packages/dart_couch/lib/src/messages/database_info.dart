import 'package:dart_mappable/dart_mappable.dart';

part 'database_info.mapper.dart';

// {
//    "instance_start_time":"1755006501",
//    "db_name":"_users",
//    "purge_seq":"0-g1AAAABPeJzLYWBgYMpgTmHgzcvPy09JdcjLz8gvLskBCeexAEmGBiD1HwiyEhlwqEtkSKqHKMgCAIT2GV4",
//    "update_seq":"0-g1AAAACLeJzLYWBgYMpgTmHgzcvPy09JdcjLz8gvLskBCeexAEmGBiD1HwiyMpgTGXKBAuyG5qbmlomm6HpwmJLIkFSPoj3ZKM0w2SwJXXEWAPMMKoQ",
//    "sizes":
//       {
//          "file":8514,
//          "external":0,
//          "active":0
//       },
//    "props":{},
//    "doc_del_count":0,
//    "doc_count":0,
//    "disk_format_version":8,
//    "compact_running":false,
//    "cluster":
//       {
//           "q":2,
//           "n":1,
//           "w":1,
//           "r":1}
//       }

@MappableClass()
class DatabaseInfo with DatabaseInfoMappable {
  @MappableField(key: 'instance_start_time')
  final String instanceStartTime;

  @MappableField(key: 'db_name')
  final String dbName;

  @MappableField(key: 'db_uuid')
  final String? dbUuid;

  @MappableField(key: 'purge_seq')
  final String purgeSeq;

  @MappableField(key: 'update_seq')
  final String updateSeq;

  final Map<String, int> sizes;
  final Map<String, dynamic> props;

  @MappableField(key: 'doc_del_count')
  final int docDelCount;

  @MappableField(key: 'doc_count')
  final int docCount;

  @MappableField(key: 'disk_format_version')
  final int diskFormatVersion;

  @MappableField(key: 'compact_running')
  final bool compactRunning;

  final Map<String, int> cluster;

  DatabaseInfo({
    required this.instanceStartTime,
    required this.dbName,
    this.dbUuid,
    required this.purgeSeq,
    required this.updateSeq,
    required this.sizes,
    required this.props,
    required this.docDelCount,
    required this.docCount,
    required this.diskFormatVersion,
    required this.compactRunning,
    required this.cluster,
  });

  int get updateSeqNumber {
    final parts = updateSeq.split('-');
    if (parts.length < 2) {
      throw FormatException('Invalid update sequence format: $updateSeq');
    }
    return int.parse(parts[0]);
  }

  static final fromMap = DatabaseInfoMapper.fromMap;
  static final fromJson = DatabaseInfoMapper.fromJson;
}
