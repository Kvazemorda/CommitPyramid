import Foundation

/// TASK-030a: парсер пользовательского ввода в seed карты.
/// nil → «случайный» (для UI). 0-sentinel записывается в AppSettings.
enum MapSeedValidator {
    static func parse(_ text: String) -> UInt64? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Только цифры.
        guard trimmed.allSatisfy(\.isNumber) else { return nil }
        return UInt64(trimmed)  // overflow → nil автоматически
    }
}
