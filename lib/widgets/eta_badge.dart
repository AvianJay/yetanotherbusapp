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
    final eta = buildEtaPresentation(
      stop,
      alwaysShowSeconds: alwaysShowSeconds,
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
