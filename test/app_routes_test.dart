import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/app_launch_service.dart';
import 'package:taiwanbus_flutter/core/app_routes.dart';
import 'package:taiwanbus_flutter/core/models.dart';

void main() {
  test('parseAppRoute recognizes feedback route', () {
    final intent = parseAppRoute('/feedback');

    expect(intent.kind, AppRouteKind.feedback);
    expect(intent.location, AppRoutes.feedback);
  });

  test('normalize maps feedback aliases to the canonical route', () {
    expect(AppRoutes.normalize('feedback'), AppRoutes.feedback);
    expect(AppRoutes.normalize('feedbacks'), AppRoutes.feedback);
  });

  test('parseAppRoute recognizes announcement detail route', () {
    final intent = parseAppRoute('/announcement/test-announcement');

    expect(intent.kind, AppRouteKind.announcementDetail);
    expect(intent.announcementId, 'test-announcement');
    expect(
      intent.location,
      AppRoutes.normalize(
        AppRoutes.announcementDetailPath('test-announcement'),
      ),
    );
  });

  test('route detail routes preserve routeId for direct opens', () {
    final location = AppRoutes.routeDetailPath(
      provider: BusProvider.tpe,
      routeKey: 123456,
      routeId: 'TPE12345',
      pathId: 1,
      stopId: 2,
    );
    final intent = parseAppRoute(location);

    expect(intent.kind, AppRouteKind.routeDetail);
    expect(intent.provider, BusProvider.tpe);
    expect(intent.routeKey, 123456);
    expect(intent.routeId, 'TPE12345');
    expect(intent.pathId, 1);
    expect(intent.stopId, 2);
  });

  test('normalize accepts supported absolute internal route URLs', () {
    final location = AppRoutes.normalize(
      'https://busapp.avianjay.sbs/route/tpe/123456?routeId=TPE12345',
    );
    final intent = parseAppRoute(location);

    expect(location, '/route/tpe/123456?routeId=TPE12345');
    expect(intent.kind, AppRouteKind.routeDetail);
    expect(intent.routeId, 'TPE12345');
  });

  test('station detail routes preserve provider and station identity', () {
    final location = AppRoutes.stationDetailPath(
      provider: BusProvider.tpe,
      stationId: 'TPE-STATION/01',
    );
    final intent = parseAppRoute(location);

    expect(intent.kind, AppRouteKind.stationDetail);
    expect(intent.provider, BusProvider.tpe);
    expect(intent.stationId, 'TPE-STATION/01');
  });

  test('native station launch payload preserves station identity', () {
    final action = AppLaunchAction.fromMap({
      'target': 'station_detail',
      'provider': 'tpe',
      'stationId': 'TPE-STATION-1',
    });

    expect(action.target, AppLaunchTarget.stationDetail);
    expect(action.provider, BusProvider.tpe);
    expect(action.stationId, 'TPE-STATION-1');
    expect(action.routeKey, isNull);
    expect(action.stopId, isNull);
  });
}
