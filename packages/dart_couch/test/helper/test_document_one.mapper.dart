// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'test_document_one.dart';

class TestDocumentOneMapper extends SubClassMapperBase<TestDocumentOne> {
  TestDocumentOneMapper._();

  static TestDocumentOneMapper? _instance;
  static TestDocumentOneMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TestDocumentOneMapper._());
      CouchDocumentBaseMapper.ensureInitialized().addSubMapper(_instance!);
      AttachmentInfoMapper.ensureInitialized();
      RevisionsMapper.ensureInitialized();
      RevsInfoMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'TestDocumentOne';

  static String _$name(TestDocumentOne v) => v.name;
  static const Field<TestDocumentOne, String> _f$name = Field('name', _$name);
  static String? _$id(TestDocumentOne v) => v.id;
  static const Field<TestDocumentOne, String> _f$id = Field(
    'id',
    _$id,
    key: r'_id',
  );
  static String? _$rev(TestDocumentOne v) => v.rev;
  static const Field<TestDocumentOne, String> _f$rev = Field(
    'rev',
    _$rev,
    key: r'_rev',
    opt: true,
  );
  static Map<String, AttachmentInfo>? _$attachments(TestDocumentOne v) =>
      v.attachments;
  static const Field<TestDocumentOne, Map<String, AttachmentInfo>>
  _f$attachments = Field(
    'attachments',
    _$attachments,
    key: r'_attachments',
    opt: true,
  );
  static Revisions? _$revisions(TestDocumentOne v) => v.revisions;
  static const Field<TestDocumentOne, Revisions> _f$revisions = Field(
    'revisions',
    _$revisions,
    key: r'_revisions',
    opt: true,
  );
  static List<RevsInfo>? _$revsInfo(TestDocumentOne v) => v.revsInfo;
  static const Field<TestDocumentOne, List<RevsInfo>> _f$revsInfo = Field(
    'revsInfo',
    _$revsInfo,
    key: r'_revs_info',
    opt: true,
  );
  static bool _$deleted(TestDocumentOne v) => v.deleted;
  static const Field<TestDocumentOne, bool> _f$deleted = Field(
    'deleted',
    _$deleted,
    key: r'_deleted',
    opt: true,
    def: false,
  );
  static Map<String, dynamic> _$unmappedProps(TestDocumentOne v) =>
      v.unmappedProps;
  static const Field<TestDocumentOne, Map<String, dynamic>> _f$unmappedProps =
      Field('unmappedProps', _$unmappedProps, opt: true, def: const {});

  @override
  final MappableFields<TestDocumentOne> fields = const {
    #name: _f$name,
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
  final dynamic discriminatorValue = 'test_document_one';
  @override
  late final ClassMapperBase superMapper =
      CouchDocumentBaseMapper.ensureInitialized();

  @override
  final MappingHook superHook = const ChainedHook([
    CouchDocumentBaseRawHook(),
    UnmappedPropertiesHook('unmappedProps'),
  ]);

  static TestDocumentOne _instantiate(DecodingData data) {
    return TestDocumentOne(
      name: data.dec(_f$name),
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

  static TestDocumentOne fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TestDocumentOne>(map);
  }

  static TestDocumentOne fromJson(String json) {
    return ensureInitialized().decodeJson<TestDocumentOne>(json);
  }
}

mixin TestDocumentOneMappable {
  String toJson() {
    return TestDocumentOneMapper.ensureInitialized()
        .encodeJson<TestDocumentOne>(this as TestDocumentOne);
  }

  Map<String, dynamic> toMap() {
    return TestDocumentOneMapper.ensureInitialized().encodeMap<TestDocumentOne>(
      this as TestDocumentOne,
    );
  }

  TestDocumentOneCopyWith<TestDocumentOne, TestDocumentOne, TestDocumentOne>
  get copyWith =>
      _TestDocumentOneCopyWithImpl<TestDocumentOne, TestDocumentOne>(
        this as TestDocumentOne,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return TestDocumentOneMapper.ensureInitialized().stringifyValue(
      this as TestDocumentOne,
    );
  }

  @override
  bool operator ==(Object other) {
    return TestDocumentOneMapper.ensureInitialized().equalsValue(
      this as TestDocumentOne,
      other,
    );
  }

  @override
  int get hashCode {
    return TestDocumentOneMapper.ensureInitialized().hashValue(
      this as TestDocumentOne,
    );
  }
}

extension TestDocumentOneValueCopy<$R, $Out>
    on ObjectCopyWith<$R, TestDocumentOne, $Out> {
  TestDocumentOneCopyWith<$R, TestDocumentOne, $Out> get $asTestDocumentOne =>
      $base.as((v, t, t2) => _TestDocumentOneCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class TestDocumentOneCopyWith<$R, $In extends TestDocumentOne, $Out>
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
    String? rev,
    Map<String, AttachmentInfo>? attachments,
    Revisions? revisions,
    List<RevsInfo>? revsInfo,
    bool? deleted,
    Map<String, dynamic>? unmappedProps,
  });
  TestDocumentOneCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _TestDocumentOneCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, TestDocumentOne, $Out>
    implements TestDocumentOneCopyWith<$R, TestDocumentOne, $Out> {
  _TestDocumentOneCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<TestDocumentOne> $mapper =
      TestDocumentOneMapper.ensureInitialized();
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
    Object? rev = $none,
    Object? attachments = $none,
    Object? revisions = $none,
    Object? revsInfo = $none,
    bool? deleted,
    Map<String, dynamic>? unmappedProps,
  }) => $apply(
    FieldCopyWithData({
      if (name != null) #name: name,
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
  TestDocumentOne $make(CopyWithData data) => TestDocumentOne(
    name: data.get(#name, or: $value.name),
    id: data.get(#id, or: $value.id),
    rev: data.get(#rev, or: $value.rev),
    attachments: data.get(#attachments, or: $value.attachments),
    revisions: data.get(#revisions, or: $value.revisions),
    revsInfo: data.get(#revsInfo, or: $value.revsInfo),
    deleted: data.get(#deleted, or: $value.deleted),
    unmappedProps: data.get(#unmappedProps, or: $value.unmappedProps),
  );

  @override
  TestDocumentOneCopyWith<$R2, TestDocumentOne, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _TestDocumentOneCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

