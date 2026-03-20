import 'package:dart_mappable/dart_mappable.dart';

import 'package:dart_couch/dart_couch.dart';

part 'test_document_one.mapper.dart';

@MappableClass(discriminatorValue: 'test_document_one')
class TestDocumentOne extends CouchDocumentBase with TestDocumentOneMappable {
  @MappableField()
  final String name;

  TestDocumentOne({
    required this.name,
    required super.id,
    super.rev,
    super.attachments,
    super.revisions,
    super.revsInfo,
    super.deleted,
    super.unmappedProps,
  });

  static final fromMap = TestDocumentOneMapper.fromMap;
  static final fromJson = TestDocumentOneMapper.fromJson;
}
