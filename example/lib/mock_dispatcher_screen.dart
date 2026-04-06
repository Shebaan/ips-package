import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ips_package/src/services/ips_integration_service.dart';

class MockDispatcherScreen extends StatefulWidget {
  final IpsIntegrationService integrationService;

  const MockDispatcherScreen({Key? key, required this.integrationService}) : super(key: key);

  @override
  State<MockDispatcherScreen> createState() => _MockDispatcherScreenState();
}

class _MockDispatcherScreenState extends State<MockDispatcherScreen> {
  GoogleMapController? _mapController;
  LatLng? _currentGuardLocation;
  bool _isAlertActive = false;
  
  StreamSubscription? _locationSub;
  StreamSubscription? _alertSub;

  @override
  void initState() {
    super.initState();
    _listenToGuard();
  }

  void _listenToGuard() {
    _locationSub = widget.integrationService.indoorLocationStream.listen((LatLng newLoc) {
      if (mounted) {
        setState(() {
          _currentGuardLocation = newLoc;
          _isAlertActive = false; // Reset alert if they go back inside
        });
        _mapController?.animateCamera(CameraUpdate.newLatLng(newLoc));
      }
    });

    _alertSub = widget.integrationService.alertStream.listen((String alertType) {
      if (alertType == 'out_of_bounds' && !_isAlertActive && mounted) {
        setState(() => _isAlertActive = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ALERT: Guard has breached the Geofence!'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _alertSub?.cancel();
    super.dispose();
  }

  Set<Polygon> _buildGeofence() {
    final fence = widget.integrationService.patrolRoomGeofence;
    if (fence.isEmpty) return {};

    return {
      Polygon(
        polygonId: const PolygonId('safe_zone'),
        points: fence,
        fillColor: Colors.blue.withOpacity(0.2),
        strokeColor: Colors.blueAccent,
        strokeWidth: 3,
      )
    };
  }

  Set<Marker> _buildGuardMarker() {
    if (_currentGuardLocation == null) return {};

    return {
      Marker(
        markerId: const MarkerId('guard_1'),
        position: _currentGuardLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          _isAlertActive ? BitmapDescriptor.hueRed : BitmapDescriptor.hueGreen,
        ),
        infoWindow: const InfoWindow(title: 'Active Guard'),
      )
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HQ Dispatcher Dashboard'),
        backgroundColor: _isAlertActive ? Colors.red.shade800 : Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          if (_isAlertActive)
            Container(
              width: double.infinity,
              color: Colors.red,
              padding: const EdgeInsets.all(12),
              child: const Text(
                'WARNING: GUARD IS OUT OF BOUNDS',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                // Start the camera exactly where your building is!
                target: widget.integrationService.patrolRoomGeofence.isNotEmpty 
                    ? widget.integrationService.patrolRoomGeofence.first 
                    : const LatLng(0, 0), 
                zoom: 19,
              ),
              onMapCreated: (controller) => _mapController = controller,
              polygons: _buildGeofence(),
              markers: _buildGuardMarker(),
            ),
          ),
        ],
      ),
    );
  }
}