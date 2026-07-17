import 'package:dart_mappable/dart_mappable.dart';
import 'package:dart_couch/dart_couch.dart';

part 'multi_inheritance_test.mapper.dart';

@MappableClass(discriminatorValue: 'Base')
class Base extends CouchDocumentBase with BaseMappable {
  @MappableField()
  final String name;

  Base({
    required this.name,
    super.id,
    super.attachments,
    super.deleted,
    super.rev,
    super.revisions,
    super.revsInfo,
    super.unmappedProps,
  });
}

/*@MappableClass(discriminatorValue: 'A')
class A extends Base with AMappable {
  @MappableField()
  final int valueA;

  A({
    required this.valueA,
    required super.name,
    super.id,
    super.attachments,
    super.deleted,
    super.rev,
    super.revisions,
    super.revsInfo,
    super.unmappedProps,
  });
}*/

void main() {
  DartCouchDb.ensureInitialized();
  BaseMapper.ensureInitialized();
  //AMapper.ensureInitialized();
}
