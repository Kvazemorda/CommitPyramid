import XCTest
@testable import CommitPyramid

final class DistrictTemplatePickerTests: XCTestCase {

    func test_ReturnsNilForUnknownFamily() {
        let result = DistrictTemplatePicker.pick(
            stage: 1, family: "klingon", biome: nil, seed: 1
        )
        XCTAssertNil(result)
    }

    func test_ReturnsNilForUnsupportedStage() {
        let result = DistrictTemplatePicker.pick(
            stage: 99, family: "egyptian", biome: nil, seed: 1
        )
        XCTAssertNil(result)
    }

    func test_ReturnsEgyptianTemplateForStageOne() {
        let result = DistrictTemplatePicker.pick(
            stage: 1, family: "egyptian", biome: nil, seed: 42
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.family, "egyptian")
        XCTAssertEqual(result?.stage, 1)
    }

    func test_IsDeterministicForSameSeed() {
        let r1 = DistrictTemplatePicker.pick(
            stage: 1, family: "egyptian", biome: nil, seed: 12345)
        let r2 = DistrictTemplatePicker.pick(
            stage: 1, family: "egyptian", biome: nil, seed: 12345)
        XCTAssertEqual(r1?.name, r2?.name)
    }

    func test_AutoFamilyMapsToEgyptianMVP() {
        let result = DistrictTemplatePicker.pick(
            stage: 1, family: "auto", biome: .meadow, seed: 1
        )
        XCTAssertEqual(result?.family, "egyptian")
    }

    func test_MixedFamilyPicksFromAvailable() {
        let available = DistrictTemplateCatalog.availableFamilies()
        let result = DistrictTemplatePicker.pick(
            stage: 1, family: "mixed", biome: nil, seed: 7
        )
        XCTAssertNotNil(result)
        if let family = result?.family {
            XCTAssertTrue(available.contains(family),
                "Mixed picked family \(family) not in available \(available)")
        }
    }

    func test_BiomePreferenceFallbackWhenNoMatch() {
        // Все egyptian шаблоны имеют biomePreference [meadow, desert].
        // Pick с biome=.sea → filter уберёт всё → fallback на исходный
        // candidates → результат не nil.
        let result = DistrictTemplatePicker.pick(
            stage: 1, family: "egyptian", biome: .sea, seed: 1
        )
        XCTAssertNotNil(result, "Должен быть fallback когда biome не совпадает с preference")
    }
}
