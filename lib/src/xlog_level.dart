import 'generated/xlog_bindings.dart';

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
