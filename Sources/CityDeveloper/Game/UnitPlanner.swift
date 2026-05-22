import Foundation

struct UnitPlanner {

    // Категориальный паттерн на 20 слотов: R=10, I=4, P=4, S=2 → 50/20/20/10%.
    // Все 4 категории появляются до 10-го юнита (slot 7 = social) — AC покрытия выполнен.
    // slot: 1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20
    //       R  I  R  P  R  R  S  I  R  P   R  I  R  R  P  I  R  S  R  P
    private static let categoryPattern: [UnitCategory] = [
        .residential, .infrastructure, .residential, .production, .residential,
        .residential, .social, .infrastructure, .residential, .production,
        .residential, .infrastructure, .residential, .residential, .production,
        .infrastructure, .residential, .social, .residential, .production,
    ]

    /// Выбрать тип юнита для следующего задания в проекте.
    ///
    /// - Parameters:
    ///   - idx:             1-based taskCount (уже инкрементирован в CityEngine).
    ///   - stage:           текущий stage квартала.
    ///   - residentialCount: фактическое число жилых юнитов проекта до этого задания.
    ///   - wellCount:       фактическое число колодцев проекта до этого задания.
    ///   - infraCount:      фактическое число infra-юнитов (включая well и road).
    ///   - productionCount: фактическое число production-юнитов.
    ///   - socialCount:     фактическое число social-юнитов.
    func nextUnitKind(
        forTaskIndex idx: Int,
        stage: Int,
        residentialCount: Int,
        wellCount: Int,
        infraCount: Int,
        productionCount: Int,
        socialCount: Int
    ) -> UnitKind {
        let category = Self.categoryPattern[(idx - 1) % Self.categoryPattern.count]

        // Well soft-guard (F-07): на случай если rotation изменят и колодцев станет недостаточно.
        // При residentialCount >= 5*(wellCount+1) и слот residential — подменяем на well.
        // На базовой rotation (2 well из 4 infra-слотов) этот guard никогда не сработает.
        if category == .residential && residentialCount >= 5 * (wellCount + 1) {
            return .well
        }

        return pickKind(
            in: category,
            stage: stage,
            infraCount: infraCount,
            productionCount: productionCount,
            socialCount: socialCount
        )
    }

    /// Выбрать конкретный тип юнита внутри категории.
    /// Rotation ведётся по фактическому числу юнитов категории в проекте (per-category счётчики),
    /// а не по taskIndex — это даёт честный цикл независимо от базового categoryPattern.
    private func pickKind(
        in category: UnitCategory,
        stage: Int,
        infraCount: Int,
        productionCount: Int,
        socialCount: Int
    ) -> UnitKind {
        switch category {
        case .residential:
            // Tier-промоушен: shack → house → villa по stage.
            return promote(.shack, toStage: stage)

        case .infrastructure:
            // Rotation [well, road, warehouse, well] по числу infra-юнитов.
            // Два well из четырёх слотов → гарантирует N=5 well-правило на базовой таблице.
            let rot: [UnitKind] = [.well, .road, .warehouse, .well]
            return rot[infraCount % rot.count]

        case .production:
            // Rotation [workshop, raw, workshop, raw] по числу production-юнитов.
            // promote: при stage >= 3 оба превращаются в workshop.
            let rot: [UnitKind] = [.workshop, .raw, .workshop, .raw]
            return promote(rot[productionCount % rot.count], toStage: stage)

        case .social:
            // Чередуем «храм-семейство» (чётный socialCount) и «обелиск-семейство» (нечётный).
            // Edge case stage < 2: social запрещён по концепту → fallback well.
            // При stage < 2 квартал <= ~5 юнитов (F-08 slow ramp), AC пропорций не применяется.
            let isFirstFamily = (socialCount % 2 == 0)
            if isFirstFamily {
                // 1-е семейство: temple → forum → well(fallback)
                if stage >= 4 { return .temple }
                if stage >= 2 { return .forum }
                return .well // fallback при stage < 2 (stage-ограничение temple/forum соблюдено)
            } else {
                // 2-е семейство: obelisk → market → well(fallback)
                if stage >= 4 { return .obelisk }
                if stage >= 2 { return .market }
                return .well // fallback при stage < 2 (stage-ограничение market соблюдено)
            }
        }
    }

    /// Tier-промоушен внутри категории.
    /// Используется для residential (shack→house→villa) и production (raw/workshop→workshop при stage≥3).
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
