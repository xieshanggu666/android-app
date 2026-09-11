import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_obd_assistant/data/record_store.dart';

void main() {
  late Directory temp;
  late FileRecordStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('record_store_test');
    store = FileRecordStore(directory: temp);
    addTearDown(() => temp.delete(recursive: true));
  });

  test('首次读取得到空结构', () async {
    final records = await store.loadRecords();
    expect(records['cases'], isEmpty);
  });

  test('保存后重新读取（模拟应用重启）内容一致', () async {
    await store.saveRecords({
      'version': 1,
      'cases': {
        'case_a': {
          'steps': [
            {
              'stepId': 'a_step_1',
              'status': 'fail',
              'note': '烟雾测试发现泄漏',
              'updatedAt': '2026-09-11T10:30:00.000',
            },
          ],
          'report': {
            'caseId': 'case_a',
            'createdAt': '2026-09-11T10:31:00.000',
            'summary': '草稿',
            'candidateCauses': ['进气泄漏'],
            'stepResults': [
              {
                'stepId': 'a_step_1',
                'status': 'fail',
                'note': '烟雾测试发现泄漏',
                'updatedAt': '2026-09-11T10:30:00.000',
              },
            ],
          },
        },
      },
    });

    // 新建同一目录的实例，等价于重启后的应用进程。
    final reopened = FileRecordStore(directory: temp);
    final records = await reopened.loadRecords();
    final caseA = (records['cases'] as Map)['case_a'] as Map<String, dynamic>;
    final step = (caseA['steps'] as List).single as Map;
    expect(step['status'], 'fail');
    expect(step['note'], '烟雾测试发现泄漏');
    final report = caseA['report'] as Map<String, dynamic>;
    expect(report['candidateCauses'], ['进气泄漏']);
  });

  test('记录文件损坏时降级为空而不是抛异常', () async {
    await File('${temp.path}/obd_assistant_records.json')
        .writeAsString('{broken json');
    final records = await store.loadRecords();
    expect(records['cases'], isEmpty);
  });
}
