import Foundation
import mars

/// Log severity used by the public iOS wrapper.
@objc public enum LogLevel: Int {
  case verbose = 0
  case debug = 1
  case info = 2
  case warning = 3
  case error = 4
  case fatal = 5
  case none = 6

  init(_ native: MarsXLogLevel) {
    self = LogLevel(rawValue: native.rawValue) ?? .none
  }

  var native: MarsXLogLevel {
    MarsXLogLevel(rawValue: rawValue) ?? MarsXLogLevel(rawValue: 6)!
  }
}

/// Appender write mode used by the public iOS wrapper.
@objc public enum XLogMode: Int {
  case async = 0
  case sync = 1

  var native: MarsXLogMode {
    MarsXLogMode(rawValue: rawValue) ?? MarsXLogMode(rawValue: 0)!
  }
}

/// Compression algorithm used by the public iOS wrapper.
@objc public enum XLogCompressMode: Int {
  case zlib = 0
  case zstd = 1

  var native: MarsXLogCompressMode {
    MarsXLogCompressMode(rawValue: rawValue) ?? MarsXLogCompressMode(rawValue: 0)!
  }
}
