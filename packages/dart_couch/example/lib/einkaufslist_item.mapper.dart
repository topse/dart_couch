// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'einkaufslist_item.dart';

class EinkaufslistItemMapper extends SubClassMapperBase<EinkaufslistItem> {
  EinkaufslistItemMapper._();

  static EinkaufslistItemMapper? _instance;
  static EinkaufslistItemMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = EinkaufslistItemMapper._());
      CouchDocumentBaseMapper.ensureInitialized().addSubMapper(_instance!);
      AttachmentInfoMapper.ensureInitialized();
      RevisionsMapper.ensureInitialized();
      RevsInfoMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'EinkaufslistItem';

  static String _$name(EinkaufslistItem v) => v.name;
  static const Field<EinkaufslistItem, String> _f$name = Field('name', _$name);
  static bool _$erledigt(EinkaufslistItem v) => v.erledigt;
  static const Field<EinkaufslistItem, bool> _f$erledigt = Field(
    'erledigt',
    _$erledigt,
  );
  static int? _$anzahl(EinkaufslistItem v) => v.anzahl;
  static const Field<EinkaufslistItem, int> _f$anzahl = Field(
    'anzahl',
    _$anzahl,
    opt: true,
  );
  static String? _$einheit(EinkaufslistItem v) => v.einheit;
  static const Field<EinkaufslistItem, String> _f$einheit = Field(
    'einheit',
    _$einheit,
  );
  static String _$category(EinkaufslistItem v) => v.category;
  static const Field<EinkaufslistItem, String> _f$category = Field(
    'category',
    _$category,
  );
  static String? _$id(EinkaufslistItem v) => v.id;
  static const Field<EinkaufslistItem, String> _f$id = Field(
    'id',
    _$id,
    key: r'_id',
    opt: true,
  );
  static String? _$rev(EinkaufslistItem v) => v.rev;
  static const Field<EinkaufslistItem, String> _f$rev = Field(
    'rev',
    _$rev,
    key: r'_rev',
    opt: true,
  );
  static Map<String, AttachmentInfo>? _$attachments(EinkaufslistItem v) =>
      v.attachments;
  static const Field<EinkaufslistItem, Map<String, AttachmentInfo>>
  _f$attachments = Field(
    'attachments',
    _$attachments,
    key: r'_attachments',
    opt: true,
  );
  static Revisions? _$revisions(EinkaufslistItem v) => v.revisions;
  static const Field<EinkaufslistItem, Revisions> _f$revisions = Field(
    'revisions',
    _$revisions,
    key: r'_revisions',
    opt: true,
  );
  static List<RevsInfo>? _$revsInfo(EinkaufslistItem v) => v.revsInfo;
  static const Field<EinkaufslistItem, List<RevsInfo>> _f$revsInfo = Field(
    'revsInfo',
    _$revsInfo,
    key: r'_revs_info',
    opt: true,
  );
  static bool _$deleted(EinkaufslistItem v) => v.deleted;
  static const Field<EinkaufslistItem, bool> _f$deleted = Field(
    'deleted',
    _$deleted,
    key: r'_deleted',
    opt: true,
    def: false,
  );
  static Map<String, dynamic> _$unmappedProps(EinkaufslistItem v) =>
      v.unmappedProps;
  static const Field<EinkaufslistItem, Map<String, dynamic>> _f$unmappedProps =
      Field('unmappedProps', _$unmappedProps, opt: true, def: const {});

  @override
  final MappableFields<EinkaufslistItem> fields = const {
    #name: _f$name,
    #erledigt: _f$erledigt,
    #anzahl: _f$anzahl,
    #einheit: _f$einheit,
    #category: _f$category,
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
  final dynamic discriminatorValue = 'item';
  @override
  late final ClassMapperBase superMapper =
      CouchDocumentBaseMapper.ensureInitialized();

  @override
  final MappingHook superHook = const ChainedHook([
    CouchDocumentBaseRawHook(),
    UnmappedPropertiesHook('unmappedProps'),
  ]);

  static EinkaufslistItem _instantiate(DecodingData data) {
    return EinkaufslistItem(
      name: data.dec(_f$name),
      erledigt: data.dec(_f$erledigt),
      anzahl: data.dec(_f$anzahl),
      einheit: data.dec(_f$einheit),
      category: data.dec(_f$category),
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

  static EinkaufslistItem fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<EinkaufslistItem>(map);
  }

  static EinkaufslistItem fromJson(String json) {
    return ensureInitialized().decodeJson<EinkaufslistItem>(json);
  }
}

mixin EinkaufslistItemMappable {
  String toJson() {
    return EinkaufslistItemMapper.ensureInitialized()
        .encodeJson<EinkaufslistItem>(this as EinkaufslistItem);
  }

  Map<String, dynamic> toMap() {
    return EinkaufslistItemMapper.ensureInitialized()
        .encodeMap<EinkaufslistItem>(this as EinkaufslistItem);
  }

  EinkaufslistItemCopyWith<EinkaufslistItem, EinkaufslistItem, EinkaufslistItem>
  get copyWith =>
      _EinkaufslistItemCopyWithImpl<EinkaufslistItem, EinkaufslistItem>(
        this as EinkaufslistItem,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return EinkaufslistItemMapper.ensureInitialized().stringifyValue(
      this as EinkaufslistItem,
    );
  }

  @override
  bool operator ==(Object other) {
    return EinkaufslistItemMapper.ensureInitialized().equalsValue(
      this as EinkaufslistItem,
      other,
    );
  }

  @override
  int get hashCode {
    return EinkaufslistItemMapper.ensureInitialized().hashValue(
      this as EinkaufslistItem,
    );
  }
}

extension EinkaufslistItemValueCopy<$R, $Out>
    on ObjectCopyWith<$R, EinkaufslistItem, $Out> {
  EinkaufslistItemCopyWith<$R, EinkaufslistItem, $Out>
  get $asEinkaufslistItem =>
      $base.as((v, t, t2) => _EinkaufslistItemCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class EinkaufslistItemCopyWith<$R, $In extends EinkaufslistItem, $Out>
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
    bool? erledigt,
    int? anzahl,
    String? einheit,
    String? category,
    String? id,
    String? rev,
    Map<String, AttachmentInfo>? attachments,
    Revisions? revisions,
    List<RevsInfo>? revsInfo,
    bool? deleted,
    Map<String, dynamic>? unmappedProps,
  });
  EinkaufslistItemCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _EinkaufslistItemCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, EinkaufslistItem, $Out>
    implements EinkaufslistItemCopyWith<$R, EinkaufslistItem, $Out> {
  _EinkaufslistItemCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<EinkaufslistItem> $mapper =
      EinkaufslistItemMapper.ensureInitialized();
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
    bool? erledigt,
    Object? anzahl = $none,
    Object? einheit = $none,
    String? category,
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
      if (erledigt != null) #erledigt: erledigt,
      if (anzahl != $none) #anzahl: anzahl,
      if (einheit != $none) #einheit: einheit,
      if (category != null) #category: category,
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
  EinkaufslistItem $make(CopyWithData data) => EinkaufslistItem(
    name: data.get(#name, or: $value.name),
    erledigt: data.get(#erledigt, or: $value.erledigt),
    anzahl: data.get(#anzahl, or: $value.anzahl),
    einheit: data.get(#einheit, or: $value.einheit),
    category: data.get(#category, or: $value.category),
    id: data.get(#id, or: $value.id),
    rev: data.get(#rev, or: $value.rev),
    attachments: data.get(#attachments, or: $value.attachments),
    revisions: data.get(#revisions, or: $value.revisions),
    revsInfo: data.get(#revsInfo, or: $value.revsInfo),
    deleted: data.get(#deleted, or: $value.deleted),
    unmappedProps: data.get(#unmappedProps, or: $value.unmappedProps),
  );

  @override
  EinkaufslistItemCopyWith<$R2, EinkaufslistItem, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _EinkaufslistItemCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class EinkaufslistCategoryMapper
    extends SubClassMapperBase<EinkaufslistCategory> {
  EinkaufslistCategoryMapper._();

  static EinkaufslistCategoryMapper? _instance;
  static EinkaufslistCategoryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = EinkaufslistCategoryMapper._());
      CouchDocumentBaseMapper.ensureInitialized().addSubMapper(_instance!);
      AttachmentInfoMapper.ensureInitialized();
      RevisionsMapper.ensureInitialized();
      RevsInfoMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'EinkaufslistCategory';

  static String _$name(EinkaufslistCategory v) => v.name;
  static const Field<EinkaufslistCategory, String> _f$name = Field(
    'name',
    _$name,
  );
  static int _$sorthint(EinkaufslistCategory v) => v.sorthint;
  static const Field<EinkaufslistCategory, int> _f$sorthint = Field(
    'sorthint',
    _$sorthint,
  );
  static String? _$id(EinkaufslistCategory v) => v.id;
  static const Field<EinkaufslistCategory, String> _f$id = Field(
    'id',
    _$id,
    key: r'_id',
    opt: true,
  );
  static String? _$rev(EinkaufslistCategory v) => v.rev;
  static const Field<EinkaufslistCategory, String> _f$rev = Field(
    'rev',
    _$rev,
    key: r'_rev',
    opt: true,
  );
  static Map<String, AttachmentInfo>? _$attachments(EinkaufslistCategory v) =>
      v.attachments;
  static const Field<EinkaufslistCategory, Map<String, AttachmentInfo>>
  _f$attachments = Field(
    'attachments',
    _$attachments,
    key: r'_attachments',
    opt: true,
  );
  static Revisions? _$revisions(EinkaufslistCategory v) => v.revisions;
  static const Field<EinkaufslistCategory, Revisions> _f$revisions = Field(
    'revisions',
    _$revisions,
    key: r'_revisions',
    opt: true,
  );
  static List<RevsInfo>? _$revsInfo(EinkaufslistCategory v) => v.revsInfo;
  static const Field<EinkaufslistCategory, List<RevsInfo>> _f$revsInfo = Field(
    'revsInfo',
    _$revsInfo,
    key: r'_revs_info',
    opt: true,
  );
  static bool _$deleted(EinkaufslistCategory v) => v.deleted;
  static const Field<EinkaufslistCategory, bool> _f$deleted = Field(
    'deleted',
    _$deleted,
    key: r'_deleted',
    opt: true,
    def: false,
  );
  static Map<String, dynamic> _$unmappedProps(EinkaufslistCategory v) =>
      v.unmappedProps;
  static const Field<EinkaufslistCategory, Map<String, dynamic>>
  _f$unmappedProps = Field(
    'unmappedProps',
    _$unmappedProps,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<EinkaufslistCategory> fields = const {
    #name: _f$name,
    #sorthint: _f$sorthint,
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
  final dynamic discriminatorValue = 'category';
  @override
  late final ClassMapperBase superMapper =
      CouchDocumentBaseMapper.ensureInitialized();

  @override
  final MappingHook superHook = const ChainedHook([
    CouchDocumentBaseRawHook(),
    UnmappedPropertiesHook('unmappedProps'),
  ]);

  static EinkaufslistCategory _instantiate(DecodingData data) {
    return EinkaufslistCategory(
      name: data.dec(_f$name),
      sorthint: data.dec(_f$sorthint),
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

  static EinkaufslistCategory fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<EinkaufslistCategory>(map);
  }

  static EinkaufslistCategory fromJson(String json) {
    return ensureInitialized().decodeJson<EinkaufslistCategory>(json);
  }
}

mixin EinkaufslistCategoryMappable {
  String toJson() {
    return EinkaufslistCategoryMapper.ensureInitialized()
        .encodeJson<EinkaufslistCategory>(this as EinkaufslistCategory);
  }

  Map<String, dynamic> toMap() {
    return EinkaufslistCategoryMapper.ensureInitialized()
        .encodeMap<EinkaufslistCategory>(this as EinkaufslistCategory);
  }

  EinkaufslistCategoryCopyWith<
    EinkaufslistCategory,
    EinkaufslistCategory,
    EinkaufslistCategory
  >
  get copyWith =>
      _EinkaufslistCategoryCopyWithImpl<
        EinkaufslistCategory,
        EinkaufslistCategory
      >(this as EinkaufslistCategory, $identity, $identity);
  @override
  String toString() {
    return EinkaufslistCategoryMapper.ensureInitialized().stringifyValue(
      this as EinkaufslistCategory,
    );
  }

  @override
  bool operator ==(Object other) {
    return EinkaufslistCategoryMapper.ensureInitialized().equalsValue(
      this as EinkaufslistCategory,
      other,
    );
  }

  @override
  int get hashCode {
    return EinkaufslistCategoryMapper.ensureInitialized().hashValue(
      this as EinkaufslistCategory,
    );
  }
}

extension EinkaufslistCategoryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, EinkaufslistCategory, $Out> {
  EinkaufslistCategoryCopyWith<$R, EinkaufslistCategory, $Out>
  get $asEinkaufslistCategory => $base.as(
    (v, t, t2) => _EinkaufslistCategoryCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class EinkaufslistCategoryCopyWith<
  $R,
  $In extends EinkaufslistCategory,
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
    String? name,
    int? sorthint,
    String? id,
    String? rev,
    Map<String, AttachmentInfo>? attachments,
    Revisions? revisions,
    List<RevsInfo>? revsInfo,
    bool? deleted,
    Map<String, dynamic>? unmappedProps,
  });
  EinkaufslistCategoryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _EinkaufslistCategoryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, EinkaufslistCategory, $Out>
    implements EinkaufslistCategoryCopyWith<$R, EinkaufslistCategory, $Out> {
  _EinkaufslistCategoryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<EinkaufslistCategory> $mapper =
      EinkaufslistCategoryMapper.ensureInitialized();
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
    int? sorthint,
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
      if (sorthint != null) #sorthint: sorthint,
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
  EinkaufslistCategory $make(CopyWithData data) => EinkaufslistCategory(
    name: data.get(#name, or: $value.name),
    sorthint: data.get(#sorthint, or: $value.sorthint),
    id: data.get(#id, or: $value.id),
    rev: data.get(#rev, or: $value.rev),
    attachments: data.get(#attachments, or: $value.attachments),
    revisions: data.get(#revisions, or: $value.revisions),
    revsInfo: data.get(#revsInfo, or: $value.revsInfo),
    deleted: data.get(#deleted, or: $value.deleted),
    unmappedProps: data.get(#unmappedProps, or: $value.unmappedProps),
  );

  @override
  EinkaufslistCategoryCopyWith<$R2, EinkaufslistCategory, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _EinkaufslistCategoryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

