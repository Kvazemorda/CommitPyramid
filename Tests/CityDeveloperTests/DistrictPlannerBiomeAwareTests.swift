import XCTest
@testable import CommitPyramid

/// Тесты biome-aware расширения `DistrictPlanner.allocateNextOrigin` (TASK-030c F-15).
///
/// MockBiomeReader позволяет задать точечную карту биомов для детерминированного
/// управления поведением планировщика без зависимости от реальной карты.
final class DistrictPlannerBiomeAwareTests: XCTestCase {

    // MARK: - Mock

    private final class MockBiomeReader: BiomeMapReader {
        let biomes: [GridPoint: BiomeKind]
        let defaultBiome: BiomeKind
        let width: Int
        let height: Int

        init(biomes: [GridPoint: BiomeKind], defaultBiome: BiomeKind = .meadow,
             width: Int = 256, height: Int = 256) {
            self.biomes = biomes
            self.defaultBiome = defaultBiome
            self.width = width
            self.height = height
        }

        func biome(atX x: Int, y: Int) -> BiomeKind {
            biomes[GridPoint(x: x, y: y)] ?? defaultBiome
        }
    }

    // MARK: - testBiomeAwareSpiralFindsPreferredBiomeOrigin

    /// Карта почти вся meadow, но один mountain-тайл в зоне первых 20 кандидатов спирали.
    /// allocateNextOrigin с preferredBiomes=[.mountain] должен вернуть именно этот тайл.
    ///
    /// Примечание: водные биомы (.sea, .river) фильтруются водным-skip (BUG-009) —
    /// preferred-scan ищет только не-водные тайлы. Используем .mountain для проверки.
    ///
    /// spiralPoint(index: 0) = (128, 128) — центр карты (meadow).
    /// spiralPoint(index: 3) = (128, 142) — один из первых кандидатов.
    /// Размещаем .mountain на (128, 142); остальные = .meadow.
    func test_BiomeAwareSpiralFindsPreferredBiomeOrigin() {
        let planner = DistrictPlanner()

        // Вычисляем координату spiral index 3 для размещения mountain-тайла.
        let mountainPoint = planner.spiralPoint(index: 3)

        let reader = MockBiomeReader(biomes: [mountainPoint: .mountain], defaultBiome: .meadow)

        let (origin, _) = planner.allocateNextOrigin(
            currentIndex: 0,
            biomeReader: reader,
            preferredBiomes: [.mountain]
        )

        XCTAssertEqual(origin, mountainPoint,
            "Планировщик должен выбрать .mountain тайл на \(mountainPoint), а не spiral-центр. Got: \(origin)")
        XCTAssertEqual(reader.biome(atX: origin.x, y: origin.y), .mountain,
            "Выбранная клетка должна иметь биом .mountain. Got: \(reader.biome(atX: origin.x, y: origin.y))")
    }

    // MARK: - testFallbackToSpiralWhenNoMatchingBiome

    /// Карта целиком .meadow, preferredBiomes=[.river].
    /// Ни один из 20 кандидатов не .river → fallback на обычную спираль (water-skipped origin).
    /// Ожидаем origin = spiralPoint(0) = центр карты (все meadow, water-skip не срабатывает).
    func test_FallbackToSpiralWhenNoMatchingBiome() {
        let planner = DistrictPlanner()
        let reader = MockBiomeReader(biomes: [:], defaultBiome: .meadow)

        let (origin, _) = planner.allocateNextOrigin(
            currentIndex: 0,
            biomeReader: reader,
            preferredBiomes: [.river]
        )

        let expectedOrigin = planner.spiralPoint(index: 0)
        XCTAssertEqual(origin, expectedOrigin,
            "При отсутствии .river тайлов fallback должен вернуть spiralPoint(0). Got: \(origin)")
    }

    // MARK: - testIsDeterministicForSameInputs

    /// Одинаковые входные данные → одинаковый результат (replay-safe).
    func test_IsDeterministicForSameInputs() {
        let planner = DistrictPlanner()
        let mountainPoint = planner.spiralPoint(index: 5)
        let reader = MockBiomeReader(biomes: [mountainPoint: .mountain], defaultBiome: .meadow)

        let r1 = planner.allocateNextOrigin(
            currentIndex: 0, biomeReader: reader, preferredBiomes: [.mountain])
        let r2 = planner.allocateNextOrigin(
            currentIndex: 0, biomeReader: reader, preferredBiomes: [.mountain])

        XCTAssertEqual(r1.origin, r2.origin,
            "Детерминизм: origin должен совпадать при одинаковых аргументах. r1=\(r1.origin), r2=\(r2.origin)")
        XCTAssertEqual(r1.newIndex, r2.newIndex,
            "Детерминизм: newIndex должен совпадать. r1=\(r1.newIndex), r2=\(r2.newIndex)")
    }

    // MARK: - testBiomeReaderNilFallsBackToSpiral

    /// biomeReader == nil → ignores preferredBiomes, возвращает spiralPoint(currentIndex).
    func test_BiomeReaderNilFallsBackToSpiral() {
        let planner = DistrictPlanner()
        let (origin, idx) = planner.allocateNextOrigin(
            currentIndex: 2,
            biomeReader: nil,
            preferredBiomes: [.river]
        )
        XCTAssertEqual(origin, planner.spiralPoint(index: 2),
            "biomeReader==nil: должен вернуть spiralPoint(2). Got: \(origin)")
        XCTAssertEqual(idx, 2,
            "biomeReader==nil: newIndex должен быть 2. Got: \(idx)")
    }

    // MARK: - testEmptyPreferredBiomesUsesOldBehavior

    /// preferredBiomes=[] → старое поведение (только water-skip).
    /// Карта: центр-тайл sea → spiralPoint(0) пропускается, возвращается следующий meadow.
    func test_EmptyPreferredBiomesSkipsWater() {
        let planner = DistrictPlanner()
        let seaPoint = planner.spiralPoint(index: 0)
        let nextPoint = planner.spiralPoint(index: 1)

        let reader = MockBiomeReader(biomes: [seaPoint: .sea], defaultBiome: .meadow)

        let (origin, _) = planner.allocateNextOrigin(
            currentIndex: 0,
            biomeReader: reader,
            preferredBiomes: []
        )

        XCTAssertEqual(origin, nextPoint,
            "preferredBiomes=[]: water-skip должен пропустить .sea и вернуть spiralPoint(1)=\(nextPoint). Got: \(origin)")
    }

    // MARK: - testWaterTileInPreferredBiomesIsSkipped

    /// Карта: первые 20 точек спирали = .river (isWater=true), остальные = .meadow.
    /// preferredBiomes=[.river], но .river — isWater → preferred-scan пропускает все 20.
    /// Fallback: water-skip loop пропускает первые 20 river-тайлов и находит meadow.
    /// Ожидаем: функция НЕ крашится, возвращает не-водную клетку.
    func test_WaterTileInPreferredBiomesIsSkipped() {
        let planner = DistrictPlanner()

        // Только первые 21 точек спирали = .river; остальная карта = .meadow.
        var biomeMap: [GridPoint: BiomeKind] = [:]
        for i in 0...20 {
            biomeMap[planner.spiralPoint(index: i)] = .river
        }
        let reader = MockBiomeReader(biomes: biomeMap, defaultBiome: .meadow)

        // preferred=[.river], но .river isWater → preferred-scan пропускает все → fallback на spiral.
        // water-skip loop: первые 21 = river → пропускает, возвращает spiralPoint(21) = .meadow.
        let (origin, _) = planner.allocateNextOrigin(
            currentIndex: 0,
            biomeReader: reader,
            preferredBiomes: [.river]
        )

        // Результат не должен быть водным тайлом (water-skip должен был сработать).
        let biome = reader.biome(atX: origin.x, y: origin.y)
        XCTAssertFalse(biome.isWater,
            "Возвращённый origin не должен быть водным тайлом. Got biome: \(biome), origin: \(origin)")
    }
}
