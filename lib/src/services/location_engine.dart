import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/ips_node.dart';
import '../utils/math_utils.dart';
import '../utils/coordinate_converter.dart';
import 'anchor_manager.dart';

class LocationEngine {
  final AnchorManager anchorManager;
  Timer? _scanTimer;

  // Broadcasts the real-world GPS coordinates (for Google Maps)
  final ValueNotifier<LatLng?> liveLocation = ValueNotifier(null);
  // Broadcasts the flat 2D grid coordinates (for our Localised Map)
  final ValueNotifier<Map<String, double>?> liveLocalPosition = ValueNotifier(null);

  LocationEngine({required this.anchorManager});

  // Simulation mode allows testing without using real WiFi scanning hardware.
  // Simulates a guard walking in a loop from router to router.
  final bool isSimulationMode = false; 
  
  // Tracks the passage of time for the simulation patrol route
  int _simTick = 0;

  void startTracking() {
    if (_scanTimer != null && _scanTimer!.isActive) return;
    
    print("Starting Live IPS Tracking...");
    
    // Trigger the first scan immediately so the UI updates instantly
    _performLocationUpdate();

    // Scan every 3 seconds 
    _scanTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _performLocationUpdate();
    });
  }

  void stopTracking() {
    print("Stopping Live IPS Tracking.");
    _scanTimer?.cancel();
    _scanTimer = null;
  }

  Future<void> _performLocationUpdate() async {
    List<Map<String, dynamic>> usableAnchors = [];

    if (isSimulationMode) {
      // ---------------------------------------------------------
      // SIMULATION MODE: The Walking Ghost Patrol
      // ---------------------------------------------------------
      if (anchorManager.wifiRouters.isEmpty) {
        print("Simulator: No routers saved in AnchorManager.");
        return;
      }

      final int numRouters = anchorManager.wifiRouters.length;
      // If you only have 1 router mapped, it can't walk anywhere!
      if (numRouters < 2) return; 

      final int stepsPerLeg = 10; // Takes 10 engine ticks (approx 30 sec) to walk to the next router

      // Calculate which router we are leaving, and which one we are walking to
      int currentLeg = (_simTick ~/ stepsPerLeg) % numRouters;
      int nextLeg = (currentLeg + 1) % numRouters;
      
      // Calculate how far along the path we are (0.0 to 1.0)
      double progress = (_simTick % stepsPerLeg) / stepsPerLeg;

      print("Simulator: Walking from Router ${currentLeg + 1} to Router ${nextLeg + 1} (Progress: ${(progress * 100).toInt()}%)");

      final random = Random();

      for (int i = 0; i < numRouters; i++) {
        final knownRouter = anchorManager.wifiRouters[i];
        double simulatedRssi;

        if (i == currentLeg) {
          // Walking AWAY from this router (Fading from -45 down to -75)
          simulatedRssi = -45.0 - (30.0 * progress);
        } else if (i == nextLeg) {
          // Walking TOWARDS this router (Fading from -75 up to -45)
          simulatedRssi = -75.0 + (30.0 * progress);
        } else {
          // We are far away from all other routers
          simulatedRssi = -75.0;
        }

        // Add a tiny bit of +/- 2 jitter so the walk looks human and organic
        int finalRssi = simulatedRssi.toInt() + (random.nextInt(5) - 2);

        final distance = MathUtils.calculateDistance(finalRssi, RfEnvironment.wifiOffice);

        usableAnchors.add({
          'x': knownRouter.localX,
          'y': knownRouter.localY,
          'distance': distance,
        });
      }

      // Advance the simulation clock for the next update!
      _simTick++; 
      
    } else {
      // ---------------------------------------------------------
      // PRODUCTION MODE: Real hardware scanning (Requires physical device)
      // ---------------------------------------------------------
      final canScan = await WiFiScan.instance.canStartScan();
      if (canScan != CanStartScan.yes) return;

      await WiFiScan.instance.startScan();
      final results = await WiFiScan.instance.getScannedResults();

      for (var ap in results) {
        try {
          final knownRouter = anchorManager.wifiRouters.firstWhere(
            (router) => router.macAddress == ap.bssid,
          );

          final distance = MathUtils.calculateDistance(ap.level, RfEnvironment.wifiOffice);

          usableAnchors.add({
            'x': knownRouter.localX,
            'y': knownRouter.localY,
            'distance': distance,
          });
        } catch (e) {
          continue; // Ignore unknown MAC addresses
        }
      }
    }

    // --- THE REST OF THE MATH ENGINE REMAINS THE SAME ---
    if (usableAnchors.isEmpty) {
      print("LocationEngine: No mapped routers visible.");
      return;
    }

    // 3. Calculate local (x,y) using WKNN
    final localPosition = MathUtils.calculateWknnPosition(usableAnchors);
    if (localPosition == null) return;

    // 4. Broadcast the flat 2D grid coordinates for the custom painter!
    liveLocalPosition.value = localPosition; 

    // 5. Find the Origin Node to reverse the math
    final originNode = anchorManager.buildingCorners.firstWhere(
      (node) => node.type == NodeType.origin
    );

    // 6. Convert local (x,y) back to Global GPS Coordinates
    final globalPos = CoordinateConverter.toGlobalCoordinates(
      localX: localPosition['x']!,
      localY: localPosition['y']!,
      origin: originNode.globalCoordinates, 
    );

    // 7. Broadcast the live GPS coordinates to the UI
    liveLocation.value = globalPos;
  }
}