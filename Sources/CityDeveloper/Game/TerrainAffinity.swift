import Foundation

/// Детерминированная функция «уместности» юнита в биоме клетки.
///
/// Используется `UnitPlanner` (TASK-035) для взвешенного выбора юнита
/// с учётом географической логики карты (F-16).
///
/// Алгоритм (4-уровневое решающее дерево):
/// 1. `terrain` пуст → 0.5 + однократная запись в errors.log.
/// 2. `terrain == BiomeKind.allCases` (все 7) → 1.0.
/// 3. `biome` в `kind.terrain` → 1.0.
/// 4. `biome == .sea` и юнит в white-list → 0.05.
/// 5. Иначе → 0.15 («неожиданный гость»).
enum TerrainAffinity {

    // MARK: - Пороговые константы (нет magic numbers в теле)
    private static let weightPreferred:  Double = 1.0
    private static let weightFallback:   Double = 0.5
    private static let weightUnexpected: Double = 0.15
    private static let weightDryInSea:   Double = 0.05

    /// Юниты, для которых weight в море ≤ 0.05 (white-list из спеки).
    /// Только Пирамида и Каменоломня — остальные сухопутные получают 0.15.
    private static let seaIncompatibleKinds: Set<UnitKind> = [.pyramid, .quarry]

    /// Для однократного warning'а на каждый «битый» kind (terrain пуст).
    private static let logLock = NSLock()
    private static var loggedEmptyTerrain: Set<UnitKind> = []

    // MARK: - Публичный API

    /// Вес «уместности» юнита в биоме клетки. Диапазон [0..1].
    ///
    /// - Returns:
    ///   - `1.0`  — биом предпочтительный (в `kind.terrain`) или `terrain` == «любой» (все 7).
    ///   - `0.5`  — `terrain` пуст (баг данных из TASK-031); однократный warning в errors.log.
    ///   - `0.15` — «неожиданный гость» (явный список, биом не совпал).
    ///   - `0.05` — Пирамида/Каменоломня в море (white-list).
    ///
    /// Функция детерминирована и не зависит от глобального состояния (replay-safe).
    static func weight(for kind: UnitKind, in biome: BiomeKind) -> Double {
        let terrain = kind.terrain

        // Edge: terrain пуст → баг данных (TASK-031 гарантирует непустоту, но защищаемся)
        if terrain.isEmpty {
            logEmptyTerrainOnce(kind: kind)
            return weightFallback
        }

        let terrainSet = Set(terrain)
        let allBiomes  = Set(BiomeKind.allCases)

        // AC #2: «любой» биом (terrain содержит все 7) → равномерный максимальный вес
        if terrainSet == allBiomes {
            return weightPreferred
        }

        // AC #3: биом входит в предпочтительный список → максимальный вес
        if terrainSet.contains(biome) {
            return weightPreferred
        }

        // Edge #4: sea-incompatible white-list (только Пирамида и Каменоломня)
        if biome == .sea && seaIncompatibleKinds.contains(kind) {
            return weightDryInSea
        }

        // Общий случай: явный список, биом не совпал → «неожиданный гость»
        return weightUnexpected
    }

    // MARK: - TASK-030c F-15: Biome-aware allocation helper

    /// Возвращает упорядоченный список предпочтительных биомов для набора юнитов.
    ///
    /// Алгоритм:
    /// 1. Для каждого биома суммирует `weight(for: kind, in: biome)` по всем kind'ам.
    /// 2. Отсекает биомы с суммарным весом ≤ 0.3 × max (слабые предпочтения).
    /// 3. Сортирует по убыванию score.
    /// 4. Пустой ввод или все нулевые веса → fallback `[.meadow, .desert]`.
    ///
    /// Pure-функция: детерминирована, не зависит от глобального состояния (replay-safe).
    static func preferredBiomes(for kinds: [UnitKind]) -> [BiomeKind] {
        guard !kinds.isEmpty else { return [.meadow, .desert] }

        var scores: [(biome: BiomeKind, score: Double)] = []
        for biome in BiomeKind.allCases {
            let s = kinds.reduce(0.0) { acc, k in acc + weight(for: k, in: biome) }
            scores.append((biome, s))
        }

        let maxScore = scores.map(\.score).max() ?? 0.0
        guard maxScore > 0 else { return [.meadow, .desert] }

        let threshold = 0.3 * maxScore
        let result = scores
            .filter { $0.score > threshold }
            .sorted { $0.score > $1.score }
            .map(\.biome)

        return result.isEmpty ? [.meadow, .desert] : result
    }

    // MARK: - Private

    private static func logEmptyTerrainOnce(kind: UnitKind) {
        logLock.lock()
        defer { logLock.unlock() }
        guard !loggedEmptyTerrain.contains(kind) else { return }
        loggedEmptyTerrain.insert(kind)
        ErrorsLog.write("TerrainAffinity: UnitKind.\(kind.rawValue) has empty terrain — returning fallback 0.5")
    }
}
