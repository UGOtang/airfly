import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'controllers/app_controller.dart';
import 'screens/home_screen.dart';
import 'theme/forui_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 预热 liquid glass shader，避免首帧白闪（纯异步磁盘 IO，不阻塞窗口出现）
  await LiquidGlassWidgets.initialize();
  runApp(
    LiquidGlassWidgets.wrap(
      // 让 glass 亮暗跟随 MaterialApp 的 ThemeMode，而不是裸 OS 亮度
      brightnessResolver: Theme.maybeBrightnessOf,
      child: const AirFlyApp(),
    ),
  );
}

class AirFlyApp extends StatefulWidget {
  const AirFlyApp({super.key});

  @override
  State<AirFlyApp> createState() => _AirFlyAppState();
}

class _AirFlyAppState extends State<AirFlyApp> with WidgetsBindingObserver {
  final AppController _controller = AppController();

  // 主题实例缓存：FTheme 要求同输入同实例，否则切换时闪烁
  late final FThemeData _light = airFlyTheme(Brightness.light);
  late final FThemeData _dark = airFlyTheme(Brightness.dark);
  late final ThemeData _matLight = airFlyMaterial(Brightness.light);
  late final ThemeData _matDark = airFlyMaterial(Brightness.dark);

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
    // 只监听 themeMode：传输进度等高频通知不再重建整个 MaterialApp
    return ListenableBuilder(
      listenable: _controller.themeMode,
      builder: (context, _) {
        return MaterialApp(
          title: 'AirFly',
          debugShowCheckedModeBanner: false,
          theme: _matLight,
          darkTheme: _matDark,
          themeMode: _controller.themeMode.value,
          supportedLocales: FLocalizations.supportedLocales,
          localizationsDelegates: const [
            ...FLocalizations.localizationsDelegates
          ],
          builder: (context, child) => FTheme(
            data: Theme.brightnessOf(context) == Brightness.light
                ? _light
                : _dark,
            child: FToaster(child: FTooltipGroup(child: child!)),
          ),
          home: HomeScreen(controller: _controller),
        );
      },
    );
  }
}
