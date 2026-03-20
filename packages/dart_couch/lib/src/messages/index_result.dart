import 'package:dart_mappable/dart_mappable.dart';

part 'index_result.mapper.dart';

/// {
///     "index": {
///         "partial_filter_selector": {
///             "year": {
///                 "$gt": 2010
///             },
///             "limit": 10,
///             "skip": 0
///         },
///         "fields": [
///             "_id",
///             "_rev",
///             "year",
///             "title"
///         ]
///     },
///     "ddoc": "example-ddoc",
///     "name": "example-index",
///     "type": "json",
///     "partitioned": false
/// }

@MappableClass()
class IndexResultList with IndexResultListMappable {
  @MappableField(key: 'total_rows')
  final int totalRows;

  @MappableField()
  final List<IndexResult> indexes;

  IndexResultList({required this.totalRows, required this.indexes});

  static final fromMap = IndexResultListMapper.fromMap;
  static final fromJson = IndexResultListMapper.fromJson;
}

@MappableClass(ignoreNull: true)
class IndexResult with IndexResultMappable {
  @MappableField()
  final String? ddoc;
  @MappableField()
  final String name;
  @MappableField()
  final String type;
  @MappableField()
  final bool? partitioned;

  @MappableField()
  final IndexDefinition def;

  IndexResult({
    required this.ddoc,
    required this.name,
    required this.type,
    required this.partitioned,
    required this.def,
  });

  static final fromMap = IndexResultMapper.fromMap;
  static final fromJson = IndexResultMapper.fromJson;
}

@MappableClass(ignoreNull: true)
class IndexRequest with IndexRequestMappable {
  @MappableField()
  final String? ddoc;
  @MappableField()
  final String name;
  @MappableField()
  final String type;
  @MappableField()
  final bool? partitioned;

  @MappableField()
  final IndexDefinition index;

  IndexRequest({
    required this.ddoc,
    required this.name,
    required this.type,
    required this.partitioned,
    required this.index,
  });

  static final fromMap = IndexResultMapper.fromMap;
  static final fromJson = IndexResultMapper.fromJson;
}

@MappableClass(ignoreNull: true)
class IndexDefinition with IndexDefinitionMappable {
  @MappableField(key: 'partial_filter_selector')
  final Map<String, dynamic>? partialFilterSelector;

  /// Field order specification. Each entry is a map where the key is the
  /// field name and the value is the sort order (`asc` or `desc`). Example:
  /// `[{'foo': SortOrder.asc}, {'bar': SortOrder.desc}]`.
  @MappableField()
  final List<Map<String, SortOrder>> fields;

  IndexDefinition({required this.fields, this.partialFilterSelector});
}

@MappableEnum()
enum SortOrder { asc, desc }

/// Example index document:
/// {
///   "_id": "_design/idx-1b14c5d5dc0a4243e4ce98acefa23933",
///   "_rev": "1-dcc80563a8a2a37e299175df4ea4e420",
///   "language": "query",
///   "views": {
///     "idx-1b14c5d5dc0a4243e4ce98acefa23933": {
///       "map": {
///         "fields": {
///           "type": "asc",
///           "sorthint": "asc"
///         }
///       },
///       "reduce": "_count",
///       "options": {
///         "def": {
///           "fields": [
///             "type",
///             "sorthint"
///           ]
///         }
///       }
///     }
///   }
/// }

@MappableClass()
class IndexDocument with IndexDocumentMappable {
  @MappableField(key: '_id')
  final String id;
  @MappableField(key: '_rev')
  final String? rev;

  @MappableField()
  final String language;

  @MappableField()
  final Map<String, IndexView> views;

  IndexDocument({
    required this.id,
    this.rev,
    required this.language,
    required this.views,
  });

  static final fromMap = IndexDocumentMapper.fromMap;
  static final fromJson = IndexDocumentMapper.fromJson;
}

@MappableClass()
class IndexView with IndexViewMappable {
  @MappableField()
  final IndexMap map;
  @MappableField()
  final String? reduce;
  @MappableField()
  final IndexOptions? options;
  IndexView({required this.map, this.reduce, this.options});

  static final fromMap = IndexViewMapper.fromMap;
  static final fromJson = IndexViewMapper.fromJson;
}

@MappableClass()
class IndexMap with IndexMapMappable {
  @MappableField()
  final Map<String, SortOrder> fields;
  IndexMap({required this.fields});

  static final fromMap = IndexMapMapper.fromMap;
  static final fromJson = IndexMapMapper.fromJson;
}

@MappableClass()
class IndexOptions with IndexOptionsMappable {
  @MappableField()
  final IndexDefinition def;
  IndexOptions({required this.def});

  static final fromMap = IndexOptionsMapper.fromMap;
  static final fromJson = IndexOptionsMapper.fromJson;
}
