import XCTest
@testable import MetronomeCore

final class MetronomeTests: XCTestCase {
    func testBundleIdentifier() {
        XCTAssertEqual(Metronome.bundleIdentifier, "com.jamesclark32.metronome")
    }
}
