import 'package:dart_mappable/dart_mappable.dart';

part 'db_updates_result.mapper.dart';

/// {"results":
///   [
///     {"db_name":"testdb1","type":"created","seq":"1-g1AAAABteJzLYWBgYMpgTmHgzcvPy09JdcjLz8gvLskBCScyJNX___8_K4M5kTEXKMBubG5gZJmciK4Yh_Y8FiDJ0ACk_oNMSWTIAgDhLSHW"},
///     {"db_name":"testdb1","type":"deleted","seq":"2-g1AAAABteJzLYWBgYMpgTmHgzcvPy09JdcjLz8gvLskBCScyJNX___8_K4M5kSkXKMBubG5gZJmciK4Yh_Y8FiDJ0ACk_oNMSWTIAgDhcyHX"},
///     {"db_name":"testdb2","type":"created","seq":"3-g1AAAACLeJzLYWBgYMpgTmHgzcvPy09JdcjLz8gvLskBCScyJNX___8_K4M5kSkXKMBubG5gZJmciK4Yh_Y8FiDJ0ACk_kNNYQSbYmhpaGGZloquJwsAPmYqXQ"},
///     {"db_name":"_dbs","type":"updated","seq":"4-g1AAAACLeJzLYWBgYMpgTmHgzcvPy09JdcjLz8gvLskBCScyJNX___8_K4M5kTkXKMBubG5gZJmciK4Yh_Y8FiDJ0ACk_kNNYQSbYmhpaGGZloquJwsAPsoqXg"},
///     {"db_name":"_users","type":"updated","seq":"5-g1AAAACLeJzLYWBgYMpgTmHgzcvPy09JdcjLz8gvLskBCScyJNX___8_K4M5kSUXKMBubG5gZJmciK4Yh_Y8FiDJ0ACk_kNNYQSbYmhpaGGZloquJwsAPy4qXw"}
///   ],
///   "last_seq":"5-g1AAAACLeJzLYWBgYMpgTmHgzcvPy09JdcjLz8gvLskBCScyJNX___8_K4M5kSUXKMBubG5gZJmciK4Yh_Y8FiDJ0ACk_kNNYQSbYmhpaGGZloquJwsAPy4qXw"
/// }

@MappableClass()
class DbUpdatesResult with DbUpdatesResultMappable {
  @MappableField()
  final List<DbUpdateEntry> results;

  @MappableField(key: 'last_seq')
  final String lastSeq;

  DbUpdatesResult({required this.results, required this.lastSeq});

  static final fromMap = DbUpdatesResultMapper.fromMap;
  static final fromJson = DbUpdatesResultMapper.fromJson;
}

@MappableEnum()
enum DbUpdateType { created, updated, deleted }

@MappableClass()
class DbUpdateEntry with DbUpdateEntryMappable {
  @MappableField(key: 'db_name')
  final String dbName;
  final DbUpdateType type;
  final String seq;
  DbUpdateEntry({required this.dbName, required this.type, required this.seq});
}
