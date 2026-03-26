class ReferencePoint {
  final String id;           // E.g. "North-West Corner"
  final double latitude;     // Real-world GPS Lat
  final double longitude;    // Real-world GPS Long
  final double localX;       // Meters from origin (usually 0.0 for the main anchor)
  final double localY;       // Meters from origin (usually 0.0 for the main anchor)
  final Map<String, int> wifiFingerprint; // e.g., {"MAC_ADDRESS_1": -45, "MAC_ADDRESS_2": -60}

  // Constructor
  ReferencePoint({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.localX,
    required this.localY,
    required this.wifiFingerprint,
  });
}