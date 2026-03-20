import 'package:dart_mappable/dart_mappable.dart';

part 'bulk_get.mapper.dart';

@MappableClass()
class BulkGetRequest with BulkGetRequestMappable {
  @MappableField()
  final List<BulkGetRequestDoc> docs;

  BulkGetRequest({required this.docs});

  static final fromMap = BulkGetRequestMapper.fromMap;
  static final fromJson = BulkGetRequestMapper.fromJson;
}

@MappableClass()
class BulkGetRequestDoc with BulkGetRequestDocMappable {
  @MappableField()
  final String id;
  @MappableField()
  final String? rev;
  @MappableField(key: 'atts_since')
  final List<String>? attsSince;

  BulkGetRequestDoc({required this.id, this.rev, this.attsSince});
}
