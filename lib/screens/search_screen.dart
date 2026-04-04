import 'dart:async';

import 'package:flutter/material.dart';

import '../app/bus_app.dart';
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

  Future<void> _search(String query) async {
    final busController = AppControllerScope.read(context);
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await busController.searchRoutes(query);
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
        builder: (_) =>
            RouteDetailScreen(routeKey: routeKey, provider: provider),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busController = AppControllerScope.of(context);
    final provider = busController.settings.provider;

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
                        _onQueryChanged('');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          if (!busController.databaseReady)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('目前還沒有 ${provider.label} 資料庫。請先回首頁下載，再進行搜尋。'),
              ),
            )
          else if (_controller.text.trim().isEmpty)
            _HistorySection(
              history: busController.history,
              onClear: busController.clearHistory,
              onSelect: (entry) {
                unawaited(
                  _openRoute(
                    provider: entry.provider,
                    routeKey: entry.routeKey,
                    routeName: entry.routeName,
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
                      child: Text(route.routeName.characters.first),
                    ),
                    title: Text(route.routeName),
                    subtitle: Text(
                      route.description.isEmpty
                          ? 'routeKey: ${route.routeKey}'
                          : route.description,
                    ),
                    onTap: () async {
                      await _openRoute(
                        provider: provider,
                        routeKey: route.routeKey,
                        routeName: route.routeName,
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
