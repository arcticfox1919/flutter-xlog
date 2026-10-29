import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'generated/xlog_bindings.dart';

/// Retains the native xlog library, FFI bindings and writer finalizer together.
///
/// The native library is opened and initialized (appender) by the platform
/// side (Kotlin on Android, the linked framework on iOS). Here we only need a
/// handle to the symbols already loaded into the process so Dart can write
/// logs through FFI.
final class XLogNative {
  XLogNative(this.library)
      : bindings = XLogBindings(library),
        finalizer = ffi.NativeFinalizer(
          library.lookup<
                  ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Void>)>>(
              'xlogger_writer_release'),
        );

  /// Requires native 1.4.0, including the per-entry tag writer C API.
  /// Resolve once and retain the library, bindings and finalizer together.
  static final XLogNative instance = XLogNative(_open());

  final ffi.DynamicLibrary library;
  final XLogBindings bindings;
  final ffi.NativeFinalizer finalizer;

  static ffi.DynamicLibrary _open() {
    // On Android the logging symbols live in libmarsxlog.so.
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libmarsxlog.so');
    }
    // On iOS the xlog code is statically linked into the host binary,
    // so the symbols are reachable from the running process.
    if (Platform.isIOS) {
      return ffi.DynamicLibrary.process();
    }
    throw UnsupportedError(
      'xlog FFI is not supported on this platform: ${Platform.operatingSystem}',
    );
  }
}
