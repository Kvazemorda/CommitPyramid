import Foundation

/// Хранение seed мира в UserDefaults — отдельно от файла карты.
/// Это гарантирует, что при удалении worldmap.json seed уцелеет и карта
/// пересоздастся с тем же жребием (EC1: карта удалена, seed жив).
enum WorldSeedStore {

    private static let key = "com.outbyte.citydeveloper.worldSeed"

    /// Загружает seed из UserDefaults. Возвращает nil, если ключ не задан.
    static func loadSeed() -> Int64? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else { return nil }
        // UserDefaults хранит Int64 как NSNumber (64-bit macOS: Int == Int64).
        // integer(forKey:) возвращает 0 при отсутствии ключа, поэтому сначала проверяем object(forKey:).
        return Int64(bitPattern: UInt64(bitPattern: Int64(defaults.integer(forKey: key))))
    }

    /// Сохраняет seed в UserDefaults.
    static func saveSeed(_ seed: Int64) {
        UserDefaults.standard.set(Int(seed), forKey: key)
    }
}
