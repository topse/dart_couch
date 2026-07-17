// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'bulk_get.dart';

class BulkGetRequestMapper extends ClassMapperBase<BulkGetRequest> {
  BulkGetRequestMapper._();

  static BulkGetRequestMapper? _instance;
  static BulkGetRequestMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = BulkGetRequestMapper._());
      BulkGetRequestDocMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'BulkGetRequest';

  static List<BulkGetRequestDoc> _$docs(BulkGetRequest v) => v.docs;
  static const Field<BulkGetRequest, List<BulkGetRequestDoc>> _f$docs = Field(
    'docs',
    _$docs,
  );

  @override
  final MappableFields<BulkGetRequest> fields = const {#docs: _f$docs};

  static BulkGetRequest _instantiate(DecodingData data) {
    return BulkGetRequest(docs: data.dec(_f$docs));
  }

  @override
  final Function instantiate = _instantiate;

  static BulkGetRequest fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<BulkGetRequest>(map);
  }

  static BulkGetRequest fromJson(String json) {
    return ensureInitialized().decodeJson<BulkGetRequest>(json);
  }
}

mixin BulkGetRequestMappable {
  String toJson() {
    return BulkGetRequestMapper.ensureInitialized().encodeJson<BulkGetRequest>(
      this as BulkGetRequest,
    );
  }

  Map<String, dynamic> toMap() {
    return BulkGetRequestMapper.ensureInitialized().encodeMap<BulkGetRequest>(
      this as BulkGetRequest,
    );
  }

  BulkGetRequestCopyWith<BulkGetRequest, BulkGetRequest, BulkGetRequest>
  get copyWith => _BulkGetRequestCopyWithImpl<BulkGetRequest, BulkGetRequest>(
    this as BulkGetRequest,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return BulkGetRequestMapper.ensureInitialized().stringifyValue(
      this as BulkGetRequest,
    );
  }

  @override
  bool operator ==(Object other) {
    return BulkGetRequestMapper.ensureInitialized().equalsValue(
      this as BulkGetRequest,
      other,
    );
  }

  @override
  int get hashCode {
    return BulkGetRequestMapper.ensureInitialized().hashValue(
      this as BulkGetRequest,
    );
  }
}

extension BulkGetRequestValueCopy<$R, $Out>
    on ObjectCopyWith<$R, BulkGetRequest, $Out> {
  BulkGetRequestCopyWith<$R, BulkGetRequest, $Out> get $asBulkGetRequest =>
      $base.as((v, t, t2) => _BulkGetRequestCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class BulkGetRequestCopyWith<$R, $In extends BulkGetRequest, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    BulkGetRequestDoc,
    BulkGetRequestDocCopyWith<$R, BulkGetRequestDoc, BulkGetRequestDoc>
  >
  get docs;
  $R call({List<BulkGetRequestDoc>? docs});
  BulkGetRequestCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _BulkGetRequestCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, BulkGetRequest, $Out>
    implements BulkGetRequestCopyWith<$R, BulkGetRequest, $Out> {
  _BulkGetRequestCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<BulkGetRequest> $mapper =
      BulkGetRequestMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    BulkGetRequestDoc,
    BulkGetRequestDocCopyWith<$R, BulkGetRequestDoc, BulkGetRequestDoc>
  >
  get docs => ListCopyWith(
    $value.docs,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(docs: v),
  );
  @override
  $R call({List<BulkGetRequestDoc>? docs}) =>
      $apply(FieldCopyWithData({if (docs != null) #docs: docs}));
  @override
  BulkGetRequest $make(CopyWithData data) =>
      BulkGetRequest(docs: data.get(#docs, or: $value.docs));

  @override
  BulkGetRequestCopyWith<$R2, BulkGetRequest, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _BulkGetRequestCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class BulkGetRequestDocMapper extends ClassMapperBase<BulkGetRequestDoc> {
  BulkGetRequestDocMapper._();

  static BulkGetRequestDocMapper? _instance;
  static BulkGetRequestDocMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = BulkGetRequestDocMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'BulkGetRequestDoc';

  static String _$id(BulkGetRequestDoc v) => v.id;
  static const Field<BulkGetRequestDoc, String> _f$id = Field('id', _$id);
  static String? _$rev(BulkGetRequestDoc v) => v.rev;
  static const Field<BulkGetRequestDoc, String> _f$rev = Field(
    'rev',
    _$rev,
    opt: true,
  );
  static List<String>? _$attsSince(BulkGetRequestDoc v) => v.attsSince;
  static const Field<BulkGetRequestDoc, List<String>> _f$attsSince = Field(
    'attsSince',
    _$attsSince,
    key: r'atts_since',
    opt: true,
  );

  @override
  final MappableFields<BulkGetRequestDoc> fields = const {
    #id: _f$id,
    #rev: _f$rev,
    #attsSince: _f$attsSince,
  };

  static BulkGetRequestDoc _instantiate(DecodingData data) {
    return BulkGetRequestDoc(
      id: data.dec(_f$id),
      rev: data.dec(_f$rev),
      attsSince: data.dec(_f$attsSince),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static BulkGetRequestDoc fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<BulkGetRequestDoc>(map);
  }

  static BulkGetRequestDoc fromJson(String json) {
    return ensureInitialized().decodeJson<BulkGetRequestDoc>(json);
  }
}

mixin BulkGetRequestDocMappable {
  String toJson() {
    return BulkGetRequestDocMapper.ensureInitialized()
        .encodeJson<BulkGetRequestDoc>(this as BulkGetRequestDoc);
  }

  Map<String, dynamic> toMap() {
    return BulkGetRequestDocMapper.ensureInitialized()
        .encodeMap<BulkGetRequestDoc>(this as BulkGetRequestDoc);
  }

  BulkGetRequestDocCopyWith<
    BulkGetRequestDoc,
    BulkGetRequestDoc,
    BulkGetRequestDoc
  >
  get copyWith =>
      _BulkGetRequestDocCopyWithImpl<BulkGetRequestDoc, BulkGetRequestDoc>(
        this as BulkGetRequestDoc,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return BulkGetRequestDocMapper.ensureInitialized().stringifyValue(
      this as BulkGetRequestDoc,
    );
  }

  @override
  bool operator ==(Object other) {
    return BulkGetRequestDocMapper.ensureInitialized().equalsValue(
      this as BulkGetRequestDoc,
      other,
    );
  }

  @override
  int get hashCode {
    return BulkGetRequestDocMapper.ensureInitialized().hashValue(
      this as BulkGetRequestDoc,
    );
  }
}

extension BulkGetRequestDocValueCopy<$R, $Out>
    on ObjectCopyWith<$R, BulkGetRequestDoc, $Out> {
  BulkGetRequestDocCopyWith<$R, BulkGetRequestDoc, $Out>
  get $asBulkGetRequestDoc => $base.as(
    (v, t, t2) => _BulkGetRequestDocCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class BulkGetRequestDocCopyWith<
  $R,
  $In extends BulkGetRequestDoc,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>? get attsSince;
  $R call({String? id, String? rev, List<String>? attsSince});
  BulkGetRequestDocCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _BulkGetRequestDocCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, BulkGetRequestDoc, $Out>
    implements BulkGetRequestDocCopyWith<$R, BulkGetRequestDoc, $Out> {
  _BulkGetRequestDocCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<BulkGetRequestDoc> $mapper =
      BulkGetRequestDocMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>? get attsSince =>
      $value.attsSince != null
      ? ListCopyWith(
          $value.attsSince!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(attsSince: v),
        )
      : null;
  @override
  $R call({String? id, Object? rev = $none, Object? attsSince = $none}) =>
      $apply(
        FieldCopyWithData({
          if (id != null) #id: id,
          if (rev != $none) #rev: rev,
          if (attsSince != $none) #attsSince: attsSince,
        }),
      );
  @override
  BulkGetRequestDoc $make(CopyWithData data) => BulkGetRequestDoc(
    id: data.get(#id, or: $value.id),
    rev: data.get(#rev, or: $value.rev),
    attsSince: data.get(#attsSince, or: $value.attsSince),
  );

  @override
  BulkGetRequestDocCopyWith<$R2, BulkGetRequestDoc, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _BulkGetRequestDocCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

