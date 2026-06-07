import 'dart:async';

import 'package:dart_couch/dart_couch.dart';
import 'package:dart_couch_widgets/dart_couch_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ViewEntry _row(String id, int value) =>
    ViewEntry(id: id, key: id, value: value);

ViewResult _result(List<ViewEntry> rows) =>
    ViewResult(totalRows: rows.length, offset: 0, rows: rows);

void main() {
  testWidgets('AnimatedViewList renders snapshot then applies deltas', (
    tester,
  ) async {
    final controller = StreamController<ViewUpdate>();
    addTearDown(controller.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedViewList(
            updates: controller.stream,
            itemBuilder: (context, row, index, animation) => SizeTransition(
              sizeFactor: animation,
              child: SizedBox(
                height: 40,
                child: Text('${row.id}:${row.value}'),
              ),
            ),
          ),
        ),
      ),
    );

    // Before the first snapshot: placeholder, no rows.
    expect(find.byType(Text), findsNothing);

    // Initial snapshot of two rows.
    controller.add(ViewSnapshot(_result([_row('a', 1), _row('b', 2)])));
    await tester.pumpAndSettle();
    expect(find.text('a:1'), findsOneWidget);
    expect(find.text('b:2'), findsOneWidget);

    // Insert a row at the end.
    controller.add(ViewChanges([ViewRowInserted(2, _row('c', 3))]));
    await tester.pumpAndSettle();
    expect(find.text('c:3'), findsOneWidget);
    expect(find.byType(Text), findsNWidgets(3));

    // Change the first row in place: new content, old content gone.
    controller.add(ViewChanges([ViewRowChanged(0, _row('a', 99))]));
    await tester.pumpAndSettle();
    expect(find.text('a:99'), findsOneWidget);
    expect(find.text('a:1'), findsNothing);

    // Remove the middle row.
    controller.add(ViewChanges([ViewRowRemoved(1, _row('b', 2))]));
    await tester.pumpAndSettle();
    expect(find.text('b:2'), findsNothing);
    expect(find.byType(Text), findsNWidgets(2));
  });

  testWidgets('AnimatedViewList resets on a later snapshot', (tester) async {
    final controller = StreamController<ViewUpdate>();
    addTearDown(controller.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedViewList(
            updates: controller.stream,
            itemBuilder: (context, row, index, animation) => SizeTransition(
              sizeFactor: animation,
              child: SizedBox(height: 40, child: Text('${row.id}')),
            ),
          ),
        ),
      ),
    );

    controller.add(ViewSnapshot(_result([_row('a', 1), _row('b', 2)])));
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsNWidgets(2));

    // A second snapshot with different rows replaces the list (animated diff).
    controller.add(ViewSnapshot(_result([_row('b', 2), _row('x', 9)])));
    await tester.pumpAndSettle();
    expect(find.text('b'), findsOneWidget);
    expect(find.text('x'), findsOneWidget);
    expect(find.text('a'), findsNothing);
    expect(find.byType(Text), findsNWidgets(2));
  });

  testWidgets('SliverAnimatedViewList works inside a CustomScrollView', (
    tester,
  ) async {
    final controller = StreamController<ViewUpdate>();
    addTearDown(controller.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAnimatedViewList(
                updates: controller.stream,
                itemBuilder: (context, row, index, animation) => SizeTransition(
                  sizeFactor: animation,
                  child: SizedBox(
                    height: 40,
                    child: Text('${row.id}:${row.value}'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(Text), findsNothing);

    controller.add(ViewSnapshot(_result([_row('a', 1), _row('b', 2)])));
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsNWidgets(2));

    controller.add(ViewChanges([ViewRowInserted(2, _row('c', 3))]));
    await tester.pumpAndSettle();
    expect(find.text('c:3'), findsOneWidget);
    expect(find.byType(Text), findsNWidgets(3));

    controller.add(ViewChanges([ViewRowRemoved(0, _row('a', 1))]));
    await tester.pumpAndSettle();
    expect(find.text('a:1'), findsNothing);
    expect(find.byType(Text), findsNWidgets(2));
  });
}
