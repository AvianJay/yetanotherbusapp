import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/models.dart';
import 'package:taiwanbus_flutter/core/route_search_grouping.dart';

void main() {
  RouteSummary route(String provider, String name) => RouteSummary(
    sourceProvider: provider,
    hashMd5: '',
    routeKey: name.hashCode,
    routeId: '$provider-$name',
    routeName: name,
    officialRouteName: '',
    description: '',
    category: '',
    sequence: 0,
    rtrip: 0,
  );

  test('groups trunk routes with extensions in the same provider', () {
    final groups = groupRouteSearchResults(<RouteSummary>[
      route('taichung', '500'),
      route('taichung', '500延'),
      route('taichung', '500跳蛙'),
    ]);

    expect(groups, hasLength(1));
    expect(groups.single.trunkName, '500');
    expect(groups.single.routes.map((route) => route.routeName), [
      '500',
      '500延',
      '500跳蛙',
    ]);
  });

  test('keeps unrelated numbers and providers separate', () {
    final groups = groupRouteSearchResults(<RouteSummary>[
      route('taichung', '50'),
      route('taichung', '500'),
      route('taipei', '500延'),
    ]);

    expect(groups, hasLength(3));
    expect(groups.map((group) => group.trunkName), ['50', '500', '500']);
  });

  test('resolves the same family name for trunk and supported variants', () {
    expect(routeFamilyName('500'), '500');
    expect(routeFamilyName('500延'), '500');
    expect(routeFamilyName('500跳蛙'), '500');
    expect(routeFamilyName('500延跳蛙'), '500');
    expect(routeFamilyName('500區'), '500區');
  });
}
