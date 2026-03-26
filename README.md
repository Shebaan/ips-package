<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/tools/pub/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/to/develop-packages).
-->

# ips-package

A pure Dart/Flutter package designed to provide real-time indoor location tracking. Because GPS signals cannot penetrate buildings, this package bridges the gap by using Wi-Fi RSSI (Received Signal Strength Indicator) and the Weighted K-Nearest Neighbors (WKNN) algorithm to calculate precise indoor coordinates.

## Features

* **Real-time Wi-Fi Scanning:** Captures raw RSSI data from surrounding Wi-Fi Access Points.
* **Distance Estimation:** Utilizes the Log-Distance Path Loss model to convert signal decibels (dBm) into physical distance (meters).
* **WKNN Trilateration:** Smooths out noisy Wi-Fi signals by weighting the user's position toward the strongest routers, avoiding the pitfalls of pure geometric trilateration.
* **Coordinate Anchoring:** Seamlessly translates local indoor movement `(X, Y in meters)` into global Geographic Coordinates `(Latitude, Longitude)` so indoor tracking can interface with standard map UI.

## Platform Limitations

**This package is Android-only.** Due to strict privacy restrictions imposed by Apple, iOS completely blocks third-party applications from reading raw Wi-Fi network data and RSSI strengths. If this package is run on an iOS device, the Wi-Fi scanning features will fail silently.

