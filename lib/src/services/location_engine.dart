import 'dart:async';
import 'dart:math';
import 'dart:io'; 
import 'package:flutter/foundation.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'; 
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sensors_plus/sensors_plus.dart'; // NEW: Barometer support

import '../models/ips_node.dart';
import '../utils/math_utils.dart';
import '../utils/coordinate_converter.dart';
import 'anchor_manager.dart';

class LocationEngine {
  final AnchorManager anchorManager;
  Timer? _scanTimer;
  StreamSubscription<BarometerEvent>? _barometerSubscription; // NEW
  
  bool _isScanning = false; 

  final ValueNotifier<LatLng?> liveLocation = ValueNotifier(null);
  final ValueNotifier<Map<String, double>?> liveLocalPosition = ValueNotifier(null);
  
  // NEW: Broadcasts the active floor!
  final ValueNotifier<int> liveFloor = ValueNotifier(1); 
  int _currentFloor = 1;

  LocationEngine({required this.anchorManager});

  final bool isSimulationMode = false; 
  int _simTick = 0;

  void startTracking() {
    if (_scanTimer != null && _scanTimer!.isActive) return;
    
    print("Starting Live IPS Tracking (Sensor Fusion & Z-Axis Active)...");
    
    // --- NEW: Start listening to the Barometer ---
    _startFloorTracking();
    
    _performLocationUpdate();

    _scanTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _performLocationUpdate();
    });
  }

  void stopTracking() {
    print("Stopping Live IPS Tracking.");
    _scanTimer?.cancel();
    _scanTimer = null;
    _barometerSubscription?.cancel(); // NEW: Turn off barometer
    _barometerSubscription = null;
    _isScanning = false;
  }

  // --- NEW: The Floor Calculator ---
  void _startFloorTracking() {
    if (anchorManager.floorPressures.isEmpty) {
      print("LocationEngine: No floor pressure baselines found. Defaulting to Floor 1.");
      _currentFloor = 1;
      liveFloor.value = 1;
      return;
    }

    _barometerSubscription = barometerEventStream().listen((event) {
      double livePressure = event.pressure;
      double smallestDiff = double.infinity;
      int closestFloor = _currentFloor;

      // Find the floor with the baseline pressure closest to right now
      anchorManager.floorPressures.forEach((floor, baselinePressure) {
        double diff = (livePressure - baselinePressure).abs();
        if (diff < smallestDiff) {
          smallestDiff = diff;
          closestFloor = floor;
        }
      });

      // If the floor changed, update the system!
      if (_currentFloor != closestFloor) {
        print("Z-AXIS SHIFT DETECTED: User moved from Floor $_currentFloor to Floor $closestFloor");
        _currentFloor = closestFloor;
        liveFloor.value = _currentFloor;
      }
    });
  }

  Future<void> _performLocationUpdate() async {
    if (_isScanning) return; 
    _isScanning = true;

    List<Map<String, dynamic>> usableAnchors = [];

    if (isSimulationMode) {
      // Simulator: Only use anchors on the current floor
      final floorAnchors = anchorManager.hardwareAnchors.where((a) => a.floor == _currentFloor).toList();
      
      if (floorAnchors.isEmpty) {
        _isScanning = false;
        return;
      }

      final int numAnchors = floorAnchors.length;
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
        final knownAnchor = floorAnchors[i];
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
      if (!kIsWeb && Platform.isAndroid) {
        usableAnchors.addAll(await _scanWifi());
      }
      usableAnchors.addAll(await _scanBle());
    }

    if (usableAnchors.isEmpty) {
      _isScanning = false;
      return;
    }

    final localPosition = MathUtils.calculateWknnPosition(usableAnchors);
    if (localPosition == null) {
      _isScanning = false;
      return;
    }

    liveLocalPosition.value = localPosition; 

    final originNode = anchorManager.buildingCorners.firstWhere(
      (node) => node.type == NodeType.origin
    );

    final globalPos = CoordinateConverter.toGlobalCoordinates(
      localX: localPosition['x']!,
      localY: localPosition['y']!,
      origin: originNode.globalCoordinates, 
    );

    liveLocation.value = globalPos;
    _isScanning = false;
  }

  Future<List<Map<String, dynamic>>> _scanWifi() async {
    List<Map<String, dynamic>> processedWifi = [];
    final canScan = await WiFiScan.instance.canStartScan();
    if (canScan != CanStartScan.yes) return processedWifi;

    await WiFiScan.instance.startScan();
    final results = await WiFiScan.instance.getScannedResults();

    for (var ap in results) {
      try {
        final knownRouter = anchorManager.hardwareAnchors.firstWhere(
          (anchor) => anchor.hardwareType == HardwareType.wifi && 
                      anchor.hardwareId == ap.bssid &&
                      anchor.floor == _currentFloor, // NEW: IGNORE ROUTERS ON OTHER FLOORS!
        );

        final distance = MathUtils.calculateDistance(ap.level, RfEnvironment.wifiOffice);
        processedWifi.add({'x': knownRouter.localX, 'y': knownRouter.localY, 'distance': distance});
      } catch (e) {
        continue; 
      }
    }
    return processedWifi;
  }

  Future<List<Map<String, dynamic>>> _scanBle() async {
    List<Map<String, dynamic>> processedBle = [];
    List<ScanResult> bleResults = [];
    
    var subscription = FlutterBluePlus.onScanResults.listen((results) {
      bleResults = results;
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 2));
    await Future.delayed(const Duration(seconds: 2));
    subscription.cancel();

    for (var r in bleResults) {
      try {
        final knownBeacon = anchorManager.hardwareAnchors.firstWhere(
          (anchor) => anchor.hardwareType == HardwareType.ble && 
                      anchor.hardwareId == r.device.remoteId.str &&
                      anchor.floor == _currentFloor, // NEW: IGNORE BEACONS ON OTHER FLOORS!
        );

        final distance = MathUtils.calculateDistance(r.rssi, RfEnvironment.wifiOffice); 
        processedBle.add({'x': knownBeacon.localX, 'y': knownBeacon.localY, 'distance': distance});
      } catch (e) {
        continue; 
      }
    }
    return processedBle;
  }
}