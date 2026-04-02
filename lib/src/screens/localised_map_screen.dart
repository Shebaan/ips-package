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
  // This controller allows us to manipulate the camera programmatically
  final TransformationController _transformationController = TransformationController();
  // The current rotation of the map in radians
  double _rotationAngle = 0.0;

  @override
  void initState() {
    super.initState();
    // Once the screen finishes drawing, zoom out and center
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resetAndCenterView();
    });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  // Math to center the massive 3000x3000 canvas and zoom out
  void _resetAndCenterView() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    const double targetScale = 0.4; // Start at 40% zoom

    final double xOffset = (3000 * targetScale - screenWidth) / 2;
    final double yOffset = (3000 * targetScale - screenHeight) / 2;

    _transformationController.value = Matrix4.identity()
      ..translate(-xOffset, -yOffset)
      ..scale(targetScale);
  }

  // The math to handle manual zoom button clicks
  void _zoom(double factor) {
    final matrix = _transformationController.value.clone();
    // Multiply the current zoom level by the factor
    matrix.scale(factor, factor, 1.0);
    _transformationController.value = matrix;
  }

  void _rotate(bool clockwise) {
    setState(() {
      // 0.785398 radians is exactly 45 degrees
      if (clockwise) {
        _rotationAngle += 0.785398;
      } else {
        _rotationAngle -= 0.785398;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Localised Floorplan'),
        backgroundColor: Colors.blueGrey,
        foregroundColor: Colors.white,
      ),
      // Use a Stack to float buttons over the map
      body: Stack(
        children: [
          // THE MAP
          InteractiveViewer(
            transformationController: _transformationController,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            minScale: 0.05, // Allowed to zoom out extremely far
            maxScale: 5.0,
            constrained: false,
            
            // Wrap the CustomPaint in a listener so it redraws live
            child: widget.locationEngine == null 
              ? Transform.rotate(
                  angle: _rotationAngle, // <-- APPLIED ROTATION HERE
                  child: CustomPaint(
                    size: const Size(3000, 3000),
                    painter: FloorplanPainter(
                      corners: widget.corners, 
                      routers: widget.routers,
                      userPos: null, // No live tracking active
                    ),
                  ),
                )
              : ValueListenableBuilder<Map<String, double>?>(
                  valueListenable: widget.locationEngine!.liveLocalPosition,
                  builder: (context, livePos, child) {
                    return Transform.rotate(
                      angle: _rotationAngle, // <-- APPLIED ROTATION HERE
                      child: CustomPaint(
                        size: const Size(3000, 3000),
                        painter: FloorplanPainter(
                          corners: widget.corners, 
                          routers: widget.routers,
                          userPos: livePos, // Feed the live coordinates to the painter
                        ),
                      ),
                    );
                  },
                ),
          ),

          // THE ZOOM & ROTATE BUTTONS
          Positioned(
            bottom: 30,
            right: 20,
            child: Column(
              children: [
                // <-- ADDED ROTATE BUTTONS HERE
                FloatingActionButton(
                  heroTag: 'rotate_left',
                  mini: true,
                  backgroundColor: Colors.blueGrey,
                  foregroundColor: Colors.white,
                  onPressed: () => _rotate(false),
                  child: const Icon(Icons.rotate_left),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: 'rotate_right',
                  mini: true,
                  backgroundColor: Colors.blueGrey,
                  foregroundColor: Colors.white,
                  onPressed: () => _rotate(true),
                  child: const Icon(Icons.rotate_right),
                ),
                const SizedBox(height: 10),
                // Existing Zoom Buttons
                FloatingActionButton(
                  heroTag: 'zoom_in',
                  mini: true,
                  onPressed: () => _zoom(1.3), // Zoom in by 30%
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: 'zoom_out',
                  mini: true,
                  onPressed: () => _zoom(0.7), // Zoom out by 30%
                  child: const Icon(Icons.remove),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: 'reset_view',
                  mini: true,
                  backgroundColor: Colors.blueGrey,
                  foregroundColor: Colors.white,
                  onPressed: _resetAndCenterView,
                  child: const Icon(Icons.center_focus_strong),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// THE PAINTER 
class FloorplanPainter extends CustomPainter {
  final List<IpsNode> corners;
  final List<IpsNode> routers;
  final Map<String, double>? userPos; // Added user position variable
  
  final double scale = 20.0; 

  // Updated constructor
  FloorplanPainter({
    required this.corners, 
    required this.routers,
    required this.userPos,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), gridPaint);
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), gridPaint);

    if (corners.isNotEmpty) {
      final pathPaint = Paint()
        ..color = Colors.blueAccent.withOpacity(0.2)
        ..style = PaintingStyle.fill;
        
      final borderPaint = Paint()
        ..color = Colors.blueAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      final path = Path();
      
      for (int i = 0; i < corners.length; i++) {
        final px = center.dx + (corners[i].localX * scale);
        final py = center.dy - (corners[i].localY * scale);

        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      path.close();
      
      canvas.drawPath(path, pathPaint);
      canvas.drawPath(path, borderPaint);
    }

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

    for (var router in routers) {
      final px = center.dx + (router.localX * scale);
      final py = center.dy - (router.localY * scale);
      
      nodePaint.color = Colors.deepOrange;
      canvas.drawCircle(Offset(px, py), 10.0, nodePaint);
      
      final ringPaint = Paint()
        ..color = Colors.deepOrange.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(Offset(px, py), 25.0, ringPaint);
    }

    // 6. DRAW THE LIVE USER LOCATION
    if (userPos != null) {
      // Use the exact same scale/center math to plot the user's local X/Y
      final px = center.dx + (userPos!['x']! * scale);
      final py = center.dy - (userPos!['y']! * scale);
      
      // Draw a soft pulsing halo
      final haloPaint = Paint()..color = Colors.blue.withOpacity(0.3);
      canvas.drawCircle(Offset(px, py), 20.0, haloPaint);

      // Draw the solid center dot
      final userDotPaint = Paint()..color = Colors.blueAccent;
      canvas.drawCircle(Offset(px, py), 10.0, userDotPaint);
      
      // Add a white border to make it pop against the grid
      final userBorder = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(Offset(px, py), 10.0, userBorder);
    }
  }

  @override
  // Ensure it repaints whenever the data changes!
  bool shouldRepaint(covariant FloorplanPainter oldDelegate) {
    return oldDelegate.userPos?['x'] != userPos?['x'] || 
           oldDelegate.userPos?['y'] != userPos?['y'];
  } 
}