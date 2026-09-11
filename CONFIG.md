# 配置说明

## 数据源

默认 Provider 位于 `lib/state/diagnostic_controller.dart`：

```dart
final obdSourceProvider = Provider<ObdSource>((ref) {
  return VirtualObdSource();
});
```

交付版默认使用 `VirtualObdSource`，可在完全断网、无 OBD 设备时演示完整流程。

接入真实 ELM327 / BLE OBD 时，将该 Provider 替换为 `BluetoothObdSource`，并在 `lib/services/obd_source.dart` 中完成：

- 蓝牙扫描
- GATT 连接
- ELM327 初始化命令
- PID 请求/响应解析
- 断线重连和超时处理

## Android 权限

`android/app/src/main/AndroidManifest.xml` 已声明：

- `BLUETOOTH`
- `BLUETOOTH_ADMIN`
- `BLUETOOTH_SCAN`
- `BLUETOOTH_CONNECT`
- `ACCESS_FINE_LOCATION`，仅 Android 11 及以下蓝牙扫描兼容

## 离线持久化

`lib/data/local_database.dart` 已提供 Drift 表结构：

- `DiagnosticDrafts`：报告草稿
- `TestRecords`：检测步骤记录

当前原型把运行态保存在 Riverpod 状态中。生产落地时用 `build_runner` 生成 Drift 数据库，并把步骤记录、报告草稿和试车前后数据写入 SQLite。
