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

    // MARK: - TASK-054 BUG-021: Large rarity factor
    /// TASK-054 BUG-021: множитель редкости для large-юнитов (флаг kind.large
    /// в каталоге) в weightedPick. Эволюционный канал (EvolutionGraph) не задействован.
    private static let largeRarityFactor: Double = 0.1

    /// TASK-054: критерий large — явный флаг kind.large в каталоге (не size).
    /// Намеренно: 16 kinds имеют size>=2×2 но large=false (farmhouse, market,
    /// mill) — для них планировщик НЕ применяет множитель.
    private static func isLarge(_ kind: UnitKind) -> Bool {
        return kind.large
    }

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

        // Дорогами теперь занимается RoadNetwork: пока план кольца квартала не построен —
        // CityEngine сам выбирает .road и не вызывает этот метод. Здесь — только здания.

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
        var weights: [Double]
        if let biome = biome {
            weights = candidates.map { kind in
                let tw = TerrainAffinity.weight(for: kind, in: biome)
                return Self.baseUniform + Self.terrainBoost * tw
            }
        } else {
            // biome == nil → uniform (back-compat F-07: w = 1.0 для всех)
            weights = Array(repeating: 1.0, count: candidates.count)
        }

        // TASK-054 BUG-021: large-юниты редкие — множитель применяется ПОСЛЕ
        // biome-аффинитета, чтобы не ломать пропорции категорий.
        for i in 0..<candidates.count {
            if Self.isLarge(candidates[i]) {
                weights[i] *= Self.largeRarityFactor
            }
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

    // MARK: - nextPosition

    /// Размещение очередного НЕ-дорожного юнита (здания).
    ///
    /// - Parameters:
    ///   - origin: центр квартала.
    ///   - buildingIndex: 0-based индекс здания внутри проекта (CityEngine считает: taskCount - planLength - 1).
    ///   - roadCells: уже построенные клетки сети (магистраль + кольца кварталов).
    ///                Используется для anchor-точек (стой рядом с дорогой) и overlap-проверки.
    ///   - builtCells: клетки, уже занятые зданиями этого (и соседних) кварталов.
    ///                 Используется для overlap-проверки зданий между собой.
    ///   - unitSize: footprint здания в тайлах (W×H).
    ///
    /// Алгоритм (TASK-041):
    /// 1. Если roadCells пуст — legacy-кольцо вокруг origin (ограниченное radius=3).
    /// 2. Иначе собираем все свободные (non-blocked) кандидаты: depth ∈ 1...5, anchor ∈ nearby, side ∈ [+1,-1].
    /// 3. Если кандидатов нет — возвращаем nil (CityEngine добавит петлю и повторит).
    /// 4. Детерминировано выбираем: candidates[i % candidates.count].
    func nextPosition(
        origin: GridPoint,
        buildingIndex: Int,
        roadCells: Set<GridPoint>,
        builtCells: Set<GridPoint>,
        unitSize: GridSize = GridSize(width: 1, height: 1),
        template: DistrictTemplate? = nil,
        kind: UnitKind? = nil,
        projectEraLevel: Int,
        otherProjectCells: Set<GridPoint> = []
    ) -> GridPoint? {
        // TASK-048c F-25: slot-based placement for templated districts.
        if let t = template, let k = kind {
            let targetRole = k.preferredSlotRole
            let sorted = t.slots
                .filter { $0.role == targetRole && $0.minEra <= projectEraLevel }
                .sorted { ($0.y, $0.x) < ($1.y, $1.x) }
            for slot in sorted {
                // Check occupancy: intersection of slot footprint with builtCells.
                // TASK-056 BUG-022: также пропускаем слот, если он пересекается с
                // клеткой другого проекта (hard-block для cross-project overlap).
                var occupied = false
                outer: for dx in 0..<slot.footprint.width {
                    for dy in 0..<slot.footprint.height {
                        let cell = GridPoint(
                            x: origin.x + slot.x + dx,
                            y: origin.y + slot.y + dy)
                        if builtCells.contains(cell) { occupied = true; break outer }
                        if otherProjectCells.contains(cell) { occupied = true; break outer }
                    }
                }
                if !occupied {
                    return GridPoint(x: origin.x + slot.x, y: origin.y + slot.y)
                }
            }
            return nil  // exhausted — CityEngine will fall back to legacy
        }

        let i = max(0, buildingIndex)

        // Fallback: legacy-кольцо вокруг origin (если карты дорог нет).
        // TASK-056: legacyRingPosition не учитывает otherProjectCells (детерминированная
        // формула без поиска). Используется только при roadCells.isEmpty (самый ранний
        // юнит проекта в pre-mainRoad сценарии) — в этой ситуации otherProjectCells
        // также пуст (никакой другой проект ещё не разместил юнит без дорог).
        if roadCells.isEmpty {
            return legacyRingPosition(origin: origin, i: i, unitSize: unitSize)
        }

        // Только дороги «своего» квартала: внутри окна ±halfSide от origin.
        // Это branch + ring; магистраль (далеко) сюда не попадёт.
        let halfSide = 4
        let nearby = roadCells.filter {
            abs($0.x - origin.x) <= halfSide && abs($0.y - origin.y) <= halfSide
        }.sorted {
            // Детерминированный порядок по (y, x).
            if $0.y != $1.y { return $0.y < $1.y }
            return $0.x < $1.x
        }

        if nearby.isEmpty {
            return legacyRingPosition(origin: origin, i: i, unitSize: unitSize)
        }

        // BUG-017/018: ТОЛЬКО depth=1 от anchor — гарантирует, что front-edge
        // здания касается дороги. Плюс мы пробуем ВСЕ 4 кардинальных направления
        // (не только perpendicular axis), чтобы здание могло «прислониться»
        // любой стороной. Плюс пробуем разные origin-углы footprint'а NxM
        // (anchor может быть с любой стороны здания, а не только перед его
        // нижне-левым углом).
        //
        // Для здания W×H анкорная клетка road может находиться с любой из 4 сторон:
        //   - снизу (anchor.y = pos.y - 1)  → pos = (anchor.x - dx, anchor.y + 1), dx ∈ 0..<W
        //   - сверху (anchor.y = pos.y + H) → pos = (anchor.x - dx, anchor.y - H), dx ∈ 0..<W
        //   - слева  (anchor.x = pos.x - 1) → pos = (anchor.x + 1, anchor.y - dy), dy ∈ 0..<H
        //   - справа (anchor.x = pos.x + W) → pos = (anchor.x - W, anchor.y - dy), dy ∈ 0..<H
        //
        // Для каждого варианта footprintBlocked отсеивает overlap с дорогой/застройкой.
        // Дополнительно footprintAdjacentToRoad(пов) подтверждает требование adjacency.
        let W = unitSize.width
        let H = unitSize.height
        var candidates: [GridPoint] = []
        var seen = Set<GridPoint>()
        for anchor in nearby {
            // anchor снизу: pos.y = anchor.y + 1, pos.x варьируем
            for dx in 0..<W {
                let pos = GridPoint(x: anchor.x - dx, y: anchor.y + 1)
                if seen.insert(pos).inserted { append(&candidates, pos, size: unitSize, roads: roadCells, built: builtCells, otherProjectCells: otherProjectCells) }
            }
            // anchor сверху: pos.y = anchor.y - H, pos.x варьируем
            for dx in 0..<W {
                let pos = GridPoint(x: anchor.x - dx, y: anchor.y - H)
                if seen.insert(pos).inserted { append(&candidates, pos, size: unitSize, roads: roadCells, built: builtCells, otherProjectCells: otherProjectCells) }
            }
            // anchor слева: pos.x = anchor.x + 1, pos.y варьируем
            for dy in 0..<H {
                let pos = GridPoint(x: anchor.x + 1, y: anchor.y - dy)
                if seen.insert(pos).inserted { append(&candidates, pos, size: unitSize, roads: roadCells, built: builtCells, otherProjectCells: otherProjectCells) }
            }
            // anchor справа: pos.x = anchor.x - W, pos.y варьируем
            for dy in 0..<H {
                let pos = GridPoint(x: anchor.x - W, y: anchor.y - dy)
                if seen.insert(pos).inserted { append(&candidates, pos, size: unitSize, roads: roadCells, built: builtCells, otherProjectCells: otherProjectCells) }
            }
        }

        // Нет свободных мест — сигнализируем CityEngine добавить петлю.
        if candidates.isEmpty { return nil }

        // Детерминированный выбор: i-й кандидат по кругу (не выходим за пределы петель).
        return candidates[i % candidates.count]
    }

    /// Добавляет position в candidates, если footprint не блокирован (overlap с
    /// дорогой/застройкой/чужим проектом) И касается дороги хотя бы одной стороной.
    /// Inline helper для уменьшения дублирования в nextPosition.
    private func append(_ candidates: inout [GridPoint], _ pos: GridPoint,
                        size: GridSize, roads: Set<GridPoint>, built: Set<GridPoint>,
                        otherProjectCells: Set<GridPoint> = []) {
        if footprintBlocked(at: pos, size: size, roads: roads, built: built,
                            otherProjectCells: otherProjectCells) { return }
        if !footprintAdjacentToRoad(at: pos, size: size, roads: roads) { return }
        candidates.append(pos)
    }

    /// BUG-017: проверяет, что хотя бы одна клетка footprint'а смежна (4-cardinal)
    /// с road-клеткой. Без этой проверки здания могут «висеть в воздухе» вдали от дорог.
    private func footprintAdjacentToRoad(at pos: GridPoint, size: GridSize, roads: Set<GridPoint>) -> Bool {
        for dx in 0..<size.width {
            for dy in 0..<size.height {
                let cell = GridPoint(x: pos.x + dx, y: pos.y + dy)
                if roads.contains(GridPoint(x: cell.x - 1, y: cell.y)) { return true }
                if roads.contains(GridPoint(x: cell.x + 1, y: cell.y)) { return true }
                if roads.contains(GridPoint(x: cell.x, y: cell.y - 1)) { return true }
                if roads.contains(GridPoint(x: cell.x, y: cell.y + 1)) { return true }
            }
        }
        return false
    }

    /// Перпендикулярная ось от road-клетки.
    /// Смотрим 4 кардинальных соседа: если road-сосед слева/справа → дорога горизонтальная, perp = (0,±1).
    /// Если сверху/снизу → дорога вертикальная, perp = (±1, 0).
    private func perpendicularAxis(at cell: GridPoint, roads: Set<GridPoint>) -> (dx: Int, dy: Int) {
        let hasLeft  = roads.contains(GridPoint(x: cell.x - 1, y: cell.y))
        let hasRight = roads.contains(GridPoint(x: cell.x + 1, y: cell.y))
        let hasDown  = roads.contains(GridPoint(x: cell.x, y: cell.y - 1))
        let hasUp    = roads.contains(GridPoint(x: cell.x, y: cell.y + 1))
        let horiz = (hasLeft ? 1 : 0) + (hasRight ? 1 : 0)
        let vert  = (hasDown ? 1 : 0) + (hasUp ? 1 : 0)
        if horiz >= vert {
            return (0, 1)   // road горизонтальная → perp по Y
        } else {
            return (1, 0)   // road вертикальная → perp по X
        }
    }

    /// Проверяет, заблокирован ли footprint W×H — перекрывается с дорогой, занятым
    /// зданием или клеткой другого проекта (TASK-056 BUG-022).
    private func footprintBlocked(
        at pos: GridPoint, size: GridSize,
        roads: Set<GridPoint>, built: Set<GridPoint>,
        otherProjectCells: Set<GridPoint> = []
    ) -> Bool {
        for dx in 0..<size.width {
            for dy in 0..<size.height {
                let p = GridPoint(x: pos.x + dx, y: pos.y + dy)
                if roads.contains(p) || built.contains(p) { return true }
                if otherProjectCells.contains(p) { return true }
            }
        }
        return false
    }

    /// Legacy-кольцо вокруг origin (только при пустой roadCells).
    /// Ограничено radius=3 (max 24 здания через ring).
    private func legacyRingPosition(origin: GridPoint, i: Int, unitSize: GridSize) -> GridPoint {
        let ring = min(i / 8 + 1, 3)
        let slot = i % 8
        let offsets: [(Int, Int)] = [
            (1, 0), (1, 1), (0, 1), (-1, 1),
            (-1, 0), (-1, -1), (0, -1), (1, -1),
        ]
        let (dx, dy) = offsets[slot]
        return GridPoint(x: origin.x + dx * ring, y: origin.y + dy * ring)
    }
}
