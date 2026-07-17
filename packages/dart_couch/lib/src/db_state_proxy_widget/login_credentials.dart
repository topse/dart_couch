/// Simple data object holding the login form result.
class LoginCredentials {
  final String url;
  final String username;
  final String password;
  final bool storeCredentials;

  const LoginCredentials({
    required this.url,
    required this.username,
    required this.password,
    this.storeCredentials = false,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'username': username,
    'password': password,
    'storeCredentials': storeCredentials,
  };

  factory LoginCredentials.fromJson(Map<String, dynamic> json) =>
      LoginCredentials(
        url: json['url'] as String,
        username: json['username'] as String,
        password: json['password'] as String,
        storeCredentials: json['storeCredentials'] as bool? ?? false,
      );
}
