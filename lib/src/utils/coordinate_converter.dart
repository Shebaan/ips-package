import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';

class CoordinateConverter {
  /// Converts a target LatLng to a local (x, y) coordinate in meters.
  /// The origin LatLng becomes (0.0, 0.0).
  static Map<String, double> toLocalCartesian({
    required LatLng target, 
    required LatLng origin
  }) {
    // Calculate X-axis (Longitude diff). Latitude stays the same.
    double xMeters = Geolocator.distanceBetween(
      origin.latitude, origin.longitude, 
      origin.latitude, target.longitude
    );
    // If target is West of origin, make it negative
    if (target.longitude < origin.longitude) {
      xMeters = -xMeters;
    }

    // Calculate Y-axis (Latitude diff). Longitude stays the same.
    double yMeters = Geolocator.distanceBetween(
      origin.latitude, origin.longitude, 
      target.latitude, origin.longitude
    );
    // If target is South of origin, make it negative
    if (target.latitude < origin.latitude) {
      yMeters = -yMeters;
    }

    return {'x': xMeters, 'y': yMeters};
  }

  /// Converts a local Cartesian (x, y) coordinate back into a global LatLng.
  /// Used to convert the WKNN output into real-world map coordinates.
  static LatLng toGlobalCoordinates({
    required double localX,
    required double localY,
    required LatLng origin,
  }) {
    // Standard approximation: 111,320 meters per degree of latitude
    const double metersPerDegree = 111320.0;
    
    // Latitude is a straight calculation
    double deltaLat = localY / metersPerDegree;
    
    // Longitude shrinks as you move away from the equator, so we factor in cosine
    double originLatRadians = origin.latitude * (pi / 180.0);
    double deltaLng = localX / (metersPerDegree * cos(originLatRadians));

    return LatLng(origin.latitude + deltaLat, origin.longitude + deltaLng);
  }
}

