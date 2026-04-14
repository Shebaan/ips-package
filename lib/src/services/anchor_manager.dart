import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ips_node.dart';
import '../utils/coordinate_converter.dart';

class AnchorManager {
  List<IpsNode> buildingCorners = [];
  List<IpsNode> hardwareAnchors = []; 
  
  // --- NEW: Store the calibrated pressures ---
  Map<int, double> floorPressures = {}; 
  
  LatLng? _originPoint;

  bool processBuildingData(Map<String, dynamic> rawData) {
    try {
      if (!rawData.containsKey('corners') || !rawData.containsKey('routers')) {
        print("AnchorManager Validation Failed: Missing data keys.");
        return false;
      }

      final List<LatLng> corners = List<LatLng>.from(rawData['corners']);
      final List<Map<String, dynamic>> anchors = List<Map<String, dynamic>>.from(rawData['routers']);

      if (corners.isEmpty) {
        print("AnchorManager Validation Failed: No building corners provided.");
        return false;
      }

      _originPoint = corners.first;
      buildingCorners.clear();
      hardwareAnchors.clear();

      for (int i = 0; i < corners.length; i++) {
        final localCoords = CoordinateConverter.toLocalCartesian(
          target: corners[i], 
          origin: _originPoint!
        );
        
        buildingCorners.add(IpsNode(
          id: 'corner_$i', 
          type: i == 0 ? NodeType.origin : NodeType.corner,
          globalCoordinates: corners[i], 
          localX: localCoords['x']!, 
          localY: localCoords['y']!,
        ));
      }

      for (int i = 0; i < anchors.length; i++) {
        final LatLng anchorCoords = anchors[i]['latLng'] as LatLng;
        final String hwId = anchors[i]['hardwareId'] as String;
        final String hwTypeStr = anchors[i]['hardwareType'] as String;
        
        // NEW: Safely extract the new variables
        final String hwName = anchors[i]['hardwareName'] as String? ?? 'Unknown Device';
        final int floor = anchors[i]['floor'] as int? ?? 1;

        final HardwareType type = hwTypeStr == 'BLE' ? HardwareType.ble : HardwareType.wifi;

        final localCoords = CoordinateConverter.toLocalCartesian(
          target: anchorCoords, 
          origin: _originPoint!
        );
        
        hardwareAnchors.add(IpsNode(
          id: 'anchor_$i', 
          type: NodeType.router,
          globalCoordinates: anchorCoords, 
          localX: localCoords['x']!, 
          localY: localCoords['y']!,
          hardwareId: hwId, 
          hardwareType: type,
          // NEW: Inject them into the node!
          hardwareName: hwName,
          floor: floor,
        ));
      }

      // --- NEW: Catch the pressure data! ---
      if (rawData.containsKey('floorPressures')) {
        Map<dynamic, dynamic> rawPressures = rawData['floorPressures'];
        // Parse keys as ints, and values as doubles
        floorPressures = rawPressures.map((key, value) => MapEntry(int.parse(key.toString()), (value as num).toDouble()));
      }

      _printDebugGrid();
      saveGridToDisk(); 
      
      return true; 

    } catch (e) {
      print("AnchorManager Error processing data: $e");
      return false; 
    }
  }
  
  Future<void> saveGridToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    
    final String cornersJson = jsonEncode(buildingCorners.map((node) => node.toJson()).toList());
    final String anchorsJson = jsonEncode(hardwareAnchors.map((node) => node.toJson()).toList());
    
    // NEW: Encode the Map<int, double> as a string so JSON can handle it
    final String pressuresJson = jsonEncode(floorPressures.map((key, value) => MapEntry(key.toString(), value)));

    await prefs.setString('ips_corners', cornersJson);
    await prefs.setString('ips_routers', anchorsJson); 
    await prefs.setString('ips_floor_pressures', pressuresJson); // NEW

    print('IPS Grid and Z-Axis Pressures successfully saved to local device storage!');
  }

  Future<bool> loadGridFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    
    final String? cornersString = prefs.getString('ips_corners');
    final String? anchorsString = prefs.getString('ips_routers');
    final String? pressuresString = prefs.getString('ips_floor_pressures'); // NEW

    if (cornersString != null && anchorsString != null) {
      final List<dynamic> decodedCorners = jsonDecode(cornersString);
      final List<dynamic> decodedAnchors = jsonDecode(anchorsString);

      buildingCorners = decodedCorners.map((item) => IpsNode.fromJson(item)).toList();
      hardwareAnchors = decodedAnchors.map((item) => IpsNode.fromJson(item)).toList();
      
      // NEW: Decode the pressure data
      if (pressuresString != null) {
        Map<String, dynamic> decodedPressures = jsonDecode(pressuresString);
        floorPressures = decodedPressures.map((key, value) => MapEntry(int.parse(key), (value as num).toDouble()));
      } else {
        floorPressures = {}; // Fallback if no pressure data was ever saved
      }

      if (buildingCorners.isNotEmpty) {
        _originPoint = buildingCorners.first.globalCoordinates;
      }
      
      print('IPS Grid successfully loaded from local storage!');
      _printDebugGrid();
      return true; 
    }
    
    print('🤷‍♂️ No saved grid found. Needs setup.');
    return false; 
  }

  void _printDebugGrid() {
    print('\n--- IPS GRID ---');
    for (var corner in buildingCorners) { print(corner); }
    print('---');
    for (var anchor in hardwareAnchors) { print(anchor); }
    print('--- Z-AXIS CALIBRATION ---');
    print(floorPressures);
    print('-------------------\n');
  }
}