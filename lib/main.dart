import 'package:flutter/material.dart';

void main() {
  runApp(const HealthKicksApp());
}

class HealthKicksApp extends StatelessWidget {
  const HealthKicksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HealthKicks Mobile',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Text('HealthKicks BLE-to-MQTT Gateway'),
        ),
      ),
    );
  }
}
