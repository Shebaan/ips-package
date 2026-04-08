/// A high-precision IPS collection screen using Crosshair-to-Map positioning.
/// Features a forced 2D view and ironclad state preservation for hardware scanning.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

enum CollectionPhase { corners, anchors }

class MapCollectionScreen extends StatefulWidget {
  @override
  _MapCollectionScreenState createState() => _MapCollectionScreenState();
}

class _MapCollectionScreenState extends State<MapCollectionScreen> {
  GoogleMapController? _mapController;
  final TextEditingController _hardwareIdController = TextEditingController();
  
  CollectionPhase _currentPhase = CollectionPhase.corners;
  
  List<LatLng> _buildingCorners = [];
  List<Map<String, dynamic>> _hardwareLocations = [];
  bool _isPerimeterClosed = false;
  String _selectedHardwareType = 'WIFI'; 
  
  // Tracks the current center of the map for the crosshair
  LatLng _mapCenter = const LatLng(51.5074, -0.1278); 
  bool _hasLocationPermission = false;

  @override
  void dispose() {
    _hardwareIdController.dispose();
    super.dispose();
  }

  /// Moves the map camera to user's location without dropping a point
  Future<void> _goToMyLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    setState(() => _hasLocationPermission = true);

    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(position.latitude, position.longitude), zoom: 19, tilt: 0, bearing: 0)
      ),
    );
  }

  /// Triggered by the main [+] button. Adds a point at the map's center.
  void _confirmSelectionAtCenter() {
    if (_currentPhase == CollectionPhase.corners) {
      if (_isPerimeterClosed) return;
      setState(() {
        _buildingCorners.add(_mapCenter);
      });
      if (_buildingCorners.length >= 3) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tap the Green Origin marker to close shape.')));
      }
    } else {
      // THE CRITICAL FIX: Only wipe the text box clean on a FRESH [+] tap!
      _hardwareIdController.clear();
      _selectedHardwareType = 'WIFI';
      
      _showHardwareDialog();
    }
  }

  /// Displays dialog for hardware ID, using the map center as the coordinate
  Future<void> _showHardwareDialog() async {
    // Note: No .clear() here anymore, so it retains the ID from the scanner!
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Add Hardware Anchor'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Verify the crosshair is centered on the device's physical location.", style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'WIFI', label: Text('Wi-Fi'), icon: Icon(Icons.wifi)),
                      ButtonSegment(value: 'BLE', label: Text('BLE'), icon: Icon(Icons.bluetooth)),
                    ],
                    selected: {_selectedHardwareType},
                    onSelectionChanged: (Set<String> newSelection) {
                      setStateDialog(() {
                        _selectedHardwareType = newSelection.first;
                        _hardwareIdController.clear();
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _hardwareIdController,
                    decoration: InputDecoration(
                      labelText: _selectedHardwareType == 'WIFI' ? 'MAC Address' : 'Beacon ID',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context); 
                      if (_selectedHardwareType == 'WIFI') {
                        _scanForWifiNetworks();
                      } else {
                        _scanForBluetoothBeacons();
                      }
                    },
                    icon: const Icon(Icons.search),
                    label: Text('Scan Nearby ${_selectedHardwareType}'),
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _hardwareLocations.add({
                        'latLng': _mapCenter,
                        'hardwareId': _hardwareIdController.text.trim().isEmpty ? 'UNKNOWN' : _hardwareIdController.text.trim(),
                        'hardwareType': _selectedHardwareType,
                      });
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Save Anchor'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  // --- Scanning Logic ---

  Future<void> _scanForWifiNetworks() async {
    await WiFiScan.instance.startScan();
    final results = await WiFiScan.instance.getScannedResults();
    results.sort((a, b) => b.level.compareTo(a.level));
    if (!mounted) return;
    _showResultsSheet(
      title: 'Wi-Fi Networks',
      items: results.map((r) => {'name': r.ssid.isEmpty ? 'Hidden' : r.ssid, 'id': r.bssid, 'signal': '${r.level} dBm'}).toList(),
      type: 'WIFI'
    );
  }

  Future<void> _scanForBluetoothBeacons() async {
    List<ScanResult> bleResults = [];
    var subscription = FlutterBluePlus.onScanResults.listen((results) => bleResults = results);
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
    await Future.delayed(const Duration(seconds: 4));
    subscription.cancel();
    
    // Filter out nameless devices for a cleaner UI
    final filtered = bleResults.where((r) => r.device.advName.isNotEmpty).toList();
    filtered.sort((a, b) => b.rssi.compareTo(a.rssi));

    if (!mounted) return;
    _showResultsSheet(
      title: 'BLE Beacons',
      items: filtered.map((r) => {'name': r.device.advName, 'id': r.device.remoteId.str, 'signal': '${r.rssi} dBm'}).toList(),
      type: 'BLE'
    );
  }

  void _showResultsSheet({required String title, required List<Map<String, String>> items, required String type}) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    leading: Icon(type == 'WIFI' ? Icons.wifi : Icons.bluetooth),
                    title: Text(item['name']!),
                    subtitle: Text('ID: ${item['id']} | Signal: ${item['signal']}'),
                    onTap: () {
                      setState(() {
                        // Injects the selected ID back into the controller!
                        _hardwareIdController.text = item['id']!;
                        _selectedHardwareType = type;
                      });
                      Navigator.pop(context);
                      _showHardwareDialog(); // Re-opens safely!
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

  // --- Map Utilities ---

  void _undoLast() {
    setState(() {
      if (_currentPhase == CollectionPhase.corners) {
        if (_isPerimeterClosed) {
          _isPerimeterClosed = false;
        } else if (_buildingCorners.isNotEmpty) {
          _buildingCorners.removeLast();
        }
      } else if (_hardwareLocations.isNotEmpty) {
        _hardwareLocations.removeLast();
      }
    });
  }

  Set<Marker> _buildMarkers() {
    Set<Marker> markers = {};
    for (int i = 0; i < _buildingCorners.length; i++) {
      bool isOrigin = (i == 0);
      markers.add(Marker(
        markerId: MarkerId('corner_$i'),
        position: _buildingCorners[i],
        icon: BitmapDescriptor.defaultMarkerWithHue(isOrigin ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueBlue),
        onTap: () {
          if (isOrigin && _currentPhase == CollectionPhase.corners && _buildingCorners.length >= 3) {
            setState(() => _isPerimeterClosed = true);
          }
        },
      ));
    }
    for (int i = 0; i < _hardwareLocations.length; i++) {
      final loc = _hardwareLocations[i];
      markers.add(Marker(
        markerId: MarkerId('anchor_$i'), // Unique ID so markers don't overwrite each other
        position: loc['latLng'],
        icon: BitmapDescriptor.defaultMarkerWithHue(loc['hardwareType'] == 'BLE' ? BitmapDescriptor.hueViolet : BitmapDescriptor.hueOrange),
      ));
    }
    return markers;
  }

  Set<Polyline> _buildPolylines() {
    if (_buildingCorners.length < 2 || (_currentPhase == CollectionPhase.corners && !_isPerimeterClosed)) return {};
    List<LatLng> polylinePoints = List.from(_buildingCorners);
    polylinePoints.add(_buildingCorners.first); 
    return {Polyline(polylineId: const PolylineId('p1'), points: polylinePoints, color: Colors.blueAccent, width: 4)};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentPhase == CollectionPhase.corners ? '1. Mark Corners' : '2. Place Anchors', style: const TextStyle(fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          if (_currentPhase == CollectionPhase.corners && _isPerimeterClosed)
            TextButton(
              onPressed: () => setState(() => _currentPhase = CollectionPhase.anchors), 
              child: const Text('Next', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black))
            )
          else if (_currentPhase == CollectionPhase.anchors)
            TextButton(
              onPressed: () => Navigator.pop(context, {'corners': _buildingCorners, 'routers': _hardwareLocations}),
              child: const Text('Finish', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green))
            )
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            // Forces 2D Top-Down View
            initialCameraPosition: CameraPosition(target: _mapCenter, zoom: 19, tilt: 0, bearing: 0),
            onMapCreated: (controller) => _mapController = controller,
            markers: _buildMarkers(),
            polylines: _buildPolylines(),
            myLocationEnabled: _hasLocationPermission,
            myLocationButtonEnabled: false,
            
            // Disables 3D gestures to prevent parallax error
            tiltGesturesEnabled: false,
            rotateGesturesEnabled: false,
            mapToolbarEnabled: false,
            
            onCameraMove: (pos) {
              if (pos.tilt != 0 || pos.bearing != 0) {
                _mapController?.animateCamera(CameraUpdate.newCameraPosition(
                  CameraPosition(target: pos.target, zoom: pos.zoom, tilt: 0, bearing: 0)
                ));
              }
              _mapCenter = pos.target;
            },
          ),
          
          // STATIC CENTRAL CROSSHAIR
          const IgnorePointer(
            child: Center(
              child: Padding(
                // Offset perfectly so the "tip" of the pin is the exact center coordinate
                padding: EdgeInsets.only(bottom: 36), 
                child: Icon(Icons.add_location_alt, color: Colors.redAccent, size: 44),
              ),
            ),
          ),

          // Instructions overlay
          Positioned(
            top: 15, left: 15, right: 15,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  _currentPhase == CollectionPhase.corners
                      ? _isPerimeterClosed 
                          ? 'Perimeter Locked. Tap NEXT.' 
                          : 'Move map to a corner and tap [+]'
                      : 'Move map to an Anchor location and tap [+]',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          )
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.large(
            heroTag: "btn_confirm",
            onPressed: _confirmSelectionAtCenter,
            backgroundColor: Colors.blueAccent,
            child: const Icon(Icons.add, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: "btn_gps",
            onPressed: _goToMyLocation,
            backgroundColor: Colors.white,
            child: const Icon(Icons.gps_fixed, color: Colors.black87),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: "btn_undo",
            mini: true,
            onPressed: _undoLast,
            backgroundColor: Colors.grey[800],
            child: const Icon(Icons.undo, color: Colors.white),
          ),
        ],
      ),
    );
  }
}