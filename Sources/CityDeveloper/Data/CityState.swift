import Foundation
import CoreGraphics

struct UnitState: Codable {
    let id: UUID
    let projectId: String
    /// TASK-034: var (был let) — нужен для эволюции kind при apply(.unitEvolved).
    var kind: UnitKind
    let position: GridPoint
    var tier: Int
    var decayLevel: Int  // зарезервировано для per-unit decay (сейчас decay хранится в ProjectState)
    let taskTitle: String?
    let taskTs: Date
    let taskSource: String?
}

// MARK: - BiomeKind
// Введён для каталога UnitKind (F-16). Когда TASK-027 принесёт свой Biome-тип —
// перенести/переименовать и оставить typealias на короткий период.
enum BiomeKind: String, Codable, CaseIterable {
    case meadow, forest, mountain, stone, river, sea, desert
}

// MARK: - GridSize
struct GridSize: Codable, Hashable {
    let width: Int
    let height: Int

    /// Total number of grid cells covered by this footprint.
    var area: Int { width * height }
}

// MARK: - UnitKind (50 case'ов, F-16)
// NOTE: rawValue старых 12 case'ов не меняется → state.json / events.jsonl декодируются без миграции.
// При добавлении новых case'ов — закрывать exhaustive switch'и через `default:` + TODO-комментарий,
// а не через явные ветки (политика проекта, см. план TASK-031).
enum UnitKind: String, Codable, CaseIterable {

    // MARK: Residential (12)
    case dugout          // Землянка
    case shack           // Лачуга  ← старый
    case hut             // Хижина
    case farmHouse       // Фермерский дом
    case house           // Дом  ← старый
    case twoStoryHouse   // Двухэтажный дом
    case stoneHouse      // Каменный дом
    case townhouse       // Таунхаус
    case tenement        // Доходный дом
    case manor           // Усадьба
    case villa           // Вилла  ← старая
    case palace          // Дворец

    // MARK: Infrastructure (8)
    case well            // Колодец  ← старый
    case road            // Дорога  ← старая
    case gate            // Ворота
    case bridge          // Мост
    case cistern         // Цистерна
    case lighthouse      // Маяк
    case irrigationCanal // Ирригационный канал
    case pier            // Причал
    // TODO TASK-035: warehouse → .production по F-16;
    // в текущей задаче оставлен .infrastructure для AC4 (не менять поведение UnitPlanner.pickKind(.infrastructure))
    case warehouse       // Склад  ← старый

    // MARK: Production (12)
    case farm            // Ферма
    case fishingPier     // Рыболовецкий причал
    case workshop        // Мастерская  ← старый
    case raw             // Сырьевая яма  ← старый
    case forge           // Кузница
    case pottery         // Гончарная мастерская
    case brewery         // Пивоварня
    case sawmill         // Лесопилка
    case quarry          // Каменоломня
    case mine            // Шахта
    case largeWarehouse  // Большой склад
    case factory         // Мануфактура

    // MARK: Social (10)
    case tavern          // Таверна
    case market          // Рынок  ← старый
    case plaza           // Площадь
    case bathhouse       // Баня
    case school          // Школа
    case hospital        // Больница
    case forum           // Форум  ← старый
    case library         // Библиотека
    case aqueduct        // Акведук
    case theater         // Театр
    // TODO TASK-035: переклассифицировать temple/obelisk в .religious одновременно с переписыванием планировщика
    case temple          // Храм  ← старый (legacy-категория .social для совместимости с UnitPlanner)
    case obelisk         // Обелиск  ← старый (legacy-категория .social для совместимости с UnitPlanner)

    // MARK: Religious (5)
    case chapel          // Часовня
    case cathedral       // Собор
    case pyramid         // Пирамида

    // MARK: Military (3)
    case watchtower      // Сторожевая башня
    case barracks        // Казармы
    case shipyard        // Верфь
}

// MARK: - UnitCategory
/// Категория юнита — единый source of truth для пропорций F-07.
/// Используется UnitPlanner и CityEngine для категориальной выборки.
enum UnitCategory: String, Codable {
    case residential    // жилые
    case infrastructure // инфра
    case production     // производство
    case social         // социальные
    case religious      // религиозные (новые F-16)
    case military       // военные (новые F-16)
}

// MARK: - UnitKindInfo
struct UnitKindInfo {
    let label: String
    let category: UnitCategory
    /// Предпочтительные биомы. «Любой» = BiomeKind.allCases; никогда не пусто (AC edge case).
    let terrain: [BiomeKind]
    let size: GridSize
    /// 0..5: минимальная стадия для размещения планировщиком.
    let minStage: Int
    /// true = крупный юнит; взаимоисключает evolvesTo (AC edge case).
    let large: Bool
    /// DEPRECATED TASK-046: логика эволюции перенесена в EvolutionGraph. Поля сохранены
    /// для обратной совместимости snapshot/events.jsonl; не используются в CityEngine.
    @available(*, deprecated, renamed: "EvolutionGraph.rules", message: "Use EvolutionGraph.rules instead")
    let evolvesTo: UnitKind?
    /// DEPRECATED TASK-046: см. evolvesTo.
    @available(*, deprecated, renamed: "EvolutionGraph.rules", message: "Use EvolutionGraph.rules instead")
    let evolutionThreshold: Int?
}

// MARK: - UnitKind extensions
extension UnitKind {
    var info: UnitKindInfo { Self.catalog[self]! }  // словарь покрывает все 50

    var label: String            { info.label }
    var category: UnitCategory   { info.category }
    var terrain: [BiomeKind]     { info.terrain }
    var size: GridSize           { info.size }
    var minStage: Int            { info.minStage }
    var large: Bool              { info.large }
    @available(*, deprecated, renamed: "EvolutionGraph.rules", message: "Use EvolutionGraph.rules instead")
    var evolvesTo: UnitKind?     { info.evolvesTo }
    @available(*, deprecated, renamed: "EvolutionGraph.rules", message: "Use EvolutionGraph.rules instead")
    var evolutionThreshold: Int? { info.evolutionThreshold }

    // MARK: - Каталог (50 записей, F-16)
    private static let catalog: [UnitKind: UnitKindInfo] = {
        let any = BiomeKind.allCases
        // 1×1 — только исключения: shack, house, well, road, dugout(zemlyanka), hut(khizhina), obelisk
        let s1x1 = GridSize(width: 1, height: 1)
        let s1x2 = GridSize(width: 1, height: 2)
        let s1x3 = GridSize(width: 1, height: 3)
        let s2x1 = GridSize(width: 2, height: 1)
        let s2x2 = GridSize(width: 2, height: 2)
        let s3x2 = GridSize(width: 3, height: 2)
        let s3x3 = GridSize(width: 3, height: 3)
        let s4x4 = GridSize(width: 4, height: 4)

        return [
            // ──── Residential (12) ────
            .dugout: UnitKindInfo(
                label: "Землянка", category: .residential,
                terrain: any, size: s1x1, minStage: 0, large: false,
                evolvesTo: .shack, evolutionThreshold: 2),

            .shack: UnitKindInfo(
                label: "Лачуга", category: .residential,
                terrain: any, size: s1x1, minStage: 0, large: false,
                evolvesTo: .hut, evolutionThreshold: 3),

            .hut: UnitKindInfo(
                label: "Хижина", category: .residential,
                terrain: any, size: s1x1, minStage: 0, large: false,
                evolvesTo: .house, evolutionThreshold: 4),

            .farmHouse: UnitKindInfo(
                label: "Фермерский дом", category: .residential,
                terrain: [.meadow, .forest], size: s2x2, minStage: 1, large: false,
                evolvesTo: .twoStoryHouse, evolutionThreshold: 5),

            .house: UnitKindInfo(
                label: "Дом", category: .residential,
                terrain: any, size: s1x1, minStage: 1, large: false,
                evolvesTo: .stoneHouse, evolutionThreshold: 5),

            .twoStoryHouse: UnitKindInfo(
                label: "Двухэтажный дом", category: .residential,
                terrain: any, size: s1x2, minStage: 2, large: false,
                evolvesTo: .townhouse, evolutionThreshold: 6),

            .stoneHouse: UnitKindInfo(
                label: "Каменный дом", category: .residential,
                terrain: [.meadow, .stone, .mountain], size: s2x1, minStage: 2, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .townhouse: UnitKindInfo(
                label: "Таунхаус", category: .residential,
                terrain: any, size: s2x2, minStage: 3, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .tenement: UnitKindInfo(
                label: "Доходный дом", category: .residential,
                terrain: any, size: s2x2, minStage: 3, large: true,
                evolvesTo: nil, evolutionThreshold: nil),

            .manor: UnitKindInfo(
                label: "Усадьба", category: .residential,
                terrain: [.meadow, .forest], size: s3x2, minStage: 4, large: true,
                evolvesTo: nil, evolutionThreshold: nil),

            .villa: UnitKindInfo(
                label: "Вилла", category: .residential,
                terrain: [.meadow, .stone], size: s3x3, minStage: 4, large: true,
                evolvesTo: nil, evolutionThreshold: nil),

            .palace: UnitKindInfo(
                label: "Дворец", category: .residential,
                terrain: any, size: s3x3, minStage: 5, large: true,
                evolvesTo: nil, evolutionThreshold: nil),

            // ──── Infrastructure (8 + warehouse legacy) ────
            .well: UnitKindInfo(
                label: "Колодец", category: .infrastructure,
                terrain: any, size: s1x1, minStage: 0, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .road: UnitKindInfo(
                label: "Дорога", category: .infrastructure,
                terrain: any, size: s1x1, minStage: 0, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .gate: UnitKindInfo(
                label: "Ворота", category: .infrastructure,
                terrain: any, size: s1x2, minStage: 2, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .bridge: UnitKindInfo(
                label: "Мост", category: .infrastructure,
                terrain: [.river, .sea], size: s1x3, minStage: 2, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .cistern: UnitKindInfo(
                label: "Цистерна", category: .infrastructure,
                terrain: [.meadow, .stone, .desert], size: s2x2, minStage: 2, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .lighthouse: UnitKindInfo(
                label: "Маяк", category: .infrastructure,
                terrain: [.sea, .river], size: s2x2, minStage: 3, large: true,
                evolvesTo: nil, evolutionThreshold: nil),

            .irrigationCanal: UnitKindInfo(
                label: "Ирригационный канал", category: .infrastructure,
                terrain: [.meadow, .desert, .river], size: s2x1, minStage: 2, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .pier: UnitKindInfo(
                label: "Причал", category: .infrastructure,
                terrain: [.sea, .river], size: s3x2, minStage: 1, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            // TODO TASK-035: warehouse → .production по F-16;
            // в текущей задаче оставлен .infrastructure для AC4
            .warehouse: UnitKindInfo(
                label: "Склад", category: .infrastructure,
                terrain: any, size: s2x2, minStage: 0, large: false,
                evolvesTo: .largeWarehouse, evolutionThreshold: 3),

            // ──── Production (12) ────
            .farm: UnitKindInfo(
                label: "Ферма", category: .production,
                terrain: [.meadow, .forest, .river], size: s3x3, minStage: 0, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .fishingPier: UnitKindInfo(
                label: "Рыболовецкий причал", category: .production,
                terrain: [.sea, .river], size: s2x2, minStage: 0, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .workshop: UnitKindInfo(
                label: "Мастерская", category: .production,
                terrain: any, size: s2x1, minStage: 1, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .raw: UnitKindInfo(
                label: "Сырьевая яма", category: .production,
                terrain: [.meadow, .stone, .mountain], size: s1x1, minStage: 0, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .forge: UnitKindInfo(
                label: "Кузница", category: .production,
                terrain: [.stone, .mountain], size: s2x1, minStage: 2, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .pottery: UnitKindInfo(
                label: "Гончарная мастерская", category: .production,
                terrain: [.meadow, .river], size: s2x1, minStage: 1, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .brewery: UnitKindInfo(
                label: "Пивоварня", category: .production,
                terrain: [.meadow, .river, .forest], size: s2x2, minStage: 2, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .sawmill: UnitKindInfo(
                label: "Лесопилка", category: .production,
                terrain: [.forest], size: s2x2, minStage: 1, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .quarry: UnitKindInfo(
                label: "Каменоломня", category: .production,
                terrain: [.stone, .mountain], size: s3x2, minStage: 1, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .mine: UnitKindInfo(
                label: "Шахта", category: .production,
                terrain: [.mountain, .stone], size: s2x2, minStage: 3, large: true,
                evolvesTo: nil, evolutionThreshold: nil),

            .largeWarehouse: UnitKindInfo(
                label: "Большой склад", category: .production,
                terrain: any, size: s3x2, minStage: 3, large: true,
                evolvesTo: nil, evolutionThreshold: nil),

            .factory: UnitKindInfo(
                label: "Мануфактура", category: .production,
                terrain: any, size: s3x3, minStage: 4, large: true,
                evolvesTo: nil, evolutionThreshold: nil),

            // ──── Social (10 + temple/obelisk legacy) ────
            .tavern: UnitKindInfo(
                label: "Таверна", category: .social,
                terrain: any, size: s2x1, minStage: 1, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .market: UnitKindInfo(
                label: "Рынок", category: .social,
                terrain: any, size: s2x2, minStage: 1, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .plaza: UnitKindInfo(
                label: "Площадь", category: .social,
                terrain: any, size: s3x3, minStage: 2, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .bathhouse: UnitKindInfo(
                label: "Баня", category: .social,
                terrain: [.meadow, .river, .stone], size: s2x2, minStage: 2, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .school: UnitKindInfo(
                label: "Школа", category: .social,
                terrain: any, size: s2x2, minStage: 2, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .hospital: UnitKindInfo(
                label: "Больница", category: .social,
                terrain: any, size: s2x2, minStage: 3, large: true,
                evolvesTo: nil, evolutionThreshold: nil),

            .forum: UnitKindInfo(
                label: "Форум", category: .social,
                terrain: any, size: s3x3, minStage: 3, large: true,
                evolvesTo: nil, evolutionThreshold: nil),

            .library: UnitKindInfo(
                label: "Библиотека", category: .social,
                terrain: any, size: s2x2, minStage: 3, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .aqueduct: UnitKindInfo(
                label: "Акведук", category: .social,
                terrain: [.meadow, .river, .stone], size: s1x3, minStage: 4, large: true,
                evolvesTo: nil, evolutionThreshold: nil),

            .theater: UnitKindInfo(
                label: "Театр", category: .social,
                terrain: any, size: s3x3, minStage: 4, large: true,
                evolvesTo: nil, evolutionThreshold: nil),

            // TODO TASK-035: переклассифицировать temple/obelisk в .religious
            // одновременно с переписыванием планировщика (UnitPlanner.pickKind(.social))
            .temple: UnitKindInfo(
                label: "Храм", category: .social,
                terrain: any, size: s3x3, minStage: 3, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .obelisk: UnitKindInfo(
                label: "Обелиск", category: .social,
                terrain: any, size: s1x1, minStage: 4, large: true,
                evolvesTo: nil, evolutionThreshold: nil),

            // ──── Religious (5) ────
            .chapel: UnitKindInfo(
                label: "Часовня", category: .religious,
                terrain: any, size: s2x1, minStage: 1, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .cathedral: UnitKindInfo(
                label: "Собор", category: .religious,
                terrain: any, size: s3x3, minStage: 4, large: true,
                evolvesTo: nil, evolutionThreshold: nil),

            .pyramid: UnitKindInfo(
                label: "Пирамида", category: .religious,
                terrain: [.desert, .stone], size: s4x4, minStage: 5, large: true,
                evolvesTo: nil, evolutionThreshold: nil),

            // ──── Military (3) ────
            .watchtower: UnitKindInfo(
                label: "Сторожевая башня", category: .military,
                terrain: any, size: s2x1, minStage: 2, large: false,
                evolvesTo: nil, evolutionThreshold: nil),

            .barracks: UnitKindInfo(
                label: "Казармы", category: .military,
                terrain: any, size: s2x2, minStage: 3, large: true,
                evolvesTo: nil, evolutionThreshold: nil),

            .shipyard: UnitKindInfo(
                label: "Верфь", category: .military,
                terrain: [.sea, .river], size: s3x3, minStage: 3, large: true,
                evolvesTo: nil, evolutionThreshold: nil),
        ]
    }()
}

struct GridPoint: Codable, Hashable {
    let x: Int
    let y: Int
}

struct ProjectState: Codable {
    let id: String                  // = project name
    let name: String
    let createdAt: Date
    var lastActivityAt: Date
    var taskCount: Int
    var stage: Int                  // 0..5
    var decayLevel: Int             // 0..4 (4 = руины)
    var lastDecayLogged: Int        // для предотвращения повторной записи decayTick
    var districtOrigin: GridPoint   // центр квартала
    var unitIds: [UUID]
    // F-25: District templates + epochs (TASK-048a)
    var templateName: String?
    var templateFamily: String?
    var eraLevel: Int

    init(
        id: String,
        name: String,
        createdAt: Date,
        lastActivityAt: Date,
        taskCount: Int,
        stage: Int,
        decayLevel: Int,
        lastDecayLogged: Int,
        districtOrigin: GridPoint,
        unitIds: [UUID],
        templateName: String? = nil,
        templateFamily: String? = nil,
        eraLevel: Int = 0
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.taskCount = taskCount
        self.stage = stage
        self.decayLevel = decayLevel
        self.lastDecayLogged = lastDecayLogged
        self.districtOrigin = districtOrigin
        self.unitIds = unitIds
        self.templateName = templateName
        self.templateFamily = templateFamily
        self.eraLevel = eraLevel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        lastActivityAt = try c.decode(Date.self, forKey: .lastActivityAt)
        taskCount = try c.decode(Int.self, forKey: .taskCount)
        stage = try c.decode(Int.self, forKey: .stage)
        decayLevel = try c.decode(Int.self, forKey: .decayLevel)
        lastDecayLogged = try c.decode(Int.self, forKey: .lastDecayLogged)
        districtOrigin = try c.decode(GridPoint.self, forKey: .districtOrigin)
        unitIds = try c.decode([UUID].self, forKey: .unitIds)
        // F-25 fields — optional decode for backwards-compat (legacy JSON без них)
        templateName = try c.decodeIfPresent(String.self, forKey: .templateName)
        templateFamily = try c.decodeIfPresent(String.self, forKey: .templateFamily)
        eraLevel = try c.decodeIfPresent(Int.self, forKey: .eraLevel) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, lastActivityAt, taskCount, stage
        case decayLevel, lastDecayLogged, districtOrigin, unitIds
        case templateName, templateFamily, eraLevel
    }
}

struct CityState: Codable {
    var projects: [String: ProjectState] = [:]
    var units: [String: UnitState] = [:]
    var nextDistrictIndex: Int = 0   // для детерминированного размещения

    var totalUnits: Int { units.count }
    var population: Int {
        projects.values.reduce(0) { acc, p in
            guard p.decayLevel < 4 else { return acc }
            return acc + max(0, p.unitIds.count - p.unitIds.count / 4) * (p.stage + 1)
        }
    }
}
