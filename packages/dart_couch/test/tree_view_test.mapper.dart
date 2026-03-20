// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'tree_view_test.dart';

class TreeNodeMapper extends SubClassMapperBase<TreeNode> {
  TreeNodeMapper._();

  static TreeNodeMapper? _instance;
  static TreeNodeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TreeNodeMapper._());
      CouchDocumentBaseMapper.ensureInitialized().addSubMapper(_instance!);
      AttachmentInfoMapper.ensureInitialized();
      RevisionsMapper.ensureInitialized();
      RevsInfoMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'TreeNode';

  static String _$name(TreeNode v) => v.name;
  static const Field<TreeNode, String> _f$name = Field('name', _$name);
  static String? _$parent(TreeNode v) => v.parent;
  static const Field<TreeNode, String> _f$parent = Field(
    'parent',
    _$parent,
    opt: true,
  );
  static String? _$id(TreeNode v) => v.id;
  static const Field<TreeNode, String> _f$id = Field(
    'id',
    _$id,
    key: r'_id',
    opt: true,
  );
  static String? _$rev(TreeNode v) => v.rev;
  static const Field<TreeNode, String> _f$rev = Field(
    'rev',
    _$rev,
    key: r'_rev',
    opt: true,
  );
  static bool _$deleted(TreeNode v) => v.deleted;
  static const Field<TreeNode, bool> _f$deleted = Field(
    'deleted',
    _$deleted,
    key: r'_deleted',
    opt: true,
    def: false,
  );
  static Map<String, AttachmentInfo>? _$attachments(TreeNode v) =>
      v.attachments;
  static const Field<TreeNode, Map<String, AttachmentInfo>> _f$attachments =
      Field('attachments', _$attachments, key: r'_attachments', opt: true);
  static Revisions? _$revisions(TreeNode v) => v.revisions;
  static const Field<TreeNode, Revisions> _f$revisions = Field(
    'revisions',
    _$revisions,
    key: r'_revisions',
    opt: true,
  );
  static List<RevsInfo>? _$revsInfo(TreeNode v) => v.revsInfo;
  static const Field<TreeNode, List<RevsInfo>> _f$revsInfo = Field(
    'revsInfo',
    _$revsInfo,
    key: r'_revs_info',
    opt: true,
  );
  static Map<String, dynamic> _$unmappedProps(TreeNode v) => v.unmappedProps;
  static const Field<TreeNode, Map<String, dynamic>> _f$unmappedProps = Field(
    'unmappedProps',
    _$unmappedProps,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<TreeNode> fields = const {
    #name: _f$name,
    #parent: _f$parent,
    #id: _f$id,
    #rev: _f$rev,
    #deleted: _f$deleted,
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
  final dynamic discriminatorValue = 'tree_node';
  @override
  late final ClassMapperBase superMapper =
      CouchDocumentBaseMapper.ensureInitialized();

  @override
  final MappingHook superHook = const ChainedHook([
    CouchDocumentBaseRawHook(),
    UnmappedPropertiesHook('unmappedProps'),
  ]);

  static TreeNode _instantiate(DecodingData data) {
    return TreeNode(
      name: data.dec(_f$name),
      parent: data.dec(_f$parent),
      id: data.dec(_f$id),
      rev: data.dec(_f$rev),
      deleted: data.dec(_f$deleted),
      attachments: data.dec(_f$attachments),
      revisions: data.dec(_f$revisions),
      revsInfo: data.dec(_f$revsInfo),
      unmappedProps: data.dec(_f$unmappedProps),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TreeNode fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TreeNode>(map);
  }

  static TreeNode fromJson(String json) {
    return ensureInitialized().decodeJson<TreeNode>(json);
  }
}

mixin TreeNodeMappable {
  String toJson() {
    return TreeNodeMapper.ensureInitialized().encodeJson<TreeNode>(
      this as TreeNode,
    );
  }

  Map<String, dynamic> toMap() {
    return TreeNodeMapper.ensureInitialized().encodeMap<TreeNode>(
      this as TreeNode,
    );
  }

  TreeNodeCopyWith<TreeNode, TreeNode, TreeNode> get copyWith =>
      _TreeNodeCopyWithImpl<TreeNode, TreeNode>(
        this as TreeNode,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return TreeNodeMapper.ensureInitialized().stringifyValue(this as TreeNode);
  }

  @override
  bool operator ==(Object other) {
    return TreeNodeMapper.ensureInitialized().equalsValue(
      this as TreeNode,
      other,
    );
  }

  @override
  int get hashCode {
    return TreeNodeMapper.ensureInitialized().hashValue(this as TreeNode);
  }
}

extension TreeNodeValueCopy<$R, $Out> on ObjectCopyWith<$R, TreeNode, $Out> {
  TreeNodeCopyWith<$R, TreeNode, $Out> get $asTreeNode =>
      $base.as((v, t, t2) => _TreeNodeCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class TreeNodeCopyWith<$R, $In extends TreeNode, $Out>
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
    String? parent,
    String? id,
    String? rev,
    bool? deleted,
    Map<String, AttachmentInfo>? attachments,
    Revisions? revisions,
    List<RevsInfo>? revsInfo,
    Map<String, dynamic>? unmappedProps,
  });
  TreeNodeCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _TreeNodeCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, TreeNode, $Out>
    implements TreeNodeCopyWith<$R, TreeNode, $Out> {
  _TreeNodeCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<TreeNode> $mapper =
      TreeNodeMapper.ensureInitialized();
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
    Object? parent = $none,
    Object? id = $none,
    Object? rev = $none,
    bool? deleted,
    Object? attachments = $none,
    Object? revisions = $none,
    Object? revsInfo = $none,
    Map<String, dynamic>? unmappedProps,
  }) => $apply(
    FieldCopyWithData({
      if (name != null) #name: name,
      if (parent != $none) #parent: parent,
      if (id != $none) #id: id,
      if (rev != $none) #rev: rev,
      if (deleted != null) #deleted: deleted,
      if (attachments != $none) #attachments: attachments,
      if (revisions != $none) #revisions: revisions,
      if (revsInfo != $none) #revsInfo: revsInfo,
      if (unmappedProps != null) #unmappedProps: unmappedProps,
    }),
  );
  @override
  TreeNode $make(CopyWithData data) => TreeNode(
    name: data.get(#name, or: $value.name),
    parent: data.get(#parent, or: $value.parent),
    id: data.get(#id, or: $value.id),
    rev: data.get(#rev, or: $value.rev),
    deleted: data.get(#deleted, or: $value.deleted),
    attachments: data.get(#attachments, or: $value.attachments),
    revisions: data.get(#revisions, or: $value.revisions),
    revsInfo: data.get(#revsInfo, or: $value.revsInfo),
    unmappedProps: data.get(#unmappedProps, or: $value.unmappedProps),
  );

  @override
  TreeNodeCopyWith<$R2, TreeNode, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _TreeNodeCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

