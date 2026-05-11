import 'package:flutter/material.dart';

import '../widgets/markdown_content_view.dart';

class LegalMarkdownPage extends StatefulWidget {
  const LegalMarkdownPage({
    required this.title,
    required this.loadDocument,
    super.key,
  });

  final String title;
  final Future<String> Function() loadDocument;

  @override
  State<LegalMarkdownPage> createState() => _LegalMarkdownPageState();
}

class _LegalMarkdownPageState extends State<LegalMarkdownPage> {
  String? _content;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final content = await widget.loadDocument();
      if (!mounted) {
        return;
      }
      setState(() {
        _content = content;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '重新整理',
            onPressed: _loading ? null : _loadDocument,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && _content == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDocument,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (_error case final error?)
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 920),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: Card(
                            color: theme.colorScheme.errorContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '文件更新失敗',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(error),
                                  const SizedBox(height: 12),
                                  FilledButton.tonalIcon(
                                    onPressed: _loadDocument,
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('重試'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_content case final content?)
                    MarkdownContentView(markdown: content)
                  else if (!_loading)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: FilledButton.tonalIcon(
                          onPressed: _loadDocument,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('重新載入文件'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}