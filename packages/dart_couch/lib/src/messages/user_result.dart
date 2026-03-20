import 'package:dart_mappable/dart_mappable.dart';

part 'user_result.mapper.dart';

/// {
///  "_id": "org.couchdb.user:MonaTobi",
///  "_rev": "2-4fb2be81971876906a8ae21842a95b42",
///  "password_scheme": "pbkdf2",
///  "pbkdf2_prf": "sha256",
///  "salt": "5a7cb9185b067e50824cd1a858656021",
///  "iterations": 600000,
///  "derived_key": "56e4fa28b804299cad041509e798b2271d18735bf4c6399c24ec7b4ab772fd9c",
///  "name": "MonaTobi",
///  "type": "user",
///  "roles": []
///}

@MappableClass()
class UserResult with UserResultMappable {
  @MappableField(key: '_id')
  final String id;
  @MappableField(key: '_rev')
  final String rev;

  @MappableField(key: 'password_scheme')
  final String passwordScheme;
  @MappableField(key: 'pbkdf2_prf')
  final String pbkdf2Prf;
  @MappableField()
  final String salt;
  @MappableField()
  final int iterations;
  @MappableField(key: 'derived_key')
  final String derivedKey;

  @MappableField()
  final String name;
  @MappableField()
  final String type;
  @MappableField()
  final List<String> roles;

  UserResult({
    required this.id,
    required this.rev,
    required this.passwordScheme,
    required this.pbkdf2Prf,
    required this.salt,
    required this.iterations,
    required this.derivedKey,
    required this.name,
    required this.type,
    required this.roles,
  });

  static final fromMap = UserResultMapper.fromMap;
  static final fromJson = UserResultMapper.fromJson;
}
