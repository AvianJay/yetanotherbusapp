import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../app/bus_app.dart';
import '../core/account_sync_models.dart';
import '../core/app_controller.dart';
import '../core/auth_service.dart';
import '../core/friendly_error.dart';

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
      _refreshAccount(controller, quiet: true);
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
      messenger.showSnackBar(const SnackBar(content: Text('無法開啟登入頁面。')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      // is 429?
      if (error.toString().contains('Too Many Requests') ||
          error.toString().contains('429')) {
        messenger.showSnackBar(
          const SnackBar(content: Text('你已受到速率限制。')),
        );
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('登入失敗：${friendlyErrorMessage(error)}')),
      );
    }
  }

  Future<void> _refreshAccount(
    AppController controller, {
    bool quiet = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.refreshAuthAccount();
    } catch (error) {
      if (!mounted || quiet) {
        return;
      }
      if (error.toString().contains('Too Many Requests') ||
          error.toString().contains('429')) {
        messenger.showSnackBar(
          const SnackBar(content: Text('你已受到速率限制。')),
        );
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('重新整理帳號失敗：${friendlyErrorMessage(error)}')),
      );
    }
  }

  Future<void> _toggleSync(AppController controller, bool enabled) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.setAccountSyncEnabled(enabled, syncNow: enabled);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(enabled ? '已開啟自動同步。' : '已關閉自動同步。')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (error.toString().contains('Too Many Requests') ||
          error.toString().contains('429')) {
        messenger.showSnackBar(
          const SnackBar(content: Text('你已受到速率限制。')),
        );
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('更新同步設定失敗：${friendlyErrorMessage(error)}')),
      );
    }
  }

  Future<void> _manualSync(AppController controller) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.syncAllAccountData();
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(const SnackBar(content: Text('同步完成。')));
    } catch (error) {
      if (error is AccountSyncConflictException) {
        await _showSyncConflictDialog(controller, error);
        return;
      }
      if (!mounted) {
        return;
      }
      if (error.toString().contains('Too Many Requests') ||
          error.toString().contains('429')) {
        messenger.showSnackBar(
          const SnackBar(content: Text('你已受到速率限制。')),
        );
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('同步失敗：${friendlyErrorMessage(error)}')),
      );
    }
  }

  Future<void> _showSyncConflictDialog(
    AppController controller,
    AccountSyncConflictException conflict,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final namespace = conflict.namespace;
    final action = await showDialog<_SyncConflictAction>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('同步發生衝突'),
          content: Text(
            conflict.message.trim().isNotEmpty
                ? conflict.message
                : '${namespace.label} 同步時發生衝突。',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_SyncConflictAction.cancel),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_SyncConflictAction.useCloud),
              child: const Text('使用雲端'),
            ),
            if (conflict.canMerge)
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(_SyncConflictAction.merge),
                child: const Text('嘗試合併'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(_SyncConflictAction.overwriteCloud),
              child: const Text('覆蓋雲端'),
            ),
          ],
        );
      },
    );
    if (!mounted || action == null || action == _SyncConflictAction.cancel) {
      return;
    }

    try {
      switch (action) {
        case _SyncConflictAction.cancel:
          return;
        case _SyncConflictAction.useCloud:
          await controller.restoreAccountNamespace(namespace);
        case _SyncConflictAction.merge:
          await controller.syncAccountNamespace(
            namespace,
            conflictPolicy: AccountSyncConflictPolicy.merge,
          );
        case _SyncConflictAction.overwriteCloud:
          await controller.syncAccountNamespace(
            namespace,
            conflictPolicy: namespace == AccountSyncNamespace.preferences
                ? AccountSyncConflictPolicy.clientWins
                : AccountSyncConflictPolicy.clientWins,
          );
      }
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(const SnackBar(content: Text('同步完成。')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('處理同步衝突失敗：${friendlyErrorMessage(error)}')),
      );
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

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final session = controller.authSession;
    final account = controller.authAccount;

    return Scaffold(
      appBar: AppBar(title: const Text('帳號')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              const SizedBox(height: 12),
              if (!controller.isAuthenticated) ...[
                _IntroCard(
                  isAuthenticated: controller.isAuthenticated,
                  displayName:
                      account?.displayName ?? session?.displayName ?? '',
                ),
                _AuthActionsCard(
                  title: '登入',
                  description: '登入來備份你的最愛站牌與設定！',
                  busy: controller.authBusy,
                  onDiscord: () => _startAuthLogin(controller, 'discord'),
                  onGoogle: () => _startAuthLogin(controller, 'google'),
                ),
              ] else ...[
                _LinkedProvidersCard(
                  account: account,
                  session: session,
                  loading: controller.authAccountLoading,
                ),
                const SizedBox(height: 12),
                _SyncCard(
                  enabled: controller.accountSyncEnabled,
                  busy: controller.accountSyncBusy,
                  lastSyncAt: controller.lastAccountSyncAt,
                  onChanged: (value) => _toggleSync(controller, value),
                  onSyncNow: () => _manualSync(controller),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: controller.authBusy
                            ? null
                            : () => _logout(controller),
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('登出'),
                      ),
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
    final title = isAuthenticated ? '已登入' : '尚未登入。';
    final subtitle = isAuthenticated
        ? (displayName.trim().isEmpty ? 'Ciallo～(∠・ω< )⌒☆' : displayName)
        : '使用 Discord 或 Google 繼續以建立或連結您的帳戶。';

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
            Text('已登入', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (loading && identities.isEmpty)
              const LinearProgressIndicator()
            else if (identities.isEmpty && fallbackProvider.isNotEmpty)
              _ProviderTile(
                provider: fallbackProvider,
                label: session?.displayName ?? fallbackProvider,
                detail: '從當前登入令牌載入',
              )
            else if (identities.isEmpty)
              const Text('尚未載入任何連結的提供者詳細資訊。')
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

class _SyncCard extends StatelessWidget {
  const _SyncCard({
    required this.enabled,
    required this.busy,
    required this.lastSyncAt,
    required this.onChanged,
    required this.onSyncNow,
  });

  final bool enabled;
  final bool busy;
  final DateTime? lastSyncAt;
  final ValueChanged<bool> onChanged;
  final VoidCallback onSyncNow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('雲端同步', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: enabled,
              onChanged: busy ? null : onChanged,
              title: const Text('啟用雲端同步'),
              subtitle: Text(
                enabled
                    ? '最後同步時間：${_formatDateTime(lastSyncAt)}'
                    : '同步已關閉。',
              ),
            ),
            // const Divider(height: 24),
            // ListTile(
            //   contentPadding: EdgeInsets.zero,
            //   leading: const Icon(Icons.schedule_rounded),
            //   title: const Text(''),
            //   subtitle: Text(_formatDateTime(lastSyncAt)),
            // ),
            if (busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy ? null : onSyncNow,
              icon: const Icon(Icons.sync_rounded),
              label: const Text('立即同步'),
            ),
          ],
        ),
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
                  label: const Text('使用 Discord 繼續'),
                ),
                FilledButton.tonalIcon(
                  onPressed: busy ? null : onGoogle,
                  icon: const FaIcon(FontAwesomeIcons.google, size: 18),
                  label: const Text('使用 Google 繼續'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return '尚未同步';
  }
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}

enum _SyncConflictAction { cancel, useCloud, merge, overwriteCloud }

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
