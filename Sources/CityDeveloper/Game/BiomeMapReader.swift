import Foundation

// MARK: - BiomeMapReader (TASK-028)
//
// Контракт чтения биомов для рендера. Намеренно тонкий — не зависит жёстко
// от конкретных типов TASK-027 (BiomeMap/BiomeClassifier).
// BiomeKind определён в Data/CityState.swift (введён TASK-031/027).

protocol BiomeMapReader {
    /// Ширина карты в клетках.
    var width: Int { get }
    /// Высота карты в клетках.
    var height: Int { get }
    /// Возвращает биом клетки (x, y). За пределами → .meadow.
    func biome(atX x: Int, y: Int) -> BiomeKind
}

// MARK: - BiomeMap conformance

extension BiomeMap: BiomeMapReader {
    func biome(atX x: Int, y: Int) -> BiomeKind {
        at(x: x, y: y)
    }
}

// MARK: - BiomeKind: transition priority

extension BiomeKind {
    /// Приоритет при разрешении тройных стыков (выше — выигрывает).
    /// Вода > горы > пустыня > лес > камни > луг.
    var transitionPriority: Int {
        switch self {
        case .sea:      return 7
        case .river:    return 6
        case .mountain: return 5
        case .desert:   return 4
        case .forest:   return 3
        case .stone:    return 2
        case .meadow:   return 1
        }
    }

    /// true — биом является водным.
    var isWaterBiome: Bool { self == .sea || self == .river }
}
