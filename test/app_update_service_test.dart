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

  test('release check strips generated download table from notes', () async {
    final service = AppUpdateService(
      buildInfo: const AppBuildInfo(
        version: '1.0.0',
        buildNumber: '1',
        gitSha: 'abc1234',
        defaultUpdateChannel: AppUpdateChannel.release,
      ),
      client: MockClient((request) async {
        expect(request.url.path, contains('/releases/latest'));
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'tag_name': '1.1.0',
              'html_url':
                  'https://github.com/AvianJay/yetanotherbusapp/releases/tag/1.1.0',
              'body': '''
## YABus 1.1.0

修正背景乘車提醒更新流程。

<!-- YABUS_RELEASE_DOWNLOAD_TABLE_START -->

## Downloads

| Platform | Package | Download |
| --- | --- | --- |
| Android | APK | [download](https://example.com/app.apk) |

<!-- YABUS_RELEASE_DOWNLOAD_TABLE_END -->
''',
              'assets': [
                {
                  'name': 'YABus-1.1.0.apk',
                  'browser_download_url': 'https://example.com/YABus-1.1.0.apk',
                },
              ],
            }),
          ),
          200,
        );
      }),
    );

    final result = await service.checkForUpdates(AppUpdateChannel.release);

    expect(result.hasUpdate, isTrue);
    expect(result.update?.summary, 'YABus 1.1.0');
    expect(result.update?.notes, contains('修正背景乘車提醒更新流程。'));
    expect(result.update?.notes, isNot(contains('## Downloads')));
    expect(
      result.update?.notes,
      isNot(contains('YABUS_RELEASE_DOWNLOAD_TABLE_START')),
    );
  });
}
