import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/widgets/route_search_keypad.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders every route prefix, digit, and action', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final changes = <String>[];
    var textInputRequests = 0;
    var collapseRequests = 0;

    await _pumpKeypad(
      tester,
      controller: controller,
      onChanged: changes.add,
      onRequestTextInput: () => textInputRequests += 1,
      onCollapse: () => collapseRequests += 1,
    );

    for (final prefix in const [
      '紅',
      '藍',
      '綠',
      '棕',
      '橘',
      '黃',
      '幹線',
      '先導',
      '市民',
      '跳蛙',
      'F',
      '內科',
      '南軟',
      '夜間',
      'R',
      '貓空',
      '小',
      '其他',
      'T',
    ]) {
      expect(
        find.byKey(ValueKey('route-keypad-prefix-$prefix')),
        findsOneWidget,
      );
    }
    for (var digit = 0; digit <= 9; digit += 1) {
      expect(find.byKey(ValueKey('route-keypad-digit-$digit')), findsOneWidget);
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('route-keypad-text')),
        matching: find.byIcon(Icons.keyboard_rounded),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('切換文字鍵盤'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('route-keypad-prefix-紅')));
    await tester.tap(find.byKey(const ValueKey('route-keypad-digit-1')));
    await tester.tap(find.byKey(const ValueKey('route-keypad-digit-2')));
    await tester.tap(find.byKey(const ValueKey('route-keypad-text')));
    await tester.tap(find.byKey(const ValueKey('route-keypad-collapse')));

    expect(controller.text, '紅12');
    expect(changes, ['紅', '紅1', '紅12']);
    expect(textInputRequests, 1);
    expect(collapseRequests, 1);
  });

  testWidgets('digits insert at the caret and replace selected text', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final changes = <String>[];

    await _pumpKeypad(tester, controller: controller, onChanged: changes.add);

    controller.value = const TextEditingValue(
      text: '紅12',
      selection: TextSelection.collapsed(offset: 1),
    );
    await tester.tap(find.byKey(const ValueKey('route-keypad-digit-3')));

    expect(controller.text, '紅312');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));

    controller.value = const TextEditingValue(
      text: '紅312',
      selection: TextSelection(baseOffset: 1, extentOffset: 3),
    );
    await tester.tap(find.byKey(const ValueKey('route-keypad-digit-4')));

    expect(controller.text, '紅42');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
    expect(changes, ['紅312', '紅42']);
  });

  testWidgets('route prefixes replace the existing leading prefix', (
    tester,
  ) async {
    final controller = TextEditingController(text: '12');
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 2);
    final changes = <String>[];

    await _pumpKeypad(tester, controller: controller, onChanged: changes.add);

    await tester.tap(find.byKey(const ValueKey('route-keypad-prefix-綠')));
    expect(controller.text, '綠12');
    expect(controller.selection, const TextSelection.collapsed(offset: 3));

    await tester.tap(find.byKey(const ValueKey('route-keypad-prefix-棕')));
    expect(controller.text, '棕12');

    final trunkPrefix = find.byKey(
      const ValueKey<String>('route-keypad-prefix-幹線'),
    );
    await tester.ensureVisible(trunkPrefix);
    await tester.pumpAndSettle();
    await tester.tap(trunkPrefix);
    expect(controller.text, '幹線');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));

    controller.value = const TextEditingValue(
      text: '綠棕12',
      selection: TextSelection.collapsed(offset: 4),
    );
    final redPrefix = find.byKey(
      const ValueKey<String>('route-keypad-prefix-紅'),
    );
    await tester.ensureVisible(redPrefix);
    await tester.pumpAndSettle();
    await tester.tap(redPrefix);

    expect(controller.text, '紅12');
    expect(controller.selection, const TextSelection.collapsed(offset: 3));
    expect(changes, ['綠12', '棕12', '幹線', '紅12']);
  });

  testWidgets('extended route prefixes replace the leading prefix', (
    tester,
  ) async {
    final controller = TextEditingController(text: '市民12');
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 4);
    final changes = <String>[];

    await _pumpKeypad(tester, controller: controller, onChanged: changes.add);

    final fPrefix = find.byKey(const ValueKey<String>('route-keypad-prefix-F'));
    await tester.ensureVisible(fPrefix);
    await tester.pumpAndSettle();
    await tester.tap(fPrefix);

    expect(controller.text, 'F12');
    expect(controller.selection, const TextSelection.collapsed(offset: 3));
    expect(changes, ['F12']);
  });

  testWidgets('suffix shortcut appends once at the end of the query', (
    tester,
  ) async {
    final controller = TextEditingController(text: '218');
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 1);
    final changes = <String>[];

    await _pumpKeypad(tester, controller: controller, onChanged: changes.add);

    final nightShortcut = find.byKey(
      const ValueKey<String>('route-keypad-prefix-夜間'),
    );
    await tester.ensureVisible(nightShortcut);
    await tester.pumpAndSettle();
    await tester.tap(nightShortcut);
    await tester.tap(nightShortcut);

    expect(controller.text, '218夜');
    expect(controller.selection, const TextSelection.collapsed(offset: 4));
    expect(changes, ['218夜']);
  });

  testWidgets('keyword and category shortcuts replace the whole query', (
    tester,
  ) async {
    final controller = TextEditingController(text: '123');
    addTearDown(controller.dispose);
    final changes = <String>[];

    await _pumpKeypad(tester, controller: controller, onChanged: changes.add);

    for (final entry in const <(String, String)>[
      ('先導', '先導'),
      ('跳蛙', '跳蛙'),
      ('幹線', '幹線'),
      ('其他', '特'),
    ]) {
      final shortcut = find.byKey(
        ValueKey<String>('route-keypad-prefix-${entry.$1}'),
      );
      await tester.ensureVisible(shortcut);
      await tester.pumpAndSettle();
      await tester.tap(shortcut);
      expect(controller.text, entry.$2);
      expect(
        controller.selection,
        TextSelection.collapsed(offset: entry.$2.length),
      );
    }

    expect(changes, ['先導', '跳蛙', '幹線', '特']);
  });

  testWidgets('backspace removes selections and one grapheme at a time', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final changes = <String>[];

    await _pumpKeypad(tester, controller: controller, onChanged: changes.add);

    const familyEmoji = '👨‍👩‍👧‍👦';
    controller.value = TextEditingValue(
      text: 'A$familyEmoji',
      selection: TextSelection.collapsed(offset: 'A$familyEmoji'.length),
    );
    await tester.tap(find.byKey(const ValueKey('route-keypad-backspace')));

    expect(controller.text, 'A');
    expect(controller.selection, const TextSelection.collapsed(offset: 1));

    controller.value = const TextEditingValue(
      text: '紅123',
      selection: TextSelection(baseOffset: 1, extentOffset: 3),
    );
    await tester.tap(find.byKey(const ValueKey('route-keypad-backspace')));

    expect(controller.text, '紅3');
    expect(controller.selection, const TextSelection.collapsed(offset: 1));
    expect(changes, ['A', '紅3']);
  });

  testWidgets('holding backspace keeps deleting until it is released', (
    tester,
  ) async {
    final controller = TextEditingController(text: '123456');
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 6);
    final changes = <String>[];

    await _pumpKeypad(tester, controller: controller, onChanged: changes.add);

    final backspace = find.byKey(
      const ValueKey<String>('route-keypad-backspace'),
    );
    final gesture = await tester.startGesture(tester.getCenter(backspace));
    await tester.pump(const Duration(milliseconds: 600));

    expect(controller.text.length, lessThan(6));
    final lengthAfterLongPress = controller.text.length;

    await tester.pump(const Duration(milliseconds: 240));
    expect(controller.text.length, lessThan(lengthAfterLongPress));
    expect(changes.length, greaterThan(1));

    await gesture.up();
    await tester.pump();
    final textAfterRelease = controller.text;
    await tester.pump(const Duration(milliseconds: 240));

    expect(controller.text, textAfterRelease);
  });

  testWidgets('all route shortcuts stay in one horizontally scrollable row', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await _pumpKeypad(
      tester,
      controller: controller,
      size: const Size(320, 568),
    );

    final firstPrefix = find.byKey(
      const ValueKey<String>('route-keypad-prefix-紅'),
    );
    final lastPrefix = find.byKey(
      const ValueKey<String>('route-keypad-prefix-T'),
    );
    expect(tester.getTopLeft(firstPrefix).dy, tester.getTopLeft(lastPrefix).dy);

    final beforeScroll = tester.getTopLeft(lastPrefix).dx;
    await tester.drag(
      find.byKey(const ValueKey<String>('route-keypad-prefix-scroll')),
      const Offset(-180, 0),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(lastPrefix).dx, lessThan(beforeScroll));
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits compact portrait and landscape viewports', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await _pumpKeypad(
      tester,
      controller: controller,
      size: const Size(320, 568),
      textScaler: const TextScaler.linear(1.3),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('route-keypad-prefix-幹線')))
          .height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('route-keypad-digit-1'))).width,
      greaterThanOrEqualTo(48),
    );

    await _setViewSize(tester, const Size(667, 375));
    await tester.pump();

    expect(tester.takeException(), isNull);
    final prefixTop = tester.getTopLeft(
      find.byKey(const ValueKey('route-keypad-prefix-紅')),
    );
    final numberTop = tester.getTopLeft(
      find.byKey(const ValueKey('route-keypad-digit-1')),
    );
    expect(prefixTop.dy, numberTop.dy);
  });
}

Future<void> _pumpKeypad(
  WidgetTester tester, {
  required TextEditingController controller,
  ValueChanged<String>? onChanged,
  VoidCallback? onRequestTextInput,
  VoidCallback? onCollapse,
  Size size = const Size(390, 844),
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await _setViewSize(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Scaffold(
        bottomNavigationBar: RouteSearchKeypad(
          controller: controller,
          onChanged: onChanged ?? (_) {},
          onRequestTextInput: onRequestTextInput ?? () {},
          onCollapse: onCollapse ?? () {},
        ),
      ),
    ),
  );
}

Future<void> _setViewSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}
