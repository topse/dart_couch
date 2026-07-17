// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'multi_inheritance_test.dart';

class BaseMapper extends SubClassMapperBase<Base> {
  BaseMapper._();

  static BaseMapper? _instance;
  static BaseMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = BaseMapper._());
      CouchDocumentBaseMapper.ensureInitialized().addSubMapper(_instance!);
      AttachmentInfoMapper.ensureInitialized();
      RevisionsMapper.ensureInitialized();
      RevsInfoMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'Base';

  static String _$name(Base v) => v.name;
  static const Field<Base, String> _f$name = Field('name', _$name);
  static String? _$id(Base v) => v.id;
  static const Field<Base, String> _f$id = Field(
    'id',
    _$id,
    key: r'_id',
    opt: true,
  );
  static Map<String, AttachmentInfo>? _$attachments(Base v) => v.attachments;
  static const Field<Base, Map<String, AttachmentInfo>> _f$attachments = Field(
    'attachments',
    _$attachments,
    key: r'_attachments',
    opt: true,
  );
  static bool _$deleted(Base v) => v.deleted;
  static const Field<Base, bool> _f$deleted = Field(
    'deleted',
    _$deleted,
    key: r'_deleted',
    opt: true,
    def: false,
  );
  static String? _$rev(Base v) => v.rev;
  static const Field<Base, String> _f$rev = Field(
    'rev',
    _$rev,
    key: r'_rev',
    opt: true,
  );
  static Revisions? _$revisions(Base v) => v.revisions;
  static const Field<Base, Revisions> _f$revisions = Field(
    'revisions',
    _$revisions,
    key: r'_revisions',
    opt: true,
  );
  static List<RevsInfo>? _$revsInfo(Base v) => v.revsInfo;
  static const Field<Base, List<RevsInfo>> _f$revsInfo = Field(
    'revsInfo',
    _$revsInfo,
    key: r'_revs_info',
    opt: true,
  );
  static Map<String, dynamic> _$unmappedProps(Base v) => v.unmappedProps;
  static const Field<Base, Map<String, dynamic>> _f$unmappedProps = Field(
    'unmappedProps',
    _$unmappedProps,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<Base> fields = const {
    #name: _f$name,
    #id: _f$id,
    #attachments: _f$attachments,
    #deleted: _f$deleted,
    #rev: _f$rev,
    #revisions: _f$revisions,
    #revsInfo: _f$revsInfo,
    #unmappedProps: _f$unmappedProps,
  };
  @override
  final bool ignoreNull = true;

  @override
  final String discriminatorKey = '!doc_type';
  @override
  final dynamic discriminatorValue = 'Base';
  @override
  late final ClassMapperBase superMapper =
      CouchDocumentBaseMapper.ensureInitialized();

  @override
  final MappingHook superHook = const ChainedHook([
    CouchDocumentBaseRawHook(),
    UnmappedPropertiesHook('unmappedProps'),
  ]);

  static Base _instantiate(DecodingData data) {
    return Base(
      name: data.dec(_f$name),
      id: data.dec(_f$id),
      attachments: data.dec(_f$attachments),
      deleted: data.dec(_f$deleted),
      rev: data.dec(_f$rev),
      revisions: data.dec(_f$revisions),
      revsInfo: data.dec(_f$revsInfo),
      unmappedProps: data.dec(_f$unmappedProps),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Base fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Base>(map);
  }

  static Base fromJson(String json) {
    return ensureInitialized().decodeJson<Base>(json);
  }
}

mixin BaseMappable {
  String toJson() {
    return BaseMapper.ensureInitialized().encodeJson<Base>(this as Base);
  }

  Map<String, dynamic> toMap() {
    return BaseMapper.ensureInitialized().encodeMap<Base>(this as Base);
  }

  BaseCopyWith<Base, Base, Base> get copyWith =>
      _BaseCopyWithImpl<Base, Base>(this as Base, $identity, $identity);
  @override
  String toString() {
    return BaseMapper.ensureInitialized().stringifyValue(this as Base);
  }

  @override
  bool operator ==(Object other) {
    return BaseMapper.ensureInitialized().equalsValue(this as Base, other);
  }

  @override
  int get hashCode {
    return BaseMapper.ensureInitialized().hashValue(this as Base);
  }
}

extension BaseValueCopy<$R, $Out> on ObjectCopyWith<$R, Base, $Out> {
  BaseCopyWith<$R, Base, $Out> get $asBase =>
      $base.as((v, t, t2) => _BaseCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class BaseCopyWith<$R, $In extends Base, $Out>
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
    String? name,
    String? id,
    Map<String, AttachmentInfo>? attachments,
    bool? deleted,
    String? rev,
    Revisions? revisions,
    List<RevsInfo>? revsInfo,
    Map<String, dynamic>? unmappedProps,
  });
  BaseCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _BaseCopyWithImpl<$R, $Out> extends ClassCopyWithBase<$R, Base, $Out>
    implements BaseCopyWith<$R, Base, $Out> {
  _BaseCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Base> $mapper = BaseMapper.ensureInitialized();
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
    String? name,
    Object? id = $none,
    Object? attachments = $none,
    bool? deleted,
    Object? rev = $none,
    Object? revisions = $none,
    Object? revsInfo = $none,
    Map<String, dynamic>? unmappedProps,
  }) => $apply(
    FieldCopyWithData({
      if (name != null) #name: name,
      if (id != $none) #id: id,
      if (attachments != $none) #attachments: attachments,
      if (deleted != null) #deleted: deleted,
      if (rev != $none) #rev: rev,
      if (revisions != $none) #revisions: revisions,
      if (revsInfo != $none) #revsInfo: revsInfo,
      if (unmappedProps != null) #unmappedProps: unmappedProps,
    }),
  );
  @override
  Base $make(CopyWithData data) => Base(
    name: data.get(#name, or: $value.name),
    id: data.get(#id, or: $value.id),
    attachments: data.get(#attachments, or: $value.attachments),
    deleted: data.get(#deleted, or: $value.deleted),
    rev: data.get(#rev, or: $value.rev),
    revisions: data.get(#revisions, or: $value.revisions),
    revsInfo: data.get(#revsInfo, or: $value.revsInfo),
    unmappedProps: data.get(#unmappedProps, or: $value.unmappedProps),
  );

  @override
  BaseCopyWith<$R2, Base, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _BaseCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

