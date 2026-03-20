import 'dart:convert';

import 'package:dart_couch/dart_couch.dart';
import 'package:test/test.dart';
import 'package:logging/logging.dart';

import 'helper/helper.dart';

void main() {

  Logger.root.level = Level.FINEST; // defaults to Level.INFO
  Logger.root.onRecord.listen((record) {
    LineSplitter ls = LineSplitter();
    for (final line in ls.convert(record.message)) {
      // ignore: avoid_print
      print('${record.loggerName} ${record.level.name}: ${record.time}: $line');
    }
  });

  group('HTTP', () {
    doTest(setUpAllHttpFunction, tearDownAllHttpFunction);
  });

  group('Local', () {
    doTest(setUpAllLocalFunction, null);
  });
}

void doTest(
  Future<DartCouchServer> Function() setupAll,
  Future<void> Function()? tearDown,
) {
  late DartCouchServer cl;

  setUpAll(() async {
    cl = await setupAll();
  });
  tearDownAll(() async {
    if (tearDown != null) await tearDown();
  });

  test('manage index and check documents', () async {
    // Create a test database
    final dbName = 'index_test_db';
    final db = await cl.createDatabase(dbName);

    // Define the index we want to create
    final indexDef = IndexDefinition(
      fields: [
        {'name': SortOrder.asc},
      ],
    );

    // Step 1: Create an index
    final indexName = await db.createIndex(
      index: indexDef,
      ddoc: 'test_ddoc',
      name: 'name_index',
    );

    expect(indexName, equals('name_index'));

    // Step 2: Retrieve the design document and verify its content
    final designDoc = await db.get('_design/test_ddoc');
    expect(designDoc, isNotNull);
    expect(designDoc!.id, equals('_design/test_ddoc'));

    // Parse as IndexDocument to verify structure
    log.fine('Design Document JSON: ${designDoc.toJson()}');
    final m = designDoc.toMap();
    log.fine('Design Document JSON as map: $m');
    final indexDoc = IndexDocument.fromMap(m);
    expect(indexDoc.language, equals('query'));
    expect(indexDoc.views.containsKey('name_index'), isTrue);

    final indexView = indexDoc.views['name_index']!;
    expect(indexView.map.fields, containsPair('name', SortOrder.asc));
    expect(indexView.reduce, equals('_count'));
    expect(indexView.options, isNotNull);
    expect(indexView.options!.def.fields.length, equals(1));
    expect(indexView.options!.def.fields[0]['name'], equals(SortOrder.asc));

    // Verify the map is a proper Map, not a String
    expect(indexView.map, isA<IndexMap>());
    expect(indexView.map.fields, isA<Map<String, SortOrder>>());

    // Step 3: Get the list of indexes and verify our index is there
    final indexList = await db.getIndexes();
    expect(
      indexList.indexes.length,
      greaterThanOrEqualTo(2),
    ); // at least all_docs + our index

    // Find the special all_docs index
    final allDocsIndex = indexList.indexes.firstWhere(
      (idx) => idx.name == '_all_docs' && idx.type == 'special',
    );
    expect(allDocsIndex, isNotNull);
    expect(allDocsIndex.ddoc, isNull); // all_docs has no design doc

    // Find our created index
    final ourIndex = indexList.indexes.firstWhere(
      (idx) => idx.name == 'name_index' && idx.ddoc == '_design/test_ddoc',
    );
    expect(ourIndex, isNotNull);
    expect(ourIndex.type, equals('json'));
    expect(ourIndex.def.fields.length, equals(1));
    expect(ourIndex.def.fields[0]['name'], equals(SortOrder.asc));

    // Step 4: Create a second index in the same design document
    final indexDef2 = IndexDefinition(
      fields: [
        {'name': SortOrder.desc},
      ],
    );

    final indexName2 = await db.createIndex(
      index: indexDef2,
      ddoc: 'test_ddoc',
      name: 'name_index_desc',
    );

    expect(indexName2, equals('name_index_desc'));

    // Verify the design doc now has both indexes
    final designDoc2 = await db.get('_design/test_ddoc');
    final indexDoc2 = IndexDocument.fromMap(designDoc2!.toMap());
    expect(indexDoc2.views.length, equals(2));
    expect(indexDoc2.views.containsKey('name_index'), isTrue);
    expect(indexDoc2.views.containsKey('name_index_desc'), isTrue);

    // Step 5: Delete one index (not the whole design doc)
    final deleted1 = await db.deleteIndex(
      designDoc: 'test_ddoc',
      name: 'name_index_desc',
    );
    expect(deleted1, isTrue);

    // Verify the design doc still exists with only one index
    final designDocAfterDelete1 = await db.get('_design/test_ddoc');
    expect(designDocAfterDelete1, isNotNull);
    final indexDocAfterDelete1 = IndexDocument.fromMap(
      designDocAfterDelete1!.toMap(),
    );
    expect(indexDocAfterDelete1.views.length, equals(1));
    expect(indexDocAfterDelete1.views.containsKey('name_index'), isTrue);
    expect(indexDocAfterDelete1.views.containsKey('name_index_desc'), isFalse);

    // Step 6: Delete the last index (should remove the whole design doc)
    final deleted2 = await db.deleteIndex(
      designDoc: 'test_ddoc',
      name: 'name_index',
    );
    expect(deleted2, isTrue);

    // Step 7: Verify the design document is gone
    final designDocAfterDelete2 = await db.get('_design/test_ddoc');
    expect(designDocAfterDelete2, isNull);

    // Step 8: Verify only all_docs index remains
    final finalIndexList = await db.getIndexes();
    expect(finalIndexList.indexes.length, equals(1));
    expect(finalIndexList.indexes[0].name, equals('_all_docs'));
    expect(finalIndexList.indexes[0].type, equals('special'));

    // Test error handling: try to delete non-existent index
    expect(
      () async =>
          await db.deleteIndex(designDoc: 'test_ddoc', name: 'nonexistent'),
      throwsA(isA<CouchDbException>()),
    );

    // Clean up
    await cl.deleteDatabase(dbName);
  });

  test('complex index definition', () async {
    // Create a test database
    final dbName = 'complex_index_test_db';
    final db = await cl.createDatabase(dbName);

    // Define a complex index with partial filter selector
    final complexIndexDef = IndexDefinition(
      fields: [
        {'_id': SortOrder.asc},
        {'_rev': SortOrder.asc},
        {'year': SortOrder.asc},
        {'title': SortOrder.asc},
      ],
      partialFilterSelector: {
        'year': {'\$gt': 2010},
      },
    );

    // Create the complex index
    final indexName = await db.createIndex(
      index: complexIndexDef,
      ddoc: 'example-ddoc',
      name: 'example-index',
      type: 'json',
      partitioned: false,
    );

    expect(indexName, equals('example-index'));

    // Retrieve the design document
    final designDoc = await db.get('_design/example-ddoc');
    expect(designDoc, isNotNull);

    // Convert to JSON and parse back to verify exact structure
    final designDocJson = designDoc!.toJson();
    final designDocMap = jsonDecode(designDocJson) as Map<String, dynamic>;

    // Verify top-level fields
    expect(designDocMap['_id'], equals('_design/example-ddoc'));
    expect(designDocMap['_rev'], isNotNull);
    expect(designDocMap['language'], equals('query'));
    expect(designDocMap['views'], isNotNull);

    // Verify the views structure
    final views = designDocMap['views'] as Map<String, dynamic>;
    expect(views.containsKey('example-index'), isTrue);

    final exampleIndexView = views['example-index'] as Map<String, dynamic>;

    // Verify the map fields structure
    expect(exampleIndexView['map'], isNotNull);
    final mapFields = exampleIndexView['map'] as Map<String, dynamic>;
    expect(mapFields['fields'], isNotNull);

    final fields = mapFields['fields'] as Map<String, dynamic>;
    expect(fields['_id'], equals('asc'));
    expect(fields['_rev'], equals('asc'));
    expect(fields['year'], equals('asc'));
    expect(fields['title'], equals('asc'));

    // Verify reduce
    expect(exampleIndexView['reduce'], equals('_count'));

    // Verify options and def structure
    expect(exampleIndexView['options'], isNotNull);
    final options = exampleIndexView['options'] as Map<String, dynamic>;
    expect(options['def'], isNotNull);

    final def = options['def'] as Map<String, dynamic>;

    // Verify partial_filter_selector
    expect(def['partial_filter_selector'], isNotNull);
    final partialFilter =
        def['partial_filter_selector'] as Map<String, dynamic>;
    expect(partialFilter['year'], isNotNull);
    final yearFilter = partialFilter['year'] as Map<String, dynamic>;
    expect(yearFilter['\$gt'], equals(2010));

    // Verify fields in def
    expect(def['fields'], isNotNull);
    final defFields = def['fields'] as List<dynamic>;
    expect(defFields.length, equals(4));

    // Check each field definition
    expect(defFields[0], isA<Map<String, dynamic>>());
    expect((defFields[0] as Map<String, dynamic>)['_id'], equals('asc'));
    expect((defFields[1] as Map<String, dynamic>)['_rev'], equals('asc'));
    expect((defFields[2] as Map<String, dynamic>)['year'], equals('asc'));
    expect((defFields[3] as Map<String, dynamic>)['title'], equals('asc'));

    // Parse as IndexDocument using the mapper
    final indexDoc = IndexDocument.fromMap(designDocMap);
    expect(indexDoc.language, equals('query'));
    expect(indexDoc.views.containsKey('example-index'), isTrue);

    final indexView = indexDoc.views['example-index']!;

    // Verify the IndexView structure
    expect(indexView.map.fields.length, equals(4));
    expect(indexView.map.fields['_id'], equals(SortOrder.asc));
    expect(indexView.map.fields['_rev'], equals(SortOrder.asc));
    expect(indexView.map.fields['year'], equals(SortOrder.asc));
    expect(indexView.map.fields['title'], equals(SortOrder.asc));
    expect(indexView.reduce, equals('_count'));

    // Verify the options and definition
    expect(indexView.options, isNotNull);
    expect(indexView.options!.def, isNotNull);

    final indexDef = indexView.options!.def;
    expect(indexDef.fields.length, equals(4));
    expect(indexDef.fields[0]['_id'], equals(SortOrder.asc));
    expect(indexDef.fields[1]['_rev'], equals(SortOrder.asc));
    expect(indexDef.fields[2]['year'], equals(SortOrder.asc));
    expect(indexDef.fields[3]['title'], equals(SortOrder.asc));

    // Verify partial filter selector
    expect(indexDef.partialFilterSelector, isNotNull);
    expect(indexDef.partialFilterSelector!['year'], isNotNull);
    expect(indexDef.partialFilterSelector!['year']['\$gt'], equals(2010));

    // Verify the index appears in the index list
    final indexList = await db.getIndexes();
    final complexIndex = indexList.indexes.firstWhere(
      (idx) =>
          idx.name == 'example-index' && idx.ddoc == '_design/example-ddoc',
    );

    expect(complexIndex, isNotNull);
    expect(complexIndex.type, equals('json'));
    // Note: partitioned may be null for local implementation
    // as it's not stored in the design document
    expect(complexIndex.partitioned, anyOf(equals(false), isNull));
    expect(complexIndex.def.fields.length, equals(4));
    expect(complexIndex.def.partialFilterSelector, isNotNull);
    expect(
      complexIndex.def.partialFilterSelector!['year']['\$gt'],
      equals(2010),
    );

    // Clean up
    await db.deleteIndex(designDoc: 'example-ddoc', name: 'example-index');
    await cl.deleteDatabase(dbName);
  });
}
