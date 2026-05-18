import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/app_routes.dart';

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
}
