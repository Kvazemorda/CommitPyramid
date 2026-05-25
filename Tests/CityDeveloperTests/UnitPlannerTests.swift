import XCTest
@testable import CommitPyramid

final class UnitPlannerTests: XCTestCase {

    // MARK: - Константы (numeric thresholds — все собраны здесь)

    private let runSize = 100
    private let proportionTolerance = 10  // ±10% от runSize, т.е. ±10 юнитов
    private let mountainAffinityFactor: Double = 1.5
    // TASK-054 BUG-021: при largeRarityFactor=0.1 фактическое ~13 на 150 задач
    // (каталог: 17 large из 51 kinds ≈ 33%, в meadow/stage5 доступно ~13).
    // Baseline=16 даёт buffer для статистической вариации (seed=deterministic).
    private let largeMaxAbsolute: Int = 16
    private let performanceLimitSeconds: Double = 5.0

    // MARK: - Helper

    /// Симулирует размещение `taskCount` юнитов в одном квартале — последовательно
    /// вызывает `UnitPlanner.nextUnitKind` с инкрементально растущими counters,
    /// **точно** как в `CityEngine.swift:297-302`. socialCount учитывает только
    /// `.social` категорию — religious/military через socialMix в planner.pickKind
    /// «занимают» social-слот pattern, но external counter их не видит (это
    /// поведение CityEngine, тест 1:1 его репродуцирует).
    private func simulateDistrict(
        taskCount: Int,
        stage: Int,
        biome: BiomeKind?
    ) -> [UnitKind] {
        let planner = UnitPlanner()
        var result: [UnitKind] = []
        var residential = 0, wells = 0, infra = 0, production = 0, social = 0
        for idx in 1...taskCount {
            let kind = planner.nextUnitKind(
                forTaskIndex: idx, stage: stage, biome: biome,
                residentialCount: residential, wellCount: wells,
                infraCount: infra, productionCount: production,
                socialCount: social
            )
            result.append(kind)
            switch kind.category {
            case .residential:    residential += 1
            case .infrastructure:
                infra += 1
                if kind == .well { wells += 1 }
            case .production:     production += 1
            case .social:         social += 1
            case .religious, .military: break  // не считаются в counters (как CityEngine)
            }
        }
        return result
    }

    // MARK: - AC#1: Категориальные пропорции (луг, stage 5)

    func test_CategoricalProportions_MeadowStage5() {
        let kinds = simulateDistrict(taskCount: runSize, stage: 5, biome: .meadow)

        let residential   = kinds.filter { $0.category == .residential }.count
        let infrastructure = kinds.filter { $0.category == .infrastructure }.count
        let production    = kinds.filter { $0.category == .production }.count
        // socialSlot = всё, что физически попадает в social-слот pattern
        // (включая religious/military через socialMix)
        let socialSlot = kinds.filter {
            $0.category == .social || $0.category == .religious || $0.category == .military
        }.count

        assertProportion(actual: residential, expected: 50,
                         tolerance: proportionTolerance, name: "residential")
        assertProportion(actual: infrastructure, expected: 20,
                         tolerance: proportionTolerance, name: "infrastructure")
        assertProportion(actual: production, expected: 20,
                         tolerance: proportionTolerance, name: "production")
        assertProportion(actual: socialSlot, expected: 10,
                         tolerance: proportionTolerance, name: "social-slot")
    }

    private func assertProportion(actual: Int, expected: Int, tolerance: Int, name: String,
                                  file: StaticString = #file, line: UInt = #line) {
        let lower = expected - tolerance
        let upper = expected + tolerance
        XCTAssertGreaterThanOrEqual(actual, lower,
            "Категория \(name): фактически \(actual), ожидается ≥ \(lower)",
            file: file, line: line)
        XCTAssertLessThanOrEqual(actual, upper,
            "Категория \(name): фактически \(actual), ожидается ≤ \(upper)",
            file: file, line: line)
    }

    // MARK: - AC#2: minStage (stage=0 не должно быть minStage>0)

    func test_MinStage_NoHighStageKindsAppearAtStageZero() {
        let kinds = simulateDistrict(taskCount: runSize, stage: 0, biome: .meadow)

        for kind in kinds {
            XCTAssertEqual(kind.minStage, 0,
                "На stage=0 не должно быть юнитов с minStage > 0, получен: \(kind) (minStage=\(kind.minStage))")
        }
    }

    // MARK: - AC#3: Biome-аффинитет (горы vs луг)

    func test_BiomeAffinity_MountainBoostsStoneKinds() {
        let stoneKinds: Set<UnitKind> = [.stoneHouse, .forge, .quarry, .mine]

        let mountainRun = simulateDistrict(taskCount: runSize, stage: 5, biome: .mountain)
        let meadowRun = simulateDistrict(taskCount: runSize, stage: 5, biome: .meadow)

        let mountainCount = mountainRun.filter { stoneKinds.contains($0) }.count
        let meadowCount = meadowRun.filter { stoneKinds.contains($0) }.count

        // Защита от деления на 0: если на лугу 0 — требуем хотя бы 2 на горах
        let threshold = mountainAffinityFactor * Double(max(meadowCount, 1))
        XCTAssertGreaterThanOrEqual(Double(mountainCount), threshold,
            "Mountain stone-kinds: \(mountainCount), Meadow: \(meadowCount), " +
            "ratio expected ≥ \(mountainAffinityFactor)× (threshold=\(threshold))")
    }

    // MARK: - AC#4: Детерминизм

    func test_Determinism_SameInputsProduceSameOutput() {
        let run1 = simulateDistrict(taskCount: runSize, stage: 5, biome: .meadow)
        let run2 = simulateDistrict(taskCount: runSize, stage: 5, biome: .meadow)

        XCTAssertEqual(run1, run2,
            "Два прогона с одинаковыми входами должны давать идентичный список юнитов")
    }

    // MARK: - AC#5: Performance (< 5 сек на 100 задачах)

    func test_Performance_HundredTasksUnderFiveSeconds() {
        let start = Date()
        _ = simulateDistrict(taskCount: runSize, stage: 5, biome: .meadow)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, performanceLimitSeconds,
            "100 задач должны планироваться за < \(performanceLimitSeconds) сек, заняло \(elapsed) сек")
    }

    // MARK: - Edge case 1: море — хотя бы 1 «водяной» юнит

    func test_EdgeCase_SeaBiomeProducesAtLeastOneWaterKind() {
        // Сужено до infrastructure/production sea-kinds:
        // lighthouse имеет large=true (planner ставит редко) и minStage=3 OK на 5,
        // shipyard — .military, попадает в pattern только при socialCount % 16 == 15.
        // Pier (infra, 20 слотов) и fishingPier (production, 20 слотов) — надёжные.
        let seaKinds: Set<UnitKind> = [.pier, .fishingPier]

        let run = simulateDistrict(taskCount: runSize, stage: 5, biome: .sea)
        let count = run.filter { seaKinds.contains($0) }.count

        XCTAssertGreaterThanOrEqual(count, 1,
            "В биоме «море» за \(runSize) задач должен появиться хотя бы 1 pier/fishingPier")
    }

    // MARK: - Edge case 2: пустыня + stage 0 — не падает, есть базовые kinds

    func test_EdgeCase_DesertStageZeroSurvivesAndProducesBaseKinds() {
        let run = simulateDistrict(taskCount: runSize, stage: 0, biome: .desert)

        XCTAssertEqual(run.count, runSize,
            "Планировщик должен вернуть ровно \(runSize) юнитов, не упасть")

        // cistern исключён: у неё minStage=2, на stage=0 отфильтрована.
        let baseKinds: Set<UnitKind> = [.dugout, .shack, .well]
        XCTAssertTrue(run.contains(where: { baseKinds.contains($0) }),
            "На пустыне + stage 0 ожидается хотя бы 1 dugout/shack/well")
    }

    // MARK: - Edge case 3: nil-биом — распределение совпадает с F-07

    func test_EdgeCase_NilBiomeFollowsF07Proportions() {
        let kinds = simulateDistrict(taskCount: runSize, stage: 5, biome: nil)

        let residential   = kinds.filter { $0.category == .residential }.count
        let infrastructure = kinds.filter { $0.category == .infrastructure }.count
        let production    = kinds.filter { $0.category == .production }.count
        let socialSlot = kinds.filter {
            $0.category == .social || $0.category == .religious || $0.category == .military
        }.count

        assertProportion(actual: residential, expected: 50,
                         tolerance: proportionTolerance, name: "residential (nil-biome)")
        assertProportion(actual: infrastructure, expected: 20,
                         tolerance: proportionTolerance, name: "infrastructure (nil-biome)")
        assertProportion(actual: production, expected: 20,
                         tolerance: proportionTolerance, name: "production (nil-biome)")
        assertProportion(actual: socialSlot, expected: 10,
                         tolerance: proportionTolerance, name: "social-slot (nil-biome)")
    }

    // MARK: - Edge case 4: large-юниты редкие (baseline guard, см. BUG-021)

    func test_EdgeCase_LargeUnitsAppearRarely() {
        let bigSize = 150
        let bigRun = simulateDistrict(taskCount: bigSize, stage: 5, biome: .meadow)

        let largeCount = bigRun.filter { $0.large }.count

        // TASK-054 BUG-021: largeRarityFactor=0.1 в weightedPick. Фактическое ~13
        // на 150 задач из meadow stage 5 (каталог: 17 large из 51 kinds ≈ 33%,
        // в meadow/stage5 доступно ~13). Baseline=16 — буфер для статвариации.
        XCTAssertLessThanOrEqual(largeCount, largeMaxAbsolute,
            "Large-юниты (TASK-054 BUG-021): для \(bigSize) задач " +
            "baseline ≤ \(largeMaxAbsolute), получено \(largeCount). " +
            "largeRarityFactor=0.1 в weightedPick снижает выбор large ~10×.")
    }
}
