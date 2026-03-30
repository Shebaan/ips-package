# NovusGuard IPS - Phase 1 Documentation: Anchor Setup & Hardware Scanning

## Phase 1 Overview
The goal of Phase 1 was to engineer the foundation for an Indoor Positioning System (IPS). This phase successfully delivered a mapping interface and data pipeline that allows a user to define a physical building's perimeter, capture the exact physical locations of Wi-Fi routers, scan for their MAC addresses via hardware RF scanning, and save this reference data to persistent storage.

---

## Package Architecture & Core Components
The Flutter package is divided into three distinct layers: UI, Data Models, and Math/Services.

### UI Layer
* **`MapCollectionScreen` (`map_collection_screen.dart`)**
  * A two-phase interactive Google Maps interface.
  * **Phase 1 (Corners):** The user taps to drop pins defining the N-sided perimeter of the building. The first pin dropped becomes the Origin Node `(0,0)`.
  * **Phase 2 (Routers):** The user drops pins representing Wi-Fi routers. This intercepts the tap and opens a dialog to capture the router's BSSID (MAC Address).
  * **Hardware Integration:** Utilizes the `wifi_scan` package to perform native Android airwave scans, populating a bottom sheet with nearby networks sorted by signal strength (RSSI).
* **Usage:** It must be launched via a `Navigator.push` and awaited. Upon successful completion, it returns a `Map<String, dynamic>` containing the raw corners and routers data. Returns `null` if the user cancels.

### Data Models
* **`IpsNode` (`ips_node.dart`)**
  * The unified data structure representing any critical point in the building.

| Field | Explanation |
| :--- | :--- |
| **id** | Unique string identifier. |
| **type** | Enum (`NodeType.origin`, `NodeType.corner`, `NodeType.router`). |
| **globalCoordinates** | Real-world `LatLng`. |
| **localX / localY** | Cartesian coordinates in meters relative to the Origin. |
| **macAddress** | Nullable string `String?` representing the Wi-Fi fingerprint (used only by routers). |

  * Includes `toJson` and `fromJson` serialization for persistent local storage.
* **Usage:** Used entirely internally by the package to format data for persistent local storage.

### Service & Math Layer
* **`CoordinateConverter` (`coordinate_convertor.dart`)**
  * Handles the spatial flattening math to convert spherical Earth coordinates into a flat, readable 2D grid.
  * Uses the standard approximation: 1 meter ≈ 0.000009° (at the equator).
* **Usage:** Internal package utility.

* **`AnchorManager` (`anchor_manager.dart`)**
  * The central service that catches the raw data from the UI layer.
  * Extracts the raw `LatLng` and MAC address strings from the returned UI dictionary.
  * Passes coordinates through the `CoordinateConverter` to calculate `localX` and `localY`.
  * Instantiates the `IpsNode` objects and saves the final grid to the device's hard drive.
* **Usage:** Instantiated in the host application specifically to process the data returned by the `MapCollectionScreen`.

---

## Integration Example: Connecting the Layers
The architecture utilizes strict separation of concerns. The UI layer (`main.dart`) does not unpack or validate the raw mapping data. It passes the raw dictionary directly to the Service layer (`AnchorManager`), which handles validation, extraction, and mathematical processing, returning a simple boolean to the UI.

```dart
import 'package:ips_package/src/screens/map_collection_screen.dart';
import 'package:ips_package/src/services/anchor_manager.dart';

// Instantiate the service
final AnchorManager _anchorManager = AnchorManager();

void _startSetup(BuildContext context) async {
  print("Opening Map Screen...");

  // 1. Launch the UI Layer and wait for the user to finish
  final result = await Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => MapCollectionScreen()),
  );

  print("Map Screen Closed. Raw Result: $result");

  // 2. Check if the user cancelled the setup
  if (result == null) {
    print("User hit the back button. Setup cancelled.");
    return;
  }

  // 3. Verify the data type and hand off to the Service Layer
  if (result is Map<String, dynamic>) {
    print("Handing off raw data to AnchorManager for validation and processing...");

    final bool isSuccess = _anchorManager.processBuildingData(result);

    // 4. React to the Service Layer's validation output
    if (isSuccess) {
      print('Successfully mapped building and saved Wi-Fi anchors!');
      // Update UI state or show success SnackBar here
    } else {
      print('Invalid data received. Please try the setup again.');
      // Show error SnackBar here
    }
  } else {
    print("Error: The returned data was not in the expected dictionary format.");
  }
}