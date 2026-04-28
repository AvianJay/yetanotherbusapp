import 'dart:async';

import 'package:flutter/material.dart';

import '../core/transit_repository.dart';
import '../widgets/transit_drawer.dart';
import '../widgets/transit_station_map.dart';

enum _TraPanel { query, map }

class TraScreen extends StatefulWidget {
  const TraScreen({required this.onModeChanged, super.key});

  final ValueChanged<TransitMode> onModeChanged;

  @override
  State<TraScreen> createState() => _TraScreenState();
}

class _TraScreenState extends State<TraScreen> {
  final TransitRepository _repo = TransitRepository();

  bool _loadingStations = true;
  bool _loadingBoard = false;
  bool _searching = false;
  String? _pageError;
  String? _queryError;
  _TraPanel _panel = _TraPanel.query;

  List<RailStation> _stations = [];
  List<RailAlert> _alerts = [];
  RailStation? _selectedStation;
  List<TraLiveBoardEntry> _boardEntries = [];
  List<TraTrainPosition> _trainPositions = [];
  String? _selectedTrainNo;
  Timer? _refreshTimer;

  RailStation? _origin;
  RailStation? _dest;
  DateTime _date = DateTime.now();
  List<TraOdTrain> _results = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loadingStations = true;
      _pageError = null;
    });
    try {
      final futures = await Future.wait([
        _repo.getTraStations(),
        _repo.getTraAlerts(),
      ]);
      if (!mounted) return;

      final stations = futures[0] as List<RailStation>;
      final alerts = futures[1] as List<RailAlert>;
      final selectedStation =
          _pickStation(stations, _selectedStation?.stationId) ??
          (stations.isNotEmpty ? stations.first : null);

      setState(() {
        _stations = stations;
        _alerts = alerts;
        _selectedStation = selectedStation;
        _origin =
            _pickStation(stations, _origin?.stationId) ??
            (stations.isNotEmpty ? stations.first : null);
        _dest =
            _pickStation(stations, _dest?.stationId) ??
            (stations.length > 1 ? stations.last : _origin);
      });
      if (selectedStation != null) {
        await _loadBoard(station: selectedStation);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _pageError = '$error');
    } finally {
      if (mounted) {
        setState(() => _loadingStations = false);
      }
    }
  }

  RailStation? _pickStation(List<RailStation> stations, String? stationId) {
    if (stationId == null || stationId.isEmpty) {
      return null;
    }
    for (final station in stations) {
      if (station.stationId == stationId) {
        return station;
      }
    }
    return null;
  }

  Future<void> _loadBoard({RailStation? station}) async {
    final activeStation = station ?? _selectedStation;
    if (activeStation == null) return;
    setState(() => _loadingBoard = true);
    try {
      final boardFuture = _repo.getTraLiveBoard(activeStation.stationId);
      final positionsFuture = _repo.getTraTrainPositions(
        activeStation.stationId,
      );
      final entries = await boardFuture;
      List<TraTrainPosition> positions;
      try {
        positions = await positionsFuture;
      } catch (_) {
        positions = const <TraTrainPosition>[];
      }
      if (!mounted) return;
      setState(() {
        _selectedStation = activeStation;
        _boardEntries = entries;
        _trainPositions = positions;
        if (_selectedTrainNo != null &&
            !positions.any(
              (position) => position.trainNo == _selectedTrainNo,
            )) {
          _selectedTrainNo = null;
        }
      });
      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _loadBoard();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _boardEntries = const [];
        _trainPositions = const [];
        _selectedTrainNo = null;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingBoard = false);
      }
    }
  }

  TraTrainPosition? get _selectedTrainPosition {
    final selectedTrainNo = _selectedTrainNo;
    if (selectedTrainNo == null) {
      return null;
    }
    for (final position in _trainPositions) {
      if (position.trainNo == selectedTrainNo) {
        return position;
      }
    }
    return null;
  }

  Future<void> _search() async {
    if (_origin == null || _dest == null) return;
    setState(() {
      _searching = true;
      _queryError = null;
    });
    try {
      final dateStr =
          '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
      final results = await _repo.getTraOdTimetable(
        origin: _origin!.stationId,
        dest: _dest!.stationId,
        date: dateStr,
      );
      if (!mounted) return;
      setState(() => _results = results);
    } catch (error) {
      if (!mounted) return;
      setState(() => _queryError = '$error');
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
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

  void _swapStations() {
    setState(() {
      final temp = _origin;
      _origin = _dest;
      _dest = temp;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('YATrain'),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            tooltip: '重新整理',
            onPressed: _loadInitialData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      drawer: TransitDrawer(
        currentMode: TransitMode.tra,
        onModeChanged: widget.onModeChanged,
      ),
      body: _loadingStations
          ? const Center(child: CircularProgressIndicator())
          : _pageError != null && _stations.isEmpty
          ? _ErrorState(message: _pageError!, onRetry: _loadInitialData)
          : RefreshIndicator(
              onRefresh: _loadInitialData,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_alerts.isNotEmpty) ...[
                    _RailAlertCard(alerts: _alerts),
                    const SizedBox(height: 16),
                  ],
                  _buildLiveOverview(theme),
                  const SizedBox(height: 16),
                  _TraPanelButtons(
                    current: _panel,
                    onChanged: (panel) => setState(() => _panel = panel),
                  ),
                  const SizedBox(height: 16),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _panel == _TraPanel.query
                        ? _buildQueryPanel(theme)
                        : _buildMapPanel(theme),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildLiveOverview(ThemeData theme) {
    final selectedStation = _selectedStation;
    final previewEntries = _boardEntries.take(3).toList(growable: false);
    final previewPositions = _trainPositions.take(4).toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '列車即時動態',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '目前用當日停靠表加延誤時間推算列車位置，地圖上的列車點位屬估算值。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selectedStation != null)
                  Chip(
                    avatar: const Icon(Icons.location_on_rounded, size: 18),
                    label: Text(selectedStation.name),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _TraStationAutocomplete(
              label: '切換觀察車站',
              stations: _stations,
              selected: selectedStation,
              onSelected: (station) => _loadBoard(station: station),
            ),
            if (_loadingBoard) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            if (selectedStation == null)
              Text(
                '先選一個車站，再看最近幾班列車。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              )
            else if (previewEntries.isEmpty)
              Text(
                '目前沒有 ${selectedStation.name} 的即時班次資料。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              )
            else
              Column(
                children: previewEntries
                    .map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _TraBoardTile(entry: entry),
                      );
                    })
                    .toList(growable: false),
              ),
            if (previewPositions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '估算中的列車位置',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: previewPositions
                    .map((position) {
                      return ActionChip(
                        avatar: const Icon(Icons.train_rounded, size: 18),
                        label: Text(
                          '${position.trainNo} ${_positionSummary(position)}',
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedTrainNo = position.trainNo;
                            _panel = _TraPanel.map;
                          });
                        },
                      );
                    })
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQueryPanel(ThemeData theme) {
    return Column(
      key: const ValueKey('query'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                _TraStationAutocomplete(
                  label: '出發站',
                  stations: _stations,
                  selected: _origin,
                  onSelected: (station) => setState(() => _origin = station),
                ),
                const SizedBox(height: 10),
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
                  onSelected: (station) => setState(() => _dest = station),
                ),
                const SizedBox(height: 14),
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
                      label: const Text('查詢班次'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_queryError != null) ...[
          const SizedBox(height: 12),
          Text(_queryError!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 16),
        Text(
          _results.isEmpty ? '尚未查詢班次' : '共 ${_results.length} 班',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        if (_results.isEmpty)
          const _EmptyPanel(
            icon: Icons.schedule_rounded,
            label: '選好出發站與到達站後，就能看班次與行車時間。',
          )
        else
          ..._results.map((train) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TraScheduleTile(train: train),
            );
          }),
      ],
    );
  }

  Widget _buildMapPanel(ThemeData theme) {
    final stationPoints = _stations
        .where((station) => station.lat != 0 || station.lon != 0)
        .map(
          (station) => TransitMapPoint(
            id: station.stationId,
            label: station.name,
            subtitle: station.nameEn,
            latitude: station.lat,
            longitude: station.lon,
            badge: station.stationClass.isEmpty ? null : station.stationClass,
            color: theme.colorScheme.primary,
          ),
        )
        .toList(growable: false);
    final trainPoints = _trainPositions
        .where((position) => position.lat != 0 || position.lon != 0)
        .map(
          (position) => TransitMapPoint(
            id: 'train:${position.trainNo}',
            label: position.status == 'between_stations'
                ? position.nextStationName
                : position.currentStationName,
            subtitle: _positionSummary(position),
            latitude: position.lat,
            longitude: position.lon,
            badge: position.trainNo,
            color: Colors.red.shade700,
          ),
        )
        .toList(growable: false);
    final mapPoints = [...stationPoints, ...trainPoints];
    final selectedPointId = _selectedTrainNo != null
        ? 'train:${_selectedTrainNo!}'
        : _selectedStation?.stationId;

    return Column(
      key: const ValueKey('map'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '車站地圖',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (_selectedStation != null)
                      FilledButton.tonalIcon(
                        onPressed: () {
                          setState(() => _panel = _TraPanel.query);
                        },
                        icon: const Icon(Icons.schedule_rounded),
                        label: const Text('看班次'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '點站牌切換車站，點紅色列車 marker 看估算中的列車位置。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TransitStationMap(
                  points: mapPoints,
                  selectedPointId: selectedPointId,
                  onPointSelected: (point) {
                    if (point.id.startsWith('train:')) {
                      setState(() => _selectedTrainNo = point.id.substring(6));
                      return;
                    }
                    final station = _pickStation(_stations, point.id);
                    if (station != null) {
                      setState(() => _selectedTrainNo = null);
                      _loadBoard(station: station);
                    }
                  },
                  height: 360,
                  emptyLabel: '台鐵站點目前沒有可用座標。',
                ),
              ],
            ),
          ),
        ),
        if (_selectedTrainPosition != null) ...[
          const SizedBox(height: 12),
          _SelectedTraTrainCard(position: _selectedTrainPosition!),
        ],
        const SizedBox(height: 12),
        if (_selectedStation != null)
          _SelectedRailStationCard(
            station: _selectedStation!,
            loading: _loadingBoard,
            entries: _boardEntries,
            onRefresh: _loadBoard,
          ),
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

  String _positionSummary(TraTrainPosition position) {
    return switch (position.status) {
      'between_stations' =>
        '${position.currentStationName} → ${position.nextStationName}',
      'arrived' => '已到 ${position.currentStationName}',
      _ => '停靠 ${position.currentStationName}',
    };
  }
}

class _TraPanelButtons extends StatelessWidget {
  const _TraPanelButtons({required this.current, required this.onChanged});

  final _TraPanel current;
  final ValueChanged<_TraPanel> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PanelButton(
            icon: Icons.schedule_rounded,
            label: '班次查詢',
            selected: current == _TraPanel.query,
            onPressed: () => onChanged(_TraPanel.query),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PanelButton(
            icon: Icons.map_rounded,
            label: '車站地圖',
            selected: current == _TraPanel.map,
            onPressed: () => onChanged(_TraPanel.map),
          ),
        ),
      ],
    );
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
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

class _TraBoardTile extends StatelessWidget {
  const _TraBoardTile({required this.entry});

  final TraLiveBoardEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delayed = entry.delayMinutes > 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  entry.trainNo,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                Text(
                  entry.trainType,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '往 ${entry.endStation}',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '預定 ${entry.scheduledDeparture}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: delayed ? Colors.red.shade50 : Colors.green.shade50,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              delayed ? '晚 ${entry.delayMinutes} 分' : '準點',
              style: theme.textTheme.bodySmall?.copyWith(
                color: delayed ? Colors.red.shade700 : Colors.green.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TraScheduleTile extends StatelessWidget {
  const _TraScheduleTile({required this.train});

  final TraOdTrain train;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 70,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
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
                  const SizedBox(height: 3),
                  Text(
                    '${train.startStation} → ${train.endStation}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(
              _duration(train.originDeparture, train.destArrival),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _duration(String departure, String arrival) {
    try {
      final depParts = departure
          .split(':')
          .map(int.parse)
          .toList(growable: false);
      final arrParts = arrival
          .split(':')
          .map(int.parse)
          .toList(growable: false);
      final depMinutes = depParts[0] * 60 + depParts[1];
      final arrMinutes = arrParts[0] * 60 + arrParts[1];
      final diff = arrMinutes - depMinutes;
      if (diff <= 0) return '';
      final hours = diff ~/ 60;
      final minutes = diff % 60;
      if (hours > 0) {
        return '${hours}h${minutes}m';
      }
      return '${minutes}m';
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
      key: ValueKey('${label}_${selected?.stationId ?? 'none'}'),
      displayStringForOption: (station) => station.name,
      initialValue: selected != null
          ? TextEditingValue(text: selected!.name)
          : null,
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return stations;
        }
        final query = textEditingValue.text.toLowerCase();
        return stations.where((station) {
          return station.name.toLowerCase().contains(query) ||
              station.stationId.toLowerCase().contains(query) ||
              station.nameEn.toLowerCase().contains(query);
        });
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

class _RailAlertCard extends StatelessWidget {
  const _RailAlertCard({required this.alerts});

  final List<RailAlert> alerts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange.shade900,
                ),
                const SizedBox(width: 8),
                Text(
                  '營運公告',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.orange.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...alerts.take(3).map((alert) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• ${alert.title}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.orange.shade900,
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

class _SelectedRailStationCard extends StatelessWidget {
  const _SelectedRailStationCard({
    required this.station,
    required this.loading,
    required this.entries,
    required this.onRefresh,
  });

  final RailStation station;
  final bool loading;
  final List<TraLiveBoardEntry> entries;
  final Future<void> Function({RailStation? station}) onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        station.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (station.nameEn.isNotEmpty)
                        Text(
                          station.nameEn,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => onRefresh(station: station),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('刷新'),
                ),
              ],
            ),
            if (loading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Text(
                '這個車站目前沒有可顯示的即時班次。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              )
            else
              ...entries.take(5).map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _TraBoardTile(entry: entry),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _SelectedTraTrainCard extends StatelessWidget {
  const _SelectedTraTrainCard({required this.position});

  final TraTrainPosition position;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delayed = position.delayMinutes > 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    position.trainNo,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.red.shade700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        position.trainType.isEmpty
                            ? '列車位置估算'
                            : position.trainType,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${position.startingStationName} → ${position.endingStationName}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: delayed ? Colors.red.shade50 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    delayed ? '晚 ${position.delayMinutes} 分' : '準點',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: delayed
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(switch (position.status) {
              'between_stations' =>
                '目前估算在 ${position.currentStationName} 與 ${position.nextStationName} 之間',
              'arrived' => '目前估算已到達 ${position.currentStationName}',
              _ => '目前估算停靠在 ${position.currentStationName}',
            }, style: theme.textTheme.bodyMedium),
            if (position.status == 'between_stations') ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: position.progress,
                minHeight: 8,
                borderRadius: BorderRadius.circular(999),
              ),
              const SizedBox(height: 6),
              Text(
                '路段進度 ${(position.progress * 100).round()}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (position.updatedAt.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '資料更新 ${position.updatedAt}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.icon, required this.label});

  final IconData icon;
  final String label;

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
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

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
