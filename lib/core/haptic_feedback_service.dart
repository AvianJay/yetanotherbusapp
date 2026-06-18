import 'package:flutter/services.dart';

/// Centralized gate for tactile feedback so the in-app "震動回饋" switch can
/// enable or disable every haptic call from a single place.
class AppHaptics {
  AppHaptics._();

  static bool _enabled = true;

  /// Whether haptic feedback is currently allowed.
  static bool get enabled => _enabled;

  /// Updates the gate from the persisted user setting.
  static void setEnabled(bool value) {
    _enabled = value;
  }

  /// Light tap used for confirmations and successful actions.
  static Future<void> lightImpact() {
    if (!_enabled) {
      return Future<void>.value();
    }
    return HapticFeedback.lightImpact();
  }

  /// Subtle click used for selection changes.
  static Future<void> selectionClick() {
    if (!_enabled) {
      return Future<void>.value();
    }
    return HapticFeedback.selectionClick();
  }
}
