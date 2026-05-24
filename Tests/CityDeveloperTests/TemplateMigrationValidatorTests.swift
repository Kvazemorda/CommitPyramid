import XCTest
@testable import CommitPyramid

final class TemplateMigrationValidatorTests: XCTestCase {

    private func makeTemplate(name: String, slots: [TemplateSlot]) -> DistrictTemplate {
        DistrictTemplate(
            name: name, family: "test", stage: 1,
            width: 10, height: 10,
            biomePreference: [.meadow],
            slots: slots
        )
    }

    private func makeUnit(kind: UnitKind, at pos: GridPoint, projectId: String = "p1") -> UnitState {
        UnitState(
            id: UUID(), projectId: projectId, kind: kind,
            position: pos, tier: 0, decayLevel: 0,
            taskTitle: nil, taskTs: Date(), taskSource: nil
        )
    }

    func testCanMigrateWhenAllPositionsMatchSlots() {
        let next = makeTemplate(name: "next", slots: [
            TemplateSlot(x: 1, y: 1, role: .residential, footprint: GridSize(width: 1, height: 1)),
            TemplateSlot(x: 2, y: 2, role: .road,        footprint: GridSize(width: 1, height: 1))
        ])
        let units = [
            makeUnit(kind: .shack, at: GridPoint(x: 1, y: 1)),  // residential
            makeUnit(kind: .road,  at: GridPoint(x: 2, y: 2))   // road
        ]
        XCTAssertTrue(TemplateMigrationValidator.canMigrate(
            units: units, to: next, districtOrigin: GridPoint(x: 0, y: 0)
        ))
    }

    func testCannotMigrateWhenUnitPositionHasNoSlot() {
        let next = makeTemplate(name: "next", slots: [
            TemplateSlot(x: 1, y: 1, role: .residential, footprint: GridSize(width: 1, height: 1))
        ])
        let units = [makeUnit(kind: .shack, at: GridPoint(x: 5, y: 5))]
        XCTAssertFalse(TemplateMigrationValidator.canMigrate(
            units: units, to: next, districtOrigin: GridPoint(x: 0, y: 0)
        ))
    }

    func testCannotMigrateWhenSlotRoleIncompatible() {
        let next = makeTemplate(name: "next", slots: [
            TemplateSlot(x: 1, y: 1, role: .warehouse, footprint: GridSize(width: 1, height: 1))
        ])
        let units = [makeUnit(kind: .shack, at: GridPoint(x: 1, y: 1))]  // shack → residential ≠ warehouse
        XCTAssertFalse(TemplateMigrationValidator.canMigrate(
            units: units, to: next, districtOrigin: GridPoint(x: 0, y: 0)
        ))
    }

    func testRespectsDistrictOriginOffset() {
        let next = makeTemplate(name: "next", slots: [
            TemplateSlot(x: 1, y: 1, role: .residential, footprint: GridSize(width: 1, height: 1))
        ])
        // Unit at absolute (101, 51) = origin(100,50) + slot(1,1)
        let units = [makeUnit(kind: .shack, at: GridPoint(x: 101, y: 51))]
        XCTAssertTrue(TemplateMigrationValidator.canMigrate(
            units: units, to: next, districtOrigin: GridPoint(x: 100, y: 50)
        ))
    }
}
