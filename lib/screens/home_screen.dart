import 'package:flutter/material.dart';

import '../app/bus_app.dart';
import '../core/app_controller.dart';
import 'favorites_screen.dart';
import 'nearby_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _showDatabaseSheet(
    BuildContext context,
    AppController controller,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '資料庫',
                  style: Theme.of(sheetContext).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text('目前資料來源：${controller.settings.provider.label}'),
                const SizedBox(height: 4),
                FutureBuilder<int?>(
                  future: controller.currentProviderLocalVersion(),
                  builder: (context, snapshot) {
                    final version = snapshot.data;
                    final text = version == null || version == 0
                        ? '本機尚未下載資料庫'
                        : '本機資料庫版本：$version';
                    return Text(text);
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  controller.databaseReady
                      ? '本機資料庫已可用。你可以在這裡重新下載，或先檢查是否有更新版本。'
                      : '第一次使用需要先下載 ${controller.settings.provider.label} 的 sqlite 資料庫，之後搜尋、路線詳情與智慧推薦才會完整可用。',
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: controller.downloadingDatabase
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              Navigator.of(sheetContext).pop();
                              try {
                                await controller
                                    .downloadCurrentProviderDatabase();
                                if (!context.mounted) {
                                  return;
                                }
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '${controller.settings.provider.label} 資料庫下載完成。',
                                    ),
                                  ),
                                );
                              } catch (error) {
                                if (!context.mounted) {
                                  return;
                                }
                                messenger.showSnackBar(
                                  SnackBar(content: Text('資料庫下載失敗：$error')),
                                );
                              }
                            },
                      icon: controller.downloadingDatabase
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              controller.databaseReady
                                  ? Icons.download_for_offline_outlined
                                  : Icons.cloud_download_outlined,
                            ),
                      label: Text(
                        controller.downloadingDatabase
                            ? '下載中...'
                            : (controller.databaseReady ? '重新下載' : '下載資料庫'),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.of(sheetContext).pop();
                        try {
                          final updates = await controller
                              .checkDatabaseUpdates();
                          if (!context.mounted) {
                            return;
                          }
                          final lines = updates.entries
                              .map(
                                (entry) => entry.value == null
                                    ? '${entry.key.label}：已是最新版本'
                                    : '${entry.key.label}：可更新到 ${entry.value}',
                              )
                              .join('\n');
                          messenger.showSnackBar(
                            SnackBar(content: Text(lines)),
                          );
                        } catch (error) {
                          if (!context.mounted) {
                            return;
                          }
                          messenger.showSnackBar(
                            SnackBar(content: Text('檢查資料庫更新失敗：$error')),
                          );
                        }
                      },
                      icon: const Icon(Icons.cloud_sync_outlined),
                      label: const Text('檢查更新'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('YABus'),
        actions: [
          IconButton(
            tooltip: '資料庫',
            onPressed: () => _showDatabaseSheet(context, controller),
            icon: controller.downloadingDatabase
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    controller.databaseReady
                        ? Icons.storage_rounded
                        : Icons.cloud_download_outlined,
                  ),
          ),
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
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.settings.provider.label,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      controller.databaseReady
                          ? '資料庫已就緒。'
                          : '尚未下載資料庫。你仍可先瀏覽功能，稍後再下載。',
                    ),
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
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: colorScheme.onPrimaryContainer),
        ),
        title: Text(title),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(subtitle),
        ),
        onTap: onTap,
      ),
    );
  }
}
