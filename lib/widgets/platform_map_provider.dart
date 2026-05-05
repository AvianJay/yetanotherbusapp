import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart' as latlong;

const double mapBoundsDefaultPadding = 28;

bool get useGoogleMapsProvider {
  if (kIsWeb) {
    return false;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };
}

gmaps.LatLng toGoogleLatLng(latlong.LatLng point) {
  return gmaps.LatLng(point.latitude, point.longitude);
}

latlong.LatLng fromGoogleLatLng(gmaps.LatLng point) {
  return latlong.LatLng(point.latitude, point.longitude);
}

gmaps.LatLngBounds googleBoundsFromLatLngs(Iterable<latlong.LatLng> points) {
  final iterator = points.iterator;
  if (!iterator.moveNext()) {
    const fallback = gmaps.LatLng(23.7, 121.0);
    return gmaps.LatLngBounds(southwest: fallback, northeast: fallback);
  }

  var south = iterator.current.latitude;
  var north = iterator.current.latitude;
  var west = iterator.current.longitude;
  var east = iterator.current.longitude;

  while (iterator.moveNext()) {
    final point = iterator.current;
    if (point.latitude < south) south = point.latitude;
    if (point.latitude > north) north = point.latitude;
    if (point.longitude < west) west = point.longitude;
    if (point.longitude > east) east = point.longitude;
  }

  return gmaps.LatLngBounds(
    southwest: gmaps.LatLng(
      south.clamp(-85.0, 85.0),
      west.clamp(-180.0, 180.0),
    ),
    northeast: gmaps.LatLng(
      north.clamp(-85.0, 85.0),
      east.clamp(-180.0, 180.0),
    ),
  );
}

double googleMarkerHueForColor(Color color) {
  return HSVColor.fromColor(color).hue;
}
