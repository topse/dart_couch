import 'package:dart_mappable/dart_mappable.dart';

part 'session_result.mapper.dart';

/// {
///   "ok":true,
///   "userCtx":{
///      "name":"admin",
///      "roles":["_admin"]
///   },
///   "info":{
///      "authentication_handlers":["cookie","default"],
///      "authenticated":"cookie"
///   }
/// }

@MappableClass()
class SessionResult with SessionResultMappable {
  final bool ok;
  final UserCtx userCtx;
  final InfoOfSession info;

  const SessionResult({
    required this.ok,
    required this.userCtx,
    required this.info,
  });

  static final fromMap = SessionResultMapper.fromMap;
  static final fromJson = SessionResultMapper.fromJson;
}

@MappableClass()
class UserCtx with UserCtxMappable {
  final String? name;
  final List<String> roles;

  const UserCtx({this.name, required this.roles});
}

/// {"authentication_handlers":["cookie","default"],"authenticated":"cookie"}
@MappableClass()
class InfoOfSession with InfoOfSessionMappable {
  @MappableField(key: "authentication_handlers")
  final List<String> authenticationHandlers;
  final String? authenticated;

  const InfoOfSession({
    required this.authenticationHandlers,
    this.authenticated,
  });
}
