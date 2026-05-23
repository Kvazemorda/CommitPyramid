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

    // MARK: - План квартала (петля от магистрали)

    /// Упорядоченный план дорог квартала: U-петля, прикреплённая к магистрали.
    private var districtPlans: [String: [GridPoint]] = [:]
    /// Сколько клеток плана уже построено.
    private var districtPlanBuilt: [String: Int] = [:]
    /// Origin квартала — нужен для extendDistrictPlan (вторая петля).
    private var districtOrigins: [String: GridPoint] = [:]

    /// Половина длины петли вдоль магистрали (loop = 2*halfW+1 в ширину).
    /// halfW=4 → 9 клеток вдоль mag.
    static let loopHalfWidth = 4
    /// Глубина петли перпендикулярно магистрали (5 клеток от mag).
    static let loopDepth = 5
    /// Вместимость интерьера петли (для логики «добавить ещё петлю»).
    static let loopInteriorCapacity = (loopHalfWidth * 2 - 1) * (loopDepth - 1)  // 7*4 = 28

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

    /// Генерирует план дорог нового квартала: U-петля, прикреплённая к магистрали.
    /// Origin находится внутри петли. Клетки добавляются в порядке «обхода» петли:
    /// connector_L → перпендикулярная сторона L → дальняя сторона → перпендикулярная R → connector_R.
    /// Клетки allCells/visual НЕ добавляются здесь — только при `consumeNextPlanCell`.
    @discardableResult
    func planDistrict(projectId: String, origin: GridPoint) -> Int {
        districtOrigins[projectId] = origin
        let loop = computeLoop(origin: origin)

        var seen = Set<GridPoint>()
        var plan: [GridPoint] = []
        for cell in loop {
            guard !seen.contains(cell) else { continue }
            seen.insert(cell)
            guard !allCells.contains(cell) else { continue }   // мост к существующей дороге
            plan.append(cell)
        }
        districtPlans[projectId] = plan
        districtPlanBuilt[projectId] = 0
        return plan.count
    }

    /// Достраивает к плану ещё одну петлю — на противоположной стороне магистрали.
    /// Используется, когда первая петля заполнена зданиями и нужно расширение.
    /// Возвращает количество добавленных клеток.
    @discardableResult
    func extendDistrictPlan(projectId: String) -> Int {
        guard let origin = districtOrigins[projectId],
              let mag    = nearestMainRoadPoint(to: origin),
              let existing = districtPlans[projectId] else { return 0 }

        // Зеркальное origin относительно магистрали → петля растёт на другой стороне.
        let outDy = origin.y >= mag.y ? 1 : -1
        let mirrored = GridPoint(x: origin.x, y: mag.y - outDy * max(2, abs(origin.y - mag.y)))
        let extraLoop = computeLoop(origin: mirrored)

        var seen = Set(existing)
        var added: [GridPoint] = []
        for cell in extraLoop {
            guard !seen.contains(cell) else { continue }
            seen.insert(cell)
            guard !allCells.contains(cell) else { continue }
            added.append(cell)
        }
        districtPlans[projectId] = existing + added
        return added.count
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
        districtOrigins.removeAll()
    }

    // MARK: - Private

    /// Генерирует U-петлю вокруг origin, прикреплённую к магистрали.
    ///
    /// Структура (для outDy=+1, mag ниже origin):
    /// ```
    ///   xMin            xMax
    ///    +---  yFar  ---+         <- дальняя сторона (параллельна mag)
    ///    |              |
    ///    |   origin O   |         <- интерьер (зона зданий)
    ///    |              |
    ///    +---  yNear ---+         <- ближняя сторона (1 клетка от mag)
    ///    .              .         <- connector_L / connector_R
    ///   mag....mag....mag         <- магистраль
    /// ```
    /// Порядок обхода: connector_L → левая → дальняя → правая → connector_R.
    /// Это даёт визуально плавную постройку от mag вокруг и обратно к mag.
    private func computeLoop(origin: GridPoint) -> [GridPoint] {
        guard let mag = nearestMainRoadPoint(to: origin) else { return [] }

        let halfW = Self.loopHalfWidth
        let depth = Self.loopDepth
        let outDy = origin.y >= mag.y ? 1 : -1
        let xMin  = origin.x - halfW
        let xMax  = origin.x + halfW
        let yNear = mag.y + outDy * 1
        let yFar  = mag.y + outDy * depth

        var ordered: [GridPoint] = []
        var seen = Set<GridPoint>()
        func add(_ p: GridPoint) {
            if seen.insert(p).inserted { ordered.append(p) }
        }
        func perpRange() -> StrideThrough<Int> {
            stride(from: yNear, through: yFar, by: outDy)
        }

        // 1. Левый connector: от nearCornerLeft вниз к mag (макс 12 клеток).
        var p = GridPoint(x: xMin, y: yNear)
        for _ in 0..<12 {
            let down = GridPoint(x: p.x, y: p.y - outDy)
            if allCells.contains(down) { break }
            add(down)
            p = down
        }

        // 2. Левая перпендикулярная сторона: yNear → yFar
        for y in perpRange() { add(GridPoint(x: xMin, y: y)) }

        // 3. Дальняя сторона (параллельна mag): xMin → xMax при y=yFar
        for x in xMin...xMax { add(GridPoint(x: x, y: yFar)) }

        // 4. Правая перпендикулярная сторона: yFar → yNear
        for y in perpRange().reversed() { add(GridPoint(x: xMax, y: y)) }

        // 5. Правый connector: от nearCornerRight вниз к mag
        p = GridPoint(x: xMax, y: yNear)
        for _ in 0..<12 {
            let down = GridPoint(x: p.x, y: p.y - outDy)
            if allCells.contains(down) { break }
            add(down)
            p = down
        }

        return ordered
    }
}
