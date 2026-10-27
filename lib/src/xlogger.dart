import 'log_writer.dart';
import 'xlog_level.dart';
import 'xlog_native.dart';

export 'log_writer.dart' show XLogWriter;
export 'xlog_level.dart' show XLogLevel;

/// Writes to the default native log instance, or binds a named native instance.
/// Writers select the destination; tags are supplied separately for each entry.
class XLogger {
  XLogger._();
  static XLogWriter? _defaultWriter;

  // ---------------------------------------------------------------------------
  // Level
  // ---------------------------------------------------------------------------

  /// The current minimum level; entries below it are dropped by the native layer.
  static XLogLevel get level =>
      XLogLevel.fromNative(XLogNative.instance.bindings.xlogger_Level());

  static set level(XLogLevel value) =>
      XLogNative.instance.bindings.xlogger_SetLevel(value.native);

  /// Whether a log at [level] would currently be emitted.
  static bool isEnabledFor(XLogLevel level) =>
      level != XLogLevel.none &&
      XLogNative.instance.bindings.xlogger_IsEnabledFor(level.native) != 0;

  // ---------------------------------------------------------------------------
  // Writers
  // ---------------------------------------------------------------------------

  /// Binds an existing native instance. No appender is created. Native owners
  /// must keep it open while using this writer; missing instances throw.
  /// Requires a native binary exposing writer C API from xloggerbase.h.
  /// [prefix] and entry tags must not contain NUL (U+0000). This precondition
  /// is not checked; native C strings end at the first NUL character.
  static XLogWriter attach(String prefix) {
    return NativeLogWriter(XLogNative.instance, prefix: prefix);
  }

  /// Shared process-lifetime writing handle for the default native instance.
  /// All static log methods reuse this handle, regardless of tag. It owns no
  /// native appender. Use [releaseDefaultWriter] for an explicit binding reset.
  static XLogWriter get defaultWriter =>
      _defaultWriter ??= NativeLogWriter(XLogNative.instance);

  /// Releases only the default writing handle; it does not close or flush the
  /// appender. Stop its producers first. Retained references become disposed;
  /// the next [defaultWriter] access binds a fresh handle.
  static void releaseDefaultWriter() {
    _defaultWriter?.dispose();
    _defaultWriter = null;
  }

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

  /// Reuses one default writer and submits through one FFI call. Explicit
  /// [isEnabledFor] can skip expensive message construction/encoding when needed.
  /// Logging failures never escape; binding failures are explicit when accessing
  /// [defaultWriter] or calling [attach].
  static void log(XLogLevel level, String tag, String message) {
    try {
      defaultWriter.write(level, tag, message);
    } catch (_) {/* A log statement must not break the calling application. */}
  }
}
