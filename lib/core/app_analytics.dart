import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class AppAnalytics {
  AppAnalytics._(this.analytics)
    : observer = analytics == null
          ? null
          : FirebaseAnalyticsObserver(analytics: analytics);

  final FirebaseAnalytics? analytics;
  final FirebaseAnalyticsObserver? observer;

  bool get isEnabled => analytics != null;

  static Future<AppAnalytics> initialize() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return AppAnalytics._(null);
    }

    try {
      await Firebase.initializeApp();
      final analytics = FirebaseAnalytics.instance;
      await analytics.setAnalyticsCollectionEnabled(true);
      await analytics.logAppOpen();
      return AppAnalytics._(analytics);
    } catch (_) {
      return AppAnalytics._(null);
    }
  }
}
