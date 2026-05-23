import Foundation

// MARK: - RoadNetwork
//
// Дорожная сеть города:
//   1. Магистраль (mainRoad) — синусоидальная диагональ SW→NE через всю карту, строится один раз.
//   2. Для каждого квартала — план дорог (branch к магистрали + кольцо вокруг origin).
//      План строится покритично, клетка за клеткой: каждая закрытая задача даёт одну клетку
//      .road, пока план не исчерпан. Затем планировщик переходит на здания.
//
// allCells содержит ВСЁ что уже построено: магистраль + построенные клетки планов кварталов.
// UnitPlanner проверяет allCells, чтобы здания не вставали на дорогу.

final class RoadNetwork {

    // MARK: - Магистраль

    /// Клетки магистрали, упорядочены вдоль направления (от SW к NE).
    private(set) var mainRoadCells: [GridPoint] = []

    /// Все построенные дорожные клетки (магистраль + построенные клетки планов).
    private(set) var allCells: Set<GridPoint> = []

    // MARK: - План квартала (branch + кольцо)

    /// Упорядоченный план дорог квартала: branch к магистрали, потом кольцо вокруг origin.
    private var districtPlans: [String: [GridPoint]] = [:]
    /// Сколько клеток плана уже построено.
    private var districtPlanBuilt: [String: Int] = [:]

    /// Полуразмер кольца: ring обходит origin по периметру квадрата (2h+1)×(2h+1).
    /// halfSide=2 → кольцо 5×5, периметр 16 клеток.
    static let ringHalfSide = 2

    // MARK: - Public API

    /// Точка входа в город — первая клетка магистрали у края карты (SW).
    var entryPoint: GridPoint? { mainRoadCells.first }

    /// Строит магистраль вдоль оси +gx (gx: 0 → cols-1) при gy ≈ rows/2.
    /// В iso-проекции это диагональ экрана от SW (лево-низ) к NE (право-верх).
    /// Извив — синусом по gy, перпендикулярно направлению движения.
    /// Море остаётся в фиксированном углу (gy ≈ 0) — магистраль его не пересекает.
    func buildMainRoad(cols: Int, rows: Int, biomeReader: BiomeMapReader) {
        let midY      = Double(rows - 1) * 0.5
        let amplitude: Double = 14    // отклонение в тайлах от центральной линии
        let waves:     Double = 2.5

        let steps = cols * 3

        var cells: [GridPoint] = []
        var lastAdded: GridPoint? = nil

        for step in 0...steps {
            let t = Double(step) / Double(steps)

            let gxF = t * Double(cols - 1)
            let gyF = midY + amplitude * sin(t * waves * .pi * 2)

            let cx = max(0, min(cols - 1, Int(gxF.rounded())))
            var cy = max(0, min(rows - 1, Int(gyF.rounded())))

            // Море при gy≈0; магистраль идёт при mid_y, пересечений быть не должно.
            // Защитный обход: если попали — двигаемся вверх по gy.
            if biomeReader.biome(atX: cx, y: cy) == .sea {
                var found = false
                for delta in 1...20 {
                    let ny = cy + delta
                    if ny < rows, biomeReader.biome(atX: cx, y: ny) != .sea {
                        cy = ny; found = true; break
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

    /// Ближайшая клетка магистрали к точке (Manhattan).
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

    // MARK: - План квартала

    /// Генерирует план дорог нового квартала: branch (origin→магистраль) + кольцо вокруг origin.
    /// План записывается в districtPlans, но клетки allCells/visual НЕ добавляются — это происходит
    /// при `consumeNextPlanCell` по мере закрытия задач.
    @discardableResult
    func planDistrict(projectId: String, origin: GridPoint) -> Int {
        let branch = computeBranch(origin: origin)
        let ring   = computeRing(origin: origin, halfSide: Self.ringHalfSide)

        // Без дублей внутри плана. Клетки магистрали — пропускаем (там и так дорога).
        var seen = Set<GridPoint>()
        var plan: [GridPoint] = []
        for cell in branch + ring {
            guard !seen.contains(cell) else { continue }
            guard !allCells.contains(cell) else {
                seen.insert(cell)
                continue
            }
            seen.insert(cell)
            plan.append(cell)
        }
        districtPlans[projectId] = plan
        districtPlanBuilt[projectId] = 0
        return plan.count
    }

    /// Помечает следующую клетку плана как построенную и возвращает её. nil — план исчерпан.
    func consumeNextPlanCell(for projectId: String) -> GridPoint? {
        guard let plan = districtPlans[projectId] else { return nil }
        let i = districtPlanBuilt[projectId] ?? 0
        guard i < plan.count else { return nil }
        let cell = plan[i]
        districtPlanBuilt[projectId] = i + 1
        allCells.insert(cell)
        return cell
    }

    /// План построен полностью (все клетки использованы)? Также true если план не существует.
    func isPlanComplete(for projectId: String) -> Bool {
        guard let plan = districtPlans[projectId] else { return true }
        return (districtPlanBuilt[projectId] ?? 0) >= plan.count
    }

    /// Уже построенные клетки плана квартала — для UnitPlanner.nextPosition.
    func builtRoadCells(for projectId: String) -> [GridPoint] {
        guard let plan = districtPlans[projectId] else { return [] }
        let n = districtPlanBuilt[projectId] ?? 0
        return Array(plan.prefix(n))
    }

    /// Возвращает все клетки плана (для replay-восстановления).
    func plannedCells(for projectId: String) -> [GridPoint] {
        districtPlans[projectId] ?? []
    }

    /// Прямой инжект состояния плана (для snapshot/replay).
    /// Используется, когда мы хотим восстановить квартал, у которого уже было построено N клеток.
    func restorePlan(projectId: String, origin: GridPoint, builtCount: Int) {
        if districtPlans[projectId] == nil {
            planDistrict(projectId: projectId, origin: origin)
        }
        guard let plan = districtPlans[projectId] else { return }
        let n = min(builtCount, plan.count)
        districtPlanBuilt[projectId] = n
        for i in 0..<n { allCells.insert(plan[i]) }
    }

    /// Сбрасывает всё (для regenerate карты).
    func reset() {
        mainRoadCells.removeAll()
        allCells.removeAll()
        districtPlans.removeAll()
        districtPlanBuilt.removeAll()
    }

    // MARK: - Private

    /// L-образный branch от origin до ближайшей клетки магистрали.
    /// Если магистрали ещё нет — пустой массив (квартал без подключения, edge case).
    private func computeBranch(origin: GridPoint) -> [GridPoint] {
        guard let target = nearestMainRoadPoint(to: origin) else { return [] }

        // Кольцо построится отдельно — branch ведёт от КРАЯ кольца к магистрали,
        // чтобы не дублировать клетки на ребре периметра.
        let h = Self.ringHalfSide
        let ringEdge = GridPoint(
            x: target.x > origin.x ? origin.x + h : (target.x < origin.x ? origin.x - h : origin.x),
            y: target.y > origin.y ? origin.y + h : (target.y < origin.y ? origin.y - h : origin.y)
        )

        var branch: [GridPoint] = []
        var seen = Set<GridPoint>()

        let stepY = target.y == ringEdge.y ? 0 : (target.y > ringEdge.y ? 1 : -1)
        var y = ringEdge.y
        while y != target.y {
            y += stepY
            let p = GridPoint(x: ringEdge.x, y: y)
            if seen.insert(p).inserted { branch.append(p) }
        }
        let stepX = target.x == ringEdge.x ? 0 : (target.x > ringEdge.x ? 1 : -1)
        var x = ringEdge.x
        while x != target.x {
            x += stepX
            let p = GridPoint(x: x, y: target.y)
            if seen.insert(p).inserted { branch.append(p) }
        }
        return branch
    }

    /// Клетки периметра квадрата 2h+1 вокруг origin, обход по часовой.
    private func computeRing(origin: GridPoint, halfSide h: Int) -> [GridPoint] {
        var ring: [GridPoint] = []
        // Низ (y = origin.y - h), слева направо
        for x in (origin.x - h)...(origin.x + h) {
            ring.append(GridPoint(x: x, y: origin.y - h))
        }
        // Правая (x = origin.x + h), снизу вверх (без угла)
        for y in (origin.y - h + 1)...(origin.y + h) {
            ring.append(GridPoint(x: origin.x + h, y: y))
        }
        // Верх (y = origin.y + h), справа налево (без угла)
        for x in stride(from: origin.x + h - 1, through: origin.x - h, by: -1) {
            ring.append(GridPoint(x: x, y: origin.y + h))
        }
        // Левая (x = origin.x - h), сверху вниз (без углов)
        for y in stride(from: origin.y + h - 1, through: origin.y - h + 1, by: -1) {
            ring.append(GridPoint(x: origin.x - h, y: y))
        }
        return ring
    }
}
