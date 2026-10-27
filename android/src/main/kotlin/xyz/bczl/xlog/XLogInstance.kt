package xyz.bczl.xlog

import com.tencent.mars.xlog.Log

private typealias MessageWriter = (String, String, Array<out Any?>?) -> Unit

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
    // Typed method references pass the array directly to Java. A direct vararg
    // call with `null as Array<Any?>?` instead creates Object[]{null}, which
    // still invokes String.format and can break messages containing '%'.
    // Cache the references so plain writes allocate neither a reference nor
    // a vararg array. Formatted writes can also forward their array unchanged.
    // -------------------------------------------------------------------------

    private val writeVerbose: MessageWriter = inner::v
    private val writeDebug: MessageWriter = inner::d
    private val writeInfo: MessageWriter = inner::i
    private val writeWarning: MessageWriter = inner::w
    private val writeError: MessageWriter = inner::e
    private val writeFatal: MessageWriter = inner::f
    private val writeStackTrace:
        (String, Throwable, String, Array<out Any?>?) -> Unit = inner::printErrStackTrace

    fun v(tag: String, msg: String) = writeVerbose(tag, msg, null)
    fun d(tag: String, msg: String) = writeDebug(tag, msg, null)
    fun i(tag: String, msg: String) = writeInfo(tag, msg, null)
    fun w(tag: String, msg: String) = writeWarning(tag, msg, null)
    fun e(tag: String, msg: String) = writeError(tag, msg, null)
    fun f(tag: String, msg: String) = writeFatal(tag, msg, null)

    // -------------------------------------------------------------------------
    // Formatted messages
    // -------------------------------------------------------------------------

    fun v(tag: String, format: String, vararg args: Any?) = writeVerbose(tag, format, args)
    fun d(tag: String, format: String, vararg args: Any?) = writeDebug(tag, format, args)
    fun i(tag: String, format: String, vararg args: Any?) = writeInfo(tag, format, args)
    fun w(tag: String, format: String, vararg args: Any?) = writeWarning(tag, format, args)
    fun e(tag: String, format: String, vararg args: Any?) = writeError(tag, format, args)
    fun f(tag: String, format: String, vararg args: Any?) = writeFatal(tag, format, args)

    // -------------------------------------------------------------------------
    // Exception stack traces
    // -------------------------------------------------------------------------

    fun e(tag: String, tr: Throwable, msg: String = "") =
        writeStackTrace(tag, tr, msg, null)

    fun e(tag: String, tr: Throwable, format: String, vararg args: Any?) =
        writeStackTrace(tag, tr, format, args)

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
