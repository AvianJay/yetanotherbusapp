import 'dart:async';

import 'package:flutter/material.dart';

import '../core/transit_repository.dart';
import '../widgets/eta_badge.dart';
import '../widgets/transit_drawer.dart';
import '../widgets/transit_station_map.dart';

enum _MetroPanel { live, map }

class MetroScreen extends StatefulWidget {
  const MetroScreen({required this.onModeChanged, super.key});

  final ValueChanged<TransitMode> onModeChanged;

  @override
  State<MetroScreen> createState() => _MetroScreenState();
}

class _MetroScreenState extends State<MetroScreen> {
  final TransitRepository _repo = TransitRepository();

  bool _loading = true;
  bool _loadingSystem = false;
  bool _loadingEta = false;
  String? _pageError;
  String? _lineError;
  _MetroPanel _panel = _MetroPanel.live;

  List<MetroSystem> _systems = [];
  List<MetroLine> _lines = [];
  List<MetroStation> _stations = [];
  List<MetroStationOfLine> _stationOfLine = [];
  MetroSystem? _selectedSystem;
  MetroLine? _selectedLine;
  String? _selectedStationId;

  List<MetroLiveBoardEntry> _etaEntries = [];
  String _etaSource = 'unknown';
  String? _etaMessage;
  List<MetroFrequencyInfo>? _frequency;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadSystems();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSystems() async {
    setState(() {
      _loading = true;
      _pageError = null;
    });
    try {
      final systems = await _repo.getMetroSystems();
      if (!mounted) {
        return;
      }
      final selectedSystem =
          _pickSystem(systems, _selectedSystem?.system) ??
          (systems.isNotEmpty ? systems.first : null);
      setState(() {
        _systems = systems;
        _selectedSystem = selectedSystem;
      });
      if (selectedSystem != null) {
        await _loadSystemData(system: selectedSystem);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _pageError = '$error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadSystemData({required MetroSystem system}) async {
    _refreshTimer?.cancel();
    setState(() {
      _loadingSystem = true;
      _lineError = null;
      _selectedSystem = system;
      _etaEntries = const [];
      _etaSource = 'unknown';
      _etaMessage = null;
      _frequency = null;
    });
    try {
      final futures = await Future.wait([
        _repo.getMetroLines(system.system),
        _repo.getMetroStations(system.system),
        _repo.getMetroStationOfLine(system.system),
      ]);
      if (!mounted) {
        return;
      }

      final lines = futures[0] as List<MetroLine>;
      final stations = futures[1] as List<MetroStation>;
      final stationOfLine = futures[2] as List<MetroStationOfLine>;
      final selectedLine =
          _pickLine(lines, _selectedLine?.lineId) ??
          (lines.isNotEmpty ? lines.first : null);
      final selectedStationId = _firstStationId(
        stationOfLine,
        selectedLine?.lineId,
      );

      setState(() {
        _lines = lines;
        _stations = stations;
        _stationOfLine = stationOfLine;
        _selectedLine = selectedLine;
        _selectedStationId = selectedStationId;
      });
      if (selectedLine != null) {
        await _loadLineEta(line: selectedLine);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _pageError = '$error');
    } finally {
      if (mounted) {
        setState(() => _loadingSystem = false);
      }
    }
  }

  Future<void> _loadLineEta({MetroLine? line, bool resetTimer = true}) async {
    final activeSystem = _selectedSystem;
    final activeLine = line ?? _selectedLine;
    if (activeSystem == null || activeLine == null) {
      return;
    }
    setState(() {
      _loadingEta = true;
      _lineError = null;
      _selectedLine = activeLine;
    });
    try {
      final eta = await _repo.getMetroLineEta(
        activeSystem.system,
        activeLine.lineId,
      );
      if (!mounted) {
        return;
      }
      final selectedStationId =
          _lineContainsStation(activeLine.lineId, _selectedStationId)
          ? _selectedStationId
          : _firstStationId(_stationOfLine, activeLine.lineId);
      setState(() {
        _selectedLine = activeLine;
        _selectedStationId = selectedStationId;
        _etaEntries = eta.entries;
        _etaSource = eta.source;
        _etaMessage = eta.message;
        _frequency = eta.frequency;
      });
      if (resetTimer) {
        _refreshTimer?.cancel();
        _refreshTimer = Timer.periodic(
          const Duration(seconds: 10),
          (_) => _loadLineEta(resetTimer: false),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _lineError = '$error');
    } finally {
      if (mounted) {
        setState(() => _loadingEta = false);
      }
    }
  }

  MetroSystem? _pickSystem(List<MetroSystem> systems, String? systemCode) {
    if (systemCode == null || systemCode.isEmpty) {
      return null;
    }
    for (final system in systems) {
      if (system.system == systemCode) {
        return system;
      }
    }
    return null;
  }

  MetroLine? _pickLine(List<MetroLine> lines, String? lineId) {
    if (lineId == null || lineId.isEmpty) {
      return null;
    }
    for (final line in lines) {
      if (line.lineId == lineId) {
        return line;
      }
    }
    return null;
  }

  String? _firstStationId(
    List<MetroStationOfLine> stationOfLine,
    String? lineId,
  ) {
    if (lineId == null) {
      return null;
    }
    for (final entry in stationOfLine) {
      if (entry.lineId == lineId && entry.stations.isNotEmpty) {
        return entry.stations.first.stationId;
      }
    }
    return null;
  }

  bool _lineContainsStation(String lineId, String? stationId) {
    if (stationId == null || stationId.isEmpty) {
      return false;
    }
    for (final entry in _lineDirections) {
      for (final station in entry.stations) {
        if (station.stationId == stationId && entry.lineId == lineId) {
          return true;
        }
      }
    }
    return false;
  }

  List<MetroStationOfLine> get _lineDirections {
    final selectedLine = _selectedLine;
    if (selectedLine == null) {
      return const [];
    }
    final filtered = _stationOfLine
        .where((entry) => entry.lineId == selectedLine.lineId)
        .toList(growable: false);
    filtered.sort((left, right) => left.direction.compareTo(right.direction));
    return filtered;
  }

  Map<String, MetroStation> get _stationLookup {
    final selectedLine = _selectedLine;
    if (selectedLine == null) {
      return const {};
    }
    final lookup = <String, MetroStation>{};
    for (final station in _stations) {
      if (station.lineId == selectedLine.lineId) {
        lookup.putIfAbsent(station.stationId, () => station);
      }
    }
    return lookup;
  }

  List<MetroStationSequence> get _uniqueStations {
    final seen = <String>{};
    final stations = <MetroStationSequence>[];
    for (final direction in _lineDirections) {
      for (final station in direction.stations) {
        if (seen.add(station.stationId)) {
          stations.add(station);
        }
      }
    }
    return stations;
  }

  MetroHeadway? get _currentHeadway {
    final selectedLine = _selectedLine;
    final frequency = _frequency;
    if (selectedLine == null || frequency == null || frequency.isEmpty) {
      return null;
    }
    final matched = frequency
        .where((item) => item.lineId == selectedLine.lineId)
        .toList();
    final pool = matched.isNotEmpty ? matched : frequency;
    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;

    for (final info in pool) {
      for (final headway in info.headways) {
        final startParts = headway.startTime.split(':');
        final endParts = headway.endTime.split(':');
        if (startParts.length < 2 || endParts.length < 2) {
          continue;
        }
        final startMinutes =
            int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
        final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
        if (nowMinutes >= startMinutes && nowMinutes <= endMinutes) {
          return headway;
        }
      }
    }

    for (final info in pool) {
      if (info.headways.isNotEmpty) {
        return info.headways.first;
      }
    }
    return null;
  }

  List<MetroLiveBoardEntry> _entriesForStation(String stationId) {
    final selectedLine = _selectedLine;
    if (selectedLine == null) {
      return const [];
    }
    final entries = _etaEntries
        .where(
          (entry) =>
              entry.lineId == selectedLine.lineId &&
              entry.stationId == stationId,
        )
        .toList(growable: false);
    entries.sort(_compareEntries);
    return entries;
  }

  int _compareEntries(MetroLiveBoardEntry left, MetroLiveBoardEntry right) {
    final leftEta = left.estimatedTime ?? 1 << 30;
    final rightEta = right.estimatedTime ?? 1 << 30;
    return leftEta.compareTo(rightEta);
  }

  MetroLiveBoardEntry? _nearestEntry(
    MetroStationOfLine direction,
    MetroStationSequence station,
  ) {
    final matches = <MetroLiveBoardEntry>[];
    final destination = direction.stations.isNotEmpty
        ? direction.stations.last
        : null;

    for (final entry in _etaEntries) {
      if (entry.stationId != station.stationId) {
        continue;
      }
      if (destination != null &&
          (entry.destinationId == destination.stationId ||
              entry.direction == direction.direction ||
              entry.tripHeadSign.contains(destination.name))) {
        matches.add(entry);
      }
    }

    if (matches.isEmpty) {
      for (final entry in _etaEntries) {
        if (entry.stationId == station.stationId) {
          matches.add(entry);
        }
      }
    }
    if (matches.isEmpty) {
      return null;
    }
    matches.sort(_compareEntries);
    return matches.first;
  }

  Color _parseLineColor(String hex) {
    if (hex.isEmpty) {
      return Colors.grey;
    }
    final cleaned = hex.replaceAll('#', '');
    if (cleaned.length == 6) {
      return Color(int.parse('FF$cleaned', radix: 16));
    }
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('YAMetro'),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            tooltip: '重新整理',
            onPressed: _selectedSystem == null
                ? _loadSystems
                : () => _loadSystemData(system: _selectedSystem!),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      drawer: TransitDrawer(
        currentMode: TransitMode.metro,
        onModeChanged: widget.onModeChanged,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _pageError != null && _systems.isEmpty
          ? _ErrorState(message: _pageError!, onRetry: _loadSystems)
          : RefreshIndicator(
              onRefresh: _selectedSystem == null
                  ? _loadSystems
                  : () => _loadSystemData(system: _selectedSystem!),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSystemSelector(theme),
                  const SizedBox(height: 16),
                  _buildLineSelector(theme),
                  const SizedBox(height: 16),
                  if (_lineError != null) ...[
                    Text(
                      _lineError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _buildSourceBanner(theme),
                  const SizedBox(height: 16),
                  _MetroPanelButtons(
                    current: _panel,
                    onChanged: (panel) => setState(() => _panel = panel),
                  ),
                  const SizedBox(height: 16),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: switch (_panel) {
                      _MetroPanel.live => _buildLivePanel(theme),
                      _MetroPanel.map => _buildMapPanel(theme),
                    },
                  ),
                ],
              ),
            ),
      );
  }

  Widget _buildSystemSelector(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '捷運系統',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '先切城市，再切路線；同一頁就能看即時到站與站點地圖。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _systems
                  .map((system) {
                    final selected = system.system == _selectedSystem?.system;
                    return ChoiceChip(
                      label: Text(system.name),
                      selected: selected,
                      avatar: Icon(_systemIcon(system.system), size: 18),
                      onSelected: _loadingSystem
                          ? null
                          : (_) => _loadSystemData(system: system),
                    );
                  })
                  .toList(growable: false),
            ),
            if (_loadingSystem) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLineSelector(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedLine == null ? '尚未選擇路線' : _selectedLine!.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_selectedLine != null)
                  FilledButton.tonalIcon(
                    onPressed: _loadingEta ? null : () => _loadLineEta(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('更新 ETA'),
                  ),
              ],
            ),
            if (_selectedLine != null && _selectedLine!.nameEn.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _selectedLine!.nameEn,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (_lines.isEmpty)
              const _EmptyPanel(
                icon: Icons.directions_transit_rounded,
                label: '這個捷運系統目前沒有可用路線。',
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _lines
                      .map((line) {
                        final selected = line.lineId == _selectedLine?.lineId;
                        return Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: _LinePill(
                            line: line,
                            selected: selected,
                            onTap: _loadingSystem
                                ? null
                                : () => _loadLineEta(line: line),
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              ),
            if (_loadingEta) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSourceBanner(ThemeData theme) {
    final currentHeadway = _currentHeadway;
    final message = switch (_etaSource) {
      'liveboard' => '目前使用即時到站資料。',
      'timetable' => _etaMessage ?? '目前改用時刻表推估到站。',
      'frequency' =>
        currentHeadway == null
            ? (_etaMessage ?? '目前只有班距資訊。')
            : '目前以班距估算，約 ${currentHeadway.minHeadway}-${currentHeadway.maxHeadway} 分鐘。',
      _ => _etaMessage ?? '目前 ETA 來源未標示。',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLivePanel(ThemeData theme) {
    if (_selectedLine == null) {
      return const _EmptyPanel(
        key: ValueKey('metro_live_empty'),
        icon: Icons.subway_rounded,
        label: '先選一條捷運路線。',
      );
    }
    if (_lineDirections.isEmpty) {
      return const _EmptyPanel(
        key: ValueKey('metro_live_no_stations'),
        icon: Icons.timeline_rounded,
        label: '這條路線目前沒有站序資料。',
      );
    }

    return Column(
      key: const ValueKey('metro_live'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _lineDirections
          .map((direction) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _DirectionSection(
                direction: direction,
                lineColor: _parseLineColor(_selectedLine!.color),
                headway: _currentHeadway,
                etaSource: _etaSource,
                onStationTap: (stationId) {
                  setState(() {
                    _selectedStationId = stationId;
                    _panel = _MetroPanel.map;
                  });
                },
                stationBuilder: (station) => _MetroStationRow(
                  station: station,
                  entry: _nearestEntry(direction, station),
                  lineColor: _parseLineColor(_selectedLine!.color),
                  frequencyLabel: _currentHeadway == null
                      ? null
                      : '${_currentHeadway!.minHeadway}-${_currentHeadway!.maxHeadway}分',
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }

  Widget _buildMapPanel(ThemeData theme) {
    final selectedLine = _selectedLine;
    final lineColor = _parseLineColor(selectedLine?.color ?? '');
    final points = _uniqueStations
        .map((sequence) {
          final station = _stationLookup[sequence.stationId];
          return TransitMapPoint(
            id: sequence.stationId,
            label: sequence.name,
            subtitle: sequence.nameEn,
            latitude: station?.lat ?? 0,
            longitude: station?.lon ?? 0,
            color: lineColor,
          );
        })
        .toList(growable: false);

    return Column(
      key: const ValueKey('metro_map'),
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
                        '路線地圖',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          setState(() => _panel = _MetroPanel.live),
                      icon: const Icon(Icons.access_time_filled_rounded),
                      label: const Text('看 ETA'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '點站點會把下方切到該站最近列車；不需要再進第二層畫面。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TransitStationMap(
                  points: points,
                  selectedPointId: _selectedStationId,
                  onPointSelected: (point) {
                    setState(() => _selectedStationId = point.id);
                  },
                  height: 360,
                  emptyLabel: '這條捷運路線目前沒有可用站點座標。',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_selectedStationCardData case final data?)
          _SelectedMetroStationCard(
            title: data.$1.name,
            subtitle: data.$1.nameEn,
            entries: data.$2,
            headway: _currentHeadway,
            onRefresh: _loadLineEta,
          ),
      ],
    );
  }

  (MetroStationSequence, List<MetroLiveBoardEntry>)?
  get _selectedStationCardData {
    final stationId = _selectedStationId;
    if (stationId == null) {
      return null;
    }
    for (final station in _uniqueStations) {
      if (station.stationId == stationId) {
        return (station, _entriesForStation(stationId));
      }
    }
    return null;
  }

  IconData _systemIcon(String system) => switch (system) {
    'TRTC' => Icons.subway_rounded,
    'KRTC' => Icons.tram_rounded,
    'TYMC' => Icons.airport_shuttle_rounded,
    'TMRT' => Icons.directions_railway_rounded,
    _ => Icons.directions_transit_rounded,
  };
}

class _MetroPanelButtons extends StatelessWidget {
  const _MetroPanelButtons({required this.current, required this.onChanged});

  final _MetroPanel current;
  final ValueChanged<_MetroPanel> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PanelButton(
            icon: Icons.access_time_filled_rounded,
            label: '即時到站',
            selected: current == _MetroPanel.live,
            onPressed: () => onChanged(_MetroPanel.live),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PanelButton(
            icon: Icons.map_rounded,
            label: '站點地圖',
            selected: current == _MetroPanel.map,
            onPressed: () => onChanged(_MetroPanel.map),
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

class _LinePill extends StatelessWidget {
  const _LinePill({
    required this.line,
    required this.selected,
    required this.onTap,
  });

  final MetroLine line;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final lineColor = _parseLineColor(line.color);
    final theme = Theme.of(context);

    return Material(
      color: selected ? lineColor.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? lineColor : theme.colorScheme.outlineVariant,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: lineColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                line.name,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _parseLineColor(String hex) {
    final cleaned = hex.replaceAll('#', '');
    if (cleaned.length == 6) {
      return Color(int.parse('FF$cleaned', radix: 16));
    }
    return Colors.grey;
  }
}

class _DirectionSection extends StatelessWidget {
  const _DirectionSection({
    required this.direction,
    required this.lineColor,
    required this.headway,
    required this.etaSource,
    required this.stationBuilder,
    required this.onStationTap,
  });

  final MetroStationOfLine direction;
  final Color lineColor;
  final MetroHeadway? headway;
  final String etaSource;
  final Widget Function(MetroStationSequence station) stationBuilder;
  final ValueChanged<String> onStationTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final destination = direction.stations.isNotEmpty
        ? direction.stations.last.name
        : '方向 ${direction.direction + 1}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: lineColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '往 $destination',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (etaSource == 'frequency' && headway != null)
                  Chip(
                    label: Text(
                      '班距 ${headway!.minHeadway}-${headway!.maxHeadway} 分',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ...direction.stations.map((station) {
              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => onStationTap(station.stationId),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: stationBuilder(station),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _MetroStationRow extends StatelessWidget {
  const _MetroStationRow({
    required this.station,
    required this.entry,
    required this.lineColor,
    required this.frequencyLabel,
  });

  final MetroStationSequence station;
  final MetroLiveBoardEntry? entry;
  final Color lineColor;
  final String? frequencyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GenericEtaBadge(
          seconds: entry?.estimatedTime,
          message: entry == null ? frequencyLabel : null,
          size: 56,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Row(
            children: [
              Container(
                width: 4,
                height: 36,
                decoration: BoxDecoration(
                  color: lineColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (entry != null && entry!.tripHeadSign.isNotEmpty)
                      Text(
                        entry!.tripHeadSign,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    else if (station.nameEn.isNotEmpty)
                      Text(
                        station.nameEn,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SelectedMetroStationCard extends StatelessWidget {
  const _SelectedMetroStationCard({
    required this.title,
    required this.subtitle,
    required this.entries,
    required this.headway,
    required this.onRefresh,
  });

  final String title;
  final String subtitle;
  final List<MetroLiveBoardEntry> entries;
  final MetroHeadway? headway;
  final Future<void> Function({MetroLine? line, bool resetTimer}) onRefresh;

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
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => onRefresh(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('刷新'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Text(
                headway == null
                    ? '這個車站目前沒有可顯示的即時班次。'
                    : '目前僅提供班距估算，約 ${headway!.minHeadway}-${headway!.maxHeadway} 分鐘。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              )
            else
              ...entries.take(4).map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _MetroArrivalTile(entry: entry),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _MetroArrivalTile extends StatelessWidget {
  const _MetroArrivalTile({required this.entry});

  final MetroLiveBoardEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          GenericEtaBadge(seconds: entry.estimatedTime, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.tripHeadSign.isEmpty
                      ? entry.destinationName
                      : entry.tripHeadSign,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '往 ${entry.destinationName}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.icon, required this.label, super.key});

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
