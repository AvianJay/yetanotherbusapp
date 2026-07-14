import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taiwanbus_flutter/core/account_sync_models.dart';
import 'package:taiwanbus_flutter/core/account_sync_service.dart';
import 'package:taiwanbus_flutter/core/app_analytics.dart';
import 'package:taiwanbus_flutter/core/app_build_info.dart';
import 'package:taiwanbus_flutter/core/app_controller.dart';
import 'package:taiwanbus_flutter/core/app_launch_service.dart';
import 'package:taiwanbus_flutter/core/app_update_installer.dart';
import 'package:taiwanbus_flutter/core/app_update_service.dart';
import 'package:taiwanbus_flutter/core/auth_service.dart';
import 'package:taiwanbus_flutter/core/bus_repository.dart';
import 'package:taiwanbus_flutter/core/models.dart';
import 'package:taiwanbus_flutter/core/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('account sync preserves a newly created empty favorite group', () async {
    final buildInfo = AppBuildInfo(
      version: '1.0.0',
      buildNumber: '1',
      gitSha: 'test',
      defaultUpdateChannel: AppUpdateChannel.release,
    );
    final storage = StorageService();
    await storage.saveAccountSyncLocalState(
      'test-account',
      const AccountSyncLocalState(
        syncEnabled: null,
        favorites: AccountSyncNamespaceLocalState(),
        preferences: AccountSyncNamespaceLocalState(
          lastSuccessfulSyncAtMs: 1,
          lastSyncedServerRevision: 1,
        ),
      ),
    );
    final syncService = _FakeAccountSyncService();
    final controller = AppController(
      repository: BusRepository(),
      storage: storage,
      analytics: await AppAnalytics.initialize(),
      buildInfo: buildInfo,
      appUpdateService: AppUpdateService(buildInfo: buildInfo),
      appUpdateInstaller: createAppUpdateInstaller(),
      authService: _FakeAuthService(),
      accountSyncService: syncService,
    );
    addTearDown(controller.dispose);

    await controller.addFavoriteGroup('New group');
    await controller.completeAuthCallback(
      const AppLaunchAction(
        target: AppLaunchTarget.authCallback,
        authToken: 'test-token',
        authAccountId: 'test-account',
        authDeviceId: 'test-device',
        authRole: 'user',
        authProvider: 'test',
        authDisplayName: 'Test User',
      ),
    );

    await controller.syncAllAccountData();

    expect(syncService.favoritePayload, {
      'groups': {'New group': <dynamic>[]},
    });
    expect(syncService.favoriteRestoreCount, 0);
    expect(controller.favoriteGroupNames, ['Old group', 'New group']);
    expect(controller.favoritesInGroup('Old group'), hasLength(1));
    expect(controller.favoritesInGroup('New group'), isEmpty);
  });
}

class _FakeAuthService extends AuthService {
  AuthSession? _fakeSession;

  @override
  AuthSession? get session => _fakeSession;

  @override
  Future<void> completeCallback({
    required String token,
    required String accountId,
    required String deviceId,
    required String role,
    required String provider,
    required String displayName,
  }) async {
    _fakeSession = AuthSession(
      token: token,
      accountId: accountId,
      deviceId: deviceId,
      role: role,
      provider: provider,
      displayName: displayName,
    );
  }

  @override
  Future<AuthAccount> fetchAccount() async {
    return const AuthAccount(
      accountId: 'test-account',
      deviceId: 'test-device',
      role: 'user',
      device: null,
      identities: [],
    );
  }
}

class _FakeAccountSyncService extends AccountSyncService {
  static const _oldFavorite = {
    'provider': 'tpe',
    'routeKey': 123,
    'pathId': 0,
    'stopId': 456,
  };

  Map<String, dynamic>? favoritePayload;
  int favoriteRestoreCount = 0;

  @override
  Future<AccountSyncSummary> fetchSummary() async {
    return AccountSyncSummary(
      serverTime: DateTime.utc(2026, 7, 14),
      documents: {
        AccountSyncNamespace.favorites: _document(
          AccountSyncNamespace.favorites,
          payload: const {
            'groups': {
              'Old group': [_oldFavorite],
            },
          },
        ),
        AccountSyncNamespace.preferences: _document(
          AccountSyncNamespace.preferences,
          payload: const {},
        ),
      },
    );
  }

  @override
  Future<AccountSyncDocument> fetchDocument(
    AccountSyncNamespace namespace,
  ) async {
    if (namespace == AccountSyncNamespace.favorites) {
      favoriteRestoreCount += 1;
    }
    return _document(namespace, payload: const {'groups': {}});
  }

  @override
  Future<AccountSyncWriteResult> upsertDocument({
    required AccountSyncNamespace namespace,
    required Map<String, dynamic> payload,
    required DateTime clientModifiedAt,
    required int schemaVersion,
    AccountSyncConflictPolicy conflictPolicy = AccountSyncConflictPolicy.abort,
    int? baseRevision,
    String? baseEtag,
  }) async {
    if (namespace == AccountSyncNamespace.favorites) {
      favoritePayload = payload;
    }
    final documentPayload = namespace == AccountSyncNamespace.favorites
        ? {
            'groups': {
              'Old group': [_oldFavorite],
              ...((payload['groups'] as Map).map(
                (key, value) => MapEntry(key.toString(), value),
              )),
            },
          }
        : payload;
    return AccountSyncWriteResult(
      status: 'updated',
      conflictPolicy: conflictPolicy,
      document: _document(namespace, payload: documentPayload),
    );
  }

  AccountSyncDocument _document(
    AccountSyncNamespace namespace, {
    required Map<String, dynamic> payload,
  }) {
    final timestamp = DateTime.utc(2026, 7, 14);
    return AccountSyncDocument(
      namespace: namespace,
      hasData: true,
      schemaVersion: 1,
      revision: 1,
      etag: 'test-etag',
      updatedAt: timestamp,
      lastSyncedAt: timestamp,
      lastClientModifiedAt: timestamp,
      payloadSizeBytes: 1,
      payload: payload,
    );
  }
}
