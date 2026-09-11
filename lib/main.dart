import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'models/diagnostics.dart';
import 'state/diagnostic_controller.dart';

void main() {
  runApp(const ProviderScope(child: ObdAssistantApp()));
}

class ObdAssistantApp extends StatelessWidget {
  const ObdAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '手机端故障排查助手',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF256D85),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F7F4),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      home: const DiagnosticWorkbench(),
    );
  }
}

class DiagnosticWorkbench extends ConsumerStatefulWidget {
  const DiagnosticWorkbench({super.key});

  @override
  ConsumerState<DiagnosticWorkbench> createState() => _DiagnosticWorkbenchState();
}

class _DiagnosticWorkbenchState extends ConsumerState<DiagnosticWorkbench> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(diagnosticControllerProvider);
    final controller = ref.read(diagnosticControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('故障排查助手'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              avatar: Icon(
                state.offlineMode ? Icons.cloud_off : Icons.cloud_done,
                size: 18,
              ),
              label: Text(state.offlineMode ? '离线可用' : '在线同步'),
            ),
          ),
        ],
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  _CaseHeader(state: state, onCaseChanged: controller.selectCase),
                  if (state.warning != null) SafetyNotice(text: state.warning!),
                  Expanded(
                    child: IndexedStack(
                      index: _tabIndex,
                      children: [
                        ConnectionPage(state: state, controller: controller),
                        PidPage(state: state),
                        FaultGraphPage(state: state),
                        GuidedStepsPage(state: state, controller: controller),
                        ComparisonPage(state: state),
                        ReportPage(state: state, controller: controller),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (value) => setState(() => _tabIndex = value),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bluetooth_searching), label: '连接'),
          NavigationDestination(icon: Icon(Icons.monitor_heart), label: '数据'),
          NavigationDestination(icon: Icon(Icons.hub), label: '关联'),
          NavigationDestination(icon: Icon(Icons.rule), label: '步骤'),
          NavigationDestination(icon: Icon(Icons.compare_arrows), label: '对比'),
          NavigationDestination(icon: Icon(Icons.description), label: '报告'),
        ],
      ),
    );
  }
}

class _CaseHeader extends StatelessWidget {
  const _CaseHeader({required this.state, required this.onCaseChanged});

  final DiagnosticState state;
  final ValueChanged<String> onCaseChanged;

  @override
  Widget build(BuildContext context) {
    final diagnosticCase = state.selectedCase;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: diagnosticCase?.id,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '故障案例 / 离线车型资料',
              prefixIcon: Icon(Icons.directions_car),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final item in state.cases)
                DropdownMenuItem(value: item.id, child: Text(item.name)),
            ],
            onChanged: (value) {
              if (value != null) {
                onCaseChanged(value);
              }
            },
          ),
          if (diagnosticCase != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _InfoChip(icon: Icons.memory, label: '${diagnosticCase.ecus.length} 个控制单元'),
                _InfoChip(icon: Icons.error_outline, label: '${diagnosticCase.codes.length} 个故障码'),
                _InfoChip(icon: Icons.car_repair, label: diagnosticCase.vehicle),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class SafetyNotice extends StatelessWidget {
  const SafetyNotice({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF4D8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined, size: 20, color: Color(0xFF8A5A00)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF5F4300),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class ConnectionPage extends StatelessWidget {
  const ConnectionPage({super.key, required this.state, required this.controller});

  final DiagnosticState state;
  final DiagnosticController controller;

  @override
  Widget build(BuildContext context) {
    return WorkbenchScroll(
      children: [
        SectionTitle(
          icon: Icons.bluetooth_connected,
          title: '设备连接',
          subtitle: _statusText(state.status),
        ),
        FilledButton.icon(
          onPressed: state.status == ObdConnectionStatus.scanning
              ? null
              : controller.scanDevices,
          icon: const Icon(Icons.search),
          label: const Text('扫描蓝牙 OBD'),
        ),
        if (state.status == ObdConnectionStatus.connected) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: controller.disconnect,
            icon: const Icon(Icons.link_off),
            label: const Text('断开 OBD（清空本次实时读数）'),
          ),
        ],
        const SizedBox(height: 12),
        for (final device in state.devices)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DeviceTile(device: device, onConnect: () => controller.connect(device)),
          ),
        const SizedBox(height: 14),
        OfflineLibraryCard(vehicles: state.vehicles),
      ],
    );
  }

  String _statusText(ObdConnectionStatus status) {
    return switch (status) {
      ObdConnectionStatus.disconnected => '未连接，支持虚拟 OBD 或真实蓝牙入口',
      ObdConnectionStatus.scanning => '正在扫描附近设备',
      ObdConnectionStatus.connected => '已连接，正在接收实测 PID',
    };
  }
}

class DeviceTile extends StatelessWidget {
  const DeviceTile({super.key, required this.device, required this.onConnect});

  final ObdDevice device;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: device.mode == ConnectionMode.virtual
              ? const Color(0xFFE6F4EA)
              : const Color(0xFFE7F0FF),
          child: Icon(
            device.mode == ConnectionMode.virtual ? Icons.memory : Icons.bluetooth,
          ),
        ),
        title: Text(device.name),
        subtitle: Text('信号 ${device.signalStrength}% · ${device.mode == ConnectionMode.virtual ? '虚拟数据源' : '蓝牙设备'}'),
        trailing: FilledButton.icon(
          onPressed: onConnect,
          icon: const Icon(Icons.link),
          label: const Text('连接'),
        ),
      ),
    );
  }
}

class OfflineLibraryCard extends StatelessWidget {
  const OfflineLibraryCard({super.key, required this.vehicles});

  final List<VehicleProfile> vehicles;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(
              icon: Icons.storage,
              title: '离线资料包',
              subtitle: '车型资料、检测记录和报告草稿保存在本机',
              compact: true,
            ),
            const SizedBox(height: 8),
            for (final vehicle in vehicles)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_copy_outlined),
                title: Text(vehicle.name),
                subtitle: Text('${vehicle.engine} · ${vehicle.notes.join(' / ')}'),
              ),
          ],
        ),
      ),
    );
  }
}

class PidPage extends StatelessWidget {
  const PidPage({super.key, required this.state});

  final DiagnosticState state;

  @override
  Widget build(BuildContext context) {
    final selectedPids = _selectedPidDefinitions(state);
    return WorkbenchScroll(
      children: [
        const SectionTitle(
          icon: Icons.monitor_heart,
          title: 'PID 仪表与曲线',
          subtitle: '默认展示与当前故障码相关的实时数据流',
        ),
        if (state.status != ObdConnectionStatus.connected)
          const LiveReadingsUnavailableCard(),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final definition in selectedPids)
              PidGauge(
                definition: definition,
                reading: state.liveReadings[definition.id],
                reference: state.selectedCase?.beforeReadings[definition.id],
              ),
          ],
        ),
        const SizedBox(height: 14),
        for (final definition in selectedPids.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PidChart(
              definition: definition,
              series: state.history[definition.id] ?? const [],
            ),
          ),
        FreezeFrameCard(frame: state.selectedCase?.freezeFrame),
      ],
    );
  }

  List<PidDefinition> _selectedPidDefinitions(DiagnosticState state) {
    final selected = <String>{
      for (final code in state.selectedCase?.codes ?? const <TroubleCode>[])
        ...code.relatedPids,
    };
    return state.pidCatalog.where((pid) => selected.contains(pid.id)).toList();
  }
}

class LiveReadingsUnavailableCard extends StatelessWidget {
  const LiveReadingsUnavailableCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F0FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.bluetooth_disabled, size: 20, color: Color(0xFF0B3D91)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '未连接 OBD：暂无实时实测数据。下方数值仅为离线案例的维修前参考值，不会作为实测结果写入维修报告。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF0B3D91),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class PidGauge extends StatelessWidget {
  const PidGauge({
    super.key,
    required this.definition,
    required this.reading,
    required this.reference,
  });

  final PidDefinition definition;
  final PidReading? reading;
  final double? reference;

  @override
  Widget build(BuildContext context) {
    final live = reading != null;
    final value = live
        ? reading!.value
        : reference ?? (definition.min + definition.max) / 2;
    final ratio = ((value - definition.min) / (definition.max - definition.min))
        .clamp(0.0, 1.0)
        .toDouble();
    // 只有实时读数才按超差标红；离线参考值保持中性展示，避免被误读为现场异常。
    final abnormal = live &&
        (value < definition.normalLow || value > definition.normalHigh);
    return SizedBox(
      width: 164,
      child: Card(
        color: live
            ? (abnormal ? const Color(0xFFFFECE8) : Colors.white)
            : const Color(0xFFF3F2EE),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(definition.name, style: Theme.of(context).textTheme.labelLarge),
                  ),
                  Icon(
                    live ? Icons.sensors : Icons.history_toggle_off,
                    size: 15,
                    color: live ? const Color(0xFF2E7D32) : Colors.grey,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                minHeight: 9,
                value: live ? ratio : null,
                backgroundColor: const Color(0xFFE7E4DC),
                color: abnormal
                    ? const Color(0xFFB3261E)
                    : live
                        ? const Color(0xFF2E7D32)
                        : Colors.grey,
              ),
              const SizedBox(height: 10),
              Text(
                '${value.toStringAsFixed(value.abs() >= 100 ? 0 : 1)} ${definition.unit}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                live
                    ? '正常 ${definition.normalLow}-${definition.normalHigh}'
                    : '案例维修前参考值 · 非实时',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: live ? null : Colors.grey,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PidChart extends StatelessWidget {
  const PidChart({
    super.key,
    required this.definition,
    required this.series,
  });

  final PidDefinition definition;
  final List<PidReading> series;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(definition.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 190,
              child: series.isEmpty
                  ? Center(
                      child: Text(
                        '连接 OBD 后显示实时曲线',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                            ),
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        minY: definition.min,
                        maxY: definition.max,
                        gridData: const FlGridData(show: true),
                        borderData: FlBorderData(show: false),
                        titlesData: const FlTitlesData(
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        extraLinesData: ExtraLinesData(
                          horizontalLines: [
                            HorizontalLine(y: definition.normalLow, color: Colors.green, strokeWidth: 1),
                            HorizontalLine(y: definition.normalHigh, color: Colors.green, strokeWidth: 1),
                          ],
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              for (var index = 0; index < series.length; index++)
                                FlSpot(index.toDouble(), series[index].value),
                            ],
                            isCurved: true,
                            color: const Color(0xFF256D85),
                            barWidth: 3,
                            dotData: const FlDotData(show: false),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class FreezeFrameCard extends StatelessWidget {
  const FreezeFrameCard({super.key, required this.frame});

  final FreezeFrame? frame;

  @override
  Widget build(BuildContext context) {
    final item = frame;
    if (item == null) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(
              icon: Icons.ac_unit,
              title: '冻结帧',
              subtitle: '故障触发时刻的关键工况',
              compact: true,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(icon: Icons.speed, label: '${item.engineRpm} rpm'),
                _InfoChip(icon: Icons.social_distance, label: '${item.vehicleSpeed} km/h'),
                _InfoChip(icon: Icons.thermostat, label: '${item.coolantTemp} C'),
                _InfoChip(icon: Icons.local_gas_station, label: 'STFT ${item.fuelTrimShort}%'),
                _InfoChip(icon: Icons.timeline, label: 'LTFT ${item.fuelTrimLong}%'),
                _InfoChip(icon: Icons.bolt, label: '负荷 ${item.load}%'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class FaultGraphPage extends StatelessWidget {
  const FaultGraphPage({super.key, required this.state});

  final DiagnosticState state;

  @override
  Widget build(BuildContext context) {
    final diagnosticCase = state.selectedCase;
    if (diagnosticCase == null) {
      return const SizedBox.shrink();
    }
    return WorkbenchScroll(
      children: [
        const SectionTitle(
          icon: Icons.hub,
          title: '故障关联图',
          subtitle: '故障码、冻结帧、实测 PID 和候选原因的证据链',
        ),
        Card(
          child: SizedBox(
            height: 300,
            child: CustomPaint(
              painter: FaultGraphPainter(diagnosticCase),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final code in diagnosticCase.codes)
          Card(
            child: ListTile(
              leading: CircleAvatar(child: Text(code.severity)),
              title: Text('${code.code} · ${code.title}'),
              subtitle: Text('${code.description}\n候选原因：${code.candidateCauses.join('；')}'),
              isThreeLine: true,
            ),
          ),
      ],
    );
  }
}

class FaultGraphPainter extends CustomPainter {
  FaultGraphPainter(this.diagnosticCase);

  final DiagnosticCase diagnosticCase;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFFB9B4A8)
      ..strokeWidth = 1.4;
    final codePaint = Paint()..color = const Color(0xFFDCEFF3);
    final pidPaint = Paint()..color = const Color(0xFFE8F1DD);
    final causePaint = Paint()..color = const Color(0xFFFFE2D8);
    final center = Offset(size.width * 0.5, 56);
    _drawNode(canvas, center, 'ECU扫描', codePaint, bold: true);

    final codeY = 132.0;
    final pidY = 212.0;
    final causesY = 274.0;
    for (var i = 0; i < diagnosticCase.codes.length; i++) {
      final code = diagnosticCase.codes[i];
      final x = size.width * (i + 1) / (diagnosticCase.codes.length + 1);
      final codePoint = Offset(x, codeY);
      canvas.drawLine(center.translate(0, 24), codePoint.translate(0, -24), linePaint);
      _drawNode(canvas, codePoint, code.code, codePaint);
      for (var j = 0; j < code.relatedPids.length; j++) {
        final pidX = x + (j - (code.relatedPids.length - 1) / 2) * 74;
        final pidPoint = Offset(
          pidX.clamp(54.0, size.width - 54.0).toDouble(),
          pidY,
        );
        canvas.drawLine(codePoint.translate(0, 24), pidPoint.translate(0, -20), linePaint);
        _drawNode(canvas, pidPoint, code.relatedPids[j], pidPaint, small: true);
      }
      final causePoint = Offset(x, causesY);
      canvas.drawLine(codePoint.translate(0, 24), causePoint.translate(0, -20), linePaint);
      _drawNode(canvas, causePoint, '候选原因', causePaint, small: true);
    }
  }

  void _drawNode(
    Canvas canvas,
    Offset center,
    String label,
    Paint paint, {
    bool bold = false,
    bool small = false,
  }) {
    final radiusX = small ? 44.0 : 56.0;
    final radiusY = small ? 19.0 : 24.0;
    final rect = Rect.fromCenter(center: center, width: radiusX * 2, height: radiusY * 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      paint,
    );
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: const Color(0xFF263238),
          fontSize: small ? 11 : 13,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: radiusX * 1.7);
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant FaultGraphPainter oldDelegate) {
    return oldDelegate.diagnosticCase.id != diagnosticCase.id;
  }
}

class GuidedStepsPage extends StatelessWidget {
  const GuidedStepsPage({super.key, required this.state, required this.controller});

  final DiagnosticState state;
  final DiagnosticController controller;

  @override
  Widget build(BuildContext context) {
    final steps = state.selectedCase?.steps ?? const <GuidedStep>[];
    return WorkbenchScroll(
      children: [
        const SectionTitle(
          icon: Icons.rule,
          title: '引导式排查步骤',
          subtitle: '按检测步骤记录结果，报告草稿离线保存',
        ),
        for (final step in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: StepResultCard(
              step: step,
              result: state.stepResults[step.id],
              onChanged: controller.updateStep,
            ),
          ),
      ],
    );
  }
}

class StepResultCard extends StatelessWidget {
  const StepResultCard({
    super.key,
    required this.step,
    required this.result,
    required this.onChanged,
  });

  final GuidedStep step;
  final StepResult? result;
  final void Function(String stepId, StepStatus status, String note) onChanged;

  @override
  Widget build(BuildContext context) {
    final current = result ?? StepResult(
      stepId: step.id,
      status: StepStatus.pending,
      note: '',
      updatedAt: DateTime.now(),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(step.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(step.method),
            const SizedBox(height: 6),
            Text('判定标准：${step.expected}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            DropdownButtonFormField<StepStatus>(
              value: current.status,
              decoration: const InputDecoration(
                labelText: '检测结果',
                prefixIcon: Icon(Icons.fact_check),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: StepStatus.pending, child: Text('待测')),
                DropdownMenuItem(value: StepStatus.pass, child: Text('通过')),
                DropdownMenuItem(value: StepStatus.fail, child: Text('异常')),
                DropdownMenuItem(value: StepStatus.skipped, child: Text('跳过')),
              ],
              onChanged: (value) {
                if (value != null) {
                  onChanged(step.id, value, current.note);
                }
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: current.note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '现场记录',
                prefixIcon: Icon(Icons.edit_note),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => onChanged(step.id, current.status, value),
              onFieldSubmitted: (value) => onChanged(step.id, current.status, value),
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            ),
          ],
        ),
      ),
    );
  }
}

class ComparisonPage extends StatelessWidget {
  const ComparisonPage({super.key, required this.state});

  final DiagnosticState state;

  @override
  Widget build(BuildContext context) {
    final diagnosticCase = state.selectedCase;
    if (diagnosticCase == null) {
      return const SizedBox.shrink();
    }
    final definitions = {for (final pid in state.pidCatalog) pid.id: pid};
    final live = state.status == ObdConnectionStatus.connected;
    return WorkbenchScroll(
      children: [
        const SectionTitle(
          icon: Icons.compare_arrows,
          title: '试车前后对比',
          subtitle: '使用同一批 PID 对比维修前、维修后和当前实测值',
        ),
        if (!live)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '未连接 OBD：“当前”列暂无实测读数，显示为 --；“前/后”两列为离线案例参考值。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF0B3D91)),
            ),
          ),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('PID')),
                DataColumn(label: Text('前')),
                DataColumn(label: Text('后')),
                DataColumn(label: Text('当前')),
              ],
              rows: [
                for (final entry in diagnosticCase.beforeReadings.entries)
                  DataRow(
                    cells: [
                      DataCell(Text(definitions[entry.key]?.name ?? entry.key)),
                      DataCell(Text(entry.value.toStringAsFixed(1))),
                      DataCell(Text((diagnosticCase.afterReadings[entry.key] ?? 0).toStringAsFixed(1))),
                      DataCell(Text(
                        state.liveReadings[entry.key]?.value.toStringAsFixed(1) ?? '--',
                        style: live ? null : const TextStyle(color: Colors.grey),
                      )),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ReportPage extends StatelessWidget {
  const ReportPage({super.key, required this.state, required this.controller});

  final DiagnosticState state;
  final DiagnosticController controller;

  @override
  Widget build(BuildContext context) {
    final diagnosticCase = state.selectedCase;
    final report = state.report;
    // 报告未生成时预览当前记录；生成后展示草稿内的快照，保证报告内容与生成时间一致。
    final shownResults = report?.stepResults ?? state.stepResults.values.toList();
    final stale = report != null && _reportIsStale(report, state);
    return WorkbenchScroll(
      children: [
        const SectionTitle(
          icon: Icons.description,
          title: '维修报告',
          subtitle: '离线草稿，结论区只输出候选原因',
        ),
        FilledButton.icon(
          onPressed: controller.generateReport,
          icon: const Icon(Icons.summarize),
          label: const Text('生成报告草稿'),
        ),
        const SizedBox(height: 12),
        if (stale)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4D8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '检测步骤在草稿生成后有修改，请重新生成报告草稿以同步最新结果与现场备注。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF8A5A00),
                  ),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(diagnosticCase?.name ?? '未选择案例', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(report?.summary ?? '完成检测步骤后生成报告草稿。'),
                const Divider(height: 24),
                Text('候选原因', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                if (report == null || report.candidateCauses.isEmpty)
                  const Text('暂无。应用不会把未验证的推测标成确定结论。')
                else
                  for (final cause in report.candidateCauses)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.help_outline, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(cause)),
                        ],
                      ),
                    ),
                const Divider(height: 24),
                ReportStepResults(
                  steps: diagnosticCase?.steps ?? const <GuidedStep>[],
                  results: shownResults,
                  isDraftSnapshot: report != null,
                ),
                const Divider(height: 24),
                Text(
                  '生成时间：${report == null ? '-' : DateFormat('yyyy-MM-dd HH:mm').format(report.createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool _reportIsStale(RepairReport report, DiagnosticState state) {
    for (final result in report.stepResults) {
      final current = state.stepResults[result.stepId];
      if (current == null ||
          current.status != result.status ||
          current.note != result.note) {
        return true;
      }
    }
    return false;
  }
}

class ReportStepResults extends StatelessWidget {
  const ReportStepResults({
    super.key,
    required this.steps,
    required this.results,
    required this.isDraftSnapshot,
  });

  final List<GuidedStep> steps;
  final List<StepResult> results;
  final bool isDraftSnapshot;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final step in steps) step.id: step};
    final recorded =
        results.where((result) => result.status != StepStatus.pending).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('检测步骤记录', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(
          '已记录 $recorded/${results.length} 步'
          '${isDraftSnapshot ? '（以下为草稿生成时的快照）' : '（生成草稿后随报告保存）'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (results.isEmpty)
          const Text('暂无检测步骤。')
        else
          for (final result in results)
            _ReportStepTile(step: byId[result.stepId], result: result),
      ],
    );
  }
}

class _ReportStepTile extends StatelessWidget {
  const _ReportStepTile({required this.step, required this.result});

  final GuidedStep? step;
  final StepResult result;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (result.status) {
      StepStatus.pending => (Icons.fiber_manual_record_outlined, Colors.grey, '待检测'),
      StepStatus.pass => (Icons.check_circle_outline, const Color(0xFF2E7D32), '通过'),
      StepStatus.fail => (Icons.cancel_outlined, const Color(0xFFB3261E), '异常'),
      StepStatus.skipped => (Icons.skip_next_outlined, const Color(0xFF8A5A00), '跳过'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  step?.title ?? result.stepId,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
            ],
          ),
          if (step != null) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                '判定标准：${step!.expected}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 4),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F2EE),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                result.note.trim().isEmpty ? '未填写现场备注' : result.note,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: result.note.trim().isEmpty ? Colors.grey : null,
                      fontStyle:
                          result.note.trim().isEmpty ? FontStyle.italic : null,
                    ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 2),
            child: Text(
              '更新时间：${DateFormat('yyyy-MM-dd HH:mm').format(result.updatedAt)}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

class WorkbenchScroll extends StatelessWidget {
  const WorkbenchScroll({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: children,
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 4 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: compact ? Theme.of(context).textTheme.titleMedium : Theme.of(context).textTheme.titleLarge),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 17),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}
