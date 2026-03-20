// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'design_document.dart';

class DesignDocumentMapper extends SubClassMapperBase<DesignDocument> {
  DesignDocumentMapper._();

  static DesignDocumentMapper? _instance;
  static DesignDocumentMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = DesignDocumentMapper._());
      CouchDocumentBaseMapper.ensureInitialized().addSubMapper(_instance!);
      ViewDataMapper.ensureInitialized();
      AttachmentInfoMapper.ensureInitialized();
      RevisionsMapper.ensureInitialized();
      RevsInfoMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'DesignDocument';

  static String? _$id(DesignDocument v) => v.id;
  static const Field<DesignDocument, String> _f$id = Field(
    'id',
    _$id,
    key: r'_id',
  );
  static String? _$rev(DesignDocument v) => v.rev;
  static const Field<DesignDocument, String> _f$rev = Field(
    'rev',
    _$rev,
    key: r'_rev',
    opt: true,
  );
  static bool _$deleted(DesignDocument v) => v.deleted;
  static const Field<DesignDocument, bool> _f$deleted = Field(
    'deleted',
    _$deleted,
    key: r'_deleted',
    opt: true,
    def: false,
  );
  static Map<String, ViewData>? _$views(DesignDocument v) => v.views;
  static const Field<DesignDocument, Map<String, ViewData>> _f$views = Field(
    'views',
    _$views,
    opt: true,
  );
  static Map<String, String>? _$updates(DesignDocument v) => v.updates;
  static const Field<DesignDocument, Map<String, String>> _f$updates = Field(
    'updates',
    _$updates,
    opt: true,
  );
  static Map<String, String>? _$filters(DesignDocument v) => v.filters;
  static const Field<DesignDocument, Map<String, String>> _f$filters = Field(
    'filters',
    _$filters,
    opt: true,
  );
  static String? _$validateDocUpdate(DesignDocument v) => v.validateDocUpdate;
  static const Field<DesignDocument, String> _f$validateDocUpdate = Field(
    'validateDocUpdate',
    _$validateDocUpdate,
    key: r'validate_doc_update',
    opt: true,
  );
  static String _$language(DesignDocument v) => v.language;
  static const Field<DesignDocument, String> _f$language = Field(
    'language',
    _$language,
    opt: true,
    def: "javascript",
  );
  static Map<String, AttachmentInfo>? _$attachments(DesignDocument v) =>
      v.attachments;
  static const Field<DesignDocument, Map<String, AttachmentInfo>>
  _f$attachments = Field(
    'attachments',
    _$attachments,
    key: r'_attachments',
    opt: true,
  );
  static Revisions? _$revisions(DesignDocument v) => v.revisions;
  static const Field<DesignDocument, Revisions> _f$revisions = Field(
    'revisions',
    _$revisions,
    key: r'_revisions',
    opt: true,
  );
  static List<RevsInfo>? _$revsInfo(DesignDocument v) => v.revsInfo;
  static const Field<DesignDocument, List<RevsInfo>> _f$revsInfo = Field(
    'revsInfo',
    _$revsInfo,
    key: r'_revs_info',
    opt: true,
  );
  static Map<String, dynamic> _$unmappedProps(DesignDocument v) =>
      v.unmappedProps;
  static const Field<DesignDocument, Map<String, dynamic>> _f$unmappedProps =
      Field('unmappedProps', _$unmappedProps, opt: true, def: const {});

  @override
  final MappableFields<DesignDocument> fields = const {
    #id: _f$id,
    #rev: _f$rev,
    #deleted: _f$deleted,
    #views: _f$views,
    #updates: _f$updates,
    #filters: _f$filters,
    #validateDocUpdate: _f$validateDocUpdate,
    #language: _f$language,
    #attachments: _f$attachments,
    #revisions: _f$revisions,
    #revsInfo: _f$revsInfo,
    #unmappedProps: _f$unmappedProps,
  };
  @override
  final bool ignoreNull = true;

  @override
  final String discriminatorKey = '!doc_type';
  @override
  final dynamic discriminatorValue = '_design_doc';
  @override
  late final ClassMapperBase superMapper =
      CouchDocumentBaseMapper.ensureInitialized();

  @override
  final MappingHook superHook = const ChainedHook([
    CouchDocumentBaseRawHook(),
    UnmappedPropertiesHook('unmappedProps'),
  ]);

  static DesignDocument _instantiate(DecodingData data) {
    return DesignDocument(
      id: data.dec(_f$id),
      rev: data.dec(_f$rev),
      deleted: data.dec(_f$deleted),
      views: data.dec(_f$views),
      updates: data.dec(_f$updates),
      filters: data.dec(_f$filters),
      validateDocUpdate: data.dec(_f$validateDocUpdate),
      language: data.dec(_f$language),
      attachments: data.dec(_f$attachments),
      revisions: data.dec(_f$revisions),
      revsInfo: data.dec(_f$revsInfo),
      unmappedProps: data.dec(_f$unmappedProps),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static DesignDocument fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<DesignDocument>(map);
  }

  static DesignDocument fromJson(String json) {
    return ensureInitialized().decodeJson<DesignDocument>(json);
  }
}

mixin DesignDocumentMappable {
  String toJson() {
    return DesignDocumentMapper.ensureInitialized().encodeJson<DesignDocument>(
      this as DesignDocument,
    );
  }

  Map<String, dynamic> toMap() {
    return DesignDocumentMapper.ensureInitialized().encodeMap<DesignDocument>(
      this as DesignDocument,
    );
  }

  DesignDocumentCopyWith<DesignDocument, DesignDocument, DesignDocument>
  get copyWith => _DesignDocumentCopyWithImpl<DesignDocument, DesignDocument>(
    this as DesignDocument,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return DesignDocumentMapper.ensureInitialized().stringifyValue(
      this as DesignDocument,
    );
  }

  @override
  bool operator ==(Object other) {
    return DesignDocumentMapper.ensureInitialized().equalsValue(
      this as DesignDocument,
      other,
    );
  }

  @override
  int get hashCode {
    return DesignDocumentMapper.ensureInitialized().hashValue(
      this as DesignDocument,
    );
  }
}

extension DesignDocumentValueCopy<$R, $Out>
    on ObjectCopyWith<$R, DesignDocument, $Out> {
  DesignDocumentCopyWith<$R, DesignDocument, $Out> get $asDesignDocument =>
      $base.as((v, t, t2) => _DesignDocumentCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class DesignDocumentCopyWith<$R, $In extends DesignDocument, $Out>
    implements CouchDocumentBaseCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, ViewData, ViewDataCopyWith<$R, ViewData, ViewData>>?
  get views;
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>?
  get updates;
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>?
  get filters;
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
    bool? deleted,
    Map<String, ViewData>? views,
    Map<String, String>? updates,
    Map<String, String>? filters,
    String? validateDocUpdate,
    String? language,
    Map<String, AttachmentInfo>? attachments,
    Revisions? revisions,
    List<RevsInfo>? revsInfo,
    Map<String, dynamic>? unmappedProps,
  });
  DesignDocumentCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _DesignDocumentCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, DesignDocument, $Out>
    implements DesignDocumentCopyWith<$R, DesignDocument, $Out> {
  _DesignDocumentCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<DesignDocument> $mapper =
      DesignDocumentMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, ViewData, ViewDataCopyWith<$R, ViewData, ViewData>>?
  get views => $value.views != null
      ? MapCopyWith(
          $value.views!,
          (v, t) => v.copyWith.$chain(t),
          (v) => call(views: v),
        )
      : null;
  @override
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>?
  get updates => $value.updates != null
      ? MapCopyWith(
          $value.updates!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(updates: v),
        )
      : null;
  @override
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>?
  get filters => $value.filters != null
      ? MapCopyWith(
          $value.filters!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(filters: v),
        )
      : null;
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
    bool? deleted,
    Object? views = $none,
    Object? updates = $none,
    Object? filters = $none,
    Object? validateDocUpdate = $none,
    String? language,
    Object? attachments = $none,
    Object? revisions = $none,
    Object? revsInfo = $none,
    Map<String, dynamic>? unmappedProps,
  }) => $apply(
    FieldCopyWithData({
      if (id != $none) #id: id,
      if (rev != $none) #rev: rev,
      if (deleted != null) #deleted: deleted,
      if (views != $none) #views: views,
      if (updates != $none) #updates: updates,
      if (filters != $none) #filters: filters,
      if (validateDocUpdate != $none) #validateDocUpdate: validateDocUpdate,
      if (language != null) #language: language,
      if (attachments != $none) #attachments: attachments,
      if (revisions != $none) #revisions: revisions,
      if (revsInfo != $none) #revsInfo: revsInfo,
      if (unmappedProps != null) #unmappedProps: unmappedProps,
    }),
  );
  @override
  DesignDocument $make(CopyWithData data) => DesignDocument(
    id: data.get(#id, or: $value.id),
    rev: data.get(#rev, or: $value.rev),
    deleted: data.get(#deleted, or: $value.deleted),
    views: data.get(#views, or: $value.views),
    updates: data.get(#updates, or: $value.updates),
    filters: data.get(#filters, or: $value.filters),
    validateDocUpdate: data.get(
      #validateDocUpdate,
      or: $value.validateDocUpdate,
    ),
    language: data.get(#language, or: $value.language),
    attachments: data.get(#attachments, or: $value.attachments),
    revisions: data.get(#revisions, or: $value.revisions),
    revsInfo: data.get(#revsInfo, or: $value.revsInfo),
    unmappedProps: data.get(#unmappedProps, or: $value.unmappedProps),
  );

  @override
  DesignDocumentCopyWith<$R2, DesignDocument, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _DesignDocumentCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ViewDataMapper extends ClassMapperBase<ViewData> {
  ViewDataMapper._();

  static ViewDataMapper? _instance;
  static ViewDataMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ViewDataMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ViewData';

  static String _$map(ViewData v) => v.map;
  static const Field<ViewData, String> _f$map = Field('map', _$map);
  static String? _$reduce(ViewData v) => v.reduce;
  static const Field<ViewData, String> _f$reduce = Field(
    'reduce',
    _$reduce,
    opt: true,
  );

  @override
  final MappableFields<ViewData> fields = const {
    #map: _f$map,
    #reduce: _f$reduce,
  };
  @override
  final bool ignoreNull = true;

  static ViewData _instantiate(DecodingData data) {
    return ViewData(map: data.dec(_f$map), reduce: data.dec(_f$reduce));
  }

  @override
  final Function instantiate = _instantiate;

  static ViewData fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ViewData>(map);
  }

  static ViewData fromJson(String json) {
    return ensureInitialized().decodeJson<ViewData>(json);
  }
}

mixin ViewDataMappable {
  String toJson() {
    return ViewDataMapper.ensureInitialized().encodeJson<ViewData>(
      this as ViewData,
    );
  }

  Map<String, dynamic> toMap() {
    return ViewDataMapper.ensureInitialized().encodeMap<ViewData>(
      this as ViewData,
    );
  }

  ViewDataCopyWith<ViewData, ViewData, ViewData> get copyWith =>
      _ViewDataCopyWithImpl<ViewData, ViewData>(
        this as ViewData,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ViewDataMapper.ensureInitialized().stringifyValue(this as ViewData);
  }

  @override
  bool operator ==(Object other) {
    return ViewDataMapper.ensureInitialized().equalsValue(
      this as ViewData,
      other,
    );
  }

  @override
  int get hashCode {
    return ViewDataMapper.ensureInitialized().hashValue(this as ViewData);
  }
}

extension ViewDataValueCopy<$R, $Out> on ObjectCopyWith<$R, ViewData, $Out> {
  ViewDataCopyWith<$R, ViewData, $Out> get $asViewData =>
      $base.as((v, t, t2) => _ViewDataCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ViewDataCopyWith<$R, $In extends ViewData, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? map, String? reduce});
  ViewDataCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ViewDataCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ViewData, $Out>
    implements ViewDataCopyWith<$R, ViewData, $Out> {
  _ViewDataCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ViewData> $mapper =
      ViewDataMapper.ensureInitialized();
  @override
  $R call({String? map, Object? reduce = $none}) => $apply(
    FieldCopyWithData({
      if (map != null) #map: map,
      if (reduce != $none) #reduce: reduce,
    }),
  );
  @override
  ViewData $make(CopyWithData data) => ViewData(
    map: data.get(#map, or: $value.map),
    reduce: data.get(#reduce, or: $value.reduce),
  );

  @override
  ViewDataCopyWith<$R2, ViewData, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ViewDataCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

