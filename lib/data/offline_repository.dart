import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/diagnostics.dart';

class OfflineRepository {
  Future<List<VehicleProfile>> loadVehicles() async {
    final raw = await rootBundle.loadString('assets/offline_vehicle_library.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return (decoded['vehicles'] as List)
        .map((item) => VehicleProfile.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<DiagnosticCase>> loadCases() async {
    final raw = await rootBundle.loadString('assets/fault_cases.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return (decoded['cases'] as List)
        .map((item) => DiagnosticCase.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<PidDefinition>> loadPidCatalog() async {
    final raw = await rootBundle.loadString('assets/config/pid_catalog.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return (decoded['pids'] as List)
        .map((item) => PidDefinition.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
