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
    func buildMainRoad(cols: Int, rows: Int, biomeReader: BiomeMapReader) {
        // Ищем строку с САМЫМ ДЛИННЫМ непрерывным отрезком walkable-клеток.
        // Это гарантирует одну сплошную полосу без разрывов (иначе море между секциями
        // создаёт 2-3 визуально отдельные «магистрали»).
        var bestRow = 0
        var bestRunLen = 0
        var bestRunStart = 0

        for y in 0..<rows {
            var runLen = 0, runStart = 0, maxRun = 0, maxStart = 0
            for x in 0..<cols {
                let b = biomeReader.biome(atX: x, y: y)
                if b != .sea && b != .mountain {
                    if runLen == 0 { runStart = x }
                    runLen += 1
                    if runLen > maxRun { maxRun = runLen; maxStart = runStart }
                } else {
                    runLen = 0
                }
            }
            if maxRun > bestRunLen {
                bestRunLen = maxRun
                bestRow = y
                bestRunStart = maxStart
            }
        }

        var cells: [GridPoint] = []
        cells.reserveCapacity(bestRunLen)
        for x in bestRunStart..<(bestRunStart + bestRunLen) {
            let p = GridPoint(x: x, y: bestRow)
            cells.append(p)
            allCells.insert(p)
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
