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

    for (final prefix in const ['紅', '藍', '綠', '棕', '橘', '黃', '幹線']) {
      expect(
        find.byKey(ValueKey('route-keypad-prefix-$prefix')),
        findsOneWidget,
      );
    }
    for (var digit = 0; digit <= 9; digit += 1) {
      expect(find.byKey(ValueKey('route-keypad-digit-$digit')), findsOneWidget);
    }

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

  testWidgets('inserts at the caret and replaces selected text', (
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
    await tester.tap(find.byKey(const ValueKey('route-keypad-prefix-綠')));

    expect(controller.text, '紅綠2');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
    expect(changes, ['紅312', '紅綠2']);
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
