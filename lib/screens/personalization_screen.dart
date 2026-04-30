import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app/bus_app.dart';
import '../core/models.dart';

/// Preset seed colors for quick selection.
const _presetColors = <Color>[
  Color(0xFF0B7285), // 青藍（預設）
  Color(0xFF1565C0), // 藍
  Color(0xFF2E7D32), // 綠
  Color(0xFFF57F17), // 琥珀
  Color(0xFFD84315), // 橘
  Color(0xFFAD1457), // 玫瑰
  Color(0xFF6A1B9A), // 紫
  Color(0xFF4E342E), // 棕
  Color(0xFF37474F), // 藍灰
  Color(0xFF00897B), // 青綠
];

/// Page key → display label
const _pageLabels = <String, String>{
  'bus': '主頁',
  'search': '搜尋',
  'favorites': '最愛',
  'nearby': '附近',
  'settings': '設定',
};

/// Page key → icon
const _pageIcons = <String, IconData>{
  'bus': Icons.home_outlined,
  'search': Icons.search_rounded,
  'favorites': Icons.favorite_outline_rounded,
  'nearby': Icons.near_me_outlined,
  'settings': Icons.settings_outlined,
};

class PersonalizationScreen extends StatelessWidget {
  const PersonalizationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final settings = controller.settings;
    final backgroundOpacity = _backgroundOpacityValue(settings);
    final isAmoled =
        settings.useAmoledDark && settings.themeMode != ThemeMode.light;

    return Scaffold(
      appBar: AppBar(title: const Text('個人化')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          // ── 背景圖片預覽滑動 ────────────────────────────
          if (settings.pageBackgroundImagePaths.isNotEmpty) ...[
            _BackgroundPreviewCarousel(
              paths: settings.pageBackgroundImagePaths,
              opacities: settings.pageBackgroundImageOpacities,
            ),
            const SizedBox(height: 12),
          ],

          // ── 配色 ──────────────────────────────────────
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () {
                _showColorSettingsDialog(context);
              },
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Icon(
                      Icons.palette_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '配色',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _colorSubtitle(settings),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (settings.seedColor != null) ...[
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: settings.seedColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── 深色模式 ─────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '深色模式',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.dark_mode_outlined),
                    title: const Text('純黑 (AMOLED) 深色主題'),
                    subtitle: const Text('深色模式下使用純黑背景，可省電並提升對比'),
                    value: settings.useAmoledDark,
                    onChanged: settings.themeMode == ThemeMode.light
                        ? null
                        : (value) {
                            controller.updateUseAmoledDark(value);
                          },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── 主頁漸層 ──────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '主頁漸層',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '調整主頁漸層背景的透明度',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  _OpacitySlider(
                    label: '漸層透明度',
                    value: settings.homeBackgroundOpacity,
                    onChanged: isAmoled
                        ? null
                        : (v) {
                            controller.updateHomeBackgroundOpacity(v);
                          },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── 背景圖片 ────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '背景圖片',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '設定各頁面的背景圖片。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Opacity(
                    opacity: isAmoled ? 0.4 : 1.0,
                    child: IgnorePointer(
                      ignoring: isAmoled,
                      child: Column(
                        children: [
                          // Global: pick + clear
                          Row(
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: () async {
                                  final picker = ImagePicker();
                                  final image = await picker.pickImage(
                                    source: ImageSource.gallery,
                                  );
                                  if (image != null) {
                                    controller.applyBackgroundImageToAllPages(
                                      image.path,
                                      backgroundOpacity,
                                    );
                                  }
                                },
                                icon: const Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 18,
                                ),
                                label: const Text('選擇圖片'),
                              ),
                              const SizedBox(width: 8),
                              if (settings.pageBackgroundImagePaths.isNotEmpty)
                                OutlinedButton.icon(
                                  onPressed: () {
                                    controller.clearAllBackgroundImages();
                                  },
                                  icon: const Icon(Icons.clear_all, size: 18),
                                  label: const Text('清除'),
                                ),
                            ],
                          ),
                            if (settings.pageBackgroundImagePaths.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _OpacitySlider(
                                label: '背景透明度',
                                value: backgroundOpacity,
                                onChanged: isAmoled
                                    ? null
                                    : (value) {
                                        controller.updateAllPageBackgroundImageOpacity(
                                          value,
                                        );
                                      },
                              ),
                            ],
                          const SizedBox(height: 12),
                          // Navigate to per-page settings
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.tune_outlined),
                            title: const Text('各頁面設定'),
                            subtitle: const Text('分別設定每個頁面的背景圖片'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      const _PerPageBackgroundScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── 覆蓋層透明度 ──────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '覆蓋層透明度',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  // Text(
                  //   '背景圖片啟用時，卡片、AppBar 等元件的透明度，數值越高越不透明',
                  //   style: Theme.of(context).textTheme.bodySmall,
                  // ),
                  const SizedBox(height: 12),
                  _OpacitySlider(
                    label: '覆蓋層',
                    value: settings.overlayOpacity,
                    onChanged: isAmoled
                        ? null
                        : (v) {
                            controller.updateOverlayOpacity(v);
                          },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _backgroundOpacityValue(AppSettings settings) {
    final configuredKeys = settings.pageBackgroundImagePaths.entries
        .where((entry) => entry.value.isNotEmpty)
        .map((entry) => entry.key)
        .toList();
    if (configuredKeys.isEmpty) {
      return 0.25;
    }

    final total = configuredKeys.fold<double>(
      0,
      (sum, key) => sum + (settings.pageBackgroundImageOpacities[key] ?? 0.25),
    );
    final average = total / configuredKeys.length;
    if (average < 0) {
      return 0;
    }
    if (average > 1) {
      return 1;
    }
    return average;
  }

  String _colorSubtitle(AppSettings settings) {
    final seedColor = settings.seedColor;
    if (seedColor == null) {
      return '自動';
    }
    return _formatColorValue(seedColor);
  }

  String _formatColorValue(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  Future<void> _showColorSettingsDialog(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final settings = controller.settings;
            return AlertDialog(
              title: const Text('配色'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '支援系統配色的裝置會自動套用系統色；選擇自訂色後會覆蓋自動配色。',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      _SeedColorPicker(
                        selectedColor: settings.seedColor,
                        presetColors: _presetColors,
                        onColorSelected: (color) {
                          controller.updateSeedColor(color);
                        },
                        onClear: () {
                          controller.updateSeedColor(null);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('關閉'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────────
// Seed color picker with presets + custom
// ────────────────────────────────────────────────────────────────

class _SeedColorPicker extends StatelessWidget {
  const _SeedColorPicker({
    required this.selectedColor,
    required this.presetColors,
    required this.onColorSelected,
    required this.onClear,
  });

  final Color? selectedColor;
  final List<Color> presetColors;
  final ValueChanged<Color> onColorSelected;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _colorChip(
              context,
              color: null,
              label: '自動',
              selected: selectedColor == null,
            ),
            for (final c in presetColors)
              _colorChip(
                context,
                color: c,
                selected: selectedColor == c,
              ),
            ActionChip(
              avatar: Icon(
                Icons.colorize_outlined,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              label: const Text('自訂'),
              onPressed: () async {
                final picked = await _showColorPickerDialog(
                  context,
                  selectedColor ?? presetColors.first,
                );
                if (picked != null) onColorSelected(picked);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _colorChip(
    BuildContext context, {
    required Color? color,
    required bool selected,
    String? label,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return ChoiceChip(
      avatar: color != null
          ? CircleAvatar(backgroundColor: color, radius: 10)
          : null,
      label: Text(label ?? _colorName(color)),
      selected: selected,
      selectedColor: color != null
          ? color.withValues(alpha: 0.18)
          : colorScheme.primaryContainer.withValues(alpha: 0.5),
      onSelected: (_) {
        if (color != null) {
          onColorSelected(color);
        } else {
          onClear();
        }
      },
    );
  }

  String _colorName(Color? color) {
    if (color == null) return '自動';
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  Future<Color?> _showColorPickerDialog(BuildContext context, Color initial) {
    return showDialog<Color>(
      context: context,
      builder: (ctx) => _CustomColorPickerDialog(initial: initial),
    );
  }
}

// ────────────────────────────────────────────────────────────────
// Simple HSV color picker dialog
// ────────────────────────────────────────────────────────────────

class _CustomColorPickerDialog extends StatefulWidget {
  const _CustomColorPickerDialog({required this.initial});

  final Color initial;

  @override
  State<_CustomColorPickerDialog> createState() =>
      _CustomColorPickerDialogState();
}

class _CustomColorPickerDialogState extends State<_CustomColorPickerDialog> {
  late double _hue;
  late double _saturation;
  late double _value;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.initial);
    _hue = hsv.hue;
    _saturation = hsv.saturation;
    _value = hsv.value;
  }

  Color get _currentColor => HSVColor.fromAHSV(1.0, _hue, _saturation, _value).toColor();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('選擇顏色'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Preview
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: _currentColor,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 16),
            // Hue
            Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text('色相', style: Theme.of(context).textTheme.labelMedium),
                ),
                Expanded(
                  child: Slider(
                    value: _hue,
                    max: 360,
                    divisions: 360,
                    label: _hue.round().toString(),
                    activeColor: _currentColor,
                    onChanged: (v) => setState(() => _hue = v),
                  ),
                ),
              ],
            ),
            // Saturation
            Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text('飽和', style: Theme.of(context).textTheme.labelMedium),
                ),
                Expanded(
                  child: Slider(
                    value: _saturation,
                    divisions: 100,
                    label: (_saturation * 100).round().toString(),
                    activeColor: _currentColor,
                    onChanged: (v) => setState(() => _saturation = v),
                  ),
                ),
              ],
            ),
            // Value / Brightness
            Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text('明度', style: Theme.of(context).textTheme.labelMedium),
                ),
                Expanded(
                  child: Slider(
                    value: _value,
                    divisions: 100,
                    label: (_value * 100).round().toString(),
                    activeColor: _currentColor,
                    onChanged: (v) => setState(() => _value = v),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_currentColor),
          child: const Text('確定'),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────
// Per-page background settings screen (separate route)
// ────────────────────────────────────────────────────────────────

class _PerPageBackgroundScreen extends StatelessWidget {
  const _PerPageBackgroundScreen();

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final settings = controller.settings;
    final isAmoled =
        settings.useAmoledDark && settings.themeMode != ThemeMode.light;

    return Scaffold(
      appBar: AppBar(title: const Text('各頁面背景設定')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          // ── Preview carousel ─────────────────────────
          if (settings.pageBackgroundImagePaths.isNotEmpty) ...[
            _BackgroundPreviewCarousel(
              paths: settings.pageBackgroundImagePaths,
              opacities: settings.pageBackgroundImageOpacities,
            ),
            const SizedBox(height: 12),
          ],

          // ── Per-page rows ────────────────────────────
          Opacity(
            opacity: isAmoled ? 0.4 : 1.0,
            child: IgnorePointer(
              ignoring: isAmoled,
              child: Column(
                children: [
                  for (final pageKey in _pageLabels.keys)
                    _PageBackgroundRow(
                      pageKey: pageKey,
                      label: _pageLabels[pageKey]!,
                      icon: _pageIcons[pageKey]!,
                      imagePath: settings.pageBackgroundImagePaths[pageKey],
                      imageOpacity:
                          settings.pageBackgroundImageOpacities[pageKey] ??
                              0.25,
                      onPick: () async {
                        final picker = ImagePicker();
                        final image = await picker.pickImage(
                          source: ImageSource.gallery,
                        );
                        if (image != null) {
                          controller.updatePageBackgroundImagePath(
                            pageKey,
                            image.path,
                          );
                        }
                      },
                      onClear: () {
                        controller.updatePageBackgroundImagePath(pageKey, null);
                      },
                      onOpacityChanged: (v) {
                        controller.updatePageBackgroundImageOpacity(pageKey, v);
                      },
                      colorScheme: Theme.of(context).colorScheme,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────
// Background preview carousel
// ────────────────────────────────────────────────────────────────

class _BackgroundPreviewCarousel extends StatelessWidget {
  const _BackgroundPreviewCarousel({
    required this.paths,
    required this.opacities,
  });

  final Map<String, String> paths;
  final Map<String, double> opacities;

  @override
  Widget build(BuildContext context) {
    final entries = paths.entries
        .where((e) => e.value.isNotEmpty && _pageLabels.containsKey(e.key))
        .toList();

    if (entries.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 196,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final entry = entries[index];
          return _PreviewPageCard(
            pageKey: entry.key,
            label: _pageLabels[entry.key] ?? entry.key,
            imagePath: entry.value,
            imageOpacity: opacities[entry.key] ?? 0.25,
          );
        },
      ),
    );
  }
}

class _PreviewPageCard extends StatelessWidget {
  const _PreviewPageCard({
    required this.pageKey,
    required this.label,
    required this.imagePath,
    required this.imageOpacity,
  });

  final String pageKey;
  final String label;
  final String imagePath;
  final double imageOpacity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isGif = imagePath.toLowerCase().endsWith('.gif');
    final appBarColor =
        theme.appBarTheme.backgroundColor ?? colorScheme.surface;
    final cardColor =
        theme.cardTheme.color ?? colorScheme.surfaceContainerHigh;
    final inputColor = theme.inputDecorationTheme.fillColor ?? cardColor;
    final bottomBarColor = theme.bottomAppBarTheme.color ?? appBarColor;
    final lineColor = colorScheme.onSurface.withValues(alpha: 0.26);
    final detailColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.42);
    final accentColor = colorScheme.primary.withValues(alpha: 0.88);
    final badgeColor = theme.brightness == Brightness.dark
        ? const Color(0xFF8B1A1A)
        : Colors.red.shade800;

    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 124,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: theme.scaffoldBackgroundColor),
                  Image.file(
                    File(imagePath),
                    fit: BoxFit.cover,
                    gaplessPlayback: isGif,
                    opacity: AlwaysStoppedAnimation(
                      imageOpacity.clamp(0.0, 1.0),
                    ),
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: colorScheme.errorContainer,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  _buildAppBar(appBarColor, accentColor, lineColor),
                  Positioned.fill(
                    top: 30,
                    left: 7,
                    right: 7,
                    bottom: pageKey == 'favorites' ? 22 : 8,
                    child: _buildPageContent(
                      accentColor,
                      cardColor,
                      inputColor,
                      lineColor,
                      detailColor,
                      badgeColor,
                    ),
                  ),
                  if (pageKey == 'favorites')
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 16,
                        color: bottomBarColor,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.centerLeft,
                        child: _buildLine(
                          lineColor,
                          widthFactor: 0.34,
                          height: 3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall,
        ),
      ],
    );
  }

  Widget _buildAppBar(
    Color backgroundColor,
    Color accentColor,
    Color lineColor,
  ) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 24,
        color: backgroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Row(
          children: [
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildLine(
                lineColor,
                widthFactor: pageKey == 'settings' ? 0.32 : 0.48,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: lineColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageContent(
    Color accentColor,
    Color cardColor,
    Color inputColor,
    Color lineColor,
    Color detailColor,
    Color badgeColor,
  ) {
    return switch (pageKey) {
      'bus' => _buildBusPreview(
        accentColor,
        cardColor,
        lineColor,
        detailColor,
        badgeColor,
      ),
      'search' => _buildSearchPreview(
        accentColor,
        cardColor,
        inputColor,
        lineColor,
        detailColor,
      ),
      'favorites' => _buildFavoritesPreview(
        accentColor,
        cardColor,
        lineColor,
        detailColor,
        badgeColor,
      ),
      'nearby' => _buildNearbyPreview(
        accentColor,
        cardColor,
        lineColor,
        detailColor,
      ),
      'settings' => _buildSettingsPreview(
        accentColor,
        cardColor,
        inputColor,
        lineColor,
        detailColor,
      ),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _buildBusPreview(
    Color accentColor,
    Color cardColor,
    Color lineColor,
    Color detailColor,
    Color badgeColor,
  ) {
    return Column(
      children: [
        Expanded(
          child: _buildCardShell(
            cardColor,
            child: Row(
              children: [
                _buildIconTile(accentColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLine(lineColor, widthFactor: 0.72, height: 5),
                      const SizedBox(height: 4),
                      _buildLine(detailColor, widthFactor: 0.95, height: 3),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _buildCardShell(
            cardColor,
            child: Row(
              children: [
                _buildIconTile(accentColor.withValues(alpha: 0.72)),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLine(lineColor, widthFactor: 0.6, height: 5),
                      const SizedBox(height: 4),
                      _buildLine(detailColor, widthFactor: 0.78, height: 3),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _buildCardShell(
            cardColor,
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLine(lineColor, widthFactor: 0.84, height: 5),
                      const SizedBox(height: 4),
                      _buildLine(detailColor, widthFactor: 0.62, height: 3),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchPreview(
    Color accentColor,
    Color cardColor,
    Color inputColor,
    Color lineColor,
    Color detailColor,
  ) {
    return Column(
      children: [
        Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: inputColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildLine(lineColor, widthFactor: 0.72, height: 4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _buildListPreviewCard(
            cardColor,
            accentColor,
            lineColor,
            detailColor,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _buildListPreviewCard(
            cardColor,
            accentColor.withValues(alpha: 0.78),
            lineColor,
            detailColor,
          ),
        ),
      ],
    );
  }

  Widget _buildFavoritesPreview(
    Color accentColor,
    Color cardColor,
    Color lineColor,
    Color detailColor,
    Color badgeColor,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          flex: 2,
          child: _buildCardShell(
            cardColor,
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLine(lineColor, widthFactor: 0.74, height: 5),
                      const SizedBox(height: 4),
                      _buildLine(detailColor, widthFactor: 0.9, height: 3),
                      const SizedBox(height: 4),
                      _buildLine(detailColor, widthFactor: 0.58, height: 3),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _buildCardShell(
            cardColor,
            child: Row(
              children: [
                _buildIconTile(accentColor.withValues(alpha: 0.74), size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLine(lineColor, widthFactor: 0.62, height: 4),
                      const SizedBox(height: 4),
                      _buildLine(detailColor, widthFactor: 0.52, height: 3),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNearbyPreview(
    Color accentColor,
    Color cardColor,
    Color lineColor,
    Color detailColor,
  ) {
    return Column(
      children: [
        Expanded(
          child: _buildNearbyListCard(
            accentColor,
            cardColor,
            lineColor,
            detailColor,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _buildNearbyListCard(
            accentColor.withValues(alpha: 0.76),
            cardColor,
            lineColor,
            detailColor,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsPreview(
    Color accentColor,
    Color cardColor,
    Color inputColor,
    Color lineColor,
    Color detailColor,
  ) {
    return Column(
      children: [
        Expanded(
          child: _buildCardShell(
            cardColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLine(lineColor, widthFactor: 0.44, height: 5),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: _buildLine(
                        detailColor,
                        widthFactor: 0.72,
                        height: 4,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 20,
                      height: 11,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.all(1),
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _buildLine(
                        detailColor,
                        widthFactor: 0.58,
                        height: 4,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _buildIconTile(accentColor.withValues(alpha: 0.7), size: 14),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _buildCardShell(
            cardColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLine(lineColor, widthFactor: 0.32, height: 5),
                const SizedBox(height: 8),
                Container(
                  height: 18,
                  decoration: BoxDecoration(
                    color: inputColor,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                const SizedBox(height: 6),
                _buildLine(detailColor, widthFactor: 0.74, height: 3),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListPreviewCard(
    Color cardColor,
    Color accentColor,
    Color lineColor,
    Color detailColor,
  ) {
    return _buildCardShell(
      cardColor,
      child: Row(
        children: [
          _buildIconTile(accentColor, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLine(lineColor, widthFactor: 0.7, height: 5),
                const SizedBox(height: 4),
                _buildLine(detailColor, widthFactor: 0.88, height: 3),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNearbyListCard(
    Color accentColor,
    Color cardColor,
    Color lineColor,
    Color detailColor,
  ) {
    return _buildCardShell(
      cardColor,
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.24),
              borderRadius: BorderRadius.circular(7),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLine(lineColor, widthFactor: 0.76, height: 5),
                const SizedBox(height: 4),
                _buildLine(detailColor, widthFactor: 0.68, height: 3),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardShell(Color color, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }

  Widget _buildIconTile(Color color, {double size = 18}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }

  Widget _buildLine(
    Color color, {
    required double widthFactor,
    double height = 4,
  }) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(height),
        ),
      ),
    );
  }
}

class _PageBackgroundRow extends StatelessWidget {
  const _PageBackgroundRow({
    required this.pageKey,
    required this.label,
    required this.icon,
    required this.imagePath,
    required this.imageOpacity,
    required this.onPick,
    required this.onClear,
    required this.onOpacityChanged,
    required this.colorScheme,
  });

  final String pageKey;
  final String label;
  final IconData icon;
  final String? imagePath;
  final double imageOpacity;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final ValueChanged<double> onOpacityChanged;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final hasImage = imagePath != null && imagePath!.isNotEmpty;
    final isGif = hasImage && imagePath!.toLowerCase().endsWith('.gif');

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Page label + icon
          Row(
            children: [
              Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isGif) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'GIF',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // Action buttons
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: onPick,
                icon: Icon(
                  hasImage ? Icons.swap_horiz : Icons.add_photo_alternate_outlined,
                  size: 18,
                ),
                label: Text(hasImage ? '更換' : '選擇圖片'),
              ),
              if (hasImage) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('移除'),
                ),
              ],
            ],
          ),

          // Opacity slider
          if (hasImage) ...[
            const SizedBox(height: 8),
            _OpacitySlider(
              label: '背景透明度',
              value: imageOpacity,
              onChanged: onOpacityChanged,
            ),
          ],
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────
// Opacity slider
// ────────────────────────────────────────────────────────────────

class _OpacitySlider extends StatelessWidget {
  const _OpacitySlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0.0,
            max: 1.0,
            divisions: 100,
            label: (value * 100).round().toString(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            '${(value * 100).round()}%',
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
