import XCTest
@testable import CommitPyramid

/// TASK-057 F-15 / BUG-008: property-тесты на сбалансированное распределение биомов.
///
/// AC из задачи:
/// - `test_TenSeeds_AfterRetry_AllBalanced`: для 10 захардкоженных seeds после
///   retry (до 5 попыток на seed: trySeed = seed, seed+1, …, seed+4) хотя бы
///   одна попытка даёт `outcome.balanced == true`. Если хоть один seed fail
///   после 5 retry — тест fail.
/// - `test_TenSeeds_WithoutRetry_MeasureBaseline`: информационный counter
///   «сколько проходят БЕЗ retry» (не fail). Пишется в консоль для observability.
final class BiomeDistributionPropertyTests: XCTestCase {

    /// Захардкоженные seeds, на которых property инвариантов должен держаться.
    private let seeds: [Int64] = [
        1, 42, 100, 1024, 9999, 12345, 67890, 314159, 271828, 1000000
    ]

    /// Сколько попыток (seed, seed+1, …) допускается в retry.
    /// Должно совпадать с `WorldMapProvider.maxRetryAttempts`.
    private let retryAttempts = WorldMapProvider.maxRetryAttempts

    /// Для каждого из 10 захардкоженных seeds симулируем retry: пробуем
    /// `seed, seed+1, …, seed+4`. Если хотя бы один из них даёт `balanced` →
    /// seed «прошёл». Ожидание: 10/10.
    func test_TenSeeds_AfterRetry_AllBalanced() throws {
        var failedSeeds: [Int64] = []
        for seed in seeds {
            var success = false
            for attempt in 0 ..< retryAttempts {
                let trySeed = seed &+ Int64(attempt)
                let noise = NoiseFieldGenerator.generate(seed: trySeed, size: NoiseMap.defaultSize)
                do {
                    let outcome = try BiomeClassifier.classify(world: noise, strict: false)
                    if outcome.balanced {
                        success = true
                        break
                    }
                } catch {
                    XCTFail("unexpected throw for seed=\(trySeed): \(error)")
                    return
                }
            }
            if !success { failedSeeds.append(seed) }
        }
        XCTAssertTrue(
            failedSeeds.isEmpty,
            "seeds failed after \(retryAttempts) retries: \(failedSeeds)"
        )
    }

    /// Информационный замер: сколько из 10 seeds проходят БЕЗ retry.
    /// Не fail при <10 — просто пишет в консоль для observability «насколько
    /// retry реально нужен».
    func test_TenSeeds_WithoutRetry_MeasureBaseline() throws {
        var passes = 0
        for seed in seeds {
            let noise = NoiseFieldGenerator.generate(seed: seed, size: NoiseMap.defaultSize)
            do {
                let outcome = try BiomeClassifier.classify(world: noise, strict: false)
                if outcome.balanced { passes += 1 }
            } catch {
                XCTFail("unexpected throw for baseline seed=\(seed): \(error)")
                return
            }
        }
        print("BiomeDistributionPropertyTests baseline pass rate (no retry): \(passes)/\(seeds.count)")
    }
}
