enum ConnectionMode { virtual, bluetooth }

enum ObdConnectionStatus { disconnected, scanning, connecting, connected }

enum StepStatus { pending, pass, fail, skipped }

class ObdDevice {
  const ObdDevice({
    required this.id,
    required this.name,
    required this.signalStrength,
    required this.mode,
    // 扫描结果中存在但当前构建不支持实际连接的设备（如尚未接入协议的
    // 真实蓝牙入口）必须显式标记为不可用，避免被当成可连接硬件。
    this.available = true,
    this.unavailableReason,
  });

  final String id;
  final String name;
  final int signalStrength;
  final ConnectionMode mode;
  final bool available;
  final String? unavailableReason;
}

/// 数据源声明当前构建无法连接真实硬件时抛出，由 controller 转成用户可见错误。
class ObdHardwareUnavailable implements Exception {
  const ObdHardwareUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

class PidDefinition {
  const PidDefinition({
    required this.id,
    required this.name,
    required this.unit,
    required this.min,
    required this.max,
    required this.normalLow,
    required this.normalHigh,
  });

  final String id;
  final String name;
  final String unit;
  final double min;
  final double max;
  final double normalLow;
  final double normalHigh;

  factory PidDefinition.fromJson(Map<String, dynamic> json) {
    return PidDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      unit: json['unit'] as String,
      min: (json['min'] as num).toDouble(),
      max: (json['max'] as num).toDouble(),
      normalLow: (json['normalLow'] as num).toDouble(),
      normalHigh: (json['normalHigh'] as num).toDouble(),
    );
  }
}

class PidReading {
  const PidReading({
    required this.pid,
    required this.value,
    required this.timestamp,
    // 默认按虚拟来源处理（fail-safe）：未显式声明为真实蓝牙的读数，
    // 永远不能被当作实测证据写进维修报告。
    this.source = ConnectionMode.virtual,
  });

  final String pid;
  final double value;
  final DateTime timestamp;
  final ConnectionMode source;

  bool get isMeasured => source == ConnectionMode.bluetooth;

  bool isOutOfRange(PidDefinition definition) {
    return value < definition.normalLow || value > definition.normalHigh;
  }
}

class TroubleCode {
  const TroubleCode({
    required this.code,
    required this.title,
    required this.ecu,
    required this.severity,
    required this.description,
    required this.relatedPids,
    required this.candidateCauses,
  });

  final String code;
  final String title;
  final String ecu;
  final String severity;
  final String description;
  final List<String> relatedPids;
  final List<String> candidateCauses;

  factory TroubleCode.fromJson(Map<String, dynamic> json) {
    return TroubleCode(
      code: json['code'] as String,
      title: json['title'] as String,
      ecu: json['ecu'] as String,
      severity: json['severity'] as String,
      description: json['description'] as String,
      relatedPids: List<String>.from(json['relatedPids'] as List),
      candidateCauses: List<String>.from(json['candidateCauses'] as List),
    );
  }
}

class FreezeFrame {
  const FreezeFrame({
    required this.engineRpm,
    required this.vehicleSpeed,
    required this.coolantTemp,
    required this.fuelTrimShort,
    required this.fuelTrimLong,
    required this.load,
  });

  final int engineRpm;
  final int vehicleSpeed;
  final int coolantTemp;
  final double fuelTrimShort;
  final double fuelTrimLong;
  final double load;

  factory FreezeFrame.fromJson(Map<String, dynamic> json) {
    return FreezeFrame(
      engineRpm: json['engineRpm'] as int,
      vehicleSpeed: json['vehicleSpeed'] as int,
      coolantTemp: json['coolantTemp'] as int,
      fuelTrimShort: (json['fuelTrimShort'] as num).toDouble(),
      fuelTrimLong: (json['fuelTrimLong'] as num).toDouble(),
      load: (json['load'] as num).toDouble(),
    );
  }
}

class GuidedStep {
  const GuidedStep({
    required this.id,
    required this.title,
    required this.method,
    required this.expected,
    required this.relatedPids,
  });

  final String id;
  final String title;
  final String method;
  final String expected;
  final List<String> relatedPids;

  factory GuidedStep.fromJson(Map<String, dynamic> json) {
    return GuidedStep(
      id: json['id'] as String,
      title: json['title'] as String,
      method: json['method'] as String,
      expected: json['expected'] as String,
      relatedPids: List<String>.from(json['relatedPids'] as List),
    );
  }
}

class StepResult {
  const StepResult({
    required this.stepId,
    required this.status,
    required this.note,
    required this.updatedAt,
  });

  final String stepId;
  final StepStatus status;
  final String note;
  final DateTime updatedAt;

  StepResult copyWith({
    StepStatus? status,
    String? note,
    DateTime? updatedAt,
  }) {
    return StepResult(
      stepId: stepId,
      status: status ?? this.status,
      note: note ?? this.note,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class DiagnosticCase {
  const DiagnosticCase({
    required this.id,
    required this.name,
    required this.vehicle,
    required this.ecus,
    required this.codes,
    required this.freezeFrame,
    required this.steps,
    required this.beforeReadings,
    required this.afterReadings,
  });

  final String id;
  final String name;
  final String vehicle;
  final List<String> ecus;
  final List<TroubleCode> codes;
  final FreezeFrame freezeFrame;
  final List<GuidedStep> steps;
  final Map<String, double> beforeReadings;
  final Map<String, double> afterReadings;

  factory DiagnosticCase.fromJson(Map<String, dynamic> json) {
    return DiagnosticCase(
      id: json['id'] as String,
      name: json['name'] as String,
      vehicle: json['vehicle'] as String,
      ecus: List<String>.from(json['ecus'] as List),
      codes: (json['codes'] as List)
          .map((item) => TroubleCode.fromJson(item as Map<String, dynamic>))
          .toList(),
      freezeFrame:
          FreezeFrame.fromJson(json['freezeFrame'] as Map<String, dynamic>),
      steps: (json['steps'] as List)
          .map((item) => GuidedStep.fromJson(item as Map<String, dynamic>))
          .toList(),
      beforeReadings: (json['beforeReadings'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      ),
      afterReadings: (json['afterReadings'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      ),
    );
  }
}

class VehicleProfile {
  const VehicleProfile({
    required this.id,
    required this.name,
    required this.engine,
    required this.notes,
  });

  final String id;
  final String name;
  final String engine;
  final List<String> notes;

  factory VehicleProfile.fromJson(Map<String, dynamic> json) {
    return VehicleProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      engine: json['engine'] as String,
      notes: List<String>.from(json['notes'] as List),
    );
  }
}

class RepairReport {
  const RepairReport({
    required this.caseId,
    required this.createdAt,
    required this.summary,
    required this.candidateCauses,
    required this.stepResults,
  });

  final String caseId;
  final DateTime createdAt;
  final String summary;
  final List<String> candidateCauses;
  final List<StepResult> stepResults;
}
