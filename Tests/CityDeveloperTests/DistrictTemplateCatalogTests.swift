import XCTest
@testable import CommitPyramid

/// Тесты модели DistrictTemplate и каталога DistrictTemplateCatalog (TASK-047, F-25).
final class DistrictTemplateCatalogTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Сбрасываем кеш перед каждым тестом для изоляции.
        DistrictTemplateCatalog.resetCache()
    }

    // MARK: - 1. Загрузка египетских шаблонов

    /// Все 5 египетских шаблонов загружаются из Bundle.
    func testLoadsAllEgyptianTemplates() {
        let templates = DistrictTemplateCatalog.byFamily("egyptian")
        XCTAssertEqual(
            templates.count, 5,
            "Ожидаем ровно 5 египетских шаблонов, получено: \(templates.count)"
        )
    }

    // MARK: - 2. Нет пересекающихся слотов

    /// validate() возвращает nil для каждого загруженного шаблона.
    /// (Guard: catalog не должен был загрузить невалидные, но проверяем явно.)
    func testNoOverlappingSlots() {
        let templates = DistrictTemplateCatalog.all()
        XCTAssertFalse(templates.isEmpty, "Catalog не должен быть пустым")
        for template in templates {
            let error = DistrictTemplateCatalog.validate(template)
            XCTAssertNil(
                error,
                "Шаблон '\(template.name)' не прошёл валидацию: \(error ?? "")"
            )
        }
    }

    // MARK: - 3. Покрытие stage 1..5

    /// Для каждого stage 1..5 в egyptian-family есть хотя бы один шаблон.
    func testStageCoverageOneToFive() {
        for stage in 1...5 {
            let stageTemplates = DistrictTemplateCatalog.byStage(stage, family: "egyptian")
            XCTAssertGreaterThanOrEqual(
                stageTemplates.count, 1,
                "Stage \(stage) egyptian: ожидаем ≥1 шаблон, нашли 0"
            )
        }
    }

    // MARK: - 4. biomePreference валидны

    /// Все значения biomePreference декодированы как BiomeKind (тавтология после decode,
    /// но явный guard на случай расхождения типов).
    func testBiomePreferenceValid() {
        let templates = DistrictTemplateCatalog.all()
        XCTAssertFalse(templates.isEmpty, "Catalog не должен быть пустым")
        // BiomeKind.allCases для быстрой проверки
        let validBiomes = Set(BiomeKind.allCases.map(\.rawValue))
        for template in templates {
            for biome in template.biomePreference {
                XCTAssertTrue(
                    validBiomes.contains(biome.rawValue),
                    "Шаблон '\(template.name)': недопустимый biome '\(biome.rawValue)'"
                )
            }
        }
    }

    // MARK: - 5. Роли слотов валидны

    /// Все role в каждом шаблоне входят в SlotRole.allCases (тавтология после decode).
    func testRolesValid() {
        let templates = DistrictTemplateCatalog.all()
        XCTAssertFalse(templates.isEmpty, "Catalog не должен быть пустым")
        let validRoles = Set(SlotRole.allCases.map(\.rawValue))
        for template in templates {
            for slot in template.slots {
                XCTAssertTrue(
                    validRoles.contains(slot.role.rawValue),
                    "Шаблон '\(template.name)': недопустимая role '\(slot.role.rawValue)' в (\(slot.x),\(slot.y))"
                )
            }
        }
    }

    // MARK: - 6. Инвариант прогрессии: slots(stage N) ⊆ slots(stage N+1)

    /// Каждый слот stage N должен присутствовать в stage N+1 с точно теми же x, y, role, footprint.
    /// Критический инвариант для TASK-049 migration.
    func testStageProgressionPreservesSlots() {
        for n in 1...4 {
            guard let stageN = DistrictTemplateCatalog.byStage(n, family: "egyptian").first,
                  let stageNext = DistrictTemplateCatalog.byStage(n + 1, family: "egyptian").first else {
                XCTFail("Не удалось загрузить stage \(n) или stage \(n + 1) из egyptian")
                continue
            }

            for slot in stageN.slots {
                let found = stageNext.slots.contains { next in
                    next.x == slot.x &&
                    next.y == slot.y &&
                    next.role == slot.role &&
                    next.footprint.width == slot.footprint.width &&
                    next.footprint.height == slot.footprint.height
                }
                XCTAssertTrue(
                    found,
                    "slot (\(slot.x),\(slot.y),\(slot.role.rawValue),\(slot.footprint.width)×\(slot.footprint.height)) " +
                    "из stage \(n) отсутствует или изменён в stage \(n + 1); " +
                    "нарушает инвариант для TASK-049 migration"
                )
            }
        }
    }

    // MARK: - 7. bbox не уменьшается между stage'ами

    /// maxX и maxY не уменьшаются при переходе stage N → stage N+1.
    func testStageProgressionBboxNonShrinking() {
        for n in 1...4 {
            guard let stageN = DistrictTemplateCatalog.byStage(n, family: "egyptian").first,
                  let stageNext = DistrictTemplateCatalog.byStage(n + 1, family: "egyptian").first else {
                XCTFail("Не удалось загрузить stage \(n) или stage \(n + 1) из egyptian")
                continue
            }

            XCTAssertGreaterThanOrEqual(
                stageNext.width, stageN.width,
                "width уменьшился: stage \(n) width=\(stageN.width), stage \(n + 1) width=\(stageNext.width)"
            )
            XCTAssertGreaterThanOrEqual(
                stageNext.height, stageN.height,
                "height уменьшился: stage \(n) height=\(stageN.height), stage \(n + 1) height=\(stageNext.height)"
            )
        }
    }
}
