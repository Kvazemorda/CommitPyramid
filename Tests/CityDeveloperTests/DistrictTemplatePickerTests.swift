import XCTest
@testable import CommitPyramid

final class DistrictTemplatePickerTests: XCTestCase {

    func test_ReturnsNilForUnknownFamily() {
        // После TASK-051: неизвестная family → availability fallback на "egyptian".
        // Nil возвращается только когда stage 99 (нет шаблонов для этого stage).
        let result = DistrictTemplatePicker.pick(
            stage: 1, family: "klingon", biome: nil, seed: 1
        )
        // Availability fallback → egyptian → шаблон stage 1 существует
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.family, "egyptian")
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

    func test_AutoFamily_MeadowMapsToEgyptian() {
        let t = DistrictTemplatePicker.pick(stage: 1, family: "auto", biome: .meadow, seed: 1)
        XCTAssertEqual(t?.family, "egyptian")  // mapping meadow → egyptian, шаблон существует
    }

    func test_AutoFamily_DesertMapsToEgyptian() {
        let t = DistrictTemplatePicker.pick(stage: 1, family: "auto", biome: .desert, seed: 1)
        XCTAssertEqual(t?.family, "egyptian")
    }

    func test_AutoFamily_MountainFallsBackToEgyptianInMVP() {
        // mapping mountain → roman, но roman нет в MVP → availability fallback egyptian + warning
        let t = DistrictTemplatePicker.pick(stage: 1, family: "auto", biome: .mountain, seed: 1)
        XCTAssertEqual(t?.family, "egyptian")
    }

    func test_AutoFamily_SeaFallsBackToEgyptianInMVP() {
        let t = DistrictTemplatePicker.pick(stage: 1, family: "auto", biome: .sea, seed: 1)
        XCTAssertEqual(t?.family, "egyptian")
    }

    func test_AutoFamily_NilBiomeMapsToEgyptian() {
        let t = DistrictTemplatePicker.pick(stage: 1, family: "auto", biome: nil, seed: 1)
        XCTAssertEqual(t?.family, "egyptian")
    }

    func test_InvalidFamilyFallsBackToEgyptian() {
        // Пользователь выбрал "roman" в Settings, но в MVP roman нет в catalog.
        // Availability fallback переводит на "egyptian", шаблон возвращается с family="egyptian".
        let t = DistrictTemplatePicker.pick(stage: 1, family: "roman", biome: .meadow, seed: 1)
        XCTAssertEqual(t?.family, "egyptian")
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
