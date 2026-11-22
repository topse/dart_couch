import 'dart:async';

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('dart_couch-query_stats');

/// Opt-in diagnostics that count every query sent from the calling isolate to
/// the drift (SQLite) executor.
///
/// Each drift query against a background-isolate database is a full isolate
/// round trip (request bookkeeping, message copy, response dispatch) that runs
/// on the *calling* isolate — typically the Flutter UI isolate. On slow devices
/// that per-query overhead, multiplied by N+1 access patterns, dominates
/// frame time even though SQLite itself runs elsewhere. These counters make
/// the query volume visible.
///
/// Must be enabled **before** the local database is opened (the interceptor
/// is installed at connection creation). Disabled by default: zero overhead.
class DbQueryStats {
  DbQueryStats._();

  /// Install the counting interceptor for databases opened from now on.
  static bool enabled = false;

  /// Interval for the periodic summary log line (only logged when queries
  /// happened in the interval).
  static Duration logInterval = const Duration(seconds: 2);

  static int _total = 0;
  static final Map<String, int> _byStatement = {};
  static Timer? _timer;

  /// Total number of queries since startup.
  static int get total => _total;

  static void _record(String statement) {
    _total++;
    final key = _normalize(statement);
    _byStatement[key] = (_byStatement[key] ?? 0) + 1;
    _timer ??= Timer(logInterval, _flush);
  }

  static void _flush() {
    _timer = null;
    if (_byStatement.isEmpty) return;
    final sum = _byStatement.values.fold<int>(0, (a, b) => a + b);
    final top = _byStatement.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final buf = StringBuffer(
      'DB queries: $sum in last ${logInterval.inMilliseconds} ms '
      '(total $_total)',
    );
    for (final e in top.take(5)) {
      buf.write('\n  ${e.value}x ${e.key}');
    }
    _byStatement.clear();
    _log.info(buf.toString());
  }

  /// Shortens a statement to its verb and table(s) so identical query shapes
  /// with different arguments aggregate into one bucket.
  static String _normalize(String sql) {
    final s = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
    final verb = s.split(' ').first.toUpperCase();
    final tables = RegExp(r'(?:FROM|JOIN|INTO|UPDATE)\s+"?(\w+)"?',
            caseSensitive: false)
        .allMatches(s)
        .map((m) => m.group(1))
        .toSet()
        .join('+');
    return '$verb $tables';
  }

  /// Wraps [executor] with the counting interceptor when [enabled].
  static QueryExecutor wrap(QueryExecutor executor) =>
      enabled ? executor.interceptWith(_CountingInterceptor()) : executor;
}

class _CountingInterceptor extends QueryInterceptor {
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    DbQueryStats._record(statement);
    return executor.runSelect(statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    DbQueryStats._record(statement);
    return executor.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    DbQueryStats._record(statement);
    return executor.runUpdate(statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    DbQueryStats._record(statement);
    return executor.runDelete(statement, args);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    DbQueryStats._record(statement);
    return executor.runCustom(statement, args);
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) {
    DbQueryStats._record('BATCH ${statements.statements.length}');
    return executor.runBatched(statements);
  }
}
