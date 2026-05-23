import Foundation
import GameplayKit

/// Детерминированный генератор трёх шумовых полей карты мира через GameplayKit Perlin noise.
/// GKPerlinNoiseSource(seed: Int32) даёт воспроизводимые значения при одном и том же seed
/// на одной и той же версии macOS SDK.
enum NoiseFieldGenerator {

    // MARK: - Параметры шума (стандартный «плавный» Perlin для плавных биомных переходов)
    private static let frequency: Double = 1.0
    private static let octaveCount: Int = 4
    private static let persistence: Double = 0.5
    private static let lacunarity: Double = 2.0

    // MARK: - splitmix64-константы для разных seed на каждое поле (EC4: seed=0/min/max)
    // Эти константы гарантируют разные паттерны для height/temperature/humidity
    // даже при граничных значениях Int64.
    private static let tempOffset: Int64 = Int64(bitPattern: 0x9E37_79B9_7F4A_7C15)
    private static let humOffset: Int64  = Int64(bitPattern: 0x6C62_272E_07BB_0142)

    /// Генерирует карту из трёх полей (высота, температура, влажность) детерминированно.
    /// - Parameters:
    ///   - seed: Базовый seed мира. Любое Int64 значение (0, min, max — всё корректно).
    ///   - size: Размер карты (по умолчанию 256). Возвращается NoiseMap с size×size клетками.
    /// - Returns: Готовая NoiseMap с полями в диапазоне 0.0...1.0.
    static func generate(seed: Int64, size: Int = NoiseMap.defaultSize) -> NoiseMap {
        let heightSeed  = Int32(truncatingIfNeeded: seed)
        let tempSeed    = Int32(truncatingIfNeeded: seed &+ tempOffset)
        let humSeed     = Int32(truncatingIfNeeded: seed &+ humOffset)

        let heightField      = sampleField(seed: heightSeed, size: size)
        let temperatureField = sampleField(seed: tempSeed,   size: size)
        let humidityField    = sampleField(seed: humSeed,    size: size)

        return NoiseMap(
            version: NoiseMap.currentVersion,
            seed: seed,
            size: size,
            height: heightField,
            temperature: temperatureField,
            humidity: humidityField
        )
    }

    // MARK: - Private

    /// Выборка одного поля шума размером size×size в диапазоне [0, 1].
    private static func sampleField(seed: Int32, size: Int) -> [Float] {
        let source = GKPerlinNoiseSource(
            frequency: frequency,
            octaveCount: octaveCount,
            persistence: persistence,
            lacunarity: lacunarity,
            seed: seed
        )
        let noise = GKNoise(source)
        let noiseMap = GKNoiseMap(
            noise,
            size: vector_double2(1.0, 1.0),
            origin: .zero,
            sampleCount: vector_int2(Int32(size), Int32(size)),
            seamless: false
        )

        var field = [Float](repeating: 0, count: size * size)
        for y in 0 ..< size {
            for x in 0 ..< size {
                // GKNoiseMap возвращает значения в [-1, +1] → нормализуем в [0, 1]
                let raw = noiseMap.value(at: vector_int2(Int32(x), Int32(y)))
                let normalized = (raw + 1.0) / 2.0
                field[y * size + x] = max(0.0, min(1.0, normalized))
            }
        }
        return field
    }
}
