import 'dart:async';
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
  final bool isSimulationMode = false;

  void startTracking() {
    if (_scanTimer != null && _scanTimer!.isActive) return;
    
    print("Starting Live IPS Tracking...");
    
    // Scan every 3 seconds (Requires Wi-Fi Throttling to be OFF in Android Dev Options)
    _scanTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _performLocationUpdate();
    });
    
    // Trigger the first scan immediately
    _performLocationUpdate();
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
      // SIMULATION MODE: Bypass the missing iOS Simulator antenna
      // ---------------------------------------------------------
      if (anchorManager.wifiRouters.isEmpty) {
        print("Simulator: No routers saved in AnchorManager.");
        return;
      }

      print("Simulator: Generating mock Wi-Fi signals...");
      
      // Generate a fake signal for every router you saved on your map
      for (int i = 0; i < anchorManager.wifiRouters.length; i++) {
        final knownRouter = anchorManager.wifiRouters[i];
        
        // Fake RSSI Logic: Pretend we are very close to the first router (-45dBm)
        // and further away from the others (-65dBm, -70dBm). 
        int mockRssi = (i == 0) ? -45 : -60 - (i * 5);

        // Pass the fake RSSI into the math engine
        final distance = MathUtils.calculateDistance(mockRssi, RfEnvironment.wifiOffice);

        usableAnchors.add({
          'x': knownRouter.localX,
          'y': knownRouter.localY,
          'distance': distance,
        });
      }
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