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

/// Категория юнита — единый source of truth для пропорций F-07.
/// Используется UnitPlanner и CityEngine для категориальной выборки.
enum UnitCategory: String, Codable {
    case residential    // жилые: shack, house, villa
    case infrastructure // инфра: well, road, warehouse (Concept F-07 дословно: «инфра — колодец, дорога, склад»)
    case production     // производство: workshop, raw
    case social         // социальные: market, forum, temple, obelisk
}

extension UnitKind {
    /// Русское название юнита для UI и для `title` системных событий.
    var label: String {
        switch self {
        case .shack:     return "Лачуга"
        case .house:     return "Дом"
        case .villa:     return "Вилла"
        case .well:      return "Колодец"
        case .road:      return "Дорога"
        case .warehouse: return "Склад"
        case .workshop:  return "Мастерская"
        case .raw:       return "Сырьевая яма"
        case .market:    return "Рынок"
        case .forum:     return "Форум"
        case .temple:    return "Храм"
        case .obelisk:   return "Обелиск"
        }
    }
}

extension UnitKind {
    /// Категория юнита. warehouse → .infrastructure по Concept F-07.
    var category: UnitCategory {
        switch self {
        case .shack, .house, .villa:            return .residential
        case .well, .road, .warehouse:          return .infrastructure
        case .workshop, .raw:                   return .production
        case .market, .forum, .temple, .obelisk: return .social
        }
    }
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
