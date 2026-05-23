import Foundation

// MARK: - SplitMix64
//
// Миниатюрный детерминированный RNG для использования в UnitPlanner (TASK-035),
// TerrainAffinity и будущих задачах (TASK-034). Статeless между вызовами — создаётся
// с нужным seed и используется один раз per выбор (replay-safe, нет глобального состояния).
//
// Алгоритм: SplitMix64 (Sebastiano Vigna, 2015). 64-bit, period 2^64.
// Ссылка: http://xoshiro.di.unimi.it/splitmix64.c

struct SplitMix64: RandomNumberGenerator {

    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }

    /// Возвращает Double в полуоткрытом интервале [0, 1).
    mutating func nextUnit() -> Double {
        // Берём 53 старших бита (мантисса Double) и делим на 2^53.
        let raw = next()
        return Double(raw >> 11) * (1.0 / 9007199254740992.0)
    }
}

// MARK: - Seed helpers

/// FNV-1a (32-bit variant, финально расширяется в UInt64) hash для детерминированного seed.
/// Используется UnitPlanner: seed = fnv1a(idx, cat.rawValue, biome?.rawValue ?? "nil").
func fnv1a(combining values: [String]) -> UInt64 {
    var hash: UInt64 = 14695981039346656037   // FNV offset basis (64-bit)
    let prime: UInt64 = 1099511628211          // FNV prime (64-bit)
    for value in values {
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        // Разделитель между значениями (исключает «aab» == «aa» + «b»).
        hash ^= 0xFF
        hash = hash &* prime
    }
    return hash
}
