import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../screens/home_screen.dart';
import '../screens/onboarding_screen.dart';
import '../widgets/app_update_dialog.dart';

class BusApp extends StatelessWidget {
  const BusApp({required this.controller, super.key});

  final AppController controller;

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
            theme: _buildTheme(Brightness.light),
            darkTheme: _buildTheme(Brightness.dark),
            home: _AppHome(controller: controller),
          );
        },
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0B7285),
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF5F7F2)
          : null,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
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
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}

class _AppHome extends StatefulWidget {
  const _AppHome({required this.controller});

  final AppController controller;

  @override
  State<_AppHome> createState() => _AppHomeState();
}

class _AppHomeState extends State<_AppHome> {
  bool _startupCheckScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeScheduleStartupCheck();
  }

  @override
  void didUpdateWidget(covariant _AppHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeScheduleStartupCheck();
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

  Future<void> _runStartupCheck() async {
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
        : const HomeScreen();
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
