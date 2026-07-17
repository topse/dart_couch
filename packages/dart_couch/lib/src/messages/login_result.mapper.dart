// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'login_result.dart';

class LoginResultBodyMapper extends ClassMapperBase<LoginResultBody> {
  LoginResultBodyMapper._();

  static LoginResultBodyMapper? _instance;
  static LoginResultBodyMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LoginResultBodyMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'LoginResultBody';

  static bool _$ok(LoginResultBody v) => v.ok;
  static const Field<LoginResultBody, bool> _f$ok = Field('ok', _$ok);
  static String _$username(LoginResultBody v) => v.username;
  static const Field<LoginResultBody, String> _f$username = Field(
    'username',
    _$username,
    key: r'name',
  );
  static List<String> _$roles(LoginResultBody v) => v.roles;
  static const Field<LoginResultBody, List<String>> _f$roles = Field(
    'roles',
    _$roles,
  );

  @override
  final MappableFields<LoginResultBody> fields = const {
    #ok: _f$ok,
    #username: _f$username,
    #roles: _f$roles,
  };

  static LoginResultBody _instantiate(DecodingData data) {
    return LoginResultBody(
      ok: data.dec(_f$ok),
      username: data.dec(_f$username),
      roles: data.dec(_f$roles),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LoginResultBody fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LoginResultBody>(map);
  }

  static LoginResultBody fromJson(String json) {
    return ensureInitialized().decodeJson<LoginResultBody>(json);
  }
}

mixin LoginResultBodyMappable {
  String toJson() {
    return LoginResultBodyMapper.ensureInitialized()
        .encodeJson<LoginResultBody>(this as LoginResultBody);
  }

  Map<String, dynamic> toMap() {
    return LoginResultBodyMapper.ensureInitialized().encodeMap<LoginResultBody>(
      this as LoginResultBody,
    );
  }

  LoginResultBodyCopyWith<LoginResultBody, LoginResultBody, LoginResultBody>
  get copyWith =>
      _LoginResultBodyCopyWithImpl<LoginResultBody, LoginResultBody>(
        this as LoginResultBody,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return LoginResultBodyMapper.ensureInitialized().stringifyValue(
      this as LoginResultBody,
    );
  }

  @override
  bool operator ==(Object other) {
    return LoginResultBodyMapper.ensureInitialized().equalsValue(
      this as LoginResultBody,
      other,
    );
  }

  @override
  int get hashCode {
    return LoginResultBodyMapper.ensureInitialized().hashValue(
      this as LoginResultBody,
    );
  }
}

extension LoginResultBodyValueCopy<$R, $Out>
    on ObjectCopyWith<$R, LoginResultBody, $Out> {
  LoginResultBodyCopyWith<$R, LoginResultBody, $Out> get $asLoginResultBody =>
      $base.as((v, t, t2) => _LoginResultBodyCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class LoginResultBodyCopyWith<$R, $In extends LoginResultBody, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get roles;
  $R call({bool? ok, String? username, List<String>? roles});
  LoginResultBodyCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _LoginResultBodyCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LoginResultBody, $Out>
    implements LoginResultBodyCopyWith<$R, LoginResultBody, $Out> {
  _LoginResultBodyCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LoginResultBody> $mapper =
      LoginResultBodyMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get roles =>
      ListCopyWith(
        $value.roles,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(roles: v),
      );
  @override
  $R call({bool? ok, String? username, List<String>? roles}) => $apply(
    FieldCopyWithData({
      if (ok != null) #ok: ok,
      if (username != null) #username: username,
      if (roles != null) #roles: roles,
    }),
  );
  @override
  LoginResultBody $make(CopyWithData data) => LoginResultBody(
    ok: data.get(#ok, or: $value.ok),
    username: data.get(#username, or: $value.username),
    roles: data.get(#roles, or: $value.roles),
  );

  @override
  LoginResultBodyCopyWith<$R2, LoginResultBody, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _LoginResultBodyCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

