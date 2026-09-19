import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/models.dart';
import 'package:taiwanbus_flutter/core/route_family.dart';

void main() {
  test('resolves the same family name for trunk and supported variants', () {
    expect(routeFamilyName('500'), '500');
    expect(routeFamilyName('500延'), '500');
    expect(routeFamilyName('500跳蛙'), '500');
    expect(routeFamilyName('500延跳蛙'), '500');
    expect(routeFamilyName('500區'), '500區');
  });

  StopInfo stop({
    required String rawStopId,
    required String name,
    required double lat,
    required double lon,
  }) {
    return StopInfo(
      routeKey: 0,
      pathId: 0,
      stopId: rawStopId.hashCode,
      rawStopId: rawStopId,
      stopName: name,
      sequence: 0,
      lat: lat,
      lon: lon,
    );
  }

  test(
    'matches route-family stops with matching names and nearby coordinates',
    () {
      expect(
        routeFamilyStopsSharePhysicalSide(
          stop(
            rawStopId: '500-main',
            name: '捷運文心櫻花站',
            lat: 24.171000,
            lon: 120.653000,
          ),
          stop(
            rawStopId: '500-extension',
            name: '捷運文心櫻花站',
            lat: 24.171015,
            lon: 120.653015,
          ),
        ),
        isTrue,
      );
    },
  );

  test(
    'does not match route-family stops with different physical locations',
    () {
      expect(
        routeFamilyStopsSharePhysicalSide(
          stop(
            rawStopId: '500-main',
            name: '捷運文心櫻花站',
            lat: 24.171000,
            lon: 120.653000,
          ),
          stop(
            rawStopId: '500-extension',
            name: '捷運文心櫻花站',
            lat: 24.172000,
            lon: 120.654000,
          ),
        ),
        isFalse,
      );
    },
  );

  test('combines family live data into the selected route stop', () {
    final merged = mergeRouteFamilyStopLiveData(
      stop(
        rawStopId: '500-main',
        name: '捷運文心櫻花站',
        lat: 24.171000,
        lon: 120.653000,
      ).copyWith(
        sec: 240,
        buses: const [
          BusVehicle(
            id: 'KKA-0001',
            type: '0',
            note: '',
            full: false,
            carOnStop: false,
          ),
        ],
      ),
      [
        stop(
          rawStopId: '500-extension',
          name: '捷運文心櫻花站',
          lat: 24.171015,
          lon: 120.653015,
        ).copyWith(
          sec: 120,
          buses: const [
            BusVehicle(
              id: 'KKA-0002',
              type: '0',
              note: '',
              full: false,
              carOnStop: false,
            ),
          ],
        ),
      ],
    );

    expect(merged.sec, 120);
    expect(merged.buses.map((bus) => bus.id), ['KKA-0001', 'KKA-0002']);
  });

  test(
    'replaces an unavailable trunk ETA with a variant ETA at shared stops',
    () {
      RouteDetailData detail({
        required String routeId,
        required String routeName,
        required StopInfo stop,
      }) {
        return RouteDetailData(
          route: RouteSummary(
            sourceProvider: 'TXG',
            hashMd5: '',
            routeKey: routeId.hashCode,
            routeId: routeId,
            routeName: routeName,
            officialRouteName: routeName,
            description: '',
            category: '',
            sequence: 0,
            rtrip: 0,
          ),
          paths: const [PathInfo(routeKey: 0, pathId: 0, name: '臺中車站')],
          stopsByPath: {
            0: [stop],
          },
          hasLiveData: true,
        );
      }

      final sharedStop = stop(
        rawStopId: '8150',
        name: '邱厝里',
        lat: 24.156715,
        lon: 120.676500,
      );
      final merged = mergeRouteFamilyLiveData(
        detail(
          routeId: 'TXG5000',
          routeName: '500',
          stop: sharedStop.copyWith(msg: '尚未發車'),
        ),
        [
          detail(
            routeId: 'TXG5002',
            routeName: '500延',
            stop: sharedStop.copyWith(sec: 33),
          ),
        ],
      );

      final sharedLiveStop = merged.stopsByPath[0]!.single;
      expect(sharedLiveStop.sec, 33);
      expect(sharedLiveStop.msg, isNull);
      expect(merged.familyRouteIds, ['TXG5000', 'TXG5002']);
    },
  );
}
