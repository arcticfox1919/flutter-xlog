package xyz.bczl.xlog_example

import android.os.Bundle
import xyz.bczl.xlog.XLog
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    private val tag = "MainActivity"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        XLog.i(tag, "onCreate")
    }

    override fun onStart() {
        super.onStart()
        XLog.i(tag, "onStart")
    }

    override fun onResume() {
        super.onResume()
        XLog.i(tag, "onResume")
    }

    override fun onPause() {
        super.onPause()
        XLog.i(tag, "onPause")
        XLog.flush()
    }

    override fun onStop() {
        super.onStop()
        XLog.i(tag, "onStop")
    }

    override fun onDestroy() {
        super.onDestroy()
        XLog.i(tag, "onDestroy")
    }
}
