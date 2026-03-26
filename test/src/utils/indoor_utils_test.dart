import 'package:flutter_test/flutter_test.dart';
// This imports all the files you exposed in ips_package.dart
import 'package:ips_package/ips_package.dart'; 

void main() {
  group('IndoorPositioningUtils Math Tests', () {
    
    test('Standing still (0m) returns the exact same Anchor coordinates', () {
      // 1. Setup our fake Anchor point
      double anchorLat = 52.5862;
      double anchorLong = -2.1288;

      // 2. Run your Week 1 math function (moving 0 meters)
      final result = IndoorPositioningUtils.translateToLatLong(
        refLat: anchorLat,
        refLong: anchorLong,
        dx: 0.0, 
        dy: 0.0,
      );

      // 3. Assert (Expect) the results
      expect(result['latitude'], anchorLat);
      expect(result['longitude'], anchorLong);
    });

    test('Moving ~111km North adds exactly 1 degree of Latitude', () {
      // Moving 111,319 meters North on Earth is mathematically equal to 1 degree of Latitude.
      final result = IndoorPositioningUtils.translateToLatLong(
        refLat: 0.0, // Standing on the equator
        refLong: 0.0,
        dx: 0.0, 
        dy: 111319.9, // Moving North
      );

      // We expect the new Latitude to be very close to 1.0
      expect(result['latitude'], closeTo(1.0, 0.01));
      // Longitude should not change because we only moved North (dy)
      expect(result['longitude'], 0.0); 
    });

  });
}