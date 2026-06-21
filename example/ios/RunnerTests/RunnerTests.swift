import XCTest
@testable import xlog

class RunnerTests: XCTestCase {
  func testConfigurationDefaults() {
    let configuration = XLogConfiguration(logDirectory: "/tmp/log", namePrefix: "test")

    XCTAssertEqual(configuration.logDirectory, "/tmp/log")
    XCTAssertEqual(configuration.namePrefix, "test")
    XCTAssertEqual(configuration.level, .debug)
    XCTAssertEqual(configuration.mode, .async)
    XCTAssertEqual(configuration.compressMode, .zlib)
    XCTAssertEqual(configuration.compressLevel, 6)
    XCTAssertTrue(configuration.consoleLogEnabled)
  }
}
