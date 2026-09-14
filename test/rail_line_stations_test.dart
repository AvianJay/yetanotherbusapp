import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/rail_line_stations.dart';
import 'package:taiwanbus_flutter/core/transit_repository.dart';

RailStation _station(String id, String name, {String nameEn = ''}) =>
    RailStation(
      stationId: id,
      name: name,
      nameEn: nameEn,
      stationClass: '',
      lat: 0,
      lon: 0,
    );

RailStationOfLine _line(
  String lineId,
  String lineName,
  List<(String, int)> stops,
) => RailStationOfLine(
  lineId: lineId,
  lineName: lineName,
  stations: [
    for (final stop in stops)
      RailLineStop(stationId: stop.$1, name: '', sequence: stop.$2),
  ],
);

void main() {
  // Shaped after the real feed: 竹南 and 彰化 sit on both 西部幹線 and 海線.
  final stations = [
    _station('1250', '竹南', nameEn: 'Zhunan'),
    _station('1260', '造橋'),
    _station('3350', '成功'),
    _station('3360', '彰化', nameEn: 'Changhua'),
    _station('2260', '追分'),
    _station('1998', '樹林調車場'),
  ];
  final lines = [
    _line('WL', '西部幹線', [('1250', 0), ('1260', 1), ('3350', 2), ('3360', 3)]),
    _line('WL-C', '海線', [('1250', 0), ('2260', 1), ('3360', 2)]),
  ];

  group('buildRailPickerGroups', () {
    test('keeps a shared station on every line it belongs to', () {
      final groups = buildRailPickerGroups(
        stations: stations,
        lines: lines,
      );

      final west = groups.firstWhere((g) => g.lineId == 'WL');
      final coast = groups.firstWhere((g) => g.lineId == 'WL-C');
      expect(west.indexOfStation('1250'), 0);
      expect(coast.indexOfStation('1250'), 0);
      expect(west.indexOfStation('3360'), 3);
      expect(coast.indexOfStation('3360'), 2);
    });

    test('orders stations by sequence, not by feed order', () {
      final scrambled = [
        _line('WL', '西部幹線', [('3360', 3), ('1250', 0), ('1260', 1)]),
      ];
      final groups = buildRailPickerGroups(
        stations: stations,
        lines: scrambled,
      );

      expect(
        groups.firstWhere((g) => g.lineId == 'WL').stations.map(
          (s) => s.stationId,
        ),
        ['1250', '1260', '3360'],
      );
    });

    test('sweeps stations no line claimed into a trailing group', () {
      final groups = buildRailPickerGroups(
        stations: stations,
        lines: lines,
      );

      expect(groups.last.lineName, kRailOtherLineName);
      expect(groups.last.stations.single.stationId, '1998');
    });

    test('omits the trailing group when every station is claimed', () {
      final groups = buildRailPickerGroups(
        stations: stations.where((s) => s.stationId != '1998').toList(),
        lines: lines,
      );

      expect(groups.map((g) => g.lineName), isNot(contains(kRailOtherLineName)));
    });

    test('falls back to one id-ordered group when the server has no lines', () {
      // This is the older-server path: the endpoint 404s, the repository hands
      // back an empty list, and the picker must still be usable.
      final groups = buildRailPickerGroups(
        stations: stations,
        lines: const [],
      );

      expect(groups, hasLength(1));
      expect(groups.single.lineName, kRailAllStationsLineName);
      expect(
        groups.single.stations.map((s) => s.stationId),
        ['1250', '1260', '1998', '2260', '3350', '3360'],
      );
    });

    test('ignores line entries referencing unknown stations', () {
      final groups = buildRailPickerGroups(
        stations: stations,
        lines: [
          _line('WL', '西部幹線', [('1250', 0), ('9999', 1)]),
        ],
      );

      expect(
        groups.first.stations.map((s) => s.stationId),
        ['1250'],
      );
    });

    test('returns nothing when there are no stations at all', () {
      expect(
        buildRailPickerGroups(stations: const [], lines: lines),
        isEmpty,
      );
    });
  });

  group('locateStationInGroups', () {
    final groups = buildRailPickerGroups(stations: stations, lines: lines);

    test('prefers the line already on screen for a shared station', () {
      final coastIndex = groups.indexWhere((g) => g.lineId == 'WL-C');
      final at = locateStationInGroups(
        groups,
        '1250',
        preferredGroup: coastIndex,
      );

      expect(at.group, coastIndex);
      expect(at.station, 0);
    });

    test('falls back to the first line carrying the station', () {
      final at = locateStationInGroups(groups, '2260');
      expect(groups[at.group].lineId, 'WL-C');
      expect(groups[at.group].stations[at.station].stationId, '2260');
    });

    test('lands on the top of the first group for unknown input', () {
      expect(locateStationInGroups(groups, null), (group: 0, station: 0));
      expect(locateStationInGroups(groups, '0000'), (group: 0, station: 0));
    });
  });

  group('findStationInGroups', () {
    final groups = buildRailPickerGroups(stations: stations, lines: lines);

    test('matches by Chinese name', () {
      final hit = findStationInGroups(groups, '彰化')!;
      expect(groups[hit.group].stations[hit.station].stationId, '3360');
    });

    test('matches by English name, case-insensitively', () {
      final hit = findStationInGroups(groups, 'zhun')!;
      expect(groups[hit.group].stations[hit.station].stationId, '1250');
    });

    test('matches by station id', () {
      final hit = findStationInGroups(groups, '2260')!;
      expect(groups[hit.group].stations[hit.station].stationId, '2260');
    });

    test('returns null when nothing matches', () {
      expect(findStationInGroups(groups, '沒有這站'), isNull);
      expect(findStationInGroups(groups, '   '), isNull);
    });

    test('prefers a prefix match over a substring match', () {
      final withSubstring = buildRailPickerGroups(
        stations: [_station('9001', '新竹南'), _station('9002', '竹南')],
        lines: const [],
      );
      final hit = findStationInGroups(withSubstring, '竹南')!;

      expect(withSubstring[hit.group].stations[hit.station].name, '竹南');
    });
  });
}
