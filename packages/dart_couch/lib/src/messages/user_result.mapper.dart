// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'user_result.dart';

class UserResultMapper extends ClassMapperBase<UserResult> {
  UserResultMapper._();

  static UserResultMapper? _instance;
  static UserResultMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = UserResultMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'UserResult';

  static String _$id(UserResult v) => v.id;
  static const Field<UserResult, String> _f$id = Field('id', _$id, key: r'_id');
  static String _$rev(UserResult v) => v.rev;
  static const Field<UserResult, String> _f$rev = Field(
    'rev',
    _$rev,
    key: r'_rev',
  );
  static String _$passwordScheme(UserResult v) => v.passwordScheme;
  static const Field<UserResult, String> _f$passwordScheme = Field(
    'passwordScheme',
    _$passwordScheme,
    key: r'password_scheme',
  );
  static String _$pbkdf2Prf(UserResult v) => v.pbkdf2Prf;
  static const Field<UserResult, String> _f$pbkdf2Prf = Field(
    'pbkdf2Prf',
    _$pbkdf2Prf,
    key: r'pbkdf2_prf',
  );
  static String _$salt(UserResult v) => v.salt;
  static const Field<UserResult, String> _f$salt = Field('salt', _$salt);
  static int _$iterations(UserResult v) => v.iterations;
  static const Field<UserResult, int> _f$iterations = Field(
    'iterations',
    _$iterations,
  );
  static String _$derivedKey(UserResult v) => v.derivedKey;
  static const Field<UserResult, String> _f$derivedKey = Field(
    'derivedKey',
    _$derivedKey,
    key: r'derived_key',
  );
  static String _$name(UserResult v) => v.name;
  static const Field<UserResult, String> _f$name = Field('name', _$name);
  static String _$type(UserResult v) => v.type;
  static const Field<UserResult, String> _f$type = Field('type', _$type);
  static List<String> _$roles(UserResult v) => v.roles;
  static const Field<UserResult, List<String>> _f$roles = Field(
    'roles',
    _$roles,
  );

  @override
  final MappableFields<UserResult> fields = const {
    #id: _f$id,
    #rev: _f$rev,
    #passwordScheme: _f$passwordScheme,
    #pbkdf2Prf: _f$pbkdf2Prf,
    #salt: _f$salt,
    #iterations: _f$iterations,
    #derivedKey: _f$derivedKey,
    #name: _f$name,
    #type: _f$type,
    #roles: _f$roles,
  };

  static UserResult _instantiate(DecodingData data) {
    return UserResult(
      id: data.dec(_f$id),
      rev: data.dec(_f$rev),
      passwordScheme: data.dec(_f$passwordScheme),
      pbkdf2Prf: data.dec(_f$pbkdf2Prf),
      salt: data.dec(_f$salt),
      iterations: data.dec(_f$iterations),
      derivedKey: data.dec(_f$derivedKey),
      name: data.dec(_f$name),
      type: data.dec(_f$type),
      roles: data.dec(_f$roles),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static UserResult fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<UserResult>(map);
  }

  static UserResult fromJson(String json) {
    return ensureInitialized().decodeJson<UserResult>(json);
  }
}

mixin UserResultMappable {
  String toJson() {
    return UserResultMapper.ensureInitialized().encodeJson<UserResult>(
      this as UserResult,
    );
  }

  Map<String, dynamic> toMap() {
    return UserResultMapper.ensureInitialized().encodeMap<UserResult>(
      this as UserResult,
    );
  }

  UserResultCopyWith<UserResult, UserResult, UserResult> get copyWith =>
      _UserResultCopyWithImpl<UserResult, UserResult>(
        this as UserResult,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return UserResultMapper.ensureInitialized().stringifyValue(
      this as UserResult,
    );
  }

  @override
  bool operator ==(Object other) {
    return UserResultMapper.ensureInitialized().equalsValue(
      this as UserResult,
      other,
    );
  }

  @override
  int get hashCode {
    return UserResultMapper.ensureInitialized().hashValue(this as UserResult);
  }
}

extension UserResultValueCopy<$R, $Out>
    on ObjectCopyWith<$R, UserResult, $Out> {
  UserResultCopyWith<$R, UserResult, $Out> get $asUserResult =>
      $base.as((v, t, t2) => _UserResultCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class UserResultCopyWith<$R, $In extends UserResult, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get roles;
  $R call({
    String? id,
    String? rev,
    String? passwordScheme,
    String? pbkdf2Prf,
    String? salt,
    int? iterations,
    String? derivedKey,
    String? name,
    String? type,
    List<String>? roles,
  });
  UserResultCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _UserResultCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, UserResult, $Out>
    implements UserResultCopyWith<$R, UserResult, $Out> {
  _UserResultCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<UserResult> $mapper =
      UserResultMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get roles =>
      ListCopyWith(
        $value.roles,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(roles: v),
      );
  @override
  $R call({
    String? id,
    String? rev,
    String? passwordScheme,
    String? pbkdf2Prf,
    String? salt,
    int? iterations,
    String? derivedKey,
    String? name,
    String? type,
    List<String>? roles,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (rev != null) #rev: rev,
      if (passwordScheme != null) #passwordScheme: passwordScheme,
      if (pbkdf2Prf != null) #pbkdf2Prf: pbkdf2Prf,
      if (salt != null) #salt: salt,
      if (iterations != null) #iterations: iterations,
      if (derivedKey != null) #derivedKey: derivedKey,
      if (name != null) #name: name,
      if (type != null) #type: type,
      if (roles != null) #roles: roles,
    }),
  );
  @override
  UserResult $make(CopyWithData data) => UserResult(
    id: data.get(#id, or: $value.id),
    rev: data.get(#rev, or: $value.rev),
    passwordScheme: data.get(#passwordScheme, or: $value.passwordScheme),
    pbkdf2Prf: data.get(#pbkdf2Prf, or: $value.pbkdf2Prf),
    salt: data.get(#salt, or: $value.salt),
    iterations: data.get(#iterations, or: $value.iterations),
    derivedKey: data.get(#derivedKey, or: $value.derivedKey),
    name: data.get(#name, or: $value.name),
    type: data.get(#type, or: $value.type),
    roles: data.get(#roles, or: $value.roles),
  );

  @override
  UserResultCopyWith<$R2, UserResult, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _UserResultCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

