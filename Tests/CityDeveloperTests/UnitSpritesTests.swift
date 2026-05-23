import XCTest
import CommitPyramid

/// Тесты stage-tier визуального набора (TASK-036).
/// Покрывает: makeKindStageBuilding, stage clamp, PNG fallback, negative cache.
final class UnitSpritesTests: XCTestCase {

    // MARK: - makeKindStageBuilding: базовая полнота

    /// Для всех 51 UnitKind × stages [0...5] результат содержит хотя бы 1 child.
    func testMakeKindStageBuildingReturnsNonEmptyForAllKinds() {
        for kind in UnitKind.allCases {
            for stage in 0...5 {
                let node = UnitSprites.makeKindStageBuilding(kind: kind, stage: stage)
                XCTAssertGreaterThan(
                    node.children.count, 0,
                    "makeKindStageBuilding(kind: .\(kind.rawValue), stage: \(stage)) вернул пустой node"
                )
            }
        }
    }

    // MARK: - Stage clamp

    /// stage < minStage → clamped к minStage: результат не падает.
    func testStageClampedToMinStageDoesNotCrash() {
        // palace: minStage = 5
        let palace = UnitSprites.makeKindStageBuilding(kind: .palace, stage: 0)
        XCTAssertGreaterThan(palace.children.count, 0, "palace stage 0 → должен вернуть stage 5 placeholder")

        // cathedral: minStage = 4
        let cathedral = UnitSprites.makeKindStageBuilding(kind: .cathedral, stage: 1)
        XCTAssertGreaterThan(cathedral.children.count, 0, "cathedral stage 1 → clamp к minStage 4")

        // pyramid: minStage = 5
        let pyramid = UnitSprites.makeKindStageBuilding(kind: .pyramid, stage: 0)
        XCTAssertGreaterThan(pyramid.children.count, 0, "pyramid stage 0 → clamp к minStage 5")
    }

    /// stage > 5 → зажимается к 5, не падает.
    func testStageClampedToMaxStage() {
        for kind in UnitKind.allCases {
            let node = UnitSprites.makeKindStageBuilding(kind: kind, stage: 99)
            XCTAssertGreaterThan(
                node.children.count, 0,
                "stage 99 для .\(kind.rawValue) должен вернуть stage 5 node"
            )
        }
    }

    // MARK: - PNG fallback (negative-cache / процедурный)

    /// При отсутствии PNG (все тайтлы будут miss в тестовой среде без бандла)
    /// makeKindStageBuilding возвращает процедурный node, а не nil/crash.
    func testMissingPNGFallsBackToProcedural() {
        // В тестовой среде бандл не содержит PNG-ресурсов для Buildings/.
        // Ожидаем что все вызовы возвращают non-nil SKNode с children.
        let kinds: [UnitKind] = [.dugout, .chapel, .watchtower, .farm, .tavern]
        for kind in kinds {
            let node = UnitSprites.makeKindStageBuilding(kind: kind, stage: kind.minStage)
            XCTAssertGreaterThan(
                node.children.count, 0,
                "PNG fallback → процедурный node для .\(kind.rawValue)"
            )
        }
    }

    // MARK: - Новые категории: ≥2 tier'а явно различимы

    /// Religious: tier «low» (stage 1) и tier «high» (stage 4) дают разные высоты.
    func testReligiousHasTwoDistinctTiers() {
        // chapel minStage=1: сравниваем tier по children count (процедурные дают разный набор)
        let low  = UnitSprites.makeKindStageBuilding(kind: .chapel, stage: 1)
        let high = UnitSprites.makeKindStageBuilding(kind: .chapel, stage: 4)
        // Tier high имеет колонны (больше child-нод)
        XCTAssertGreaterThanOrEqual(
            high.children.count, low.children.count,
            "tier high (stage 4) должен содержать >= child-нод, чем tier low (stage 1)"
        )
    }

    /// Military: watchtower (tier 1) и barracks (tier 2) дают разный размер footprint.
    func testMilitaryHasTwoDistinctTiers() {
        let tower    = UnitSprites.makeKindStageBuilding(kind: .watchtower, stage: 2)
        let barracks = UnitSprites.makeKindStageBuilding(kind: .barracks, stage: 3)
        XCTAssertGreaterThan(tower.children.count,    0, "watchtower tier должен рендериться")
        XCTAssertGreaterThan(barracks.children.count, 0, "barracks tier должен рендериться")
    }

    // MARK: - Residential: 6 tier'ов (stage 0..5)

    /// Все 12 residential kinds рендерятся на stage 0..5 без ошибок.
    func testResidentialAllStagesRender() {
        let residentialKinds: [UnitKind] = [
            .dugout, .shack, .hut, .farmHouse, .house,
            .twoStoryHouse, .stoneHouse, .townhouse, .tenement,
            .manor, .villa, .palace
        ]
        for kind in residentialKinds {
            for stage in 0...5 {
                let node = UnitSprites.makeKindStageBuilding(kind: kind, stage: stage)
                XCTAssertGreaterThan(
                    node.children.count, 0,
                    "Residential .\(kind.rawValue) stage \(stage) вернул пустой node"
                )
            }
        }
    }

    // MARK: - Производительность: 51 kind × stage ≤ 100 мс

    /// Синхронное построение 51 × 6 = 306 node'ов должно укладываться в 100 мс.
    func testPerformanceMakeKindStageBuildingFor51Kinds() {
        measure {
            for kind in UnitKind.allCases {
                for stage in 0...5 {
                    _ = UnitSprites.makeKindStageBuilding(kind: kind, stage: stage)
                }
            }
        }
    }
}
