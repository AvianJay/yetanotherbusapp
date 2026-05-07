import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_config.dart';
import 'api_user_agent.dart';
import 'auth_token_store.dart';

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

class AuthService {
  static const _deviceKeyKey = 'auth_device_key';
  static const _tokenKey = 'auth_token';
  static const _accountIdKey = 'auth_account_id';
  static const _deviceIdKey = 'auth_device_id';
  static const _roleKey = 'auth_role';
  static const _providerKey = 'auth_provider';
  static const _displayNameKey = 'auth_display_name';

  AuthSession? _session;

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

    final prefs = await SharedPreferences.getInstance();
    final deviceKey = await _ensureDeviceKey(prefs);
    final platform = kIsWeb ? 'web' : 'app';
    final redirectUri = kIsWeb
        ? ApiConfig.webAuthRedirectUri
        : ApiConfig.appAuthRedirectUri;
    final uri =
        Uri.parse(
          '${ApiConfig.baseUrl}/api/v1/auth/$normalizedProvider-start',
        ).replace(
          queryParameters: {
            'platform': platform,
            'redirect': redirectUri,
            'device_key': deviceKey,
          },
        );

    return launchUrl(uri, mode: LaunchMode.externalApplication);
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

  Future<void> logout() async {
    final token = _session?.token ?? AuthTokenStore.token;
    if (token != null && token.isNotEmpty) {
      try {
        final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/auth/logout');
        await http.post(
          uri,
          headers: ApiUserAgent.applyTo(const {
            'Accept': 'application/json',
            'Accept-Encoding': 'gzip',
          }),
        );
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
