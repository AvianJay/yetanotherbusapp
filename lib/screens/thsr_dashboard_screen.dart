import 'dart:async';

import 'package:flutter/material.dart';

import '../app/bus_app.dart';
import '../core/friendly_error.dart';
import '../core/rail_line_stations.dart';
import '../core/rail_time.dart';
import '../core/request_sequence.dart';
import '../core/transit_repository.dart';
import '../core/user_location.dart';
import '../widgets/background_image_wrapper.dart';
import '../widgets/rail_station_picker.dart';
import '../widgets/transit_drawer.dart';
import '../widgets/transit_panels.dart';
import '../widgets/transit_station_map.dart';
import '../widgets/ad_banner_widget.dart';

enum _ThsrPanel { timetable, seats, map }

class ThsrScreen extends StatefulWidget {
  const ThsrScreen({
    required this.onModeChanged,
    required this.isActive,
    super.key,
  });

  final ValueChanged<TransitMode> onModeChanged;
  final bool isActive;

  @override
  State<ThsrScreen> createState() => _ThsrScreenState();
}

class _ThsrScreenState extends State<ThsrScreen> {
  final TransitRepository _repo = TransitRepository.shared;

  bool _loadingStations = true;
  bool _loadingSeats = false;
  bool _searching = false;
  String? _pageError;
  String? _queryError;
  String? _seatError;
  _ThsrPanel _panel = _ThsrPanel.timetable;

  List<RailStation> _stations = [];
  List<RailPickerLine> _pickerGroups = const [];
  List<RailAlert> _alerts = [];
  RailStation? _selectedStation;
  RailStation? _origin;
  RailStation? _dest;
  DateTime _date = DateTime.now();
  List<ThsrOdTrain> _results = [];
  List<ThsrSeatInfo> _seatInfos = [];
  bool _showPastTrains = false;

  /// Wall clock behind every "has this train left?" decision, ticked by
  /// [_clockTimer] so rows grey out between the 30s seat refreshes.
  DateTime _now = DateTime.now();

  Timer? _seatRefreshTimer;
  Timer? _clockTimer;
  final _initialDataRequest = RequestSequence();
  final _seatsRequest = RequestSequence();

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _seatRefreshTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ThsrScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) {
      return;
    }
    if (!widget.isActive) {
      _seatRefreshTimer?.cancel();
      _seatRefreshTimer = null;
      _clockTimer?.cancel();
      _clockTimer = null;
      return;
    }
    // A tab left in the background for a while has a stale clock; catch up
    // before drawing or departed trains still look catchable.
    setState(() => _now = DateTime.now());
    _ensureClockTimer();
    if (_selectedStation != null) {
      unawaited(_loadSeats());
    } else if (!_loadingStations) {
      unawaited(_loadInitialData());
    }
  }

  /// Pure repaint tick. Separate from the seat refresh on purpose: whether a
  /// train has left changes with the clock, not with the data, so it must keep
  /// working when the network does not.
  void _ensureClockTimer() {
    if (!widget.isActive) {
      return;
    }
    _clockTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || !widget.isActive) {
        _clockTimer?.cancel();
        _clockTimer = null;
        return;
      }
      setState(() => _now = DateTime.now());
    });
  }

  Future<void> _loadInitialData({bool refresh = false}) async {
    final request = _initialDataRequest.next();
    _seatsRequest.next();
    if (refresh) {
      _repo.invalidateCache('thsr_');
    }
    setState(() {
      _loadingStations = true;
      _pageError = null;
    });
    try {
      final futures = await Future.wait([
        _repo.getThsrStations(),
        _repo.getThsrAlerts(),
      ]);
      if (!mounted || !_initialDataRequest.isCurrent(request)) {
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
        // TDX publishes no StationOfLine resource for THSR, so this always
        // collapses to a single station-id-ordered group -- which for 12
        // stations on one line is exactly the right shape anyway.
        _pickerGroups = buildRailPickerGroups(
          stations: stations,
          lines: const [],
        );
        _selectedStation = selectedStation;
        _origin = origin;
        _dest = dest;
      });
      _ensureClockTimer();
      if (selectedStation != null) {
        await _loadSeats(station: selectedStation);
      }
    } catch (error) {
      if (!mounted || !_initialDataRequest.isCurrent(request)) {
        return;
      }
      setState(() => _pageError = friendlyErrorMessage(error));
    } finally {
      if (mounted && _initialDataRequest.isCurrent(request)) {
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
    final request = _seatsRequest.next();
    setState(() {
      _loadingSeats = true;
      _seatError = null;
    });
    try {
      final seatInfos = await _repo.getThsrSeats(activeStation.stationId);
      if (!mounted || !_seatsRequest.isCurrent(request)) {
        return;
      }
      setState(() {
        _selectedStation = activeStation;
        _seatInfos = seatInfos;
      });
      if (resetTimer && widget.isActive) {
        _seatRefreshTimer?.cancel();
        _seatRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
          if (!mounted || !widget.isActive) {
            _seatRefreshTimer?.cancel();
            _seatRefreshTimer = null;
            return;
          }
          unawaited(_loadSeats(resetTimer: false));
        });
      }
    } catch (error) {
      if (!mounted || !_seatsRequest.isCurrent(request)) {
        return;
      }
      setState(() {
        _selectedStation = activeStation;
        _seatError = friendlyErrorMessage(error);
      });
    } finally {
      if (mounted && _seatsRequest.isCurrent(request)) {
        setState(() => _loadingSeats = false);
      }
    }
  }

  Future<NearestRailStation?> _locateNearestStation() async {
    final position = await resolveUserPosition();
    return nearestRailStation(
      _stations,
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  Future<RailStation?> _pickStationWithWheel({
    required String title,
    RailStation? initial,
    RailStation? excluded,
  }) {
    return showRailStationPicker(
      context: context,
      title: title,
      groups: _pickerGroups,
      initial: initial,
      excluded: excluded,
      onLocate: _locateNearestStation,
    );
  }

  Future<void> _chooseObservedStation() async {
    final picked = await _pickStationWithWheel(
      title: '選擇車站',
      initial: _selectedStation,
    );
    if (picked == null || !mounted) return;
    unawaited(_loadSeats(station: picked));
  }

  Future<void> _chooseOrigin() async {
    final picked = await _pickStationWithWheel(
      title: '選擇出發站',
      initial: _origin,
      excluded: _dest,
    );
    if (picked == null || !mounted) return;
    setState(() => _origin = picked);
  }

  Future<void> _chooseDest() async {
    final picked = await _pickStationWithWheel(
      title: '選擇到達站',
      initial: _dest,
      excluded: _origin,
    );
    if (picked == null || !mounted) return;
    setState(() => _dest = picked);
  }

  /// True once this timetable row's departure is behind [_now].
  ///
  /// THSR publishes no live delay feed (only seat availability), so there is
  /// no delay to fold in here -- unlike TRA.
  bool _isTrainPast(String departure, {DateTime? serviceDate}) {
    return isRailDeparturePast(
      scheduledDeparture: departure,
      serviceDate: serviceDate ?? _date,
      now: _now,
    );
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
      setState(() {
        _results = results;
        // Only today has a mix worth hiding; any other date is all-past or
        // all-future, and collapsing would leave an empty list under a header.
        _showPastTrains = !_isSameDay(_date, DateTime.now());
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _queryError = friendlyErrorMessage(error));
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
      setState(() {
        _date = picked;
        _showPastTrains = !_isSameDay(picked, DateTime.now());
      });
    }
  }

  static bool _isSameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

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
    final hasBackgroundImage = hasBackgroundImageForPage(
      AppControllerScope.of(context).settings,
      pageKey: 'bus',
    );
    return Scaffold(
      backgroundColor: hasBackgroundImage ? Colors.transparent : null,
      appBar: AppBar(
        title: const Text('YAHSR'),
        automaticallyImplyLeading: false,
        leading:
            MediaQuery.sizeOf(context).width >= kDesktopNavigationRailBreakpoint
            ? null
            : Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
        actions: [
          IconButton(
            tooltip: '重新整理',
            onPressed: () => _loadInitialData(refresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      drawer: TransitDrawer(
        currentMode: TransitMode.thsr,
        onModeChanged: widget.onModeChanged,
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: _loadingStations && _stations.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _pageError != null && _stations.isEmpty
                    ? TransitErrorState(
                        message: _pageError!,
                        onRetry: () => _loadInitialData(refresh: true),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _loadInitialData(refresh: true),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (_alerts.isNotEmpty) ...[
                              RailAlertCard(alerts: _alerts),
                              const SizedBox(height: 16),
                            ],
                            _buildSeatOverview(theme),
                            const SizedBox(height: 16),
                            _ThsrPanelButtons(
                              current: _panel,
                              onChanged: (panel) =>
                                  setState(() => _panel = panel),
                            ),
                            const SizedBox(height: 16),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: switch (_panel) {
                                _ThsrPanel.timetable => _buildTimetablePanel(
                                  theme,
                                ),
                                _ThsrPanel.seats => _buildSeatPanel(theme),
                                _ThsrPanel.map => _buildMapPanel(theme),
                              },
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          const AdBannerWidget(),
        ],
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
                      // const SizedBox(height: 4),
                      // Text(
                      //   '先看站點座位餘量，再決定要不要切到時刻表查下一班。',
                      //   style: theme.textTheme.bodySmall?.copyWith(
                      //     color: theme.colorScheme.onSurfaceVariant,
                      //   ),
                      // ),
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
            RailStationField(
              key: const ValueKey('thsr-observed-selector'),
              label: '觀察車站',
              station: selectedStation,
              placeholder: '選擇車站',
              onTap: _pickerGroups.isEmpty ? null : _chooseObservedStation,
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
                          // Seat data is live, so it is always about today.
                          isPast: _isTrainPast(
                            info.departureTime,
                            serviceDate: DateTime.now(),
                          ),
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
    final past = _results
        .where((train) => _isTrainPast(train.originDeparture))
        .toList(growable: false);
    final upcoming = _results
        .where((train) => !_isTrainPast(train.originDeparture))
        .toList(growable: false);

    return Column(
      key: const ValueKey('timetable'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                RailStationField(
                  key: const ValueKey('thsr-origin-selector'),
                  label: '出發站',
                  station: _origin,
                  placeholder: '選擇出發站',
                  onTap: _pickerGroups.isEmpty ? null : _chooseOrigin,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: _swapStations,
                    icon: const Icon(Icons.swap_vert_rounded),
                    tooltip: '交換',
                  ),
                ),
                RailStationField(
                  key: const ValueKey('thsr-dest-selector'),
                  label: '到達站',
                  station: _dest,
                  placeholder: '選擇到達站',
                  onTap: _pickerGroups.isEmpty ? null : _chooseDest,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today_rounded),
                        label: Text(
                          '${_date.month}/${_date.day}（${railWeekdayLabel(_date.weekday)}）',
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
          _results.isEmpty
              ? '尚未查詢班次'
              : '還有 ${upcoming.length} 班可搭（共 ${_results.length} 班）',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        if (_results.isEmpty)
          const TransitEmptyPanel(
            icon: Icons.schedule_rounded,
            label: '選好起訖站與日期後，就能看高鐵班次。',
          )
        else ...[
          if (past.isNotEmpty) ...[
            PastTrainsDisclosure(
              key: const ValueKey('thsr-past-toggle'),
              count: past.length,
              expanded: _showPastTrains,
              onToggle: () =>
                  setState(() => _showPastTrains = !_showPastTrains),
            ),
            const SizedBox(height: 10),
            if (_showPastTrains)
              ...past.map(
                (train) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ThsrTimetableTile(train: train, isPast: true),
                ),
              ),
          ],
          if (upcoming.isEmpty)
            TransitEmptyPanel(
              icon: Icons.nightlight_round,
              label: '這一天的班次都開完了。',
            )
          else
            ...upcoming.map(
              (train) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ThsrTimetableTile(train: train),
              ),
            ),
        ],
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
                // const SizedBox(height: 8),
                // Text(
                //   '這裡直接看站點即時座位資訊；想換站時，地圖面板會比較直覺。',
                //   style: theme.textTheme.bodySmall?.copyWith(
                //     color: theme.colorScheme.onSurfaceVariant,
                //   ),
                // ),
                const SizedBox(height: 16),
                RailStationField(
                  key: const ValueKey('thsr-seat-selector'),
                  label: '查詢站點',
                  station: _selectedStation,
                  placeholder: '選擇車站',
                  onTap: _pickerGroups.isEmpty ? null : _chooseObservedStation,
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
          const TransitEmptyPanel(
            icon: Icons.airline_seat_recline_normal_rounded,
            label: '先選一個站，再看各班次座位餘量。',
          )
        else if (_seatInfos.isEmpty)
          const TransitEmptyPanel(
            icon: Icons.airline_seat_recline_normal_rounded,
            label: '目前沒有可顯示的座位資料。',
          )
        else
          ..._seatInfos.map((info) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ThsrSeatTile(
                info: info,
                station: _selectedStation!,
                isPast: _isTrainPast(
                  info.departureTime,
                  serviceDate: DateTime.now(),
                ),
              ),
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
                // const SizedBox(height: 8),
                // Text(
                //   '點一下站點就能把下面的座位資訊切過去，動線比先選列表再回上一頁快。',
                //   style: theme.textTheme.bodySmall?.copyWith(
                //     color: theme.colorScheme.onSurfaceVariant,
                //   ),
                // ),
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
          child: TransitPanelButton(
            icon: Icons.schedule_rounded,
            label: '班次查詢',
            selected: current == _ThsrPanel.timetable,
            onPressed: () => onChanged(_ThsrPanel.timetable),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TransitPanelButton(
            icon: Icons.airline_seat_recline_normal_rounded,
            label: '座位資訊',
            selected: current == _ThsrPanel.seats,
            onPressed: () => onChanged(_ThsrPanel.seats),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TransitPanelButton(
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


class _ThsrTimetableTile extends StatelessWidget {
  const _ThsrTimetableTile({required this.train, this.isPast = false});

  final ThsrOdTrain train;
  final bool isPast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Past rows drop the high-speed-rail amber for the app's neutral "nothing
    // useful to say" pair, rather than being wrapped in Opacity — cards are
    // already translucent when a background image is set.
    final chipBackground = isPast
        ? cs.surfaceContainerHighest
        : (isDark
              ? Colors.orange.shade900.withValues(alpha: 0.35)
              : Colors.orange.shade100);
    final chipForeground = isPast
        ? cs.onSurfaceVariant
        : (isDark ? Colors.orange.shade200 : Colors.orange.shade900);

    return Card(
      color: isPast
          ? cs.surfaceContainerHighest.withValues(alpha: 0.22)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 72,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: BoxDecoration(
                color: chipBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    train.trainNo,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: chipForeground,
                    ),
                  ),
                  Text(
                    '高鐵',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: chipForeground,
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
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: isPast ? cs.onSurfaceVariant : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${train.startStation} → ${train.endStation}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isPast ? cs.outline : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (isPast)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 13,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '已開出',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              )
            else
              Text(
                railDurationLabel(train.originDeparture, train.destArrival),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }

}

class _ThsrSeatTile extends StatelessWidget {
  const _ThsrSeatTile({
    required this.info,
    required this.station,
    this.isPast = false,
  });

  final ThsrSeatInfo info;
  final RailStation station;

  /// Seat availability on a train that has already left is pure noise.
  final bool isPast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final seat = _seatForStation();
    final chipBackground = isPast
        ? cs.surfaceContainerHighest
        : (isDark
              ? Colors.orange.shade900.withValues(alpha: 0.35)
              : Colors.orange.shade100);

    return Card(
      color: isPast
          ? cs.surfaceContainerHighest.withValues(alpha: 0.22)
          : null,
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
                    color: chipBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    info.trainNo,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isPast
                          ? cs.onSurfaceVariant
                          : (isDark
                                ? Colors.orange.shade200
                                : Colors.orange.shade900),
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


