import 'dart:math';

class IndoorPositioningUtils {
  // Constants for Earth's radius and degree-to-meter conversions
  static const double earthRadius = 6378137.0; // in meters

  /// Converts (dx, dy) meters from a reference Lat/Long into a new Lat/Long
  /// dx: Meters moved East (+) or West (-)
  /// dy: Meters moved North (+) or South (-)
  static Map<String, double> translateToLatLong({
    required double refLat,
    required double refLong,
    required double dx,
    required double dy,
  }) {
    // Calculate Latitude change
    double dLat = dy / earthRadius;

    // Calculate Longitude change (adjusted for Earth's curvature at current Lat)
    double dLong = dx / (earthRadius * cos(refLat * pi / 180.0));

    // Convert radians back to degrees and add to reference
    double newLat = refLat + (dLat * 180.0 / pi);
    double newLong = refLong + (dLong * 180.0 / pi);

    return {
      'latitude': newLat,
      'longitude': newLong,
    };
  }
}