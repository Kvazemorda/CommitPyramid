import Foundation

struct DistrictPlanner {

    // MARK: - Spiral helper

    /// Базовая точка спирали — около середины карты, рядом с магистралью (gy ≈ rows/2).
    /// 256×256 карта → центр (128, 128). С шагом 14 кварталы укладываются плотно вдоль дороги,
    /// branch от origin до магистрали — короткий (≤ 14 тайлов).
    private static let spiralCenter = GridPoint(x: 128, y: 128)

    /// Возвращает GridPoint спирали для заданного индекса (без учёта биомов).
    /// `internal` (не `private`) — используется в тестах через @testable import.
    func spiralPoint(index: Int) -> GridPoint {
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
    func allocateNextOrigin(
        currentIndex: Int,
        biomeReader: BiomeMapReader?,
        preferredBiomes: [BiomeKind] = []
    ) -> (origin: GridPoint, newIndex: Int) {
        guard let reader = biomeReader else {
            // Нет карты биомов — старое поведение (back-compat до TASK-026).
            return (spiralPoint(index: currentIndex), currentIndex)
        }

        let maxAttempts = currentIndex + 10_000
        var idx = currentIndex
        var origin = spiralPoint(index: idx)

        // BUG-009: пропускаем водные клетки.
        while reader.biome(atX: origin.x, y: origin.y).isWater && idx < maxAttempts {
            idx += 1
            origin = spiralPoint(index: idx)
        }

        // TASK-030c F-15: biome-aware preference filter.
        // Если задан список предпочтительных биомов — сканируем первые 20 кандидатов
        // начиная с currentIndex, ищем первую не-водную клетку в preferredBiomes.
        // Если ни одна не подошла — fallback на уже найденный (water-skipped) origin.
        if !preferredBiomes.isEmpty {
            let preferredSet = Set(preferredBiomes)
            let scanLimit = currentIndex + 20
            var scanIdx = currentIndex
            while scanIdx <= scanLimit {
                let candidate = spiralPoint(index: scanIdx)
                let b = reader.biome(atX: candidate.x, y: candidate.y)
                if !b.isWater && preferredSet.contains(b) {
                    return (candidate, scanIdx)
                }
                scanIdx += 1
            }
            // Fallback: ни один из 20 кандидатов не в предпочтительном биоме —
            // возвращаем уже найденный water-skipped origin.
        }

        // Если все 10 000 клеток оказались водой — возвращаем последнюю найденную позицию
        // без дополнительного инкремента (карта целиком водная — edge case).
        return (origin, idx)
    }

    // MARK: - Allocation along magistrale

    /// Кладёт origin В ЦЕНТРЕ карты, вдоль магистрали: первые 2 квартала по обе стороны от
    /// центра mag, далее «слоями» по uSide=±1 (forward/backward вдоль mag), vSide=±1 (R/L от mag).
    ///
    /// - Parameters:
    ///   - currentIndex: счётчик кварталов из CityState.
    ///   - mainRoadCells: упорядоченные клетки магистрали.
    ///   - biomeReader: для пропуска водных клеток.
    /// - Returns: (origin, newIndex). Если магистраль пуста — fallback к spiralPoint.
    func allocateAlongMagistrale(
        currentIndex: Int,
        mainRoadCells: [GridPoint],
        biomeReader: BiomeMapReader?
    ) -> (origin: GridPoint, newIndex: Int) {
        guard !mainRoadCells.isEmpty else {
            return allocateNextOrigin(currentIndex: currentIndex, biomeReader: biomeReader)
        }

        let mag = mainRoadCells
        let centerIdx    = mag.count / 2
        let stepAlongMag = 8       // > 2*halfW для непересечения соседних петель
        let offsetPerp   = 3       // origin отстоит на 3 клетки от mag по перпендикуляру (v=3 внутри loop)

        let maxAttempts = currentIndex + 1_000
        var idx = currentIndex
        while idx < maxAttempts {
            let layer: Int
            let uSide: Int   // +1 forward вдоль mag (+gx), -1 backward (-gx)
            let vSide: Int   // +1 ABOVE mag (+gy → к LEFT/TOP по экрану), -1 BELOW (-gy → к BOTTOM/RIGHT)
            if idx == 0 {
                layer = 0; uSide = 0; vSide = 1
            } else if idx == 1 {
                layer = 0; uSide = 0; vSide = -1
            } else {
                let i = idx - 2
                layer = i / 4 + 1
                let sub = i % 4
                uSide = (sub / 2 == 0) ? 1 : -1
                vSide = (sub % 2 == 0) ? 1 : -1
            }
            let magIdx = centerIdx + uSide * layer * stepAlongMag
            guard magIdx >= 0, magIdx < mag.count else {
                idx += 1
                continue
            }
            let m = mag[magIdx]
            // Магистраль горизонтальна (gy=midY), перпендикуляр в гриде — ось ±gy.
            let origin = GridPoint(
                x: m.x,
                y: m.y + vSide * offsetPerp
            )

            if let reader = biomeReader, reader.biome(atX: origin.x, y: origin.y).isWater {
                idx += 1
                continue
            }
            return (origin, idx)
        }
        return (mag[centerIdx], idx)
    }
}
