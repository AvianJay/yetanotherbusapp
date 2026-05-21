import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
    if (webConfig == null) {
      return const FirebaseBootstrapState(
        firebaseReady: false,
        messagingReady: false,
        appBaseUrl: 'https://busapp.avianjay.sbs',
      );
    }

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

  static Future<_WebMessagingConfig?> _loadWebMessagingConfig() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/push/public-config'),
        headers: ApiUserAgent.applyTo(const {
          'Accept': 'application/json',
          'Accept-Encoding': 'gzip',
        }),
      );
      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        return null;
      }
      final payload = decoded.map((key, value) => MapEntry('$key', value));
      final rawWeb = payload['web'];
      if (rawWeb is! Map) {
        return null;
      }
      final web = rawWeb.map((key, value) => MapEntry('$key', '$value'));
      return _WebMessagingConfig(
        appBaseUrl:
            '${payload['app_base_url'] ?? 'https://busapp.avianjay.sbs'}',
        apiKey: web['apiKey'] ?? '',
        authDomain: web['authDomain'] ?? '',
        projectId: web['projectId'] ?? '',
        storageBucket: web['storageBucket'] ?? '',
        messagingSenderId: web['messagingSenderId'] ?? '',
        appId: web['appId'] ?? '',
        measurementId: web['measurementId'] ?? '',
        vapidKey: web['vapidKey'] ?? '',
      );
    } catch (_) {
      return null;
    }
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
}
