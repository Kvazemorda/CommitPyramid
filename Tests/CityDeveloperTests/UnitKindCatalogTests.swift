import XCTest
@testable import CommitPyramid

/// Compile-time / runtime инварианты каталога UnitKind (TASK-031).
/// Страхуют от ручных опечаток в таблице на 51 юнит и нарушения AC edge cases.
final class UnitKindCatalogTests: XCTestCase {

    // MARK: - Полнота каталога

    /// Каталог покрывает все case'ы UnitKind (нет дыр).
    func testCatalogCoversAllCases() {
        for kind in UnitKind.allCases {
            XCTAssertNotNil(
                kind.info as UnitKindInfo?,
                "UnitKind.\(kind.rawValue) отсутствует в catalog"
            )
        }
    }

    /// Ровно 51 case (50 из F-16 + warehouse legacy).
    func testUnitKindCaseCount() {
        XCTAssertEqual(
            UnitKind.allCases.count, 51,
            "Ожидаем 51 case: 50 из F-16 + 1 legacy warehouse"
        )
    }

    // MARK: - AC edge cases (из постановки TASK-031)

    /// large == true → evolvesTo == nil (взаимоисключающие свойства).
    func testLargeImpliesNoEvolution() {
        for kind in UnitKind.allCases {
            if kind.large {
                XCTAssertNil(
                    kind.evolvesTo,
                    "UnitKind.\(kind.rawValue): large=true, но evolvesTo != nil"
                )
            }
        }
    }

    /// evolvesTo != nil ↔ evolutionThreshold != nil (всегда парные).
    func testEvolutionPairConsistency() {
        for kind in UnitKind.allCases {
            let hasTarget    = kind.evolvesTo != nil
            let hasThreshold = kind.evolutionThreshold != nil
            XCTAssertEqual(
                hasTarget, hasThreshold,
                "UnitKind.\(kind.rawValue): evolvesTo и evolutionThreshold должны быть либо оба nil, либо оба non-nil"
            )
        }
    }

    /// Terrain непустой для всех юнитов (AC edge case «любой = все 7 биомов, не nil»).
    func testTerrainNeverEmpty() {
        for kind in UnitKind.allCases {
            XCTAssertFalse(
                kind.terrain.isEmpty,
                "UnitKind.\(kind.rawValue): terrain пустой"
            )
        }
    }

    /// Нет циклических эволюционных цепочек (A → B → ... → A).
    func testNoEvolutionCycles() {
        for startKind in UnitKind.allCases {
            var visited = Set<UnitKind>()
            var current: UnitKind? = startKind
            while let c = current {
                XCTAssertFalse(
                    visited.contains(c),
                    "Цикл эволюции обнаружен, начиная с UnitKind.\(startKind.rawValue)"
                )
                visited.insert(c)
                current = c.evolvesTo
            }
        }
    }

    // MARK: - RawValue совместимость для старых 12 case'ов (AC4)

    func testLegacyRawValues() {
        XCTAssertEqual(UnitKind.shack.rawValue,     "shack")
        XCTAssertEqual(UnitKind.house.rawValue,     "house")
        XCTAssertEqual(UnitKind.villa.rawValue,     "villa")
        XCTAssertEqual(UnitKind.well.rawValue,      "well")
        XCTAssertEqual(UnitKind.road.rawValue,      "road")
        XCTAssertEqual(UnitKind.warehouse.rawValue, "warehouse")
        XCTAssertEqual(UnitKind.workshop.rawValue,  "workshop")
        XCTAssertEqual(UnitKind.raw.rawValue,       "raw")
        XCTAssertEqual(UnitKind.market.rawValue,    "market")
        XCTAssertEqual(UnitKind.forum.rawValue,     "forum")
        XCTAssertEqual(UnitKind.temple.rawValue,    "temple")
        XCTAssertEqual(UnitKind.obelisk.rawValue,   "obelisk")
    }

    // MARK: - Категории расширены (AC3)

    func testUnitCategoryHasSixValues() {
        let allCategories: [UnitCategory] = [
            .residential, .infrastructure, .production,
            .social, .religious, .military
        ]
        XCTAssertEqual(allCategories.count, 6)
    }

    // MARK: - minStage в диапазоне 0..5

    func testMinStageRange() {
        for kind in UnitKind.allCases {
            XCTAssertTrue(
                (0...5).contains(kind.minStage),
                "UnitKind.\(kind.rawValue): minStage=\(kind.minStage) вне диапазона 0..5"
            )
        }
    }

    // MARK: - label непустой у всех юнитов

    func testLabelsNonEmpty() {
        for kind in UnitKind.allCases {
            XCTAssertFalse(
                kind.label.isEmpty,
                "UnitKind.\(kind.rawValue): label пустой"
            )
        }
    }
}
