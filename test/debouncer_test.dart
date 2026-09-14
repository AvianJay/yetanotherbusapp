import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/debouncer.dart';

void main() {
  test('runs only the most recently scheduled action', () async {
    final debouncer = Debouncer(const Duration(milliseconds: 50));
    var firstRuns = 0;
    var secondRuns = 0;

    debouncer.schedule(() => firstRuns++);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    debouncer.schedule(() => secondRuns++);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(firstRuns, 0);
    expect(secondRuns, 1);
    debouncer.dispose();
  });

  test('does not run pending work after disposal', () async {
    final debouncer = Debouncer(const Duration(milliseconds: 50));
    var runs = 0;

    debouncer.schedule(() => runs++);
    debouncer.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(runs, 0);
  });
}
