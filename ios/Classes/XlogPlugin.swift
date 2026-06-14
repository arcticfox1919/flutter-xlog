import Flutter
import UIKit

public class XlogPlugin: NSObject, FlutterPlugin {
  /// Retained so the API stays alive for the lifetime of the plugin.
  private var configApi: XlogConfigApiImpl?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = XlogPlugin()
    let api = XlogConfigApiImpl()
    instance.configApi = api
    XlogConfigApiSetup.setUp(binaryMessenger: registrar.messenger(), api: api)
  }
}
