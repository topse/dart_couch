import 'package:dart_mappable/dart_mappable.dart';

part 'revs_diff_result.mapper.dart';

/// Represents a single entry in the RevsDiff result
/// in CouchDB's _revs_diff response shape:
/// {
///   "missing": ["1-...","2-..."],
///   "possible_ancestors": ["..."]
/// }
@MappableClass()
class RevsDiffEntry with RevsDiffEntryMappable {
  /// List of revisions missing in the database
  @MappableField()
  final List<String>? missing;

  /// List of known revisions that might be ancestors of missing revisions
  @MappableField(key: 'possible_ancestors')
  final List<String>? possibleAncestors;

  const RevsDiffEntry({this.missing, this.possibleAncestors});
}
