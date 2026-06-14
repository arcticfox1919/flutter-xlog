import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import 'generated/xlog_bindings.dart';
import 'xlog_native.dart';

/// Log severity levels, mirroring the native [TLogLevel].
enum XLogLevel {
  verbose(TLogLevel.kLevelVerbose),
  debug(TLogLevel.kLevelDebug),
  info(TLogLevel.kLevelInfo),
  warn(TLogLevel.kLevelWarn),
  error(TLogLevel.kLevelError),
  fatal(TLogLevel.kLevelFatal),
  none(TLogLevel.kLevelNone);

  const XLogLevel(this.native);

  /// The corresponding native enum value.
  final TLogLevel native;

  static XLogLevel fromNative(TLogLevel level) {
    return switch (level) {
      TLogLevel.kLevelAll => XLogLevel.verbose,
      TLogLevel.kLevelDebug => XLogLevel.debug,
      TLogLevel.kLevelInfo => XLogLevel.info,
      TLogLevel.kLevelWarn => XLogLevel.warn,
      TLogLevel.kLevelError => XLogLevel.error,
      TLogLevel.kLevelFatal => XLogLevel.fatal,
      TLogLevel.kLevelNone => XLogLevel.none,
    };
  }
}

/// Dart wrapper over the native xlog logging API.
///
/// Hides FFI pointers, struct layout and memory management; callers pass an
/// already-composed log string.
///
/// The log file lifecycle (open / flush / close) is owned by the platform
/// side (Kotlin on Android, the framework linked into the host on iOS). This
/// class only writes log entries and reads/writes the log level.
///
/// Usage:
/// ```dart
/// XLogger.i('MainPage', 'app started');
/// XLogger.e('Network', 'request failed: $error');
/// ```
class XLogger {
  XLogger._();

  static XLogBindings get _b => XLogNative.bindings;

  // ---------------------------------------------------------------------------
  // Level
  // ---------------------------------------------------------------------------

  /// The current minimum level; entries below it are dropped by the native layer.
  static XLogLevel get level => XLogLevel.fromNative(_b.xlogger_Level());

  static set level(XLogLevel value) => _b.xlogger_SetLevel(value.native);

  /// Whether a log at [level] would currently be emitted.
  static bool isEnabledFor(XLogLevel level) =>
      _b.xlogger_IsEnabledFor(level.native) != 0;

  // ---------------------------------------------------------------------------
  // Writing
  // ---------------------------------------------------------------------------

  static void v(String tag, String message) =>
      log(XLogLevel.verbose, tag, message);

  static void d(String tag, String message) =>
      log(XLogLevel.debug, tag, message);

  static void i(String tag, String message) =>
      log(XLogLevel.info, tag, message);

  static void w(String tag, String message) =>
      log(XLogLevel.warn, tag, message);

  static void e(String tag, String message) =>
      log(XLogLevel.error, tag, message);

  static void f(String tag, String message) =>
      log(XLogLevel.fatal, tag, message);

  /// Writes a single log entry at [level]. [message] is composed by the caller.
  ///
  /// Logging must never break the calling code, so any failure while
  /// marshalling or writing is swallowed. The [using] arena still releases its
  /// native memory either way.
  static void log(XLogLevel level, String tag, String message) {
    // Skip all marshalling when the level is filtered out.
    if (_b.xlogger_IsEnabledFor(level.native) == 0) return;

    try {
      using((arena) {
        final info = arena<XLoggerInfo_t>();
        final ref = info.ref;
        ref.levelAsInt = level.native.value;
        ref.tag = tag.toNativeUtf8(allocator: arena).cast<ffi.Char>();

        // Fill the timestamp so the formatter can render it; otherwise the time
        // field is left empty (the native side only formats it when tv_sec != 0).
        final us = DateTime.now().microsecondsSinceEpoch;
        ref.timeval1.tv_sec = us ~/ 1000000;
        ref.timeval1.tv_usec = us % 1000000;

        // -1 is a sentinel: xlogger_Write fills pid/tid/maintid via
        // xlogger_pid()/tid()/maintid() only when the field equals -1
        ref.pid = -1;
        ref.tid = -1;
        ref.maintid = -1;

        final log = message.toNativeUtf8(allocator: arena).cast<ffi.Char>();
        _b.xlogger_Write(info, log);
      });
    } catch (_) {
      // Intentionally ignored: a logging failure should not propagate.
    }
  }
}
