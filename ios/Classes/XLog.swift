import Foundation
import mars

/// Configuration shared by native callers and the Flutter platform channel.
@objcMembers public final class XLogConfiguration: NSObject, NSCopying {
  public let logDirectory: String
  public let namePrefix: String
  public var cacheDirectory: String?
  public var publicKey: String?
  public var cacheDays = 0
  public var level: LogLevel = .debug
  public var mode: XLogMode = .async
  public var compressMode: XLogCompressMode = .zlib
  public var compressLevel = 6
  public var consoleLogEnabled = true

  public init(logDirectory: String, namePrefix: String) {
    self.logDirectory = logDirectory
    self.namePrefix = namePrefix
    super.init()
  }

  public func copy(with zone: NSZone? = nil) -> Any {
    let copy = XLogConfiguration(logDirectory: logDirectory, namePrefix: namePrefix)
    copy.cacheDirectory = cacheDirectory
    copy.publicKey = publicKey
    copy.cacheDays = cacheDays
    copy.level = level
    copy.mode = mode
    copy.compressMode = compressMode
    copy.compressLevel = compressLevel
    copy.consoleLogEnabled = consoleLogEnabled
    return copy
  }

  var native: MarsXLogConfiguration {
    let configuration = MarsXLogConfiguration(
      logDirectory: logDirectory,
      namePrefix: namePrefix
    )
    configuration.cacheDirectory = cacheDirectory
    configuration.publicKey = publicKey
    configuration.cacheDays = cacheDays
    configuration.level = level.native
    configuration.mode = mode.native
    configuration.compressMode = compressMode.native
    configuration.compressLevel = compressLevel
    return configuration
  }
}

/// Native iOS facade over mars-xlog, shared with the Flutter implementation.
@objcMembers public final class XLog: NSObject {
  private override init() {}

  @discardableResult
  public static func initialize(configuration: XLogConfiguration) -> Bool {
    let opened = MarsXLog.open(with: configuration.native)
    if opened {
      MarsXLog.setConsoleLogEnabled(configuration.consoleLogEnabled)
    }
    return opened
  }

  public static func close() {
    MarsXLog.close()
  }

  public static func flush() {
    MarsXLog.flush()
  }

  public static func flushSync() {
    MarsXLog.flushSync()
  }

  public static var level: LogLevel {
    get { LogLevel(MarsXLog.level()) }
    set { MarsXLog.setLevel(newValue.native) }
  }

  public static func setConsoleLogEnabled(_ enabled: Bool) {
    MarsXLog.setConsoleLogEnabled(enabled)
  }

  public static func setAppenderMode(_ mode: XLogMode) {
    MarsXLog.setMode(mode.native)
  }

  public static func setMaxFileSize(_ maxBytes: Int64) {
    MarsXLog.setMaxFileSize(maxBytes)
  }

  public static func setMaxAliveTime(_ seconds: TimeInterval) {
    MarsXLog.setMaxAliveTime(seconds)
  }

  public static func log(
    level: LogLevel,
    tag: String,
    message: String,
    file: String = #fileID,
    function: String = #function,
    line: Int = #line
  ) {
    MarsXLog.log(
      with: level.native,
      tag: tag,
      message: message,
      file: file,
      function: function,
      line: line
    )
  }

  public static func verbose(_ tag: String, message: String) {
    MarsXLog.verbose(tag, message: message)
  }

  public static func debug(_ tag: String, message: String) {
    MarsXLog.debug(tag, message: message)
  }

  public static func info(_ tag: String, message: String) {
    MarsXLog.info(tag, message: message)
  }

  public static func warning(_ tag: String, message: String) {
    MarsXLog.warning(tag, message: message)
  }

  public static func error(_ tag: String, message: String) {
    MarsXLog.error(tag, message: message)
  }

  public static func fatal(_ tag: String, message: String) {
    MarsXLog.fatal(tag, message: message)
  }

  public static func logFiles(timeSpanDays: Int, prefix: String) -> [String] {
    MarsXLog.files(fromTimeSpan: timeSpanDays, prefix: prefix)
  }

  public static func openInstance(configuration: XLogConfiguration) -> XLogInstance? {
    guard let instance = MarsXLog.openInstance(with: configuration.native) else {
      return nil
    }
    instance.setConsoleLogEnabled(configuration.consoleLogEnabled)
    return XLogInstance(native: instance)
  }

  public static func instance(namePrefix: String) -> XLogInstance? {
    guard let instance = MarsXLog.instance(forNamePrefix: namePrefix) else {
      return nil
    }
    return XLogInstance(native: instance)
  }

  public static var instanceNamePrefixes: [String] {
    MarsXLog.instanceNamePrefixes()
  }

  public static func closeInstance(namePrefix: String) {
    MarsXLog.closeInstance(withNamePrefix: namePrefix)
  }
}
