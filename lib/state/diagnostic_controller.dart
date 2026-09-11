import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/offline_repository.dart';
import '../models/diagnostics.dart';
import '../services/obd_source.dart';

final offlineRepositoryProvider = Provider<OfflineRepository>((ref) {
  return OfflineRepository();
});

final obdSourceProvider = Provider<ObdSource>((ref) {
  return VirtualObdSource();
});

final diagnosticControllerProvider =
    NotifierProvider<DiagnosticController, DiagnosticState>(
  DiagnosticController.new,
);

class DiagnosticState {
  const DiagnosticState({
    this.loading = true,
    this.status = ObdConnectionStatus.disconnected,
    this.devices = const [],
    this.vehicles = const [],
    this.cases = const [],
    this.pidCatalog = const [],
    this.selectedCase,
    this.liveReadings = const {},
    this.history = const {},
    this.stepResults = const {},
    this.report,
    this.offlineMode = true,
    this.warning,
  });

  final bool loading;
  final ObdConnectionStatus status;
  final List<ObdDevice> devices;
  final List<VehicleProfile> vehicles;
  final List<DiagnosticCase> cases;
  final List<PidDefinition> pidCatalog;
  final DiagnosticCase? selectedCase;
  final Map<String, PidReading> liveReadings;
  final Map<String, List<PidReading>> history;
  final Map<String, StepResult> stepResults;
  final RepairReport? report;
  final bool offlineMode;
  final String? warning;

  DiagnosticState copyWith({
    bool? loading,
    ObdConnectionStatus? status,
    List<ObdDevice>? devices,
    List<VehicleProfile>? vehicles,
    List<DiagnosticCase>? cases,
    List<PidDefinition>? pidCatalog,
    DiagnosticCase? selectedCase,
    Map<String, PidReading>? liveReadings,
    Map<String, List<PidReading>>? history,
    Map<String, StepResult>? stepResults,
    RepairReport? report,
    bool? offlineMode,
    String? warning,
  }) {
    return DiagnosticState(
      loading: loading ?? this.loading,
      status: status ?? this.status,
      devices: devices ?? this.devices,
      vehicles: vehicles ?? this.vehicles,
      cases: cases ?? this.cases,
      pidCatalog: pidCatalog ?? this.pidCatalog,
      selectedCase: selectedCase ?? this.selectedCase,
      liveReadings: liveReadings ?? this.liveReadings,
      history: history ?? this.history,
      stepResults: stepResults ?? this.stepResults,
      report: report ?? this.report,
      offlineMode: offlineMode ?? this.offlineMode,
      warning: warning ?? this.warning,
    );
  }
}

class DiagnosticController extends Notifier<DiagnosticState> {
  StreamSubscription<Map<String, PidReading>>? _pidSubscription;

  @override
  DiagnosticState build() {
    ref.onDispose(() {
      _pidSubscription?.cancel();
    });
    Future<void>.microtask(_loadOfflineData);
    return const DiagnosticState();
  }

  Future<void> _loadOfflineData() async {
    final repository = ref.read(offlineRepositoryProvider);
    final vehicles = await repository.loadVehicles();
    final cases = await repository.loadCases();
    final pidCatalog = await repository.loadPidCatalog();
    final selectedCase = cases.isEmpty ? null : cases.first;
    state = state.copyWith(
      loading: false,
      vehicles: vehicles,
      cases: cases,
      pidCatalog: pidCatalog,
      selectedCase: selectedCase,
      stepResults: _initialResults(selectedCase),
      warning: '当前为离线优先模式：所有候选原因均来自故障码、冻结帧和实测 PID 关联，不标记为确定结论。',
    );
  }

  Map<String, StepResult> _initialResults(DiagnosticCase? diagnosticCase) {
    if (diagnosticCase == null) {
      return const {};
    }
    return {
      for (final step in diagnosticCase.steps)
        step.id: StepResult(
          stepId: step.id,
          status: StepStatus.pending,
          note: '',
          updatedAt: DateTime.now(),
        ),
    };
  }

  Future<void> scanDevices() async {
    state = state.copyWith(status: ObdConnectionStatus.scanning);
    final devices = await ref.read(obdSourceProvider).scan().first;
    state = state.copyWith(
      status: ObdConnectionStatus.disconnected,
      devices: devices,
    );
  }

  Future<void> connect(ObdDevice device) async {
    await ref.read(obdSourceProvider).connect(device);
    state = state.copyWith(status: ObdConnectionStatus.connected);
    _startPidStream();
  }

  void selectCase(String id) {
    final diagnosticCase = state.cases.firstWhere((item) => item.id == id);
    // 切换案例时清空实时数据：离线案例的 beforeReadings 只是参考资料，
    // 绝不能伪装成带当前时间戳的实测读数（否则会被报告当作实测异常采信）。
    state = state.copyWith(
      selectedCase: diagnosticCase,
      liveReadings: const {},
      history: const {},
      stepResults: _initialResults(diagnosticCase),
      report: RepairReport(
        caseId: diagnosticCase.id,
        createdAt: DateTime.now(),
        summary: '已切换案例，报告草稿待重新生成。',
        candidateCauses: const [],
        stepResults: _initialResults(diagnosticCase).values.toList(),
      ),
    );
    if (state.status == ObdConnectionStatus.connected) {
      _startPidStream();
    }
  }

  Future<void> disconnect() async {
    await _pidSubscription?.cancel();
    _pidSubscription = null;
    await ref.read(obdSourceProvider).disconnect();
    // 断开后丢弃本次会话的实时读数，避免旧值继续显示或被写入报告。
    state = state.copyWith(
      status: ObdConnectionStatus.disconnected,
      liveReadings: const {},
      history: const {},
    );
  }

  void _startPidStream() {
    final diagnosticCase = state.selectedCase;
    if (diagnosticCase == null) {
      return;
    }
    _pidSubscription?.cancel();
    _pidSubscription = ref.read(obdSourceProvider).watchPids(diagnosticCase).listen(
      (readings) {
        final nextHistory = {
          for (final entry in state.history.entries)
            entry.key: List<PidReading>.from(entry.value),
        };
        for (final reading in readings.values) {
          final series = nextHistory.putIfAbsent(reading.pid, () => []);
          series.add(reading);
          if (series.length > 28) {
            series.removeAt(0);
          }
        }
        state = state.copyWith(liveReadings: readings, history: nextHistory);
      },
    );
  }

  void updateStep(String stepId, StepStatus status, String note) {
    final result = state.stepResults[stepId];
    if (result == null) {
      return;
    }
    final nextResults = Map<String, StepResult>.from(state.stepResults);
    nextResults[stepId] = result.copyWith(
      status: status,
      note: note,
      updatedAt: DateTime.now(),
    );
    state = state.copyWith(stepResults: nextResults);
  }

  void generateReport() {
    final diagnosticCase = state.selectedCase;
    if (diagnosticCase == null) {
      return;
    }
    final candidates = <String>{
      for (final code in diagnosticCase.codes) ...code.candidateCauses,
      ..._measuredCandidates(diagnosticCase),
    }.toList();
    final done = state.stepResults.values
        .where((result) => result.status != StepStatus.pending)
        .length;
    state = state.copyWith(
      report: RepairReport(
        caseId: diagnosticCase.id,
        createdAt: DateTime.now(),
        summary: '已记录 $done/${diagnosticCase.steps.length} 个检测步骤。报告仅列出候选原因，需要维修人员结合实测结果确认。',
        candidateCauses: candidates,
        stepResults: state.stepResults.values.toList(),
      ),
    );
  }

  List<String> _measuredCandidates(DiagnosticCase diagnosticCase) {
    // 只有已连接 OBD 且确实收到实时数据流时，才允许把数值判为“实测异常”；
    // 离线案例的维修前参考值不能作为实测证据进入报告。
    if (state.status != ObdConnectionStatus.connected ||
        state.liveReadings.isEmpty) {
      return const [];
    }
    final definitions = {for (final pid in state.pidCatalog) pid.id: pid};
    final candidates = <String>[];
    for (final reading in state.liveReadings.values) {
      final definition = definitions[reading.pid];
      if (definition != null && reading.isOutOfRange(definition)) {
        candidates.add('${definition.name}实测值偏离正常范围，建议优先复核其传感器、线路和相关执行器。');
      }
    }
    return candidates;
  }
}
