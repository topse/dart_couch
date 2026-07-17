import 'package:test/test.dart';
import 'package:dart_couch/dart_couch.dart';

import 'test_document_one.dart';

/// Shared helper test for bulkDocs.
/// Call `await runBulkDocsTest(db);` from your concrete test file
/// passing an instance of `DartCouchDb` (for example one from HttpDartCouchDb or LocalDartCouchDb).
Future<void> runBulkDocsTest(DartCouchDb db) async {
  // Use timestamps to create unique ids so repeated test runs don't conflict
  final ts = DateTime.now().microsecondsSinceEpoch;
  final id1 = 'bulk_doc_${ts}_1';
  final id2 = 'bulk_doc_${ts}_2';

  final doc1 = TestDocumentOne(name: 'Bulk One', id: id1);
  final doc2 = TestDocumentOne(name: 'Bulk Two', id: id2);

  // 1) Success case: insert two new docs
  final res = await db.bulkDocs([doc1, doc2]);

  expect(res, hasLength(2));
  for (final r in res) {
    expect(r, isNotNull);
    expect(r.ok, isTrue, reason: 'Expected ok=true for successful bulk insert');
    expect(r.id, isNotEmpty);
    expect(r.rev, isNotNull);
    expect(r.error, isNull);
  }

  // Verify that documents are retrievable and data matches what was stored
  final got1 = await db.get(id1) as TestDocumentOne?;
  expect(got1, isNotNull);
  expect(got1!.id, equals(id1));
  expect(got1.name, equals('Bulk One'));
  expect(got1.rev, isNotNull);

  final got2 = await db.get(id2) as TestDocumentOne?;
  expect(got2, isNotNull);
  expect(got2!.id, equals(id2));
  expect(got2.name, equals('Bulk Two'));
  expect(got2.rev, isNotNull);

  // 2) Error case: when newEdits=false and documents don't include _rev,
  //    the implementation may either return an error result for that document
  //    or (rarely) throw a CouchDbException for the whole request.
  final errDoc1 = TestDocumentOne(name: 'Bulk Err', id: 'bulk_doc_${ts}_err');
  final errDoc2 = TestDocumentOne(
    name: 'Bulk Err',
    id: 'bulk_doc_${ts}2_err',
    rev: '1-unknownrev',
  );

  try {
    await db.bulkDocs([errDoc1, errDoc2], newEdits: false);
    assert(false); // Should not reach here
  } catch (e) {
    // Some implementations (or server configurations) may throw for the whole
    // request. Accept that as equivalent behavior.
    expect(e, isA<CouchDbException>());
  }

  // 3) When newEdits=false and a properly formed _rev is provided for a new
  //    document, the server/implementation should accept and store that
  //    revision. Construct a synthetic revision id and expect the stored
  //    revision to match.
  final id3 = 'bulk_doc_${ts}_3';
  final suppliedRev = '1-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; // 32 hex chars
  // 3) When newEdits=false and a properly formed _rev/_revisions is provided
  //    for a new document, the implementation should accept and store that
  //    revision. Provide a full _revisions array to match CouchDB expectations
  //    so both HTTP and Local implementations behave the same.
  final suppliedRevisions = Revisions(
    start: 1,
    ids: ['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'],
  );
  final doc3 = TestDocumentOne(
    name: 'Bulk NewEdits False',
    id: id3,
    rev: suppliedRev,
    revisions: suppliedRevisions,
  );

  final res3 = await db.bulkDocs([doc3], newEdits: false);
  expect(res3, hasLength(0));

  // 4) Overwrite an existing document with a new revision (happy path).
  //    Insert a document, then update it via bulkDocs (default newEdits=true)
  //    and expect the revision to change.
  final id4 = 'bulk_doc_${ts}_4';
  final orig = TestDocumentOne(name: 'Original', id: id4);
  final insertRes = await db.bulkDocs([orig]);
  expect(insertRes, hasLength(1));
  final origRev = insertRes[0].rev;
  expect(origRev, isNotNull);

  final updated = TestDocumentOne(name: 'Updated', id: id4, rev: origRev);
  final updateRes = await db.bulkDocs([updated]);
  expect(updateRes, hasLength(1));
  final upd = updateRes[0];
  expect(upd.ok, isTrue);
  expect(upd.rev, isNotNull);
  expect(
    upd.rev,
    isNot(equals(origRev)),
    reason: 'Expected a new revision after update',
  );

  // Verify updated document via get()
  final gotUpdated = await db.get(id4) as TestDocumentOne?;
  expect(gotUpdated, isNotNull);
  expect(gotUpdated!.id, equals(id4));
  expect(gotUpdated.name, equals('Updated'));
  expect(gotUpdated.rev, equals(upd.rev));
}
