import 'package:flutter/material.dart';
import 'package:xlog/xlog.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const _tag = 'XLogExample';

  XLogLevel _level = XLogLevel.verbose;
  late final XLogWriter _writer;
  late final XLogWriter _otherWriter;

  @override
  void initState() {
    super.initState();
    // Note: the log file must be opened by the platform side (e.g. Kotlin
    // XLog.init on Android) before these writes are persisted to disk.
    _level = XLogger.level;
    _writer = XLogger.defaultWriter;
    _otherWriter = XLogger.attach('xlog_other');
    _writer.i(_tag, 'example app started');
    _writer.i('Startup', 'Another tag, same default instance');
    _otherWriter.i('Business', 'Dart bound the second native instance');
  }

  void _write(XLogLevel level) {
    _writer.log(level, _tag,
        'sample ${level.name} log at ${DateTime.now().millisecondsSinceEpoch}');
    _otherWriter.log(level, 'Business', 'sample ${level.name} log');
  }

  @override
  void dispose() {
    // The shared default writer lives with the process. This page owns only
    // the named binding; disposing it keeps the native appender open.
    _otherWriter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('xlog example')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Current level: ${_level.name}'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: () => _write(XLogLevel.verbose),
                    child: const Text('verbose'),
                  ),
                  ElevatedButton(
                    onPressed: () => _write(XLogLevel.debug),
                    child: const Text('debug'),
                  ),
                  ElevatedButton(
                    onPressed: () => _write(XLogLevel.info),
                    child: const Text('info'),
                  ),
                  ElevatedButton(
                    onPressed: () => _write(XLogLevel.warn),
                    child: const Text('warn'),
                  ),
                  ElevatedButton(
                    onPressed: () => _write(XLogLevel.error),
                    child: const Text('error'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _level = _level == XLogLevel.verbose
                        ? XLogLevel.warn
                        : XLogLevel.verbose;
                    XLogger.level = _level;
                  });
                },
                child: const Text('toggle level'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
