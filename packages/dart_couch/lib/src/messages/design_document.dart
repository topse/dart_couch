import 'package:dart_mappable/dart_mappable.dart';

import 'couch_document_base.dart';

part 'design_document.mapper.dart';

@MappableClass(discriminatorValue: '_design_doc')
class DesignDocument extends CouchDocumentBase with DesignDocumentMappable {
  // https://docs.couchdb.org/en/stable/ddocs/ddocs.html

  final Map<String, ViewData>? views;
  final Map<String, String>? updates;
  final Map<String, String>? filters;

  @MappableField(key: 'validate_doc_update')
  final String? validateDocUpdate;

  final String language;

  DesignDocument({
    required super.id,
    super.rev,
    super.deleted = false,
    this.views,
    this.updates,
    this.filters,
    this.validateDocUpdate,
    this.language = "javascript",
    super.attachments,
    super.revisions,
    super.revsInfo,
    super.unmappedProps,
  });

  static final fromMap = DesignDocumentMapper.fromMap;
  static final fromJson = DesignDocumentMapper.fromJson;
}

@MappableClass(ignoreNull: true)
class ViewData with ViewDataMappable {
  final String map;
  final String? reduce;

  const ViewData({required this.map, this.reduce});
}
