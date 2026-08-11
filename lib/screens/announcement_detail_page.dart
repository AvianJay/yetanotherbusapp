import 'dart:async';

import 'package:flutter/material.dart';

import '../app/bus_app.dart';
import '../widgets/announcement_content.dart';
import '../widgets/announcement_reaction_bar.dart';

class AnnouncementDetailPage extends StatefulWidget {
  const AnnouncementDetailPage({required this.announcementId, super.key});

  final String announcementId;

  @override
  State<AnnouncementDetailPage> createState() => _AnnouncementDetailPageState();
}

class _AnnouncementDetailPageState extends State<AnnouncementDetailPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(AppControllerScope.read(context).ensureAnnouncementsLoaded());
    });
  }

  Future<void> _refresh() {
    return AppControllerScope.read(context).refreshAnnouncements(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final announcement = controller.findAnnouncementById(widget.announcementId);
        final loading = controller.announcementsLoading;
        final error = controller.announcementsError;

        return Scaffold(
          appBar: AppBar(
            title: Text(announcement?.title ?? '公告'),
            actions: [
              IconButton(
                tooltip: '重新整理',
                onPressed: loading ? null : _refresh,
                icon: loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: announcement == null && loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 920),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: announcement == null
                                  ? Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '找不到這則公告。',
                                          style: theme.textTheme.titleMedium,
                                        ),
                                        if (error != null) ...[
                                          const SizedBox(height: 8),
                                          Text(error),
                                        ],
                                        const SizedBox(height: 12),
                                        FilledButton.tonalIcon(
                                          onPressed: _refresh,
                                          icon: const Icon(Icons.refresh_rounded),
                                          label: const Text('重新同步公告'),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (error != null) ...[
                                          Card(
                                            color: theme.colorScheme.errorContainer,
                                            child: Padding(
                                              padding: const EdgeInsets.all(16),
                                              child: Text(error),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                        ],
                                        AnnouncementContent(
                                          announcement: announcement,
                                        ),
                                        const Divider(height: 24),
                                        AnnouncementReactionBar(
                                          announcement: announcement,
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}