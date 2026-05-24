import XCTest
@testable import CommitPyramid

final class EraRulesTests: XCTestCase {

    func testComputeEraReturnsZeroBelowStage5() {
        for stage in 0..<5 {
            XCTAssertEqual(EraRules.computeEra(taskCount: 99999, stage: stage, ageDays: 99999), 0,
                "Expected era 0 for stage \(stage)")
        }
    }

    func testComputeEraReachesOneAt100TasksAnd30Days() {
        XCTAssertEqual(EraRules.computeEra(taskCount: 100, stage: 5, ageDays: 30), 1)
        XCTAssertEqual(EraRules.computeEra(taskCount: 99,  stage: 5, ageDays: 30), 0)
        XCTAssertEqual(EraRules.computeEra(taskCount: 100, stage: 5, ageDays: 29), 0)
    }

    func testComputeEraReachesTwoAt500TasksAnd180Days() {
        XCTAssertEqual(EraRules.computeEra(taskCount: 500, stage: 5, ageDays: 180), 2)
        XCTAssertEqual(EraRules.computeEra(taskCount: 499, stage: 5, ageDays: 180), 1)
        XCTAssertEqual(EraRules.computeEra(taskCount: 500, stage: 5, ageDays: 179), 1)
    }

    func testComputeEraReachesThreeAt2000TasksAnd365Days() {
        XCTAssertEqual(EraRules.computeEra(taskCount: 2000, stage: 5, ageDays: 365), 3)
        XCTAssertEqual(EraRules.computeEra(taskCount: 1999, stage: 5, ageDays: 365), 2)
        XCTAssertEqual(EraRules.computeEra(taskCount: 2000, stage: 5, ageDays: 364), 2)
    }
}
