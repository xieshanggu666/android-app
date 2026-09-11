import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_obd_assistant/models/diagnostics.dart';
import 'package:mobile_obd_assistant/services/obd_source.dart';

void main() {
  const source = BluetoothObdSource();

  const placeholder = ObdDevice(
    id: 'bt-placeholder',
    name: '车间 OBD-II 蓝牙适配器（真实蓝牙入口）',
    signalStrength: 0,
    mode: ConnectionMode.bluetooth,
    available: false,
    unavailableReason: BluetoothObdSource.unavailableMessage,
  );

  test('真实蓝牙协议未接入：扫描结果不提供可连接设备', () async {
    final devices = await source.scan().first;
    expect(devices.single.available, isFalse,
        reason: '占位入口不能被当作已发现、可连接的硬件');
    expect(devices.single.unavailableReason, isNotNull);
  });

  test('真实蓝牙协议未接入：连接直接失败而不是假装已连接', () async {
    expect(
      () => source.connect(placeholder),
      throwsA(isA<ObdHardwareUnavailable>()),
    );
    expect(
      source.watchPids(
        const DiagnosticCase(
          id: 'c',
          name: 'c',
          vehicle: 'v',
          ecus: [],
          codes: [],
          freezeFrame: FreezeFrame(
            engineRpm: 0,
            vehicleSpeed: 0,
            coolantTemp: 0,
            fuelTrimShort: 0,
            fuelTrimLong: 0,
            load: 0,
          ),
          steps: [],
          beforeReadings: {},
          afterReadings: {},
        ),
      ),
      emitsDone,
    );
  });
}
