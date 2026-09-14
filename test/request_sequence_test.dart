import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/request_sequence.dart';

void main() {
  test('only recognizes the latest request', () {
    final sequence = RequestSequence();

    final first = sequence.next();
    final second = sequence.next();

    expect(sequence.isCurrent(first), isFalse);
    expect(sequence.isCurrent(second), isTrue);
  });
}
