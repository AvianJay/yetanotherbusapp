import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app_controller.dart';
import 'desktop_discord_presence_service.dart';

class DesktopDiscordRouteObserver extends NavigatorObserver {
  DesktopDiscordRouteObserver(this.controller);

  final AppController controller;

  static const _routeLabels = <String, String>{
    'settings': '設定',
    'personalization': '個人化',
    'search': '搜尋路線',
    'favorites': '我的最愛',
    'favorite_groups': '最愛群組',
    'nearby': '附近站牌',
    'database_settings': '資料庫設定',
    'route_detail': '查看路線',
  };

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _syncNamedRoute(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _syncNamedRoute(previousRoute, fallbackToHome: true);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _syncNamedRoute(newRoute);
  }

  void _syncNamedRoute(Route<dynamic>? route, {bool fallbackToHome = false}) {
    final routeName = route?.settings.name;
    final screenLabel = routeName == null ? null : _routeLabels[routeName];
    if (screenLabel != null) {
      unawaited(
        desktopDiscordPresenceService.updateScreen(
          settings: controller.settings,
          screenLabel: screenLabel,
          provider: controller.settings.provider,
        ),
      );
      return;
    }
    if (!fallbackToHome) {
      return;
    }
    unawaited(
      desktopDiscordPresenceService.updateScreen(
        settings: controller.settings,
        screenLabel: '公車首頁',
        provider: controller.settings.provider,
      ),
    );
  }
}
