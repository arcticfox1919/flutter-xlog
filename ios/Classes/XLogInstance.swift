import Foundation
import mars

/// Handle for an independently configured mars-xlog instance.
@objcMembers public final class XLogInstance: NSObject {
  private let native: MarsXLogInstance

  init(native: MarsXLogInstance) {
    self.native = native
    super.init()
  }

  public var namePrefix: String { native.namePrefix }
  public var isClosed: Bool { native.isClosed }

  public var level: LogLevel {
    get { LogLevel(native.level) }
    set { native.level = newValue.native }
  }

  public func log(
    level: LogLevel,
    tag: String,
    message: String,
    file: String = #fileID,
    function: String = #function,
    line: Int = #line
  ) {
    native.log(
      with: level.native,
      tag: tag,
      message: message,
      file: file,
      function: function,
      line: line
    )
  }

  public func verbose(_ tag: String, message: String) {
    native.verbose(tag, message: message)
  }

  public func debug(_ tag: String, message: String) {
    native.debug(tag, message: message)
  }

  public func info(_ tag: String, message: String) {
    native.info(tag, message: message)
  }

  public func warning(_ tag: String, message: String) {
    native.warning(tag, message: message)
  }

  public func error(_ tag: String, message: String) {
    native.error(tag, message: message)
  }

  public func fatal(_ tag: String, message: String) {
    native.fatal(tag, message: message)
  }

  public func flush() {
    native.flush()
  }

  public func flushSync() {
    native.flushSync()
  }

  public func setAppenderMode(_ mode: XLogMode) {
    native.setMode(mode.native)
  }

  public func setConsoleLogEnabled(_ enabled: Bool) {
    native.setConsoleLogEnabled(enabled)
  }

  public func setMaxFileSize(_ maxBytes: Int64) {
    native.setMaxFileSize(maxBytes)
  }

  public func setMaxAliveTime(_ seconds: TimeInterval) {
    native.setMaxAliveTime(seconds)
  }

  public func logFiles(timeSpanDays: Int) -> [String] {
    native.files(fromTimeSpan: timeSpanDays)
  }

  public func close() {
    native.close()
  }
}
