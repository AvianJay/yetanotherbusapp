import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/account_sync_models.dart';
import 'package:taiwanbus_flutter/core/models.dart';

void main() {
  test('eta presentation keeps seconds when enabled', () {
    final stop = StopInfo(
      routeKey: 1,
      pathId: 0,
      stopId: 10,
      stopName: 'Main Station',
      sequence: 1,
      lon: 121.5,
      lat: 25.0,
      sec: 125,
    );

    final eta = buildEtaPresentation(stop, alwaysShowSeconds: true);

    expect(eta.text, '2分\n5秒');
  });

  test('eta presentation keeps floor minutes when seconds are hidden', () {
    final stop = StopInfo(
      routeKey: 1,
      pathId: 0,
      stopId: 10,
      stopName: 'Main Station',
      sequence: 1,
      lon: 121.5,
      lat: 25.0,
      sec: 61,
    );

    final eta = buildEtaPresentation(stop, alwaysShowSeconds: false);

    expect(eta.text, '1分');
  });

  test('effective stop eta subtracts elapsed time from realtime timestamp', () {
    final now = DateTime(2026, 6, 9, 8, 0);
    final stop = StopInfo(
      routeKey: 1,
      pathId: 0,
      stopId: 10,
      stopName: 'Main Station',
      sequence: 1,
      lon: 121.5,
      lat: 25.0,
      sec: 90,
      t: now.subtract(const Duration(seconds: 35)).toIso8601String(),
    );

    expect(effectiveStopEtaSeconds(stop, now: now), 55);
  });

  test('effective stop eta ignores stale timestamps', () {
    final now = DateTime(2026, 6, 9, 8, 0);
    final stop = StopInfo(
      routeKey: 1,
      pathId: 0,
      stopId: 10,
      stopName: 'Main Station',
      sequence: 1,
      lon: 121.5,
      lat: 25.0,
      sec: 90,
      t: now.subtract(const Duration(minutes: 20)).toIso8601String(),
    );

    expect(effectiveStopEtaSeconds(stop, now: now), 90);
  });

  test('vehicle eta lookup normalizes plate ids', () {
    final stop = StopInfo(
      routeKey: 1,
      pathId: 0,
      stopId: 10,
      stopName: 'Main Station',
      sequence: 1,
      lon: 121.5,
      lat: 25.0,
      etas: const [
        StopEta(sec: 60, vehicleId: 'EAL-5959'),
        StopEta(sec: 180, vehicleId: 'abc 1234'),
      ],
    );

    expect(stopEtaForVehicle(stop, ' eal-5959 ')?.sec, 60);
    expect(stopEtaForVehicle(stop, 'ABC1234')?.sec, 180);
  });

  test('vehicle eta uses matching bus instead of stop summary', () {
    final now = DateTime(2026, 6, 9, 8, 0);
    final stop = StopInfo(
      routeKey: 1,
      pathId: 0,
      stopId: 10,
      stopName: 'Destination',
      sequence: 1,
      lon: 121.5,
      lat: 25.0,
      sec: 90,
      t: now.subtract(const Duration(seconds: 30)).toIso8601String(),
      etas: const [
        StopEta(sec: 45, msg: '即將進站', vehicleId: 'wrong-bus'),
        StopEta(sec: 300, vehicleId: 'EAL-5959'),
      ],
    );

    expect(effectiveStopEtaSecondsForVehicle(stop, 'EAL-5959', now: now), 270);
    expect(effectiveStopEtaMessageForVehicle(stop, 'EAL-5959'), isNull);
    expect(effectiveStopEtaMessageForVehicle(stop, 'wrong-bus'), '即將進站');
  });

  test('backfill source no longer forces offline severity', () {
    expect(
      busOfflineSeverity(
        source: 'backfill_buses',
        updatedAt: DateTime(2026, 6, 23, 10, 0, 0),
        now: DateTime(2026, 6, 23, 10, 0, 5),
      ),
      0,
    );
  });

  test('fresh native bus stays near zero offline severity', () {
    expect(
      busOfflineSeverity(
        source: 'tdx',
        updatedAt: DateTime(2026, 6, 23, 10, 0, 0),
        now: DateTime(2026, 6, 23, 10, 0, 5),
      ),
      0,
    );
  });

  test('native bus stays non-offline even when timestamp is old', () {
    expect(
      busOfflineSeverity(
        source: 'tdx',
        updatedAt: DateTime(2026, 6, 23, 10, 0, 0),
        now: DateTime(2026, 6, 23, 10, 2, 40),
      ),
      0,
    );
  });

  test('formatEtaBadgeText wraps text by length', () {
    expect(formatEtaBadgeText(''), '');
    expect(formatEtaBadgeText('12:34'), '12:34');
    expect(formatEtaBadgeText('今日停駛'), '今日\n停駛');
    expect(formatEtaBadgeText('末班車已過'), '末班\n車已過');
    expect(formatEtaBadgeText('今日班次已過'), '今日班\n次已過');
  });

  test('distance formatter switches to km over one kilometer', () {
    expect(formatDistance(320), '320m');
    expect(formatDistance(1530), '1.5km');
  });

  test('app settings persist mobile map provider', () {
    final settings = AppSettings.defaults().copyWith(
      mobileMapProvider: MobileMapProvider.osm,
    );

    final restored = AppSettings.fromJson(settings.toJson());

    expect(restored.mobileMapProvider, MobileMapProvider.osm);
  });

  test('app settings persist wear os sync preferences', () {
    final settings = AppSettings.defaults().copyWith(
      wearSyncEnabled: true,
      wearSelectedFavoriteIds: const ['tpe:307:0:1001', 'nwt:920:1:2202'],
    );

    final restored = AppSettings.fromJson(settings.toJson());

    expect(restored.wearSyncEnabled, isTrue);
    expect(restored.wearSelectedFavoriteIds, const [
      'tpe:307:0:1001',
      'nwt:920:1:2202',
    ]);
  });

  test('app settings persist read route alerts', () {
    final settings = AppSettings.defaults().copyWith(
      readRouteAlerts: const [
        ReadRouteAlert(routeId: 'TPE123', alertId: 'alert-a'),
        ReadRouteAlert(routeId: 'TPE123', alertId: 'alert-b'),
      ],
    );

    final restored = AppSettings.fromJson(settings.toJson());

    expect(restored.readRouteAlerts, const [
      ReadRouteAlert(routeId: 'TPE123', alertId: 'alert-a'),
      ReadRouteAlert(routeId: 'TPE123', alertId: 'alert-b'),
    ]);
  });

  test('favorite usage profile prunes entries older than seven days', () {
    final now = DateTime(2026, 4, 10, 18, 10);
    final profile = FavoriteUsageProfile(
      provider: BusProvider.nwt,
      routeKey: 12,
      pathId: 1,
      stopId: 1001,
      selectionTimestampsMs: <int>[
        now.subtract(const Duration(days: 8)).millisecondsSinceEpoch,
        now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
      ],
    );

    final updated = profile.recordSelection(now);

    expect(updated.totalSelectionsAt(now: now), 2);
    expect(updated.selectionCountAtHour(18, now: now), 2);
  });

  test('account sync local state preserves namespace metadata', () {
    final state = AccountSyncLocalState.empty()
        .copyWith(syncEnabled: true)
        .copyWithNamespace(
          AccountSyncNamespace.preferences,
          const AccountSyncNamespaceLocalState(
            lastSuccessfulSyncAtMs: 1716000000000,
            lastSyncedLocalModifiedAtMs: 1716000000000,
            lastSyncedServerRevision: 4,
            lastSyncedServerEtag: '"etag"',
            lastSyncedServerUpdatedAt: '2026-05-21T10:00:00Z',
            preservedPayload: {
              'appearance': {'themeMode': 'dark'},
            },
          ),
        );

    final restored = AccountSyncLocalState.fromJson(state.toJson());

    expect(restored.syncEnabled, isTrue);
    expect(restored.preferences.lastSyncedServerRevision, 4);
    expect(
      restored.preferences.preservedPayload?['appearance']['themeMode'],
      'dark',
    );
  });

  test('account sync namespace status detects conflicts', () {
    final status = AccountSyncNamespaceStatus(
      namespace: AccountSyncNamespace.favorites,
      localState: const AccountSyncNamespaceLocalState(
        lastSyncedLocalModifiedAtMs: 100,
        lastSyncedServerRevision: 1,
      ),
      serverDocument: AccountSyncDocument(
        namespace: AccountSyncNamespace.favorites,
        hasData: true,
        schemaVersion: 1,
        revision: 2,
        etag: '"etag"',
        updatedAt: DateTime(2026, 5, 21, 9, 0),
        lastSyncedAt: DateTime(2026, 5, 21, 9, 1),
        lastClientModifiedAt: DateTime(2026, 5, 21, 8, 59),
        payloadSizeBytes: 64,
        payload: const {'groups': {}},
      ),
      localModifiedAt: DateTime.fromMillisecondsSinceEpoch(200),
    );

    expect(status.health, AccountSyncHealth.conflict);
    expect(status.localChanges, isTrue);
    expect(status.cloudChanges, isTrue);
  });
}
