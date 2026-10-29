import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/generated/xlog_config.g.dart',
    kotlinOut: 'android/src/main/kotlin/xyz/bczl/xlog/XlogConfigApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'xyz.bczl.xlog'),
    swiftOut: 'ios/Classes/XlogConfigApi.g.swift',
    dartPackageName: 'xlog',
  ),
)

/// Log severity level. Mirrors the native mars/xlog `TLogLevel`.
enum XlogLevel {
  verbose,
  debug,
  info,
  warning,
  error,
  fatal,
  none,
}

/// Appender write mode.
enum XlogMode {
  /// Asynchronous write (default, best performance).
  async,

  /// Synchronous write.
  sync,
}

/// Compression algorithm used for log content.
enum XlogCompressMode {
  /// zlib compression (default).
  zlib,

  /// zstd compression.
  zstd,
}

/// Configuration used to open the global xlog appender.
///
/// Only the initialization/configuration surface is exposed through pigeon.
/// Writing log entries is handled separately through Dart FFI.
class XlogConfig {
  XlogConfig({
    required this.cacheDir,
    required this.logDir,
    required this.namePrefix,
    this.level = XlogLevel.debug,
    this.mode = XlogMode.async,
    this.pubKey = '',
    this.compressMode = XlogCompressMode.zlib,
    this.compressLevel = 6,
    this.cacheDays = 0,
    this.consoleLogEnabled = true,
    this.maxFileSizeBytes = 0,
    this.maxAliveTimeSeconds = 10 * 24 * 60 * 60,
  });

  /// Memory-mapped cache directory (e.g. context.cacheDir on Android).
  String cacheDir;

  /// Directory the log files are written to.
  String logDir;

  /// Log file name prefix.
  String namePrefix;

  /// Minimum level to emit.
  XlogLevel level;

  /// Appender write mode.
  XlogMode mode;

  /// Encryption public key. Empty string disables encryption.
  String pubKey;

  /// Compression algorithm for log content.
  XlogCompressMode compressMode;

  /// Compression level passed to the native backend; this config defaults to 6.
  /// zstd uses this value (0 selects its algorithm default, 3). The current
  /// zlib backend ignores it and always uses level 9; 0 does not disable it.
  int compressLevel;

  /// Number of days to keep cached (mmap) logs. 0 uses the native default.
  int cacheDays;

  /// Whether logs are also mirrored to the system console (logcat / Xcode).
  bool consoleLogEnabled;

  /// Creation-only file splitting threshold in bytes; 0 disables size splitting.
  int maxFileSizeBytes;

  /// Creation-only expiry threshold in seconds; minimum one day, default ten.
  int maxAliveTimeSeconds;
}

/// Initialization and configuration API for xlog.
///
/// Implemented natively (Kotlin / Swift) and called from Dart. This lets a
/// pure-Flutter app initialize xlog from Dart, while a hybrid app may instead
/// initialize natively and skip these calls entirely.
///
/// Log writing is NOT part of this API; it goes through Dart FFI.
@HostApi()
abstract class XlogConfigApi {
  /// Opens the global log appender with [config].
  void initialize(XlogConfig config);

  /// Flushes buffered logs to disk. When [sync] is true, blocks until the
  /// write completes (do not call on the UI thread).
  void flush(bool sync);

  /// Closes the appender and releases resources.
  void close();

  /// Changes the global minimum log level at runtime.
  void setLevel(XlogLevel level);

  /// Returns the current global minimum log level.
  XlogLevel getLevel();

  /// Enables or disables mirroring logs to the system console.
  void setConsoleLogEnabled(bool enabled);

  /// Switches the appender write mode at runtime. Must be called after
  /// [initialize].
  void setAppenderMode(XlogMode mode);

  // ---------------------------------------------------------------------------
  // Multi-instance management.
  //
  // Instances are CREATED on the native side; Dart only manages already-open
  // ones, addressed by their name prefix. Writing to an instance is not part
  // of this API.
  // ---------------------------------------------------------------------------

  /// Returns the prefixes of all currently open log instances.
  List<String> instancePrefixes();

  /// Whether a log instance with [prefix] is currently open.
  bool hasInstance(String prefix);

  /// Flushes the instance's buffered logs. When [sync] is true, blocks until
  /// the write completes (do not call on the UI thread).
  void flushInstance(String prefix, bool sync);

  /// Returns the instance's current minimum log level.
  XlogLevel getInstanceLevel(String prefix);

  /// Enables or disables mirroring the instance's logs to the system console.
  void setInstanceConsoleLogEnabled(String prefix, bool enabled);

  /// Closes the instance and releases its resources.
  void closeInstance(String prefix);

  /// Returns the instance's log file paths over the last [timespanDays] days
  /// counting back from today (0 = today only). Useful for uploading logs.
  List<String> getInstanceLogFiles(String prefix, int timespanDays);
}
