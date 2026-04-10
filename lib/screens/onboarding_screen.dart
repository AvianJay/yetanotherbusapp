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
          _permissionMessage = '定位服務尚未開啟。你仍可手動選擇資料庫。';
        });
      } else if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        setState(() {
          _permissionMessage = '沒有取得定位權限。請改為手動選擇資料庫。';
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
            _permissionMessage = '定位權限已授權，但暫時無法取得位置。請改為手動選擇資料庫。';
          });
        } else {
          await _applySuggestedProvider(controller, position);
          if (!mounted) {
            return;
          }
          setState(() {
            _permissionMessage =
                '已自動選擇最近的資料庫：${controller.settings.provider.label}。';
          });
        }
      }
    } catch (error) {
      setState(() {
        _permissionMessage = '定位設定失敗（$error）。請改為手動選擇資料庫。';
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
                      onProviderToggled: (provider, selected) async {
                        _manualProviderSelection = true;
                        if (selected) {
                          await controller.updateProvider(provider);
                        } else {
                          await controller.toggleSelectedProvider(
                            provider,
                            false,
                          );
                        }
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
        Text('歡迎來到 YABus', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 24),
        const _OnboardingFeature(
          icon: Icons.search_rounded,
          title: '搜尋路線',
          subtitle: '輸入公車名稱或號碼，直接打開即時站牌頁。',
        ),
        const SizedBox(height: 12),
        const _OnboardingFeature(
          icon: Icons.favorite_outline_rounded,
          title: '收藏站牌',
          subtitle: '把常搭的站牌分群保存，下次一鍵回來。',
        ),
        const SizedBox(height: 12),
        const _OnboardingFeature(
          icon: Icons.near_me_outlined,
          title: '附近站牌',
          subtitle: '配合定位權限快速找周邊站點。',
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: onNext, child: const Text('開始設定')),
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
        Text('定位權限', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 10),
        Text(
          '如果你願意開啟定位，系統會先幫你選擇最近的縣市資料庫；就算跳過，也能手動選擇。',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('這一步只用來預先挑選資料庫，不會影響其他功能。'),
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
              child: OutlinedButton(onPressed: onBack, child: const Text('返回')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: busy ? null : onRequestPermission,
                child: Text(busy ? '處理中...' : '授權並繼續'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: busy ? null : onSkip,
            child: const Text('手動選擇資料庫'),
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
    required this.onProviderToggled,
    required this.onBack,
    required this.onFinish,
  });

  final AppController controller;
  final BusProvider? suggestedProvider;
  final Future<void> Function(BusProvider provider, bool selected)
  onProviderToggled;
  final Future<void> Function() onBack;
  final Future<void> Function() onFinish;

  @override
  Widget build(BuildContext context) {
    final provider = controller.settings.provider;
    final selectedProviders = controller.selectedProviders;
    final downloadedCount = selectedProviders
        .where(controller.isDatabaseReady)
        .length;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('下載資料庫', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 10),
        Text(
          '可複選要在這台裝置使用的縣市資料庫。即使先不下載，仍可先進入首頁。',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('縣市清單', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: BusProvider.values.map((item) {
                        return FilterChip(
                          label: Text(item.label),
                          selected: selectedProviders.contains(item),
                          onSelected: (selected) {
                            onProviderToggled(item, selected);
                          },
                          avatar: controller.isDatabaseReady(item)
                              ? const Icon(
                                  Icons.download_done_rounded,
                                  size: 18,
                                )
                              : const Icon(Icons.cloud_outlined, size: 18),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
              if (suggestedProvider != null) ...[
                const SizedBox(height: 12),
                Text(
                  '最近建議：${suggestedProvider!.label}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('預設資料來源：${provider.label}'),
                      const SizedBox(height: 8),
                      Text(
                        '已選資料庫：${selectedProviders.map((item) => item.label).join('、')}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '已下載 $downloadedCount / ${selectedProviders.length} 份資料庫',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(onPressed: onBack, child: const Text('返回')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: controller.downloadingDatabase
                    ? null
                    : () async {
                        try {
                          await controller.downloadSelectedProviderDatabases();
                          if (!context.mounted) {
                            return;
                          }
                          await onFinish();
                        } catch (error) {
                          if (!context.mounted) {
                            return;
                          }
                          final messenger = ScaffoldMessenger.of(context);
                          messenger.showSnackBar(
                            SnackBar(content: Text('下載失敗：$error')),
                          );
                        }
                      },
                child: Text(
                  controller.downloadingDatabase ? '下載中...' : '下載並進入首頁',
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
            child: Text(controller.databaseReady ? '完成並進入首頁' : '稍後再說，先進首頁'),
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
