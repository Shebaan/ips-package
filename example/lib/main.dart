import 'package:flutter/material.dart';
// Import the screen from your package!
import 'package:ips_package/ips_package.dart';

void main() {
  runApp(const IpsTestApp());
}

class IpsTestApp extends StatelessWidget {
  const IpsTestApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IPS Package Tester',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      // Call your package's screen here
      home: MapCollectionScreen(), 
    );
  }
}