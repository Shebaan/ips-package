import '../models/reference_point.dart';

class AnchorManager {
  // The internal "database" list. 
  final List<ReferencePoint> _anchors = [];

  /// Returns a read-only view of the anchors.
  List<ReferencePoint> get anchors => _anchors;

  /// Adds a newly created Reference Point to the database.
  void addAnchor(ReferencePoint point) {
    _anchors.add(point);
  }

  /// Clears all anchors (useful for resetting the map)
  void clearAnchors() {
    _anchors.clear();
  }

  /// Finds the primary "Origin" anchor where (X: 0, Y: 0)
  ReferencePoint? getOriginAnchor() {
    try {
      // Searches the list for the first anchor that matches this condition
      return _anchors.firstWhere(
        (anchor) => anchor.localX == 0.0 && anchor.localY == 0.0,
      );
    } catch (e) {
      // If no origin exists yet, return null
      return null; 
    }
  }
}