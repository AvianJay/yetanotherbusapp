import 'package:flutter/material.dart';

import '../core/models.dart';

class EtaBadge extends StatelessWidget {
  const EtaBadge({
    required this.stop,
    required this.alwaysShowSeconds,
    this.size = 58,
    super.key,
  });

  final StopInfo stop;
  final bool alwaysShowSeconds;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eta = buildEtaPresentation(
      stop,
      alwaysShowSeconds: alwaysShowSeconds,
      brightness: theme.brightness,
      colorScheme: theme.colorScheme,
    );
    final fontSize = size * 0.24;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: eta.backgroundColor,
        borderRadius: BorderRadius.circular(size * 0.31),
      ),
      child: Text(
        eta.text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: eta.foregroundColor,
          fontWeight: FontWeight.w700,
          fontSize: fontSize,
          height: 1.1,
        ),
      ),
    );
  }
}

/// A generic ETA badge that accepts seconds directly.
/// Useful for metro, rail, and other transit systems.
class GenericEtaBadge extends StatelessWidget {
  const GenericEtaBadge({
    required this.seconds,
    this.message,
    this.size = 58,
    super.key,
  });

  final int? seconds;
  final String? message;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eta = buildGenericEtaPresentation(
      seconds: seconds,
      message: message,
      brightness: theme.brightness,
      colorScheme: theme.colorScheme,
    );
    final fontSize = size * 0.24;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: eta.backgroundColor,
        borderRadius: BorderRadius.circular(size * 0.31),
      ),
      child: Text(
        eta.text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: eta.foregroundColor,
          fontWeight: FontWeight.w700,
          fontSize: fontSize,
          height: 1.1,
        ),
      ),
    );
  }
}

/// Build ETA presentation from raw seconds.
EtaPresentation buildGenericEtaPresentation({
  required int? seconds,
  String? message,
  Brightness brightness = Brightness.light,
  ColorScheme? colorScheme,
}) {
  final isDark = brightness == Brightness.dark;
  final cs = colorScheme;

  if (message != null && message.isNotEmpty) {
    return EtaPresentation(
      text: message,
      backgroundColor: cs?.primaryContainer ??
          (isDark ? const Color(0xFF16383D) : Colors.teal.shade50),
      foregroundColor: cs?.onPrimaryContainer ??
          (isDark ? const Color(0xFFBEECEF) : Colors.teal.shade900),
    );
  }

  if (seconds == null) {
    return EtaPresentation(
      text: '--',
      backgroundColor: cs?.surfaceContainerHighest ?? const Color(0xFF364152),
      foregroundColor: cs?.onSurfaceVariant ?? const Color(0xFFD8E2F1),
    );
  }

  if (seconds <= 0) {
    return EtaPresentation(
      text: '進站中',
      backgroundColor: Colors.red.shade800,
      foregroundColor: Colors.white,
    );
  }

  if (seconds < 60) {
    // For metro, show "即將到站" instead of exact seconds
    return EtaPresentation(
      text: '$seconds秒',
      backgroundColor: Colors.red.shade600,
      foregroundColor: Colors.white,
    );
  }

  final minutes = seconds ~/ 60;
  final urgent = minutes < 3;

  return EtaPresentation(
    text: '$minutes分',
    backgroundColor: urgent
        ? Colors.orange.shade700
        : (cs?.primary ??
            (isDark ? const Color(0xFF233A41) : const Color(0xFFE2F4F1))),
    foregroundColor: urgent
        ? Colors.white
        : (cs?.onSurface ??
            (isDark ? const Color(0xFFD7F1F3) : const Color(0xFF0D4E57))),
  );
}
