package xyz.bczl.xlog

import com.tencent.mars.xlog.Log
import xyz.bczl.xlog.LogLevel
import xyz.bczl.xlog.XLog

/**
 * An independent log instance, mapping to mars xlog's multi-instance write
 * capability. Created via [XLog.openInstance] and released via
 * [XLog.closeInstance] or [close].
 */
class XLogInstance internal constructor(
    val prefix: String,
    private val inner: Log.LogInstance
) {

    // -------------------------------------------------------------------------
    // Plain messages
    //
    // Pass an explicit null vararg so the Java side takes the `obj == null`
    // branch and logs the message verbatim. Calling inner.v(tag, msg) would
    // pass an empty Object[] (not null), forcing String.format(msg) and
    // breaking any message that contains a '%'.
    // -------------------------------------------------------------------------

    fun v(tag: String, msg: String) = inner.v(tag, msg, null as Array<Any?>?)
    fun d(tag: String, msg: String) = inner.d(tag, msg, null as Array<Any?>?)
    fun i(tag: String, msg: String) = inner.i(tag, msg, null as Array<Any?>?)
    fun w(tag: String, msg: String) = inner.w(tag, msg, null as Array<Any?>?)
    fun e(tag: String, msg: String) = inner.e(tag, msg, null as Array<Any?>?)
    fun f(tag: String, msg: String) = inner.f(tag, msg, null as Array<Any?>?)

    // -------------------------------------------------------------------------
    // Formatted messages
    // -------------------------------------------------------------------------

    fun v(tag: String, format: String, vararg args: Any?) = inner.v(tag, format, *args)
    fun d(tag: String, format: String, vararg args: Any?) = inner.d(tag, format, *args)
    fun i(tag: String, format: String, vararg args: Any?) = inner.i(tag, format, *args)
    fun w(tag: String, format: String, vararg args: Any?) = inner.w(tag, format, *args)
    fun e(tag: String, format: String, vararg args: Any?) = inner.e(tag, format, *args)
    fun f(tag: String, format: String, vararg args: Any?) = inner.f(tag, format, *args)

    // -------------------------------------------------------------------------
    // Exception stack traces
    // -------------------------------------------------------------------------

    fun e(tag: String, tr: Throwable, msg: String = "") =
        inner.printErrStackTrace(tag, tr, msg)

    fun e(tag: String, tr: Throwable, format: String, vararg args: Any?) =
        inner.printErrStackTrace(tag, tr, format, *args)

    // -------------------------------------------------------------------------
    // Flush / level / console
    // -------------------------------------------------------------------------

    fun flush()    = inner.appenderFlush()
    fun flushSync() = inner.appenderFlushSync()

    fun getLevel(): LogLevel = LogLevel.fromValue(inner.logLevel)

    fun setConsoleLogEnabled(enabled: Boolean) = inner.setConsoleLogOpen(enabled)

    // -------------------------------------------------------------------------
    // File query (for upload)
    // -------------------------------------------------------------------------

    /**
     * Returns this instance's log file paths over the last [timeSpanDays] days
     * counting back from today (0 = today only). Useful for uploading logs.
     */
    fun getLogFiles(timeSpanDays: Int): List<String> =
        inner.getFilesFromTimeSpan(timeSpanDays).toList()

    // -------------------------------------------------------------------------
    // Lifecycle
    // -------------------------------------------------------------------------

    /** Closes and releases this instance. */
    fun close() = XLog.closeInstance(prefix)
}
