import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taiwanbus_flutter/core/account_sync_models.dart';
import 'package:taiwanbus_flutter/core/account_sync_service.dart';
import 'package:taiwanbus_flutter/core/auth_token_store.dart';

void main() {
  tearDown(() {
    AuthTokenStore.token = null;
  });

  test('fetchSummary sends auth header and parses document metadata', () async {
    AuthTokenStore.token = 'sync-token';
    final service = AccountSyncService(
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/account/sync');
        expect(
          request.headers['Authorization'] ?? request.headers['authorization'],
          'Bearer sync-token',
        );
        return http.Response(
          jsonEncode({
            'server_time': '2026-05-21T10:00:00Z',
            'documents': {
              'favorites': {
                'namespace': 'favorites',
                'has_data': true,
                'schema_version': 1,
                'revision': 3,
                'etag': '"sync-favorites-3-abc"',
                'updated_at': '2026-05-21T09:00:00Z',
                'last_synced_at': '2026-05-21T09:01:00Z',
                'last_client_modified_at': '2026-05-21T08:59:00Z',
                'payload_size_bytes': 1234,
              },
              'preferences': {
                'namespace': 'preferences',
                'has_data': false,
                'schema_version': null,
                'revision': 0,
                'etag': null,
                'updated_at': null,
                'last_synced_at': null,
                'last_client_modified_at': null,
                'payload_size_bytes': 0,
              },
            },
          }),
          200,
        );
      }),
    );

    final summary = await service.fetchSummary();

    expect(summary.serverTime, isNotNull);
    expect(summary.documents[AccountSyncNamespace.favorites]?.revision, 3);
    expect(summary.documents[AccountSyncNamespace.favorites]?.hasData, isTrue);
    expect(
      summary.documents[AccountSyncNamespace.preferences]?.hasData,
      isFalse,
    );
  });

  test('upsertDocument posts payload and parses success response', () async {
    AuthTokenStore.token = 'sync-token';
    final service = AccountSyncService(
      client: MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/api/v1/account/sync/preferences');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['schema_version'], 1);
        expect(body['conflict_policy'], 'abort');
        expect(body['payload']['appearance']['themeMode'], 'dark');
        return http.Response(
          jsonEncode({
            'ok': true,
            'status': 'updated',
            'conflict_policy': 'abort',
            'document': {
              'namespace': 'preferences',
              'has_data': true,
              'schema_version': 1,
              'revision': 4,
              'etag': '"sync-preferences-4-abc"',
              'updated_at': '2026-05-21T09:00:00Z',
              'last_synced_at': '2026-05-21T09:01:00Z',
              'last_client_modified_at': '2026-05-21T08:59:00Z',
              'payload_size_bytes': 222,
              'payload': {
                'appearance': {'themeMode': 'dark'},
              },
            },
          }),
          200,
        );
      }),
    );

    final result = await service.upsertDocument(
      namespace: AccountSyncNamespace.preferences,
      payload: {
        'appearance': {'themeMode': 'dark'},
      },
      clientModifiedAt: DateTime.utc(2026, 5, 21, 8, 59),
      schemaVersion: 1,
    );

    expect(result.status, 'updated');
    expect(result.document?.revision, 4);
    expect(result.document?.payload?['appearance']['themeMode'], 'dark');
  });

  test('upsertDocument surfaces conflict details', () async {
    final service = AccountSyncService(
      client: MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'ok': false,
              'status': 'conflict',
              'namespace': 'favorites',
              'message': 'Server data changed since the last sync.',
              'server_document': {
                'namespace': 'favorites',
                'has_data': true,
                'schema_version': 1,
                'revision': 5,
                'etag': '"sync-favorites-5-abc"',
                'updated_at': '2026-05-21T09:30:00Z',
                'last_synced_at': '2026-05-21T09:31:00Z',
                'last_client_modified_at': '2026-05-21T09:29:00Z',
                'payload_size_bytes': 128,
                'payload': {
                  'groups': {
                    '通勤': [
                      {
                        'provider': 'tpe',
                        'routeKey': 1,
                        'pathId': 0,
                        'stopId': 100,
                      },
                    ],
                  },
                },
              },
              'merge_preview': {
                'status': 'possible',
                'message': null,
                'payload': {'groups': {}},
              },
            }),
          ),
          409,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    expect(
      () => service.upsertDocument(
        namespace: AccountSyncNamespace.favorites,
        payload: {
          'groups': {
            '通勤': [
              {'provider': 'tpe', 'routeKey': 1, 'pathId': 0, 'stopId': 100},
            ],
          },
        },
        clientModifiedAt: DateTime.utc(2026, 5, 21, 9, 0),
        schemaVersion: 1,
      ),
      throwsA(
        isA<AccountSyncConflictException>()
            .having(
              (error) => error.namespace,
              'namespace',
              AccountSyncNamespace.favorites,
            )
            .having((error) => error.canMerge, 'canMerge', isTrue)
            .having(
              (error) => error.serverDocument?.revision,
              'server revision',
              5,
            ),
      ),
    );
  });
}
