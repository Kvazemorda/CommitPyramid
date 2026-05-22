import Foundation

struct UnitPlanner {

    // Детерминированный паттерн «какой юнит на N-й задаче».
    // Распределение примерно: 50% жилые, 20% инфра, 20% производство, 10% социальные.
    private static let pattern: [UnitKind] = [
        .shack, .well, .shack, .workshop, .shack,        // 1..5
        .road, .shack, .warehouse, .shack, .market,      // 6..10
        .shack, .raw, .shack, .well, .shack,             // 11..15
        .workshop, .shack, .warehouse, .road, .shack,    // 16..20
    ]

    func nextUnitKind(forTaskIndex idx: Int, stage: Int) -> UnitKind {
        let base = Self.pattern[(idx - 1) % Self.pattern.count]
        return promote(base, toStage: stage)
    }

    private func promote(_ kind: UnitKind, toStage stage: Int) -> UnitKind {
        switch kind {
        case .shack:
            if stage >= 4 { return .villa }
            if stage >= 2 { return .house }
            return .shack
        case .market:
            if stage < 2 { return .well }
            if stage >= 4 { return .forum }
            return .market
        case .raw, .workshop:
            return stage >= 3 ? .workshop : kind
        default:
            return kind
        }
    }

    func nextPosition(origin: GridPoint, taskIndex: Int) -> GridPoint {
        // Кольцевое размещение вокруг центра квартала: по 8 юнитов на кольце.
        let i = taskIndex - 1
        if i == 0 { return origin }
        let ring = (i - 1) / 8 + 1
        let slot = (i - 1) % 8
        let offsets: [(Int, Int)] = [
            (1, 0), (1, 1), (0, 1), (-1, 1),
            (-1, 0), (-1, -1), (0, -1), (1, -1),
        ]
        let (dx, dy) = offsets[slot]
        return GridPoint(x: origin.x + dx * ring, y: origin.y + dy * ring)
    }
}
