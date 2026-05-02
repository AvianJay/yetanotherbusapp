import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'settings_screen.dart';

const _settingsDialogBreakpoint = 1100.0;
const _settingsDialogMaxWidth = 780.0;
const _settingsDialogMaxHeight = 920.0;

Future<void> openAdaptiveSettingsScreen(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  if (size.width < _settingsDialogBreakpoint) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'settings'),
        builder: (_) => const SettingsScreen(),
      ),
    );
  }

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final dialogSize = MediaQuery.sizeOf(dialogContext);
      return Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: math.min(dialogSize.width - 48, _settingsDialogMaxWidth),
          height: math.min(dialogSize.height - 48, _settingsDialogMaxHeight),
          child: const SettingsScreen(),
        ),
      );
    },
  );
}
