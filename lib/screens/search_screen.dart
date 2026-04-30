import 'dart:async';

import 'package:flutter/material.dart';

import '../app/bus_app.dart';
import '../core/app_controller.dart';
import '../core/models.dart';
import 'route_detail_screen.dart';
import '../widgets/background_image_wrapper.dart';

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

  int _providerPriority(AppController busController, BusProvider provider) {
    final currentProvider = busController.settings.provider;
    if (provider == currentProvider) {
      return 0;
    }
    if (provider == BusProvider.inter) {
      return 1;
    }
    return 2;
  }

  Future<void> _search(String query) async {
    final busController = AppControllerScope.read(context);
    final trimmedQuery = query.trim();
    final providerCount = busController.searchProviders.length;
    final localProviderCount = busController.searchProviders
        .where(
          (provider) =>
              provider.supportsLocalDatabase &&
              busController.isDatabaseReady(provider),
        )
        .length;
    final remoteProviderCount = providerCount - localProviderCount;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = <RouteSummary>[];
      for (final provider in busController.searchProviders) {
        if (provider.supportsLocalDatabase &&
            busController.isDatabaseReady(provider)) {
          results.addAll(
            await busController.searchRoutes(query, provider: provider),
          );
        } else {
          results.addAll(
            await busController.searchRoutesViaApi(query, provider: provider),
          );
        }
      }

      results.sort((left, right) {
        final leftProvider = busProviderFromString(left.sourceProvider);
        final rightProvider = busProviderFromString(right.sourceProvider);
        final leftPriority = _providerPriority(busController, leftProvider);
        final rightPriority = _providerPriority(busController, rightProvider);
        if (leftPriority != rightPriority) {
          return leftPriority.compareTo(rightPriority);
        }
        final routeNameCompare = left.routeName.compareTo(right.routeName);
        if (routeNameCompare != 0) {
          return routeNameCompare;
        }
        return left.description.compareTo(right.description);
      });

      if (!mounted) {
        return;
      }
      setState(() {
        _results = results;
      });
      unawaited(
        busController.analytics.logSearchExecuted(
          queryLength: trimmedQuery.length,
          resultsCount: results.length,
          providerCount: providerCount,
          localProviderCount: localProviderCount,
          remoteProviderCount: remoteProviderCount,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$error';
      });
      unawaited(
        busController.analytics.logSearchFailed(
          queryLength: trimmedQuery.length,
          providerCount: providerCount,
        ),
      );
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
    String source = 'search_result',
  }) async {
    final busController = AppControllerScope.read(context);
    if (saveHistory && route != null) {
      await busController.addHistoryEntry(route, provider: provider);
    }
    await busController.recordRouteSelection(
      provider: provider,
      routeKey: routeKey,
      routeName: routeName,
      source: source,
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
    final hasSearchBackgroundImage = hasBackgroundImageForPage(
      busController.settings,
      pageKey: 'search',
    );
    // ignore: unused_local_variable
    final missingProviders = selectedProviders
        .where((provider) => !busController.isDatabaseReady(provider))
        .toList();

    return BackgroundImageWrapper(
      pageKey: 'search',
      child: Scaffold(
        backgroundColor: hasSearchBackgroundImage ? Colors.transparent : null,
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
              hintText: '輸入公車號碼、路線名稱或客運名稱',
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
          // if (missingProviders.isNotEmpty)
          //   Card(
          //     child: Padding(
          //       padding: const EdgeInsets.all(16),
          //       child: Text(
          //         '尚未下載：${missingProviders.map((provider) => provider.label).join('、')}。\n'
          //         '搜尋時會自動改走線上 API；公路客運固定使用線上查詢。',
          //       ),
          //     ),
          //   ),
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
                    source: 'search_history',
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
                subtitle: Text(
                  entry.pathName != null && entry.pathName!.isNotEmpty
                      ? '${entry.provider.label} | ${entry.pathName}'
                      : entry.provider.label,
                ),
                onTap: () => onSelect(entry),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
