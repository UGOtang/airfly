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

class _AirFlyAppState extends State<AirFlyApp> with WidgetsBindingObserver {
  final AppController _controller = AppController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // 应用进入后台，暂停服务以降低功耗
        _controller.onAppPaused();
        break;
      case AppLifecycleState.resumed:
        // 应用回到前台，恢复服务
        _controller.onAppResumed();
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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