import Foundation

/// Placeholder implementation of the pigeon-generated `XlogConfigApi` for iOS.
///
/// mars/xlog is not yet integrated on iOS (no XCFramework, no Swift wrapper),
/// so every call throws to make the missing integration explicit rather than
/// silently pretending the log was configured.
///
/// Once mars/xlog is integrated, replace the bodies here with real calls.
/// Note: log writing is handled through Dart FFI, not this API.
class XlogConfigApiImpl: XlogConfigApi {

  private static let notImplemented = FlutterError(
    code: "unimplemented",
    message: "xlog is not yet integrated on iOS",
    details: nil
  )

  func initialize(config: XlogConfig) throws {
    throw XlogConfigApiImpl.notImplemented
  }

  func flush(sync: Bool) throws {
    throw XlogConfigApiImpl.notImplemented
  }

  func close() throws {
    throw XlogConfigApiImpl.notImplemented
  }

  func setLevel(level: XlogLevel) throws {
    throw XlogConfigApiImpl.notImplemented
  }

  func getLevel() throws -> XlogLevel {
    throw XlogConfigApiImpl.notImplemented
  }

  func setConsoleLogEnabled(enabled: Bool) throws {
    throw XlogConfigApiImpl.notImplemented
  }

  func setAppenderMode(mode: XlogMode) throws {
    throw XlogConfigApiImpl.notImplemented
  }

  func setMaxFileSize(maxBytes: Int64) throws {
    throw XlogConfigApiImpl.notImplemented
  }

  func setMaxAliveSeconds(seconds: Int64) throws {
    throw XlogConfigApiImpl.notImplemented
  }

  func instancePrefixes() throws -> [String] {
    throw XlogConfigApiImpl.notImplemented
  }

  func hasInstance(prefix: String) throws -> Bool {
    throw XlogConfigApiImpl.notImplemented
  }

  func flushInstance(prefix: String, sync: Bool) throws {
    throw XlogConfigApiImpl.notImplemented
  }

  func getInstanceLevel(prefix: String) throws -> XlogLevel {
    throw XlogConfigApiImpl.notImplemented
  }

  func setInstanceConsoleLogEnabled(prefix: String, enabled: Bool) throws {
    throw XlogConfigApiImpl.notImplemented
  }

  func closeInstance(prefix: String) throws {
    throw XlogConfigApiImpl.notImplemented
  }

  func getInstanceLogFiles(prefix: String, timespanDays: Int64) throws -> [String] {
    throw XlogConfigApiImpl.notImplemented
  }
}
