import 'package:dart_mappable/dart_mappable.dart';

import 'couch_document_base.dart';

part 'changes_result.mapper.dart';

enum ChangesResultType { normal, continuous }

class ChangesResult {
  final ChangesResultType type;
  final ChangesResultNormal? normal;

  final ChangeEntry? continuous;

  ChangesResult._({required this.type, this.normal, this.continuous});

  factory ChangesResult.normal(ChangesResultNormal normal) {
    return ChangesResult._(type: ChangesResultType.normal, normal: normal);
  }

  factory ChangesResult.continuous(ChangeEntry continuous) {
    return ChangesResult._(
      type: ChangesResultType.continuous,
      continuous: continuous,
    );
  }
}

@MappableClass()
class ChangesResultNormal with ChangesResultNormalMappable {
  @MappableField(key: 'last_seq')
  late final String lastSeq;

  /// [pending] tells you how many changes are still waiting to be sent after the
  /// ones you’ve already received in this response.
  ///
  /// It’s the count of unreported changes that exist after the last_seq value returned.
  /// It helps clients understand whether they’ve caught up with the database or if there’s more to read.
  /// this field is only used for feedmode=normal or longpoll
  @MappableField()
  late final int pending;

  /// this field is only used for feedmode=normal or longpoll
  @MappableField()
  late final List<ChangeEntry> results;

  ChangesResultNormal({
    required this.lastSeq,
    required this.pending,
    required this.results,
  });

  int get lastSeqNumber {
    final parts = lastSeq.split('-');
    if (parts.length < 2) {
      throw FormatException('Invalid last sequence format: $lastSeq');
    }
    return int.parse(parts[0]);
  }

  static final fromMap = ChangesResultNormalMapper.fromMap;
  static final fromJson = ChangesResultNormalMapper.fromJson;
}

@MappableClass()
class ChangeEntry with ChangeEntryMappable {
  @MappableField()
  final String id;
  @MappableField()
  final String seq;
  @MappableField()
  final List<RevisionListEntry> changes;
  @MappableField()
  final bool deleted;

  final CouchDocumentBase? doc;

  ChangeEntry({
    required this.id,
    required this.seq,
    required this.changes,
    this.deleted = false,
    this.doc,
  });

  int get seqNumber {
    final parts = seq.split('-');
    if (parts.length < 2) {
      throw FormatException('Invalid last sequence format: $seq');
    }
    return int.parse(parts[0]);
  }

  static final fromMap = ChangeEntryMapper.fromMap;
  static final fromJson = ChangeEntryMapper.fromJson;
}

@MappableClass()
class RevisionListEntry with RevisionListEntryMappable {
  @MappableField()
  final String rev;
  RevisionListEntry({required this.rev});
}
