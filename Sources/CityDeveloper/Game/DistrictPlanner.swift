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
        preferredBiomes: [BiomeKind] = [],
        otherProjectsClaims: Set<GridPoint> = [],
        minDistrictRadius: Int = 8
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

        // TASK-056 BUG-022: пропускаем origin'ы в Чебышёвской окрестности
        // minDistrictRadius от любой клетки другого проекта.
        // Порядок (water-skip → cross-project-skip → preferred-biome-scan):
        // water — hard-block, cross-project — hard-block, preferred-biome — soft.
        while idx < maxAttempts {
            let tooClose = otherProjectsClaims.contains { cell in
                max(abs(cell.x - origin.x), abs(cell.y - origin.y)) < minDistrictRadius
            }
            if !tooClose { break }
            idx += 1
            origin = spiralPoint(index: idx)
            // Повторная проверка water-skip после bump'а cross-project skip.
            while reader.biome(atX: origin.x, y: origin.y).isWater && idx < maxAttempts {
                idx += 1
                origin = spiralPoint(index: idx)
            }
        }

        // TASK-030c F-15: biome-aware preference filter.
        // TASK-056: scanStart = idx (после water+cross-skip), а не currentIndex.
        // Намеренно: cross-project — hard-block, preferred-biome — soft-preference;
        // preferred-скан не должен возвращаться на индексы, которые уже отвергнуты
        // как water или как лежащие в радиусе чужого квартала.
        if !preferredBiomes.isEmpty {
            let preferredSet = Set(preferredBiomes)
            let scanStart = idx
            let scanLimit = scanStart + 20
            var scanIdx = scanStart
            while scanIdx <= scanLimit {
                let candidate = spiralPoint(index: scanIdx)
                let b = reader.biome(atX: candidate.x, y: candidate.y)
                let candidateTooClose = otherProjectsClaims.contains { cell in
                    max(abs(cell.x - candidate.x), abs(cell.y - candidate.y)) < minDistrictRadius
                }
                if !b.isWater && !candidateTooClose && preferredSet.contains(b) {
                    return (candidate, scanIdx)
                }
                scanIdx += 1
            }
            // Fallback: ни один из 20 кандидатов не в предпочтительном биоме —
            // возвращаем уже найденный water+cross-skipped origin.
        }

        // Если все 10 000 клеток оказались водой/занятыми — логируем warning и возвращаем
        // последнюю найденную позицию без дополнительного инкремента (edge case backstop).
        if idx >= maxAttempts {
            ErrorsLog.write(
                "DistrictPlanner.allocateNextOrigin: no land cell within spiral radius after " +
                "\(idx - currentIndex) attempts; returning defensive fallback at \(origin)"
            )
        }
        return (origin, idx)
    }

    // MARK: - Allocation along magistrale

    /// Порог: первые N кварталов идут вдоль магистрали (старая логика),
    /// с (N+1)-го — branching-ответвления от магистрали под прямым углом.
    static let branchingThreshold = 3

    /// Кладёт origin В ЦЕНТРЕ карты, вдоль магистрали: первые N (branchingThreshold) кварталов
    /// идут вдоль mag (старая ветка); начиная с индекса branchingThreshold — branching-ветка:
    /// origin уходит перпендикулярно от магистрали на perpOffset=minDistrictRadius клеток.
    ///
    /// Branching формула (MAG-HORIZONTAL ASSUMPTION: mag по gy=midY):
    ///   i = idx - branchingThreshold
    ///   layer = i / 4 + 1                      // 1,1,1,1, 2,2,2,2 ...
    ///   sub = i % 4
    ///   uSide = (sub / 2 == 0) ? +1 : -1       // forward/backward по mag.x
    ///   vSide = (sub % 2 == 0) ? +1 : -1       // выше/ниже mag.y
    ///   magIdx = centerIdx + uSide * layer * stepAlongMag
    ///   perpOffset = minDistrictRadius * layer  // 8, 16, 24 …
    ///   origin = (m.x, m.y + vSide * perpOffset)
    ///
    /// - Parameters:
    ///   - currentIndex: счётчик кварталов из CityState.
    ///   - mainRoadCells: упорядоченные клетки магистрали.
    ///   - biomeReader: для пропуска водных клеток.
    /// - Returns: (origin, newIndex). Если магистраль пуста — fallback к spiralPoint.
    func allocateAlongMagistrale(
        currentIndex: Int,
        mainRoadCells: [GridPoint],
        biomeReader: BiomeMapReader?,
        otherProjectsClaims: Set<GridPoint> = [],
        minDistrictRadius: Int = 8
    ) -> (origin: GridPoint, newIndex: Int) {
        guard !mainRoadCells.isEmpty else {
            return allocateNextOrigin(
                currentIndex: currentIndex,
                biomeReader: biomeReader,
                otherProjectsClaims: otherProjectsClaims,
                minDistrictRadius: minDistrictRadius
            )
        }

        let mag = mainRoadCells
        let centerIdx    = mag.count / 2
        let stepAlongMag = 8       // > 2*halfW для непересечения соседних петель
        let offsetPerp   = 3       // along-mag ветка: origin на 3 клетки от mag (v=3 внутри loop)

        let maxAttempts = currentIndex + 1_000
        var idx = currentIndex
        while idx < maxAttempts {
            let origin: GridPoint

            if idx < Self.branchingThreshold {
                // --- Старая ветка: вдоль магистрали ---
                let layer: Int
                let uSide: Int   // +1 forward вдоль mag (+gx), -1 backward (-gx)
                let vSide: Int   // +1 ABOVE mag (+gy), -1 BELOW (-gy)
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
                // MAG-HORIZONTAL ASSUMPTION: mag по gy=midY, перпендикуляр — ось ±gy.
                origin = GridPoint(x: m.x, y: m.y + vSide * offsetPerp)
            } else {
                // --- Branching ветка: перпендикулярно от магистрали ---
                let i = idx - Self.branchingThreshold
                let layer = i / 4 + 1
                let sub   = i % 4
                let uSide = (sub / 2 == 0) ? 1 : -1
                let vSide = (sub % 2 == 0) ? 1 : -1
                let magIdx = centerIdx + uSide * layer * stepAlongMag
                guard magIdx >= 0, magIdx < mag.count else {
                    idx += 1
                    continue
                }
                let m = mag[magIdx]
                let perpOffset = minDistrictRadius * layer   // 8, 16, 24 …
                // MAG-HORIZONTAL ASSUMPTION: перпендикуляр — ось ±gy.
                let candidateY = m.y + vSide * perpOffset
                // Граница карты: проверяем что origin не выходит за пределы.
                // Для branching нет rows-параметра, поэтому используем простое bounds-check
                // через biomeReader (если nil — разрешаем). Настоящий bound-check —
                // через water-skip ниже (sea = граница карты).
                guard candidateY >= 0 else {
                    idx += 1
                    continue
                }
                origin = GridPoint(x: m.x, y: candidateY)
            }

            if let reader = biomeReader, reader.biome(atX: origin.x, y: origin.y).isWater {
                idx += 1
                continue
            }
            // TASK-056 BUG-022: hard-block для cross-project overlap.
            // Чебышёвская окрестность minDistrictRadius от любой чужой клетки.
            let tooClose = otherProjectsClaims.contains { cell in
                max(abs(cell.x - origin.x), abs(cell.y - origin.y)) < minDistrictRadius
            }
            if tooClose {
                idx += 1
                continue
            }
            return (origin, idx)
        }
        // maxAttempts exhausted — логируем warning (defensive fallback на центр магистрали).
        ErrorsLog.write(
            "DistrictPlanner.allocateAlongMagistrale: maxAttempts \(maxAttempts - currentIndex) " +
            "exhausted; returning defensive fallback at mag[\(centerIdx)]=\(mag[centerIdx])"
        )
        return (mag[centerIdx], idx)
    }
}
