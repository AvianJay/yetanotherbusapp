import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app/bus_app.dart';

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

class PersonalizationScreen extends StatelessWidget {
  const PersonalizationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final settings = controller.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('個人化')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          // ── 配色 ──────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('配色', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '選擇 App 整體色調，或跟隨系統桌布配色（Android 12+）',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.wallpaper_outlined),
                    title: const Text('跟隨系統配色'),
                    subtitle: const Text('Material You · Android 12+ 以上可用'),
                    value: settings.useDynamicColor,
                    onChanged: (value) {
                      controller.updateUseDynamicColor(value);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '自訂色調',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  _SeedColorPicker(
                    selectedColor: settings.seedColor,
                    presetColors: _presetColors,
                    enabled: !settings.useDynamicColor,
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

          // ── 背景透明度 ────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '主頁背景',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '調整主頁漸層背景的透明度，AMOLED 模式下會自動關閉漸層',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  _OpacitySlider(
                    label: '漸層透明度',
                    value: settings.homeBackgroundOpacity,
                    onChanged: settings.useAmoledDark &&
                            settings.themeMode != ThemeMode.light
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

          // ── 背景圖片（各頁面） ────────────────────────────
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
                    '每個頁面可以設定各自的背景圖片（支援 GIF），AMOLED 模式下會自動隱藏',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  _PerPageBackgroundSection(
                    paths: settings.pageBackgroundImagePaths,
                    opacities: settings.pageBackgroundImageOpacities,
                    isAmoled:
                        settings.useAmoledDark &&
                        settings.themeMode != ThemeMode.light,
                    onPathChanged: (pageKey, path) {
                      controller.updatePageBackgroundImagePath(pageKey, path);
                    },
                    onOpacityChanged: (pageKey, opacity) {
                      controller.updatePageBackgroundImageOpacity(pageKey, opacity);
                    },
                    onApplyToAll: (path, opacity) {
                      controller.applyBackgroundImageToAllPages(path, opacity);
                    },
                    onClearAll: () {
                      controller.clearAllBackgroundImages();
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
}

// ────────────────────────────────────────────────────────────────
// Seed color picker with presets + custom
// ────────────────────────────────────────────────────────────────

class _SeedColorPicker extends StatelessWidget {
  const _SeedColorPicker({
    required this.selectedColor,
    required this.presetColors,
    required this.enabled,
    required this.onColorSelected,
    required this.onClear,
  });

  final Color? selectedColor;
  final List<Color> presetColors;
  final bool enabled;
  final ValueChanged<Color> onColorSelected;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Column(
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                // "Default" chip – clears seed color
                _colorChip(
                  context,
                  color: null,
                  label: '預設',
                  selected: selectedColor == null,
                ),
                for (final c in presetColors)
                  _colorChip(
                    context,
                    color: c,
                    selected: selectedColor == c,
                  ),
                // Custom picker
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
        ),
      ),
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
    if (color == null) return '預設';
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
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
// Per-page background image section
// ────────────────────────────────────────────────────────────────

const _pageLabels = <String, String>{
  'bus': '公車',
  'metro': '捷運',
  'thsr': '高鐵',
  'tra': '火車',
  'youbike': 'YouBike',
};

const _pageIcons = <String, IconData>{
  'bus': Icons.directions_bus_outlined,
  'metro': Icons.subway_outlined,
  'thsr': Icons.train_outlined,
  'tra': Icons.directions_railway_outlined,
  'youbike': Icons.pedal_bike_outlined,
};

class _PerPageBackgroundSection extends StatelessWidget {
  const _PerPageBackgroundSection({
    required this.paths,
    required this.opacities,
    required this.isAmoled,
    required this.onPathChanged,
    required this.onOpacityChanged,
    required this.onApplyToAll,
    required this.onClearAll,
  });

  final Map<String, String> paths;
  final Map<String, double> opacities;
  final bool isAmoled;
  final void Function(String pageKey, String? path) onPathChanged;
  final void Function(String pageKey, double opacity) onOpacityChanged;
  final void Function(String path, double opacity) onApplyToAll;
  final VoidCallback onClearAll;

  Future<void> _pickImage(BuildContext context, String pageKey) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
    );
    if (image != null) {
      onPathChanged(pageKey, image.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Opacity(
      opacity: isAmoled ? 0.4 : 1.0,
      child: IgnorePointer(
        ignoring: isAmoled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // One-click apply all
            if (paths.isNotEmpty) ...[
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () {
                      // Use the first available image as source
                      final firstEntry = paths.entries.first;
                      final opacity = opacities[firstEntry.key] ?? 0.25;
                      onApplyToAll(firstEntry.value, opacity);
                    },
                    icon: const Icon(Icons.copy_all_rounded, size: 18),
                    label: const Text('一鍵套用全部'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: onClearAll,
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text('清除全部'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
            ],

            // Per-page rows
            for (final pageKey in _pageLabels.keys)
              _PageBackgroundRow(
                pageKey: pageKey,
                label: _pageLabels[pageKey]!,
                icon: _pageIcons[pageKey]!,
                imagePath: paths[pageKey],
                imageOpacity: opacities[pageKey] ?? 0.25,
                onPick: () => _pickImage(context, pageKey),
                onClear: () => onPathChanged(pageKey, null),
                onOpacityChanged: (v) => onOpacityChanged(pageKey, v),
                colorScheme: colorScheme,
              ),
          ],
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
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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

          // Preview
          if (hasImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.file(
                      File(imagePath!),
                      width: double.infinity,
                      fit: BoxFit.cover,
                      gaplessPlayback: isGif,
                      errorBuilder: (context, error, stackTrace) => Container(
                        height: 60,
                        color: colorScheme.errorContainer,
                        alignment: Alignment.center,
                        child: Text(
                          '無法載入圖片',
                          style: TextStyle(color: colorScheme.onErrorContainer),
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      height: 120,
                      color: Theme.of(context)
                          .scaffoldBackgroundColor
                          .withValues(alpha: 1.0 - imageOpacity),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Action buttons
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: onPick,
                icon: Icon(hasImage ? Icons.swap_horiz : Icons.add_photo_alternate_outlined, size: 18),
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
              label: '透明度',
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
