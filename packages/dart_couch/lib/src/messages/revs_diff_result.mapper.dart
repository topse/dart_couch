// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'revs_diff_result.dart';

class RevsDiffEntryMapper extends ClassMapperBase<RevsDiffEntry> {
  RevsDiffEntryMapper._();

  static RevsDiffEntryMapper? _instance;
  static RevsDiffEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RevsDiffEntryMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RevsDiffEntry';

  static List<String>? _$missing(RevsDiffEntry v) => v.missing;
  static const Field<RevsDiffEntry, List<String>> _f$missing = Field(
    'missing',
    _$missing,
    opt: true,
  );
  static List<String>? _$possibleAncestors(RevsDiffEntry v) =>
      v.possibleAncestors;
  static const Field<RevsDiffEntry, List<String>> _f$possibleAncestors = Field(
    'possibleAncestors',
    _$possibleAncestors,
    key: r'possible_ancestors',
    opt: true,
  );

  @override
  final MappableFields<RevsDiffEntry> fields = const {
    #missing: _f$missing,
    #possibleAncestors: _f$possibleAncestors,
  };

  static RevsDiffEntry _instantiate(DecodingData data) {
    return RevsDiffEntry(
      missing: data.dec(_f$missing),
      possibleAncestors: data.dec(_f$possibleAncestors),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RevsDiffEntry fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RevsDiffEntry>(map);
  }

  static RevsDiffEntry fromJson(String json) {
    return ensureInitialized().decodeJson<RevsDiffEntry>(json);
  }
}

mixin RevsDiffEntryMappable {
  String toJson() {
    return RevsDiffEntryMapper.ensureInitialized().encodeJson<RevsDiffEntry>(
      this as RevsDiffEntry,
    );
  }

  Map<String, dynamic> toMap() {
    return RevsDiffEntryMapper.ensureInitialized().encodeMap<RevsDiffEntry>(
      this as RevsDiffEntry,
    );
  }

  RevsDiffEntryCopyWith<RevsDiffEntry, RevsDiffEntry, RevsDiffEntry>
  get copyWith => _RevsDiffEntryCopyWithImpl<RevsDiffEntry, RevsDiffEntry>(
    this as RevsDiffEntry,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return RevsDiffEntryMapper.ensureInitialized().stringifyValue(
      this as RevsDiffEntry,
    );
  }

  @override
  bool operator ==(Object other) {
    return RevsDiffEntryMapper.ensureInitialized().equalsValue(
      this as RevsDiffEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return RevsDiffEntryMapper.ensureInitialized().hashValue(
      this as RevsDiffEntry,
    );
  }
}

extension RevsDiffEntryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RevsDiffEntry, $Out> {
  RevsDiffEntryCopyWith<$R, RevsDiffEntry, $Out> get $asRevsDiffEntry =>
      $base.as((v, t, t2) => _RevsDiffEntryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RevsDiffEntryCopyWith<$R, $In extends RevsDiffEntry, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>? get missing;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>?
  get possibleAncestors;
  $R call({List<String>? missing, List<String>? possibleAncestors});
  RevsDiffEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _RevsDiffEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RevsDiffEntry, $Out>
    implements RevsDiffEntryCopyWith<$R, RevsDiffEntry, $Out> {
  _RevsDiffEntryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RevsDiffEntry> $mapper =
      RevsDiffEntryMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>? get missing =>
      $value.missing != null
      ? ListCopyWith(
          $value.missing!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(missing: v),
        )
      : null;
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>?
  get possibleAncestors => $value.possibleAncestors != null
      ? ListCopyWith(
          $value.possibleAncestors!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(possibleAncestors: v),
        )
      : null;
  @override
  $R call({Object? missing = $none, Object? possibleAncestors = $none}) =>
      $apply(
        FieldCopyWithData({
          if (missing != $none) #missing: missing,
          if (possibleAncestors != $none) #possibleAncestors: possibleAncestors,
        }),
      );
  @override
  RevsDiffEntry $make(CopyWithData data) => RevsDiffEntry(
    missing: data.get(#missing, or: $value.missing),
    possibleAncestors: data.get(
      #possibleAncestors,
      or: $value.possibleAncestors,
    ),
  );

  @override
  RevsDiffEntryCopyWith<$R2, RevsDiffEntry, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RevsDiffEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

