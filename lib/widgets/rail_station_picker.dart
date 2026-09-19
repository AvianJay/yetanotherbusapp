import 'package:flutter/material.dart';

import '../core/debouncer.dart';
import '../core/models.dart';
import '../core/rail_line_stations.dart';
import '../core/transit_repository.dart';
import '../core/user_location.dart';

/// Opens the wheel station picker and returns the chosen station, or `null`.
///
/// [onLocate] is injected rather than called directly so this widget never
/// touches Geolocator itself — that keeps it drivable from a widget test, and
/// keeps the permission prompt behind an explicit user tap. Pass `null` to hide
/// the location button entirely.
Future<RailStation?> showRailStationPicker({
  required BuildContext context,
  required String title,
  required List<RailPickerLine> groups,
  RailStation? initial,
  RailStation? excluded,
  Future<NearestRailStation?> Function()? onLocate,
}) {
  return showModalBottomSheet<RailStation>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => RailStationPickerSheet(
      title: title,
      groups: groups,
      initial: initial,
      excluded: excluded,
      onLocate: onLocate,
    ),
  );
}

class RailStationPickerSheet extends StatefulWidget {
  const RailStationPickerSheet({
    required this.title,
    required this.groups,
    this.initial,
    this.excluded,
    this.onLocate,
    super.key,
  });

  final String title;
  final List<RailPickerLine> groups;
  final RailStation? initial;
  final RailStation? excluded;
  final Future<NearestRailStation?> Function()? onLocate;

  @override
  State<RailStationPickerSheet> createState() => _RailStationPickerSheetState();
}

class _RailStationPickerSheetState extends State<RailStationPickerSheet> {
  static const double _itemExtent = 44;
  static const int _visibleRows = 5;

  final _searchController = TextEditingController();
  final _searchDebouncer = Debouncer(const Duration(milliseconds: 200));

  late FixedExtentScrollController _lineController;
  late FixedExtentScrollController _stationController;

  int _groupIndex = 0;
  int _stationIndex = 0;

  /// Bumped to force the station wheel to remount. See [_selectLine].
  int _stationWheelGeneration = 0;

  String? _message;
  bool _locating = false;
  bool _locationUnavailable = false;

  @override
  void initState() {
    super.initState();
    final at = locateStationInGroups(widget.groups, widget.initial?.stationId);
    _groupIndex = at.group;
    _stationIndex = at.station;
    _lineController = FixedExtentScrollController(initialItem: _groupIndex);
    _stationController = FixedExtentScrollController(
      initialItem: _stationIndex,
    );
  }

  @override
  void dispose() {
    _searchDebouncer.dispose();
    _searchController.dispose();
    _lineController.dispose();
    _stationController.dispose();
    super.dispose();
  }

  List<RailPickerLine> get _groups => widget.groups;

  List<RailStation> get _stations =>
      _groupIndex < _groups.length ? _groups[_groupIndex].stations : const [];

  RailStation? get _selected {
    final stations = _stations;
    if (stations.isEmpty) {
      return null;
    }
    // Never index with the raw controller offset: it is not clamped when the
    // list shrinks under it. _stationIndex is the clamped mirror.
    return stations[_stationIndex.clamp(0, stations.length - 1)];
  }

  bool get _confirmEnabled {
    final selected = _selected;
    if (selected == null) {
      return false;
    }
    return selected.stationId != widget.excluded?.stationId;
  }

  /// Switches the line wheel's selection and rebuilds the station wheel.
  ///
  /// The station wheel is **remounted** (new controller + new key) rather than
  /// handed a shorter child list. Flutter does re-clamp a scroll offset that
  /// ends up past the new extent, so this is not guarding against a crash; it
  /// is guarding against the wheel and [_stationIndex] disagreeing. Switching
  /// from 西部幹線 (112 stations) to 成追線 (2 stations) leaves the old position
  /// clamped to the *last* branch station while the state says the *first*.
  /// `initialItem` is only read when a fresh `ScrollPosition` attaches, which
  /// is why the key has to change too.
  void _selectLine(int lineIndex, {int? stationIndex}) {
    if (lineIndex < 0 || lineIndex >= _groups.length) {
      return;
    }
    if (lineIndex == _groupIndex && stationIndex == null) {
      return;
    }

    final nextStations = _groups[lineIndex].stations;
    int nextIndex;
    if (stationIndex != null) {
      nextIndex = stationIndex;
    } else {
      // Keep the same physical station when it also sits on the new line
      // (臺東 is on both 東部幹線 and 南迴線); otherwise start at the top.
      final current = _selected;
      final carried = current == null
          ? -1
          : _groups[lineIndex].indexOfStation(current.stationId);
      nextIndex = carried >= 0 ? carried : 0;
    }
    nextIndex = nextStations.isEmpty
        ? 0
        : nextIndex.clamp(0, nextStations.length - 1);

    final previousController = _stationController;
    setState(() {
      _groupIndex = lineIndex;
      _stationIndex = nextIndex;
      _stationWheelGeneration++;
      _stationController = FixedExtentScrollController(initialItem: nextIndex);
    });
    // The old position detaches when the key change disposes its element, so
    // the controller can only be disposed after that frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previousController.dispose();
    });
  }

  void _onSearchChanged(String value) {
    _searchDebouncer.schedule(() {
      if (!mounted) {
        return;
      }
      if (value.trim().isEmpty) {
        setState(() => _message = null);
        return;
      }
      final hit = findStationInGroups(_groups, value);
      if (hit == null) {
        setState(() => _message = '找不到符合的車站');
        return;
      }
      setState(() => _message = null);
      _jumpTo(hit.group, hit.station);
    });
  }

  /// Moves both wheels onto one station. Deliberately does not filter the wheel
  /// contents — a list that shrinks as you type is disorienting.
  void _jumpTo(int groupIndex, int stationIndex) {
    if (groupIndex == _groupIndex) {
      setState(() => _stationIndex = stationIndex);
      if (_stationController.hasClients) {
        _stationController.animateToItem(
          stationIndex,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }
    _selectLine(groupIndex, stationIndex: stationIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _lineController.hasClients) {
        // _groupIndex is already updated, so the resulting
        // onSelectedItemChanged is a no-op inside _selectLine.
        _lineController.jumpToItem(groupIndex);
      }
    });
  }

  Future<void> _useCurrentLocation() async {
    final onLocate = widget.onLocate;
    if (onLocate == null || _locating) {
      return;
    }
    setState(() {
      _locating = true;
      _message = null;
    });
    try {
      final nearest = await onLocate();
      if (!mounted) {
        return;
      }
      if (nearest == null) {
        setState(() => _message = '找不到附近的車站。');
        return;
      }
      final at = locateStationInGroups(
        _groups,
        nearest.station.stationId,
        preferredGroup: _groupIndex,
      );
      final distance = formatDistance(nearest.distanceMeters);
      setState(
        () => _message = '最近的車站：${nearest.station.name}（約 $distance）',
      );
      // Does not auto-confirm: the user sees which station was picked and still
      // taps 選擇, so a bad GPS fix never silently changes their query.
      _jumpTo(at.group, at.station);
    } on LocationFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = error.message;
        _locationUnavailable = error.deniedForever;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _message = '目前無法取得定位，請稍後再試。');
    } finally {
      if (mounted) {
        setState(() => _locating = false);
      }
    }
  }

  void _confirm() {
    final selected = _selected;
    if (selected == null || !_confirmEnabled) {
      return;
    }
    Navigator.of(context).pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final wheelHeight = _itemExtent * _visibleRows;
    // A short viewport (landscape phone) cannot fit the stacked layout, so the
    // controls move beside the wheels instead of above them.
    final isCompactHeight = media.size.height < 480;

    final wheels = SizedBox(
      height: wheelHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_groups.length > 1) ...[
            Expanded(
              flex: 2,
              child: _WheelColumn(
                key: const ValueKey('rail-picker-line-wheel'),
                controller: _lineController,
                itemExtent: _itemExtent,
                itemCount: _groups.length,
                selectedIndex: _groupIndex,
                onSelectedItemChanged: (index) => _selectLine(index),
                labelBuilder: (index) => _groups[index].lineName,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            flex: 3,
            child: _WheelColumn(
              key: ValueKey(
                'rail-picker-station-wheel-$_stationWheelGeneration',
              ),
              controller: _stationController,
              itemExtent: _itemExtent,
              itemCount: _stations.length,
              selectedIndex: _stationIndex,
              onSelectedItemChanged: (index) {
                final stations = _stations;
                if (stations.isEmpty) {
                  return;
                }
                setState(
                  () => _stationIndex = index.clamp(0, stations.length - 1),
                );
              },
              labelBuilder: (index) => _stations[index].name,
              onItemTapped: (index) {
                if (index == _stationIndex) {
                  _confirm();
                } else if (_stationController.hasClients) {
                  _stationController.animateToItem(
                    index,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                  );
                }
              },
            ),
          ),
        ],
      ),
    );

    final controls = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('rail-picker-search'),
          controller: _searchController,
          onChanged: _onSearchChanged,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '搜尋車站名稱或代碼',
            prefixIcon: Icon(Icons.search_rounded),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        if (widget.onLocate != null && !_locationUnavailable) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey('rail-picker-use-location'),
            onPressed: _locating ? null : _useCurrentLocation,
            icon: _locating
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded),
            label: const Text('使用目前位置'),
          ),
        ],
        if (_message != null) ...[
          const SizedBox(height: 8),
          Text(
            _message!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );

    final actions = Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton(
            key: const ValueKey('rail-picker-confirm'),
            onPressed: _confirmEnabled ? _confirm : null,
            child: Text(
              _selected == null ? '選擇車站' : '選擇 ${_selected!.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + media.viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            if (isCompactHeight)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: controls),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: wheels),
                ],
              )
            else ...[
              controls,
              const SizedBox(height: 12),
              wheels,
            ],
            if (!_confirmEnabled && _selected != null) ...[
              const SizedBox(height: 8),
              Text(
                '這一站已經是另一端的車站',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 14),
            actions,
          ],
        ),
      ),
    );
  }
}

/// One themed wheel column.
///
/// Built on `ListWheelScrollView` rather than `CupertinoPicker`: the app uses
/// no Cupertino widgets anywhere, and the iOS magnifier/curvature would read as
/// foreign here. The scroll machinery is identical; only the selection band is
/// hand-drawn with Material 3 tokens.
class _WheelColumn extends StatelessWidget {
  const _WheelColumn({
    required this.controller,
    required this.itemExtent,
    required this.itemCount,
    required this.selectedIndex,
    required this.onSelectedItemChanged,
    required this.labelBuilder,
    this.onItemTapped,
    super.key,
  });

  final FixedExtentScrollController controller;
  final double itemExtent;
  final int itemCount;
  final int selectedIndex;
  final ValueChanged<int> onSelectedItemChanged;
  final String Function(int index) labelBuilder;
  final ValueChanged<int>? onItemTapped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (itemCount == 0) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Container(
                height: itemExtent,
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.symmetric(
                    horizontal: BorderSide(color: cs.outlineVariant),
                  ),
                ),
              ),
            ),
          ),
        ),
        ListWheelScrollView.useDelegate(
          controller: controller,
          itemExtent: itemExtent,
          physics: const FixedExtentScrollPhysics(),
          perspective: 0.003,
          diameterRatio: 1.8,
          onSelectedItemChanged: onSelectedItemChanged,
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: itemCount,
            // Returning null for an out-of-range index is the documented
            // contract for this delegate, and covers the frame between "list
            // shrank" and "controller reconciled".
            builder: (context, index) {
              if (index < 0 || index >= itemCount) {
                return null;
              }
              final isSelected = index == selectedIndex;
              final label = Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    labelBuilder(index),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: isSelected ? cs.onSurface : cs.onSurfaceVariant,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
              );
              if (onItemTapped == null) {
                return label;
              }
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onItemTapped!(index),
                child: label,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Tappable field that opens [showRailStationPicker].
///
/// Replaces the `Autocomplete<RailStation>` that the TRA and THSR dashboards
/// each carried a private copy of.
class RailStationField extends StatelessWidget {
  const RailStationField({
    required this.label,
    required this.station,
    required this.placeholder,
    required this.onTap,
    super.key,
  });

  final String label;
  final RailStation? station;
  final String placeholder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = station;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.train_rounded),
          suffixIcon: const Icon(Icons.expand_more_rounded),
          border: const OutlineInputBorder(),
        ),
        child: Text(
          selected == null ? placeholder : selected.name,
          style: theme.textTheme.titleMedium?.copyWith(
            color: selected == null
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onSurface,
            fontWeight: selected == null ? FontWeight.w400 : FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
