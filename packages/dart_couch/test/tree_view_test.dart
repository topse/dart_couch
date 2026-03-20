// ignore_for_file: unused_local_variable

import 'package:dart_mappable/dart_mappable.dart';
import 'package:test/test.dart';
import 'package:dart_couch/dart_couch.dart';
import 'dart:convert';
import 'package:logging/logging.dart';

import 'helper/helper.dart';

part 'tree_view_test.mapper.dart';

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

  test('create a tree structure and use it with view', () async {
    final db = await cl.createDatabase('testdb');
    await db.put(
      DesignDocument(
        id: '_design/tree_view',
        views: {
          'by_parent': ViewData(
            map: '''
          function(doc) {
            if (doc['!doc_type'] !== null &&  doc['!doc_type'] === 'tree_node') {
              emit([doc.parent, doc.name], doc.name);
            }
          }
        ''',
          ),
        },
      ),
    );

    final node1 = await db.post(TreeNode(name: 'Node 1'));
    final node2 = await db.post(TreeNode(name: 'Node 2'));
    final node11 = await db.post(TreeNode(name: 'Node 1.1', parent: node1.id));
    final node12 = await db.post(TreeNode(name: 'Node 1.2', parent: node1.id));
    final node21 = await db.post(TreeNode(name: 'Node 2.1', parent: node2.id));
    final node111 = await db.post(
      TreeNode(name: 'Node 1.1.1', parent: node11.id),
    );
    final node112 = await db.post(
      TreeNode(name: 'Node 1.1.2', parent: node11.id),
    );

    ViewResult? res = await db.query(
      'tree_view/by_parent',
      startkey: "[null]",
      endkey: "[null, {}]",
    );
    expect(res, isNotNull);
    expect(res!.totalRows, 7);
    expect(res.rows.length, 2);
    expect(res.rows[0].key, [null, 'Node 1']);
    expect(res.rows[0].value, 'Node 1');
    expect(res.rows[1].key, [null, 'Node 2']);
    expect(res.rows[1].value, 'Node 2');

    res = await db.query(
      'tree_view/by_parent',
      startkey: '["${node1.id}"]',
      endkey: '["${node1.id}", {}]',
    );
    expect(res, isNotNull);
    expect(res!.rows.length, 2);
    expect(res.totalRows, 7);
    expect(res.rows[0].key, [node1.id, 'Node 1.1']);
    expect(res.rows[0].value, 'Node 1.1');
    expect(res.rows[1].key, [node1.id, 'Node 1.2']);
    expect(res.rows[1].value, 'Node 1.2');

    res = await db.query(
      'tree_view/by_parent',
      startkey: '["${node11.id}"]',
      endkey: '["${node11.id}", {}]',
    );
    expect(res, isNotNull);
    expect(res!.rows.length, 2);
    expect(res.totalRows, 7);
    expect(res.rows[0].key, [node11.id, 'Node 1.1.1']);
    expect(res.rows[0].value, 'Node 1.1.1');
    expect(res.rows[1].key, [node11.id, 'Node 1.1.2']);
    expect(res.rows[1].value, 'Node 1.1.2');

    await cl.deleteDatabase("testdb");
  });
}

@MappableClass(discriminatorValue: 'tree_node')
class TreeNode extends CouchDocumentBase with TreeNodeMappable {
  final String? parent;
  final String name;

  TreeNode({
    required this.name,
    this.parent,
    super.id,
    super.rev,
    super.deleted,
    super.attachments,
    super.revisions,
    super.revsInfo,
    super.unmappedProps,
  });

  static final fromMap = TreeNodeMapper.fromMap;
  static final fromJson = TreeNodeMapper.fromJson;
}
