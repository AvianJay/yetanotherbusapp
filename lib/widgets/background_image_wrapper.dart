import 'dart:io';

import 'package:flutter/material.dart';

import '../app/bus_app.dart';

/// A wrapper that paints a user-selected background image behind its child,
/// with configurable opacity.
///
/// Usage: wrap the `body` of a Scaffold (or the whole Scaffold) with this
/// widget. When no background image is set, it just returns `child` unchanged.
class BackgroundImageWrapper extends StatelessWidget {
  const BackgroundImageWrapper({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final settings = controller.settings;
    final path = settings.backgroundImagePath;
    final opacity = settings.backgroundImageOpacity;

    // AMOLED mode: hide background image to preserve pure black
    final isAmoled = settings.useAmoledDark &&
        settings.themeMode != ThemeMode.light;

    // No image or AMOLED → just pass through
    if (path == null || path.isEmpty || isAmoled) return child;

    final file = File(path);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background image with opacity
        Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          ),
        ),
        // Content on top
        child,
      ],
    );
  }
}
