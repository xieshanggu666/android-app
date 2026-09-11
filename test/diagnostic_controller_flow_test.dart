import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_obd_assistant/data/offline_repository.dart';
import 'package:mobile_obd_assistant/data/record_store.dart';
import 'package:mobile_obd_assistant/models/diagnostics.dart';
import 'package:mobile_obd_assistant/services/obd_source.dart';
import 'package:mobile_obd_assistant/state/diagnostic_controller.dart';

class _FakeRepository implements OfflineRepository {
  @override
  Future<List<VehicleProfile>> loadVehicles() async => const [
        VehicleProfile(id: 'v1', name: '测试车型', engine: '1.5T', notes: []),
      ];

  @override
  Future<List<DiagnosticCase>> loadCases() async => const [
        DiagnosticCase(
          id: 'case_a',
          name: '案例 A',
          vehicle: '测试车',
          ecus: ['ECM'],
          codes: [
            TroubleCode(
              code: 'P0171',
              title: '系统过稀',
              ecu: 'ECM',
              severity: '中',
              description: '混合气偏稀',
              relatedPids: ['stft'],
              candidateCauses: ['进气泄漏'],
            ),
          ],
          freezeFrame: FreezeFrame(
            engineRpm: 760,
            vehicleSpeed: 0,
            coolantTemp: 88,
            fuelTrimShort: 18.4,
            fuelTrimLong: 21.8,
            load: 22,
          ),
          steps: [
            GuidedStep(
              id: 'a_step_1',
              title: '查看燃油修正',
              method: '观察 STFT',
              expected: '回到 ±10%',
              relatedPids: ['stft'],
            ),
          ],
          beforeReadings: {'stft': 18.4},
          afterReadings: {'stft': 3.2},
        ),
        DiagnosticCase(
          id: 'case_b',
          name: '案例 B',
          vehicle: '测试车',
          ecus: ['ECM'],
          codes: [
            TroubleCode(
              code: 'P0302',
              title: '二缸失火',
              ecu: 'ECM',
              severity: '高',
              description: '二缸燃烧异常',
              relatedPids: ['misfire'],
              candidateCauses: ['点火线圈异常'],
            ),
          ],
          freezeFrame: FreezeFrame(
            engineRpm: 2140,
            vehicleSpeed: 42,
            coolantTemp: 91,
            fuelTrimShort: 6.1,
            fuelTrimLong: 4.8,
            load: 48,
          ),
          steps: [
            GuidedStep(
              id: 'b_step_1',
              title: '确认失火计数',
              method: '试车观察',
              expected: '计数不再增长',
              relatedPids: ['misfire'],
            ),
          ],
          beforeReadings: {'misfire': 18},
          afterReadings: {'misfire': 0},
        ),
      ];

  @override
  Future<List<PidDefinition>> loadPidCatalog() async => const [
        PidDefinition(
          id: 'stft',
          name: '短期燃油修正',
          unit: '%',
          min: -35,
          max: 35,
          normalLow: -10,
          normalHigh: 10,
        ),
        PidDefinition(
          id: 'misfire',
          name: '二缸失火计数',
          unit: '次',
          min: 0,
          max: 100,
          normalLow: 0,
          normalHigh: 0,
        ),
      ];
}

class _FakeObdSource implements ObdSource {
  _FakeObdSource(this.mode);

  final ConnectionMode mode;
  final StreamController<Map<String, PidReading>> controller =
      StreamController<Map<String, PidReading>>.broadcast();
  ObdDevice? connectedDevice;

  @override
  Stream<List<ObdDevice>> scan() => Stream.value(const []);

  @override
  Future<void> connect(ObdDevice device) async {
    if (device.mode != mode) {
      throw ArgumentError('设备模式 ${device.mode} 与数据源 $mode 不匹配');
    }
    connectedDevice = device;
  }

  @override
  Stream<Map<String, PidReading>> watchPids(DiagnosticCase diagnosticCase) {
    return controller.stream;
  }

  @override
  Future<void> disconnect() async {
    connectedDevice = null;
  }
}

const _virtualDevice = ObdDevice(
  id: 'virtual',
  name: '虚拟 OBD',
  signalStrength: 100,
  mode: ConnectionMode.virtual,
);

const _bluetoothDevice = ObdDevice(
  id: 'bt',
  name: '车间 OBD-II 蓝牙适配器',
  signalStrength: 82,
  mode: ConnectionMode.bluetooth,
);

const _unavailableBluetoothDevice = ObdDevice(
  id: 'bt-placeholder',
  name: '车间 OBD-II 蓝牙适配器（真实蓝牙入口）',
  signalStrength: 0,
  mode: ConnectionMode.bluetooth,
  available: false,
  unavailableReason: BluetoothObdSource.unavailableMessage,
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late ProviderContainer container;
  late DiagnosticController controller;
  late _FakeObdSource virtualSource;
  late _FakeObdSource bluetoothSource;
  late InMemoryRecordStore store;

  Future<void> createController() async {
    container = ProviderContainer(overrides: [
      offlineRepositoryProvider.overrideWithValue(_FakeRepository()),
      recordStoreProvider.overrideWithValue(store),
      virtualObdSourceProvider.overrideWithValue(
        virtualSource = _FakeObdSource(ConnectionMode.virtual),
      ),
      bluetoothObdSourceProvider.overrideWithValue(
        bluetoothSource = _FakeObdSource(ConnectionMode.bluetooth),
      ),
    ]);
    addTearDown(container.dispose);
    controller = container.read(diagnosticControllerProvider.notifier);
    for (var i = 0;
        i < 5 && container.read(diagnosticControllerProvider).loading;
        i++) {
      await _settle();
    }
  }

  setUp(() {
    store = InMemoryRecordStore();
  });

  test('未连接 OBD 时没有实时读数，切换案例也不会注入参考值', () async {
    await createController();
    final state = container.read(diagnosticControllerProvider);

    expect(state.status, ObdConnectionStatus.disconnected);
    expect(state.liveReadings, isEmpty);
    expect(state.history, isEmpty);

    controller.selectCase('case_b');
    await _settle();
    final switched = container.read(diagnosticControllerProvider);

    expect(switched.selectedCase!.id, 'case_b');
    expect(switched.liveReadings, isEmpty,
        reason: '案例的 beforeReadings 不能伪装成实时读数');
    expect(switched.history, isEmpty);
  });

  test('未连接时生成报告，不会把案例参考值写成实测异常', () async {
    await createController();

    controller.selectCase('case_a');
    await _settle();
    await controller.generateReport();
    final report = container.read(diagnosticControllerProvider).report!;

    expect(report.candidateCauses, equals(['进气泄漏']));
    expect(
      report.candidateCauses.any((cause) => cause.contains('实测值偏离')),
      isFalse,
      reason: '没有实时数据流时，不应产生实测异常候选原因',
    );
  });

  test('连接虚拟设备：模拟读数可显示但不会写成实测异常', () async {
    await createController();

    controller.selectCase('case_a');
    await _settle();
    await controller.connect(_virtualDevice);
    final state = container.read(diagnosticControllerProvider);
    expect(state.status, ObdConnectionStatus.connected);
    expect(state.connectionMode, ConnectionMode.virtual);
    expect(state.isMeasuring, isFalse);
    expect(virtualSource.connectedDevice, _virtualDevice);

    virtualSource.controller.add({
      'stft': PidReading(
        pid: 'stft',
        value: 18.4,
        timestamp: DateTime.now(),
        source: ConnectionMode.virtual,
      ),
    });
    await _settle();
    await _settle();
    expect(
      container
          .read(diagnosticControllerProvider)
          .liveReadings
          .values
          .single
          .source,
      ConnectionMode.virtual,
    );

    await controller.generateReport();
    final report = container.read(diagnosticControllerProvider).report!;
    expect(
      report.candidateCauses.any((cause) => cause.contains('实测值偏离')),
      isFalse,
      reason: '虚拟设备的模拟读数绝不能进入实测证据',
    );
  });

  test('连接蓝牙设备：真实实测异常可进入报告，断开后实时读数被清空', () async {
    await createController();

    controller.selectCase('case_a');
    await _settle();
    await controller.connect(_bluetoothDevice);
    final connected = container.read(diagnosticControllerProvider);
    expect(connected.status, ObdConnectionStatus.connected);
    expect(connected.connectionMode, ConnectionMode.bluetooth);
    expect(connected.isMeasuring, isTrue);
    expect(bluetoothSource.connectedDevice, _bluetoothDevice);

    bluetoothSource.controller.add({
      'stft': PidReading(
        pid: 'stft',
        value: 18.4,
        timestamp: DateTime.now(),
        source: ConnectionMode.bluetooth,
      ),
    });
    await _settle();
    await _settle();
    expect(
        container.read(diagnosticControllerProvider).liveReadings, isNotEmpty);

    await controller.generateReport();
    expect(
      container
          .read(diagnosticControllerProvider)
          .report!
          .candidateCauses
          .any((cause) => cause.contains('实测值偏离')),
      isTrue,
    );

    await controller.disconnect();
    final after = container.read(diagnosticControllerProvider);
    expect(after.status, ObdConnectionStatus.disconnected);
    expect(after.connectionMode, isNull);
    expect(after.liveReadings, isEmpty);
    expect(after.history, isEmpty);
  });

  test('连接不可用的占位蓝牙设备：拒绝连接并报错，不进入测量状态', () async {
    await createController();

    controller.selectCase('case_a');
    await _settle();
    await controller.connect(_unavailableBluetoothDevice);
    await _settle();
    final state = container.read(diagnosticControllerProvider);

    expect(state.status, ObdConnectionStatus.disconnected,
        reason: '不可用设备绝不能进入已连接态');
    expect(state.isMeasuring, isFalse);
    expect(state.connectionMode, isNull);
    expect(state.liveReadings, isEmpty);
    expect(state.connectionError,
        contains('尚未接入真实蓝牙 OBD 协议'));
    expect(bluetoothSource.connectedDevice, isNull);

    // 失败后生成报告同样不能出现实测异常。
    await controller.generateReport();
    expect(
      container
          .read(diagnosticControllerProvider)
          .report!
          .candidateCauses
          .any((cause) => cause.contains('实测值偏离')),
      isFalse,
    );
  });

  test('步骤结果、现场备注与报告草稿在应用重启后仍然恢复', () async {
    await createController();
    controller.selectCase('case_a');
    await _settle();

    // 修理工记录一个异常步骤并填写现场备注。
    await controller.updateStep('a_step_1', StepStatus.fail, '烟雾测试发现进气管开裂');
    await controller.generateReport();
    final beforeReport = container.read(diagnosticControllerProvider).report!;
    expect(beforeReport.candidateCauses, contains('进气泄漏'));

    // 模拟关闭应用：丢弃容器与控制器，但保留同一个存储。
    container.dispose();
    await createController();

    final restarted = container.read(diagnosticControllerProvider);
    expect(restarted.selectedCase!.id, 'case_a');
    final restored = restarted.stepResults['a_step_1']!;
    expect(restored.status, StepStatus.fail, reason: '步骤状态重启后不能回到待检测');
    expect(restored.note, '烟雾测试发现进气管开裂', reason: '现场备注必须离线保留');
    expect(restarted.report, isNotNull, reason: '报告草稿重启后不能消失');
    expect(restarted.report!.summary, beforeReport.summary);
    expect(restarted.report!.candidateCauses, contains('进气泄漏'));
    final restoredInReport = restarted.report!.stepResults
        .singleWhere((r) => r.stepId == 'a_step_1');
    expect(restoredInReport.status, StepStatus.fail);
    expect(restoredInReport.note, '烟雾测试发现进气管开裂');
  });

  test('未填写过记录的案例重启后保持初始状态', () async {
    await createController();
    controller.selectCase('case_b');
    await _settle();
    container.dispose();
    await createController();

    final restarted = container.read(diagnosticControllerProvider);
    expect(restarted.selectedCase!.id, 'case_a', reason: '默认选中第一个案例');
    expect(restarted.report, isNull);
    expect(
      restarted.stepResults.values
          .every((r) => r.status == StepStatus.pending),
      isTrue,
    );
  });

  test('从有草稿的案例切到无草稿案例：不串显他案例报告，也不错误归属落盘', () async {
    await createController();

    // 案例 A：记录步骤并生成报告。
    controller.selectCase('case_a');
    await _settle();
    await controller.updateStep('a_step_1', StepStatus.fail, 'A 的现场备注');
    await controller.generateReport();
    expect(container.read(diagnosticControllerProvider).report, isNotNull);

    // 切到尚无草稿的案例 B：报告必须被清空，而不是残留 A 的内容。
    controller.selectCase('case_b');
    await _settle();
    final stateB = container.read(diagnosticControllerProvider);
    expect(stateB.selectedCase!.id, 'case_b');
    expect(stateB.report, isNull,
        reason: '案例 B 没有草稿，不能显示案例 A 的报告');
    expect(
      stateB.stepResults.keys,
      ['b_step_1'],
      reason: '步骤结果也必须是 B 自己的，不能残留 A 的 a_step_1',
    );

    // 在 B 上继续编辑（触发持久化）：错误的 A 报告不能写进 B 的本地记录。
    await controller.updateStep('b_step_1', StepStatus.pass, 'B 的现场备注');

    final stored = await store.loadRecords();
    final cases = stored['cases'] as Map;
    final storedB = cases['case_b'] as Map<String, dynamic>;
    expect(storedB.containsKey('report'), isFalse,
        reason: '案例 A 的报告绝不能归属到案例 B');
    final storedBSteps = storedB['steps'] as List;
    expect(storedBSteps.map((s) => (s as Map)['stepId']), ['b_step_1']);

    // A 的草稿仍然完整保留，且切回 A 时恢复的是 A 自己的报告。
    final storedA = cases['case_a'] as Map<String, dynamic>;
    expect((storedA['report'] as Map)['caseId'], 'case_a');
    controller.selectCase('case_a');
    await _settle();
    final stateA = container.read(diagnosticControllerProvider);
    expect(stateA.report, isNotNull);
    expect(stateA.report!.caseId, 'case_a');
    expect(stateA.stepResults['a_step_1']!.note, 'A 的现场备注');
  });

  test('PidReading 默认按虚拟来源处理（fail-safe）', () {
    final reading = PidReading(pid: 'stft', value: 18.4, timestamp: DateTime(2026));
    expect(reading.isMeasured, isFalse,
        reason: '忘记标记来源的读数不能被当作实测值');
  });
}
