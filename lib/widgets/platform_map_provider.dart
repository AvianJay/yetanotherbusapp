import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart' as latlong;

const double mapBoundsDefaultPadding = 28;

bool get supportsGoogleMapsProvider {
  if (kIsWeb) {
    return false;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };
}

bool get useGoogleMapsRouteProvider => supportsGoogleMapsProvider;

bool get useGoogleMapsPointProvider => false;

String mapTileUrlTemplate(Brightness brightness) {
  if (brightness == Brightness.dark) {
    return 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
  }
  return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
}

List<String> mapTileSubdomains(Brightness brightness) {
  if (brightness == Brightness.dark) {
    return const <String>['a', 'b', 'c', 'd'];
  }
  return const <String>[];
}

Set<Factory<OneSequenceGestureRecognizer>> buildGoogleMapGestureRecognizers() {
  return <Factory<OneSequenceGestureRecognizer>>{
    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
  };
}

String googleMapStyleForBrightness(Brightness brightness) {
  if (brightness == Brightness.dark) {
    return _googleDarkMapStyle;
  }
  return '[]';
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

const String _googleDarkMapStyle = '''
[
  {
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#1f2733"
      }
    ]
  },
  {
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#9aa8b6"
      }
    ]
  },
  {
    "elementType": "labels.text.stroke",
    "stylers": [
      {
        "color": "#11161d"
      }
    ]
  },
  {
    "featureType": "administrative",
    "elementType": "geometry.stroke",
    "stylers": [
      {
        "color": "#33404c"
      }
    ]
  },
  {
    "featureType": "landscape.man_made",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#202b36"
      }
    ]
  },
  {
    "featureType": "landscape.natural",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#16202a"
      }
    ]
  },
  {
    "featureType": "poi",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#22303d"
      }
    ]
  },
  {
    "featureType": "poi",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#7f93a6"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#314150"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "geometry.stroke",
    "stylers": [
      {
        "color": "#1c2630"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#bdc8d3"
      }
    ]
  },
  {
    "featureType": "transit",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#263544"
      }
    ]
  },
  {
    "featureType": "transit.station",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#c2ccd6"
      }
    ]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#0f1a24"
      }
    ]
  },
  {
    "featureType": "water",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#5f7487"
      }
    ]
  }
]
''';
