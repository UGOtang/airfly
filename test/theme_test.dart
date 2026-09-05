import 'package:airfly/controllers/app_controller.dart';
import 'package:airfly/screens/home_screen.dart';
import 'package:airfly/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('深色模式下四个页签均可正常构建', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'af_theme_mode': 'dark'});
    final controller = AppController();
    // initialize() 含真 IO（终端初始目录探测），必须包在 runAsync 里，
    // 否则 FakeAsync 下永远等不到 IO 完成。
    await tester.runAsync(() => controller.initialize());
    expect(controller.themeMode, ThemeMode.dark);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: controller.themeMode,
        home: HomeScreen(controller: controller),
      ),
    );
    await tester.pump();

    // 暗夜调色板应生效
    final context = tester.element(find.text('剪切板'));
    expect(AppPalette.of(context).isDark, isTrue);

    // 逐一切页，把页面的深色分支都构建出来
    expect(find.text('共享剪切板'), findsOneWidget);
    await tester.tap(find.text('文件'));
    await tester.pump();
    expect(find.text('云端文件'), findsOneWidget);
    await tester.tap(find.text('终端'));
    await tester.pump();
    expect(find.text('本地终端'), findsOneWidget);
    await tester.tap(find.text('设备'));
    await tester.pump();
    await tester.tap(find.text('设置'));
    await tester.pump();
    // 外观卡可能在首屏下方（offstage），不断言可见，只断言已构建
    expect(find.text('外观', skipOffstage: false), findsOneWidget);
    // SegmentedButton 三个选项齐全
    expect(find.text('跟随系统', skipOffstage: false), findsOneWidget);
    expect(find.text('浅色', skipOffstage: false), findsOneWidget);
    expect(find.text('深色', skipOffstage: false), findsOneWidget);

    controller.dispose();
  });

  testWidgets('主题切换即时生效并持久化', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await tester.runAsync(() => controller.initialize());
    expect(controller.themeMode, ThemeMode.system);

    await controller.setThemeMode(ThemeMode.dark);
    expect(controller.themeMode, ThemeMode.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('af_theme_mode'), 'dark');

    // 非法存量值回退到跟随系统，不崩
    await prefs.setString('af_theme_mode', 'nope');
    final again = AppController();
    await tester.runAsync(() => again.initialize());
    expect(again.themeMode, ThemeMode.system);

    controller.dispose();
    again.dispose();
  });
}
