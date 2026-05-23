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
    static let minDiversity: Int = 4

    /// Максимальная доля доминирующего биома (AC1).
    static let maxDominantShare: Double = 0.75

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
    private static func computeThresholds(world: NoiseMap) -> Thresholds {
        let sortedH = world.height.sorted()
        let sortedT = world.temperature.sorted()
        let sortedM = world.humidity.sorted()
        let n = sortedH.count

        // Море — bottom 25% высоты
        let seaLevel      = quantile(sorted: sortedH, p: 0.25)
        // Камни — top 20% высоты (предгорье)
        let stoneLevel    = quantile(sorted: sortedH, p: 0.80)
        // Горы — top 10% высоты
        let mountainLevel = quantile(sorted: sortedH, p: 0.90)

        // Жарко — top 35% температуры
        let hotTemp       = quantile(sorted: sortedT, p: 0.65)
        // Холодно — bottom 35% температуры (не используется отдельно, но для баланса)
        let coldTemp      = quantile(sorted: sortedT, p: 0.35)

        // Сухо — bottom 35% влажности
        let dryHumidity   = quantile(sorted: sortedM, p: 0.35)
        // Влажно — top 40% влажности
        let wetHumidity   = quantile(sorted: sortedM, p: 0.60)

        _ = n
        _ = coldTemp

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

    private static func classifyLand(world: NoiseMap, W: Int, thresholds t: Thresholds) -> [BiomeKind] {
        let n = W * W
        var cells = [BiomeKind](repeating: .meadow, count: n)
        for i in 0 ..< n {
            let h = world.height[i]
            let temp = world.temperature[i]
            let hum  = world.humidity[i]

            if h >= t.mountainLevel {
                cells[i] = .mountain
            } else if h >= t.stoneLevel {
                cells[i] = .stone
            } else if h < t.seaLevel {
                // предварительно помечаем как море; flood-fill потом отфильтрует «лужи»
                cells[i] = .sea
            } else {
                // суша: таблица (temperature, humidity)
                if temp >= t.hotTemp && hum < t.dryHumidity {
                    cells[i] = .desert
                } else if temp >= t.hotTemp && hum >= t.wetHumidity {
                    cells[i] = .forest
                } else if hum >= t.wetHumidity {
                    cells[i] = .forest
                } else {
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
    private static func carveOnePath(from startIdx: Int, cells: inout [BiomeKind],
                                      W: Int, H: Int, world: NoiseMap) {
        var cur = startIdx
        var visited = Set<Int>()
        // Максимальная длина пути — чтобы не зациклиться на плато
        let maxSteps = W + H

        for _ in 0 ..< maxSteps {
            guard !visited.contains(cur) else { break }
            visited.insert(cur)

            if cells[cur] == .sea {
                // Достигли моря — конец реки
                break
            }

            // Помечаем текущую клетку рекой (если не море и не гора)
            if cells[cur] != .mountain {
                cells[cur] = .river
                // Расширяем русло на 1 клетку в стороны (ширина 2–3 клетки суммарно)
                let cx = cur % W
                let cy = cur / W
                for (dx, dy) in [(-1,0),(1,0),(0,-1),(0,1)] {
                    let nx = cx + dx
                    let ny = cy + dy
                    guard nx >= 0, nx < W, ny >= 0, ny < H else { continue }
                    let nIdx = ny * W + nx
                    if cells[nIdx] != .sea && cells[nIdx] != .mountain && cells[nIdx] != .river {
                        cells[nIdx] = .river
                    }
                }
            }

            // Шаг вниз по самому крутому градиенту среди 4 соседей
            let cx = cur % W
            let cy = cur / W
            var bestIdx: Int? = nil
            var bestH: Float = world.height[cur]

            for (dx, dy) in [(-1,0),(1,0),(0,-1),(0,1)] {
                let nx = cx + dx
                let ny = cy + dy
                guard nx >= 0, nx < W, ny >= 0, ny < H else { continue }
                let nIdx = ny * W + nx
                if world.height[nIdx] < bestH {
                    bestH = world.height[nIdx]
                    bestIdx = nIdx
                }
            }

            if let next = bestIdx {
                cur = next
            } else {
                // Плато или локальный минимум без выхода в море
                // Оставляем частичную реку; документируем: edge case TASK-027
                break
            }
        }
    }

    // MARK: - Шаг 5: validateDiversity

    private static func validateDiversity(cells: [BiomeKind], total: Int) throws {
        var counts: [BiomeKind: Int] = [:]
        for b in cells { counts[b, default: 0] += 1 }
        let unique = counts.count
        let dominantCount = counts.values.max() ?? 0
        let dominantShare = Double(dominantCount) / Double(total)

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
