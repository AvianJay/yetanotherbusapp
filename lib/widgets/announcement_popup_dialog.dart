import 'package:flutter/material.dart';

import '../core/announcement_models.dart';
import 'announcement_content.dart';

enum AnnouncementPopupResult { later, dismissForever, viewDetails }

Future<AnnouncementPopupResult> showAnnouncementPopupDialog(
  BuildContext context, {
  required AppAnnouncement announcement,
}) async {
  final result = await showDialog<AnnouncementPopupResult>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(announcement.title),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: AnnouncementContent(announcement: announcement, compact: true),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(AnnouncementPopupResult.later),
            child: const Text('稍後'),
          ),
          if (announcement.behavior.popup == AnnouncementRepeatBehavior.forever)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                AnnouncementPopupResult.dismissForever,
              ),
              child: const Text('不再顯示'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(AnnouncementPopupResult.viewDetails),
            child: const Text('查看公告'),
          ),
        ],
      );
    },
  );
  return result ?? AnnouncementPopupResult.later;
}