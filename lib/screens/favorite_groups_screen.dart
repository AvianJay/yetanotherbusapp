import 'package:flutter/material.dart';

import '../app/bus_app.dart';
import '../core/models.dart';

class FavoriteGroupDraft {
  const FavoriteGroupDraft({required this.name, required this.kind});

  final String name;
  final FavoriteGroupKind kind;
}

Future<FavoriteGroupDraft?> showFavoriteGroupDialog(
  BuildContext context, {
  FavoriteGroupKind initialKind = FavoriteGroupKind.boarding,
  FavoriteItemType? compatibleItemType,
}) async {
  final textController = TextEditingController();
  var selectedKind = initialKind;
  final selectableKinds = compatibleItemType == null
      ? FavoriteGroupKind.values
      : FavoriteGroupKind.values
            .where((kind) => kind.acceptsType(compatibleItemType))
            .toList(growable: false);
  final result = await showDialog<FavoriteGroupDraft>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: const Text('新增群組'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '群組名稱',
                  hintText: '例如：回家',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<FavoriteGroupKind>(
                initialValue: selectedKind,
                decoration: const InputDecoration(labelText: '收藏類別'),
                items: selectableKinds
                    .map(
                      (kind) => DropdownMenuItem(
                        value: kind,
                        child: Text(kind.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (kind) {
                  if (kind != null) {
                    setState(() => selectedKind = kind);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = textController.text.trim();
                if (name.isEmpty) {
                  return;
                }
                Navigator.of(
                  context,
                ).pop(FavoriteGroupDraft(name: name, kind: selectedKind));
              },
              child: const Text('新增'),
            ),
          ],
        );
      },
    ),
  );
  textController.dispose();
  return result;
}

class FavoriteGroupsScreen extends StatelessWidget {
  const FavoriteGroupsScreen({super.key});

  Future<void> _showAddGroupDialog(BuildContext context) async {
    final controller = AppControllerScope.read(context);
    final draft = await showFavoriteGroupDialog(context);
    if (draft == null) {
      return;
    }
    if (controller.favoriteGroups.containsKey(draft.name)) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已有相同名稱的收藏群組。')));
      }
      return;
    }
    await controller.addFavoriteGroup(draft.name, kind: draft.kind);
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final groups = controller.favoriteGroupNames;

    return Scaffold(
      appBar: AppBar(
        title: const Text('最愛群組'),
        actions: [
          IconButton(
            onPressed: () => _showAddGroupDialog(context),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: groups.isEmpty
          ? const Center(child: Text('還沒有群組。'))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  itemCount: groups.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    final count = controller.favoriteGroups[group]?.length ?? 0;
                    final kind = controller.favoriteGroupKind(group);
                    return Dismissible(
                      key: ValueKey(group),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                      confirmDismiss: (_) async {
                        final shouldDelete = await showDialog<bool>(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              title: const Text('刪除群組'),
                              content: Text('確定要刪除「$group」嗎？'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: const Text('刪除'),
                                ),
                              ],
                            );
                          },
                        );
                        return shouldDelete ?? false;
                      },
                      onDismissed: (_) async {
                        await controller.deleteFavoriteGroup(group);
                      },
                      child: Card(
                        child: ListTile(
                          title: Text(group),
                          subtitle: Text('${kind.label} · $count 個收藏'),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }
}
