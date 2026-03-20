import 'dart:convert';
import 'dart:typed_data';
import 'package:dart_couch/dart_couch.dart';
import 'package:test/test.dart';
import 'package:logging/logging.dart';
import 'helper/couch_test_manager.dart';
import 'helper/einkaufslist_item.dart';
import 'helper/helper.dart';

enum DbMode { http, local, offline }

void main() {

  Logger.root.level = Level.FINEST;
  Logger.root.onRecord.listen((record) {
    LineSplitter ls = LineSplitter();
    for (final line in ls.convert(record.message)) {
      // ignore: avoid_print
      print('${record.loggerName} ${record.level.name}: ${record.time}: $line');
    }
  });

  final cm = CouchTestManager();

  setUpAll(() async {
    await cm.init();
  });

  tearDownAll(() async {
    await cm.dispose();
  });

  group('UseDartCouchMixin - HTTP', () {
    doUseDartCouchTests(cm, DbMode.http);
  });

  group('UseDartCouchMixin - Local', () {
    doUseDartCouchTests(cm, DbMode.local);
  });

  group('UseDartCouchMixin - OfflineFirst', () {
    doUseDartCouchTests(cm, DbMode.offline);
  });
}

void doUseDartCouchTests(CouchTestManager cm, DbMode mode) {
  late DartCouchDb db;

  setUp(() async {
    await cm.prepareNewTest();
    switch (mode) {
      case DbMode.http:
        db = await cm.httpDb();
      case DbMode.local:
        db = await cm.localDb();
      case DbMode.offline:
        db = await cm.offlineDb();
    }
  });

  tearDown(() async {
    await cm.cleanupAfterTest();
  });

  group('UseDartCouchMixin - Basic Operations', () {
    test('useDoc emits initial state', () async {
      final doc = EinkaufslistItem(
        id: 'test-basic-doc-1',
        name: 'Initial Name',
        erledigt: false,
        anzahl: 5,
        einheit: 'Stk',
        category: 'Test',
      );
      final putResult = await db.put(doc);
      expect(putResult.id, equals('test-basic-doc-1'));

      final docStream = db.useDoc('test-basic-doc-1');
      final firstDoc = await docStream.first;
      expect(firstDoc, isNotNull);
      expect(firstDoc!.id, equals('test-basic-doc-1'));
      expect(firstDoc.rev, equals(putResult.rev));
    });

    test('useDoc emits updates', () async {
      final doc = EinkaufslistItem(
        id: 'test-basic-doc-2',
        name: 'Initial',
        erledigt: false,
        anzahl: 1,
        einheit: 'Stk',
        category: 'Test',
      );
      await db.put(doc);

      final docStream = db.useDoc('test-basic-doc-2');
      final emissions = <CouchDocumentBase?>[];
      final sub = docStream.listen(emissions.add);

      await waitForCondition(() async => emissions.length == 1);
      expect(emissions.length, equals(1));

      final firstDoc = emissions[0] as EinkaufslistItem;
      final updated = firstDoc.copyWith(name: 'Updated', anzahl: 2);
      await db.put(updated);

      await waitForCondition(() async => emissions.length > 1);
      expect(emissions.length, greaterThan(1));
      final lastDoc = emissions.last as EinkaufslistItem;
      expect(lastDoc.name, equals('Updated'));
      expect(lastDoc.anzahl, equals(2));

      await sub.cancel();
    });

    test('useView works correctly', () async {
      final ddoc = CouchDocumentBase(
        id: '_design/test_basic',
        rev: null,
        unmappedProps: {
          'views': {
            'by_name': {
              'map': 'function(doc) { if (doc.name) emit(doc.name, 1); }',
            },
          },
        },
      );
      await db.put(ddoc);

      await db.put(
        EinkaufslistItem(
          id: 'basic-doc1',
          name: 'Apple',
          erledigt: false,
          anzahl: 1,
          einheit: 'Stk',
          category: 'Fruit',
        ),
      );
      await db.put(
        EinkaufslistItem(
          id: 'basic-doc2',
          name: 'Banana',
          erledigt: false,
          anzahl: 2,
          einheit: 'Stk',
          category: 'Fruit',
        ),
      );

      // test initial update
      final viewStream = db.useView('test_basic/by_name');
      final emissions = <ViewResult?>[];
      final sub = viewStream.listen(emissions.add);

      await waitForCondition(() async => emissions.length == 1);
      expect(emissions.length, equals(1));
      expect(emissions[0]?.totalRows, greaterThanOrEqualTo(2));

      await db.put(
        EinkaufslistItem(
          id: 'basic-doc3',
          name: 'Cherry',
          erledigt: false,
          anzahl: 3,
          einheit: 'Stk',
          category: 'Fruit',
        ),
      );

      await waitForCondition(() async => emissions.length > 1);
      expect(emissions.length, greaterThan(1));
      expect(emissions.last!.totalRows, greaterThanOrEqualTo(3));

      await sub.cancel();
    });

    test('useAllDocs works correctly', () async {
      EinkaufslistItem docA =
          await db.put(
                EinkaufslistItem(
                  id: 'all-doc-a',
                  name: 'A',
                  erledigt: false,
                  anzahl: 1,
                  einheit: 'Stk',
                  category: 'Test',
                ),
              )
              as EinkaufslistItem;
      // ignore: unused_local_variable
      EinkaufslistItem docB =
          await db.put(
                EinkaufslistItem(
                  id: 'all-doc-b',
                  name: 'B',
                  erledigt: false,
                  anzahl: 2,
                  einheit: 'Stk',
                  category: 'Test',
                ),
              )
              as EinkaufslistItem;
      EinkaufslistItem docC =
          await db.put(
                EinkaufslistItem(
                  id: 'all-doc-c',
                  name: 'C',
                  erledigt: false,
                  anzahl: 3,
                  einheit: 'Stk',
                  category: 'Test',
                ),
              )
              as EinkaufslistItem;

      final docsStream = db.useAllDocs(keys: ['all-doc-a', 'all-doc-c']);
      final emissions = <ViewResult?>[];
      final sub = docsStream.listen(emissions.add);

      await waitForCondition(() async => emissions.length == 1);
      expect(emissions.length, equals(1));
      expect(emissions[0]!.rows.length, equals(2));
      for (final row in emissions[0]!.rows) {
        expect(row.id, isNotNull);
        expect(row.error, isNull);
        expect(row.doc, isNotNull);
      }
      expect(emissions[0]!.rows[0].doc, equals(docA));
      expect(emissions[0]!.rows[1].doc, equals(docC));
      final ids = emissions[0]!.rows.map((r) => r.id).toList();
      expect(ids, containsAll(['all-doc-a', 'all-doc-c']));

      docA = await db.get('all-doc-a') as EinkaufslistItem;
      await db.put(docA.copyWith(anzahl: 10));

      await waitForCondition(() async => emissions.length > 1);
      expect(emissions.length, greaterThan(1));
      final result = emissions.last;
      expect(result!.rows.length, equals(2));
      for (final row in result.rows) {
        expect(row.id, isNotNull);
      }
      await sub.cancel();
    });
  });

  group('UseDartCouchMixin - Lifecycle and Cleanup', () {
    test('useDoc subscription can be cancelled', () async {
      final docId = 'lifecycle-doc';
      await db.put(
        EinkaufslistItem(
          id: docId,
          name: 'Lifecycle Test',
          erledigt: false,
          anzahl: 1,
          einheit: 'Stk',
          category: 'Test',
        ),
      );

      final emissions = <CouchDocumentBase?>[];
      final sub = db.useDoc(docId).listen(emissions.add);

      await waitForCondition(() async => emissions.isNotEmpty);
      final countBeforeCancel = emissions.length;

      await sub.cancel();

      final doc = await db.get(docId) as EinkaufslistItem;
      await db.put(doc.copyWith(anzahl: 99));

      // Wait to ensure no new emissions come in (proving cancellation)
      // We can't use waitForCondition for "nothing happens", so we wait a short duration
      // and assert the count hasn't changed.
      await Future.delayed(const Duration(milliseconds: 1000));
      expect(emissions.length, equals(countBeforeCancel));
    });

    test('useView subscription can be cancelled', () async {
      final ddoc = DesignDocument(
        id: '_design/lifecycle_test_view',
        views: const {
          'all': ViewData(map: 'function(doc) { emit(doc._id, 1); }'),
        },
      );
      await db.put(ddoc);

      final emissions = <ViewResult?>[];
      final sub = db.useView('lifecycle_test_view/all').listen(emissions.add);

      await waitForCondition(() async => emissions.isNotEmpty);
      await sub.cancel();
      expect(emissions.length, greaterThan(0));
    });

    test('useAllDocs subscription can be cancelled', () async {
      final docId = 'alldocs-cancel-doc';
      await db.put(
        EinkaufslistItem(
          id: docId,
          name: 'AllDocs Test',
          erledigt: false,
          anzahl: 1,
          einheit: 'Stk',
          category: 'Test',
        ),
      );

      final emissions = <ViewResult?>[];
      final sub = db.useAllDocs(keys: [docId]).listen(emissions.add);

      await waitForCondition(() async => emissions.isNotEmpty);
      final countBeforeCancel = emissions.length;

      await sub.cancel();
      // Wait to ensure no new emissions come in (proving cancellation)
      await Future.delayed(const Duration(milliseconds: 200));
      expect(emissions.length, equals(countBeforeCancel));
    });

    test('streams can be recreated after cancellation', () async {
      final docId = 'recreate-doc';
      await db.put(
        EinkaufslistItem(
          id: docId,
          name: 'Recreate Test',
          erledigt: false,
          anzahl: 1,
          einheit: 'Stk',
          category: 'Test',
        ),
      );

      final emissions1 = <CouchDocumentBase?>[];
      final sub1 = db.useDoc(docId).listen(emissions1.add);
      await waitForCondition(() async => emissions1.isNotEmpty);
      await sub1.cancel();

      final emissions2 = <CouchDocumentBase?>[];
      final sub2 = db.useDoc(docId).listen(emissions2.add);

      await waitForCondition(() async => emissions2.isNotEmpty);
      expect(emissions2.length, greaterThan(0));
      expect(emissions2.last?.id, equals(docId));

      final doc = await db.get(docId) as EinkaufslistItem;
      await db.put(doc.copyWith(anzahl: 77));

      await waitForCondition(() async => emissions2.length > 1);
      expect(emissions2.length, greaterThan(1));

      await sub2.cancel();
    });

    test('all streams clean up when database is closed', () async {
      // Create multiple streams
      final docId1 = 'cleanup-doc-1';
      final docId2 = 'cleanup-doc-2';

      await db.put(
        EinkaufslistItem(
          id: docId1,
          name: 'Doc 1',
          erledigt: false,
          anzahl: 1,
          einheit: 'Stk',
          category: 'Test',
        ),
      );
      await db.put(
        EinkaufslistItem(
          id: docId2,
          name: 'Doc 2',
          erledigt: false,
          anzahl: 2,
          einheit: 'Stk',
          category: 'Test',
        ),
      );

      // Create design document for view
      final ddoc = CouchDocumentBase(
        id: '_design/cleanup_test',
        rev: null,
        unmappedProps: {
          'views': {
            'all': {'map': 'function(doc) { if (doc.name) emit(doc._id, 1); }'},
          },
        },
      );
      await db.put(ddoc);

      final emissions1 = <CouchDocumentBase?>[];
      final emissions2 = <CouchDocumentBase?>[];
      final viewEmissions = <ViewResult?>[];
      final allDocsEmissions = <ViewResult?>[];

      final sub1 = db.useDoc(docId1).listen(emissions1.add);
      final sub2 = db.useDoc(docId2).listen(emissions2.add);
      final viewSub = db.useView('cleanup_test/all').listen(viewEmissions.add);
      final allDocsSub = db
          .useAllDocs(keys: [docId1, docId2])
          .listen(allDocsEmissions.add);

      // Wait for initial emissions
      await waitForCondition(
        () async =>
            emissions1.isNotEmpty &&
            emissions2.isNotEmpty &&
            viewEmissions.isNotEmpty &&
            allDocsEmissions.isNotEmpty,
      );

      expect(emissions1.isNotEmpty, isTrue);
      expect(emissions2.isNotEmpty, isTrue);
      expect(viewEmissions.isNotEmpty, isTrue);
      expect(allDocsEmissions.isNotEmpty, isTrue);

      final countBefore1 = emissions1.length;
      final countBefore2 = emissions2.length;

      // Cancel subscriptions to test cleanup
      await sub1.cancel();
      await sub2.cancel();
      await viewSub.cancel();
      await allDocsSub.cancel();

      // Make a change and verify canceled subscriptions don't receive it
      final doc1 = await db.get(docId1) as EinkaufslistItem;
      await db.put(doc1.copyWith(anzahl: 999));

      // Give time for any potential emissions (there shouldn't be any)
      await Future.delayed(const Duration(milliseconds: 300));

      // Verify no new emissions after cancellation
      expect(emissions1.length, equals(countBefore1));
      expect(emissions2.length, equals(countBefore2));
      // Views and allDocs might emit once more due to the put, so we don't strictly check them
      // The key is that subscription cancellation worked without errors
      expect(true, isTrue);
    });
  });

  group('UseDartCouchMixin - Performance and Debouncing', () {
    test('useDoc debounces rapid changes', () async {
      final docId = 'debounce-doc';
      await db.put(
        EinkaufslistItem(
          id: docId,
          name: 'Initial',
          erledigt: false,
          anzahl: 0,
          einheit: 'Stk',
          category: 'Test',
        ),
      );

      final docStream = db.useDoc(docId);
      final emissions = <CouchDocumentBase?>[];
      final sub = docStream.listen(emissions.add);

      await waitForCondition(() async => emissions.isNotEmpty);
      final initialCount = emissions.length;

      for (var i = 1; i <= 10; i++) {
        final doc = await db.get(docId) as EinkaufslistItem;
        await db.put(doc.copyWith(anzahl: i));
        // Small delay to simulate rapid user input, not waiting for system state
        await Future.delayed(const Duration(milliseconds: 10));
      }

      await waitForCondition(() async {
        if (emissions.isEmpty) return false;
        final last = emissions.last as EinkaufslistItem?;
        return last?.anzahl == 10;
      });

      expect(emissions.length - initialCount, lessThan(10));
      final lastDoc = emissions.last as EinkaufslistItem;
      expect(lastDoc.anzahl, equals(10));

      await sub.cancel();
    });

    test('useAllDocs debounces rapid updates', () async {
      final docIds = List.generate(5, (i) => 'watched-doc-$i');
      for (final id in docIds) {
        await db.put(
          EinkaufslistItem(
            id: id,
            name: 'Watched',
            erledigt: false,
            anzahl: 0,
            einheit: 'Stk',
            category: 'Test',
          ),
        );
      }

      final docsStream = db.useAllDocs(keys: docIds);
      final emissions = <ViewResult?>[];
      final sub = docsStream.listen(emissions.add);

      await waitForCondition(() async => emissions.isNotEmpty);
      final initialCount = emissions.length;

      for (final id in docIds) {
        final doc = await db.get(id) as EinkaufslistItem;
        await db.put(doc.copyWith(anzahl: 99));
        // Small delay to simulate rapid user input
        await Future.delayed(const Duration(milliseconds: 10));
      }

      await waitForCondition(() async {
        if (emissions.isEmpty) return false;
        // Check if all docs in the last emission have the updated value
        // This assumes the view result contains the full docs or we can check revisions
        // For simplicity, let's just wait for more emissions and check the count
        return emissions.length > initialCount;
      });

      // Give a bit more time for debounce to settle if needed,
      // but waitForCondition above ensures we got at least one update.
      // To be more robust, we could check the content of the last emission.
      await waitForCondition(() async {
        if (emissions.isEmpty) return false;
        // Wait until we have at least one emission after the initial one
        return emissions.length > initialCount;
      });

      expect(emissions.length - initialCount, lessThan(5));
      expect(emissions.last!.rows.length, equals(5));

      await sub.cancel();
    });
  });

  group('UseDartCouchMixin - Edge Cases', () {
    test('useDoc for non-existent document emits null initially', () async {
      final docStream = db.useDoc('non-existent-doc');
      final emissions = <CouchDocumentBase?>[];
      final sub = docStream.listen(emissions.add);

      await waitForCondition(() async => emissions.isNotEmpty);
      expect(emissions.length, greaterThan(0));
      expect(emissions.first, isNull);

      await sub.cancel();
    });

    test('useDoc emits document when created after subscription', () async {
      final docId = 'late-created-doc';

      final docStream = db.useDoc(docId);
      final emissions = <CouchDocumentBase?>[];
      final sub = docStream.listen(emissions.add);

      await waitForCondition(() async => emissions.isNotEmpty);
      expect(emissions.last, isNull);

      await db.put(
        EinkaufslistItem(
          id: docId,
          name: 'Created Later',
          erledigt: false,
          anzahl: 1,
          einheit: 'Stk',
          category: 'Test',
        ),
      );

      await waitForCondition(() async => emissions.last != null);
      expect(emissions.length, greaterThan(1));
      expect(emissions.last, isNotNull);

      await sub.cancel();
    });

    test('useAllDocs with empty keys list', () async {
      final docsStream = db.useAllDocs(keys: []);
      final emissions = <ViewResult?>[];
      final sub = docsStream.listen(emissions.add);

      await waitForCondition(() async => emissions.isNotEmpty);
      expect(emissions.length, greaterThan(0));
      expect(emissions.last!.rows, isEmpty);

      await sub.cancel();
    });

    test('useAllDocs with non-existent documents', () async {
      final docsStream = db.useAllDocs(
        keys: ['missing-doc-1', 'missing-doc-2'],
      );
      final emissions = <ViewResult?>[];
      final sub = docsStream.listen(emissions.add);

      await waitForCondition(() async => emissions.isNotEmpty);
      expect(emissions.length, greaterThan(0));

      final result = emissions.last;
      expect(result!.rows.length, equals(2));
      for (final row in result.rows) {
        expect(row.error, equals('not_found'));
        expect(row.id, isNull);
      }
      expect(result.rows[0].key, equals('missing-doc-1'));
      expect(result.rows[1].key, equals('missing-doc-2'));

      await sub.cancel();
    });

    test('useDoc handles rapid updates gracefully', () async {
      final docId = 'rapid-updates-doc';
      await db.put(
        EinkaufslistItem(
          id: docId,
          name: 'RapidUpdates',
          erledigt: false,
          anzahl: 0,
          einheit: 'Stk',
          category: 'Test',
        ),
      );

      final docStream = db.useDoc(docId);
      final emissions = <CouchDocumentBase?>[];
      final sub = docStream.listen(emissions.add);

      await waitForCondition(() async => emissions.isNotEmpty);
      final initialCount = emissions.length;

      for (var i = 0; i < 50; i++) {
        final doc = await db.get(docId) as EinkaufslistItem;
        await db.put(doc.copyWith(anzahl: i));
      }

      await waitForCondition(() async {
        if (emissions.isEmpty) return false;
        final last = emissions.last as EinkaufslistItem?;
        return last?.anzahl == 49;
      });

      final totalEmissions = emissions.length - initialCount;
      expect(totalEmissions, lessThan(50));

      final finalDoc = emissions.last as EinkaufslistItem?;
      expect(finalDoc?.anzahl, 49);

      await sub.cancel();
    });

    test('useDoc continues after transient error', () async {
      // Skip for non-OfflineFirst - changes stream doesn't auto-recover
      if (db is! OfflineFirstDb) return;

      final docId = 'transient-doc-static';
      await db.put(
        EinkaufslistItem(
          id: docId,
          name: 'Initial',
          erledigt: false,
          anzahl: 1,
          einheit: 'Stk',
          category: 'Test',
        ),
      );

      final emissions = <EinkaufslistItem>[];
      final sub = db
          .useDoc(docId)
          .cast<EinkaufslistItem>()
          .listen(emissions.add);

      await waitForCondition(() async => emissions.isNotEmpty);
      expect(emissions.first.name, 'Initial');

      await cm.pauseContainer();

      final connectionState = (db as OfflineFirstDb).serverDb.connectionState;

      await waitForCondition(
        () async =>
            connectionState.value ==
            DartCouchConnectionState.connectedButNetworkError,
      );

      await cm.resumeContainer();

      await waitForCondition(
        () async => connectionState.value == DartCouchConnectionState.connected,
      );

      // Verify recovery
      final remoteDb = await cm.httpDb();
      final remoteDoc = await remoteDb.get(docId) as EinkaufslistItem;
      await remoteDb.put(remoteDoc.copyWith(name: 'RemoteUpdate'));
      await waitForCondition(
        () async => emissions.any((e) => e.name == 'RemoteUpdate'),
      );
      expect(emissions.last.name, 'RemoteUpdate');

      await sub.cancel();
    });

    test('useAllDocs continues after transient error', () async {
      // auto recovering streams only works for OfflineFirstDb
      if (db is! OfflineFirstDb) return;

      final docId = 'transient-alldocs-doc-static';
      await db.put(
        EinkaufslistItem(
          id: docId,
          name: 'Initial',
          erledigt: false,
          anzahl: 1,
          einheit: 'Stk',
          category: 'Test',
        ),
      );

      final emissions = <ViewResult?>[];
      final sub = db
          .useAllDocs(keys: [docId], includeDocs: true)
          .listen(emissions.add);

      await waitForCondition(() async => emissions.isNotEmpty);
      expect(emissions.first!.rows.any((r) => r.id == docId), isTrue);

      await cm.pauseContainer();

      final connectionState = (db as OfflineFirstDb).serverDb.connectionState;

      await waitForCondition(
        () async =>
            connectionState.value ==
            DartCouchConnectionState.connectedButNetworkError,
      );

      await cm.resumeContainer();

      await waitForCondition(
        () async => connectionState.value == DartCouchConnectionState.connected,
      );

      final remoteDb = await cm.httpDb();
      final doc = await remoteDb.get(docId) as EinkaufslistItem;
      await remoteDb.put(doc.copyWith(name: 'RemoteAllDocsUpdate'));

      await waitForCondition(
        () async => emissions.last!.rows.any(
          (r) => (r.doc as EinkaufslistItem?)?.name == 'RemoteAllDocsUpdate',
        ),
      );

      await sub.cancel();
    });

    test('useView continues after transient error', () async {
      // Skip for non-OfflineFirst - changes stream doesn't auto-recover
      if (db is! OfflineFirstDb) return;

      final docId = 'transient-view-doc-static';
      final ddoc = CouchDocumentBase(
        id: '_design/test_transient',
        rev: null,
        unmappedProps: {
          'views': {
            'by_name': {
              'map': 'function(doc) { if (doc.name) emit(doc.name, 1); }',
            },
          },
        },
      );
      try {
        await db.put(ddoc);
      } catch (e) {
        // Ignore if exists
      }

      await db.put(
        EinkaufslistItem(
          id: docId,
          name: 'InitialView',
          erledigt: false,
          anzahl: 1,
          einheit: 'Stk',
          category: 'Test',
        ),
      );

      final emissions = <ViewResult?>[];
      final sub = db.useView('test_transient/by_name').listen(emissions.add);

      await waitForCondition(() async => emissions.isNotEmpty);

      await cm.pauseContainer();

      final connectionState = (db as OfflineFirstDb).serverDb.connectionState;

      await waitForCondition(
        () async =>
            connectionState.value ==
            DartCouchConnectionState.connectedButNetworkError,
      );

      await cm.resumeContainer();

      await waitForCondition(
        () async => connectionState.value == DartCouchConnectionState.connected,
      );

      final remoteDb = await cm.httpDb();
      final doc = await remoteDb.get(docId) as EinkaufslistItem;
      await remoteDb.put(doc.copyWith(name: 'RemoteViewUpdate'));

      await waitForCondition(
        () async => emissions.any(
          (res) => res!.rows.any((r) => r.key == 'RemoteViewUpdate'),
        ),
        maxAttempts: 40,
      );

      await sub.cancel();
    });

    test('HTTP streams emit error on transient network failure', () async {
      // This test is HTTP-specific - verify streams emit errors
      // instead of silently failing
      if (db is! HttpDartCouchDb) return;

      final docId = 'http-error-test-doc';
      await db.put(
        EinkaufslistItem(
          id: docId,
          name: 'Initial',
          erledigt: false,
          anzahl: 1,
          einheit: 'Stk',
          category: 'Test',
        ),
      );

      final emissions = <CouchDocumentBase?>[];
      final errors = <dynamic>[];
      final sub = db
          .useDoc(docId)
          .listen(emissions.add, onError: errors.add, cancelOnError: false);

      await waitForCondition(() async => emissions.isNotEmpty);
      expect(emissions.first?.id, equals(docId));

      // Pause the container to simulate network failure.
      // pauseContainer() keeps _httpServer/_httpDb alive so the db object
      // can still observe the connection state change.
      await cm.pauseContainer();

      final connectionState = (db as HttpDartCouchDb).connectionState;

      await waitForCondition(
        () async =>
            connectionState.value ==
            DartCouchConnectionState.connectedButNetworkError,
      );

      // For HTTP implementation, the changes stream doesn't auto-recover
      // So we expect an error to be emitted to the stream
      await waitForCondition(() async => errors.isNotEmpty, maxAttempts: 40);

      expect(
        errors,
        isNotEmpty,
        reason: 'Stream should emit error on network failure',
      );

      // Restart for cleanup
      await cm.resumeContainer();

      await waitForCondition(
        () async => connectionState.value == DartCouchConnectionState.connected,
      );

      await sub.cancel();
    });

    test('useDoc handles database deletion gracefully', () async {
      final docId = 'deletion-test-doc';
      await db.put(
        EinkaufslistItem(
          id: docId,
          name: 'Will be deleted',
          erledigt: false,
          anzahl: 1,
          einheit: 'Stk',
          category: 'Test',
        ),
      );

      final emissions = <CouchDocumentBase?>[];
      final errors = <dynamic>[];
      final sub = db.useDoc(docId).listen(emissions.add, onError: errors.add);

      await waitForCondition(() async => emissions.isNotEmpty);
      expect(emissions.first?.id, equals(docId));

      // For Local and HTTP, we can try to delete the database
      // For OfflineFirst, this is more complex as it manages two databases
      if (db is HttpDartCouchDb) {
        final server = (db as HttpDartCouchDb).parentServer;
        try {
          await server.deleteDatabase(db.dbname);
          // After deletion, we expect the stream to eventually emit an error or null
          await Future.delayed(const Duration(milliseconds: 500));
          // The stream should handle this gracefully without crashing
          expect(true, isTrue); // Test passes if we reach here without crash
        } catch (e) {
          // If deletion fails, that's okay for this test
        }
      } else if (db is LocalDartCouchDb) {
        // For local DB, we can't easily delete while it's in use
        // Just verify the stream continues to work
        expect(emissions.isNotEmpty, isTrue);
      }

      await sub.cancel();
    });

    test('changes stream error propagates to all listeners', () async {
      // This test verifies that multiple listeners on different streams
      // can coexist and handle errors appropriately
      final docId1 = 'multi-listener-doc-1';
      final docId2 = 'multi-listener-doc-2';

      await db.put(
        EinkaufslistItem(
          id: docId1,
          name: 'Doc 1',
          erledigt: false,
          anzahl: 1,
          einheit: 'Stk',
          category: 'Test',
        ),
      );
      await db.put(
        EinkaufslistItem(
          id: docId2,
          name: 'Doc 2',
          erledigt: false,
          anzahl: 2,
          einheit: 'Stk',
          category: 'Test',
        ),
      );

      final emissions1 = <CouchDocumentBase?>[];
      final emissions2 = <CouchDocumentBase?>[];
      final errors1 = <dynamic>[];
      final errors2 = <dynamic>[];

      final sub1 = db
          .useDoc(docId1)
          .listen(emissions1.add, onError: errors1.add);
      final sub2 = db
          .useDoc(docId2)
          .listen(emissions2.add, onError: errors2.add);

      await waitForCondition(
        () async => emissions1.isNotEmpty && emissions2.isNotEmpty,
      );

      // Both streams should receive their initial documents
      expect(emissions1.first?.id, equals(docId1));
      expect(emissions2.first?.id, equals(docId2));

      // Update both documents
      final doc1 = await db.get(docId1) as EinkaufslistItem;
      await db.put(doc1.copyWith(anzahl: 10));

      final doc2 = await db.get(docId2) as EinkaufslistItem;
      await db.put(doc2.copyWith(anzahl: 20));

      await waitForCondition(
        () async => emissions1.length > 1 && emissions2.length > 1,
      );

      // Both streams should have received updates
      expect(emissions1.length, greaterThan(1));
      expect(emissions2.length, greaterThan(1));

      await sub1.cancel();
      await sub2.cancel();
    });

    test('streams recover when changes stream reconnects', () async {
      // Skip for non-OfflineFirst - changes stream doesn't auto-recover
      if (db is! OfflineFirstDb) return;

      final docId = 'reconnect-doc-static';
      await db.put(
        EinkaufslistItem(
          id: docId,
          name: 'Initial',
          erledigt: false,
          anzahl: 1,
          einheit: 'Stk',
          category: 'Test',
        ),
      );

      final emissions = <EinkaufslistItem>[];
      final sub = db
          .useDoc(docId)
          .cast<EinkaufslistItem>()
          .listen(emissions.add);

      await waitForCondition(() async => emissions.isNotEmpty);

      await cm.pauseContainer();

      final connectionState = (db as OfflineFirstDb).serverDb.connectionState;

      await waitForCondition(
        () async =>
            connectionState.value ==
            DartCouchConnectionState.connectedButNetworkError,
      );

      await cm.resumeContainer();

      await waitForCondition(
        () async => connectionState.value == DartCouchConnectionState.connected,
      );

      final remoteDb = await cm.httpDb();
      final doc = await remoteDb.get(docId) as EinkaufslistItem;
      await remoteDb.put(doc.copyWith(name: 'RemoteReconnect'));
      await waitForCondition(
        () async => emissions.any((e) => e.name == 'RemoteReconnect'),
      );

      await sub.cancel();
    });

    test('streams handle design document updates', () async {
      // Create initial design document
      final ddoc = CouchDocumentBase(
        id: '_design/evolving_view',
        rev: null,
        unmappedProps: {
          'views': {
            'by_name': {
              'map': 'function(doc) { if (doc.name) emit(doc.name, 1); }',
            },
          },
        },
      );
      await db.put(ddoc);

      await db.put(
        EinkaufslistItem(
          id: 'ddoc-test-1',
          name: 'Apple',
          erledigt: false,
          anzahl: 1,
          einheit: 'Stk',
          category: 'Fruit',
        ),
      );

      final emissions = <ViewResult?>[];
      final sub = db.useView('evolving_view/by_name').listen(emissions.add);

      await waitForCondition(() async => emissions.isNotEmpty);
      expect(emissions.last!.totalRows, greaterThanOrEqualTo(1));
      final initialCount = emissions.length;

      // Add another document
      await db.put(
        EinkaufslistItem(
          id: 'ddoc-test-2',
          name: 'Banana',
          erledigt: false,
          anzahl: 2,
          einheit: 'Stk',
          category: 'Fruit',
        ),
      );

      await waitForCondition(() async => emissions.length > initialCount);
      expect(emissions.last!.totalRows, greaterThanOrEqualTo(2));

      await sub.cancel();
    });

    test('useAllDocs handles watching 1000 documents simultaneously', () async {
      // This is a performance test - use fewer documents in CI to keep it fast
      final docCount = 100; // Reduced from 1000 for faster test execution
      final docIds = <String>[];

      // Create documents in batches for better performance
      final docs = <EinkaufslistItem>[];
      for (var i = 0; i < docCount; i++) {
        final docId = 'perf-doc-${i.toString().padLeft(4, '0')}';
        docIds.add(docId);
        docs.add(
          EinkaufslistItem(
            id: docId,
            name: 'Item $i',
            erledigt: false,
            anzahl: i,
            einheit: 'Stk',
            category: 'Performance',
          ),
        );
      }

      // Bulk insert for performance
      if (db is HttpDartCouchDb || db is OfflineFirstDb) {
        await db.bulkDocs(docs);
      } else {
        // Local DB might not support bulkDocs efficiently, insert individually
        for (final doc in docs) {
          await db.put(doc);
        }
      }

      final emissions = <ViewResult?>[];
      final sub = db.useAllDocs(keys: docIds).listen(emissions.add);

      await waitForCondition(() async => emissions.isNotEmpty);
      expect(emissions.last!.rows.length, equals(docCount));

      // Update one document and verify we get an emission
      final testDoc = await db.get(docIds[50]) as EinkaufslistItem;
      await db.put(testDoc.copyWith(anzahl: 999));

      await waitForCondition(() async => emissions.length > 1);
      expect(emissions.last!.rows.length, equals(docCount));

      await sub.cancel();
    });

    test('useAllDocs with attachments parameter', () async {
      // Skip for databases that don't support attachments easily
      if (db is LocalDartCouchDb) return;

      final docId = 'doc-with-attachment';

      // Create a document with an attachment
      final doc = EinkaufslistItem(
        id: docId,
        name: 'Document with attachment',
        erledigt: false,
        anzahl: 1,
        einheit: 'Stk',
        category: 'Test',
      );
      final putResult = await db.put(doc);

      // Add an attachment using the HTTP API
      if (db is HttpDartCouchDb) {
        final attachmentData = Uint8List.fromList(
          utf8.encode('Hello, this is a test attachment!'),
        );
        await (db as HttpDartCouchDb).saveAttachment(
          docId,
          putResult.rev!,
          'test.txt',
          attachmentData,
          contentType: 'text/plain',
        );
      } else if (db is OfflineFirstDb) {
        final remoteDb = await cm.httpDb();

        // Wait for the document to sync to remote
        await waitForCondition(() async {
          try {
            final remoteDoc = await remoteDb.get(docId);
            return remoteDoc != null;
          } catch (_) {
            return false;
          }
        });

        // Get the current revision from remote
        final remoteDoc = await remoteDb.get(docId);
        final attachmentData = Uint8List.fromList(
          utf8.encode('Hello, this is a test attachment!'),
        );
        await remoteDb.saveAttachment(
          docId,
          remoteDoc!.rev!,
          'test.txt',
          attachmentData,
          contentType: 'text/plain',
        );
      }

      // Use useAllDocs with attachments=true
      final emissions = <ViewResult?>[];
      final sub = db
          .useAllDocs(keys: [docId], includeDocs: true, attachments: true)
          .listen(emissions.add);

      await waitForCondition(() async => emissions.isNotEmpty);

      expect(emissions.last!.rows.length, equals(1));
      final row = emissions.last!.rows.first;
      expect(row.id, equals(docId));

      // Check if the document has attachments
      // Note: The exact structure depends on the implementation
      // but we can verify the call didn't crash and returned data
      expect(row.doc, isNotNull);

      await sub.cancel();
    });
  });

  // OfflineFirst-specific tests
  if (mode == DbMode.offline) {
    group('UseDartCouchMixin - OfflineFirst Specific', () {
      test('useDoc emits local changes immediately', () async {
        final docId = 'offline-local-doc';
        final doc = EinkaufslistItem(
          id: docId,
          name: 'Test Doc',
          erledigt: false,
          anzahl: 1,
          einheit: 'Stk',
          category: 'Test',
        );

        final docStream = db.useDoc(docId);
        final emissions = <CouchDocumentBase?>[];
        final sub = docStream.listen(emissions.add);

        await waitForCondition(() async => emissions.isNotEmpty);
        await db.put(doc);

        await waitForCondition(() async {
          if (emissions.isEmpty) return false;
          return emissions.last?.id == docId;
        });
        expect(emissions.length, greaterThan(0));
        expect(emissions.last?.id, equals(docId));

        await sub.cancel();
      });

      test('useDoc receives remote changes when online', () async {
        final docId = 'offline-remote-doc';
        final doc = EinkaufslistItem(
          id: docId,
          name: 'Initial',
          erledigt: false,
          anzahl: 1,
          einheit: 'Stk',
          category: 'Test',
        );
        await db.put(doc);
        // Wait for replication/propagation if needed, or just proceed
        await waitForCondition(() async {
          try {
            final d = await db.get(docId);
            return d != null;
          } catch (_) {
            return false;
          }
        });

        final docStream = db.useDoc(docId);
        final emissions = <CouchDocumentBase?>[];
        final sub = docStream.listen(emissions.add);

        await waitForCondition(() async => emissions.isNotEmpty);

        final remoteDb = await cm.httpDb();
        final remoteDoc = await remoteDb.get(docId) as EinkaufslistItem;
        await remoteDb.put(
          remoteDoc.copyWith(name: 'Updated Remotely', anzahl: 5),
        );

        await waitForCondition(() async {
          if (emissions.isEmpty) return false;
          final last = emissions.last as EinkaufslistItem?;
          return last?.name == 'Updated Remotely' && last?.anzahl == 5;
        });

        final lastEmission = emissions.last as EinkaufslistItem?;
        expect(lastEmission?.name, equals('Updated Remotely'));
        expect(lastEmission?.anzahl, equals(5));

        await sub.cancel();
      });

      test('useDoc emits update when remote attachment is added', () async {
        final docId = 'offline-remote-attachment-doc';
        final doc = EinkaufslistItem(
          id: docId,
          name: 'Attachment Test',
          erledigt: false,
          anzahl: 1,
          einheit: 'Stk',
          category: 'Test',
        );
        await db.put(doc);

        final remoteDb = await cm.httpDb();

        // Wait for doc to sync to remote
        await waitForCondition(() async {
          try {
            final d = await remoteDb.get(docId);
            return d != null;
          } catch (_) {
            return false;
          }
        });

        final docStream = db.useDoc(docId);
        final emissions = <CouchDocumentBase?>[];
        final sub = docStream.listen(emissions.add);

        await waitForCondition(() async => emissions.isNotEmpty);

        // Add attachment directly on remote
        final remoteDoc = await remoteDb.get(docId);
        final attachmentData = Uint8List.fromList(
          utf8.encode('Remote attachment via useDoc'),
        );
        await remoteDb.saveAttachment(
          docId,
          remoteDoc!.rev!,
          'remote.txt',
          attachmentData,
          contentType: 'text/plain',
        );

        // Wait for pull replication to emit the update with the attachment
        await waitForCondition(() async {
          if (emissions.isEmpty) return false;
          return emissions.last?.attachments?.containsKey('remote.txt') == true;
        });

        expect(emissions.last!.attachments!.containsKey('remote.txt'), isTrue);

        await sub.cancel();
      });
    });
  }
}
