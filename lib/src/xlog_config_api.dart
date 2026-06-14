import 'generated/xlog_config.g.dart' as pigeon;
import 'xlogger.dart' show XLogLevel;

/// Appender write mode.
enum XLogMode {
  /// Asynchronous write (default, best performance).
  async,

  /// Synchronous write.
  sync,
}

/// Compression algorithm used for log content.
enum XLogCompressMode {
  /// zlib compression (default).
  zlib,

  /// zstd compression.
  zstd,
}

/// Manages the xlog appender from Dart: opens/closes it and controls runtime
/// settings (level, flush, console mirroring) through the platform channel.
///
/// Use this in a pure-Flutter app to initialize and control the log appender.
/// In a hybrid-stack app where native code already calls the platform
/// XLog.init, you can skip this entirely.
///
/// Writing log entries is NOT handled here; use [XLogger] (Dart FFI).
class XLogManager {
  XLogManager._();

  static final pigeon.XlogConfigApi _api = pigeon.XlogConfigApi();

  /// Opens the global log appender.
  ///
  /// - [cacheDir]: memory-mapped cache directory (e.g. application cache dir).
  /// - [logDir]: directory the log files are written to.
  /// - [namePrefix]: log file name prefix.
  /// - [level]: minimum level to emit.
  /// - [mode]: appender write mode.
  /// - [pubKey]: encryption public key; empty string disables encryption.
  /// - [compressMode]: compression algorithm (zlib / zstd).
  /// - [compressLevel]: compression level 0-9 (0 = none, 6 = native default).
  /// - [cacheDays]: days to keep cached (mmap) logs; 0 uses the native default.
  /// - [consoleLogEnabled]: also mirror logs to the system console
  ///   (logcat / Xcode).
  static Future<void> initialize({
    required String cacheDir,
    required String logDir,
    required String namePrefix,
    XLogLevel level = XLogLevel.debug,
    XLogMode mode = XLogMode.async,
    String pubKey = '',
    XLogCompressMode compressMode = XLogCompressMode.zlib,
    int compressLevel = 6,
    int cacheDays = 0,
    bool consoleLogEnabled = true,
  }) {
    return _api.initialize(
      pigeon.XlogConfig(
        cacheDir: cacheDir,
        logDir: logDir,
        namePrefix: namePrefix,
        level: _toPigeonLevel(level),
        mode: mode == XLogMode.sync
            ? pigeon.XlogMode.sync
            : pigeon.XlogMode.async,
        pubKey: pubKey,
        compressMode: compressMode == XLogCompressMode.zstd
            ? pigeon.XlogCompressMode.zstd
            : pigeon.XlogCompressMode.zlib,
        compressLevel: compressLevel,
        cacheDays: cacheDays,
        consoleLogEnabled: consoleLogEnabled,
      ),
    );
  }

  /// Flushes buffered logs to disk. When [sync] is true, blocks natively until
  /// the write completes (avoid calling from a latency-sensitive path).
  static Future<void> flush({bool sync = false}) => _api.flush(sync);

  /// Closes the appender and releases resources.
  static Future<void> close() => _api.close();

  /// Changes the global minimum log level at runtime.
  static Future<void> setLevel(XLogLevel level) =>
      _api.setLevel(_toPigeonLevel(level));

  /// Returns the current global minimum log level.
  static Future<XLogLevel> getLevel() async =>
      _fromPigeonLevel(await _api.getLevel());

  /// Enables or disables mirroring logs to the system console.
  static Future<void> setConsoleLogEnabled(bool enabled) =>
      _api.setConsoleLogEnabled(enabled);

  /// Switches the appender write mode at runtime. Must be called after
  /// [initialize].
  static Future<void> setAppenderMode(XLogMode mode) => _api.setAppenderMode(
        mode == XLogMode.sync ? pigeon.XlogMode.sync : pigeon.XlogMode.async,
      );

  /// Sets the maximum size in bytes of a single log file; the appender rolls
  /// to a new file once exceeded. Must be called after [initialize].
  static Future<void> setMaxFileSize(int maxBytes) =>
      _api.setMaxFileSize(maxBytes);

  /// Sets the maximum retention time in seconds for log files; older files are
  /// deleted automatically. Must be called after [initialize].
  static Future<void> setMaxAliveSeconds(int seconds) =>
      _api.setMaxAliveSeconds(seconds);

  static pigeon.XlogLevel _toPigeonLevel(XLogLevel level) {
    return switch (level) {
      XLogLevel.verbose => pigeon.XlogLevel.verbose,
      XLogLevel.debug => pigeon.XlogLevel.debug,
      XLogLevel.info => pigeon.XlogLevel.info,
      XLogLevel.warn => pigeon.XlogLevel.warning,
      XLogLevel.error => pigeon.XlogLevel.error,
      XLogLevel.fatal => pigeon.XlogLevel.fatal,
      XLogLevel.none => pigeon.XlogLevel.none,
    };
  }

  static XLogLevel _fromPigeonLevel(pigeon.XlogLevel level) {
    return switch (level) {
      pigeon.XlogLevel.verbose => XLogLevel.verbose,
      pigeon.XlogLevel.debug => XLogLevel.debug,
      pigeon.XlogLevel.info => XLogLevel.info,
      pigeon.XlogLevel.warning => XLogLevel.warn,
      pigeon.XlogLevel.error => XLogLevel.error,
      pigeon.XlogLevel.fatal => XLogLevel.fatal,
      pigeon.XlogLevel.none => XLogLevel.none,
    };
  }

  // ---------------------------------------------------------------------------
  // Multi-instance management.
  //
  // Log instances are CREATED on the native side (Kotlin/Swift), which knows
  // the directories, encryption and compression to use. Dart only takes over
  // already-open instances to manage them: flush, query level, toggle console
  // output, list log files for upload, and close. Writing to an instance is
  // not supported from Dart.
  // ---------------------------------------------------------------------------

  /// Takes over an already-open native log instance by its [prefix], returning
  /// a handle to manage it, or null if no such instance is open.
  static Future<XLogInstanceHandle?> getInstance(String prefix) async {
    if (!await _api.hasInstance(prefix)) return null;
    return XLogInstanceHandle._(prefix);
  }

  /// Returns handles for all currently open native log instances.
  static Future<List<XLogInstanceHandle>> instances() async {
    final prefixes = await _api.instancePrefixes();
    return prefixes.map(XLogInstanceHandle._).toList();
  }
}

/// A handle to a single native-created log instance, addressed by its name
/// [prefix]. Use it to manage the instance from Dart (flush, query level,
/// toggle console output, list files for upload, close).
///
/// Obtain one via [XLogManager.getInstance] or [XLogManager.instances]. This
/// handle does not write log entries; logging stays on the native side.
class XLogInstanceHandle {
  XLogInstanceHandle._(this.prefix);

  /// The name prefix identifying this instance.
  final String prefix;

  static pigeon.XlogConfigApi get _api => XLogManager._api;

  /// Flushes this instance's buffered logs to disk. When [sync] is true, blocks
  /// until the write completes (do not call on the UI thread).
  Future<void> flush({bool sync = false}) => _api.flushInstance(prefix, sync);

  /// Returns this instance's current minimum log level.
  Future<XLogLevel> getLevel() async =>
      XLogManager._fromPigeonLevel(await _api.getInstanceLevel(prefix));

  /// Enables or disables mirroring this instance's logs to the system console.
  Future<void> setConsoleLogEnabled(bool enabled) =>
      _api.setInstanceConsoleLogEnabled(prefix, enabled);

  /// Returns this instance's log file paths over the last [timespanDays] days
  /// counting back from today (0 = today only). Useful for uploading logs.
  Future<List<String>> getLogFiles({int timespanDays = 0}) =>
      _api.getInstanceLogFiles(prefix, timespanDays);

  /// Closes this instance and releases its resources. The handle should not be
  /// used afterwards.
  Future<void> close() => _api.closeInstance(prefix);
}
