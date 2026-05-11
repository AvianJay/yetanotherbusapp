/// Thrown when the server rejects the current auth token (HTTP 401/403),
/// indicating that the session is no longer valid and the user should be
/// logged out locally.
class AuthTokenExpiredException implements Exception {
  const AuthTokenExpiredException([this.message = 'Auth token expired.']);

  final String message;

  @override
  String toString() => message;
}

class AuthTokenStore {
  AuthTokenStore._();

  static String? _token;

  static String? get token {
    final value = _token?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static set token(String? value) {
    final trimmed = value?.trim();
    _token = trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
