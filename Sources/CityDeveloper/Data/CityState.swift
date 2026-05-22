import Foundation
import CoreGraphics

struct UnitState: Codable {
    let id: UUID
    let projectId: String
    let kind: UnitKind
    let position: GridPoint
    var tier: Int
    var decayLevel: Int  // зарезервировано для per-unit decay (сейчас decay хранится в ProjectState)
    let taskTitle: String?
    let taskTs: Date
    let taskSource: String?
}

enum UnitKind: String, Codable, CaseIterable {
    case shack       // лачуга
    case house       // дом
    case villa       // вилла
    case well        // колодец
    case road        // дорога
    case warehouse   // склад
    case workshop    // мастерская
    case raw         // сырьевая яма / поле
    case market      // рынок
    case forum       // форум
    case temple      // храм
    case obelisk     // обелиск
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
}

struct CityState: Codable {
    var projects: [String: ProjectState] = [:]
    var units: [UUID: UnitState] = [:]
    var nextDistrictIndex: Int = 0   // для детерминированного размещения

    var totalUnits: Int { units.count }
    var population: Int {
        projects.values.reduce(0) { acc, p in
            guard p.decayLevel < 4 else { return acc }
            return acc + max(0, p.unitIds.count - p.unitIds.count / 4) * (p.stage + 1)
        }
    }
}
