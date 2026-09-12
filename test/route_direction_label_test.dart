import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/models.dart';
import 'package:taiwanbus_flutter/core/route_direction_label.dart';

NearbyStopResult _result({
  required String routeName,
  required String description,
  required int pathId,
  int stopId = 1,
}) {
  return NearbyStopResult(
    route: RouteSummary(
      sourceProvider: 'tpe',
      hashMd5: '',
      routeKey: routeName.hashCode,
      routeId: 'TPE$routeName',
      routeName: routeName,
      officialRouteName: routeName,
      description: description,
      category: '',
      sequence: pathId,
      rtrip: pathId,
    ),
    stop: StopInfo(
      routeKey: routeName.hashCode,
      pathId: pathId,
      stopId: stopId,
      rawStopId: '$stopId',
      stopName: '捷運南屯站(文心路)',
      sequence: 1,
      lon: 0,
      lat: 0,
    ),
    distanceMeters: 42,
  );
}

void main() {
  group('routeDirectionLabel', () {
    test('passes through a name that already carries the 往 prefix', () {
      expect(routeDirectionLabel(pathName: '往撫遠街', pathId: 0), '往撫遠街');
    });

    test('prepends 往 with a space when the prefix is missing', () {
      expect(routeDirectionLabel(pathName: '撫遠街', pathId: 0), '往 撫遠街');
    });

    test('trims surrounding whitespace', () {
      expect(routeDirectionLabel(pathName: '  台北車站  ', pathId: 0), '往 台北車站');
    });

    test('falls back to the direction ordinal for placeholder names', () {
      expect(routeDirectionLabel(pathName: 'Unknown', pathId: 0), '去程');
      expect(routeDirectionLabel(pathName: 'unknown', pathId: 1), '返程');
      expect(routeDirectionLabel(pathName: 'Path 0', pathId: 1), '返程');
      expect(routeDirectionLabel(pathName: 'PATH 1', pathId: 2), '方向 2');
    });

    test('falls back when the path name is just the route name', () {
      expect(
        routeDirectionLabel(pathName: '307', pathId: 1, routeName: '307'),
        '返程',
      );
      expect(
        routeDirectionLabel(pathName: '307', pathId: 1, routeName: ' 307 '),
        '返程',
      );
    });

    test('keeps a path name that merely resembles another route', () {
      expect(
        routeDirectionLabel(pathName: '撫遠街', pathId: 0, routeName: '307'),
        '往 撫遠街',
      );
    });

    test('returns empty when there is no name and no ordinal to fall back to', () {
      expect(routeDirectionLabel(pathName: '', pathId: null), '');
      expect(routeDirectionLabel(pathName: null, pathId: null), '');
    });
  });

  group('isMeaningfulPathName', () {
    test('rejects null, empty and placeholder names', () {
      expect(isMeaningfulPathName(null), isFalse);
      expect(isMeaningfulPathName('   '), isFalse);
      expect(isMeaningfulPathName('Unknown'), isFalse);
      expect(isMeaningfulPathName('path 1'), isFalse);
    });

    test('rejects a name identical to the route name', () {
      expect(isMeaningfulPathName('307', routeName: '307'), isFalse);
    });

    test('accepts a real destination', () {
      expect(isMeaningfulPathName('往南港'), isTrue);
    });
  });

  group('directionOrdinalLabel', () {
    test('maps TDX Direction values', () {
      expect(directionOrdinalLabel(0), '去程');
      expect(directionOrdinalLabel(1), '返程');
      expect(directionOrdinalLabel(3), '方向 3');
      expect(directionOrdinalLabel(null), '');
    });
  });

  group('labelNearbyRouteDirections', () {
    test('leaves distinct destinations alone', () {
      final rows = labelNearbyRouteDirections([
        _result(routeName: '307', description: '往撫遠街', pathId: 0),
        _result(routeName: '307', description: '往青年公園', pathId: 1),
      ]);

      expect(rows.map((row) => row.directionLabel), ['往撫遠街', '往青年公園']);
    });

    test('appends the ordinal when a circular route repeats its destination', () {
      final rows = labelNearbyRouteDirections([
        _result(routeName: '棕20', description: '往捷運麟光新村站', pathId: 0),
        _result(routeName: '棕20', description: '往捷運麟光新村站', pathId: 1),
      ]);

      expect(rows.map((row) => row.directionLabel), [
        '往捷運麟光新村站（去程）',
        '往捷運麟光新村站（返程）',
      ]);
    });

    test('does not double up when both rows already fell back to the ordinal', () {
      final rows = labelNearbyRouteDirections([
        _result(routeName: '88', description: '', pathId: 0),
        _result(routeName: '88', description: '', pathId: 1),
      ]);

      expect(rows.map((row) => row.directionLabel), ['去程', '返程']);
    });

    test('does not treat two different routes as a collision', () {
      final rows = labelNearbyRouteDirections([
        _result(routeName: '307', description: '往撫遠街', pathId: 0),
        _result(routeName: '藍7', description: '往撫遠街', pathId: 0),
      ]);

      expect(rows.map((row) => row.directionLabel), ['往撫遠街', '往撫遠街']);
    });

    test('preserves input order and identity', () {
      final input = [
        _result(routeName: '307', description: '往撫遠街', pathId: 0, stopId: 11),
        _result(routeName: '307', description: '往青年公園', pathId: 1, stopId: 22),
      ];

      final rows = labelNearbyRouteDirections(input);

      expect(rows, hasLength(input.length));
      expect(rows[0].result, same(input[0]));
      expect(rows[1].result, same(input[1]));
    });

    test('handles an empty group', () {
      expect(labelNearbyRouteDirections(const []), isEmpty);
    });
  });
}
