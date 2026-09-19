import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/transit_repository.dart';
import 'package:taiwanbus_flutter/widgets/rail_station_picker.dart';
import 'package:taiwanbus_flutter/widgets/transit_panels.dart';

Future<void> _pump(WidgetTester tester, Widget child, {Brightness? brightness}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B7285),
          brightness: brightness ?? Brightness.light,
        ),
      ),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('PastTrainsDisclosure', () {
    testWidgets('labels itself by state and reports taps', (tester) async {
      var toggles = 0;
      await _pump(
        tester,
        PastTrainsDisclosure(
          count: 43,
          expanded: false,
          onToggle: () => toggles++,
        ),
      );

      expect(find.text('顯示已開出的 43 班'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

      await tester.tap(find.byType(PastTrainsDisclosure));
      await tester.pump();
      expect(toggles, 1);
    });

    testWidgets('flips its label and chevron when expanded', (tester) async {
      await _pump(
        tester,
        PastTrainsDisclosure(count: 43, expanded: true, onToggle: () {}),
      );

      expect(find.text('收合已開出的 43 班'), findsOneWidget);
      expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
    });
  });

  group('RailStationField', () {
    const station = RailStation(
      stationId: '1000',
      name: '臺北',
      nameEn: 'Taipei',
      stationClass: '',
      lat: 0,
      lon: 0,
    );

    testWidgets('shows the placeholder when nothing is chosen', (tester) async {
      await _pump(
        tester,
        const RailStationField(
          label: '出發站',
          station: null,
          placeholder: '選擇出發站',
          onTap: null,
        ),
      );

      expect(find.text('選擇出發站'), findsOneWidget);
      expect(find.text('出發站'), findsOneWidget);
    });

    testWidgets('shows the chosen station and fires onTap', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        RailStationField(
          label: '出發站',
          station: station,
          placeholder: '選擇出發站',
          onTap: () => taps++,
        ),
      );

      expect(find.text('臺北'), findsOneWidget);
      await tester.tap(find.byType(RailStationField));
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('RailAlertCard', () {
    RailAlert alert(String title) => RailAlert(
      alertId: title,
      title: title,
      description: '',
      status: 0,
      publishTime: '',
      startTime: '',
      endTime: '',
    );

    testWidgets('caps how many alerts it lists', (tester) async {
      await _pump(
        tester,
        RailAlertCard(
          alerts: [alert('一'), alert('二'), alert('三'), alert('四')],
        ),
      );

      expect(find.text('營運公告'), findsOneWidget);
      expect(find.text('• 一'), findsOneWidget);
      expect(find.text('• 三'), findsOneWidget);
      expect(find.text('• 四'), findsNothing);
    });

    testWidgets('stays legible in dark mode', (tester) async {
      // The two private copies this replaced hard-coded orange.shade900 on
      // orange.shade50, which is near-invisible on the AMOLED dark surfaces.
      await _pump(
        tester,
        RailAlertCard(alerts: [alert('延誤')]),
        brightness: Brightness.dark,
      );

      final title = tester.widget<Text>(find.text('營運公告'));
      final lightness = HSLColor.fromColor(title.style!.color!).lightness;
      expect(lightness, greaterThan(0.5));
    });
  });

  group('TransitEmptyPanel', () {
    testWidgets('renders an optional action', (tester) async {
      await _pump(
        tester,
        TransitEmptyPanel(
          icon: Icons.train_rounded,
          label: '選好出發站和到達站。',
          action: FilledButton(onPressed: () {}, child: const Text('用目前位置')),
        ),
      );

      expect(find.text('選好出發站和到達站。'), findsOneWidget);
      expect(find.text('用目前位置'), findsOneWidget);
    });

    testWidgets('omits the action slot when none is given', (tester) async {
      await _pump(
        tester,
        const TransitEmptyPanel(icon: Icons.train_rounded, label: '沒有資料'),
      );

      expect(find.byType(FilledButton), findsNothing);
    });
  });
}
