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
  static const _stepCount = 4;

  final PageController _pageController = PageController();
  int _stepIndex = 0;
  bool _requestingPermission = false;
  String? _permissionMessage;

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

  Future<void> _requestLocationPermission() async {
    setState(() {
      _requestingPermission = true;
      _permissionMessage = null;
    });

    try {
      var shouldAdvance = false;
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _permissionMessage = '定位服務尚未開啟，但你之後仍可先繼續使用 app。';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      setState(() {
        _permissionMessage = switch (permission) {
          LocationPermission.always ||
          LocationPermission.whileInUse => '定位權限已授權。',
          LocationPermission.denied => '定位權限被拒絕，你之後仍可在設定重開。',
          LocationPermission.deniedForever => '定位權限被永久拒絕，可稍後到系統設定開啟。',
          LocationPermission.unableToDetermine => '目前無法判斷定位權限狀態。',
        };
      });
      shouldAdvance = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;

      if (shouldAdvance) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
        if (mounted && _stepIndex == 2) {
          await _nextStep();
        }
      }
    } catch (error) {
      setState(() {
        _permissionMessage = '定位權限請求失敗：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _requestingPermission = false;
        });
      }
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
                    _ProviderStep(
                      provider: controller.settings.provider,
                      databaseReady: controller.databaseReady,
                      onProviderChanged: controller.updateProvider,
                      onNext: _nextStep,
                    ),
                    _PermissionStep(
                      requestingPermission: _requestingPermission,
                      permissionMessage: _permissionMessage,
                      onRequestPermission: _requestLocationPermission,
                      onNext: _nextStep,
                      onBack: () => _goToStep(_stepIndex - 1),
                    ),
                    _DatabaseStep(
                      controller: controller,
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

class _ProviderStep extends StatelessWidget {
  const _ProviderStep({
    required this.provider,
    required this.databaseReady,
    required this.onProviderChanged,
    required this.onNext,
  });

  final BusProvider provider;
  final bool databaseReady;
  final ValueChanged<BusProvider> onProviderChanged;
  final Future<void> Function() onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('先選資料來源', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 10),
        Text(
          '這會決定目前使用哪一份 sqlite 路線資料。之後在設定頁隨時都可以切換。',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        SegmentedButton<BusProvider>(
          multiSelectionEnabled: false,
          showSelectedIcon: false,
          segments: BusProvider.values
              .map(
                (item) => ButtonSegment<BusProvider>(
                  value: item,
                  label: Text(item.label),
                ),
              )
              .toList(),
          selected: {provider},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              onProviderChanged(selection.first);
            }
          },
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              databaseReady
                  ? '這個 provider 的資料庫已經準備好了。'
                  : '目前還沒下載 ${provider.label} 資料庫，下一步會幫你處理。',
            ),
          ),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: onNext, child: const Text('繼續')),
        ),
      ],
    );
  }
}

class _PermissionStep extends StatelessWidget {
  const _PermissionStep({
    required this.requestingPermission,
    required this.permissionMessage,
    required this.onRequestPermission,
    required this.onNext,
    required this.onBack,
  });

  final bool requestingPermission;
  final String? permissionMessage;
  final Future<void> Function() onRequestPermission;
  final Future<void> Function() onNext;
  final Future<void> Function() onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('定位權限', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 10),
        Text(
          '如果你想用「附近站牌」，這裡可以先授權。就算先跳過，之後一樣能在系統設定補開。',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('建議：授權「使用 App 時允許」。'),
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
                onPressed: requestingPermission ? null : onRequestPermission,
                child: Text(requestingPermission ? '請求中...' : '請求權限'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: TextButton(onPressed: onNext, child: const Text('先跳過，繼續')),
        ),
      ],
    );
  }
}

class _DatabaseStep extends StatelessWidget {
  const _DatabaseStep({
    required this.controller,
    required this.onBack,
    required this.onFinish,
  });

  final AppController controller;
  final Future<void> Function() onBack;
  final Future<void> Function() onFinish;

  @override
  Widget build(BuildContext context) {
    final provider = controller.settings.provider;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('下載初始資料庫', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 10),
        Text(
          '先把 ${provider.label} 路線資料同步到本機，搜尋和即時站牌就能直接用了。',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('目前 provider：${provider.label}'),
                const SizedBox(height: 8),
                Text(controller.databaseReady ? '狀態：已就緒' : '狀態：尚未下載'),
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
                            const SnackBar(content: Text('資料庫下載完成。')),
                          );
                        } catch (error) {
                          if (!context.mounted) {
                            return;
                          }
                          messenger.showSnackBar(
                            SnackBar(content: Text('下載失敗：$error')),
                          );
                        }
                      },
                child: Text(
                  controller.downloadingDatabase ? '下載中...' : '下載資料庫',
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
