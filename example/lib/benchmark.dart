import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xlog/xlog.dart';

enum LogTarget {
  application('默认实例', 'xlog_example'),
  business('业务子实例', 'xlog_other');

  const LogTarget(this.label, this.prefix);
  final String label;
  final String prefix;
}

const benchmarkMessageBytes = 256;
const benchmarkWarmupCount = 200;
const benchmarkCounts = [1000, 10000];
const _tag = 'RequestBenchmark';

/// Generate realistic, varying messages before timing. The byte count excludes
/// the tag and native timestamp/header, compression and encryption overhead.
List<String> benchmarkMessages(int count) => List.generate(count, (index) {
      final id = index.toString().padLeft(6, '0');
      final trace =
          ((index * 2654435761) & 0xffffffff).toRadixString(16).padLeft(8, '0');
      final message = '{"event":"request.completed","request_id":"req-$id",'
          '"method":"POST","route":"/v1/orders","status":200,'
          '"elapsed_ms":${10 + index % 90},"user_id":${1000 + index % 9000},'
          '"network":"wifi","trace":"$trace","note":"订单提交成功"}';
      final padding = benchmarkMessageBytes - utf8.encode(message).length;
      if (padding < 0) throw StateError('Benchmark message exceeds 256 bytes');
      // JSON permits trailing whitespace; pad bytes, not Unicode characters.
      return message.padRight(message.length + padding);
    }, growable: false);

class BenchmarkResult {
  const BenchmarkResult({
    required this.target,
    required this.count,
    required this.writeTime,
    required this.flushTime,
  });

  final LogTarget target;
  final int count;
  final Duration writeTime;
  final Duration flushTime;

  double get writeMilliseconds => writeTime.inMicroseconds / 1000;
  double get flushMilliseconds => flushTime.inMicroseconds / 1000;
  double get microsecondsPerLog => writeTime.inMicroseconds / count;
  double get logsPerSecond => writeTime.inMicroseconds == 0
      ? 0
      : count * Duration.microsecondsPerSecond / writeTime.inMicroseconds;
}

/// Time only the public write calls, including UTF-8 encoding and native work.
/// Flush is timed separately. A successful submission is not a durability claim.
Future<BenchmarkResult> measureBenchmark({
  required LogTarget target,
  required int count,
  required XLogWriter writer,
  required Future<void> Function() flush,
}) async {
  if (!benchmarkCounts.contains(count)) {
    throw ArgumentError.value(count, 'count', 'Use 1000 or 10000');
  }
  if (!writer.isEnabledFor(XLogLevel.info)) {
    throw StateError('INFO 日志未启用，无法测量真实写入');
  }
  final messages = benchmarkMessages(count);
  await flush();
  for (var i = 0; i < benchmarkWarmupCount; i++) {
    if (!writer.write(XLogLevel.info, _tag, messages[i])) {
      throw StateError('预热日志提交失败');
    }
  }
  await flush();

  var rejected = 0;
  final writeWatch = Stopwatch()..start();
  for (final message in messages) {
    if (!writer.write(XLogLevel.info, _tag, message)) rejected++;
  }
  writeWatch.stop();
  final flushWatch = Stopwatch()..start();
  await flush();
  flushWatch.stop();
  if (rejected != 0) {
    throw StateError('$rejected / $count 条日志未成功提交，本次结果无效');
  }
  return BenchmarkResult(
    target: target,
    count: count,
    writeTime: writeWatch.elapsed,
    flushTime: flushWatch.elapsed,
  );
}

Future<BenchmarkResult> runNativeBenchmark(LogTarget target, int count) {
  final token = ServicesBinding.rootIsolateToken;
  if (token == null) throw StateError('请从主 isolate 启动测试');
  return compute(
    _runInWorker,
    _BenchmarkRequest(target, count, token),
    debugLabel: 'xlog-benchmark',
  );
}

class _BenchmarkRequest {
  const _BenchmarkRequest(this.target, this.count, this.token);
  final LogTarget target;
  final int count;
  final RootIsolateToken token;
}

Future<BenchmarkResult> _runInWorker(_BenchmarkRequest request) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(request.token);
  final isDefault = request.target == LogTarget.application;
  final instance =
      isDefault ? null : await XLogManager.getInstance(request.target.prefix);
  if (!isDefault && instance == null) {
    throw StateError('原生子实例尚未初始化：${request.target.prefix}');
  }
  // Bind inside this isolate. Native pointers and scratch buffers are never
  // shared with the UI isolate; both bindings refer to the same native appender.
  final writer = isDefault ? XLogger.defaultWriter : instance!.writer();
  try {
    return await measureBenchmark(
      target: request.target,
      count: request.count,
      writer: writer,
      flush: () => isDefault
          ? XLogManager.flush(sync: true)
          : instance!.flush(sync: true),
    );
  } finally {
    if (isDefault) {
      XLogger.releaseDefaultWriter();
    } else {
      writer.dispose();
    }
  }
}
