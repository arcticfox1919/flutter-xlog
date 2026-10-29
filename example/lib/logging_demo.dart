import 'dart:io';

import 'package:xlog/xlog.dart';

import 'benchmark.dart';

/// UI boundary also lets widget tests run without loading a native library.
abstract class ExampleLogClient {
  Future<void> initialize();
  void writeSample(LogTarget target);
  Future<BenchmarkResult> benchmark(LogTarget target, int count);
  Future<List<String>> businessLogFiles();
  void dispose();
}

class NativeExampleLogClient implements ExampleLogClient {
  XLogInstanceHandle? _business;
  XLogWriter? _businessWriter;
  bool _disposed = false;

  @override
  Future<void> initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError('请在 Android 或 iOS 设备上运行示例');
    }
    final business = await XLogManager.getInstance(LogTarget.business.prefix);
    if (business == null) throw StateError('请在原生启动入口创建 xlog_other');
    // Console mirroring would dominate a logging benchmark.
    await XLogManager.setConsoleLogEnabled(false);
    await business.setConsoleLogEnabled(false);
    if (_disposed) return;
    _businessWriter?.dispose();
    _business = business;
    _businessWriter = business.writer();
    if (!XLogger.defaultWriter.isEnabledFor(XLogLevel.info) ||
        !_businessWriter!.isEnabledFor(XLogLevel.info)) {
      throw StateError('默认实例和子实例均需启用 INFO 日志');
    }
  }

  @override
  void writeSample(LogTarget target) {
    final writer = target == LogTarget.application
        ? XLogger.defaultWriter
        : _businessWriter!;
    final message = target == LogTarget.application
        ? 'event=screen.view screen=benchmark source=button'
        : 'event=order.created order_id=demo-001 amount=128.50 currency=CNY';
    if (!writer.write(XLogLevel.info, 'Example', message)) {
      throw StateError('示例日志提交失败');
    }
  }

  @override
  Future<BenchmarkResult> benchmark(LogTarget target, int count) =>
      runNativeBenchmark(target, count);

  @override
  Future<List<String>> businessLogFiles() async {
    final business = _business!;
    await business.flush(sync: true);
    return business.getLogFiles();
  }

  @override
  void dispose() {
    _disposed = true;
    _businessWriter?.dispose();
    _businessWriter = null;
    // The root-isolate default binding and native appenders live with the app.
    // A page must not close appenders that may still have other producers.
  }
}
