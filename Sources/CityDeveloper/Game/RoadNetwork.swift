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
        // 1. Найти ряд с максимальным числом walkable-клеток.
        var bestRow = 0
        var bestCount = -1
        for y in 0..<rows {
            var count = 0
            for x in 0..<cols {
                let b = biomeReader.biome(atX: x, y: y)
                if b != .sea && b != .mountain { count += 1 }
            }
            if count > bestCount {
                bestCount = count
                bestRow = y
            }
        }

        // 2. Пройти по выбранному ряду, добавляя только walkable-клетки.
        //    «Разрывы» в ряду пропускаются — путь не строго непрерывен,
        //    но в подавляющем большинстве сидов разрывов мало (выбран максимум).
        var cells: [GridPoint] = []
        cells.reserveCapacity(cols)
        for x in 0..<cols {
            let b = biomeReader.biome(atX: x, y: bestRow)
            if b != .sea && b != .mountain {
                let p = GridPoint(x: x, y: bestRow)
                cells.append(p)
                allCells.insert(p)
            }
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
