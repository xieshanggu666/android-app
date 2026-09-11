import 'package:drift/drift.dart';

class DiagnosticDrafts extends Table {
  TextColumn get id => text()();
  TextColumn get caseId => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class TestRecords extends Table {
  TextColumn get id => text()();
  TextColumn get caseId => text()();
  TextColumn get stepId => text()();
  TextColumn get status => text()();
  TextColumn get note => text()();
  DateTimeColumn get recordedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class OfflineSchemaNotes {
  const OfflineSchemaNotes();

  String get summary =>
      'Drift tables for diagnostic drafts and detection records. In production '
      'wire these tables to a generated AppDatabase and persist to device '
      'storage via sqlite3_flutter_libs/path_provider.';
}
