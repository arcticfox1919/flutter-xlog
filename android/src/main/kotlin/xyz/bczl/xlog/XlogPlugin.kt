package xyz.bczl.xlog

import io.flutter.embedding.engine.plugins.FlutterPlugin

/** XlogPlugin registers the pigeon-generated xlog configuration API. */
class XlogPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        XlogConfigApi.setUp(binding.binaryMessenger, XlogConfigApiImpl())
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        XlogConfigApi.setUp(binding.binaryMessenger, null)
    }
}
