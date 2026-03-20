import 'package:dart_mappable/dart_mappable.dart';
import 'package:dart_couch/dart_couch.dart';

part 'view_result.mapper.dart';

@MappableClass()
class ViewResult with ViewResultMappable {
  @MappableField(key: 'total_rows')
  /// maybe null in case of _local_docs
  final int? totalRows;

  /// This field represents the number of documents that have
  /// already been skipped (or excluded) from the current
  /// result set. It's used in conjunction with limit to
  /// implement pagination. For example, if limit is 10 and
  /// offset is 20, you’re requesting the next 10 results after
  /// skipping the first 20.
  ///
  /// maybe null in case of _local_docs
  @MappableField()
  final int? offset;
  @MappableField()
  final List<ViewEntry> rows;

  ViewResult({
    required this.totalRows,
    required this.offset,
    required this.rows,
  });

  static final fromMap = ViewResultMapper.fromMap;
  static final fromJson = ViewResultMapper.fromJson;
}

@MappableClass()
class ViewEntry with ViewEntryMappable {
  @MappableField()
  final String? id;
  @MappableField()
  final dynamic key;
  @MappableField()
  final dynamic value;
  @MappableField()
  final String? error;

  @MappableField()
  final CouchDocumentBase? doc;

  ViewEntry({this.id, this.key, this.value, this.error, this.doc});
}
