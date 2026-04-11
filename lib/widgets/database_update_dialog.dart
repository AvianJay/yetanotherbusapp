import 'package:flutter/material.dart';

import '../core/models.dart';

Future<bool> showDatabaseUpdateDialog(
  BuildContext context, {
  required Map<BusProvider, int> updates,
}) async {
  final sortedEntries = updates.entries.toList()
    ..sort((left, right) => left.key.label.compareTo(right.key.label));

  final shouldUpdate =
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('資料庫有新版本'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('已檢查到以下地區有資料庫更新：'),
                const SizedBox(height: 12),
                ...sortedEntries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(child: Text(entry.key.label)),
                        Text('版本 ${entry.value}'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('稍後'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('立即更新'),
              ),
            ],
          );
        },
      ) ??
      false;

  return shouldUpdate;
}
