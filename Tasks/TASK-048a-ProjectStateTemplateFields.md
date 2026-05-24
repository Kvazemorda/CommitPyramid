# TASK-048a: `ProjectState` поля + `AppSettings.templateFamily` + persistence v4

## Связь
- **F-25** из Concept.md (шаблоны кварталов)
- **D-25** из Diff.md (часть 2.1/5 — фундамент для Picker/migration/era)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-24_

### Что хотим

Чисто данный слой для остального F-25: расширить `ProjectState` тремя
новыми полями (`templateName/templateFamily/eraLevel`) и добавить
`AppSettings.templateFamily` (+ persistence v3→v4 миграция). Без этого
TASK-048b/c не имеют, куда писать выбранный шаблон.

Этот шаг **полностью изолирован от логики**: только модель + сериализация
+ persistence. Никакой Picker, никакой UnitPlanner, никакая интеграция.

### Пользовательский сценарий

1. Разработчик добавляет поля → пересборка → код компилируется без правок
   в существующих местах (поля optional / default-значения).
2. На запуске игры старый `state.json` (без новых полей) загружается без
   ошибок; новые поля = nil/0.
3. На запуске игры старый `UserDefaults` (persistence v3, без
   templateFamily) → миграция v3→v4 проставляет templateFamily="auto".
4. Тесты подтверждают: round-trip Codable, миграция UserDefaults, default-значения.

### Acceptance criteria

- [ ] `ProjectState` (в `Sources/CityDeveloper/Data/CityState.swift:440-451`)
      расширен полями:
      - `var templateName: String?` (default nil)
      - `var templateFamily: String?` (default nil)
      - `var eraLevel: Int` (default 0)
- [ ] Codable backwards-compat: старый JSON без этих полей декодируется
      без ошибок, новые поля = nil/0. Достигается через `init(from:)`
      decoder с `try? decode` для optional полей и
      `(try? decode) ?? 0` для eraLevel.
- [ ] `SnapshotStore` версия snapshot bumped (если есть схема версии в
      `Data/SnapshotStore.swift` или `StateSnapshot.swift` — `currentVersion`
      инкрементируется; иначе backwards-compat достаточно).
- [ ] `AppSettings` (в `Sources/CityDeveloper/Data/AppSettings.swift`)
      расширен:
      - `var templateFamily: String` (default `"auto"`)
      - `var previewTemplateSilhouette: Bool` (default `false`)
- [ ] UserDefaults persistence v3 → v4 миграция:
      - Bump `version: 3 → 4` в `AppSettings.save()`.
      - На load: если ключа `templateFamily` нет в декодированном Persisted →
        дефолт "auto". При следующем `save()` запишется version:4 и поле
        templateFamily. (Сам load() ничего НЕ пишет — версия v4 появляется
        в UserDefaults только после первого save() с новой версией. Это
        стандартный AppSettings-паттерн в проекте, см. TASK-043 v2→v3.)
      - Без потери существующих настроек (`commitWeightMultiplier`,
        `taskWeightMultiplier`, `gitRepos`, и т.д.).
- [ ] Тесты `ProjectStateTemplateFieldsTests.swift`:
      - `testDefaultsForNewProject`: новый ProjectState (через init по умолчанию)
        имеет templateName=nil, templateFamily=nil, eraLevel=0.
      - `testCodableRoundtripWithNewFields`: encode → decode → поля совпадают.
      - `testCodableBackwardsCompatLegacyJSON`: декод JSON БЕЗ новых полей
        (фикстура — JSON-строка в тесте) → поля = nil/0, без ошибок.
- [ ] Тесты `AppSettingsV4MigrationTests.swift`:
      - `testDefaultTemplateFamilyIsAuto`: свежий AppSettings.load() с пустым
        UserDefaults → templateFamily == "auto".
      - `testV3ToV4MigrationPreservesOtherSettings`: засеять UserDefaults
        v3-значениями (commitWeightMultiplier=0.5, taskWeightMultiplier=2.0),
        load → templateFamily="auto", остальные значения сохранены.
      - `testTemplateFamilyPersistenceRoundtrip`: set "egyptian" → save →
        load → "egyptian".

### Что НЕ делаем (границы скоупа)

- НЕ создаём `DistrictTemplatePicker` — это TASK-048b.
- НЕ меняем `UnitPlanner` / `CityEngine` — это TASK-048c.
- НЕ добавляем Settings UI Picker — это TASK-051.
- НЕ добавляем `UnitKind.preferredSlotRole` mapping — это TASK-048b.

### Edge cases

- [ ] Старый snapshot v2 (до v3) — миграция уже работает через TASK-037,
      не трогаем.
- [ ] UserDefaults содержит мусор в `templateFamily` (например, "xyz") —
      на этом шаге не валидируем (это работа Picker'а в 048b); load
      просто читает как есть.
- [ ] `eraLevel` приходит из JSON как отрицательное число → принять как
      есть (валидация в TASK-050 EraRules).
- [ ] Test isolation: тесты используют `UserDefaults.standard` (как реальный
      AppSettings), в setUp сохраняют текущее значение ключа
      `com.commitpyramid.app.settings`, в tearDown восстанавливают.
      **Trade-off:** если тест крашится между setUp и tearDown — production
      настройки удаляются на время следующего запуска приложения. Это
      принято намеренно — рефакторинг `AppSettings.load(defaults:)` параметра
      выходит за scope этой задачи (это micro-task в Backlog).

### Зависимости

- **Blocked-by:** TASK-047 ✅ (есть DistrictTemplate, можно ссылаться на
  имена шаблонов).
- **Soft-blocks:** TASK-048b (Picker), TASK-048c (Planner integration),
  TASK-049, TASK-050, TASK-051.

### Дизайн

Не применимо (только модель + сериализация).

### Done-критерий

_Из F-25:_ «ProjectState расширяется: templateName/templateFamily/eraLevel
сериализуются в state.json и unit_built events, replay восстанавливает
выбор шаблона детерминированно». Эта TASK даёт фундамент; реальная
запись templateName происходит в TASK-048b.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-24_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

**В коде уже есть (Explore TASK-048a):**
- `Sources/CityDeveloper/Data/CityState.swift:440-451` — `struct ProjectState: Codable`
  с 10 полями (id, name, createdAt, lastActivityAt, taskCount, stage, decayLevel,
  lastDecayLogged, districtOrigin, unitIds). **Автосинтез Codable** — добавление
  новых non-optional полей сломает декод старого JSON. Нужен явный `init(from:)`.
- `Sources/CityDeveloper/Game/CityEngine.swift:277-288` — единственное место
  создания `ProjectState`. Memberwise init. **Нужно добавить новые параметры со
  значениями по умолчанию**, иначе сломаем compile.
- `Sources/CityDeveloper/Data/AppSettings.swift:121-136` — `private struct Persisted: Codable`
  уже использует паттерн optional-полей для backwards-compat (catchUpIntervalMinutes,
  notesSources, gitRepos, commitWeightMultiplier, taskWeightMultiplier — все
  optional). Версия `version: 3` в `save()` (строка 105).
- `Sources/CityDeveloper/Data/AppSettings.swift:67-100` — `static func load()` —
  паттерн `decoded.foo ?? defaultValue`. **Для миграции v3→v4 нужно: добавить
  optional templateFamily/previewTemplateSilhouette в Persisted, бамп version: 4
  в save, ?? defaults в load.**
- `Sources/CityDeveloper/Data/AppSettings.swift:1-50` — `final class AppSettings:
  ObservableObject` с `@Published var` полями. Singleton отсутствует — создаётся
  через `AppSettings.load()` в `App/AppDelegate.swift:30`.
- `Tests/CityDeveloperTests/LegacyStateMigrationTests.swift` — паттерн backwards-compat
  тестов: фикстурный JSON-строкой → decode → проверка.
- `Sources/CityDeveloper/Data/StateSnapshot.swift:1-11` — `currentVersion = 1`,
  трогать НЕ нужно (это уровень всего CityState, не вложенного ProjectState).

**Связанные модули, не трогать:**
- `events.jsonl` — формат не зависит от новых полей (см. Explore п.3).
- `SnapshotStore` — load/save через `StateSnapshot.currentVersion` — версия не бампается.

**Что переиспользуем:** паттерн `decoded.X ?? default` из AppSettings.load(),
паттерн `try? container.decodeIfPresent(...) ?? default` для optional декода.

**Что нужно дописать:**
- `CityState.swift`: 3 новых поля в ProjectState + явный `init(from:)` + расширение
  memberwise init.
- `CityEngine.swift:277-288`: передать `templateName: nil, templateFamily: nil, eraLevel: 0`
  явно при создании ProjectState.
- `AppSettings.swift`: 2 новых @Published, обновить Persisted, save→version:4, load
  с defaults.
- 2 новых тестовых файла: `ProjectStateTemplateFieldsTests.swift`,
  `AppSettingsV4MigrationTests.swift`.

### Архитектурное решение

**ProjectState backwards-compat — через явный `init(from:)`:**
- Добавляем 3 поля **БЕЗ default-значений** в declaration (Swift автосинтез
  Codable требует explicit handling для backwards-compat либо all-or-nothing
  defaults).
- Пишем явный `init(from decoder:)` где новые поля декодируются через
  `decodeIfPresent(...) ?? <default>`. Старый JSON без полей → defaults.
- Пишем явный memberwise-like `init(id:, name:, ..., templateName: String? = nil,
  templateFamily: String? = nil, eraLevel: Int = 0)` чтобы CityEngine продолжал
  работать без указания новых полей (но в CityEngine всё равно поправим — чтобы
  явно передавать nil/0 и не было implicit-зависимостей).
- `encode(to:)` — не пишем, автосинтез по полям сериализует все 13 полей. Это
  делает запись JSON «вперёд» (всегда содержит новые поля).

**AppSettings v3→v4 — следуем существующему паттерну Persisted:**
- В `Persisted` struct (строки 121-136) добавляем `let templateFamily: String?`,
  `let previewTemplateSilhouette: Bool?`.
- В `load()` (67-100): `decoded.templateFamily ?? "auto"`,
  `decoded.previewTemplateSilhouette ?? false`.
- В `save()` (102-119): `version: 4`, передаём `templateFamily: templateFamily`,
  `previewTemplateSilhouette: previewTemplateSilhouette`.
- В `AppSettings` class: новые `@Published var templateFamily: String = "auto"`,
  `@Published var previewTemplateSilhouette: Bool = false`.

**Test isolation для AppSettings** — без рефакторинга API:
- `AppSettings.save/load` использует `UserDefaults.standard` напрямую (key
  `"com.commitpyramid.app.settings"`). В тестах: в `setUp` сохранять текущее
  значение этого ключа в `var savedDefaults: Data?`, в `tearDown` восстанавливать.
- Это минимально инвазивный путь, не трогаем AppSettings API.

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку, без импровизации.

1. **Расширить `ProjectState` тремя полями + явный `init(from:)`** `[AC:1,2]`
   - Файл: `Sources/CityDeveloper/Data/CityState.swift:440-451`
   - Заменить тело struct ровно на:
     ```swift
     struct ProjectState: Codable {
         let id: String
         let name: String
         let createdAt: Date
         var lastActivityAt: Date
         var taskCount: Int
         var stage: Int
         var decayLevel: Int
         var lastDecayLogged: Int
         var districtOrigin: GridPoint
         var unitIds: [UUID]
         // F-25: District templates + epochs (TASK-048a)
         var templateName: String?
         var templateFamily: String?
         var eraLevel: Int

         init(
             id: String,
             name: String,
             createdAt: Date,
             lastActivityAt: Date,
             taskCount: Int,
             stage: Int,
             decayLevel: Int,
             lastDecayLogged: Int,
             districtOrigin: GridPoint,
             unitIds: [UUID],
             templateName: String? = nil,
             templateFamily: String? = nil,
             eraLevel: Int = 0
         ) {
             self.id = id
             self.name = name
             self.createdAt = createdAt
             self.lastActivityAt = lastActivityAt
             self.taskCount = taskCount
             self.stage = stage
             self.decayLevel = decayLevel
             self.lastDecayLogged = lastDecayLogged
             self.districtOrigin = districtOrigin
             self.unitIds = unitIds
             self.templateName = templateName
             self.templateFamily = templateFamily
             self.eraLevel = eraLevel
         }

         init(from decoder: Decoder) throws {
             let c = try decoder.container(keyedBy: CodingKeys.self)
             id = try c.decode(String.self, forKey: .id)
             name = try c.decode(String.self, forKey: .name)
             createdAt = try c.decode(Date.self, forKey: .createdAt)
             lastActivityAt = try c.decode(Date.self, forKey: .lastActivityAt)
             taskCount = try c.decode(Int.self, forKey: .taskCount)
             stage = try c.decode(Int.self, forKey: .stage)
             decayLevel = try c.decode(Int.self, forKey: .decayLevel)
             lastDecayLogged = try c.decode(Int.self, forKey: .lastDecayLogged)
             districtOrigin = try c.decode(GridPoint.self, forKey: .districtOrigin)
             unitIds = try c.decode([UUID].self, forKey: .unitIds)
             // F-25 fields — optional decode for backwards-compat (legacy JSON без них)
             templateName = try c.decodeIfPresent(String.self, forKey: .templateName)
             templateFamily = try c.decodeIfPresent(String.self, forKey: .templateFamily)
             eraLevel = try c.decodeIfPresent(Int.self, forKey: .eraLevel) ?? 0
         }

         enum CodingKeys: String, CodingKey {
             case id, name, createdAt, lastActivityAt, taskCount, stage
             case decayLevel, lastDecayLogged, districtOrigin, unitIds
             case templateName, templateFamily, eraLevel
         }
     }
     ```
   - `encode(to:)` НЕ пишем. Swift синтезирует `encode(to:)` отдельно от
     `init(from:)`; пока есть явный `CodingKeys` enum — все 13 полей
     сериализуются автоматически.
   - **Зачем два init'a** (memberwise и `init(from:)`): добавление `init(from:)`
     автоматически отменяет сгенерированный компилятором memberwise init для
     struct. Поэтому memberwise мы тоже пишем явно — он нужен для существующих
     call site'ов в CityEngine/GameScene. Это стандартный Swift-паттерн при
     добавлении custom Codable conformance.

2. **Обновить вызов в `CityEngine.swift`** `[AC:1]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift:277-288`
   - Заменить вызов `ProjectState(...)` на:
     ```swift
     project = ProjectState(
         id: projectKey,
         name: projectKey,
         createdAt: event.ts,
         lastActivityAt: event.ts,
         taskCount: 1,
         stage: 0,
         decayLevel: 0,
         lastDecayLogged: 0,
         districtOrigin: origin,
         unitIds: [],
         templateName: nil,        // TASK-048c assign через Picker
         templateFamily: nil,      // TASK-048c assign
         eraLevel: 0               // TASK-050 будет менять
     )
     ```
   - Явное указание новых полей — отметка для будущих кодеров «здесь нужно
     дописать assignment, см. TASK-048c».

2b. **Обновить вызов в `GameScene.swift`** `[AC:1]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift:948` (второй и
     единственный другой вызов `ProjectState(...)` — bench-проект для
     CITY_BENCH_UNITS).
   - Аналогично шагу 2: добавить 3 явных параметра в конец вызова:
     ```swift
     // в существующем ProjectState(...) bench-проекта добавить:
         templateName: nil,        // bench: visual-only, шаблон не используется
         templateFamily: nil,
         eraLevel: 0
     ```
   - Без этого тоже скомпилируется (есть defaults в init), но явная запись
     требуется по принципу «нет implicit-зависимостей» (по аналогии с CityEngine
     в шаге 2).

3. **Расширить `AppSettings`** `[AC:4]`
   - Файл: `Sources/CityDeveloper/Data/AppSettings.swift`
   - **3.1.** В class AppSettings (после строки ~14 с `taskWeightMultiplier`)
     добавить:
     ```swift
     // F-25: District templates
     @Published var templateFamily: String = "auto"
     @Published var previewTemplateSilhouette: Bool = false
     ```
   - **3.2.** Отредактировать designated init AppSettings (строки 44-54 в
     теле класса, **не** через extension, **не** convenience init) — добавить
     два параметра в конец сигнатуры:
     ```swift
     templateFamily: String = "auto",
     previewTemplateSilhouette: Bool = false
     ```
     И assign'ы в теле init'а:
     ```swift
     self.templateFamily = templateFamily
     self.previewTemplateSilhouette = previewTemplateSilhouette
     ```
   - **3.3.** В `struct Persisted` (121-136) добавить два поля в конец:
     ```swift
     let templateFamily: String?              // optional для v1..v3 backward-compat
     let previewTemplateSilhouette: Bool?     // optional для v1..v3 backward-compat
     ```
   - **3.4.** В `load()` (67-100) расширить return AppSettings(...) с новыми
     параметрами:
     ```swift
     return AppSettings(
         ... // существующие параметры
         commitWeightMultiplier: decoded.commitWeightMultiplier ?? 0.1,
         taskWeightMultiplier: decoded.taskWeightMultiplier ?? 1.0,
         templateFamily: decoded.templateFamily ?? "auto",
         previewTemplateSilhouette: decoded.previewTemplateSilhouette ?? false
     )
     ```
   - **3.5.** В `save()` (102-119):
     - Изменить `version: 3` → `version: 4`.
     - Добавить в `Persisted(...)`:
       ```swift
       templateFamily: templateFamily,
       previewTemplateSilhouette: previewTemplateSilhouette
       ```

4. **Тесты `ProjectStateTemplateFieldsTests.swift`** `[AC:7]`
   - Файл: `Tests/CityDeveloperTests/ProjectStateTemplateFieldsTests.swift` (НОВЫЙ)
   - Содержимое целиком:
     ```swift
     import XCTest
     @testable import CommitPyramid

     final class ProjectStateTemplateFieldsTests: XCTestCase {

         func test_DefaultsForNewProject() {
             let project = ProjectState(
                 id: "p1", name: "p1",
                 createdAt: Date(), lastActivityAt: Date(),
                 taskCount: 0, stage: 0, decayLevel: 0, lastDecayLogged: 0,
                 districtOrigin: GridPoint(x: 0, y: 0), unitIds: []
             )
             XCTAssertNil(project.templateName)
             XCTAssertNil(project.templateFamily)
             XCTAssertEqual(project.eraLevel, 0)
         }

         func test_CodableRoundtripWithNewFields() throws {
             let original = ProjectState(
                 id: "p1", name: "Project One",
                 createdAt: Date(timeIntervalSince1970: 1000),
                 lastActivityAt: Date(timeIntervalSince1970: 2000),
                 taskCount: 5, stage: 2, decayLevel: 0, lastDecayLogged: 0,
                 districtOrigin: GridPoint(x: 10, y: 20),
                 unitIds: [UUID()],
                 templateName: "stage1-deir-el-medina",
                 templateFamily: "egyptian",
                 eraLevel: 1
             )
             let encoded = try JSONEncoder().encode(original)
             let decoded = try JSONDecoder().decode(ProjectState.self, from: encoded)

             XCTAssertEqual(decoded.templateName, "stage1-deir-el-medina")
             XCTAssertEqual(decoded.templateFamily, "egyptian")
             XCTAssertEqual(decoded.eraLevel, 1)
             XCTAssertEqual(decoded.id, original.id)
             XCTAssertEqual(decoded.unitIds, original.unitIds)
         }

         func test_CodableBackwardsCompatLegacyJSON() throws {
             // Legacy JSON (формат до TASK-048a — без templateName/templateFamily/eraLevel)
             let legacyJSON = """
             {
               "id": "legacy-project",
               "name": "Legacy Project",
               "createdAt": 0,
               "lastActivityAt": 100,
               "taskCount": 3,
               "stage": 1,
               "decayLevel": 0,
               "lastDecayLogged": 0,
               "districtOrigin": { "x": 5, "y": 5 },
               "unitIds": []
             }
             """
             let data = legacyJSON.data(using: .utf8)!
             let decoded = try JSONDecoder().decode(ProjectState.self, from: data)

             XCTAssertEqual(decoded.id, "legacy-project")
             XCTAssertEqual(decoded.taskCount, 3)
             XCTAssertNil(decoded.templateName, "Legacy snapshot должен дать templateName = nil")
             XCTAssertNil(decoded.templateFamily, "Legacy snapshot должен дать templateFamily = nil")
             XCTAssertEqual(decoded.eraLevel, 0, "Legacy snapshot должен дать eraLevel = 0")
         }
     }
     ```

5. **Тесты `AppSettingsV4MigrationTests.swift`** `[AC:7]`
   - Файл: `Tests/CityDeveloperTests/AppSettingsV4MigrationTests.swift` (НОВЫЙ)
   - Содержимое целиком:
     ```swift
     import XCTest
     @testable import CommitPyramid

     final class AppSettingsV4MigrationTests: XCTestCase {

         // Тесты используют UserDefaults.standard (как продакшн AppSettings).
         // setUp сохраняет текущее значение settings-ключа, tearDown восстанавливает.
         private let settingsKey = "com.commitpyramid.app.settings"
         private var savedData: Data?

         override func setUp() {
             super.setUp()
             savedData = UserDefaults.standard.data(forKey: settingsKey)
             UserDefaults.standard.removeObject(forKey: settingsKey)
         }

         override func tearDown() {
             if let savedData {
                 UserDefaults.standard.set(savedData, forKey: settingsKey)
             } else {
                 UserDefaults.standard.removeObject(forKey: settingsKey)
             }
             super.tearDown()
         }

         func test_DefaultTemplateFamilyIsAuto() {
             // Пусто в UserDefaults → AppSettings.load() даёт defaults
             let settings = AppSettings.load()
             XCTAssertEqual(settings.templateFamily, "auto")
             XCTAssertEqual(settings.previewTemplateSilhouette, false)
         }

         func test_V3ToV4MigrationPreservesOtherSettings() throws {
             // Засеиваем UserDefaults в формате v3 (без templateFamily)
             let v3JSON: [String: Any] = [
                 "version": 3,
                 "tasksJsonlPath": "file:///tmp/tasks.jsonl",
                 "dataDirectory": "file:///tmp/data",
                 "hotkeyKeyCode": 5,
                 "hotkeyModifiers": 0,
                 "catchUpIntervalMinutes": 10,
                 "commitWeightMultiplier": 0.5,
                 "taskWeightMultiplier": 2.0
             ]
             let v3Data = try JSONSerialization.data(withJSONObject: v3JSON)
             UserDefaults.standard.set(v3Data, forKey: settingsKey)

             let settings = AppSettings.load()
             XCTAssertEqual(settings.commitWeightMultiplier, 0.5,
                            "v3 commitWeightMultiplier должен сохраниться")
             XCTAssertEqual(settings.taskWeightMultiplier, 2.0,
                            "v3 taskWeightMultiplier должен сохраниться")
             XCTAssertEqual(settings.catchUpIntervalMinutes, 10)
             XCTAssertEqual(settings.templateFamily, "auto",
                            "v3 не знал про templateFamily → дефолт auto")
             XCTAssertEqual(settings.previewTemplateSilhouette, false)
         }

         func test_TemplateFamilyPersistenceRoundtrip() {
             let s1 = AppSettings.load()
             s1.templateFamily = "egyptian"
             s1.previewTemplateSilhouette = true
             s1.save()

             let s2 = AppSettings.load()
             XCTAssertEqual(s2.templateFamily, "egyptian")
             XCTAssertEqual(s2.previewTemplateSilhouette, true)
         }
     }
     ```

### Edge cases (явно обработать)

- [x] Legacy JSON без новых полей → `init(from:)` через `decodeIfPresent` →
      nil/0. Тест `test_CodableBackwardsCompatLegacyJSON`.
- [x] eraLevel приходит как отрицательное число → принимается as-is
      (валидация в TASK-050 EraRules, не здесь).
- [x] AppSettings test isolation через save/restore UserDefaults blob в
      setUp/tearDown. Не глобальное загрязнение.
- [x] CityEngine.swift:277-288 — после правки compile должен пройти; явные
      nil/0 для новых полей.
- [x] Конфликта с TASK-037 LegacyStateMigration (legacy UnitKind rawValue
      mapping) нет — мы трогаем ProjectState, а TASK-037 был про UnitState.

### Файлы для изменения

- `Sources/CityDeveloper/Data/CityState.swift` — заменить `struct ProjectState`
  (строки 440-451) на расширенную версию из шага 1.
- `Sources/CityDeveloper/Game/CityEngine.swift:277-288` — добавить 3 явных
  параметра в `ProjectState(...)` вызов.
- `Sources/CityDeveloper/Game/GameScene.swift:948` — аналогично, в bench-вызов
  ProjectState добавить 3 явных параметра nil/nil/0 с комментарием
  «bench: visual-only».
- `Sources/CityDeveloper/Data/AppSettings.swift` — 5 micro-правок из шага 3.
- `Tests/CityDeveloperTests/ProjectStateTemplateFieldsTests.swift` (НОВЫЙ).
- `Tests/CityDeveloperTests/AppSettingsV4MigrationTests.swift` (НОВЫЙ).

### Файлы НЕ трогать

- `Sources/CityDeveloper/Data/StateSnapshot.swift` — currentVersion остаётся 1,
  это уровень всего CityState, не вложенного ProjectState (Explore п.2).
- `Sources/CityDeveloper/Data/SnapshotStore.swift` — load/save через
  StateSnapshot.currentVersion не меняется.
- `Sources/CityDeveloper/Data/GameEvent.swift` — events.jsonl формат
  стабилен (Explore п.3, в unit_built пишется только `title`).
- `Sources/CityDeveloper/Game/Templates/*` — это TASK-048b/c.
- `Sources/CityDeveloper/App/AppDelegate.swift:30` — `AppSettings.load()`
  вызов не меняется (load сам прочитает новые поля).
- UI / Settings view — это TASK-051.

### Команды проверки (для DoD)

- Компиляция: `swift build`
- Только новые тесты:
  - `swift test --filter ProjectStateTemplateFieldsTests` → 3/3 PASS
  - `swift test --filter AppSettingsV4MigrationTests` → 3/3 PASS
- Существующие тесты не сломаны: `swift test --filter LegacyStateMigrationTests`
  → 7/7 PASS (старый snapshot.json должен по-прежнему загружаться).
- Полный прогон: `swift test` → 83+6=89 PASS, 1 known-fail BUG-020.

### Сложность

`junior-middle`

**Обоснование:** Линейные правки в 3 файлах + 2 тестовых файла, нет
архитектурных решений (паттерны Persisted и init(from:) уже есть в проекте).
Не чисто junior, потому что (а) явный init(from:) + CodingKeys требует
понимания почему он нужен (backwards-compat при автосинтезе), (б) тестовая
изоляция UserDefaults — нестандартный setUp/tearDown паттерн.

### Ожидаемое время

S (≤2ч)

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: junior-middle_
_Объём: S_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] `swift test --filter ProjectStateTemplateFieldsTests` — 3/3 PASS
- [ ] `swift test --filter AppSettingsV4MigrationTests` — 3/3 PASS

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Существующие 83 тестов не сломаны (84 total, 1 known-fail BUG-020) →
      после: 83+6=89 PASS, 1 known-fail
- [ ] Старый snapshot.json (если был) загружается без warning'ов в errors.log

#### Обновление документации
- [ ] `Current.md`: F-25 → ⚠️ (часть 2.1/5)
- [ ] `Diff.md`: D-25 не закрывать

---

## Статус

`[x] done` (closed 2026-05-24)

## Метаданные
- Создана PM: 2026-05-24
- Spec-review: approved
- Lead-model: opus
- Plan-review: revised (круг 1 → 5 правок применены)
- Run-model: sonnet (delegated, junior-middle)
- Blocked-by: TASK-047 ✅
- Готова к работе: 2026-05-24
- Завершена: 2026-05-24
- Коммит: pending
- Артефакты:
  - `CityState.swift`: ProjectState + 3 поля + явный init(from:) + CodingKeys
  - `CityEngine.swift:277-288`: 3 явных параметра
  - `GameScene.swift:948`: 3 явных параметра (bench)
  - `AppSettings.swift`: 5 micro-правок, version 3→4
  - `Tests/.../ProjectStateTemplateFieldsTests.swift` (3 PASS)
  - `Tests/.../AppSettingsV4MigrationTests.swift` (3 PASS)
- Отклонений от плана нет.
