import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app/bus_app.dart';
import '../core/desktop_discord_presence_service.dart';
import '../widgets/background_image_wrapper.dart';
import '../widgets/transit_drawer.dart';
import 'home_screen.dart';
import 'metro_dashboard_screen.dart';
import 'thsr_dashboard_screen.dart';
import 'tra_screen.dart';
import 'youbike_screen.dart';

/// Main shell that manages in-place switching between transit modes.
///
/// Lazily mounts top-level screens and animates between visited ones in place.
class MainTransitShell extends StatefulWidget {
  const MainTransitShell({super.key});

  @override
  State<MainTransitShell> createState() => _MainTransitShellState();
}

class _MainTransitShellState extends State<MainTransitShell>
    with SingleTickerProviderStateMixin {
  TransitMode _currentMode = TransitMode.bus;
  TransitMode? _outgoingMode;
  final Set<TransitMode> _loadedModes = {TransitMode.bus};
  late final AnimationController _modeTransitionController;
  double _modeTransitionDirection = 1;

  static const _desktopRailExtendedBreakpoint = 1280.0;
  static const _compactNavigationHeight = 64.0;
  static const _switchDuration = Duration(milliseconds: 220);

  @override
  void initState() {
    super.initState();
    _modeTransitionController =
        AnimationController(vsync: this, duration: _switchDuration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed && mounted) {
              setState(() => _outgoingMode = null);
            }
          });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_syncDesktopPresenceForMode(_currentMode));
  }

  void _setMode(TransitMode mode) {
    if (!kTransitModeDestinations.any(
      (destination) => destination.mode == mode,
    )) {
      mode = TransitMode.bus;
    }
    if (mode == _currentMode) {
      return;
    }
    final outgoingMode = _currentMode;
    final outgoingIndex = kTransitModeDestinations.indexWhere(
      (destination) => destination.mode == outgoingMode,
    );
    final incomingIndex = kTransitModeDestinations.indexWhere(
      (destination) => destination.mode == mode,
    );

    setState(() {
      _loadedModes.add(mode);
      _outgoingMode = outgoingMode;
      _currentMode = mode;
      _modeTransitionDirection = incomingIndex < outgoingIndex ? -1 : 1;
    });
    _modeTransitionController.forward(from: 0);
    unawaited(_syncDesktopPresenceForMode(mode));
  }

  @override
  void dispose() {
    _modeTransitionController.dispose();
    super.dispose();
  }

  Future<void> _syncDesktopPresenceForMode(TransitMode mode) async {
    final controller = AppControllerScope.read(context);
    final screenLabel = switch (mode) {
      TransitMode.bus => '公車首頁',
      TransitMode.metro => '捷運',
      TransitMode.thsr => '高鐵',
      TransitMode.tra => '台鐵',
      TransitMode.youbike => 'YouBike',
    };
    final provider = switch (mode) {
      TransitMode.bus => controller.settings.provider,
      _ => null,
    };
    await desktopDiscordPresenceService.updateScreen(
      settings: controller.settings,
      screenLabel: screenLabel,
      provider: provider,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < kDesktopNavigationRailBreakpoint;
    final screens = kTransitModeDestinations
        .where((destination) => _loadedModes.contains(destination.mode))
        .map(
          (destination) => (
            mode: destination.mode,
            child: _buildScreenForMode(destination.mode, isMobile: isMobile),
          ),
        )
        .toList();
    final orderedScreens = [
      ...screens.where((screen) => screen.mode != _currentMode),
      ...screens.where((screen) => screen.mode == _currentMode),
    ];

    final modeStack = Stack(
      fit: StackFit.expand,
      children: [
        for (final screen in orderedScreens)
          KeyedSubtree(
            key: ValueKey(screen.mode),
            child: _buildModeLayer(mode: screen.mode, child: screen.child),
          ),
      ],
    );

    if (isMobile) {
      final mobileModeStack = MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: modeStack,
      );
      return Column(
        children: [
          Expanded(child: mobileModeStack),
          _buildModeNavigation(),
        ],
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final isExtendedRail = screenWidth >= _desktopRailExtendedBreakpoint;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NavigationRail(
          extended: isExtendedRail,
          minExtendedWidth: 184,
          backgroundColor: colorScheme.surfaceContainerHigh,
          groupAlignment: -0.82,
          trailingAtBottom: true,
          trailing: Padding(
            padding: const EdgeInsets.all(16),
            child: SvgPicture.asset(
              'assets/branding/icon.svg',
              width: 48,
              height: 48,
              semanticsLabel: 'YABus',
              colorFilter: ColorFilter.mode(
                colorScheme.onSurfaceVariant,
                BlendMode.srcIn,
              ),
            ),
          ),
          selectedIndex: kTransitModeDestinations.indexWhere(
            (destination) => destination.mode == _currentMode,
          ),
          onDestinationSelected: (index) {
            if (index >= 0 && index < kTransitModeDestinations.length) {
              _setMode(kTransitModeDestinations[index].mode);
            }
          },
          labelType: isExtendedRail ? null : NavigationRailLabelType.all,
          destinations: [
            for (final destination in kTransitModeDestinations)
              NavigationRailDestination(
                icon: Icon(destination.icon),
                selectedIcon: Icon(destination.icon),
                label: Text(destination.label),
              ),
          ],
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: colorScheme.outlineVariant,
        ),
        Expanded(child: modeStack),
      ],
    );
  }

  Widget _buildModeNavigation() {
    final theme = Theme.of(context);
    // NavigationBar has its own SafeArea. The status-bar inset belongs to
    // the page above, not to this bottom bar; keep the other insets intact.
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        elevation: 8,
        shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.2),
        shape: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            height: _compactNavigationHeight,
            backgroundColor: Colors.transparent,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            selectedIndex: kTransitModeDestinations.indexWhere(
              (destination) => destination.mode == _currentMode,
            ),
            onDestinationSelected: (index) {
              if (index >= 0 && index < kTransitModeDestinations.length) {
                _setMode(kTransitModeDestinations[index].mode);
              }
            },
            destinations: [
              for (final destination in kTransitModeDestinations)
                NavigationDestination(
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(destination.icon),
                  label: destination.label,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScreenForMode(TransitMode mode, {required bool isMobile}) {
    return switch (mode) {
      TransitMode.bus => const HomeScreen(),
      TransitMode.metro => MetroScreen(
        isActive: mode == _currentMode,
        showAdBanner: !isMobile,
      ),
      TransitMode.thsr => ThsrScreen(
        isActive: mode == _currentMode,
        showAdBanner: !isMobile,
      ),
      TransitMode.tra => TraScreen(
        isActive: mode == _currentMode,
        showAdBanner: !isMobile,
      ),
      TransitMode.youbike => YouBikeScreen(
        isActive: mode == _currentMode,
        showAdBanner: !isMobile,
      ),
    };
  }

  Widget _buildModeLayer({required TransitMode mode, required Widget child}) {
    final isActive = mode == _currentMode;
    final isOutgoing = mode == _outgoingMode;
    // All 5 transit modes share the 'bus' (main/home) page key
    // so the background image is shared across the home page tabs.
    const pageKey = 'bus';
    final content = BackgroundImageWrapper(pageKey: pageKey, child: child);

    return Offstage(
      offstage: !isActive && !isOutgoing,
      child: IgnorePointer(
        ignoring: !isActive,
        child: ExcludeSemantics(
          excluding: !isActive,
          child: TickerMode(
            enabled: isActive,
            child: AnimatedBuilder(
              animation: _modeTransitionController,
              child: content,
              builder: (context, child) {
                final offset = isActive && _outgoingMode != null
                    ? _modeTransitionDirection *
                          (1 -
                              Curves.easeOutCubic.transform(
                                _modeTransitionController.value,
                              ))
                    : 0.0;
                return FractionalTranslation(
                  translation: Offset(offset, 0),
                  child: child,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
