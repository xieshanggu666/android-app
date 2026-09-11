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
      ObdDevice(
        id: 'shop-obd-02',
        name: '车间 OBD-II 蓝牙适配器',
        signalStrength: 82,
        mode: ConnectionMode.bluetooth,
      ),
    ];
  }

  @override
  Future<void> connect(ObdDevice device) async {
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
            PidReading(pid: pid, value: value + trend + noise, timestamp: now),
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

class BluetoothObdSource implements ObdSource {
  const BluetoothObdSource();

  @override
  Stream<List<ObdDevice>> scan() async* {
    // The real adapter is intentionally isolated behind this source so field
    // builds can replace the virtual mode without changing the diagnostic UI.
    yield const [
      ObdDevice(
        id: 'bt-placeholder',
        name: '真实蓝牙扫描入口',
        signalStrength: 0,
        mode: ConnectionMode.bluetooth,
      ),
    ];
  }

  @override
  Future<void> connect(ObdDevice device) async {}

  @override
  Stream<Map<String, PidReading>> watchPids(DiagnosticCase diagnosticCase) {
    return const Stream.empty();
  }

  @override
  Future<void> disconnect() async {}
}
