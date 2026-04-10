import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taiwanbus_flutter/core/app_build_info.dart';
import 'package:taiwanbus_flutter/core/app_update_service.dart';
import 'package:taiwanbus_flutter/core/models.dart';

void main() {
  test(
    'nightly check reports update when latest workflow commit differs',
    () async {
      final service = AppUpdateService(
        buildInfo: const AppBuildInfo(
          version: '1.0.0',
          buildNumber: '1',
          gitSha: 'abc1234',
          defaultUpdateChannel: AppUpdateChannel.nightly,
        ),
        client: MockClient((request) async {
          expect(request.url.path, contains('/actions/workflows/'));
          expect(request.url.queryParameters['branch'], 'main');
          expect(request.url.queryParameters['event'], 'push');
          return http.Response(
            jsonEncode({
              'workflow_runs': [
                {
                  'head_sha': 'def5678fedcba',
                  'head_commit': {'message': 'nightly update'},
                },
              ],
            }),
            200,
          );
        }),
      );

      final result = await service.checkForUpdates(AppUpdateChannel.nightly);

      expect(result.hasUpdate, isTrue);
      expect(result.update?.latestVersionLabel, 'def5678');
      expect(result.update?.downloadUrl, endsWith('android-apk-release.zip'));
    },
  );

  test('nightly check reports up to date when commit matches', () async {
    final service = AppUpdateService(
      buildInfo: const AppBuildInfo(
        version: '1.0.0',
        buildNumber: '1',
        gitSha: 'abc1234',
        defaultUpdateChannel: AppUpdateChannel.nightly,
      ),
      client: MockClient((request) async {
        expect(request.url.queryParameters['branch'], 'main');
        expect(request.url.queryParameters['event'], 'push');
        return http.Response(
          jsonEncode({
            'workflow_runs': [
              {
                'head_sha': 'abc1234fedcba',
                'head_commit': {'message': 'same commit'},
              },
            ],
          }),
          200,
        );
      }),
    );

    final result = await service.checkForUpdates(AppUpdateChannel.nightly);

    expect(result.status, AppUpdateStatus.upToDate);
    expect(result.hasUpdate, isFalse);
  });
}
