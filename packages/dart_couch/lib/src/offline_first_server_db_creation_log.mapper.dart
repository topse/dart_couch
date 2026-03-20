// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'offline_first_server_db_creation_log.dart';

class EntryModeMapper extends EnumMapper<EntryMode> {
  EntryModeMapper._();

  static EntryModeMapper? _instance;
  static EntryModeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = EntryModeMapper._());
    }
    return _instance!;
  }

  static EntryMode fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  EntryMode decode(dynamic value) {
    switch (value) {
      case r'created':
        return EntryMode.created;
      case r'deleted':
        return EntryMode.deleted;
      case r'recreated':
        return EntryMode.recreated;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(EntryMode self) {
    switch (self) {
      case EntryMode.created:
        return r'created';
      case EntryMode.deleted:
        return r'deleted';
      case EntryMode.recreated:
        return r'recreated';
    }
  }
}

extension EntryModeMapperExtension on EntryMode {
  String toValue() {
    EntryModeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<EntryMode>(this) as String;
  }
}

class OfflineFirstServerDbCreationLogMapper
    extends SubClassMapperBase<OfflineFirstServerDbCreationLog> {
  OfflineFirstServerDbCreationLogMapper._();

  static OfflineFirstServerDbCreationLogMapper? _instance;
  static OfflineFirstServerDbCreationLogMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = OfflineFirstServerDbCreationLogMapper._(),
      );
      CouchDocumentBaseMapper.ensureInitialized().addSubMapper(_instance!);
      OfflineFirstServerDbCreationLogEntryMapper.ensureInitialized();
      AttachmentInfoMapper.ensureInitialized();
      RevisionsMapper.ensureInitialized();
      RevsInfoMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'OfflineFirstServerDbCreationLog';

  static List<OfflineFirstServerDbCreationLogEntry> _$entries(
    OfflineFirstServerDbCreationLog v,
  ) => v.entries;
  static const Field<
    OfflineFirstServerDbCreationLog,
    List<OfflineFirstServerDbCreationLogEntry>
  >
  _f$entries = Field('entries', _$entries);
  static String? _$id(OfflineFirstServerDbCreationLog v) => v.id;
  static const Field<OfflineFirstServerDbCreationLog, String> _f$id = Field(
    'id',
    _$id,
    key: r'_id',
  );
  static String? _$rev(OfflineFirstServerDbCreationLog v) => v.rev;
  static const Field<OfflineFirstServerDbCreationLog, String> _f$rev = Field(
    'rev',
    _$rev,
    key: r'_rev',
    opt: true,
  );
  static Map<String, AttachmentInfo>? _$attachments(
    OfflineFirstServerDbCreationLog v,
  ) => v.attachments;
  static const Field<
    OfflineFirstServerDbCreationLog,
    Map<String, AttachmentInfo>
  >
  _f$attachments = Field(
    'attachments',
    _$attachments,
    key: r'_attachments',
    opt: true,
  );
  static Revisions? _$revisions(OfflineFirstServerDbCreationLog v) =>
      v.revisions;
  static const Field<OfflineFirstServerDbCreationLog, Revisions> _f$revisions =
      Field('revisions', _$revisions, key: r'_revisions', opt: true);
  static List<RevsInfo>? _$revsInfo(OfflineFirstServerDbCreationLog v) =>
      v.revsInfo;
  static const Field<OfflineFirstServerDbCreationLog, List<RevsInfo>>
  _f$revsInfo = Field('revsInfo', _$revsInfo, key: r'_revs_info', opt: true);
  static bool _$deleted(OfflineFirstServerDbCreationLog v) => v.deleted;
  static const Field<OfflineFirstServerDbCreationLog, bool> _f$deleted = Field(
    'deleted',
    _$deleted,
    key: r'_deleted',
    opt: true,
    def: false,
  );
  static Map<String, dynamic> _$unmappedProps(
    OfflineFirstServerDbCreationLog v,
  ) => v.unmappedProps;
  static const Field<OfflineFirstServerDbCreationLog, Map<String, dynamic>>
  _f$unmappedProps = Field(
    'unmappedProps',
    _$unmappedProps,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<OfflineFirstServerDbCreationLog> fields = const {
    #entries: _f$entries,
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
  final dynamic discriminatorValue = 'offline_first_server_db_creation_log';
  @override
  late final ClassMapperBase superMapper =
      CouchDocumentBaseMapper.ensureInitialized();

  @override
  final MappingHook superHook = const ChainedHook([
    CouchDocumentBaseRawHook(),
    UnmappedPropertiesHook('unmappedProps'),
  ]);

  static OfflineFirstServerDbCreationLog _instantiate(DecodingData data) {
    return OfflineFirstServerDbCreationLog(
      entries: data.dec(_f$entries),
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

  static OfflineFirstServerDbCreationLog fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<OfflineFirstServerDbCreationLog>(map);
  }

  static OfflineFirstServerDbCreationLog fromJson(String json) {
    return ensureInitialized().decodeJson<OfflineFirstServerDbCreationLog>(
      json,
    );
  }
}

mixin OfflineFirstServerDbCreationLogMappable {
  String toJson() {
    return OfflineFirstServerDbCreationLogMapper.ensureInitialized()
        .encodeJson<OfflineFirstServerDbCreationLog>(
          this as OfflineFirstServerDbCreationLog,
        );
  }

  Map<String, dynamic> toMap() {
    return OfflineFirstServerDbCreationLogMapper.ensureInitialized()
        .encodeMap<OfflineFirstServerDbCreationLog>(
          this as OfflineFirstServerDbCreationLog,
        );
  }

  OfflineFirstServerDbCreationLogCopyWith<
    OfflineFirstServerDbCreationLog,
    OfflineFirstServerDbCreationLog,
    OfflineFirstServerDbCreationLog
  >
  get copyWith =>
      _OfflineFirstServerDbCreationLogCopyWithImpl<
        OfflineFirstServerDbCreationLog,
        OfflineFirstServerDbCreationLog
      >(this as OfflineFirstServerDbCreationLog, $identity, $identity);
  @override
  String toString() {
    return OfflineFirstServerDbCreationLogMapper.ensureInitialized()
        .stringifyValue(this as OfflineFirstServerDbCreationLog);
  }

  @override
  bool operator ==(Object other) {
    return OfflineFirstServerDbCreationLogMapper.ensureInitialized()
        .equalsValue(this as OfflineFirstServerDbCreationLog, other);
  }

  @override
  int get hashCode {
    return OfflineFirstServerDbCreationLogMapper.ensureInitialized().hashValue(
      this as OfflineFirstServerDbCreationLog,
    );
  }
}

extension OfflineFirstServerDbCreationLogValueCopy<$R, $Out>
    on ObjectCopyWith<$R, OfflineFirstServerDbCreationLog, $Out> {
  OfflineFirstServerDbCreationLogCopyWith<
    $R,
    OfflineFirstServerDbCreationLog,
    $Out
  >
  get $asOfflineFirstServerDbCreationLog => $base.as(
    (v, t, t2) =>
        _OfflineFirstServerDbCreationLogCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class OfflineFirstServerDbCreationLogCopyWith<
  $R,
  $In extends OfflineFirstServerDbCreationLog,
  $Out
>
    implements CouchDocumentBaseCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    OfflineFirstServerDbCreationLogEntry,
    OfflineFirstServerDbCreationLogEntryCopyWith<
      $R,
      OfflineFirstServerDbCreationLogEntry,
      OfflineFirstServerDbCreationLogEntry
    >
  >
  get entries;
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
    List<OfflineFirstServerDbCreationLogEntry>? entries,
    String? id,
    String? rev,
    Map<String, AttachmentInfo>? attachments,
    Revisions? revisions,
    List<RevsInfo>? revsInfo,
    bool? deleted,
    Map<String, dynamic>? unmappedProps,
  });
  OfflineFirstServerDbCreationLogCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _OfflineFirstServerDbCreationLogCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, OfflineFirstServerDbCreationLog, $Out>
    implements
        OfflineFirstServerDbCreationLogCopyWith<
          $R,
          OfflineFirstServerDbCreationLog,
          $Out
        > {
  _OfflineFirstServerDbCreationLogCopyWithImpl(
    super.value,
    super.then,
    super.then2,
  );

  @override
  late final ClassMapperBase<OfflineFirstServerDbCreationLog> $mapper =
      OfflineFirstServerDbCreationLogMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    OfflineFirstServerDbCreationLogEntry,
    OfflineFirstServerDbCreationLogEntryCopyWith<
      $R,
      OfflineFirstServerDbCreationLogEntry,
      OfflineFirstServerDbCreationLogEntry
    >
  >
  get entries => ListCopyWith(
    $value.entries,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(entries: v),
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
    List<OfflineFirstServerDbCreationLogEntry>? entries,
    Object? id = $none,
    Object? rev = $none,
    Object? attachments = $none,
    Object? revisions = $none,
    Object? revsInfo = $none,
    bool? deleted,
    Map<String, dynamic>? unmappedProps,
  }) => $apply(
    FieldCopyWithData({
      if (entries != null) #entries: entries,
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
  OfflineFirstServerDbCreationLog $make(CopyWithData data) =>
      OfflineFirstServerDbCreationLog(
        entries: data.get(#entries, or: $value.entries),
        id: data.get(#id, or: $value.id),
        rev: data.get(#rev, or: $value.rev),
        attachments: data.get(#attachments, or: $value.attachments),
        revisions: data.get(#revisions, or: $value.revisions),
        revsInfo: data.get(#revsInfo, or: $value.revsInfo),
        deleted: data.get(#deleted, or: $value.deleted),
        unmappedProps: data.get(#unmappedProps, or: $value.unmappedProps),
      );

  @override
  OfflineFirstServerDbCreationLogCopyWith<
    $R2,
    OfflineFirstServerDbCreationLog,
    $Out2
  >
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _OfflineFirstServerDbCreationLogCopyWithImpl<$R2, $Out2>(
        $value,
        $cast,
        t,
      );
}

class OfflineFirstServerDbCreationLogEntryMapper
    extends ClassMapperBase<OfflineFirstServerDbCreationLogEntry> {
  OfflineFirstServerDbCreationLogEntryMapper._();

  static OfflineFirstServerDbCreationLogEntryMapper? _instance;
  static OfflineFirstServerDbCreationLogEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = OfflineFirstServerDbCreationLogEntryMapper._(),
      );
      EntryModeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'OfflineFirstServerDbCreationLogEntry';

  static String _$name(OfflineFirstServerDbCreationLogEntry v) => v.name;
  static const Field<OfflineFirstServerDbCreationLogEntry, String> _f$name =
      Field('name', _$name);
  static EntryMode _$mode(OfflineFirstServerDbCreationLogEntry v) => v.mode;
  static const Field<OfflineFirstServerDbCreationLogEntry, EntryMode> _f$mode =
      Field('mode', _$mode);

  @override
  final MappableFields<OfflineFirstServerDbCreationLogEntry> fields = const {
    #name: _f$name,
    #mode: _f$mode,
  };

  static OfflineFirstServerDbCreationLogEntry _instantiate(DecodingData data) {
    return OfflineFirstServerDbCreationLogEntry(
      name: data.dec(_f$name),
      mode: data.dec(_f$mode),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static OfflineFirstServerDbCreationLogEntry fromMap(
    Map<String, dynamic> map,
  ) {
    return ensureInitialized().decodeMap<OfflineFirstServerDbCreationLogEntry>(
      map,
    );
  }

  static OfflineFirstServerDbCreationLogEntry fromJson(String json) {
    return ensureInitialized().decodeJson<OfflineFirstServerDbCreationLogEntry>(
      json,
    );
  }
}

mixin OfflineFirstServerDbCreationLogEntryMappable {
  String toJson() {
    return OfflineFirstServerDbCreationLogEntryMapper.ensureInitialized()
        .encodeJson<OfflineFirstServerDbCreationLogEntry>(
          this as OfflineFirstServerDbCreationLogEntry,
        );
  }

  Map<String, dynamic> toMap() {
    return OfflineFirstServerDbCreationLogEntryMapper.ensureInitialized()
        .encodeMap<OfflineFirstServerDbCreationLogEntry>(
          this as OfflineFirstServerDbCreationLogEntry,
        );
  }

  OfflineFirstServerDbCreationLogEntryCopyWith<
    OfflineFirstServerDbCreationLogEntry,
    OfflineFirstServerDbCreationLogEntry,
    OfflineFirstServerDbCreationLogEntry
  >
  get copyWith =>
      _OfflineFirstServerDbCreationLogEntryCopyWithImpl<
        OfflineFirstServerDbCreationLogEntry,
        OfflineFirstServerDbCreationLogEntry
      >(this as OfflineFirstServerDbCreationLogEntry, $identity, $identity);
  @override
  String toString() {
    return OfflineFirstServerDbCreationLogEntryMapper.ensureInitialized()
        .stringifyValue(this as OfflineFirstServerDbCreationLogEntry);
  }

  @override
  bool operator ==(Object other) {
    return OfflineFirstServerDbCreationLogEntryMapper.ensureInitialized()
        .equalsValue(this as OfflineFirstServerDbCreationLogEntry, other);
  }

  @override
  int get hashCode {
    return OfflineFirstServerDbCreationLogEntryMapper.ensureInitialized()
        .hashValue(this as OfflineFirstServerDbCreationLogEntry);
  }
}

extension OfflineFirstServerDbCreationLogEntryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, OfflineFirstServerDbCreationLogEntry, $Out> {
  OfflineFirstServerDbCreationLogEntryCopyWith<
    $R,
    OfflineFirstServerDbCreationLogEntry,
    $Out
  >
  get $asOfflineFirstServerDbCreationLogEntry => $base.as(
    (v, t, t2) =>
        _OfflineFirstServerDbCreationLogEntryCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class OfflineFirstServerDbCreationLogEntryCopyWith<
  $R,
  $In extends OfflineFirstServerDbCreationLogEntry,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? name, EntryMode? mode});
  OfflineFirstServerDbCreationLogEntryCopyWith<$R2, $In, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _OfflineFirstServerDbCreationLogEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, OfflineFirstServerDbCreationLogEntry, $Out>
    implements
        OfflineFirstServerDbCreationLogEntryCopyWith<
          $R,
          OfflineFirstServerDbCreationLogEntry,
          $Out
        > {
  _OfflineFirstServerDbCreationLogEntryCopyWithImpl(
    super.value,
    super.then,
    super.then2,
  );

  @override
  late final ClassMapperBase<OfflineFirstServerDbCreationLogEntry> $mapper =
      OfflineFirstServerDbCreationLogEntryMapper.ensureInitialized();
  @override
  $R call({String? name, EntryMode? mode}) => $apply(
    FieldCopyWithData({
      if (name != null) #name: name,
      if (mode != null) #mode: mode,
    }),
  );
  @override
  OfflineFirstServerDbCreationLogEntry $make(CopyWithData data) =>
      OfflineFirstServerDbCreationLogEntry(
        name: data.get(#name, or: $value.name),
        mode: data.get(#mode, or: $value.mode),
      );

  @override
  OfflineFirstServerDbCreationLogEntryCopyWith<
    $R2,
    OfflineFirstServerDbCreationLogEntry,
    $Out2
  >
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _OfflineFirstServerDbCreationLogEntryCopyWithImpl<$R2, $Out2>(
        $value,
        $cast,
        t,
      );
}

