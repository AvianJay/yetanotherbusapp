import 'dart:io';

import 'package:flutter/material.dart';

import '../app/bus_app.dart';

/// A wrapper that paints a user-selected background image behind its child,
/// with configurable opacity. Supports static images and animated GIFs.
///
/// Provide a [pageKey] that corresponds to the key used in
/// `AppSettings.pageBackgroundImagePaths` (e.g. 'bus', 'search', 'favorites').
///
/// When no background image is set for the given page (or AMOLED is active),
/// this widget just returns [child] unchanged.
///
/// If [pageKey] is null, the wrapper tries the 'bus' (main/home) key as fallback.
class BackgroundImageWrapper extends StatelessWidget {
  const BackgroundImageWrapper({
    this.pageKey,
    required this.child,
    super.key,
  });

  /// Key matching `AppSettings.pageBackgroundImagePaths`, e.g. 'bus'.
  /// If null, falls back to the first available background image.
  final String? pageKey;

  /// The content to render above the background image.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final settings = controller.settings;
    final theme = Theme.of(context);

    // AMOLED mode: hide background image to preserve pure black
    final isAmoled = settings.useAmoledDark &&
        settings.themeMode != ThemeMode.light;

    if (isAmoled) return child;

    // Resolve path: specific pageKey → fallback to first available
    final paths = settings.pageBackgroundImagePaths;
    final opacities = settings.pageBackgroundImageOpacities;
    String? path;
    double opacity;

    if (pageKey != null && paths[pageKey!] != null) {
      path = paths[pageKey!];
      opacity = opacities[pageKey!] ?? 0.25;
    } else if (pageKey != null && paths.isNotEmpty) {
      // No image for this specific page → fall back to 'bus' (home) key
      if (paths.containsKey('bus')) {
        path = paths['bus'];
        opacity = opacities['bus'] ?? 0.25;
      } else {
        return child;
      }
    } else if (paths.isNotEmpty) {
      // No pageKey specified → use first available
      final first = paths.entries.first;
      path = first.value;
      opacity = opacities[first.key] ?? 0.25;
    } else {
      return child;
    }

    if (path == null || path.isEmpty) return child;

    final file = File(path);
    final isGif = path.toLowerCase().endsWith('.gif');

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: theme.scaffoldBackgroundColor),
        // Keep opacity on the image itself so we do not add a full-screen
        // composited layer that can briefly read as a dark scrim while the
        // file image is resolving.
        Image.file(
          file,
          fit: BoxFit.cover,
          gaplessPlayback: isGif,
          opacity: AlwaysStoppedAnimation(opacity.clamp(0.0, 1.0)),
          errorBuilder: (context, error, stackTrace) =>
              const SizedBox.shrink(),
        ),
        // Content on top — Cards/AppBar/BottomBar get their own
        // semi-transparent tint via overlayOpacity applied through
        // the theme in BusApp.
        child,
      ],
    );
  }
}
