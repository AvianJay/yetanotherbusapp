import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/transit_repository.dart';

void main() {
  test('parses general and 2.0E bike availability separately', () {
    final station = BikeStation.fromJson(const <String, dynamic>{
      'station_uid': 'TXG001',
      'station_id': '001',
      'name': '測試站',
      'available_rent': 8,
      'available_rent_general': 5,
      'available_rent_electric': 3,
      'available_return': 12,
    });

    expect(station.availableRent, 8);
    expect(station.availableRentGeneral, 5);
    expect(station.availableRentElectric, 3);
    expect(station.availableReturn, 12);
  });
}
