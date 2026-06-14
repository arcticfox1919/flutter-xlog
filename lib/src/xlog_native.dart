import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'generated/xlog_bindings.dart';

/// Loads the native xlog library and exposes a shared [XLogBindings].
///
/// The native library is opened and initialized (appender) by the platform
/// side (Kotlin on Android, the linked framework on iOS). Here we only need a
/// handle to the symbols already loaded into the process so Dart can write
/// logs through FFI.
class XLogNative {
  XLogNative._();

  static XLogBindings? _bindings;

  /// The shared bindings instance, lazily resolved on first use.
  static XLogBindings get bindings => _bindings ??= XLogBindings(_open());

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
