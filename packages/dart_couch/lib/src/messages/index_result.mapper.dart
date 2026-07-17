// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'index_result.dart';

class SortOrderMapper extends EnumMapper<SortOrder> {
  SortOrderMapper._();

  static SortOrderMapper? _instance;
  static SortOrderMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SortOrderMapper._());
    }
    return _instance!;
  }

  static SortOrder fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  SortOrder decode(dynamic value) {
    switch (value) {
      case r'asc':
        return SortOrder.asc;
      case r'desc':
        return SortOrder.desc;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(SortOrder self) {
    switch (self) {
      case SortOrder.asc:
        return r'asc';
      case SortOrder.desc:
        return r'desc';
    }
  }
}

extension SortOrderMapperExtension on SortOrder {
  String toValue() {
    SortOrderMapper.ensureInitialized();
    return MapperContainer.globals.toValue<SortOrder>(this) as String;
  }
}

class IndexResultListMapper extends ClassMapperBase<IndexResultList> {
  IndexResultListMapper._();

  static IndexResultListMapper? _instance;
  static IndexResultListMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = IndexResultListMapper._());
      IndexResultMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'IndexResultList';

  static int _$totalRows(IndexResultList v) => v.totalRows;
  static const Field<IndexResultList, int> _f$totalRows = Field(
    'totalRows',
    _$totalRows,
    key: r'total_rows',
  );
  static List<IndexResult> _$indexes(IndexResultList v) => v.indexes;
  static const Field<IndexResultList, List<IndexResult>> _f$indexes = Field(
    'indexes',
    _$indexes,
  );

  @override
  final MappableFields<IndexResultList> fields = const {
    #totalRows: _f$totalRows,
    #indexes: _f$indexes,
  };

  static IndexResultList _instantiate(DecodingData data) {
    return IndexResultList(
      totalRows: data.dec(_f$totalRows),
      indexes: data.dec(_f$indexes),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static IndexResultList fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<IndexResultList>(map);
  }

  static IndexResultList fromJson(String json) {
    return ensureInitialized().decodeJson<IndexResultList>(json);
  }
}

mixin IndexResultListMappable {
  String toJson() {
    return IndexResultListMapper.ensureInitialized()
        .encodeJson<IndexResultList>(this as IndexResultList);
  }

  Map<String, dynamic> toMap() {
    return IndexResultListMapper.ensureInitialized().encodeMap<IndexResultList>(
      this as IndexResultList,
    );
  }

  IndexResultListCopyWith<IndexResultList, IndexResultList, IndexResultList>
  get copyWith =>
      _IndexResultListCopyWithImpl<IndexResultList, IndexResultList>(
        this as IndexResultList,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return IndexResultListMapper.ensureInitialized().stringifyValue(
      this as IndexResultList,
    );
  }

  @override
  bool operator ==(Object other) {
    return IndexResultListMapper.ensureInitialized().equalsValue(
      this as IndexResultList,
      other,
    );
  }

  @override
  int get hashCode {
    return IndexResultListMapper.ensureInitialized().hashValue(
      this as IndexResultList,
    );
  }
}

extension IndexResultListValueCopy<$R, $Out>
    on ObjectCopyWith<$R, IndexResultList, $Out> {
  IndexResultListCopyWith<$R, IndexResultList, $Out> get $asIndexResultList =>
      $base.as((v, t, t2) => _IndexResultListCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class IndexResultListCopyWith<$R, $In extends IndexResultList, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    IndexResult,
    IndexResultCopyWith<$R, IndexResult, IndexResult>
  >
  get indexes;
  $R call({int? totalRows, List<IndexResult>? indexes});
  IndexResultListCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _IndexResultListCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, IndexResultList, $Out>
    implements IndexResultListCopyWith<$R, IndexResultList, $Out> {
  _IndexResultListCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<IndexResultList> $mapper =
      IndexResultListMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    IndexResult,
    IndexResultCopyWith<$R, IndexResult, IndexResult>
  >
  get indexes => ListCopyWith(
    $value.indexes,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(indexes: v),
  );
  @override
  $R call({int? totalRows, List<IndexResult>? indexes}) => $apply(
    FieldCopyWithData({
      if (totalRows != null) #totalRows: totalRows,
      if (indexes != null) #indexes: indexes,
    }),
  );
  @override
  IndexResultList $make(CopyWithData data) => IndexResultList(
    totalRows: data.get(#totalRows, or: $value.totalRows),
    indexes: data.get(#indexes, or: $value.indexes),
  );

  @override
  IndexResultListCopyWith<$R2, IndexResultList, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _IndexResultListCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class IndexResultMapper extends ClassMapperBase<IndexResult> {
  IndexResultMapper._();

  static IndexResultMapper? _instance;
  static IndexResultMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = IndexResultMapper._());
      IndexDefinitionMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'IndexResult';

  static String? _$ddoc(IndexResult v) => v.ddoc;
  static const Field<IndexResult, String> _f$ddoc = Field('ddoc', _$ddoc);
  static String _$name(IndexResult v) => v.name;
  static const Field<IndexResult, String> _f$name = Field('name', _$name);
  static String _$type(IndexResult v) => v.type;
  static const Field<IndexResult, String> _f$type = Field('type', _$type);
  static bool? _$partitioned(IndexResult v) => v.partitioned;
  static const Field<IndexResult, bool> _f$partitioned = Field(
    'partitioned',
    _$partitioned,
  );
  static IndexDefinition _$def(IndexResult v) => v.def;
  static const Field<IndexResult, IndexDefinition> _f$def = Field('def', _$def);

  @override
  final MappableFields<IndexResult> fields = const {
    #ddoc: _f$ddoc,
    #name: _f$name,
    #type: _f$type,
    #partitioned: _f$partitioned,
    #def: _f$def,
  };
  @override
  final bool ignoreNull = true;

  static IndexResult _instantiate(DecodingData data) {
    return IndexResult(
      ddoc: data.dec(_f$ddoc),
      name: data.dec(_f$name),
      type: data.dec(_f$type),
      partitioned: data.dec(_f$partitioned),
      def: data.dec(_f$def),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static IndexResult fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<IndexResult>(map);
  }

  static IndexResult fromJson(String json) {
    return ensureInitialized().decodeJson<IndexResult>(json);
  }
}

mixin IndexResultMappable {
  String toJson() {
    return IndexResultMapper.ensureInitialized().encodeJson<IndexResult>(
      this as IndexResult,
    );
  }

  Map<String, dynamic> toMap() {
    return IndexResultMapper.ensureInitialized().encodeMap<IndexResult>(
      this as IndexResult,
    );
  }

  IndexResultCopyWith<IndexResult, IndexResult, IndexResult> get copyWith =>
      _IndexResultCopyWithImpl<IndexResult, IndexResult>(
        this as IndexResult,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return IndexResultMapper.ensureInitialized().stringifyValue(
      this as IndexResult,
    );
  }

  @override
  bool operator ==(Object other) {
    return IndexResultMapper.ensureInitialized().equalsValue(
      this as IndexResult,
      other,
    );
  }

  @override
  int get hashCode {
    return IndexResultMapper.ensureInitialized().hashValue(this as IndexResult);
  }
}

extension IndexResultValueCopy<$R, $Out>
    on ObjectCopyWith<$R, IndexResult, $Out> {
  IndexResultCopyWith<$R, IndexResult, $Out> get $asIndexResult =>
      $base.as((v, t, t2) => _IndexResultCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class IndexResultCopyWith<$R, $In extends IndexResult, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  IndexDefinitionCopyWith<$R, IndexDefinition, IndexDefinition> get def;
  $R call({
    String? ddoc,
    String? name,
    String? type,
    bool? partitioned,
    IndexDefinition? def,
  });
  IndexResultCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _IndexResultCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, IndexResult, $Out>
    implements IndexResultCopyWith<$R, IndexResult, $Out> {
  _IndexResultCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<IndexResult> $mapper =
      IndexResultMapper.ensureInitialized();
  @override
  IndexDefinitionCopyWith<$R, IndexDefinition, IndexDefinition> get def =>
      $value.def.copyWith.$chain((v) => call(def: v));
  @override
  $R call({
    Object? ddoc = $none,
    String? name,
    String? type,
    Object? partitioned = $none,
    IndexDefinition? def,
  }) => $apply(
    FieldCopyWithData({
      if (ddoc != $none) #ddoc: ddoc,
      if (name != null) #name: name,
      if (type != null) #type: type,
      if (partitioned != $none) #partitioned: partitioned,
      if (def != null) #def: def,
    }),
  );
  @override
  IndexResult $make(CopyWithData data) => IndexResult(
    ddoc: data.get(#ddoc, or: $value.ddoc),
    name: data.get(#name, or: $value.name),
    type: data.get(#type, or: $value.type),
    partitioned: data.get(#partitioned, or: $value.partitioned),
    def: data.get(#def, or: $value.def),
  );

  @override
  IndexResultCopyWith<$R2, IndexResult, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _IndexResultCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class IndexDefinitionMapper extends ClassMapperBase<IndexDefinition> {
  IndexDefinitionMapper._();

  static IndexDefinitionMapper? _instance;
  static IndexDefinitionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = IndexDefinitionMapper._());
      SortOrderMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'IndexDefinition';

  static List<Map<String, SortOrder>> _$fields(IndexDefinition v) => v.fields;
  static const Field<IndexDefinition, List<Map<String, SortOrder>>> _f$fields =
      Field('fields', _$fields);
  static Map<String, dynamic>? _$partialFilterSelector(IndexDefinition v) =>
      v.partialFilterSelector;
  static const Field<IndexDefinition, Map<String, dynamic>>
  _f$partialFilterSelector = Field(
    'partialFilterSelector',
    _$partialFilterSelector,
    key: r'partial_filter_selector',
    opt: true,
  );

  @override
  final MappableFields<IndexDefinition> fields = const {
    #fields: _f$fields,
    #partialFilterSelector: _f$partialFilterSelector,
  };
  @override
  final bool ignoreNull = true;

  static IndexDefinition _instantiate(DecodingData data) {
    return IndexDefinition(
      fields: data.dec(_f$fields),
      partialFilterSelector: data.dec(_f$partialFilterSelector),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static IndexDefinition fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<IndexDefinition>(map);
  }

  static IndexDefinition fromJson(String json) {
    return ensureInitialized().decodeJson<IndexDefinition>(json);
  }
}

mixin IndexDefinitionMappable {
  String toJson() {
    return IndexDefinitionMapper.ensureInitialized()
        .encodeJson<IndexDefinition>(this as IndexDefinition);
  }

  Map<String, dynamic> toMap() {
    return IndexDefinitionMapper.ensureInitialized().encodeMap<IndexDefinition>(
      this as IndexDefinition,
    );
  }

  IndexDefinitionCopyWith<IndexDefinition, IndexDefinition, IndexDefinition>
  get copyWith =>
      _IndexDefinitionCopyWithImpl<IndexDefinition, IndexDefinition>(
        this as IndexDefinition,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return IndexDefinitionMapper.ensureInitialized().stringifyValue(
      this as IndexDefinition,
    );
  }

  @override
  bool operator ==(Object other) {
    return IndexDefinitionMapper.ensureInitialized().equalsValue(
      this as IndexDefinition,
      other,
    );
  }

  @override
  int get hashCode {
    return IndexDefinitionMapper.ensureInitialized().hashValue(
      this as IndexDefinition,
    );
  }
}

extension IndexDefinitionValueCopy<$R, $Out>
    on ObjectCopyWith<$R, IndexDefinition, $Out> {
  IndexDefinitionCopyWith<$R, IndexDefinition, $Out> get $asIndexDefinition =>
      $base.as((v, t, t2) => _IndexDefinitionCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class IndexDefinitionCopyWith<$R, $In extends IndexDefinition, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    Map<String, SortOrder>,
    ObjectCopyWith<$R, Map<String, SortOrder>, Map<String, SortOrder>>
  >
  get fields;
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>?>?
  get partialFilterSelector;
  $R call({
    List<Map<String, SortOrder>>? fields,
    Map<String, dynamic>? partialFilterSelector,
  });
  IndexDefinitionCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _IndexDefinitionCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, IndexDefinition, $Out>
    implements IndexDefinitionCopyWith<$R, IndexDefinition, $Out> {
  _IndexDefinitionCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<IndexDefinition> $mapper =
      IndexDefinitionMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    Map<String, SortOrder>,
    ObjectCopyWith<$R, Map<String, SortOrder>, Map<String, SortOrder>>
  >
  get fields => ListCopyWith(
    $value.fields,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(fields: v),
  );
  @override
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>?>?
  get partialFilterSelector => $value.partialFilterSelector != null
      ? MapCopyWith(
          $value.partialFilterSelector!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(partialFilterSelector: v),
        )
      : null;
  @override
  $R call({
    List<Map<String, SortOrder>>? fields,
    Object? partialFilterSelector = $none,
  }) => $apply(
    FieldCopyWithData({
      if (fields != null) #fields: fields,
      if (partialFilterSelector != $none)
        #partialFilterSelector: partialFilterSelector,
    }),
  );
  @override
  IndexDefinition $make(CopyWithData data) => IndexDefinition(
    fields: data.get(#fields, or: $value.fields),
    partialFilterSelector: data.get(
      #partialFilterSelector,
      or: $value.partialFilterSelector,
    ),
  );

  @override
  IndexDefinitionCopyWith<$R2, IndexDefinition, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _IndexDefinitionCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class IndexRequestMapper extends ClassMapperBase<IndexRequest> {
  IndexRequestMapper._();

  static IndexRequestMapper? _instance;
  static IndexRequestMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = IndexRequestMapper._());
      IndexDefinitionMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'IndexRequest';

  static String? _$ddoc(IndexRequest v) => v.ddoc;
  static const Field<IndexRequest, String> _f$ddoc = Field('ddoc', _$ddoc);
  static String _$name(IndexRequest v) => v.name;
  static const Field<IndexRequest, String> _f$name = Field('name', _$name);
  static String _$type(IndexRequest v) => v.type;
  static const Field<IndexRequest, String> _f$type = Field('type', _$type);
  static bool? _$partitioned(IndexRequest v) => v.partitioned;
  static const Field<IndexRequest, bool> _f$partitioned = Field(
    'partitioned',
    _$partitioned,
  );
  static IndexDefinition _$index(IndexRequest v) => v.index;
  static const Field<IndexRequest, IndexDefinition> _f$index = Field(
    'index',
    _$index,
  );

  @override
  final MappableFields<IndexRequest> fields = const {
    #ddoc: _f$ddoc,
    #name: _f$name,
    #type: _f$type,
    #partitioned: _f$partitioned,
    #index: _f$index,
  };
  @override
  final bool ignoreNull = true;

  static IndexRequest _instantiate(DecodingData data) {
    return IndexRequest(
      ddoc: data.dec(_f$ddoc),
      name: data.dec(_f$name),
      type: data.dec(_f$type),
      partitioned: data.dec(_f$partitioned),
      index: data.dec(_f$index),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static IndexRequest fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<IndexRequest>(map);
  }

  static IndexRequest fromJson(String json) {
    return ensureInitialized().decodeJson<IndexRequest>(json);
  }
}

mixin IndexRequestMappable {
  String toJson() {
    return IndexRequestMapper.ensureInitialized().encodeJson<IndexRequest>(
      this as IndexRequest,
    );
  }

  Map<String, dynamic> toMap() {
    return IndexRequestMapper.ensureInitialized().encodeMap<IndexRequest>(
      this as IndexRequest,
    );
  }

  IndexRequestCopyWith<IndexRequest, IndexRequest, IndexRequest> get copyWith =>
      _IndexRequestCopyWithImpl<IndexRequest, IndexRequest>(
        this as IndexRequest,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return IndexRequestMapper.ensureInitialized().stringifyValue(
      this as IndexRequest,
    );
  }

  @override
  bool operator ==(Object other) {
    return IndexRequestMapper.ensureInitialized().equalsValue(
      this as IndexRequest,
      other,
    );
  }

  @override
  int get hashCode {
    return IndexRequestMapper.ensureInitialized().hashValue(
      this as IndexRequest,
    );
  }
}

extension IndexRequestValueCopy<$R, $Out>
    on ObjectCopyWith<$R, IndexRequest, $Out> {
  IndexRequestCopyWith<$R, IndexRequest, $Out> get $asIndexRequest =>
      $base.as((v, t, t2) => _IndexRequestCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class IndexRequestCopyWith<$R, $In extends IndexRequest, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  IndexDefinitionCopyWith<$R, IndexDefinition, IndexDefinition> get index;
  $R call({
    String? ddoc,
    String? name,
    String? type,
    bool? partitioned,
    IndexDefinition? index,
  });
  IndexRequestCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _IndexRequestCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, IndexRequest, $Out>
    implements IndexRequestCopyWith<$R, IndexRequest, $Out> {
  _IndexRequestCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<IndexRequest> $mapper =
      IndexRequestMapper.ensureInitialized();
  @override
  IndexDefinitionCopyWith<$R, IndexDefinition, IndexDefinition> get index =>
      $value.index.copyWith.$chain((v) => call(index: v));
  @override
  $R call({
    Object? ddoc = $none,
    String? name,
    String? type,
    Object? partitioned = $none,
    IndexDefinition? index,
  }) => $apply(
    FieldCopyWithData({
      if (ddoc != $none) #ddoc: ddoc,
      if (name != null) #name: name,
      if (type != null) #type: type,
      if (partitioned != $none) #partitioned: partitioned,
      if (index != null) #index: index,
    }),
  );
  @override
  IndexRequest $make(CopyWithData data) => IndexRequest(
    ddoc: data.get(#ddoc, or: $value.ddoc),
    name: data.get(#name, or: $value.name),
    type: data.get(#type, or: $value.type),
    partitioned: data.get(#partitioned, or: $value.partitioned),
    index: data.get(#index, or: $value.index),
  );

  @override
  IndexRequestCopyWith<$R2, IndexRequest, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _IndexRequestCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class IndexDocumentMapper extends ClassMapperBase<IndexDocument> {
  IndexDocumentMapper._();

  static IndexDocumentMapper? _instance;
  static IndexDocumentMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = IndexDocumentMapper._());
      IndexViewMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'IndexDocument';

  static String _$id(IndexDocument v) => v.id;
  static const Field<IndexDocument, String> _f$id = Field(
    'id',
    _$id,
    key: r'_id',
  );
  static String? _$rev(IndexDocument v) => v.rev;
  static const Field<IndexDocument, String> _f$rev = Field(
    'rev',
    _$rev,
    key: r'_rev',
    opt: true,
  );
  static String _$language(IndexDocument v) => v.language;
  static const Field<IndexDocument, String> _f$language = Field(
    'language',
    _$language,
  );
  static Map<String, IndexView> _$views(IndexDocument v) => v.views;
  static const Field<IndexDocument, Map<String, IndexView>> _f$views = Field(
    'views',
    _$views,
  );

  @override
  final MappableFields<IndexDocument> fields = const {
    #id: _f$id,
    #rev: _f$rev,
    #language: _f$language,
    #views: _f$views,
  };

  static IndexDocument _instantiate(DecodingData data) {
    return IndexDocument(
      id: data.dec(_f$id),
      rev: data.dec(_f$rev),
      language: data.dec(_f$language),
      views: data.dec(_f$views),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static IndexDocument fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<IndexDocument>(map);
  }

  static IndexDocument fromJson(String json) {
    return ensureInitialized().decodeJson<IndexDocument>(json);
  }
}

mixin IndexDocumentMappable {
  String toJson() {
    return IndexDocumentMapper.ensureInitialized().encodeJson<IndexDocument>(
      this as IndexDocument,
    );
  }

  Map<String, dynamic> toMap() {
    return IndexDocumentMapper.ensureInitialized().encodeMap<IndexDocument>(
      this as IndexDocument,
    );
  }

  IndexDocumentCopyWith<IndexDocument, IndexDocument, IndexDocument>
  get copyWith => _IndexDocumentCopyWithImpl<IndexDocument, IndexDocument>(
    this as IndexDocument,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return IndexDocumentMapper.ensureInitialized().stringifyValue(
      this as IndexDocument,
    );
  }

  @override
  bool operator ==(Object other) {
    return IndexDocumentMapper.ensureInitialized().equalsValue(
      this as IndexDocument,
      other,
    );
  }

  @override
  int get hashCode {
    return IndexDocumentMapper.ensureInitialized().hashValue(
      this as IndexDocument,
    );
  }
}

extension IndexDocumentValueCopy<$R, $Out>
    on ObjectCopyWith<$R, IndexDocument, $Out> {
  IndexDocumentCopyWith<$R, IndexDocument, $Out> get $asIndexDocument =>
      $base.as((v, t, t2) => _IndexDocumentCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class IndexDocumentCopyWith<$R, $In extends IndexDocument, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<
    $R,
    String,
    IndexView,
    IndexViewCopyWith<$R, IndexView, IndexView>
  >
  get views;
  $R call({
    String? id,
    String? rev,
    String? language,
    Map<String, IndexView>? views,
  });
  IndexDocumentCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _IndexDocumentCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, IndexDocument, $Out>
    implements IndexDocumentCopyWith<$R, IndexDocument, $Out> {
  _IndexDocumentCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<IndexDocument> $mapper =
      IndexDocumentMapper.ensureInitialized();
  @override
  MapCopyWith<
    $R,
    String,
    IndexView,
    IndexViewCopyWith<$R, IndexView, IndexView>
  >
  get views => MapCopyWith(
    $value.views,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(views: v),
  );
  @override
  $R call({
    String? id,
    Object? rev = $none,
    String? language,
    Map<String, IndexView>? views,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (rev != $none) #rev: rev,
      if (language != null) #language: language,
      if (views != null) #views: views,
    }),
  );
  @override
  IndexDocument $make(CopyWithData data) => IndexDocument(
    id: data.get(#id, or: $value.id),
    rev: data.get(#rev, or: $value.rev),
    language: data.get(#language, or: $value.language),
    views: data.get(#views, or: $value.views),
  );

  @override
  IndexDocumentCopyWith<$R2, IndexDocument, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _IndexDocumentCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class IndexViewMapper extends ClassMapperBase<IndexView> {
  IndexViewMapper._();

  static IndexViewMapper? _instance;
  static IndexViewMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = IndexViewMapper._());
      IndexMapMapper.ensureInitialized();
      IndexOptionsMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'IndexView';

  static IndexMap _$map(IndexView v) => v.map;
  static const Field<IndexView, IndexMap> _f$map = Field('map', _$map);
  static String? _$reduce(IndexView v) => v.reduce;
  static const Field<IndexView, String> _f$reduce = Field(
    'reduce',
    _$reduce,
    opt: true,
  );
  static IndexOptions? _$options(IndexView v) => v.options;
  static const Field<IndexView, IndexOptions> _f$options = Field(
    'options',
    _$options,
    opt: true,
  );

  @override
  final MappableFields<IndexView> fields = const {
    #map: _f$map,
    #reduce: _f$reduce,
    #options: _f$options,
  };

  static IndexView _instantiate(DecodingData data) {
    return IndexView(
      map: data.dec(_f$map),
      reduce: data.dec(_f$reduce),
      options: data.dec(_f$options),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static IndexView fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<IndexView>(map);
  }

  static IndexView fromJson(String json) {
    return ensureInitialized().decodeJson<IndexView>(json);
  }
}

mixin IndexViewMappable {
  String toJson() {
    return IndexViewMapper.ensureInitialized().encodeJson<IndexView>(
      this as IndexView,
    );
  }

  Map<String, dynamic> toMap() {
    return IndexViewMapper.ensureInitialized().encodeMap<IndexView>(
      this as IndexView,
    );
  }

  IndexViewCopyWith<IndexView, IndexView, IndexView> get copyWith =>
      _IndexViewCopyWithImpl<IndexView, IndexView>(
        this as IndexView,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return IndexViewMapper.ensureInitialized().stringifyValue(
      this as IndexView,
    );
  }

  @override
  bool operator ==(Object other) {
    return IndexViewMapper.ensureInitialized().equalsValue(
      this as IndexView,
      other,
    );
  }

  @override
  int get hashCode {
    return IndexViewMapper.ensureInitialized().hashValue(this as IndexView);
  }
}

extension IndexViewValueCopy<$R, $Out> on ObjectCopyWith<$R, IndexView, $Out> {
  IndexViewCopyWith<$R, IndexView, $Out> get $asIndexView =>
      $base.as((v, t, t2) => _IndexViewCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class IndexViewCopyWith<$R, $In extends IndexView, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  IndexMapCopyWith<$R, IndexMap, IndexMap> get map;
  IndexOptionsCopyWith<$R, IndexOptions, IndexOptions>? get options;
  $R call({IndexMap? map, String? reduce, IndexOptions? options});
  IndexViewCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _IndexViewCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, IndexView, $Out>
    implements IndexViewCopyWith<$R, IndexView, $Out> {
  _IndexViewCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<IndexView> $mapper =
      IndexViewMapper.ensureInitialized();
  @override
  IndexMapCopyWith<$R, IndexMap, IndexMap> get map =>
      $value.map.copyWith.$chain((v) => call(map: v));
  @override
  IndexOptionsCopyWith<$R, IndexOptions, IndexOptions>? get options =>
      $value.options?.copyWith.$chain((v) => call(options: v));
  @override
  $R call({IndexMap? map, Object? reduce = $none, Object? options = $none}) =>
      $apply(
        FieldCopyWithData({
          if (map != null) #map: map,
          if (reduce != $none) #reduce: reduce,
          if (options != $none) #options: options,
        }),
      );
  @override
  IndexView $make(CopyWithData data) => IndexView(
    map: data.get(#map, or: $value.map),
    reduce: data.get(#reduce, or: $value.reduce),
    options: data.get(#options, or: $value.options),
  );

  @override
  IndexViewCopyWith<$R2, IndexView, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _IndexViewCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class IndexMapMapper extends ClassMapperBase<IndexMap> {
  IndexMapMapper._();

  static IndexMapMapper? _instance;
  static IndexMapMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = IndexMapMapper._());
      SortOrderMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'IndexMap';

  static Map<String, SortOrder> _$fields(IndexMap v) => v.fields;
  static const Field<IndexMap, Map<String, SortOrder>> _f$fields = Field(
    'fields',
    _$fields,
  );

  @override
  final MappableFields<IndexMap> fields = const {#fields: _f$fields};

  static IndexMap _instantiate(DecodingData data) {
    return IndexMap(fields: data.dec(_f$fields));
  }

  @override
  final Function instantiate = _instantiate;

  static IndexMap fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<IndexMap>(map);
  }

  static IndexMap fromJson(String json) {
    return ensureInitialized().decodeJson<IndexMap>(json);
  }
}

mixin IndexMapMappable {
  String toJson() {
    return IndexMapMapper.ensureInitialized().encodeJson<IndexMap>(
      this as IndexMap,
    );
  }

  Map<String, dynamic> toMap() {
    return IndexMapMapper.ensureInitialized().encodeMap<IndexMap>(
      this as IndexMap,
    );
  }

  IndexMapCopyWith<IndexMap, IndexMap, IndexMap> get copyWith =>
      _IndexMapCopyWithImpl<IndexMap, IndexMap>(
        this as IndexMap,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return IndexMapMapper.ensureInitialized().stringifyValue(this as IndexMap);
  }

  @override
  bool operator ==(Object other) {
    return IndexMapMapper.ensureInitialized().equalsValue(
      this as IndexMap,
      other,
    );
  }

  @override
  int get hashCode {
    return IndexMapMapper.ensureInitialized().hashValue(this as IndexMap);
  }
}

extension IndexMapValueCopy<$R, $Out> on ObjectCopyWith<$R, IndexMap, $Out> {
  IndexMapCopyWith<$R, IndexMap, $Out> get $asIndexMap =>
      $base.as((v, t, t2) => _IndexMapCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class IndexMapCopyWith<$R, $In extends IndexMap, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, SortOrder, ObjectCopyWith<$R, SortOrder, SortOrder>>
  get fields;
  $R call({Map<String, SortOrder>? fields});
  IndexMapCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _IndexMapCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, IndexMap, $Out>
    implements IndexMapCopyWith<$R, IndexMap, $Out> {
  _IndexMapCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<IndexMap> $mapper =
      IndexMapMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, SortOrder, ObjectCopyWith<$R, SortOrder, SortOrder>>
  get fields => MapCopyWith(
    $value.fields,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(fields: v),
  );
  @override
  $R call({Map<String, SortOrder>? fields}) =>
      $apply(FieldCopyWithData({if (fields != null) #fields: fields}));
  @override
  IndexMap $make(CopyWithData data) =>
      IndexMap(fields: data.get(#fields, or: $value.fields));

  @override
  IndexMapCopyWith<$R2, IndexMap, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _IndexMapCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class IndexOptionsMapper extends ClassMapperBase<IndexOptions> {
  IndexOptionsMapper._();

  static IndexOptionsMapper? _instance;
  static IndexOptionsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = IndexOptionsMapper._());
      IndexDefinitionMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'IndexOptions';

  static IndexDefinition _$def(IndexOptions v) => v.def;
  static const Field<IndexOptions, IndexDefinition> _f$def = Field(
    'def',
    _$def,
  );

  @override
  final MappableFields<IndexOptions> fields = const {#def: _f$def};

  static IndexOptions _instantiate(DecodingData data) {
    return IndexOptions(def: data.dec(_f$def));
  }

  @override
  final Function instantiate = _instantiate;

  static IndexOptions fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<IndexOptions>(map);
  }

  static IndexOptions fromJson(String json) {
    return ensureInitialized().decodeJson<IndexOptions>(json);
  }
}

mixin IndexOptionsMappable {
  String toJson() {
    return IndexOptionsMapper.ensureInitialized().encodeJson<IndexOptions>(
      this as IndexOptions,
    );
  }

  Map<String, dynamic> toMap() {
    return IndexOptionsMapper.ensureInitialized().encodeMap<IndexOptions>(
      this as IndexOptions,
    );
  }

  IndexOptionsCopyWith<IndexOptions, IndexOptions, IndexOptions> get copyWith =>
      _IndexOptionsCopyWithImpl<IndexOptions, IndexOptions>(
        this as IndexOptions,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return IndexOptionsMapper.ensureInitialized().stringifyValue(
      this as IndexOptions,
    );
  }

  @override
  bool operator ==(Object other) {
    return IndexOptionsMapper.ensureInitialized().equalsValue(
      this as IndexOptions,
      other,
    );
  }

  @override
  int get hashCode {
    return IndexOptionsMapper.ensureInitialized().hashValue(
      this as IndexOptions,
    );
  }
}

extension IndexOptionsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, IndexOptions, $Out> {
  IndexOptionsCopyWith<$R, IndexOptions, $Out> get $asIndexOptions =>
      $base.as((v, t, t2) => _IndexOptionsCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class IndexOptionsCopyWith<$R, $In extends IndexOptions, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  IndexDefinitionCopyWith<$R, IndexDefinition, IndexDefinition> get def;
  $R call({IndexDefinition? def});
  IndexOptionsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _IndexOptionsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, IndexOptions, $Out>
    implements IndexOptionsCopyWith<$R, IndexOptions, $Out> {
  _IndexOptionsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<IndexOptions> $mapper =
      IndexOptionsMapper.ensureInitialized();
  @override
  IndexDefinitionCopyWith<$R, IndexDefinition, IndexDefinition> get def =>
      $value.def.copyWith.$chain((v) => call(def: v));
  @override
  $R call({IndexDefinition? def}) =>
      $apply(FieldCopyWithData({if (def != null) #def: def}));
  @override
  IndexOptions $make(CopyWithData data) =>
      IndexOptions(def: data.get(#def, or: $value.def));

  @override
  IndexOptionsCopyWith<$R2, IndexOptions, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _IndexOptionsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

