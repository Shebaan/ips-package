import 'dart:async';
import 'dart:math';
import 'dart:io'; // Needed to check if Platform is iOS or Android
import 'package:flutter/foundation.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'; // Added BLE package
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/ips_node.dart';
import '../utils/math_utils.dart';
import '../utils/coordinate_converter.dart';
import 'anchor_manager.dart';

class LocationEngine {
  final AnchorManager anchorManager;
  Timer? _scanTimer;
  
  // Prevents the 3-second timer from overlapping scans if hardware is slow
  bool _isScanning = false; 

  // Broadcasts the real-world GPS coordinates (for Google Maps)
  final ValueNotifier<LatLng?> liveLocation = ValueNotifier(null);
  // Broadcasts the flat 2D grid coordinates (for our Localised Map)
  final ValueNotifier<Map<String, double>?> liveLocalPosition = ValueNotifier(null);

  LocationEngine({required this.anchorManager});

  // Toggle this to TRUE if you are testing on a Mac/PC emulator!
  final bool isSimulationMode = false; 
  
  // Tracks the passage of time for the simulation patrol route
  int _simTick = 0;

  void startTracking() {
    if (_scanTimer != null && _scanTimer!.isActive) return;
    
    print("Starting Live IPS Tracking (Sensor Fusion Active)...");
    
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
    _isScanning = false;
  }

  Future<void> _performLocationUpdate() async {
    // Overlap protection
    if (_isScanning) return; 
    _isScanning = true;

    List<Map<String, dynamic>> usableAnchors = [];

    if (isSimulationMode) {
      // ---------------------------------------------------------
      // SIMULATION MODE: The Walking Ghost Patrol
      // ---------------------------------------------------------
      if (anchorManager.hardwareAnchors.isEmpty) {
        print("Simulator: No anchors saved in AnchorManager.");
        _isScanning = false;
        return;
      }

      final int numAnchors = anchorManager.hardwareAnchors.length;
      if (numAnchors < 2) {
        _isScanning = false;
        return; 
      }

      final int stepsPerLeg = 10; 
      int currentLeg = (_simTick ~/ stepsPerLeg) % numAnchors;
      int nextLeg = (currentLeg + 1) % numAnchors;
      double progress = (_simTick % stepsPerLeg) / stepsPerLeg;

      final random = Random();

      for (int i = 0; i < numAnchors; i++) {
        final knownAnchor = anchorManager.hardwareAnchors[i];
        double simulatedRssi;

        if (i == currentLeg) {
          simulatedRssi = -45.0 - (30.0 * progress);
        } else if (i == nextLeg) {
          simulatedRssi = -75.0 + (30.0 * progress);
        } else {
          simulatedRssi = -75.0;
        }

        int finalRssi = simulatedRssi.toInt() + (random.nextInt(5) - 2);
        final distance = MathUtils.calculateDistance(finalRssi, RfEnvironment.wifiOffice);

        usableAnchors.add({
          'x': knownAnchor.localX,
          'y': knownAnchor.localY,
          'distance': distance,
        });
      }
      _simTick++; 
      
    } else {
      // ---------------------------------------------------------
      // PRODUCTION MODE: Sensor Fusion (Wi-Fi + BLE)
      // ---------------------------------------------------------
      
      // 1. Android ONLY: Scan for Wi-Fi Networks
      if (!kIsWeb && Platform.isAndroid) {
        usableAnchors.addAll(await _scanWifi());
      }

      // 2. ALL PLATFORMS (iOS & Android): Scan for BLE Beacons
      usableAnchors.addAll(await _scanBle());
    }

    // --- MATH ENGINE (Executes regardless of simulation or platform) ---
    if (usableAnchors.isEmpty) {
      print("LocationEngine: No mapped anchors visible.");
      _isScanning = false;
      return;
    }

    // 3. Calculate local (x,y) using WKNN
    final localPosition = MathUtils.calculateWknnPosition(usableAnchors);
    if (localPosition == null) {
      _isScanning = false;
      return;
    }

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
    
    // Unlock the scanner for the next tick
    _isScanning = false;
  }

  // ===================================================================
  // HARDWARE SCANNER HELPERS
  // ===================================================================

  Future<List<Map<String, dynamic>>> _scanWifi() async {
    List<Map<String, dynamic>> processedWifi = [];
    final canScan = await WiFiScan.instance.canStartScan();
    if (canScan != CanStartScan.yes) return processedWifi;

    await WiFiScan.instance.startScan();
    final results = await WiFiScan.instance.getScannedResults();

    for (var ap in results) {
      try {
        final knownRouter = anchorManager.hardwareAnchors.firstWhere(
          (anchor) => anchor.hardwareType == HardwareType.wifi && anchor.hardwareId == ap.bssid,
        );

        final distance = MathUtils.calculateDistance(ap.level, RfEnvironment.wifiOffice);
        processedWifi.add({'x': knownRouter.localX, 'y': knownRouter.localY, 'distance': distance});
      } catch (e) {
        continue; // Not a router we care about
      }
    }
    return processedWifi;
  }

  Future<List<Map<String, dynamic>>> _scanBle() async {
    List<Map<String, dynamic>> processedBle = [];
    List<ScanResult> bleResults = [];
    
    // Listen to the BLE stream
    var subscription = FlutterBluePlus.onScanResults.listen((results) {
      bleResults = results;
    });

    // Scan for exactly 2 seconds
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 2));
    await Future.delayed(const Duration(seconds: 2));
    subscription.cancel();

    for (var r in bleResults) {
      try {
        final knownBeacon = anchorManager.hardwareAnchors.firstWhere(
          (anchor) => anchor.hardwareType == HardwareType.ble && anchor.hardwareId == r.device.remoteId.str,
        );

        // BLE math is identical to Wi-Fi math (Log-Distance Path Loss)
        final distance = MathUtils.calculateDistance(r.rssi, RfEnvironment.wifiOffice); 
        processedBle.add({'x': knownBeacon.localX, 'y': knownBeacon.localY, 'distance': distance});
      } catch (e) {
        continue; // Not a beacon we care about
      }
    }
    return processedBle;
  }
}