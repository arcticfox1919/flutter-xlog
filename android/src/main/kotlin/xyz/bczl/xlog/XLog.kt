package xyz.bczl.xlog

import android.content.Context
import com.tencent.mars.xlog.Log
import com.tencent.mars.xlog.Xlog

/**
 * Secondary wrapper over mars/xlog, hiding the implementation details from the app.
 *
 * Typical usage:
 * ```kotlin
 * // Application.onCreate()
 * XLog.init(
 *     cacheDir = cacheDir.absolutePath,
 *     logDir   = getExternalFilesDir(null)!!.absolutePath + "/log",
 *     prefix   = "app"
 * )
 *
 * // Write logs
 * XLog.i("MainActivity", "Hello XLog")
 * XLog.i("MainActivity", "User %s logged in at %d", name, time)
 *
 * // Before collecting logs for upload (call on a worker thread)
 * XLog.flushSync()
 * // Keep the appender open for the process lifetime.
 * ```
 */
object XLog {

    /** Asynchronous write (default, best performance). */
    const val MODE_ASYNC = Xlog.AppednerModeAsync

    /** Synchronous write. */
    const val MODE_SYNC = Xlog.AppednerModeSync

    /** zlib compression (default). */
    const val COMPRESS_ZLIB = Xlog.ZLIB_MODE

    /** zstd compression. */
    const val COMPRESS_ZSTD = Xlog.ZSTD_MODE

    /** Holds the backend for runtime appender-mode changes. */
    private var xlogImpl: Xlog? = null

    // -------------------------------------------------------------------------
    // Lifecycle
    // -------------------------------------------------------------------------

    /**
     * Initializes the global default log instance.
     *
     * @param cacheDir      Memory-mapped cache directory (prefer context.cacheDir.absolutePath)
     * @param logDir        Log file directory
     * @param prefix        Log file name prefix
     * @param level         Minimum output level, defaults to [LogLevel.DEBUG]
     * @param mode          Write mode, defaults to [MODE_ASYNC]
     * @param pubKey        Encryption public key, pass an empty string to disable encryption
     * @param compressMode  Compression algorithm, [COMPRESS_ZLIB] or [COMPRESS_ZSTD]
     * @param compressLevel Compression level passed to the native backend. For zstd,
     *                      0 selects the algorithm default (3); positive levels such
     *                      as 1-9 trade speed for compression, and native zstd also
     *                      supports negative levels. This Kotlin API defaults to 0.
     *                      The current zlib backend ignores this parameter and uses
     *                      fixed level 9 (Z_BEST_COMPRESSION); 0 does not disable it.
     * @param cacheDays     Days to keep cached (mmap) logs, 0 uses the native default
     * @param loadLib       Whether this method loads the .so (pass false if the app already loaded it)
     * @param maxFileSizeBytes Creation-only soft splitting threshold; 0 disables it
     * @param maxAliveTimeSeconds Creation-only expiry threshold; minimum one day
     * Each instance must have dedicated log/cache directories; cleanup is directory-wide.
     */
    @JvmOverloads
    fun init(
        cacheDir: String,
        logDir: String,
        prefix: String,
        level: LogLevel = LogLevel.DEBUG,
        mode: Int = MODE_ASYNC,
        pubKey: String = "",
        compressMode: Int = COMPRESS_ZLIB,
        compressLevel: Int = 0,
        cacheDays: Int = 0,
        loadLib: Boolean = true,
        maxFileSizeBytes: Long = 0,
        maxAliveTimeSeconds: Long = 10L * 24 * 60 * 60
    ) {
        val config = Xlog.XLogConfig().apply {
            this.level = level.value
            this.mode = mode
            cachedir = cacheDir
            logdir = logDir
            nameprefix = prefix
            pubkey = pubKey
            compressmode = compressMode
            compresslevel = compressLevel
            cachedays = cacheDays
            this.maxFileSizeBytes = maxFileSizeBytes
            this.maxAliveTimeSeconds = maxAliveTimeSeconds
        }
        val xlog = Xlog()
        Xlog.open(loadLib, config)
        xlogImpl = xlog
        Log.setLogImp(xlog)
    }

    /**
     * Explicitly closes the global appender and releases resources.
     * Stop/dispose all native and Dart writers first. Process-lifetime apps
     * normally keep it open; no Application.onTerminate() hook is required.
     */
    fun close() {
        Log.appenderClose()
        xlogImpl = null
    }

    /**
     * Asynchronously flushes buffered logs (across all open instances) to disk.
     * Returns immediately without blocking the current thread.
     */
    fun flush() {
        Log.appenderFlush()
    }

    /**
     * Synchronously flushes buffered logs to disk, **blocking the current thread**
     * until the write completes. Do not call on the main thread; use a worker
     * thread or coroutine (IO dispatcher).
     */
    fun flushSync() {
        Log.appenderFlushSync(true)
    }

    /**
     * Changes the global log output level at runtime.
     *
     * @param level The new log level
     */
    fun setLevel(level: LogLevel) {
        Log.setLevel(level.value, true)
    }

    /**
     * Returns the currently effective log level.
     */
    fun getLevel(): LogLevel = LogLevel.fromValue(Log.getLogLevel())

    /**
     * Sets whether logs are also written to logcat.
     */
    fun setConsoleLogEnabled(enabled: Boolean) {
        Log.setConsoleLogOpen(enabled)
    }

    /**
     * Sets the Context used to pop a Toast on Fatal-level logs (debug builds only).
     * Pass null to clear it.
     */
    fun setToastContext(context: Context?) {
        Log.toastSupportContext = context
    }

    /**
     * Switches the write mode at runtime ([MODE_ASYNC] / [MODE_SYNC]).
     * Must be called after [init].
     */
    fun setAppenderMode(mode: Int) {
        xlogImpl?.setAppenderMode(0L, mode)
    }

    // -------------------------------------------------------------------------
    // Log output (global instance) — plain messages
    // -------------------------------------------------------------------------

    @JvmStatic fun v(tag: String, msg: String) = Log.v(tag, msg)
    @JvmStatic fun d(tag: String, msg: String) = Log.d(tag, msg)
    @JvmStatic fun i(tag: String, msg: String) = Log.i(tag, msg)
    @JvmStatic fun w(tag: String, msg: String) = Log.w(tag, msg)
    @JvmStatic fun e(tag: String, msg: String) = Log.e(tag, msg)
    @JvmStatic fun f(tag: String, msg: String) = Log.f(tag, msg)

    // -------------------------------------------------------------------------
    // Log output (global instance) — formatted messages
    // -------------------------------------------------------------------------

    @JvmStatic fun v(tag: String, format: String, vararg args: Any?) = Log.v(tag, format, *args)
    @JvmStatic fun d(tag: String, format: String, vararg args: Any?) = Log.d(tag, format, *args)
    @JvmStatic fun i(tag: String, format: String, vararg args: Any?) = Log.i(tag, format, *args)
    @JvmStatic fun w(tag: String, format: String, vararg args: Any?) = Log.w(tag, format, *args)
    @JvmStatic fun e(tag: String, format: String, vararg args: Any?) = Log.e(tag, format, *args)
    @JvmStatic fun f(tag: String, format: String, vararg args: Any?) = Log.f(tag, format, *args)

    // -------------------------------------------------------------------------
    // Log output (global instance) — exception stack traces
    // -------------------------------------------------------------------------

    // Pass a nullable array through a cached reference so plain messages bypass
    // String.format and formatted messages do not need a spread-array copy.
    private val writeStackTrace:
        (String, Throwable, String, Array<out Any?>?) -> Unit = Log::printErrStackTrace

    @JvmStatic
    fun e(tag: String, tr: Throwable, msg: String = "") =
        writeStackTrace(tag, tr, msg, null)

    @JvmStatic
    fun e(tag: String, tr: Throwable, format: String, vararg args: Any?) =
        writeStackTrace(tag, tr, format, args)

    // -------------------------------------------------------------------------
    // Multi-instance support
    // -------------------------------------------------------------------------

    /**
     * Opens an independent log instance that coexists with the main instance and
     * writes to a different file.
     *
     * @return [XLogInstance] handle used for subsequent writes and closing
     */
    @JvmOverloads
    fun openInstance(
        cacheDir: String,
        logDir: String,
        prefix: String,
        level: LogLevel = LogLevel.DEBUG,
        mode: Int = MODE_ASYNC,
        cacheDays: Int = 0,
        maxFileSizeBytes: Long = 0,
        maxAliveTimeSeconds: Long = 10L * 24 * 60 * 60
    ): XLogInstance = openInstance(
        cacheDir = cacheDir, logDir = logDir, prefix = prefix, pubKey = "",
        level = level, mode = mode, cacheDays = cacheDays,
        maxFileSizeBytes = maxFileSizeBytes, maxAliveTimeSeconds = maxAliveTimeSeconds
    )

    /**
     * Creates an instance with its own encryption and compression settings.
     *
     * [pubKey] is the 128-hex-character secp256k1 public key generated by xlog's
     * key tool; empty means unencrypted. [compressLevel] has the same semantics
     * as in [init]: zstd 0 selects its default (3), while zlib always uses level 9.
     * Uses the native XLogConfig creation overload. An existing prefix reuses
     * its native instance without applying any new configuration.
     * Unsupported backends, invalid configuration and failed creation throw.
     * Keep it open while Dart writers are bound to it.
     *
     * The original overload remains available with its original defaults.
     */
    @JvmOverloads
    fun openInstance(
        cacheDir: String,
        logDir: String,
        prefix: String,
        pubKey: String,
        level: LogLevel = LogLevel.DEBUG,
        mode: Int = MODE_ASYNC,
        compressMode: Int = COMPRESS_ZLIB,
        compressLevel: Int = 0,
        cacheDays: Int = 0,
        maxFileSizeBytes: Long = 0,
        maxAliveTimeSeconds: Long = 10L * 24 * 60 * 60
    ): XLogInstance {
        val config = Xlog.XLogConfig().apply {
            this.level = level.value
            this.mode = mode
            cachedir = cacheDir
            logdir = logDir
            nameprefix = prefix
            pubkey = pubKey
            compressmode = compressMode
            compresslevel = compressLevel
            cachedays = cacheDays
            this.maxFileSizeBytes = maxFileSizeBytes
            this.maxAliveTimeSeconds = maxAliveTimeSeconds
        }
        val inner = Log.openLogInstance(config)
        return XLogInstance(prefix, inner)
    }

    /**
     * Returns an already-opened log instance by prefix, or null if none exists.
     */
    fun getLogInstance(prefix: String): XLogInstance? {
        val inner = Log.getLogInstance(prefix) ?: return null
        return XLogInstance(prefix, inner)
    }

    /**
     * Returns the prefixes of all currently open log instances.
     */
    fun instancePrefixes(): List<String> = Log.getLogInstancePrefixes().toList()

    /**
     * Closes the log instance with the given prefix and releases its resources.
     */
    fun closeInstance(prefix: String) {
        Log.closeLogInstance(prefix)
    }
}
