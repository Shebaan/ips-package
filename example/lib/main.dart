import 'package:flutter/material.dart';

// Import your package UI and logic
import 'package:ips_package/ips_package.dart';

void main() {
  runApp(const IpsTestApp());
}

class IpsTestApp extends StatelessWidget {
  const IpsTestApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IPS Package Tester',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomeScreen(), 
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 1. Core Services
  final AnchorManager _anchorManager = AnchorManager();
  late final LocationEngine _locationEngine;

  // 2. UI State Variables
  bool _hasSavedGrid = false;
  bool _isTracking = false;

  @override
  void initState() {
    super.initState();
    // Initialize the new Week 2 Location Engine
    _locationEngine = LocationEngine(anchorManager: _anchorManager);
    _checkSavedData();
  }

  @override
  void dispose() {
    // CRITICAL: Stop the background scanner when the app closes to save battery
    _locationEngine.stopTracking();
    super.dispose();
  }

  // Automatically check the hard drive when the app opens
  Future<void> _checkSavedData() async {
    final hasData = await _anchorManager.loadGridFromDisk();
    setState(() {
      _hasSavedGrid = hasData;
    });
  }

  // W1: Setup Building & Routers
  void _startSetup(BuildContext context) async {
    print("Opening Map Screen...");
    
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => MapCollectionScreen()),
    );

    print("Map Screen Closed. Raw Result: $result");

    if (result == null) {
      print("User hit the back button. Setup cancelled.");
      return;
    }

    if (result is Map<String, dynamic>) {
      print("Handing off raw data to AnchorManager for validation and processing...");
      
      final bool isSuccess = _anchorManager.processBuildingData(result);

      if (isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully mapped building and saved Wi-Fi anchors!')),
        );
        setState(() {
          _hasSavedGrid = true;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid data received. Please try the setup again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else {
      print("Error: The returned data was not in the expected dictionary format.");
    }
  }

  // W1: View Localised 2D Map
  void _viewLocalisedMap(BuildContext context) {
    if (!_hasSavedGrid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please run Map Setup first!')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocalisedMapScreen(
          corners: _anchorManager.buildingCorners,
          routers: _anchorManager.wifiRouters,
          locationEngine: _locationEngine,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IPS Package Tester'),
      ),
      body: Center(
        child: SingleChildScrollView( // Added scroll view in case the screen gets cramped
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // --- WEEK 1 FEATURES ---
              ElevatedButton.icon(
                onPressed: () => _startSetup(context),
                icon: const Icon(Icons.add_location_alt),
                label: const Text('Start Map Setup', style: TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(250, 50),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
              
              const SizedBox(height: 20),
              
              ElevatedButton.icon(
                onPressed: () => _viewLocalisedMap(context),
                icon: const Icon(Icons.architecture),
                label: const Text('View Localised Map', style: TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(250, 50),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),

              const SizedBox(height: 40),

              // --- WEEK 2 FEATURES ---
              // Only show the live tracking UI if a building has actually been mapped
              if (_hasSavedGrid) ...[
                const Divider(thickness: 2, indent: 40, endIndent: 40),
                const SizedBox(height: 20),
                
                ElevatedButton.icon(
                  icon: Icon(_isTracking ? Icons.stop : Icons.play_arrow),
                  label: Text(
                    _isTracking ? 'Stop Live Tracking' : 'Start Live Tracking',
                    style: const TextStyle(fontSize: 18)
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(250, 50),
                    backgroundColor: _isTracking ? Colors.red : Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    setState(() {
                      _isTracking = !_isTracking;
                      if (_isTracking) {
                        _locationEngine.startTracking();
                      } else {
                        _locationEngine.stopTracking();
                      }
                    });
                  },
                ),
                
                const SizedBox(height: 30),

                // Live Coordinate Display Listens to the Engine
                ValueListenableBuilder(
                  valueListenable: _locationEngine.liveLocation,
                  builder: (context, location, child) {
                    if (!_isTracking) {
                      return const Text(
                        'Tracker Stopped',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      );
                    }
                    if (location == null) {
                      return const Text(
                        'Scanning for routers...',
                        style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
                      );
                    }
                    
                    return Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            '📍 Live Position',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Lat: ${location.latitude.toStringAsFixed(6)}\nLng: ${location.longitude.toStringAsFixed(6)}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 18, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}