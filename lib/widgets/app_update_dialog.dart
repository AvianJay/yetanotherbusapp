import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_build_info.dart';
import '../core/app_controller.dart';
import '../core/app_update_service.dart';
import '../core/models.dart';

Future<void> showAppUpdateDialog(
  BuildContext context, {
  required AppController controller,
  required AppUpdateCheckResult result,
}) async {
  final update = result.update;
  if (update == null) {
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _AppUpdateDialog(controller: controller, update: update);
    },
  );
}

class _AppUpdateDialog extends StatefulWidget {
  const _AppUpdateDialog({required this.controller, required this.update});

  final AppController controller;
  final AppUpdateInfo update;

  @override
  State<_AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<_AppUpdateDialog> {
  bool _installing = false;
  double? _progress;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _statusMessage = widget.update.summary;
  }

  Future<void> _copyLink(String url, String label) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label已複製到剪貼簿。')));
  }

  Future<void> _openMarkdownLink(String? href) async {
    if (href == null) {
      return;
    }

    final uri = Uri.tryParse(href);
    if (uri == null) {
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted || opened) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('無法開啟連結。')));
  }

  String? _buildChangelogMarkdown() {
    final notes = widget.update.notes?.trim();
    final detailsUrl = widget.update.detailsUrl?.trim();
    final sections = <String>[];

    if (widget.update.channel == AppUpdateChannel.nightly) {
      sections.add(_buildNightlyCommitMarkdown());
    }

    if (detailsUrl != null && detailsUrl.isNotEmpty) {
      final rangeLabel =
          '${widget.update.currentVersionLabel}...${widget.update.latestVersionLabel}';
      sections.add('變更紀錄：[$rangeLabel]($detailsUrl)');
    }

    if (notes != null && notes.isNotEmpty) {
      sections.add(notes);
    }

    if (sections.isEmpty) {
      return null;
    }
    return sections.join('\n\n');
  }

  String _buildNightlyCommitMarkdown() {
    final commitHash = widget.update.latestVersionLabel;
    final commitUrl = Uri.https(
      'github.com',
      '/${AppBuildInfo.repoOwner}/${AppBuildInfo.repoName}/commit/$commitHash',
    );
    final comment = widget.update.summary.trim();
    return '[`$commitHash`]($commitUrl): $comment';
  }

  Future<void> _installUpdate() async {
    if (_installing) {
      return;
    }

    setState(() {
      _installing = true;
      _progress = 0;
      _statusMessage = '準備更新…';
    });

    final messenger = ScaffoldMessenger.of(context);
    final installResult = await widget.controller.installAppUpdate(
      widget.update,
      onProgress: (progress, message) {
        if (!mounted) {
          return;
        }
        setState(() {
          _progress = progress;
          _statusMessage = message;
        });
      },
    );

    if (!mounted) {
      return;
    }

    if (installResult.didLaunchInstaller &&
        _shouldExitAfterSchedulingInstaller) {
      Navigator.of(context).pop();
      await widget.controller.appUpdateInstaller.exitAfterLaunchingInstaller();
      await SystemNavigator.pop();
      return;
    }

    setState(() {
      _installing = false;
      _progress = null;
      _statusMessage = widget.update.summary;
    });

    messenger.showSnackBar(SnackBar(content: Text(installResult.message)));

    if (installResult.didLaunchInstaller) {
      Navigator.of(context).pop();
    }
  }

  bool get _shouldExitAfterSchedulingInstaller =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  Widget build(BuildContext context) {
    final canInstallInApp =
        widget.controller.appUpdateInstaller.supportsInAppInstall;
    final changelogMarkdown = _buildChangelogMarkdown();

    return AlertDialog(
      title: Text(widget.update.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Text(widget.update.summary),
              const SizedBox(height: 12),
              Text('目前版本：${widget.update.currentVersionLabel}'),
              Text('最新版本：${widget.update.latestVersionLabel}'),
              if (_installing) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
                Text(_statusMessage),
              ],
              if (changelogMarkdown != null) ...[
                const SizedBox(height: 16),
                Text('更新內容', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                MarkdownBody(
                  data: changelogMarkdown,
                  onTapLink: (text, href, title) => _openMarkdownLink(href),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _installing
              ? null
              : () => _copyLink(widget.update.downloadUrl, '下載連結'),
          child: Text(canInstallInApp ? '複製下載連結' : '下載連結'),
        ),
        TextButton(
          onPressed: _installing ? null : () => Navigator.of(context).pop(),
          child: Text(canInstallInApp ? '稍後' : '關閉'),
        ),
        if (canInstallInApp)
          FilledButton(
            onPressed: _installing ? null : _installUpdate,
            child: const Text('下載並安裝'),
          ),
      ],
    );
  }
}
