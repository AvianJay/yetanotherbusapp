import 'dart:io';

import 'package:flutter/material.dart';

import '../app/bus_app.dart';

/// A wrapper that paints a user-selected background image behind its child,
/// with configurable opacity. Supports static images and animated GIFs.
///
/// Provide a [pageKey] that corresponds to the key used in
/// `AppSettings.pageBackgroundImagePaths` (e.g. 'bus', 'metro').
///
/// When no background image is set for the given page (or AMOLED is active),
/// this widget just returns [child] unchanged.
class BackgroundImageWrapper extends StatelessWidget {
  const BackgroundImageWrapper({
    required this.pageKey,
    required this.child,
    super.key,
  });

  /// Key matching `AppSettings.pageBackgroundImagePaths`, e.g. 'bus'.
  final String pageKey;

  /// The content to render above the background image.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final settings = controller.settings;
    final path = settings.pageBackgroundImagePaths[pageKey];
    final opacity =
        settings.pageBackgroundImageOpacities[pageKey] ?? 0.25;

    // AMOLED mode: hide background image to preserve pure black
    final isAmoled = settings.useAmoledDark &&
        settings.themeMode != ThemeMode.light;

    // No image or AMOLED → just pass through
    if (path == null || path.isEmpty || isAmoled) return child;

    final file = File(path);
    final isGif = path.toLowerCase().endsWith('.gif');

    return Stack(
      fit: StackFit.expand,
      children: [
        // Background image with opacity
        Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Image.file(
            file,
            fit: BoxFit.cover,
            // GIF files animate automatically with Image.file
            gaplessPlayback: isGif,
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
