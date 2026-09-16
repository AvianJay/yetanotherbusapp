import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taiwanbus_flutter/core/app_build_info.dart';
import 'package:taiwanbus_flutter/core/app_update_service.dart';
import 'package:taiwanbus_flutter/core/models.dart';

void main() {
  List<Map<String, String>> nightlyAssets(String downloadUrl) => [
    {'name': 'YABus-nightly.apk', 'browser_download_url': downloadUrl},
    {
      'name': 'YABus-nightly-windows-x64-setup.exe',
      'browser_download_url': downloadUrl,
    },
    {
      'name': 'YABus-nightly-linux-amd64.deb',
      'browser_download_url': downloadUrl,
    },
    {'name': 'YABus-nightly-macos.dmg', 'browser_download_url': downloadUrl},
  ];

  test(
    'nightly compares normalized full SHAs and uses its release asset',
    () async {
      const currentSha = 'abcdef0123456789abcdef0123456789abcdef01';
      const latestSha = 'abcdef0fedcba9876543210fedcba9876543210f';
      const artifactUrl =
          'https://github.com/AvianJay/yetanotherbusapp/releases/download/nightly/YABus-nightly.apk';
      final service = AppUpdateService(
        buildInfo: const AppBuildInfo(
          version: '1.0.0',
          buildNumber: '1',
          gitSha: ' ABCDEF0123456789ABCDEF0123456789ABCDEF01 ',
          defaultUpdateChannel: AppUpdateChannel.nightly,
        ),
        client: MockClient((request) async {
          expect(request.url.path, '/repos/AvianJay/yetanotherbusapp/releases');
          expect(request.url.queryParameters['per_page'], '30');
          return http.Response(
            jsonEncode([
              {
                'tag_name': 'nightly-$latestSha',
                'prerelease': true,
                'body': 'Nightly build for this commit.',
                'assets': nightlyAssets(artifactUrl),
              },
              {
                'tag_name': 'v1.0.0',
                'prerelease': false,
                'assets': [
                  {
                    'name': 'unrelated-artifact',
                    'browser_download_url': 'https://example.com/unrelated.zip',
                  },
                ],
              },
            ]),
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
    'nightly check reports up to date when normalized full release tag matches',
    () async {
      const sha = 'abcdef0123456789abcdef0123456789abcdef01';
      final service = AppUpdateService(
        buildInfo: const AppBuildInfo(
          version: '1.0.0',
          buildNumber: '1',
          gitSha: ' ABCDEF0123456789ABCDEF0123456789ABCDEF01 ',
          defaultUpdateChannel: AppUpdateChannel.nightly,
        ),
        client: MockClient((request) async {
          expect(request.url.path, '/repos/AvianJay/yetanotherbusapp/releases');
          return http.Response(
            jsonEncode([
              {
                'tag_name': 'nightly-$sha',
                'prerelease': true,
                'assets': const [],
              },
            ]),
            200,
          );
        }),
      );

      final result = await service.checkForUpdates(AppUpdateChannel.nightly);

      expect(result.status, AppUpdateStatus.upToDate);
      expect(result.hasUpdate, isFalse);
    },
  );

  test('nightly ignores pre-releases without a full commit tag', () async {
    final service = AppUpdateService(
      buildInfo: const AppBuildInfo(
        version: '1.0.0',
        buildNumber: '1',
        gitSha: 'abcdef0123456789abcdef0123456789abcdef01',
        defaultUpdateChannel: AppUpdateChannel.nightly,
      ),
      client: MockClient((request) async {
        return http.Response(
          jsonEncode([
            {
              'tag_name': 'nightly-main',
              'prerelease': true,
              'assets': const [],
            },
          ]),
          200,
        );
      }),
    );

    final result = await service.checkForUpdates(AppUpdateChannel.nightly);

    expect(result.status, AppUpdateStatus.unavailable);
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
