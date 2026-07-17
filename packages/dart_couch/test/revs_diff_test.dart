import 'package:test/test.dart';

import 'package:dart_couch/dart_couch.dart';
import 'package:collection/collection.dart';

import 'helper/helper.dart';
import 'helper/test_document_one.dart';

// This test is isolated and only checks parity of revsDiff between
// Http and Local implementations. It runs its own setup/teardown and
// doesn't depend on other test groups.

void main() {
  test('revsDiff parity between Http and Local implementations', () async {
    // Create independent servers
    final httpServer = await setUpAllHttpFunction();
    final localServer = await setUpAllLocalFunction();

    final httpDb = await httpServer.createDatabase('revsdiff_test');
    final localDb = await localServer.createDatabase('revsdiff_test');

    // create identical revision histories on both implementations
    final httpRevsA = await createThreeRevisions(httpDb, 'docA');
    final httpRevsB = await createThreeRevisions(httpDb, 'docB');

    await createThreeRevisions(localDb, 'docA');
    await createThreeRevisions(localDb, 'docB');

    final revsMap = {
      'docA': [httpRevsA[0].rev!, httpRevsA[1].rev!, '9-nonexistent'],
      'docB': [httpRevsB[0].rev!, '1-unknown'],
    };

    final Map<String, RevsDiffEntry> resHttp = await httpDb.revsDiff(revsMap);
    final Map<String, RevsDiffEntry> resLocal = await localDb.revsDiff(revsMap);

    // Compare by mapping each RevsDiffEntry to its Map representation
    final Map<String, dynamic> httpMap = resHttp.map(
      (k, v) => MapEntry(k, v.toMap()),
    );
    final Map<String, dynamic> localMap = resLocal.map(
      (k, v) => MapEntry(k, v.toMap()),
    );

    expect(DeepCollectionEquality().equals(httpMap, localMap), isTrue);

    await httpServer.deleteDatabase('revsdiff_test');
    await localServer.deleteDatabase('revsdiff_test');
    await tearDownAllHttpFunction();
  });
}

Future<List<TestDocumentOne>> createThreeRevisions(
  DartCouchDb db,
  String docid,
) {
  return createRevisions(db, docid, 3);
}

Future<List<TestDocumentOne>> createRevisions(
  DartCouchDb db,
  String docid,
  int numOfRevisions,
) async {
  List<TestDocumentOne?> revs = List.filled(numOfRevisions, null);

  TestDocumentOne doc = TestDocumentOne(name: 'Hallo 1', id: docid);
  revs[numOfRevisions - 1] = await db.put(doc) as TestDocumentOne;

  int num = 2;
  for (int i = numOfRevisions - 2; i >= 0; --i) {
    revs[i] =
        await db.put(revs[i + 1]!.copyWith(name: "Hallo ${num++}"))
            as TestDocumentOne;
  }

  await doCompaction(db);

  return List<TestDocumentOne>.from(revs);
}

Future<void> doCompaction(DartCouchDb db) async {
  await db.startCompaction();
  while (await db.isCompactionRunning() == true) {
    await Future.delayed(Duration(milliseconds: 1000));
  }
}
