import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_obd_assistant/main.dart';
import 'package:mobile_obd_assistant/models/diagnostics.dart';

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

  testWidgets('报告草稿包含已记录的步骤结果和现场备注', (tester) async {
    await tester.pumpWidget(const ObdAssistantApp());
    await tester.pumpAndSettle();

    // 进入“步骤”页，把第一步标记为异常并填写现场备注。
    await tester.tap(find.text('步骤'));
    await tester.pumpAndSettle();
    final firstResultDropdown = find
        .widgetWithText(DropdownButtonFormField<StepStatus>, '待测')
        .first;
    await tester.tap(firstResultDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('异常').last);
    await tester.pumpAndSettle();

    const note = '怠速 STFT 持续偏高，疑似进气泄漏。';
    await tester.enterText(find.byType(TextFormField).first, note);
    await tester.pumpAndSettle();

    // 进入“报告”页生成草稿。
    await tester.tap(find.text('报告'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生成报告草稿'));
    await tester.pumpAndSettle();

    expect(find.text('检测步骤记录'), findsOneWidget);
    expect(find.textContaining('已记录 1/'), findsOneWidget);
    expect(find.text('异常'), findsOneWidget);
    expect(find.text(note), findsOneWidget);

    // 生成后再修改步骤，报告应提示草稿过期需要重新生成。
    await tester.tap(find.text('步骤'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '$note 已补做烟雾测试。');
    await tester.pumpAndSettle();
    await tester.tap(find.text('报告'));
    await tester.pumpAndSettle();
    expect(find.textContaining('请重新生成报告草稿'), findsOneWidget);
  });
}
