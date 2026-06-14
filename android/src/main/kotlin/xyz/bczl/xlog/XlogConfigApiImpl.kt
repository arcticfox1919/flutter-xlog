package xyz.bczl.xlog

/**
 * Native implementation of the pigeon-generated [XlogConfigApi].
 *
 * Bridges the Dart-side configuration calls to the [XLog] wrapper. This exists
 * so a pure-Flutter app can initialize xlog from Dart; a hybrid app may instead
 * call [XLog.init] directly from native code and never touch this API.
 *
 * Only configuration is handled here. Writing log entries goes through Dart FFI.
 */
class XlogConfigApiImpl : XlogConfigApi {

    override fun initialize(config: XlogConfig) {
        XLog.init(
            cacheDir = config.cacheDir,
            logDir = config.logDir,
            prefix = config.namePrefix,
            level = config.level.toLogLevel(),
            mode = config.mode.toAppenderMode(),
            pubKey = config.pubKey,
            compressMode = config.compressMode.toCompressMode(),
            compressLevel = config.compressLevel.toInt(),
            cacheDays = config.cacheDays.toInt(),
        )
        XLog.setConsoleLogEnabled(config.consoleLogEnabled)
    }

    override fun flush(sync: Boolean) {
        if (sync) XLog.flushSync() else XLog.flush()
    }

    override fun close() {
        XLog.close()
    }

    override fun setLevel(level: XlogLevel) {
        XLog.setLevel(level.toLogLevel())
    }

    override fun getLevel(): XlogLevel = XLog.getLevel().toXlogLevel()

    override fun setConsoleLogEnabled(enabled: Boolean) {
        XLog.setConsoleLogEnabled(enabled)
    }

    override fun setAppenderMode(mode: XlogMode) {
        XLog.setAppenderMode(mode.toAppenderMode())
    }

    override fun setMaxFileSize(maxBytes: Long) {
        XLog.setMaxFileSize(maxBytes)
    }

    override fun setMaxAliveSeconds(seconds: Long) {
        XLog.setMaxAliveTime(seconds)
    }

    // -------------------------------------------------------------------------
    // Multi-instance management (instances are created natively).
    // -------------------------------------------------------------------------

    override fun instancePrefixes(): List<String> = XLog.instancePrefixes()

    override fun hasInstance(prefix: String): Boolean =
        XLog.getLogInstance(prefix) != null

    override fun flushInstance(prefix: String, sync: Boolean) {
        val instance = XLog.getLogInstance(prefix) ?: return
        if (sync) instance.flushSync() else instance.flush()
    }

    override fun getInstanceLevel(prefix: String): XlogLevel =
        (XLog.getLogInstance(prefix)?.getLevel() ?: LogLevel.NONE).toXlogLevel()

    override fun setInstanceConsoleLogEnabled(prefix: String, enabled: Boolean) {
        XLog.getLogInstance(prefix)?.setConsoleLogEnabled(enabled)
    }

    override fun closeInstance(prefix: String) {
        XLog.closeInstance(prefix)
    }

    override fun getInstanceLogFiles(prefix: String, timespanDays: Long): List<String> =
        XLog.getLogInstance(prefix)?.getLogFiles(timespanDays.toInt()) ?: emptyList()
}

private fun XlogLevel.toLogLevel(): LogLevel = when (this) {
    XlogLevel.VERBOSE -> LogLevel.VERBOSE
    XlogLevel.DEBUG -> LogLevel.DEBUG
    XlogLevel.INFO -> LogLevel.INFO
    XlogLevel.WARNING -> LogLevel.WARNING
    XlogLevel.ERROR -> LogLevel.ERROR
    XlogLevel.FATAL -> LogLevel.FATAL
    XlogLevel.NONE -> LogLevel.NONE
}

private fun LogLevel.toXlogLevel(): XlogLevel = when (this) {
    LogLevel.VERBOSE -> XlogLevel.VERBOSE
    LogLevel.DEBUG -> XlogLevel.DEBUG
    LogLevel.INFO -> XlogLevel.INFO
    LogLevel.WARNING -> XlogLevel.WARNING
    LogLevel.ERROR -> XlogLevel.ERROR
    LogLevel.FATAL -> XlogLevel.FATAL
    LogLevel.NONE -> XlogLevel.NONE
}

private fun XlogMode.toAppenderMode(): Int = when (this) {
    XlogMode.ASYNC -> XLog.MODE_ASYNC
    XlogMode.SYNC -> XLog.MODE_SYNC
}

private fun XlogCompressMode.toCompressMode(): Int = when (this) {
    XlogCompressMode.ZLIB -> XLog.COMPRESS_ZLIB
    XlogCompressMode.ZSTD -> XLog.COMPRESS_ZSTD
}
