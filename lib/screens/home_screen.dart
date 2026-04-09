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
                  'Database',
                  style: Theme.of(sheetContext).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text('Selected region: ${controller.settings.provider.label}'),
                const SizedBox(height: 4),
                FutureBuilder<int?>(
                  future: controller.currentProviderLocalVersion(),
                  builder: (context, snapshot) {
                    final version = snapshot.data;
                    final text = version == null || version == 0
                        ? 'No local database downloaded yet.'
                        : 'Local version: $version';
                    return Text(text);
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  controller.databaseReady
                      ? 'The selected database is ready to use.'
                      : 'Download the selected database to enable route search, favorites refresh, and nearby stops.',
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
                                      '${controller.settings.provider.label} downloaded successfully.',
                                    ),
                                  ),
                                );
                              } catch (error) {
                                if (!context.mounted) {
                                  return;
                                }
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('Download failed: $error'),
                                  ),
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
                            ? 'Downloading...'
                            : (controller.databaseReady
                                  ? 'Redownload'
                                  : 'Download'),
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
                                    ? '${entry.key.label}: up to date'
                                    : '${entry.key.label}: update ${entry.value} available',
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
                            SnackBar(
                              content: Text('Update check failed: $error'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.cloud_sync_outlined),
                      label: const Text('Check updates'),
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
            tooltip: 'Database',
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
                          ? 'Database ready.'
                          : 'No database downloaded yet. You can still browse the app and download it later.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _FeatureCard(
              icon: Icons.search_rounded,
              title: 'Search routes',
              subtitle:
                  'Search the currently selected database and open live ETAs.',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            _FeatureCard(
              icon: Icons.favorite_outline_rounded,
              title: 'Favorites',
              subtitle:
                  'Refresh saved stops and route groups from the selected database.',
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
              title: 'Nearby stops',
              subtitle:
                  'Use your location to find nearby stops inside the selected database.',
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
