import 'package:flutter_test/flutter_test.dart';

import 'package:airfly/main.dart';

void main() {
  testWidgets('AirFly app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const AirFlyApp());
    await tester.pump();

    // 验证应用标题存在
    expect(find.text('AirFly'), findsOneWidget);
  });
}