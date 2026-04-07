# NovusGuard IPS - Phase 2 Documentation: Live Tracking Engine & WKNN Math

**Goal:** Translate environmental Wi-Fi radio frequencies into precise, physical 2D coordinates on a digital floorplan.

## Core Logic & Physics
Phase 2 operates as the analytical core of the Indoor Positioning System (IPS). It runs on a continuous 3-second lifecycle, executing three distinct operations to determine the user's location:

1. **Signal Acquisition (The Listener):** The device's hardware antenna scans the environment for the Wi-Fi routers mapped during Phase 1. It records the Received Signal Strength Indicator (RSSI) for each router. For context, an RSSI of `-45 dBm` indicates close proximity, while `-80 dBm` indicates a weak, distant signal.
   
2. **Distance Estimation (The Ruler):** Raw signal strength is highly variable. The `MathUtils` service passes the RSSI values through the **Log-Distance Path Loss** formula. This translates invisible radio wave strength into an estimated physical distance in meters (e.g., establishing that the device is approximately 4.2 meters away from Router A).

3. **Coordinate Calculation (WKNN Trilateration):** Once the system has distances to multiple known routers, it utilizes the **Weighted K-Nearest Neighbors (WKNN)** algorithm. WKNN acts as a localised gravity model: the closer the user is to a specific router, the stronger its mathematical "pull" on their calculated position. The algorithm balances these intersecting radii to pinpoint a final `(X, Y)` coordinate on the floorplan.

## Architecture & Key Files

* **`location_engine.dart` (The Orchestrator):** The central service that drives the tracking loop. It manages the 3-second `Timer`, interfaces with the hardware scanner, delegates calculations to the math utilities, and broadcasts the final GPS and local coordinates via `ValueNotifier`.
  
* **`math_utils.dart` (The Calculator):** A library of pure mathematical functions dedicated strictly to Distance Estimation and WKNN calculations. Keeping this isolated ensures the math is highly testable.
  
* **`localised_map_screen.dart` (The Reactive Canvas):** The frontend visualization. This is a purely reactive UI component; it contains no business logic. It simply listens to the state of the `LocationEngine` and dynamically repaints the user's blue tracking dot on the floorplan whenever new coordinates are broadcast.

## Usage & Implementation

To initialize and start the tracking engine within the host application:

```dart
// 1. Initialize the Anchor Manager (Phase 1 data)
final anchorManager = AnchorManager();

// 2. Inject the manager into the Location Engine
final locationEngine = LocationEngine(anchorManager: anchorManager);

// 3. Initiate the 3-second hardware scanning lifecycle
locationEngine.startTracking();

// 4. Attach a listener to react to real-time location updates
locationEngine.liveLocation.addListener(() {
  final currentPos = locationEngine.liveLocation.value;
  if (currentPos != null) {
    print("Active tracking coordinate updated: ${currentPos.latitude}, ${currentPos.longitude}");
  }
});
```

## Developer Note on Simulation

Desktop and mobile emulators do not possess the physical Wi-Fi antennas required for RF scanning. To test the mathematical pipeline and UI rendering locally, set isSimulationMode = true within the LocationEngine. This bypasses hardware restrictions by generating interpolated signal data, effectively simulating a user walking a patrol route between mapped routers.