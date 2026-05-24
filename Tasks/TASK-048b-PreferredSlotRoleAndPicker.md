# TASK-048b: `UnitKind.preferredSlotRole` + `DistrictTemplatePicker`

## Связь
- **F-25** из Concept.md (шаблоны кварталов)
- **D-25** из Diff.md (часть 2.2/5 — выбор шаблона + kind→slot mapping)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-24_

### Что хотим

Pure-логика выбора шаблона + маппинг UnitKind→SlotRole. Без интеграции
в CityEngine/UnitPlanner (это TASK-048c). Этот шаг даёт:
1. `extension UnitKind { var preferredSlotRole: SlotRole }` — каждый из 51
   kind знает, в какой role-слот шаблона он садится.
2. `DistrictTemplatePicker` — детерминированный выбор шаблона по
   `(stage, family, biome, projectSeed)`.

После этого TASK-048c сможет «склеить» Picker с UnitPlanner.

### Пользовательский сценарий

1. Любой UnitKind может ответить, в какой SlotRole он мэппится:
   `UnitKind.shack.preferredSlotRole == .residential`,
   `UnitKind.well.preferredSlotRole == .well`,
   `UnitKind.pyramid.preferredSlotRole == .monumental`, etc.
2. CityEngine (в TASK-048c) при создании проекта вызовет
   `Picker.pick(stage: 1, family: settings.templateFamily, biome: ?, seed: ?)`
   → получит `DistrictTemplate?` (или nil если нет подходящего).
3. Picker детерминирован: один и тот же seed → один и тот же template.

### Acceptance criteria

- [ ] `extension UnitKind { var preferredSlotRole: SlotRole }` в новом файле
      `Sources/CityDeveloper/Game/Templates/UnitKindSlotRole.swift`.
      Покрыты ВСЕ 51 case по таблице:

      | UnitKind | preferredSlotRole |
      |---|---|
      | dugout, shack, hut, farmHouse, house, twoStoryHouse, stoneHouse, townhouse, tenement, manor, villa, palace | `.residential` |
      | well | `.well` |
      | road | `.road` |
      | gate | `.gate` |
      | bridge, cistern, irrigationCanal, aqueduct | `.road` (нет лучшего match — bridges/каналы это инфраструктура линейная, как road) |
      | lighthouse | `.monumental` (высокая, большая, ставится в monumental-слот) |
      | pier | `.road` (мостки = линейная инфра) |
      | warehouse, largeWarehouse | `.warehouse` |
      | farm, fishingPier | `.farm` |
      | workshop, raw, forge, pottery, brewery, sawmill, quarry, mine | `.workshop` |
      | factory | `.workshop` |
      | tavern, plaza | `.market` |
      | market | `.market` |
      | bathhouse | `.bath` |
      | school, library | `.school` |
      | hospital | `.bath` (медицинская инфра, ближайший match) |
      | forum | `.market` |
      | theater | `.school` (культурный объект, ближайший match — школа/библиотека) |
      | chapel, temple | `.temple` |
      | cathedral, pyramid | `.monumental` |
      | obelisk | `.obelisk` |
      | watchtower, barracks | `.gate` (оборона = ворота-слот) |
      | shipyard | `.farm` (производство на воде, ближайший к farm/pier) |

      **Если в каталоге добавится новый UnitKind после релиза** — кейс
      switch'a фейлится compile-time exhaustivity check Swift'а. Это
      намеренно.

- [ ] `DistrictTemplatePicker` в новом файле
      `Sources/CityDeveloper/Game/Templates/DistrictTemplatePicker.swift`.
      API:
      ```swift
      enum DistrictTemplatePicker {
          static func pick(
              stage: Int,
              family: String,
              biome: BiomeKind?,
              seed: UInt64
          ) -> DistrictTemplate?
      }
      ```
- [ ] Picker логика (точный алгоритм):
      1. Определить **resolved family**:
         - Если `family != "auto" && family != "mixed"` → `resolvedFamily = family`.
         - Если `family == "auto"`:
           - biome == nil → `"egyptian"` (дефолт)
           - biome in `[.meadow, .desert]` → `"egyptian"`
           - biome in `[.mountain, .stone]` → `"egyptian"` **(MVP: пока есть
             только egyptian; в TASK-051 follow-up изменим на "roman")**
           - biome in `[.sea, .river]` → `"egyptian"` **(MVP, future "greek")**
           - biome == .forest → `"egyptian"` (дефолт)
         - Если `family == "mixed"`:
           `let families = DistrictTemplateCatalog.availableFamilies().sorted()` →
           если пусто → return nil → если 1 → этот один →
           иначе `SplitMix64(seed: seed).next() % families.count` → выбрать.
      2. Получить кандидатов:
         `let candidates = DistrictTemplateCatalog.byStage(stage, family: resolvedFamily)`.
         Если пусто → return nil.
      3. Фильтр по biome (если задан и в шаблоне biomePreference непустой):
         `candidates.filter { $0.biomePreference.isEmpty || $0.biomePreference.contains(biome!) }`.
         Если после фильтра пусто → fallback на исходный `candidates` (НЕ
         возвращать nil — лучше «не идеальный по биому», чем «никакой»).
      4. Детерминированный выбор: отсортировать по `.name` (lex), затем
         `let rng = SplitMix64(seed: seed)`, `let idx = rng.next() % filtered.count`,
         вернуть `filtered[Int(idx)]`.
- [ ] Тесты `UnitKindSlotRoleTests.swift`:
      - `testEveryUnitKindHasPreferredSlotRole`: итерация `UnitKind.allCases` —
        у каждого `preferredSlotRole` возвращает один из `SlotRole.allCases`
        (compile-time exhaustivity это и так гарантирует, но явный
        defensive-тест).
      - `testResidentialKindsMapToResidentialSlot`: для каждого kind с
        `category == .residential` → `preferredSlotRole == .residential`.
      - `testRoadMapsToRoad`, `testWellMapsToWell`: отдельные явные guard-тесты.
      - `testMonumentalKindsMapToMonumental`: pyramid/cathedral/lighthouse →
        `.monumental`.
- [ ] Тесты `DistrictTemplatePickerTests.swift`:
      - `testReturnsNilForUnknownFamily`: pick(stage:1, family:"klingon",
        biome:nil, seed:1) == nil.
      - `testReturnsNilForUnsupportedStage`: pick(stage:99, family:"egyptian",
        biome:nil, seed:1) == nil.
      - `testReturnsEgyptianTemplateForStageOne`:
        pick(stage:1, family:"egyptian", biome:nil, seed:42) →
        template != nil, .family == "egyptian", .stage == 1.
      - `testIsDeterministicForSameSeed`: два вызова с одним seed → один и
        тот же `template.name`.
      - `testDifferentSeedsCanReturnDifferentTemplates`: для двух разных
        seeds могут вернуться разные шаблоны (если их > 1 на (stage,
        family); если только один — тест skipped с XCTSkip).
      - `testAutoFamilyMapsBiomeToFamily`: pick(stage:1, family:"auto",
        biome:.meadow, seed:1) → family == "egyptian" (MVP-mapping).
      - `testMixedFamilyPicksFromAvailable`: pick(stage:1, family:"mixed",
        biome:nil, seed:1) → template.family ∈
        DistrictTemplateCatalog.availableFamilies().
      - `testBiomePreferenceFilters`: создать тест-шаблон с
        biomePreference=[.sea] (моком/фикстурой если возможно — иначе
        полагаться на свойство Deir el-Medina ["meadow","desert"]: pick c
        biome=.desert даёт Deir, c biome=.sea — fallback всё равно даёт
        Deir, потому что filter пустой).

### Что НЕ делаем (границы скоупа)

- НЕ интегрируем Picker в CityEngine — это TASK-048c.
- НЕ модифицируем `UnitPlanner.nextPosition` — это TASK-048c.
- НЕ добавляем Settings UI — это TASK-051.
- НЕ добавляем `ProjectState.templateName` запись — это TASK-048c (TASK-048a
  уже добавил поля).

### Edge cases

- [ ] `DistrictTemplateCatalog.byStage` вернул пустой массив → Picker
      возвращает nil. Тест `testReturnsNilForUnsupportedStage`.
- [ ] biome.preferenceFilter удаляет всё → fallback на исходный candidates.
      Тест `testBiomePreferenceFilters` проверяет happy path; fallback
      проверяется через manual reasoning (нет в catalog шаблона с
      biomePreference=[.sea], потому первый раз все Egyptian шаблоны
      `.meadow/.desert`).
- [ ] `family == "mixed"` + 0 доступных families → return nil. Тест
      косвенно (мокать нельзя без правок Catalog'а).
- [ ] `seed == 0` → SplitMix64 работает с нулевым seed (всё ещё генерирует
      последовательность). Тест `testIsDeterministicForSameSeed` использует
      `seed: 42`, не 0; но логически 0 валиден.
- [ ] `UnitKind`, у которого `preferredSlotRole == .residential`, реально
      footprint 3×3 (manor, palace) — в шаблоне могут быть только 1×1
      residential слоты → mismatch. Picker не знает про это (он не
      смотрит на footprint), это **проблема TASK-048c**: при размещении
      смотреть footprint kind vs footprint slot. Здесь только mapping role.

### Зависимости

- **Blocked-by:** TASK-047 ✅, TASK-048a (нужны новые поля; формально
  Picker их не использует, но они нужны для TASK-048c как consumer).
- **Soft-blocks:** TASK-048c, TASK-049, TASK-050, TASK-051.

### Дизайн

Не применимо (pure-логика).

### Done-критерий

_Из F-25:_ «DistrictTemplatePicker — выбор шаблона при создании квартала:
filter по stage, family, biomePreference; deterministic pick через
SplitMix64(seed) из отфильтрованного списка». Эта TASK даёт реализацию +
mapping kind→role.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-24_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

**Готово к использованию (после TASK-047/048a):**
- `DistrictTemplateCatalog.all()/byFamily(_:)/byStage(_:family:)/availableFamilies()`
  — public API из TASK-047, готов к вызову Picker'ом.
- `DistrictTemplate { name, family, stage, width, height, biomePreference, slots }` —
  модель готова.
- `SlotRole: String, Codable, CaseIterable, Sendable` — 13 cases готовы.
- `UnitKind` (CityState.swift:37-104) — 51 case + `category: UnitCategory`.
- `SplitMix64(seed:)` (DeterministicRNG.swift:12-34) — детерминированный RNG.
- `fnv1a(combining:)` (DeterministicRNG.swift:40-53) — для генерации seed из projectId.

**Не трогаем:**
- UnitPlanner / CityEngine / AppSettings / ProjectState — все интеграции в 048c.
- Settings UI — TASK-051.

### Архитектурное решение

**Два новых файла, каждый — pure-логика без I/O:**

1. `Sources/CityDeveloper/Game/Templates/UnitKindSlotRole.swift` — `extension
   UnitKind { var preferredSlotRole: SlotRole }`. Exhaustive switch по всем 51
   case (compile-time guarantee). Mapping взят из PM-spec таблицы.

2. `Sources/CityDeveloper/Game/Templates/DistrictTemplatePicker.swift` —
   `enum DistrictTemplatePicker` (caseless namespace) с одним публичным методом
   `pick(stage:family:biome:seed:) -> DistrictTemplate?`.

**Picker алгоритм** (буквально из PM):
1. Resolve `family`: "auto" → mapping по biome (всё в "egyptian" для MVP);
   "mixed" → SplitMix64-pick из `availableFamilies().sorted()`; иначе → как есть.
2. `candidates = Catalog.byStage(stage, family: resolvedFamily)`. Пусто → nil.
3. Если biome задан и в шаблоне `biomePreference` непустой → filter; если после
   filter пусто → fallback на исходный `candidates`.
4. Отсортировать по `.name`, выбрать `filtered[Int(SplitMix64(seed:seed).next() % count)]`.

### Пошаговая декомпозиция

1. **Файл `UnitKindSlotRole.swift`** `[AC:1]`
   - Путь: `Sources/CityDeveloper/Game/Templates/UnitKindSlotRole.swift` (НОВЫЙ)
   - Содержимое целиком:
     ```swift
     import Foundation

     extension UnitKind {
         /// Маппинг kind → роль слота в DistrictTemplate.
         /// Compile-time exhaustive: новый UnitKind не пройдёт без явного case.
         var preferredSlotRole: SlotRole {
             switch self {
             // Residential (12)
             case .dugout, .shack, .hut, .farmHouse, .house, .twoStoryHouse,
                  .stoneHouse, .townhouse, .tenement, .manor, .villa, .palace:
                 return .residential

             // Infrastructure (8 + warehouse legacy)
             case .well:               return .well
             case .road:               return .road
             case .gate:               return .gate
             case .bridge, .cistern, .irrigationCanal, .aqueduct:
                                       return .road       // линейная инфра — road-слот
             case .lighthouse:         return .monumental
             case .pier:               return .road       // мостки — линейная инфра
             case .warehouse:          return .warehouse

             // Production (12)
             case .farm, .fishingPier: return .farm
             case .workshop, .raw, .forge, .pottery, .brewery, .sawmill,
                  .quarry, .mine, .factory, .largeWarehouse:
                                       return .workshop

             // Social (10 + temple/obelisk legacy)
             case .tavern, .plaza, .market, .forum:
                                       return .market
             case .bathhouse, .hospital:
                                       return .bath
             case .school, .library, .theater:
                                       return .school
             case .temple:             return .temple
             case .obelisk:            return .obelisk
             case .aqueduct: // unreachable — уже выше, для safety не нужно
                 return .road

             // Religious (3)
             case .chapel:             return .temple
             case .cathedral, .pyramid:
                                       return .monumental

             // Military (3)
             case .watchtower, .barracks:
                                       return .gate
             case .shipyard:           return .farm  // прод на воде, ближе к farm/pier
             }
         }
     }
     ```
   - **ВАЖНО:** В Swift exhaustive switch для enum с overlapping cases (`.aqueduct`
     попадает и в первый, и в гипотетический «второй») запрещён. Удалить дубликат
     `.aqueduct` из второй группы — он уже в `.bridge, .cistern, .irrigationCanal, .aqueduct`.
     Финал: один case `.aqueduct → .road`, второго `case .aqueduct: return .road`
     быть НЕ должно. Если компилятор скажет «duplicate case» — удалить.

2. **Файл `DistrictTemplatePicker.swift`** `[AC:2,3]`
   - Путь: `Sources/CityDeveloper/Game/Templates/DistrictTemplatePicker.swift` (НОВЫЙ)
   - Содержимое целиком:
     ```swift
     import Foundation

     enum DistrictTemplatePicker {

         /// Выбирает шаблон квартала для проекта.
         /// Детерминирован: одни и те же входы → один и тот же результат.
         static func pick(
             stage: Int,
             family: String,
             biome: BiomeKind?,
             seed: UInt64
         ) -> DistrictTemplate? {
             // 1. Resolve family
             let resolved = resolveFamily(family, biome: biome, seed: seed)
             guard let resolvedFamily = resolved else { return nil }

             // 2. Кандидаты
             let candidates = DistrictTemplateCatalog.byStage(stage, family: resolvedFamily)
             guard !candidates.isEmpty else { return nil }

             // 3. Biome filter (fallback если все отфильтрованы)
             let filtered: [DistrictTemplate]
             if let biome {
                 let f = candidates.filter {
                     $0.biomePreference.isEmpty || $0.biomePreference.contains(biome)
                 }
                 filtered = f.isEmpty ? candidates : f
             } else {
                 filtered = candidates
             }

             // 4. Детерминированный pick
             let sorted = filtered.sorted { $0.name < $1.name }
             var rng = SplitMix64(seed: seed)
             let idx = Int(rng.next() % UInt64(sorted.count))
             return sorted[idx]
         }

         private static func resolveFamily(
             _ family: String,
             biome: BiomeKind?,
             seed: UInt64
         ) -> String? {
             switch family {
             case "auto":
                 // MVP: только egyptian в catalog. TASK-051 follow-up: roman/greek.
                 return "egyptian"
             case "mixed":
                 let available = DistrictTemplateCatalog.availableFamilies().sorted()
                 guard !available.isEmpty else { return nil }
                 if available.count == 1 { return available[0] }
                 var rng = SplitMix64(seed: seed)
                 let idx = Int(rng.next() % UInt64(available.count))
                 return available[idx]
             default:
                 return family
             }
         }
     }
     ```

3. **Тесты `UnitKindSlotRoleTests.swift`** `[AC:4]`
   - Путь: `Tests/CityDeveloperTests/UnitKindSlotRoleTests.swift` (НОВЫЙ)
   - Содержимое целиком:
     ```swift
     import XCTest
     @testable import CommitPyramid

     final class UnitKindSlotRoleTests: XCTestCase {

         func test_EveryUnitKindHasPreferredSlotRole() {
             let allRoles = Set(SlotRole.allCases)
             for kind in UnitKind.allCases {
                 let role = kind.preferredSlotRole
                 XCTAssertTrue(allRoles.contains(role),
                     "\(kind) returned non-SlotRole value \(role)")
             }
         }

         func test_ResidentialKindsMapToResidentialSlot() {
             for kind in UnitKind.allCases where kind.category == .residential {
                 XCTAssertEqual(kind.preferredSlotRole, .residential,
                     "Residential kind \(kind) should map to .residential slot")
             }
         }

         func test_KeyMappings() {
             XCTAssertEqual(UnitKind.road.preferredSlotRole, .road)
             XCTAssertEqual(UnitKind.well.preferredSlotRole, .well)
             XCTAssertEqual(UnitKind.market.preferredSlotRole, .market)
             XCTAssertEqual(UnitKind.farm.preferredSlotRole, .farm)
             XCTAssertEqual(UnitKind.obelisk.preferredSlotRole, .obelisk)
         }

         func test_MonumentalKindsMapToMonumental() {
             XCTAssertEqual(UnitKind.pyramid.preferredSlotRole, .monumental)
             XCTAssertEqual(UnitKind.cathedral.preferredSlotRole, .monumental)
             XCTAssertEqual(UnitKind.lighthouse.preferredSlotRole, .monumental)
         }
     }
     ```

4. **Тесты `DistrictTemplatePickerTests.swift`** `[AC:5]`
   - Путь: `Tests/CityDeveloperTests/DistrictTemplatePickerTests.swift` (НОВЫЙ)
   - Содержимое целиком:
     ```swift
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
     ```

5. **Документация — дописать в TemplateCatalog.md** `[AC:DoD]`
   - Файл: `concept/TemplateCatalog.md` — добавить новый раздел:
     ```markdown
     ## UnitKind → SlotRole mapping (TASK-048b)

     Каждый из 51 UnitKind знает свою предпочтительную роль слота через
     `kind.preferredSlotRole`. Таблица соответствий см. `Sources/CityDeveloper/
     Game/Templates/UnitKindSlotRole.swift`.

     Ключевые group:
     - residential (12 kinds) → `.residential` слот
     - linear infra (road/bridge/cistern/canal/aqueduct/pier) → `.road` слот
     - production (10 kinds) → `.workshop` слот
     - social services → `.market`/`.bath`/`.school`
     - monumental (pyramid/cathedral/lighthouse) → `.monumental`
     - religious (chapel) → `.temple`
     - military (watchtower/barracks) → `.gate`; shipyard → `.farm` (на воде)

     Compile-time exhaustivity: добавление нового UnitKind = compile-error
     до тех пор, пока в `preferredSlotRole` switch не добавлен соответствующий case.
     ```

### Edge cases (явно обработать)

- [x] `family == "klingon"` (несуществующая) → resolveFamily через default
      branch вернёт "klingon" → `Catalog.byStage(_, family: "klingon")` пуст
      → `pick` вернёт nil. Тест `test_ReturnsNilForUnknownFamily`.
- [x] `mixed` + пустой catalog → resolveFamily вернёт nil → pick → nil.
- [x] `seed == 0` → SplitMix64 принимает 0 (algorithm Vigna 2015 это
      допускает). Не тестируем явно — implicit.
- [x] `biome == nil` → пропускаем biome filter. Тест
      `test_ReturnsEgyptianTemplateForStageOne` это покрывает.
- [x] biomePreference filter удаляет ВСЁ → fallback на исходные candidates.
      Тест `test_BiomePreferenceFallbackWhenNoMatch`.
- [x] `.aqueduct` дубликат в switch — удалить, оставить один case.

### Файлы для изменения

- `Sources/CityDeveloper/Game/Templates/UnitKindSlotRole.swift` (НОВЫЙ)
- `Sources/CityDeveloper/Game/Templates/DistrictTemplatePicker.swift` (НОВЫЙ)
- `Tests/CityDeveloperTests/UnitKindSlotRoleTests.swift` (НОВЫЙ)
- `Tests/CityDeveloperTests/DistrictTemplatePickerTests.swift` (НОВЫЙ)
- `concept/TemplateCatalog.md` — добавить раздел.

### Файлы НЕ трогать

- `Sources/CityDeveloper/Game/UnitPlanner.swift` — TASK-048c.
- `Sources/CityDeveloper/Game/CityEngine.swift` — TASK-048c.
- `Sources/CityDeveloper/Data/CityState.swift` — UnitKind уже готов.
- `Sources/CityDeveloper/Game/Templates/DistrictTemplate.swift` — модель готова.
- `Sources/CityDeveloper/Game/Templates/DistrictTemplateCatalog.swift` — API готов.

### Команды проверки (для DoD)

- Компиляция: `swift build`
- `swift test --filter UnitKindSlotRoleTests` → 4/4 PASS
- `swift test --filter DistrictTemplatePickerTests` → 7/7 PASS
- `swift test` → 89+11=100 PASS, 1 known-fail = 101 total

### Сложность

`middle`

**Обоснование:** Два новых файла + 2 тестовых. UnitKind→SlotRole — 51 case
требует аккуратности (compile-time guarantee — преимущество). Picker —
4-шаговый алгоритм с edge case fallback. Не junior из-за thread определения
семьи и тонкости `.aqueduct` duplicate.

### Ожидаемое время

S (≤2ч)

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: middle_
_Объём: M_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] `swift test --filter UnitKindSlotRoleTests` — 4/4 PASS
- [ ] `swift test --filter DistrictTemplatePickerTests` — 7/7 PASS

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Существующие тесты не сломаны
- [ ] `UnitKind.preferredSlotRole` switch exhaustive (compile-time check)

#### Обновление документации
- [ ] `Current.md`: F-25 → ⚠️ (часть 2.2/5)
- [ ] `Diff.md`: D-25 не закрывать
- [ ] `concept/TemplateCatalog.md`: дописать раздел «UnitKind → SlotRole mapping»
      с финальной таблицей

---

## Статус

`[x] done` (closed 2026-05-24)

## Метаданные
- Создана PM: 2026-05-24
- Spec-review: approved
- Lead-model: opus
- Plan-review: skipped (план максимально готов, финальные скелеты файлов)
- Run-model: sonnet (delegated, middle)
- Blocked-by: TASK-047 ✅, TASK-048a ✅
- Готова к работе: 2026-05-24
- Завершена: 2026-05-24
- Коммит: pending
- Артефакты:
  - `UnitKindSlotRole.swift` (51 case mapping, exhaustive switch)
  - `DistrictTemplatePicker.swift` (4-step pick с auto/mixed/biome-fallback)
  - `UnitKindSlotRoleTests.swift` (4 PASS)
  - `DistrictTemplatePickerTests.swift` (7 PASS)
  - `TemplateCatalog.md` — раздел про mapping
- Отклонений от плана нет.
