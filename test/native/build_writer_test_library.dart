// Compiles the production C adapter with a capture sink for host FFI tests.
// Requires a host C++ compiler and the companion native xlog checkout.
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final options = <String, String>{};
  for (var i = 0; i < arguments.length; i += 2) {
    if (i + 1 == arguments.length ||
        !{'--compiler', '--mars-root'}.contains(arguments[i])) {
      throw ArgumentError(
          'Usage: --compiler clang++ --mars-root /path/to/xlog');
    }
    options[arguments[i]] = arguments[i + 1];
  }
  final project = File.fromUri(Platform.script).parent.parent.parent;
  final mars = Directory(
      options['--mars-root'] ?? '${project.parent.parent.path}/c++/xlog');
  final source = File('${mars.path}/mars/xlog/src/xlogger_interface.cc')
      .readAsStringSync();
  const marker =
      '// C ABI adapter. The upstream instance lifecycle and write paths stay unchanged.';
  final start = source.indexOf(marker);
  if (start < 0) throw StateError('Native checkout has no writer C adapter');
  final output = Directory('${project.path}/.dart_tool/native_writer')
    ..createSync(recursive: true);
  final bridge = File('${output.path}/production_writer_adapter.cc')
    ..writeAsStringSync(
        '#include "mars/xlog/xlogger_interface.h"\n${source.substring(start)}');
  final extension = Platform.isWindows
      ? 'dll'
      : Platform.isMacOS
          ? 'dylib'
          : 'so';
  final library = '${output.path}/writer_test.$extension';
  final compiler = options['--compiler'] ?? 'clang++';
  final args = [
    '-std=c++14',
    '-O2',
    '-shared',
    if (!Platform.isWindows) '-fPIC',
    '-I',
    mars.path,
    '-I',
    '${mars.path}/mars/comm/xlogger',
    bridge.path,
    '${project.path}/test/native/writer_test_backend.cc',
    '-o',
    library,
  ];
  final result = await Process.run(compiler, args);
  if (result.exitCode != 0) {
    stderr.write(result.stdout);
    stderr.write(result.stderr);
    exit(result.exitCode);
  }
  stdout.writeln(library);
}
