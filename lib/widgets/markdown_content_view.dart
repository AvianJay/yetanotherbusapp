import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../core/app_link_handler.dart';

class MarkdownContentView extends StatelessWidget {
  const MarkdownContentView({
    required this.markdown,
    this.maxWidth = 920,
    this.padding = const EdgeInsets.all(20),
    super.key,
  });

  final String markdown;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  Future<void> _handleLink(BuildContext context, String? href) async {
    if (href == null || href.trim().isEmpty) {
      return;
    }
    final opened = await openAppLink(context, href);
    if (!context.mounted || opened) {
      return;
    }
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('無法開啟連結。')));
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding,
          child: MarkdownBody(
            data: markdown,
            onTapLink: (text, href, title) => _handleLink(context, href),
          ),
        ),
      ),
    );
  }
}