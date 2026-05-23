import Foundation

// MARK: - RoadNetwork
//
// Простая сеть дорог поверх биом-карты: одна «магистраль» (mainRoad) вдоль
// наиболее проходимого ряда + L-образные ответвления (branch) от каждого
// квартала к ближайшей точке магистрали.
//
// Используется UnitPlanner для размещения зданий вдоль ответвлений и
// CitizenManager для входа жителей в город с края карты.

final class RoadNetwork {

    /// Клетки магистрали, упорядочены вдоль направления (слева-направо для горизонтального ряда).
    private(set) var mainRoadCells: [GridPoint] = []

    /// Все клетки сети (магистраль + ветки) для быстрой проверки занятости.
    private(set) var allCells: Set<GridPoint> = []

    /// Ветки кварталов: districtBranches[projectId] = упорядоченные клетки
    /// от districtOrigin в сторону магистрали (включая стык, без дублирования с allCells).
    private(set) var districtBranches: [String: [GridPoint]] = [:]

    // MARK: - Public API

    /// Точка входа в город — первая клетка магистрали у края карты.
    var entryPoint: GridPoint? { mainRoadCells.first }

    /// Строит магистраль вдоль ряда (row, y=const) с максимальным числом проходимых клеток.
    /// Проходимая = не .sea и не .mountain.
    /// Строит магистраль от визуального левого угла карты (0, rows-1)
    /// до визуального правого угла (cols-1, 0) с синусоидальным извивом.
    /// Путь НИКОГДА не пересекает море: при попадании на морскую клетку
    /// алгоритм ищет ближайшую сухопутную клетку перпендикулярно диагонали.
    func buildMainRoad(cols: Int, rows: Int, biomeReader: BiomeMapReader) {
        let amplitude: Double = 14   // максимальное отклонение в тайлах
        let waves:     Double = 3.0  // количество волн на всю длину пути

        // Шагов достаточно, чтобы гарантировать непрерывность (каждый тайл покрыт).
        let steps = (cols + rows) * 3

        var cells: [GridPoint] = []
        var lastAdded: GridPoint? = nil

        for step in 0...steps {
            let t = Double(step) / Double(steps)

            // Базовая диагональ (0,rows-1) → (cols-1,0)
            let baseX = t * Double(cols - 1)
            let baseY = (1.0 - t) * Double(rows - 1)

            // Синусоидальный сдвиг перпендикулярно диагонали.
            // Перпендикуляр к направлению (1,-1)/√2 — это (1,1)/√2,
            // поэтому оба x и y смещаются одновременно.
            let sine = amplitude * sin(t * waves * .pi * 2)
            let perp = sine * 0.707   // ≈ sine / √2

            var cx = max(0, min(cols - 1, Int((baseX + perp).rounded())))
            var cy = max(0, min(rows - 1, Int((baseY + perp).rounded())))

            // Если клетка — море, ищем ближайшую не-морскую
            // в направлении, перпендикулярном диагонали.
            if biomeReader.biome(atX: cx, y: cy) == .sea {
                var found = false
                outer: for delta in 1...25 {
                    let candidates: [(Int, Int)] = [
                        (cx - delta, cy - delta), (cx + delta, cy + delta),
                        (cx - delta, cy),          (cx, cy - delta),
                        (cx + delta, cy),          (cx, cy + delta),
                    ]
                    for (nx, ny) in candidates {
                        if nx >= 0, nx < cols, ny >= 0, ny < rows,
                           biomeReader.biome(atX: nx, y: ny) != .sea {
                            cx = nx; cy = ny; found = true; break outer
                        }
                    }
                }
                if !found { continue }
            }

            let p = GridPoint(x: cx, y: cy)
            guard p != lastAdded else { continue }
            cells.append(p)
            allCells.insert(p)
            lastAdded = p
        }

        mainRoadCells = cells
    }

    /// Ищет ближайшую к точке клетку магистрали по Manhattan-дистанции.
    func nearestMainRoadPoint(to point: GridPoint) -> GridPoint? {
        guard !mainRoadCells.isEmpty else { return nil }
        var best: GridPoint? = nil
        var bestDist = Int.max
        for cell in mainRoadCells {
            let d = abs(cell.x - point.x) + abs(cell.y - point.y)
            if d < bestDist {
                bestDist = d
                best = cell
            }
        }
        return best
    }

    /// Подключает квартал к магистрали L-образной веткой.
    /// Возвращает свежедобавленные клетки ветки (без уже существующих в allCells).
    /// Алгоритм: от origin сначала меняем Y до nearest.y, затем X до nearest.x.
    @discardableResult
    func connectDistrict(projectId: String, origin: GridPoint) -> [GridPoint] {
        guard let target = nearestMainRoadPoint(to: origin) else {
            districtBranches[projectId] = []
            return []
        }

        var branch: [GridPoint] = []
        var added: [GridPoint] = []

        // Шаг 1: вертикальный сегмент (origin.x фиксирован, y движется к target.y).
        let stepY = target.y == origin.y ? 0 : (target.y > origin.y ? 1 : -1)
        var y = origin.y
        while y != target.y {
            let p = GridPoint(x: origin.x, y: y)
            branch.append(p)
            if !allCells.contains(p) {
                allCells.insert(p)
                added.append(p)
            }
            y += stepY
        }

        // Шаг 2: горизонтальный сегмент (y = target.y, x движется от origin.x к target.x).
        let stepX = target.x == origin.x ? 0 : (target.x > origin.x ? 1 : -1)
        var x = origin.x
        while x != target.x {
            let p = GridPoint(x: x, y: target.y)
            branch.append(p)
            if !allCells.contains(p) {
                allCells.insert(p)
                added.append(p)
            }
            x += stepX
        }

        // Точка стыка с магистралью (target) уже в allCells — branch её не дублирует.
        districtBranches[projectId] = branch
        return added
    }

    /// Все клетки ветки квартала (для UnitPlanner и CitizenManager).
    func branchCells(for projectId: String) -> [GridPoint] {
        districtBranches[projectId] ?? []
    }

    /// Сбрасывает всё (для regenerate карты).
    func reset() {
        mainRoadCells.removeAll()
        allCells.removeAll()
        districtBranches.removeAll()
    }
}
