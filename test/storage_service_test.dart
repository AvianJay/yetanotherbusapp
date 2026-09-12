import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taiwanbus_flutter/core/storage_service.dart';

void main() {
  test('legacy migration removes only obsolete API cache data', () async {
    SharedPreferences.setMockInitialValues({
      'app_settings': '{"themeMode":"dark"}',
      'search_history': '[{"routeKey":100}]',
      'favorite_groups': '{"Home":[]}',
      'route_usage_profiles': '{"100":1}',
      'favorite_usage_profiles': '{"Home":1}',
      'tracked_buses': '["legacy-cache"]',
    });
    final storage = StorageService();

    await storage.migrateLegacyApiDataIfNeeded();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_settings'), '{"themeMode":"dark"}');
    expect(prefs.getString('search_history'), '[{"routeKey":100}]');
    expect(prefs.getString('favorite_groups'), '{"Home":[]}');
    expect(prefs.getString('route_usage_profiles'), '{"100":1}');
    expect(prefs.getString('favorite_usage_profiles'), '{"Home":1}');
    expect(prefs.containsKey('tracked_buses'), isFalse);
    expect(prefs.getInt('storage_schema_version'), 3);
  });
}
