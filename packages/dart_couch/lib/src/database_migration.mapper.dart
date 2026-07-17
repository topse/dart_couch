// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'database_migration.dart';

class MigrationDocumentMapper extends SubClassMapperBase<MigrationDocument> {
  MigrationDocumentMapper._();

  static MigrationDocumentMapper? _instance;
  static MigrationDocumentMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = MigrationDocumentMapper._());
      CouchDocumentBaseMapper.ensureInitialized().addSubMapper(_instance!);
      AttachmentInfoMapper.ensureInitialized();
      RevisionsMapper.ensureInitialized();
      RevsInfoMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'MigrationDocument';

  static int _$version(MigrationDocument v) => v.version;
  static const Field<MigrationDocument, int> _f$version = Field(
    'version',
    _$version,
  );
  static String? _$id(MigrationDocument v) => v.id;
  static const Field<MigrationDocument, String> _f$id = Field(
    'id',
    _$id,
    key: r'_id',
  );
  static String? _$rev(MigrationDocument v) => v.rev;
  static const Field<MigrationDocument, String> _f$rev = Field(
    'rev',
    _$rev,
    key: r'_rev',
    opt: true,
  );
  static Map<String, AttachmentInfo>? _$attachments(MigrationDocument v) =>
      v.attachments;
  static const Field<MigrationDocument, Map<String, AttachmentInfo>>
  _f$attachments = Field(
    'attachments',
    _$attachments,
    key: r'_attachments',
    opt: true,
  );
  static Revisions? _$revisions(MigrationDocument v) => v.revisions;
  static const Field<MigrationDocument, Revisions> _f$revisions = Field(
    'revisions',
    _$revisions,
    key: r'_revisions',
    opt: true,
  );
  static List<RevsInfo>? _$revsInfo(MigrationDocument v) => v.revsInfo;
  static const Field<MigrationDocument, List<RevsInfo>> _f$revsInfo = Field(
    'revsInfo',
    _$revsInfo,
    key: r'_revs_info',
    opt: true,
  );
  static bool _$deleted(MigrationDocument v) => v.deleted;
  static const Field<MigrationDocument, bool> _f$deleted = Field(
    'deleted',
    _$deleted,
    key: r'_deleted',
    opt: true,
    def: false,
  );
  static Map<String, dynamic> _$unmappedProps(MigrationDocument v) =>
      v.unmappedProps;
  static const Field<MigrationDocument, Map<String, dynamic>> _f$unmappedProps =
      Field('unmappedProps', _$unmappedProps, opt: true, def: const {});

  @override
  final MappableFields<MigrationDocument> fields = const {
    #version: _f$version,
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
  final dynamic discriminatorValue = '!migration_document';
  @override
  late final ClassMapperBase superMapper =
      CouchDocumentBaseMapper.ensureInitialized();

  @override
  final MappingHook superHook = const ChainedHook([
    CouchDocumentBaseRawHook(),
    UnmappedPropertiesHook('unmappedProps'),
  ]);

  static MigrationDocument _instantiate(DecodingData data) {
    return MigrationDocument(
      version: data.dec(_f$version),
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

  static MigrationDocument fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<MigrationDocument>(map);
  }

  static MigrationDocument fromJson(String json) {
    return ensureInitialized().decodeJson<MigrationDocument>(json);
  }
}

mixin MigrationDocumentMappable {
  String toJson() {
    return MigrationDocumentMapper.ensureInitialized()
        .encodeJson<MigrationDocument>(this as MigrationDocument);
  }

  Map<String, dynamic> toMap() {
    return MigrationDocumentMapper.ensureInitialized()
        .encodeMap<MigrationDocument>(this as MigrationDocument);
  }

  MigrationDocumentCopyWith<
    MigrationDocument,
    MigrationDocument,
    MigrationDocument
  >
  get copyWith =>
      _MigrationDocumentCopyWithImpl<MigrationDocument, MigrationDocument>(
        this as MigrationDocument,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return MigrationDocumentMapper.ensureInitialized().stringifyValue(
      this as MigrationDocument,
    );
  }

  @override
  bool operator ==(Object other) {
    return MigrationDocumentMapper.ensureInitialized().equalsValue(
      this as MigrationDocument,
      other,
    );
  }

  @override
  int get hashCode {
    return MigrationDocumentMapper.ensureInitialized().hashValue(
      this as MigrationDocument,
    );
  }
}

extension MigrationDocumentValueCopy<$R, $Out>
    on ObjectCopyWith<$R, MigrationDocument, $Out> {
  MigrationDocumentCopyWith<$R, MigrationDocument, $Out>
  get $asMigrationDocument => $base.as(
    (v, t, t2) => _MigrationDocumentCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class MigrationDocumentCopyWith<
  $R,
  $In extends MigrationDocument,
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
    int? version,
    String? id,
    String? rev,
    Map<String, AttachmentInfo>? attachments,
    Revisions? revisions,
    List<RevsInfo>? revsInfo,
    bool? deleted,
    Map<String, dynamic>? unmappedProps,
  });
  MigrationDocumentCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _MigrationDocumentCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, MigrationDocument, $Out>
    implements MigrationDocumentCopyWith<$R, MigrationDocument, $Out> {
  _MigrationDocumentCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<MigrationDocument> $mapper =
      MigrationDocumentMapper.ensureInitialized();
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
    int? version,
    Object? id = $none,
    Object? rev = $none,
    Object? attachments = $none,
    Object? revisions = $none,
    Object? revsInfo = $none,
    bool? deleted,
    Map<String, dynamic>? unmappedProps,
  }) => $apply(
    FieldCopyWithData({
      if (version != null) #version: version,
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
  MigrationDocument $make(CopyWithData data) => MigrationDocument(
    version: data.get(#version, or: $value.version),
    id: data.get(#id, or: $value.id),
    rev: data.get(#rev, or: $value.rev),
    attachments: data.get(#attachments, or: $value.attachments),
    revisions: data.get(#revisions, or: $value.revisions),
    revsInfo: data.get(#revsInfo, or: $value.revsInfo),
    deleted: data.get(#deleted, or: $value.deleted),
    unmappedProps: data.get(#unmappedProps, or: $value.unmappedProps),
  );

  @override
  MigrationDocumentCopyWith<$R2, MigrationDocument, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _MigrationDocumentCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

