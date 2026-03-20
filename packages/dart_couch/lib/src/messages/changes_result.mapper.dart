// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'changes_result.dart';

class ChangesResultNormalMapper extends ClassMapperBase<ChangesResultNormal> {
  ChangesResultNormalMapper._();

  static ChangesResultNormalMapper? _instance;
  static ChangesResultNormalMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ChangesResultNormalMapper._());
      ChangeEntryMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ChangesResultNormal';

  static String _$lastSeq(ChangesResultNormal v) => v.lastSeq;
  static const Field<ChangesResultNormal, String> _f$lastSeq = Field(
    'lastSeq',
    _$lastSeq,
    key: r'last_seq',
  );
  static int _$pending(ChangesResultNormal v) => v.pending;
  static const Field<ChangesResultNormal, int> _f$pending = Field(
    'pending',
    _$pending,
  );
  static List<ChangeEntry> _$results(ChangesResultNormal v) => v.results;
  static const Field<ChangesResultNormal, List<ChangeEntry>> _f$results = Field(
    'results',
    _$results,
  );

  @override
  final MappableFields<ChangesResultNormal> fields = const {
    #lastSeq: _f$lastSeq,
    #pending: _f$pending,
    #results: _f$results,
  };

  static ChangesResultNormal _instantiate(DecodingData data) {
    return ChangesResultNormal(
      lastSeq: data.dec(_f$lastSeq),
      pending: data.dec(_f$pending),
      results: data.dec(_f$results),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ChangesResultNormal fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ChangesResultNormal>(map);
  }

  static ChangesResultNormal fromJson(String json) {
    return ensureInitialized().decodeJson<ChangesResultNormal>(json);
  }
}

mixin ChangesResultNormalMappable {
  String toJson() {
    return ChangesResultNormalMapper.ensureInitialized()
        .encodeJson<ChangesResultNormal>(this as ChangesResultNormal);
  }

  Map<String, dynamic> toMap() {
    return ChangesResultNormalMapper.ensureInitialized()
        .encodeMap<ChangesResultNormal>(this as ChangesResultNormal);
  }

  ChangesResultNormalCopyWith<
    ChangesResultNormal,
    ChangesResultNormal,
    ChangesResultNormal
  >
  get copyWith =>
      _ChangesResultNormalCopyWithImpl<
        ChangesResultNormal,
        ChangesResultNormal
      >(this as ChangesResultNormal, $identity, $identity);
  @override
  String toString() {
    return ChangesResultNormalMapper.ensureInitialized().stringifyValue(
      this as ChangesResultNormal,
    );
  }

  @override
  bool operator ==(Object other) {
    return ChangesResultNormalMapper.ensureInitialized().equalsValue(
      this as ChangesResultNormal,
      other,
    );
  }

  @override
  int get hashCode {
    return ChangesResultNormalMapper.ensureInitialized().hashValue(
      this as ChangesResultNormal,
    );
  }
}

extension ChangesResultNormalValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ChangesResultNormal, $Out> {
  ChangesResultNormalCopyWith<$R, ChangesResultNormal, $Out>
  get $asChangesResultNormal => $base.as(
    (v, t, t2) => _ChangesResultNormalCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class ChangesResultNormalCopyWith<
  $R,
  $In extends ChangesResultNormal,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    ChangeEntry,
    ChangeEntryCopyWith<$R, ChangeEntry, ChangeEntry>
  >
  get results;
  $R call({String? lastSeq, int? pending, List<ChangeEntry>? results});
  ChangesResultNormalCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ChangesResultNormalCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ChangesResultNormal, $Out>
    implements ChangesResultNormalCopyWith<$R, ChangesResultNormal, $Out> {
  _ChangesResultNormalCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ChangesResultNormal> $mapper =
      ChangesResultNormalMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    ChangeEntry,
    ChangeEntryCopyWith<$R, ChangeEntry, ChangeEntry>
  >
  get results => ListCopyWith(
    $value.results,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(results: v),
  );
  @override
  $R call({String? lastSeq, int? pending, List<ChangeEntry>? results}) =>
      $apply(
        FieldCopyWithData({
          if (lastSeq != null) #lastSeq: lastSeq,
          if (pending != null) #pending: pending,
          if (results != null) #results: results,
        }),
      );
  @override
  ChangesResultNormal $make(CopyWithData data) => ChangesResultNormal(
    lastSeq: data.get(#lastSeq, or: $value.lastSeq),
    pending: data.get(#pending, or: $value.pending),
    results: data.get(#results, or: $value.results),
  );

  @override
  ChangesResultNormalCopyWith<$R2, ChangesResultNormal, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _ChangesResultNormalCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ChangeEntryMapper extends ClassMapperBase<ChangeEntry> {
  ChangeEntryMapper._();

  static ChangeEntryMapper? _instance;
  static ChangeEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ChangeEntryMapper._());
      RevisionListEntryMapper.ensureInitialized();
      CouchDocumentBaseMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ChangeEntry';

  static String _$id(ChangeEntry v) => v.id;
  static const Field<ChangeEntry, String> _f$id = Field('id', _$id);
  static String _$seq(ChangeEntry v) => v.seq;
  static const Field<ChangeEntry, String> _f$seq = Field('seq', _$seq);
  static List<RevisionListEntry> _$changes(ChangeEntry v) => v.changes;
  static const Field<ChangeEntry, List<RevisionListEntry>> _f$changes = Field(
    'changes',
    _$changes,
  );
  static bool _$deleted(ChangeEntry v) => v.deleted;
  static const Field<ChangeEntry, bool> _f$deleted = Field(
    'deleted',
    _$deleted,
    opt: true,
    def: false,
  );
  static CouchDocumentBase? _$doc(ChangeEntry v) => v.doc;
  static const Field<ChangeEntry, CouchDocumentBase> _f$doc = Field(
    'doc',
    _$doc,
    opt: true,
  );

  @override
  final MappableFields<ChangeEntry> fields = const {
    #id: _f$id,
    #seq: _f$seq,
    #changes: _f$changes,
    #deleted: _f$deleted,
    #doc: _f$doc,
  };

  static ChangeEntry _instantiate(DecodingData data) {
    return ChangeEntry(
      id: data.dec(_f$id),
      seq: data.dec(_f$seq),
      changes: data.dec(_f$changes),
      deleted: data.dec(_f$deleted),
      doc: data.dec(_f$doc),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ChangeEntry fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ChangeEntry>(map);
  }

  static ChangeEntry fromJson(String json) {
    return ensureInitialized().decodeJson<ChangeEntry>(json);
  }
}

mixin ChangeEntryMappable {
  String toJson() {
    return ChangeEntryMapper.ensureInitialized().encodeJson<ChangeEntry>(
      this as ChangeEntry,
    );
  }

  Map<String, dynamic> toMap() {
    return ChangeEntryMapper.ensureInitialized().encodeMap<ChangeEntry>(
      this as ChangeEntry,
    );
  }

  ChangeEntryCopyWith<ChangeEntry, ChangeEntry, ChangeEntry> get copyWith =>
      _ChangeEntryCopyWithImpl<ChangeEntry, ChangeEntry>(
        this as ChangeEntry,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ChangeEntryMapper.ensureInitialized().stringifyValue(
      this as ChangeEntry,
    );
  }

  @override
  bool operator ==(Object other) {
    return ChangeEntryMapper.ensureInitialized().equalsValue(
      this as ChangeEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return ChangeEntryMapper.ensureInitialized().hashValue(this as ChangeEntry);
  }
}

extension ChangeEntryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ChangeEntry, $Out> {
  ChangeEntryCopyWith<$R, ChangeEntry, $Out> get $asChangeEntry =>
      $base.as((v, t, t2) => _ChangeEntryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ChangeEntryCopyWith<$R, $In extends ChangeEntry, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    RevisionListEntry,
    RevisionListEntryCopyWith<$R, RevisionListEntry, RevisionListEntry>
  >
  get changes;
  CouchDocumentBaseCopyWith<$R, CouchDocumentBase, CouchDocumentBase>? get doc;
  $R call({
    String? id,
    String? seq,
    List<RevisionListEntry>? changes,
    bool? deleted,
    CouchDocumentBase? doc,
  });
  ChangeEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ChangeEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ChangeEntry, $Out>
    implements ChangeEntryCopyWith<$R, ChangeEntry, $Out> {
  _ChangeEntryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ChangeEntry> $mapper =
      ChangeEntryMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    RevisionListEntry,
    RevisionListEntryCopyWith<$R, RevisionListEntry, RevisionListEntry>
  >
  get changes => ListCopyWith(
    $value.changes,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(changes: v),
  );
  @override
  CouchDocumentBaseCopyWith<$R, CouchDocumentBase, CouchDocumentBase>?
  get doc => $value.doc?.copyWith.$chain((v) => call(doc: v));
  @override
  $R call({
    String? id,
    String? seq,
    List<RevisionListEntry>? changes,
    bool? deleted,
    Object? doc = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (seq != null) #seq: seq,
      if (changes != null) #changes: changes,
      if (deleted != null) #deleted: deleted,
      if (doc != $none) #doc: doc,
    }),
  );
  @override
  ChangeEntry $make(CopyWithData data) => ChangeEntry(
    id: data.get(#id, or: $value.id),
    seq: data.get(#seq, or: $value.seq),
    changes: data.get(#changes, or: $value.changes),
    deleted: data.get(#deleted, or: $value.deleted),
    doc: data.get(#doc, or: $value.doc),
  );

  @override
  ChangeEntryCopyWith<$R2, ChangeEntry, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ChangeEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RevisionListEntryMapper extends ClassMapperBase<RevisionListEntry> {
  RevisionListEntryMapper._();

  static RevisionListEntryMapper? _instance;
  static RevisionListEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RevisionListEntryMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RevisionListEntry';

  static String _$rev(RevisionListEntry v) => v.rev;
  static const Field<RevisionListEntry, String> _f$rev = Field('rev', _$rev);

  @override
  final MappableFields<RevisionListEntry> fields = const {#rev: _f$rev};

  static RevisionListEntry _instantiate(DecodingData data) {
    return RevisionListEntry(rev: data.dec(_f$rev));
  }

  @override
  final Function instantiate = _instantiate;

  static RevisionListEntry fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RevisionListEntry>(map);
  }

  static RevisionListEntry fromJson(String json) {
    return ensureInitialized().decodeJson<RevisionListEntry>(json);
  }
}

mixin RevisionListEntryMappable {
  String toJson() {
    return RevisionListEntryMapper.ensureInitialized()
        .encodeJson<RevisionListEntry>(this as RevisionListEntry);
  }

  Map<String, dynamic> toMap() {
    return RevisionListEntryMapper.ensureInitialized()
        .encodeMap<RevisionListEntry>(this as RevisionListEntry);
  }

  RevisionListEntryCopyWith<
    RevisionListEntry,
    RevisionListEntry,
    RevisionListEntry
  >
  get copyWith =>
      _RevisionListEntryCopyWithImpl<RevisionListEntry, RevisionListEntry>(
        this as RevisionListEntry,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RevisionListEntryMapper.ensureInitialized().stringifyValue(
      this as RevisionListEntry,
    );
  }

  @override
  bool operator ==(Object other) {
    return RevisionListEntryMapper.ensureInitialized().equalsValue(
      this as RevisionListEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return RevisionListEntryMapper.ensureInitialized().hashValue(
      this as RevisionListEntry,
    );
  }
}

extension RevisionListEntryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RevisionListEntry, $Out> {
  RevisionListEntryCopyWith<$R, RevisionListEntry, $Out>
  get $asRevisionListEntry => $base.as(
    (v, t, t2) => _RevisionListEntryCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class RevisionListEntryCopyWith<
  $R,
  $In extends RevisionListEntry,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? rev});
  RevisionListEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RevisionListEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RevisionListEntry, $Out>
    implements RevisionListEntryCopyWith<$R, RevisionListEntry, $Out> {
  _RevisionListEntryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RevisionListEntry> $mapper =
      RevisionListEntryMapper.ensureInitialized();
  @override
  $R call({String? rev}) =>
      $apply(FieldCopyWithData({if (rev != null) #rev: rev}));
  @override
  RevisionListEntry $make(CopyWithData data) =>
      RevisionListEntry(rev: data.get(#rev, or: $value.rev));

  @override
  RevisionListEntryCopyWith<$R2, RevisionListEntry, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RevisionListEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

