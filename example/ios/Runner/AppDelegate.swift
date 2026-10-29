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
    configuration.cacheDirectory = cacheDirectory.appendingPathComponent("xlog-example").path
    configuration.level = .info
    configuration.mode = .async
    configuration.consoleLogEnabled = false
    configuration.maxFileSizeBytes = 8 * 1024 * 1024
    configuration.maxAliveTimeSeconds = 7 * 24 * 60 * 60
    XLog.initialize(configuration: configuration)
    XLog.info("AppDelegate", message: "XLog initialized at \(logDirectory.path)")

    let otherConfiguration = XLogConfiguration(
      // Each appender needs its own log/cache directories, even when their
      // prefixes differ. Directory-wide cleanup must not touch another owner.
      logDirectory: logDirectory.deletingLastPathComponent().appendingPathComponent("xlog-other").path,
      namePrefix: "xlog_other"
    )
    otherConfiguration.cacheDirectory = cacheDirectory.appendingPathComponent("xlog-other").path
    otherConfiguration.level = .info
    otherConfiguration.mode = .async
    otherConfiguration.consoleLogEnabled = false
    otherConfiguration.maxFileSizeBytes = 8 * 1024 * 1024
    otherConfiguration.maxAliveTimeSeconds = 7 * 24 * 60 * 60
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
