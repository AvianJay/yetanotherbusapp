import 'dart:async';

import 'package:flutter/material.dart';

import '../core/haptic_feedback_service.dart';

/// A compact, route-oriented keypad used by the mobile search screen.
///
/// The keypad edits [controller] directly so insertions and deletions respect
/// the field's current selection. Programmatic edits are reported through
/// [onChanged] because [TextField.onChanged] is not called for controller
/// updates.
class RouteSearchKeypad extends StatelessWidget {
  const RouteSearchKeypad({
    required this.controller,
    required this.onChanged,
    required this.onRequestTextInput,
    required this.onCollapse,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onRequestTextInput;
  final VoidCallback onCollapse;

  static const List<_RouteShortcutKey> _shortcutKeys = <_RouteShortcutKey>[
    _RouteShortcutKey.prefix('紅', Color(0xFFD84A4A)),
    _RouteShortcutKey.prefix('藍', Color(0xFF3975C6)),
    _RouteShortcutKey.prefix('綠', Color(0xFF3D8B57)),
    _RouteShortcutKey.prefix('棕', Color(0xFF8D6E63)),
    _RouteShortcutKey.prefix('橘', Color(0xFFE2762D)),
    _RouteShortcutKey.prefix('黃', Color(0xFFC69216)),
    _RouteShortcutKey.keyword('幹線', Color(0xFF7357B5)),
    _RouteShortcutKey.keyword('先導', Color(0xFF7357B5)),
    _RouteShortcutKey.prefix('市民', Color(0xFF3975C6)),
    _RouteShortcutKey.keyword('跳蛙', Color(0xFF3D8B57)),
    _RouteShortcutKey.prefix('F', Color(0xFF3975C6)),
    _RouteShortcutKey.prefix('內科', Color(0xFF3975C6)),
    _RouteShortcutKey.prefix('南軟', Color(0xFF3975C6)),
    _RouteShortcutKey.suffix('夜間', '夜', Color(0xFF4F5B93)),
    _RouteShortcutKey.prefix('R', Color(0xFFD84A4A)),
    _RouteShortcutKey.prefix('貓空', Color(0xFF8D6E63)),
    _RouteShortcutKey.prefix('小', Color(0xFFE2762D)),
    _RouteShortcutKey.category('其他', '特', Color(0xFF6F7178)),
    _RouteShortcutKey.prefix('T', Color(0xFF3975C6)),
  ];

  static const List<String> _digitKeys = <String>[
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
  ];

  TextSelection _normalizedSelection(String text) {
    final selection = controller.selection;
    if (!selection.isValid ||
        selection.start > text.length ||
        selection.end > text.length) {
      return TextSelection.collapsed(offset: text.length);
    }
    return selection;
  }

  void _commitEditingValue(TextEditingValue value) {
    if (value == controller.value) {
      return;
    }
    controller.value = value;
    onChanged(value.text);
  }

  void _insertAtSelection(String value) {
    unawaited(AppHaptics.selectionClick());
    final currentValue = controller.value;
    final currentText = currentValue.text;
    final selection = _normalizedSelection(currentText);
    final start = selection.start;
    final end = selection.end;
    final nextText = currentText.replaceRange(start, end, value);
    _commitEditingValue(
      currentValue.copyWith(
        text: nextText,
        selection: TextSelection.collapsed(offset: start + value.length),
        composing: TextRange.empty,
      ),
    );
  }

  void _selectPrefix(String value) {
    unawaited(AppHaptics.selectionClick());
    final currentValue = controller.value;
    final currentText = currentValue.text;
    final selection = _normalizedSelection(currentText);
    final oldPrefixLength = _leadingPrefixLength(currentText);
    final nextText = value + currentText.substring(oldPrefixLength);

    int remapOffset(int offset) {
      if (oldPrefixLength == 0) {
        return offset + value.length;
      }
      if (offset <= oldPrefixLength) {
        return value.length;
      }
      return offset - oldPrefixLength + value.length;
    }

    _commitEditingValue(
      currentValue.copyWith(
        text: nextText,
        selection: TextSelection(
          baseOffset: remapOffset(selection.baseOffset),
          extentOffset: remapOffset(selection.extentOffset),
          affinity: selection.affinity,
          isDirectional: selection.isDirectional,
        ),
        composing: TextRange.empty,
      ),
    );
  }

  void _selectSuffix(String value) {
    unawaited(AppHaptics.selectionClick());
    final currentValue = controller.value;
    if (currentValue.text.endsWith(value)) {
      return;
    }
    final nextText = '${currentValue.text}$value';
    _commitEditingValue(
      currentValue.copyWith(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
        composing: TextRange.empty,
      ),
    );
  }

  void _replaceQuery(String value) {
    unawaited(AppHaptics.selectionClick());
    final currentValue = controller.value;
    _commitEditingValue(
      currentValue.copyWith(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
        composing: TextRange.empty,
      ),
    );
  }

  void _selectShortcut(_RouteShortcutKey key) {
    switch (key.action) {
      case _RouteShortcutAction.prefix:
        _selectPrefix(key.data);
      case _RouteShortcutAction.suffix:
        _selectSuffix(key.data);
      case _RouteShortcutAction.keyword:
      case _RouteShortcutAction.category:
        _replaceQuery(key.data);
    }
  }

  int _leadingPrefixLength(String text) {
    var offset = 0;
    while (offset < text.length) {
      String? matchedPrefix;
      for (final key in _shortcutKeys) {
        if (key.action == _RouteShortcutAction.prefix &&
            text.startsWith(key.data, offset)) {
          matchedPrefix = key.data;
          break;
        }
      }
      if (matchedPrefix == null) {
        break;
      }
      offset += matchedPrefix.length;
    }
    return offset;
  }

  void _backspace() {
    unawaited(AppHaptics.selectionClick());
    final currentValue = controller.value;
    final currentText = currentValue.text;
    final selection = _normalizedSelection(currentText);
    final start = selection.start;
    final end = selection.end;

    if (start != end) {
      _commitEditingValue(
        currentValue.copyWith(
          text: currentText.replaceRange(start, end, ''),
          selection: TextSelection.collapsed(offset: start),
          composing: TextRange.empty,
        ),
      );
      return;
    }
    if (start == 0) {
      return;
    }

    final previousCharacter = currentText.substring(0, start).characters.last;
    final deleteStart = start - previousCharacter.length;
    _commitEditingValue(
      currentValue.copyWith(
        text: currentText.replaceRange(deleteStart, start, ''),
        selection: TextSelection.collapsed(offset: deleteStart),
        composing: TextRange.empty,
      ),
    );
  }

  void _requestTextInput() {
    unawaited(AppHaptics.selectionClick());
    onRequestTextInput();
  }

  void _collapse() {
    unawaited(AppHaptics.selectionClick());
    onCollapse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final surfaceColor =
        theme.bottomAppBarTheme.color ?? colorScheme.surfaceContainer;

    return Material(
      key: const ValueKey<String>('route-search-keypad'),
      color: surfaceColor,
      elevation: 3,
      surfaceTintColor: colorScheme.surfaceTint,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('路線字首與號碼', style: theme.textTheme.titleSmall),
                  ),
                  IconButton(
                    key: const ValueKey<String>('route-keypad-collapse'),
                    tooltip: '收合快捷鍵盤',
                    onPressed: _collapse,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isLandscape =
                      MediaQuery.orientationOf(context) ==
                          Orientation.landscape &&
                      constraints.maxWidth >= 520;
                  final prefixRail = _PrefixRail(
                    keys: _shortcutKeys,
                    onPressed: _selectShortcut,
                  );
                  final numberGrid = _NumberGrid(
                    digits: _digitKeys,
                    onDigitPressed: _insertAtSelection,
                    onTextInputPressed: _requestTextInput,
                    onBackspacePressed: _backspace,
                  );

                  if (isLandscape) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: prefixRail),
                        const SizedBox(width: 12),
                        Expanded(child: numberGrid),
                      ],
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      prefixRail,
                      const SizedBox(height: 12),
                      numberGrid,
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrefixRail extends StatelessWidget {
  const _PrefixRail({required this.keys, required this.onPressed});

  final List<_RouteShortcutKey> keys;
  final ValueChanged<_RouteShortcutKey> onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      key: const ValueKey<String>('route-keypad-prefix-scroll'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < keys.length; index += 1) ...[
            if (index > 0) const SizedBox(width: 8),
            FilledButton.tonal(
              key: ValueKey<String>('route-keypad-prefix-${keys[index].label}'),
              onPressed: () => onPressed(keys[index]),
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                foregroundColor: colorScheme.onSurface,
                backgroundColor: colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: keys[index].color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colorScheme.outline.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(keys[index].label, maxLines: 1),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NumberGrid extends StatelessWidget {
  const _NumberGrid({
    required this.digits,
    required this.onDigitPressed,
    required this.onTextInputPressed,
    required this.onBackspacePressed,
  });

  final List<String> digits;
  final ValueChanged<String> onDigitPressed;
  final VoidCallback onTextInputPressed;
  final VoidCallback onBackspacePressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final keyStyle = FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      foregroundColor: colorScheme.onSurface,
      backgroundColor: colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: Theme.of(context).textTheme.titleMedium,
    );
    final children = <Widget>[
      for (final digit in digits)
        FilledButton.tonal(
          key: ValueKey<String>('route-keypad-digit-$digit'),
          onPressed: () => onDigitPressed(digit),
          style: keyStyle,
          child: Text(digit),
        ),
      Tooltip(
        message: '切換文字鍵盤',
        child: FilledButton.tonal(
          key: const ValueKey<String>('route-keypad-text'),
          onPressed: onTextInputPressed,
          style: keyStyle,
          child: const Icon(Icons.keyboard_rounded),
        ),
      ),
      FilledButton.tonal(
        key: const ValueKey<String>('route-keypad-digit-0'),
        onPressed: () => onDigitPressed('0'),
        style: keyStyle,
        child: const Text('0'),
      ),
      Tooltip(
        message: '退格',
        child: FilledButton.tonal(
          key: const ValueKey<String>('route-keypad-backspace'),
          onPressed: onBackspacePressed,
          style: keyStyle,
          child: const Icon(Icons.backspace_outlined),
        ),
      ),
    ];

    return GridView.count(
      shrinkWrap: true,
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      mainAxisExtent: 48,
      children: children,
    );
  }
}

enum _RouteShortcutAction { prefix, suffix, keyword, category }

class _RouteShortcutKey {
  const _RouteShortcutKey.prefix(this.label, this.color)
    : data = label,
      action = _RouteShortcutAction.prefix;

  const _RouteShortcutKey.suffix(this.label, this.data, this.color)
    : action = _RouteShortcutAction.suffix;

  const _RouteShortcutKey.keyword(this.label, this.color)
    : data = label,
      action = _RouteShortcutAction.keyword;

  const _RouteShortcutKey.category(this.label, this.data, this.color)
    : action = _RouteShortcutAction.category;

  final String label;
  final String data;
  final Color color;
  final _RouteShortcutAction action;
}
