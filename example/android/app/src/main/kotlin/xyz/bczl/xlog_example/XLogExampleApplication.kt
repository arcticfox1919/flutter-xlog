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
            cacheDir = cacheDir.absolutePath,
            logDir   = logDir,
            prefix   = "xlog_example",
            level    = LogLevel.DEBUG,
        )

        XLog.setConsoleLogEnabled(true)
        otherLog = XLog.openInstance(
            cacheDir = cacheDir.absolutePath,
            logDir = logDir,
            prefix = "xlog_other",
            pubKey = "",
            level = LogLevel.DEBUG,
        )
        otherLog.setConsoleLogEnabled(true)
        otherLog.i("NativeOther", "Independent instance initialized")

        XLog.i("XLogExampleApplication", "XLog initialized, logDir=$logDir")
    }

    // Keep appenders open for the process lifetime. Flush before collecting
    // files for upload, from a worker thread when using flushSync().
}
