import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/models.dart';
import 'package:taiwanbus_flutter/core/stop_route_merge.dart';

StopRouteSearchResult _result(
  String routeId, {
  int pathId = 0,
  required int stopId,
  int? sec,
}) {
  return StopRouteSearchResult(
    route: RouteSummary(
      sourceProvider: 'txg',
      hashMd5: '',
      routeKey: routeId.hashCode,
      routeId: routeId,
      routeName: routeId,
      officialRouteName: routeId,
      description: '',
      category: '',
      sequence: 0,
      rtrip: 0,
    ),
    matchedStop: StopInfo(
      routeKey: routeId.hashCode,
      pathId: pathId,
      stopId: stopId,
      rawStopId: '$stopId',
      stopName: '捷運南屯站(文心路)',
      sequence: 1,
      lon: 0,
      lat: 0,
      sec: sec,
    ),
  );
}

void main() {
  test('merges disjoint passby and local results without duplicates', () {
    final merged = mergeStopRouteResults(
      passby: [_result('TXG4030', pathId: 1, stopId: 21746, sec: 120)],
      local: [
        _result('TXG73', stopId: 21884),
        _result('TXG3020', pathId: 1, stopId: 24080),
      ],
    );

    expect(
      merged.results.map((result) => result.route.routeId),
      containsAll(<String>['TXG4030', 'TXG73', 'TXG3020']),
    );
    expect(merged.results, hasLength(3));
    expect(merged.passbyKeys, <String>{'TXG4030:1'});
  });

  test('passby wins over local for the same route and path', () {
    // The server stamps the requested stop id (21746) on every route it
    // returns, while the local lookup carries the route's own id — so the same
    // entry legitimately arrives with two different stop ids.
    final merged = mergeStopRouteResults(
      passby: [_result('TXG4030', pathId: 1, stopId: 21746, sec: 120)],
      local: [_result('TXG4030', pathId: 1, stopId: 99999)],
    );

    expect(merged.results, hasLength(1));
    expect(merged.results.single.matchedStop.stopId, 21746);
    expect(merged.results.single.matchedStop.sec, 120);
    expect(merged.passbyKeys, contains('TXG4030:1'));
  });

  test('keeps both paths of one route and marks only the passby path', () {
    final merged = mergeStopRouteResults(
      passby: [_result('TXG4030', pathId: 1, stopId: 21746, sec: 120)],
      local: [_result('TXG4030', stopId: 21826)],
    );

    expect(merged.results, hasLength(2));
    expect(
      merged.results.map((result) => result.matchedStop.pathId),
      containsAll(<int>[0, 1]),
    );
    expect(merged.passbyKeys, <String>{'TXG4030:1'});
  });

  test('dedupes route ids that differ only by surrounding whitespace', () {
    final merged = mergeStopRouteResults(
      passby: [_result('TXG4030', stopId: 21746, sec: 60)],
      local: [_result(' TXG4030 ', stopId: 21826)],
    );

    expect(merged.results, hasLength(1));
    expect(merged.results.single.matchedStop.sec, 60);
  });

  test('passes local results through when passby is empty', () {
    final merged = mergeStopRouteResults(
      passby: const <StopRouteSearchResult>[],
      local: [
        _result('TXG73', stopId: 21884),
        _result('TXG365', stopId: 24127),
      ],
    );

    expect(merged.results, hasLength(2));
    expect(merged.passbyKeys, isEmpty);
  });
}
