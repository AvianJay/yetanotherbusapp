class ApiConfig {
  ApiConfig._();

  static const baseUrl = String.fromEnvironment(
    'YABUS_API_BASE_URL',
    defaultValue: 'https://bus.avianjay.sbs',
  );

  static const webAuthRedirectUri = String.fromEnvironment(
    'YABUS_WEB_AUTH_REDIRECT_URI',
    defaultValue: 'https://busapp.avianjay.sbs/auth-callback',
  );

  static const appAuthRedirectUri = String.fromEnvironment(
    'YABUS_APP_AUTH_REDIRECT_URI',
    defaultValue: 'yabus://auth-callback',
  );
}
