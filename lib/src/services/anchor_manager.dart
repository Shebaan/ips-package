import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ips_node.dart';
import '../utils/coordinate_converter.dart';

class AnchorManager {
  List<IpsNode> buildingCorners = [];
  List<IpsNode> wifiRouters = [];
  
  LatLng? _originPoint;

  void processBuildingData({
    required List<LatLng> corners, 
    required List<Map<String, dynamic>> routers, // Updated signature
  }) {
    if (corners.isEmpty) return;
    _originPoint = corners.first;
    buildingCorners.clear();
    wifiRouters.clear();

    // Process Corners (Unchanged)
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

    // Process Routers (Now unpacks the Map to extract LatLng and MAC)
    for (int i = 0; i < routers.length; i++) {
      final LatLng routerCoords = routers[i]['latLng'] as LatLng;
      final String macAddress = routers[i]['macAddress'] as String;

      final localCoords = CoordinateConverter.toLocalCartesian(
        target: routerCoords, 
        origin: _originPoint!
      );
      
      wifiRouters.add(IpsNode(
        id: 'router_$i', 
        type: NodeType.router,
        globalCoordinates: routerCoords, 
        localX: localCoords['x']!, 
        localY: localCoords['y']!,
        macAddress: macAddress, // Inject the MAC address into the data model
      ));
    }

    _printDebugGrid();
    saveGridToDisk(); 
  }

  Future<void> saveGridToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Convert lists to JSON strings
    final String cornersJson = jsonEncode(buildingCorners.map((node) => node.toJson()).toList());
    final String routersJson = jsonEncode(wifiRouters.map((node) => node.toJson()).toList());

    // Write to device storage
    await prefs.setString('ips_corners', cornersJson);
    await prefs.setString('ips_routers', routersJson);
    print('IPS Grid successfully saved to local device storage!');
  }

  Future<bool> loadGridFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    
    final String? cornersString = prefs.getString('ips_corners');
    final String? routersString = prefs.getString('ips_routers');

    if (cornersString != null && routersString != null) {
      // Decode the JSON strings back into Lists of dynamic maps
      final List<dynamic> decodedCorners = jsonDecode(cornersString);
      final List<dynamic> decodedRouters = jsonDecode(routersString);

      // Rebuild the IpsNode objects
      buildingCorners = decodedCorners.map((item) => IpsNode.fromJson(item)).toList();
      wifiRouters = decodedRouters.map((item) => IpsNode.fromJson(item)).toList();
      
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
    for (var router in wifiRouters) { print(router); }
    print('-------------------\n');
  }
}