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
