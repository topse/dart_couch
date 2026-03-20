// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $LocalDatabasesTable extends LocalDatabases
    with TableInfo<$LocalDatabasesTable, LocalDatabase> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalDatabasesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _updateSeqMeta = const VerificationMeta(
    'updateSeq',
  );
  @override
  late final GeneratedColumn<int> updateSeq = GeneratedColumn<int>(
    'update_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, updateSeq];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_databases';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalDatabase> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('update_seq')) {
      context.handle(
        _updateSeqMeta,
        updateSeq.isAcceptableOrUnknown(data['update_seq']!, _updateSeqMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalDatabase map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalDatabase(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      updateSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}update_seq'],
      )!,
    );
  }

  @override
  $LocalDatabasesTable createAlias(String alias) {
    return $LocalDatabasesTable(attachedDatabase, alias);
  }
}

class LocalDatabase extends DataClass implements Insertable<LocalDatabase> {
  final int id;
  final String name;

  /// when a database is created, this starts with zero,
  /// first document added gets seq 1, next seq 2, ...
  final int updateSeq;
  const LocalDatabase({
    required this.id,
    required this.name,
    required this.updateSeq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['update_seq'] = Variable<int>(updateSeq);
    return map;
  }

  LocalDatabasesCompanion toCompanion(bool nullToAbsent) {
    return LocalDatabasesCompanion(
      id: Value(id),
      name: Value(name),
      updateSeq: Value(updateSeq),
    );
  }

  factory LocalDatabase.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalDatabase(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      updateSeq: serializer.fromJson<int>(json['updateSeq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'updateSeq': serializer.toJson<int>(updateSeq),
    };
  }

  LocalDatabase copyWith({int? id, String? name, int? updateSeq}) =>
      LocalDatabase(
        id: id ?? this.id,
        name: name ?? this.name,
        updateSeq: updateSeq ?? this.updateSeq,
      );
  LocalDatabase copyWithCompanion(LocalDatabasesCompanion data) {
    return LocalDatabase(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      updateSeq: data.updateSeq.present ? data.updateSeq.value : this.updateSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalDatabase(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('updateSeq: $updateSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, updateSeq);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalDatabase &&
          other.id == this.id &&
          other.name == this.name &&
          other.updateSeq == this.updateSeq);
}

class LocalDatabasesCompanion extends UpdateCompanion<LocalDatabase> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> updateSeq;
  const LocalDatabasesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.updateSeq = const Value.absent(),
  });
  LocalDatabasesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.updateSeq = const Value.absent(),
  }) : name = Value(name);
  static Insertable<LocalDatabase> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? updateSeq,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (updateSeq != null) 'update_seq': updateSeq,
    });
  }

  LocalDatabasesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<int>? updateSeq,
  }) {
    return LocalDatabasesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      updateSeq: updateSeq ?? this.updateSeq,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (updateSeq.present) {
      map['update_seq'] = Variable<int>(updateSeq.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalDatabasesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('updateSeq: $updateSeq')
          ..write(')'))
        .toString();
  }
}

class $LocalDocumentsTable extends LocalDocuments
    with TableInfo<$LocalDocumentsTable, LocalDocument> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalDocumentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _fkdatabaseMeta = const VerificationMeta(
    'fkdatabase',
  );
  @override
  late final GeneratedColumn<int> fkdatabase = GeneratedColumn<int>(
    'fkdatabase',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_databases (id)',
    ),
  );
  static const VerificationMeta _docidMeta = const VerificationMeta('docid');
  @override
  late final GeneratedColumn<String> docid = GeneratedColumn<String>(
    'docid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revMeta = const VerificationMeta('rev');
  @override
  late final GeneratedColumn<String> rev = GeneratedColumn<String>(
    'rev',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
  );
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    fkdatabase,
    docid,
    rev,
    version,
    deleted,
    seq,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_documents';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalDocument> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('fkdatabase')) {
      context.handle(
        _fkdatabaseMeta,
        fkdatabase.isAcceptableOrUnknown(data['fkdatabase']!, _fkdatabaseMeta),
      );
    } else if (isInserting) {
      context.missing(_fkdatabaseMeta);
    }
    if (data.containsKey('docid')) {
      context.handle(
        _docidMeta,
        docid.isAcceptableOrUnknown(data['docid']!, _docidMeta),
      );
    } else if (isInserting) {
      context.missing(_docidMeta);
    }
    if (data.containsKey('rev')) {
      context.handle(
        _revMeta,
        rev.isAcceptableOrUnknown(data['rev']!, _revMeta),
      );
    } else if (isInserting) {
      context.missing(_revMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    } else if (isInserting) {
      context.missing(_seqMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalDocument map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalDocument(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      fkdatabase: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fkdatabase'],
      )!,
      docid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}docid'],
      )!,
      rev: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rev'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      ),
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
    );
  }

  @override
  $LocalDocumentsTable createAlias(String alias) {
    return $LocalDocumentsTable(attachedDatabase, alias);
  }
}

class LocalDocument extends DataClass implements Insertable<LocalDocument> {
  final int id;
  final int fkdatabase;
  final String docid;

  /// rev is the revision identifier, e.g. "1-abcdef1234567890"
  final String rev;

  /// version is part of the revision identifier, e.g. "1" in "1-abcdef1234567890"
  /// it is incremented with each new revision and additionally stored as
  /// integer for easy sorting
  final int version;
  final bool? deleted;

  /// The sequence number when this revision was added, last updated or last deleted
  /// when updating a document:
  ///   first get updateSeq from LocalDatabases
  ///   then increment it by one
  ///   then set this field to that value
  ///   then update updateSeq in LocalDatabases to that value
  /// So the document updated last has the same seq as the database updateSeq
  final int seq;
  const LocalDocument({
    required this.id,
    required this.fkdatabase,
    required this.docid,
    required this.rev,
    required this.version,
    this.deleted,
    required this.seq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['fkdatabase'] = Variable<int>(fkdatabase);
    map['docid'] = Variable<String>(docid);
    map['rev'] = Variable<String>(rev);
    map['version'] = Variable<int>(version);
    if (!nullToAbsent || deleted != null) {
      map['deleted'] = Variable<bool>(deleted);
    }
    map['seq'] = Variable<int>(seq);
    return map;
  }

  LocalDocumentsCompanion toCompanion(bool nullToAbsent) {
    return LocalDocumentsCompanion(
      id: Value(id),
      fkdatabase: Value(fkdatabase),
      docid: Value(docid),
      rev: Value(rev),
      version: Value(version),
      deleted: deleted == null && nullToAbsent
          ? const Value.absent()
          : Value(deleted),
      seq: Value(seq),
    );
  }

  factory LocalDocument.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalDocument(
      id: serializer.fromJson<int>(json['id']),
      fkdatabase: serializer.fromJson<int>(json['fkdatabase']),
      docid: serializer.fromJson<String>(json['docid']),
      rev: serializer.fromJson<String>(json['rev']),
      version: serializer.fromJson<int>(json['version']),
      deleted: serializer.fromJson<bool?>(json['deleted']),
      seq: serializer.fromJson<int>(json['seq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'fkdatabase': serializer.toJson<int>(fkdatabase),
      'docid': serializer.toJson<String>(docid),
      'rev': serializer.toJson<String>(rev),
      'version': serializer.toJson<int>(version),
      'deleted': serializer.toJson<bool?>(deleted),
      'seq': serializer.toJson<int>(seq),
    };
  }

  LocalDocument copyWith({
    int? id,
    int? fkdatabase,
    String? docid,
    String? rev,
    int? version,
    Value<bool?> deleted = const Value.absent(),
    int? seq,
  }) => LocalDocument(
    id: id ?? this.id,
    fkdatabase: fkdatabase ?? this.fkdatabase,
    docid: docid ?? this.docid,
    rev: rev ?? this.rev,
    version: version ?? this.version,
    deleted: deleted.present ? deleted.value : this.deleted,
    seq: seq ?? this.seq,
  );
  LocalDocument copyWithCompanion(LocalDocumentsCompanion data) {
    return LocalDocument(
      id: data.id.present ? data.id.value : this.id,
      fkdatabase: data.fkdatabase.present
          ? data.fkdatabase.value
          : this.fkdatabase,
      docid: data.docid.present ? data.docid.value : this.docid,
      rev: data.rev.present ? data.rev.value : this.rev,
      version: data.version.present ? data.version.value : this.version,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      seq: data.seq.present ? data.seq.value : this.seq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalDocument(')
          ..write('id: $id, ')
          ..write('fkdatabase: $fkdatabase, ')
          ..write('docid: $docid, ')
          ..write('rev: $rev, ')
          ..write('version: $version, ')
          ..write('deleted: $deleted, ')
          ..write('seq: $seq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, fkdatabase, docid, rev, version, deleted, seq);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalDocument &&
          other.id == this.id &&
          other.fkdatabase == this.fkdatabase &&
          other.docid == this.docid &&
          other.rev == this.rev &&
          other.version == this.version &&
          other.deleted == this.deleted &&
          other.seq == this.seq);
}

class LocalDocumentsCompanion extends UpdateCompanion<LocalDocument> {
  final Value<int> id;
  final Value<int> fkdatabase;
  final Value<String> docid;
  final Value<String> rev;
  final Value<int> version;
  final Value<bool?> deleted;
  final Value<int> seq;
  const LocalDocumentsCompanion({
    this.id = const Value.absent(),
    this.fkdatabase = const Value.absent(),
    this.docid = const Value.absent(),
    this.rev = const Value.absent(),
    this.version = const Value.absent(),
    this.deleted = const Value.absent(),
    this.seq = const Value.absent(),
  });
  LocalDocumentsCompanion.insert({
    this.id = const Value.absent(),
    required int fkdatabase,
    required String docid,
    required String rev,
    required int version,
    this.deleted = const Value.absent(),
    required int seq,
  }) : fkdatabase = Value(fkdatabase),
       docid = Value(docid),
       rev = Value(rev),
       version = Value(version),
       seq = Value(seq);
  static Insertable<LocalDocument> custom({
    Expression<int>? id,
    Expression<int>? fkdatabase,
    Expression<String>? docid,
    Expression<String>? rev,
    Expression<int>? version,
    Expression<bool>? deleted,
    Expression<int>? seq,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fkdatabase != null) 'fkdatabase': fkdatabase,
      if (docid != null) 'docid': docid,
      if (rev != null) 'rev': rev,
      if (version != null) 'version': version,
      if (deleted != null) 'deleted': deleted,
      if (seq != null) 'seq': seq,
    });
  }

  LocalDocumentsCompanion copyWith({
    Value<int>? id,
    Value<int>? fkdatabase,
    Value<String>? docid,
    Value<String>? rev,
    Value<int>? version,
    Value<bool?>? deleted,
    Value<int>? seq,
  }) {
    return LocalDocumentsCompanion(
      id: id ?? this.id,
      fkdatabase: fkdatabase ?? this.fkdatabase,
      docid: docid ?? this.docid,
      rev: rev ?? this.rev,
      version: version ?? this.version,
      deleted: deleted ?? this.deleted,
      seq: seq ?? this.seq,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (fkdatabase.present) {
      map['fkdatabase'] = Variable<int>(fkdatabase.value);
    }
    if (docid.present) {
      map['docid'] = Variable<String>(docid.value);
    }
    if (rev.present) {
      map['rev'] = Variable<String>(rev.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalDocumentsCompanion(')
          ..write('id: $id, ')
          ..write('fkdatabase: $fkdatabase, ')
          ..write('docid: $docid, ')
          ..write('rev: $rev, ')
          ..write('version: $version, ')
          ..write('deleted: $deleted, ')
          ..write('seq: $seq')
          ..write(')'))
        .toString();
  }
}

class $DocumentBlobsTable extends DocumentBlobs
    with TableInfo<$DocumentBlobsTable, DocumentBlob> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DocumentBlobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _documentIdMeta = const VerificationMeta(
    'documentId',
  );
  @override
  late final GeneratedColumn<int> documentId = GeneratedColumn<int>(
    'document_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_documents (id)',
    ),
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [documentId, data];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'document_blobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<DocumentBlob> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('document_id')) {
      context.handle(
        _documentIdMeta,
        documentId.isAcceptableOrUnknown(data['document_id']!, _documentIdMeta),
      );
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {documentId};
  @override
  DocumentBlob map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DocumentBlob(
      documentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}document_id'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      )!,
    );
  }

  @override
  $DocumentBlobsTable createAlias(String alias) {
    return $DocumentBlobsTable(attachedDatabase, alias);
  }
}

class DocumentBlob extends DataClass implements Insertable<DocumentBlob> {
  final int documentId;
  final String data;
  const DocumentBlob({required this.documentId, required this.data});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['document_id'] = Variable<int>(documentId);
    map['data'] = Variable<String>(data);
    return map;
  }

  DocumentBlobsCompanion toCompanion(bool nullToAbsent) {
    return DocumentBlobsCompanion(
      documentId: Value(documentId),
      data: Value(data),
    );
  }

  factory DocumentBlob.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DocumentBlob(
      documentId: serializer.fromJson<int>(json['documentId']),
      data: serializer.fromJson<String>(json['data']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'documentId': serializer.toJson<int>(documentId),
      'data': serializer.toJson<String>(data),
    };
  }

  DocumentBlob copyWith({int? documentId, String? data}) => DocumentBlob(
    documentId: documentId ?? this.documentId,
    data: data ?? this.data,
  );
  DocumentBlob copyWithCompanion(DocumentBlobsCompanion data) {
    return DocumentBlob(
      documentId: data.documentId.present
          ? data.documentId.value
          : this.documentId,
      data: data.data.present ? data.data.value : this.data,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DocumentBlob(')
          ..write('documentId: $documentId, ')
          ..write('data: $data')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(documentId, data);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DocumentBlob &&
          other.documentId == this.documentId &&
          other.data == this.data);
}

class DocumentBlobsCompanion extends UpdateCompanion<DocumentBlob> {
  final Value<int> documentId;
  final Value<String> data;
  const DocumentBlobsCompanion({
    this.documentId = const Value.absent(),
    this.data = const Value.absent(),
  });
  DocumentBlobsCompanion.insert({
    this.documentId = const Value.absent(),
    required String data,
  }) : data = Value(data);
  static Insertable<DocumentBlob> custom({
    Expression<int>? documentId,
    Expression<String>? data,
  }) {
    return RawValuesInsertable({
      if (documentId != null) 'document_id': documentId,
      if (data != null) 'data': data,
    });
  }

  DocumentBlobsCompanion copyWith({
    Value<int>? documentId,
    Value<String>? data,
  }) {
    return DocumentBlobsCompanion(
      documentId: documentId ?? this.documentId,
      data: data ?? this.data,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (documentId.present) {
      map['document_id'] = Variable<int>(documentId.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DocumentBlobsCompanion(')
          ..write('documentId: $documentId, ')
          ..write('data: $data')
          ..write(')'))
        .toString();
  }
}

class $RevisionHistoriesTable extends RevisionHistories
    with TableInfo<$RevisionHistoriesTable, RevisionHistory> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RevisionHistoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _fkdocumentMeta = const VerificationMeta(
    'fkdocument',
  );
  @override
  late final GeneratedColumn<int> fkdocument = GeneratedColumn<int>(
    'fkdocument',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_documents (id)',
    ),
  );
  static const VerificationMeta _revMeta = const VerificationMeta('rev');
  @override
  late final GeneratedColumn<String> rev = GeneratedColumn<String>(
    'rev',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    fkdocument,
    rev,
    version,
    seq,
    deleted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'revision_histories';
  @override
  VerificationContext validateIntegrity(
    Insertable<RevisionHistory> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('fkdocument')) {
      context.handle(
        _fkdocumentMeta,
        fkdocument.isAcceptableOrUnknown(data['fkdocument']!, _fkdocumentMeta),
      );
    } else if (isInserting) {
      context.missing(_fkdocumentMeta);
    }
    if (data.containsKey('rev')) {
      context.handle(
        _revMeta,
        rev.isAcceptableOrUnknown(data['rev']!, _revMeta),
      );
    } else if (isInserting) {
      context.missing(_revMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    } else if (isInserting) {
      context.missing(_seqMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RevisionHistory map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RevisionHistory(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      fkdocument: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fkdocument'],
      )!,
      rev: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rev'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      ),
    );
  }

  @override
  $RevisionHistoriesTable createAlias(String alias) {
    return $RevisionHistoriesTable(attachedDatabase, alias);
  }
}

class RevisionHistory extends DataClass implements Insertable<RevisionHistory> {
  final int id;
  final int fkdocument;

  /// rev is the complete rev lik2 '3-12baafe552...'
  final String rev;

  /// version is only the first part of the ref -- for simpler sorting
  final int version;
  final int seq;
  final bool? deleted;
  const RevisionHistory({
    required this.id,
    required this.fkdocument,
    required this.rev,
    required this.version,
    required this.seq,
    this.deleted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['fkdocument'] = Variable<int>(fkdocument);
    map['rev'] = Variable<String>(rev);
    map['version'] = Variable<int>(version);
    map['seq'] = Variable<int>(seq);
    if (!nullToAbsent || deleted != null) {
      map['deleted'] = Variable<bool>(deleted);
    }
    return map;
  }

  RevisionHistoriesCompanion toCompanion(bool nullToAbsent) {
    return RevisionHistoriesCompanion(
      id: Value(id),
      fkdocument: Value(fkdocument),
      rev: Value(rev),
      version: Value(version),
      seq: Value(seq),
      deleted: deleted == null && nullToAbsent
          ? const Value.absent()
          : Value(deleted),
    );
  }

  factory RevisionHistory.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RevisionHistory(
      id: serializer.fromJson<int>(json['id']),
      fkdocument: serializer.fromJson<int>(json['fkdocument']),
      rev: serializer.fromJson<String>(json['rev']),
      version: serializer.fromJson<int>(json['version']),
      seq: serializer.fromJson<int>(json['seq']),
      deleted: serializer.fromJson<bool?>(json['deleted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'fkdocument': serializer.toJson<int>(fkdocument),
      'rev': serializer.toJson<String>(rev),
      'version': serializer.toJson<int>(version),
      'seq': serializer.toJson<int>(seq),
      'deleted': serializer.toJson<bool?>(deleted),
    };
  }

  RevisionHistory copyWith({
    int? id,
    int? fkdocument,
    String? rev,
    int? version,
    int? seq,
    Value<bool?> deleted = const Value.absent(),
  }) => RevisionHistory(
    id: id ?? this.id,
    fkdocument: fkdocument ?? this.fkdocument,
    rev: rev ?? this.rev,
    version: version ?? this.version,
    seq: seq ?? this.seq,
    deleted: deleted.present ? deleted.value : this.deleted,
  );
  RevisionHistory copyWithCompanion(RevisionHistoriesCompanion data) {
    return RevisionHistory(
      id: data.id.present ? data.id.value : this.id,
      fkdocument: data.fkdocument.present
          ? data.fkdocument.value
          : this.fkdocument,
      rev: data.rev.present ? data.rev.value : this.rev,
      version: data.version.present ? data.version.value : this.version,
      seq: data.seq.present ? data.seq.value : this.seq,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RevisionHistory(')
          ..write('id: $id, ')
          ..write('fkdocument: $fkdocument, ')
          ..write('rev: $rev, ')
          ..write('version: $version, ')
          ..write('seq: $seq, ')
          ..write('deleted: $deleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, fkdocument, rev, version, seq, deleted);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RevisionHistory &&
          other.id == this.id &&
          other.fkdocument == this.fkdocument &&
          other.rev == this.rev &&
          other.version == this.version &&
          other.seq == this.seq &&
          other.deleted == this.deleted);
}

class RevisionHistoriesCompanion extends UpdateCompanion<RevisionHistory> {
  final Value<int> id;
  final Value<int> fkdocument;
  final Value<String> rev;
  final Value<int> version;
  final Value<int> seq;
  final Value<bool?> deleted;
  const RevisionHistoriesCompanion({
    this.id = const Value.absent(),
    this.fkdocument = const Value.absent(),
    this.rev = const Value.absent(),
    this.version = const Value.absent(),
    this.seq = const Value.absent(),
    this.deleted = const Value.absent(),
  });
  RevisionHistoriesCompanion.insert({
    this.id = const Value.absent(),
    required int fkdocument,
    required String rev,
    required int version,
    required int seq,
    this.deleted = const Value.absent(),
  }) : fkdocument = Value(fkdocument),
       rev = Value(rev),
       version = Value(version),
       seq = Value(seq);
  static Insertable<RevisionHistory> custom({
    Expression<int>? id,
    Expression<int>? fkdocument,
    Expression<String>? rev,
    Expression<int>? version,
    Expression<int>? seq,
    Expression<bool>? deleted,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fkdocument != null) 'fkdocument': fkdocument,
      if (rev != null) 'rev': rev,
      if (version != null) 'version': version,
      if (seq != null) 'seq': seq,
      if (deleted != null) 'deleted': deleted,
    });
  }

  RevisionHistoriesCompanion copyWith({
    Value<int>? id,
    Value<int>? fkdocument,
    Value<String>? rev,
    Value<int>? version,
    Value<int>? seq,
    Value<bool?>? deleted,
  }) {
    return RevisionHistoriesCompanion(
      id: id ?? this.id,
      fkdocument: fkdocument ?? this.fkdocument,
      rev: rev ?? this.rev,
      version: version ?? this.version,
      seq: seq ?? this.seq,
      deleted: deleted ?? this.deleted,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (fkdocument.present) {
      map['fkdocument'] = Variable<int>(fkdocument.value);
    }
    if (rev.present) {
      map['rev'] = Variable<String>(rev.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RevisionHistoriesCompanion(')
          ..write('id: $id, ')
          ..write('fkdocument: $fkdocument, ')
          ..write('rev: $rev, ')
          ..write('version: $version, ')
          ..write('seq: $seq, ')
          ..write('deleted: $deleted')
          ..write(')'))
        .toString();
  }
}

class $LocalAttachmentsTable extends LocalAttachments
    with TableInfo<$LocalAttachmentsTable, LocalAttachment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalAttachmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _fkdocumentMeta = const VerificationMeta(
    'fkdocument',
  );
  @override
  late final GeneratedColumn<int> fkdocument = GeneratedColumn<int>(
    'fkdocument',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_documents (id)',
    ),
  );
  static const VerificationMeta _orderingMeta = const VerificationMeta(
    'ordering',
  );
  @override
  late final GeneratedColumn<int> ordering = GeneratedColumn<int>(
    'ordering',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revposMeta = const VerificationMeta('revpos');
  @override
  late final GeneratedColumn<int> revpos = GeneratedColumn<int>(
    'revpos',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lengthMeta = const VerificationMeta('length');
  @override
  late final GeneratedColumn<int> length = GeneratedColumn<int>(
    'length',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentTypeMeta = const VerificationMeta(
    'contentType',
  );
  @override
  late final GeneratedColumn<String> contentType = GeneratedColumn<String>(
    'content_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _digestMeta = const VerificationMeta('digest');
  @override
  late final GeneratedColumn<String> digest = GeneratedColumn<String>(
    'digest',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _encodingMeta = const VerificationMeta(
    'encoding',
  );
  @override
  late final GeneratedColumn<String> encoding = GeneratedColumn<String>(
    'encoding',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    fkdocument,
    ordering,
    revpos,
    name,
    length,
    contentType,
    digest,
    encoding,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_attachments';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalAttachment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('fkdocument')) {
      context.handle(
        _fkdocumentMeta,
        fkdocument.isAcceptableOrUnknown(data['fkdocument']!, _fkdocumentMeta),
      );
    } else if (isInserting) {
      context.missing(_fkdocumentMeta);
    }
    if (data.containsKey('ordering')) {
      context.handle(
        _orderingMeta,
        ordering.isAcceptableOrUnknown(data['ordering']!, _orderingMeta),
      );
    } else if (isInserting) {
      context.missing(_orderingMeta);
    }
    if (data.containsKey('revpos')) {
      context.handle(
        _revposMeta,
        revpos.isAcceptableOrUnknown(data['revpos']!, _revposMeta),
      );
    } else if (isInserting) {
      context.missing(_revposMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('length')) {
      context.handle(
        _lengthMeta,
        length.isAcceptableOrUnknown(data['length']!, _lengthMeta),
      );
    } else if (isInserting) {
      context.missing(_lengthMeta);
    }
    if (data.containsKey('content_type')) {
      context.handle(
        _contentTypeMeta,
        contentType.isAcceptableOrUnknown(
          data['content_type']!,
          _contentTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentTypeMeta);
    }
    if (data.containsKey('digest')) {
      context.handle(
        _digestMeta,
        digest.isAcceptableOrUnknown(data['digest']!, _digestMeta),
      );
    } else if (isInserting) {
      context.missing(_digestMeta);
    }
    if (data.containsKey('encoding')) {
      context.handle(
        _encodingMeta,
        encoding.isAcceptableOrUnknown(data['encoding']!, _encodingMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalAttachment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalAttachment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      fkdocument: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fkdocument'],
      )!,
      ordering: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ordering'],
      )!,
      revpos: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revpos'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      length: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}length'],
      )!,
      contentType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_type'],
      )!,
      digest: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}digest'],
      )!,
      encoding: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encoding'],
      ),
    );
  }

  @override
  $LocalAttachmentsTable createAlias(String alias) {
    return $LocalAttachmentsTable(attachedDatabase, alias);
  }
}

class LocalAttachment extends DataClass implements Insertable<LocalAttachment> {
  /// Integer primary key — also used as the filename in `att/`.
  final int id;
  final int fkdocument;
  final int ordering;

  /// revpos when the attachment was added or last updated
  /// corresponds to the documents version number
  final int revpos;
  final String name;

  /// Byte length of the uncompressed attachment data.
  final int length;
  final String contentType;

  /// CouchDB-style MD5 digest, e.g. `md5-<base64>`.
  ///
  /// The value depends on the write path:
  /// - **Local write** ([LocalDartCouchDb.saveAttachment]): computed from the raw
  ///   (uncompressed) bytes. File content matches digest.
  /// - **Replicated from CouchDB** ([LocalDartCouchDb.bulkDocsFromMultipart]):
  ///   copied verbatim from the CouchDB attachment stub. When [encoding] is
  ///   non-null (e.g. `'gzip'`), this is MD5 of the **compressed** bytes —
  ///   even though the `att/{id}` file holds the **decompressed** content.
  ///   See [encoding] and "CouchDB Attachment Compression" in CLAUDE.md.
  final String digest;

  /// Content-encoding applied by CouchDB before storage, e.g. `'gzip'`.
  ///
  /// `null` for locally-created attachments ([LocalDartCouchDb.saveAttachment]),
  /// where [digest] = MD5(raw bytes) and the file content matches the digest.
  ///
  /// `'gzip'` (or another codec) when replicated from CouchDB and CouchDB
  /// compressed the attachment: [digest] = MD5(compressed bytes), but the
  /// `att/{id}` file holds the decompressed content. This matches CouchDB's
  /// `encoding` field returned with `att_encoding_info=true`.
  final String? encoding;
  const LocalAttachment({
    required this.id,
    required this.fkdocument,
    required this.ordering,
    required this.revpos,
    required this.name,
    required this.length,
    required this.contentType,
    required this.digest,
    this.encoding,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['fkdocument'] = Variable<int>(fkdocument);
    map['ordering'] = Variable<int>(ordering);
    map['revpos'] = Variable<int>(revpos);
    map['name'] = Variable<String>(name);
    map['length'] = Variable<int>(length);
    map['content_type'] = Variable<String>(contentType);
    map['digest'] = Variable<String>(digest);
    if (!nullToAbsent || encoding != null) {
      map['encoding'] = Variable<String>(encoding);
    }
    return map;
  }

  LocalAttachmentsCompanion toCompanion(bool nullToAbsent) {
    return LocalAttachmentsCompanion(
      id: Value(id),
      fkdocument: Value(fkdocument),
      ordering: Value(ordering),
      revpos: Value(revpos),
      name: Value(name),
      length: Value(length),
      contentType: Value(contentType),
      digest: Value(digest),
      encoding: encoding == null && nullToAbsent
          ? const Value.absent()
          : Value(encoding),
    );
  }

  factory LocalAttachment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalAttachment(
      id: serializer.fromJson<int>(json['id']),
      fkdocument: serializer.fromJson<int>(json['fkdocument']),
      ordering: serializer.fromJson<int>(json['ordering']),
      revpos: serializer.fromJson<int>(json['revpos']),
      name: serializer.fromJson<String>(json['name']),
      length: serializer.fromJson<int>(json['length']),
      contentType: serializer.fromJson<String>(json['contentType']),
      digest: serializer.fromJson<String>(json['digest']),
      encoding: serializer.fromJson<String?>(json['encoding']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'fkdocument': serializer.toJson<int>(fkdocument),
      'ordering': serializer.toJson<int>(ordering),
      'revpos': serializer.toJson<int>(revpos),
      'name': serializer.toJson<String>(name),
      'length': serializer.toJson<int>(length),
      'contentType': serializer.toJson<String>(contentType),
      'digest': serializer.toJson<String>(digest),
      'encoding': serializer.toJson<String?>(encoding),
    };
  }

  LocalAttachment copyWith({
    int? id,
    int? fkdocument,
    int? ordering,
    int? revpos,
    String? name,
    int? length,
    String? contentType,
    String? digest,
    Value<String?> encoding = const Value.absent(),
  }) => LocalAttachment(
    id: id ?? this.id,
    fkdocument: fkdocument ?? this.fkdocument,
    ordering: ordering ?? this.ordering,
    revpos: revpos ?? this.revpos,
    name: name ?? this.name,
    length: length ?? this.length,
    contentType: contentType ?? this.contentType,
    digest: digest ?? this.digest,
    encoding: encoding.present ? encoding.value : this.encoding,
  );
  LocalAttachment copyWithCompanion(LocalAttachmentsCompanion data) {
    return LocalAttachment(
      id: data.id.present ? data.id.value : this.id,
      fkdocument: data.fkdocument.present
          ? data.fkdocument.value
          : this.fkdocument,
      ordering: data.ordering.present ? data.ordering.value : this.ordering,
      revpos: data.revpos.present ? data.revpos.value : this.revpos,
      name: data.name.present ? data.name.value : this.name,
      length: data.length.present ? data.length.value : this.length,
      contentType: data.contentType.present
          ? data.contentType.value
          : this.contentType,
      digest: data.digest.present ? data.digest.value : this.digest,
      encoding: data.encoding.present ? data.encoding.value : this.encoding,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalAttachment(')
          ..write('id: $id, ')
          ..write('fkdocument: $fkdocument, ')
          ..write('ordering: $ordering, ')
          ..write('revpos: $revpos, ')
          ..write('name: $name, ')
          ..write('length: $length, ')
          ..write('contentType: $contentType, ')
          ..write('digest: $digest, ')
          ..write('encoding: $encoding')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    fkdocument,
    ordering,
    revpos,
    name,
    length,
    contentType,
    digest,
    encoding,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalAttachment &&
          other.id == this.id &&
          other.fkdocument == this.fkdocument &&
          other.ordering == this.ordering &&
          other.revpos == this.revpos &&
          other.name == this.name &&
          other.length == this.length &&
          other.contentType == this.contentType &&
          other.digest == this.digest &&
          other.encoding == this.encoding);
}

class LocalAttachmentsCompanion extends UpdateCompanion<LocalAttachment> {
  final Value<int> id;
  final Value<int> fkdocument;
  final Value<int> ordering;
  final Value<int> revpos;
  final Value<String> name;
  final Value<int> length;
  final Value<String> contentType;
  final Value<String> digest;
  final Value<String?> encoding;
  const LocalAttachmentsCompanion({
    this.id = const Value.absent(),
    this.fkdocument = const Value.absent(),
    this.ordering = const Value.absent(),
    this.revpos = const Value.absent(),
    this.name = const Value.absent(),
    this.length = const Value.absent(),
    this.contentType = const Value.absent(),
    this.digest = const Value.absent(),
    this.encoding = const Value.absent(),
  });
  LocalAttachmentsCompanion.insert({
    this.id = const Value.absent(),
    required int fkdocument,
    required int ordering,
    required int revpos,
    required String name,
    required int length,
    required String contentType,
    required String digest,
    this.encoding = const Value.absent(),
  }) : fkdocument = Value(fkdocument),
       ordering = Value(ordering),
       revpos = Value(revpos),
       name = Value(name),
       length = Value(length),
       contentType = Value(contentType),
       digest = Value(digest);
  static Insertable<LocalAttachment> custom({
    Expression<int>? id,
    Expression<int>? fkdocument,
    Expression<int>? ordering,
    Expression<int>? revpos,
    Expression<String>? name,
    Expression<int>? length,
    Expression<String>? contentType,
    Expression<String>? digest,
    Expression<String>? encoding,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fkdocument != null) 'fkdocument': fkdocument,
      if (ordering != null) 'ordering': ordering,
      if (revpos != null) 'revpos': revpos,
      if (name != null) 'name': name,
      if (length != null) 'length': length,
      if (contentType != null) 'content_type': contentType,
      if (digest != null) 'digest': digest,
      if (encoding != null) 'encoding': encoding,
    });
  }

  LocalAttachmentsCompanion copyWith({
    Value<int>? id,
    Value<int>? fkdocument,
    Value<int>? ordering,
    Value<int>? revpos,
    Value<String>? name,
    Value<int>? length,
    Value<String>? contentType,
    Value<String>? digest,
    Value<String?>? encoding,
  }) {
    return LocalAttachmentsCompanion(
      id: id ?? this.id,
      fkdocument: fkdocument ?? this.fkdocument,
      ordering: ordering ?? this.ordering,
      revpos: revpos ?? this.revpos,
      name: name ?? this.name,
      length: length ?? this.length,
      contentType: contentType ?? this.contentType,
      digest: digest ?? this.digest,
      encoding: encoding ?? this.encoding,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (fkdocument.present) {
      map['fkdocument'] = Variable<int>(fkdocument.value);
    }
    if (ordering.present) {
      map['ordering'] = Variable<int>(ordering.value);
    }
    if (revpos.present) {
      map['revpos'] = Variable<int>(revpos.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (length.present) {
      map['length'] = Variable<int>(length.value);
    }
    if (contentType.present) {
      map['content_type'] = Variable<String>(contentType.value);
    }
    if (digest.present) {
      map['digest'] = Variable<String>(digest.value);
    }
    if (encoding.present) {
      map['encoding'] = Variable<String>(encoding.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalAttachmentsCompanion(')
          ..write('id: $id, ')
          ..write('fkdocument: $fkdocument, ')
          ..write('ordering: $ordering, ')
          ..write('revpos: $revpos, ')
          ..write('name: $name, ')
          ..write('length: $length, ')
          ..write('contentType: $contentType, ')
          ..write('digest: $digest, ')
          ..write('encoding: $encoding')
          ..write(')'))
        .toString();
  }
}

class $LocalViewsTable extends LocalViews
    with TableInfo<$LocalViewsTable, LocalView> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalViewsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _databaseMeta = const VerificationMeta(
    'database',
  );
  @override
  late final GeneratedColumn<int> database = GeneratedColumn<int>(
    'database',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_databases (id)',
    ),
  );
  static const VerificationMeta _viewPathShortMeta = const VerificationMeta(
    'viewPathShort',
  );
  @override
  late final GeneratedColumn<String> viewPathShort = GeneratedColumn<String>(
    'view_path_short',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updateSeqMeta = const VerificationMeta(
    'updateSeq',
  );
  @override
  late final GeneratedColumn<int> updateSeq = GeneratedColumn<int>(
    'update_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _mapFunctionMeta = const VerificationMeta(
    'mapFunction',
  );
  @override
  late final GeneratedColumn<String> mapFunction = GeneratedColumn<String>(
    'map_function',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reduceFunctionMeta = const VerificationMeta(
    'reduceFunction',
  );
  @override
  late final GeneratedColumn<String> reduceFunction = GeneratedColumn<String>(
    'reduce_function',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    database,
    viewPathShort,
    updateSeq,
    mapFunction,
    reduceFunction,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_views';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalView> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('database')) {
      context.handle(
        _databaseMeta,
        database.isAcceptableOrUnknown(data['database']!, _databaseMeta),
      );
    } else if (isInserting) {
      context.missing(_databaseMeta);
    }
    if (data.containsKey('view_path_short')) {
      context.handle(
        _viewPathShortMeta,
        viewPathShort.isAcceptableOrUnknown(
          data['view_path_short']!,
          _viewPathShortMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_viewPathShortMeta);
    }
    if (data.containsKey('update_seq')) {
      context.handle(
        _updateSeqMeta,
        updateSeq.isAcceptableOrUnknown(data['update_seq']!, _updateSeqMeta),
      );
    }
    if (data.containsKey('map_function')) {
      context.handle(
        _mapFunctionMeta,
        mapFunction.isAcceptableOrUnknown(
          data['map_function']!,
          _mapFunctionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_mapFunctionMeta);
    }
    if (data.containsKey('reduce_function')) {
      context.handle(
        _reduceFunctionMeta,
        reduceFunction.isAcceptableOrUnknown(
          data['reduce_function']!,
          _reduceFunctionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalView map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalView(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      database: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}database'],
      )!,
      viewPathShort: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}view_path_short'],
      )!,
      updateSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}update_seq'],
      )!,
      mapFunction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}map_function'],
      )!,
      reduceFunction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reduce_function'],
      ),
    );
  }

  @override
  $LocalViewsTable createAlias(String alias) {
    return $LocalViewsTable(attachedDatabase, alias);
  }
}

class LocalView extends DataClass implements Insertable<LocalView> {
  final int id;
  final int database;

  /// Shortname of the view, e.g. _all_docs or design_doc_name/view_name
  final String viewPathShort;

  /// update sequence number, when the view was last updated
  final int updateSeq;
  final String mapFunction;
  final String? reduceFunction;
  const LocalView({
    required this.id,
    required this.database,
    required this.viewPathShort,
    required this.updateSeq,
    required this.mapFunction,
    this.reduceFunction,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['database'] = Variable<int>(database);
    map['view_path_short'] = Variable<String>(viewPathShort);
    map['update_seq'] = Variable<int>(updateSeq);
    map['map_function'] = Variable<String>(mapFunction);
    if (!nullToAbsent || reduceFunction != null) {
      map['reduce_function'] = Variable<String>(reduceFunction);
    }
    return map;
  }

  LocalViewsCompanion toCompanion(bool nullToAbsent) {
    return LocalViewsCompanion(
      id: Value(id),
      database: Value(database),
      viewPathShort: Value(viewPathShort),
      updateSeq: Value(updateSeq),
      mapFunction: Value(mapFunction),
      reduceFunction: reduceFunction == null && nullToAbsent
          ? const Value.absent()
          : Value(reduceFunction),
    );
  }

  factory LocalView.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalView(
      id: serializer.fromJson<int>(json['id']),
      database: serializer.fromJson<int>(json['database']),
      viewPathShort: serializer.fromJson<String>(json['viewPathShort']),
      updateSeq: serializer.fromJson<int>(json['updateSeq']),
      mapFunction: serializer.fromJson<String>(json['mapFunction']),
      reduceFunction: serializer.fromJson<String?>(json['reduceFunction']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'database': serializer.toJson<int>(database),
      'viewPathShort': serializer.toJson<String>(viewPathShort),
      'updateSeq': serializer.toJson<int>(updateSeq),
      'mapFunction': serializer.toJson<String>(mapFunction),
      'reduceFunction': serializer.toJson<String?>(reduceFunction),
    };
  }

  LocalView copyWith({
    int? id,
    int? database,
    String? viewPathShort,
    int? updateSeq,
    String? mapFunction,
    Value<String?> reduceFunction = const Value.absent(),
  }) => LocalView(
    id: id ?? this.id,
    database: database ?? this.database,
    viewPathShort: viewPathShort ?? this.viewPathShort,
    updateSeq: updateSeq ?? this.updateSeq,
    mapFunction: mapFunction ?? this.mapFunction,
    reduceFunction: reduceFunction.present
        ? reduceFunction.value
        : this.reduceFunction,
  );
  LocalView copyWithCompanion(LocalViewsCompanion data) {
    return LocalView(
      id: data.id.present ? data.id.value : this.id,
      database: data.database.present ? data.database.value : this.database,
      viewPathShort: data.viewPathShort.present
          ? data.viewPathShort.value
          : this.viewPathShort,
      updateSeq: data.updateSeq.present ? data.updateSeq.value : this.updateSeq,
      mapFunction: data.mapFunction.present
          ? data.mapFunction.value
          : this.mapFunction,
      reduceFunction: data.reduceFunction.present
          ? data.reduceFunction.value
          : this.reduceFunction,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalView(')
          ..write('id: $id, ')
          ..write('database: $database, ')
          ..write('viewPathShort: $viewPathShort, ')
          ..write('updateSeq: $updateSeq, ')
          ..write('mapFunction: $mapFunction, ')
          ..write('reduceFunction: $reduceFunction')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    database,
    viewPathShort,
    updateSeq,
    mapFunction,
    reduceFunction,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalView &&
          other.id == this.id &&
          other.database == this.database &&
          other.viewPathShort == this.viewPathShort &&
          other.updateSeq == this.updateSeq &&
          other.mapFunction == this.mapFunction &&
          other.reduceFunction == this.reduceFunction);
}

class LocalViewsCompanion extends UpdateCompanion<LocalView> {
  final Value<int> id;
  final Value<int> database;
  final Value<String> viewPathShort;
  final Value<int> updateSeq;
  final Value<String> mapFunction;
  final Value<String?> reduceFunction;
  const LocalViewsCompanion({
    this.id = const Value.absent(),
    this.database = const Value.absent(),
    this.viewPathShort = const Value.absent(),
    this.updateSeq = const Value.absent(),
    this.mapFunction = const Value.absent(),
    this.reduceFunction = const Value.absent(),
  });
  LocalViewsCompanion.insert({
    this.id = const Value.absent(),
    required int database,
    required String viewPathShort,
    this.updateSeq = const Value.absent(),
    required String mapFunction,
    this.reduceFunction = const Value.absent(),
  }) : database = Value(database),
       viewPathShort = Value(viewPathShort),
       mapFunction = Value(mapFunction);
  static Insertable<LocalView> custom({
    Expression<int>? id,
    Expression<int>? database,
    Expression<String>? viewPathShort,
    Expression<int>? updateSeq,
    Expression<String>? mapFunction,
    Expression<String>? reduceFunction,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (database != null) 'database': database,
      if (viewPathShort != null) 'view_path_short': viewPathShort,
      if (updateSeq != null) 'update_seq': updateSeq,
      if (mapFunction != null) 'map_function': mapFunction,
      if (reduceFunction != null) 'reduce_function': reduceFunction,
    });
  }

  LocalViewsCompanion copyWith({
    Value<int>? id,
    Value<int>? database,
    Value<String>? viewPathShort,
    Value<int>? updateSeq,
    Value<String>? mapFunction,
    Value<String?>? reduceFunction,
  }) {
    return LocalViewsCompanion(
      id: id ?? this.id,
      database: database ?? this.database,
      viewPathShort: viewPathShort ?? this.viewPathShort,
      updateSeq: updateSeq ?? this.updateSeq,
      mapFunction: mapFunction ?? this.mapFunction,
      reduceFunction: reduceFunction ?? this.reduceFunction,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (database.present) {
      map['database'] = Variable<int>(database.value);
    }
    if (viewPathShort.present) {
      map['view_path_short'] = Variable<String>(viewPathShort.value);
    }
    if (updateSeq.present) {
      map['update_seq'] = Variable<int>(updateSeq.value);
    }
    if (mapFunction.present) {
      map['map_function'] = Variable<String>(mapFunction.value);
    }
    if (reduceFunction.present) {
      map['reduce_function'] = Variable<String>(reduceFunction.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalViewsCompanion(')
          ..write('id: $id, ')
          ..write('database: $database, ')
          ..write('viewPathShort: $viewPathShort, ')
          ..write('updateSeq: $updateSeq, ')
          ..write('mapFunction: $mapFunction, ')
          ..write('reduceFunction: $reduceFunction')
          ..write(')'))
        .toString();
  }
}

class $LocalViewEntriesTable extends LocalViewEntries
    with TableInfo<$LocalViewEntriesTable, LocalViewEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalViewEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _fkviewMeta = const VerificationMeta('fkview');
  @override
  late final GeneratedColumn<int> fkview = GeneratedColumn<int>(
    'fkview',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_views (id)',
    ),
  );
  static const VerificationMeta _docidMeta = const VerificationMeta('docid');
  @override
  late final GeneratedColumn<String> docid = GeneratedColumn<String>(
    'docid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, fkview, docid, key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_view_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalViewEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('fkview')) {
      context.handle(
        _fkviewMeta,
        fkview.isAcceptableOrUnknown(data['fkview']!, _fkviewMeta),
      );
    } else if (isInserting) {
      context.missing(_fkviewMeta);
    }
    if (data.containsKey('docid')) {
      context.handle(
        _docidMeta,
        docid.isAcceptableOrUnknown(data['docid']!, _docidMeta),
      );
    } else if (isInserting) {
      context.missing(_docidMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalViewEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalViewEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      fkview: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fkview'],
      )!,
      docid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}docid'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $LocalViewEntriesTable createAlias(String alias) {
    return $LocalViewEntriesTable(attachedDatabase, alias);
  }
}

class LocalViewEntry extends DataClass implements Insertable<LocalViewEntry> {
  final int id;
  final int fkview;
  final String docid;
  final String key;
  final String value;
  const LocalViewEntry({
    required this.id,
    required this.fkview,
    required this.docid,
    required this.key,
    required this.value,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['fkview'] = Variable<int>(fkview);
    map['docid'] = Variable<String>(docid);
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  LocalViewEntriesCompanion toCompanion(bool nullToAbsent) {
    return LocalViewEntriesCompanion(
      id: Value(id),
      fkview: Value(fkview),
      docid: Value(docid),
      key: Value(key),
      value: Value(value),
    );
  }

  factory LocalViewEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalViewEntry(
      id: serializer.fromJson<int>(json['id']),
      fkview: serializer.fromJson<int>(json['fkview']),
      docid: serializer.fromJson<String>(json['docid']),
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'fkview': serializer.toJson<int>(fkview),
      'docid': serializer.toJson<String>(docid),
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  LocalViewEntry copyWith({
    int? id,
    int? fkview,
    String? docid,
    String? key,
    String? value,
  }) => LocalViewEntry(
    id: id ?? this.id,
    fkview: fkview ?? this.fkview,
    docid: docid ?? this.docid,
    key: key ?? this.key,
    value: value ?? this.value,
  );
  LocalViewEntry copyWithCompanion(LocalViewEntriesCompanion data) {
    return LocalViewEntry(
      id: data.id.present ? data.id.value : this.id,
      fkview: data.fkview.present ? data.fkview.value : this.fkview,
      docid: data.docid.present ? data.docid.value : this.docid,
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalViewEntry(')
          ..write('id: $id, ')
          ..write('fkview: $fkview, ')
          ..write('docid: $docid, ')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, fkview, docid, key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalViewEntry &&
          other.id == this.id &&
          other.fkview == this.fkview &&
          other.docid == this.docid &&
          other.key == this.key &&
          other.value == this.value);
}

class LocalViewEntriesCompanion extends UpdateCompanion<LocalViewEntry> {
  final Value<int> id;
  final Value<int> fkview;
  final Value<String> docid;
  final Value<String> key;
  final Value<String> value;
  const LocalViewEntriesCompanion({
    this.id = const Value.absent(),
    this.fkview = const Value.absent(),
    this.docid = const Value.absent(),
    this.key = const Value.absent(),
    this.value = const Value.absent(),
  });
  LocalViewEntriesCompanion.insert({
    this.id = const Value.absent(),
    required int fkview,
    required String docid,
    required String key,
    required String value,
  }) : fkview = Value(fkview),
       docid = Value(docid),
       key = Value(key),
       value = Value(value);
  static Insertable<LocalViewEntry> custom({
    Expression<int>? id,
    Expression<int>? fkview,
    Expression<String>? docid,
    Expression<String>? key,
    Expression<String>? value,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fkview != null) 'fkview': fkview,
      if (docid != null) 'docid': docid,
      if (key != null) 'key': key,
      if (value != null) 'value': value,
    });
  }

  LocalViewEntriesCompanion copyWith({
    Value<int>? id,
    Value<int>? fkview,
    Value<String>? docid,
    Value<String>? key,
    Value<String>? value,
  }) {
    return LocalViewEntriesCompanion(
      id: id ?? this.id,
      fkview: fkview ?? this.fkview,
      docid: docid ?? this.docid,
      key: key ?? this.key,
      value: value ?? this.value,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (fkview.present) {
      map['fkview'] = Variable<int>(fkview.value);
    }
    if (docid.present) {
      map['docid'] = Variable<String>(docid.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalViewEntriesCompanion(')
          ..write('id: $id, ')
          ..write('fkview: $fkview, ')
          ..write('docid: $docid, ')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $LocalDatabasesTable localDatabases = $LocalDatabasesTable(this);
  late final $LocalDocumentsTable localDocuments = $LocalDocumentsTable(this);
  late final $DocumentBlobsTable documentBlobs = $DocumentBlobsTable(this);
  late final $RevisionHistoriesTable revisionHistories =
      $RevisionHistoriesTable(this);
  late final $LocalAttachmentsTable localAttachments = $LocalAttachmentsTable(
    this,
  );
  late final $LocalViewsTable localViews = $LocalViewsTable(this);
  late final $LocalViewEntriesTable localViewEntries = $LocalViewEntriesTable(
    this,
  );
  late final Index localDocumentsDocid = Index(
    'local_documents_docid',
    'CREATE INDEX local_documents_docid ON local_documents (docid)',
  );
  late final Index localDocumentsVersion = Index(
    'local_documents_version',
    'CREATE INDEX local_documents_version ON local_documents (version)',
  );
  late final Index localDocumentsSeq = Index(
    'local_documents_seq',
    'CREATE INDEX local_documents_seq ON local_documents (seq)',
  );
  late final Index localDocumentsFkdatabaseDocid = Index(
    'local_documents_fkdatabase_docid',
    'CREATE UNIQUE INDEX local_documents_fkdatabase_docid ON local_documents (fkdatabase, docid)',
  );
  late final Index revisionHistoriesRevIndex = Index(
    'revision_histories_rev_index',
    'CREATE INDEX revision_histories_rev_index ON revision_histories (rev)',
  );
  late final Index revisionHistoriesVersionIndex = Index(
    'revision_histories_version_index',
    'CREATE INDEX revision_histories_version_index ON revision_histories (version)',
  );
  late final Index revisionHistoriesSeq = Index(
    'revision_histories_seq',
    'CREATE INDEX revision_histories_seq ON revision_histories (seq)',
  );
  late final Index localAttachmentsNameIndex = Index(
    'local_attachments_name_index',
    'CREATE INDEX local_attachments_name_index ON local_attachments (name)',
  );
  late final Index localAttachmentsRevposIndex = Index(
    'local_attachments_revpos_index',
    'CREATE INDEX local_attachments_revpos_index ON local_attachments (revpos)',
  );
  late final Index localAttachmentsFkdocumentIndex = Index(
    'local_attachments_fkdocument_index',
    'CREATE INDEX local_attachments_fkdocument_index ON local_attachments (fkdocument)',
  );
  late final Index localViewViewPathShortIndex = Index(
    'local_view_view_path_short_index',
    'CREATE INDEX local_view_view_path_short_index ON local_views (view_path_short)',
  );
  late final Index localViewsUnique = Index(
    'local_views_unique',
    'CREATE UNIQUE INDEX local_views_unique ON local_views ("database", view_path_short)',
  );
  late final Index localViewEntriesDocidIndex = Index(
    'local_view_entries_docid_index',
    'CREATE INDEX local_view_entries_docid_index ON local_view_entries (docid)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localDatabases,
    localDocuments,
    documentBlobs,
    revisionHistories,
    localAttachments,
    localViews,
    localViewEntries,
    localDocumentsDocid,
    localDocumentsVersion,
    localDocumentsSeq,
    localDocumentsFkdatabaseDocid,
    revisionHistoriesRevIndex,
    revisionHistoriesVersionIndex,
    revisionHistoriesSeq,
    localAttachmentsNameIndex,
    localAttachmentsRevposIndex,
    localAttachmentsFkdocumentIndex,
    localViewViewPathShortIndex,
    localViewsUnique,
    localViewEntriesDocidIndex,
  ];
}

typedef $$LocalDatabasesTableCreateCompanionBuilder =
    LocalDatabasesCompanion Function({
      Value<int> id,
      required String name,
      Value<int> updateSeq,
    });
typedef $$LocalDatabasesTableUpdateCompanionBuilder =
    LocalDatabasesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<int> updateSeq,
    });

final class $$LocalDatabasesTableReferences
    extends BaseReferences<_$AppDatabase, $LocalDatabasesTable, LocalDatabase> {
  $$LocalDatabasesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$LocalDocumentsTable, List<LocalDocument>>
  _localDocumentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.localDocuments,
    aliasName: $_aliasNameGenerator(
      db.localDatabases.id,
      db.localDocuments.fkdatabase,
    ),
  );

  $$LocalDocumentsTableProcessedTableManager get localDocumentsRefs {
    final manager = $$LocalDocumentsTableTableManager(
      $_db,
      $_db.localDocuments,
    ).filter((f) => f.fkdatabase.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_localDocumentsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$LocalViewsTable, List<LocalView>>
  _localViewsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.localViews,
    aliasName: $_aliasNameGenerator(
      db.localDatabases.id,
      db.localViews.database,
    ),
  );

  $$LocalViewsTableProcessedTableManager get localViewsRefs {
    final manager = $$LocalViewsTableTableManager(
      $_db,
      $_db.localViews,
    ).filter((f) => f.database.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_localViewsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$LocalDatabasesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalDatabasesTable> {
  $$LocalDatabasesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updateSeq => $composableBuilder(
    column: $table.updateSeq,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> localDocumentsRefs(
    Expression<bool> Function($$LocalDocumentsTableFilterComposer f) f,
  ) {
    final $$LocalDocumentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.localDocuments,
      getReferencedColumn: (t) => t.fkdatabase,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalDocumentsTableFilterComposer(
            $db: $db,
            $table: $db.localDocuments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> localViewsRefs(
    Expression<bool> Function($$LocalViewsTableFilterComposer f) f,
  ) {
    final $$LocalViewsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.localViews,
      getReferencedColumn: (t) => t.database,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalViewsTableFilterComposer(
            $db: $db,
            $table: $db.localViews,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LocalDatabasesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalDatabasesTable> {
  $$LocalDatabasesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updateSeq => $composableBuilder(
    column: $table.updateSeq,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalDatabasesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalDatabasesTable> {
  $$LocalDatabasesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get updateSeq =>
      $composableBuilder(column: $table.updateSeq, builder: (column) => column);

  Expression<T> localDocumentsRefs<T extends Object>(
    Expression<T> Function($$LocalDocumentsTableAnnotationComposer a) f,
  ) {
    final $$LocalDocumentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.localDocuments,
      getReferencedColumn: (t) => t.fkdatabase,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalDocumentsTableAnnotationComposer(
            $db: $db,
            $table: $db.localDocuments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> localViewsRefs<T extends Object>(
    Expression<T> Function($$LocalViewsTableAnnotationComposer a) f,
  ) {
    final $$LocalViewsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.localViews,
      getReferencedColumn: (t) => t.database,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalViewsTableAnnotationComposer(
            $db: $db,
            $table: $db.localViews,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LocalDatabasesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalDatabasesTable,
          LocalDatabase,
          $$LocalDatabasesTableFilterComposer,
          $$LocalDatabasesTableOrderingComposer,
          $$LocalDatabasesTableAnnotationComposer,
          $$LocalDatabasesTableCreateCompanionBuilder,
          $$LocalDatabasesTableUpdateCompanionBuilder,
          (LocalDatabase, $$LocalDatabasesTableReferences),
          LocalDatabase,
          PrefetchHooks Function({bool localDocumentsRefs, bool localViewsRefs})
        > {
  $$LocalDatabasesTableTableManager(
    _$AppDatabase db,
    $LocalDatabasesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalDatabasesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalDatabasesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalDatabasesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> updateSeq = const Value.absent(),
              }) => LocalDatabasesCompanion(
                id: id,
                name: name,
                updateSeq: updateSeq,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<int> updateSeq = const Value.absent(),
              }) => LocalDatabasesCompanion.insert(
                id: id,
                name: name,
                updateSeq: updateSeq,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LocalDatabasesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({localDocumentsRefs = false, localViewsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (localDocumentsRefs) db.localDocuments,
                    if (localViewsRefs) db.localViews,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (localDocumentsRefs)
                        await $_getPrefetchedData<
                          LocalDatabase,
                          $LocalDatabasesTable,
                          LocalDocument
                        >(
                          currentTable: table,
                          referencedTable: $$LocalDatabasesTableReferences
                              ._localDocumentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalDatabasesTableReferences(
                                db,
                                table,
                                p0,
                              ).localDocumentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.fkdatabase == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (localViewsRefs)
                        await $_getPrefetchedData<
                          LocalDatabase,
                          $LocalDatabasesTable,
                          LocalView
                        >(
                          currentTable: table,
                          referencedTable: $$LocalDatabasesTableReferences
                              ._localViewsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalDatabasesTableReferences(
                                db,
                                table,
                                p0,
                              ).localViewsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.database == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$LocalDatabasesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalDatabasesTable,
      LocalDatabase,
      $$LocalDatabasesTableFilterComposer,
      $$LocalDatabasesTableOrderingComposer,
      $$LocalDatabasesTableAnnotationComposer,
      $$LocalDatabasesTableCreateCompanionBuilder,
      $$LocalDatabasesTableUpdateCompanionBuilder,
      (LocalDatabase, $$LocalDatabasesTableReferences),
      LocalDatabase,
      PrefetchHooks Function({bool localDocumentsRefs, bool localViewsRefs})
    >;
typedef $$LocalDocumentsTableCreateCompanionBuilder =
    LocalDocumentsCompanion Function({
      Value<int> id,
      required int fkdatabase,
      required String docid,
      required String rev,
      required int version,
      Value<bool?> deleted,
      required int seq,
    });
typedef $$LocalDocumentsTableUpdateCompanionBuilder =
    LocalDocumentsCompanion Function({
      Value<int> id,
      Value<int> fkdatabase,
      Value<String> docid,
      Value<String> rev,
      Value<int> version,
      Value<bool?> deleted,
      Value<int> seq,
    });

final class $$LocalDocumentsTableReferences
    extends BaseReferences<_$AppDatabase, $LocalDocumentsTable, LocalDocument> {
  $$LocalDocumentsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalDatabasesTable _fkdatabaseTable(_$AppDatabase db) =>
      db.localDatabases.createAlias(
        $_aliasNameGenerator(
          db.localDocuments.fkdatabase,
          db.localDatabases.id,
        ),
      );

  $$LocalDatabasesTableProcessedTableManager get fkdatabase {
    final $_column = $_itemColumn<int>('fkdatabase')!;

    final manager = $$LocalDatabasesTableTableManager(
      $_db,
      $_db.localDatabases,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_fkdatabaseTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$DocumentBlobsTable, List<DocumentBlob>>
  _documentBlobsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.documentBlobs,
    aliasName: $_aliasNameGenerator(
      db.localDocuments.id,
      db.documentBlobs.documentId,
    ),
  );

  $$DocumentBlobsTableProcessedTableManager get documentBlobsRefs {
    final manager = $$DocumentBlobsTableTableManager(
      $_db,
      $_db.documentBlobs,
    ).filter((f) => f.documentId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_documentBlobsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$RevisionHistoriesTable, List<RevisionHistory>>
  _revisionHistoriesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.revisionHistories,
        aliasName: $_aliasNameGenerator(
          db.localDocuments.id,
          db.revisionHistories.fkdocument,
        ),
      );

  $$RevisionHistoriesTableProcessedTableManager get revisionHistoriesRefs {
    final manager = $$RevisionHistoriesTableTableManager(
      $_db,
      $_db.revisionHistories,
    ).filter((f) => f.fkdocument.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _revisionHistoriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$LocalAttachmentsTable, List<LocalAttachment>>
  _localAttachmentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.localAttachments,
    aliasName: $_aliasNameGenerator(
      db.localDocuments.id,
      db.localAttachments.fkdocument,
    ),
  );

  $$LocalAttachmentsTableProcessedTableManager get localAttachmentsRefs {
    final manager = $$LocalAttachmentsTableTableManager(
      $_db,
      $_db.localAttachments,
    ).filter((f) => f.fkdocument.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _localAttachmentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$LocalDocumentsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalDocumentsTable> {
  $$LocalDocumentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get docid => $composableBuilder(
    column: $table.docid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rev => $composableBuilder(
    column: $table.rev,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalDatabasesTableFilterComposer get fkdatabase {
    final $$LocalDatabasesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fkdatabase,
      referencedTable: $db.localDatabases,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalDatabasesTableFilterComposer(
            $db: $db,
            $table: $db.localDatabases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> documentBlobsRefs(
    Expression<bool> Function($$DocumentBlobsTableFilterComposer f) f,
  ) {
    final $$DocumentBlobsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.documentBlobs,
      getReferencedColumn: (t) => t.documentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentBlobsTableFilterComposer(
            $db: $db,
            $table: $db.documentBlobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> revisionHistoriesRefs(
    Expression<bool> Function($$RevisionHistoriesTableFilterComposer f) f,
  ) {
    final $$RevisionHistoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.revisionHistories,
      getReferencedColumn: (t) => t.fkdocument,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RevisionHistoriesTableFilterComposer(
            $db: $db,
            $table: $db.revisionHistories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> localAttachmentsRefs(
    Expression<bool> Function($$LocalAttachmentsTableFilterComposer f) f,
  ) {
    final $$LocalAttachmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.localAttachments,
      getReferencedColumn: (t) => t.fkdocument,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalAttachmentsTableFilterComposer(
            $db: $db,
            $table: $db.localAttachments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LocalDocumentsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalDocumentsTable> {
  $$LocalDocumentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get docid => $composableBuilder(
    column: $table.docid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rev => $composableBuilder(
    column: $table.rev,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalDatabasesTableOrderingComposer get fkdatabase {
    final $$LocalDatabasesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fkdatabase,
      referencedTable: $db.localDatabases,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalDatabasesTableOrderingComposer(
            $db: $db,
            $table: $db.localDatabases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LocalDocumentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalDocumentsTable> {
  $$LocalDocumentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get docid =>
      $composableBuilder(column: $table.docid, builder: (column) => column);

  GeneratedColumn<String> get rev =>
      $composableBuilder(column: $table.rev, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  $$LocalDatabasesTableAnnotationComposer get fkdatabase {
    final $$LocalDatabasesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fkdatabase,
      referencedTable: $db.localDatabases,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalDatabasesTableAnnotationComposer(
            $db: $db,
            $table: $db.localDatabases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> documentBlobsRefs<T extends Object>(
    Expression<T> Function($$DocumentBlobsTableAnnotationComposer a) f,
  ) {
    final $$DocumentBlobsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.documentBlobs,
      getReferencedColumn: (t) => t.documentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentBlobsTableAnnotationComposer(
            $db: $db,
            $table: $db.documentBlobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> revisionHistoriesRefs<T extends Object>(
    Expression<T> Function($$RevisionHistoriesTableAnnotationComposer a) f,
  ) {
    final $$RevisionHistoriesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.revisionHistories,
          getReferencedColumn: (t) => t.fkdocument,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RevisionHistoriesTableAnnotationComposer(
                $db: $db,
                $table: $db.revisionHistories,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> localAttachmentsRefs<T extends Object>(
    Expression<T> Function($$LocalAttachmentsTableAnnotationComposer a) f,
  ) {
    final $$LocalAttachmentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.localAttachments,
      getReferencedColumn: (t) => t.fkdocument,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalAttachmentsTableAnnotationComposer(
            $db: $db,
            $table: $db.localAttachments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LocalDocumentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalDocumentsTable,
          LocalDocument,
          $$LocalDocumentsTableFilterComposer,
          $$LocalDocumentsTableOrderingComposer,
          $$LocalDocumentsTableAnnotationComposer,
          $$LocalDocumentsTableCreateCompanionBuilder,
          $$LocalDocumentsTableUpdateCompanionBuilder,
          (LocalDocument, $$LocalDocumentsTableReferences),
          LocalDocument,
          PrefetchHooks Function({
            bool fkdatabase,
            bool documentBlobsRefs,
            bool revisionHistoriesRefs,
            bool localAttachmentsRefs,
          })
        > {
  $$LocalDocumentsTableTableManager(
    _$AppDatabase db,
    $LocalDocumentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalDocumentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalDocumentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalDocumentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> fkdatabase = const Value.absent(),
                Value<String> docid = const Value.absent(),
                Value<String> rev = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<bool?> deleted = const Value.absent(),
                Value<int> seq = const Value.absent(),
              }) => LocalDocumentsCompanion(
                id: id,
                fkdatabase: fkdatabase,
                docid: docid,
                rev: rev,
                version: version,
                deleted: deleted,
                seq: seq,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int fkdatabase,
                required String docid,
                required String rev,
                required int version,
                Value<bool?> deleted = const Value.absent(),
                required int seq,
              }) => LocalDocumentsCompanion.insert(
                id: id,
                fkdatabase: fkdatabase,
                docid: docid,
                rev: rev,
                version: version,
                deleted: deleted,
                seq: seq,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LocalDocumentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                fkdatabase = false,
                documentBlobsRefs = false,
                revisionHistoriesRefs = false,
                localAttachmentsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (documentBlobsRefs) db.documentBlobs,
                    if (revisionHistoriesRefs) db.revisionHistories,
                    if (localAttachmentsRefs) db.localAttachments,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (fkdatabase) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.fkdatabase,
                                    referencedTable:
                                        $$LocalDocumentsTableReferences
                                            ._fkdatabaseTable(db),
                                    referencedColumn:
                                        $$LocalDocumentsTableReferences
                                            ._fkdatabaseTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (documentBlobsRefs)
                        await $_getPrefetchedData<
                          LocalDocument,
                          $LocalDocumentsTable,
                          DocumentBlob
                        >(
                          currentTable: table,
                          referencedTable: $$LocalDocumentsTableReferences
                              ._documentBlobsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalDocumentsTableReferences(
                                db,
                                table,
                                p0,
                              ).documentBlobsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.documentId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (revisionHistoriesRefs)
                        await $_getPrefetchedData<
                          LocalDocument,
                          $LocalDocumentsTable,
                          RevisionHistory
                        >(
                          currentTable: table,
                          referencedTable: $$LocalDocumentsTableReferences
                              ._revisionHistoriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalDocumentsTableReferences(
                                db,
                                table,
                                p0,
                              ).revisionHistoriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.fkdocument == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (localAttachmentsRefs)
                        await $_getPrefetchedData<
                          LocalDocument,
                          $LocalDocumentsTable,
                          LocalAttachment
                        >(
                          currentTable: table,
                          referencedTable: $$LocalDocumentsTableReferences
                              ._localAttachmentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalDocumentsTableReferences(
                                db,
                                table,
                                p0,
                              ).localAttachmentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.fkdocument == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$LocalDocumentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalDocumentsTable,
      LocalDocument,
      $$LocalDocumentsTableFilterComposer,
      $$LocalDocumentsTableOrderingComposer,
      $$LocalDocumentsTableAnnotationComposer,
      $$LocalDocumentsTableCreateCompanionBuilder,
      $$LocalDocumentsTableUpdateCompanionBuilder,
      (LocalDocument, $$LocalDocumentsTableReferences),
      LocalDocument,
      PrefetchHooks Function({
        bool fkdatabase,
        bool documentBlobsRefs,
        bool revisionHistoriesRefs,
        bool localAttachmentsRefs,
      })
    >;
typedef $$DocumentBlobsTableCreateCompanionBuilder =
    DocumentBlobsCompanion Function({
      Value<int> documentId,
      required String data,
    });
typedef $$DocumentBlobsTableUpdateCompanionBuilder =
    DocumentBlobsCompanion Function({
      Value<int> documentId,
      Value<String> data,
    });

final class $$DocumentBlobsTableReferences
    extends BaseReferences<_$AppDatabase, $DocumentBlobsTable, DocumentBlob> {
  $$DocumentBlobsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalDocumentsTable _documentIdTable(_$AppDatabase db) =>
      db.localDocuments.createAlias(
        $_aliasNameGenerator(db.documentBlobs.documentId, db.localDocuments.id),
      );

  $$LocalDocumentsTableProcessedTableManager get documentId {
    final $_column = $_itemColumn<int>('document_id')!;

    final manager = $$LocalDocumentsTableTableManager(
      $_db,
      $_db.localDocuments,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_documentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DocumentBlobsTableFilterComposer
    extends Composer<_$AppDatabase, $DocumentBlobsTable> {
  $$DocumentBlobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalDocumentsTableFilterComposer get documentId {
    final $$LocalDocumentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.documentId,
      referencedTable: $db.localDocuments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalDocumentsTableFilterComposer(
            $db: $db,
            $table: $db.localDocuments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DocumentBlobsTableOrderingComposer
    extends Composer<_$AppDatabase, $DocumentBlobsTable> {
  $$DocumentBlobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalDocumentsTableOrderingComposer get documentId {
    final $$LocalDocumentsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.documentId,
      referencedTable: $db.localDocuments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalDocumentsTableOrderingComposer(
            $db: $db,
            $table: $db.localDocuments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DocumentBlobsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DocumentBlobsTable> {
  $$DocumentBlobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  $$LocalDocumentsTableAnnotationComposer get documentId {
    final $$LocalDocumentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.documentId,
      referencedTable: $db.localDocuments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalDocumentsTableAnnotationComposer(
            $db: $db,
            $table: $db.localDocuments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DocumentBlobsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DocumentBlobsTable,
          DocumentBlob,
          $$DocumentBlobsTableFilterComposer,
          $$DocumentBlobsTableOrderingComposer,
          $$DocumentBlobsTableAnnotationComposer,
          $$DocumentBlobsTableCreateCompanionBuilder,
          $$DocumentBlobsTableUpdateCompanionBuilder,
          (DocumentBlob, $$DocumentBlobsTableReferences),
          DocumentBlob,
          PrefetchHooks Function({bool documentId})
        > {
  $$DocumentBlobsTableTableManager(_$AppDatabase db, $DocumentBlobsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DocumentBlobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DocumentBlobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DocumentBlobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> documentId = const Value.absent(),
                Value<String> data = const Value.absent(),
              }) => DocumentBlobsCompanion(documentId: documentId, data: data),
          createCompanionCallback:
              ({
                Value<int> documentId = const Value.absent(),
                required String data,
              }) => DocumentBlobsCompanion.insert(
                documentId: documentId,
                data: data,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DocumentBlobsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({documentId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (documentId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.documentId,
                                referencedTable: $$DocumentBlobsTableReferences
                                    ._documentIdTable(db),
                                referencedColumn: $$DocumentBlobsTableReferences
                                    ._documentIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DocumentBlobsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DocumentBlobsTable,
      DocumentBlob,
      $$DocumentBlobsTableFilterComposer,
      $$DocumentBlobsTableOrderingComposer,
      $$DocumentBlobsTableAnnotationComposer,
      $$DocumentBlobsTableCreateCompanionBuilder,
      $$DocumentBlobsTableUpdateCompanionBuilder,
      (DocumentBlob, $$DocumentBlobsTableReferences),
      DocumentBlob,
      PrefetchHooks Function({bool documentId})
    >;
typedef $$RevisionHistoriesTableCreateCompanionBuilder =
    RevisionHistoriesCompanion Function({
      Value<int> id,
      required int fkdocument,
      required String rev,
      required int version,
      required int seq,
      Value<bool?> deleted,
    });
typedef $$RevisionHistoriesTableUpdateCompanionBuilder =
    RevisionHistoriesCompanion Function({
      Value<int> id,
      Value<int> fkdocument,
      Value<String> rev,
      Value<int> version,
      Value<int> seq,
      Value<bool?> deleted,
    });

final class $$RevisionHistoriesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $RevisionHistoriesTable,
          RevisionHistory
        > {
  $$RevisionHistoriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalDocumentsTable _fkdocumentTable(_$AppDatabase db) =>
      db.localDocuments.createAlias(
        $_aliasNameGenerator(
          db.revisionHistories.fkdocument,
          db.localDocuments.id,
        ),
      );

  $$LocalDocumentsTableProcessedTableManager get fkdocument {
    final $_column = $_itemColumn<int>('fkdocument')!;

    final manager = $$LocalDocumentsTableTableManager(
      $_db,
      $_db.localDocuments,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_fkdocumentTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RevisionHistoriesTableFilterComposer
    extends Composer<_$AppDatabase, $RevisionHistoriesTable> {
  $$RevisionHistoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rev => $composableBuilder(
    column: $table.rev,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalDocumentsTableFilterComposer get fkdocument {
    final $$LocalDocumentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fkdocument,
      referencedTable: $db.localDocuments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalDocumentsTableFilterComposer(
            $db: $db,
            $table: $db.localDocuments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RevisionHistoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $RevisionHistoriesTable> {
  $$RevisionHistoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rev => $composableBuilder(
    column: $table.rev,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalDocumentsTableOrderingComposer get fkdocument {
    final $$LocalDocumentsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fkdocument,
      referencedTable: $db.localDocuments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalDocumentsTableOrderingComposer(
            $db: $db,
            $table: $db.localDocuments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RevisionHistoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RevisionHistoriesTable> {
  $$RevisionHistoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get rev =>
      $composableBuilder(column: $table.rev, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  $$LocalDocumentsTableAnnotationComposer get fkdocument {
    final $$LocalDocumentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fkdocument,
      referencedTable: $db.localDocuments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalDocumentsTableAnnotationComposer(
            $db: $db,
            $table: $db.localDocuments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RevisionHistoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RevisionHistoriesTable,
          RevisionHistory,
          $$RevisionHistoriesTableFilterComposer,
          $$RevisionHistoriesTableOrderingComposer,
          $$RevisionHistoriesTableAnnotationComposer,
          $$RevisionHistoriesTableCreateCompanionBuilder,
          $$RevisionHistoriesTableUpdateCompanionBuilder,
          (RevisionHistory, $$RevisionHistoriesTableReferences),
          RevisionHistory,
          PrefetchHooks Function({bool fkdocument})
        > {
  $$RevisionHistoriesTableTableManager(
    _$AppDatabase db,
    $RevisionHistoriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RevisionHistoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RevisionHistoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RevisionHistoriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> fkdocument = const Value.absent(),
                Value<String> rev = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> seq = const Value.absent(),
                Value<bool?> deleted = const Value.absent(),
              }) => RevisionHistoriesCompanion(
                id: id,
                fkdocument: fkdocument,
                rev: rev,
                version: version,
                seq: seq,
                deleted: deleted,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int fkdocument,
                required String rev,
                required int version,
                required int seq,
                Value<bool?> deleted = const Value.absent(),
              }) => RevisionHistoriesCompanion.insert(
                id: id,
                fkdocument: fkdocument,
                rev: rev,
                version: version,
                seq: seq,
                deleted: deleted,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RevisionHistoriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({fkdocument = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (fkdocument) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.fkdocument,
                                referencedTable:
                                    $$RevisionHistoriesTableReferences
                                        ._fkdocumentTable(db),
                                referencedColumn:
                                    $$RevisionHistoriesTableReferences
                                        ._fkdocumentTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RevisionHistoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RevisionHistoriesTable,
      RevisionHistory,
      $$RevisionHistoriesTableFilterComposer,
      $$RevisionHistoriesTableOrderingComposer,
      $$RevisionHistoriesTableAnnotationComposer,
      $$RevisionHistoriesTableCreateCompanionBuilder,
      $$RevisionHistoriesTableUpdateCompanionBuilder,
      (RevisionHistory, $$RevisionHistoriesTableReferences),
      RevisionHistory,
      PrefetchHooks Function({bool fkdocument})
    >;
typedef $$LocalAttachmentsTableCreateCompanionBuilder =
    LocalAttachmentsCompanion Function({
      Value<int> id,
      required int fkdocument,
      required int ordering,
      required int revpos,
      required String name,
      required int length,
      required String contentType,
      required String digest,
      Value<String?> encoding,
    });
typedef $$LocalAttachmentsTableUpdateCompanionBuilder =
    LocalAttachmentsCompanion Function({
      Value<int> id,
      Value<int> fkdocument,
      Value<int> ordering,
      Value<int> revpos,
      Value<String> name,
      Value<int> length,
      Value<String> contentType,
      Value<String> digest,
      Value<String?> encoding,
    });

final class $$LocalAttachmentsTableReferences
    extends
        BaseReferences<_$AppDatabase, $LocalAttachmentsTable, LocalAttachment> {
  $$LocalAttachmentsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalDocumentsTable _fkdocumentTable(_$AppDatabase db) =>
      db.localDocuments.createAlias(
        $_aliasNameGenerator(
          db.localAttachments.fkdocument,
          db.localDocuments.id,
        ),
      );

  $$LocalDocumentsTableProcessedTableManager get fkdocument {
    final $_column = $_itemColumn<int>('fkdocument')!;

    final manager = $$LocalDocumentsTableTableManager(
      $_db,
      $_db.localDocuments,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_fkdocumentTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$LocalAttachmentsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalAttachmentsTable> {
  $$LocalAttachmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ordering => $composableBuilder(
    column: $table.ordering,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revpos => $composableBuilder(
    column: $table.revpos,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get length => $composableBuilder(
    column: $table.length,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get digest => $composableBuilder(
    column: $table.digest,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encoding => $composableBuilder(
    column: $table.encoding,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalDocumentsTableFilterComposer get fkdocument {
    final $$LocalDocumentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fkdocument,
      referencedTable: $db.localDocuments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalDocumentsTableFilterComposer(
            $db: $db,
            $table: $db.localDocuments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LocalAttachmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalAttachmentsTable> {
  $$LocalAttachmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ordering => $composableBuilder(
    column: $table.ordering,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revpos => $composableBuilder(
    column: $table.revpos,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get length => $composableBuilder(
    column: $table.length,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get digest => $composableBuilder(
    column: $table.digest,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encoding => $composableBuilder(
    column: $table.encoding,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalDocumentsTableOrderingComposer get fkdocument {
    final $$LocalDocumentsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fkdocument,
      referencedTable: $db.localDocuments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalDocumentsTableOrderingComposer(
            $db: $db,
            $table: $db.localDocuments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LocalAttachmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalAttachmentsTable> {
  $$LocalAttachmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get ordering =>
      $composableBuilder(column: $table.ordering, builder: (column) => column);

  GeneratedColumn<int> get revpos =>
      $composableBuilder(column: $table.revpos, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get length =>
      $composableBuilder(column: $table.length, builder: (column) => column);

  GeneratedColumn<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get digest =>
      $composableBuilder(column: $table.digest, builder: (column) => column);

  GeneratedColumn<String> get encoding =>
      $composableBuilder(column: $table.encoding, builder: (column) => column);

  $$LocalDocumentsTableAnnotationComposer get fkdocument {
    final $$LocalDocumentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fkdocument,
      referencedTable: $db.localDocuments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalDocumentsTableAnnotationComposer(
            $db: $db,
            $table: $db.localDocuments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LocalAttachmentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalAttachmentsTable,
          LocalAttachment,
          $$LocalAttachmentsTableFilterComposer,
          $$LocalAttachmentsTableOrderingComposer,
          $$LocalAttachmentsTableAnnotationComposer,
          $$LocalAttachmentsTableCreateCompanionBuilder,
          $$LocalAttachmentsTableUpdateCompanionBuilder,
          (LocalAttachment, $$LocalAttachmentsTableReferences),
          LocalAttachment,
          PrefetchHooks Function({bool fkdocument})
        > {
  $$LocalAttachmentsTableTableManager(
    _$AppDatabase db,
    $LocalAttachmentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalAttachmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalAttachmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalAttachmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> fkdocument = const Value.absent(),
                Value<int> ordering = const Value.absent(),
                Value<int> revpos = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> length = const Value.absent(),
                Value<String> contentType = const Value.absent(),
                Value<String> digest = const Value.absent(),
                Value<String?> encoding = const Value.absent(),
              }) => LocalAttachmentsCompanion(
                id: id,
                fkdocument: fkdocument,
                ordering: ordering,
                revpos: revpos,
                name: name,
                length: length,
                contentType: contentType,
                digest: digest,
                encoding: encoding,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int fkdocument,
                required int ordering,
                required int revpos,
                required String name,
                required int length,
                required String contentType,
                required String digest,
                Value<String?> encoding = const Value.absent(),
              }) => LocalAttachmentsCompanion.insert(
                id: id,
                fkdocument: fkdocument,
                ordering: ordering,
                revpos: revpos,
                name: name,
                length: length,
                contentType: contentType,
                digest: digest,
                encoding: encoding,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LocalAttachmentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({fkdocument = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (fkdocument) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.fkdocument,
                                referencedTable:
                                    $$LocalAttachmentsTableReferences
                                        ._fkdocumentTable(db),
                                referencedColumn:
                                    $$LocalAttachmentsTableReferences
                                        ._fkdocumentTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$LocalAttachmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalAttachmentsTable,
      LocalAttachment,
      $$LocalAttachmentsTableFilterComposer,
      $$LocalAttachmentsTableOrderingComposer,
      $$LocalAttachmentsTableAnnotationComposer,
      $$LocalAttachmentsTableCreateCompanionBuilder,
      $$LocalAttachmentsTableUpdateCompanionBuilder,
      (LocalAttachment, $$LocalAttachmentsTableReferences),
      LocalAttachment,
      PrefetchHooks Function({bool fkdocument})
    >;
typedef $$LocalViewsTableCreateCompanionBuilder =
    LocalViewsCompanion Function({
      Value<int> id,
      required int database,
      required String viewPathShort,
      Value<int> updateSeq,
      required String mapFunction,
      Value<String?> reduceFunction,
    });
typedef $$LocalViewsTableUpdateCompanionBuilder =
    LocalViewsCompanion Function({
      Value<int> id,
      Value<int> database,
      Value<String> viewPathShort,
      Value<int> updateSeq,
      Value<String> mapFunction,
      Value<String?> reduceFunction,
    });

final class $$LocalViewsTableReferences
    extends BaseReferences<_$AppDatabase, $LocalViewsTable, LocalView> {
  $$LocalViewsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $LocalDatabasesTable _databaseTable(_$AppDatabase db) =>
      db.localDatabases.createAlias(
        $_aliasNameGenerator(db.localViews.database, db.localDatabases.id),
      );

  $$LocalDatabasesTableProcessedTableManager get database {
    final $_column = $_itemColumn<int>('database')!;

    final manager = $$LocalDatabasesTableTableManager(
      $_db,
      $_db.localDatabases,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_databaseTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$LocalViewEntriesTable, List<LocalViewEntry>>
  _localViewEntriesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.localViewEntries,
    aliasName: $_aliasNameGenerator(
      db.localViews.id,
      db.localViewEntries.fkview,
    ),
  );

  $$LocalViewEntriesTableProcessedTableManager get localViewEntriesRefs {
    final manager = $$LocalViewEntriesTableTableManager(
      $_db,
      $_db.localViewEntries,
    ).filter((f) => f.fkview.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _localViewEntriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$LocalViewsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalViewsTable> {
  $$LocalViewsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get viewPathShort => $composableBuilder(
    column: $table.viewPathShort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updateSeq => $composableBuilder(
    column: $table.updateSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mapFunction => $composableBuilder(
    column: $table.mapFunction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reduceFunction => $composableBuilder(
    column: $table.reduceFunction,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalDatabasesTableFilterComposer get database {
    final $$LocalDatabasesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.database,
      referencedTable: $db.localDatabases,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalDatabasesTableFilterComposer(
            $db: $db,
            $table: $db.localDatabases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> localViewEntriesRefs(
    Expression<bool> Function($$LocalViewEntriesTableFilterComposer f) f,
  ) {
    final $$LocalViewEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.localViewEntries,
      getReferencedColumn: (t) => t.fkview,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalViewEntriesTableFilterComposer(
            $db: $db,
            $table: $db.localViewEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LocalViewsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalViewsTable> {
  $$LocalViewsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get viewPathShort => $composableBuilder(
    column: $table.viewPathShort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updateSeq => $composableBuilder(
    column: $table.updateSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mapFunction => $composableBuilder(
    column: $table.mapFunction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reduceFunction => $composableBuilder(
    column: $table.reduceFunction,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalDatabasesTableOrderingComposer get database {
    final $$LocalDatabasesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.database,
      referencedTable: $db.localDatabases,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalDatabasesTableOrderingComposer(
            $db: $db,
            $table: $db.localDatabases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LocalViewsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalViewsTable> {
  $$LocalViewsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get viewPathShort => $composableBuilder(
    column: $table.viewPathShort,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updateSeq =>
      $composableBuilder(column: $table.updateSeq, builder: (column) => column);

  GeneratedColumn<String> get mapFunction => $composableBuilder(
    column: $table.mapFunction,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reduceFunction => $composableBuilder(
    column: $table.reduceFunction,
    builder: (column) => column,
  );

  $$LocalDatabasesTableAnnotationComposer get database {
    final $$LocalDatabasesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.database,
      referencedTable: $db.localDatabases,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalDatabasesTableAnnotationComposer(
            $db: $db,
            $table: $db.localDatabases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> localViewEntriesRefs<T extends Object>(
    Expression<T> Function($$LocalViewEntriesTableAnnotationComposer a) f,
  ) {
    final $$LocalViewEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.localViewEntries,
      getReferencedColumn: (t) => t.fkview,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalViewEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.localViewEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LocalViewsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalViewsTable,
          LocalView,
          $$LocalViewsTableFilterComposer,
          $$LocalViewsTableOrderingComposer,
          $$LocalViewsTableAnnotationComposer,
          $$LocalViewsTableCreateCompanionBuilder,
          $$LocalViewsTableUpdateCompanionBuilder,
          (LocalView, $$LocalViewsTableReferences),
          LocalView,
          PrefetchHooks Function({bool database, bool localViewEntriesRefs})
        > {
  $$LocalViewsTableTableManager(_$AppDatabase db, $LocalViewsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalViewsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalViewsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalViewsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> database = const Value.absent(),
                Value<String> viewPathShort = const Value.absent(),
                Value<int> updateSeq = const Value.absent(),
                Value<String> mapFunction = const Value.absent(),
                Value<String?> reduceFunction = const Value.absent(),
              }) => LocalViewsCompanion(
                id: id,
                database: database,
                viewPathShort: viewPathShort,
                updateSeq: updateSeq,
                mapFunction: mapFunction,
                reduceFunction: reduceFunction,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int database,
                required String viewPathShort,
                Value<int> updateSeq = const Value.absent(),
                required String mapFunction,
                Value<String?> reduceFunction = const Value.absent(),
              }) => LocalViewsCompanion.insert(
                id: id,
                database: database,
                viewPathShort: viewPathShort,
                updateSeq: updateSeq,
                mapFunction: mapFunction,
                reduceFunction: reduceFunction,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LocalViewsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({database = false, localViewEntriesRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (localViewEntriesRefs) db.localViewEntries,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (database) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.database,
                                    referencedTable: $$LocalViewsTableReferences
                                        ._databaseTable(db),
                                    referencedColumn:
                                        $$LocalViewsTableReferences
                                            ._databaseTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (localViewEntriesRefs)
                        await $_getPrefetchedData<
                          LocalView,
                          $LocalViewsTable,
                          LocalViewEntry
                        >(
                          currentTable: table,
                          referencedTable: $$LocalViewsTableReferences
                              ._localViewEntriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalViewsTableReferences(
                                db,
                                table,
                                p0,
                              ).localViewEntriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.fkview == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$LocalViewsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalViewsTable,
      LocalView,
      $$LocalViewsTableFilterComposer,
      $$LocalViewsTableOrderingComposer,
      $$LocalViewsTableAnnotationComposer,
      $$LocalViewsTableCreateCompanionBuilder,
      $$LocalViewsTableUpdateCompanionBuilder,
      (LocalView, $$LocalViewsTableReferences),
      LocalView,
      PrefetchHooks Function({bool database, bool localViewEntriesRefs})
    >;
typedef $$LocalViewEntriesTableCreateCompanionBuilder =
    LocalViewEntriesCompanion Function({
      Value<int> id,
      required int fkview,
      required String docid,
      required String key,
      required String value,
    });
typedef $$LocalViewEntriesTableUpdateCompanionBuilder =
    LocalViewEntriesCompanion Function({
      Value<int> id,
      Value<int> fkview,
      Value<String> docid,
      Value<String> key,
      Value<String> value,
    });

final class $$LocalViewEntriesTableReferences
    extends
        BaseReferences<_$AppDatabase, $LocalViewEntriesTable, LocalViewEntry> {
  $$LocalViewEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalViewsTable _fkviewTable(_$AppDatabase db) =>
      db.localViews.createAlias(
        $_aliasNameGenerator(db.localViewEntries.fkview, db.localViews.id),
      );

  $$LocalViewsTableProcessedTableManager get fkview {
    final $_column = $_itemColumn<int>('fkview')!;

    final manager = $$LocalViewsTableTableManager(
      $_db,
      $_db.localViews,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_fkviewTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$LocalViewEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalViewEntriesTable> {
  $$LocalViewEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get docid => $composableBuilder(
    column: $table.docid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalViewsTableFilterComposer get fkview {
    final $$LocalViewsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fkview,
      referencedTable: $db.localViews,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalViewsTableFilterComposer(
            $db: $db,
            $table: $db.localViews,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LocalViewEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalViewEntriesTable> {
  $$LocalViewEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get docid => $composableBuilder(
    column: $table.docid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalViewsTableOrderingComposer get fkview {
    final $$LocalViewsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fkview,
      referencedTable: $db.localViews,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalViewsTableOrderingComposer(
            $db: $db,
            $table: $db.localViews,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LocalViewEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalViewEntriesTable> {
  $$LocalViewEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get docid =>
      $composableBuilder(column: $table.docid, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  $$LocalViewsTableAnnotationComposer get fkview {
    final $$LocalViewsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fkview,
      referencedTable: $db.localViews,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalViewsTableAnnotationComposer(
            $db: $db,
            $table: $db.localViews,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LocalViewEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalViewEntriesTable,
          LocalViewEntry,
          $$LocalViewEntriesTableFilterComposer,
          $$LocalViewEntriesTableOrderingComposer,
          $$LocalViewEntriesTableAnnotationComposer,
          $$LocalViewEntriesTableCreateCompanionBuilder,
          $$LocalViewEntriesTableUpdateCompanionBuilder,
          (LocalViewEntry, $$LocalViewEntriesTableReferences),
          LocalViewEntry,
          PrefetchHooks Function({bool fkview})
        > {
  $$LocalViewEntriesTableTableManager(
    _$AppDatabase db,
    $LocalViewEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalViewEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalViewEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalViewEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> fkview = const Value.absent(),
                Value<String> docid = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
              }) => LocalViewEntriesCompanion(
                id: id,
                fkview: fkview,
                docid: docid,
                key: key,
                value: value,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int fkview,
                required String docid,
                required String key,
                required String value,
              }) => LocalViewEntriesCompanion.insert(
                id: id,
                fkview: fkview,
                docid: docid,
                key: key,
                value: value,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LocalViewEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({fkview = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (fkview) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.fkview,
                                referencedTable:
                                    $$LocalViewEntriesTableReferences
                                        ._fkviewTable(db),
                                referencedColumn:
                                    $$LocalViewEntriesTableReferences
                                        ._fkviewTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$LocalViewEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalViewEntriesTable,
      LocalViewEntry,
      $$LocalViewEntriesTableFilterComposer,
      $$LocalViewEntriesTableOrderingComposer,
      $$LocalViewEntriesTableAnnotationComposer,
      $$LocalViewEntriesTableCreateCompanionBuilder,
      $$LocalViewEntriesTableUpdateCompanionBuilder,
      (LocalViewEntry, $$LocalViewEntriesTableReferences),
      LocalViewEntry,
      PrefetchHooks Function({bool fkview})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$LocalDatabasesTableTableManager get localDatabases =>
      $$LocalDatabasesTableTableManager(_db, _db.localDatabases);
  $$LocalDocumentsTableTableManager get localDocuments =>
      $$LocalDocumentsTableTableManager(_db, _db.localDocuments);
  $$DocumentBlobsTableTableManager get documentBlobs =>
      $$DocumentBlobsTableTableManager(_db, _db.documentBlobs);
  $$RevisionHistoriesTableTableManager get revisionHistories =>
      $$RevisionHistoriesTableTableManager(_db, _db.revisionHistories);
  $$LocalAttachmentsTableTableManager get localAttachments =>
      $$LocalAttachmentsTableTableManager(_db, _db.localAttachments);
  $$LocalViewsTableTableManager get localViews =>
      $$LocalViewsTableTableManager(_db, _db.localViews);
  $$LocalViewEntriesTableTableManager get localViewEntries =>
      $$LocalViewEntriesTableTableManager(_db, _db.localViewEntries);
}
