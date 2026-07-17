// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'bulk_docs_result.dart';

class BulkDocsResultMapper extends ClassMapperBase<BulkDocsResult> {
  BulkDocsResultMapper._();

  static BulkDocsResultMapper? _instance;
  static BulkDocsResultMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = BulkDocsResultMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'BulkDocsResult';

  static String _$id(BulkDocsResult v) => v.id;
  static const Field<BulkDocsResult, String> _f$id = Field('id', _$id);
  static bool? _$ok(BulkDocsResult v) => v.ok;
  static const Field<BulkDocsResult, bool> _f$ok = Field('ok', _$ok, opt: true);
  static String? _$rev(BulkDocsResult v) => v.rev;
  static const Field<BulkDocsResult, String> _f$rev = Field(
    'rev',
    _$rev,
    opt: true,
  );
  static String? _$error(BulkDocsResult v) => v.error;
  static const Field<BulkDocsResult, String> _f$error = Field(
    'error',
    _$error,
    opt: true,
  );
  static String? _$reason(BulkDocsResult v) => v.reason;
  static const Field<BulkDocsResult, String> _f$reason = Field(
    'reason',
    _$reason,
    opt: true,
  );

  @override
  final MappableFields<BulkDocsResult> fields = const {
    #id: _f$id,
    #ok: _f$ok,
    #rev: _f$rev,
    #error: _f$error,
    #reason: _f$reason,
  };

  static BulkDocsResult _instantiate(DecodingData data) {
    return BulkDocsResult(
      id: data.dec(_f$id),
      ok: data.dec(_f$ok),
      rev: data.dec(_f$rev),
      error: data.dec(_f$error),
      reason: data.dec(_f$reason),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static BulkDocsResult fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<BulkDocsResult>(map);
  }

  static BulkDocsResult fromJson(String json) {
    return ensureInitialized().decodeJson<BulkDocsResult>(json);
  }
}

mixin BulkDocsResultMappable {
  String toJson() {
    return BulkDocsResultMapper.ensureInitialized().encodeJson<BulkDocsResult>(
      this as BulkDocsResult,
    );
  }

  Map<String, dynamic> toMap() {
    return BulkDocsResultMapper.ensureInitialized().encodeMap<BulkDocsResult>(
      this as BulkDocsResult,
    );
  }

  BulkDocsResultCopyWith<BulkDocsResult, BulkDocsResult, BulkDocsResult>
  get copyWith => _BulkDocsResultCopyWithImpl<BulkDocsResult, BulkDocsResult>(
    this as BulkDocsResult,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return BulkDocsResultMapper.ensureInitialized().stringifyValue(
      this as BulkDocsResult,
    );
  }

  @override
  bool operator ==(Object other) {
    return BulkDocsResultMapper.ensureInitialized().equalsValue(
      this as BulkDocsResult,
      other,
    );
  }

  @override
  int get hashCode {
    return BulkDocsResultMapper.ensureInitialized().hashValue(
      this as BulkDocsResult,
    );
  }
}

extension BulkDocsResultValueCopy<$R, $Out>
    on ObjectCopyWith<$R, BulkDocsResult, $Out> {
  BulkDocsResultCopyWith<$R, BulkDocsResult, $Out> get $asBulkDocsResult =>
      $base.as((v, t, t2) => _BulkDocsResultCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class BulkDocsResultCopyWith<$R, $In extends BulkDocsResult, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? id, bool? ok, String? rev, String? error, String? reason});
  BulkDocsResultCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _BulkDocsResultCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, BulkDocsResult, $Out>
    implements BulkDocsResultCopyWith<$R, BulkDocsResult, $Out> {
  _BulkDocsResultCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<BulkDocsResult> $mapper =
      BulkDocsResultMapper.ensureInitialized();
  @override
  $R call({
    String? id,
    Object? ok = $none,
    Object? rev = $none,
    Object? error = $none,
    Object? reason = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (ok != $none) #ok: ok,
      if (rev != $none) #rev: rev,
      if (error != $none) #error: error,
      if (reason != $none) #reason: reason,
    }),
  );
  @override
  BulkDocsResult $make(CopyWithData data) => BulkDocsResult(
    id: data.get(#id, or: $value.id),
    ok: data.get(#ok, or: $value.ok),
    rev: data.get(#rev, or: $value.rev),
    error: data.get(#error, or: $value.error),
    reason: data.get(#reason, or: $value.reason),
  );

  @override
  BulkDocsResultCopyWith<$R2, BulkDocsResult, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _BulkDocsResultCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

