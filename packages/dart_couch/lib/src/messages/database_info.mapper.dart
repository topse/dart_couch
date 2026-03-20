// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'database_info.dart';

class DatabaseInfoMapper extends ClassMapperBase<DatabaseInfo> {
  DatabaseInfoMapper._();

  static DatabaseInfoMapper? _instance;
  static DatabaseInfoMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = DatabaseInfoMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'DatabaseInfo';

  static String _$instanceStartTime(DatabaseInfo v) => v.instanceStartTime;
  static const Field<DatabaseInfo, String> _f$instanceStartTime = Field(
    'instanceStartTime',
    _$instanceStartTime,
    key: r'instance_start_time',
  );
  static String _$dbName(DatabaseInfo v) => v.dbName;
  static const Field<DatabaseInfo, String> _f$dbName = Field(
    'dbName',
    _$dbName,
    key: r'db_name',
  );
  static String? _$dbUuid(DatabaseInfo v) => v.dbUuid;
  static const Field<DatabaseInfo, String> _f$dbUuid = Field(
    'dbUuid',
    _$dbUuid,
    key: r'db_uuid',
    opt: true,
  );
  static String _$purgeSeq(DatabaseInfo v) => v.purgeSeq;
  static const Field<DatabaseInfo, String> _f$purgeSeq = Field(
    'purgeSeq',
    _$purgeSeq,
    key: r'purge_seq',
  );
  static String _$updateSeq(DatabaseInfo v) => v.updateSeq;
  static const Field<DatabaseInfo, String> _f$updateSeq = Field(
    'updateSeq',
    _$updateSeq,
    key: r'update_seq',
  );
  static Map<String, int> _$sizes(DatabaseInfo v) => v.sizes;
  static const Field<DatabaseInfo, Map<String, int>> _f$sizes = Field(
    'sizes',
    _$sizes,
  );
  static Map<String, dynamic> _$props(DatabaseInfo v) => v.props;
  static const Field<DatabaseInfo, Map<String, dynamic>> _f$props = Field(
    'props',
    _$props,
  );
  static int _$docDelCount(DatabaseInfo v) => v.docDelCount;
  static const Field<DatabaseInfo, int> _f$docDelCount = Field(
    'docDelCount',
    _$docDelCount,
    key: r'doc_del_count',
  );
  static int _$docCount(DatabaseInfo v) => v.docCount;
  static const Field<DatabaseInfo, int> _f$docCount = Field(
    'docCount',
    _$docCount,
    key: r'doc_count',
  );
  static int _$diskFormatVersion(DatabaseInfo v) => v.diskFormatVersion;
  static const Field<DatabaseInfo, int> _f$diskFormatVersion = Field(
    'diskFormatVersion',
    _$diskFormatVersion,
    key: r'disk_format_version',
  );
  static bool _$compactRunning(DatabaseInfo v) => v.compactRunning;
  static const Field<DatabaseInfo, bool> _f$compactRunning = Field(
    'compactRunning',
    _$compactRunning,
    key: r'compact_running',
  );
  static Map<String, int> _$cluster(DatabaseInfo v) => v.cluster;
  static const Field<DatabaseInfo, Map<String, int>> _f$cluster = Field(
    'cluster',
    _$cluster,
  );

  @override
  final MappableFields<DatabaseInfo> fields = const {
    #instanceStartTime: _f$instanceStartTime,
    #dbName: _f$dbName,
    #dbUuid: _f$dbUuid,
    #purgeSeq: _f$purgeSeq,
    #updateSeq: _f$updateSeq,
    #sizes: _f$sizes,
    #props: _f$props,
    #docDelCount: _f$docDelCount,
    #docCount: _f$docCount,
    #diskFormatVersion: _f$diskFormatVersion,
    #compactRunning: _f$compactRunning,
    #cluster: _f$cluster,
  };

  static DatabaseInfo _instantiate(DecodingData data) {
    return DatabaseInfo(
      instanceStartTime: data.dec(_f$instanceStartTime),
      dbName: data.dec(_f$dbName),
      dbUuid: data.dec(_f$dbUuid),
      purgeSeq: data.dec(_f$purgeSeq),
      updateSeq: data.dec(_f$updateSeq),
      sizes: data.dec(_f$sizes),
      props: data.dec(_f$props),
      docDelCount: data.dec(_f$docDelCount),
      docCount: data.dec(_f$docCount),
      diskFormatVersion: data.dec(_f$diskFormatVersion),
      compactRunning: data.dec(_f$compactRunning),
      cluster: data.dec(_f$cluster),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static DatabaseInfo fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<DatabaseInfo>(map);
  }

  static DatabaseInfo fromJson(String json) {
    return ensureInitialized().decodeJson<DatabaseInfo>(json);
  }
}

mixin DatabaseInfoMappable {
  String toJson() {
    return DatabaseInfoMapper.ensureInitialized().encodeJson<DatabaseInfo>(
      this as DatabaseInfo,
    );
  }

  Map<String, dynamic> toMap() {
    return DatabaseInfoMapper.ensureInitialized().encodeMap<DatabaseInfo>(
      this as DatabaseInfo,
    );
  }

  DatabaseInfoCopyWith<DatabaseInfo, DatabaseInfo, DatabaseInfo> get copyWith =>
      _DatabaseInfoCopyWithImpl<DatabaseInfo, DatabaseInfo>(
        this as DatabaseInfo,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return DatabaseInfoMapper.ensureInitialized().stringifyValue(
      this as DatabaseInfo,
    );
  }

  @override
  bool operator ==(Object other) {
    return DatabaseInfoMapper.ensureInitialized().equalsValue(
      this as DatabaseInfo,
      other,
    );
  }

  @override
  int get hashCode {
    return DatabaseInfoMapper.ensureInitialized().hashValue(
      this as DatabaseInfo,
    );
  }
}

extension DatabaseInfoValueCopy<$R, $Out>
    on ObjectCopyWith<$R, DatabaseInfo, $Out> {
  DatabaseInfoCopyWith<$R, DatabaseInfo, $Out> get $asDatabaseInfo =>
      $base.as((v, t, t2) => _DatabaseInfoCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class DatabaseInfoCopyWith<$R, $In extends DatabaseInfo, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, int, ObjectCopyWith<$R, int, int>> get sizes;
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>?>
  get props;
  MapCopyWith<$R, String, int, ObjectCopyWith<$R, int, int>> get cluster;
  $R call({
    String? instanceStartTime,
    String? dbName,
    String? dbUuid,
    String? purgeSeq,
    String? updateSeq,
    Map<String, int>? sizes,
    Map<String, dynamic>? props,
    int? docDelCount,
    int? docCount,
    int? diskFormatVersion,
    bool? compactRunning,
    Map<String, int>? cluster,
  });
  DatabaseInfoCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _DatabaseInfoCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, DatabaseInfo, $Out>
    implements DatabaseInfoCopyWith<$R, DatabaseInfo, $Out> {
  _DatabaseInfoCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<DatabaseInfo> $mapper =
      DatabaseInfoMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, int, ObjectCopyWith<$R, int, int>> get sizes =>
      MapCopyWith(
        $value.sizes,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(sizes: v),
      );
  @override
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>?>
  get props => MapCopyWith(
    $value.props,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(props: v),
  );
  @override
  MapCopyWith<$R, String, int, ObjectCopyWith<$R, int, int>> get cluster =>
      MapCopyWith(
        $value.cluster,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(cluster: v),
      );
  @override
  $R call({
    String? instanceStartTime,
    String? dbName,
    Object? dbUuid = $none,
    String? purgeSeq,
    String? updateSeq,
    Map<String, int>? sizes,
    Map<String, dynamic>? props,
    int? docDelCount,
    int? docCount,
    int? diskFormatVersion,
    bool? compactRunning,
    Map<String, int>? cluster,
  }) => $apply(
    FieldCopyWithData({
      if (instanceStartTime != null) #instanceStartTime: instanceStartTime,
      if (dbName != null) #dbName: dbName,
      if (dbUuid != $none) #dbUuid: dbUuid,
      if (purgeSeq != null) #purgeSeq: purgeSeq,
      if (updateSeq != null) #updateSeq: updateSeq,
      if (sizes != null) #sizes: sizes,
      if (props != null) #props: props,
      if (docDelCount != null) #docDelCount: docDelCount,
      if (docCount != null) #docCount: docCount,
      if (diskFormatVersion != null) #diskFormatVersion: diskFormatVersion,
      if (compactRunning != null) #compactRunning: compactRunning,
      if (cluster != null) #cluster: cluster,
    }),
  );
  @override
  DatabaseInfo $make(CopyWithData data) => DatabaseInfo(
    instanceStartTime: data.get(
      #instanceStartTime,
      or: $value.instanceStartTime,
    ),
    dbName: data.get(#dbName, or: $value.dbName),
    dbUuid: data.get(#dbUuid, or: $value.dbUuid),
    purgeSeq: data.get(#purgeSeq, or: $value.purgeSeq),
    updateSeq: data.get(#updateSeq, or: $value.updateSeq),
    sizes: data.get(#sizes, or: $value.sizes),
    props: data.get(#props, or: $value.props),
    docDelCount: data.get(#docDelCount, or: $value.docDelCount),
    docCount: data.get(#docCount, or: $value.docCount),
    diskFormatVersion: data.get(
      #diskFormatVersion,
      or: $value.diskFormatVersion,
    ),
    compactRunning: data.get(#compactRunning, or: $value.compactRunning),
    cluster: data.get(#cluster, or: $value.cluster),
  );

  @override
  DatabaseInfoCopyWith<$R2, DatabaseInfo, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _DatabaseInfoCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

