import XCTest
import CommitPyramid

final class CitizenManagerTests: XCTestCase {

    func testActiveCitizenCountExcludesLeaving() {
        let cm = CitizenManager()
        _ = cm._testSeed(projectId: "p1", leaving: false)
        _ = cm._testSeed(projectId: "p1", leaving: false)
        _ = cm._testSeed(projectId: "p1", leaving: true)  // in citizensLeaving
        XCTAssertEqual(cm.activeCitizenCount(for: "p1"), 2)
    }

    func testActiveCitizenCountUnknownProjectIsZero() {
        let cm = CitizenManager()
        XCTAssertEqual(cm.activeCitizenCount(for: "ghost"), 0)
    }

    func testActiveCitizenCountDecreasesWhenMarkedLeaving() {
        let cm = CitizenManager()
        let a = cm._testSeed(projectId: "p1", leaving: false)
        let b = cm._testSeed(projectId: "p1", leaving: false)
        XCTAssertEqual(cm.activeCitizenCount(for: "p1"), 2)
        _ = cm._testSeed(projectId: "p1", leaving: true)
        XCTAssertEqual(cm.activeCitizenCount(for: "p1"), 2,
                       "Leaving citizen must not count as active")
        _ = (a, b) // suppress unused warning
    }
}
