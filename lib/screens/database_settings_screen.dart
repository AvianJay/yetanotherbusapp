import 'package:flutter/material.dart';

import '../app/bus_app.dart';
import '../core/app_controller.dart';
import '../core/models.dart';

class DatabaseSettingsScreen extends StatelessWidget {
  const DatabaseSettingsScreen({super.key});

  Future<void> _checkDatabaseUpdates(
    BuildContext context,
    AppController controller,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updates = await controller.checkDatabaseUpdates();
      if (!context.mounted) {
        return;
      }

      final availableUpdates = updates.entries
          .where((entry) => entry.value != null)
          .toList();
      if (availableUpdates.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('目前資料庫已是最新版本。')));
        return;
      }

      final lines = availableUpdates
          .map((entry) => '${entry.key.label} 有新版本 ${entry.value}')
          .join('\n');
      messenger.showSnackBar(SnackBar(content: Text(lines)));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('檢查資料庫更新失敗：$error')));
    }
  }

  Future<void> _downloadProviders(
    BuildContext context,
    AppController controller, {
    required Iterable<BusProvider> providers,
    required String successMessage,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final targets = providers.toSet().toList();
    if (targets.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('目前沒有可更新的資料庫。')));
      return;
    }

    try {
      await controller.downloadProviderDatabases(targets);
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('下載資料庫失敗：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('資料庫與下載')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('啟動時更新', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<DatabaseAutoUpdateMode>(
                    initialValue: controller.settings.databaseAutoUpdateMode,
                    decoration: const InputDecoration(labelText: '自動更新模式'),
                    items: DatabaseAutoUpdateMode.values
                        .map(
                          (mode) => DropdownMenuItem(
                            value: mode,
                            child: Text(mode.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        controller.updateDatabaseAutoUpdateMode(value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    controller.settings.databaseAutoUpdateMode.description,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (controller.hasPendingDatabaseUpdates) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.45,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '目前有 ${controller.pendingDatabaseUpdates.length} 個地區可更新',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            controller.pendingDatabaseUpdates.entries
                                .map(
                                  (entry) => '${entry.key.label} v${entry.value}',
                                )
                                .join('、'),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: controller.downloadingDatabase
                            ? null
                            : () => _checkDatabaseUpdates(context, controller),
                        icon: const Icon(Icons.cloud_sync_outlined),
                        label: const Text('立即檢查更新'),
                      ),
                      FilledButton.icon(
                        onPressed:
                            controller.downloadingDatabase ||
                                !controller.hasPendingDatabaseUpdates
                            ? null
                            : () => _downloadProviders(
                                context,
                                controller,
                                providers: controller.pendingDatabaseUpdates.keys,
                                successMessage: '已更新所有有新版本的資料庫。',
                              ),
                        icon: controller.downloadingDatabase
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download_rounded),
                        label: const Text('更新可用更新'),
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
                  Text('資料來源', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<BusProvider>(
                    initialValue: controller.settings.provider,
                    decoration: const InputDecoration(labelText: '預設顯示地區'),
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
                  Text(
                    '選取要保留在本機的地區資料庫。若未下載，搜尋與詳細頁會在需要時改走線上 API。',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: BusProvider.values.map((provider) {
                      return FilterChip(
                        label: Text(provider.label),
                        selected: controller.selectedProviders.contains(provider),
                        onSelected: (value) {
                          controller.toggleSelectedProvider(provider, value);
                        },
                        avatar: controller.isDatabaseReady(provider)
                            ? const Icon(Icons.download_done_rounded, size: 18)
                            : const Icon(Icons.cloud_outlined, size: 18),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: controller.downloadingDatabase
                        ? null
                        : () => _downloadProviders(
                            context,
                            controller,
                            providers: controller.selectedProviders,
                            successMessage: '已下載選取地區的資料庫。',
                          ),
                    icon: controller.downloadingDatabase
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_for_offline_outlined),
                    label: const Text('下載已選地區資料庫'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...controller.selectedProviders.map(
            (provider) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              provider.label,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          if (controller.pendingDatabaseUpdates[provider]
                              case final version?)
                            Chip(
                              avatar: const Icon(Icons.system_update_alt_rounded),
                              label: Text('可更新 v$version'),
                            )
                          else
                            Chip(
                              avatar: Icon(
                                controller.isDatabaseReady(provider)
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.cloud_off_outlined,
                              ),
                              label: Text(
                                controller.isDatabaseReady(provider)
                                    ? '已下載'
                                    : '未下載',
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FutureBuilder<int?>(
                        future: controller.localVersionForProvider(provider),
                        builder: (context, snapshot) {
                          final version = snapshot.data;
                          return Text(
                            version == null || version == 0
                                ? '本機版本：未下載'
                                : '本機版本：$version',
                            style: theme.textTheme.bodyMedium,
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: controller.downloadingDatabase
                                ? null
                                : () => _downloadProviders(
                                    context,
                                    controller,
                                    providers: [provider],
                                    successMessage: '${provider.label} 資料庫已更新。',
                                  ),
                            icon: const Icon(Icons.download_rounded),
                            label: Text(
                              controller.isDatabaseReady(provider) ? '重新下載' : '下載',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: controller.downloadingDatabase
                                ? null
                                : () async {
                                    final messenger = ScaffoldMessenger.of(
                                      context,
                                    );
                                    try {
                                      await controller.deleteProviderDatabase(
                                        provider,
                                      );
                                      if (!context.mounted) {
                                        return;
                                      }
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '${provider.label} 資料庫已刪除。',
                                          ),
                                        ),
                                      );
                                    } catch (error) {
                                      if (!context.mounted) {
                                        return;
                                      }
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text('刪除資料庫失敗：$error'),
                                        ),
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('刪除'),
                          ),
                        ],
                      ),
                      CheckboxListTile(
                        value: !controller.shouldAskDownloadPrompt(provider),
                        onChanged: (value) {
                          controller.setSkipDownloadPrompt(
                            provider,
                            value ?? false,
                          );
                        },
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('未下載時不要再提醒我，直接改走線上 API'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
