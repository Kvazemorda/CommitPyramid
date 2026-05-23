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

// MARK: - BiomeClassifier

/// Детерминированный классификатор: NoiseMap → BiomeMap.
/// Pure-функция: никакого глобального состояния, Date(), random.
struct BiomeClassifier {

    // MARK: - Константы

    /// Минимальная связная площадь моря (клеток). Меньше — «лужа», сглаживается.
    static let minSeaArea: Int = 8

    /// Минимальное число различных биомов (AC1).
    static let minDiversity: Int = 7

    /// Максимальная доля доминирующего биома (AC1). BUG-008: снижен с 0.75 до 0.40.
    static let maxDominantShare: Double = 0.40

    /// Минимальная доля каждого биома (BUG-008: цель ≥5%).
    static let minBiomeShare: Double = 0.05

    /// Число истоков рек. Берём топ-N пиков по высоте.
    static let riverSourceCount: Int = 5

    // MARK: - Публичный API

    /// Классифицирует NoiseMap в BiomeMap.
    /// - Throws: `BiomeClassifierError.sizeMismatch` если поля NoiseMap не согласованы.
    ///           `BiomeClassifierError.insufficientDiversity` если < 4 биомов или доля
    ///            доминирующего > 75%.
    static func classify(world: NoiseMap) throws -> BiomeMap {
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

        // 4. Проложить реки
        carveRivers(cells: &cells, W: W, H: H, world: world, thresholds: thresholds)

        // 5. Проверить разнообразие
        try validateDiversity(cells: cells, total: W * H)

        return BiomeMap(width: W, height: H, cells: cells)
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
    ///   sea≈30%  mountain≈10%  stone≈15%  desert≈12%  forest≈12%  meadow≈20%  river≈1%
    private static func classifyLand(world: NoiseMap, W: Int, thresholds t: Thresholds) -> [BiomeKind] {
        let n = W * W
        var cells = [BiomeKind](repeating: .meadow, count: n)
        for i in 0 ..< n {
            let h    = world.height[i]
            let temp = world.temperature[i]
            let hum  = world.humidity[i]

            if h >= t.mountainLevel {
                // Горные вершины
                cells[i] = .mountain
            } else if h >= t.stoneLevel {
                // Предгорье / каменистые склоны
                cells[i] = .stone
            } else if h < t.seaLevel {
                // Кандидат в море; flood-fill отфильтрует «лужи»
                cells[i] = .sea
            } else {
                // --- Суша: классификация по температуре + влажности ---
                if temp < t.coldTemp {
                    // Холодная тундра: переиспользуем .stone (каменистая холодная земля)
                    cells[i] = .stone
                } else if temp >= t.hotTemp && hum < t.dryHumidity {
                    // Жарко + сухо → пустыня
                    cells[i] = .desert
                } else if hum >= t.wetHumidity {
                    // Высокая влажность → лес
                    cells[i] = .forest
                } else {
                    // Умеренные условия → луг (дефолт)
                    cells[i] = .meadow
                }
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

    // MARK: - Шаг 4: carveRivers — downhill tracing

    /// Трассирует реки от топ-N пиков по высоте вниз до моря/края карты.
    /// Истоки выбираются детерминированно: сортируем по убыванию height[i],
    /// берём первые riverSourceCount, у которых биом НЕ mountain (чтобы реки
    /// начинались на предгорье/камнях, а не на макушке горы).
    private static func carveRivers(cells: inout [BiomeKind], W: Int, H: Int,
                                     world: NoiseMap, thresholds: Thresholds) {
        let n = W * H

        // Собираем кандидаты: камни или предгорье (высота >= stoneLevel, < mountainLevel)
        // Для детерминизма — только индексы, сортированные по убыванию height[i]
        let candidates = (0 ..< n)
            .filter { cells[$0] == .stone }
            .sorted { world.height[$0] > world.height[$1] }

        // Берём до riverSourceCount истоков, равномерно распределённых по списку
        let stride = max(1, candidates.count / riverSourceCount)
        let sources: [Int] = (0 ..< riverSourceCount).compactMap { k in
            let idx = k * stride
            return idx < candidates.count ? candidates[idx] : nil
        }

        for source in sources {
            carveOnePath(from: source, cells: &cells, W: W, H: H, world: world)
        }
    }

    /// Прокладывает одну реку от source вниз по градиенту высоты до моря или края.
    /// Ограничивает меандрирование: ширина русла (отклонение от стартовой колонки) ≤ maxRiverHalfWidth.
    private static let maxRiverHalfWidth = 15  // was 3, increased for natural meandering

    private static func carveOnePath(from startIdx: Int, cells: inout [BiomeKind],
                                      W: Int, H: Int, world: NoiseMap) {
        var cur = startIdx
        var visited = Set<Int>()
        let startX = startIdx % W
        // Максимальная длина пути — чтобы не зациклиться на плато
        let maxSteps = W + H

        for _ in 0 ..< maxSteps {
            guard !visited.contains(cur) else { break }
            visited.insert(cur)

            if cells[cur] == .sea || cells[cur] == .river {
                // Достигли моря или уже существующей реки — конец пути.
                // Остановка на .river предотвращает слияние компонент и сохраняет отдельные русла.
                break
            }

            // Помечаем текущую клетку рекой (если не гора)
            if cells[cur] != .mountain {
                cells[cur] = .river
            }

            // Шаг вниз по самому крутому градиенту среди 4 соседей.
            // Кандидаты ограничены полосой ±maxRiverHalfWidth клеток от стартовой X-позиции,
            // чтобы река не меандрировала в квадратную «лужу».
            let cx = cur % W
            let cy = cur / W
            var bestIdx: Int? = nil
            var bestH: Float = world.height[cur]

            for (dx, dy) in [(-1,0),(1,0),(0,-1),(0,1)] {
                let nx = cx + dx
                let ny = cy + dy
                guard nx >= 0, nx < W, ny >= 0, ny < H else { continue }
                // Ограничение меандра
                guard abs(nx - startX) <= maxRiverHalfWidth else { continue }
                let nIdx = ny * W + nx
                if world.height[nIdx] < bestH {
                    bestH = world.height[nIdx]
                    bestIdx = nIdx
                }
            }

            if let next = bestIdx {
                cur = next
            } else {
                // Плато или локальный минимум без выхода в море (или вышли за maxRiverHalfWidth)
                break
            }
        }
    }

    // MARK: - Шаг 5: validateDiversity

    /// BUG-008: проверяет разнообразие биомов. Бросает ошибку если:
    ///   - уникальных биомов < minDiversity (7),
    ///   - или доминирующий биом занимает > maxDominantShare (40%).
    /// Дополнительно логирует предупреждение если любой биом < minBiomeShare (5%).
    private static func validateDiversity(cells: [BiomeKind], total: Int) throws {
        var counts: [BiomeKind: Int] = [:]
        for b in cells { counts[b, default: 0] += 1 }
        let unique = counts.count
        let dominantCount = counts.values.max() ?? 0
        let dominantShare = Double(dominantCount) / Double(total)

        // Логируем распределение для диагностики (аналогично BUG-006 BiomeDistribution)
        let distributionStr = BiomeKind.allCases.compactMap { kind -> String? in
            guard let c = counts[kind] else { return nil }
            let pct = Double(c) / Double(total) * 100.0
            return "\(kind.rawValue):\(String(format: "%.1f", pct))%"
        }.joined(separator: " ")
        ErrorsLog.write("BiomeClassifier distribution [\(unique) kinds]: \(distributionStr)")

        // Предупреждение если любой из 7 биомов < 5% (BUG-008 цель)
        for kind in BiomeKind.allCases {
            let share = Double(counts[kind] ?? 0) / Double(total)
            if share < minBiomeShare {
                ErrorsLog.write("BiomeClassifier WARNING: \(kind.rawValue) share \(String(format: "%.1f", share * 100))% < \(Int(minBiomeShare * 100))% target")
            }
        }

        if unique < minDiversity || dominantShare > maxDominantShare {
            throw BiomeClassifierError.insufficientDiversity(found: unique, dominantShare: dominantShare)
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
