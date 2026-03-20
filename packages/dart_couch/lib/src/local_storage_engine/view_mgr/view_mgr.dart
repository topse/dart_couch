import 'package:drift/drift.dart';

import '../../messages/couch_document_base.dart';
import '../../messages/design_document.dart';
import '../database.dart';
import 'view_ctrl.dart';

class ViewMgr {
  final AppDatabase db;

  final Future<CouchDocumentBase?> Function(
    String docid, {
    String? rev,
    bool revs,
    bool revsInfo,
    bool attachments,
  })
  dbGetFunction;

  final int dbid;

  Future<void>? _initialized;

  ViewMgr({required this.db, required this.dbGetFunction, required this.dbid});

  Future<void> _init() {
    // load all views from sqlite
    return db.transaction<void>(() async {
      final viewRows = await db.select(db.localViews).get();

      // check if views' map/reduce functions still match and update if needed
      // also check if views are still present in the design documents

      bool allDocsExists = false;
      for (final LocalView view in viewRows) {
        // only check other than _all_docs
        if (view.viewPathShort != '_all_docs') {
          // first get design doc name and viewname
          final ViewPathShortHandler n = ViewPathShortHandler(
            view.viewPathShort,
          );

          DesignDocument? designDoc =
              (await dbGetFunction("_design/${n.designDocName}"))
                  as DesignDocument?;

          if (designDoc?.views?.keys.contains(n.viewName) == false) {
            // view is not existing anymore - delete it from database and also from map
            await (db.delete(
              db.localViews,
            )..where((tbl) => tbl.id.equals(view.id))).go();
          } else {
            // view still exists -- check map/reduce-functions
            final String mapFct = designDoc!.views![n.viewName]!.map;
            final String? reduceFct = designDoc.views![n.viewName]!.reduce;

            if (mapFct != view.mapFunction ||
                reduceFct != view.reduceFunction) {
              // view needs to be updated
              LocalView newView = view.copyWith(
                mapFunction: mapFct,
                reduceFunction: Value.absentIfNull(reduceFct),
                updateSeq: 0,
              );

              // delete processed view entries
              await (db.delete(
                db.localViewEntries,
              )..where((tbl) => tbl.fkview.equals(view.id))).go();
              // update and invalidate view
              await db.update(db.localViews).replace(newView);
            }
          }
        } else {
          allDocsExists = true;
        }
      }
      if (allDocsExists == false) {
        await db
            .into(db.localViews)
            .insert(
              LocalViewsCompanion.insert(
                database: dbid,
                viewPathShort: '_all_docs',
                mapFunction: '''function(doc) {
                                  emit(doc._id, { rev: doc._rev });
                                }''',
              ),
            );
      }
    });
  }

  Future<ViewCtrl?> getView(String viewPathShort) async {
    _initialized ??= _init();
    await _initialized;

    // 1. check if the view has already been created
    final row =
        await (db.select(db.localViews)
              ..where((tbl) => tbl.viewPathShort.equals(viewPathShort)))
            .getSingleOrNull();
    if (row != null) {
      // Check if this cached view still exists in its design document
      // (it might have been deleted since the view was cached)
      if (viewPathShort != '_all_docs') {
        final ViewPathShortHandler n = ViewPathShortHandler(viewPathShort);
        DesignDocument? designDoc =
            (await dbGetFunction("_design/${n.designDocName}"))
                as DesignDocument?;
        if (designDoc?.views?.keys.contains(n.viewName) == false) {
          // View was deleted from the design document - remove it from cache
          log.info('ViewMgr.getView: View $viewPathShort was deleted from design document, removing from cache');
          await (db.delete(
            db.localViews,
          )..where((tbl) => tbl.id.equals(row.id))).go();
          return null;
        }
      }
      
      log.info(
        'ViewMgr.getView: Found existing view id=${row.id}, updateSeq=${row.updateSeq} for $viewPathShort',
      );
      return ViewCtrl(
        db: db,
        dbid: dbid,
        view: row,
        dbGetFunction: dbGetFunction,
      );
    }

    // 2. check if the real _design-document/_view exists
    //    and try to create view
    if (viewPathShort == '_all_docs') {
      LocalView v = await (db.select(
        db.localViews,
      )..where((tbl) => tbl.viewPathShort.equals('_all_docs'))).getSingle();

      return ViewCtrl(
        dbid: dbid,
        db: db,
        view: v,
        dbGetFunction: dbGetFunction,
      );
    } else {
      final ViewPathShortHandler n = ViewPathShortHandler(viewPathShort);
      DesignDocument? designDoc =
          (await dbGetFunction("_design/${n.designDocName}"))
              as DesignDocument?;
      if (designDoc?.views?.keys.contains(n.viewName) == true) {
        LocalViewsCompanion newView = LocalViewsCompanion(
          database: Value(dbid),
          viewPathShort: Value(viewPathShort),
          mapFunction: Value(designDoc!.views![n.viewName]!.map),
          reduceFunction: Value(designDoc.views![n.viewName]!.reduce),
        );

        try {
          int id = await db.into(db.localViews).insert(newView);
          log.info('ViewMgr: Created new view with id=$id for $viewPathShort');

          // load new view and create ctrl:
          LocalView v = await (db.select(
            db.localViews,
          )..where((tbl) => tbl.id.equals(id))).getSingle();

          return ViewCtrl(
            dbid: dbid,
            db: db,
            view: v,
            dbGetFunction: dbGetFunction,
          );
        } catch (e) {
          log.info('ViewMgr: Failed to insert view for $viewPathShort: $e');
          // Check if it failed due to unique constraint violation
          // (Another concurrent call already created the view)
          final existingView =
              await (db.select(db.localViews)..where(
                    (tbl) =>
                        tbl.viewPathShort.equals(viewPathShort) &
                        tbl.database.equals(dbid),
                  ))
                  .getSingleOrNull();

          if (existingView != null) {
            log.info('ViewMgr: Using existing view with id=${existingView.id}');
            // Use the existing view
            return ViewCtrl(
              dbid: dbid,
              db: db,
              view: existingView,
              dbGetFunction: dbGetFunction,
            );
          }

          // Some other error, rethrow
          rethrow;
        }
      }
    }

    return null;
  }
}

class ViewPathShortHandler {
  final String viewPathShort;
  late final String designDocName;
  late final String viewName;

  ViewPathShortHandler(this.viewPathShort) {
    List<String> tokens = viewPathShort.split("/");
    assert(tokens.length == 2);
    designDocName = tokens[0];
    viewName = tokens[1];
  }
}
