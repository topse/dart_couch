// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'db_updates_result.dart';

class DbUpdateTypeMapper extends EnumMapper<DbUpdateType> {
  DbUpdateTypeMapper._();

  static DbUpdateTypeMapper? _instance;
  static DbUpdateTypeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = DbUpdateTypeMapper._());
    }
    return _instance!;
  }

  static DbUpdateType fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  DbUpdateType decode(dynamic value) {
    switch (value) {
      case r'created':
        return DbUpdateType.created;
      case r'updated':
        return DbUpdateType.updated;
      case r'deleted':
        return DbUpdateType.deleted;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(DbUpdateType self) {
    switch (self) {
      case DbUpdateType.created:
        return r'created';
      case DbUpdateType.updated:
        return r'updated';
      case DbUpdateType.deleted:
        return r'deleted';
    }
  }
}

extension DbUpdateTypeMapperExtension on DbUpdateType {
  String toValue() {
    DbUpdateTypeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<DbUpdateType>(this) as String;
  }
}

class DbUpdatesResultMapper extends ClassMapperBase<DbUpdatesResult> {
  DbUpdatesResultMapper._();

  static DbUpdatesResultMapper? _instance;
  static DbUpdatesResultMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = DbUpdatesResultMapper._());
      DbUpdateEntryMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'DbUpdatesResult';

  static List<DbUpdateEntry> _$results(DbUpdatesResult v) => v.results;
  static const Field<DbUpdatesResult, List<DbUpdateEntry>> _f$results = Field(
    'results',
    _$results,
  );
  static String _$lastSeq(DbUpdatesResult v) => v.lastSeq;
  static const Field<DbUpdatesResult, String> _f$lastSeq = Field(
    'lastSeq',
    _$lastSeq,
    key: r'last_seq',
  );

  @override
  final MappableFields<DbUpdatesResult> fields = const {
    #results: _f$results,
    #lastSeq: _f$lastSeq,
  };

  static DbUpdatesResult _instantiate(DecodingData data) {
    return DbUpdatesResult(
      results: data.dec(_f$results),
      lastSeq: data.dec(_f$lastSeq),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static DbUpdatesResult fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<DbUpdatesResult>(map);
  }

  static DbUpdatesResult fromJson(String json) {
    return ensureInitialized().decodeJson<DbUpdatesResult>(json);
  }
}

mixin DbUpdatesResultMappable {
  String toJson() {
    return DbUpdatesResultMapper.ensureInitialized()
        .encodeJson<DbUpdatesResult>(this as DbUpdatesResult);
  }

  Map<String, dynamic> toMap() {
    return DbUpdatesResultMapper.ensureInitialized().encodeMap<DbUpdatesResult>(
      this as DbUpdatesResult,
    );
  }

  DbUpdatesResultCopyWith<DbUpdatesResult, DbUpdatesResult, DbUpdatesResult>
  get copyWith =>
      _DbUpdatesResultCopyWithImpl<DbUpdatesResult, DbUpdatesResult>(
        this as DbUpdatesResult,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return DbUpdatesResultMapper.ensureInitialized().stringifyValue(
      this as DbUpdatesResult,
    );
  }

  @override
  bool operator ==(Object other) {
    return DbUpdatesResultMapper.ensureInitialized().equalsValue(
      this as DbUpdatesResult,
      other,
    );
  }

  @override
  int get hashCode {
    return DbUpdatesResultMapper.ensureInitialized().hashValue(
      this as DbUpdatesResult,
    );
  }
}

extension DbUpdatesResultValueCopy<$R, $Out>
    on ObjectCopyWith<$R, DbUpdatesResult, $Out> {
  DbUpdatesResultCopyWith<$R, DbUpdatesResult, $Out> get $asDbUpdatesResult =>
      $base.as((v, t, t2) => _DbUpdatesResultCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class DbUpdatesResultCopyWith<$R, $In extends DbUpdatesResult, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    DbUpdateEntry,
    DbUpdateEntryCopyWith<$R, DbUpdateEntry, DbUpdateEntry>
  >
  get results;
  $R call({List<DbUpdateEntry>? results, String? lastSeq});
  DbUpdatesResultCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _DbUpdatesResultCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, DbUpdatesResult, $Out>
    implements DbUpdatesResultCopyWith<$R, DbUpdatesResult, $Out> {
  _DbUpdatesResultCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<DbUpdatesResult> $mapper =
      DbUpdatesResultMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    DbUpdateEntry,
    DbUpdateEntryCopyWith<$R, DbUpdateEntry, DbUpdateEntry>
  >
  get results => ListCopyWith(
    $value.results,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(results: v),
  );
  @override
  $R call({List<DbUpdateEntry>? results, String? lastSeq}) => $apply(
    FieldCopyWithData({
      if (results != null) #results: results,
      if (lastSeq != null) #lastSeq: lastSeq,
    }),
  );
  @override
  DbUpdatesResult $make(CopyWithData data) => DbUpdatesResult(
    results: data.get(#results, or: $value.results),
    lastSeq: data.get(#lastSeq, or: $value.lastSeq),
  );

  @override
  DbUpdatesResultCopyWith<$R2, DbUpdatesResult, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _DbUpdatesResultCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class DbUpdateEntryMapper extends ClassMapperBase<DbUpdateEntry> {
  DbUpdateEntryMapper._();

  static DbUpdateEntryMapper? _instance;
  static DbUpdateEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = DbUpdateEntryMapper._());
      DbUpdateTypeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'DbUpdateEntry';

  static String _$dbName(DbUpdateEntry v) => v.dbName;
  static const Field<DbUpdateEntry, String> _f$dbName = Field(
    'dbName',
    _$dbName,
    key: r'db_name',
  );
  static DbUpdateType _$type(DbUpdateEntry v) => v.type;
  static const Field<DbUpdateEntry, DbUpdateType> _f$type = Field(
    'type',
    _$type,
  );
  static String _$seq(DbUpdateEntry v) => v.seq;
  static const Field<DbUpdateEntry, String> _f$seq = Field('seq', _$seq);

  @override
  final MappableFields<DbUpdateEntry> fields = const {
    #dbName: _f$dbName,
    #type: _f$type,
    #seq: _f$seq,
  };

  static DbUpdateEntry _instantiate(DecodingData data) {
    return DbUpdateEntry(
      dbName: data.dec(_f$dbName),
      type: data.dec(_f$type),
      seq: data.dec(_f$seq),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static DbUpdateEntry fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<DbUpdateEntry>(map);
  }

  static DbUpdateEntry fromJson(String json) {
    return ensureInitialized().decodeJson<DbUpdateEntry>(json);
  }
}

mixin DbUpdateEntryMappable {
  String toJson() {
    return DbUpdateEntryMapper.ensureInitialized().encodeJson<DbUpdateEntry>(
      this as DbUpdateEntry,
    );
  }

  Map<String, dynamic> toMap() {
    return DbUpdateEntryMapper.ensureInitialized().encodeMap<DbUpdateEntry>(
      this as DbUpdateEntry,
    );
  }

  DbUpdateEntryCopyWith<DbUpdateEntry, DbUpdateEntry, DbUpdateEntry>
  get copyWith => _DbUpdateEntryCopyWithImpl<DbUpdateEntry, DbUpdateEntry>(
    this as DbUpdateEntry,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return DbUpdateEntryMapper.ensureInitialized().stringifyValue(
      this as DbUpdateEntry,
    );
  }

  @override
  bool operator ==(Object other) {
    return DbUpdateEntryMapper.ensureInitialized().equalsValue(
      this as DbUpdateEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return DbUpdateEntryMapper.ensureInitialized().hashValue(
      this as DbUpdateEntry,
    );
  }
}

extension DbUpdateEntryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, DbUpdateEntry, $Out> {
  DbUpdateEntryCopyWith<$R, DbUpdateEntry, $Out> get $asDbUpdateEntry =>
      $base.as((v, t, t2) => _DbUpdateEntryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class DbUpdateEntryCopyWith<$R, $In extends DbUpdateEntry, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? dbName, DbUpdateType? type, String? seq});
  DbUpdateEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _DbUpdateEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, DbUpdateEntry, $Out>
    implements DbUpdateEntryCopyWith<$R, DbUpdateEntry, $Out> {
  _DbUpdateEntryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<DbUpdateEntry> $mapper =
      DbUpdateEntryMapper.ensureInitialized();
  @override
  $R call({String? dbName, DbUpdateType? type, String? seq}) => $apply(
    FieldCopyWithData({
      if (dbName != null) #dbName: dbName,
      if (type != null) #type: type,
      if (seq != null) #seq: seq,
    }),
  );
  @override
  DbUpdateEntry $make(CopyWithData data) => DbUpdateEntry(
    dbName: data.get(#dbName, or: $value.dbName),
    type: data.get(#type, or: $value.type),
    seq: data.get(#seq, or: $value.seq),
  );

  @override
  DbUpdateEntryCopyWith<$R2, DbUpdateEntry, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _DbUpdateEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

