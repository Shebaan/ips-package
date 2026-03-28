import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Import your package UI and logic
import 'package:ips_package/ips_package.dart';
import 'package:ips_package/src/services/anchor_manager.dart';

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

// 1. Upgraded to StatefulWidget so it can remember data!
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 2. These variables live at the class level now, so ALL functions can see them.
  final AnchorManager _anchorManager = AnchorManager();
  bool _hasSavedGrid = false;

  @override
  void initState() {
    super.initState();
    _checkSavedData();
  }

  // 3. Automatically check the hard drive when the app opens
  Future<void> _checkSavedData() async {
    final hasData = await _anchorManager.loadGridFromDisk();
    setState(() {
      _hasSavedGrid = hasData;
    });
  }

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

    try {
      final Map<String, dynamic> data = Map<String, dynamic>.from(result as Map);
      final List<LatLng> corners = List<LatLng>.from(data['corners']);
      final List<LatLng> routers = List<LatLng>.from(data['routers']);

      print("Data extracted! Corners: ${corners.length}, Routers: ${routers.length}");
      print("Handing off to AnchorManager...");
      
      // 4. Use the class-level _anchorManager here!
      _anchorManager.processBuildingData(corners: corners, routers: routers);
      
      // 5. Tell the UI we now have data
      setState(() {
        _hasSavedGrid = true;
      });
      
    } catch (e) {
      print("Error parsing the returned data: $e");
    }
  }

  // 6. Matched the UK spelling!
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
            
            const SizedBox(height: 20),
            
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