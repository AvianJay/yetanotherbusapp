import 'dart:async';

import 'package:flutter/material.dart';

import '../core/transit_repository.dart';

class TraScreen extends StatefulWidget {
  const TraScreen({super.key});

  @override
  State<TraScreen> createState() => _TraScreenState();
}

class _TraScreenState extends State<TraScreen>
    with SingleTickerProviderStateMixin {
  final TransitRepository _repo = TransitRepository();
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('台鐵'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '即時看板'),
            Tab(text: '班次查詢'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _TraLiveBoardTab(repo: _repo),
          _TraOdTab(repo: _repo),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  LiveBoard Tab
// ══════════════════════════════════════════════════════════════════════════════

class _TraLiveBoardTab extends StatefulWidget {
  const _TraLiveBoardTab({required this.repo});

  final TransitRepository repo;

  @override
  State<_TraLiveBoardTab> createState() => _TraLiveBoardTabState();
}

class _TraLiveBoardTabState extends State<_TraLiveBoardTab>
    with AutomaticKeepAliveClientMixin {
  bool _loadingStations = true;
  bool _loadingBoard = false;
  List<RailStation> _stations = [];
  RailStation? _selectedStation;
  List<TraLiveBoardEntry> _entries = [];
  List<RailAlert> _alerts = [];
  Timer? _refreshTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadStations();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStations() async {
    try {
      final stations = await widget.repo.getTraStations();
      final alerts = await widget.repo.getTraAlerts();
      if (!mounted) return;
      setState(() {
        _stations = stations;
        _alerts = alerts;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingStations = false);
    }
  }

  Future<void> _loadBoard() async {
    if (_selectedStation == null) return;
    setState(() => _loadingBoard = true);
    try {
      final entries =
          await widget.repo.getTraLiveBoard(_selectedStation!.stationId);
      if (!mounted) return;
      setState(() => _entries = entries);
      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _loadBoard();
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingBoard = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    if (_loadingStations) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Alerts
        if (_alerts.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.orange.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _alerts.map((a) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '⚠️ ${a.title}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade900,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

        // Station picker
        Padding(
          padding: const EdgeInsets.all(16),
          child: Autocomplete<RailStation>(
            displayStringForOption: (s) => s.name,
            optionsBuilder: (textEditingValue) {
              if (textEditingValue.text.isEmpty) return _stations;
              final query = textEditingValue.text.toLowerCase();
              return _stations.where((s) =>
                  s.name.toLowerCase().contains(query) ||
                  s.stationId.contains(query));
            },
            fieldViewBuilder: (_, controller, focusNode, onSubmitted) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: const InputDecoration(
                  labelText: '搜尋車站',
                  prefixIcon: Icon(Icons.search_rounded),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => onSubmitted(),
              );
            },
            onSelected: (station) {
              setState(() => _selectedStation = station);
              _loadBoard();
            },
          ),
        ),

        if (_loadingBoard) const LinearProgressIndicator(),

        // Board
        Expanded(
          child: _entries.isEmpty
              ? Center(
                  child: Text(
                    _selectedStation == null ? '搜尋並選擇車站' : '載入中…',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadBoard,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _entries.length,
                    itemBuilder: (context, index) {
                      final e = _entries[index];
                      final delayed = e.delayMinutes > 0;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                width: 64,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      e.trainNo,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: theme
                                            .colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                    Text(
                                      e.trainType,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                        color: theme
                                            .colorScheme.onPrimaryContainer,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '往 ${e.endStation}',
                                      style: theme.textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '預定 ${e.scheduledTime}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              if (delayed)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '晚 ${e.delayMinutes} 分',
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.red.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '準點',
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  OD Query Tab
// ══════════════════════════════════════════════════════════════════════════════

class _TraOdTab extends StatefulWidget {
  const _TraOdTab({required this.repo});

  final TransitRepository repo;

  @override
  State<_TraOdTab> createState() => _TraOdTabState();
}

class _TraOdTabState extends State<_TraOdTab>
    with AutomaticKeepAliveClientMixin {
  bool _loadingStations = true;
  bool _searching = false;
  String? _error;
  List<RailStation> _stations = [];
  RailStation? _origin;
  RailStation? _dest;
  DateTime _date = DateTime.now();
  List<TraOdTrain> _results = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadStations();
  }

  Future<void> _loadStations() async {
    try {
      final stations = await widget.repo.getTraStations();
      if (!mounted) return;
      setState(() {
        _stations = stations;
        if (stations.length >= 2) {
          _origin = stations.first;
          _dest = stations.last;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loadingStations = false);
    }
  }

  Future<void> _search() async {
    if (_origin == null || _dest == null) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final dateStr =
          '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
      final results = await widget.repo.getTraOdTimetable(
        origin: _origin!.stationId,
        dest: _dest!.stationId,
        date: dateStr,
      );
      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _swapStations() {
    setState(() {
      final temp = _origin;
      _origin = _dest;
      _dest = temp;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 14)),
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    if (_loadingStations) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Query card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _TraStationAutocomplete(
                  label: '出發站',
                  stations: _stations,
                  selected: _origin,
                  onSelected: (s) => setState(() => _origin = s),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: _swapStations,
                    icon: const Icon(Icons.swap_vert_rounded),
                    tooltip: '交換',
                  ),
                ),
                _TraStationAutocomplete(
                  label: '到達站',
                  stations: _stations,
                  selected: _dest,
                  onSelected: (s) => setState(() => _dest = s),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today_rounded),
                        label: Text(
                          '${_date.month}/${_date.day}（${_weekdayLabel(_date.weekday)}）',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _searching ? null : _search,
                      icon: _searching
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.search_rounded),
                      label: const Text('查詢'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],

        if (_results.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('共 ${_results.length} 班', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ..._results.map((train) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 68,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Text(
                            train.trainNo,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          Text(
                            train.trainType,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${train.originDeparture} → ${train.destArrival}',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${train.originStation} → ${train.destStation}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _duration(train.originDeparture, train.destArrival),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  String _weekdayLabel(int weekday) => switch (weekday) {
        1 => '一',
        2 => '二',
        3 => '三',
        4 => '四',
        5 => '五',
        6 => '六',
        7 => '日',
        _ => '',
      };

  String _duration(String departure, String arrival) {
    try {
      final depParts = departure.split(':').map(int.parse).toList();
      final arrParts = arrival.split(':').map(int.parse).toList();
      final depMin = depParts[0] * 60 + depParts[1];
      final arrMin = arrParts[0] * 60 + arrParts[1];
      final diff = arrMin - depMin;
      if (diff <= 0) return '';
      final h = diff ~/ 60;
      final m = diff % 60;
      if (h > 0) return '${h}h${m}m';
      return '${m}m';
    } catch (_) {
      return '';
    }
  }
}

class _TraStationAutocomplete extends StatelessWidget {
  const _TraStationAutocomplete({
    required this.label,
    required this.stations,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final List<RailStation> stations;
  final RailStation? selected;
  final ValueChanged<RailStation> onSelected;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<RailStation>(
      displayStringForOption: (s) => s.name,
      initialValue:
          selected != null ? TextEditingValue(text: selected!.name) : null,
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) return stations;
        final query = textEditingValue.text.toLowerCase();
        return stations.where((s) =>
            s.name.toLowerCase().contains(query) ||
            s.stationId.contains(query));
      },
      fieldViewBuilder: (_, controller, focusNode, onSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.train_rounded),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => onSubmitted(),
        );
      },
      onSelected: onSelected,
    );
  }
}
