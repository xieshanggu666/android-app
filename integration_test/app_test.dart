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
    expect(find.textContaining('车间 OBD-II 蓝牙适配器'), findsOneWidget);
  });

  testWidgets('虚拟设备的模拟读数全程标注，且不进入维修报告', (tester) async {
    await tester.pumpWidget(const ObdAssistantApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('扫描蓝牙 OBD'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 列表第一个“连接”按钮对应虚拟演示设备。
    await tester.tap(find.text('连接').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 数据页：明确提示当前为模拟读数。
    await tester.tap(find.text('数据'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('虚拟演示设备'), findsOneWidget);
    expect(find.textContaining('不会写入维修报告'), findsWidgets);

    // 等待至少一帧模拟读数到达。
    await tester.pump(const Duration(seconds: 1));

    // 报告页：即使模拟数值超差，也不出现“实测值偏离”候选原因。
    await tester.tap(find.text('报告'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生成报告草稿'));
    await tester.pumpAndSettle();
    expect(find.textContaining('实测值偏离'), findsNothing);
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
