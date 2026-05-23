import XCTest
@testable import CityDeveloper

final class NoiseFieldGeneratorTests: XCTestCase {

    // MARK: - Детерминизм (AC3)

    func testSameSeedProducesIdenticalMaps() {
        let map1 = NoiseFieldGenerator.generate(seed: 42)
        let map2 = NoiseFieldGenerator.generate(seed: 42)

        XCTAssertEqual(map1.height, map2.height, "height: одинаковый seed → идентичные значения")
        XCTAssertEqual(map1.temperature, map2.temperature, "temperature: одинаковый seed → идентичные значения")
        XCTAssertEqual(map1.humidity, map2.humidity, "humidity: одинаковый seed → идентичные значения")
    }

    func testDifferentSeedsProduceDifferentMaps() {
        let map1 = NoiseFieldGenerator.generate(seed: 42)
        let map2 = NoiseFieldGenerator.generate(seed: 43)

        XCTAssertNotEqual(map1.height, map2.height, "height: разный seed → разные значения")
        XCTAssertNotEqual(map1.temperature, map2.temperature, "temperature: разный seed → разные значения")
        XCTAssertNotEqual(map1.humidity, map2.humidity, "humidity: разный seed → разные значения")
    }

    // MARK: - Нормализация (AC2)

    func testAllValuesInZeroToOneRange() {
        let map = NoiseFieldGenerator.generate(seed: 1234)
        for v in map.height      { XCTAssertTrue(v >= 0.0 && v <= 1.0, "height out of range: \(v)") }
        for v in map.temperature { XCTAssertTrue(v >= 0.0 && v <= 1.0, "temperature out of range: \(v)") }
        for v in map.humidity    { XCTAssertTrue(v >= 0.0 && v <= 1.0, "humidity out of range: \(v)") }
    }

    // MARK: - Плавность (AC4)

    func testNeighbourCellsSmoothness() {
        let map = NoiseFieldGenerator.generate(seed: 7)
        let size = map.size
        var totalDelta: Float = 0
        var count: Int = 0
        // Выборка 1000 случайных пар соседей по горизонтали и вертикали
        var prng = SystemRandomNumberGenerator()
        for _ in 0 ..< 1000 {
            let x = Int.random(in: 0 ..< size - 1, using: &prng)
            let y = Int.random(in: 0 ..< size - 1, using: &prng)
            // Горизонтальная пара
            let dh = abs(map.height(at: x, y: y) - map.height(at: x + 1, y: y))
            totalDelta += dh
            count += 1
            // Вертикальная пара
            let dv = abs(map.height(at: x, y: y) - map.height(at: x, y: y + 1))
            totalDelta += dv
            count += 1
        }
        let avgDelta = totalDelta / Float(count)
        // Плавность: среднее изменение между соседними клетками < 0.15
        XCTAssertLessThan(avgDelta, 0.15, "Средняя дельта между соседями \(avgDelta) — карта слишком резкая")
    }

    // MARK: - Граничный clamp (EC3)

    func testOutOfBoundsAccessDoesNotCrash() {
        let map = NoiseFieldGenerator.generate(seed: 0)
        // Координаты за пределами — должны вернуть граничное значение без падения
        let h = map.height(at: -10, y: 500)
        XCTAssertTrue(h >= 0.0 && h <= 1.0, "height вне bounds должен вернуть граничное значение [0,1]")
        let t = map.temperature(at: -1, y: -1)
        XCTAssertTrue(t >= 0.0 && t <= 1.0)
        let hu = map.humidity(at: 1000, y: 1000)
        XCTAssertTrue(hu >= 0.0 && hu <= 1.0)
        // Верхняя граничная клетка должна совпадать с clamp'ed значением
        let expected = map.height(at: map.size - 1, y: map.size - 1)
        XCTAssertEqual(hu, map.humidity(at: map.size - 1, y: map.size - 1))
        _ = expected
    }

    // MARK: - Граничные seed (EC4)

    func testBoundarySeedsGenerateCorrectly() {
        for seed: Int64 in [0, Int64.min, Int64.max, -1, 1] {
            let map = NoiseFieldGenerator.generate(seed: seed)
            XCTAssertEqual(map.height.count, NoiseMap.defaultSize * NoiseMap.defaultSize,
                           "seed=\(seed): неверная длина height")
            XCTAssertEqual(map.temperature.count, NoiseMap.defaultSize * NoiseMap.defaultSize,
                           "seed=\(seed): неверная длина temperature")
            XCTAssertEqual(map.humidity.count, NoiseMap.defaultSize * NoiseMap.defaultSize,
                           "seed=\(seed): неверная длина humidity")
        }
    }

    // MARK: - Метаданные карты

    func testMapMetadata() {
        let map = NoiseFieldGenerator.generate(seed: 99)
        XCTAssertEqual(map.version, NoiseMap.currentVersion)
        XCTAssertEqual(map.seed, 99)
        XCTAssertEqual(map.size, NoiseMap.defaultSize)
    }
}
