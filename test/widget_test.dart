import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:airfly/main.dart';

void main() {
  testWidgets('AirFly 启动显示四个页签与状态条', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AirFlyApp());
    await tester.pump();

    expect(find.text('剪切板'), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('设备'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('共享剪切板'), findsOneWidget);
  });
}
