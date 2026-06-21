import Flutter
import UIKit
import xlog

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let fileManager = FileManager.default
    let cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    let logDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("xlog", isDirectory: true)

    let configuration = XLogConfiguration(
      logDirectory: logDirectory.path,
      namePrefix: "xlog_example"
    )
    configuration.cacheDirectory = cacheDirectory.path
    configuration.level = .debug
    configuration.consoleLogEnabled = true
    XLog.initialize(configuration: configuration)
    XLog.info("AppDelegate", message: "XLog initialized at \(logDirectory.path)")

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    XLog.flushSync()
    XLog.close()
    super.applicationWillTerminate(application)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
