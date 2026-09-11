import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/offline_repository.dart';
import '../data/record_store.dart';
import '../models/diagnostics.dart';
import '../services/obd_source.dart';

final offlineRepositoryProvider = Provider<OfflineRepository>((ref) {
  return OfflineRepository();
});

final recordStoreProvider = Provider<RecordStore>((ref) {
  return FileRecordStore();
});

final virtualObdSourceProvider = Provider<ObdSource>((ref) {
  return VirtualObdSource();
});

final bluetoothObdSourceProvider = Provider<ObdSource>((ref) {
  return const BluetoothObdSource();
});

final diagnosticControllerProvider =
    NotifierProvider<DiagnosticController, DiagnosticState>(
  DiagnosticController.new,
);

/// 用于把可空字段（如 connectionMode）显式重置回 null。
const Object _unset = Object();

class DiagnosticState {
  const DiagnosticState({
    this.loading = true,
    this.status = ObdConnectionStatus.disconnected,
    this.connectionMode,
    this.connectionError,
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
  final ConnectionMode? connectionMode;
  final String? connectionError;
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

  bool get isMeasuring =>
      status == ObdConnectionStatus.connected &&
      connectionMode == ConnectionMode.bluetooth;

  DiagnosticState copyWith({
    bool? loading,
    ObdConnectionStatus? status,
    Object? connectionMode = _unset,
    Object? connectionError = _unset,
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
      connectionMode: connectionMode == _unset
          ? this.connectionMode
          : connectionMode as ConnectionMode?,
      connectionError: connectionError == _unset
          ? this.connectionError
          : connectionError as String?,
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
  ObdSource? _activeSource;

  /// 按案例缓存已持久化的步骤结果与报告草稿，与离线存储内容保持一致。
  final Map<String, _CaseRecord> _caseRecords = {};

  ObdSource _sourceFor(ObdDevice device) {
    // 按设备模式路由数据源：蓝牙模式设备绝不能走虚拟演示源。
    return switch (device.mode) {
      ConnectionMode.virtual => ref.read(virtualObdSourceProvider),
      ConnectionMode.bluetooth => ref.read(bluetoothObdSourceProvider),
    };
  }

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
    await _hydrateRecords(cases);
    final selectedCase = cases.isEmpty ? null : cases.first;
    final record = selectedCase == null ? null : _caseRecords[selectedCase.id];
    state = state.copyWith(
      loading: false,
      vehicles: vehicles,
      cases: cases,
      pidCatalog: pidCatalog,
      selectedCase: selectedCase,
      stepResults:
          record?.results ?? _initialResults(selectedCase),
      report: record?.report,
      warning: '当前为离线优先模式：所有候选原因均来自故障码、冻结帧和实测 PID 关联，不标记为确定结论。检测步骤与报告草稿保存在本机，重启后仍可查看。',
    );
  }

  Future<void> _hydrateRecords(List<DiagnosticCase> cases) async {
    final byCaseId = {for (final c in cases) c.id: c};
    final loaded = await ref.read(recordStoreProvider).loadRecords();
    final casesNode = (loaded['cases'] as Map?) ?? const {};
    casesNode.forEach((rawId, rawNode) {
      final caseId = rawId as String;
      final diagnosticCase = byCaseId[caseId];
      if (diagnosticCase == null || rawNode is! Map) {
        return;
      }
      final record = _CaseRecord();
      for (final rawStep in (rawNode['steps'] as List?) ?? const []) {
        if (rawStep is Map) {
          final result = _decodeResult(rawStep.cast<String, dynamic>());
          record.results[result.stepId] = result;
        }
      }
      final rawReport = rawNode['report'];
      if (rawReport is Map) {
        record.report = _decodeReport(
          rawReport.cast<String, dynamic>(),
        );
      }
      _caseRecords[caseId] = record;
    });
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
    state = state.copyWith(
      status: ObdConnectionStatus.scanning,
      connectionError: null,
    );
    // 同时扫描虚拟演示设备和真实蓝牙设备，两类入口分别标注来源。
    final results = await Future.wait([
      ref.read(virtualObdSourceProvider).scan().first,
      ref.read(bluetoothObdSourceProvider).scan().first,
    ]);
    final devices = [for (final list in results) ...list];
    state = state.copyWith(
      status: ObdConnectionStatus.disconnected,
      devices: devices,
    );
  }

  Future<void> connect(ObdDevice device) async {
    // 不可用设备（如尚未接入协议的真实蓝牙入口）直接拒绝，
    // 绝不能进入 connected/isMeasuring 状态。
    if (!device.available) {
      state = state.copyWith(
        status: ObdConnectionStatus.disconnected,
        connectionMode: null,
        connectionError:
            device.unavailableReason ?? '该设备当前无法连接，请选择其他设备。',
        liveReadings: const {},
        history: const {},
      );
      return;
    }
    await _pidSubscription?.cancel();
    _pidSubscription = null;
    state = state.copyWith(
      status: ObdConnectionStatus.connecting,
      connectionError: null,
    );
    final source = _sourceFor(device);
    try {
      await source.connect(device);
    } on Object catch (error) {
      // 连接失败（硬件未接入/未发现设备/超时）：回到未连接并给出明确原因，
      // 不允许保留“已连接、正在接收实测 PID”的假象。
      _activeSource = null;
      state = state.copyWith(
        status: ObdConnectionStatus.disconnected,
        connectionMode: null,
        connectionError: error is ObdHardwareUnavailable
            ? error.message
            : '连接 ${device.name} 失败：$error',
        liveReadings: const {},
        history: const {},
      );
      return;
    }
    _activeSource = source;
    // 新连接建立前清空上一轮读数，防止把旧会话的数据归因到新设备。
    state = state.copyWith(
      status: ObdConnectionStatus.connected,
      connectionMode: device.mode,
      connectionError: null,
      liveReadings: const {},
      history: const {},
    );
    _startPidStream();
  }

  void selectCase(String id) {
    final diagnosticCase = state.cases.firstWhere((item) => item.id == id);
    // 切换案例时清空实时数据：离线案例的 beforeReadings 只是参考资料，
    // 绝不能伪装成带当前时间戳的实测读数（否则会被报告当作实测异常采信）。
    // 步骤结果与报告草稿从本机存储恢复，而不是重置。
    final record = _caseRecords[id];
    state = state.copyWith(
      selectedCase: diagnosticCase,
      liveReadings: const {},
      history: const {},
      stepResults: record?.results ?? _initialResults(diagnosticCase),
      report: record?.report,
    );
    if (state.status == ObdConnectionStatus.connected) {
      _startPidStream();
    }
  }

  Future<void> disconnect() async {
    await _pidSubscription?.cancel();
    _pidSubscription = null;
    await _activeSource?.disconnect();
    _activeSource = null;
    // 断开后丢弃本次会话的实时读数，避免旧值继续显示或被写入报告。
    state = state.copyWith(
      status: ObdConnectionStatus.disconnected,
      connectionMode: null,
      connectionError: null,
      liveReadings: const {},
      history: const {},
    );
  }

  void _startPidStream() {
    final diagnosticCase = state.selectedCase;
    final source = _activeSource;
    if (diagnosticCase == null || source == null) {
      return;
    }
    _pidSubscription?.cancel();
    _pidSubscription = source.watchPids(diagnosticCase).listen(
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

  Future<void> updateStep(String stepId, StepStatus status, String note) async {
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
    await _persistCurrentCase();
  }

  Future<void> generateReport() async {
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
    await _persistCurrentCase();
  }

  Future<void> _persistCurrentCase() async {
    final diagnosticCase = state.selectedCase;
    if (diagnosticCase == null) {
      return;
    }
    _caseRecords[diagnosticCase.id] = _CaseRecord(
      results: Map<String, StepResult>.from(state.stepResults),
      report: state.report,
    );
    final store = ref.read(recordStoreProvider);
    final payload = <String, dynamic>{
      'version': 1,
      'cases': {
        for (final entry in _caseRecords.entries)
          entry.key: _encodeCaseRecord(entry.value),
      },
    };
    // 持久化失败不能中断现场操作或清空内存状态；下次操作会重试写入。
    try {
      await store.saveRecords(payload);
    } on Object {
      // 保留内存中的记录，本次会话可继续使用，下一次写入会重试。
    }
  }

  Map<String, dynamic> _encodeCaseRecord(_CaseRecord record) {
    return {
      'steps': [
        for (final result in record.results.values)
          {
            'stepId': result.stepId,
            'status': result.status.name,
            'note': result.note,
            'updatedAt': result.updatedAt.toIso8601String(),
          },
      ],
      if (record.report != null)
        'report': {
          'caseId': record.report!.caseId,
          'createdAt': record.report!.createdAt.toIso8601String(),
          'summary': record.report!.summary,
          'candidateCauses': record.report!.candidateCauses,
          'stepResults': [
            for (final result in record.report!.stepResults)
              {
                'stepId': result.stepId,
                'status': result.status.name,
                'note': result.note,
                'updatedAt': result.updatedAt.toIso8601String(),
              },
          ],
        },
    };
  }

  StepResult _decodeResult(Map<String, dynamic> json) {
    return StepResult(
      stepId: json['stepId'] as String,
      status: StepStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => StepStatus.pending,
      ),
      note: (json['note'] as String?) ?? '',
      updatedAt: DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  RepairReport _decodeReport(Map<String, dynamic> json) {
    return RepairReport(
      caseId: json['caseId'] as String,
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
              DateTime.now(),
      summary: (json['summary'] as String?) ?? '',
      candidateCauses:
          ((json['candidateCauses'] as List?) ?? const [])
              .map((item) => item as String)
              .toList(),
      stepResults: ((json['stepResults'] as List?) ?? const [])
          .map((item) => _decodeResult((item as Map).cast<String, dynamic>()))
          .toList(),
    );
  }

  List<String> _measuredCandidates(DiagnosticCase diagnosticCase) {
    // 只有连接真实蓝牙设备且确实收到标记为实测来源的读数时，才允许判为“实测异常”。
    // 虚拟演示源的模拟波形、离线案例参考值、已连接但尚未收到数据的会话，
    // 都不能作为实测证据进入报告。
    if (!state.isMeasuring || state.liveReadings.isEmpty) {
      return const [];
    }
    final definitions = {for (final pid in state.pidCatalog) pid.id: pid};
    final candidates = <String>[];
    for (final reading in state.liveReadings.values) {
      if (!reading.isMeasured) {
        continue;
      }
      final definition = definitions[reading.pid];
      if (definition != null && reading.isOutOfRange(definition)) {
        candidates.add('${definition.name}实测值偏离正常范围，建议优先复核其传感器、线路和相关执行器。');
      }
    }
    return candidates;
  }
}

/// 单个案例在本机保存的检测记录：步骤结果与报告草稿。
class _CaseRecord {
  _CaseRecord({Map<String, StepResult>? results, this.report})
      : results = results ?? {};

  final Map<String, StepResult> results;
  RepairReport? report;
}
