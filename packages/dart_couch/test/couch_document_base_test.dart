import 'dart:convert';

import 'package:dart_couch/dart_couch.dart';
import 'package:test/test.dart';

import 'helper/einkaufslist_item.dart';
import 'helper/test_document_one.dart';

String designDoc = '''{
  "_id": "_design/my_design_doc",
  "_rev": "2-6899d30fcf19436daeee53f11ae34d67",
  "views": {
    "testview": {
      "map": "function(doc) {\\n    if(doc.date && doc.title) {\\n        emit(doc.date, doc.title);\\n    }\\n}"
    }
  },
      "updates": {
        "updatefun1": "function(doc,req) {/* function code here - see below */}",
        "updatefun2": "function(doc,req) {/* function code here - see below */}"
    },
    "filters": {
        "filterfunction1": "function(doc, req){ /* function code here - see below */ }"
    },
    "validate_doc_update": "function(newDoc, oldDoc, userCtx, secObj) { /* function code here - see below */ }",
    "language": "javascript"
}''';

void main() {
  DartCouchDb.ensureInitialized();
  test("design documents", () {
    TestDocumentOne td1 = TestDocumentOne(id: "test", name: "test");
    final td2 = CouchDocumentBase.fromJson(td1.toJson());
    expect(td2, isA<TestDocumentOne>());

    final doc = CouchDocumentBase.fromJson(designDoc);
    expect(doc, isA<DesignDocument>());
    String s = doc.toJson();
    expect(s.contains('!doc_type'), isFalse);

    final td3 = td1.toMap();
    td3['INVALID'] = 'INVALID';
    final td4 = CouchDocumentBase.fromJson(json.encode(td3));
    expect(td4.unmappedProps.length, 1);
    expect(td4.unmappedProps.keys.first, equals("INVALID"));
    expect(td4.toJson(), contains("INVALID"));
  });

  test(
    'check behaviour of unknown !doc_type values',
    () {
      final jsonStr = '''{
      "_id": "some_id",
      "!doc_type": "unknown_type",
      "some_field": "some_value"
    }''';

      final doc = CouchDocumentBase.fromJson(jsonStr);
      expect(doc, isA<CouchDocumentBase>());
      expect(doc.id, equals("some_id"));
      expect(doc.unmappedProps['some_field'], equals("some_value"));

      final rejson = doc.toJson();
      expect(rejson.contains('"!doc_type":"unknown_type"'), isTrue);

      EinkaufslistItem item = EinkaufslistItem(
        id: "item1",
        name: "Milk",
        erledigt: false,
        anzahl: 1,
        einheit: '',
        category: '',
      );

      expect(item.toJson(), contains('"!doc_type":"einkaufslist_item"'));
      expect(item.toMap()['!doc_type'], equals("einkaufslist_item"));

      expect(
        CouchDocumentBase.fromJson(item.toJson()),
        isA<EinkaufslistItem>(),
      );
      expect(
        CouchDocumentBase.fromJson(item.toJson()).toMap()['!doc_type'],
        equals('einkaufslist_item'),
      );
    },
    skip:
        "This test currently fails due to missing support for unknown discriminator values. When a document with an unrecognized !doc_type is decoded, it defaults to CouchDocumentBase, but the !doc_type field is not preserved during encoding. This needs to be addressed in the mapping logic to ensure that unknown types retain their discriminator value upon re-encoding.",
  );
}
