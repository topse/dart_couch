import 'package:dart_mappable/dart_mappable.dart';

import 'couch_document_base.dart';

part 'deleted_document.mapper.dart';

@MappableClass(discriminatorValue: '!deleted_document')
class DeletedDocument extends CouchDocumentBase with DeletedDocumentMappable {
  DeletedDocument({
    required super.id,
    required super.rev,
    super.attachments,
    super.revisions,
    super.revsInfo,
    super.deleted,
    super.unmappedProps,
  });

  static final fromMap = DeletedDocumentMapper.fromMap;
  static final fromJson = DeletedDocumentMapper.fromJson;
}
