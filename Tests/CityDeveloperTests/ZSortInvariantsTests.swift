import XCTest
@testable import CommitPyramid

final class ZSortInvariantsTests: XCTestCase {
    // Воспроизводит формулу из GameScene.drawUnit (TASK-052)
    private func zPositionForUnit(_ kind: UnitKind, position: GridPoint) -> Double {
        let s = kind.size
        let farSum = position.x + position.y + s.width + s.height - 2
        let layerOffset: Double = (kind == .road) ? -0.5 : 0.0
        return -Double(farSum) + layerOffset
    }

    func test_1x1Plus1x1_FarUnitGetsHigherZBackward() {
        // Far building (higher x+y) gets MORE NEGATIVE z → drawn first.
        let near = zPositionForUnit(.house, position: GridPoint(x: 5, y: 5))    // 1×1, farSum=10
        let far  = zPositionForUnit(.house, position: GridPoint(x: 10, y: 10))  // 1×1, farSum=20
        XCTAssertGreaterThan(near, far,
            "Ближний 1×1 должен иметь больший zPosition чем дальний 1×1")
    }

    func test_1x1Plus2x2_FarUnitGetsHigherZ_LargeAnchorFix() {
        // 2×2 at (8,8) covers (8..9, 8..9) → far corner (9,9) → farSum=18.
        // 1×1 at (5,5) → farSum=10. 2×2 should be "further" → lower z.
        let small = zPositionForUnit(.house, position: GridPoint(x: 5, y: 5))   // farSum=10
        let large = zPositionForUnit(.manor, position: GridPoint(x: 8, y: 8))   // 2×2, farSum=18
        XCTAssertGreaterThan(small, large)
    }

    func test_2x2Plus2x2_FarUnitGetsHigherZ() {
        let near = zPositionForUnit(.manor, position: GridPoint(x: 5, y: 5))    // farSum=10
        let far  = zPositionForUnit(.manor, position: GridPoint(x: 10, y: 10))  // farSum=22
        XCTAssertGreaterThan(near, far)
    }

    func test_RoadBelowBuildingAtSameFarSum() {
        // At same far-sum, road should have STRICTLY LOWER z (drawn first).
        let road    = zPositionForUnit(.road, position: GridPoint(x: 10, y: 10))  // farSum=20, offset=-0.5 → -20.5
        let building = zPositionForUnit(.house, position: GridPoint(x: 10, y: 10)) // farSum=20, offset=0 → -20
        XCTAssertLessThan(road, building)
    }

    func test_FarRoadStillBelowNearBuilding() {
        // Кросс-layer: дальняя road НЕ должна перекрывать ближнее building.
        let farRoad   = zPositionForUnit(.road, position: GridPoint(x: 15, y: 15))   // -30.5
        let nearBldg  = zPositionForUnit(.house, position: GridPoint(x: 5, y: 5))    // -10
        XCTAssertLessThan(farRoad, nearBldg)
    }
}
