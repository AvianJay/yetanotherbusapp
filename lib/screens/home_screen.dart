import 'package:flutter/material.dart';

import '../app/bus_app.dart';
import 'favorites_screen.dart';
import 'nearby_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'tracked_buses_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('YABus'),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              );
            },
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primaryContainer.withValues(alpha: 0.65),
              Theme.of(context).scaffoldBackgroundColor,
              colorScheme.secondaryContainer.withValues(alpha: 0.25),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '又一個公車的 App。',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    // const SizedBox(height: 8),
                    // Text(
                    //   '目前資料來源：${controller.settings.provider.label}',
                    //   style: Theme.of(context).textTheme.bodyLarge,
                    // ),
                    // const SizedBox(height: 16),
                    // Wrap(
                    //   spacing: 12,
                    //   runSpacing: 12,
                    //   children: [
                    //     Chip(
                    //       avatar: Icon(
                    //         controller.databaseReady
                    //             ? Icons.check_circle
                    //             : Icons.download_rounded,
                    //       ),
                    //       label: Text(
                    //         controller.databaseReady ? '資料庫已就緒' : '尚未下載資料庫',
                    //       ),
                    //     ),
                    //     if (controller.checkingDatabase)
                    //       const Chip(
                    //         avatar: SizedBox.square(
                    //           dimension: 18,
                    //           child: CircularProgressIndicator(strokeWidth: 2),
                    //         ),
                    //         label: Text('檢查中'),
                    //       ),
                    //   ],
                    // ),
                    if (!controller.databaseReady) ...[
                      const SizedBox(height: 16),
                      Text(
                        '第一次使用需要先下載 ${controller.settings.provider.label} 的 sqlite 資料庫，之後搜尋和即時站牌才會可用。',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: controller.downloadingDatabase
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                try {
                                  await controller
                                      .downloadCurrentProviderDatabase();
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
                        icon: controller.downloadingDatabase
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.cloud_download_outlined),
                        label: Text(
                          controller.downloadingDatabase
                              ? '下載中...'
                              : '下載 ${controller.settings.provider.label} 資料庫',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _FeatureCard(
              icon: Icons.search_rounded,
              title: '搜尋路線',
              subtitle: '輸入公車號碼或名稱，直接看即時到站資訊。',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            _FeatureCard(
              icon: Icons.favorite_outline_rounded,
              title: '我的最愛',
              subtitle: '整理常用站牌與群組，快速跳回指定站點。',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const FavoritesScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _FeatureCard(
              icon: Icons.directions_bus_filled_outlined,
              title: '追蹤公車',
              subtitle: controller.trackedBuses.isEmpty
                  ? '在路線頁點車牌後，可以把公車加入追蹤清單。'
                  : '目前追蹤 ${controller.trackedBuses.length} 輛公車，查看最新位置與離線狀態。',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TrackedBusesScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _FeatureCard(
              icon: Icons.near_me_outlined,
              title: '附近站牌',
              subtitle: '依照你目前位置找附近的公車站牌。',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const NearbyScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
