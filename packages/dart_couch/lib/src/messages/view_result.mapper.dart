// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'view_result.dart';

class ViewResultMapper extends ClassMapperBase<ViewResult> {
  ViewResultMapper._();

  static ViewResultMapper? _instance;
  static ViewResultMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ViewResultMapper._());
      ViewEntryMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ViewResult';

  static int? _$totalRows(ViewResult v) => v.totalRows;
  static const Field<ViewResult, int> _f$totalRows = Field(
    'totalRows',
    _$totalRows,
    key: r'total_rows',
  );
  static int? _$offset(ViewResult v) => v.offset;
  static const Field<ViewResult, int> _f$offset = Field('offset', _$offset);
  static List<ViewEntry> _$rows(ViewResult v) => v.rows;
  static const Field<ViewResult, List<ViewEntry>> _f$rows = Field(
    'rows',
    _$rows,
  );

  @override
  final MappableFields<ViewResult> fields = const {
    #totalRows: _f$totalRows,
    #offset: _f$offset,
    #rows: _f$rows,
  };

  static ViewResult _instantiate(DecodingData data) {
    return ViewResult(
      totalRows: data.dec(_f$totalRows),
      offset: data.dec(_f$offset),
      rows: data.dec(_f$rows),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ViewResult fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ViewResult>(map);
  }

  static ViewResult fromJson(String json) {
    return ensureInitialized().decodeJson<ViewResult>(json);
  }
}

mixin ViewResultMappable {
  String toJson() {
    return ViewResultMapper.ensureInitialized().encodeJson<ViewResult>(
      this as ViewResult,
    );
  }

  Map<String, dynamic> toMap() {
    return ViewResultMapper.ensureInitialized().encodeMap<ViewResult>(
      this as ViewResult,
    );
  }

  ViewResultCopyWith<ViewResult, ViewResult, ViewResult> get copyWith =>
      _ViewResultCopyWithImpl<ViewResult, ViewResult>(
        this as ViewResult,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ViewResultMapper.ensureInitialized().stringifyValue(
      this as ViewResult,
    );
  }

  @override
  bool operator ==(Object other) {
    return ViewResultMapper.ensureInitialized().equalsValue(
      this as ViewResult,
      other,
    );
  }

  @override
  int get hashCode {
    return ViewResultMapper.ensureInitialized().hashValue(this as ViewResult);
  }
}

extension ViewResultValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ViewResult, $Out> {
  ViewResultCopyWith<$R, ViewResult, $Out> get $asViewResult =>
      $base.as((v, t, t2) => _ViewResultCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ViewResultCopyWith<$R, $In extends ViewResult, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, ViewEntry, ViewEntryCopyWith<$R, ViewEntry, ViewEntry>>
  get rows;
  $R call({int? totalRows, int? offset, List<ViewEntry>? rows});
  ViewResultCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ViewResultCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ViewResult, $Out>
    implements ViewResultCopyWith<$R, ViewResult, $Out> {
  _ViewResultCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ViewResult> $mapper =
      ViewResultMapper.ensureInitialized();
  @override
  ListCopyWith<$R, ViewEntry, ViewEntryCopyWith<$R, ViewEntry, ViewEntry>>
  get rows => ListCopyWith(
    $value.rows,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(rows: v),
  );
  @override
  $R call({
    Object? totalRows = $none,
    Object? offset = $none,
    List<ViewEntry>? rows,
  }) => $apply(
    FieldCopyWithData({
      if (totalRows != $none) #totalRows: totalRows,
      if (offset != $none) #offset: offset,
      if (rows != null) #rows: rows,
    }),
  );
  @override
  ViewResult $make(CopyWithData data) => ViewResult(
    totalRows: data.get(#totalRows, or: $value.totalRows),
    offset: data.get(#offset, or: $value.offset),
    rows: data.get(#rows, or: $value.rows),
  );

  @override
  ViewResultCopyWith<$R2, ViewResult, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ViewResultCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ViewEntryMapper extends ClassMapperBase<ViewEntry> {
  ViewEntryMapper._();

  static ViewEntryMapper? _instance;
  static ViewEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ViewEntryMapper._());
      CouchDocumentBaseMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ViewEntry';

  static String? _$id(ViewEntry v) => v.id;
  static const Field<ViewEntry, String> _f$id = Field('id', _$id, opt: true);
  static dynamic _$key(ViewEntry v) => v.key;
  static const Field<ViewEntry, dynamic> _f$key = Field(
    'key',
    _$key,
    opt: true,
  );
  static dynamic _$value(ViewEntry v) => v.value;
  static const Field<ViewEntry, dynamic> _f$value = Field(
    'value',
    _$value,
    opt: true,
  );
  static String? _$error(ViewEntry v) => v.error;
  static const Field<ViewEntry, String> _f$error = Field(
    'error',
    _$error,
    opt: true,
  );
  static CouchDocumentBase? _$doc(ViewEntry v) => v.doc;
  static const Field<ViewEntry, CouchDocumentBase> _f$doc = Field(
    'doc',
    _$doc,
    opt: true,
  );

  @override
  final MappableFields<ViewEntry> fields = const {
    #id: _f$id,
    #key: _f$key,
    #value: _f$value,
    #error: _f$error,
    #doc: _f$doc,
  };

  static ViewEntry _instantiate(DecodingData data) {
    return ViewEntry(
      id: data.dec(_f$id),
      key: data.dec(_f$key),
      value: data.dec(_f$value),
      error: data.dec(_f$error),
      doc: data.dec(_f$doc),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ViewEntry fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ViewEntry>(map);
  }

  static ViewEntry fromJson(String json) {
    return ensureInitialized().decodeJson<ViewEntry>(json);
  }
}

mixin ViewEntryMappable {
  String toJson() {
    return ViewEntryMapper.ensureInitialized().encodeJson<ViewEntry>(
      this as ViewEntry,
    );
  }

  Map<String, dynamic> toMap() {
    return ViewEntryMapper.ensureInitialized().encodeMap<ViewEntry>(
      this as ViewEntry,
    );
  }

  ViewEntryCopyWith<ViewEntry, ViewEntry, ViewEntry> get copyWith =>
      _ViewEntryCopyWithImpl<ViewEntry, ViewEntry>(
        this as ViewEntry,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ViewEntryMapper.ensureInitialized().stringifyValue(
      this as ViewEntry,
    );
  }

  @override
  bool operator ==(Object other) {
    return ViewEntryMapper.ensureInitialized().equalsValue(
      this as ViewEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return ViewEntryMapper.ensureInitialized().hashValue(this as ViewEntry);
  }
}

extension ViewEntryValueCopy<$R, $Out> on ObjectCopyWith<$R, ViewEntry, $Out> {
  ViewEntryCopyWith<$R, ViewEntry, $Out> get $asViewEntry =>
      $base.as((v, t, t2) => _ViewEntryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ViewEntryCopyWith<$R, $In extends ViewEntry, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  CouchDocumentBaseCopyWith<$R, CouchDocumentBase, CouchDocumentBase>? get doc;
  $R call({
    String? id,
    dynamic key,
    dynamic value,
    String? error,
    CouchDocumentBase? doc,
  });
  ViewEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ViewEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ViewEntry, $Out>
    implements ViewEntryCopyWith<$R, ViewEntry, $Out> {
  _ViewEntryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ViewEntry> $mapper =
      ViewEntryMapper.ensureInitialized();
  @override
  CouchDocumentBaseCopyWith<$R, CouchDocumentBase, CouchDocumentBase>?
  get doc => $value.doc?.copyWith.$chain((v) => call(doc: v));
  @override
  $R call({
    Object? id = $none,
    Object? key = $none,
    Object? value = $none,
    Object? error = $none,
    Object? doc = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != $none) #id: id,
      if (key != $none) #key: key,
      if (value != $none) #value: value,
      if (error != $none) #error: error,
      if (doc != $none) #doc: doc,
    }),
  );
  @override
  ViewEntry $make(CopyWithData data) => ViewEntry(
    id: data.get(#id, or: $value.id),
    key: data.get(#key, or: $value.key),
    value: data.get(#value, or: $value.value),
    error: data.get(#error, or: $value.error),
    doc: data.get(#doc, or: $value.doc),
  );

  @override
  ViewEntryCopyWith<$R2, ViewEntry, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ViewEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

