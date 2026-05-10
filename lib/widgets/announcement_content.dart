import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../core/announcement_models.dart';
import '../core/app_link_handler.dart';
import '../core/relative_time_formatter.dart';

class AnnouncementContent extends StatelessWidget {
  const AnnouncementContent({
    required this.announcement,
    this.compact = false,
    super.key,
  });

  final AppAnnouncement announcement;
  final bool compact;

  Future<void> _openLink(BuildContext context, String url) async {
    final opened = await openAppLink(context, url);
    if (!context.mounted || opened) {
      return;
    }
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('無法開啟連結。')));
  }

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      Chip(
        avatar: const Icon(Icons.schedule_outlined, size: 18),
        label: Text(formatRelativeTimestamp(announcement.createdAtDateTime)),
      ),
      if (announcement.author case final author?)
        Chip(
          avatar: const Icon(Icons.person_outline_rounded, size: 18),
          label: Text(author),
        ),
      // if (announcement.expireAtDateTime case final expireAt?)
      //   Chip(
      //     avatar: const Icon(Icons.hourglass_bottom_rounded, size: 18),
      //     label: Text('到 ${_formatTimestamp(expireAt)}'),
      //   ),
      // if (announcement.behavior.redDot == AnnouncementRepeatBehavior.forever)
      //   const Chip(
      //     avatar: Icon(Icons.brightness_1_rounded, size: 14),
      //     label: Text('紅點持續顯示'),
      //   ),
      // if (announcement.behavior.popup == AnnouncementRepeatBehavior.forever)
      //   const Chip(
      //     avatar: Icon(Icons.notification_important_outlined, size: 18),
      //     label: Text('持續彈出'),
      //   ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: chips),
        const SizedBox(height: 16),
        MarkdownBody(
          data: announcement.content,
          onTapLink: (text, href, title) {
            if (href != null) {
              _openLink(context, href);
            }
          },
        ),
        if (announcement.embed case final embed?) ...[
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: const Icon(Icons.ondemand_video_outlined),
              title: Text(embed.type.isEmpty ? '嵌入內容' : embed.type),
              subtitle: Text(embed.url),
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: () => _openLink(context, embed.url),
            ),
          ),
        ],
        if (announcement.soundUrl case final soundUrl?) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.volume_up_outlined),
              title: const Text('提示音'),
              subtitle: Text(soundUrl),
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: () => _openLink(context, soundUrl),
            ),
          ),
        ],
        if (announcement.actions.isNotEmpty) ...[
          // const SizedBox(height: 20),
          // Text('操作', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final action in announcement.actions)
                FilledButton.tonal(
                  onPressed: action.url.isEmpty
                      ? null
                      : () => _openLink(context, action.url),
                  child: Text(action.label),
                ),
            ],
          ),
        ],
        if (!compact) const SizedBox(height: 24),
      ],
    );
  }
}
