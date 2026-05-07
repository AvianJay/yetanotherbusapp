import 'dart:async';

import 'package:flutter/services.dart';

import 'models.dart';
import 'web_auth_callback_stub.dart'
    if (dart.library.html) 'web_auth_callback_web.dart'
    as web_auth;

enum AppLaunchTarget { routeDetail, favoritesGroup, authCallback }

class AppLaunchAction {
  const AppLaunchAction({
    required this.target,
    this.provider,
    this.routeKey,
    this.pathId,
    this.stopId,
    this.destinationPathId,
    this.destinationStopId,
    this.groupName,
    this.authToken,
    this.authAccountId,
    this.authDeviceId,
    this.authRole,
    this.authProvider,
    this.authDisplayName,
    this.authError,
  });

  factory AppLaunchAction.fromMap(Map<Object?, Object?> map) {
    final targetName = (map['target'] as String? ?? '').trim();
    if (targetName == 'auth_callback') {
      return AppLaunchAction(
        target: AppLaunchTarget.authCallback,
        authToken: map['token']?.toString(),
        authAccountId: map['account_id']?.toString(),
        authDeviceId: map['device_id']?.toString(),
        authRole: map['role']?.toString(),
        authProvider: map['provider']?.toString(),
        authDisplayName: map['display_name']?.toString(),
        authError: map['error']?.toString(),
      );
    }

    return AppLaunchAction(
      target: targetName == 'favorites_group'
          ? AppLaunchTarget.favoritesGroup
          : AppLaunchTarget.routeDetail,
      provider: map['provider'] == null
          ? null
          : busProviderFromString(map['provider'] as String),
      routeKey: (map['routeKey'] as num?)?.toInt(),
      pathId: (map['pathId'] as num?)?.toInt(),
      stopId: (map['stopId'] as num?)?.toInt(),
      destinationPathId: (map['destinationPathId'] as num?)?.toInt(),
      destinationStopId: (map['destinationStopId'] as num?)?.toInt(),
      groupName: map['groupName'] as String?,
    );
  }

  final AppLaunchTarget target;
  final BusProvider? provider;
  final int? routeKey;
  final int? pathId;
  final int? stopId;
  final int? destinationPathId;
  final int? destinationStopId;
  final String? groupName;
  final String? authToken;
  final String? authAccountId;
  final String? authDeviceId;
  final String? authRole;
  final String? authProvider;
  final String? authDisplayName;
  final String? authError;
}

class AppLaunchService {
  AppLaunchService._();

  static final instance = AppLaunchService._();
  static const _channel = MethodChannel(
    'tw.avianjay.taiwanbus.flutter/app_launch',
  );

  final StreamController<AppLaunchAction> _actions =
      StreamController<AppLaunchAction>.broadcast();
  AppLaunchAction? _initialAction;
  bool _initialized = false;

  Stream<AppLaunchAction> get actions => _actions.stream;
  AppLaunchAction? takePendingInitialAction() {
    final action = _initialAction;
    _initialAction = null;
    return action;
  }

  Future<void> initialize({List<String> initialArguments = const []}) async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    _initialAction =
        _authActionFromArguments(initialArguments) ??
        _authActionFromWebCallback();

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLaunchAction' && call.arguments is Map) {
        final action = AppLaunchAction.fromMap(
          Map<Object?, Object?>.from(call.arguments as Map),
        );
        _actions.add(action);
      }
    });

    try {
      await _channel.invokeMethod<void>('setLaunchListenerReady');
    } on MissingPluginException {
      // Native launch bridges are optional on platforms without deep links.
    } on PlatformException {
      // Ignore setup failures so app startup continues.
    }

    try {
      final payload = await _channel.invokeMethod<Map<Object?, Object?>>(
        'takeInitialLaunchAction',
      );
      if (payload != null && _initialAction == null) {
        _initialAction = AppLaunchAction.fromMap(payload);
      }
    } on MissingPluginException {
      // Keep any auth callback already recovered from web or process args.
    } on PlatformException {
      // Keep any auth callback already recovered from web or process args.
    }
  }

  AppLaunchAction? _authActionFromWebCallback() {
    final payload = web_auth.takeWebAuthCallbackPayload();
    if (payload == null) {
      return null;
    }
    return AppLaunchAction.fromMap(Map<Object?, Object?>.from(payload));
  }

  AppLaunchAction? _authActionFromArguments(List<String> arguments) {
    for (final argument in arguments) {
      final action = _authActionFromUri(argument);
      if (action != null) {
        return action;
      }
    }
    return null;
  }

  AppLaunchAction? _authActionFromUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'yabus') {
      return null;
    }
    if (uri.host.toLowerCase() != 'auth-callback') {
      return null;
    }
    final params = <String, String>{...uri.queryParameters};
    if (uri.fragment.isNotEmpty) {
      try {
        params.addAll(Uri.splitQueryString(uri.fragment));
      } catch (_) {
        return null;
      }
    }
    return AppLaunchAction.fromMap(
      Map<Object?, Object?>.from({'target': 'auth_callback', ...params}),
    );
  }
}
