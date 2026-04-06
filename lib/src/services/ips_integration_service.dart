import 'dart:async';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'location_engine.dart';

class IpsIntegrationService {
  final LocationEngine locationEngine;

  // Streams for the NovusGuard app to listen to
  final StreamController<LatLng> _indoorLocationStream = StreamController<LatLng>.broadcast();
  Stream<LatLng> get indoorLocationStream => _indoorLocationStream.stream;

  final StreamController<String> _alertStream = StreamController<String>.broadcast();
  Stream<String> get alertStream => _alertStream.stream;

  // The Geofence Polygon (Safe Zone)
  List<LatLng> patrolRoomGeofence = [];

  IpsIntegrationService({required this.locationEngine}) {
    _listenToEngine();
  }

  void setPatrolZone(List<LatLng> safeZonePerimeter) {
    patrolRoomGeofence = safeZonePerimeter;
  }

  void _listenToEngine() {
    locationEngine.liveLocation.addListener(() {
      final currentLocation = locationEngine.liveLocation.value;
      
      if (currentLocation != null) {
        // 1. Push to the App Stream
        _indoorLocationStream.add(currentLocation);
        
        // 2. Simulate sending to Backend via Socket.io
        _simulateSocketEmit(currentLocation);
        
        // 3. Run Security Geo-fence Checks
        _checkGeofence(currentLocation);
      }
    });
  }

  void _checkGeofence(LatLng currentLocation) {
    if (patrolRoomGeofence.isEmpty) return;

    final isInside = _isPointInPolygon(currentLocation, patrolRoomGeofence);

    if (!isInside) {
      _triggerPatrolAlert();
    }
  }

  /// Ray-Casting Algorithm to determine if a point is inside a custom polygon
  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    int intersectCount = 0;
    
    for (int j = 0; j < polygon.length - 1; j++) {
      if (_rayCastIntersect(point, polygon[j], polygon[j + 1])) {
        intersectCount++;
      }
    }
    
    // Check the closing line of the polygon
    if (_rayCastIntersect(point, polygon.last, polygon.first)) {
      intersectCount++;
    }

    return (intersectCount % 2 == 1); // Odd = Inside, Even = Outside
  }

  bool _rayCastIntersect(LatLng point, LatLng vertA, LatLng vertB) {
    final double px = point.longitude;
    final double py = point.latitude;
    final double ax = vertA.longitude;
    final double ay = vertA.latitude;
    final double bx = vertB.longitude;
    final double by = vertB.latitude;

    if (ay > py == by > py) return false;
    if (px > (bx - ax) * (py - ay) / (by - ay) + ax) return false;
    
    return true;
  }

  void _triggerPatrolAlert() {
    print("SOCKET EMIT: patrol_alert -> status: out_of_bounds");
    _alertStream.add('out_of_bounds'); 
  }

  void _simulateSocketEmit(LatLng loc) {
    // In the real app, this is where you use socket.emit()
    print("SOCKET EMIT: update_location -> ${loc.latitude}, ${loc.longitude}");
  }

  void dispose() {
    _indoorLocationStream.close();
    _alertStream.close();
  }
}