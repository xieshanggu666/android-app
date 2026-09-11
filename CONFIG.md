# 配置说明

## 数据源

Provider 位于 `lib/state/diagnostic_controller.dart`，按设备模式分别注入：

```dart
final virtualObdSourceProvider = Provider<ObdSource>((ref) {
  return VirtualObdSource();
});

final bluetoothObdSourceProvider = Provider<ObdSource>((ref) {
  return const BluetoothObdSource();
});
```

扫描会合并两个数据源的设备列表；连接时按 `ObdDevice.mode` 路由：`virtual` 设备只走 `VirtualObdSource`，`bluetooth` 设备只走 `BluetoothObdSource`。虚拟源产出的 `PidReading` 一律带 `source: ConnectionMode.virtual`，仅用于演示界面，不会被维修报告采信为实测数据（见 `DiagnosticState.isMeasuring` 与 `_measuredCandidates`）。

`VirtualObdSource` 可在完全断网、无 OBD 设备时演示完整界面流程，但读数始终标注为“模拟”。

`BluetoothObdSource` 在真实协议接入前不会伪造可连接硬件：扫描只返回一个 `available: false` 的灰色入口，调用 `connect` 会抛出 `ObdHardwareUnavailable`，应用据此停留在未连接态并提示原因，不会显示“已连接/正在接收实测 PID”。

接入真实 ELM327 / BLE OBD 时，在 `lib/services/obd_source.dart` 的 `BluetoothObdSource` 中完成：

- 蓝牙扫描
- GATT 连接
- ELM327 初始化命令
- PID 请求/响应解析（解析出的读数必须带 `source: ConnectionMode.bluetooth`）
- 断线重连和超时处理

## Android 权限

`android/app/src/main/AndroidManifest.xml` 已声明：

- `BLUETOOTH`
- `BLUETOOTH_ADMIN`
- `BLUETOOTH_SCAN`
- `BLUETOOTH_CONNECT`
- `ACCESS_FINE_LOCATION`，仅 Android 11 及以下蓝牙扫描兼容

## 离线持久化

步骤结果、现场备注和报告草稿会在填写/生成时立即离线保存，应用关闭重启后自动恢复（`lib/data/record_store.dart` 的 `FileRecordStore`）：JSON 经临时文件原子写入应用文档目录（使用 `path_provider`），无需代码生成；启动时由 `DiagnosticController._hydrateRecords` 按案例水合。写入失败只保留在内存中且下次操作重试，不阻断现场流程。

`lib/data/local_database.dart` 同时提供后续生产落地用的 Drift 表结构：

- `DiagnosticDrafts`：报告草稿
- `TestRecords`：检测步骤记录

后续用 `build_runner` 生成 Drift `AppDatabase` 时，实现一个新的 `RecordStore`（读写 SQLite）并替换 `recordStoreProvider` 即可，controller 与 UI 无需改动。
