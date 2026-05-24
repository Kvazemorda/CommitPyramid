import Foundation

// MARK: - RoadNetwork
//
// Дорожная сеть города:
//   1. Магистраль (mainRoad) — грид-линия gy = midY через весь ромб карты.
//      В iso-проекции это диагональ экрана от середины левого-нижнего ребра
//      (LEFT→BOTTOM) к середине правого-верхнего (RIGHT→TOP), проходящая через центр.
//   2. Для каждого квартала — план дорог (петля по обе стороны от магистрали).
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
    /// Стороны магистрали (outV), которые УЖЕ заняты петлями этого квартала.
    /// Используется extendDistrictPlan — следующая петля идёт на противоположную сторону.
    private var districtLoopSides: [String: [Int]] = [:]

    /// Половина длины петли вдоль магистрали (loop = 2*halfW+1 клеток).
    /// halfW=3 → 7 вдоль mag.
    static let loopHalfWidth = 3
    /// Глубина петли перпендикулярно магистрали (v=1..depth).
    static let loopDepth = 5
    /// Вместимость интерьера одной петли (для логики «добавить ещё петлю»).
    /// (2*halfW-1) × (depth-1) = 5×4 = 20 буильдабельных клеток.
    static let loopInteriorCapacity = (loopHalfWidth * 2 - 1) * (loopDepth - 1)

    // MARK: - Public API

    /// Точка входа в город — первая клетка магистрали у края карты (середина LEFT→BOTTOM).
    var entryPoint: GridPoint? { mainRoadCells.first }

    /// Строит магистраль по грид-линии gy = midY: от grid(0, midY) до grid(cols-1, midY).
    /// В iso-проекции это прямая через центр карты от середины левого-нижнего ребра
    /// (gx=0) к середине правого-верхнего (gx=cols-1), под углом ровно вдоль ромба.
    ///
    /// Защита от моря: если клетка (k, midY) попала в .sea — смещаемся вдоль ±gy
    /// до первой не-морской клетки. Море в нижне-правом ребре карты (gy≈0)
    /// до midY не доходит, но защита остаётся на случай экзотических сидов.
    func buildMainRoad(cols: Int, rows: Int, biomeReader: BiomeMapReader) {
        let midY = rows / 2
        var cells: [GridPoint] = []
        cells.reserveCapacity(cols)

        for k in 0..<cols {
            var p = GridPoint(x: k, y: midY)
            if biomeReader.biome(atX: p.x, y: p.y) == .sea {
                var found: GridPoint? = nil
                for delta in 1...30 {
                    let candidates = [
                        GridPoint(x: k, y: midY + delta),
                        GridPoint(x: k, y: midY - delta),
                    ]
                    for c in candidates {
                        guard c.x >= 0, c.x < cols, c.y >= 0, c.y < rows else { continue }
                        if biomeReader.biome(atX: c.x, y: c.y) != .sea {
                            found = c
                            break
                        }
                    }
                    if found != nil { break }
                }
                guard let fp = found else { continue }
                p = fp
            }
            cells.append(p)
            allCells.insert(p)
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
        let mag = nearestMainRoadPoint(to: origin)
        let originV = (mag.map { origin.y - $0.y }) ?? 0
        let side = originV >= 0 ? 1 : -1
        districtLoopSides[projectId] = [side]

        let loop = computeLoop(origin: origin, sideOverride: side)

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

    /// Достраивает к плану ещё одну петлю — на противоположной стороне магистрали
    /// (или на следующей по перпендикулярной глубине, если обе стороны заняты).
    /// Используется, когда первая петля заполнена зданиями и нужно расширение.
    /// Возвращает количество добавленных клеток.
    @discardableResult
    func extendDistrictPlan(projectId: String) -> Int {
        guard (districtLoopSides[projectId]?.count ?? 0) < 20 else {
            ErrorsLog.write("RoadNetwork: loop limit 20 reached for \(projectId)")
            return 0
        }
        guard let origin   = districtOrigins[projectId],
              let existing = districtPlans[projectId] else { return 0 }

        let usedSides = districtLoopSides[projectId] ?? []
        // Следующая сторона: противоположная первой; если уже две — циклим.
        let nextSide: Int
        if usedSides.contains(1) && !usedSides.contains(-1) {
            nextSide = -1
        } else if usedSides.contains(-1) && !usedSides.contains(1) {
            nextSide = 1
        } else {
            // Обе стороны уже использованы — повторяем последнюю (по сути это
            // плейсхолдер; для глубокой экспансии нужно сдвигать u, см. TODO).
            nextSide = usedSides.last ?? 1
        }
        districtLoopSides[projectId] = usedSides + [nextSide]

        let extraLoop = computeLoop(origin: origin, sideOverride: nextSide)

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

    /// Сколько петель уже привязано к кварталу (1 после planDistrict, 2 после первого extend, …).
    func loopCount(for projectId: String) -> Int {
        districtLoopSides[projectId]?.count ?? 0
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
        districtLoopSides.removeAll()
    }

    // MARK: - Private

    /// Генерирует петлю-прямоугольник, выровненный с горизонтальной магистралью (gy=midY).
    ///
    /// Координаты (u, v): u — вдоль магистрали (=gx), v — перпендикулярно (=gy-mag.y).
    /// Обратное преобразование: gx = u, gy = mag.y + v.
    ///
    /// Петля (для outV=+1, side ABOVE mag в гриде, к LEFT-TOP по экрану):
    /// ```
    ///       (uMin,vFar)---далёкая---(uMax,vFar)
    ///            |                       |
    ///            |       origin O        |
    ///            |                       |
    ///       (uMin,vNear)--ближняя--(uMax,vNear)
    ///                       ↓
    ///                 магистраль (gy=mag.y)
    /// ```
    /// Порядок обхода: левая перп → дальняя → правая перп → ближняя (зашивает обратно к mag).
    private func computeLoop(origin: GridPoint, sideOverride outV: Int? = nil) -> [GridPoint] {
        guard let mag = nearestMainRoadPoint(to: origin) else { return [] }

        // (u, v) координаты
        let halfW = Self.loopHalfWidth
        let depth = Self.loopDepth
        let magU  = mag.x
        let originV = origin.y - mag.y
        let outVdir: Int = outV ?? (originV >= 0 ? 1 : -1)

        let uMin  = magU - halfW
        let uMax  = magU + halfW
        let vNear = outVdir * 1
        let vFar  = outVdir * depth

        var ordered: [GridPoint] = []
        var seen = Set<GridPoint>()
        func add(_ p: GridPoint) {
            if seen.insert(p).inserted { ordered.append(p) }
        }
        func cell(_ u: Int, _ v: Int) -> GridPoint {
            GridPoint(x: u, y: mag.y + v)
        }
        let vRange = stride(from: vNear, through: vFar, by: outVdir)

        // 1. Левая перпендикулярная: u=uMin, v=vNear..vFar
        for v in vRange { add(cell(uMin, v)) }
        // 2. Дальняя параллельная: v=vFar, u=uMin..uMax
        for u in uMin...uMax { add(cell(u, vFar)) }
        // 3. Правая перпендикулярная (обратный обход): u=uMax, v=vFar..vNear
        for v in vRange.reversed() { add(cell(uMax, v)) }
        // 4. Ближняя параллельная (зашивает обратно к mag): v=vNear, u=uMax..uMin
        for u in stride(from: uMax, through: uMin, by: -1) { add(cell(u, vNear)) }

        return ordered
    }
}
