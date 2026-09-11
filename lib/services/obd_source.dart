import 'dart:async';
import 'dart:math';

// ignore: unused_import
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as flutter_blue_plus;

import '../models/diagnostics.dart';

abstract class ObdSource {
  Stream<List<ObdDevice>> scan();
  Future<void> connect(ObdDevice device);
  Stream<Map<String, PidReading>> watchPids(DiagnosticCase diagnosticCase);
  Future<void> disconnect();
}

/// 演示用模拟数据源。只允许连接 [ConnectionMode.virtual] 的设备，
/// 产出的读数一律标记为虚拟来源，绝不允许进入维修报告的实测证据。
class VirtualObdSource implements ObdSource {
  final _random = Random(7);
  ObdDevice? _connected;

  @override
  Stream<List<ObdDevice>> scan() async* {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    yield const [
      ObdDevice(
        id: 'virtual-elm327',
        name: '虚拟 ELM327 / 离线演示',
        signalStrength: 100,
        mode: ConnectionMode.virtual,
      ),
    ];
  }

  @override
  Future<void> connect(ObdDevice device) async {
    if (device.mode != ConnectionMode.virtual) {
      throw ArgumentError(
        'VirtualObdSource 只能连接虚拟演示设备，'
        '${device.name}(${device.mode.name}) 必须走真实蓝牙数据源。',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _connected = device;
  }

  @override
  Stream<Map<String, PidReading>> watchPids(DiagnosticCase diagnosticCase) {
    return Stream<Map<String, PidReading>>.periodic(
      const Duration(milliseconds: 900),
      (tick) {
        final now = DateTime.now();
        return diagnosticCase.beforeReadings.map((pid, value) {
          final wave = sin((tick + pid.hashCode % 9) / 2.5);
          final noise = (_random.nextDouble() - 0.5) * 2.0;
          final trend = diagnosticCase.id == 'case_misfire_p0302' && pid == 'misfire_cyl2'
              ? 8 + wave * 4
              : wave * 1.8;
          return MapEntry(
            pid,
            PidReading(
              pid: pid,
              value: value + trend + noise,
              timestamp: now,
              source: ConnectionMode.virtual,
            ),
          );
        });
      },
    ).takeWhile((_) => _connected != null);
  }

  @override
  Future<void> disconnect() async {
    _connected = null;
  }
}

/// 真实蓝牙适配器数据源。现场版本在此接入 flutter_blue_plus；
/// 当前原型未实现真实协议，扫描只提供入口、连接后不产出任何读数。
/// 未来接入真实流时，读数必须带 source: ConnectionMode.bluetooth。
class BluetoothObdSource implements ObdSource {
  const BluetoothObdSource();

  @override
  Stream<List<ObdDevice>> scan() async* {
    // The real adapter is intentionally isolated behind this source so field
    // builds can replace the virtual mode without changing the diagnostic UI.
    yield const [
      ObdDevice(
        id: 'bt-placeholder',
        name: '车间 OBD-II 蓝牙适配器（真实蓝牙入口）',
        signalStrength: 0,
        mode: ConnectionMode.bluetooth,
      ),
    ];
  }

  @override
  Future<void> connect(ObdDevice device) {
    if (device.mode != ConnectionMode.bluetooth) {
      throw ArgumentError(
        'BluetoothObdSource 只能连接真实蓝牙设备，不能连接 ${device.mode.name} 设备。',
      );
    }
    // TODO(field-build): 使用 flutter_blue_plus 建立连接并读取真实 PID。
    return Future.value();
  }

  @override
  Stream<Map<String, PidReading>> watchPids(DiagnosticCase diagnosticCase) {
    // 真实协议未接入前返回空流：宁可没有读数，也不能用模拟值冒充实测值。
    return const Stream.empty();
  }

  @override
  Future<void> disconnect() async {}
}
