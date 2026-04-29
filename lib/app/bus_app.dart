import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/app_analytics.dart';
import '../core/app_launch_service.dart';
import '../core/android_home_integration.dart';
import '../core/ios_widget_integration.dart';
import '../core/models.dart';
import '../core/route_detail_launch_bridge.dart';
import '../screens/favorites_screen.dart';
import '../screens/main_transit_shell.dart';
import '../screens/onboarding_screen.dart';
import '../screens/route_detail_screen.dart';
import '../widgets/app_update_dialog.dart';
import '../widgets/database_update_dialog.dart';

class BusApp extends StatelessWidget {
  const BusApp({required this.controller, required this.analytics, super.key});

  final AppController controller;
  final AppAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    return AppControllerScope(
      controller: controller,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return MaterialApp(
            title: 'YetAnotherBusApp',
            debugShowCheckedModeBanner: false,
            themeMode: controller.settings.themeMode,
            theme: _buildTheme(
              Brightness.light,
              settings: controller.settings,
            ),
            darkTheme: _buildTheme(
              Brightness.dark,
              settings: controller.settings,
            ),
            navigatorObservers: [
              if (analytics.observer != null) analytics.observer!,
            ],
            home: _AppHome(controller: controller),
          );
        },
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness, {required AppSettings settings}) {
    final useAmoled = settings.useAmoledDark && brightness == Brightness.dark;

    // Pick seed color: custom > default
    final seedColor = settings.seedColor ?? const Color(0xFF0B7285);

    var colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    // Dynamic color support (Android 12+)
    if (settings.useDynamicColor && brightness == Brightness.dark) {
      final dynamicColorScheme = _tryGetDynamicColorScheme(brightness);
      if (dynamicColorScheme != null) {
        colorScheme = dynamicColorScheme;
      }
    } else if (settings.useDynamicColor && brightness == Brightness.light) {
      final dynamicColorScheme = _tryGetDynamicColorScheme(brightness);
      if (dynamicColorScheme != null) {
        colorScheme = dynamicColorScheme;
      }
    }

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

    // Card/AppBar/BottomBar background tint: mix surface color with
    // scaffold background at overlayAlpha so they become semi-transparent
    // against background images.
    final Color overlaySurface = Color.alphaBlend(
      colorScheme.surface.withValues(alpha: overlayAlpha),
      scaffoldBackground ?? colorScheme.surface,
    );
    final Color overlaySurfaceContainer = Color.alphaBlend(
      (useAmoled ? const Color(0xFF0A0A0A) : colorScheme.surfaceContainer)
          .withValues(alpha: overlayAlpha),
      scaffoldBackground ?? colorScheme.surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackground,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: hasBackgroundImage && !useAmoled
            ? overlaySurface.withValues(alpha: overlayAlpha)
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
        fillColor: useAmoled ? const Color(0xFF0A0A0A) : colorScheme.surface,
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
        color: hasBackgroundImage && !useAmoled
            ? overlaySurface.withValues(alpha: overlayAlpha)
            : null,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }

  /// Attempt to get the system's dynamic color scheme on Android 12+.
  /// Returns `null` if not available (e.g. pre-Android 12, iOS, desktop).
  ColorScheme? _tryGetDynamicColorScheme(Brightness brightness) {
    // Dynamic color requires the `dynamic_color` package or platform channel.
    // For now we return null; this will be wired up when the platform plugin
    // is integrated. The personalization UI already offers the toggle so
    // users can enable it once the native side is ready.
    return null;
  }
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
  AppLaunchAction? _pendingLaunchAction;
  StreamSubscription<AppLaunchAction>? _launchSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(AndroidHomeIntegration.setApplicationInForeground(true));
    _pendingLaunchAction = AppLaunchService.instance.takePendingInitialAction();
    _launchSubscription = AppLaunchService.instance.actions.listen((action) {
      _pendingLaunchAction = action;
      _maybeScheduleLaunchAction();
    });
    _scheduleIOSWidgetSync();
  }

  @override
  void dispose() {
    unawaited(AndroidHomeIntegration.setApplicationInForeground(false));
    WidgetsBinding.instance.removeObserver(this);
    _launchSubscription?.cancel();
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
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeScheduleStartupCheck();
    _maybeScheduleLaunchAction();
  }

  @override
  void didUpdateWidget(covariant _AppHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeScheduleStartupCheck();
    _maybeScheduleLaunchAction();
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

  Future<void> _consumeLaunchAction() async {
    final action = _pendingLaunchAction;
    if (!mounted || action == null) {
      return;
    }
    _pendingLaunchAction = null;
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
          MaterialPageRoute<void>(
            builder: (_) => RouteDetailScreen(
              routeKey: routeKey,
              provider: provider,
              initialPathId: action.pathId,
              initialStopId: action.stopId,
              initialDestinationPathId: action.destinationPathId,
              initialDestinationStopId: action.destinationStopId,
            ),
          ),
        );
      case AppLaunchTarget.favoritesGroup:
        await navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => FavoritesScreen(initialGroupName: action.groupName),
          ),
        );
    }
  }

  Future<void> _runStartupCheck() async {
    try {
      final databasePlan =
          await widget.controller.maybeCheckForDatabaseUpdatesOnLaunch();
      if (mounted && databasePlan != null && databasePlan.hasUpdates) {
        if (databasePlan.shouldAutoDownload) {
          final providers = databasePlan.updates.keys.toList();
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.showSnackBar(
            const SnackBar(content: Text('正在更新資料庫...')),
          );
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
              SnackBar(content: Text('自動更新資料庫失敗：$error')),
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
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(content: Text('資料庫更新完成。')),
              );
            } catch (error) {
              if (!mounted) {
                return;
              }
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(content: Text('資料庫更新失敗：$error')),
              );
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
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(content: Text('資料庫更新完成。')),
                    );
                  } catch (error) {
                    if (!mounted) {
                      return;
                    }
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      SnackBar(content: Text('資料庫更新失敗：$error')),
                    );
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
        )?.showSnackBar(SnackBar(content: Text('檢查資料庫更新失敗：$error')));
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
