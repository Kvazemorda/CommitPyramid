import Foundation

/// Детерминированная шумовая карта мира: seed + три плотных 2D-поля (высота, температура, влажность).
/// Каждое поле — row-major [Float] длиной size*size, все значения в диапазоне 0.0...1.0.
/// Намеренно отделена от CityState/event-log; живёт в sidecar-файле worldmap.json.
struct NoiseMap: Codable {

    static let currentVersion: Int = 1
    static let defaultSize: Int = 256

    let version: Int
    let seed: Int64
    let size: Int

    /// Row-major, index = y * size + x. Диапазон 0.0...1.0.
    let height: [Float]
    /// Row-major, index = y * size + x. Диапазон 0.0...1.0.
    let temperature: [Float]
    /// Row-major, index = y * size + x. Диапазон 0.0...1.0.
    let humidity: [Float]

    // MARK: - Accessors с граничным clamp (edge case EC3)

    /// Значение поля высоты в клетке (x, y). Координаты вне [0, size) → ближайшая граничная клетка.
    func height(at x: Int, y: Int) -> Float {
        height[clampedIndex(x: x, y: y)]
    }

    /// Значение поля температуры в клетке (x, y). Координаты вне [0, size) → ближайшая граничная клетка.
    func temperature(at x: Int, y: Int) -> Float {
        temperature[clampedIndex(x: x, y: y)]
    }

    /// Значение поля влажности в клетке (x, y). Координаты вне [0, size) → ближайшая граничная клетка.
    func humidity(at x: Int, y: Int) -> Float {
        humidity[clampedIndex(x: x, y: y)]
    }

    // MARK: - Private helpers

    private func clampedIndex(x: Int, y: Int) -> Int {
        let cx = max(0, min(size - 1, x))
        let cy = max(0, min(size - 1, y))
        return cy * size + cx
    }
}
