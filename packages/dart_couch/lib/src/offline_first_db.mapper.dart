// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'offline_first_db.dart';

class LocalMigrationDocumentMapper
    extends SubClassMapperBase<LocalMigrationDocument> {
  LocalMigrationDocumentMapper._();

  static LocalMigrationDocumentMapper? _instance;
  static LocalMigrationDocumentMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LocalMigrationDocumentMapper._());
      CouchDocumentBaseMapper.ensureInitialized().addSubMapper(_instance!);
      AttachmentInfoMapper.ensureInitialized();
      RevisionsMapper.ensureInitialized();
      RevsInfoMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'LocalMigrationDocument';

  static int _$lastSeq(LocalMigrationDocument v) => v.lastSeq;
  static const Field<LocalMigrationDocument, int> _f$lastSeq = Field(
    'lastSeq',
    _$lastSeq,
    key: r'last_seq',
  );
  static String? _$id(LocalMigrationDocument v) => v.id;
  static const Field<LocalMigrationDocument, String> _f$id = Field(
    'id',
    _$id,
    key: r'_id',
    opt: true,
    def: '_local/migration_state',
  );
  static String? _$rev(LocalMigrationDocument v) => v.rev;
  static const Field<LocalMigrationDocument, String> _f$rev = Field(
    'rev',
    _$rev,
    key: r'_rev',
    opt: true,
  );
  static Map<String, AttachmentInfo>? _$attachments(LocalMigrationDocument v) =>
      v.attachments;
  static const Field<LocalMigrationDocument, Map<String, AttachmentInfo>>
  _f$attachments = Field(
    'attachments',
    _$attachments,
    key: r'_attachments',
    opt: true,
  );
  static Revisions? _$revisions(LocalMigrationDocument v) => v.revisions;
  static const Field<LocalMigrationDocument, Revisions> _f$revisions = Field(
    'revisions',
    _$revisions,
    key: r'_revisions',
    opt: true,
  );
  static List<RevsInfo>? _$revsInfo(LocalMigrationDocument v) => v.revsInfo;
  static const Field<LocalMigrationDocument, List<RevsInfo>> _f$revsInfo =
      Field('revsInfo', _$revsInfo, key: r'_revs_info', opt: true);
  static bool _$deleted(LocalMigrationDocument v) => v.deleted;
  static const Field<LocalMigrationDocument, bool> _f$deleted = Field(
    'deleted',
    _$deleted,
    key: r'_deleted',
    opt: true,
    def: false,
  );
  static Map<String, dynamic> _$unmappedProps(LocalMigrationDocument v) =>
      v.unmappedProps;
  static const Field<LocalMigrationDocument, Map<String, dynamic>>
  _f$unmappedProps = Field(
    'unmappedProps',
    _$unmappedProps,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<LocalMigrationDocument> fields = const {
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
  final dynamic discriminatorValue = '!local_migration_state';
  @override
  late final ClassMapperBase superMapper =
      CouchDocumentBaseMapper.ensureInitialized();

  @override
  final MappingHook superHook = const ChainedHook([
    CouchDocumentBaseRawHook(),
    UnmappedPropertiesHook('unmappedProps'),
  ]);

  static LocalMigrationDocument _instantiate(DecodingData data) {
    return LocalMigrationDocument(
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

  static LocalMigrationDocument fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LocalMigrationDocument>(map);
  }

  static LocalMigrationDocument fromJson(String json) {
    return ensureInitialized().decodeJson<LocalMigrationDocument>(json);
  }
}

mixin LocalMigrationDocumentMappable {
  String toJson() {
    return LocalMigrationDocumentMapper.ensureInitialized()
        .encodeJson<LocalMigrationDocument>(this as LocalMigrationDocument);
  }

  Map<String, dynamic> toMap() {
    return LocalMigrationDocumentMapper.ensureInitialized()
        .encodeMap<LocalMigrationDocument>(this as LocalMigrationDocument);
  }

  LocalMigrationDocumentCopyWith<
    LocalMigrationDocument,
    LocalMigrationDocument,
    LocalMigrationDocument
  >
  get copyWith =>
      _LocalMigrationDocumentCopyWithImpl<
        LocalMigrationDocument,
        LocalMigrationDocument
      >(this as LocalMigrationDocument, $identity, $identity);
  @override
  String toString() {
    return LocalMigrationDocumentMapper.ensureInitialized().stringifyValue(
      this as LocalMigrationDocument,
    );
  }

  @override
  bool operator ==(Object other) {
    return LocalMigrationDocumentMapper.ensureInitialized().equalsValue(
      this as LocalMigrationDocument,
      other,
    );
  }

  @override
  int get hashCode {
    return LocalMigrationDocumentMapper.ensureInitialized().hashValue(
      this as LocalMigrationDocument,
    );
  }
}

extension LocalMigrationDocumentValueCopy<$R, $Out>
    on ObjectCopyWith<$R, LocalMigrationDocument, $Out> {
  LocalMigrationDocumentCopyWith<$R, LocalMigrationDocument, $Out>
  get $asLocalMigrationDocument => $base.as(
    (v, t, t2) => _LocalMigrationDocumentCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class LocalMigrationDocumentCopyWith<
  $R,
  $In extends LocalMigrationDocument,
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
    int? lastSeq,
    String? id,
    String? rev,
    Map<String, AttachmentInfo>? attachments,
    Revisions? revisions,
    List<RevsInfo>? revsInfo,
    bool? deleted,
    Map<String, dynamic>? unmappedProps,
  });
  LocalMigrationDocumentCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _LocalMigrationDocumentCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LocalMigrationDocument, $Out>
    implements
        LocalMigrationDocumentCopyWith<$R, LocalMigrationDocument, $Out> {
  _LocalMigrationDocumentCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LocalMigrationDocument> $mapper =
      LocalMigrationDocumentMapper.ensureInitialized();
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
    int? lastSeq,
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
  LocalMigrationDocument $make(CopyWithData data) => LocalMigrationDocument(
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
  LocalMigrationDocumentCopyWith<$R2, LocalMigrationDocument, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _LocalMigrationDocumentCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

