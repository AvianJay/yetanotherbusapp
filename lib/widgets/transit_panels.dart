import 'package:flutter/material.dart';

import '../core/transit_repository.dart';

/// Segmented-looking button used by the transit dashboards to switch panels.
///
/// Extracted from three byte-identical private copies (`tra_screen.dart:702`,
/// `thsr_dashboard_screen.dart:729`, `metro_dashboard_screen.dart:880`).
class TransitPanelButton extends StatelessWidget {
  const TransitPanelButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: selected
          ? FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label),
            )
          : FilledButton.tonalIcon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label),
            ),
    );
  }
}

/// Placeholder shown when a panel has nothing to list yet.
class TransitEmptyPanel extends StatelessWidget {
  const TransitEmptyPanel({
    required this.icon,
    required this.label,
    this.action,
    super.key,
  });

  final IconData icon;
  final String label;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: theme.colorScheme.outline),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

/// Full-page error state with a retry button.
class TransitErrorState extends StatelessWidget {
  const TransitErrorState({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重試'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Operating-notice card shared by the TRA and THSR dashboards.
///
/// The two private copies this replaces hard-coded `Colors.orange.shade50` on
/// `Colors.orange.shade900`, which is close to invisible under the AMOLED dark
/// theme (`bus_app.dart:136-147` drives surfaces to near-black). The amber
/// identity is kept — status colours are hard-coded `Colors.*` by convention
/// here — but now picked per brightness.
class RailAlertCard extends StatelessWidget {
  const RailAlertCard({required this.alerts, this.maxAlerts = 3, super.key});

  final List<RailAlert> alerts;
  final int maxAlerts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final background = isDark
        ? Colors.orange.shade900.withValues(alpha: 0.22)
        : Colors.orange.shade50;
    final foreground = isDark ? Colors.orange.shade200 : Colors.orange.shade900;

    return Card(
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: foreground),
                const SizedBox(width: 8),
                Text(
                  '營運公告',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...alerts.take(maxAlerts).map((alert) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• ${alert.title}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Disclosure header that hides the departures a user can no longer catch.
///
/// A full day of 臺北→臺中 is ~65 trains; by early evening ~45 have gone, so
/// showing them all greyed means opening the app to a wall of grey. Collapsed,
/// the first visible row is the next catchable train — which also removes any
/// need for scroll-to-first machinery.
class PastTrainsDisclosure extends StatelessWidget {
  const PastTrainsDisclosure({
    required this.count,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  final int count;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              expanded ? '收合已開出的 $count 班' : '顯示已開出的 $count 班',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
