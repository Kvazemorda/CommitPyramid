import Foundation

/// TASK-057 F-15: результат генерации (с учётом retry на bad-seed).
///
/// `actualSeed` может отличаться от `requestedSeed` (на 1..4) если первая
/// попытка дала несбалансированную карту. `finalBalanced == false` означает,
/// что все 5 попыток оказались плохими — выбран лучший (последний) fallback.
struct RegenerateOutcome {
    let map: NoiseMap
    let requestedSeed: Int64
    let actualSeed: Int64
    /// Фактическое число попыток (1…5).
    let attempts: Int
    let finalBalanced: Bool
    let distribution: [BiomeKind: Int]
}

/// Фасад/координатор бутстрапа карты мира.
/// Создаётся в AppDelegate.applicationDidFinishLaunching до GameScene,
/// чтобы при didMove(to:) карта уже была доступна.
///
/// Порядок инициализации:
/// 1. Прочитать seed из WorldSeedStore; если нет — сгенерировать и сохранить.
/// 2. Прочитать карту из WorldMapStore; если нет/несовпадение → перегенерировать
///    через `generateWithRetry` (TASK-057: до 5 попыток на bad seed) и сохранить.
/// 3. Готовая NoiseMap оседает в `provider.map`, фактически использованный
///    seed — в `provider.seed`.
final class WorldMapProvider {

    /// Максимальное число попыток retry на bad seed (TASK-057).
    static let maxRetryAttempts: Int = 5

    /// Текущая карта мира. Гарантированно не nil после инициализации.
    private(set) var map: NoiseMap

    /// Фактически использованный seed мира (после retry, если был).
    private(set) var seed: Int64

    /// Запрошенный seed последней операции (для UI requested→actual).
    /// `nil` если использовалась cached worldmap.json (retry не запускался).
    private(set) var lastRequestedSeed: Int64?

    /// Фактическое число попыток последней операции (1…5).
    /// `nil` если использовалась cached worldmap.json.
    private(set) var lastAttempts: Int?

    private let mapStore: WorldMapStore

    init(
        seedStore: WorldSeedStore.Type = WorldSeedStore.self,
        mapStore: WorldMapStore = WorldMapStore()
    ) {
        self.mapStore = mapStore

        // Шаг 1: получить или сгенерировать seed.
        let resolvedSeed: Int64
        if let saved = seedStore.loadSeed() {
            resolvedSeed = saved
        } else {
            resolvedSeed = Int64.random(in: .min ... .max)
            seedStore.saveSeed(resolvedSeed)
        }

        // Шаг 2: загрузить карту или перегенерировать (с retry).
        let existingMap = mapStore.load()
        if let loaded = existingMap,
           loaded.seed == resolvedSeed,
           loaded.version == NoiseMap.currentVersion,
           loaded.size == NoiseMap.defaultSize {
            // Cached worldmap.json — источник истины для replay determinism (F-03).
            // НЕ делаем retry даже если он несбалансирован.
            self.seed = resolvedSeed
            self.map = loaded
            self.lastRequestedSeed = nil
            self.lastAttempts = nil
        } else {
            if existingMap != nil {
                ErrorsLog.write("WorldMapProvider: worldmap mismatch (seed or version/size), regenerating")
            }
            let outcome = Self.generateWithRetry(requested: resolvedSeed)
            mapStore.save(outcome.map)
            seedStore.saveSeed(outcome.actualSeed)
            self.seed = outcome.actualSeed
            self.map = outcome.map
            self.lastRequestedSeed = outcome.requestedSeed
            self.lastAttempts = outcome.attempts
        }
    }

    /// Перегенерирует карту с новым seed (или с тем же, если newSeed == nil).
    /// Предназначен для TASK-030 («Сбросить карту»).
    /// TASK-057: возвращает `RegenerateOutcome` с requested/actual seed после retry.
    @discardableResult
    func regenerate(newSeed: Int64? = nil) -> RegenerateOutcome {
        let requested = newSeed ?? Int64.random(in: .min ... .max)
        let outcome = Self.generateWithRetry(requested: requested)
        seed = outcome.actualSeed
        map = outcome.map
        mapStore.save(outcome.map)
        WorldSeedStore.saveSeed(outcome.actualSeed)
        lastRequestedSeed = outcome.requestedSeed
        lastAttempts = outcome.attempts
        return outcome
    }

    // MARK: - Retry helper

    /// TASK-057 F-15: пытается сгенерировать сбалансированную карту,
    /// инкрементируя seed до 5 раз. Non-throwing: при `sizeMismatch` (программный
    /// баг, NoiseMap.defaultSize фиксирован) — `fatalError`. При иных ошибках
    /// классификатора — лог и переход к следующей попытке.
    private static func generateWithRetry(requested: Int64) -> RegenerateOutcome {
        var lastBalancedSeed: Int64? = nil
        var lastBalancedMap: NoiseMap? = nil
        var lastBalancedOutcome: ClassificationOutcome? = nil

        var lastAnyMap: NoiseMap? = nil
        var lastAnyOutcome: ClassificationOutcome? = nil
        var lastAnySeed: Int64? = nil

        var attemptsUsed = 0
        var sizeMismatchHit = false

        for attempt in 0 ..< maxRetryAttempts {
            let trySeed = requested &+ Int64(attempt)
            let noise = NoiseFieldGenerator.generate(seed: trySeed, size: NoiseMap.defaultSize)
            attemptsUsed = attempt + 1

            do {
                let outcome = try BiomeClassifier.classify(world: noise, strict: false)
                lastAnyMap = noise
                lastAnyOutcome = outcome
                lastAnySeed = trySeed

                if outcome.balanced {
                    lastBalancedSeed = trySeed
                    lastBalancedMap = noise
                    lastBalancedOutcome = outcome
                    break
                } else {
                    ErrorsLog.write(
                        "WorldMapProvider attempt \(attempt + 1)/\(maxRetryAttempts) seed=\(trySeed) NOT balanced "
                        + "(dominant=\(String(format: "%.1f", outcome.dominantShare * 100))%, "
                        + "nonWater≥5%: \(outcome.nonWaterAboveThreshold))"
                    )
                }
            } catch BiomeClassifierError.sizeMismatch {
                ErrorsLog.write("WorldMapProvider FATAL sizeMismatch at seed=\(trySeed) — abort retry")
                sizeMismatchHit = true
                break
            } catch {
                ErrorsLog.write("WorldMapProvider attempt \(attempt + 1)/\(maxRetryAttempts) seed=\(trySeed) unexpected error: \(error)")
            }
        }

        // Выбор chosen-карты.
        let chosenMap: NoiseMap
        let actualSeed: Int64
        let chosenOutcome: ClassificationOutcome
        let finalBalanced: Bool

        if let bMap = lastBalancedMap, let bSeed = lastBalancedSeed, let bOut = lastBalancedOutcome {
            chosenMap = bMap
            actualSeed = bSeed
            chosenOutcome = bOut
            finalBalanced = true
        } else if let aMap = lastAnyMap, let aSeed = lastAnySeed, let aOut = lastAnyOutcome {
            chosenMap = aMap
            actualSeed = aSeed
            chosenOutcome = aOut
            finalBalanced = false
            ErrorsLog.write(
                "WorldMapProvider WARNING: all \(maxRetryAttempts) attempts NOT balanced, falling back to last try seed=\(actualSeed)"
            )
        } else {
            // sizeMismatch при первой же попытке — NoiseMap.defaultSize фиксирован,
            // в production-flow это невозможно.
            let suffix = sizeMismatchHit ? "sizeMismatch" : "unexpected"
            fatalError(
                "WorldMapProvider: no map produced (\(suffix)). NoiseMap.defaultSize is fixed; this should never happen in production."
            )
        }

        // Финальный structured лог по AC «Логирование» (requested/actual/attempts/distribution).
        let distributionStr = formatDistribution(chosenOutcome.distribution, total: chosenOutcome.total)
        ErrorsLog.write(
            "WorldMapProvider regenerate requested=\(requested) actual=\(actualSeed) "
            + "attempts=\(attemptsUsed) balanced=\(finalBalanced) distribution={\(distributionStr)}"
        )

        return RegenerateOutcome(
            map: chosenMap,
            requestedSeed: requested,
            actualSeed: actualSeed,
            attempts: attemptsUsed,
            finalBalanced: finalBalanced,
            distribution: chosenOutcome.distribution
        )
    }

    /// Форматирует распределение `meadow:20.5%,desert:30.2%,...` для лога.
    private static func formatDistribution(_ counts: [BiomeKind: Int], total: Int) -> String {
        guard total > 0 else { return "" }
        return BiomeKind.allCases.compactMap { kind -> String? in
            guard let c = counts[kind], c > 0 else { return nil }
            let pct = Double(c) / Double(total) * 100.0
            return "\(kind.rawValue):\(String(format: "%.1f", pct))%"
        }.joined(separator: ",")
    }
}
