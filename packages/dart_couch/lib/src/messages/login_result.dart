import 'package:dart_mappable/dart_mappable.dart';

import 'couch_db_status_codes.dart';

part 'login_result.mapper.dart';

class LoginResult {
  final CouchDbStatusCodes statusCode;
  final String? errorMsg;
  final bool success;

  final LoginResultBody? body;

  LoginResult({
    required this.statusCode,
    this.errorMsg,
    required this.success,
    this.body,
  });
}

@MappableClass()
class LoginResultBody with LoginResultBodyMappable {
  final bool ok;

  @MappableField(key: 'name')
  final String username;

  final List<String> roles;

  LoginResultBody({
    required this.ok,
    required this.username,
    required this.roles,
  });

  static final fromMap = LoginResultBodyMapper.fromMap;
  static final fromJson = LoginResultBodyMapper.fromJson;
}
