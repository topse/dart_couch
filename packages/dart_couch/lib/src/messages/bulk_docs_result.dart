import 'package:dart_mappable/dart_mappable.dart';

part 'bulk_docs_result.mapper.dart';

@MappableClass()
class BulkDocsResult with BulkDocsResultMappable {
  @MappableField()
  final String id;
  @MappableField()
  final bool? ok;
  @MappableField()
  final String? rev;
  @MappableField()
  final String? error;
  @MappableField()
  final String? reason;

  const BulkDocsResult({
    required this.id,
    this.ok,
    this.rev,
    this.error,
    this.reason,
  });

  static final fromMap = BulkDocsResultMapper.fromMap;
  static final fromJson = BulkDocsResultMapper.fromJson;
}
