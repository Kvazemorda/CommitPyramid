import XCTest
@testable import CommitPyramid

final class UnitPlannerSlotPlacementTests: XCTestCase {
    private func makeFixtureTemplate() -> DistrictTemplate {
        // In-memory fixture (similar to stage1-deir-el-medina) to avoid Bundle dependency.
        DistrictTemplate(
            name: "test-stage1",
            family: "test",
            stage: 1,
            width: 8, height: 5,
            biomePreference: [.meadow],
            slots: [
                TemplateSlot(x: 1, y: 1, role: .residential, footprint: GridSize(width: 1, height: 1)),
                TemplateSlot(x: 2, y: 1, role: .residential, footprint: GridSize(width: 1, height: 1)),
                TemplateSlot(x: 1, y: 2, role: .road, footprint: GridSize(width: 1, height: 1)),
                TemplateSlot(x: 2, y: 2, role: .road, footprint: GridSize(width: 1, height: 1)),
                TemplateSlot(x: 3, y: 2, role: .road, footprint: GridSize(width: 1, height: 1)),
                TemplateSlot(x: 1, y: 3, role: .residential, footprint: GridSize(width: 1, height: 1)),
                TemplateSlot(x: 2, y: 3, role: .well, footprint: GridSize(width: 1, height: 1))
            ]
        )
    }

    func testNextPositionUsesTemplateSlotForRoad() {
        let planner = UnitPlanner()
        let template = makeFixtureTemplate()
        let pos = planner.nextPosition(
            origin: GridPoint(x: 0, y: 0),
            buildingIndex: 0,
            roadCells: [],
            builtCells: [],
            unitSize: GridSize(width: 1, height: 1),
            template: template,
            kind: .road
        )
        XCTAssertEqual(pos, GridPoint(x: 1, y: 2))  // first road slot sorted (y, x)
    }

    func testNextPositionFindsNextFreeSlotWhenFirstOccupied() {
        let planner = UnitPlanner()
        let template = makeFixtureTemplate()
        let pos = planner.nextPosition(
            origin: GridPoint(x: 0, y: 0),
            buildingIndex: 0,
            roadCells: [],
            builtCells: [GridPoint(x: 1, y: 2)],
            unitSize: GridSize(width: 1, height: 1),
            template: template,
            kind: .road
        )
        XCTAssertEqual(pos, GridPoint(x: 2, y: 2))
    }

    func testNextPositionReturnsNilWhenAllSlotsOccupied() {
        let planner = UnitPlanner()
        let template = makeFixtureTemplate()
        let occupied: Set<GridPoint> = [
            GridPoint(x: 1, y: 2),
            GridPoint(x: 2, y: 2),
            GridPoint(x: 3, y: 2)
        ]
        let pos = planner.nextPosition(
            origin: GridPoint(x: 0, y: 0),
            buildingIndex: 0,
            roadCells: [],
            builtCells: occupied,
            unitSize: GridSize(width: 1, height: 1),
            template: template,
            kind: .road
        )
        XCTAssertNil(pos)
    }

    func testNextPositionRespectsDistrictOriginOffset() {
        let planner = UnitPlanner()
        let template = makeFixtureTemplate()
        let pos = planner.nextPosition(
            origin: GridPoint(x: 100, y: 50),
            buildingIndex: 0,
            roadCells: [],
            builtCells: [],
            unitSize: GridSize(width: 1, height: 1),
            template: template,
            kind: .road
        )
        XCTAssertEqual(pos, GridPoint(x: 101, y: 52))
    }

    func testNextPositionFallsBackToLegacyWhenTemplateNil() throws {
        let planner = UnitPlanner()
        // Legacy branch: one road cell at (5,5), origin nearby.
        let road: Set<GridPoint> = [GridPoint(x: 5, y: 5)]
        let pos = planner.nextPosition(
            origin: GridPoint(x: 5, y: 5),
            buildingIndex: 0,
            roadCells: road,
            builtCells: [],
            unitSize: GridSize(width: 1, height: 1),
            template: nil,
            kind: nil
        )
        // Legacy: should return a position at depth=1 from road.
        // Must be adjacent (manhattan dist 1) to road cell (5,5) and NOT overlap road.
        let p = try XCTUnwrap(pos)
        let neighbors: Set<GridPoint> = [
            GridPoint(x: 4, y: 5), GridPoint(x: 6, y: 5),
            GridPoint(x: 5, y: 4), GridPoint(x: 5, y: 6)
        ]
        XCTAssertTrue(neighbors.contains(p),
            "Expected depth-1 adjacency to road, got \(p)")
    }
}
