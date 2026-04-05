import 'dart:async';

import 'package:flutter/services.dart';

import 'models.dart';

enum AppLaunchTarget { routeDetail, favoritesGroup }

class AppLaunchAction {
  const AppLaunchAction({
    required this.target,
    this.provider,
    this.routeKey,
    this.pathId,
    this.stopId,
    this.groupName,
  });

  factory AppLaunchAction.fromMap(Map<Object?, Object?> map) {
    final targetName = (map['target'] as String? ?? '').trim();
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
      groupName: map['groupName'] as String?,
    );
  }

  final AppLaunchTarget target;
  final BusProvider? provider;
  final int? routeKey;
  final int? pathId;
  final int? stopId;
  final String? groupName;
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

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLaunchAction' && call.arguments is Map) {
        final action = AppLaunchAction.fromMap(
          Map<Object?, Object?>.from(call.arguments as Map),
        );
        _actions.add(action);
      }
    });

    try {
      final payload = await _channel.invokeMethod<Map<Object?, Object?>>(
        'takeInitialLaunchAction',
      );
      if (payload != null) {
        _initialAction = AppLaunchAction.fromMap(payload);
      }
    } on MissingPluginException {
      _initialAction = null;
    } on PlatformException {
      _initialAction = null;
    }
  }
}
