import 'package:flutter/material.dart';

enum CatStateMood { sad, cry, laugh }

class CatStateCard extends StatelessWidget {
  const CatStateCard({
    required this.title,
    this.message,
    this.mood = CatStateMood.sad,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.all(20),
    super.key,
  });

  final String title;
  final String? message;
  final CatStateMood mood;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  String get _assetPath => switch (mood) {
    CatStateMood.sad => 'assets/cat_sad.png',
    CatStateMood.cry => 'assets/cat_cry.png',
    CatStateMood.laugh => 'assets/cat_laugh.png',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionLabel = this.actionLabel;
    final onAction = this.onAction;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 112,
              height: 112,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.45,
                ),
                shape: BoxShape.circle,
              ),
              child: Image.asset(_assetPath, fit: BoxFit.contain),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (message != null && message!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
