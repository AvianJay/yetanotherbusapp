import 'dart:async';

import 'package:flutter/material.dart';

import '../core/transit_repository.dart';
import '../widgets/transit_drawer.dart';

class ThsrScreen extends StatefulWidget {
  const ThsrScreen({required this.onModeChanged, super.key});

  final ValueChanged<TransitMode> onModeChanged;

  @override
  State<ThsrScreen> createState() => _ThsrScreenState();
}

class _ThsrScreenState extends State<ThsrScreen>
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
        title: const Text('YAHSR'),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '班次查詢'),
            Tab(text: '即時座位'),
          ],
        ),
      ),
      drawer: TransitDrawer(
        currentMode: TransitMode.thsr,
        onModeChanged: widget.onModeChanged,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ThsrOdTab(repo: _repo),
          _ThsrSeatsTab(repo: _repo),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  OD Timetable Tab
// ══════════════════════════════════════════════════════════════════════════════

class _ThsrOdTab extends StatefulWidget {
  const _ThsrOdTab({required this.repo});

  final TransitRepository repo;

  @override
  State<_ThsrOdTab> createState() => _ThsrOdTabState();
}

class _ThsrOdTabState extends State<_ThsrOdTab>
    with AutomaticKeepAliveClientMixin {
  bool _loadingStations = true;
  bool _searching = false;
  String? _error;
  List<RailStation> _stations = [];
  RailStation? _origin;
  RailStation? _dest;
  DateTime _date = DateTime.now();
  List<ThsrOdTrain> _results = [];
  List<RailAlert> _alerts = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadStations();
  }

  Future<void> _loadStations() async {
    try {
      final stations = await widget.repo.getThsrStations();
      final alerts = await widget.repo.getThsrAlerts();
      if (!mounted) return;
      setState(() {
        _stations = stations;
        _alerts = alerts;
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
      final results = await widget.repo.getThsrOdTimetable(
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
      lastDate: DateTime.now().add(const Duration(days: 28)),
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
    if (_error != null && _stations.isEmpty) {
      return Center(child: Text(_error!));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Alerts
        if (_alerts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _alerts.map((a) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
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
            ),
          ),

        // Station pickers
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StationDropdown(
                        label: '出發站',
                        stations: _stations,
                        selected: _origin,
                        onChanged: (s) => setState(() => _origin = s),
                      ),
                    ),
                    IconButton(
                      onPressed: _swapStations,
                      icon: const Icon(Icons.swap_horiz_rounded),
                      tooltip: '交換',
                    ),
                    Expanded(
                      child: _StationDropdown(
                        label: '到達站',
                        stations: _stations,
                        selected: _dest,
                        onChanged: (s) => setState(() => _dest = s),
                      ),
                    ),
                  ],
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

        if (_error != null && _stations.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],

        // Results
        if (_results.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '共 ${_results.length} 班',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ..._results.map((train) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        train.trainNo,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
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

// ══════════════════════════════════════════════════════════════════════════════
//  Seats Tab
// ══════════════════════════════════════════════════════════════════════════════

class _ThsrSeatsTab extends StatefulWidget {
  const _ThsrSeatsTab({required this.repo});

  final TransitRepository repo;

  @override
  State<_ThsrSeatsTab> createState() => _ThsrSeatsTabState();
}

class _ThsrSeatsTabState extends State<_ThsrSeatsTab>
    with AutomaticKeepAliveClientMixin {
  bool _loadingStations = true;
  bool _loadingSeats = false;
  List<RailStation> _stations = [];
  RailStation? _selectedStation;
  List<ThsrSeatInfo> _seats = [];
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
      final stations = await widget.repo.getThsrStations();
      if (!mounted) return;
      setState(() {
        _stations = stations;
        if (stations.isNotEmpty) {
          _selectedStation = stations.first;
          _loadSeats();
        }
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingStations = false);
    }
  }

  Future<void> _loadSeats() async {
    if (_selectedStation == null) return;
    setState(() => _loadingSeats = true);
    try {
      final seats = await widget.repo.getThsrSeats(_selectedStation!.stationId);
      if (!mounted) return;
      setState(() => _seats = seats);
      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _loadSeats();
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingSeats = false);
    }
  }

  String _seatLabel(String status) => switch (status) {
        'Available' => '有座位',
        'Limited' => '座位有限',
        'Full' => '已滿',
        'Unknown' => '—',
        _ => status.isEmpty ? '—' : status,
      };

  Color _seatColor(String status) => switch (status) {
        'Available' => Colors.green.shade700,
        'Limited' => Colors.orange.shade700,
        'Full' => Colors.red.shade700,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    if (_loadingStations) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: DropdownButtonFormField<RailStation>(
            value: _selectedStation,
            decoration: const InputDecoration(
              labelText: '選擇車站',
              border: OutlineInputBorder(),
            ),
            items: _stations.map((s) {
              return DropdownMenuItem(value: s, child: Text(s.name));
            }).toList(),
            onChanged: (s) {
              if (s == null) return;
              setState(() => _selectedStation = s);
              _loadSeats();
            },
          ),
        ),
        if (_loadingSeats) const LinearProgressIndicator(),
        Expanded(
          child: _seats.isEmpty
              ? const Center(child: Text('選擇車站後顯示即時座位資訊'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _seats.length,
                  itemBuilder: (context, index) {
                    final seat = _seats[index];
                    // Find seat info for selected station
                    ThsrCarSeat? stationSeat;
                    for (final cs in seat.seatInfo) {
                      if (cs.stationId == _selectedStation?.stationId) {
                        stationSeat = cs;
                        break;
                      }
                    }

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                seat.trainNo,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${seat.departureTime} 往 ${seat.destination}',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  if (stationSeat != null) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        _SeatChip(
                                          label: '自由座',
                                          status: stationSeat.standardSeat,
                                          seatLabel: _seatLabel,
                                          seatColor: _seatColor,
                                        ),
                                        const SizedBox(width: 8),
                                        _SeatChip(
                                          label: '商務座',
                                          status: stationSeat.businessSeat,
                                          seatLabel: _seatLabel,
                                          seatColor: _seatColor,
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SeatChip extends StatelessWidget {
  const _SeatChip({
    required this.label,
    required this.status,
    required this.seatLabel,
    required this.seatColor,
  });

  final String label;
  final String status;
  final String Function(String) seatLabel;
  final Color Function(String) seatColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: seatColor(status).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: ${seatLabel(status)}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: seatColor(status),
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

// ── Shared ──

class _StationDropdown extends StatelessWidget {
  const _StationDropdown({
    required this.label,
    required this.stations,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<RailStation> stations;
  final RailStation? selected;
  final ValueChanged<RailStation?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<RailStation>(
      value: selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: stations.map((s) {
        return DropdownMenuItem(value: s, child: Text(s.name));
      }).toList(),
      onChanged: onChanged,
    );
  }
}
