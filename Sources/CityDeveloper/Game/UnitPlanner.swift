import Foundation

// MARK: - UnitPlanner (TASK-035: biome-aware, 5-шаговый алгоритм)
//
// Реализует F-16: выбор юнита с учётом биома, minStage, эволюционных корней и terrain-весов.
// Алгоритм: pattern → category → minStage-filter → evolution-roots-cut → weighted sample.
// Replay-инвариант: seed = FNV-1a(idx, category, biome) → SplitMix64 → weighted pick.

struct UnitPlanner {

    // MARK: - Категориальный паттерн (F-07)
    // 20 слотов: R=10, I=4, P=4, S=2 → 50/20/20/10%.
    // slot: 1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20
    //       R  I  R  P  R  R  S  I  R  P   R  I  R  R  P  I  R  S  R  P
    private static let categoryPattern: [UnitCategory] = [
        .residential, .infrastructure, .residential, .production, .residential,
        .residential, .social, .infrastructure, .residential, .production,
        .residential, .infrastructure, .residential, .residential, .production,
        .infrastructure, .residential, .social, .residential, .production,
    ]

    // MARK: - Social mix: religious/military подкатегории (Plan-review Sonnet)
    // Период 16: [0..6] = social, [7] = religious, [8..14] = social, [15] = military.
    // Religious = 1/16 = 6.25%, military = 1/16 = 6.25%, social = 14/16 = 87.5% → итого 12.5% ≤ AC 15%.
    private enum SocialMix {
        static let period: Int = 16
        static let religiousSlot: Int = 7   // socialCount % period == religiousSlot → religious
        static let militarySlot: Int = 15   // socialCount % period == militarySlot  → military
    }

    // MARK: - Формула веса (F-15, AC «≥ 2× при terrain-аффинитете»)
    // w(k) = baseUniform + terrainBoost * terrainWeight(k, biome)
    // baseUniform ≈ 0.15 (15% «неожиданность» из F-15), terrainBoost ≈ 0.85.
    // При terrainWeight = 1.0: w = 1.0 (preferred). При weight = 0.15: w ≈ 0.2775.
    // Ratio preferred/unexpected ≈ 1.0/0.2775 ≈ 3.6× → удовлетворяет AC «≥ 2×».
    private static let baseUniform:   Double = 0.15
    private static let terrainBoost:  Double = 0.85

    // MARK: - Кэш юнитов по категории (один раз, static lazy)
    // O(50) фильтрация вынесена из hot path.
    private static let unitsByCategory: [UnitCategory: [UnitKind]] = {
        var result: [UnitCategory: [UnitKind]] = [:]
        for kind in UnitKind.allCases {
            let cat = kind.category
            result[cat, default: []].append(kind)
        }
        return result
    }()

    // MARK: - Evolution targets (шаг 4)
    // Юниты, которые появляются ТОЛЬКО через TASK-034 (evolution), а не через планировщик.
    // Планировщик ставит только «корни» (roots) и non-evolution юниты.
    // Целевые формы (targets) исключены из sample — они появляются через applyEvolutionsIfReady.
    // TODO TASK-034: при мерже TASK-034 заменить на EvolutionTable.targets.
    private static let evolutionTargets: Set<UnitKind> = [
        .shack,          // dugout → shack
        .hut,            // shack → hut
        .house,          // hut → house
        .twoStoryHouse,  // farmHouse → twoStoryHouse
        .stoneHouse,     // house → stoneHouse
        .townhouse,      // twoStoryHouse → townhouse
        .largeWarehouse, // warehouse → largeWarehouse
    ]

    // MARK: - Однократное логирование edge cases (без флуда)
    private static let logLock = NSLock()
    private static var loggedEmptyCategories: Set<UnitCategory> = []

    // MARK: - Публичный API

    /// Выбрать тип юнита для следующего задания в проекте (biome-aware, F-16).
    ///
    /// - Parameters:
    ///   - idx:             1-based taskCount (уже инкрементирован в CityEngine).
    ///   - stage:           текущий stage квартала.
    ///   - biome:           биом клетки квартала (nil → равномерный вес для всех, back-compat F-07).
    ///   - residentialCount: фактическое число жилых юнитов проекта до этого задания.
    ///   - wellCount:       фактическое число колодцев проекта до этого задания.
    ///   - infraCount:      фактическое число infra-юнитов (включая well и road).
    ///   - productionCount: фактическое число production-юнитов.
    ///   - socialCount:     фактическое число social-юнитов.
    func nextUnitKind(
        forTaskIndex idx: Int,
        stage: Int,
        biome: BiomeKind? = nil,
        residentialCount: Int,
        wellCount: Int,
        infraCount: Int,
        productionCount: Int,
        socialCount: Int
    ) -> UnitKind {

        // BUG-010: первый юнит квартала всегда road — фундамент.
        // idx — 1-based taskCount; idx == 1 означает самый первый юнит нового проекта.
        // Без этого правила road выпадал случайно по category-pattern,
        // и кварталы могли вырасти «в чистом поле» без дороги.
        if idx == 1 {
            return .road
        }

        // ── Шаг 1: Pick category по слоту (F-07 pattern) ──
        let baseCategory = Self.categoryPattern[(idx - 1) % Self.categoryPattern.count]

        // Well soft-guard (F-07): при residentialCount >= 5*(wellCount+1) и слот residential
        // подменяем на well (срабатывает только при изменённом pattern — в базовом rotation никогда).
        if baseCategory == .residential && residentialCount >= 5 * (wellCount + 1) {
            return .well
        }

        // Social mix: религиозная/военная подкатегория «откусываются» из social-слотов.
        let category: UnitCategory
        if baseCategory == .social {
            let slot = socialCount % SocialMix.period
            if slot == SocialMix.religiousSlot {
                category = .religious
            } else if slot == SocialMix.militarySlot {
                category = .military
            } else {
                category = .social
            }
        } else {
            category = baseCategory
        }

        return pickKind(
            in: category,
            taskIndex: idx,
            stage: stage,
            biome: biome,
            infraCount: infraCount,
            productionCount: productionCount,
            socialCount: socialCount
        )
    }

    // MARK: - Private: 5-шаговый pickKind

    private func pickKind(
        in requestedCategory: UnitCategory,
        taskIndex idx: Int,
        stage: Int,
        biome: BiomeKind?,
        infraCount: Int,
        productionCount: Int,
        socialCount: Int
    ) -> UnitKind {

        // ── Шаг 2: Получить candidates категории (из кэша) ──
        var candidates = Self.unitsByCategory[requestedCategory] ?? []

        // ── Шаг 3: Фильтр по minStage ──
        let filtered = candidates.filter { $0.minStage <= stage }

        // Edge case: категория пуста после minStage-фильтра → деградировать + логировать.
        if filtered.isEmpty {
            logEmptyCategoryOnce(requestedCategory)
            return degradeFallback(from: requestedCategory, stage: stage, biome: biome, taskIndex: idx)
        }
        candidates = filtered

        // ── Шаг 4: Отсечь evolution-targets (планировщик ставит только «корни») ──
        // Исключаем только те targets, которые имеют альтернативы в текущей категории.
        // Если после отсечения кандидатов не останется — оставляем целевые формы (corner case: stage < 2).
        let withoutTargets = candidates.filter { !Self.evolutionTargets.contains($0) }
        if !withoutTargets.isEmpty {
            candidates = withoutTargets
        }
        // Если withoutTargets пуст — candidates остаётся без изменений (все roots — targets, не случается в нормальном каталоге).

        // ── Шаг 5: Взвешенный детерминированный sample ──
        return weightedPick(from: candidates, biome: biome, taskIndex: idx, category: requestedCategory)
    }

    // MARK: - Weighted Sample (Шаг 5)

    private func weightedPick(
        from candidates: [UnitKind],
        biome: BiomeKind?,
        taskIndex idx: Int,
        category: UnitCategory
    ) -> UnitKind {
        guard !candidates.isEmpty else { return .well }
        if candidates.count == 1 { return candidates[0] }

        // Вычислить веса.
        let weights: [Double]
        if let biome = biome {
            weights = candidates.map { kind in
                let tw = TerrainAffinity.weight(for: kind, in: biome)
                return Self.baseUniform + Self.terrainBoost * tw
            }
        } else {
            // biome == nil → uniform (back-compat F-07: w = 1.0 для всех)
            weights = Array(repeating: 1.0, count: candidates.count)
        }

        let sum = weights.reduce(0, +)

        // Edge case: все веса == 0 → равномерный sample.
        if sum <= 0 {
            var rng = SplitMix64(seed: seedFor(taskIndex: idx, category: category, biome: biome))
            let idx2 = Int(rng.next() % UInt64(candidates.count))
            return candidates[idx2]
        }

        // SplitMix64 seed от (taskIndex, category, biome) — детерминирован, без глобального состояния.
        var rng = SplitMix64(seed: seedFor(taskIndex: idx, category: category, biome: biome))
        let r = rng.nextUnit() * sum

        var acc = 0.0
        for (kind, w) in zip(candidates, weights) {
            acc += w
            if r < acc { return kind }
        }
        return candidates.last!  // floating-point safety: если r == sum
    }

    // MARK: - Seed

    private func seedFor(taskIndex: Int, category: UnitCategory, biome: BiomeKind?) -> UInt64 {
        fnv1a(combining: [
            String(taskIndex),
            category.rawValue,
            biome?.rawValue ?? "nil"
        ])
    }

    // MARK: - Fallback деградация (edge case: пустая категория после minStage)

    private func degradeFallback(
        from category: UnitCategory,
        stage: Int,
        biome: BiomeKind?,
        taskIndex idx: Int
    ) -> UnitKind {
        // Деградация: social → infrastructure → residential → .well (абсолютный fallback).
        let degradeOrder: [UnitCategory] = [.infrastructure, .residential]
        let startFrom: [UnitCategory]
        switch category {
        case .social, .religious, .military:
            startFrom = degradeOrder
        case .production:
            startFrom = degradeOrder
        case .infrastructure:
            startFrom = [.residential]
        case .residential:
            startFrom = []
        }

        for fallbackCategory in startFrom {
            let pool = (Self.unitsByCategory[fallbackCategory] ?? []).filter { $0.minStage <= stage }
            if !pool.isEmpty {
                return weightedPick(from: pool, biome: biome, taskIndex: idx, category: fallbackCategory)
            }
        }
        return .well
    }

    // MARK: - Logging (однократный)

    private func logEmptyCategoryOnce(_ category: UnitCategory) {
        Self.logLock.lock()
        defer { Self.logLock.unlock() }
        guard !Self.loggedEmptyCategories.contains(category) else { return }
        Self.loggedEmptyCategories.insert(category)
        ErrorsLog.write("UnitPlanner: no candidates for category .\(category.rawValue) after minStage-filter — degrading to fallback")
    }

    // MARK: - nextPosition (без изменений)

    func nextPosition(origin: GridPoint, taskIndex: Int) -> GridPoint {
        // Кольцевое размещение вокруг центра квартала: по 8 юнитов на кольце.
        let i = taskIndex - 1
        if i == 0 { return origin }
        let ring = (i - 1) / 8 + 1
        let slot = (i - 1) % 8
        let offsets: [(Int, Int)] = [
            (1, 0), (1, 1), (0, 1), (-1, 1),
            (-1, 0), (-1, -1), (0, -1), (1, -1),
        ]
        let (dx, dy) = offsets[slot]
        return GridPoint(x: origin.x + dx * ring, y: origin.y + dy * ring)
    }
}
