import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_obd_assistant/models/diagnostics.dart';

void main() {
  test('candidate result wording stays non-deterministic', () {
    const code = TroubleCode(
      code: 'P0171',
      title: '系统过稀 Bank 1',
      ecu: 'ECM',
      severity: '中',
      description: '闭环燃油修正持续偏高。',
      relatedPids: ['stft_b1'],
      candidateCauses: ['进气系统存在未计量空气泄漏'],
    );

    expect(code.candidateCauses.single, contains('泄漏'));
    expect(code.candidateCauses.single, isNot(contains('确定')));
  });

  test('PID reading detects values outside measured normal range', () {
    const definition = PidDefinition(
      id: 'stft_b1',
      name: '短期燃油修正 B1',
      unit: '%',
      min: -35,
      max: 35,
      normalLow: -10,
      normalHigh: 10,
    );
    final reading = PidReading(
      pid: 'stft_b1',
      value: 18.4,
      timestamp: DateTime(2026, 9, 11),
    );

    expect(reading.isOutOfRange(definition), isTrue);
  });
}
