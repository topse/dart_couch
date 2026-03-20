import 'package:test/test.dart';
import 'package:dart_couch/dart_couch.dart';
import 'dart:convert';
import 'package:logging/logging.dart';

import 'helper/helper.dart';

void main() {
  DartCouchDb.ensureInitialized();

  Logger.root.level = Level.FINEST;
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

  test('_count reduce without grouping', () async {
    final dbName = 'test_reduce_count';
    final db = await cl.createDatabase(dbName);

    // Create documents with categories
    await db.put(
      CouchDocumentBase(
        id: 'doc1',
        unmappedProps: {'category': 'fruit', 'name': 'Apple'},
      ),
    );
    await db.put(
      CouchDocumentBase(
        id: 'doc2',
        unmappedProps: {'category': 'fruit', 'name': 'Banana'},
      ),
    );
    await db.put(
      CouchDocumentBase(
        id: 'doc3',
        unmappedProps: {'category': 'vegetable', 'name': 'Carrot'},
      ),
    );

    // Create view with _count reduce
    await db.put(
      DesignDocument(
        id: '_design/test',
        views: {
          'by_category': ViewData(
            map:
                'function(doc) { if (doc.category) { emit(doc.category, 1); } }',
            reduce: '_count',
          ),
        },
      ),
    );

    // Test reduce=true without grouping: should return single row with total count
    final result = await db.query('test/by_category');
    expect(result, isNotNull);
    expect(result!.rows, hasLength(1));
    expect(result.rows[0].key, isNull);
    expect(result.rows[0].value, equals(3));

    await cl.deleteDatabase(dbName);
  });

  test('_count reduce with group=true', () async {
    final dbName = 'test_reduce_count_group';
    final db = await cl.createDatabase(dbName);

    await db.put(
      CouchDocumentBase(
        id: 'doc1',
        unmappedProps: {'category': 'fruit', 'name': 'Apple'},
      ),
    );
    await db.put(
      CouchDocumentBase(
        id: 'doc2',
        unmappedProps: {'category': 'fruit', 'name': 'Banana'},
      ),
    );
    await db.put(
      CouchDocumentBase(
        id: 'doc3',
        unmappedProps: {'category': 'vegetable', 'name': 'Carrot'},
      ),
    );
    await db.put(
      CouchDocumentBase(
        id: 'doc4',
        unmappedProps: {'category': 'vegetable', 'name': 'Daikon'},
      ),
    );

    await db.put(
      DesignDocument(
        id: '_design/test',
        views: {
          'by_category': ViewData(
            map:
                'function(doc) { if (doc.category) { emit(doc.category, 1); } }',
            reduce: '_count',
          ),
        },
      ),
    );

    // Test grouped reduce
    final result = await db.query('test/by_category', group: true);
    expect(result, isNotNull);
    expect(result!.rows, hasLength(2));
    // Results should be sorted by key
    expect(result.rows[0].key, equals('fruit'));
    expect(result.rows[0].value, equals(2));
    expect(result.rows[1].key, equals('vegetable'));
    expect(result.rows[1].value, equals(2));

    await cl.deleteDatabase(dbName);
  });

  test('_count reduce with reduce=false returns map results', () async {
    final dbName = 'test_reduce_false';
    final db = await cl.createDatabase(dbName);

    await db.put(
      CouchDocumentBase(
        id: 'doc1',
        unmappedProps: {'category': 'fruit', 'name': 'Apple'},
      ),
    );
    await db.put(
      CouchDocumentBase(
        id: 'doc2',
        unmappedProps: {'category': 'fruit', 'name': 'Banana'},
      ),
    );

    await db.put(
      DesignDocument(
        id: '_design/test',
        views: {
          'by_category': ViewData(
            map:
                'function(doc) { if (doc.category) { emit(doc.category, 1); } }',
            reduce: '_count',
          ),
        },
      ),
    );

    // Test reduce=false: should return raw map entries
    final result = await db.query('test/by_category', reduce: false);
    expect(result, isNotNull);
    expect(result!.rows, hasLength(2));
    expect(result.rows[0].id, isNotNull);
    expect(result.rows[1].id, isNotNull);

    await cl.deleteDatabase(dbName);
  });

  test('_sum reduce', () async {
    final dbName = 'test_reduce_sum';
    final db = await cl.createDatabase(dbName);

    await db.put(
      CouchDocumentBase(
        id: 'doc1',
        unmappedProps: {'category': 'fruit', 'amount': 10},
      ),
    );
    await db.put(
      CouchDocumentBase(
        id: 'doc2',
        unmappedProps: {'category': 'fruit', 'amount': 20},
      ),
    );
    await db.put(
      CouchDocumentBase(
        id: 'doc3',
        unmappedProps: {'category': 'vegetable', 'amount': 30},
      ),
    );

    await db.put(
      DesignDocument(
        id: '_design/test',
        views: {
          'sum_by_category': ViewData(
            map:
                'function(doc) { if (doc.category) { emit(doc.category, doc.amount); } }',
            reduce: '_sum',
          ),
        },
      ),
    );

    // Test ungrouped sum
    final result = await db.query('test/sum_by_category');
    expect(result, isNotNull);
    expect(result!.rows, hasLength(1));
    expect(result.rows[0].key, isNull);
    expect(result.rows[0].value, equals(60));

    // Test grouped sum
    final grouped = await db.query('test/sum_by_category', group: true);
    expect(grouped, isNotNull);
    expect(grouped!.rows, hasLength(2));
    expect(grouped.rows[0].key, equals('fruit'));
    expect(grouped.rows[0].value, equals(30));
    expect(grouped.rows[1].key, equals('vegetable'));
    expect(grouped.rows[1].value, equals(30));

    await cl.deleteDatabase(dbName);
  });

  test('_stats reduce', () async {
    final dbName = 'test_reduce_stats';
    final db = await cl.createDatabase(dbName);

    await db.put(CouchDocumentBase(id: 'doc1', unmappedProps: {'value': 10}));
    await db.put(CouchDocumentBase(id: 'doc2', unmappedProps: {'value': 20}));
    await db.put(CouchDocumentBase(id: 'doc3', unmappedProps: {'value': 30}));

    await db.put(
      DesignDocument(
        id: '_design/test',
        views: {
          'stats_view': ViewData(
            map:
                'function(doc) { if (doc.value) { emit(doc._id, doc.value); } }',
            reduce: '_stats',
          ),
        },
      ),
    );

    final result = await db.query('test/stats_view');
    expect(result, isNotNull);
    expect(result!.rows, hasLength(1));
    final stats = result.rows[0].value as Map;
    expect(stats['sum'], equals(60));
    expect(stats['count'], equals(3));
    expect(stats['min'], equals(10));
    expect(stats['max'], equals(30));
    expect(stats['sumsqr'], equals(10 * 10 + 20 * 20 + 30 * 30));

    await cl.deleteDatabase(dbName);
  });

  test('custom JavaScript reduce', () async {
    final dbName = 'test_reduce_custom';
    final db = await cl.createDatabase(dbName);

    await db.put(
      CouchDocumentBase(
        id: 'doc1',
        unmappedProps: {'category': 'a', 'amount': 5},
      ),
    );
    await db.put(
      CouchDocumentBase(
        id: 'doc2',
        unmappedProps: {'category': 'a', 'amount': 15},
      ),
    );
    await db.put(
      CouchDocumentBase(
        id: 'doc3',
        unmappedProps: {'category': 'b', 'amount': 25},
      ),
    );

    await db.put(
      DesignDocument(
        id: '_design/test',
        views: {
          'custom_reduce': ViewData(
            map:
                'function(doc) { if (doc.category) { emit(doc.category, doc.amount); } }',
            reduce:
                'function(keys, values, rereduce) { return values.reduce(function(a, b) { return a + b; }, 0); }',
          ),
        },
      ),
    );

    // Test ungrouped custom reduce
    final result = await db.query('test/custom_reduce');
    expect(result, isNotNull);
    expect(result!.rows, hasLength(1));
    expect(result.rows[0].value, equals(45));

    // Test grouped custom reduce
    final grouped = await db.query('test/custom_reduce', group: true);
    expect(grouped, isNotNull);
    expect(grouped!.rows, hasLength(2));
    expect(grouped.rows[0].key, equals('a'));
    expect(grouped.rows[0].value, equals(20));
    expect(grouped.rows[1].key, equals('b'));
    expect(grouped.rows[1].value, equals(25));

    await cl.deleteDatabase(dbName);
  });

  test('group_level with array keys', () async {
    final dbName = 'test_reduce_group_level';
    final db = await cl.createDatabase(dbName);

    await db.put(
      CouchDocumentBase(
        id: 'doc1',
        unmappedProps: {'year': 2024, 'month': 1, 'amount': 100},
      ),
    );
    await db.put(
      CouchDocumentBase(
        id: 'doc2',
        unmappedProps: {'year': 2024, 'month': 1, 'amount': 200},
      ),
    );
    await db.put(
      CouchDocumentBase(
        id: 'doc3',
        unmappedProps: {'year': 2024, 'month': 2, 'amount': 300},
      ),
    );
    await db.put(
      CouchDocumentBase(
        id: 'doc4',
        unmappedProps: {'year': 2025, 'month': 1, 'amount': 400},
      ),
    );

    await db.put(
      DesignDocument(
        id: '_design/test',
        views: {
          'by_date': ViewData(
            map:
                'function(doc) { if (doc.year) { emit([doc.year, doc.month], doc.amount); } }',
            reduce: '_sum',
          ),
        },
      ),
    );

    // Test group_level=1: group by year only
    final byYear = await db.query('test/by_date', group: true, groupLevel: 1);
    expect(byYear, isNotNull);
    expect(byYear!.rows, hasLength(2));
    expect(byYear.rows[0].key, equals([2024]));
    expect(byYear.rows[0].value, equals(600));
    expect(byYear.rows[1].key, equals([2025]));
    expect(byYear.rows[1].value, equals(400));

    // Test group_level=2: group by year and month
    final byMonth = await db.query('test/by_date', group: true, groupLevel: 2);
    expect(byMonth, isNotNull);
    expect(byMonth!.rows, hasLength(3));
    expect(byMonth.rows[0].key, equals([2024, 1]));
    expect(byMonth.rows[0].value, equals(300));
    expect(byMonth.rows[1].key, equals([2024, 2]));
    expect(byMonth.rows[1].value, equals(300));
    expect(byMonth.rows[2].key, equals([2025, 1]));
    expect(byMonth.rows[2].value, equals(400));

    await cl.deleteDatabase(dbName);
  });

  test('reduce with skip and limit', () async {
    final dbName = 'test_reduce_skip_limit';
    final db = await cl.createDatabase(dbName);

    await db.put(
      CouchDocumentBase(
        id: 'doc1',
        unmappedProps: {'category': 'a', 'amount': 10},
      ),
    );
    await db.put(
      CouchDocumentBase(
        id: 'doc2',
        unmappedProps: {'category': 'b', 'amount': 20},
      ),
    );
    await db.put(
      CouchDocumentBase(
        id: 'doc3',
        unmappedProps: {'category': 'c', 'amount': 30},
      ),
    );

    await db.put(
      DesignDocument(
        id: '_design/test',
        views: {
          'by_category': ViewData(
            map:
                'function(doc) { if (doc.category) { emit(doc.category, doc.amount); } }',
            reduce: '_sum',
          ),
        },
      ),
    );

    // Test skip
    final skipped = await db.query('test/by_category', group: true, skip: 1);
    expect(skipped, isNotNull);
    expect(skipped!.rows, hasLength(2));
    expect(skipped.rows[0].key, equals('b'));

    // Test limit
    final limited = await db.query('test/by_category', group: true, limit: 1);
    expect(limited, isNotNull);
    expect(limited!.rows, hasLength(1));
    expect(limited.rows[0].key, equals('a'));

    // Test skip + limit
    final both = await db.query(
      'test/by_category',
      group: true,
      skip: 1,
      limit: 1,
    );
    expect(both, isNotNull);
    expect(both!.rows, hasLength(1));
    expect(both.rows[0].key, equals('b'));

    await cl.deleteDatabase(dbName);
  });
}
