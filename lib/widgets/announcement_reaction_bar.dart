import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

import '../app/bus_app.dart';
import '../core/announcement_models.dart';
import '../core/app_routes.dart';

/// A Discord-style reaction bar: a wrap of emoji count chips plus an add
/// button. Tapping a chip toggles the signed-in user's reaction; the add
/// button opens an emoji picker. Anonymous users see the counts but are
/// prompted to log in when they try to react.
class AnnouncementReactionBar extends StatelessWidget {
  const AnnouncementReactionBar({required this.announcement, super.key});

  final AppAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final reaction in announcement.reactions)
          FilterChip(
            label: Text('${reaction.emoji} ${reaction.count}'),
            selected: announcement.myReactions.contains(reaction.emoji),
            showCheckmark: false,
            onSelected: (_) => _toggle(context, reaction.emoji),
          ),
        ActionChip(
          avatar: const Icon(Icons.add_reaction_outlined, size: 18),
          label: const Text('反應'),
          tooltip: '新增表情符號反應',
          onPressed: () => _openPicker(context),
        ),
        if (announcement.reactions.isEmpty)
          Text(
            '成為第一個反應的人',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    if (!_ensureLoggedIn(context)) {
      return;
    }
    final theme = Theme.of(context);
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: 320,
            child: EmojiPicker(
              onEmojiSelected: (category, emoji) {
                Navigator.of(sheetContext).pop(emoji.emoji);
              },
              config: Config(
                height: 320,
                checkPlatformCompatibility: true,
                emojiViewConfig: EmojiViewConfig(
                  backgroundColor: theme.colorScheme.surface,
                ),
                categoryViewConfig: CategoryViewConfig(
                  backgroundColor: theme.colorScheme.surface,
                  iconColorSelected: theme.colorScheme.primary,
                  indicatorColor: theme.colorScheme.primary,
                ),
                bottomActionBarConfig: const BottomActionBarConfig(
                  enabled: false,
                ),
              ),
            ),
          ),
        );
      },
    );
    if (selected != null && selected.isNotEmpty && context.mounted) {
      await _toggle(context, selected);
    }
  }

  Future<void> _toggle(BuildContext context, String emoji) async {
    if (!_ensureLoggedIn(context)) {
      return;
    }
    final controller = AppControllerScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.toggleAnnouncementReaction(announcement.id, emoji);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('無法更新反應，請稍後再試。')),
      );
    }
  }

  bool _ensureLoggedIn(BuildContext context) {
    final controller = AppControllerScope.read(context);
    if (controller.isAuthenticated) {
      return true;
    }
    final navigator = Navigator.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('請先登入才能新增反應'),
        action: SnackBarAction(
          label: '登入',
          onPressed: () => navigator.pushNamed(AppRoutes.account),
        ),
      ),
    );
    return false;
  }
}
