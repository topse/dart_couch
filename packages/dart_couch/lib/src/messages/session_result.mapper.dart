// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'session_result.dart';

class SessionResultMapper extends ClassMapperBase<SessionResult> {
  SessionResultMapper._();

  static SessionResultMapper? _instance;
  static SessionResultMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SessionResultMapper._());
      UserCtxMapper.ensureInitialized();
      InfoOfSessionMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'SessionResult';

  static bool _$ok(SessionResult v) => v.ok;
  static const Field<SessionResult, bool> _f$ok = Field('ok', _$ok);
  static UserCtx _$userCtx(SessionResult v) => v.userCtx;
  static const Field<SessionResult, UserCtx> _f$userCtx = Field(
    'userCtx',
    _$userCtx,
  );
  static InfoOfSession _$info(SessionResult v) => v.info;
  static const Field<SessionResult, InfoOfSession> _f$info = Field(
    'info',
    _$info,
  );

  @override
  final MappableFields<SessionResult> fields = const {
    #ok: _f$ok,
    #userCtx: _f$userCtx,
    #info: _f$info,
  };

  static SessionResult _instantiate(DecodingData data) {
    return SessionResult(
      ok: data.dec(_f$ok),
      userCtx: data.dec(_f$userCtx),
      info: data.dec(_f$info),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static SessionResult fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SessionResult>(map);
  }

  static SessionResult fromJson(String json) {
    return ensureInitialized().decodeJson<SessionResult>(json);
  }
}

mixin SessionResultMappable {
  String toJson() {
    return SessionResultMapper.ensureInitialized().encodeJson<SessionResult>(
      this as SessionResult,
    );
  }

  Map<String, dynamic> toMap() {
    return SessionResultMapper.ensureInitialized().encodeMap<SessionResult>(
      this as SessionResult,
    );
  }

  SessionResultCopyWith<SessionResult, SessionResult, SessionResult>
  get copyWith => _SessionResultCopyWithImpl<SessionResult, SessionResult>(
    this as SessionResult,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return SessionResultMapper.ensureInitialized().stringifyValue(
      this as SessionResult,
    );
  }

  @override
  bool operator ==(Object other) {
    return SessionResultMapper.ensureInitialized().equalsValue(
      this as SessionResult,
      other,
    );
  }

  @override
  int get hashCode {
    return SessionResultMapper.ensureInitialized().hashValue(
      this as SessionResult,
    );
  }
}

extension SessionResultValueCopy<$R, $Out>
    on ObjectCopyWith<$R, SessionResult, $Out> {
  SessionResultCopyWith<$R, SessionResult, $Out> get $asSessionResult =>
      $base.as((v, t, t2) => _SessionResultCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class SessionResultCopyWith<$R, $In extends SessionResult, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  UserCtxCopyWith<$R, UserCtx, UserCtx> get userCtx;
  InfoOfSessionCopyWith<$R, InfoOfSession, InfoOfSession> get info;
  $R call({bool? ok, UserCtx? userCtx, InfoOfSession? info});
  SessionResultCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _SessionResultCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SessionResult, $Out>
    implements SessionResultCopyWith<$R, SessionResult, $Out> {
  _SessionResultCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SessionResult> $mapper =
      SessionResultMapper.ensureInitialized();
  @override
  UserCtxCopyWith<$R, UserCtx, UserCtx> get userCtx =>
      $value.userCtx.copyWith.$chain((v) => call(userCtx: v));
  @override
  InfoOfSessionCopyWith<$R, InfoOfSession, InfoOfSession> get info =>
      $value.info.copyWith.$chain((v) => call(info: v));
  @override
  $R call({bool? ok, UserCtx? userCtx, InfoOfSession? info}) => $apply(
    FieldCopyWithData({
      if (ok != null) #ok: ok,
      if (userCtx != null) #userCtx: userCtx,
      if (info != null) #info: info,
    }),
  );
  @override
  SessionResult $make(CopyWithData data) => SessionResult(
    ok: data.get(#ok, or: $value.ok),
    userCtx: data.get(#userCtx, or: $value.userCtx),
    info: data.get(#info, or: $value.info),
  );

  @override
  SessionResultCopyWith<$R2, SessionResult, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _SessionResultCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class UserCtxMapper extends ClassMapperBase<UserCtx> {
  UserCtxMapper._();

  static UserCtxMapper? _instance;
  static UserCtxMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = UserCtxMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'UserCtx';

  static String? _$name(UserCtx v) => v.name;
  static const Field<UserCtx, String> _f$name = Field(
    'name',
    _$name,
    opt: true,
  );
  static List<String> _$roles(UserCtx v) => v.roles;
  static const Field<UserCtx, List<String>> _f$roles = Field('roles', _$roles);

  @override
  final MappableFields<UserCtx> fields = const {
    #name: _f$name,
    #roles: _f$roles,
  };

  static UserCtx _instantiate(DecodingData data) {
    return UserCtx(name: data.dec(_f$name), roles: data.dec(_f$roles));
  }

  @override
  final Function instantiate = _instantiate;

  static UserCtx fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<UserCtx>(map);
  }

  static UserCtx fromJson(String json) {
    return ensureInitialized().decodeJson<UserCtx>(json);
  }
}

mixin UserCtxMappable {
  String toJson() {
    return UserCtxMapper.ensureInitialized().encodeJson<UserCtx>(
      this as UserCtx,
    );
  }

  Map<String, dynamic> toMap() {
    return UserCtxMapper.ensureInitialized().encodeMap<UserCtx>(
      this as UserCtx,
    );
  }

  UserCtxCopyWith<UserCtx, UserCtx, UserCtx> get copyWith =>
      _UserCtxCopyWithImpl<UserCtx, UserCtx>(
        this as UserCtx,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return UserCtxMapper.ensureInitialized().stringifyValue(this as UserCtx);
  }

  @override
  bool operator ==(Object other) {
    return UserCtxMapper.ensureInitialized().equalsValue(
      this as UserCtx,
      other,
    );
  }

  @override
  int get hashCode {
    return UserCtxMapper.ensureInitialized().hashValue(this as UserCtx);
  }
}

extension UserCtxValueCopy<$R, $Out> on ObjectCopyWith<$R, UserCtx, $Out> {
  UserCtxCopyWith<$R, UserCtx, $Out> get $asUserCtx =>
      $base.as((v, t, t2) => _UserCtxCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class UserCtxCopyWith<$R, $In extends UserCtx, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get roles;
  $R call({String? name, List<String>? roles});
  UserCtxCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _UserCtxCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, UserCtx, $Out>
    implements UserCtxCopyWith<$R, UserCtx, $Out> {
  _UserCtxCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<UserCtx> $mapper =
      UserCtxMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get roles =>
      ListCopyWith(
        $value.roles,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(roles: v),
      );
  @override
  $R call({Object? name = $none, List<String>? roles}) => $apply(
    FieldCopyWithData({
      if (name != $none) #name: name,
      if (roles != null) #roles: roles,
    }),
  );
  @override
  UserCtx $make(CopyWithData data) => UserCtx(
    name: data.get(#name, or: $value.name),
    roles: data.get(#roles, or: $value.roles),
  );

  @override
  UserCtxCopyWith<$R2, UserCtx, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _UserCtxCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class InfoOfSessionMapper extends ClassMapperBase<InfoOfSession> {
  InfoOfSessionMapper._();

  static InfoOfSessionMapper? _instance;
  static InfoOfSessionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = InfoOfSessionMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'InfoOfSession';

  static List<String> _$authenticationHandlers(InfoOfSession v) =>
      v.authenticationHandlers;
  static const Field<InfoOfSession, List<String>> _f$authenticationHandlers =
      Field(
        'authenticationHandlers',
        _$authenticationHandlers,
        key: r'authentication_handlers',
      );
  static String? _$authenticated(InfoOfSession v) => v.authenticated;
  static const Field<InfoOfSession, String> _f$authenticated = Field(
    'authenticated',
    _$authenticated,
    opt: true,
  );

  @override
  final MappableFields<InfoOfSession> fields = const {
    #authenticationHandlers: _f$authenticationHandlers,
    #authenticated: _f$authenticated,
  };

  static InfoOfSession _instantiate(DecodingData data) {
    return InfoOfSession(
      authenticationHandlers: data.dec(_f$authenticationHandlers),
      authenticated: data.dec(_f$authenticated),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static InfoOfSession fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<InfoOfSession>(map);
  }

  static InfoOfSession fromJson(String json) {
    return ensureInitialized().decodeJson<InfoOfSession>(json);
  }
}

mixin InfoOfSessionMappable {
  String toJson() {
    return InfoOfSessionMapper.ensureInitialized().encodeJson<InfoOfSession>(
      this as InfoOfSession,
    );
  }

  Map<String, dynamic> toMap() {
    return InfoOfSessionMapper.ensureInitialized().encodeMap<InfoOfSession>(
      this as InfoOfSession,
    );
  }

  InfoOfSessionCopyWith<InfoOfSession, InfoOfSession, InfoOfSession>
  get copyWith => _InfoOfSessionCopyWithImpl<InfoOfSession, InfoOfSession>(
    this as InfoOfSession,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return InfoOfSessionMapper.ensureInitialized().stringifyValue(
      this as InfoOfSession,
    );
  }

  @override
  bool operator ==(Object other) {
    return InfoOfSessionMapper.ensureInitialized().equalsValue(
      this as InfoOfSession,
      other,
    );
  }

  @override
  int get hashCode {
    return InfoOfSessionMapper.ensureInitialized().hashValue(
      this as InfoOfSession,
    );
  }
}

extension InfoOfSessionValueCopy<$R, $Out>
    on ObjectCopyWith<$R, InfoOfSession, $Out> {
  InfoOfSessionCopyWith<$R, InfoOfSession, $Out> get $asInfoOfSession =>
      $base.as((v, t, t2) => _InfoOfSessionCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class InfoOfSessionCopyWith<$R, $In extends InfoOfSession, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get authenticationHandlers;
  $R call({List<String>? authenticationHandlers, String? authenticated});
  InfoOfSessionCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _InfoOfSessionCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, InfoOfSession, $Out>
    implements InfoOfSessionCopyWith<$R, InfoOfSession, $Out> {
  _InfoOfSessionCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<InfoOfSession> $mapper =
      InfoOfSessionMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get authenticationHandlers => ListCopyWith(
    $value.authenticationHandlers,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(authenticationHandlers: v),
  );
  @override
  $R call({
    List<String>? authenticationHandlers,
    Object? authenticated = $none,
  }) => $apply(
    FieldCopyWithData({
      if (authenticationHandlers != null)
        #authenticationHandlers: authenticationHandlers,
      if (authenticated != $none) #authenticated: authenticated,
    }),
  );
  @override
  InfoOfSession $make(CopyWithData data) => InfoOfSession(
    authenticationHandlers: data.get(
      #authenticationHandlers,
      or: $value.authenticationHandlers,
    ),
    authenticated: data.get(#authenticated, or: $value.authenticated),
  );

  @override
  InfoOfSessionCopyWith<$R2, InfoOfSession, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _InfoOfSessionCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

