import XCTest
@testable import CommitPyramid

/// Тесты pure-helper `TerrainAffinity.preferredBiomes(for:)` (TASK-030c F-15).
///
/// Проверяют корректность выбора предпочтительных биомов по составу юнитов:
/// рыболовный проект → water-биомы, горный → mountain/stone, пустой → fallback.
final class TerrainAffinityPreferredBiomesTests: XCTestCase {

    // MARK: - testFishingProjectPrefersRiverSea

    /// Рыболовный проект (fishingPier, pier, lighthouse — все terrain: [.sea, .river]) →
    /// предпочтительные биомы должны содержать .river и/или .sea.
    func testFishingProjectPrefersRiverSea() {
        let kinds: [UnitKind] = [.fishingPier, .pier, .lighthouse]
        let preferred = TerrainAffinity.preferredBiomes(for: kinds)

        XCTAssertFalse(preferred.isEmpty,
            "Рыболовный проект не должен возвращать пустой список биомов. Got: \(preferred)")

        let containsWaterBiome = preferred.contains(.river) || preferred.contains(.sea)
        XCTAssertTrue(containsWaterBiome,
            "Рыболовный проект (fishingPier/pier/lighthouse) должен предпочесть .river или .sea. Got: \(preferred)")

        // Water-биомы должны быть в топе (первые два позиции).
        let topTwo = Set(preferred.prefix(2))
        let topHasWater = topTwo.contains(.river) || topTwo.contains(.sea)
        XCTAssertTrue(topHasWater,
            "Водные биомы должны быть в топе для рыболовного проекта. Top-2: \(topTwo)")
    }

    // MARK: - testMiningProjectPrefersMountainStone

    /// Горный проект (mine, quarry, forge — terrain: [.mountain/.stone]) →
    /// предпочтительные биомы должны содержать .mountain и/или .stone.
    func testMiningProjectPrefersMountainStone() {
        let kinds: [UnitKind] = [.mine, .quarry, .forge]
        let preferred = TerrainAffinity.preferredBiomes(for: kinds)

        XCTAssertFalse(preferred.isEmpty,
            "Горный проект не должен возвращать пустой список. Got: \(preferred)")

        let containsRockBiome = preferred.contains(.mountain) || preferred.contains(.stone)
        XCTAssertTrue(containsRockBiome,
            "Горный проект (mine/quarry/forge) должен предпочесть .mountain или .stone. Got: \(preferred)")

        // Горные биомы — в топе.
        let topTwo = Set(preferred.prefix(2))
        let topHasRock = topTwo.contains(.mountain) || topTwo.contains(.stone)
        XCTAssertTrue(topHasRock,
            "Горные биомы должны быть в топе для горного проекта. Top-2: \(topTwo)")
    }

    // MARK: - testNeutralProjectFallsBackToMeadowDesert

    /// Нейтральный проект (well, shack — terrain: «любой») →
    /// список непустой, не должно крашить.
    /// well/shack имеют terrain=any → weight=1.0 во всех биомах →
    /// threshold отсекает биомы с весом ≤ 0.3 × max (здесь 0.3 × 2.0 = 0.6),
    /// все биомы равны 2.0 → все проходят порог → список содержит все 7 биомов.
    func testNeutralProjectFallsBackToMeadowDesert() {
        let kinds: [UnitKind] = [.well, .shack]
        let preferred = TerrainAffinity.preferredBiomes(for: kinds)

        XCTAssertFalse(preferred.isEmpty,
            "Нейтральный проект не должен возвращать пустой список. Got: \(preferred)")

        // При terrain=«любой» все биомы имеют одинаковый вес → должны быть все 7.
        XCTAssertEqual(preferred.count, BiomeKind.allCases.count,
            "При terrain=«любой» все биомы должны попасть в preferred (одинаковый вес). Got: \(preferred)")
    }

    // MARK: - testEmptyProjectReturnsFallback

    /// Пустой ввод → fallback [.meadow, .desert].
    func testEmptyProjectReturnsFallback() {
        let preferred = TerrainAffinity.preferredBiomes(for: [])

        XCTAssertEqual(preferred, [.meadow, .desert],
            "Пустой список юнитов должен возвращать fallback [.meadow, .desert]. Got: \(preferred)")
    }

    // MARK: - testThresholdCutsWeakBiomes

    /// Проект с одним только fishingPier (terrain: [.sea, .river]) →
    /// только .sea и .river имеют вес 1.0; остальные — 0.15 (< 0.3 × 1.0 = 0.3) → отсекаются.
    func testThresholdCutsWeakBiomes() {
        let kinds: [UnitKind] = [.fishingPier]
        let preferred = TerrainAffinity.preferredBiomes(for: kinds)

        // .sea и .river — в списке.
        XCTAssertTrue(preferred.contains(.sea),
            "fishingPier: .sea должен быть в preferred. Got: \(preferred)")
        XCTAssertTrue(preferred.contains(.river),
            "fishingPier: .river должен быть в preferred. Got: \(preferred)")

        // Остальные биомы (вес 0.15) отсекаются порогом 0.3 × 1.0 = 0.3.
        for biome in BiomeKind.allCases where biome != .sea && biome != .river {
            XCTAssertFalse(preferred.contains(biome),
                "fishingPier: биом .\(biome) (вес 0.15) не должен проходить порог. Got: \(preferred)")
        }
    }

    // MARK: - testDeterminism

    /// Два вызова с одинаковым вводом дают идентичный результат.
    func testDeterminism() {
        let kinds: [UnitKind] = [.mine, .quarry, .forge]
        let r1 = TerrainAffinity.preferredBiomes(for: kinds)
        let r2 = TerrainAffinity.preferredBiomes(for: kinds)
        XCTAssertEqual(r1, r2,
            "preferredBiomes должен быть детерминирован. r1=\(r1), r2=\(r2)")
    }
}
