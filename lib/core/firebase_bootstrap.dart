import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_http.dart';
import 'api_config.dart';
import 'api_user_agent.dart';

class FirebaseBootstrapState {
  const FirebaseBootstrapState({
    required this.firebaseReady,
    required this.messagingReady,
    required this.appBaseUrl,
    this.webVapidKey,
  });

  final bool firebaseReady;
  final bool messagingReady;
  final String appBaseUrl;
  final String? webVapidKey;
}

class FirebaseBootstrap {
  FirebaseBootstrap._();

  static const _defaultWebMessagingConfig = _WebMessagingConfig(
    appBaseUrl: 'https://busapp.avianjay.sbs',
    apiKey: 'AIzaSyAMzgL6WxQarMcuXYrrqOHZsxUFVytkcuM',
    authDomain: 'yabus-111c1.firebaseapp.com',
    projectId: 'yabus-111c1',
    storageBucket: 'yabus-111c1.firebasestorage.app',
    messagingSenderId: '1011547280811',
    appId: '1:1011547280811:web:7e1e0c0a1baa160df7aeee',
    measurementId: 'G-RB7WBXXRQN',
    vapidKey: '',
  );

  static Future<FirebaseBootstrapState>? _initializationFuture;

  static Future<FirebaseBootstrapState> initialize() {
    return _initializationFuture ??= _initializeInternal();
  }

  static Future<FirebaseBootstrapState> _initializeInternal() async {
    if (!kIsWeb &&
        defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return const FirebaseBootstrapState(
        firebaseReady: false,
        messagingReady: false,
        appBaseUrl: 'https://busapp.avianjay.sbs',
      );
    }

    if (!kIsWeb) {
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp();
        }
        return const FirebaseBootstrapState(
          firebaseReady: true,
          messagingReady: true,
          appBaseUrl: 'https://busapp.avianjay.sbs',
        );
      } catch (_) {
        return const FirebaseBootstrapState(
          firebaseReady: false,
          messagingReady: false,
          appBaseUrl: 'https://busapp.avianjay.sbs',
        );
      }
    }

    final webConfig = await _loadWebMessagingConfig();

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: webConfig.apiKey,
            appId: webConfig.appId,
            messagingSenderId: webConfig.messagingSenderId,
            projectId: webConfig.projectId,
            authDomain: webConfig.authDomain,
            storageBucket: webConfig.storageBucket,
            measurementId: webConfig.measurementId,
          ),
        );
      }
      return FirebaseBootstrapState(
        firebaseReady: true,
        messagingReady: webConfig.vapidKey.isNotEmpty,
        appBaseUrl: webConfig.appBaseUrl,
        webVapidKey: webConfig.vapidKey.isEmpty ? null : webConfig.vapidKey,
      );
    } catch (_) {
      return FirebaseBootstrapState(
        firebaseReady: false,
        messagingReady: false,
        appBaseUrl: webConfig.appBaseUrl,
        webVapidKey: webConfig.vapidKey.isEmpty ? null : webConfig.vapidKey,
      );
    }
  }

  static Future<_WebMessagingConfig> _loadWebMessagingConfig() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/push/public-config'),
        headers: ApiUserAgent.applyTo(apiJsonHeaders),
      );
      if (response.statusCode != 200) {
        return _defaultWebMessagingConfig;
      }

      final decoded = apiDecodeJsonResponse(response);
      if (decoded is! Map) {
        return _defaultWebMessagingConfig;
      }
      final payload = decoded.map((key, value) => MapEntry('$key', value));
      final rawWeb = payload['web'];
      final webEnabled = payload['web_enabled'] != false;
      final web = rawWeb is Map
          ? rawWeb.map((key, value) => MapEntry('$key', '$value'))
          : const <String, String>{};
      return _defaultWebMessagingConfig.copyWith(
        appBaseUrl: _mergedString(
          payload['app_base_url'],
          _defaultWebMessagingConfig.appBaseUrl,
        ),
        apiKey: _mergedString(web['apiKey'], _defaultWebMessagingConfig.apiKey),
        authDomain: _mergedString(
          web['authDomain'],
          _defaultWebMessagingConfig.authDomain,
        ),
        projectId: _mergedString(
          web['projectId'],
          _defaultWebMessagingConfig.projectId,
        ),
        storageBucket: _mergedString(
          web['storageBucket'],
          _defaultWebMessagingConfig.storageBucket,
        ),
        messagingSenderId: _mergedString(
          web['messagingSenderId'],
          _defaultWebMessagingConfig.messagingSenderId,
        ),
        appId: _mergedString(web['appId'], _defaultWebMessagingConfig.appId),
        measurementId: _mergedString(
          web['measurementId'],
          _defaultWebMessagingConfig.measurementId,
        ),
        vapidKey: webEnabled ? _mergedString(web['vapidKey'], '') : '',
      );
    } catch (_) {
      return _defaultWebMessagingConfig;
    }
  }

  static String _mergedString(Object? value, String fallback) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? fallback : text;
  }
}

class _WebMessagingConfig {
  const _WebMessagingConfig({
    required this.appBaseUrl,
    required this.apiKey,
    required this.authDomain,
    required this.projectId,
    required this.storageBucket,
    required this.messagingSenderId,
    required this.appId,
    required this.measurementId,
    required this.vapidKey,
  });

  final String appBaseUrl;
  final String apiKey;
  final String authDomain;
  final String projectId;
  final String storageBucket;
  final String messagingSenderId;
  final String appId;
  final String measurementId;
  final String vapidKey;

  _WebMessagingConfig copyWith({
    String? appBaseUrl,
    String? apiKey,
    String? authDomain,
    String? projectId,
    String? storageBucket,
    String? messagingSenderId,
    String? appId,
    String? measurementId,
    String? vapidKey,
  }) {
    return _WebMessagingConfig(
      appBaseUrl: appBaseUrl ?? this.appBaseUrl,
      apiKey: apiKey ?? this.apiKey,
      authDomain: authDomain ?? this.authDomain,
      projectId: projectId ?? this.projectId,
      storageBucket: storageBucket ?? this.storageBucket,
      messagingSenderId: messagingSenderId ?? this.messagingSenderId,
      appId: appId ?? this.appId,
      measurementId: measurementId ?? this.measurementId,
      vapidKey: vapidKey ?? this.vapidKey,
    );
  }
}
