import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/rail_line_stations.dart';
import 'package:taiwanbus_flutter/core/transit_repository.dart';
import 'package:taiwanbus_flutter/core/user_location.dart';
import 'package:taiwanbus_flutter/widgets/rail_station_picker.dart';

RailStation _station(String id, String name, {String nameEn = ''}) =>
    RailStation(
      stationId: id,
      name: name,
      nameEn: nameEn,
      stationClass: '',
      lat: 0,
      lon: 0,
    );

/// A long trunk line plus a two-station branch — the shape that stresses
/// switching between wildly different column lengths.
List<RailPickerLine> _groups() => [
  RailPickerLine(
    lineId: 'WL',
    lineName: '西部幹線',
    stations: [
      for (var i = 0; i < 40; i++)
        _station('1${i.toString().padLeft(3, '0')}', '西$i'),
    ],
  ),
  RailPickerLine(
    lineId: 'CZ',
    lineName: '成追線',
    stations: [_station('3350', '成功'), _station('2260', '追分')],
  ),
];

Future<RailStation?> _pumpPicker(
  WidgetTester tester, {
  List<RailPickerLine>? groups,
  RailStation? initial,
  RailStation? excluded,
  Future<NearestRailStation?> Function()? onLocate,
}) async {
  RailStation? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showRailStationPicker(
                  context: context,
                  title: '選擇出發站',
                  groups: groups ?? _groups(),
                  initial: initial,
                  excluded: excluded,
                  onLocate: onLocate,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('opens on the initial station', (tester) async {
    await _pumpPicker(tester, initial: _station('1005', '西5'));

    expect(find.text('選擇 西5'), findsOneWidget);
  });

  testWidgets('typing jumps the wheel to the matching station', (tester) async {
    await _pumpPicker(tester, initial: _station('1000', '西0'));

    await tester.enterText(find.byKey(const ValueKey('rail-picker-search')), '西12');
    // The search is debounced at 200ms.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.text('選擇 西12'), findsOneWidget);
  });

  testWidgets('an unmatched search leaves the wheel alone and explains', (
    tester,
  ) async {
    await _pumpPicker(tester, initial: _station('1005', '西5'));

    await tester.enterText(
      find.byKey(const ValueKey('rail-picker-search')),
      '沒有這站',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.text('找不到符合的車站'), findsOneWidget);
    expect(find.text('選擇 西5'), findsOneWidget);
  });

  testWidgets(
    'switching from a long line to a two-station branch stays in range',
    (tester) async {
      // Parked at index 30 of a 40-station line, then switched to a 2-station
      // line. Flutter's ScrollPosition does re-clamp the offset on layout, so
      // this is not the crash it looks like — but _stationIndex must follow the
      // shorter list too, or the confirm button would name a station that is no
      // longer on the wheel.
      await _pumpPicker(tester, initial: _station('1030', '西30'));
      expect(find.text('選擇 西30'), findsOneWidget);

      await tester.drag(
        find.byKey(const ValueKey('rail-picker-line-wheel')),
        const Offset(0, -60),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Fell back to the top of the branch line, since 西30 is not on it.
      expect(find.text('選擇 成功'), findsOneWidget);
      // The wheel itself must have moved, not just the label: if the viewport
      // were left parked at item 30 of the old 40-station line, neither branch
      // station would be rendered at all.
      expect(find.text('成功'), findsWidgets);
      expect(find.text('追分'), findsWidgets);
    },
  );

  testWidgets('searching lands on a station that lives on another line', (
    tester,
  ) async {
    // The cross-group path: the station wheel is rebuilt for the new line and
    // has to land on a specific index in it.
    await _pumpPicker(tester, initial: _station('1030', '西30'));

    await tester.enterText(
      find.byKey(const ValueKey('rail-picker-search')),
      '成功',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 成功 is index 0 of the branch. A wheel left at its old offset would clamp
    // to the LAST item instead, so this distinguishes landing from clamping.
    expect(find.text('選擇 成功'), findsOneWidget);
  });

  testWidgets('a station on both lines survives a line switch', (tester) async {
    final shared = _station('3350', '成功');
    final groups = [
      RailPickerLine(
        lineId: 'WL',
        lineName: '西部幹線',
        stations: [_station('1000', '西0'), shared, _station('1002', '西2')],
      ),
      RailPickerLine(
        lineId: 'CZ',
        lineName: '成追線',
        stations: [shared, _station('2260', '追分')],
      ),
    ];
    await _pumpPicker(tester, groups: groups, initial: shared);

    await tester.drag(
      find.byKey(const ValueKey('rail-picker-line-wheel')),
      const Offset(0, -60),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('選擇 成功'), findsOneWidget);
  });

  testWidgets('confirming returns the centred station', (tester) async {
    RailStation? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked = await showRailStationPicker(
                    context: context,
                    title: '選擇出發站',
                    groups: _groups(),
                    initial: _station('1007', '西7'),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('rail-picker-confirm')));
    await tester.pumpAndSettle();

    expect(picked?.stationId, '1007');
  });

  testWidgets('the excluded station cannot be confirmed', (tester) async {
    await _pumpPicker(
      tester,
      initial: _station('1005', '西5'),
      excluded: _station('1005', '西5'),
    );

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('rail-picker-confirm')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('這一站已經是另一端的車站'), findsOneWidget);
  });

  testWidgets('the location button is hidden when no handler is given', (
    tester,
  ) async {
    await _pumpPicker(tester);

    expect(find.byKey(const ValueKey('rail-picker-use-location')), findsNothing);
  });

  testWidgets('locating moves the wheel and reports the distance', (
    tester,
  ) async {
    await _pumpPicker(
      tester,
      initial: _station('1000', '西0'),
      onLocate: () async => NearestRailStation(
        station: _station('1009', '西9'),
        distanceMeters: 350,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('rail-picker-use-location')));
    await tester.pumpAndSettle();

    expect(find.textContaining('最近的車站：西9'), findsOneWidget);
    // Deliberately does not auto-confirm — the sheet stays open.
    expect(find.text('選擇 西9'), findsOneWidget);
  });

  testWidgets('a denied permission replaces the button with its reason', (
    tester,
  ) async {
    await _pumpPicker(
      tester,
      initial: _station('1000', '西0'),
      onLocate: () async =>
          throw const LocationFailure('沒有取得定位權限。', deniedForever: true),
    );

    await tester.tap(find.byKey(const ValueKey('rail-picker-use-location')));
    await tester.pumpAndSettle();

    expect(find.text('沒有取得定位權限。'), findsOneWidget);
    expect(find.byKey(const ValueKey('rail-picker-use-location')), findsNothing);
  });
}
