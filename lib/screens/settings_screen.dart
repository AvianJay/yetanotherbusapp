import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/ad_service.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/bus_app.dart';
import '../core/android_trip_monitor.dart';
import '../core/app_build_info.dart';
import '../core/app_routes.dart';
import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/wear_os_integration.dart';
import '../widgets/app_update_dialog.dart';
import 'account_screen.dart';
import 'database_settings_screen.dart';
import 'personalization_screen.dart';
import '../widgets/background_image_wrapper.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _favoriteWidgetRefreshOptions = <int>[0, 15, 30, 60, 120, 180];
  static final _discordCommunityUri = Uri.parse('https://dc.avianjay.sbs/');
  static const _rgbContributorPalette = <Color>[
    Color(0xFFFF4D4D),
    Color(0xFF16C172),
    Color(0xFF2D9CFF),
  ];

  late Future<WearOsSyncStatus> _wearSyncStatusFuture;
  int _adToggleCount = 0;
  bool _adToggleLocked = false;
  bool _adToggleConfirmed = false;

  @override
  void initState() {
    super.initState();
    _wearSyncStatusFuture = WearOsIntegration.getStatus();
    _loadAdToggleLockState();
  }

  Future<void> _loadAdToggleLockState() async {
    final locked = await AdService.instance.isAdToggleLocked();
    if (mounted) {
      setState(() => _adToggleLocked = locked);
    }
  }

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

  Future<void> _handleAdToggle(
    BuildContext context,
    AppController controller,
    bool value,
  ) async {
    _adToggleCount++;

    // Lock after 5 toggles.
    if (_adToggleCount > 5) {
      await AdService.instance.lockAdToggle();
      await controller.updateEnableAds(true);
      if (!context.mounted) return;
      setState(() => _adToggleLocked = true);
      // await showDialog<void>(
      //   context: context,
      //   barrierDismissible: false,
      //   builder: (dialogContext) => AlertDialog(
      //     title: const Text('再玩啊哈哈'),
      //     content: const Text('開關已經被鎖起來了，只能重裝 app 才能解除鎖定 🥺'),
      //     actions: [
      //       FilledButton(
      //         onPressed: () => Navigator.of(dialogContext).pop(),
      //         child: const Text('好啦 🥺'),
      //       ),
      //     ],
      //   ),
      // );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('再玩啊哈哈')));
      return;
    }

    // Turning ads on → no confirmation needed.
    if (value) {
      await controller.updateEnableAds(true);
      return;
    }

    // Turning ads off → ask for confirmation.
    final confirmed = _adToggleConfirmed
        ? true
        : await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('你確定嗎'),
                  content: const Text('我沒有摳摳 :('),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('算了不關'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('確定關閉'),
                    ),
                  ],
                ),
              ) ??
              false;
    if (confirmed == true) {
      _adToggleConfirmed = true;
      await controller.updateEnableAds(false);
    }
  }

  Future<void> _openDiscordCommunity(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await launchUrl(
      _discordCommunityUri,
      mode: LaunchMode.externalApplication,
    );
    if (!context.mounted || opened) {
      return;
    }

    messenger.showSnackBar(const SnackBar(content: Text('無法開啟 Discord 社群連結。')));
  }

  InlineSpan _buildRgbContributorSpan(
    String name,
    ThemeData theme,
    Color color,
  ) {
    final style = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.35,
    );

    return TextSpan(
      text: name,
      style: style?.copyWith(
        color: color,
        shadows: [
          Shadow(color: color.withValues(alpha: 0.9), blurRadius: 10),
          Shadow(color: color.withValues(alpha: 0.55), blurRadius: 22),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final buildInfo = controller.buildInfo;
    final theme = Theme.of(context);
    final hasSettingsBackgroundImage = hasBackgroundImageForPage(
      controller.settings,
      pageKey: 'settings',
    );
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final supportsRouteBackgroundMonitor = isAndroid || isIOS;
    final authSession = controller.authSession;
    // final databaseProviders = controller.selectedProviders
    //     .map((provider) => provider.label)
    //     .join('、');

    return BackgroundImageWrapper(
      pageKey: 'settings',
      child: Scaffold(
        backgroundColor: hasSettingsBackgroundImage ? Colors.transparent : null,
        appBar: AppBar(title: const Text('設定')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '外觀',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
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
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('精簡模式'),
                          subtitle: const Text('首頁與部分卡片減少說明文字顯示；桌面首頁固定維持精簡。'),
                          value: controller.settings.enableCompactMode,
                          onChanged: controller.updateEnableCompactMode,
                        ),
                        if (isAndroid || isIOS) ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<MobileMapProvider>(
                            initialValue: controller.settings.mobileMapProvider,
                            decoration: const InputDecoration(
                              labelText: '地圖提供者',
                            ),
                            items: MobileMapProvider.values
                                .map(
                                  (provider) =>
                                      DropdownMenuItem<MobileMapProvider>(
                                        value: provider,
                                        child: Text(provider.label),
                                      ),
                                )
                                .toList(growable: false),
                            onChanged: (value) {
                              if (value != null) {
                                controller.updateMobileMapProvider(value);
                              }
                            },
                          ),
                        ],
                        const SizedBox(height: 12),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.palette_outlined),
                          title: const Text('個人化'),
                          subtitle: const Text('配色、背景透明度'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                settings: const RouteSettings(
                                  name: 'personalization',
                                ),
                                builder: (_) => const PersonalizationScreen(),
                              ),
                            );
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
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.account_circle_outlined),
                      title: const Text('帳戶'),
                      subtitle: Text(
                        authSession == null
                            ? '尚未登入。'
                            : '已登入為 ${authSession.displayName.isEmpty ? authSession.provider : authSession.displayName}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            settings: const RouteSettings(name: 'account'),
                            builder: (_) => const AccountScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                if (isAndroid) ...[
                  const SizedBox(height: 12),
                  FutureBuilder<WearOsSyncStatus>(
                    future: _wearSyncStatusFuture,
                    builder: (context, snapshot) {
                      final status = snapshot.data;
                      if (snapshot.connectionState == ConnectionState.waiting ||
                          (status == null || !status.hasConnectedNodes)) {
                        return const SizedBox.shrink();
                      }

                      final groupNames = controller.favoriteGroupNames;
                      final hasFavorites = groupNames.isNotEmpty;
                      final selectedIds = controller
                          .settings
                          .wearSelectedFavoriteIds
                          .toSet();

                      // Get all available favorite IDs across all groups
                      final availableIds = <String>[];
                      for (final favorites
                          in controller.favoriteGroups.values) {
                        for (final fav in favorites) {
                          availableIds.add(fav.stableKey);
                        }
                      }
                      final availableSet = availableIds.toSet();

                      String? selectedValue;
                      if (selectedIds.isEmpty) {
                        selectedValue = null;
                      } else if (setEquals(selectedIds, availableSet)) {
                        selectedValue = '__all__';
                      } else {
                        // Check if it matches any specific group
                        for (final groupName in groupNames) {
                          final groupStableKeys =
                              controller.favoriteGroups[groupName]
                                  ?.map((e) => e.stableKey)
                                  .toSet() ??
                              const <String>{};
                          if (groupStableKeys.isNotEmpty &&
                              setEquals(selectedIds, groupStableKeys)) {
                            selectedValue = groupName;
                            break;
                          }
                        }
                      }

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Wear OS',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '已連接的手錶：${status.connectedNodeNames.join('、')}'
                                '${status.connectedNodeCount > 1 ? ' 等 ${status.connectedNodeCount} 台' : ''}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 12),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('啟用 Wear OS 同步'),
                                subtitle: const Text('將最愛站牌同步到手錶'),
                                value: controller.settings.wearSyncEnabled,
                                onChanged: controller.updateWearSyncEnabled,
                              ),
                              if (controller.settings.wearSyncEnabled) ...[
                                if (!hasFavorites)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      '尚無最愛站牌。請先新增最愛，再進行同步。',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                  )
                                else ...[
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    initialValue: selectedValue,
                                    decoration: const InputDecoration(
                                      labelText: '同步分類',
                                    ),
                                    items: [
                                      const DropdownMenuItem(
                                        value: '__all__',
                                        child: Text('所有分類'),
                                      ),
                                      ...groupNames.map(
                                        (groupName) => DropdownMenuItem(
                                          value: groupName,
                                          child: Text(groupName),
                                        ),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      if (value == '__all__') {
                                        controller
                                            .updateWearSelectedFavoriteIds(
                                              availableIds,
                                            );
                                      } else if (value != null) {
                                        final keys =
                                            controller.favoriteGroups[value]
                                                ?.map((e) => e.stableKey)
                                                .toList() ??
                                            const <String>[];
                                        controller
                                            .updateWearSelectedFavoriteIds(
                                              keys,
                                            );
                                      }
                                    },
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
                if (!kIsWeb) ...[
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
                                  settings: const RouteSettings(
                                    name: 'database_settings',
                                  ),
                                  builder: (_) =>
                                      const DatabaseSettingsScreen(),
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
                ],
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
                          title: const Text('強制顯示秒數'),
                          subtitle: const Text(
                            '這個通常不太準',
                            style: TextStyle(
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          value: controller.settings.alwaysShowSeconds,
                          onChanged: controller.updateAlwaysShowSeconds,
                        ),
                        if (isAndroid || isIOS)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('震動回饋'),
                            subtitle: const Text('點選及操作時提供觸覺回饋'),
                            value: controller.settings.enableHapticFeedback,
                            onChanged: controller.updateEnableHapticFeedback,
                          ),
                        if (!kIsWeb &&
                            defaultTargetPlatform == TargetPlatform.android)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('顯示廣告'),
                            subtitle: _adToggleLocked
                                ? Text.rich(
                                    TextSpan(
                                      children: [
                                        WidgetSpan(
                                          alignment:
                                              PlaceholderAlignment.middle,
                                          child: Image.asset(
                                            "assets/cat_laugh.png",
                                            width: 20,
                                            height: 20,
                                          ),
                                        ),
                                        const TextSpan(text: ' 再玩啊哈哈'),
                                      ],
                                    ),
                                  )
                                : controller.settings.enableAds
                                ? const Text('把開發者的飯碗搶走。')
                                : Text.rich(
                                    TextSpan(
                                      children: [
                                        WidgetSpan(
                                          alignment:
                                              PlaceholderAlignment.middle,
                                          child: Image.asset(
                                            [
                                              "assets/cat_cry.png",
                                              "assets/cat_sad.png",
                                            ][Random().nextInt(2)],
                                            width: 20,
                                            height: 20,
                                          ),
                                        ),
                                        TextSpan(
                                          text:
                                              ' ${["我求你了", "我跪著有用嗎", "你不能這樣對我", "QAQ"][Random().nextInt(4)]}',
                                        ),
                                      ],
                                    ),
                                  ),
                            value: _adToggleLocked
                                ? true
                                : controller.settings.enableAds,
                            onChanged: _adToggleLocked
                                ? null
                                : (value) => _handleAdToggle(
                                    context,
                                    controller,
                                    value,
                                  ),
                          ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('智慧推薦'),
                          subtitle: const Text('依照你常開啟的時段與路線，在首頁顯示推薦。'),
                          value: controller.settings.enableSmartRecommendations,
                          onChanged:
                              controller.updateEnableSmartRecommendations,
                        ),
                        if (isAndroid)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('智慧推薦通知'),
                            subtitle: const Text('在常用時段背景提醒你可能想看的路線。'),
                            value: controller
                                .settings
                                .enableSmartRouteNotifications,
                            onChanged: (value) =>
                                _toggleSmartRouteNotifications(
                                  context,
                                  controller,
                                  value,
                                ),
                          ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('進入公車頁保持亮屏'),
                          subtitle: const Text('在路線詳細頁面維持螢幕常亮。'),
                          value:
                              controller.settings.keepScreenAwakeOnRouteDetail,
                          onChanged:
                              controller.updateKeepScreenAwakeOnRouteDetail,
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
                            value: controller
                                .settings
                                .enableRouteBackgroundMonitor,
                            onChanged: (value) {
                              controller.updateEnableRouteBackgroundMonitor(
                                value,
                              );
                            },
                          ),
                        if (isAndroid) ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            initialValue: controller
                                .settings
                                .favoriteWidgetAutoRefreshMinutes,
                            decoration: const InputDecoration(
                              labelText: '最愛小工具背景更新',
                              helperText: 'Android 小工具最低更新間隔為 15 分鐘。',
                            ),
                            items: _favoriteWidgetRefreshOptions
                                .map(
                                  (minutes) => DropdownMenuItem(
                                    value: minutes,
                                    child: Text(
                                      _favoriteWidgetRefreshLabel(minutes),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                controller
                                    .updateFavoriteWidgetAutoRefreshMinutes(
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
                        Text(
                          '錯誤後重試間隔：${controller.settings.busErrorUpdateTime} 秒',
                        ),
                        Slider(
                          min: 1,
                          max: 15,
                          divisions: 14,
                          value: controller.settings.busErrorUpdateTime
                              .toDouble(),
                          label: '${controller.settings.busErrorUpdateTime} 秒',
                          onChanged: (value) {
                            controller.updateBusErrorUpdateTime(value.round());
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                if (!kIsWeb && !AppBuildInfo.isAabBuild) ...[
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
                          DropdownButtonFormField<AppUpdateChannel>(
                            initialValue: controller.settings.appUpdateChannel,
                            decoration: const InputDecoration(
                              labelText: '更新通道',
                            ),
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
                            initialValue:
                                controller.settings.appUpdateCheckMode,
                            decoration: const InputDecoration(
                              labelText: '啟動時檢查',
                            ),
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
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.system_update_alt_rounded),
                            label: Text(
                              controller.checkingAppUpdate
                                  ? '檢查中…'
                                  : '立即檢查 App 更新',
                            ),
                          ),
                          if (controller.lastAppUpdateResult
                              case final result?) ...[
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
                ],
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
                        Text(
                          '智慧推薦路線：${controller.routeUsageProfiles.length} 條',
                        ),
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
                        const SizedBox(height: 16),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.gavel_outlined),
                          title: const Text('服務條款'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(
                              context,
                            ).pushNamed(AppRoutes.termsOfService);
                          },
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.privacy_tip_outlined),
                          title: const Text('隱私權政策'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(
                              context,
                            ).pushNamed(AppRoutes.privacyPolicy);
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
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '關於',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'YetAnotherBusApp',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text('版本：${buildInfo.displayVersion}'),
                        Text('commit：${buildInfo.shortGitSha}'),
                        const SizedBox(height: 8),
                        Text.rich(
                          TextSpan(
                            style: theme.textTheme.bodyMedium,
                            children: [
                              const TextSpan(text: '貢獻者清單：\n'),
                              _buildRgbContributorSpan(
                                'AvianJay',
                                theme,
                                _rgbContributorPalette[0],
                              ),
                              const TextSpan(text: '\n'),
                              _buildRgbContributorSpan(
                                'itouSouta',
                                theme,
                                _rgbContributorPalette[1],
                              ),
                              const TextSpan(text: '\n'),
                              _buildRgbContributorSpan(
                                'Axoled',
                                theme,
                                _rgbContributorPalette[2],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const FaIcon(
                            FontAwesomeIcons.discord,
                            size: 22,
                          ),
                          title: const Text('加入角蛙社群'),
                          subtitle: const Text('我的 Discord 伺服器 uwu'),
                          trailing: const Icon(Icons.open_in_new_rounded),
                          onTap: () => _openDiscordCommunity(context),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.feedback_outlined),
                          title: const Text('意見回饋'),
                          subtitle: const Text('回報問題、提出功能需求或任何想說的話'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).pushNamed(AppRoutes.feedback);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// SettingsScreen
