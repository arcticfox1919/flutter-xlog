import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xlog/xlog.dart';
import 'package:xlog_example/benchmark.dart';

class RecordingWriter extends XLogWriter {
  bool enabled = true;
  int writes = 0;
  int? rejectAt;
  final phases = <int>[];

  @override
  bool isEnabledFor(XLogLevel level) => enabled;

  @override
  bool write(XLogLevel level, String tag, String message) {
    expect(level, XLogLevel.info);
    writes++;
    return writes != rejectAt;
  }

  Future<void> flush() async => phases.add(writes);

  @override
  void dispose() {}
}

void main() {
  test('messages have moderate fixed UTF-8 size and varying request data', () {
    final messages = benchmarkMessages(10000);
    expect(messages.map((m) => utf8.encode(m).length).toSet(), {256});
    final first = jsonDecode(messages.first) as Map<String, dynamic>;
    final last = jsonDecode(messages.last) as Map<String, dynamic>;
    expect(first['note'], '订单提交成功');
    expect(first['request_id'], isNot(last['request_id']));
    expect(messages.toSet(), hasLength(10000));
  });

  for (final count in benchmarkCounts) {
    test('$count writes are measured after warmup and flushed afterwards',
        () async {
      final writer = RecordingWriter();
      final result = await measureBenchmark(
        target: LogTarget.business,
        count: count,
        writer: writer,
        flush: writer.flush,
      );
      expect(writer.phases,
          [0, benchmarkWarmupCount, benchmarkWarmupCount + count]);
      expect(result.count, count);
      expect(result.target, LogTarget.business);
      expect(result.writeTime, greaterThanOrEqualTo(Duration.zero));
      expect(result.flushTime, greaterThanOrEqualTo(Duration.zero));
    });
  }

  test('filtered INFO is an error, not a spuriously fast benchmark', () async {
    final writer = RecordingWriter()..enabled = false;
    await expectLater(
      measureBenchmark(
          target: LogTarget.application,
          count: 1000,
          writer: writer,
          flush: writer.flush),
      throwsStateError,
    );
    expect(writer.writes, 0);
    expect(writer.phases, isEmpty);
  });

  test('a rejected timed entry invalidates the whole result', () async {
    final writer = RecordingWriter()..rejectAt = benchmarkWarmupCount + 500;
    await expectLater(
      measureBenchmark(
          target: LogTarget.application,
          count: 1000,
          writer: writer,
          flush: writer.flush),
      throwsStateError,
    );
    expect(writer.phases.last, benchmarkWarmupCount + 1000);
  });

  test('flush failures do not produce a success result', () async {
    final writer = RecordingWriter();
    var flushes = 0;
    await expectLater(
      measureBenchmark(
          target: LogTarget.business,
          count: 1000,
          writer: writer,
          flush: () async {
            if (++flushes == 3) throw StateError('flush failed');
          }),
      throwsStateError,
    );
  });
}
