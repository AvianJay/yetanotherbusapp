import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../app/bus_app.dart';
import '../core/account_sync_models.dart';
import '../core/app_controller.dart';
import '../core/auth_service.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _requestedInitialRefresh = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requestedInitialRefresh) {
      return;
    }
    final controller = AppControllerScope.of(context);
    if (!controller.isAuthenticated) {
      return;
    }

    _requestedInitialRefresh = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _refreshAccountAndSync(controller, quiet: true);
    });
  }

  Future<void> _startAuthLogin(
    AppController controller,
    String provider,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final opened = await controller.startAuthLogin(provider);
      if (!mounted || opened) {
        return;
      }
      messenger.showSnackBar(const SnackBar(content: Text('無法開啟登入流程。')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('登入失敗：$error')));
    }
  }

  Future<void> _refreshAccountAndSync(
    AppController controller, {
    bool quiet = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.refreshAuthAccount();
      await controller.refreshAccountSyncStatus();
    } catch (error) {
      if (!mounted || quiet) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('重新整理帳號資料失敗：$error')));
    }
  }

  Future<void> _logout(AppController controller) async {
    final messenger = ScaffoldMessenger.of(context);
    await controller.logoutAuth();
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('已登出。')));
  }

  Future<void> _syncAll(AppController controller) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.syncAllAccountData();
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(const SnackBar(content: Text('雲端同步完成。')));
    } catch (error) {
      await _handleSyncError(
        controller,
        error,
        namespace: null,
        defaultConflictMessage: '全部同步時發生衝突。',
      );
    }
  }

  Future<void> _syncNamespace(
    AppController controller,
    AccountSyncNamespace namespace,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.syncAccountNamespace(namespace);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('${namespace.label} 已同步到雲端。')),
      );
    } catch (error) {
      await _handleSyncError(
        controller,
        error,
        namespace: namespace,
        defaultConflictMessage: '${namespace.label} 同步時發生衝突。',
      );
    }
  }

  Future<void> _restoreNamespace(
    AppController controller,
    AccountSyncNamespace namespace,
  ) async {
    final status = controller.accountSyncStatusFor(namespace);
    if (status.localChanges) {
      final confirmed = await _confirmDestructiveAction(
        title: '套用雲端版本？',
        message: '本機的${namespace.shortLabel}有尚未同步的新變更，套用雲端版本會覆蓋本機資料。',
        confirmLabel: '套用雲端',
      );
      if (!confirmed) {
        return;
      }
    }
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.restoreAccountNamespace(namespace);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('已套用雲端${namespace.shortLabel}。')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('套用雲端${namespace.shortLabel}失敗：$error')),
      );
    }
  }

  Future<void> _handleSyncError(
    AppController controller,
    Object error, {
    required AccountSyncNamespace? namespace,
    required String defaultConflictMessage,
  }) async {
    if (!mounted) {
      return;
    }
    if (error is AccountSyncConflictException) {
      await _showConflictDialog(
        controller,
        error,
        fallbackNamespace: namespace,
        defaultConflictMessage: defaultConflictMessage,
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('同步失敗：$error')));
  }

  Future<void> _showConflictDialog(
    AppController controller,
    AccountSyncConflictException conflict, {
    required AccountSyncNamespace? fallbackNamespace,
    required String defaultConflictMessage,
  }) async {
    final namespace = fallbackNamespace ?? conflict.namespace;
    final message = conflict.message.trim().isEmpty
        ? defaultConflictMessage
        : conflict.message;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('${namespace.label} 發生衝突'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 12),
              Text(
                '你可以選擇保留本機、保留雲端，或在支援時嘗試合併。',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
              if (conflict.serverDocument?.updatedAt case final updatedAt?)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '雲端最後更新：${_formatDateTime(updatedAt)}',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _restoreNamespace(controller, namespace);
              },
              child: const Text('套用雲端'),
            ),
            if (conflict.canMerge)
              FilledButton.tonal(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await _retryConflictAction(
                    controller,
                    namespace,
                    AccountSyncConflictPolicy.merge,
                    successMessage: '${namespace.label} 已合併同步。',
                  );
                },
                child: const Text('嘗試合併'),
              ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                final confirmed = await _confirmDestructiveAction(
                  title: '覆蓋雲端版本？',
                  message: '這會用本機的${namespace.shortLabel}覆蓋目前雲端資料。',
                  confirmLabel: '覆蓋雲端',
                );
                if (!confirmed) {
                  return;
                }
                await _retryConflictAction(
                  controller,
                  namespace,
                  AccountSyncConflictPolicy.clientWins,
                  successMessage: '已用本機資料覆蓋雲端${namespace.shortLabel}。',
                );
              },
              child: const Text('保留本機'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _retryConflictAction(
    AppController controller,
    AccountSyncNamespace namespace,
    AccountSyncConflictPolicy policy, {
    required String successMessage,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.syncAccountNamespace(namespace, conflictPolicy: policy);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('處理同步衝突失敗：$error')));
    }
  }

  Future<bool> _confirmDestructiveAction({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final session = controller.authSession;
    final account = controller.authAccount;

    return Scaffold(
      appBar: AppBar(title: const Text('帳號')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              const SizedBox(height: 12),
              if (!controller.isAuthenticated) ...[
                _IntroCard(
                  isAuthenticated: false,
                  displayName:
                      account?.displayName ?? session?.displayName ?? '',
                ),
                const SizedBox(height: 12),
                _AuthActionsCard(
                  title: '登入',
                  description: '登入後即可同步最愛站牌、分類與偏好設定，並查看目前的同步狀態。',
                  busy: controller.authBusy,
                  onDiscord: () => _startAuthLogin(controller, 'discord'),
                  onGoogle: () => _startAuthLogin(controller, 'google'),
                ),
              ] else ...[
                _IntroCard(
                  isAuthenticated: true,
                  displayName:
                      account?.displayName ?? session?.displayName ?? '',
                ),
                const SizedBox(height: 12),
                _AccountSummaryCard(
                  account: account,
                  session: session,
                  loading: controller.authAccountLoading,
                  onRefresh: () => _refreshAccountAndSync(controller),
                ),
                const SizedBox(height: 12),
                _LinkedProvidersCard(
                  account: account,
                  session: session,
                  loading: controller.authAccountLoading,
                ),
                const SizedBox(height: 12),
                _CloudSyncCard(
                  controller: controller,
                  onRefresh: () => _refreshAccountAndSync(controller),
                  onSyncAll: () => _syncAll(controller),
                  onSyncNamespace: (namespace) =>
                      _syncNamespace(controller, namespace),
                  onRestoreNamespace: (namespace) =>
                      _restoreNamespace(controller, namespace),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: OutlinedButton.icon(
                      onPressed: controller.authBusy
                          ? null
                          : () => _logout(controller),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('登出'),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.isAuthenticated, required this.displayName});

  final bool isAuthenticated;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = isAuthenticated ? '已登入' : '登入帳號';
    final subtitle = isAuthenticated
        ? (displayName.trim().isEmpty ? '帳號已連線。' : displayName)
        : '登入後可以把最愛站牌、分類與偏好設定備份到雲端。';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              child: Icon(
                isAuthenticated
                    ? Icons.verified_user_outlined
                    : Icons.account_circle_outlined,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(subtitle, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountSummaryCard extends StatelessWidget {
  const _AccountSummaryCard({
    required this.account,
    required this.session,
    required this.loading,
    required this.onRefresh,
  });

  final AuthAccount? account;
  final AuthSession? session;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accountId = account?.accountId ?? session?.accountId ?? '';
    final deviceId = account?.deviceId ?? session?.deviceId ?? '';
    final role = account?.role ?? session?.role ?? 'user';
    final deviceName = account?.device?.deviceName?.trim() ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('帳戶資訊', style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: '重新整理',
                  onPressed: loading ? null : onRefresh,
                  icon: loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _DetailRow(label: 'Account ID', value: accountId),
            _DetailRow(label: 'Device ID', value: deviceId),
            _DetailRow(label: 'Role', value: role),
            if (deviceName.isNotEmpty)
              _DetailRow(label: 'Device', value: deviceName),
          ],
        ),
      ),
    );
  }
}

class _LinkedProvidersCard extends StatelessWidget {
  const _LinkedProvidersCard({
    required this.account,
    required this.session,
    required this.loading,
  });

  final AuthAccount? account;
  final AuthSession? session;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final identities = account?.identities ?? const <AuthIdentity>[];
    final fallbackProvider = session?.provider ?? '';
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('已連結的登入方式', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (loading && identities.isEmpty)
              const LinearProgressIndicator()
            else if (identities.isEmpty && fallbackProvider.isNotEmpty)
              _ProviderTile(
                provider: fallbackProvider,
                label: session?.displayName ?? fallbackProvider,
                detail: '已登入，但帳戶資訊還在更新。',
              )
            else if (identities.isEmpty)
              const Text('目前還沒有可顯示的登入資訊。')
            else
              for (final identity in identities)
                _ProviderTile(
                  provider: identity.provider,
                  label: identity.label,
                  detail: identity.email.isEmpty
                      ? identity.providerUserId
                      : identity.email,
                ),
          ],
        ),
      ),
    );
  }
}

class _CloudSyncCard extends StatelessWidget {
  const _CloudSyncCard({
    required this.controller,
    required this.onRefresh,
    required this.onSyncAll,
    required this.onSyncNamespace,
    required this.onRestoreNamespace,
  });

  final AppController controller;
  final VoidCallback onRefresh;
  final VoidCallback onSyncAll;
  final void Function(AccountSyncNamespace namespace) onSyncNamespace;
  final void Function(AccountSyncNamespace namespace) onRestoreNamespace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final favoriteCount = controller.favoriteGroups.values.fold<int>(
      0,
      (total, group) => total + group.length,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('雲端同步', style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: '重新整理同步狀態',
                  onPressed: controller.accountSyncBusy ? null : onRefresh,
                  icon: controller.accountSyncBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '這裡會同步最愛站牌與分類，以及主題、顏色與使用／更新相關偏好設定。'
              ' 最愛站牌雲端備份上限為 25 筆。',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: controller.accountSyncBusy ? null : onSyncAll,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('同步全部到雲端'),
                ),
                if (controller.accountSyncError?.trim().isNotEmpty == true)
                  Chip(
                    avatar: const Icon(Icons.error_outline_rounded, size: 18),
                    label: Text(controller.accountSyncError!),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _CloudSyncNamespacePanel(
              namespace: AccountSyncNamespace.favorites,
              status: controller.accountSyncStatusFor(
                AccountSyncNamespace.favorites,
              ),
              description: '同步最愛站牌與分類，不會上傳空分類。',
              localCountLabel: '$favoriteCount / 25 筆',
              onSync: () => onSyncNamespace(AccountSyncNamespace.favorites),
              onRestore: () =>
                  onRestoreNamespace(AccountSyncNamespace.favorites),
              busy: controller.accountSyncBusy,
            ),
            const SizedBox(height: 16),
            _CloudSyncNamespacePanel(
              namespace: AccountSyncNamespace.preferences,
              status: controller.accountSyncStatusFor(
                AccountSyncNamespace.preferences,
              ),
              description:
                  '同步主題、顏色，以及使用與更新相關偏好。'
                  ' 不支援的平台會忽略對應設定。',
              localCountLabel: '已包含偏好設定',
              onSync: () => onSyncNamespace(AccountSyncNamespace.preferences),
              onRestore: () =>
                  onRestoreNamespace(AccountSyncNamespace.preferences),
              busy: controller.accountSyncBusy,
            ),
          ],
        ),
      ),
    );
  }
}

class _CloudSyncNamespacePanel extends StatelessWidget {
  const _CloudSyncNamespacePanel({
    required this.namespace,
    required this.status,
    required this.description,
    required this.localCountLabel,
    required this.onSync,
    required this.onRestore,
    required this.busy,
  });

  final AccountSyncNamespace namespace;
  final AccountSyncNamespaceStatus status;
  final String description;
  final String localCountLabel;
  final VoidCallback onSync;
  final VoidCallback onRestore;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chipStyle = _statusStyle(colorScheme, status.health);
    final document = status.serverDocument;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(namespace.label, style: theme.textTheme.titleSmall),
              ),
              Chip(
                backgroundColor: chipStyle.background,
                avatar: Icon(
                  chipStyle.icon,
                  size: 18,
                  color: chipStyle.foreground,
                ),
                label: Text(
                  status.healthLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: chipStyle.foreground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(description, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              _MetaItem(label: '本機資料', value: localCountLabel),
              _MetaItem(
                label: '本機最後變更',
                value: _formatDateTime(status.localModifiedAt),
              ),
              _MetaItem(
                label: '最後同步',
                value: _formatDateTime(status.localState.lastSuccessfulSyncAt),
              ),
              _MetaItem(
                label: '雲端最後更新',
                value: _formatDateTime(document?.updatedAt),
              ),
              _MetaItem(
                label: '雲端修訂版',
                value: document == null || !document.hasData
                    ? '-'
                    : 'r${document.revision}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.tonalIcon(
                onPressed: busy ? null : onSync,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(document?.hasData == true ? '同步到雲端' : '建立雲端備份'),
              ),
              OutlinedButton.icon(
                onPressed: busy || !(document?.hasData ?? false)
                    ? null
                    : onRestore,
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('套用雲端版本'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AuthActionsCard extends StatelessWidget {
  const _AuthActionsCard({
    required this.title,
    required this.description,
    required this.busy,
    required this.onDiscord,
    required this.onGoogle,
  });

  final String title;
  final String description;
  final bool busy;
  final VoidCallback onDiscord;
  final VoidCallback onGoogle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(description),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : onDiscord,
                  icon: const FaIcon(FontAwesomeIcons.discord, size: 18),
                  label: const Text('使用 Discord 登入'),
                ),
                FilledButton.tonalIcon(
                  onPressed: busy ? null : onGoogle,
                  icon: const FaIcon(FontAwesomeIcons.google, size: 18),
                  label: const Text('使用 Google 登入'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: SelectableText(
              value.trim().isEmpty ? '-' : value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.provider,
    required this.label,
    required this.detail,
  });

  final String provider;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: _providerIcon(provider)),
      title: Text(label.trim().isEmpty ? _providerName(provider) : label),
      subtitle: Text(detail.trim().isEmpty ? _providerName(provider) : detail),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _StatusChipStyle {
  const _StatusChipStyle({
    required this.background,
    required this.foreground,
    required this.icon,
  });

  final Color background;
  final Color foreground;
  final IconData icon;
}

_StatusChipStyle _statusStyle(
  ColorScheme colorScheme,
  AccountSyncHealth health,
) {
  return switch (health) {
    AccountSyncHealth.inSync => _StatusChipStyle(
      background: colorScheme.secondaryContainer,
      foreground: colorScheme.onSecondaryContainer,
      icon: Icons.cloud_done_outlined,
    ),
    AccountSyncHealth.localChanges => _StatusChipStyle(
      background: colorScheme.tertiaryContainer,
      foreground: colorScheme.onTertiaryContainer,
      icon: Icons.upload_file_outlined,
    ),
    AccountSyncHealth.cloudChanges => _StatusChipStyle(
      background: colorScheme.primaryContainer,
      foreground: colorScheme.onPrimaryContainer,
      icon: Icons.download_for_offline_outlined,
    ),
    AccountSyncHealth.conflict => _StatusChipStyle(
      background: colorScheme.errorContainer,
      foreground: colorScheme.onErrorContainer,
      icon: Icons.warning_amber_rounded,
    ),
    AccountSyncHealth.noBackup => _StatusChipStyle(
      background: colorScheme.surfaceContainerHighest,
      foreground: colorScheme.onSurfaceVariant,
      icon: Icons.cloud_off_outlined,
    ),
    AccountSyncHealth.unknown => _StatusChipStyle(
      background: colorScheme.surfaceContainerHighest,
      foreground: colorScheme.onSurfaceVariant,
      icon: Icons.help_outline_rounded,
    ),
  };
}

Widget _providerIcon(String provider) {
  switch (provider) {
    case 'discord':
      return const FaIcon(FontAwesomeIcons.discord, size: 18);
    case 'google':
      return const FaIcon(FontAwesomeIcons.google, size: 18);
    default:
      return const Icon(Icons.link_rounded, size: 18);
  }
}

String _providerName(String provider) {
  switch (provider) {
    case 'discord':
      return 'Discord';
    case 'google':
      return 'Google';
    default:
      return provider.trim().isEmpty ? 'OAuth' : provider;
  }
}

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return '-';
  }
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}
