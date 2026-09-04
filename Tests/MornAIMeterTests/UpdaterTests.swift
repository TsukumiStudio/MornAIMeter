import XCTest
@testable import MornAIMeter

final class UpdaterTests: XCTestCase {
    func testNewerPatchTagIsNewer() {
        XCTAssertTrue(Updater.isNewer(latestTag: "v0.6.0", current: "0.5.0"))
    }

    func testSameVersionIsNotNewer() {
        XCTAssertFalse(Updater.isNewer(latestTag: "v0.5.0", current: "0.5.0"))
    }

    func testPatchBumpIsNewer() {
        XCTAssertTrue(Updater.isNewer(latestTag: "v0.5.1", current: "0.5.0"))
    }

    func testNumericMinorComparisonNotLexicographic() {
        XCTAssertTrue(Updater.isNewer(latestTag: "v0.10.0", current: "0.9.0"))
    }

    func testInvalidTagIsNotNewer() {
        XCTAssertFalse(Updater.isNewer(latestTag: "not-a-version", current: "0.5.0"))
    }
}
