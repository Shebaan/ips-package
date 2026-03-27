import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Import your package UI
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

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  void _startSetup(BuildContext context) async {
    print("Opening Map Screen...");
    
    // Open the screen and wait
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => MapCollectionScreen()),
    );

    // Process results
    print("Map Screen Closed. Raw Result: $result");

    if (result == null) {
      print("User hit the back button. Setup cancelled.");
      return;
    }

    // Safely extract the data
    try {
      final Map<String, dynamic> data = Map<String, dynamic>.from(result as Map);
      final List<LatLng> corners = List<LatLng>.from(data['corners']);
      final List<LatLng> routers = List<LatLng>.from(data['routers']);

      print("Data extracted! Corners: ${corners.length}, Routers: ${routers.length}");
      print("Handing off to AnchorManager...");
      
      // Run the math function to convert to local coordinates and save to disk
      final anchorManager = AnchorManager();
      anchorManager.processBuildingData(corners: corners, routers: routers);
      
    } catch (e) {
      print("Error parsing the returned data: $e");
    }
  }

  // Placeholder function for next commit
  void _viewLocalisedMap(BuildContext context) {
    print("Navigating to Localised Map...");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Localised Map Screen coming soon!')),
    );
    
    // TODO: In next commit, replace the SnackBar with a Navigator.push
    // to new CustomPaint 2D blueprint screen.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IPS Package Tester'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Button 1: Map Setup
            ElevatedButton.icon(
              onPressed: () => _startSetup(context),
              icon: const Icon(Icons.add_location_alt),
              label: const Text('Start Map Setup', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
            
            const SizedBox(height: 20), // Breathing room between buttons
            
            // Button 2: View Localised Map
            ElevatedButton.icon(
              onPressed: () => _viewLocalisedMap(context),
              icon: const Icon(Icons.architecture),
              label: const Text('View Localised Map', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}