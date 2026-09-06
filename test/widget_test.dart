import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:airfly/main.dart';

void main() {
  testWidgets('AirFly 启动显示五个页签与状态条', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AirFlyApp());
    await tester.pump();

    // GlassTabBar 为选中/未选中各渲染一份标签，断言存在即可
    expect(find.text('剪切板'), findsWidgets);
    expect(find.text('文件'), findsWidgets);
    expect(find.text('终端'), findsWidgets);
    expect(find.text('设备'), findsWidgets);
    expect(find.text('设置'), findsWidgets);
    expect(find.text('共享剪切板'), findsOneWidget);
  });
}
