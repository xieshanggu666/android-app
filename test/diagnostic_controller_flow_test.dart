import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_obd_assistant/data/offline_repository.dart';
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
  final StreamController<Map<String, PidReading>> controller =
      StreamController<Map<String, PidReading>>.broadcast();
  bool connected = false;

  @override
  Stream<List<ObdDevice>> scan() => Stream.value(const []);

  @override
  Future<void> connect(ObdDevice device) async {
    connected = true;
  }

  @override
  Stream<Map<String, PidReading>> watchPids(DiagnosticCase diagnosticCase) {
    return controller.stream;
  }

  @override
  Future<void> disconnect() async {
    connected = false;
  }
}

const _device = ObdDevice(
  id: 'virtual',
  name: '虚拟 OBD',
  signalStrength: 100,
  mode: ConnectionMode.virtual,
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late ProviderContainer container;
  late DiagnosticController controller;
  late _FakeObdSource obdSource;

  Future<void> createController() async {
    container = ProviderContainer(overrides: [
      offlineRepositoryProvider.overrideWithValue(_FakeRepository()),
      obdSourceProvider.overrideWithValue(
        obdSource = _FakeObdSource(),
      ),
    ]);
    addTearDown(container.dispose);
    controller = container.read(diagnosticControllerProvider.notifier);
    for (var i = 0; i < 5 && container.read(diagnosticControllerProvider).loading; i++) {
      await _settle();
    }
  }

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
    controller.generateReport();
    final report = container.read(diagnosticControllerProvider).report!;

    expect(report.candidateCauses, equals(['进气泄漏']));
    expect(
      report.candidateCauses.any((cause) => cause.contains('实测值偏离')),
      isFalse,
      reason: '没有实时数据流时，不应产生实测异常候选原因',
    );
  });

  test('连接后的实时异常可进入报告，断开后实时读数被清空', () async {
    await createController();

    controller.selectCase('case_a');
    await _settle();
    await controller.connect(_device);
    expect(container.read(diagnosticControllerProvider).status,
        ObdConnectionStatus.connected);

    obdSource.controller.add({
      'stft': PidReading(pid: 'stft', value: 18.4, timestamp: DateTime.now()),
    });
    await _settle();
    await _settle();
    expect(container.read(diagnosticControllerProvider).liveReadings, isNotEmpty);

    controller.generateReport();
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
    expect(after.liveReadings, isEmpty);
    expect(after.history, isEmpty);
  });
}
