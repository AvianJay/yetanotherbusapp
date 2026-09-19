import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taiwanbus_flutter/core/app_build_info.dart';
import 'package:taiwanbus_flutter/core/app_update_service.dart';
import 'package:taiwanbus_flutter/core/models.dart';

void main() {
  List<Map<String, String>> nightlyAssets(String sha, String downloadUrl) => [
    {'name': 'YABus-nightly-$sha.apk', 'browser_download_url': downloadUrl},
    {
      'name': 'YABus-nightly-$sha-windows-x64-setup.exe',
      'browser_download_url': downloadUrl,
    },
    {
      'name': 'YABus-nightly-$sha-linux-amd64.deb',
      'browser_download_url': downloadUrl,
    },
    {
      'name': 'YABus-nightly-$sha-macos.dmg',
      'browser_download_url': downloadUrl,
    },
  ];

  test(
    'nightly compares normalized full SHAs and uses its release asset',
    () async {
      const currentSha = 'abcdef0123456789abcdef0123456789abcdef01';
      const latestSha = '1234567890abcdef1234567890abcdef12345678';
      const artifactUrl =
          'https://github.com/YetAnotherBusDeveloper/yetanotherbusapp/releases/download/nightly-$latestSha/YABus-nightly-$latestSha.apk';
      final service = AppUpdateService(
        buildInfo: const AppBuildInfo(
          version: '1.0.0',
          buildNumber: '1',
          gitSha: ' ABCDEF0123456789ABCDEF0123456789ABCDEF01 ',
          defaultUpdateChannel: AppUpdateChannel.nightly,
        ),
        client: MockClient((request) async {
          expect(
            request.url.path,
            '/repos/YetAnotherBusDeveloper/yetanotherbusapp/releases',
          );
          expect(request.url.queryParameters['per_page'], '30');
          expect(request.headers['cache-control'], 'no-cache');
          expect(request.headers['pragma'], 'no-cache');
          return http.Response(
            jsonEncode([
              {
                'tag_name': 'nightly-$latestSha',
                'prerelease': true,
                'body':
                    '''
<!-- YABUS_ROLLING_NIGHTLY -->

Nightly build for commit `$latestSha`.
''',
                'assets': [
                  ...nightlyAssets(
                    '1111111111111111111111111111111111111111',
                    'https://example.com/stale.apk',
                  ),
                  ...nightlyAssets(latestSha, artifactUrl),
                ],
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
      expect(result.update?.currentDisplayLabel, 'abcdef0');
      expect(result.update?.latestDisplayLabel, '1234567');
      expect(result.update?.title, 'Nightly 更新');
      expect(result.update?.summary, 'Nightly 建置 1234567 已可下載。');
      expect(result.update?.notes, isNull);
      expect(result.update?.downloadUrl, artifactUrl);
      expect(
        result.update?.detailsUrl,
        'https://github.com/YetAnotherBusDeveloper/yetanotherbusapp/compare/$currentSha...$latestSha',
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
          expect(
            request.url.path,
            '/repos/YetAnotherBusDeveloper/yetanotherbusapp/releases',
          );
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

  test('nightly rejects assets that belong to another commit', () async {
    const currentSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const latestSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final service = AppUpdateService(
      buildInfo: const AppBuildInfo(
        version: '1.0.0',
        buildNumber: '1',
        gitSha: currentSha,
        defaultUpdateChannel: AppUpdateChannel.nightly,
      ),
      client: MockClient((request) async {
        return http.Response(
          jsonEncode([
            {
              'tag_name': 'nightly-$latestSha',
              'prerelease': true,
              'assets': nightlyAssets(
                currentSha,
                'https://example.com/stale.apk',
              ),
            },
          ]),
          200,
        );
      }),
    );

    final result = await service.checkForUpdates(AppUpdateChannel.nightly);

    expect(result.status, AppUpdateStatus.unavailable);
    expect(result.hasUpdate, isFalse);
    expect(result.update, isNull);
  });

  test('nightly rejects missing or blank platform assets', () async {
    const currentSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const latestSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final invalidAssetSets = <List<Map<String, String>>>[
      const [],
      nightlyAssets(latestSha, ''),
    ];

    for (final assets in invalidAssetSets) {
      final service = AppUpdateService(
        buildInfo: const AppBuildInfo(
          version: '1.0.0',
          buildNumber: '1',
          gitSha: currentSha,
          defaultUpdateChannel: AppUpdateChannel.nightly,
        ),
        client: MockClient((request) async {
          return http.Response(
            jsonEncode([
              {
                'tag_name': 'nightly-$latestSha',
                'prerelease': true,
                'assets': assets,
              },
            ]),
            200,
          );
        }),
      );

      final result = await service.checkForUpdates(AppUpdateChannel.nightly);

      expect(result.status, AppUpdateStatus.unavailable);
      expect(result.hasUpdate, isFalse);
      expect(result.update, isNull);
    }
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
                  'https://github.com/YetAnotherBusDeveloper/yetanotherbusapp/releases/tag/1.1.0',
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
    expect(result.update?.currentDisplayLabel, '1.0.0');
    expect(result.update?.latestDisplayLabel, '1.1.0');
    expect(result.update?.notes, contains('修正背景乘車提醒更新流程。'));
    expect(result.update?.notes, isNot(contains('## Downloads')));
    expect(
      result.update?.notes,
      isNot(contains('YABUS_RELEASE_DOWNLOAD_TABLE_START')),
    );
  });
}
