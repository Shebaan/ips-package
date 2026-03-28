import 'package:google_maps_flutter/google_maps_flutter.dart';

enum NodeType { origin, corner, router }

class IpsNode {
  final String id;
  final NodeType type;
  final LatLng globalCoordinates; 
  final double localX;            
  final double localY;            

  IpsNode({
    required this.id,
    required this.type,
    required this.globalCoordinates,
    required this.localX,
    required this.localY,
  });

  // Convert Object TO JSON (For Saving)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name, // Saves 'origin', 'corner', or 'router'
      'lat': globalCoordinates.latitude,
      'lng': globalCoordinates.longitude,
      'localX': localX,
      'localY': localY,
    };
  }

  // Rebuild Object FROM JSON (For Loading)
  factory IpsNode.fromJson(Map<String, dynamic> json) {
    return IpsNode(
      id: json['id'],
      type: NodeType.values.firstWhere((e) => e.name == json['type']),
      globalCoordinates: LatLng(json['lat'], json['lng']),
      localX: json['localX'],
      localY: json['localY'],
    );
  }

  @override
  String toString() {
    return '${type.name.toUpperCase()} "$id" -> (x: ${localX.toStringAsFixed(2)}m, y: ${localY.toStringAsFixed(2)}m)';
  }
}