import 'dart:async';

/// Defers work until calls have stopped for [delay].
class Debouncer {
  Debouncer(this.delay);

  final Duration delay;
  Timer? _timer;

  void schedule(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      action();
    });
  }

  void dispose() => _timer?.cancel();
}
