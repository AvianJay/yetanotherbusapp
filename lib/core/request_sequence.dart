/// Tracks asynchronous work so only the latest request can update a screen.
class RequestSequence {
  var _current = 0;

  int next() => ++_current;

  bool isCurrent(int request) => request == _current;
}
