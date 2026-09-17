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
}
