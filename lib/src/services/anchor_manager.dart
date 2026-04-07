import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ips_node.dart';
import '../utils/coordinate_converter.dart';

class AnchorManager {
  List<IpsNode> buildingCorners = [];
  // Renamed to hardwareAnchors to support both Wi-Fi and BLE
  List<IpsNode> hardwareAnchors = []; 
  
  LatLng? _originPoint;

  /// Ingests the raw data dictionary from the MapCollectionScreen.
  /// Validates the data, processes spatial coordinates, and saves to disk.
  /// Returns [true] if successful, [false] if the data was invalid.
  bool processBuildingData(Map<String, dynamic> rawData) {
    try {
      // 1. Validation phase
      if (!rawData.containsKey('corners') || !rawData.containsKey('routers')) {
        print("AnchorManager Validation Failed: Missing data keys.");
        return false;
      }

      // Safely unpack the data
      final List<LatLng> corners = List<LatLng>.from(rawData['corners']);
      final List<Map<String, dynamic>> anchors = List<Map<String, dynamic>>.from(rawData['routers']);

      if (corners.isEmpty) {
        print("AnchorManager Validation Failed: No building corners provided.");
        return false;
      }

      // 2. Processing phase
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
        // Parse the new Sensor Fusion variables
        final String hwId = anchors[i]['hardwareId'] as String;
        final String hwTypeStr = anchors[i]['hardwareType'] as String;

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
        ));
      }

      // 3. Storage phase
      _printDebugGrid();
      saveGridToDisk(); 
      
      return true; // Success!

    } catch (e) {
      print("AnchorManager Error processing data: $e");
      return false; // Something went wrong during extraction or math
    }
  }
  
  Future<void> saveGridToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Convert lists to JSON strings
    final String cornersJson = jsonEncode(buildingCorners.map((node) => node.toJson()).toList());
    final String anchorsJson = jsonEncode(hardwareAnchors.map((node) => node.toJson()).toList());

    // Write to device storage
    await prefs.setString('ips_corners', cornersJson);
    await prefs.setString('ips_routers', anchorsJson); // Kept key as 'ips_routers' to not break existing saves
    print('IPS Grid successfully saved to local device storage!');
  }

  Future<bool> loadGridFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    
    final String? cornersString = prefs.getString('ips_corners');
    final String? anchorsString = prefs.getString('ips_routers');

    if (cornersString != null && anchorsString != null) {
      // Decode the JSON strings back into Lists of dynamic maps
      final List<dynamic> decodedCorners = jsonDecode(cornersString);
      final List<dynamic> decodedAnchors = jsonDecode(anchorsString);

      // Rebuild the IpsNode objects
      buildingCorners = decodedCorners.map((item) => IpsNode.fromJson(item)).toList();
      hardwareAnchors = decodedAnchors.map((item) => IpsNode.fromJson(item)).toList();
      
      if (buildingCorners.isNotEmpty) {
        _originPoint = buildingCorners.first.globalCoordinates;
      }
      
      print('IPS Grid successfully loaded from local storage!');
      _printDebugGrid();
      return true; // Data exists!
    }
    
    print('🤷‍♂️ No saved grid found. Needs setup.');
    return false; // No data, user needs to do the map setup.
  }

  void _printDebugGrid() {
    print('\n--- IPS GRID ---');
    for (var corner in buildingCorners) { print(corner); }
    print('---');
    for (var anchor in hardwareAnchors) { print(anchor); }
    print('-------------------\n');
  }
}