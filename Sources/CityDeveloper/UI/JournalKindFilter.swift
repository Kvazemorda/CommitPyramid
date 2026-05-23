import Foundation

/// Фильтр по типу события в журнале (TASK-015).
enum JournalKindFilter: Equatable {
    case all
    case some(Set<GameEvent.Kind>)
}

extension JournalKindFilter {
    /// Применяет фильтр к одному событию. true = пропустить, false = отбросить.
    func passes(_ event: GameEvent) -> Bool {
        switch self {
        case .all: return true
        case .some(let kinds): return kinds.contains(event.kind)
        }
    }

    /// Пустой `.some(∅)` — особое состояние «ничего не выбрано».
    var isEmptySelection: Bool {
        if case .some(let kinds) = self, kinds.isEmpty { return true }
        return false
    }
}

/// Иконки SF Symbols для каждого kind'а (используется в JournalRow).
extension GameEvent.Kind {
    var iconName: String {
        switch self {
        case .taskCompleted: return "checkmark.circle"
        case .unitBuilt:     return "building.2"
        case .stageUp:       return "arrow.up.square"
        case .decayTick:     return "clock.arrow.circlepath"
        case .fire:          return "flame"
        case .restore:       return "arrow.uturn.up"
        case .ruinsCleared:  return "trash.slash"
        case .unitEvolved:   return "arrow.triangle.2.circlepath"  // TASK-034
        }
    }

    /// Человекочитаемое название для popover «Кастом» и пресетов.
    var displayName: String {
        switch self {
        case .taskCompleted: return "Закрытие задачи"
        case .unitBuilt:     return "Постройка юнита"
        case .stageUp:       return "Апгрейд стадии"
        case .decayTick:     return "Decay-тик"
        case .fire:          return "Пожар"
        case .restore:       return "Восстановление"
        case .ruinsCleared:  return "Снос руин"
        case .unitEvolved:   return "Эволюция юнита"  // TASK-034
        }
    }
}

/// Pure-функция фильтрации журнала. Вынесена сюда для юнит-тестируемости
/// без зависимости от SwiftUI / engine.
enum JournalFilter {
    static func apply(
        events: [GameEvent],
        projectId: String?,
        dateFrom: Date,
        dateTo: Date,
        kindFilter: JournalKindFilter
    ) -> [GameEvent] {
        // Edge: пустой `.some(∅)` → отбрасываем всё.
        if kindFilter.isEmptySelection { return [] }
        let dateRangeValid = dateFrom <= dateTo
        return events
            .sorted { $0.ts > $1.ts }
            .filter { e in
                guard kindFilter.passes(e) else { return false }
                if let sel = projectId, !sel.isEmpty {
                    guard e.project == sel else { return false }
                }
                if dateRangeValid {
                    guard e.ts >= dateFrom && e.ts <= dateTo.endOfDay else { return false }
                }
                return true
            }
    }
}
