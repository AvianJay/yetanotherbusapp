import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/bus_app.dart';
import '../core/android_trip_monitor.dart';
import '../core/app_controller.dart';
import '../core/models.dart';
import '../widgets/app_update_dialog.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _favoriteWidgetRefreshOptions = <int>[0, 15, 30, 60, 120, 180];

  String _favoriteWidgetRefreshLabel(int minutes) {
    if (minutes <= 0) {
      return '關閉';
    }
    return '$minutes 分鐘';
  }

  Future<void> _checkAppUpdate(
    BuildContext context,
    AppController controller,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await controller.checkForAppUpdate();
    if (!context.mounted) {
      return;
    }

    if (result.hasUpdate) {
      await showAppUpdateDialog(
        context,
        controller: controller,
        result: result,
      );
      return;
    }

    messenger.showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _toggleSmartRouteNotifications(
    BuildContext context,
    AppController controller,
    bool value,
  ) async {
    if (!value) {
      await controller.updateEnableSmartRouteNotifications(false);
      return;
    }

    final granted = await AndroidTripMonitor.requestNotificationPermission();
    if (!context.mounted) {
      return;
    }
    if (!granted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('智慧推薦通知需要通知權限。')));
      return;
    }
    await controller.updateEnableSmartRouteNotifications(true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final buildInfo = controller.buildInfo;
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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
                  Text('資料庫', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<BusProvider>(
                    initialValue: controller.settings.provider,
                    decoration: const InputDecoration(labelText: '資料來源'),
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
                      final text = version == null || version == 0
                          ? '本機尚未下載資料庫'
                          : '本機資料庫版本：$version';
                      return Text(text);
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
                                    const SnackBar(content: Text('資料庫下載完成。')),
                                  );
                                } catch (error) {
                                  if (!context.mounted) {
                                    return;
                                  }
                                  messenger.showSnackBar(
                                    SnackBar(content: Text('下載資料庫失敗：$error')),
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
                            : const Icon(Icons.download_rounded),
                        label: Text(
                          controller.downloadingDatabase ? '下載中...' : '下載最新資料庫',
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
                                      ? '${entry.key.label}：無法取得版本'
                                      : '${entry.key.label}：最新版本 ${entry.value}',
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
                        icon: const Icon(Icons.cloud_outlined),
                        label: const Text('檢查資料庫更新'),
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
                  Text('顯示與更新', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('顯示秒數'),
                    value: controller.settings.alwaysShowSeconds,
                    onChanged: controller.updateAlwaysShowSeconds,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('智慧推薦'),
                    subtitle: const Text('學習你在不同時段最常打開的路線，並在首頁推薦給你。'),
                    value: controller.settings.enableSmartRecommendations,
                    onChanged: controller.updateEnableSmartRecommendations,
                  ),
                  if (isAndroid)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('智慧推薦通知'),
                      subtitle: const Text('在你常打開這條路線的時間點附近，依最近站牌到站時間主動提醒。'),
                      value: controller.settings.enableSmartRouteNotifications,
                      onChanged: (value) => _toggleSmartRouteNotifications(
                        context,
                        controller,
                        value,
                      ),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('公車頁面保持螢幕常亮'),
                    subtitle: const Text('在路線詳情頁持續保持螢幕亮著。'),
                    value: controller.settings.keepScreenAwakeOnRouteDetail,
                    onChanged: controller.updateKeepScreenAwakeOnRouteDetail,
                  ),
                  if (isAndroid)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('背景乘車提醒'),
                      subtitle: const Text('在背景持續追蹤目前路線，並在接近目的地下車時提醒你。'),
                      value: controller.settings.enableRouteBackgroundMonitor,
                      onChanged: (value) {
                        controller.updateEnableRouteBackgroundMonitor(value);
                      },
                    ),
                  if (isAndroid) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue:
                          controller.settings.favoriteWidgetAutoRefreshMinutes,
                      decoration: const InputDecoration(
                        labelText: '最愛小工具背景更新',
                        helperText: 'Android 背景排程最低 15 分鐘一次',
                      ),
                      items: _favoriteWidgetRefreshOptions
                          .map(
                            (minutes) => DropdownMenuItem(
                              value: minutes,
                              child: Text(_favoriteWidgetRefreshLabel(minutes)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          controller.updateFavoriteWidgetAutoRefreshMinutes(
                            value,
                          );
                        }
                      },
                    ),
                  ],
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
                  Text('錯誤後重試間隔：${controller.settings.busErrorUpdateTime} 秒'),
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
                  Text(
                    'App 更新',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Text('目前版本：${buildInfo.displayVersion}'),
                  Text('內建 commit：${buildInfo.shortGitSha}'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<AppUpdateChannel>(
                    initialValue: controller.settings.appUpdateChannel,
                    decoration: const InputDecoration(labelText: '更新通道'),
                    items: AppUpdateChannel.values
                        .map(
                          (channel) => DropdownMenuItem(
                            value: channel,
                            child: Text(channel.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        controller.updateAppUpdateChannel(value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<AppUpdateCheckMode>(
                    initialValue: controller.settings.appUpdateCheckMode,
                    decoration: const InputDecoration(labelText: '啟動時檢查'),
                    items: AppUpdateCheckMode.values
                        .map(
                          (mode) => DropdownMenuItem(
                            value: mode,
                            child: Text(mode.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        controller.updateAppUpdateCheckMode(value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    controller.settings.appUpdateChannel.description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    controller.settings.appUpdateCheckMode.description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: controller.checkingAppUpdate
                        ? null
                        : () => _checkAppUpdate(context, controller),
                    icon: controller.checkingAppUpdate
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.system_update_alt_rounded),
                    label: Text(
                      controller.checkingAppUpdate ? '檢查中...' : '檢查 app 更新',
                    ),
                  ),
                  if (controller.lastAppUpdateResult case final result?) ...[
                    const SizedBox(height: 12),
                    Text(
                      '上次結果：${result.message}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
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
                  Text(
                    '搜尋紀錄與學習',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Text('最多保留 ${controller.settings.maxHistory} 筆'),
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
                  const SizedBox(height: 8),
                  Text('已學習路線：${controller.routeUsageProfiles.length} 條'),
                  const SizedBox(height: 4),
                  Text('已記錄路線選擇：${controller.recordedRouteSelections} 次'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: controller.clearHistory,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('清除搜尋紀錄'),
                      ),
                      OutlinedButton.icon(
                        onPressed: controller.clearRouteUsageProfiles,
                        icon: const Icon(Icons.psychology_alt_outlined),
                        label: const Text('清除智慧推薦學習'),
                      ),
                      OutlinedButton.icon(
                        onPressed: controller.clearRouteSelectionHistory,
                        icon: const Icon(Icons.route_outlined),
                        label: const Text('清除路線選擇紀錄'),
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
                  Text('首次啟動', style: Theme.of(context).textTheme.titleMedium),
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
                    label: const Text('重新開始設定流程'),
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
