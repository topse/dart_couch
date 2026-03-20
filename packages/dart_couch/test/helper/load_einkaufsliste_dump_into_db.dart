import 'dart:convert';
import 'dart:io';
import 'package:dart_couch/dart_couch.dart';
import 'package:test/test.dart';

Future<void> loadEinkaufslisteDumpIntoDb(DartCouchDb hdb) async {
  // Load einkaufsliste dump and write it into the HTTP database via bulkDocs

  List<CouchDocumentBase> docs = await getTestContent();

  // Use default newEdits=true to let CouchDB generate new _rev values
  await hdb.bulkDocs(docs, newEdits: false);
  expect(docs.length, (await hdb.allDocs()).rows.length);

  // Quick sanity check: one known category should be present afterwards
  final category = await hdb.get('categorie_obst_gemüse');
  expect(category, isNotNull);
}

Future<List<CouchDocumentBase>> getTestContent() async {
  final dumpPath = 'test/fixtures/einkaufsliste_dump.json';
  final file = File(dumpPath);
  expect(
    await file.exists(),
    isTrue,
    reason: 'Fixture file not found at $dumpPath',
  );
  final content = await file.readAsString();
  final List<dynamic> decoded = jsonDecode(content) as List<dynamic>;
  // Decode into CouchDocumentBase so we can pass mixed documents (items, categories, design docs)
  final docs = decoded
      .whereType<Map<String, dynamic>>()
      .map<CouchDocumentBase>(CouchDocumentBase.fromMap)
      .toList(growable: false);
  return docs;
}
