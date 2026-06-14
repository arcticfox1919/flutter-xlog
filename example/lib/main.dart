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

  @override
  void initState() {
    super.initState();
    // Note: the log file must be opened by the platform side (e.g. Kotlin
    // XLog.init on Android) before these writes are persisted to disk.
    _level = XLogger.level;
    XLogger.i(_tag, 'example app started');
  }

  void _write(XLogLevel level, void Function(String, String) fn) {
    fn(_tag, 'sample ${level.name} log at ${DateTime.now().millisecondsSinceEpoch}');
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
                    onPressed: () => _write(XLogLevel.verbose, XLogger.v),
                    child: const Text('verbose'),
                  ),
                  ElevatedButton(
                    onPressed: () => _write(XLogLevel.debug, XLogger.d),
                    child: const Text('debug'),
                  ),
                  ElevatedButton(
                    onPressed: () => _write(XLogLevel.info, XLogger.i),
                    child: const Text('info'),
                  ),
                  ElevatedButton(
                    onPressed: () => _write(XLogLevel.warn, XLogger.w),
                    child: const Text('warn'),
                  ),
                  ElevatedButton(
                    onPressed: () => _write(XLogLevel.error, XLogger.e),
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
