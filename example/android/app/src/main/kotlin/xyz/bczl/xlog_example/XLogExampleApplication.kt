package xyz.bczl.xlog_example

import android.app.Application
import xyz.bczl.xlog.LogLevel
import xyz.bczl.xlog.XLog

class XLogExampleApplication : Application() {

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

        XLog.i("XLogExampleApplication", "XLog initialized, logDir=$logDir")
    }

    override fun onTerminate() {
        super.onTerminate()
        XLog.flushSync()
        XLog.close()
    }
}
