import Foundation

// MARK: - BiomeKind Extensions (TASK-027)
//
// Enum BiomeKind сам определён в Data/CityState.swift (добавлен TASK-031).
// Здесь — расширения, которые нужны классификатору карты и будущему рендеру.

extension BiomeKind {

    /// Русское название биома для UI и debug-дампа.
    var label: String {
        switch self {
        case .meadow:   return "Луг"
        case .desert:   return "Пустыня"
        case .forest:   return "Лес"
        case .mountain: return "Горы"
        case .stone:    return "Камни"
        case .river:    return "Река"
        case .sea:      return "Море"
        }
    }

    /// Символ для ASCII-дампа (один байт на клетку).
    var asciiSymbol: Character {
        switch self {
        case .meadow:   return "."
        case .desert:   return "D"
        case .forest:   return "F"
        case .mountain: return "M"
        case .stone:    return "S"
        case .river:    return "~"
        case .sea:      return "W"
        }
    }

    /// Водный биом (нужен TASK-028-рендеру и TASK-030-аффинитету).
    var isWater: Bool {
        self == .sea || self == .river
    }
}
