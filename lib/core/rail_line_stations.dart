import 'transit_repository.dart';

/// Label for the group holding stations no line claimed (depots, sidings).
const kRailOtherLineName = '其他';

/// Label used when the server gave us no line data at all.
const kRailAllStationsLineName = '全部車站';

/// One column-1 entry in the station picker: a line and its stations in
/// running order.
class RailPickerLine {
  const RailPickerLine({
    required this.lineId,
    required this.lineName,
    required this.stations,
  });

  final String lineId;
  final String lineName;
  final List<RailStation> stations;

  int indexOfStation(String stationId) {
    for (var i = 0; i < stations.length; i++) {
      if (stations[i].stationId == stationId) {
        return i;
      }
    }
    return -1;
  }
}

/// Groups [stations] by line for the picker wheel.
///
/// Stations are looked up from [stations] by id rather than trusting the names
/// inside [lines], because `/tra/station-of-line` carries only a bare Chinese
/// name and no English name or coordinates — the full record lives in
/// `/tra/stations`.
///
/// A station that sits on two lines (山線/海線 share 竹南 and 彰化; every branch
/// shares its junction with the trunk) appears under **both**, which is what a
/// user scrolling a line expects to see.
///
/// When [lines] is empty — an older server without the endpoint — everything
/// collapses into a single [kRailAllStationsLineName] group ordered by station
/// id, which for TRA runs roughly north-to-south along the trunk. Search and
/// "nearest station" keep working; only the line column is lost.
List<RailPickerLine> buildRailPickerGroups({
  required List<RailStation> stations,
  required List<RailStationOfLine> lines,
}) {
  if (stations.isEmpty) {
    return const [];
  }

  final byId = <String, RailStation>{
    for (final station in stations) station.stationId: station,
  };

  if (lines.isEmpty) {
    return [
      RailPickerLine(
        lineId: '',
        lineName: kRailAllStationsLineName,
        stations: _sortedById(stations),
      ),
    ];
  }

  final groups = <RailPickerLine>[];
  final claimed = <String>{};

  for (final line in lines) {
    final ordered = [...line.stations]
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    final resolved = <RailStation>[];
    for (final stop in ordered) {
      final station = byId[stop.stationId];
      if (station == null) {
        continue;
      }
      resolved.add(station);
      claimed.add(station.stationId);
    }
    if (resolved.isEmpty) {
      continue;
    }
    groups.add(
      RailPickerLine(
        lineId: line.lineId,
        lineName: line.lineName.isEmpty ? line.lineId : line.lineName,
        stations: resolved,
      ),
    );
  }

  if (groups.isEmpty) {
    return [
      RailPickerLine(
        lineId: '',
        lineName: kRailAllStationsLineName,
        stations: _sortedById(stations),
      ),
    ];
  }

  final leftovers = stations
      .where((station) => !claimed.contains(station.stationId))
      .toList(growable: false);
  if (leftovers.isNotEmpty) {
    groups.add(
      RailPickerLine(
        lineId: '',
        lineName: kRailOtherLineName,
        stations: _sortedById(leftovers),
      ),
    );
  }

  return groups;
}

/// First group/station position matching [stationId], or `(0, 0)` if absent.
({int group, int station}) locateStationInGroups(
  List<RailPickerLine> groups,
  String? stationId, {
  int preferredGroup = 0,
}) {
  if (stationId == null || stationId.isEmpty || groups.isEmpty) {
    return (group: 0, station: 0);
  }
  // A station on several lines should stay on the line already shown.
  if (preferredGroup >= 0 && preferredGroup < groups.length) {
    final index = groups[preferredGroup].indexOfStation(stationId);
    if (index >= 0) {
      return (group: preferredGroup, station: index);
    }
  }
  for (var g = 0; g < groups.length; g++) {
    final index = groups[g].indexOfStation(stationId);
    if (index >= 0) {
      return (group: g, station: index);
    }
  }
  return (group: 0, station: 0);
}

/// First station matching [query] by name, English name, or station id.
/// Prefix matches beat substring matches so typing 「臺北」 lands on 臺北, not
/// 新臺北-something.
({int group, int station})? findStationInGroups(
  List<RailPickerLine> groups,
  String query,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return null;
  }
  ({int group, int station})? substringHit;
  for (var g = 0; g < groups.length; g++) {
    final stations = groups[g].stations;
    for (var s = 0; s < stations.length; s++) {
      final station = stations[s];
      final fields = [
        station.name.toLowerCase(),
        station.nameEn.toLowerCase(),
        station.stationId.toLowerCase(),
      ];
      if (fields.any((field) => field.startsWith(needle))) {
        return (group: g, station: s);
      }
      if (substringHit == null &&
          fields.any((field) => field.contains(needle))) {
        substringHit = (group: g, station: s);
      }
    }
  }
  return substringHit;
}

List<RailStation> _sortedById(List<RailStation> stations) {
  final sorted = [...stations]
    ..sort((a, b) => a.stationId.compareTo(b.stationId));
  return sorted;
}
