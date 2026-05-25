import Foundation

// MARK: - BiomeMap

/// Карта биомов: плоский row-major массив BiomeKind, parallel к NoiseMap.
/// Индексация: cells[y * width + x].
struct BiomeMap {
    let width: Int
    let height: Int
    /// Row-major, индекс = y * width + x.
    let cells: [BiomeKind]

    /// Возвращает биом клетки (x, y).
    /// Координаты вне диапазона → .meadow (edge case EC, TASK-027).
    func at(x: Int, y: Int) -> BiomeKind {
        guard x >= 0, x < width, y >= 0, y < height else { return .meadow }
        return cells[y * width + x]
    }
}

// MARK: - BiomeClassifierError

enum BiomeClassifierError: Error {
    case sizeMismatch
    case insufficientDiversity(found: Int, dominantShare: Double)
}

// MARK: - ClassificationOutcome

/// TASK-057 F-15: метаданные классификации, возвращаемые `classify(world:strict:)`.
/// Используется WorldMapProvider для retry-логики на «несбалансированных» seed'ах.
struct ClassificationOutcome {
    /// Сама биомная карта.
    let map: BiomeMap
    /// Распределение биомов: `BiomeKind → count` (только присутствующие).
    let distribution: [BiomeKind: Int]
    /// Общее число клеток (= width × height).
    let total: Int
    /// Максимальная доля одного биома (0…1).
    let dominantShare: Double
    /// Число неводных биомов из {meadow, desert, forest, mountain, stone},
    /// у которых доля ≥ `BiomeClassifier.minBiomeShare`.
    let nonWaterAboveThreshold: Int
    /// `≥1 клетка` sea присутствует (информационно, НЕ влияет на `balanced`).
    let seaPresent: Bool
    /// `dominantShare ≤ maxDominantShare && nonWaterAboveThreshold ≥ minDiversity`.
    let balanced: Bool
}

// MARK: - BiomeClassifier

/// Детерминированный классификатор: NoiseMap → BiomeMap.
/// Pure-функция: никакого глобального состояния, Date(), random.
struct BiomeClassifier {

    // MARK: - Константы

    /// Минимальная связная площадь моря (клеток). Меньше — «лужа», сглаживается.
    static let minSeaArea: Int = 8

    /// Минимальное число неводных биомов из {meadow, desert, forest, mountain, stone}
    /// с долей ≥ `minBiomeShare`. TASK-057: снижено с 6 до 4 (5 неводных минус
    /// 1 допустимый «провал», например stone в жарких seed'ах).
    static let minDiversity: Int = 4

    /// Максимальная доля доминирующего биома. Море теперь — компактный блоб (<5% карты),
    /// доминировать будут луга/леса. 0.55 запаса достаточно для типичного шум-сида.
    static let maxDominantShare: Double = 0.55

    /// Минимальная доля каждого биома (BUG-008: цель ≥5%).
    static let minBiomeShare: Double = 0.05

    /// Базовый радиус морского блоба в долях стороны карты.
    /// 0.22 при W=256 → r≈56 (≈9.5% площади до клампа углами). При W=16 → r≈3.5.
    static let seaBlobRadiusFraction: Double = 0.22

    /// Минимальный радиус морского блоба в тайлах — гарантирует ≥ minSeaArea клеток.
    static let seaBlobMinRadius: Double = 4.0

    /// Центр морского блоба в нормализованных grid-координатах (nx, ny ∈ [0,1]).
    /// (0.85, 0.05) — у RIGHT-вершины ромба, в нижне-правом углу экрана.
    /// Радиус (≈ W·0.22 = 56 при W=256) даёт блоб, который растекается ВДОЛЬ
    /// нижне-правого ребра (BOTTOM↔RIGHT) и не доходит по gy до магистрали (gy=W/2=128).
    static let seaBlobCenter: (nx: Double, ny: Double) = (0.85, 0.05)

    // MARK: - Публичный API

    /// Классифицирует NoiseMap в BiomeMap (strict-режим, back-compat обёртка).
    /// - Throws: `BiomeClassifierError.sizeMismatch` если поля NoiseMap не согласованы.
    ///           `BiomeClassifierError.insufficientDiversity` если набор биомов
    ///            не сбалансирован (см. `ClassificationOutcome.balanced`).
    static func classify(world: NoiseMap) throws -> BiomeMap {
        try classify(world: world, strict: true).map
    }

    /// TASK-057 F-15: классифицирует NoiseMap, возвращает полную метадату.
    /// - Parameter strict: при `true` бросает `insufficientDiversity` если не balanced;
    ///   при `false` — никогда не бросает `insufficientDiversity` (но пишет WARN
    ///   в `ErrorsLog` и возвращает outcome с `balanced=false`).
    ///   `sizeMismatch` бросается всегда — это сломанные входные данные.
    static func classify(world: NoiseMap, strict: Bool) throws -> ClassificationOutcome {
        let n = world.size * world.size
        guard world.height.count == n,
              world.temperature.count == n,
              world.humidity.count == n else {
            throw BiomeClassifierError.sizeMismatch
        }

        let W = world.size
        let H = world.size

        // 1. Квантильные пороги
        let thresholds = computeThresholds(world: world)

        // 2. Базовая классификация суши (один проход O(N))
        var cells = classifyLand(world: world, W: W, thresholds: thresholds)

        // 3. Разметить море flood-fill + сгладить «лужи»
        markSea(cells: &cells, W: W, H: H, seaThreshold: thresholds.seaLevel, world: world)

        // 4. Подсчёт распределения и формирование outcome.
        let total = W * H
        var distribution: [BiomeKind: Int] = [:]
        for b in cells { distribution[b, default: 0] += 1 }
        let dominantCount = distribution.values.max() ?? 0
        let dominantShare = Double(dominantCount) / Double(total)

        let nonWaterKinds: [BiomeKind] = [.meadow, .desert, .forest, .mountain, .stone]
        let nonWaterAboveThreshold = nonWaterKinds.reduce(into: 0) { acc, kind in
            let share = Double(distribution[kind] ?? 0) / Double(total)
            if share >= minBiomeShare { acc += 1 }
        }

        let seaPresent = (distribution[.sea] ?? 0) > 0
        let balanced = dominantShare <= maxDominantShare
            && nonWaterAboveThreshold >= minDiversity

        let outcome = ClassificationOutcome(
            map: BiomeMap(width: W, height: H, cells: cells),
            distribution: distribution,
            total: total,
            dominantShare: dominantShare,
            nonWaterAboveThreshold: nonWaterAboveThreshold,
            seaPresent: seaPresent,
            balanced: balanced
        )

        // 5. Проверить разнообразие (логи + опциональный throw).
        try validateDiversity(outcome: outcome, strict: strict)

        return outcome
    }

    // MARK: - Внутренние структуры

    private struct Thresholds {
        let seaLevel: Float      // высота ниже → кандидат в море
        let mountainLevel: Float // высота выше → горы
        let stoneLevel: Float    // высота выше → камни (предгорье)
        let hotTemp: Float       // температура выше → жарко
        let coldTemp: Float      // температура ниже → холодно
        let dryHumidity: Float   // влажность ниже → сухо
        let wetHumidity: Float   // влажность выше → влажно
    }

    // MARK: - Шаг 1: квантильные пороги

    /// Считает пороги по квантилям, чтобы даже «плоский» seed дал ≥ 4 биома.
    /// BUG-008: пороги пересмотрены так, чтобы каждый из 7 биомов занимал ≥5% карты.
    private static func computeThresholds(world: NoiseMap) -> Thresholds {
        let sortedH = world.height.sorted()
        let sortedT = world.temperature.sorted()
        let sortedM = world.humidity.sorted()
        let n = sortedH.count

        // Море — bottom 30% высоты (чуть выше для чёткой береговой линии, BUG-008)
        let seaLevel      = quantile(sorted: sortedH, p: 0.30)
        // Камни — top 20% высоты (предгорье)
        let stoneLevel    = quantile(sorted: sortedH, p: 0.80)
        // Горы — top 10% высоты
        let mountainLevel = quantile(sorted: sortedH, p: 0.90)

        // Жарко — top 50% температуры (медиана; даёт больше клеток под desert/savanna)
        let hotTemp       = quantile(sorted: sortedT, p: 0.50)
        // Холодно — bottom 20% температуры (tundra → .stone biome)
        let coldTemp      = quantile(sorted: sortedT, p: 0.20)

        // Сухо — bottom 50% влажности (медиана; делает desert заметнее)
        let dryHumidity   = quantile(sorted: sortedM, p: 0.50)
        // Влажно — top 40% влажности
        let wetHumidity   = quantile(sorted: sortedM, p: 0.60)

        _ = n

        return Thresholds(
            seaLevel: seaLevel,
            mountainLevel: mountainLevel,
            stoneLevel: stoneLevel,
            hotTemp: hotTemp,
            coldTemp: coldTemp,
            dryHumidity: dryHumidity,
            wetHumidity: wetHumidity
        )
    }

    private static func quantile(sorted: [Float], p: Double) -> Float {
        guard !sorted.isEmpty else { return 0.5 }
        let idx = max(0, min(sorted.count - 1, Int(Double(sorted.count - 1) * p)))
        return sorted[idx]
    }

    // MARK: - Шаг 2: базовая классификация суши (O(N), детерминированно)

    /// BUG-008: расширенная таблица биомов — все 7 case'ов получают ≥5% карты.
    ///
    /// Приоритет (сверху вниз):
    ///   1. mountain  — h ≥ mountainLevel                      (~10%)
    ///   2. stone     — h ≥ stoneLevel                         (~10%, предгорье)
    ///   3. sea       — h < seaLevel (предварительно)          (~30%, flood-fill уберёт лужи)
    ///   4. Суша (~50%): разбивается по t+m:
    ///      a. stone   — cold tundra (t<coldTemp)              (~10% суши → ~5% карты)
    ///      b. desert  — hot+dry (t≥hotTemp && m<dryHumidity)  (~25% суши → ~12.5% карты)
    ///      c. forest  — wet (m≥wetHumidity)                   (~25% суши → ~12.5% карты)
    ///      d. meadow  — дефолт (умеренные условия)            (~40% суши → ~20% карты)
    ///
    /// Ожидаемое распределение (типичный seed):
    ///   sea≈30%  mountain≈10%  stone≈15%  desert≈12%  forest≈12%  meadow≈20%
    /// Реки (.river) сейчас не генерируются — фича отключена (см. коммит 31acaad,
    /// плохой рендер и пересечение с дорогами/городом). Enum-case `.river` остаётся
    /// для совместимости с CityState/terrain и tileset.
    private static func classifyLand(world: NoiseMap, W: Int, thresholds t: Thresholds) -> [BiomeKind] {
        let n = W * W
        var cells = [BiomeKind](repeating: .meadow, count: n)

        // Центр и радиус морского блоба в grid-координатах.
        // Кромка модулируется тремя синусами по углу (3+5+7 лепестков) — рваный,
        // органический контур вместо идеального круга.
        let cxF = seaBlobCenter.nx * Double(W - 1)
        let cyF = seaBlobCenter.ny * Double(W - 1)
        let r0  = max(seaBlobMinRadius, Double(W) * seaBlobRadiusFraction)

        for i in 0 ..< n {
            let gx = Double(i % W)
            let gy = Double(i / W)
            let dx = gx - cxF
            let dy = gy - cyF
            let dist2 = dx * dx + dy * dy

            // Быстрый отбой: точки заведомо за внешним контуром (r0 * 1.5).
            let rOuter = r0 * 1.5
            if dist2 > rOuter * rOuter {
                // не море — fallthrough к сушевой логике ниже
            } else {
                let angle = atan2(dy, dx)
                // Многочастотная модуляция радиуса по углу — лепестки разной частоты
                // и фазы создают «рваный» контур.
                let lobes = sin(angle * 3.0 + 0.7) * 0.22
                          + sin(angle * 5.0 + 1.6) * 0.16
                          + sin(angle * 7.0 + 2.4) * 0.10
                let noiseTerm = Double(world.humidity[i] - 0.5) * 0.18
                let r = r0 * (1.0 + lobes + noiseTerm)
                if dist2 <= r * r {
                    cells[i] = .sea
                    continue
                }
            }

            let h    = world.height[i]
            let temp = world.temperature[i]
            let hum  = world.humidity[i]

            // Суша: классификация по высоте/температуре/влажности.
            // Шум-вода (h < seaLevel) теперь НЕ становится морем — низины идут в meadow,
            // чтобы море осталось ТОЛЬКО в фиксированном углу.
            if h >= t.mountainLevel {
                cells[i] = .mountain
            } else if h >= t.stoneLevel {
                cells[i] = .stone
            } else if temp < t.coldTemp {
                cells[i] = .stone
            } else if temp >= t.hotTemp && hum < t.dryHumidity {
                cells[i] = .desert
            } else if hum >= t.wetHumidity {
                cells[i] = .forest
            } else {
                // h < seaLevel (бывшие низины) и нормальные климатические клетки.
                cells[i] = .meadow
            }
        }
        return cells
    }

    // MARK: - Шаг 3: markSea — flood-fill + сглаживание «луж»

    /// Находит все связные компоненты .sea.
    /// Компоненты < minSeaArea клеток — «лужи»: переклассифицируются в наиболее
    /// часто встречающийся соседний биом суши.
    private static func markSea(cells: inout [BiomeKind], W: Int, H: Int,
                                 seaThreshold: Float, world: NoiseMap) {
        let n = W * H
        var visited = [Bool](repeating: false, count: n)

        for startIdx in 0 ..< n {
            guard cells[startIdx] == .sea, !visited[startIdx] else { continue }

            // BFS для связной компоненты
            var component: [Int] = []
            var queue: [Int] = [startIdx]
            visited[startIdx] = true

            while !queue.isEmpty {
                let cur = queue.removeLast()
                component.append(cur)
                let cx = cur % W
                let cy = cur / W
                for (dx, dy) in [(-1,0),(1,0),(0,-1),(0,1)] {
                    let nx = cx + dx
                    let ny = cy + dy
                    guard nx >= 0, nx < W, ny >= 0, ny < H else { continue }
                    let nIdx = ny * W + nx
                    if !visited[nIdx] && cells[nIdx] == .sea {
                        visited[nIdx] = true
                        queue.append(nIdx)
                    }
                }
            }

            // Если компонент мал — это «лужа», заменяем на доминирующий сосед
            if component.count < minSeaArea {
                let replacement = dominantNeighborBiome(indices: component, cells: cells, W: W, H: H)
                for idx in component {
                    cells[idx] = replacement
                }
            }
        }
    }

    /// Возвращает наиболее часто встречающийся не-sea биом среди соседей указанных клеток.
    private static func dominantNeighborBiome(indices: [Int], cells: [BiomeKind], W: Int, H: Int) -> BiomeKind {
        var counts: [BiomeKind: Int] = [:]
        let H = cells.count / W
        for idx in indices {
            let cx = idx % W
            let cy = idx / W
            for (dx, dy) in [(-1,0),(1,0),(0,-1),(0,1)] {
                let nx = cx + dx
                let ny = cy + dy
                guard nx >= 0, nx < W, ny >= 0, ny < H else { continue }
                let nBiome = cells[ny * W + nx]
                if nBiome != .sea {
                    counts[nBiome, default: 0] += 1
                }
            }
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? .meadow
    }

    // MARK: - Шаг 5: validateDiversity

    /// TASK-057 F-15: логирует распределение и опционально бросает throw.
    /// - `strict == true`: при `!outcome.balanced` бросает `insufficientDiversity`.
    /// - `strict == false`: всегда возвращает (но пишет WARN). Используется
    ///    WorldMapProvider в retry-цикле.
    private static func validateDiversity(outcome: ClassificationOutcome, strict: Bool) throws {
        let counts = outcome.distribution
        let total = outcome.total
        let unique = counts.count

        // Логируем распределение для диагностики (аналогично BUG-006 BiomeDistribution).
        let distributionStr = BiomeKind.allCases.compactMap { kind -> String? in
            guard let c = counts[kind] else { return nil }
            let pct = Double(c) / Double(total) * 100.0
            return "\(kind.rawValue):\(String(format: "%.1f", pct))%"
        }.joined(separator: " ")
        ErrorsLog.write("BiomeClassifier distribution [\(unique) kinds]: \(distributionStr)")

        // Предупреждение если любой из 7 биомов < 5% (BUG-008 цель).
        for kind in BiomeKind.allCases {
            let share = Double(counts[kind] ?? 0) / Double(total)
            if share < minBiomeShare {
                ErrorsLog.write("BiomeClassifier WARNING: \(kind.rawValue) share \(String(format: "%.1f", share * 100))% < \(Int(minBiomeShare * 100))% target")
            }
        }

        // Диагностический WARN если sea-блоб полностью «съеден» как лужа.
        // Не блокирует balanced — markSea центр-зафиксирован, retry бессмыслен.
        if !outcome.seaPresent {
            ErrorsLog.write("BiomeClassifier: sea blob absent (markSea removed all sea cells as < minSeaArea)")
        }

        if !outcome.balanced {
            ErrorsLog.write("BiomeClassifier WARNING: distribution NOT balanced (dominant=\(String(format: "%.1f", outcome.dominantShare * 100))%, nonWater≥5%: \(outcome.nonWaterAboveThreshold)/\(minDiversity))")
            if strict {
                throw BiomeClassifierError.insufficientDiversity(
                    found: outcome.nonWaterAboveThreshold,
                    dominantShare: outcome.dominantShare
                )
            }
        }
    }
}

// MARK: - Debug ASCII Dump

/// Преобразует BiomeMap в текстовую сетку для ручной проверки «географичности».
/// Только для тестов и REPL, не вызывается из продового кода.
func debugAsciiDump(_ map: BiomeMap) -> String {
    var lines: [String] = []
    lines.reserveCapacity(map.height)
    for y in 0 ..< map.height {
        var row = ""
        row.reserveCapacity(map.width)
        for x in 0 ..< map.width {
            row.append(map.at(x: x, y: y).asciiSymbol)
        }
        lines.append(row)
    }
    return lines.joined(separator: "\n")
}
