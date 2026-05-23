import XCTest
import CommitPyramid

/// Тесты чистой функции `TerrainAffinity.weight(for:in:)` (TASK-033).
///
/// Покрывают все AC из спеки и edge cases из технического разбора.
final class TerrainAffinityTests: XCTestCase {

    // MARK: - AC #2: terrain = «любой» → 1.0 во всех биомах

    /// Землянка, Дорога и Дом имеют terrain=«любой» — вес должен быть 1.0 во всех 7 биомах.
    func testAnyTerrainGivesUniformOne() {
        let anyKinds: [UnitKind] = [.dugout, .road, .house]
        for kind in anyKinds {
            for biome in BiomeKind.allCases {
                let w = TerrainAffinity.weight(for: kind, in: biome)
                XCTAssertEqual(
                    w, 1.0,
                    "UnitKind.\(kind.rawValue) (terrain=«любой») в биоме .\(biome) ожидаем 1.0, получили \(w)"
                )
            }
        }
    }

    // MARK: - AC #3: предпочтение → ≥ 0.8 в своих, ≤ 0.2 в чужих

    /// Каменоломня (terrain: [.stone, .mountain]):
    /// - в stone/mountain → 1.0
    /// - в meadow/desert/forest/river → 0.15
    /// - в sea → 0.05 (white-list)
    func testPreferredHighOtherLow() {
        // Предпочтительные биомы Каменоломни
        for biome in [BiomeKind.stone, .mountain] {
            let w = TerrainAffinity.weight(for: .quarry, in: biome)
            XCTAssertEqual(w, 1.0, "Каменоломня в .\(biome): ожидаем 1.0, получили \(w)")
        }

        // Чужие биомы (не море)
        for biome in [BiomeKind.meadow, .desert, .forest, .river] {
            let w = TerrainAffinity.weight(for: .quarry, in: biome)
            XCTAssertLessThanOrEqual(w, 0.2,
                "Каменоломня в .\(biome): ожидаем ≤ 0.2, получили \(w)")
            XCTAssertEqual(w, 0.15, "Каменоломня в .\(biome): ожидаем 0.15, получили \(w)")
        }

        // Море — Каменоломня в white-list
        let wSea = TerrainAffinity.weight(for: .quarry, in: .sea)
        XCTAssertEqual(wSea, 0.05, "Каменоломня в .sea: ожидаем 0.05, получили \(wSea)")
    }

    // MARK: - AC #4: для любой категории и любого биома есть юнит с весом ≥ 0.5

    /// Проходим по всем 6 категориям × 7 биомам.
    /// Для каждой пары должен найтись хотя бы один юнит с весом ≥ 0.5.
    func testForEachCategoryAndBiomeAtLeastOneHigh() {
        // UnitCategory не CaseIterable — перечисляем вручную
        let allCategories: [UnitCategory] = [
            .residential, .infrastructure, .production,
            .social, .religious, .military
        ]

        for category in allCategories {
            let kindsInCategory = UnitKind.allCases.filter { $0.category == category }

            for biome in BiomeKind.allCases {
                let maxWeight = kindsInCategory.map {
                    TerrainAffinity.weight(for: $0, in: biome)
                }.max() ?? 0.0

                XCTAssertGreaterThanOrEqual(
                    maxWeight, 0.5,
                    "Категория .\(category), биом .\(biome): ни один юнит не имеет веса ≥ 0.5 (max=\(maxWeight))"
                )
            }
        }
    }

    // MARK: - Edge #2: terrain пуст → 0.5 + однократный лог

    /// Инвариант: у всех существующих юнитов terrain непустой.
    /// Если это нарушится — здесь сразу увидим.
    func testAllKindsHaveNonEmptyTerrain() {
        for kind in UnitKind.allCases {
            XCTAssertFalse(
                kind.terrain.isEmpty,
                "UnitKind.\(kind.rawValue) имеет пустой terrain (нарушение инварианта TASK-031)"
            )
        }
    }

    // MARK: - Edge #4: море — white-list только для Пирамиды и Каменоломни

    /// - Пирамида и Каменоломня в море → 0.05
    /// - Шахта, Цистерна, Кузница в море → 0.15 (не в white-list)
    /// - Часовня (terrain=любой) в море → 1.0
    /// - Рыболовецкий причал (terrain=[.sea, .river]) в море → 1.0
    func testSeaPenaltyOnlyForWhitelist() {
        // White-list: минимальный штраф
        let wPyramid = TerrainAffinity.weight(for: .pyramid, in: .sea)
        XCTAssertEqual(wPyramid, 0.05, "Пирамида в .sea: ожидаем 0.05, получили \(wPyramid)")

        let wQuarry = TerrainAffinity.weight(for: .quarry, in: .sea)
        XCTAssertEqual(wQuarry, 0.05, "Каменоломня в .sea: ожидаем 0.05, получили \(wQuarry)")

        // Сухопутные не из white-list → 0.15 (не ≤ 0.05)
        for kind in [UnitKind.mine, .cistern, .forge] {
            let w = TerrainAffinity.weight(for: kind, in: .sea)
            XCTAssertEqual(
                w, 0.15,
                "UnitKind.\(kind.rawValue) в .sea: ожидаем 0.15, получили \(w)"
            )
        }

        // Часовня — terrain=«любой» → 1.0 в любом биоме включая море
        let wChapel = TerrainAffinity.weight(for: .chapel, in: .sea)
        XCTAssertEqual(wChapel, 1.0, "Часовня в .sea: ожидаем 1.0, получили \(wChapel)")

        // Рыболовецкий причал — terrain=[.sea, .river] → море предпочтительно
        let wFishing = TerrainAffinity.weight(for: .fishingPier, in: .sea)
        XCTAssertEqual(wFishing, 1.0, "Рыболовецкий причал в .sea: ожидаем 1.0, получили \(wFishing)")
    }

    // MARK: - AC #5: детерминизм

    /// Два последовательных вызова с одними аргументами дают побитово равный Double.
    func testDeterminism() {
        for kind in UnitKind.allCases {
            for biome in BiomeKind.allCases {
                let w1 = TerrainAffinity.weight(for: kind, in: biome)
                let w2 = TerrainAffinity.weight(for: kind, in: biome)
                XCTAssertEqual(
                    w1.bitPattern, w2.bitPattern,
                    "UnitKind.\(kind.rawValue) × .\(biome): вес недетерминирован (\(w1) != \(w2))"
                )
            }
        }
    }

    // MARK: - Диапазон [0..1]

    /// Все веса лежат строго в [0, 1].
    func testWeightsInRange() {
        for kind in UnitKind.allCases {
            for biome in BiomeKind.allCases {
                let w = TerrainAffinity.weight(for: kind, in: biome)
                XCTAssertTrue(
                    (0.0...1.0).contains(w),
                    "UnitKind.\(kind.rawValue) × .\(biome): вес \(w) вне диапазона [0, 1]"
                )
            }
        }
    }
}
