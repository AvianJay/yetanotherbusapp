import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdService {
  AdService._();

  static final AdService instance = AdService._();

  static const String bannerAdUnitId =
      'ca-app-pub-4517104314307871/8300540302';

  static const String _adToggleLockedKey = 'ad_toggle_locked';

  bool _initialized = false;

  /// Whether the ad SDK is initialized and the platform supports ads.
  bool get isAvailable =>
      _initialized &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await MobileAds.instance.initialize();
      _initialized = true;
    } catch (_) {
      // Silently fail – ads are non-critical.
    }
  }

  /// Returns `true` if the ad toggle has been permanently locked.
  Future<bool> isAdToggleLocked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_adToggleLockedKey) ?? false;
  }

  /// Permanently lock the ad toggle. Can only be reset by reinstalling the app.
  Future<void> lockAdToggle() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_adToggleLockedKey, true);
  }
}
