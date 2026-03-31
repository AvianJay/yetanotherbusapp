import 'package:flutter/material.dart';

import '../app/bus_app.dart';
import '../core/models.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('外觀', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ThemeMode>(
                    key: ValueKey(controller.settings.themeMode),
                    initialValue: controller.settings.themeMode,
                    decoration: const InputDecoration(labelText: '主題'),
                    items: const [
                      DropdownMenuItem(
                        value: ThemeMode.system,
                        child: Text('跟隨系統'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.light,
                        child: Text('淺色'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.dark,
                        child: Text('深色'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        controller.updateThemeMode(value);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('資料來源', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<BusProvider>(
                    key: ValueKey(controller.settings.provider),
                    initialValue: controller.settings.provider,
                    decoration: const InputDecoration(labelText: 'Provider'),
                    items: BusProvider.values
                        .map(
                          (provider) => DropdownMenuItem(
                            value: provider,
                            child: Text(provider.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        controller.updateProvider(value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<int?>(
                    future: controller.currentProviderLocalVersion(),
                    builder: (context, snapshot) {
                      final version = snapshot.data;
                      return Text(
                        version == null || version == 0
                            ? '本機版本：尚未下載'
                            : '本機版本：$version',
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
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
                                    const SnackBar(content: Text('資料庫更新完成。')),
                                  );
                                } catch (error) {
                                  if (!context.mounted) {
                                    return;
                                  }
                                  messenger.showSnackBar(
                                    SnackBar(content: Text('更新失敗：$error')),
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
                            : const Icon(Icons.sync_rounded),
                        label: Text(
                          controller.downloadingDatabase ? '同步中...' : '同步資料庫',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            final updates = await controller
                                .checkDatabaseUpdates();
                            if (!context.mounted) {
                              return;
                            }
                            final lines = updates.entries
                                .map(
                                  (entry) => entry.value == null
                                      ? '${entry.key.label}：最新'
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
                              SnackBar(content: Text('檢查失敗：$error')),
                            );
                          }
                        },
                        icon: const Icon(Icons.cloud_outlined),
                        label: const Text('檢查更新'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('即時公車', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('分鐘顯示秒數'),
                    value: controller.settings.alwaysShowSeconds,
                    onChanged: controller.updateAlwaysShowSeconds,
                  ),
                  const SizedBox(height: 8),
                  Text('正常更新間隔：${controller.settings.busUpdateTime} 秒'),
                  Slider(
                    min: 5,
                    max: 60,
                    divisions: 11,
                    value: controller.settings.busUpdateTime.toDouble(),
                    label: '${controller.settings.busUpdateTime} 秒',
                    onChanged: (value) {
                      controller.updateBusUpdateTime(value.round());
                    },
                  ),
                  const SizedBox(height: 8),
                  Text('失敗重試間隔：${controller.settings.busErrorUpdateTime} 秒'),
                  Slider(
                    min: 1,
                    max: 15,
                    divisions: 14,
                    value: controller.settings.busErrorUpdateTime.toDouble(),
                    label: '${controller.settings.busErrorUpdateTime} 秒',
                    onChanged: (value) {
                      controller.updateBusErrorUpdateTime(value.round());
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('搜尋紀錄', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Text('最多保留：${controller.settings.maxHistory} 筆'),
                  Slider(
                    min: 0,
                    max: 30,
                    divisions: 30,
                    value: controller.settings.maxHistory.toDouble(),
                    label: '${controller.settings.maxHistory} 筆',
                    onChanged: (value) {
                      controller.updateMaxHistory(value.round());
                    },
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: controller.clearHistory,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('清除搜尋紀錄'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('啟動導覽', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await controller.setOnboardingCompleted(false);
                      if (!context.mounted) {
                        return;
                      }
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('重新執行首次導覽'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
