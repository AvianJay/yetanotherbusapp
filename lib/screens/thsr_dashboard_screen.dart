import 'dart:async';

import 'package:flutter/material.dart';

import '../core/transit_repository.dart';
import '../widgets/transit_drawer.dart';
import '../widgets/transit_station_map.dart';

enum _ThsrPanel { timetable, seats, map }

class ThsrScreen extends StatefulWidget {
  const ThsrScreen({required this.onModeChanged, super.key});

  final ValueChanged<TransitMode> onModeChanged;

  @override
  State<ThsrScreen> createState() => _ThsrScreenState();
}

class _ThsrScreenState extends State<ThsrScreen> {
  final TransitRepository _repo = TransitRepository();

  bool _loadingStations = true;
  bool _loadingSeats = false;
  bool _searching = false;
  String? _pageError;
  String? _queryError;
  String? _seatError;
  _ThsrPanel _panel = _ThsrPanel.timetable;

  List<RailStation> _stations = [];
  List<RailAlert> _alerts = [];
  RailStation? _selectedStation;
  RailStation? _origin;
  RailStation? _dest;
  DateTime _date = DateTime.now();
  List<ThsrOdTrain> _results = [];
  List<ThsrSeatInfo> _seatInfos = [];
  Timer? _seatRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _seatRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loadingStations = true;
      _pageError = null;
    });
    try {
      final futures = await Future.wait([
        _repo.getThsrStations(),
        _repo.getThsrAlerts(),
      ]);
      if (!mounted) {
        return;
      }

      final stations = futures[0] as List<RailStation>;
      final alerts = futures[1] as List<RailAlert>;
      final selectedStation =
          _pickStation(stations, _selectedStation?.stationId) ??
          (stations.isNotEmpty ? stations.first : null);
      final origin =
          _pickStation(stations, _origin?.stationId) ??
          (stations.isNotEmpty ? stations.first : null);
      final dest =
          _pickStation(stations, _dest?.stationId) ??
          (stations.length > 1 ? stations.last : origin);

      setState(() {
        _stations = stations;
        _alerts = alerts;
        _selectedStation = selectedStation;
        _origin = origin;
        _dest = dest;
      });
      if (selectedStation != null) {
        await _loadSeats(station: selectedStation);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
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

  Future<void> _loadSeats({
    RailStation? station,
    bool resetTimer = true,
  }) async {
    final activeStation = station ?? _selectedStation;
    if (activeStation == null) {
      return;
    }
    setState(() {
      _loadingSeats = true;
      _seatError = null;
    });
    try {
      final seatInfos = await _repo.getThsrSeats(activeStation.stationId);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedStation = activeStation;
        _seatInfos = seatInfos;
      });
      if (resetTimer) {
        _seatRefreshTimer?.cancel();
        _seatRefreshTimer = Timer.periodic(
          const Duration(seconds: 30),
          (_) => _loadSeats(resetTimer: false),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedStation = activeStation;
        _seatInfos = const [];
        _seatError = '$error';
      });
    } finally {
      if (mounted) {
        setState(() => _loadingSeats = false);
      }
    }
  }

  Future<void> _search() async {
    if (_origin == null || _dest == null) {
      return;
    }
    setState(() {
      _searching = true;
      _queryError = null;
    });
    try {
      final dateStr =
          '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
      final results = await _repo.getThsrOdTimetable(
        origin: _origin!.stationId,
        dest: _dest!.stationId,
        date: dateStr,
      );
      if (!mounted) {
        return;
      }
      setState(() => _results = results);
    } catch (error) {
      if (!mounted) {
        return;
      }
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
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  void _swapStations() {
    setState(() {
      final currentOrigin = _origin;
      _origin = _dest;
      _dest = currentOrigin;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('YAHSR'),
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
        currentMode: TransitMode.thsr,
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
                  _buildSeatOverview(theme),
                  const SizedBox(height: 16),
                  _ThsrPanelButtons(
                    current: _panel,
                    onChanged: (panel) => setState(() => _panel = panel),
                  ),
                  const SizedBox(height: 16),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: switch (_panel) {
                      _ThsrPanel.timetable => _buildTimetablePanel(theme),
                      _ThsrPanel.seats => _buildSeatPanel(theme),
                      _ThsrPanel.map => _buildMapPanel(theme),
                    },
                  ),
                ],
              ),
            ),
      );
  }

  Widget _buildSeatOverview(ThemeData theme) {
    final selectedStation = _selectedStation;
    final previewInfos = _seatInfos.take(3).toList(growable: false);

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
                        '座位即時概況',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '先看站點座位餘量，再決定要不要切到時刻表查下一班。',
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
            _RailStationAutocomplete(
              label: '切換觀察車站',
              stations: _stations,
              selected: selectedStation,
              onSelected: (station) => _loadSeats(station: station),
            ),
            if (_loadingSeats) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_seatError != null) ...[
              const SizedBox(height: 12),
              Text(
                _seatError!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            if (selectedStation == null)
              Text(
                '先選一個車站，再看最近幾班高鐵的座位狀況。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              )
            else if (previewInfos.isEmpty)
              Text(
                '目前沒有 ${selectedStation.name} 的座位即時資料。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              )
            else
              Column(
                children: previewInfos
                    .map((info) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ThsrSeatTile(
                          info: info,
                          station: selectedStation,
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimetablePanel(ThemeData theme) {
    return Column(
      key: const ValueKey('timetable'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                _RailStationAutocomplete(
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
                _RailStationAutocomplete(
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
            label: '選好起訖站與日期後，就能看高鐵班次。',
          )
        else
          ..._results.map((train) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ThsrTimetableTile(train: train),
            );
          }),
      ],
    );
  }

  Widget _buildSeatPanel(ThemeData theme) {
    return Column(
      key: const ValueKey('seats'),
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
                        '自由座與商務車座位',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _selectedStation == null
                          ? null
                          : () => _loadSeats(station: _selectedStation),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('刷新'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '這裡直接看站點即時座位資訊；想換站時，地圖面板會比較直覺。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _RailStationAutocomplete(
                  label: '查詢站點',
                  stations: _stations,
                  selected: _selectedStation,
                  onSelected: (station) => _loadSeats(station: station),
                ),
                if (_loadingSeats) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
        if (_seatError != null) ...[
          const SizedBox(height: 12),
          Text(_seatError!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 16),
        if (_selectedStation == null)
          const _EmptyPanel(
            icon: Icons.airline_seat_recline_normal_rounded,
            label: '先選一個站，再看各班次座位餘量。',
          )
        else if (_seatInfos.isEmpty)
          const _EmptyPanel(
            icon: Icons.airline_seat_recline_normal_rounded,
            label: '目前沒有可顯示的座位資料。',
          )
        else
          ..._seatInfos.map((info) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ThsrSeatTile(info: info, station: _selectedStation!),
            );
          }),
      ],
    );
  }

  Widget _buildMapPanel(ThemeData theme) {
    final mapPoints = _stations
        .where((station) => station.lat != 0 || station.lon != 0)
        .map(
          (station) => TransitMapPoint(
            id: station.stationId,
            label: station.name,
            subtitle: station.nameEn,
            latitude: station.lat,
            longitude: station.lon,
            color: Colors.orange.shade700,
          ),
        )
        .toList(growable: false);

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
                        '站點地圖',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          setState(() => _panel = _ThsrPanel.seats),
                      icon: const Icon(
                        Icons.airline_seat_recline_normal_rounded,
                      ),
                      label: const Text('看座位'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '點一下站點就能把下面的座位資訊切過去，動線比先選列表再回上一頁快。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TransitStationMap(
                  points: mapPoints,
                  selectedPointId: _selectedStation?.stationId,
                  onPointSelected: (point) {
                    final station = _pickStation(_stations, point.id);
                    if (station != null) {
                      _loadSeats(station: station);
                    }
                  },
                  height: 360,
                  emptyLabel: '高鐵站點目前沒有可用座標。',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_selectedStation != null)
          _SelectedThsrStationCard(
            station: _selectedStation!,
            loading: _loadingSeats,
            infos: _seatInfos,
            onRefresh: _loadSeats,
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
}

class _ThsrPanelButtons extends StatelessWidget {
  const _ThsrPanelButtons({required this.current, required this.onChanged});

  final _ThsrPanel current;
  final ValueChanged<_ThsrPanel> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PanelButton(
            icon: Icons.schedule_rounded,
            label: '班次查詢',
            selected: current == _ThsrPanel.timetable,
            onPressed: () => onChanged(_ThsrPanel.timetable),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PanelButton(
            icon: Icons.airline_seat_recline_normal_rounded,
            label: '座位資訊',
            selected: current == _ThsrPanel.seats,
            onPressed: () => onChanged(_ThsrPanel.seats),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PanelButton(
            icon: Icons.map_rounded,
            label: '站點地圖',
            selected: current == _ThsrPanel.map,
            onPressed: () => onChanged(_ThsrPanel.map),
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

class _ThsrTimetableTile extends StatelessWidget {
  const _ThsrTimetableTile({required this.train});

  final ThsrOdTrain train;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 72,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    train.trainNo,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.orange.shade900,
                    ),
                  ),
                  Text(
                    '高鐵',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade900,
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
      if (diff <= 0) {
        return '';
      }
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

class _ThsrSeatTile extends StatelessWidget {
  const _ThsrSeatTile({required this.info, required this.station});

  final ThsrSeatInfo info;
  final RailStation station;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seat = _seatForStation();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 58,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    info.trainNo,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.orange.shade900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${info.departureTime} 發車',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '往 ${info.destination}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (seat == null)
              Text(
                '這班車目前沒有 ${station.name} 的座位欄位。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SeatStatusChip(label: '標準車', value: seat.standardSeat),
                  _SeatStatusChip(label: '商務車', value: seat.businessSeat),
                ],
              ),
          ],
        ),
      ),
    );
  }

  ThsrCarSeat? _seatForStation() {
    for (final seat in info.seatInfo) {
      if (seat.stationId == station.stationId) {
        return seat;
      }
    }
    if (info.seatInfo.isEmpty) {
      return null;
    }
    return info.seatInfo.first;
  }
}

class _SeatStatusChip extends StatelessWidget {
  const _SeatStatusChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _statusStyle(value);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: style.foreground.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: style.foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value.isEmpty ? '未提供' : value,
            style: theme.textTheme.bodySmall?.copyWith(color: style.foreground),
          ),
        ],
      ),
    );
  }

  _SeatChipStyle _statusStyle(String rawValue) {
    final value = rawValue.toLowerCase();
    if (value.contains('滿') ||
        value.contains('無') ||
        value.contains('full') ||
        value.contains('sold')) {
      return _SeatChipStyle(
        foreground: Colors.red.shade700,
        background: Colors.red.shade50,
      );
    }
    if (value.contains('少') ||
        value.contains('緊') ||
        value.contains('limited') ||
        value.contains('few')) {
      return _SeatChipStyle(
        foreground: Colors.orange.shade900,
        background: Colors.orange.shade50,
      );
    }
    return _SeatChipStyle(
      foreground: Colors.green.shade800,
      background: Colors.green.shade50,
    );
  }
}

class _SeatChipStyle {
  const _SeatChipStyle({required this.foreground, required this.background});

  final Color foreground;
  final Color background;
}

class _RailStationAutocomplete extends StatelessWidget {
  const _RailStationAutocomplete({
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

class _SelectedThsrStationCard extends StatelessWidget {
  const _SelectedThsrStationCard({
    required this.station,
    required this.loading,
    required this.infos,
    required this.onRefresh,
  });

  final RailStation station;
  final bool loading;
  final List<ThsrSeatInfo> infos;
  final Future<void> Function({RailStation? station, bool resetTimer})
  onRefresh;

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
            if (infos.isEmpty)
              Text(
                '這個站目前沒有可顯示的座位資料。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              )
            else
              ...infos.take(5).map((info) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ThsrSeatTile(info: info, station: station),
                );
              }),
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
