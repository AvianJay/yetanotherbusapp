import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StartupPermissionService {
  StartupPermissionService._();

  static final instance = StartupPermissionService._();

  static const _photosPromptAttemptedKey =
      'startup_permissions.photos_prompt_attempted';
  static const _notificationsPromptAttemptedKey =
      'startup_permissions.notifications_prompt_attempted';

  bool _requestInProgress = false;

  Future<void> requestInitialPermissions() async {
    if (kIsWeb || !Platform.isIOS || _requestInProgress) {
      return;
    }

    _requestInProgress = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final requestedPhotos = await _requestIfNeeded(
        prefs: prefs,
        preferenceKey: _photosPromptAttemptedKey,
        permission: Permission.photos,
        isSatisfied: _photosPermissionSatisfied,
      );
      if (requestedPhotos) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
      await _requestIfNeeded(
        prefs: prefs,
        preferenceKey: _notificationsPromptAttemptedKey,
        permission: Permission.notification,
        isSatisfied: _notificationPermissionSatisfied,
      );
    } finally {
      _requestInProgress = false;
    }
  }

  Future<bool> _requestIfNeeded({
    required SharedPreferences prefs,
    required String preferenceKey,
    required Permission permission,
    required bool Function(PermissionStatus status) isSatisfied,
  }) async {
    if (prefs.getBool(preferenceKey) == true) {
      return false;
    }

    PermissionStatus status;
    try {
      status = await permission.status;
    } on PlatformException {
      return false;
    }

    if (isSatisfied(status) ||
        status.isPermanentlyDenied ||
        status.isRestricted) {
      await prefs.setBool(preferenceKey, true);
      return false;
    }

    if (!status.isDenied) {
      return false;
    }

    try {
      await permission.request();
      await prefs.setBool(preferenceKey, true);
      return true;
    } on PlatformException {
      return false;
    }
  }

  bool _photosPermissionSatisfied(PermissionStatus status) {
    return status.isGranted || status.isLimited;
  }

  bool _notificationPermissionSatisfied(PermissionStatus status) {
    return status.isGranted || status.isProvisional;
  }
}
