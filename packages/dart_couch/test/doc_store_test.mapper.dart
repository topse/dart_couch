// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'doc_store_test.dart';

class PlayPositionMapper extends SubClassMapperBase<PlayPosition> {
  PlayPositionMapper._();

  static PlayPositionMapper? _instance;
  static PlayPositionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PlayPositionMapper._());
      CouchDocumentBaseMapper.ensureInitialized().addSubMapper(_instance!);
      PlayPositionItemMapper.ensureInitialized();
      AttachmentInfoMapper.ensureInitialized();
      RevisionsMapper.ensureInitialized();
      RevsInfoMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'PlayPosition';

  static String _$deviceId(PlayPosition v) => v.deviceId;
  static const Field<PlayPosition, String> _f$deviceId = Field(
    'deviceId',
    _$deviceId,
    key: r'device_id',
  );
  static Map<String, PlayPositionItem> _$items(PlayPosition v) => v.items;
  static const Field<PlayPosition, Map<String, PlayPositionItem>> _f$items =
      Field('items', _$items, opt: true, def: const {});
  static String? _$id(PlayPosition v) => v.id;
  static const Field<PlayPosition, String> _f$id = Field(
    'id',
    _$id,
    key: r'_id',
    opt: true,
  );
  static String? _$rev(PlayPosition v) => v.rev;
  static const Field<PlayPosition, String> _f$rev = Field(
    'rev',
    _$rev,
    key: r'_rev',
    opt: true,
  );
  static Map<String, AttachmentInfo>? _$attachments(PlayPosition v) =>
      v.attachments;
  static const Field<PlayPosition, Map<String, AttachmentInfo>> _f$attachments =
      Field('attachments', _$attachments, key: r'_attachments', opt: true);
  static bool _$deleted(PlayPosition v) => v.deleted;
  static const Field<PlayPosition, bool> _f$deleted = Field(
    'deleted',
    _$deleted,
    key: r'_deleted',
    opt: true,
    def: false,
  );
  static Revisions? _$revisions(PlayPosition v) => v.revisions;
  static const Field<PlayPosition, Revisions> _f$revisions = Field(
    'revisions',
    _$revisions,
    key: r'_revisions',
    opt: true,
  );
  static List<RevsInfo>? _$revsInfo(PlayPosition v) => v.revsInfo;
  static const Field<PlayPosition, List<RevsInfo>> _f$revsInfo = Field(
    'revsInfo',
    _$revsInfo,
    key: r'_revs_info',
    opt: true,
  );
  static Map<String, dynamic> _$unmappedProps(PlayPosition v) =>
      v.unmappedProps;
  static const Field<PlayPosition, Map<String, dynamic>> _f$unmappedProps =
      Field('unmappedProps', _$unmappedProps, opt: true, def: const {});

  @override
  final MappableFields<PlayPosition> fields = const {
    #deviceId: _f$deviceId,
    #items: _f$items,
    #id: _f$id,
    #rev: _f$rev,
    #attachments: _f$attachments,
    #deleted: _f$deleted,
    #revisions: _f$revisions,
    #revsInfo: _f$revsInfo,
    #unmappedProps: _f$unmappedProps,
  };
  @override
  final bool ignoreNull = true;

  @override
  final String discriminatorKey = '!doc_type';
  @override
  final dynamic discriminatorValue = 'play_position';
  @override
  late final ClassMapperBase superMapper =
      CouchDocumentBaseMapper.ensureInitialized();

  @override
  final MappingHook superHook = const ChainedHook([
    CouchDocumentBaseRawHook(),
    UnmappedPropertiesHook('unmappedProps'),
  ]);

  static PlayPosition _instantiate(DecodingData data) {
    return PlayPosition(
      deviceId: data.dec(_f$deviceId),
      items: data.dec(_f$items),
      id: data.dec(_f$id),
      rev: data.dec(_f$rev),
      attachments: data.dec(_f$attachments),
      deleted: data.dec(_f$deleted),
      revisions: data.dec(_f$revisions),
      revsInfo: data.dec(_f$revsInfo),
      unmappedProps: data.dec(_f$unmappedProps),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PlayPosition fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PlayPosition>(map);
  }

  static PlayPosition fromJson(String json) {
    return ensureInitialized().decodeJson<PlayPosition>(json);
  }
}

mixin PlayPositionMappable {
  String toJson() {
    return PlayPositionMapper.ensureInitialized().encodeJson<PlayPosition>(
      this as PlayPosition,
    );
  }

  Map<String, dynamic> toMap() {
    return PlayPositionMapper.ensureInitialized().encodeMap<PlayPosition>(
      this as PlayPosition,
    );
  }

  PlayPositionCopyWith<PlayPosition, PlayPosition, PlayPosition> get copyWith =>
      _PlayPositionCopyWithImpl<PlayPosition, PlayPosition>(
        this as PlayPosition,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return PlayPositionMapper.ensureInitialized().stringifyValue(
      this as PlayPosition,
    );
  }

  @override
  bool operator ==(Object other) {
    return PlayPositionMapper.ensureInitialized().equalsValue(
      this as PlayPosition,
      other,
    );
  }

  @override
  int get hashCode {
    return PlayPositionMapper.ensureInitialized().hashValue(
      this as PlayPosition,
    );
  }
}

extension PlayPositionValueCopy<$R, $Out>
    on ObjectCopyWith<$R, PlayPosition, $Out> {
  PlayPositionCopyWith<$R, PlayPosition, $Out> get $asPlayPosition =>
      $base.as((v, t, t2) => _PlayPositionCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class PlayPositionCopyWith<$R, $In extends PlayPosition, $Out>
    implements CouchDocumentBaseCopyWith<$R, $In, $Out> {
  MapCopyWith<
    $R,
    String,
    PlayPositionItem,
    PlayPositionItemCopyWith<$R, PlayPositionItem, PlayPositionItem>
  >
  get items;
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
    String? deviceId,
    Map<String, PlayPositionItem>? items,
    String? id,
    String? rev,
    Map<String, AttachmentInfo>? attachments,
    bool? deleted,
    Revisions? revisions,
    List<RevsInfo>? revsInfo,
    Map<String, dynamic>? unmappedProps,
  });
  PlayPositionCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _PlayPositionCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PlayPosition, $Out>
    implements PlayPositionCopyWith<$R, PlayPosition, $Out> {
  _PlayPositionCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PlayPosition> $mapper =
      PlayPositionMapper.ensureInitialized();
  @override
  MapCopyWith<
    $R,
    String,
    PlayPositionItem,
    PlayPositionItemCopyWith<$R, PlayPositionItem, PlayPositionItem>
  >
  get items => MapCopyWith(
    $value.items,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(items: v),
  );
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
    String? deviceId,
    Map<String, PlayPositionItem>? items,
    Object? id = $none,
    Object? rev = $none,
    Object? attachments = $none,
    bool? deleted,
    Object? revisions = $none,
    Object? revsInfo = $none,
    Map<String, dynamic>? unmappedProps,
  }) => $apply(
    FieldCopyWithData({
      if (deviceId != null) #deviceId: deviceId,
      if (items != null) #items: items,
      if (id != $none) #id: id,
      if (rev != $none) #rev: rev,
      if (attachments != $none) #attachments: attachments,
      if (deleted != null) #deleted: deleted,
      if (revisions != $none) #revisions: revisions,
      if (revsInfo != $none) #revsInfo: revsInfo,
      if (unmappedProps != null) #unmappedProps: unmappedProps,
    }),
  );
  @override
  PlayPosition $make(CopyWithData data) => PlayPosition(
    deviceId: data.get(#deviceId, or: $value.deviceId),
    items: data.get(#items, or: $value.items),
    id: data.get(#id, or: $value.id),
    rev: data.get(#rev, or: $value.rev),
    attachments: data.get(#attachments, or: $value.attachments),
    deleted: data.get(#deleted, or: $value.deleted),
    revisions: data.get(#revisions, or: $value.revisions),
    revsInfo: data.get(#revsInfo, or: $value.revsInfo),
    unmappedProps: data.get(#unmappedProps, or: $value.unmappedProps),
  );

  @override
  PlayPositionCopyWith<$R2, PlayPosition, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PlayPositionCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class PlayPositionItemMapper extends ClassMapperBase<PlayPositionItem> {
  PlayPositionItemMapper._();

  static PlayPositionItemMapper? _instance;
  static PlayPositionItemMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PlayPositionItemMapper._());
      PlayPositionPointMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'PlayPositionItem';

  static String _$title(PlayPositionItem v) => v.title;
  static const Field<PlayPositionItem, String> _f$title = Field(
    'title',
    _$title,
    opt: true,
    def: '',
  );
  static PlayPositionPoint? _$position(PlayPositionItem v) => v.position;
  static const Field<PlayPositionItem, PlayPositionPoint> _f$position = Field(
    'position',
    _$position,
    opt: true,
  );
  static bool _$done(PlayPositionItem v) => v.done;
  static const Field<PlayPositionItem, bool> _f$done = Field(
    'done',
    _$done,
    opt: true,
    def: false,
  );

  @override
  final MappableFields<PlayPositionItem> fields = const {
    #title: _f$title,
    #position: _f$position,
    #done: _f$done,
  };
  @override
  final bool ignoreNull = true;

  static PlayPositionItem _instantiate(DecodingData data) {
    return PlayPositionItem(
      title: data.dec(_f$title),
      position: data.dec(_f$position),
      done: data.dec(_f$done),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PlayPositionItem fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PlayPositionItem>(map);
  }

  static PlayPositionItem fromJson(String json) {
    return ensureInitialized().decodeJson<PlayPositionItem>(json);
  }
}

mixin PlayPositionItemMappable {
  String toJson() {
    return PlayPositionItemMapper.ensureInitialized()
        .encodeJson<PlayPositionItem>(this as PlayPositionItem);
  }

  Map<String, dynamic> toMap() {
    return PlayPositionItemMapper.ensureInitialized()
        .encodeMap<PlayPositionItem>(this as PlayPositionItem);
  }

  PlayPositionItemCopyWith<PlayPositionItem, PlayPositionItem, PlayPositionItem>
  get copyWith =>
      _PlayPositionItemCopyWithImpl<PlayPositionItem, PlayPositionItem>(
        this as PlayPositionItem,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return PlayPositionItemMapper.ensureInitialized().stringifyValue(
      this as PlayPositionItem,
    );
  }

  @override
  bool operator ==(Object other) {
    return PlayPositionItemMapper.ensureInitialized().equalsValue(
      this as PlayPositionItem,
      other,
    );
  }

  @override
  int get hashCode {
    return PlayPositionItemMapper.ensureInitialized().hashValue(
      this as PlayPositionItem,
    );
  }
}

extension PlayPositionItemValueCopy<$R, $Out>
    on ObjectCopyWith<$R, PlayPositionItem, $Out> {
  PlayPositionItemCopyWith<$R, PlayPositionItem, $Out>
  get $asPlayPositionItem =>
      $base.as((v, t, t2) => _PlayPositionItemCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class PlayPositionItemCopyWith<$R, $In extends PlayPositionItem, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  PlayPositionPointCopyWith<$R, PlayPositionPoint, PlayPositionPoint>?
  get position;
  $R call({String? title, PlayPositionPoint? position, bool? done});
  PlayPositionItemCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _PlayPositionItemCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PlayPositionItem, $Out>
    implements PlayPositionItemCopyWith<$R, PlayPositionItem, $Out> {
  _PlayPositionItemCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PlayPositionItem> $mapper =
      PlayPositionItemMapper.ensureInitialized();
  @override
  PlayPositionPointCopyWith<$R, PlayPositionPoint, PlayPositionPoint>?
  get position => $value.position?.copyWith.$chain((v) => call(position: v));
  @override
  $R call({String? title, Object? position = $none, bool? done}) => $apply(
    FieldCopyWithData({
      if (title != null) #title: title,
      if (position != $none) #position: position,
      if (done != null) #done: done,
    }),
  );
  @override
  PlayPositionItem $make(CopyWithData data) => PlayPositionItem(
    title: data.get(#title, or: $value.title),
    position: data.get(#position, or: $value.position),
    done: data.get(#done, or: $value.done),
  );

  @override
  PlayPositionItemCopyWith<$R2, PlayPositionItem, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PlayPositionItemCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class PlayPositionPointMapper extends ClassMapperBase<PlayPositionPoint> {
  PlayPositionPointMapper._();

  static PlayPositionPointMapper? _instance;
  static PlayPositionPointMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PlayPositionPointMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'PlayPositionPoint';

  static int _$track(PlayPositionPoint v) => v.track;
  static const Field<PlayPositionPoint, int> _f$track = Field('track', _$track);
  static int _$seconds(PlayPositionPoint v) => v.seconds;
  static const Field<PlayPositionPoint, int> _f$seconds = Field(
    'seconds',
    _$seconds,
  );

  @override
  final MappableFields<PlayPositionPoint> fields = const {
    #track: _f$track,
    #seconds: _f$seconds,
  };

  static PlayPositionPoint _instantiate(DecodingData data) {
    return PlayPositionPoint(
      track: data.dec(_f$track),
      seconds: data.dec(_f$seconds),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PlayPositionPoint fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PlayPositionPoint>(map);
  }

  static PlayPositionPoint fromJson(String json) {
    return ensureInitialized().decodeJson<PlayPositionPoint>(json);
  }
}

mixin PlayPositionPointMappable {
  String toJson() {
    return PlayPositionPointMapper.ensureInitialized()
        .encodeJson<PlayPositionPoint>(this as PlayPositionPoint);
  }

  Map<String, dynamic> toMap() {
    return PlayPositionPointMapper.ensureInitialized()
        .encodeMap<PlayPositionPoint>(this as PlayPositionPoint);
  }

  PlayPositionPointCopyWith<
    PlayPositionPoint,
    PlayPositionPoint,
    PlayPositionPoint
  >
  get copyWith =>
      _PlayPositionPointCopyWithImpl<PlayPositionPoint, PlayPositionPoint>(
        this as PlayPositionPoint,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return PlayPositionPointMapper.ensureInitialized().stringifyValue(
      this as PlayPositionPoint,
    );
  }

  @override
  bool operator ==(Object other) {
    return PlayPositionPointMapper.ensureInitialized().equalsValue(
      this as PlayPositionPoint,
      other,
    );
  }

  @override
  int get hashCode {
    return PlayPositionPointMapper.ensureInitialized().hashValue(
      this as PlayPositionPoint,
    );
  }
}

extension PlayPositionPointValueCopy<$R, $Out>
    on ObjectCopyWith<$R, PlayPositionPoint, $Out> {
  PlayPositionPointCopyWith<$R, PlayPositionPoint, $Out>
  get $asPlayPositionPoint => $base.as(
    (v, t, t2) => _PlayPositionPointCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class PlayPositionPointCopyWith<
  $R,
  $In extends PlayPositionPoint,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({int? track, int? seconds});
  PlayPositionPointCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _PlayPositionPointCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PlayPositionPoint, $Out>
    implements PlayPositionPointCopyWith<$R, PlayPositionPoint, $Out> {
  _PlayPositionPointCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PlayPositionPoint> $mapper =
      PlayPositionPointMapper.ensureInitialized();
  @override
  $R call({int? track, int? seconds}) => $apply(
    FieldCopyWithData({
      if (track != null) #track: track,
      if (seconds != null) #seconds: seconds,
    }),
  );
  @override
  PlayPositionPoint $make(CopyWithData data) => PlayPositionPoint(
    track: data.get(#track, or: $value.track),
    seconds: data.get(#seconds, or: $value.seconds),
  );

  @override
  PlayPositionPointCopyWith<$R2, PlayPositionPoint, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PlayPositionPointCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

