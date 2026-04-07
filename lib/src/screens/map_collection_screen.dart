/// A fully interactive map screen for collecting Indoor Positioning System (IPS) anchors.
/// Supports both Wi-Fi Routers and Bluetooth Low Energy (BLE) Beacons.

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
  // Remembers where the user tapped while switching between dialogs!
  LatLng? _currentTappedPoint;
  bool _hasLocationPermission = false;

  @override
  void dispose() {
    _hardwareIdController.dispose();
    super.dispose();
  }

  Future<void> _addCurrentLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions are denied.')));
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions are permanently denied. Please enable in settings.')));
      return;
    }

    // Turn on the Google Map's blue dot safely!
    setState(() {
      _hasLocationPermission = true;
    });

    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    _addPoint(LatLng(position.latitude, position.longitude));
    _mapController?.animateCamera(CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)));
  }

  /// Displays the dialog to capture Wi-Fi or BLE fingerprint data
  Future<void> _showHardwareDialog() async {

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
                      labelText: _selectedHardwareType == 'WIFI' ? 'MAC Address' : 'Beacon UUID / MAC',
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
                    icon: Icon(_selectedHardwareType == 'WIFI' ? Icons.wifi_find : Icons.bluetooth_searching),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Scan Nearby ${_selectedHardwareType == 'WIFI' ? 'Networks' : 'Beacons'}'),
                    ),
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
                        'latLng': _currentTappedPoint!, // Use the saved tap location
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

  Future<void> _scanForWifiNetworks() async {
    final canStartScan = await WiFiScan.instance.canStartScan();
    if (canStartScan != CanStartScan.yes) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wi-Fi scanning not supported.')));
      return;
    }

    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scanning Wi-Fi...')));
    await WiFiScan.instance.startScan();
    final results = await WiFiScan.instance.getScannedResults();
    results.sort((a, b) => b.level.compareTo(a.level));

    if (!mounted) return;
    _showResultsSheet(
      title: 'Wi-Fi Networks',
      items: results.map((r) => {'name': r.ssid.isEmpty ? 'Hidden Network' : r.ssid, 'id': r.bssid, 'signal': '${r.level} dBm'}).toList(),
      type: 'WIFI'
    );
  }

  Future<void> _scanForBluetoothBeacons() async {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scanning Bluetooth...')));
    
    List<ScanResult> bleResults = [];
    var subscription = FlutterBluePlus.onScanResults.listen((results) {
      bleResults = results;
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
    await Future.delayed(const Duration(seconds: 4));
    subscription.cancel();

    bleResults.sort((a, b) => b.rssi.compareTo(a.rssi));

    if (!mounted) return;
    _showResultsSheet(
      title: 'BLE Beacons',
      items: bleResults.map((r) => {'name': r.device.advName.isEmpty ? 'Unknown Beacon' : r.device.advName, 'id': r.device.remoteId.str, 'signal': '${r.rssi} dBm'}).toList(),
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
              child: items.isEmpty
                  ? const Center(child: Text('No devices found.'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          leading: Icon(type == 'WIFI' ? Icons.wifi : Icons.bluetooth),
                          title: Text(item['name']!),
                          subtitle: Text('ID: ${item['id']} | Signal: ${item['signal']}'),
                          onTap: () {
                            setState(() {
                              _hardwareIdController.text = item['id']!;
                              _selectedHardwareType = type;
                            });
                            Navigator.pop(context);
                            _showHardwareDialog(); // Re-open dialog without needing coordinates
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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Perimeter is locked! Undo to edit, or tap Next.')));
        }
      });
    } else {
      _currentTappedPoint = point; // Save the point globally

      _hardwareIdController.clear();
      _selectedHardwareType = 'WIFI';
      _showHardwareDialog();
    }
  }

  void _undoLast() {
    setState(() {
      if (_currentPhase == CollectionPhase.corners) {
        if (_isPerimeterClosed) {
          _isPerimeterClosed = false;
        } else if (_buildingCorners.isNotEmpty) {
          _buildingCorners.removeLast();
        }
      } else if (_currentPhase == CollectionPhase.anchors && _hardwareLocations.isNotEmpty) {
        _hardwareLocations.removeLast();
      }
    });
  }

  void _resetAll() {
    setState(() {
      _buildingCorners.clear();
      _hardwareLocations.clear();
      _isPerimeterClosed = false;
      _currentPhase = CollectionPhase.corners;
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
        infoWindow: InfoWindow(title: isOrigin ? 'Origin Node (0,0)' : 'Corner ${i + 1}'),
        onTap: () {
          if (isOrigin && _currentPhase == CollectionPhase.corners && _buildingCorners.length >= 3) {
            setState(() { _isPerimeterClosed = true; });
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Perimeter closed successfully!')));
          }
        },
      ));
    }

    for (int i = 0; i < _hardwareLocations.length; i++) {
      final pos = _hardwareLocations[i]['latLng'] as LatLng;
      final hwId = _hardwareLocations[i]['hardwareId'] as String;
      final hwType = _hardwareLocations[i]['hardwareType'] as String;

      markers.add(Marker(
        markerId: MarkerId('anchor_$i'),
        position: pos,
        icon: BitmapDescriptor.defaultMarkerWithHue(hwType == 'BLE' ? BitmapDescriptor.hueViolet : BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(title: '$hwType Anchor ${i + 1}', snippet: 'ID: $hwId'),
      ));
    }

    return markers;
  }

  Set<Polyline> _buildPolylines() {
    if (_buildingCorners.length < 2) return {};
    List<LatLng> polylinePoints = List.from(_buildingCorners);
    if (_isPerimeterClosed) polylinePoints.add(_buildingCorners.first); 
    return {Polyline(polylineId: const PolylineId('building_perimeter'), points: polylinePoints, color: Colors.blueAccent, width: 4)};
  }

  void _saveAndExit() {
    if (_buildingCorners.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You must define a building perimeter first.')));
      return;
    }

    final collectedData = {
      'corners': _buildingCorners,
      'routers': _hardwareLocations, // Key remains 'routers' to map directly to AnchorManager ingestion
    };

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Setup Complete!')));
    if (Navigator.canPop(context)) {
      Navigator.pop(context, collectedData);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentPhase == CollectionPhase.corners ? '1. Map Building Corners' : '2. Place Hardware Anchors', style: const TextStyle(fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          if (_currentPhase == CollectionPhase.corners)
            TextButton(onPressed: () => setState(() => _currentPhase = CollectionPhase.anchors), child: const Text('Next', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)))
          else
            TextButton(onPressed: _saveAndExit, child: const Text('Finish', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)))
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(target: LatLng(51.5074, -0.1278), zoom: 15),
            onMapCreated: (controller) => _mapController = controller,
            onTap: _addPoint,
            markers: _buildMarkers(),
            polylines: _buildPolylines(),
            myLocationEnabled: _hasLocationPermission,
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
                      : 'Place Wi-Fi or BLE Anchors inside the perimeter.',
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
          FloatingActionButton.extended(heroTag: "btn_loc", onPressed: _addCurrentLocation, icon: const Icon(Icons.my_location), label: const Text('Use My Location'), backgroundColor: Colors.indigo, foregroundColor: Colors.white),
          const SizedBox(height: 12),
          FloatingActionButton.extended(heroTag: "btn_undo", onPressed: _undoLast, icon: const Icon(Icons.undo), label: const Text('Undo Last'), backgroundColor: Colors.grey[800], foregroundColor: Colors.white),
          const SizedBox(height: 12),
          FloatingActionButton.extended(heroTag: "btn_reset", onPressed: _resetAll, icon: const Icon(Icons.clear_all), label: const Text('Reset All'), backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
        ],
      ),
    );
  }
}