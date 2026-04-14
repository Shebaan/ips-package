import 'package:google_maps_flutter/google_maps_flutter.dart';

enum NodeType { origin, corner, router }

// Added HardwareType to support Sensor Fusion (Wi-Fi & BLE)
enum HardwareType { wifi, ble, none }

class IpsNode {
  final String id;
  final NodeType type;
  final LatLng globalCoordinates; 
  final double localX;            
  final double localY;  
  // Added fields to store hardware information for routers (nullable)
  final String? hardwareId; 
  final HardwareType hardwareType;          
  final String? hardwareName; 
  final int? floor;

  IpsNode({
    required this.id,
    required this.type,
    required this.globalCoordinates,
    required this.localX,
    required this.localY,
    this.hardwareId,
    this.hardwareType = HardwareType.none, // Defaults to none for corners/origins
    this.hardwareName,
    this.floor = 1, // Default to floor 1 if not specified
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name, 
      'lat': globalCoordinates.latitude,
      'lng': globalCoordinates.longitude,
      'localX': localX,
      'localY': localY,
      'hardwareId': hardwareId, 
      'hardwareType': hardwareType.name,
      'hardwareName': hardwareName,
      'floor': floor,
    };
  }

  factory IpsNode.fromJson(Map<String, dynamic> json) {
    return IpsNode(
      id: json['id'],
      type: NodeType.values.firstWhere((e) => e.name == json['type']),
      globalCoordinates: LatLng(json['lat'], json['lng']),
      localX: json['localX'],
      localY: json['localY'],
      // 4. Parse the new hardware data
      hardwareId: json['hardwareId'], 
      // Safety fallback: If loading an old map from Phase 1, it won't crash
      hardwareType: json['hardwareType'] != null 
          ? HardwareType.values.firstWhere((e) => e.name == json['hardwareType'])
          : HardwareType.none, 
      hardwareName: json['hardwareName'],
      floor: json['floor'] ?? 1, // Default to floor 1 if not specified
    );
  }

  @override
  String toString() {
    // Updated the debug string to show if it's broadcasting Wi-Fi or BLE
    String hardwareStr = '';
    if (hardwareId != null && hardwareType != HardwareType.none) {
      hardwareStr = ' [${hardwareType.name.toUpperCase()}: $hardwareId]';
    }
    return '${type.name.toUpperCase()} "$id"$hardwareStr -> (x: ${localX.toStringAsFixed(2)}m, y: ${localY.toStringAsFixed(2)}m)';
  }
}