import 'package:airfly/controllers/app_controller.dart';
import 'package:airfly/models/clipboard_item.dart';
import 'package:airfly/screens/home_screen.dart';
import 'package:airfly/theme/app_theme.dart';
import 'package:airfly/theme/forui_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 测试专用的主题包装，与 main.dart 保持一致（Forui 亮/暗 + Material 派生）。
Widget _wrapForTest(Widget home, ThemeMode mode) {
  final light = airFlyTheme(Brightness.light);
  final dark = airFlyTheme(Brightness.dark);
  return MaterialApp(
    theme: airFlyMaterial(Brightness.light),
    darkTheme: airFlyMaterial(Brightness.dark),
    themeMode: mode,
    builder: (context, child) => FTheme(
      data: Theme.brightnessOf(context) == Brightness.light ? light : dark,
      child: child!,
    ),
    home: home,
  );
}

void main() {
  testWidgets('深色模式下五个页签均可正常构建', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'af_theme_mode': 'dark'});
    final controller = AppController();
    // initialize() 含真 IO（终端初始目录探测），必须包在 runAsync 里，
    // 否则 FakeAsync 下永远等不到 IO 完成。
    await tester.runAsync(() => controller.initialize());
    expect(controller.themeMode.value, ThemeMode.dark);

    await tester.pumpWidget(
      _wrapForTest(
        HomeScreen(controller: controller),
        controller.themeMode.value,
      ),
    );
    await tester.pump();

    // 暗夜调色板应生效（GlassTabBar 选中/未选中各渲染一份标签，取第一份）
    final context = tester.element(find.text('剪切板').first);
    expect(AppPalette.of(context).isDark, isTrue);

    // 逐一切页，把页面的深色分支都构建出来（同理用 .first 点可命中的那份）
    expect(find.text('共享剪切板'), findsOneWidget);
    await tester.tap(find.text('文件').first);
    await tester.pump();
    expect(find.text('云端文件'), findsOneWidget);
    await tester.tap(find.text('终端').first);
    await tester.pump();
    expect(find.text('本地终端'), findsOneWidget);
    await tester.tap(find.text('设备').first);
    await tester.pump();
    await tester.tap(find.text('设置').first);
    await tester.pump();
    // 外观卡在首屏下方（ListView 懒加载）：先滚再断言。
    // 注意取第一个 Scrollable：FTextField 内部自带 Scrollable，
    // ListView 自己的排最前。
    final settingsList = find.byKey(const Key('settings_list'));
    final settingsScrollable = find
        .descendant(of: settingsList, matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(
      find.descendant(of: settingsList, matching: find.text('外观')),
      300,
      scrollable: settingsScrollable,
    );
    await tester.pump();
    expect(find.text('外观'), findsOneWidget);
    // SegmentedButton 三个选项齐全
    expect(find.text('跟随系统', skipOffstage: false), findsOneWidget);
    expect(find.text('浅色', skipOffstage: false), findsOneWidget);
    expect(find.text('深色', skipOffstage: false), findsOneWidget);

    // 冲掉 Forui 按压态的 100ms 计时器，避免 teardown 断言挂起 timer
    await tester.pump(const Duration(milliseconds: 200));
    controller.dispose();
  });

  testWidgets('主题切换即时生效并持久化', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await tester.runAsync(() => controller.initialize());
    expect(controller.themeMode.value, ThemeMode.system);

    await controller.setThemeMode(ThemeMode.dark);
    expect(controller.themeMode.value, ThemeMode.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('af_theme_mode'), 'dark');

    // 非法存量值回退到跟随系统，不崩
    await prefs.setString('af_theme_mode', 'nope');
    final again = AppController();
    await tester.runAsync(() => again.initialize());
    expect(again.themeMode.value, ThemeMode.system);

    // 冲掉 Forui 按压态的 100ms 计时器，避免 teardown 断言挂起 timer
    await tester.pump(const Duration(milliseconds: 200));
    controller.dispose();
    again.dispose();
  });

  testWidgets('剪切板分页与双时间显示', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await tester.runAsync(() => controller.initialize());
    final now = DateTime.now();
    controller.service.clipHistory = List.generate(
      45,
      (i) => ClipboardItem(
        id: 'c$i',
        text: '内容 $i ' * 5,
        deviceId: 'd',
        deviceName: '测试设备',
        updatedAt: now.subtract(Duration(minutes: i)),
      ),
    );

    await tester.pumpWidget(
      _wrapForTest(
        HomeScreen(controller: controller),
        ThemeMode.light,
      ),
    );
    await tester.pump();

    // 加载更多按钮在 20 张卡之后：先滚再断言/点击
    // （同上，取第一个 Scrollable，避开 FTextField 内部的）
    final list = find.byKey(const Key('clipboard_list'));
    final listScrollable = find
        .descendant(of: list, matching: find.byType(Scrollable))
        .first;
    Future<void> scrollToLoadMore(String label) {
      return tester.scrollUntilVisible(
        find.descendant(of: list, matching: find.textContaining(label)),
        300,
        scrollable: listScrollable,
      );
    }

    await scrollToLoadMore('剩余 25 条');
    await tester.pump();
    expect(find.textContaining('剩余 25 条'), findsOneWidget);
    await tester.tap(find.textContaining('剩余 25 条'));
    // FButton 按下态有约 100ms 延迟才触发 onPress，走完它再断言
    await tester.pump(const Duration(milliseconds: 200));
    // 展开后新按钮在更下方：滚过去再断言（ListView 只构建视口附近）
    await scrollToLoadMore('剩余 5 条');
    await tester.pump();
    expect(find.textContaining('剩余 5 条'), findsOneWidget);

    // 冲掉 Forui 按压态的 100ms 计时器，避免 teardown 断言挂起 timer
    await tester.pump(const Duration(milliseconds: 200));
    controller.dispose();
  });

  testWidgets('剪切板双时间显示', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await tester.runAsync(() => controller.initialize());
    final now = DateTime.now();
    controller.service.clipHistory = [
      ClipboardItem(
        id: 'c-new',
        text: '刚来的',
        deviceId: 'd',
        deviceName: '测试设备',
        updatedAt: now.subtract(const Duration(minutes: 5)),
      ),
      ClipboardItem(
        id: 'c-old',
        text: '去年的',
        deviceId: 'd',
        deviceName: '测试设备',
        updatedAt: DateTime(2024, 3, 5, 14, 30),
      ),
    ];

    // 加高测试画布，保证两张卡都装得下（Forui 输入框比原来高）
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _wrapForTest(
        HomeScreen(controller: controller),
        ThemeMode.light,
      ),
    );
    await tester.pump();

    // 相对 + 绝对同时出现
    expect(find.textContaining('分钟前'), findsOneWidget);
    expect(find.textContaining('2024年3月5日'), findsOneWidget);

    // 冲掉 Forui 按压态的 100ms 计时器，避免 teardown 断言挂起 timer
    await tester.pump(const Duration(milliseconds: 200));
    controller.dispose();
  });

  testWidgets('设置页显示上次记录的值', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'af_server_url': 'ws://10.0.0.5:8080/ws',
      'af_space_id': 'my-space',
      'af_device_name': '测试机',
    });
    final controller = AppController();
    await tester.runAsync(() => controller.initialize());
    await tester.pumpWidget(
      _wrapForTest(
        HomeScreen(controller: controller),
        ThemeMode.light,
      ),
    );
    await tester.pump();
    await tester.tap(find.text('设置'));
    await tester.pump();

    // 连接卡“当前记录”区直接展示（记录行与输入框各一处）
    expect(find.text('ws://10.0.0.5:8080/ws'), findsWidgets);
    // 输入框也被回填（读 EditableText，而非找 Text）
    String field(String key) => tester
        .widget<EditableText>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(EditableText),
          ),
        )
        .controller
        .text;
    expect(field('f_server'), 'ws://10.0.0.5:8080/ws');
    expect(field('f_space'), 'my-space');
    expect(field('f_name'), '测试机');

    // 冲掉 Forui 按压态的 100ms 计时器，避免 teardown 断言挂起 timer
    await tester.pump(const Duration(milliseconds: 200));
    controller.dispose();
  });
}
