/// A fully interactive map screen for collecting Indoor Positioning System (IPS) anchors.
/// 
/// This screen walks the user through a two-step process:
/// 1. Defining the building perimeter (creating an N-sided polygon).
/// 2. Placing internal Wi-Fi routers (RF anchors) and capturing their MAC addresses.
/// 
/// ### Prerequisites for the Host App:
/// * **Android:** Google Maps API key in `AndroidManifest.xml` & Location permissions.
/// * **iOS:** Google Maps API key in `AppDelegate.swift` & Location permissions in `Info.plist`.
/// 
/// ### How to Start & Check Return Data:
/// Launch this screen using `Navigator.push`. Because the user might cancel or 
/// complete the setup, you should `await` the result.
/// 
/// Example usage:
// import 'package:ips_package/src/services/anchor_manager.dart';
//
// void _startSetup(BuildContext context) async {
//   final result = await Navigator.push(
//     context,
//     MaterialPageRoute(builder: (context) => MapCollectionScreen()),
//   );
//
//   if (result != null) {
//     final Map<String, dynamic> data = Map<String, dynamic>.from(result as Map);
//     final List<LatLng> corners = List<LatLng>.from(data['corners']);
//     final List<Map<String, dynamic>> routers = List<Map<String, dynamic>>.from(data['routers']);
//
//     final anchorManager = AnchorManager();
//     anchorManager.processBuildingData(corners: corners, routers: routers);
//   }
// }
//
/// ### How to Exit:
/// * **Cancel/Abort:** The user can press the standard back button in the AppBar. This returns `null`.
/// * **Finish/Save:** The user taps "Finish" on the routers phase. Returns a `Map<String, dynamic>`.

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wifi_scan/wifi_scan.dart';

enum CollectionPhase { corners, routers }

class MapCollectionScreen extends StatefulWidget {
  @override
  _MapCollectionScreenState createState() => _MapCollectionScreenState();
}

class _MapCollectionScreenState extends State<MapCollectionScreen> {
  GoogleMapController? _mapController;
  final TextEditingController _macController = TextEditingController();
  
  CollectionPhase _currentPhase = CollectionPhase.corners;
  
  List<LatLng> _buildingCorners = [];
  // Updated to hold both coordinates and MAC address
  List<Map<String, dynamic>> _routerLocations = [];
  bool _isPerimeterClosed = false;

  @override
  void dispose() {
    _macController.dispose();
    super.dispose();
  }

  Future<void> _addCurrentLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are denied.')),
        );
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permissions are permanently denied. Please enable in settings.')),
      );
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    
    _addPoint(LatLng(position.latitude, position.longitude));
    
    _mapController?.animateCamera(CameraUpdate.newLatLng(
      LatLng(position.latitude, position.longitude)
    ));
  }

  /// Displays the dialog to capture Wi-Fi fingerprint data
  Future<void> _showWifiDialog(LatLng tappedPoint) async {
    _macController.clear();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add Wi-Fi Router'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter the MAC Address (BSSID) for this router, or scan nearby networks.'),
              const SizedBox(height: 16),
              TextField(
                controller: _macController,
                decoration: const InputDecoration(
                  labelText: 'MAC Address (e.g., 00:1A:2B:3C:4D:5E)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _scanForWifiNetworks, // Updated to call the scanner
                icon: const Icon(Icons.wifi_find),
                label: const Text('Scan Nearby Networks'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 40),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _routerLocations.add({
                    'latLng': tappedPoint,
                    'macAddress': _macController.text.trim().isEmpty ? 'UNKNOWN' : _macController.text.trim(),
                  });
                });
                Navigator.pop(context);
              },
              child: const Text('Save Router'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _scanForWifiNetworks() async {
    // 1. Check if the device is capable of scanning
    final canStartScan = await WiFiScan.instance.canStartScan();
    
    if (canStartScan != CanStartScan.yes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Wi-Fi scanning is not supported or permitted on this device. Code: $canStartScan')),
        );
      }
      return;
    }

    // 2. Trigger the hardware scan
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scanning for networks...')),
      );
    }
    
    await WiFiScan.instance.startScan();
    
    // 3. Retrieve the results
    final List<WiFiAccessPoint> accessPoints = await WiFiScan.instance.getScannedResults();

    if (accessPoints.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No networks found. Ensure Wi-Fi is enabled.')),
        );
      }
      return;
    }

    // Sort by signal strength (strongest first)
    accessPoints.sort((a, b) => b.level.compareTo(a.level));

    // 4. Display the results in a Bottom Sheet
    if (!mounted) return;
    
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Nearby Networks',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: accessPoints.length,
                itemBuilder: (context, index) {
                  final ap = accessPoints[index];
                  return ListTile(
                    leading: const Icon(Icons.wifi),
                    title: Text(ap.ssid.isNotEmpty ? ap.ssid : 'Hidden Network'),
                    subtitle: Text('MAC: ${ap.bssid} | Signal: ${ap.level} dBm'),
                    onTap: () {
                      // Auto-fill the text field and close the bottom sheet
                      setState(() {
                        _macController.text = ap.bssid;
                      });
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _addPoint(LatLng point) {
    if (_currentPhase == CollectionPhase.corners) {
      setState(() {
        if (!_isPerimeterClosed) {
          _buildingCorners.add(point);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Perimeter is locked! Undo to edit, or tap Next.')),
          );
        }
      });
    } else {
      // Trigger dialog instead of immediate placement
      _showWifiDialog(point);
    }
  }

  // Undo Logic
  void _undoLast() {
    setState(() {
      if (_currentPhase == CollectionPhase.corners) {
        if (_isPerimeterClosed) {
          _isPerimeterClosed = false;
        } else if (_buildingCorners.isNotEmpty) {
          _buildingCorners.removeLast();
        }
      } else if (_currentPhase == CollectionPhase.routers && _routerLocations.isNotEmpty) {
        _routerLocations.removeLast();
      }
    });
  }

  // Reset everything back to zero
  void _resetAll() {
    setState(() {
      _buildingCorners.clear();
      _routerLocations.clear();
      _isPerimeterClosed = false;
      _currentPhase = CollectionPhase.corners;
    });
  }

  Set<Marker> _buildMarkers() {
    Set<Marker> markers = {};

    for (int i = 0; i < _buildingCorners.length; i++) {
      bool isOrigin = (i == 0);
      markers.add(
        Marker(
          markerId: MarkerId('corner_$i'),
          position: _buildingCorners[i],
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isOrigin ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueBlue,
          ),
          infoWindow: InfoWindow(title: isOrigin ? 'Origin Node (0,0)' : 'Corner ${i + 1}'),
          onTap: () {
            if (isOrigin && _currentPhase == CollectionPhase.corners && _buildingCorners.length >= 3) {
              setState(() {
                _isPerimeterClosed = true;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Perimeter closed successfully!')),
              );
            }
          },
        ),
      );
    }

    // Updated to extract data from the Map structure
    for (int i = 0; i < _routerLocations.length; i++) {
      final pos = _routerLocations[i]['latLng'] as LatLng;
      final mac = _routerLocations[i]['macAddress'] as String;

      markers.add(
        Marker(
          markerId: MarkerId('router_$i'),
          position: pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(title: 'Wi-Fi Router ${i + 1}', snippet: 'MAC: $mac'),
        ),
      );
    }

    return markers;
  }

  Set<Polyline> _buildPolylines() {
    if (_buildingCorners.length < 2) return {};

    List<LatLng> polylinePoints = List.from(_buildingCorners);
    if (_isPerimeterClosed) {
      polylinePoints.add(_buildingCorners.first); 
    }

    return {
      Polyline(
        polylineId: const PolylineId('building_perimeter'),
        points: polylinePoints,
        color: Colors.blueAccent,
        width: 4,
      )
    };
  }

  // Save and Exit logic
  void _saveAndExit() {
    if (_buildingCorners.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must define a building perimeter first.')),
      );
      return;
    }

    final collectedData = {
      'corners': _buildingCorners,
      'routers': _routerLocations,
    };

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Setup Complete!')),
    );

    if (Navigator.canPop(context)) {
      Navigator.pop(context, collectedData);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentPhase == CollectionPhase.corners 
            ? '1. Map Building Corners' 
            : '2. Place Wi-Fi Routers', style: const TextStyle(fontSize: 18),),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          if (_currentPhase == CollectionPhase.corners)
            TextButton(
              onPressed: () => setState(() => _currentPhase = CollectionPhase.routers),
              child: const Text('Next', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
            )
          else
            TextButton(
              onPressed: _saveAndExit,
              child: const Text('Finish', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
            )
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(51.5074, -0.1278), // Default to London
              zoom: 15,
            ),
            onMapCreated: (controller) => _mapController = controller,
            onTap: _addPoint,
            markers: _buildMarkers(),
            polylines: _buildPolylines(),
            myLocationEnabled: true,
            myLocationButtonEnabled: false, 
          ),
          
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  _currentPhase == CollectionPhase.corners
                      ? _buildingCorners.isEmpty 
                          ? 'Place the FIRST node. This is your Origin (0,0).'
                          : _isPerimeterClosed 
                              ? 'Perimeter locked. Tap Next to continue.'
                              : 'Keep placing nodes. Tap the Origin (Green) to close the shape.'
                      : 'Place Wi-Fi routers inside the perimeter.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ),
          )
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: "btn_loc",
            onPressed: _addCurrentLocation,
            icon: const Icon(Icons.my_location),
            label: const Text('Use My Location'),
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: "btn_undo",
            onPressed: _undoLast,
            icon: const Icon(Icons.undo),
            label: const Text('Undo Last'),
            backgroundColor: Colors.grey[800],
            foregroundColor: Colors.white,
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: "btn_reset",
            onPressed: _resetAll,
            icon: const Icon(Icons.clear_all),
            label: const Text('Reset All'),
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
          ),
        ],
      ),
    );
  }
}