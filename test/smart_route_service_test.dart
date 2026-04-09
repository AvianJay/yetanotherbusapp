import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/models.dart';
import 'package:taiwanbus_flutter/core/smart_route_service.dart';

void main() {
  test('recordOpen increments total and hourly counters', () {
    const profile = RouteUsageProfile(
      provider: BusProvider.nwt,
      routeKey: 12,
      routeName: '307',
      totalOpens: 2,
      lastOpenedAtMs: 0,
      hourlyOpens: <int, int>{7: 2},
    );

    final updated = profile.recordOpen(
      DateTime(2026, 4, 4, 7, 30),
      routeName: '307',
    );

    expect(updated.totalOpens, 3);
    expect(updated.countAtHour(7), 3);
    expect(updated.preferredHour, 7);
  });

  test('recordSelection increments selection counters', () {
    const profile = RouteUsageProfile(
      provider: BusProvider.nwt,
      routeKey: 12,
      routeName: '307',
      totalOpens: 0,
      lastOpenedAtMs: 0,
    );

    final updated = profile.recordSelection(
      DateTime(2026, 4, 4, 18, 10),
      routeName: '307',
    );

    expect(updated.totalSelections, 1);
    expect(updated.selectionCountAtHour(18), 1);
    expect(updated.preferredHour, 18);
  });

  test('chooseProfileForTime prefers the route used in this time window', () {
    const morningRoute = RouteUsageProfile(
      provider: BusProvider.nwt,
      routeKey: 101,
      routeName: '307',
      totalOpens: 8,
      lastOpenedAtMs: 1712000000000,
      hourlyOpens: <int, int>{7: 5, 8: 2},
    );
    const nightRoute = RouteUsageProfile(
      provider: BusProvider.nwt,
      routeKey: 102,
      routeName: '300',
      totalOpens: 20,
      lastOpenedAtMs: 1712000000000,
      hourlyOpens: <int, int>{21: 10},
    );

    final result = SmartRouteService.chooseProfileForTime(const [
      morningRoute,
      nightRoute,
    ], DateTime(2026, 4, 4, 7, 20));

    expect(result?.routeKey, 101);
  });

  test('chooseProfileForTime returns null outside learned hours', () {
    const morningRoute = RouteUsageProfile(
      provider: BusProvider.nwt,
      routeKey: 101,
      routeName: '307',
      totalOpens: 8,
      lastOpenedAtMs: 1712000000000,
      hourlyOpens: <int, int>{7: 5, 8: 2},
    );

    final result = SmartRouteService.chooseProfileForTime(const [
      morningRoute,
    ], DateTime(2026, 4, 4, 14, 00));

    expect(result, isNull);
  });

  test('chooseProfileForTime also uses selection history', () {
    const selectedRoute = RouteUsageProfile(
      provider: BusProvider.nwt,
      routeKey: 202,
      routeName: '綠3',
      totalOpens: 3,
      lastOpenedAtMs: 1712000000000,
      totalSelections: 4,
      lastSelectedAtMs: 1712000000000,
      hourlyOpens: <int, int>{18: 1, 17: 1, 19: 1},
      hourlySelections: <int, int>{18: 4},
    );
    const weakerRoute = RouteUsageProfile(
      provider: BusProvider.nwt,
      routeKey: 303,
      routeName: '綠5',
      totalOpens: 3,
      lastOpenedAtMs: 1712000000000,
      hourlyOpens: <int, int>{18: 2, 17: 1},
    );

    final result = SmartRouteService.chooseProfileForTime(const [
      selectedRoute,
      weakerRoute,
    ], DateTime(2026, 4, 4, 18, 15));

    expect(result?.routeKey, 202);
  });

  test('chooseProfileForTime requires enough actual opens', () {
    const notLearnedEnough = RouteUsageProfile(
      provider: BusProvider.nwt,
      routeKey: 88,
      routeName: '11',
      totalOpens: 1,
      lastOpenedAtMs: 1712000000000,
      totalSelections: 4,
      lastSelectedAtMs: 1712000000000,
      hourlyOpens: <int, int>{7: 1},
      hourlySelections: <int, int>{7: 4},
    );

    final result = SmartRouteService.chooseProfileForTime(const [
      notLearnedEnough,
    ], DateTime(2026, 4, 4, 7, 10));

    expect(result, isNull);
  });
}
