import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app/bus_app.dart';
import '../core/app_controller.dart';
import '../core/models.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _stepCount = 3;

  final PageController _pageController = PageController();
  int _stepIndex = 0;
  bool _requestingPermission = false;
  bool _resolvingLocation = false;
  bool _manualProviderSelection = false;
  String? _permissionMessage;
  BusProvider? _suggestedProvider;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _goToStep(int index) async {
    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _nextStep() async {
    if (_stepIndex >= _stepCount - 1) {
      final controller = AppControllerScope.read(context);
      await controller.completeOnboarding();
      return;
    }
    await _goToStep(_stepIndex + 1);
  }

  Future<void> _applySuggestedProvider(
    AppController controller,
    Position position,
  ) async {
    final suggested = nearestBusProvider(
      latitude: position.latitude,
      longitude: position.longitude,
    );
    _suggestedProvider = suggested;
    if (_manualProviderSelection || controller.settings.provider == suggested) {
      return;
    }
    await controller.updateProvider(suggested);
  }

  Future<Position?> _resolveCurrentPosition() async {
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 6),
          ),
        );
      } catch (_) {
        return lastKnown;
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> _requestLocationPermissionAndContinue() async {
    final controller = AppControllerScope.read(context);
    setState(() {
      _requestingPermission = true;
      _resolvingLocation = false;
      _permissionMessage = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (!serviceEnabled) {
        setState(() {
          _permissionMessage =
              'Location services are turned off. You can still choose a database manually.';
        });
      } else if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        setState(() {
          _permissionMessage =
              'Location permission was not granted. Choose a database manually.';
        });
      } else {
        setState(() {
          _resolvingLocation = true;
        });
        final position = await _resolveCurrentPosition();
        if (!mounted) {
          return;
        }
        if (position == null) {
          setState(() {
            _permissionMessage =
                'Location was allowed, but no position was available. Choose a database manually.';
          });
        } else {
          await _applySuggestedProvider(controller, position);
          if (!mounted) {
            return;
          }
          setState(() {
            _permissionMessage =
                'Nearest database selected: ${controller.settings.provider.label}.';
          });
        }
      }
    } catch (error) {
      setState(() {
        _permissionMessage =
            'Location setup failed ($error). Choose a database manually.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _requestingPermission = false;
          _resolvingLocation = false;
        });
      }
    }

    if (mounted && _stepIndex == 1) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await _nextStep();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            children: [
              Row(
                children: List.generate(_stepCount, (index) {
                  final active = index <= _stepIndex;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: index == _stepCount - 1 ? 0 : 8,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        height: 6,
                        decoration: BoxDecoration(
                          color: active
                              ? colorScheme.primary
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (index) {
                    setState(() {
                      _stepIndex = index;
                    });
                  },
                  children: [
                    _IntroStep(onNext: _nextStep),
                    _PermissionStep(
                      requestingPermission: _requestingPermission,
                      resolvingLocation: _resolvingLocation,
                      permissionMessage: _permissionMessage,
                      onRequestPermission:
                          _requestLocationPermissionAndContinue,
                      onSkip: _nextStep,
                      onBack: () => _goToStep(_stepIndex - 1),
                    ),
                    _DatabaseStep(
                      controller: controller,
                      suggestedProvider: _suggestedProvider,
                      onProviderChanged: (provider) async {
                        _manualProviderSelection = true;
                        await controller.updateProvider(provider);
                      },
                      onBack: () => _goToStep(_stepIndex - 1),
                      onFinish: _nextStep,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroStep extends StatelessWidget {
  const _IntroStep({required this.onNext});

  final Future<void> Function() onNext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Icon(
            Icons.directions_bus_rounded,
            size: 44,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Welcome to YABus',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 24),
        const _OnboardingFeature(
          icon: Icons.search_rounded,
          title: 'Route search',
          subtitle:
              'Search routes locally after downloading the selected database.',
        ),
        const SizedBox(height: 12),
        const _OnboardingFeature(
          icon: Icons.favorite_outline_rounded,
          title: 'Favorites',
          subtitle: 'Save stops and route groups for quick access later.',
        ),
        const SizedBox(height: 12),
        const _OnboardingFeature(
          icon: Icons.near_me_outlined,
          title: 'Nearby stops',
          subtitle:
              'Use location to jump into the closest routes once a database is ready.',
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: onNext, child: const Text('Continue')),
        ),
      ],
    );
  }
}

class _PermissionStep extends StatelessWidget {
  const _PermissionStep({
    required this.requestingPermission,
    required this.resolvingLocation,
    required this.permissionMessage,
    required this.onRequestPermission,
    required this.onSkip,
    required this.onBack,
  });

  final bool requestingPermission;
  final bool resolvingLocation;
  final String? permissionMessage;
  final Future<void> Function() onRequestPermission;
  final Future<void> Function() onSkip;
  final Future<void> Function() onBack;

  @override
  Widget build(BuildContext context) {
    final busy = requestingPermission || resolvingLocation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'Location permission',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        Text(
          'Allow location access now to preselect the nearest city or county database. If location is unavailable, you can still choose one manually.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('This step only helps with database preselection.'),
                if (permissionMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(permissionMessage!),
                ],
              ],
            ),
          ),
        ),
        const Spacer(),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onBack,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: busy ? null : onRequestPermission,
                child: Text(busy ? 'Checking...' : 'Allow and continue'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: busy ? null : onSkip,
            child: const Text('Choose manually'),
          ),
        ),
      ],
    );
  }
}

class _DatabaseStep extends StatelessWidget {
  const _DatabaseStep({
    required this.controller,
    required this.suggestedProvider,
    required this.onProviderChanged,
    required this.onBack,
    required this.onFinish,
  });

  final AppController controller;
  final BusProvider? suggestedProvider;
  final Future<void> Function(BusProvider provider) onProviderChanged;
  final Future<void> Function() onBack;
  final Future<void> Function() onFinish;

  @override
  Widget build(BuildContext context) {
    final provider = controller.settings.provider;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'Download database',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        Text(
          'Select the city or county database you want to use on this device. The app stays usable even if you skip the download for now.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        DropdownButtonFormField<BusProvider>(
          initialValue: provider,
          decoration: const InputDecoration(labelText: 'Database'),
          items: BusProvider.values
              .map(
                (item) =>
                    DropdownMenuItem(value: item, child: Text(item.label)),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              onProviderChanged(value);
            }
          },
        ),
        if (suggestedProvider != null) ...[
          const SizedBox(height: 12),
          Text(
            'Nearest suggestion: ${suggestedProvider!.label}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Selected: ${provider.label}'),
                const SizedBox(height: 8),
                Text(
                  controller.databaseReady
                      ? 'This database is already downloaded.'
                      : 'This database has not been downloaded yet.',
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onBack,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: controller.downloadingDatabase
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await controller.downloadCurrentProviderDatabase();
                          if (!context.mounted) {
                            return;
                          }
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                '${controller.settings.provider.label} downloaded successfully.',
                              ),
                            ),
                          );
                        } catch (error) {
                          if (!context.mounted) {
                            return;
                          }
                          messenger.showSnackBar(
                            SnackBar(content: Text('Download failed: $error')),
                          );
                        }
                      },
                child: Text(
                  controller.downloadingDatabase
                      ? 'Downloading...'
                      : 'Download',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonal(
            onPressed: onFinish,
            child: Text(
              controller.databaseReady
                  ? 'Finish setup'
                  : 'Finish without download',
            ),
          ),
        ),
      ],
    );
  }
}

class _OnboardingFeature extends StatelessWidget {
  const _OnboardingFeature({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(subtitle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
