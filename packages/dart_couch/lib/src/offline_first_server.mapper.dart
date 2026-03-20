// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'offline_first_server.dart';

class OfflineFirstServerDbUpdatesStateMapper
    extends SubClassMapperBase<OfflineFirstServerDbUpdatesState> {
  OfflineFirstServerDbUpdatesStateMapper._();

  static OfflineFirstServerDbUpdatesStateMapper? _instance;
  static OfflineFirstServerDbUpdatesStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = OfflineFirstServerDbUpdatesStateMapper._(),
      );
      CouchDocumentBaseMapper.ensureInitialized().addSubMapper(_instance!);
      AttachmentInfoMapper.ensureInitialized();
      RevisionsMapper.ensureInitialized();
      RevsInfoMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'OfflineFirstServerDbUpdatesState';

  static String _$lastSeq(OfflineFirstServerDbUpdatesState v) => v.lastSeq;
  static const Field<OfflineFirstServerDbUpdatesState, String> _f$lastSeq =
      Field('lastSeq', _$lastSeq);
  static String? _$id(OfflineFirstServerDbUpdatesState v) => v.id;
  static const Field<OfflineFirstServerDbUpdatesState, String> _f$id = Field(
    'id',
    _$id,
    key: r'_id',
  );
  static String? _$rev(OfflineFirstServerDbUpdatesState v) => v.rev;
  static const Field<OfflineFirstServerDbUpdatesState, String> _f$rev = Field(
    'rev',
    _$rev,
    key: r'_rev',
    opt: true,
  );
  static Map<String, AttachmentInfo>? _$attachments(
    OfflineFirstServerDbUpdatesState v,
  ) => v.attachments;
  static const Field<
    OfflineFirstServerDbUpdatesState,
    Map<String, AttachmentInfo>
  >
  _f$attachments = Field(
    'attachments',
    _$attachments,
    key: r'_attachments',
    opt: true,
  );
  static Revisions? _$revisions(OfflineFirstServerDbUpdatesState v) =>
      v.revisions;
  static const Field<OfflineFirstServerDbUpdatesState, Revisions> _f$revisions =
      Field('revisions', _$revisions, key: r'_revisions', opt: true);
  static List<RevsInfo>? _$revsInfo(OfflineFirstServerDbUpdatesState v) =>
      v.revsInfo;
  static const Field<OfflineFirstServerDbUpdatesState, List<RevsInfo>>
  _f$revsInfo = Field('revsInfo', _$revsInfo, key: r'_revs_info', opt: true);
  static bool _$deleted(OfflineFirstServerDbUpdatesState v) => v.deleted;
  static const Field<OfflineFirstServerDbUpdatesState, bool> _f$deleted = Field(
    'deleted',
    _$deleted,
    key: r'_deleted',
    opt: true,
    def: false,
  );
  static Map<String, dynamic> _$unmappedProps(
    OfflineFirstServerDbUpdatesState v,
  ) => v.unmappedProps;
  static const Field<OfflineFirstServerDbUpdatesState, Map<String, dynamic>>
  _f$unmappedProps = Field(
    'unmappedProps',
    _$unmappedProps,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<OfflineFirstServerDbUpdatesState> fields = const {
    #lastSeq: _f$lastSeq,
    #id: _f$id,
    #rev: _f$rev,
    #attachments: _f$attachments,
    #revisions: _f$revisions,
    #revsInfo: _f$revsInfo,
    #deleted: _f$deleted,
    #unmappedProps: _f$unmappedProps,
  };
  @override
  final bool ignoreNull = true;

  @override
  final String discriminatorKey = '!doc_type';
  @override
  final dynamic discriminatorValue = '!offline_first_server_db_updates_state';
  @override
  late final ClassMapperBase superMapper =
      CouchDocumentBaseMapper.ensureInitialized();

  @override
  final MappingHook superHook = const ChainedHook([
    CouchDocumentBaseRawHook(),
    UnmappedPropertiesHook('unmappedProps'),
  ]);

  static OfflineFirstServerDbUpdatesState _instantiate(DecodingData data) {
    return OfflineFirstServerDbUpdatesState(
      lastSeq: data.dec(_f$lastSeq),
      id: data.dec(_f$id),
      rev: data.dec(_f$rev),
      attachments: data.dec(_f$attachments),
      revisions: data.dec(_f$revisions),
      revsInfo: data.dec(_f$revsInfo),
      deleted: data.dec(_f$deleted),
      unmappedProps: data.dec(_f$unmappedProps),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static OfflineFirstServerDbUpdatesState fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<OfflineFirstServerDbUpdatesState>(map);
  }

  static OfflineFirstServerDbUpdatesState fromJson(String json) {
    return ensureInitialized().decodeJson<OfflineFirstServerDbUpdatesState>(
      json,
    );
  }
}

mixin OfflineFirstServerDbUpdatesStateMappable {
  String toJson() {
    return OfflineFirstServerDbUpdatesStateMapper.ensureInitialized()
        .encodeJson<OfflineFirstServerDbUpdatesState>(
          this as OfflineFirstServerDbUpdatesState,
        );
  }

  Map<String, dynamic> toMap() {
    return OfflineFirstServerDbUpdatesStateMapper.ensureInitialized()
        .encodeMap<OfflineFirstServerDbUpdatesState>(
          this as OfflineFirstServerDbUpdatesState,
        );
  }

  OfflineFirstServerDbUpdatesStateCopyWith<
    OfflineFirstServerDbUpdatesState,
    OfflineFirstServerDbUpdatesState,
    OfflineFirstServerDbUpdatesState
  >
  get copyWith =>
      _OfflineFirstServerDbUpdatesStateCopyWithImpl<
        OfflineFirstServerDbUpdatesState,
        OfflineFirstServerDbUpdatesState
      >(this as OfflineFirstServerDbUpdatesState, $identity, $identity);
  @override
  String toString() {
    return OfflineFirstServerDbUpdatesStateMapper.ensureInitialized()
        .stringifyValue(this as OfflineFirstServerDbUpdatesState);
  }

  @override
  bool operator ==(Object other) {
    return OfflineFirstServerDbUpdatesStateMapper.ensureInitialized()
        .equalsValue(this as OfflineFirstServerDbUpdatesState, other);
  }

  @override
  int get hashCode {
    return OfflineFirstServerDbUpdatesStateMapper.ensureInitialized().hashValue(
      this as OfflineFirstServerDbUpdatesState,
    );
  }
}

extension OfflineFirstServerDbUpdatesStateValueCopy<$R, $Out>
    on ObjectCopyWith<$R, OfflineFirstServerDbUpdatesState, $Out> {
  OfflineFirstServerDbUpdatesStateCopyWith<
    $R,
    OfflineFirstServerDbUpdatesState,
    $Out
  >
  get $asOfflineFirstServerDbUpdatesState => $base.as(
    (v, t, t2) =>
        _OfflineFirstServerDbUpdatesStateCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class OfflineFirstServerDbUpdatesStateCopyWith<
  $R,
  $In extends OfflineFirstServerDbUpdatesState,
  $Out
>
    implements CouchDocumentBaseCopyWith<$R, $In, $Out> {
  @override
  MapCopyWith<
    $R,
    String,
    AttachmentInfo,
    AttachmentInfoCopyWith<$R, AttachmentInfo, AttachmentInfo>
  >?
  get attachments;
  @override
  RevisionsCopyWith<$R, Revisions, Revisions>? get revisions;
  @override
  ListCopyWith<$R, RevsInfo, RevsInfoCopyWith<$R, RevsInfo, RevsInfo>>?
  get revsInfo;
  @override
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>?>
  get unmappedProps;
  @override
  $R call({
    String? lastSeq,
    String? id,
    String? rev,
    Map<String, AttachmentInfo>? attachments,
    Revisions? revisions,
    List<RevsInfo>? revsInfo,
    bool? deleted,
    Map<String, dynamic>? unmappedProps,
  });
  OfflineFirstServerDbUpdatesStateCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _OfflineFirstServerDbUpdatesStateCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, OfflineFirstServerDbUpdatesState, $Out>
    implements
        OfflineFirstServerDbUpdatesStateCopyWith<
          $R,
          OfflineFirstServerDbUpdatesState,
          $Out
        > {
  _OfflineFirstServerDbUpdatesStateCopyWithImpl(
    super.value,
    super.then,
    super.then2,
  );

  @override
  late final ClassMapperBase<OfflineFirstServerDbUpdatesState> $mapper =
      OfflineFirstServerDbUpdatesStateMapper.ensureInitialized();
  @override
  MapCopyWith<
    $R,
    String,
    AttachmentInfo,
    AttachmentInfoCopyWith<$R, AttachmentInfo, AttachmentInfo>
  >?
  get attachments => $value.attachments != null
      ? MapCopyWith(
          $value.attachments!,
          (v, t) => v.copyWith.$chain(t),
          (v) => call(attachments: v),
        )
      : null;
  @override
  RevisionsCopyWith<$R, Revisions, Revisions>? get revisions =>
      $value.revisions?.copyWith.$chain((v) => call(revisions: v));
  @override
  ListCopyWith<$R, RevsInfo, RevsInfoCopyWith<$R, RevsInfo, RevsInfo>>?
  get revsInfo => $value.revsInfo != null
      ? ListCopyWith(
          $value.revsInfo!,
          (v, t) => v.copyWith.$chain(t),
          (v) => call(revsInfo: v),
        )
      : null;
  @override
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>?>
  get unmappedProps => MapCopyWith(
    $value.unmappedProps,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(unmappedProps: v),
  );
  @override
  $R call({
    String? lastSeq,
    Object? id = $none,
    Object? rev = $none,
    Object? attachments = $none,
    Object? revisions = $none,
    Object? revsInfo = $none,
    bool? deleted,
    Map<String, dynamic>? unmappedProps,
  }) => $apply(
    FieldCopyWithData({
      if (lastSeq != null) #lastSeq: lastSeq,
      if (id != $none) #id: id,
      if (rev != $none) #rev: rev,
      if (attachments != $none) #attachments: attachments,
      if (revisions != $none) #revisions: revisions,
      if (revsInfo != $none) #revsInfo: revsInfo,
      if (deleted != null) #deleted: deleted,
      if (unmappedProps != null) #unmappedProps: unmappedProps,
    }),
  );
  @override
  OfflineFirstServerDbUpdatesState $make(CopyWithData data) =>
      OfflineFirstServerDbUpdatesState(
        lastSeq: data.get(#lastSeq, or: $value.lastSeq),
        id: data.get(#id, or: $value.id),
        rev: data.get(#rev, or: $value.rev),
        attachments: data.get(#attachments, or: $value.attachments),
        revisions: data.get(#revisions, or: $value.revisions),
        revsInfo: data.get(#revsInfo, or: $value.revsInfo),
        deleted: data.get(#deleted, or: $value.deleted),
        unmappedProps: data.get(#unmappedProps, or: $value.unmappedProps),
      );

  @override
  OfflineFirstServerDbUpdatesStateCopyWith<
    $R2,
    OfflineFirstServerDbUpdatesState,
    $Out2
  >
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _OfflineFirstServerDbUpdatesStateCopyWithImpl<$R2, $Out2>(
        $value,
        $cast,
        t,
      );
}

class OfflineFirstServerLoginStateMapper
    extends SubClassMapperBase<OfflineFirstServerLoginState> {
  OfflineFirstServerLoginStateMapper._();

  static OfflineFirstServerLoginStateMapper? _instance;
  static OfflineFirstServerLoginStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = OfflineFirstServerLoginStateMapper._(),
      );
      CouchDocumentBaseMapper.ensureInitialized().addSubMapper(_instance!);
      AttachmentInfoMapper.ensureInitialized();
      RevisionsMapper.ensureInitialized();
      RevsInfoMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'OfflineFirstServerLoginState';

  static String _$hashedUsername(OfflineFirstServerLoginState v) =>
      v.hashedUsername;
  static const Field<OfflineFirstServerLoginState, String> _f$hashedUsername =
      Field('hashedUsername', _$hashedUsername);
  static String _$hashedPassword(OfflineFirstServerLoginState v) =>
      v.hashedPassword;
  static const Field<OfflineFirstServerLoginState, String> _f$hashedPassword =
      Field('hashedPassword', _$hashedPassword);
  static bool _$canAllDbs(OfflineFirstServerLoginState v) => v.canAllDbs;
  static const Field<OfflineFirstServerLoginState, bool> _f$canAllDbs = Field(
    'canAllDbs',
    _$canAllDbs,
  );
  static String? _$id(OfflineFirstServerLoginState v) => v.id;
  static const Field<OfflineFirstServerLoginState, String> _f$id = Field(
    'id',
    _$id,
    key: r'_id',
  );
  static String? _$rev(OfflineFirstServerLoginState v) => v.rev;
  static const Field<OfflineFirstServerLoginState, String> _f$rev = Field(
    'rev',
    _$rev,
    key: r'_rev',
    opt: true,
  );
  static Map<String, AttachmentInfo>? _$attachments(
    OfflineFirstServerLoginState v,
  ) => v.attachments;
  static const Field<OfflineFirstServerLoginState, Map<String, AttachmentInfo>>
  _f$attachments = Field(
    'attachments',
    _$attachments,
    key: r'_attachments',
    opt: true,
  );
  static Revisions? _$revisions(OfflineFirstServerLoginState v) => v.revisions;
  static const Field<OfflineFirstServerLoginState, Revisions> _f$revisions =
      Field('revisions', _$revisions, key: r'_revisions', opt: true);
  static List<RevsInfo>? _$revsInfo(OfflineFirstServerLoginState v) =>
      v.revsInfo;
  static const Field<OfflineFirstServerLoginState, List<RevsInfo>> _f$revsInfo =
      Field('revsInfo', _$revsInfo, key: r'_revs_info', opt: true);
  static bool _$deleted(OfflineFirstServerLoginState v) => v.deleted;
  static const Field<OfflineFirstServerLoginState, bool> _f$deleted = Field(
    'deleted',
    _$deleted,
    key: r'_deleted',
    opt: true,
    def: false,
  );
  static Map<String, dynamic> _$unmappedProps(OfflineFirstServerLoginState v) =>
      v.unmappedProps;
  static const Field<OfflineFirstServerLoginState, Map<String, dynamic>>
  _f$unmappedProps = Field(
    'unmappedProps',
    _$unmappedProps,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<OfflineFirstServerLoginState> fields = const {
    #hashedUsername: _f$hashedUsername,
    #hashedPassword: _f$hashedPassword,
    #canAllDbs: _f$canAllDbs,
    #id: _f$id,
    #rev: _f$rev,
    #attachments: _f$attachments,
    #revisions: _f$revisions,
    #revsInfo: _f$revsInfo,
    #deleted: _f$deleted,
    #unmappedProps: _f$unmappedProps,
  };
  @override
  final bool ignoreNull = true;

  @override
  final String discriminatorKey = '!doc_type';
  @override
  final dynamic discriminatorValue = '!offline_first_server_login_state';
  @override
  late final ClassMapperBase superMapper =
      CouchDocumentBaseMapper.ensureInitialized();

  @override
  final MappingHook superHook = const ChainedHook([
    CouchDocumentBaseRawHook(),
    UnmappedPropertiesHook('unmappedProps'),
  ]);

  static OfflineFirstServerLoginState _instantiate(DecodingData data) {
    return OfflineFirstServerLoginState(
      hashedUsername: data.dec(_f$hashedUsername),
      hashedPassword: data.dec(_f$hashedPassword),
      canAllDbs: data.dec(_f$canAllDbs),
      id: data.dec(_f$id),
      rev: data.dec(_f$rev),
      attachments: data.dec(_f$attachments),
      revisions: data.dec(_f$revisions),
      revsInfo: data.dec(_f$revsInfo),
      deleted: data.dec(_f$deleted),
      unmappedProps: data.dec(_f$unmappedProps),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static OfflineFirstServerLoginState fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<OfflineFirstServerLoginState>(map);
  }

  static OfflineFirstServerLoginState fromJson(String json) {
    return ensureInitialized().decodeJson<OfflineFirstServerLoginState>(json);
  }
}

mixin OfflineFirstServerLoginStateMappable {
  String toJson() {
    return OfflineFirstServerLoginStateMapper.ensureInitialized()
        .encodeJson<OfflineFirstServerLoginState>(
          this as OfflineFirstServerLoginState,
        );
  }

  Map<String, dynamic> toMap() {
    return OfflineFirstServerLoginStateMapper.ensureInitialized()
        .encodeMap<OfflineFirstServerLoginState>(
          this as OfflineFirstServerLoginState,
        );
  }

  OfflineFirstServerLoginStateCopyWith<
    OfflineFirstServerLoginState,
    OfflineFirstServerLoginState,
    OfflineFirstServerLoginState
  >
  get copyWith =>
      _OfflineFirstServerLoginStateCopyWithImpl<
        OfflineFirstServerLoginState,
        OfflineFirstServerLoginState
      >(this as OfflineFirstServerLoginState, $identity, $identity);
  @override
  String toString() {
    return OfflineFirstServerLoginStateMapper.ensureInitialized()
        .stringifyValue(this as OfflineFirstServerLoginState);
  }

  @override
  bool operator ==(Object other) {
    return OfflineFirstServerLoginStateMapper.ensureInitialized().equalsValue(
      this as OfflineFirstServerLoginState,
      other,
    );
  }

  @override
  int get hashCode {
    return OfflineFirstServerLoginStateMapper.ensureInitialized().hashValue(
      this as OfflineFirstServerLoginState,
    );
  }
}

extension OfflineFirstServerLoginStateValueCopy<$R, $Out>
    on ObjectCopyWith<$R, OfflineFirstServerLoginState, $Out> {
  OfflineFirstServerLoginStateCopyWith<$R, OfflineFirstServerLoginState, $Out>
  get $asOfflineFirstServerLoginState => $base.as(
    (v, t, t2) => _OfflineFirstServerLoginStateCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class OfflineFirstServerLoginStateCopyWith<
  $R,
  $In extends OfflineFirstServerLoginState,
  $Out
>
    implements CouchDocumentBaseCopyWith<$R, $In, $Out> {
  @override
  MapCopyWith<
    $R,
    String,
    AttachmentInfo,
    AttachmentInfoCopyWith<$R, AttachmentInfo, AttachmentInfo>
  >?
  get attachments;
  @override
  RevisionsCopyWith<$R, Revisions, Revisions>? get revisions;
  @override
  ListCopyWith<$R, RevsInfo, RevsInfoCopyWith<$R, RevsInfo, RevsInfo>>?
  get revsInfo;
  @override
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>?>
  get unmappedProps;
  @override
  $R call({
    String? hashedUsername,
    String? hashedPassword,
    bool? canAllDbs,
    String? id,
    String? rev,
    Map<String, AttachmentInfo>? attachments,
    Revisions? revisions,
    List<RevsInfo>? revsInfo,
    bool? deleted,
    Map<String, dynamic>? unmappedProps,
  });
  OfflineFirstServerLoginStateCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _OfflineFirstServerLoginStateCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, OfflineFirstServerLoginState, $Out>
    implements
        OfflineFirstServerLoginStateCopyWith<
          $R,
          OfflineFirstServerLoginState,
          $Out
        > {
  _OfflineFirstServerLoginStateCopyWithImpl(
    super.value,
    super.then,
    super.then2,
  );

  @override
  late final ClassMapperBase<OfflineFirstServerLoginState> $mapper =
      OfflineFirstServerLoginStateMapper.ensureInitialized();
  @override
  MapCopyWith<
    $R,
    String,
    AttachmentInfo,
    AttachmentInfoCopyWith<$R, AttachmentInfo, AttachmentInfo>
  >?
  get attachments => $value.attachments != null
      ? MapCopyWith(
          $value.attachments!,
          (v, t) => v.copyWith.$chain(t),
          (v) => call(attachments: v),
        )
      : null;
  @override
  RevisionsCopyWith<$R, Revisions, Revisions>? get revisions =>
      $value.revisions?.copyWith.$chain((v) => call(revisions: v));
  @override
  ListCopyWith<$R, RevsInfo, RevsInfoCopyWith<$R, RevsInfo, RevsInfo>>?
  get revsInfo => $value.revsInfo != null
      ? ListCopyWith(
          $value.revsInfo!,
          (v, t) => v.copyWith.$chain(t),
          (v) => call(revsInfo: v),
        )
      : null;
  @override
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>?>
  get unmappedProps => MapCopyWith(
    $value.unmappedProps,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(unmappedProps: v),
  );
  @override
  $R call({
    String? hashedUsername,
    String? hashedPassword,
    bool? canAllDbs,
    Object? id = $none,
    Object? rev = $none,
    Object? attachments = $none,
    Object? revisions = $none,
    Object? revsInfo = $none,
    bool? deleted,
    Map<String, dynamic>? unmappedProps,
  }) => $apply(
    FieldCopyWithData({
      if (hashedUsername != null) #hashedUsername: hashedUsername,
      if (hashedPassword != null) #hashedPassword: hashedPassword,
      if (canAllDbs != null) #canAllDbs: canAllDbs,
      if (id != $none) #id: id,
      if (rev != $none) #rev: rev,
      if (attachments != $none) #attachments: attachments,
      if (revisions != $none) #revisions: revisions,
      if (revsInfo != $none) #revsInfo: revsInfo,
      if (deleted != null) #deleted: deleted,
      if (unmappedProps != null) #unmappedProps: unmappedProps,
    }),
  );
  @override
  OfflineFirstServerLoginState $make(CopyWithData data) =>
      OfflineFirstServerLoginState(
        hashedUsername: data.get(#hashedUsername, or: $value.hashedUsername),
        hashedPassword: data.get(#hashedPassword, or: $value.hashedPassword),
        canAllDbs: data.get(#canAllDbs, or: $value.canAllDbs),
        id: data.get(#id, or: $value.id),
        rev: data.get(#rev, or: $value.rev),
        attachments: data.get(#attachments, or: $value.attachments),
        revisions: data.get(#revisions, or: $value.revisions),
        revsInfo: data.get(#revsInfo, or: $value.revsInfo),
        deleted: data.get(#deleted, or: $value.deleted),
        unmappedProps: data.get(#unmappedProps, or: $value.unmappedProps),
      );

  @override
  OfflineFirstServerLoginStateCopyWith<$R2, OfflineFirstServerLoginState, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _OfflineFirstServerLoginStateCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class DatabaseSyncMarkerMapper extends SubClassMapperBase<DatabaseSyncMarker> {
  DatabaseSyncMarkerMapper._();

  static DatabaseSyncMarkerMapper? _instance;
  static DatabaseSyncMarkerMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = DatabaseSyncMarkerMapper._());
      CouchDocumentBaseMapper.ensureInitialized().addSubMapper(_instance!);
      AttachmentInfoMapper.ensureInitialized();
      RevisionsMapper.ensureInitialized();
      RevsInfoMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'DatabaseSyncMarker';

  static String _$instanceUuid(DatabaseSyncMarker v) => v.instanceUuid;
  static const Field<DatabaseSyncMarker, String> _f$instanceUuid = Field(
    'instanceUuid',
    _$instanceUuid,
  );
  static String _$databaseUuid(DatabaseSyncMarker v) => v.databaseUuid;
  static const Field<DatabaseSyncMarker, String> _f$databaseUuid = Field(
    'databaseUuid',
    _$databaseUuid,
  );
  static DateTime _$createdAt(DatabaseSyncMarker v) => v.createdAt;
  static const Field<DatabaseSyncMarker, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static String _$createdBy(DatabaseSyncMarker v) => v.createdBy;
  static const Field<DatabaseSyncMarker, String> _f$createdBy = Field(
    'createdBy',
    _$createdBy,
  );
  static List<String> _$activeInstances(DatabaseSyncMarker v) =>
      v.activeInstances;
  static const Field<DatabaseSyncMarker, List<String>> _f$activeInstances =
      Field('activeInstances', _$activeInstances, opt: true);
  static bool _$tombstone(DatabaseSyncMarker v) => v.tombstone;
  static const Field<DatabaseSyncMarker, bool> _f$tombstone = Field(
    'tombstone',
    _$tombstone,
    opt: true,
    def: false,
  );
  static String? _$id(DatabaseSyncMarker v) => v.id;
  static const Field<DatabaseSyncMarker, String> _f$id = Field(
    'id',
    _$id,
    key: r'_id',
    opt: true,
    def: '_local/db_sync_marker',
  );
  static String? _$rev(DatabaseSyncMarker v) => v.rev;
  static const Field<DatabaseSyncMarker, String> _f$rev = Field(
    'rev',
    _$rev,
    key: r'_rev',
    opt: true,
  );
  static Map<String, AttachmentInfo>? _$attachments(DatabaseSyncMarker v) =>
      v.attachments;
  static const Field<DatabaseSyncMarker, Map<String, AttachmentInfo>>
  _f$attachments = Field(
    'attachments',
    _$attachments,
    key: r'_attachments',
    opt: true,
  );
  static Revisions? _$revisions(DatabaseSyncMarker v) => v.revisions;
  static const Field<DatabaseSyncMarker, Revisions> _f$revisions = Field(
    'revisions',
    _$revisions,
    key: r'_revisions',
    opt: true,
  );
  static List<RevsInfo>? _$revsInfo(DatabaseSyncMarker v) => v.revsInfo;
  static const Field<DatabaseSyncMarker, List<RevsInfo>> _f$revsInfo = Field(
    'revsInfo',
    _$revsInfo,
    key: r'_revs_info',
    opt: true,
  );
  static bool _$deleted(DatabaseSyncMarker v) => v.deleted;
  static const Field<DatabaseSyncMarker, bool> _f$deleted = Field(
    'deleted',
    _$deleted,
    key: r'_deleted',
    opt: true,
    def: false,
  );
  static Map<String, dynamic> _$unmappedProps(DatabaseSyncMarker v) =>
      v.unmappedProps;
  static const Field<DatabaseSyncMarker, Map<String, dynamic>>
  _f$unmappedProps = Field(
    'unmappedProps',
    _$unmappedProps,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<DatabaseSyncMarker> fields = const {
    #instanceUuid: _f$instanceUuid,
    #databaseUuid: _f$databaseUuid,
    #createdAt: _f$createdAt,
    #createdBy: _f$createdBy,
    #activeInstances: _f$activeInstances,
    #tombstone: _f$tombstone,
    #id: _f$id,
    #rev: _f$rev,
    #attachments: _f$attachments,
    #revisions: _f$revisions,
    #revsInfo: _f$revsInfo,
    #deleted: _f$deleted,
    #unmappedProps: _f$unmappedProps,
  };
  @override
  final bool ignoreNull = true;

  @override
  final String discriminatorKey = '!doc_type';
  @override
  final dynamic discriminatorValue = '!db_sync_marker';
  @override
  late final ClassMapperBase superMapper =
      CouchDocumentBaseMapper.ensureInitialized();

  @override
  final MappingHook superHook = const ChainedHook([
    CouchDocumentBaseRawHook(),
    UnmappedPropertiesHook('unmappedProps'),
  ]);

  static DatabaseSyncMarker _instantiate(DecodingData data) {
    return DatabaseSyncMarker(
      instanceUuid: data.dec(_f$instanceUuid),
      databaseUuid: data.dec(_f$databaseUuid),
      createdAt: data.dec(_f$createdAt),
      createdBy: data.dec(_f$createdBy),
      activeInstances: data.dec(_f$activeInstances),
      tombstone: data.dec(_f$tombstone),
      id: data.dec(_f$id),
      rev: data.dec(_f$rev),
      attachments: data.dec(_f$attachments),
      revisions: data.dec(_f$revisions),
      revsInfo: data.dec(_f$revsInfo),
      deleted: data.dec(_f$deleted),
      unmappedProps: data.dec(_f$unmappedProps),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static DatabaseSyncMarker fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<DatabaseSyncMarker>(map);
  }

  static DatabaseSyncMarker fromJson(String json) {
    return ensureInitialized().decodeJson<DatabaseSyncMarker>(json);
  }
}

mixin DatabaseSyncMarkerMappable {
  String toJson() {
    return DatabaseSyncMarkerMapper.ensureInitialized()
        .encodeJson<DatabaseSyncMarker>(this as DatabaseSyncMarker);
  }

  Map<String, dynamic> toMap() {
    return DatabaseSyncMarkerMapper.ensureInitialized()
        .encodeMap<DatabaseSyncMarker>(this as DatabaseSyncMarker);
  }

  DatabaseSyncMarkerCopyWith<
    DatabaseSyncMarker,
    DatabaseSyncMarker,
    DatabaseSyncMarker
  >
  get copyWith =>
      _DatabaseSyncMarkerCopyWithImpl<DatabaseSyncMarker, DatabaseSyncMarker>(
        this as DatabaseSyncMarker,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return DatabaseSyncMarkerMapper.ensureInitialized().stringifyValue(
      this as DatabaseSyncMarker,
    );
  }

  @override
  bool operator ==(Object other) {
    return DatabaseSyncMarkerMapper.ensureInitialized().equalsValue(
      this as DatabaseSyncMarker,
      other,
    );
  }

  @override
  int get hashCode {
    return DatabaseSyncMarkerMapper.ensureInitialized().hashValue(
      this as DatabaseSyncMarker,
    );
  }
}

extension DatabaseSyncMarkerValueCopy<$R, $Out>
    on ObjectCopyWith<$R, DatabaseSyncMarker, $Out> {
  DatabaseSyncMarkerCopyWith<$R, DatabaseSyncMarker, $Out>
  get $asDatabaseSyncMarker => $base.as(
    (v, t, t2) => _DatabaseSyncMarkerCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class DatabaseSyncMarkerCopyWith<
  $R,
  $In extends DatabaseSyncMarker,
  $Out
>
    implements CouchDocumentBaseCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get activeInstances;
  @override
  MapCopyWith<
    $R,
    String,
    AttachmentInfo,
    AttachmentInfoCopyWith<$R, AttachmentInfo, AttachmentInfo>
  >?
  get attachments;
  @override
  RevisionsCopyWith<$R, Revisions, Revisions>? get revisions;
  @override
  ListCopyWith<$R, RevsInfo, RevsInfoCopyWith<$R, RevsInfo, RevsInfo>>?
  get revsInfo;
  @override
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>?>
  get unmappedProps;
  @override
  $R call({
    String? instanceUuid,
    String? databaseUuid,
    DateTime? createdAt,
    String? createdBy,
    List<String>? activeInstances,
    bool? tombstone,
    String? id,
    String? rev,
    Map<String, AttachmentInfo>? attachments,
    Revisions? revisions,
    List<RevsInfo>? revsInfo,
    bool? deleted,
    Map<String, dynamic>? unmappedProps,
  });
  DatabaseSyncMarkerCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _DatabaseSyncMarkerCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, DatabaseSyncMarker, $Out>
    implements DatabaseSyncMarkerCopyWith<$R, DatabaseSyncMarker, $Out> {
  _DatabaseSyncMarkerCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<DatabaseSyncMarker> $mapper =
      DatabaseSyncMarkerMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get activeInstances => ListCopyWith(
    $value.activeInstances,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(activeInstances: v),
  );
  @override
  MapCopyWith<
    $R,
    String,
    AttachmentInfo,
    AttachmentInfoCopyWith<$R, AttachmentInfo, AttachmentInfo>
  >?
  get attachments => $value.attachments != null
      ? MapCopyWith(
          $value.attachments!,
          (v, t) => v.copyWith.$chain(t),
          (v) => call(attachments: v),
        )
      : null;
  @override
  RevisionsCopyWith<$R, Revisions, Revisions>? get revisions =>
      $value.revisions?.copyWith.$chain((v) => call(revisions: v));
  @override
  ListCopyWith<$R, RevsInfo, RevsInfoCopyWith<$R, RevsInfo, RevsInfo>>?
  get revsInfo => $value.revsInfo != null
      ? ListCopyWith(
          $value.revsInfo!,
          (v, t) => v.copyWith.$chain(t),
          (v) => call(revsInfo: v),
        )
      : null;
  @override
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>?>
  get unmappedProps => MapCopyWith(
    $value.unmappedProps,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(unmappedProps: v),
  );
  @override
  $R call({
    String? instanceUuid,
    String? databaseUuid,
    DateTime? createdAt,
    String? createdBy,
    Object? activeInstances = $none,
    bool? tombstone,
    Object? id = $none,
    Object? rev = $none,
    Object? attachments = $none,
    Object? revisions = $none,
    Object? revsInfo = $none,
    bool? deleted,
    Map<String, dynamic>? unmappedProps,
  }) => $apply(
    FieldCopyWithData({
      if (instanceUuid != null) #instanceUuid: instanceUuid,
      if (databaseUuid != null) #databaseUuid: databaseUuid,
      if (createdAt != null) #createdAt: createdAt,
      if (createdBy != null) #createdBy: createdBy,
      if (activeInstances != $none) #activeInstances: activeInstances,
      if (tombstone != null) #tombstone: tombstone,
      if (id != $none) #id: id,
      if (rev != $none) #rev: rev,
      if (attachments != $none) #attachments: attachments,
      if (revisions != $none) #revisions: revisions,
      if (revsInfo != $none) #revsInfo: revsInfo,
      if (deleted != null) #deleted: deleted,
      if (unmappedProps != null) #unmappedProps: unmappedProps,
    }),
  );
  @override
  DatabaseSyncMarker $make(CopyWithData data) => DatabaseSyncMarker(
    instanceUuid: data.get(#instanceUuid, or: $value.instanceUuid),
    databaseUuid: data.get(#databaseUuid, or: $value.databaseUuid),
    createdAt: data.get(#createdAt, or: $value.createdAt),
    createdBy: data.get(#createdBy, or: $value.createdBy),
    activeInstances: data.get(#activeInstances, or: $value.activeInstances),
    tombstone: data.get(#tombstone, or: $value.tombstone),
    id: data.get(#id, or: $value.id),
    rev: data.get(#rev, or: $value.rev),
    attachments: data.get(#attachments, or: $value.attachments),
    revisions: data.get(#revisions, or: $value.revisions),
    revsInfo: data.get(#revsInfo, or: $value.revsInfo),
    deleted: data.get(#deleted, or: $value.deleted),
    unmappedProps: data.get(#unmappedProps, or: $value.unmappedProps),
  );

  @override
  DatabaseSyncMarkerCopyWith<$R2, DatabaseSyncMarker, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _DatabaseSyncMarkerCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class InstanceStateMapper extends SubClassMapperBase<InstanceState> {
  InstanceStateMapper._();

  static InstanceStateMapper? _instance;
  static InstanceStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = InstanceStateMapper._());
      CouchDocumentBaseMapper.ensureInitialized().addSubMapper(_instance!);
      AttachmentInfoMapper.ensureInitialized();
      RevisionsMapper.ensureInitialized();
      RevsInfoMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'InstanceState';

  static String _$instanceUuid(InstanceState v) => v.instanceUuid;
  static const Field<InstanceState, String> _f$instanceUuid = Field(
    'instanceUuid',
    _$instanceUuid,
  );
  static Map<String, String> _$pendingMarkerRepairs(InstanceState v) =>
      v.pendingMarkerRepairs;
  static const Field<InstanceState, Map<String, String>>
  _f$pendingMarkerRepairs = Field(
    'pendingMarkerRepairs',
    _$pendingMarkerRepairs,
  );
  static String? _$id(InstanceState v) => v.id;
  static const Field<InstanceState, String> _f$id = Field(
    'id',
    _$id,
    key: r'_id',
  );
  static String? _$rev(InstanceState v) => v.rev;
  static const Field<InstanceState, String> _f$rev = Field(
    'rev',
    _$rev,
    key: r'_rev',
    opt: true,
  );
  static Map<String, AttachmentInfo>? _$attachments(InstanceState v) =>
      v.attachments;
  static const Field<InstanceState, Map<String, AttachmentInfo>>
  _f$attachments = Field(
    'attachments',
    _$attachments,
    key: r'_attachments',
    opt: true,
  );
  static Revisions? _$revisions(InstanceState v) => v.revisions;
  static const Field<InstanceState, Revisions> _f$revisions = Field(
    'revisions',
    _$revisions,
    key: r'_revisions',
    opt: true,
  );
  static List<RevsInfo>? _$revsInfo(InstanceState v) => v.revsInfo;
  static const Field<InstanceState, List<RevsInfo>> _f$revsInfo = Field(
    'revsInfo',
    _$revsInfo,
    key: r'_revs_info',
    opt: true,
  );
  static bool _$deleted(InstanceState v) => v.deleted;
  static const Field<InstanceState, bool> _f$deleted = Field(
    'deleted',
    _$deleted,
    key: r'_deleted',
    opt: true,
    def: false,
  );
  static Map<String, dynamic> _$unmappedProps(InstanceState v) =>
      v.unmappedProps;
  static const Field<InstanceState, Map<String, dynamic>> _f$unmappedProps =
      Field('unmappedProps', _$unmappedProps, opt: true, def: const {});

  @override
  final MappableFields<InstanceState> fields = const {
    #instanceUuid: _f$instanceUuid,
    #pendingMarkerRepairs: _f$pendingMarkerRepairs,
    #id: _f$id,
    #rev: _f$rev,
    #attachments: _f$attachments,
    #revisions: _f$revisions,
    #revsInfo: _f$revsInfo,
    #deleted: _f$deleted,
    #unmappedProps: _f$unmappedProps,
  };
  @override
  final bool ignoreNull = true;

  @override
  final String discriminatorKey = '!doc_type';
  @override
  final dynamic discriminatorValue = '!instance_state';
  @override
  late final ClassMapperBase superMapper =
      CouchDocumentBaseMapper.ensureInitialized();

  @override
  final MappingHook superHook = const ChainedHook([
    CouchDocumentBaseRawHook(),
    UnmappedPropertiesHook('unmappedProps'),
  ]);

  static InstanceState _instantiate(DecodingData data) {
    return InstanceState(
      instanceUuid: data.dec(_f$instanceUuid),
      pendingMarkerRepairs: data.dec(_f$pendingMarkerRepairs),
      id: data.dec(_f$id),
      rev: data.dec(_f$rev),
      attachments: data.dec(_f$attachments),
      revisions: data.dec(_f$revisions),
      revsInfo: data.dec(_f$revsInfo),
      deleted: data.dec(_f$deleted),
      unmappedProps: data.dec(_f$unmappedProps),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static InstanceState fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<InstanceState>(map);
  }

  static InstanceState fromJson(String json) {
    return ensureInitialized().decodeJson<InstanceState>(json);
  }
}

mixin InstanceStateMappable {
  String toJson() {
    return InstanceStateMapper.ensureInitialized().encodeJson<InstanceState>(
      this as InstanceState,
    );
  }

  Map<String, dynamic> toMap() {
    return InstanceStateMapper.ensureInitialized().encodeMap<InstanceState>(
      this as InstanceState,
    );
  }

  InstanceStateCopyWith<InstanceState, InstanceState, InstanceState>
  get copyWith => _InstanceStateCopyWithImpl<InstanceState, InstanceState>(
    this as InstanceState,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return InstanceStateMapper.ensureInitialized().stringifyValue(
      this as InstanceState,
    );
  }

  @override
  bool operator ==(Object other) {
    return InstanceStateMapper.ensureInitialized().equalsValue(
      this as InstanceState,
      other,
    );
  }

  @override
  int get hashCode {
    return InstanceStateMapper.ensureInitialized().hashValue(
      this as InstanceState,
    );
  }
}

extension InstanceStateValueCopy<$R, $Out>
    on ObjectCopyWith<$R, InstanceState, $Out> {
  InstanceStateCopyWith<$R, InstanceState, $Out> get $asInstanceState =>
      $base.as((v, t, t2) => _InstanceStateCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class InstanceStateCopyWith<$R, $In extends InstanceState, $Out>
    implements CouchDocumentBaseCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get pendingMarkerRepairs;
  @override
  MapCopyWith<
    $R,
    String,
    AttachmentInfo,
    AttachmentInfoCopyWith<$R, AttachmentInfo, AttachmentInfo>
  >?
  get attachments;
  @override
  RevisionsCopyWith<$R, Revisions, Revisions>? get revisions;
  @override
  ListCopyWith<$R, RevsInfo, RevsInfoCopyWith<$R, RevsInfo, RevsInfo>>?
  get revsInfo;
  @override
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>?>
  get unmappedProps;
  @override
  $R call({
    String? instanceUuid,
    Map<String, String>? pendingMarkerRepairs,
    String? id,
    String? rev,
    Map<String, AttachmentInfo>? attachments,
    Revisions? revisions,
    List<RevsInfo>? revsInfo,
    bool? deleted,
    Map<String, dynamic>? unmappedProps,
  });
  InstanceStateCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _InstanceStateCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, InstanceState, $Out>
    implements InstanceStateCopyWith<$R, InstanceState, $Out> {
  _InstanceStateCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<InstanceState> $mapper =
      InstanceStateMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get pendingMarkerRepairs => MapCopyWith(
    $value.pendingMarkerRepairs,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(pendingMarkerRepairs: v),
  );
  @override
  MapCopyWith<
    $R,
    String,
    AttachmentInfo,
    AttachmentInfoCopyWith<$R, AttachmentInfo, AttachmentInfo>
  >?
  get attachments => $value.attachments != null
      ? MapCopyWith(
          $value.attachments!,
          (v, t) => v.copyWith.$chain(t),
          (v) => call(attachments: v),
        )
      : null;
  @override
  RevisionsCopyWith<$R, Revisions, Revisions>? get revisions =>
      $value.revisions?.copyWith.$chain((v) => call(revisions: v));
  @override
  ListCopyWith<$R, RevsInfo, RevsInfoCopyWith<$R, RevsInfo, RevsInfo>>?
  get revsInfo => $value.revsInfo != null
      ? ListCopyWith(
          $value.revsInfo!,
          (v, t) => v.copyWith.$chain(t),
          (v) => call(revsInfo: v),
        )
      : null;
  @override
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>?>
  get unmappedProps => MapCopyWith(
    $value.unmappedProps,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(unmappedProps: v),
  );
  @override
  $R call({
    String? instanceUuid,
    Map<String, String>? pendingMarkerRepairs,
    Object? id = $none,
    Object? rev = $none,
    Object? attachments = $none,
    Object? revisions = $none,
    Object? revsInfo = $none,
    bool? deleted,
    Map<String, dynamic>? unmappedProps,
  }) => $apply(
    FieldCopyWithData({
      if (instanceUuid != null) #instanceUuid: instanceUuid,
      if (pendingMarkerRepairs != null)
        #pendingMarkerRepairs: pendingMarkerRepairs,
      if (id != $none) #id: id,
      if (rev != $none) #rev: rev,
      if (attachments != $none) #attachments: attachments,
      if (revisions != $none) #revisions: revisions,
      if (revsInfo != $none) #revsInfo: revsInfo,
      if (deleted != null) #deleted: deleted,
      if (unmappedProps != null) #unmappedProps: unmappedProps,
    }),
  );
  @override
  InstanceState $make(CopyWithData data) => InstanceState(
    instanceUuid: data.get(#instanceUuid, or: $value.instanceUuid),
    pendingMarkerRepairs: data.get(
      #pendingMarkerRepairs,
      or: $value.pendingMarkerRepairs,
    ),
    id: data.get(#id, or: $value.id),
    rev: data.get(#rev, or: $value.rev),
    attachments: data.get(#attachments, or: $value.attachments),
    revisions: data.get(#revisions, or: $value.revisions),
    revsInfo: data.get(#revsInfo, or: $value.revsInfo),
    deleted: data.get(#deleted, or: $value.deleted),
    unmappedProps: data.get(#unmappedProps, or: $value.unmappedProps),
  );

  @override
  InstanceStateCopyWith<$R2, InstanceState, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _InstanceStateCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

