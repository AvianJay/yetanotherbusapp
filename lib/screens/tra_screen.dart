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

enum _TraPanel { query, map }

class TraScreen extends StatefulWidget {
  const TraScreen({
    required this.onModeChanged,
    required this.isActive,
    super.key,
  });

  final ValueChanged<TransitMode> onModeChanged;
  final bool isActive;

  @override
  State<TraScreen> createState() => _TraScreenState();
}

class _TraScreenState extends State<TraScreen> {
  static const _storageSystem = 'tra';

  final TransitRepository _repo = TransitRepository.shared;

  bool _loadingStations = true;
  bool _loadingBoard = false;
  bool _loadingOd = false;
  String? _pageError;
  String? _odError;
  _TraPanel _panel = _TraPanel.query;

  List<RailStation> _stations = [];
  List<RailPickerLine> _pickerGroups = const [];
  List<RailAlert> _alerts = [];

  RailStation? _origin;
  RailStation? _dest;
  DateTime _date = DateTime.now();

  List<TraOdTrain> _odTrains = const [];
  Map<String, TraLiveBoardEntry> _liveByTrainNo = const {};
  List<TraTrainPosition> _trainPositions = [];
  String? _selectedTrainNo;
  bool _showPastTrains = false;

  /// Wall clock used for every "has this train left?" decision, refreshed by
  /// [_clockTimer] so rows grey out on their own between network refreshes.
  DateTime _now = DateTime.now();

  Timer? _liveTimer;
  Timer? _clockTimer;

  final _initialDataRequest = RequestSequence();
  final _boardRequest = RequestSequence();
  final _odRequest = RequestSequence();

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TraScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) {
      return;
    }
    if (!widget.isActive) {
      _cancelTimers();
      return;
    }
    // Coming back to a tab that sat in the background for a while: the clock
    // has to catch up before anything is drawn, or trains that left 20 minutes
    // ago would still look catchable.
    setState(() => _now = DateTime.now());
    if (_origin != null) {
      _applyOd();
    } else if (!_loadingStations) {
      unawaited(_loadInitialData());
    }
    _ensureTimers();
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  Future<void> _loadInitialData({bool refresh = false}) async {
    final request = _initialDataRequest.next();
    _boardRequest.next();
    _odRequest.next();
    if (refresh) {
      _repo.invalidateCache('tra_');
    }
    setState(() {
      _loadingStations = true;
      _pageError = null;
    });
    // Captured before the first await so the context is not used across gaps.
    final storage = AppControllerScope.read(context).storage;
    try {
      // All four are independent, so they go out together rather than costing
      // four serial round trips on a cold start. Only the station list is
      // fatal: alerts are just a banner, and a missing station-of-line only
      // costs the picker its line column.
      final stationsFuture = _repo.getTraStations();
      final alertsFuture = _repo.getTraAlerts().catchError(
        (_) => const <RailAlert>[],
      );
      final linesFuture = _repo.getTraStationOfLine();
      final savedFuture = storage.loadRailOdSelection(_storageSystem);

      final stations = await stationsFuture;
      final alerts = await alertsFuture;
      final lines = await linesFuture;
      final saved = await savedFuture;
      if (!mounted || !_initialDataRequest.isCurrent(request)) return;

      setState(() {
        _stations = stations;
        _alerts = alerts;
        _pickerGroups = buildRailPickerGroups(
          stations: stations,
          lines: lines,
        );
        _origin =
            _pickStation(stations, _origin?.stationId) ??
            _pickStation(stations, saved.origin);
        _dest =
            _pickStation(stations, _dest?.stationId) ??
            _pickStation(stations, saved.dest);
      });
      _applyOd();
    } catch (error) {
      if (!mounted || !_initialDataRequest.isCurrent(request)) return;
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

  /// Single funnel for every change of origin / destination / date.
  ///
  /// The timetable and the live board are fetched **concurrently and
  /// independently**: they are different endpoints, so a live-board outage must
  /// not blank the timetable. The OD list renders first and delay chips fill in
  /// when the board lands.
  void _applyOd() {
    if (_origin == null || _dest == null) {
      setState(() {
        _odTrains = const [];
        _liveByTrainNo = const {};
        _trainPositions = const [];
        _odError = null;
      });
      _cancelTimers();
      return;
    }
    unawaited(_loadOd());
    unawaited(_loadBoard());
    _ensureTimers();
  }

  Future<void> _loadOd() async {
    final origin = _origin;
    final dest = _dest;
    if (origin == null || dest == null) return;
    if (origin.stationId == dest.stationId) {
      setState(() {
        _odTrains = const [];
        _odError = '出發站和到達站不能一樣。';
      });
      return;
    }
    final request = _odRequest.next();
    setState(() {
      _loadingOd = true;
      _odError = null;
    });
    try {
      final dateStr =
          '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
      final results = await _repo.getTraOdTimetable(
        origin: origin.stationId,
        dest: dest.stationId,
        date: dateStr,
      );
      if (!mounted || !_odRequest.isCurrent(request)) return;
      // TDX ordering is not contractual, and the collapsed past section relies
      // on past rows being contiguous.
      final sorted = [...results]
        ..sort((a, b) {
          final left = parseRailClockTime(a.originDeparture, _date);
          final right = parseRailClockTime(b.originDeparture, _date);
          if (left == null || right == null) {
            return 0;
          }
          return left.compareTo(right);
        });
      setState(() {
        _odTrains = sorted;
        // Only today has trains worth hiding. On any other date every row is
        // either all-past or all-future, so collapsing would leave the user
        // staring at a disclosure header above an empty list.
        _showPastTrains = !_isSameDay(_date, DateTime.now());
      });
    } catch (error) {
      if (!mounted || !_odRequest.isCurrent(request)) return;
      setState(() => _odError = friendlyErrorMessage(error));
    } finally {
      if (mounted && _odRequest.isCurrent(request)) {
        setState(() => _loadingOd = false);
      }
    }
  }

  Future<void> _loadBoard() async {
    final origin = _origin;
    if (origin == null) return;
    // Delays and estimated positions only exist for today's services.
    if (!_isSameDay(_date, DateTime.now())) {
      setState(() {
        _liveByTrainNo = const {};
        _trainPositions = const [];
      });
      return;
    }
    final request = _boardRequest.next();
    setState(() => _loadingBoard = true);
    try {
      final boardFuture = _repo.getTraLiveBoard(origin.stationId);
      final positionsFuture = _repo.getTraTrainPositions(origin.stationId);
      final entries = await boardFuture;
      List<TraTrainPosition> positions;
      try {
        positions = await positionsFuture;
      } catch (_) {
        positions = const <TraTrainPosition>[];
      }
      if (!mounted || !_boardRequest.isCurrent(request)) return;
      setState(() {
        _liveByTrainNo = {
          for (final entry in entries)
            if (entry.trainNo.isNotEmpty) entry.trainNo: entry,
        };
        _trainPositions = positions;
        if (_selectedTrainNo != null &&
            !positions.any(
              (position) => position.trainNo == _selectedTrainNo,
            )) {
          _selectedTrainNo = null;
        }
      });
    } catch (_) {
      if (!mounted || !_boardRequest.isCurrent(request)) return;
    } finally {
      if (mounted && _boardRequest.isCurrent(request)) {
        setState(() => _loadingBoard = false);
      }
    }
  }

  // ── Timers ────────────────────────────────────────────────────────────────

  /// Creates both timers once. The live timer used to be re-armed inside
  /// `_loadBoard`'s success path, which meant a single failed fetch stopped the
  /// board refreshing for good.
  void _ensureTimers() {
    if (!widget.isActive || _origin == null) {
      return;
    }
    _liveTimer ??= Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted || !widget.isActive) {
        _cancelTimers();
        return;
      }
      unawaited(_loadBoard());
    });
    // Pure repaint tick: whether a train has left changes with the clock, not
    // with the data, so this must not depend on the network succeeding.
    _clockTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || !widget.isActive) {
        _cancelTimers();
        return;
      }
      setState(() => _now = DateTime.now());
    });
  }

  void _cancelTimers() {
    _liveTimer?.cancel();
    _liveTimer = null;
    _clockTimer?.cancel();
    _clockTimer = null;
  }

  static bool _isSameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  // ── Selection ─────────────────────────────────────────────────────────────

  Future<NearestRailStation?> _locateNearestStation() async {
    final position = await resolveUserPosition();
    return nearestRailStation(
      _stations,
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  Future<void> _chooseOrigin() async {
    final picked = await showRailStationPicker(
      context: context,
      title: '選擇出發站',
      groups: _pickerGroups,
      initial: _origin,
      excluded: _dest,
      onLocate: _locateNearestStation,
    );
    if (picked == null || !mounted) return;
    setState(() => _origin = picked);
    _persistSelection();
    _applyOd();
  }

  Future<void> _chooseDest() async {
    final picked = await showRailStationPicker(
      context: context,
      title: '選擇到達站',
      groups: _pickerGroups,
      initial: _dest,
      excluded: _origin,
      onLocate: _locateNearestStation,
    );
    if (picked == null || !mounted) return;
    setState(() => _dest = picked);
    _persistSelection();
    _applyOd();
  }

  void _persistSelection() {
    unawaited(
      AppControllerScope.read(context).storage.saveRailOdSelection(
        _storageSystem,
        origin: _origin?.stationId,
        dest: _dest?.stationId,
      ),
    );
  }

  void _swapStations() {
    setState(() {
      final temp = _origin;
      _origin = _dest;
      _dest = temp;
    });
    _persistSelection();
    _applyOd();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 14)),
    );
    if (picked != null && mounted) {
      setState(() {
        _date = picked;
        _showPastTrains = !_isSameDay(picked, DateTime.now());
      });
      _applyOd();
    }
  }

  Future<void> _assignFromMap(RailStation station) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                station.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: station.nameEn.isEmpty ? null : Text(station.nameEn),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.trip_origin_rounded),
              title: const Text('設為出發站'),
              onTap: () => Navigator.of(sheetContext).pop('origin'),
            ),
            ListTile(
              leading: const Icon(Icons.place_rounded),
              title: const Text('設為到達站'),
              onTap: () => Navigator.of(sheetContext).pop('dest'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() {
      if (choice == 'origin') {
        if (_dest?.stationId == station.stationId) _dest = null;
        _origin = station;
      } else {
        if (_origin?.stationId == station.stationId) _origin = null;
        _dest = station;
      }
      _selectedTrainNo = null;
      _panel = _TraPanel.query;
    });
    _persistSelection();
    _applyOd();
  }

  // ── Derived data ──────────────────────────────────────────────────────────

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

  /// Live entry for a timetable row, or `null` when the board has not heard of
  /// this train.
  ///
  /// A board entry whose scheduled departure disagrees with the timetable is
  /// dropped: that means a different service day slipped through the 10s cache.
  TraLiveBoardEntry? _liveFor(TraOdTrain train) {
    final live = _liveByTrainNo[train.trainNo];
    if (live == null) {
      return null;
    }
    if (live.scheduledDeparture.isEmpty || train.originDeparture.isEmpty) {
      return live;
    }
    final boardMinutes = parseRailClockTime(live.scheduledDeparture, _date);
    final odMinutes = parseRailClockTime(train.originDeparture, _date);
    if (boardMinutes == null || odMinutes == null) {
      return live;
    }
    return boardMinutes == odMinutes ? live : null;
  }

  List<_TraOdRow> _buildRows() {
    return _odTrains.map((train) {
      final live = _liveFor(train);
      final delay = live?.delayMinutes ?? 0;
      return _TraOdRow(
        train: train,
        live: live,
        isPast: isRailDeparturePast(
          scheduledDeparture: train.originDeparture,
          serviceDate: _date,
          delayMinutes: delay,
          now: _now,
        ),
        minutesUntilDeparture: minutesUntilRailDeparture(
          scheduledDeparture: train.originDeparture,
          serviceDate: _date,
          delayMinutes: delay,
          now: _now,
        ),
        effectiveDeparture: resolveRailDeparture(
          scheduledDeparture: train.originDeparture,
          serviceDate: _date,
          delayMinutes: delay,
        ),
      );
    }).toList(growable: false);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _buildRows();
    final hasBackgroundImage = hasBackgroundImageForPage(
      AppControllerScope.of(context).settings,
      pageKey: 'bus',
    );
    return Scaffold(
      backgroundColor: hasBackgroundImage ? Colors.transparent : null,
      appBar: AppBar(
        title: const Text('YATrain'),
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
        currentMode: TransitMode.tra,
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
                            _buildOdCard(theme, rows),
                            const SizedBox(height: 16),
                            _buildPanelButtons(),
                            const SizedBox(height: 16),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: _panel == _TraPanel.query
                                  ? _buildQueryPanel(theme, rows)
                                  : _buildMapPanel(theme),
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

  Widget _buildPanelButtons() {
    return Row(
      children: [
        Expanded(
          child: TransitPanelButton(
            icon: Icons.schedule_rounded,
            label: '班次',
            selected: _panel == _TraPanel.query,
            onPressed: () => setState(() => _panel = _TraPanel.query),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TransitPanelButton(
            icon: Icons.map_rounded,
            label: '車站地圖',
            selected: _panel == _TraPanel.map,
            onPressed: () => setState(() => _panel = _TraPanel.map),
          ),
        ),
      ],
    );
  }

  Widget _buildOdCard(ThemeData theme, List<_TraOdRow> rows) {
    final upcoming = rows.where((row) => !row.isPast).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RailStationField(
              key: const ValueKey('tra-origin-selector'),
              label: '出發站',
              station: _origin,
              placeholder: '選擇出發站',
              onTap: _pickerGroups.isEmpty ? null : _chooseOrigin,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                key: const ValueKey('tra-swap'),
                onPressed: (_origin == null && _dest == null)
                    ? null
                    : _swapStations,
                icon: const Icon(Icons.swap_vert_rounded),
                tooltip: '對調出發站與到達站',
              ),
            ),
            RailStationField(
              key: const ValueKey('tra-dest-selector'),
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
                    key: const ValueKey('tra-date'),
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_rounded),
                    label: Text(
                      '${_date.month}/${_date.day}（${railWeekdayLabel(_date.weekday)}）',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (_odTrains.isNotEmpty)
                  Text(
                    '還有 $upcoming 班可搭',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
            if (_loadingOd || _loadingBoard) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQueryPanel(ThemeData theme, List<_TraOdRow> rows) {
    final past = rows.where((row) => row.isPast).toList(growable: false);
    final upcoming = rows.where((row) => !row.isPast).toList(growable: false);

    return Column(
      key: const ValueKey('query'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_odError != null) ...[
          Text(_odError!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 12),
        ],
        if (_origin == null || _dest == null)
          TransitEmptyPanel(
            icon: Icons.train_rounded,
            label: '選好出發站和到達站，就會顯示今天還搭得到的班次。',
            action: FilledButton.tonalIcon(
              key: const ValueKey('tra-cold-start-locate'),
              onPressed: _pickerGroups.isEmpty ? null : _chooseOrigin,
              icon: const Icon(Icons.my_location_rounded),
              label: const Text('用目前位置選出發站'),
            ),
          )
        else if (rows.isEmpty)
          TransitEmptyPanel(
            icon: Icons.schedule_rounded,
            label: _loadingOd
                ? '查詢中…'
                : '這兩站之間今天沒有直達班次，可能需要轉車。',
          )
        else ...[
          if (past.isNotEmpty) ...[
            PastTrainsDisclosure(
              key: const ValueKey('tra-past-toggle'),
              count: past.length,
              expanded: _showPastTrains,
              onToggle: () =>
                  setState(() => _showPastTrains = !_showPastTrains),
            ),
            const SizedBox(height: 10),
            if (_showPastTrains)
              ...past.map(
                (row) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _TraOdTile(
                    row: row,
                    origin: _origin!,
                    dest: _dest!,
                    onTap: () => _showTrainOnMap(row.train.trainNo),
                  ),
                ),
              ),
          ],
          if (upcoming.isEmpty)
            TransitEmptyPanel(
              icon: Icons.nightlight_round,
              label: '今天從 ${_origin!.name} 到 ${_dest!.name} 的班次都開完了。',
              action: FilledButton.tonalIcon(
                onPressed: () {
                  setState(() {
                    _date = _date.add(const Duration(days: 1));
                    _showPastTrains = true;
                  });
                  _applyOd();
                },
                icon: const Icon(Icons.east_rounded),
                label: const Text('看明天的班次'),
              ),
            )
          else
            ...upcoming.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TraOdTile(
                  row: row,
                  origin: _origin!,
                  dest: _dest!,
                  onTap: () => _showTrainOnMap(row.train.trainNo),
                ),
              ),
            ),
        ],
      ],
    );
  }

  void _showTrainOnMap(String trainNo) {
    setState(() {
      _selectedTrainNo = trainNo;
      _panel = _TraPanel.map;
    });
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
        : _origin?.stationId;

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
                  '點站牌可設為出發站或到達站，點紅色列車 marker 看估算中的列車位置。',
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
                      unawaited(_assignFromMap(station));
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
      ],
    );
  }


  String _positionSummary(TraTrainPosition position) {
    return switch (position.status) {
      'between_stations' =>
        '${position.currentStationName} → ${position.nextStationName}',
      'arrived' => '已到 ${position.currentStationName}',
      _ => '停靠 ${position.currentStationName}',
    };
  }
}

/// One timetable row plus everything derived from the clock and live board.
class _TraOdRow {
  const _TraOdRow({
    required this.train,
    required this.live,
    required this.isPast,
    required this.minutesUntilDeparture,
    required this.effectiveDeparture,
  });

  final TraOdTrain train;
  final TraLiveBoardEntry? live;
  final bool isPast;
  final int? minutesUntilDeparture;

  /// Scheduled departure plus any live delay — the time the train will really
  /// leave. Null when the scheduled time could not be read.
  final DateTime? effectiveDeparture;
}


class _TraOdTile extends StatelessWidget {
  const _TraOdTile({
    required this.row,
    required this.origin,
    required this.dest,
    required this.onTap,
  });

  final _TraOdRow row;
  final RailStation origin;
  final RailStation dest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final train = row.train;
    final isPast = row.isPast;

    // Past rows drop one step fainter than a normal row rather than being
    // wrapped in Opacity: cards are already translucent when a background image
    // is set (bus_app.dart:161-176), and compositing twice goes muddy.
    final rowBackground = isPast
        ? cs.surfaceContainerHighest.withValues(alpha: 0.22)
        : cs.surfaceContainerHighest.withValues(alpha: 0.45);
    final chipBackground = isPast
        ? cs.surfaceContainerHighest
        : cs.primaryContainer;
    final chipForeground = isPast ? cs.onSurfaceVariant : cs.onPrimaryContainer;

    final duration = railDurationLabel(train.originDeparture, train.destArrival);
    final status = _status(cs);
    final headline =
        '${origin.name} ${train.originDeparture} → ${dest.name} ${train.destArrival}';

    return Semantics(
      button: true,
      label: '${train.trainNo} 次 ${train.trainType}，$headline'
          '${status == null ? '' : '，${status.text}'}',
      child: InkWell(
        key: ValueKey('tra-train-${train.trainNo}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: rowBackground,
            borderRadius: BorderRadius.circular(18),
            border: isPast
                ? Border.all(color: cs.outlineVariant.withValues(alpha: 0.5))
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 62,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
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
                      train.trainType,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: chipForeground,
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
                      headline,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isPast ? cs.onSurfaceVariant : cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        '往 ${train.endStation}',
                        if (duration.isNotEmpty) duration,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isPast ? cs.outline : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (status != null) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: status.background,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(status.icon, size: 13, color: status.foreground),
                          const SizedBox(width: 4),
                          Text(
                            status.text,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: status.foreground,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (status.detail != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        status.detail!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// One mutually-exclusive status slot.
  ///
  /// Returns `null` for a far-future train rather than claiming 準點 for a
  /// service the live board has never reported on — which is what the old tile
  /// did for every train with `delayMinutes <= 0`.
  _TraStatus? _status(ColorScheme cs) {
    // A delay is meaningless once the train has gone, and a red 晚3分 on an
    // uncatchable train reads as "hurry", the opposite of the truth.
    if (row.isPast) {
      return _TraStatus(
        text: '已開出',
        icon: Icons.history_rounded,
        background: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        foreground: cs.onSurfaceVariant,
      );
    }

    final live = row.live;
    if (live != null && live.delayMinutes > 0) {
      final actual = row.effectiveDeparture;
      return _TraStatus(
        text: '晚 ${live.delayMinutes} 分',
        icon: Icons.trending_down_rounded,
        background: cs.errorContainer,
        foreground: cs.onErrorContainer,
        detail: actual == null
            ? null
            : '${actual.hour.toString().padLeft(2, '0')}:'
                  '${actual.minute.toString().padLeft(2, '0')} 發車',
      );
    }

    if (live != null) {
      return _TraStatus(
        text: '準點',
        icon: Icons.check_circle_outline_rounded,
        background: cs.tertiaryContainer,
        foreground: cs.onTertiaryContainer,
      );
    }

    final minutes = row.minutesUntilDeparture;
    if (minutes != null && minutes <= 30) {
      return _TraStatus(
        text: '$minutes 分後',
        icon: Icons.schedule_rounded,
        background: cs.secondaryContainer.withValues(alpha: 0.6),
        foreground: cs.onSecondaryContainer,
      );
    }

    return null;
  }
}

class _TraStatus {
  const _TraStatus({
    required this.text,
    required this.icon,
    required this.background,
    required this.foreground,
    this.detail,
  });

  final String text;
  final IconData icon;
  final Color background;
  final Color foreground;
  final String? detail;
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
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    position.trainNo,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onErrorContainer,
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
                    color: delayed
                        ? theme.colorScheme.errorContainer
                        : theme.colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    delayed ? '晚 ${position.delayMinutes} 分' : '準點',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: delayed
                          ? theme.colorScheme.onErrorContainer
                          : theme.colorScheme.onTertiaryContainer,
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
