import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_obd_assistant/main.dart';
import 'package:mobile_obd_assistant/models/diagnostics.dart';

void main() {
  const step = GuidedStep(
    id: 'lean_step_2',
    title: '检查进气泄漏',
    method: '检查进气软管、真空管、PCV 和制动助力管，必要时烟雾测试。',
    expected: '修复泄漏后燃油修正应回到 +/-10% 范围。',
    relatedPids: ['stft_b1', 'ltft_b1'],
  );

  Widget host() {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReportStepResults(
            steps: const [step],
            results: [
              StepResult(
                stepId: 'lean_step_2',
                status: StepStatus.fail,
                note: '进气软管接口处开裂，现场烟雾测试确认泄漏。',
                updatedAt: DateTime(2026, 9, 11, 10, 30),
              ),
              StepResult(
                stepId: 'lean_step_3',
                status: StepStatus.pending,
                note: '',
                updatedAt: DateTime(2026, 9, 11, 10, 31),
              ),
            ],
            isDraftSnapshot: true,
          ),
        ),
      ),
    );
  }

  testWidgets('报告区块展示步骤状态、现场备注和判定标准', (tester) async {
    await tester.pumpWidget(host());

    expect(find.text('检查进气泄漏'), findsOneWidget);
    expect(find.text('异常'), findsOneWidget);
    expect(find.textContaining('进气软管接口处开裂'), findsOneWidget);
    expect(find.textContaining('修复泄漏后燃油修正'), findsOneWidget);
    expect(find.textContaining('2026-09-11 10:30'), findsOneWidget);
    expect(find.textContaining('已记录 1/2 步'), findsOneWidget);
  });

  testWidgets('未填写备注的待检测步骤给出明确占位文案', (tester) async {
    await tester.pumpWidget(host());

    expect(find.text('未填写现场备注'), findsOneWidget);
    expect(find.text('待检测'), findsOneWidget);
  });
}
