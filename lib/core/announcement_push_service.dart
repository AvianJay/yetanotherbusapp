import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_user_agent.dart';
import 'app_routes.dart';
import 'firebase_bootstrap.dart';
import 'foreground_web_notification.dart';

class AnnouncementPushService {
  AnnouncementPushService._();

  static final instance = AnnouncementPushService._();

  static const _channelId = 'announcement_push';
  static const _channelName = 'Announcements';
  static const _channelDescription = 'YABus announcement notifications';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final StreamController<String> _announcementOpens =
      StreamController<String>.broadcast();
  Future<void>? _initializationFuture;

  bool _localNotificationsReady = false;
  String? _pendingInitialAnnouncementId;
  String? _webVapidKey;

  Stream<String> get announcementOpens => _announcementOpens.stream;

  String? takePendingAnnouncementId() {
    final id = _pendingInitialAnnouncementId;
    _pendingInitialAnnouncementId = null;
    return id;
  }

  Future<void> initialize() {
    return _initializationFuture ??= _initializeInternal();
  }

  Future<void> _initializeInternal() async {
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final bootstrap = await FirebaseBootstrap.initialize();
    _webVapidKey = bootstrap.webVapidKey;
    if (!bootstrap.firebaseReady || !bootstrap.messagingReady) {
      return;
    }

    if (kIsWeb) {
      final supported = await FirebaseMessaging.instance.isSupported();
      if (!supported) {
        return;
      }
    }

    await _initializeLocalNotifications();
    await _requestPermissionAndSyncToken();

    FirebaseMessaging.onMessage.listen((message) {
      unawaited(_handleForegroundMessage(message));
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _queueAnnouncementOpen(_announcementIdFromMessage(message));
    });
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      unawaited(_registerToken(token));
    });

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _queueAnnouncementOpen(
        _announcementIdFromMessage(initialMessage),
        storeAsPending: true,
      );
    }
  }

  Future<void> _initializeLocalNotifications() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    if (_localNotificationsReady) {
      return;
    }

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        _queueAnnouncementOpen((response.payload ?? '').trim());
      },
    );
    final androidImplementation = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImplementation?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );
    _localNotificationsReady = true;
  }

  Future<void> _requestPermissionAndSyncToken() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return;
    }
    if (kIsWeb && (_webVapidKey == null || _webVapidKey!.trim().isEmpty)) {
      return;
    }

    final token = await FirebaseMessaging.instance.getToken(
      vapidKey: kIsWeb ? _webVapidKey : null,
    );
    if (token == null || token.trim().isEmpty) {
      return;
    }
    await _registerToken(token);
  }

  Future<void> _registerToken(String token) async {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/push/fcm-token'),
        headers: ApiUserAgent.applyTo(const {
          'Accept': 'application/json',
          'Accept-Encoding': 'gzip',
          'Content-Type': 'application/json',
        }),
        body: jsonEncode({
          'token': normalizedToken,
          'platform': kIsWeb ? 'web' : 'android',
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return;
      }
    } catch (_) {
      return;
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final announcementId = _announcementIdFromMessage(message);
    if (announcementId == null) {
      return;
    }
    final title = _messageTitle(message);
    final body = _messageBody(message);
    final routePath = AppRoutes.announcementDetailPath(announcementId);

    if (kIsWeb) {
      await showForegroundWebNotification(
        title: title,
        body: body,
        routePath: routePath,
      );
      return;
    }

    if (!_localNotificationsReady) {
      return;
    }
    await _localNotifications.show(
      announcementId.hashCode & 0x7fffffff,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: announcementId,
    );
  }

  void _queueAnnouncementOpen(
    String? announcementId, {
    bool storeAsPending = false,
  }) {
    final normalizedId = (announcementId ?? '').trim();
    if (normalizedId.isEmpty) {
      return;
    }
    if (storeAsPending) {
      _pendingInitialAnnouncementId = normalizedId;
      if (!_announcementOpens.hasListener) {
        return;
      }
      _pendingInitialAnnouncementId = null;
    }
    _announcementOpens.add(normalizedId);
  }

  String? _announcementIdFromMessage(RemoteMessage message) {
    final announcementId = '${message.data['announcement_id'] ?? ''}'.trim();
    if (announcementId.isEmpty) {
      return null;
    }
    return announcementId;
  }

  String _messageTitle(RemoteMessage message) {
    final title = message.notification?.title?.trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }
    final dataTitle = '${message.data['title'] ?? ''}'.trim();
    return dataTitle.isNotEmpty ? dataTitle : 'YABus';
  }

  String _messageBody(RemoteMessage message) {
    final body = message.notification?.body?.trim();
    if (body != null && body.isNotEmpty) {
      return body;
    }
    final dataBody = '${message.data['content'] ?? ''}'.trim();
    return dataBody;
  }
}
