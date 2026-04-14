import 'package:flutter/material.dart';
import '../models/ips_node.dart';
import '../services/location_engine.dart';

class LocalisedMapScreen extends StatefulWidget {
  final List<IpsNode> corners;
  final List<IpsNode> routers;
  final LocationEngine? locationEngine;

  const LocalisedMapScreen({
    Key? key,
    required this.corners,
    required this.routers,
    this.locationEngine,
  }) : super(key: key);

  @override
  State<LocalisedMapScreen> createState() => _LocalisedMapScreenState();
}

class _LocalisedMapScreenState extends State<LocalisedMapScreen> {
  final TransformationController _transformationController = TransformationController();
  double _rotationAngle = 0.0;

  // Z-Axis UI State
  int? _selectedFloorOverride; 
  List<int> _availableFloors = [];

  @override
  void initState() {
    super.initState();
    
    // Dynamically figure out how many floors we mapped during setup
    _availableFloors = widget.routers.map((r) => r.floor ?? 1).toSet().toList();
    _availableFloors.sort(); 
    if (_availableFloors.isEmpty) _availableFloors = [1]; 

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resetAndCenterView();
    });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _resetAndCenterView() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    const double targetScale = 0.4; 

    final double xOffset = (3000 * targetScale - screenWidth) / 2;
    final double yOffset = (3000 * targetScale - screenHeight) / 2;

    _transformationController.value = Matrix4.identity()
      ..translate(-xOffset, -yOffset)
      ..scale(targetScale);
  }

  void _zoom(double factor) {
    final matrix = _transformationController.value.clone();
    matrix.scale(factor, factor, 1.0);
    _transformationController.value = matrix;
  }

  void _rotate(bool clockwise) {
    setState(() {
      if (clockwise) {
        _rotationAngle += 0.785398;
      } else {
        _rotationAngle -= 0.785398;
      }
    });
  }

  // --- OPTIMIZED CANVAS BUILDER ---
  Widget _buildCanvas(Map<String, double>? livePos, int activeFloor) {
    return Transform.rotate(
      angle: _rotationAngle,
      child: Stack(
        children: [
          // BOTTOM LAYER: The Static Building (Cached, rarely redraws)
          RepaintBoundary(
            child: CustomPaint(
              size: const Size(3000, 3000),
              painter: StaticBuildingPainter(
                corners: widget.corners, 
                anchors: widget.routers,
                activeFloor: activeFloor, 
              ),
            ),
          ),
          // TOP LAYER: The Live User Dot (Redraws instantly on movement)
          RepaintBoundary(
            child: CustomPaint(
              size: const Size(3000, 3000),
              painter: LiveUserPainter(
                userPos: livePos, 
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Localised Floorplan'),
        backgroundColor: Colors.blueGrey,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // THE MAP LAYER
          InteractiveViewer(
            transformationController: _transformationController,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            minScale: 0.05, 
            maxScale: 5.0,
            constrained: false,
            
            child: widget.locationEngine == null 
              ? _buildCanvas(null, _selectedFloorOverride ?? _availableFloors.first)
              : ValueListenableBuilder<int>(
                  valueListenable: widget.locationEngine!.liveFloor,
                  builder: (context, liveFloor, _) {
                    return ValueListenableBuilder<Map<String, double>?>(
                      valueListenable: widget.locationEngine!.liveLocalPosition,
                      builder: (context, livePos, _) {
                        final activeFloor = _selectedFloorOverride ?? liveFloor;
                        return _buildCanvas(livePos, activeFloor);
                      },
                    );
                  },
                ),
          ),

          // THE FLOOR SELECTOR DROPDOWN
          Positioned(
            top: 20,
            left: 20,
            child: Card(
              elevation: 4,
              color: Colors.white.withOpacity(0.9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    value: _selectedFloorOverride,
                    icon: const Icon(Icons.layers, color: Colors.blueGrey),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                    items: [
                      DropdownMenuItem(
                        value: null, 
                        enabled: widget.locationEngine != null,
                        child: Text(widget.locationEngine != null ? 'Live Floor (Auto)' : 'Select Floor:'),
                      ),
                      ..._availableFloors.map((floor) => DropdownMenuItem(
                        value: floor, 
                        child: Text('Level $floor'),
                      )),
                    ],
                    onChanged: (int? newValue) {
                      setState(() {
                        _selectedFloorOverride = newValue;
                      });
                    },
                  ),
                ),
              ),
            ),
          ),

          // THE ZOOM & ROTATE BUTTONS
          Positioned(
            bottom: 30,
            right: 20,
            child: Column(
              children: [
                FloatingActionButton(heroTag: 'rotate_left', mini: true, backgroundColor: Colors.blueGrey, foregroundColor: Colors.white, onPressed: () => _rotate(false), child: const Icon(Icons.rotate_left)),
                const SizedBox(height: 10),
                FloatingActionButton(heroTag: 'rotate_right', mini: true, backgroundColor: Colors.blueGrey, foregroundColor: Colors.white, onPressed: () => _rotate(true), child: const Icon(Icons.rotate_right)),
                const SizedBox(height: 10),
                FloatingActionButton(heroTag: 'zoom_in', mini: true, onPressed: () => _zoom(1.3), child: const Icon(Icons.add)),
                const SizedBox(height: 10),
                FloatingActionButton(heroTag: 'zoom_out', mini: true, onPressed: () => _zoom(0.7), child: const Icon(Icons.remove)),
                const SizedBox(height: 10),
                FloatingActionButton(heroTag: 'reset_view', mini: true, backgroundColor: Colors.blueGrey, foregroundColor: Colors.white, onPressed: _resetAndCenterView, child: const Icon(Icons.center_focus_strong)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- LAYER 1: STATIC BUILDING PAINTER ---
class StaticBuildingPainter extends CustomPainter {
  final List<IpsNode> corners;
  final List<IpsNode> anchors;
  final int activeFloor;
  final double scale = 20.0; 

  StaticBuildingPainter({required this.corners, required this.anchors, required this.activeFloor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // 1. Grid
    final gridPaint = Paint()..color = Colors.grey.withOpacity(0.3)..style = PaintingStyle.stroke..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), gridPaint);
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), gridPaint);

    // 2. Perimeter
    if (corners.isNotEmpty) {
      final pathPaint = Paint()..color = Colors.blueAccent.withOpacity(0.2)..style = PaintingStyle.fill;
      final borderPaint = Paint()..color = Colors.blueAccent..style = PaintingStyle.stroke..strokeWidth = 3.0;
      final path = Path();
      for (int i = 0; i < corners.length; i++) {
        final px = center.dx + (corners[i].localX * scale);
        final py = center.dy - (corners[i].localY * scale);
        i == 0 ? path.moveTo(px, py) : path.lineTo(px, py);
      }
      path.close();
      canvas.drawPath(path, pathPaint);
      canvas.drawPath(path, borderPaint);
    }

    // 3. Corner Nodes
    final nodePaint = Paint()..style = PaintingStyle.fill;
    for (var corner in corners) {
      final px = center.dx + (corner.localX * scale);
      final py = center.dy - (corner.localY * scale);
      if (corner.type == NodeType.origin) {
        nodePaint.color = Colors.green;
        canvas.drawCircle(Offset(px, py), 8.0, nodePaint);
      } else {
        nodePaint.color = Colors.blue;
        canvas.drawCircle(Offset(px, py), 5.0, nodePaint);
      }
    }

    // 4. Hardware Anchors (Filtered by activeFloor)
    final visibleAnchors = anchors.where((a) => a.floor == activeFloor).toList();
    for (var anchor in visibleAnchors) {
      final px = center.dx + (anchor.localX * scale);
      final py = center.dy - (anchor.localY * scale);
      final isBle = anchor.hardwareType == HardwareType.ble;
      final baseColor = isBle ? Colors.deepPurple : Colors.deepOrange;
      
      nodePaint.color = baseColor;
      canvas.drawCircle(Offset(px, py), 10.0, nodePaint);
      canvas.drawCircle(Offset(px, py), 25.0, Paint()..color = baseColor.withOpacity(0.4)..style = PaintingStyle.stroke..strokeWidth = 2.0);
    }
  }

  @override
  bool shouldRepaint(covariant StaticBuildingPainter oldDelegate) {
    return oldDelegate.activeFloor != activeFloor;
  } 
}

// --- LAYER 2: LIVE USER PAINTER ---
class LiveUserPainter extends CustomPainter {
  final Map<String, double>? userPos; 
  final double scale = 20.0; 

  LiveUserPainter({required this.userPos});

  @override
  void paint(Canvas canvas, Size size) {
    if (userPos == null) return;

    final center = Offset(size.width / 2, size.height / 2);
    final px = center.dx + (userPos!['x']! * scale);
    final py = center.dy - (userPos!['y']! * scale);
    
    canvas.drawCircle(Offset(px, py), 20.0, Paint()..color = Colors.blue.withOpacity(0.3));
    canvas.drawCircle(Offset(px, py), 10.0, Paint()..color = Colors.blueAccent);
    canvas.drawCircle(Offset(px, py), 10.0, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.0);
  }

  @override
  bool shouldRepaint(covariant LiveUserPainter oldDelegate) {
    return oldDelegate.userPos?['x'] != userPos?['x'] || oldDelegate.userPos?['y'] != userPos?['y'];
  } 
}