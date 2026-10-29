// Optional companion-SDK contract checks, with Android/JNI replaced by host
// stubs. Not part of the Flutter app build and not an Android runtime test.
import 'dart:io';

const _stubs = {
  'android/content/Context.java':
      'package android.content; public class Context {}',
  'android/os/Looper.java': '''package android.os; public class Looper {
    public static Looper getMainLooper() { return new Looper(); }
    public Thread getThread() { return Thread.currentThread(); } }''',
  'android/os/Handler.java': '''package android.os; public class Handler {
    public Handler(Looper looper) {} public boolean post(Runnable action) {
    action.run(); return true; } }''',
  'android/os/Process.java': '''package android.os; public class Process {
    public static int myPid() { return 1; }
    public static int myTid() { return 1; } }''',
  'android/widget/Toast.java': '''package android.widget;
    import android.content.Context; public class Toast {
    public static final int LENGTH_LONG = 1;
    public static Toast makeText(Context context, String text, int duration) {
    return new Toast(); } public void show() {} }''',
  'android/util/Log.java': '''package android.util; public class Log {
    public static int v(String tag, String text) { return 0; }
    public static int d(String tag, String text) { return 0; }
    public static int i(String tag, String text) { return 0; }
    public static int w(String tag, String text) { return 0; }
    public static int e(String tag, String text) { return 0; }
    public static String getStackTraceString(Throwable error) {
    return error.toString(); } }''',
};

Future<void> _run(String executable, List<String> args) async {
  final result = await Process.run(executable, args);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) exit(result.exitCode);
}

Future<void> main(List<String> arguments) async {
  final options = <String, String>{};
  for (var i = 0; i < arguments.length; i += 2) {
    if (i + 1 == arguments.length ||
        !{
          '--mars-root',
          '--javac',
          '--java',
          '--kotlin-classes',
          '--kotlin-stdlib'
        }.contains(arguments[i])) {
      throw ArgumentError('Expected --option value pairs');
    }
    options[arguments[i]] = arguments[i + 1];
  }
  final kotlin = options['--kotlin-classes'];
  final stdlib = options['--kotlin-stdlib'];
  if ((kotlin == null) != (stdlib == null)) {
    throw ArgumentError('Supply both --kotlin-classes and --kotlin-stdlib');
  }
  final project = File.fromUri(Platform.script).parent.parent.parent;
  final mars =
      options['--mars-root'] ?? '${project.parent.parent.path}/c++/xlog';
  final output = '${project.path}/.dart_tool/java_instance_test';
  final sources = <String>[];
  for (final stub in _stubs.entries) {
    final file = File('$output/stubs/${stub.key}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(stub.value);
    sources.add(file.path);
  }
  for (final module in ['mars_xlog_sdk', 'mars_android_sdk']) {
    final classes = Directory('$output/$module')..createSync(recursive: true);
    final javaSource =
        '$mars/mars/libraries/$module/src/main/java/com/tencent/mars/xlog';
    await _run(options['--javac'] ?? 'javac', [
      '-source',
      '8',
      '-target',
      '8',
      '-Xlint:-options',
      '-encoding',
      'UTF-8',
      '-d',
      classes.path,
      ...sources,
      '$javaSource/Log.java',
      '$javaSource/Xlog.java',
      '${project.path}/test/java/ConfiguredInstanceTest.java',
      '${project.path}/test/java/InstanceLifecycleTest.java',
    ]);
    stdout.writeln(module);
    final includeKotlin = module == 'mars_xlog_sdk' && kotlin != null;
    final classpath = [
      classes.path,
      if (includeKotlin) kotlin,
      if (includeKotlin) stdlib!,
    ].join(Platform.isWindows ? ';' : ':');
    await _run(options['--java'] ?? 'java', [
      '-cp',
      classpath,
      'ConfiguredInstanceTest',
      if (includeKotlin) 'kotlin',
    ]);
    await _run(options['--java'] ?? 'java', [
      '-cp',
      classes.path,
      'InstanceLifecycleTest',
    ]);
  }
}
