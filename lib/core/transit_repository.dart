import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Lightweight repository for non-bus transit data (Metro, THSR, TRA, Bike).
/// All data comes from the API server — no local SQLite database needed.
class TransitRepository {
  TransitRepository({http.Client? client})
      : _client = client ?? http.Client();

  static const _apiBaseUrl = 'https://bus.avianjay.sbs';
  static const _headers = <String, String>{
    'Accept': 'application/json',
    'Accept-Encoding': 'gzip',
    'User-Agent': 'Mozilla/5.0 (YABus Flutter)',
  };

  final http.Client _client;

  // ── In-memory cache ─────────────────────────────────────────────────────

  final Map<String, _TimedValue<Object>> _cache = {};
  final Map<String, Future<Object>> _inFlight = {};

  Future<T> _cached<T extends Object>(
    String key,
    Duration ttl,
    Future<T> Function() fetcher,
  ) async {
    final existing = _cache[key];
    if (existing != null && !existing.isExpired(ttl)) {
      return existing.value as T;
    }

    // De-duplicate in-flight requests.
    if (_inFlight.containsKey(key)) {
      return await _inFlight[key]! as T;
    }

    final future = fetcher();
    _inFlight[key] = future;
    try {
      final result = await future;
      _cache[key] = _TimedValue(result);
      return result;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<List<dynamic>> _getJsonList(String path) async {
    final uri = Uri.parse('$_apiBaseUrl$path');
    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('API error ${response.statusCode}: ${response.body}');
    }
    final decoded = json.decode(response.body);
    return decoded is List ? decoded : [];
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Metro
  // ══════════════════════════════════════════════════════════════════════════

  static const _metroStaticTtl = Duration(hours: 1);
  static const _metroLiveTtl = Duration(seconds: 10);

  Future<List<MetroSystem>> getMetroSystems() async {
    return _cached('metro_systems', _metroStaticTtl, () async {
      final data = await _getJsonList('/api/v1/metro/systems');
      return data.map((e) => MetroSystem.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  Future<List<MetroLine>> getMetroLines(String system) async {
    return _cached('metro_lines_$system', _metroStaticTtl, () async {
      final data = await _getJsonList('/api/v1/metro/$system/lines');
      return data.map((e) => MetroLine.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  Future<List<MetroStation>> getMetroStations(String system) async {
    return _cached('metro_stations_$system', _metroStaticTtl, () async {
      final data = await _getJsonList('/api/v1/metro/$system/stations');
      return data.map((e) => MetroStation.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  Future<List<MetroStationOfLine>> getMetroStationOfLine(String system) async {
    return _cached('metro_sol_$system', _metroStaticTtl, () async {
      final data = await _getJsonList('/api/v1/metro/$system/station-of-line');
      return data.map((e) => MetroStationOfLine.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  Future<List<MetroLiveBoardEntry>> getMetroLiveBoard(
    String system,
    String lineId,
  ) async {
    return _cached('metro_live_${system}_$lineId', _metroLiveTtl, () async {
      final data = await _getJsonList('/api/v1/metro/$system/lines/$lineId/liveboard');
      return data.map((e) => MetroLiveBoardEntry.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  Future<List<MetroFrequencyInfo>> getMetroFrequency(String system) async {
    return _cached('metro_freq_$system', _metroStaticTtl, () async {
      final data = await _getJsonList('/api/v1/metro/$system/frequency');
      return data.map((e) => MetroFrequencyInfo.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  THSR
  // ══════════════════════════════════════════════════════════════════════════

  static const _thsrStaticTtl = Duration(hours: 1);
  static const _thsrTimetableTtl = Duration(minutes: 5);
  static const _thsrSeatsTtl = Duration(seconds: 30);

  Future<List<RailStation>> getThsrStations() async {
    return _cached('thsr_stations', _thsrStaticTtl, () async {
      final data = await _getJsonList('/api/v1/thsr/stations');
      return data.map((e) => RailStation.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  Future<List<ThsrOdTrain>> getThsrOdTimetable({
    required String origin,
    required String dest,
    String date = '',
  }) async {
    final dateParam = date.isNotEmpty ? '&date=$date' : '';
    final key = 'thsr_od_${origin}_${dest}_$date';
    return _cached(key, _thsrTimetableTtl, () async {
      final data = await _getJsonList(
        '/api/v1/thsr/timetable/od?origin=$origin&dest=$dest$dateParam',
      );
      return data.map((e) => ThsrOdTrain.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  Future<List<ThsrSeatInfo>> getThsrSeats(String stationId) async {
    return _cached('thsr_seats_$stationId', _thsrSeatsTtl, () async {
      final data = await _getJsonList('/api/v1/thsr/seats/$stationId');
      return data.map((e) => ThsrSeatInfo.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  Future<List<RailAlert>> getThsrAlerts() async {
    return _cached('thsr_alerts', const Duration(minutes: 5), () async {
      final data = await _getJsonList('/api/v1/thsr/alerts');
      return data.map((e) => RailAlert.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  TRA
  // ══════════════════════════════════════════════════════════════════════════

  static const _traStaticTtl = Duration(hours: 1);
  static const _traLiveTtl = Duration(seconds: 10);

  Future<List<RailStation>> getTraStations() async {
    return _cached('tra_stations', _traStaticTtl, () async {
      final data = await _getJsonList('/api/v1/tra/stations');
      return data.map((e) => RailStation.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  Future<List<TraOdTrain>> getTraOdTimetable({
    required String origin,
    required String dest,
    String date = '',
  }) async {
    final dateParam = date.isNotEmpty ? '&date=$date' : '';
    final key = 'tra_od_${origin}_${dest}_$date';
    return _cached(key, const Duration(minutes: 5), () async {
      final data = await _getJsonList(
        '/api/v1/tra/timetable/od?origin=$origin&dest=$dest$dateParam',
      );
      return data.map((e) => TraOdTrain.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  Future<List<TraLiveBoardEntry>> getTraLiveBoard(String stationId) async {
    return _cached('tra_live_$stationId', _traLiveTtl, () async {
      final data = await _getJsonList('/api/v1/tra/liveboard/$stationId');
      return data.map((e) => TraLiveBoardEntry.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  Future<List<RailAlert>> getTraAlerts() async {
    return _cached('tra_alerts', const Duration(minutes: 5), () async {
      final data = await _getJsonList('/api/v1/tra/alerts');
      return data.map((e) => RailAlert.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Bike (YouBike)
  // ══════════════════════════════════════════════════════════════════════════

  static const _bikeCitiesTtl = Duration(hours: 1);
  static const _bikeStationsTtl = Duration(seconds: 30);

  Future<List<BikeCity>> getBikeCities() async {
    return _cached('bike_cities', _bikeCitiesTtl, () async {
      final data = await _getJsonList('/api/v1/bike/cities');
      return data.map((e) => BikeCity.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  Future<List<BikeStation>> getBikeStations({
    required String city,
    double lat = 0,
    double lon = 0,
    int radius = 0,
  }) async {
    final key = 'bike_stations_${city}_${lat}_${lon}_$radius';
    return _cached(key, _bikeStationsTtl, () async {
      final params = <String>['city=$city'];
      if (lat != 0 || lon != 0) {
        params.addAll(['lat=$lat', 'lon=$lon']);
      }
      if (radius > 0) {
        params.add('radius=$radius');
      }
      final data = await _getJsonList('/api/v1/bike/stations?${params.join('&')}');
      return data.map((e) => BikeStation.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  Future<List<BikeStation>> getBikeNearby({
    required double lat,
    required double lon,
    int radius = 500,
  }) async {
    final key = 'bike_nearby_${lat}_${lon}_$radius';
    return _cached(key, _bikeStationsTtl, () async {
      final data = await _getJsonList(
        '/api/v1/bike/nearby?lat=$lat&lon=$lon&radius=$radius',
      );
      return data.map((e) => BikeStation.fromJson(e as Map<String, dynamic>)).toList();
    });
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Models
// ══════════════════════════════════════════════════════════════════════════════

class _TimedValue<T> {
  _TimedValue(this.value) : _createdAt = DateTime.now();

  final T value;
  final DateTime _createdAt;

  bool isExpired(Duration ttl) =>
      DateTime.now().difference(_createdAt) > ttl;
}

// ── Metro ──

class MetroSystem {
  const MetroSystem({
    required this.system,
    required this.city,
    required this.name,
    required this.nameEn,
  });

  factory MetroSystem.fromJson(Map<String, dynamic> json) => MetroSystem(
        system: json['system'] as String? ?? '',
        city: json['city'] as String? ?? '',
        name: json['name'] as String? ?? '',
        nameEn: json['name_en'] as String? ?? '',
      );

  final String system;
  final String city;
  final String name;
  final String nameEn;
}

class MetroLine {
  const MetroLine({
    required this.lineId,
    required this.lineNo,
    required this.name,
    required this.nameEn,
    required this.color,
  });

  factory MetroLine.fromJson(Map<String, dynamic> json) => MetroLine(
        lineId: json['line_id'] as String? ?? '',
        lineNo: json['line_no'] as String? ?? '',
        name: json['name'] as String? ?? '',
        nameEn: json['name_en'] as String? ?? '',
        color: json['color'] as String? ?? '',
      );

  final String lineId;
  final String lineNo;
  final String name;
  final String nameEn;
  final String color;
}

class MetroStation {
  const MetroStation({
    required this.stationId,
    required this.name,
    required this.nameEn,
    required this.lineId,
    required this.lat,
    required this.lon,
  });

  factory MetroStation.fromJson(Map<String, dynamic> json) => MetroStation(
        stationId: json['station_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        nameEn: json['name_en'] as String? ?? '',
        lineId: json['line_id'] as String? ?? '',
        lat: (json['lat'] as num?)?.toDouble() ?? 0,
        lon: (json['lon'] as num?)?.toDouble() ?? 0,
      );

  final String stationId;
  final String name;
  final String nameEn;
  final String lineId;
  final double lat;
  final double lon;
}

class MetroStationOfLine {
  const MetroStationOfLine({
    required this.lineId,
    required this.direction,
    required this.stations,
  });

  factory MetroStationOfLine.fromJson(Map<String, dynamic> json) {
    final rawStations = json['stations'] as List<dynamic>? ?? [];
    return MetroStationOfLine(
      lineId: json['line_id'] as String? ?? '',
      direction: (json['direction'] as num?)?.toInt() ?? 0,
      stations: rawStations
          .map((e) => MetroStationSequence.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final String lineId;
  final int direction;
  final List<MetroStationSequence> stations;
}

class MetroStationSequence {
  const MetroStationSequence({
    required this.stationId,
    required this.name,
    required this.nameEn,
    required this.sequence,
  });

  factory MetroStationSequence.fromJson(Map<String, dynamic> json) =>
      MetroStationSequence(
        stationId: json['station_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        nameEn: json['name_en'] as String? ?? '',
        sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      );

  final String stationId;
  final String name;
  final String nameEn;
  final int sequence;
}

class MetroLiveBoardEntry {
  const MetroLiveBoardEntry({
    required this.stationId,
    required this.stationName,
    required this.lineId,
    required this.destinationId,
    required this.destinationName,
    required this.direction,
    required this.tripHeadSign,
    required this.estimatedTime,
    required this.serviceStatus,
  });

  factory MetroLiveBoardEntry.fromJson(Map<String, dynamic> json) =>
      MetroLiveBoardEntry(
        stationId: json['station_id'] as String? ?? '',
        stationName: json['station_name'] as String? ?? '',
        lineId: json['line_id'] as String? ?? '',
        destinationId: json['destination_id'] as String? ?? '',
        destinationName: json['destination_name'] as String? ?? '',
        direction: (json['direction'] as num?)?.toInt() ?? 0,
        tripHeadSign: json['trip_head_sign'] as String? ?? '',
        estimatedTime: (json['estimated_time'] as num?)?.toInt(),
        serviceStatus: (json['service_status'] as num?)?.toInt() ?? 0,
      );

  final String stationId;
  final String stationName;
  final String lineId;
  final String destinationId;
  final String destinationName;
  final int direction;
  final String tripHeadSign;
  final int? estimatedTime; // seconds
  final int serviceStatus;
}

class MetroFrequencyInfo {
  const MetroFrequencyInfo({
    required this.lineId,
    required this.routeId,
    required this.serviceDay,
    required this.headways,
  });

  factory MetroFrequencyInfo.fromJson(Map<String, dynamic> json) {
    final rawHw = json['headways'] as List<dynamic>? ?? [];
    return MetroFrequencyInfo(
      lineId: json['line_id'] as String? ?? '',
      routeId: json['route_id'] as String? ?? '',
      serviceDay: json['service_day'] as Map<String, dynamic>? ?? {},
      headways: rawHw
          .map((e) => MetroHeadway.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final String lineId;
  final String routeId;
  final Map<String, dynamic> serviceDay;
  final List<MetroHeadway> headways;
}

class MetroHeadway {
  const MetroHeadway({
    required this.peakFlag,
    required this.startTime,
    required this.endTime,
    required this.minHeadway,
    required this.maxHeadway,
  });

  factory MetroHeadway.fromJson(Map<String, dynamic> json) => MetroHeadway(
        peakFlag: json['peak_flag'] as String? ?? '',
        startTime: json['start_time'] as String? ?? '',
        endTime: json['end_time'] as String? ?? '',
        minHeadway: (json['min_headway'] as num?)?.toInt() ?? 0,
        maxHeadway: (json['max_headway'] as num?)?.toInt() ?? 0,
      );

  final String peakFlag;
  final String startTime;
  final String endTime;
  final int minHeadway;
  final int maxHeadway;
}

// ── Shared Rail ──

class RailStation {
  const RailStation({
    required this.stationId,
    required this.name,
    required this.nameEn,
    required this.stationClass,
    required this.lat,
    required this.lon,
  });

  factory RailStation.fromJson(Map<String, dynamic> json) => RailStation(
        stationId: json['station_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        nameEn: json['name_en'] as String? ?? '',
        stationClass: json['station_class'] as String? ?? '',
        lat: (json['lat'] as num?)?.toDouble() ?? 0,
        lon: (json['lon'] as num?)?.toDouble() ?? 0,
      );

  final String stationId;
  final String name;
  final String nameEn;
  final String stationClass;
  final double lat;
  final double lon;
}

class RailAlert {
  const RailAlert({
    required this.alertId,
    required this.title,
    required this.description,
    required this.status,
    required this.publishTime,
    required this.startTime,
    required this.endTime,
  });

  factory RailAlert.fromJson(Map<String, dynamic> json) => RailAlert(
        alertId: json['alert_id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        status: json['status'] is num
            ? (json['status'] as num).toInt()
            : int.tryParse('${json['status']}') ?? 0,
        publishTime: json['publish_time'] as String? ?? '',
        startTime: json['start_time'] as String? ?? '',
        endTime: json['end_time'] as String? ?? '',
      );

  final String alertId;
  final String title;
  final String description;
  final int status;
  final String publishTime;
  final String startTime;
  final String endTime;
}

// ── THSR ──

class ThsrOdTrain {
  const ThsrOdTrain({
    required this.trainNo,
    required this.direction,
    required this.startStation,
    required this.endStation,
    required this.originDeparture,
    required this.destArrival,
  });

  factory ThsrOdTrain.fromJson(Map<String, dynamic> json) => ThsrOdTrain(
        trainNo: json['train_no'] as String? ?? '',
        direction: (json['direction'] as num?)?.toInt() ?? 0,
        startStation: json['start_station'] as String? ?? '',
        endStation: json['end_station'] as String? ?? '',
        originDeparture: json['origin_departure'] as String? ?? '',
        destArrival: json['dest_arrival'] as String? ?? '',
      );

  final String trainNo;
  final int direction;
  final String startStation;
  final String endStation;
  final String originDeparture;
  final String destArrival;
}

class ThsrSeatInfo {
  const ThsrSeatInfo({
    required this.trainNo,
    required this.direction,
    required this.departureTime,
    required this.destination,
    required this.seatInfo,
  });

  factory ThsrSeatInfo.fromJson(Map<String, dynamic> json) {
    final rawSeats = json['seat_info'] as List<dynamic>? ?? [];
    return ThsrSeatInfo(
      trainNo: json['train_no'] as String? ?? '',
      direction: (json['direction'] as num?)?.toInt() ?? 0,
      departureTime: json['departure_time'] as String? ?? '',
      destination: json['destination'] as String? ?? '',
      seatInfo: rawSeats
          .map((e) => ThsrCarSeat.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final String trainNo;
  final int direction;
  final String departureTime;
  final String destination;
  final List<ThsrCarSeat> seatInfo;
}

class ThsrCarSeat {
  const ThsrCarSeat({
    required this.stationId,
    required this.stationName,
    required this.standardSeat,
    required this.businessSeat,
  });

  factory ThsrCarSeat.fromJson(Map<String, dynamic> json) => ThsrCarSeat(
        stationId: json['station_id'] as String? ?? '',
        stationName: json['station_name'] as String? ?? '',
        standardSeat: json['standard_seat'] as String? ?? '',
        businessSeat: json['business_seat'] as String? ?? '',
      );

  final String stationId;
  final String stationName;
  final String standardSeat;
  final String businessSeat;
}

// ── TRA ──

class TraOdTrain {
  const TraOdTrain({
    required this.trainNo,
    required this.trainType,
    required this.direction,
    required this.startStation,
    required this.endStation,
    required this.originDeparture,
    required this.destArrival,
  });

  factory TraOdTrain.fromJson(Map<String, dynamic> json) => TraOdTrain(
        trainNo: json['train_no'] as String? ?? '',
        trainType: json['train_type'] as String? ?? '',
        direction: (json['direction'] as num?)?.toInt() ?? 0,
        startStation: json['start_station'] as String? ?? '',
        endStation: json['end_station'] as String? ?? '',
        originDeparture: json['origin_departure'] as String? ?? '',
        destArrival: json['dest_arrival'] as String? ?? '',
      );

  final String trainNo;
  final String trainType;
  final int direction;
  final String startStation;
  final String endStation;
  final String originDeparture;
  final String destArrival;
}

class TraLiveBoardEntry {
  const TraLiveBoardEntry({
    required this.trainNo,
    required this.trainType,
    required this.stationId,
    required this.stationName,
    required this.endStation,
    required this.direction,
    required this.scheduledArrival,
    required this.scheduledDeparture,
    required this.delayMinutes,
  });

  factory TraLiveBoardEntry.fromJson(Map<String, dynamic> json) =>
      TraLiveBoardEntry(
        trainNo: json['train_no'] as String? ?? '',
        trainType: json['train_type'] as String? ?? '',
        stationId: json['station_id'] as String? ?? '',
        stationName: json['station_name'] as String? ?? '',
        endStation: json['end_station'] as String? ?? '',
        direction: (json['direction'] as num?)?.toInt() ?? 0,
        scheduledArrival: json['scheduled_arrival'] as String? ?? '',
        scheduledDeparture: json['scheduled_departure'] as String? ?? '',
        delayMinutes: (json['delay_minutes'] as num?)?.toInt() ?? 0,
      );

  final String trainNo;
  final String trainType;
  final String stationId;
  final String stationName;
  final String endStation;
  final int direction;
  final String scheduledArrival;
  final String scheduledDeparture;
  final int delayMinutes;
}

// ── Bike ──

class BikeCity {
  const BikeCity({required this.city, required this.name});

  factory BikeCity.fromJson(Map<String, dynamic> json) => BikeCity(
        city: json['city'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );

  final String city;
  final String name;
}

class BikeStation {
  const BikeStation({
    required this.stationUid,
    required this.stationId,
    required this.name,
    required this.nameEn,
    required this.address,
    required this.lat,
    required this.lon,
    required this.availableRent,
    required this.availableRentGeneral,
    required this.availableRentElectric,
    required this.availableReturn,
    required this.serviceStatus,
    required this.updateTime,
    this.distanceMeters,
    this.city,
  });

  factory BikeStation.fromJson(Map<String, dynamic> json) => BikeStation(
        stationUid: json['station_uid'] as String? ?? '',
        stationId: json['station_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        nameEn: json['name_en'] as String? ?? '',
        address: json['address'] as String? ?? '',
        lat: (json['lat'] as num?)?.toDouble() ?? 0,
        lon: (json['lon'] as num?)?.toDouble() ?? 0,
        availableRent: (json['available_rent'] as num?)?.toInt() ?? 0,
        availableRentGeneral: (json['available_rent_general'] as num?)?.toInt() ?? 0,
        availableRentElectric: (json['available_rent_electric'] as num?)?.toInt() ?? 0,
        availableReturn: (json['available_return'] as num?)?.toInt() ?? 0,
        serviceStatus: (json['service_status'] as num?)?.toInt() ?? 0,
        updateTime: json['update_time'] as String? ?? '',
        distanceMeters: (json['distance_meters'] as num?)?.toInt(),
        city: json['city'] as String?,
      );

  final String stationUid;
  final String stationId;
  final String name;
  final String nameEn;
  final String address;
  final double lat;
  final double lon;
  final int availableRent;
  final int availableRentGeneral;
  final int availableRentElectric;
  final int availableReturn;
  final int serviceStatus;
  final String updateTime;
  final int? distanceMeters;
  final String? city;
}
