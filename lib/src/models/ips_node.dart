import 'package:google_maps_flutter/google_maps_flutter.dart';

enum NodeType { origin, corner, router }

class IpsNode {
  final String id;
  final NodeType type;
  final LatLng globalCoordinates; 
  final double localX;            
  final double localY;  
  final String? macAddress; // The Wi-Fi Fingerprint (BSSID)          

  IpsNode({
    required this.id,
    required this.type,
    required this.globalCoordinates,
    required this.localX,
    required this.localY,
    this.macAddress, 
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name, 
      'lat': globalCoordinates.latitude,
      'lng': globalCoordinates.longitude,
      'localX': localX,
      'localY': localY,
      'macAddress': macAddress, 
    };
  }

  factory IpsNode.fromJson(Map<String, dynamic> json) {
    return IpsNode(
      id: json['id'],
      type: NodeType.values.firstWhere((e) => e.name == json['type']),
      globalCoordinates: LatLng(json['lat'], json['lng']),
      localX: json['localX'],
      localY: json['localY'],
      macAddress: json['macAddress'], 
    );
  }

  @override
  String toString() {
    return '${type.name.toUpperCase()} "$id" ${macAddress != null ? '[$macAddress]' : ''} -> (x: ${localX.toStringAsFixed(2)}m, y: ${localY.toStringAsFixed(2)}m)';
  }
}