import Foundation

struct DistrictPlanner {

    // MARK: - Spiral helper

    /// Базовая точка спирали — около середины карты, рядом с магистралью (gy ≈ rows/2).
    /// 256×256 карта → центр (128, 128). С шагом 14 кварталы укладываются плотно вдоль дороги,
    /// branch от origin до магистрали — короткий (≤ 14 тайлов).
    private static let spiralCenter = GridPoint(x: 128, y: 128)

    /// Возвращает GridPoint спирали для заданного индекса (без учёта биомов).
    private func spiralPoint(index: Int) -> GridPoint {
        if index == 0 { return Self.spiralCenter }

        let layer = Int(((Double(index) + 1).squareRoot() + 1) / 2)
        let layerSize = 2 * layer
        let firstInLayer = (2 * layer - 1) * (2 * layer - 1)
        let offsetInLayer = index - firstInLayer
        let side = offsetInLayer / layerSize
        let stepInSide = offsetInLayer % layerSize

        var x = 0, y = 0
        switch side {
        case 0: x = layer; y = -layer + 1 + stepInSide
        case 1: x = layer - 1 - stepInSide; y = layer
        case 2: x = -layer; y = layer - 1 - stepInSide
        case 3: x = -layer + 1 + stepInSide; y = -layer
        default: break
        }

        let spacing = 14
        return GridPoint(
            x: Self.spiralCenter.x + x * spacing,
            y: Self.spiralCenter.y + y * spacing
        )
    }

    // MARK: - BUG-009: allocateNextOrigin with biome awareness

    /// Возвращает следующий origin по спирали и итоговый индекс (уже после skip).
    ///
    /// - Parameters:
    ///   - currentIndex: текущий счётчик спирали из CityState.
    ///   - biomeReader: если nil — fallback на старое поведение (разрешаем любую клетку).
    ///                  если задан — пропускаем водные клетки (.sea / .river).
    /// - Returns: кортеж (origin: GridPoint, newIndex: Int), где newIndex = idx финального шага.
    ///            Caller должен сохранить newIndex в state.nextDistrictIndex.
    func allocateNextOrigin(currentIndex: Int, biomeReader: BiomeMapReader?) -> (origin: GridPoint, newIndex: Int) {
        guard let reader = biomeReader else {
            // Нет карты биомов — старое поведение (back-compat до TASK-026).
            return (spiralPoint(index: currentIndex), currentIndex)
        }

        let maxAttempts = currentIndex + 10_000
        var idx = currentIndex
        var origin = spiralPoint(index: idx)

        while reader.biome(atX: origin.x, y: origin.y).isWater && idx < maxAttempts {
            idx += 1
            origin = spiralPoint(index: idx)
        }

        // Если все 10 000 клеток оказались водой — возвращаем последнюю найденную позицию
        // без дополнительного инкремента (карта целиком водная — edge case).
        return (origin, idx)
    }
}
