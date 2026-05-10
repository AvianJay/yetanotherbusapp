import 'dart:async';

import 'package:flutter/material.dart';

import '../app/bus_app.dart';
// import '../core/announcement_models.dart';
import '../core/app_routes.dart';
import '../core/relative_time_formatter.dart';

class AnnouncementsPage extends StatefulWidget {
  const AnnouncementsPage({super.key});

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadAnnouncements());
    });
  }

  Future<void> _loadAnnouncements({bool force = false}) async {
    final controller = AppControllerScope.read(context);
    if (force) {
      await controller.refreshAnnouncements(force: true);
    } else {
      await controller.ensureAnnouncementsLoaded();
    }
    await controller.markAnnouncementListViewed();
  }

  String _excerpt(String markdown) {
    final normalized = markdown
        .replaceAll(RegExp(r'[#>*_`\[\]\(\)!-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.length <= 92) {
      return normalized;
    }
    return '${normalized.substring(0, 92)}…';
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final announcements = controller.announcements;
        final error = controller.announcementsError;
        final loading = controller.announcementsLoading;

        return Scaffold(
          appBar: AppBar(
            title: const Text('公告'),
            actions: [
              IconButton(
                tooltip: '重新整理',
                onPressed: loading ? null : () => _loadAnnouncements(force: true),
                icon: loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: loading && announcements.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () => _loadAnnouncements(force: true),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      if (error != null)
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 920),
                            child: SizedBox(
                              width: double.infinity,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Card(
                                  color: theme.colorScheme.errorContainer,
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '公告同步失敗',
                                          style: theme.textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(error),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (announcements.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                const Icon(Icons.campaign_outlined, size: 40),
                                const SizedBox(height: 12),
                                Text(
                                  '目前沒有公告。',
                                  style: theme.textTheme.titleMedium,
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        for (final announcement in announcements) ...[
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 920),
                              child: SizedBox(
                                width: double.infinity,
                                child: Card(
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(24),
                                    onTap: () {
                                      Navigator.of(context).pushNamed(
                                        AppRoutes.announcementDetailPath(
                                          announcement.id,
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(18),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            announcement.title,
                                            style: theme.textTheme.titleLarge,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(_excerpt(announcement.content)),
                                          const SizedBox(height: 12),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              Chip(
                                                avatar: const Icon(
                                                  Icons.schedule_outlined,
                                                  size: 18,
                                                ),
                                                label: Text(
                                                  formatRelativeTimestamp(
                                                    announcement.createdAtDateTime,
                                                  ),
                                                ),
                                              ),
                                              if (announcement.author case final author?)
                                                Chip(
                                                  avatar: const Icon(
                                                    Icons.person_outline_rounded,
                                                    size: 18,
                                                  ),
                                                  label: Text(author),
                                                ),
                                              // if (announcement.behavior.popup ==
                                              //     AnnouncementRepeatBehavior.forever)
                                              //   const Chip(
                                              //     avatar: Icon(
                                              //       Icons.notification_important_outlined,
                                              //       size: 18,
                                              //     ),
                                              //     label: Text('持續彈出'),
                                              //   ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                    ],
                  ),
                ),
        );
      },
    );
  }
}
