// MARK: - TASK-046: Cross-unit эволюция через требования по окружению
// EvolutionGraph заменяет UnitKind.evolvesTo / evolutionThreshold.
// Детерминизм: rules — static таблица, итерация в порядке массива.

import Foundation

// MARK: - EvolutionRequirement

/// Требование к окружению квартала для срабатывания правила эволюции.
/// Все юниты данного kind с tier >= minStage считаются удовлетворяющими.
struct EvolutionRequirement {
    /// Тип юнита, который должен присутствовать в квартале.
    let kind: UnitKind
    /// Минимальная стадия (tier) юнитов данного kind.
    let minStage: Int
    /// Минимальное количество таких юнитов.
    let minCount: Int
}

// MARK: - EvolutionRule

/// Одно правило эволюции: fromKind → toKind при выполнении requirements.
struct EvolutionRule {
    /// Тип юнита, который эволюционирует.
    let from: UnitKind
    /// Тип юнита, в который превращается.
    let to: UnitKind
    /// Сколько юнитов from нужно для срабатывания правила.
    /// MVP: эволюционирует только старейший; остальные consumeCount-1 — gate-только.
    let consumeCount: Int
    /// Список требований к другим юнитам квартала (и возможно к самому from).
    let requirements: [EvolutionRequirement]
}

// MARK: - EvolutionGraph

/// Таблица правил эволюции (TASK-046 F-23).
/// Порядок правил: по (from.rawValue, to.rawValue) лексикографически — обеспечивает детерминизм.
/// При нескольких подходящих правилах с одним from — выбирается первое в массиве.
enum EvolutionGraph {
    // swiftlint:disable line_length
    static let rules: [EvolutionRule] = [
        // 1. Землянка (dugout) → Лачуга (shack): нужно ≥2 землянок
        EvolutionRule(
            from: .dugout, to: .shack, consumeCount: 1,
            requirements: [
                EvolutionRequirement(kind: .dugout, minStage: 0, minCount: 2),
            ]
        ),

        // 2. Хижина (hut) → Каменный дом (stoneHouse): нужно ≥2 хижин + ≥1 каменоломня tier≥1
        EvolutionRule(
            from: .hut, to: .stoneHouse, consumeCount: 1,
            requirements: [
                EvolutionRequirement(kind: .hut,    minStage: 0, minCount: 2),
                EvolutionRequirement(kind: .quarry,  minStage: 1, minCount: 1),
            ]
        ),

        // 3. Лачуга (shack) → Дом (house): нужно ≥1 колодец + ≥3 лачуги tier≥1 + ≥5 дорог
        EvolutionRule(
            from: .shack, to: .house, consumeCount: 1,
            requirements: [
                EvolutionRequirement(kind: .well,   minStage: 0, minCount: 1),
                EvolutionRequirement(kind: .shack,  minStage: 1, minCount: 3),
                EvolutionRequirement(kind: .road,   minStage: 0, minCount: 5),
            ]
        ),

        // 4. Дом (house) → Доходный дом (tenement): нужно ≥1 рынок tier≥1 + ≥2 колодца + ≥3 дома tier≥2
        EvolutionRule(
            from: .house, to: .tenement, consumeCount: 3,
            requirements: [
                EvolutionRequirement(kind: .market, minStage: 1, minCount: 1),
                EvolutionRequirement(kind: .well,   minStage: 0, minCount: 2),
                EvolutionRequirement(kind: .house,  minStage: 2, minCount: 3),
            ]
        ),

        // 5. Каменный дом (stoneHouse) → Усадьба (manor): нужно ≥2 кам. дома tier≥2 + ≥1 форум
        EvolutionRule(
            from: .stoneHouse, to: .manor, consumeCount: 2,
            requirements: [
                EvolutionRequirement(kind: .stoneHouse, minStage: 2, minCount: 2),
                EvolutionRequirement(kind: .forum,      minStage: 0, minCount: 1),
            ]
        ),

        // 6. Двухэтажный дом (twoStoryHouse) → Доходный дом (tenement): нужно ≥2 двухэтажных tier≥2 + ≥1 рынок
        EvolutionRule(
            from: .twoStoryHouse, to: .tenement, consumeCount: 2,
            requirements: [
                EvolutionRequirement(kind: .twoStoryHouse, minStage: 2, minCount: 2),
                EvolutionRequirement(kind: .market,        minStage: 1, minCount: 1),
            ]
        ),

        // 7. Фермерский дом (farmHouse) → Усадьба (manor): нужно ≥1 ферма tier≥1 + ≥1 колодец
        EvolutionRule(
            from: .farmHouse, to: .manor, consumeCount: 1,
            requirements: [
                EvolutionRequirement(kind: .farm, minStage: 1, minCount: 1),
                EvolutionRequirement(kind: .well, minStage: 0, minCount: 1),
            ]
        ),

        // 8. Склад (warehouse) → Большой склад (largeWarehouse): нужно ≥3 склада tier≥2 + ≥8 дорог
        EvolutionRule(
            from: .warehouse, to: .largeWarehouse, consumeCount: 3,
            requirements: [
                EvolutionRequirement(kind: .warehouse, minStage: 2, minCount: 3),
                EvolutionRequirement(kind: .road,      minStage: 0, minCount: 8),
            ]
        ),

        // 9. Мастерская (workshop) → Мануфактура (factory): нужно ≥2 мастерских tier≥3 + ≥1 склад tier≥1
        EvolutionRule(
            from: .workshop, to: .factory, consumeCount: 2,
            requirements: [
                EvolutionRequirement(kind: .workshop,  minStage: 3, minCount: 2),
                EvolutionRequirement(kind: .warehouse,  minStage: 1, minCount: 1),
            ]
        ),

        // 10. Часовня (chapel) → Храм (temple): нужно ≥1 часовня tier≥2 + ≥1 форум tier≥1
        EvolutionRule(
            from: .chapel, to: .temple, consumeCount: 1,
            requirements: [
                EvolutionRequirement(kind: .chapel, minStage: 2, minCount: 1),
                EvolutionRequirement(kind: .forum,  minStage: 1, minCount: 1),
            ]
        ),
    ]
    // swiftlint:enable line_length
}
