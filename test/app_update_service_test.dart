import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taiwanbus_flutter/core/app_build_info.dart';
import 'package:taiwanbus_flutter/core/app_update_service.dart';
import 'package:taiwanbus_flutter/core/models.dart';

void main() {
  test(
    'nightly compares normalized full SHAs and uses the selected run artifact',
    () async {
      const currentSha = 'abcdef0123456789abcdef0123456789abcdef01';
      const latestSha = 'abcdef0fedcba9876543210fedcba9876543210f';
      const artifactUrl =
          'https://api.github.com/repos/AvianJay/yetanotherbusapp/actions/artifacts/2468/zip';
      final service = AppUpdateService(
        buildInfo: const AppBuildInfo(
          version: '1.0.0',
          buildNumber: '1',
          gitSha: ' ABCDEF0123456789ABCDEF0123456789ABCDEF01 ',
          defaultUpdateChannel: AppUpdateChannel.nightly,
        ),
        client: MockClient((request) async {
          if (request.url.path.contains('/actions/workflows/')) {
            expect(request.url.queryParameters['branch'], 'main');
            expect(request.url.queryParameters['event'], 'push');
            return http.Response(
              jsonEncode({
                'workflow_runs': [
                  {
                    'id': 1357,
                    'head_sha': latestSha.toUpperCase(),
                    'head_commit': {'message': 'nightly update'},
                  },
                ],
              }),
              200,
            );
          }

          expect(
            request.url.path,
            '/repos/AvianJay/yetanotherbusapp/actions/runs/1357/artifacts',
          );
          expect(request.url.queryParameters['per_page'], '100');
          return http.Response(
            jsonEncode({
              'artifacts': [
                {
                  'name': 'unrelated-artifact',
                  'archive_download_url': 'https://example.com/unrelated.zip',
                },
                {
                  'name': AppBuildInfo.nightlyArtifactName,
                  'expired': false,
                  'archive_download_url': artifactUrl,
                },
              ],
            }),
            200,
          );
        }),
      );

      final result = await service.checkForUpdates(AppUpdateChannel.nightly);

      expect(result.hasUpdate, isTrue);
      expect(result.update?.currentVersionLabel, currentSha);
      expect(result.update?.latestVersionLabel, latestSha);
      expect(result.update?.downloadUrl, artifactUrl);
      expect(
        result.update?.detailsUrl,
        'https://github.com/AvianJay/yetanotherbusapp/compare/$currentSha...$latestSha',
      );
    },
  );

  test(
    'nightly check reports up to date when normalized full commit matches',
    () async {
      final service = AppUpdateService(
        buildInfo: const AppBuildInfo(
          version: '1.0.0',
          buildNumber: '1',
          gitSha: ' ABCDEF0123456789ABCDEF0123456789ABCDEF01 ',
          defaultUpdateChannel: AppUpdateChannel.nightly,
        ),
        client: MockClient((request) async {
          expect(request.url.queryParameters['branch'], 'main');
          expect(request.url.queryParameters['event'], 'push');
          return http.Response(
            jsonEncode({
              'workflow_runs': [
                {
                  'id': 1357,
                  'head_sha': 'abcdef0123456789abcdef0123456789abcdef01',
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
    },
  );

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
