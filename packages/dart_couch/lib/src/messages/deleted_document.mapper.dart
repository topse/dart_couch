// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'deleted_document.dart';

class DeletedDocumentMapper extends SubClassMapperBase<DeletedDocument> {
  DeletedDocumentMapper._();

  static DeletedDocumentMapper? _instance;
  static DeletedDocumentMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = DeletedDocumentMapper._());
      CouchDocumentBaseMapper.ensureInitialized().addSubMapper(_instance!);
      AttachmentInfoMapper.ensureInitialized();
      RevisionsMapper.ensureInitialized();
      RevsInfoMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'DeletedDocument';

  static String? _$id(DeletedDocument v) => v.id;
  static const Field<DeletedDocument, String> _f$id = Field(
    'id',
    _$id,
    key: r'_id',
  );
  static String? _$rev(DeletedDocument v) => v.rev;
  static const Field<DeletedDocument, String> _f$rev = Field(
    'rev',
    _$rev,
    key: r'_rev',
  );
  static Map<String, AttachmentInfo>? _$attachments(DeletedDocument v) =>
      v.attachments;
  static const Field<DeletedDocument, Map<String, AttachmentInfo>>
  _f$attachments = Field(
    'attachments',
    _$attachments,
    key: r'_attachments',
    opt: true,
  );
  static Revisions? _$revisions(DeletedDocument v) => v.revisions;
  static const Field<DeletedDocument, Revisions> _f$revisions = Field(
    'revisions',
    _$revisions,
    key: r'_revisions',
    opt: true,
  );
  static List<RevsInfo>? _$revsInfo(DeletedDocument v) => v.revsInfo;
  static const Field<DeletedDocument, List<RevsInfo>> _f$revsInfo = Field(
    'revsInfo',
    _$revsInfo,
    key: r'_revs_info',
    opt: true,
  );
  static bool _$deleted(DeletedDocument v) => v.deleted;
  static const Field<DeletedDocument, bool> _f$deleted = Field(
    'deleted',
    _$deleted,
    key: r'_deleted',
    opt: true,
    def: false,
  );
  static Map<String, dynamic> _$unmappedProps(DeletedDocument v) =>
      v.unmappedProps;
  static const Field<DeletedDocument, Map<String, dynamic>> _f$unmappedProps =
      Field('unmappedProps', _$unmappedProps, opt: true, def: const {});

  @override
  final MappableFields<DeletedDocument> fields = const {
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
  final dynamic discriminatorValue = '!deleted_document';
  @override
  late final ClassMapperBase superMapper =
      CouchDocumentBaseMapper.ensureInitialized();

  @override
  final MappingHook superHook = const ChainedHook([
    CouchDocumentBaseRawHook(),
    UnmappedPropertiesHook('unmappedProps'),
  ]);

  static DeletedDocument _instantiate(DecodingData data) {
    return DeletedDocument(
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

  static DeletedDocument fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<DeletedDocument>(map);
  }

  static DeletedDocument fromJson(String json) {
    return ensureInitialized().decodeJson<DeletedDocument>(json);
  }
}

mixin DeletedDocumentMappable {
  String toJson() {
    return DeletedDocumentMapper.ensureInitialized()
        .encodeJson<DeletedDocument>(this as DeletedDocument);
  }

  Map<String, dynamic> toMap() {
    return DeletedDocumentMapper.ensureInitialized().encodeMap<DeletedDocument>(
      this as DeletedDocument,
    );
  }

  DeletedDocumentCopyWith<DeletedDocument, DeletedDocument, DeletedDocument>
  get copyWith =>
      _DeletedDocumentCopyWithImpl<DeletedDocument, DeletedDocument>(
        this as DeletedDocument,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return DeletedDocumentMapper.ensureInitialized().stringifyValue(
      this as DeletedDocument,
    );
  }

  @override
  bool operator ==(Object other) {
    return DeletedDocumentMapper.ensureInitialized().equalsValue(
      this as DeletedDocument,
      other,
    );
  }

  @override
  int get hashCode {
    return DeletedDocumentMapper.ensureInitialized().hashValue(
      this as DeletedDocument,
    );
  }
}

extension DeletedDocumentValueCopy<$R, $Out>
    on ObjectCopyWith<$R, DeletedDocument, $Out> {
  DeletedDocumentCopyWith<$R, DeletedDocument, $Out> get $asDeletedDocument =>
      $base.as((v, t, t2) => _DeletedDocumentCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class DeletedDocumentCopyWith<$R, $In extends DeletedDocument, $Out>
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
    String? id,
    String? rev,
    Map<String, AttachmentInfo>? attachments,
    Revisions? revisions,
    List<RevsInfo>? revsInfo,
    bool? deleted,
    Map<String, dynamic>? unmappedProps,
  });
  DeletedDocumentCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _DeletedDocumentCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, DeletedDocument, $Out>
    implements DeletedDocumentCopyWith<$R, DeletedDocument, $Out> {
  _DeletedDocumentCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<DeletedDocument> $mapper =
      DeletedDocumentMapper.ensureInitialized();
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
    Object? id = $none,
    Object? rev = $none,
    Object? attachments = $none,
    Object? revisions = $none,
    Object? revsInfo = $none,
    bool? deleted,
    Map<String, dynamic>? unmappedProps,
  }) => $apply(
    FieldCopyWithData({
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
  DeletedDocument $make(CopyWithData data) => DeletedDocument(
    id: data.get(#id, or: $value.id),
    rev: data.get(#rev, or: $value.rev),
    attachments: data.get(#attachments, or: $value.attachments),
    revisions: data.get(#revisions, or: $value.revisions),
    revsInfo: data.get(#revsInfo, or: $value.revsInfo),
    deleted: data.get(#deleted, or: $value.deleted),
    unmappedProps: data.get(#unmappedProps, or: $value.unmappedProps),
  );

  @override
  DeletedDocumentCopyWith<$R2, DeletedDocument, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _DeletedDocumentCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

