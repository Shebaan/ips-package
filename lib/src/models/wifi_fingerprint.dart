class WifiFingerprint {
  // Map of <MAC Address, RSSI Signal Strength>
  // Example: {"00:14:22:01:23:45": -65, "00:14:22:01:23:46": -70}
  final Map<String, int> accessPoints;
  
  // Record exactly when the scan happened
  final DateTime timestamp;

  WifiFingerprint({
    required this.accessPoints,
    required this.timestamp,
  });

  // A helper method to easily see how many routers the phone heard
  int get routerCount => accessPoints.length;
}