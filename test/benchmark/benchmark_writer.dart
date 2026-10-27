// Host bridge microbenchmark; deliberately excludes disk/compression costs.
// Build the capture library with test/native/build_writer_test_library.dart.
// Run this as an AOT executable; uses identical sinks with prebuilt messages.
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:xlog/src/generated/xlog_bindings.dart';
import 'package:xlog/src/log_writer.dart';
import 'package:xlog/src/xlog_native.dart';

void main(List<String> arguments) {
  final suffix = Platform.isWindows
      ? 'dll'
      : Platform.isMacOS
          ? 'dylib'
          : 'so';
  final library = ffi.DynamicLibrary.open(File(
          arguments.length > 1 && !arguments[1].startsWith('--')
              ? arguments[1]
              : '.dart_tool/native_writer/writer_test.$suffix')
      .absolute
      .path);
  final api = XLogNative(library);
  final bindings = api.bindings;
  final records = library
      .lookupFunction<ffi.Int32 Function(), int Function()>('test_records');
  final iterations = arguments.isEmpty ? 200000 : int.parse(arguments.first);
  final fast = NativeLogWriter(api, prefix: 'network');
  final tags = List.generate(
      32, (i) => arguments.contains('--vary-tags') ? 'Module$i' : 'Bench');
  void original(String tag, String message) {
    if (bindings.xlogger_IsEnabledFor(TLogLevel.kLevelInfo) == 0) return;
    using((arena) {
      final info = arena<XLoggerInfo_t>();
      final ref = info.ref;
      ref.levelAsInt = TLogLevel.kLevelInfo.value;
      ref.tag = tag.toNativeUtf8(allocator: arena).cast();
      final us = DateTime.now().microsecondsSinceEpoch;
      ref.timeval1.tv_sec = us ~/ 1000000;
      ref.timeval1.tv_usec = us % 1000000;
      ref.pid = -1;
      ref.tid = -1;
      ref.maintid = -1;
      bindings.xlogger_Write(
          info, message.toNativeUtf8(allocator: arena).cast());
    });
  }

  try {
    for (final sample in <String, String>{
      'ASCII': 'request=0123456789 status=200 elapsed=12ms',
      'CJK':
          '\u8bf7\u6c42\u5b8c\u6210 \u7528\u6237=123 \u72b6\u6001=200 \u8017\u65f6=12ms',
      'emoji': 'request completed \u{1f600}\u{1f680} status=200',
      '1KiB ASCII': 'request=0123456789 ' * 57,
    }.entries) {
      final messages = List.generate(32, (i) => '${sample.value} #$i');
      final operations = <String, void Function(String, String)>{
        if (!arguments.contains('--native-only')) 'original': original,
        'native writer': fast.i,
      };
      final timings = <String, double>{};
      for (final operation in operations.entries) {
        for (var i = 0; i < 10000; i++) {
          operation.value(tags[i & 31], messages[i & 31]);
        }
        final samples = <double>[];
        for (var round = 0; round < 5; round++) {
          final before = records();
          final timer = Stopwatch()..start();
          for (var i = 0; i < iterations; i++) {
            operation.value(tags[i & 31], messages[i & 31]);
          }
          timer.stop();
          if (records() - before != iterations) {
            throw StateError('Lost records in ${operation.key}');
          }
          samples.add(timer.elapsedTicks * 1e9 / timer.frequency / iterations);
        }
        samples.sort();
        timings[operation.key] = samples[2];
      }
      stdout.writeln(sample.key);
      for (final timing in timings.entries) {
        stdout.writeln(
            '  ${timing.key}: ${timing.value.toStringAsFixed(1)} ns/log '
            '(${((timings['original'] ?? timing.value) / timing.value).toStringAsFixed(2)}x)');
      }
    }
  } finally {
    fast.dispose();
  }
}
