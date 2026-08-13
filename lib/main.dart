import 'package:flutter/material.dart';

import 'controllers/app_controller.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AirFlyApp());
}

class AirFlyApp extends StatefulWidget {
  const AirFlyApp({super.key});

  @override
  State<AirFlyApp> createState() => _AirFlyAppState();
}

class _AirFlyAppState extends State<AirFlyApp> {
  final AppController _controller = AppController();

  @override
  void initState() {
    super.initState();
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AirFly',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: HomeScreen(controller: _controller),
    );
  }
}