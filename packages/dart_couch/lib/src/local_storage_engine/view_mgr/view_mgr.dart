import 'package:drift/drift.dart';
import 'package:mutex/mutex.dart';

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

  /// Batched winner-document loader (see [ViewCtrl.dbGetManyFunction]).
  final DbGetManyFunction dbGetManyFunction;

  final int dbid;

  Future<void>? _initialized;

  /// One controller per view path, kept across queries (see [getView]).
  final Map<String, ViewCtrl> _ctrls = {};

  /// Paths in [_ctrls] validated against their design document with no
  /// design-document change up to [_validatedSeq].
  final Set<String> _validated = {};

  /// Database update seq up to which [_validated] holds; null before the
  /// first [getView].
  int? _validatedSeq;

  /// Serialises [getView] so cache fills and re-validations cannot race.
  final Mutex _getViewMutex = Mutex();

  ViewMgr({
    required this.db,
    required this.dbGetFunction,
    required this.dbGetManyFunction,
    required this.dbid,
  });

  /// Whether [viewPathShort] has the `designDocName/viewName` shape of a
  /// design-document view. `_all_docs` is not a view here: it is served
  /// directly from the documents table (`LocalDartCouchDb._internalAllDocs`)
  /// and has no `local_views` row (removed by the schema v8 migration).
  static bool _isDesignViewPath(String viewPathShort) =>
      viewPathShort.split('/').length == 2;

  Future<void> _init() {
    // load the views of THIS database from sqlite (one SQLite file hosts
    // several databases; their views must not be validated against this
    // database's design documents)
    return db.transaction<void>(() async {
      final viewRows = await (db.select(
        db.localViews,
      )..where((tbl) => tbl.database.equals(dbid))).get();

      // check if views' map/reduce functions still match and update if needed
      // also check if views are still present in the design documents
      for (final LocalView view in viewRows) {
        // Legacy `_all_docs` rows (pre-v8) are skipped.
        if (_isDesignViewPath(view.viewPathShort)) {
          // first get design doc name and viewname
          final ViewPathShortHandler n = ViewPathShortHandler(
            view.viewPathShort,
          );

          DesignDocument? designDoc =
              (await dbGetFunction("_design/${n.designDocName}"))
                  as DesignDocument?;

          // A missing design document (null) means the view is gone, too.
          if (designDoc?.views?.keys.contains(n.viewName) != true) {
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
        }
      }
    });
  }

  /// Returns the controller of the design-document view [viewPathShort]
  /// (`designDocName/viewName`) of this database, creating its index row on
  /// first use, or `null` when no such view exists. `_all_docs` (and any
  /// other non-`ddoc/view` path) yields `null`.
  ///
  /// Controllers are cached per path. A cached controller is re-validated
  /// against its design document (deleted view / changed map or reduce →
  /// same handling as on first use) only when a design document of this
  /// database was written since the last validation; otherwise a call costs
  /// one query ([AppDatabase.designDocChangeProbe]), whose update seq is
  /// handed to the controller so its index check needs no query of its own.
  Future<ViewCtrl?> getView(String viewPathShort) async {
    if (!_isDesignViewPath(viewPathShort)) return null;
    _initialized ??= _init();
    await _initialized;

    return _getViewMutex.protect(() async {
      final probe = await db.designDocChangeProbe(dbid, _validatedSeq ?? -1);
      if (_validatedSeq == null || probe.designDocsChanged) {
        // Some design document changed since the cached controllers were
        // validated: each must be re-validated on its next use.
        _validated.clear();
      }
      // Every path in [_validated] is valid at least up to probe.updateSeq
      // (no design doc changed in between).
      _validatedSeq = probe.updateSeq;

      final ViewCtrl? cached = _ctrls[viewPathShort];
      if (cached != null && _validated.contains(viewPathShort)) {
        cached.noteDbUpdateSeq(probe.updateSeq);
        return cached;
      }

      final ViewCtrl? ctrl = await _validateView(viewPathShort, cached);
      if (ctrl == null) {
        _ctrls.remove(viewPathShort);
        _validated.remove(viewPathShort);
        return null;
      }
      _ctrls[viewPathShort] = ctrl;
      _validated.add(viewPathShort);
      ctrl.noteDbUpdateSeq(probe.updateSeq);
      return ctrl;
    });
  }

  /// Validates [viewPathShort] against its current design document and
  /// returns its controller — [cached] (updated in place) when there is one,
  /// so a view never has two controllers (each serialises its own index
  /// updates) — or `null` when the view does not exist (any index row is
  /// then removed).
  Future<ViewCtrl?> _validateView(
    String viewPathShort,
    ViewCtrl? cached,
  ) async {
    // Applies a row change to [cached] without racing a running index update.
    Future<void> exclusive(Future<void> Function() action) =>
        cached != null ? cached.runExclusive(action) : action();

    final ViewPathShortHandler n = ViewPathShortHandler(viewPathShort);
    final DesignDocument? designDoc =
        (await dbGetFunction("_design/${n.designDocName}")) as DesignDocument?;
    final ViewData? def = designDoc?.views?[n.viewName];

    // 1. check if the view has already been created (in THIS database)
    final row =
        await (db.select(db.localViews)..where(
              (tbl) =>
                  tbl.viewPathShort.equals(viewPathShort) &
                  tbl.database.equals(dbid),
            ))
            .getSingleOrNull();
    if (row != null) {
      // Validate the cached view against its current design document: it may
      // have been deleted, or its map/reduce definition may have changed since
      // the view was cached. `effective` is the row the ViewCtrl will use.
      LocalView effective = row;
      if (def == null) {
        // View no longer exists (removed from the design document, or the
        // whole design document was deleted) - remove it from cache.
        log.info(
          'ViewMgr.getView: View $viewPathShort no longer exists in its design document, removing from cache',
        );
        await exclusive(
          () => (db.delete(
            db.localViews,
          )..where((tbl) => tbl.id.equals(row.id))).go(),
        );
        return null;
      }
      if (def.map != row.mapFunction || def.reduce != row.reduceFunction) {
        // The view definition changed. Discard the stale index and adopt the
        // new map/reduce with a reset updateSeq so the next query re-indexes
        // every document — matching CouchDB, which rebuilds a view when its
        // design document's view signature changes.
        log.info(
          'ViewMgr.getView: View $viewPathShort definition changed, invalidating index for rebuild',
        );
        effective = row.copyWith(
          mapFunction: def.map,
          reduceFunction: Value(def.reduce),
          updateSeq: 0,
        );
        final LocalView newRow = effective;
        await exclusive(() async {
          // One round trip, atomic.
          await db.batch((b) {
            b.deleteWhere(
              db.localViewEntries,
              (tbl) => tbl.fkview.equals(row.id),
            );
            b.replace(db.localViews, newRow);
          });
          cached?.adoptView(newRow);
        });
      } else if (cached != null &&
          (cached.view.id != row.id ||
              cached.view.mapFunction != row.mapFunction ||
              cached.view.reduceFunction != row.reduceFunction)) {
        // The row was replaced behind this controller's back (e.g. by another
        // instance of this database): follow the stored row. An unchanged
        // row is NOT adopted — the controller's in-memory updateSeq may be
        // ahead of the stored one (see ViewCtrl._maxUnpersistedDocs).
        await exclusive(() async => cached.adoptView(row));
      }

      log.fine(
        () =>
            'ViewMgr.getView: Found existing view id=${effective.id}, updateSeq=${effective.updateSeq} for $viewPathShort',
      );
      return cached ?? _newCtrl(effective);
    }

    // 2. check if the real _design-document/_view exists
    //    and try to create view
    if (def != null) {
      LocalViewsCompanion newView = LocalViewsCompanion(
        database: Value(dbid),
        viewPathShort: Value(viewPathShort),
        mapFunction: Value(def.map),
        reduceFunction: Value(def.reduce),
      );

      LocalView v;
      try {
        int id = await db.into(db.localViews).insert(newView);
        log.info('ViewMgr: Created new view with id=$id for $viewPathShort');

        // load new view and create ctrl:
        v = await (db.select(
          db.localViews,
        )..where((tbl) => tbl.id.equals(id))).getSingle();
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

        if (existingView == null) {
          // Some other error, rethrow
          rethrow;
        }
        log.fine(
          () => 'ViewMgr: Using existing view with id=${existingView.id}',
        );
        // Use the existing view
        v = existingView;
      }
      if (cached != null) {
        // The row vanished behind the cached controller (e.g. removed by
        // another instance) and was re-created: follow the new row.
        final LocalView newRow = v;
        await exclusive(() async => cached.adoptView(newRow));
        return cached;
      }
      return _newCtrl(v);
    }

    return null;
  }

  ViewCtrl _newCtrl(LocalView view) => ViewCtrl(
    dbid: dbid,
    db: db,
    view: view,
    dbGetFunction: dbGetFunction,
    dbGetManyFunction: dbGetManyFunction,
  );
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
