import 'package:flutter/material.dart';

import '../app/bus_app.dart';

class FavoriteGroupsScreen extends StatelessWidget {
  const FavoriteGroupsScreen({super.key});

  Future<void> _showAddGroupDialog(BuildContext context) async {
    final controller = AppControllerScope.read(context);
    final textController = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新增群組'),
          content: TextField(
            controller: textController,
            autofocus: true,
            decoration: const InputDecoration(hintText: '例如：回家'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(textController.text),
              child: const Text('新增'),
            ),
          ],
        );
      },
    );

    textController.dispose();
    if (name == null || name.trim().isEmpty) {
      return;
    }

    await controller.addFavoriteGroup(name);
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
                          subtitle: Text('$count 個站牌'),
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
