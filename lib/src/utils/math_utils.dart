import 'dart:math';

/// Defines the environmental variables for RF signal calculations.
/// This makes the math modular for both Wi-Fi and future Bluetooth integrations.
class RfEnvironment {
  final int baseTxPower; // The 'A' value (Signal strength at 1 meter in dBm)
  final double pathLossExponent; // The 'n' value (Environmental obstacle factor)

  const RfEnvironment({
    required this.baseTxPower,
    required this.pathLossExponent,
  });

  // Pre-configured profiles
  static const RfEnvironment wifiOffice = RfEnvironment(baseTxPower: -45, pathLossExponent: 3.0);
  static const RfEnvironment wifiOpen = RfEnvironment(baseTxPower: -40, pathLossExponent: 2.0);
  static const RfEnvironment bleBeacon = RfEnvironment(baseTxPower: -59, pathLossExponent: 2.5); // For your future phase!
}

/// A mathematical utility class for Indoor Positioning.
class MathUtils {
  
  /// Calculates distance in meters using the Log-Distance Path Loss Model.
  /// Equation: d = 10 ^ ((A - RSSI) / 10n)
  static double calculateDistance(int currentRssi, RfEnvironment env) {
    final double power = (env.baseTxPower - currentRssi) / (10.0 * env.pathLossExponent);
    return pow(10.0, power).toDouble();
  }

  /// Calculates the estimated (x,y) position using Weighted K-Nearest Neighbors (WKNN).
  /// [anchorData] must contain maps with 'x', 'y', and 'distance'.
  static Map<String, double>? calculateWknnPosition(List<Map<String, dynamic>> anchorData) {
    if (anchorData.isEmpty) return null;

    double sumWeights = 0.0;
    double sumX = 0.0;
    double sumY = 0.0;

    for (var anchor in anchorData) {
      double distance = anchor['distance'] as double;
      double x = anchor['x'] as double;
      double y = anchor['y'] as double;

      // Prevent division by zero if distance is mathematically 0
      if (distance < 0.1) distance = 0.1;

      // The weight is the inverse of the distance. 
      // Closer routers have a higher weight and pull the user towards them.
      double weight = 1.0 / distance;

      sumWeights += weight;
      sumX += (x * weight);
      sumY += (y * weight);
    }

    // Calculate the weighted average for X and Y
    return {
      'x': sumX / sumWeights,
      'y': sumY / sumWeights,
    };
  }
}