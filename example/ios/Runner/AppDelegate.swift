import Flutter
import UIKit
import xlog

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var otherLog: XLogInstance?
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

    let otherConfiguration = XLogConfiguration(
      logDirectory: logDirectory.path,
      namePrefix: "xlog_other"
    )
    otherConfiguration.cacheDirectory = cacheDirectory.path
    otherConfiguration.level = .debug
    otherConfiguration.consoleLogEnabled = true
    guard let other = XLog.openInstance(configuration: otherConfiguration) else {
      fatalError("Cannot initialize xlog_other")
    }
    otherLog = other
    other.info("NativeOther", message: "Independent instance initialized")

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Keep the native appender open for the process lifetime. Collecting logs
  // for upload can explicitly flush on a worker queue; termination needs no close.

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
