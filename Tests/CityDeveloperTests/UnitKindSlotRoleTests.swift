import XCTest
@testable import CommitPyramid

final class UnitKindSlotRoleTests: XCTestCase {

    func test_EveryUnitKindHasPreferredSlotRole() {
        let allRoles = Set(SlotRole.allCases)
        for kind in UnitKind.allCases {
            let role = kind.preferredSlotRole
            XCTAssertTrue(allRoles.contains(role),
                "\(kind) returned non-SlotRole value \(role)")
        }
    }

    func test_ResidentialKindsMapToResidentialSlot() {
        for kind in UnitKind.allCases where kind.category == .residential {
            XCTAssertEqual(kind.preferredSlotRole, .residential,
                "Residential kind \(kind) should map to .residential slot")
        }
    }

    func test_KeyMappings() {
        XCTAssertEqual(UnitKind.road.preferredSlotRole, .road)
        XCTAssertEqual(UnitKind.well.preferredSlotRole, .well)
        XCTAssertEqual(UnitKind.market.preferredSlotRole, .market)
        XCTAssertEqual(UnitKind.farm.preferredSlotRole, .farm)
        XCTAssertEqual(UnitKind.obelisk.preferredSlotRole, .obelisk)
    }

    func test_MonumentalKindsMapToMonumental() {
        XCTAssertEqual(UnitKind.pyramid.preferredSlotRole, .monumental)
        XCTAssertEqual(UnitKind.cathedral.preferredSlotRole, .monumental)
        XCTAssertEqual(UnitKind.lighthouse.preferredSlotRole, .monumental)
    }
}
