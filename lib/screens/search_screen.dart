import 'dart:async';

import 'package:flutter/material.dart';

import '../app/bus_app.dart';
import '../core/app_controller.dart';
import '../core/models.dart';
import 'route_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  final Set<BusProvider> _apiAllowedThisSession = <BusProvider>{};
  bool _isLoading = false;
  String? _error;
  List<RouteSummary> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _isLoading = false;
        _error = null;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_search(value));
    });
  }

  Future<bool> _ensureProvidersReadyForSearch(
    AppController busController,
  ) async {
    for (final provider in busController.selectedProviders) {
      if (busController.isDatabaseReady(provider)) {
        continue;
      }
      if (!busController.shouldAskDownloadPrompt(provider) ||
          _apiAllowedThisSession.contains(provider)) {
        continue;
      }

      final action = await _showMissingDatabaseDialog(provider);
      if (!mounted) {
        return false;
      }

      switch (action) {
        case _MissingDatabaseAction.download:
          await busController.downloadProviderDatabase(provider);
          if (!mounted) {
            return false;
          }
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('${provider.label} 資料庫下載完成。')));
          break;
        case _MissingDatabaseAction.apiOnce:
          _apiAllowedThisSession.add(provider);
          break;
        case _MissingDatabaseAction.apiAlways:
          _apiAllowedThisSession.add(provider);
          await busController.setSkipDownloadPrompt(provider, true);
          break;
        case _MissingDatabaseAction.cancel:
          return false;
      }
    }

    return true;
  }

  Future<_MissingDatabaseAction> _showMissingDatabaseDialog(
    BusProvider provider,
  ) async {
    final action = await showDialog<_MissingDatabaseAction>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('${provider.label} 尚未下載'),
          content: const Text('要先下載資料庫，或改為直接使用 API 查詢？'),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_MissingDatabaseAction.cancel),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_MissingDatabaseAction.apiOnce),
              child: const Text('這次用 API'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_MissingDatabaseAction.apiAlways),
              child: const Text('改用 API 且不再詢問'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_MissingDatabaseAction.download),
              child: const Text('下載資料庫'),
            ),
          ],
        );
      },
    );
    return action ?? _MissingDatabaseAction.cancel;
  }

  Future<void> _search(String query) async {
    final busController = AppControllerScope.read(context);
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final shouldContinue = await _ensureProvidersReadyForSearch(
        busController,
      );
      if (!shouldContinue) {
        return;
      }

      final results = <RouteSummary>[];
      for (final provider in busController.selectedProviders) {
        if (busController.isDatabaseReady(provider)) {
          results.addAll(
            await busController.searchRoutes(query, provider: provider),
          );
        } else if (!busController.shouldAskDownloadPrompt(provider) ||
            _apiAllowedThisSession.contains(provider)) {
          results.addAll(
            await busController.searchRoutesViaApi(query, provider: provider),
          );
        }
      }

      results.sort((left, right) {
        final leftDownloaded = busController.isDatabaseReady(
          busProviderFromString(left.sourceProvider),
        );
        final rightDownloaded = busController.isDatabaseReady(
          busProviderFromString(right.sourceProvider),
        );
        if (leftDownloaded != rightDownloaded) {
          return leftDownloaded ? -1 : 1;
        }
        return left.routeName.compareTo(right.routeName);
      });

      if (!mounted) {
        return;
      }
      setState(() {
        _results = results;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openRoute({
    required BusProvider provider,
    required int routeKey,
    required String routeName,
    String? routeIdHint,
    int? initialPathId,
    RouteSummary? route,
    bool saveHistory = false,
  }) async {
    final busController = AppControllerScope.read(context);
    if (saveHistory && route != null) {
      await busController.addHistoryEntry(route, provider: provider);
    }
    await busController.recordRouteSelection(
      provider: provider,
      routeKey: routeKey,
      routeName: routeName,
    );
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RouteDetailScreen(
          routeKey: routeKey,
          provider: provider,
          routeIdHint: routeIdHint,
          routeNameHint: routeName,
          initialPathId: initialPathId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busController = AppControllerScope.of(context);
    final selectedProviders = busController.selectedProviders;
    final missingProviders = selectedProviders
        .where((provider) => !busController.isDatabaseReady(provider))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('搜尋路線')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          TextField(
            controller: _controller,
            onChanged: _onQueryChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (value) => _search(value),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: '輸入公車號碼或路線名稱',
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _controller.clear();
                        setState(() {});
                        _onQueryChanged('');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          if (missingProviders.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '尚未下載：${missingProviders.map((provider) => provider.label).join('、')}。\n'
                  '搜尋時會先用已下載資料庫；未下載縣市可選擇下載或改走 API。',
                ),
              ),
            ),
          if (_controller.text.trim().isEmpty)
            _HistorySection(
              history: busController.history,
              onClear: busController.clearHistory,
              onSelect: (entry) {
                unawaited(
                  _openRoute(
                    provider: entry.provider,
                    routeKey: entry.routeKey,
                    routeName: entry.routeName,
                    routeIdHint: entry.routeId,
                  ),
                );
              },
            )
          else if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('搜尋失敗：$_error'),
              ),
            )
          else if (_results.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('找不到符合的路線。'),
              ),
            )
          else
            ..._results.map(
              (route) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        route.routeName.trim().isEmpty
                            ? '?'
                            : route.routeName.characters.first,
                      ),
                    ),
                    title: Text(route.routeName),
                    subtitle: Text(
                      route.description.trim().isEmpty
                          ? busProviderFromString(route.sourceProvider).label
                          : route.description,
                    ),
                    onTap: () async {
                      final routeProvider = busProviderFromString(
                        route.sourceProvider,
                      );
                      await _openRoute(
                        provider: routeProvider,
                        routeKey: route.routeKey,
                        routeName: route.routeName,
                        routeIdHint: route.routeId,
                        initialPathId: route.rtrip,
                        route: route,
                        saveHistory: true,
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _MissingDatabaseAction { download, apiOnce, apiAlways, cancel }

class _HistorySection extends StatelessWidget {
  const _HistorySection({
    required this.history,
    required this.onClear,
    required this.onSelect,
  });

  final List<SearchHistoryEntry> history;
  final Future<void> Function() onClear;
  final ValueChanged<SearchHistoryEntry> onSelect;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const Card(
        child: Padding(padding: EdgeInsets.all(16), child: Text('還沒有搜尋紀錄。')),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('最近搜尋', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton(
              onPressed: () async {
                await onClear();
              },
              child: const Text('清除'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...history.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.history_rounded),
                title: Text(entry.routeName),
                subtitle: Text(entry.provider.label),
                onTap: () => onSelect(entry),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
