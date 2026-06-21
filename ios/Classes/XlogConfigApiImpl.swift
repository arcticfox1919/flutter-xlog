import Foundation

/// Bridges Flutter configuration calls to the same facade available to native code.
class XlogConfigApiImpl: XlogConfigApi {
  func initialize(config: XlogConfig) throws {
    let configuration = XLogConfiguration(
      logDirectory: config.logDir,
      namePrefix: config.namePrefix
    )
    configuration.cacheDirectory = config.cacheDir.isEmpty ? nil : config.cacheDir
    configuration.publicKey = config.pubKey.isEmpty ? nil : config.pubKey
    configuration.cacheDays = Int(config.cacheDays)
    configuration.level = config.level.logLevel
    configuration.mode = config.mode.xlogMode
    configuration.compressMode = config.compressMode.xlogCompressMode
    configuration.compressLevel = Int(config.compressLevel)
    configuration.consoleLogEnabled = config.consoleLogEnabled

    guard XLog.initialize(configuration: configuration) else {
      throw PigeonError(
        code: "initialize_failed",
        message: "mars-xlog failed to open the global appender",
        details: nil
      )
    }
  }

  func flush(sync: Bool) throws {
    sync ? XLog.flushSync() : XLog.flush()
  }

  func close() throws {
    XLog.close()
  }

  func setLevel(level: XlogLevel) throws {
    XLog.level = level.logLevel
  }

  func getLevel() throws -> XlogLevel {
    XLog.level.pigeonLevel
  }

  func setConsoleLogEnabled(enabled: Bool) throws {
    XLog.setConsoleLogEnabled(enabled)
  }

  func setAppenderMode(mode: XlogMode) throws {
    XLog.setAppenderMode(mode.xlogMode)
  }

  func setMaxFileSize(maxBytes: Int64) throws {
    XLog.setMaxFileSize(maxBytes)
  }

  func setMaxAliveSeconds(seconds: Int64) throws {
    XLog.setMaxAliveTime(TimeInterval(seconds))
  }

  func instancePrefixes() throws -> [String] {
    XLog.instanceNamePrefixes
  }

  func hasInstance(prefix: String) throws -> Bool {
    XLog.instance(namePrefix: prefix) != nil
  }

  func flushInstance(prefix: String, sync: Bool) throws {
    guard let instance = XLog.instance(namePrefix: prefix) else { return }
    sync ? instance.flushSync() : instance.flush()
  }

  func getInstanceLevel(prefix: String) throws -> XlogLevel {
    (XLog.instance(namePrefix: prefix)?.level ?? .none).pigeonLevel
  }

  func setInstanceConsoleLogEnabled(prefix: String, enabled: Bool) throws {
    XLog.instance(namePrefix: prefix)?.setConsoleLogEnabled(enabled)
  }

  func closeInstance(prefix: String) throws {
    XLog.closeInstance(namePrefix: prefix)
  }

  func getInstanceLogFiles(prefix: String, timespanDays: Int64) throws -> [String] {
    XLog.instance(namePrefix: prefix)?.logFiles(timeSpanDays: Int(timespanDays)) ?? []
  }
}

private extension XlogLevel {
  var logLevel: LogLevel {
    LogLevel(rawValue: rawValue) ?? .none
  }
}

private extension LogLevel {
  var pigeonLevel: XlogLevel {
    XlogLevel(rawValue: rawValue) ?? .none
  }
}

private extension XlogMode {
  var xlogMode: XLogMode {
    XLogMode(rawValue: rawValue) ?? .async
  }
}

private extension XlogCompressMode {
  var xlogCompressMode: XLogCompressMode {
    XLogCompressMode(rawValue: rawValue) ?? .zlib
  }
}
