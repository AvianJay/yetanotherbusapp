import 'dart:async';

import 'package:flutter/material.dart';

import '../core/transit_repository.dart';
import '../widgets/eta_badge.dart';
import '../widgets/transit_drawer.dart';

class MetroScreen extends StatefulWidget {
  const MetroScreen({required this.onModeChanged, super.key});

  final ValueChanged<TransitMode> onModeChanged;

  @override
  State<MetroScreen> createState() => _MetroScreenState();
}

class _MetroScreenState extends State<MetroScreen> {
  final TransitRepository _repo = TransitRepository();
  bool _loading = true;
  String? _error;
  List<MetroSystem> _systems = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final systems = await _repo.getMetroSystems();
      if (!mounted) return;
      setState(() => _systems = systems);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('YAMetro'),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
      ),
      drawer: TransitDrawer(
        currentMode: TransitMode.metro,
        onModeChanged: widget.onModeChanged,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('重試'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _systems.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final sys = _systems[index];
                    return _SystemCard(
                      system: sys,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _MetroLinesScreen(
                              repo: _repo,
                              system: sys,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}

class _SystemCard extends StatelessWidget {
  const _SystemCard({required this.system, required this.onTap});

  final MetroSystem system;
  final VoidCallback onTap;

  IconData get _icon => switch (system.system) {
        'TRTC' => Icons.subway_rounded,
        'KRTC' => Icons.tram_rounded,
        'TYMC' => Icons.airport_shuttle_rounded,
        'TMRT' => Icons.directions_railway_rounded,
        _ => Icons.directions_transit_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(_icon, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      system.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      system.nameEn,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Metro Lines Screen (per system)
// ══════════════════════════════════════════════════════════════════════════════

class _MetroLinesScreen extends StatefulWidget {
  const _MetroLinesScreen({required this.repo, required this.system});

  final TransitRepository repo;
  final MetroSystem system;

  @override
  State<_MetroLinesScreen> createState() => _MetroLinesScreenState();
}

class _MetroLinesScreenState extends State<_MetroLinesScreen> {
  bool _loading = true;
  String? _error;
  List<MetroLine> _lines = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lines = await widget.repo.getMetroLines(widget.system.system);
      if (!mounted) return;
      setState(() => _lines = lines);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _parseColor(String hex) {
    if (hex.isEmpty) return Colors.grey;
    final cleaned = hex.replaceAll('#', '');
    if (cleaned.length == 6) {
      return Color(int.parse('FF$cleaned', radix: 16));
    }
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.system.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('重試'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _lines.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final line = _lines[index];
                    final lineColor = _parseColor(line.color);
                    return Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => MetroLineDetailScreen(
                                repo: widget.repo,
                                system: widget.system,
                                line: line,
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: lineColor,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      line.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    if (line.nameEn.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        line.nameEn,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Metro Line Detail Screen (liveboard)
// ══════════════════════════════════════════════════════════════════════════════

class MetroLineDetailScreen extends StatefulWidget {
  const MetroLineDetailScreen({
    required this.repo,
    required this.system,
    required this.line,
    super.key,
  });

  final TransitRepository repo;
  final MetroSystem system;
  final MetroLine line;

  @override
  State<MetroLineDetailScreen> createState() => _MetroLineDetailScreenState();
}

class _MetroLineDetailScreenState extends State<MetroLineDetailScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  List<MetroStationOfLine> _stationOfLine = [];
  List<MetroLiveBoardEntry> _liveboard = [];
  String _etaSource = 'unknown';
  String? _etaMessage;
  List<MetroFrequencyInfo>? _frequency;
  Timer? _refreshTimer;
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final futures = await Future.wait([
        widget.repo.getMetroStationOfLine(widget.system.system),
        widget.repo.getMetroLineEta(widget.system.system, widget.line.lineId),
      ]);
      if (!mounted) return;

      final allSol = futures[0] as List<MetroStationOfLine>;
      final etaResponse = futures[1] as MetroEtaResponse;

      // Filter to this line only.
      final filtered =
          allSol.where((s) => s.lineId == widget.line.lineId).toList();

      if (_tabController == null || _tabController!.length != filtered.length) {
        _tabController?.dispose();
        _tabController = TabController(
          length: filtered.length.clamp(1, 10),
          vsync: this,
        );
      }

      setState(() {
        _stationOfLine = filtered;
        _liveboard = etaResponse.entries;
        _etaSource = etaResponse.source;
        _etaMessage = etaResponse.message;
        _frequency = etaResponse.frequency;
      });

      _startAutoRefresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _refreshLiveboard();
    });
  }

  Future<void> _refreshLiveboard() async {
    try {
      final etaResponse = await widget.repo.getMetroLineEta(
        widget.system.system,
        widget.line.lineId,
      );
      if (!mounted) return;
      setState(() {
        _liveboard = etaResponse.entries;
        _etaSource = etaResponse.source;
        _etaMessage = etaResponse.message;
        _frequency = etaResponse.frequency;
      });
    } catch (_) {
      // Silently ignore refresh errors.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.line.name),
        actions: [
          IconButton(
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: _stationOfLine.length > 1 && _tabController != null
            ? TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: _stationOfLine.map((sol) {
                  final label = sol.direction == 0 ? '方向 1' : '方向 2';
                  final stations = sol.stations;
                  if (stations.isNotEmpty) {
                    return Tab(text: '往${stations.last.name}');
                  }
                  return Tab(text: label);
                }).toList(),
              )
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _loadAll,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('重試'),
                        ),
                      ],
                    ),
                  ),
                )
              : _stationOfLine.isEmpty
                  ? const Center(child: Text('此路線尚無站點資料。'))
                  : Column(
                      children: [
                        // Show message for frequency-only mode (TMRT)
                        if (_etaSource == 'frequency' || _liveboard.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 18,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _etaMessage ?? '此捷運系統目前無即時到站資訊',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // Show frequency info for TMRT
                        if (_etaSource == 'frequency' && _frequency != null)
                          ..._buildFrequencyInfo(),
                        Expanded(
                          child: _stationOfLine.length <= 1
                              ? _buildStationList(_stationOfLine.first)
                              : TabBarView(
                                  controller: _tabController,
                                  children: _stationOfLine
                                      .map(_buildStationList)
                                      .toList(),
                                ),
                        ),
                      ],
                    ),
    );
  }

  List<Widget> _buildFrequencyInfo() {
    if (_frequency == null || _frequency!.isEmpty) return [];

    final theme = Theme.of(context);
    final currentHeadway = _getCurrentHeadway();
    if (currentHeadway == null) return [];

    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        child: Row(
          children: [
            Icon(
              Icons.schedule_rounded,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '班距約 ${currentHeadway.minHeadway}-${currentHeadway.maxHeadway} 分鐘',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  MetroHeadway? _getCurrentHeadway() {
    if (_frequency == null || _frequency!.isEmpty) return null;

    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;

    for (final freq in _frequency!) {
      for (final hw in freq.headways) {
        final startParts = hw.startTime.split(':');
        final endParts = hw.endTime.split(':');
        if (startParts.length >= 2 && endParts.length >= 2) {
          final startMinutes =
              int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
          final endMinutes =
              int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
          if (nowMinutes >= startMinutes && nowMinutes <= endMinutes) {
            return hw;
          }
        }
      }
    }

    // Return first headway as fallback
    return _frequency!.first.headways.isNotEmpty
        ? _frequency!.first.headways.first
        : null;
  }

  Widget _buildStationList(MetroStationOfLine sol) {
    final theme = Theme.of(context);
    // Build lookup: stationId → list of liveboard entries for this direction
    final liveMap = <String, List<MetroLiveBoardEntry>>{};
    for (final entry in _liveboard) {
      // Only include entries matching this direction's destination
      if (sol.stations.isNotEmpty) {
        final lastStation = sol.stations.last;
        // Match by destination or direction
        if (entry.destinationId == lastStation.stationId ||
            entry.direction == sol.direction ||
            entry.tripHeadSign.contains(lastStation.name)) {
          liveMap.putIfAbsent(entry.stationId, () => []).add(entry);
        }
      }
    }

    // If no filtered entries, show all (fallback)
    if (liveMap.isEmpty) {
      for (final entry in _liveboard) {
        liveMap.putIfAbsent(entry.stationId, () => []).add(entry);
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: sol.stations.length,
      itemBuilder: (context, index) {
        final station = sol.stations[index];
        final liveEntries = liveMap[station.stationId] ?? [];
        // Pick the nearest arrival (smallest positive estimatedTime)
        MetroLiveBoardEntry? nearestEntry;
        for (final e in liveEntries) {
          if (e.estimatedTime != null) {
            if (nearestEntry == null ||
                (e.estimatedTime! >= 0 &&
                    (nearestEntry.estimatedTime! < 0 ||
                        e.estimatedTime! < nearestEntry.estimatedTime!))) {
              nearestEntry = e;
            }
          }
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ETA Badge
                  GenericEtaBadge(
                    seconds: nearestEntry?.estimatedTime,
                    size: 58,
                  ),
                  const SizedBox(width: 16),
                  // Station name and divider
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Line color indicator
                        Container(
                          width: 4,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _parseLineColor(),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Station name
                        Text(
                          station.name,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Divider line
                        Expanded(
                          child: Container(
                            height: 1,
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        // Show destination if available
                        if (nearestEntry != null &&
                            nearestEntry.tripHeadSign.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            nearestEntry.tripHeadSign,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _parseLineColor() {
    final hex = widget.line.color.replaceAll('#', '');
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    return Colors.grey;
  }
}
