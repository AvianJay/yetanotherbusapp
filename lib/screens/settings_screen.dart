import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/bus_app.dart';
import '../core/android_trip_monitor.dart';
import '../core/app_controller.dart';
import '../core/models.dart';
import '../widgets/app_update_dialog.dart';
import 'database_settings_screen.dart';

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
      ).showSnackBar(const SnackBar(content: Text('需要通知權限才能啟用智慧推薦通知。')));
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
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final supportsRouteBackgroundMonitor = isAndroid || isIOS;
    final databaseProviders = controller.selectedProviders
        .map((provider) => provider.label)
        .join('、');

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
                    decoration: const InputDecoration(labelText: '主題模式'),
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
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('純黑 (AMOLED) 深色主題'),
                    subtitle: const Text('深色模式下使用純黑背景，可省電並提升對比'),
                    value: controller.settings.useAmoledDark,
                    onChanged: controller.settings.themeMode == ThemeMode.light
                        ? null
                        : (value) {
                            controller.updateUseAmoledDark(value);
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
                    '資料庫與下載',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '目前地區：${controller.settings.provider.label}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '已選地區：$databaseProviders',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '公路客運固定走線上查詢，不提供下載。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '啟動更新：${controller.settings.databaseAutoUpdateMode.label}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (controller.hasPendingDatabaseUpdates) ...[
                    const SizedBox(height: 4),
                    Text(
                      '目前有 ${controller.pendingDatabaseUpdates.length} 個地區可更新',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 14),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const DatabaseSettingsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.storage_rounded),
                    label: const Text('開啟資料庫頁面'),
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
                    '使用與更新',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
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
                    subtitle: const Text('依照你常開啟的時段與路線，在首頁顯示推薦。'),
                    value: controller.settings.enableSmartRecommendations,
                    onChanged: controller.updateEnableSmartRecommendations,
                  ),
                  if (isAndroid)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('智慧推薦通知'),
                      subtitle: const Text('在常用時段背景提醒你可能想看的路線。'),
                      value: controller.settings.enableSmartRouteNotifications,
                      onChanged: (value) => _toggleSmartRouteNotifications(
                        context,
                        controller,
                        value,
                      ),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('進入公車頁保持亮屏'),
                    subtitle: const Text('在路線詳細頁面維持螢幕常亮。'),
                    value: controller.settings.keepScreenAwakeOnRouteDetail,
                    onChanged: controller.updateKeepScreenAwakeOnRouteDetail,
                  ),
                  if (supportsRouteBackgroundMonitor)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('背景乘車提醒'),
                      subtitle: Text(
                        isIOS
                            ? '需要通知與背景定位權限，才能在背景持續提醒搭車狀態。'
                            : '需要通知與定位權限，才能在背景持續提醒搭車狀態。',
                      ),
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
                        helperText: 'Android 小工具最低更新間隔為 15 分鐘。',
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
                  Text('一般更新間隔：${controller.settings.busUpdateTime} 秒'),
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
                  Text('目前 commit：${buildInfo.shortGitSha}'),
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
                      controller.checkingAppUpdate ? '檢查中…' : '立即檢查 App 更新',
                    ),
                  ),
                  if (controller.lastAppUpdateResult case final result?) ...[
                    const SizedBox(height: 12),
                    Text(
                      '最近結果：${result.message}',
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
                    '紀錄與隱私',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Text('搜尋紀錄上限：${controller.settings.maxHistory} 筆'),
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
                  Text('智慧推薦路線：${controller.routeUsageProfiles.length} 條'),
                  const SizedBox(height: 4),
                  Text('路線選擇紀錄：${controller.recordedRouteSelections} 次'),
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
                        label: const Text('清除智慧推薦紀錄'),
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
                  Text(
                    '開始流程',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
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
                    label: const Text('重新執行開始流程'),
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
