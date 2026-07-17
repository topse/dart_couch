import 'package:dart_mappable/dart_mappable.dart';
import 'package:dart_couch/dart_couch.dart';

part 'einkaufslist_item.mapper.dart';

@MappableClass(discriminatorValue: 'einkaufslist_item')
class EinkaufslistItem extends CouchDocumentBase with EinkaufslistItemMappable {
  @MappableField()
  final String name;
  @MappableField()
  final bool erledigt;
  @MappableField()
  final int anzahl;
  @MappableField()
  final String einheit;
  @MappableField()
  final String category;
  EinkaufslistItem({
    required this.name,
    required this.erledigt,
    required this.anzahl,
    required this.einheit,
    required this.category,
    super.id,
    super.rev,
    super.attachments,
    super.revisions,
    super.revsInfo,
    super.deleted,
    super.unmappedProps,
  });
  static final fromMap = EinkaufslistItemMapper.fromMap;
  static final fromJson = EinkaufslistItemMapper.fromJson;
}

@MappableClass(discriminatorValue: 'einkaufslist_category')
class EinkaufslistCategory extends CouchDocumentBase
    with EinkaufslistCategoryMappable {
  @MappableField()
  final String name;
  @MappableField()
  final int sorthint;

  EinkaufslistCategory({
    required this.name,
    required this.sorthint,
    super.id,
    super.rev,
    super.attachments,
    super.revisions,
    super.revsInfo,
    super.deleted,
    super.unmappedProps,
  });

  static final fromMap = EinkaufslistCategoryMapper.fromMap;
  static final fromJson = EinkaufslistCategoryMapper.fromJson;
}
