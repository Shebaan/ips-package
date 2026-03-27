/// A fully interactive map screen for collecting Indoor Positioning System (IPS) anchors.
/// 
/// This screen walks the user through a two-step process:
/// 1. Defining the building perimeter (creating an N-sided polygon).
/// 2. Placing internal Wi-Fi routers (RF anchors).
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
//   // Open the screen and wait for the result
//   final result = await Navigator.push(
//     context,
//     MaterialPageRoute(builder: (context) => MapCollectionScreen()),
//   );

//   // Check if the user actually finished the setup (result will be null if they canceled)
//   if (result != null && result is Map<String, List<LatLng>>) {
    
//     // Extract the data
//     final List<LatLng> corners = result['corners']!;
//     final List<LatLng> routers = result['routers']!;

//     // Pass data to anchorManager service for processing and storage
//     final anchorManager = AnchorManager();
//     anchorManager.processBuildingData(corners: corners, routers: routers);
    
//     print('Successfully saved to AnchorManager!');
//   }
// }
//
/// /// ### How to Exit:
/// * **Cancel/Abort:** The user can press the standard back button in the AppBar. This returns `null`.
/// * **Finish/Save:** The user taps "Finish" on the routers phase. This returns a `Map<String, List<LatLng>>`.

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

enum CollectionPhase { corners, routers }

class MapCollectionScreen extends StatefulWidget {
  @override
  _MapCollectionScreenState createState() => _MapCollectionScreenState();
}

class _MapCollectionScreenState extends State<MapCollectionScreen> {
  GoogleMapController? _mapController;
  
  CollectionPhase _currentPhase = CollectionPhase.corners;
  
  List<LatLng> _buildingCorners = [];
  List<LatLng> _routerLocations = [];
  bool _isPerimeterClosed = false;

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

  void _addPoint(LatLng point) {
    setState(() {
      if (_currentPhase == CollectionPhase.corners) {
        if (!_isPerimeterClosed) {
          _buildingCorners.add(point);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Perimeter is locked! Undo to edit, or tap Next.')),
          );
        }
      } else {
        _routerLocations.add(point);
      }
    });
  }

  // Undo Logic
  void _undoLast() {
    setState(() {
      if (_currentPhase == CollectionPhase.corners) {
        if (_isPerimeterClosed) {
          // If closed, the first Undo just opens the shape back up
          _isPerimeterClosed = false;
        } else if (_buildingCorners.isNotEmpty) {
          // If open, delete the last point
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

    for (int i = 0; i < _routerLocations.length; i++) {
      markers.add(
        Marker(
          markerId: MarkerId('router_$i'),
          position: _routerLocations[i],
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(title: 'Wi-Fi Router ${i + 1}'),
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

    // Bundle the collected data into a Map
    final collectedData = {
      'corners': _buildingCorners,
      'routers': _routerLocations,
    };

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Setup Complete!')),
    );

    // Exit the screen and hand the data back to the caller
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
        backgroundColor: Colors.white, // Made AppBar white so black text pops
        foregroundColor: Colors.black, // Makes the back button black
        actions: [
          if (_currentPhase == CollectionPhase.corners)
            TextButton(
              onPressed: () => setState(() => _currentPhase = CollectionPhase.routers),
              // FIX: Black "Next" text
              child: const Text('Next', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
            )
          else
            TextButton(
              onPressed: _saveAndExit,
              // FIX: Black "Finish" text
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