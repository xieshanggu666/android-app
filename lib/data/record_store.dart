import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 检测步骤结果与报告草稿的离线持久化。
///
/// 现场流程要求：修理工填写的步骤结果、现场备注和已生成的报告草稿，
/// 在应用关闭重启后必须仍然存在。当前实现把全部记录以 JSON 原子写入
/// 应用文档目录；`local_database.dart` 中的 Drift 表是后续生产落地的目标
/// schema，接入 build_runner 生成 AppDatabase 后可替换本实现而不改 controller。
abstract class RecordStore {
  /// 读取全部记录；文件不存在或损坏时返回空结构，绝不抛出影响启动。
  Future<Map<String, dynamic>> loadRecords();

  /// 覆盖写入全部记录（原子写：先写临时文件再 rename）。
  Future<void> saveRecords(Map<String, dynamic> records);
}

class FileRecordStore implements RecordStore {
  FileRecordStore({
    this.fileName = 'obd_assistant_records.json',
    Directory? directory,
  }) : _directory = directory;

  static const _version = 1;
  final String fileName;
  final Directory? _directory;

  static Map<String, dynamic> emptyRecords() =>
      const {'version': _version, 'cases': <String, dynamic>{}};

  Future<Directory> _resolveDirectory() async {
    return _directory ?? await getApplicationDocumentsDirectory();
  }

  @override
  Future<Map<String, dynamic>> loadRecords() async {
    try {
      final dir = await _resolveDirectory();
      final file = File(p.join(dir.path, fileName));
      if (!await file.exists()) {
        return emptyRecords();
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic> && decoded['cases'] is Map) {
        return decoded;
      }
      return emptyRecords();
    } on FormatException {
      // 记录文件损坏时降级为空记录，避免阻断应用启动。
      return emptyRecords();
    }
  }

  @override
  Future<void> saveRecords(Map<String, dynamic> records) async {
    final dir = await _resolveDirectory();
    await dir.create(recursive: true);
    final temp = File(p.join(dir.path, '.$fileName.tmp'));
    await temp.writeAsString(jsonEncode(records), flush: true);
    await temp.rename(p.join(dir.path, fileName));
  }
}

/// 测试用内存实现，行为与文件实现一致（深拷贝避免调用方就地篡改）。
class InMemoryRecordStore implements RecordStore {
  Map<String, dynamic> _data = FileRecordStore.emptyRecords();

  @override
  Future<Map<String, dynamic>> loadRecords() async {
    return jsonDecode(jsonEncode(_data)) as Map<String, dynamic>;
  }

  @override
  Future<void> saveRecords(Map<String, dynamic> records) async {
    _data = jsonDecode(jsonEncode(records)) as Map<String, dynamic>;
  }
}
