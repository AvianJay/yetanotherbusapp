import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Bus and user-location markers shared by the route sheet and the city map.
///
/// Google Maps takes bitmaps rather than widgets, so every marker exists twice:
/// as a Flutter widget for `flutter_map`, and as a rasterised PNG for the
/// platform view. Lifted verbatim from `route_bus_map_sheet.dart`.

class BusMapBusMarker extends StatelessWidget {
  const BusMapBusMarker({
    super.key,
    required this.color,
    required this.selected,
    required this.label,
  });

  final Color color;
  final bool selected;
  final String label;

  @override
  Widget build(BuildContext context) {
    final foreground = color.computeLuminance() > 0.45
        ? Colors.black87
        : Colors.white;
    return AnimatedScale(
      scale: selected ? 1.08 : 1,
      duration: const Duration(milliseconds: 180),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: selected ? 3 : 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Tooltip(
          message: label,
          child: Icon(
            Icons.directions_bus_rounded,
            color: foreground,
            size: selected ? 24 : 20,
          ),
        ),
      ),
    );
  }
}

class BusMapUserLocationMarker extends StatelessWidget {
  const BusMapUserLocationMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1E88E5),
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
    );
  }
}

class GoogleBusIconRequest {
  const GoogleBusIconRequest({
    required this.key,
    required this.color,
    required this.selected,
    required this.pixelRatio,
  });

  final String key;
  final Color color;
  final bool selected;
  final double pixelRatio;

  double get logicalSize => selected ? 48 : 40;

  double get radius => selected ? 20 : 17;

  double get borderWidth => selected ? 3 : 2;

  double get iconSize => selected ? 24 : 20;
}

class GoogleUserLocationIconRequest {
  const GoogleUserLocationIconRequest({required this.pixelRatio});

  static const double baseLogicalSize = 24;

  final double pixelRatio;

  double get logicalSize => baseLogicalSize;

  double get outerRadius => 10;

  double get innerRadius => 7.2;
}

String googleBusIconKey({
  required Color color,
  required bool selected,
  required double pixelRatio,
}) {
  return [
    color.toARGB32().toRadixString(16),
    selected ? 'selected' : 'normal',
    pixelRatio.toStringAsFixed(2),
  ].join('|');
}

Future<Uint8List> drawGoogleBusIcon(GoogleBusIconRequest request) async {
  final pixelSize = (request.logicalSize * request.pixelRatio).ceil();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..scale(request.pixelRatio, request.pixelRatio);
  final center = ui.Offset(request.logicalSize / 2, request.logicalSize / 2);
  final foreground = request.color.computeLuminance() > 0.45
      ? Colors.black87
      : Colors.white;

  canvas.drawCircle(
    center.translate(0, 1.5),
    request.radius,
    ui.Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3),
  );
  canvas.drawCircle(center, request.radius, ui.Paint()..color = request.color);
  canvas.drawCircle(
    center,
    request.radius,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = request.borderWidth
      ..color = Colors.white,
  );

  final busIconPainter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(Icons.directions_bus_rounded.codePoint),
      style: TextStyle(
        fontFamily: Icons.directions_bus_rounded.fontFamily,
        package: Icons.directions_bus_rounded.fontPackage,
        fontSize: request.iconSize,
        color: foreground,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  busIconPainter.paint(
    canvas,
    center - ui.Offset(busIconPainter.width / 2, busIconPainter.height / 2),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(pixelSize, pixelSize);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return byteData!.buffer.asUint8List();
}

Future<Uint8List> drawGoogleUserLocationIcon(double pixelRatio) async {
  final request = GoogleUserLocationIconRequest(pixelRatio: pixelRatio);
  final pixelSize = (request.logicalSize * pixelRatio).ceil();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(pixelRatio, pixelRatio);
  final center = ui.Offset(request.logicalSize / 2, request.logicalSize / 2);

  canvas.drawCircle(
    center,
    request.outerRadius,
    ui.Paint()..color = const Color(0x331E88E5),
  );
  canvas.drawCircle(
    center.translate(0, 1.5),
    request.innerRadius,
    ui.Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3),
  );
  canvas.drawCircle(
    center,
    request.innerRadius,
    ui.Paint()..color = const Color(0xFF1E88E5),
  );
  canvas.drawCircle(
    center,
    request.innerRadius,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.white,
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(pixelSize, pixelSize);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return byteData!.buffer.asUint8List();
}

/// A count bubble standing in for several buses at low zoom.
class BusMapClusterMarker extends StatelessWidget {
  const BusMapClusterMarker({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '此處 $count 輛公車，點一下放大',
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          shape: BoxShape.circle,
          border: Border.all(color: colorScheme.surface, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          clusterCountLabel(count),
          style: TextStyle(
            color: colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

/// Keeps the bubble readable, and the Google bitmap cache bounded.
String clusterCountLabel(int count) => count > 99 ? '99+' : '$count';

/// How wide a cluster bubble is for a given count.
double clusterMarkerSize(int count) {
  if (count >= 50) {
    return 52;
  }
  if (count >= 10) {
    return 44;
  }
  return 36;
}

String googleClusterIconKey({required int count, required double pixelRatio}) {
  return [clusterCountLabel(count), pixelRatio.toStringAsFixed(2)].join('|');
}

/// The same bubble, rasterised for the Google Maps platform view.
Future<Uint8List> drawGoogleClusterIcon({
  required int count,
  required double pixelRatio,
  required Color background,
  required Color foreground,
  required Color border,
}) async {
  final logicalSize = clusterMarkerSize(count);
  final pixelSize = (logicalSize * pixelRatio).ceil();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(pixelRatio, pixelRatio);
  final center = ui.Offset(logicalSize / 2, logicalSize / 2);
  final radius = logicalSize / 2 - 2;

  canvas.drawCircle(
    center.translate(0, 1.5),
    radius,
    ui.Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3),
  );
  canvas.drawCircle(center, radius, ui.Paint()..color = background);
  canvas.drawCircle(
    center,
    radius,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = border,
  );

  final painter = TextPainter(
    text: TextSpan(
      text: clusterCountLabel(count),
      style: TextStyle(
        color: foreground,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(
    canvas,
    center - ui.Offset(painter.width / 2, painter.height / 2),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(pixelSize, pixelSize);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return byteData!.buffer.asUint8List();
}
