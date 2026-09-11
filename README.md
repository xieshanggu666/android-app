# 手机端故障排查助手

Flutter / Dart 离线优先 OBD 诊断原型，面向修理工连接蓝牙 OBD 后的现场流程：扫描控制单元和故障码、查看冻结帧、选择相关实时数据流、按检测步骤记录结果、试车前后对比并生成维修报告草稿。

## 已包含

- Android Flutter 项目骨架，包名 `com.example.mobile_obd_assistant`
- Riverpod 状态管理
- `flutter_blue_plus` 蓝牙 OBD 接入隔离层
- `fl_chart` PID 曲线
- Drift 离线草稿/检测记录表结构
- 虚拟 OBD 数据源
- 两个离线故障案例：`P0171 系统过稀`、`P0302 二缸失火`
- 离线车型资料、PID 配置和报告草稿边界说明
- `flutter_test` 单元测试和 `integration_test` 冒烟测试

## 配置

1. 安装 Flutter，并确保 Android 工具链可用。
2. 如果 Android 模板文件不完整，例如缺少 `android/gradlew`，先运行：

   ```bash
   flutter create . --platforms=android
   ```

3. 在项目根目录运行：

   ```bash
   flutter pub get
   flutter run -d android
   ```

4. 构建 APK：

   ```bash
   flutter build apk --debug
   ```

5. 测试：

   ```bash
   flutter test
   flutter test integration_test
   ```

## 离线数据

- `assets/offline_vehicle_library.json`：车型资料包
- `assets/fault_cases.json`：两个故障案例、冻结帧、检测步骤、试车前后读数
- `assets/config/pid_catalog.json`：PID 名称、单位和正常范围

应用启动后直接读取本地 assets，不依赖网络。修理工记录的检测步骤、现场备注和报告草稿会立即保存在本机文档目录，关闭重启后自动恢复；Drift 表结构位于 `lib/data/local_database.dart`，后续可替换 `lib/data/record_store.dart` 的 JSON 实现接入生成的 `AppDatabase`。

## 安全边界

报告页只输出“候选原因”。候选原因来自故障码、冻结帧、相关 PID 和修理工记录的实测步骤，应用不会把未验证的推测标成确定结论。
