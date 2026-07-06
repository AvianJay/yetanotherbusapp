import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/announcement_models.dart';
import '../core/announcement_push_service.dart';
import '../core/app_controller.dart';
import '../core/app_analytics.dart';
import '../core/app_routes.dart';
import '../core/app_launch_service.dart';
import '../core/android_home_integration.dart';
import '../core/desktop_discord_presence_service.dart';
import '../core/desktop_discord_route_observer.dart';
import '../core/friendly_error.dart';
import '../core/app_route_observer.dart';
import '../core/ios_widget_integration.dart';
import '../core/models.dart';
import '../core/route_detail_launch_bridge.dart';
import '../core/startup_permission_service.dart';
import '../core/web_update_checker_stub.dart'
    if (dart.library.html) '../core/web_update_checker_web.dart'
    as web_update;

import '../screens/account_screen.dart';
import '../screens/announcement_detail_page.dart';
import '../screens/announcements_page.dart';
import '../screens/database_settings_screen.dart';
import '../screens/feedback_screen.dart';
import '../screens/favorites_screen.dart';
import '../screens/main_transit_shell.dart';
import '../screens/nearby_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/privacy_policy_page.dart';
import '../screens/route_detail_navigation.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/terms_of_service_page.dart';
import '../widgets/app_update_dialog.dart';
import '../widgets/announcement_popup_dialog.dart';
import '../widgets/database_update_dialog.dart';

class BusApp extends StatelessWidget {
  const BusApp({required this.controller, required this.analytics, super.key});

  final AppController controller;
  final AppAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    return AppControllerScope(
      controller: controller,
      child: DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) {
          return AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              return MaterialApp(
                title: 'YetAnotherBusApp',
                debugShowCheckedModeBanner: false,
                themeMode: controller.settings.themeMode,
                theme: _buildTheme(
                  Brightness.light,
                  settings: controller.settings,
                  dynamicColorScheme: lightDynamic,
                ),
                darkTheme: _buildTheme(
                  Brightness.dark,
                  settings: controller.settings,
                  dynamicColorScheme: darkDynamic,
                ),
                navigatorObservers: [
                  appRouteObserver,
                  DesktopDiscordRouteObserver(controller),
                  if (analytics.observer != null) analytics.observer!,
                ],
                builder: (context, child) {
                  final theme = Theme.of(context);
                  final isDark = theme.brightness == Brightness.dark;
                  return AnnotatedRegion<SystemUiOverlayStyle>(
                    value: SystemUiOverlayStyle(
                      statusBarColor: Colors.transparent,
                      statusBarIconBrightness: isDark
                          ? Brightness.light
                          : Brightness.dark,
                      statusBarBrightness: isDark
                          ? Brightness.dark
                          : Brightness.light,
                      systemNavigationBarColor: theme.scaffoldBackgroundColor,
                      systemNavigationBarDividerColor: Colors.transparent,
                      systemNavigationBarIconBrightness: isDark
                          ? Brightness.light
                          : Brightness.dark,
                      systemNavigationBarContrastEnforced: false,
                    ),
                    child: child ?? const SizedBox.shrink(),
                  );
                },
                onGenerateRoute: (settings) =>
                    _buildAppRoute(settings, controller),
                onGenerateInitialRoutes: (initialRoute) =>
                    _buildInitialRoutes(initialRoute, controller),
                onUnknownRoute: (_) => _buildHomeRoute(controller),
              );
            },
          );
        },
      ),
    );
  }

  ThemeData _buildTheme(
    Brightness brightness, {
    required AppSettings settings,
    ColorScheme? dynamicColorScheme,
  }) {
    final useAmoled = settings.useAmoledDark && brightness == Brightness.dark;

    // Color priority: manual seed override > system dynamic color > fallback seed.
    var colorScheme = settings.seedColor != null
        ? ColorScheme.fromSeed(
            seedColor: settings.seedColor!,
            brightness: brightness,
          )
        : (dynamicColorScheme ??
              ColorScheme.fromSeed(
                seedColor: const Color(0xFF0B7285),
                brightness: brightness,
              ));

    if (useAmoled) {
      colorScheme = colorScheme.copyWith(
        surface: Colors.black,
        surfaceDim: Colors.black,
        surfaceBright: const Color(0xFF1A1A1A),
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF0A0A0A),
        surfaceContainer: const Color(0xFF111111),
        surfaceContainerHigh: const Color(0xFF1A1A1A),
        surfaceContainerHighest: const Color(0xFF222222),
      );
    }

    final Color? scaffoldBackground;
    if (brightness == Brightness.light) {
      scaffoldBackground = const Color(0xFFF5F7F2);
    } else if (useAmoled) {
      scaffoldBackground = Colors.black;
    } else {
      scaffoldBackground = null;
    }

    // When background images are active, apply overlayOpacity to
    // Cards, AppBar, and BottomBar so content remains readable.
    final hasBackgroundImage = settings.pageBackgroundImagePaths.isNotEmpty;
    final overlayAlpha = hasBackgroundImage && !useAmoled
        ? settings.overlayOpacity.clamp(0.0, 1.0)
        : 1.0;

    // Use real alpha on component surfaces so the background image remains
    // visible behind AppBar, cards, inputs, and bottom bars.
    final Color overlaySurface = hasBackgroundImage && !useAmoled
        ? colorScheme.surface.withValues(alpha: overlayAlpha)
        : (scaffoldBackground ?? colorScheme.surface);
    final Color overlaySurfaceContainer = hasBackgroundImage && !useAmoled
        ? (useAmoled ? const Color(0xFF0A0A0A) : colorScheme.surfaceContainer)
              .withValues(alpha: overlayAlpha)
        : (useAmoled ? const Color(0xFF0A0A0A) : colorScheme.surface);
    final Color overlayInputFill = hasBackgroundImage && !useAmoled
        ? colorScheme.surface.withValues(alpha: overlayAlpha)
        : (useAmoled ? const Color(0xFF0A0A0A) : colorScheme.surface);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackground,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: hasBackgroundImage && !useAmoled
            ? overlaySurface
            : Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: hasBackgroundImage && !useAmoled
            ? overlaySurfaceContainer
            : (useAmoled ? const Color(0xFF0A0A0A) : colorScheme.surface),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: overlayInputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
      ),
      bottomAppBarTheme: BottomAppBarThemeData(
        color: hasBackgroundImage && !useAmoled ? overlaySurface : null,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}

Route<dynamic> _buildHomeRoute(AppController controller) {
  return MaterialPageRoute<void>(
    settings: const RouteSettings(name: AppRoutes.home),
    builder: (_) => _AppHome(controller: controller),
  );
}

Route<dynamic>? _buildAppRoute(
  RouteSettings settings,
  AppController controller,
) {
  final intent = parseAppRoute(settings.name);
  switch (intent.kind) {
    case AppRouteKind.home:
      return _buildHomeRoute(controller);
    case AppRouteKind.search:
      return MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.search),
        builder: (_) => const SearchScreen(),
      );
    case AppRouteKind.favorites:
      return MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.favorites),
        builder: (_) => const FavoritesScreen(),
      );
    case AppRouteKind.nearby:
      return MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.nearby),
        builder: (_) => const NearbyScreen(),
      );
    case AppRouteKind.settings:
      return MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.settings),
        builder: (_) => const SettingsScreen(),
      );
    case AppRouteKind.account:
      return MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.account),
        builder: (_) => const AccountScreen(),
      );
    case AppRouteKind.feedback:
      return MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.feedback),
        builder: (_) => const FeedbackScreen(),
      );
    case AppRouteKind.databaseSettings:
      return MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.databaseSettings),
        builder: (_) => const DatabaseSettingsScreen(),
      );
    case AppRouteKind.termsOfService:
      return MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.termsOfService),
        builder: (_) => const TermsOfServicePage(),
      );
    case AppRouteKind.privacyPolicy:
      return MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.privacyPolicy),
        builder: (_) => const PrivacyPolicyPage(),
      );
    case AppRouteKind.announcements:
      return MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.announcements),
        builder: (_) => const AnnouncementsPage(),
      );
    case AppRouteKind.announcementDetail:
      final announcementId = intent.announcementId;
      if (announcementId == null || announcementId.isEmpty) {
        return null;
      }
      return MaterialPageRoute<void>(
        settings: RouteSettings(name: intent.location),
        builder: (_) => AnnouncementDetailPage(announcementId: announcementId),
      );
    case AppRouteKind.routeDetail:
      final provider = intent.provider;
      final routeKey = intent.routeKey;
      if (provider == null || routeKey == null) {
        return null;
      }
      return buildRouteDetailRoute(
        routeKey: routeKey,
        provider: provider,
        routeIdHint: intent.routeId,
        initialPathId: intent.pathId,
        initialStopId: intent.stopId,
        initialDestinationPathId: intent.destinationPathId,
        initialDestinationStopId: intent.destinationStopId,
      );
    case AppRouteKind.stopDetail:
    case AppRouteKind.unknown:
      return null;
  }
}

List<Route<dynamic>> _buildInitialRoutes(
  String initialRoute,
  AppController controller,
) {
  final intent = parseAppRoute(initialRoute);
  final homeRoute = _buildHomeRoute(controller);
  if (intent.kind == AppRouteKind.home) {
    return [homeRoute];
  }

  final leafRoute = _buildAppRoute(
    RouteSettings(name: intent.location),
    controller,
  );
  if (leafRoute == null) {
    return [homeRoute];
  }
  return [homeRoute, leafRoute];
}

class _AppHome extends StatefulWidget {
  const _AppHome({required this.controller});

  final AppController controller;

  @override
  State<_AppHome> createState() => _AppHomeState();
}

class _AppHomeState extends State<_AppHome> with WidgetsBindingObserver {
  bool _startupCheckScheduled = false;
  bool _widgetSyncScheduled = false;
  bool _announcementCheckScheduled = false;
  bool _accountSyncPromptScheduled = false;
  bool _showingAnnouncementPopup = false;
  bool _showingAccountSyncPrompt = false;
  AppLaunchAction? _pendingLaunchAction;
  String? _pendingAnnouncementOpenId;
  final Set<String> _deferredAnnouncementPopupIds = <String>{};
  StreamSubscription<AppLaunchAction>? _launchSubscription;
  StreamSubscription<String>? _announcementOpenSubscription;
  StreamSubscription<web_update.WebUpdateCheckResult>? _webUpdateSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_handleControllerChanged);
    unawaited(AndroidHomeIntegration.setApplicationInForeground(true));
    _pendingLaunchAction = AppLaunchService.instance.takePendingInitialAction();
    _pendingAnnouncementOpenId = AnnouncementPushService.instance
        .takePendingAnnouncementId();
    _launchSubscription = AppLaunchService.instance.actions.listen((action) {
      _pendingLaunchAction = action;
      _maybeScheduleLaunchAction();
    });
    _announcementOpenSubscription = AnnouncementPushService
        .instance
        .announcementOpens
        .listen((announcementId) {
          _pendingAnnouncementOpenId = announcementId;
          _maybeScheduleAnnouncementOpen();
        });
    _scheduleIOSWidgetSync();
    _scheduleStartupPermissionPrompt();
    _initWebUpdateChecker();
  }

  void _scheduleStartupPermissionPrompt() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(StartupPermissionService.instance.requestInitialPermissions());
    });
  }

  void _initWebUpdateChecker() {
    if (!kIsWeb) return;
    final checker = web_update.createWebUpdateChecker();
    if (checker == null) return;
    _webUpdateSubscription = checker.onUpdateAvailable.listen((result) {
      if (!mounted) return;
      _showWebUpdateBanner(result);
    });
    checker.startPeriodicCheck();
  }

  void _showWebUpdateBanner(web_update.WebUpdateCheckResult result) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          '有新版本可用（${result.latestVersion}+${result.latestBuildNumber}）',
        ),
        action: SnackBarAction(
          label: '重新載入',
          onPressed: () => web_update.reloadPage(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(AndroidHomeIntegration.setApplicationInForeground(false));
    unawaited(desktopDiscordPresenceService.dispose());
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_handleControllerChanged);
    _launchSubscription?.cancel();
    _announcementOpenSubscription?.cancel();
    _webUpdateSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isForeground = switch (state) {
      AppLifecycleState.resumed => true,
      AppLifecycleState.inactive => true,
      AppLifecycleState.hidden => false,
      AppLifecycleState.paused => false,
      AppLifecycleState.detached => false,
    };
    unawaited(AndroidHomeIntegration.setApplicationInForeground(isForeground));
    if (state == AppLifecycleState.resumed) {
      _syncIOSWidgets();
      widget.controller.scheduleForegroundAccountSync();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeScheduleStartupCheck();
    _maybeScheduleAccountSyncPrompt();
    _maybeScheduleLaunchAction();
    _maybeScheduleAnnouncementOpen();
    _maybeScheduleAnnouncementChecks();
  }

  @override
  void didUpdateWidget(covariant _AppHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    _maybeScheduleStartupCheck();
    _maybeScheduleAccountSyncPrompt();
    _maybeScheduleLaunchAction();
    _maybeScheduleAnnouncementOpen();
    _maybeScheduleAnnouncementChecks();
  }

  void _handleControllerChanged() {
    _maybeScheduleAccountSyncPrompt();
  }

  void _maybeScheduleStartupCheck() {
    if (_startupCheckScheduled || widget.controller.needsOnboarding) {
      return;
    }

    _startupCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runStartupCheck();
    });
  }

  void _maybeScheduleAccountSyncPrompt() {
    if (_accountSyncPromptScheduled ||
        _showingAccountSyncPrompt ||
        !widget.controller.shouldPromptToEnableAccountSync) {
      return;
    }
    _accountSyncPromptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _accountSyncPromptScheduled = false;
      unawaited(_showAccountSyncPromptIfNeeded());
    });
  }

  Future<void> _showAccountSyncPromptIfNeeded() async {
    if (!mounted ||
        _showingAccountSyncPrompt ||
        !widget.controller.shouldPromptToEnableAccountSync) {
      return;
    }
    _showingAccountSyncPrompt = true;
    final enabled = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('啟用雲端同步？'),
          content: const Text(
            '登入後可以自動同步最愛站牌與偏好設定。之後進入 app 時會自動更新，資料變更後也會稍後自動同步。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('先不要'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('開啟同步'),
            ),
          ],
        );
      },
    );
    _showingAccountSyncPrompt = false;
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await widget.controller.setAccountSyncEnabled(enabled == true);
      if (!mounted) {
        return;
      }
      messenger?.showSnackBar(
        SnackBar(
          content: Text(enabled == true ? '已開啟雲端同步。' : '已略過自動同步，你之後仍可手動同步。'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger?.showSnackBar(
        SnackBar(content: Text('設定同步偏好失敗：${friendlyErrorMessage(error)}')),
      );
    }
  }

  void _scheduleIOSWidgetSync() {
    if (_widgetSyncScheduled) {
      return;
    }

    _widgetSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _widgetSyncScheduled = false;
      _syncIOSWidgets();
    });
  }

  void _syncIOSWidgets() {
    unawaited(
      IOSWidgetIntegration.syncFavoriteGroups(
        widget.controller.favoriteGroups,
        waitForBridge: true,
      ),
    );
  }

  void _maybeScheduleLaunchAction() {
    if (_pendingLaunchAction == null || widget.controller.needsOnboarding) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumeLaunchAction();
    });
  }

  void _maybeScheduleAnnouncementOpen() {
    if (_pendingAnnouncementOpenId == null ||
        widget.controller.needsOnboarding) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_consumeAnnouncementOpen());
    });
  }

  void _maybeScheduleAnnouncementChecks() {
    if (_announcementCheckScheduled || widget.controller.needsOnboarding) {
      return;
    }

    _announcementCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _announcementCheckScheduled = false;
      unawaited(_syncAnnouncementsAndMaybeShowPopup());
    });
  }

  Future<void> _syncAnnouncementsAndMaybeShowPopup() async {
    await widget.controller.ensureAnnouncementsLoaded();
    if (!mounted) {
      return;
    }
    await _maybeShowAnnouncementPopup();
  }

  Future<void> _maybeShowAnnouncementPopup() async {
    if (!mounted ||
        _showingAnnouncementPopup ||
        widget.controller.needsOnboarding) {
      return;
    }

    final announcement = widget.controller.nextPendingAnnouncementPopup(
      sessionDeferredIds: _deferredAnnouncementPopupIds,
    );
    if (announcement == null) {
      return;
    }

    _showingAnnouncementPopup = true;
    final result = await showAnnouncementPopupDialog(
      context,
      announcement: announcement,
    );
    await widget.controller.markAnnouncementPopupShown(announcement);
    if (!mounted) {
      _showingAnnouncementPopup = false;
      return;
    }

    switch (result) {
      case AnnouncementPopupResult.dismissForever:
        await widget.controller.dismissAnnouncementPopup(announcement);
      case AnnouncementPopupResult.viewDetails:
        await Navigator.of(
          context,
        ).pushNamed(AppRoutes.announcementDetailPath(announcement.id));
      case AnnouncementPopupResult.later:
        if (announcement.behavior.popup == AnnouncementRepeatBehavior.forever) {
          _deferredAnnouncementPopupIds.add(announcement.id);
        }
    }

    _showingAnnouncementPopup = false;
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_maybeShowAnnouncementPopup());
      });
    }
  }

  Future<void> _consumeAnnouncementOpen() async {
    final announcementId = _pendingAnnouncementOpenId;
    if (!mounted || announcementId == null || announcementId.isEmpty) {
      return;
    }
    _pendingAnnouncementOpenId = null;

    await widget.controller.refreshAnnouncements(force: true);
    if (!mounted) {
      return;
    }
    await Navigator.of(
      context,
    ).pushNamed(AppRoutes.announcementDetailPath(announcementId));
  }

  Future<void> _consumeLaunchAction() async {
    final action = _pendingLaunchAction;
    if (!mounted || action == null) {
      return;
    }
    _pendingLaunchAction = null;

    if (action.target == AppLaunchTarget.authCallback) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      try {
        await widget.controller.completeAuthCallback(action);
        if (!mounted) {
          return;
        }
        messenger?.showSnackBar(const SnackBar(content: Text('登入成功。')));
      } catch (error) {
        if (!mounted) {
          return;
        }
        messenger?.showSnackBar(
          SnackBar(content: Text('登入失敗：${friendlyErrorMessage(error)}')),
        );
      }
      return;
    }

    final navigator = Navigator.of(context);

    if (action.target == AppLaunchTarget.routeDetail) {
      final didHandleInPlace = await RouteDetailLaunchBridge.instance.tryHandle(
        action,
      );
      if (didHandleInPlace) {
        return;
      }
    }

    switch (action.target) {
      case AppLaunchTarget.routeDetail:
        final provider = action.provider;
        final routeKey = action.routeKey;
        if (provider == null || routeKey == null) {
          return;
        }
        await navigator.push(
          buildRouteDetailRoute(
            routeKey: routeKey,
            provider: provider,
            routeIdHint: action.routeId,
            initialPathId: action.pathId,
            initialStopId: action.stopId,
            initialDestinationPathId: action.destinationPathId,
            initialDestinationStopId: action.destinationStopId,
          ),
        );
        return;
      case AppLaunchTarget.favoritesGroup:
        await navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => FavoritesScreen(initialGroupName: action.groupName),
          ),
        );
        return;
      case AppLaunchTarget.internalLocation:
        final location = action.location;
        if (location == null || location.isEmpty) {
          return;
        }
        final intent = parseAppRoute(location);
        if (intent.kind == AppRouteKind.unknown ||
            intent.kind == AppRouteKind.stopDetail) {
          return;
        }
        if (intent.kind == AppRouteKind.home) {
          navigator.popUntil((route) => route.isFirst);
          return;
        }
        await navigator.pushNamed(intent.location);
        return;
      case AppLaunchTarget.authCallback:
        return;
    }
  }

  Future<void> _runStartupCheck() async {
    try {
      final databasePlan = await widget.controller
          .maybeCheckForDatabaseUpdatesOnLaunch();
      if (mounted && databasePlan != null && databasePlan.hasUpdates) {
        if (databasePlan.shouldAutoDownload) {
          final providers = databasePlan.updates.keys.toList();
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.showSnackBar(const SnackBar(content: Text('正在更新資料庫...')));
          try {
            await widget.controller.downloadProviderDatabases(providers);
            if (!mounted) {
              return;
            }
            messenger?.showSnackBar(
              SnackBar(
                content: Text(
                  '資料庫已更新：${providers.map((provider) => provider.label).join('、')}',
                ),
              ),
            );
          } catch (error) {
            if (!mounted) {
              return;
            }
            messenger?.showSnackBar(
              SnackBar(content: Text('自動更新資料庫失敗：${friendlyErrorMessage(error)}')),
            );
          }
        } else if (databasePlan.shouldShowPopup) {
          final shouldUpdate = await showDatabaseUpdateDialog(
            context,
            updates: databasePlan.updates,
          );
          if (shouldUpdate && mounted) {
            try {
              await widget.controller.downloadProviderDatabases(
                databasePlan.updates.keys,
              );
              if (!mounted) {
                return;
              }
              ScaffoldMessenger.maybeOf(
                context,
              )?.showSnackBar(const SnackBar(content: Text('資料庫更新完成。')));
            } catch (error) {
              if (!mounted) {
                return;
              }
              ScaffoldMessenger.maybeOf(
                context,
              )?.showSnackBar(SnackBar(content: Text('資料庫更新失敗：${friendlyErrorMessage(error)}')));
            }
          }
        } else if (databasePlan.shouldShowNotification) {
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.showSnackBar(
            SnackBar(
              content: Text(
                '資料庫有新版本：${databasePlan.updates.keys.map((provider) => provider.label).join('、')}',
              ),
              action: SnackBarAction(
                label: '更新',
                onPressed: () async {
                  final shouldUpdate = await showDatabaseUpdateDialog(
                    context,
                    updates: databasePlan.updates,
                  );
                  if (!mounted || !shouldUpdate) {
                    return;
                  }
                  try {
                    await widget.controller.downloadProviderDatabases(
                      databasePlan.updates.keys,
                    );
                    if (!mounted) {
                      return;
                    }
                    ScaffoldMessenger.maybeOf(
                      context,
                    )?.showSnackBar(const SnackBar(content: Text('資料庫更新完成。')));
                  } catch (error) {
                    if (!mounted) {
                      return;
                    }
                    ScaffoldMessenger.maybeOf(
                      context,
                    )?.showSnackBar(SnackBar(content: Text('資料庫更新失敗：${friendlyErrorMessage(error)}')));
                  }
                },
              ),
            ),
          );
        } else if (databasePlan.deferredReason case final reason?) {
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(SnackBar(content: Text(reason)));
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(
          SnackBar(content: Text('檢查資料庫更新失敗：${friendlyErrorMessage(error)}')),
        );
      }
    }

    final result = await widget.controller.maybeCheckForAppUpdateOnLaunch();
    if (!mounted || result == null || !result.hasUpdate) {
      return;
    }

    switch (widget.controller.settings.appUpdateCheckMode) {
      case AppUpdateCheckMode.off:
        return;
      case AppUpdateCheckMode.notify:
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(
          SnackBar(
            content: Text(result.message),
            action: SnackBarAction(
              label: '查看',
              onPressed: () {
                showAppUpdateDialog(
                  context,
                  controller: widget.controller,
                  result: result,
                );
              },
            ),
          ),
        );
      case AppUpdateCheckMode.popup:
        await showAppUpdateDialog(
          context,
          controller: widget.controller,
          result: result,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.controller.needsOnboarding
        ? const OnboardingScreen()
        : const MainTransitShell();
  }
}

class AppControllerScope extends InheritedNotifier<AppController> {
  const AppControllerScope({
    required AppController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppControllerScope>();
    assert(scope != null, 'AppControllerScope not found in widget tree.');
    return scope!.notifier!;
  }

  static AppController read(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<AppControllerScope>();
    final scope = element?.widget as AppControllerScope?;
    assert(scope != null, 'AppControllerScope not found in widget tree.');
    return scope!.notifier!;
  }
}
