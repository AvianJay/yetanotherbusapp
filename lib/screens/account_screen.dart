import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../app/bus_app.dart';
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
      messenger.showSnackBar(const SnackBar(content: Text('無法開啟登入頁面 :(')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('登入失敗: $error')));
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
      messenger.showSnackBar(SnackBar(content: Text('無法刷新帳戶資訊: $error')));
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
      appBar: AppBar(title: const Text('帳戶')),
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
                  description: '登入來備份你的最愛站牌與設定！（WIP）',
                  busy: controller.authBusy,
                  onDiscord: () => _startAuthLogin(controller, 'discord'),
                  onGoogle: () => _startAuthLogin(controller, 'google'),
                ),
              ] else ...[
                // _AccountSummaryCard(
                //   account: account,
                //   session: session,
                //   loading: controller.authAccountLoading,
                //   onRefresh: () => _refreshAccount(controller),
                // ),
                // const SizedBox(height: 12),
                _LinkedProvidersCard(
                  account: account,
                  session: session,
                  loading: controller.authAccountLoading,
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

// ignore: unused_element
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
    // final accountId = account?.accountId ?? session?.accountId ?? '';
    // final deviceId = account?.deviceId ?? session?.deviceId ?? '';
    // final role = account?.role ?? session?.role ?? 'user';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('當前帳戶資訊', style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: '刷新',
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
            // const SizedBox(height: 8),
            // _DetailRow(label: 'Account ID', value: accountId),
            // _DetailRow(label: 'Device ID', value: deviceId),
            // _DetailRow(label: 'Role', value: role),
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

// ignore: unused_element
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
