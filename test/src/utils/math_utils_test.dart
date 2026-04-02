import 'package:flutter_test/flutter_test.dart';
import 'package:ips_package/src/utils/math_utils.dart'; // Adjust path if needed

void main() {
  group('MathUtils Physics Engine Tests', () {
    test('Distance Calculation: RSSI matches Base Power exactly (should be 1 meter)', () {
      // If the RSSI is exactly -45, and the base power is -45, we are exactly 1 meter away.
      final distance = MathUtils.calculateDistance(-45, RfEnvironment.wifiOffice);
      expect(distance, closeTo(1.0, 0.01));
    });

    test('WKNN Position Calculation: Perfectly between two routers', () {
      // User is perfectly between two routers, seeing them with the exact same signal strength (distance).
      final List<Map<String, dynamic>> anchors = [
        {'x': 0.0, 'y': 0.0, 'distance': 5.0}, // Router A
        {'x': 10.0, 'y': 0.0, 'distance': 5.0}, // Router B
      ];

      final position = MathUtils.calculateWknnPosition(anchors);
      
      // The gravity should pull them to exactly the midpoint: (5.0, 0.0)
      expect(position!['x'], closeTo(5.0, 0.01));
      expect(position['y'], closeTo(0.0, 0.01));
    });

    test('WKNN Position Calculation: Pulled closer to the stronger signal', () {
      final List<Map<String, dynamic>> anchors = [
        {'x': 0.0, 'y': 0.0, 'distance': 2.0}, // Router A is very close (strong signal)
        {'x': 10.0, 'y': 0.0, 'distance': 8.0}, // Router B is far away (weak signal)
      ];

      final position = MathUtils.calculateWknnPosition(anchors);
      
      // Because Router A has 4x less distance, it has a much heavier weight.
      // The X coordinate should be pulled heavily toward 0.0.
      expect(position!['x'], lessThan(5.0)); // Should be around 2.0
    });
  });
}