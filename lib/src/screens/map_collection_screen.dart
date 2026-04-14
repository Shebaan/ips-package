/// A high-precision IPS collection screen using Crosshair-to-Map positioning.
/// Features a forced 2D view, Auto-Grab functionality, and Floor/Z-Axis Tracking.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:sensors_plus/sensors_plus.dart'; // NEW: For the Barometer

enum CollectionPhase { corners, anchors }

class MapCollectionScreen extends StatefulWidget {
  @override
  _MapCollectionScreenState createState() => _MapCollectionScreenState();
}

class _MapCollectionScreenState extends State<MapCollectionScreen> {
  GoogleMapController? _mapController;
  final TextEditingController _hardwareIdController = TextEditingController();
  final TextEditingController _hardwareNameController = TextEditingController(); 
  
  CollectionPhase _currentPhase = CollectionPhase.corners;
  
  List<LatLng> _buildingCorners = [];
  List<Map<String, dynamic>> _hardwareLocations = [];
  bool _isPerimeterClosed = false;
  String _selectedHardwareType = 'WIFI'; 
  
  LatLng _mapCenter = const LatLng(51.5074, -0.1278); 
  bool _hasLocationPermission = false;
  bool _isAutoScanning = false; 

  // --- Z-AXIS TRACKING VARIABLES ---
  int _currentFloor = 1; 
  Map<int, double> _floorPressures = {}; // Stores the calibrated pressure for each floor
  double _livePressure = 0.0;
  StreamSubscription<BarometerEvent>? _barometerSubscription;

  @override
  void initState() {
    super.initState();
    // Start listening to the barometer immediately
    _barometerSubscription = barometerEventStream().listen((BarometerEvent event) {
      if (mounted) {
        setState(() {
          _livePressure = event.pressure;
        });
      }
    });
  }

  @override
  void dispose() {
    _hardwareIdController.dispose();
    _hardwareNameController.dispose();
    _barometerSubscription?.cancel(); // Clean up the sensor
    super.dispose();
  }

  // NEW: Captures the 10-second average pressure for the current floor
  Future<void> _calibrateCurrentFloor() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Calibrating Floor Pressure...\nPlease hold the phone steady."),
          ],
        ),
      ),
    );

    // Collect data for 3 seconds to get a stable average
    List<double> readings = [];
    StreamSubscription<BarometerEvent> tempSub = barometerEventStream().listen((event) {
      readings.add(event.pressure);
    });

    await Future.delayed(const Duration(seconds: 3));
    tempSub.cancel();
    
    if (mounted) Navigator.pop(context); // Close dialog

    if (readings.isNotEmpty) {
      double average = readings.reduce((a, b) => a + b) / readings.length;
      setState(() {
        _floorPressures[_currentFloor] = average;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Floor $_currentFloor calibrated at ${average.toStringAsFixed(2)} hPa')));
    }
  }

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
      _hardwareIdController.clear();
      _hardwareNameController.clear();
      _selectedHardwareType = 'WIFI';
      _isAutoScanning = false; 
      _showHardwareDialog();
    }
  }

  Future<void> _autoGrabStrongest(void Function(void Function()) setStateDialog) async {
    setStateDialog(() => _isAutoScanning = true);
    
    try {
      if (_selectedHardwareType == 'WIFI') {
        await WiFiScan.instance.startScan();
        final results = await WiFiScan.instance.getScannedResults();
        if (results.isNotEmpty) {
          results.sort((a, b) => b.level.compareTo(a.level));
          final best = results.first;
          setStateDialog(() {
            _hardwareIdController.text = best.bssid;
            _hardwareNameController.text = best.ssid.isEmpty ? 'Hidden Network' : best.ssid;
          });
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No Wi-Fi networks found.')));
        }
      } else {
        List<ScanResult> bleResults = [];
        var subscription = FlutterBluePlus.onScanResults.listen((results) => bleResults = results);
        
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 2));
        await Future.delayed(const Duration(seconds: 2));
        subscription.cancel();
        
        final filtered = bleResults.where((r) => r.device.advName.isNotEmpty).toList();
        if (filtered.isNotEmpty) {
          filtered.sort((a, b) => b.rssi.compareTo(a.rssi));
          final best = filtered.first;
          setStateDialog(() {
            _hardwareIdController.text = best.device.remoteId.str;
            _hardwareNameController.text = best.device.advName;
          });
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No named BLE beacons found.')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: Make sure $_selectedHardwareType is turned on.'))
        );
      }
    } finally {
      try {
        setStateDialog(() => _isAutoScanning = false);
      } catch (e) {
        _isAutoScanning = false; 
      }
    }
  }

  Future<void> _showHardwareDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Add Hardware Anchor'),
              content: SingleChildScrollView( 
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // NEW: Shows what floor this anchor will be saved to!
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.blue.withOpacity(0.1),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.layers, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text('Saving to: Floor $_currentFloor', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
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
                          _hardwareNameController.clear();
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _hardwareNameController,
                      decoration: const InputDecoration(labelText: 'Device Name (Optional)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _hardwareIdController,
                      decoration: InputDecoration(labelText: _selectedHardwareType == 'WIFI' ? 'MAC Address' : 'Beacon ID', border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isAutoScanning ? null : () => _autoGrabStrongest(setStateDialog),
                            icon: _isAutoScanning ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.bolt, color: Colors.amber),
                            label: const Text('Auto-Grab', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isAutoScanning ? null : () {
                              Navigator.pop(context); 
                              if (_selectedHardwareType == 'WIFI') {
                                _scanForWifiNetworks();
                              } else {
                                _scanForBluetoothBeacons();
                              }
                            },
                            icon: const Icon(Icons.list),
                            label: const Text('Scan List', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _hardwareLocations.add({
                        'latLng': _mapCenter,
                        'hardwareId': _hardwareIdController.text.trim().isEmpty ? 'UNKNOWN' : _hardwareIdController.text.trim(),
                        'hardwareName': _hardwareNameController.text.trim().isEmpty ? 'Unknown Device' : _hardwareNameController.text.trim(),
                        'hardwareType': _selectedHardwareType,
                        'floor': _currentFloor, // NEW: Binds the beacon to the active floor!
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
    try {
      await WiFiScan.instance.startScan();
      final results = await WiFiScan.instance.getScannedResults();
      results.sort((a, b) => b.level.compareTo(a.level));
      if (!mounted) return;
      _showResultsSheet(
        title: 'Wi-Fi Networks',
        items: results.map((r) => {'name': r.ssid.isEmpty ? 'Hidden' : r.ssid, 'id': r.bssid, 'signal': '${r.level} dBm'}).toList(),
        type: 'WIFI'
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to scan Wi-Fi')));
    }
  }

  Future<void> _scanForBluetoothBeacons() async {
    try {
      List<ScanResult> bleResults = [];
      var subscription = FlutterBluePlus.onScanResults.listen((results) => bleResults = results);
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
      await Future.delayed(const Duration(seconds: 4));
      subscription.cancel();
      
      final filtered = bleResults.where((r) => r.device.advName.isNotEmpty).toList();
      filtered.sort((a, b) => b.rssi.compareTo(a.rssi));

      if (!mounted) return;
      _showResultsSheet(
        title: 'BLE Beacons',
        items: filtered.map((r) => {'name': r.device.advName, 'id': r.device.remoteId.str, 'signal': '${r.rssi} dBm'}).toList(),
        type: 'BLE'
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to scan BLE. Is Bluetooth on?')));
    }
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
                        _hardwareIdController.text = item['id']!;
                        _hardwareNameController.text = item['name']!;
                        _selectedHardwareType = type;
                      });
                      Navigator.pop(context);
                      _showHardwareDialog(); 
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
    
    // NEW: Only draw markers for the CURRENT floor so the map doesn't get messy
    final currentFloorAnchors = _hardwareLocations.where((loc) => loc['floor'] == _currentFloor).toList();
    
    for (int i = 0; i < currentFloorAnchors.length; i++) {
      final loc = currentFloorAnchors[i];
      markers.add(Marker(
        markerId: MarkerId('anchor_${loc['hardwareId']}'),
        position: loc['latLng'],
        icon: BitmapDescriptor.defaultMarkerWithHue(loc['hardwareType'] == 'BLE' ? BitmapDescriptor.hueViolet : BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(title: loc['hardwareName'], snippet: 'Floor ${loc['floor']} | ID: ${loc['hardwareId']}'),
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
              onPressed: () {
                // EXPORT BOTH the anchors AND the pressure baseline data
                Navigator.pop(context, {
                  'corners': _buildingCorners, 
                  'routers': _hardwareLocations,
                  'floorPressures': _floorPressures 
                });
              },
              child: const Text('Finish', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green))
            )
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _mapCenter, zoom: 19, tilt: 0, bearing: 0),
            onMapCreated: (controller) => _mapController = controller,
            markers: _buildMarkers(),
            polylines: _buildPolylines(),
            myLocationEnabled: _hasLocationPermission,
            myLocationButtonEnabled: false,
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
          
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 36), 
                child: Icon(Icons.add_location_alt, color: Colors.redAccent, size: 44),
              ),
            ),
          ),

          // NEW: The Z-Axis / Floor Control Panel
          if (_currentPhase == CollectionPhase.anchors)
            Positioned(
              top: 15, left: 15, right: 15,
              child: Card(
                elevation: 6,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Active Floor:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () => setState(() { if (_currentFloor > 0) _currentFloor--; }),
                              ),
                              Text('$_currentFloor', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: () => setState(() { _currentFloor++; }),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Pressure: ${_livePressure.toStringAsFixed(2)} hPa', style: const TextStyle(color: Colors.grey)),
                          TextButton.icon(
                            icon: Icon(
                              _floorPressures.containsKey(_currentFloor) ? Icons.check_circle : Icons.warning,
                              color: _floorPressures.containsKey(_currentFloor) ? Colors.green : Colors.orange,
                            ),
                            label: Text(_floorPressures.containsKey(_currentFloor) ? 'Calibrated' : 'Calibrate Floor'),
                            onPressed: _calibrateCurrentFloor,
                          )
                        ],
                      )
                    ],
                  ),
                ),
              ),
            )
          else
            Positioned(
              top: 15, left: 15, right: 15,
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    _isPerimeterClosed 
                        ? 'Perimeter Locked. Tap NEXT.' 
                        : 'Move map to a corner and tap [+]',
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