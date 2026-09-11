import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_obd_assistant/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offline virtual OBD workflow is visible', (tester) async {
    await tester.pumpWidget(const ObdAssistantApp());
    await tester.pumpAndSettle();

    expect(find.text('故障排查助手'), findsOneWidget);
    expect(find.text('离线可用'), findsOneWidget);
    expect(find.text('扫描蓝牙 OBD'), findsOneWidget);

    await tester.tap(find.text('扫描蓝牙 OBD'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('虚拟 ELM327 / 离线演示'), findsOneWidget);
  });
}
