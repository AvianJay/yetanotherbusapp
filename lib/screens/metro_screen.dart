import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/transit_repository.dart';

class MetroScreen extends StatefulWidget {
  const MetroScreen({super.key});

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
      appBar: AppBar(title: const Text('捷運')),
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
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
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
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
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
        widget.repo.getMetroLiveBoard(widget.system.system, widget.line.lineId),
      ]);
      if (!mounted) return;

      final allSol = futures[0] as List<MetroStationOfLine>;
      final liveboard = futures[1] as List<MetroLiveBoardEntry>;

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
        _liveboard = liveboard;
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
      final liveboard = await widget.repo.getMetroLiveBoard(
        widget.system.system,
        widget.line.lineId,
      );
      if (!mounted) return;
      setState(() => _liveboard = liveboard);
    } catch (_) {
      // Silently ignore refresh errors.
    }
  }

  String _formatEta(int? seconds) {
    if (seconds == null) return '--';
    if (seconds <= 0) return '進站中';
    if (seconds < 60) return '$seconds秒';
    final min = seconds ~/ 60;
    return '$min分';
  }

  Color _etaColor(int? seconds) {
    if (seconds == null) return Colors.grey;
    if (seconds <= 0) return Colors.red.shade700;
    if (seconds < 120) return Colors.orange.shade700;
    return Colors.teal.shade700;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                  : _stationOfLine.length <= 1
                      ? _buildStationList(_stationOfLine.first)
                      : TabBarView(
                          controller: _tabController,
                          children: _stationOfLine
                              .map(_buildStationList)
                              .toList(),
                        ),
    );
  }

  Widget _buildStationList(MetroStationOfLine sol) {
    // Build lookup: stationId → list of liveboard entries
    // TDX does not reliably return Direction for LiveBoard, so show all
    // entries per station regardless of direction.
    final liveMap = <String, List<MetroLiveBoardEntry>>{};
    for (final entry in _liveboard) {
      liveMap.putIfAbsent(entry.stationId, () => []).add(entry);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sol.stations.length,
      itemBuilder: (context, index) {
        final station = sol.stations[index];
        final liveEntries = liveMap[station.stationId] ?? [];
        final isFirst = index == 0;
        final isLast = index == sol.stations.length - 1;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Station line indicator
                SizedBox(
                  width: 32,
                  child: Column(
                    children: [
                      if (!isFirst)
                        Expanded(
                          child: Container(
                            width: 4,
                            color:
                                _parseLineColor().withValues(alpha: 0.6),
                          ),
                        ),
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: _parseLineColor(),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.surface,
                            width: 2,
                          ),
                        ),
                      ),
                      if (!isLast)
                        Expanded(
                          child: Container(
                            width: 4,
                            color:
                                _parseLineColor().withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Station info
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          station.name,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if (liveEntries.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: liveEntries.map((entry) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _etaColor(entry.estimatedTime)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${entry.tripHeadSign.isNotEmpty ? entry.tripHeadSign : '往${entry.destinationName}'} ${_formatEta(entry.estimatedTime)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color:
                                            _etaColor(entry.estimatedTime),
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
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
