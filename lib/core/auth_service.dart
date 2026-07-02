import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_http.dart';
import 'api_config.dart';
import 'api_user_agent.dart';
import 'auth_token_store.dart';
import 'http_error_utils.dart';

class AuthSession {
  const AuthSession({
    required this.token,
    required this.accountId,
    required this.deviceId,
    required this.role,
    required this.provider,
    required this.displayName,
  });

  final String token;
  final String accountId;
  final String deviceId;
  final String role;
  final String provider;
  final String displayName;

  bool get isAuthenticated => token.trim().isNotEmpty;
}

class AuthIdentity {
  const AuthIdentity({
    required this.provider,
    required this.providerUserId,
    required this.email,
    required this.displayName,
    required this.avatarUrl,
  });

  final String provider;
  final String providerUserId;
  final String email;
  final String displayName;
  final String avatarUrl;

  String get label {
    final name = displayName.trim();
    if (name.isNotEmpty) {
      return name;
    }
    final address = email.trim();
    if (address.isNotEmpty) {
      return address;
    }
    return provider;
  }

  factory AuthIdentity.fromJson(Map<String, dynamic> json) {
    return AuthIdentity(
      provider: '${json['provider'] ?? ''}',
      providerUserId: '${json['provider_user_id'] ?? ''}',
      email: '${json['email'] ?? ''}',
      displayName: '${json['display_name'] ?? ''}',
      avatarUrl: '${json['avatar_url'] ?? ''}',
    );
  }
}

class AuthDeviceInfo {
  const AuthDeviceInfo({
    required this.deviceKey,
    required this.deviceName,
    required this.createdAt,
    required this.lastSeenAt,
  });

  final String deviceKey;
  final String? deviceName;
  final int? createdAt;
  final int? lastSeenAt;

  factory AuthDeviceInfo.fromJson(Map<String, dynamic> json) {
    return AuthDeviceInfo(
      deviceKey: '${json['device_key'] ?? ''}',
      deviceName: json['device_name']?.toString(),
      createdAt: _jsonInt(json['created_at']),
      lastSeenAt: _jsonInt(json['last_seen_at']),
    );
  }
}

class AuthAccount {
  const AuthAccount({
    required this.accountId,
    required this.deviceId,
    required this.role,
    required this.device,
    required this.identities,
  });

  final String accountId;
  final String deviceId;
  final String role;
  final AuthDeviceInfo? device;
  final List<AuthIdentity> identities;

  bool get hasDiscord =>
      identities.any((identity) => identity.provider == 'discord');
  bool get hasGoogle =>
      identities.any((identity) => identity.provider == 'google');

  String get displayName {
    for (final identity in identities) {
      final label = identity.label.trim();
      if (label.isNotEmpty) {
        return label;
      }
    }
    return accountId;
  }

  factory AuthAccount.fromJson(Map<String, dynamic> json) {
    final rawDevice = json['device'];
    final rawIdentities = json['identities'];
    return AuthAccount(
      accountId: '${json['account_id'] ?? ''}',
      deviceId: '${json['device_id'] ?? ''}',
      role: '${json['role'] ?? 'user'}',
      device: rawDevice is Map
          ? AuthDeviceInfo.fromJson(_stringKeyedMap(rawDevice))
          : null,
      identities: rawIdentities is List
          ? rawIdentities
                .whereType<Map>()
                .map((entry) => AuthIdentity.fromJson(_stringKeyedMap(entry)))
                .toList(growable: false)
          : const [],
    );
  }
}

class AuthService {
  static const _deviceKeyKey = 'auth_device_key';
  static const _tokenKey = 'auth_token';
  static const _accountIdKey = 'auth_account_id';
  static const _deviceIdKey = 'auth_device_id';
  static const _roleKey = 'auth_role';
  static const _providerKey = 'auth_provider';
  static const _displayNameKey = 'auth_display_name';

  AuthSession? _session;
  Future<void>? _googleSignInInitializeFuture;
  bool _googleSignInInitialized = false;

  AuthSession? get session => _session;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureDeviceKey(prefs);
    final token = prefs.getString(_tokenKey)?.trim();
    if (token == null || token.isEmpty) {
      AuthTokenStore.token = null;
      _session = null;
      return;
    }

    AuthTokenStore.token = token;
    _session = AuthSession(
      token: token,
      accountId: prefs.getString(_accountIdKey) ?? '',
      deviceId: prefs.getString(_deviceIdKey) ?? '',
      role: prefs.getString(_roleKey) ?? 'user',
      provider: prefs.getString(_providerKey) ?? '',
      displayName: prefs.getString(_displayNameKey) ?? '',
    );
  }

  Future<bool> startLogin(String provider) async {
    final normalizedProvider = provider.trim().toLowerCase();
    if (normalizedProvider != 'discord' && normalizedProvider != 'google') {
      throw ArgumentError('Unsupported auth provider: $provider');
    }
    if (normalizedProvider == 'google' && _supportsNativeGoogleSignIn) {
      await _startNativeGoogleLogin();
      return true;
    }

    return _startBrowserLogin(normalizedProvider);
  }

  bool get _supportsNativeGoogleSignIn {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> _startNativeGoogleLogin() async {
    await _ensureGoogleSignInInitialized();
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      return _startBrowserGoogleLoginFallback();
    }

    final prefs = await SharedPreferences.getInstance();
    final deviceKey = await _ensureDeviceKey(prefs);
    final account = await GoogleSignIn.instance.authenticate(
      scopeHint: const ['openid', 'email', 'profile'],
    );
    final idToken = account.authentication.idToken?.trim();
    if (idToken == null || idToken.isEmpty) {
      throw Exception('Google Sign-In did not return an ID token.');
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/auth/google-native');
    final response = await http.post(
      uri,
      headers: ApiUserAgent.applyTo(apiJsonContentHeaders),
      body: jsonEncode({
        'id_token': idToken,
        'device_key': deviceKey,
        'device_name': _buildDeviceName(),
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(
        _authErrorMessage(response, 'Google native login failed'),
      );
    }

    final decoded = apiDecodeJsonResponse(response);
    if (decoded is! Map) {
      throw const FormatException(
        'Native login response was not a JSON object.',
      );
    }
    final payload = _stringKeyedMap(decoded);
    await completeCallback(
      token: '${payload['token'] ?? ''}',
      accountId: '${payload['account_id'] ?? ''}',
      deviceId: '${payload['device_id'] ?? ''}',
      role: '${payload['role'] ?? 'user'}',
      provider: '${payload['provider'] ?? 'google'}',
      displayName: '${payload['display_name'] ?? account.displayName ?? ''}',
    );
  }

  Future<void> _startBrowserGoogleLoginFallback() async {
    final opened = await _startBrowserLogin('google');
    if (!opened) {
      throw Exception('Could not open Google login page.');
    }
  }

  Future<bool> _startBrowserLogin(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceKey = await _ensureDeviceKey(prefs);
    final platform = kIsWeb ? 'web' : 'app';
    final redirectUri = kIsWeb
        ? ApiConfig.webAuthRedirectUri
        : ApiConfig.appAuthRedirectUri;
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/auth/$provider-start')
        .replace(
          queryParameters: {
            'platform': platform,
            'redirect': redirectUri,
            'device_key': deviceKey,
          },
        );

    return launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: kIsWeb ? '_self' : null,
    );
  }

  Future<void> _ensureGoogleSignInInitialized() {
    if (_googleSignInInitializeFuture != null) {
      return _googleSignInInitializeFuture!;
    }

    String? emptyToNull(String value) {
      final cleaned = value.trim();
      return cleaned.isEmpty ? null : cleaned;
    }

    final clientId = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
        ? emptyToNull(ApiConfig.googleIosClientId)
        : null;
    final serverClientId = emptyToNull(ApiConfig.googleWebClientId);
    _googleSignInInitializeFuture = GoogleSignIn.instance
        .initialize(clientId: clientId, serverClientId: serverClientId)
        .then((_) {
          _googleSignInInitialized = true;
        });
    return _googleSignInInitializeFuture!;
  }

  Future<void> completeCallback({
    required String token,
    required String accountId,
    required String deviceId,
    required String role,
    required String provider,
    required String displayName,
  }) async {
    final cleanedToken = token.trim();
    if (cleanedToken.isEmpty) {
      throw ArgumentError('Missing auth token.');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, cleanedToken);
    await prefs.setString(_accountIdKey, accountId);
    await prefs.setString(_deviceIdKey, deviceId);
    await prefs.setString(_roleKey, role.isEmpty ? 'user' : role);
    await prefs.setString(_providerKey, provider);
    await prefs.setString(_displayNameKey, displayName);

    AuthTokenStore.token = cleanedToken;
    _session = AuthSession(
      token: cleanedToken,
      accountId: accountId,
      deviceId: deviceId,
      role: role.isEmpty ? 'user' : role,
      provider: provider,
      displayName: displayName,
    );
  }

  Future<AuthAccount> fetchAccount() async {
    final token = _session?.token ?? AuthTokenStore.token;
    if (token == null || token.trim().isEmpty) {
      throw StateError('Authentication required.');
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/auth/me');
    final response = await http.get(
      uri,
      headers: ApiUserAgent.applyTo(apiJsonHeaders),
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AuthTokenExpiredException();
    }
    if (response.statusCode != 200) {
      throw Exception(
        httpStatusMessage(
          response.statusCode,
          'Could not load account (${response.statusCode}).',
        ),
      );
    }

    final decoded = apiDecodeJsonResponse(response);
    if (decoded is! Map) {
      throw const FormatException('Account response was not a JSON object.');
    }
    return AuthAccount.fromJson(_stringKeyedMap(decoded));
  }

  Future<void> logout() async {
    final token = _session?.token ?? AuthTokenStore.token;
    if (token != null && token.isNotEmpty) {
      try {
        final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/auth/logout');
        await http.post(uri, headers: ApiUserAgent.applyTo(apiJsonHeaders));
      } catch (_) {
        // Local logout should still succeed if the network is unavailable.
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_accountIdKey);
    await prefs.remove(_deviceIdKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_providerKey);
    await prefs.remove(_displayNameKey);
    if (_googleSignInInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Google Sign-In state is best-effort; YABus token logout already won.
      }
    }
    AuthTokenStore.token = null;
    _session = null;
  }

  Future<String> _ensureDeviceKey(SharedPreferences prefs) async {
    final existing = prefs.getString(_deviceKeyKey)?.trim();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final deviceKey = _uuidV4();
    await prefs.setString(_deviceKeyKey, deviceKey);
    return deviceKey;
  }

  static String _buildDeviceName() {
    if (kIsWeb) {
      return 'Web (App)';
    }
    try {
      final os = Platform.operatingSystem.toLowerCase();
      final version = Platform.operatingSystemVersion;

      if (os == 'android') {
        final match = RegExp(r'(\d+)').firstMatch(version);
        final major = match?.group(1) ?? '';
        return major.isNotEmpty ? 'Android $major (App)' : 'Android (App)';
      }

      if (os == 'ios') {
        final match = RegExp(r'(\d+)').firstMatch(version);
        final major = match?.group(1) ?? '';
        // Detect iPad via the version string or model hint
        final isIpad =
            version.toLowerCase().contains('ipad') ||
            Platform.environment.containsKey('SIMULATOR_DEVICE_NAME') &&
                (Platform.environment['SIMULATOR_DEVICE_NAME'] ?? '')
                    .toLowerCase()
                    .contains('ipad');
        // On real devices, iPads running iPadOS report screen size > 1024
        // but the most reliable check is the OS version string.
        // UIDevice detection is handled in the native plugin; here we
        // check the version string that Dart exposes.
        final versionLower = version.toLowerCase();
        final effectiveIsIpad = isIpad || versionLower.contains('ipad');
        final osLabel = effectiveIsIpad ? 'iPadOS' : 'iOS';
        return major.isNotEmpty ? '$osLabel $major (App)' : '$osLabel (App)';
      }

      if (os == 'macos') return 'macOS (App)';
      if (os == 'windows') return 'Windows (App)';
      if (os == 'linux') return 'Linux (App)';

      return '${os[0].toUpperCase()}${os.substring(1)} (App)';
    } catch (_) {
      return 'App';
    }
  }

  String _uuidV4() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final chars = bytes.map(hex).join();
    return [
      chars.substring(0, 8),
      chars.substring(8, 12),
      chars.substring(12, 16),
      chars.substring(16, 20),
      chars.substring(20),
    ].join('-');
  }

  static Map<String, String> authPayloadFromFragment(String fragment) {
    if (fragment.trim().isEmpty) {
      return const {};
    }
    try {
      return Uri.splitQueryString(fragment);
    } catch (_) {
      return const {};
    }
  }

  static Map<String, String> authPayloadFromJson(String raw) {
    if (raw.trim().isEmpty) {
      return const {};
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return const {};
    }
    return decoded.map((key, value) => MapEntry('$key', '$value'));
  }
}

Map<String, dynamic> _stringKeyedMap(Map<dynamic, dynamic> source) {
  return source.map((key, value) => MapEntry('$key', value));
}

int? _jsonInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse('$value');
}

String _authErrorMessage(http.Response response, String fallback) {
  return httpErrorMessage(response, '$fallback (${response.statusCode}).');
}
