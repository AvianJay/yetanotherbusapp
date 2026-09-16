import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/models.dart';
import 'package:taiwanbus_flutter/core/transfer_options.dart';

void main() {
  NearbyStopResult nearby({
    required String routeName,
    required String stopName,
    required double lat,
    required double lon,
    required double distanceMeters,
  }) {
    return NearbyStopResult(
      route: RouteSummary(
        sourceProvider: 'txg',
        hashMd5: '',
        routeKey: routeName.hashCode,
        routeId: routeName,
        routeName: routeName,
        officialRouteName: '',
        description: '',
        category: '',
        sequence: 0,
        rtrip: 0,
      ),
      stop: StopInfo(
        routeKey: routeName.hashCode,
        pathId: 0,
        stopId: routeName.hashCode,
        stopName: stopName,
        sequence: 1,
        lat: lat,
        lon: lon,
      ),
      distanceMeters: distanceMeters,
    );
  }

  test('groups routes at the same nearby transfer stop', () {
    final groups = groupNearbyTransferStops(<NearbyStopResult>[
      nearby(
        routeName: '500',
        stopName: '捷運南屯站',
        lat: 24.12341,
        lon: 120.54321,
        distanceMeters: 37,
      ),
      nearby(
        routeName: '73',
        stopName: '捷運南屯站',
        lat: 24.12344,
        lon: 120.54324,
        distanceMeters: 39,
      ),
      nearby(
        routeName: '99',
        stopName: '文心森林公園',
        lat: 24.124,
        lon: 120.544,
        distanceMeters: 210,
      ),
    ]);

    expect(groups, hasLength(2));
    expect(groups.first.stopName, '捷運南屯站');
    expect(groups.first.distanceMeters, 37);
    expect(groups.first.routes.map((result) => result.route.routeName), [
      '500',
      '73',
    ]);
  });
}
