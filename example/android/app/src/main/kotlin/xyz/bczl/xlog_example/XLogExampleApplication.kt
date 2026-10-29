package xyz.bczl.xlog_example

import android.app.Application
import xyz.bczl.xlog.LogLevel
import xyz.bczl.xlog.XLog
import xyz.bczl.xlog.XLogInstance

class XLogExampleApplication : Application() {
    private lateinit var otherLog: XLogInstance

    override fun onCreate() {
        super.onCreate()

        val logDir = filesDir.absolutePath + "/log"

        XLog.init(
            cacheDir = cacheDir.absolutePath + "/xlog-example",
            logDir   = logDir,
            prefix   = "xlog_example",
            level    = LogLevel.INFO,
            mode     = XLog.MODE_ASYNC,
            maxFileSizeBytes = 8L * 1024 * 1024,
            maxAliveTimeSeconds = 7L * 24 * 60 * 60,
        )

        // Console mirroring would dominate the benchmark. Each appender needs
        // its own log/cache directories, including the default appender.
        XLog.setConsoleLogEnabled(false)
        otherLog = XLog.openInstance(
            cacheDir = cacheDir.absolutePath + "/xlog-other",
            logDir = filesDir.absolutePath + "/log-other",
            prefix = "xlog_other",
            pubKey = "",
            level = LogLevel.INFO,
            mode = XLog.MODE_ASYNC,
            maxFileSizeBytes = 8L * 1024 * 1024,
            maxAliveTimeSeconds = 7L * 24 * 60 * 60,
        )
        otherLog.setConsoleLogEnabled(false)
        otherLog.i("NativeOther", "Independent instance initialized")

        XLog.i("XLogExampleApplication", "XLog initialized, logDir=$logDir")
    }

    // Keep appenders open for the process lifetime. Flush before collecting
    // files for upload, from a worker thread when using flushSync().
}
