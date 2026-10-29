import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xlog/xlog.dart';
import 'package:xlog_example/benchmark.dart';
import 'package:xlog_example/logging_demo.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real default and child appenders support both benchmark sizes',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final client = NativeExampleLogClient();
    try {
      await client.initialize();
      for (final target in LogTarget.values) {
        client.writeSample(target);
        for (final count in benchmarkCounts) {
          final result = await client.benchmark(target, count);
          expect(result.target, target);
          expect(result.count, count);
          expect(result.writeTime.inMicroseconds, greaterThan(0));
          expect(result.flushTime.inMicroseconds, greaterThan(0));
          // Diagnostic only: a Debug emulator is not a performance baseline.
          // ignore: avoid_print
          print('${target.prefix}: $count logs, '
              'submit=${result.writeMilliseconds.toStringAsFixed(2)} ms, '
              'flush=${result.flushMilliseconds.toStringAsFixed(2)} ms');
        }
      }
      final files = await client.businessLogFiles();
      expect(files, isNotEmpty);
      expect(files.every((path) => path.contains('xlog_other')), isTrue);
      final child = await XLogManager.getInstance(LogTarget.business.prefix);
      expect(child, isNotNull); // Disposing worker bindings must not close it.
    } finally {
      client.dispose();
    }
  });
}
