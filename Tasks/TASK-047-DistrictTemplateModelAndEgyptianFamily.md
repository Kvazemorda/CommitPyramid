# TASK-047: Модель `DistrictTemplate` + egyptian-семья (5 шаблонов) + Catalog loader

## Связь
- **F-25** из Concept.md (шаблоны кварталов)
- **D-25** из Diff.md (часть 1/5 — формат + первая семья)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-24_

### Что хотим

Заложить **фундамент** F-25: ввести Codable-модель `DistrictTemplate` (grid слотов
с ролями), описать JSON-схему, положить **5 шаблонов egyptian-семьи** (stage 1–5)
в `Resources/DistrictTemplates/egyptian/`, и сделать `DistrictTemplateCatalog`,
который грузит шаблоны на старте в память. На этом шаге шаблоны ещё **не
используются** UnitPlanner'ом — только описаны, провалидированы и доступны через
API. Это снимает риск «придумываем формат на ходу, потом всё ломаем».

### Пользовательский сценарий

1. Разработчик хочет добавить новый шаблон → создаёт JSON в
   `Resources/DistrictTemplates/<family>/`, пересобирает — он автоматически
   подхватывается `DistrictTemplateCatalog.all()`.
2. На swift test `DistrictTemplateCatalogTests` проверяет, что все 5 egyptian
   шаблонов загружаются, валидны (нет out-of-bounds слотов, нет дублирующих
   позиций, корректные роли).
3. Игра запускается как раньше — никаких визуальных изменений (это
   подготовительный шаг).

### Acceptance criteria

- [ ] Создан тип `DistrictTemplate: Codable, Sendable` со всеми полями из
      F-25 п.1: `name, family, stage, width, height, biomePreference, slots`.
- [ ] Создан тип `TemplateSlot: Codable` с полями `x, y, role, footprint`.
- [ ] Создан enum `SlotRole: String, Codable, CaseIterable` с 13 значениями
      из F-25: `residential, well, road, market, temple, workshop, farm,
      bath, school, obelisk, gate, warehouse, monumental`.
- [ ] В `Resources/DistrictTemplates/egyptian/` лежат **5 JSON-файлов**:
      `stage1-deir-el-medina.json`, `stage2-kahun.json`,
      `stage3-ahmarna-middle.json`, `stage4-pharaonic-services.json`,
      `stage5-akhetaten-ceremonial.json`.
- [ ] Каждый JSON валиден относительно схемы: все слоты внутри
      `[0..width) × [0..height)`, нет двух слотов с пересекающимися
      footprint, slot.role ∈ SlotRole.allCases.
- [ ] `DistrictTemplateCatalog` — singleton с методами `all() ->
      [DistrictTemplate]`, `byFamily(_ family: String) ->
      [DistrictTemplate]`, `byStage(_ stage: Int, family: String) ->
      [DistrictTemplate]`. Грузит из `Bundle.module` лениво (один раз).
- [ ] `Tests/CityDeveloperTests/DistrictTemplateCatalogTests.swift`:
      `testLoadsAllEgyptianTemplates`, `testNoOverlappingSlots`,
      `testStageCoverageOneToFive`, `testBiomePreferenceValid`,
      `testRolesValid`. Все зелёные.

### Что НЕ делаем (границы скоупа)

- НЕ меняем `UnitPlanner` — это TASK-048/049.
- НЕ добавляем Roman/Greek families — это backlog follow-up.
- НЕ добавляем `templateName/templateFamily/eraLevel` в `ProjectState` (хотя
  их нужно добавить — это TASK-048, чтобы было что выбирать).
- НЕ интегрируем `DistrictTemplate` в Settings UI — это TASK-051.

### Edge cases

- [ ] JSON с битым полем (например, `role: "unknown"`) → ловится при load,
      шаблон НЕ загружается, в `errors.log` записывается строка
      `[template-loader] skipped <file>: invalid role 'unknown'`.
- [ ] Шаблон с дублирующимся `name` в той же family → один из них пропускается
      (первый загруженный wins, второй пишет warning).
- [ ] Пустой `slots: []` → шаблон считается валидным, но при попытке использования
      должен fallback на legacy placement (это уже задача TASK-048).
- [ ] `biomePreference: []` → значит «подходит для любого биома» (не фильтрует).
- [ ] Slot footprint=1×1 по умолчанию (если не задан в JSON).

### Зависимости

- **Blocked-by:** нет (фундамент F-25).
- **Soft-blocks:** TASK-048 (Picker), TASK-049 (slot-based placement),
  TASK-050 (migration), TASK-051 (Settings UI).

### Дизайн

ASCII-эскизы 5 egyptian-шаблонов даны в обсуждении 2026-05-24 (см. чат-история).
Перенос в JSON — прямой: 1 ASCII-клетка = 1 slot, легенда:
`R/r/H` → role=residential (footprint 1×1 / 2×2 / 3×3), `W` → well 1×1,
`=` → road 1×1, `M/T/S/F/P/p/G/O/▲` → соответствующие роли.

### Done-критерий

_Часть F-25 Done-критерия:_ «В Resources лежит ≥15 JSON-шаблонов (3 family × 5
stage)». Эта TASK закрывает **5 из 15** (egyptian-family). Остальные 10 —
backlog (Roman + Greek). Загрузка через `DistrictTemplateCatalog` валидирована
тестами.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-24_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

**В коде уже есть (Explore TASK-047):**
- `Package.swift:11-13` — `.process("Resources")` уже подключён. Новые
  JSON в `Sources/CityDeveloper/Resources/DistrictTemplates/egyptian/*.json`
  подхватятся автоматически без правок Package.swift.
- `Sources/CityDeveloper/Data/CityState.swift:20-22` — `BiomeKind: String,
  Codable, CaseIterable` с 7 cases (meadow, forest, mountain, stone, river,
  sea, desert). Готов к JSON-полю `biomePreference: [BiomeKind]`.
- `Sources/CityDeveloper/Data/CityState.swift:25-31` — `GridSize { width: Int,
  height: Int }`, `Codable, Hashable`. Готов к `slot.footprint`.
- `Sources/CityDeveloper/Game/UnitSprites.swift:32-33` — пример
  `Bundle.module.url(forResource: name, withExtension: "png",
  subdirectory: "Buildings")`. Тот же паттерн для JSON.
- `Sources/CityDeveloper/World/WorldMapStore.swift:17-29` — стандартный
  JSONDecoder + try/decode + fallback на errors.log. Точно эта же схема.
- `Sources/CityDeveloper/Data/ErrorsLog.swift:1-22` — `ErrorsLog.write(_:)`
  async + ISO8601 timestamp. Использовать для validation warnings.

**Связанные модули, не трогать:**
- `Game/UnitPlanner.swift` — интеграция с шаблонами в TASK-048, не сейчас.
- `Game/CityEngine.swift` — пока шаблон только грузится, не используется.

**Что переиспользуем:** `BiomeKind`, `GridSize`, `Bundle.module`,
`JSONDecoder`, `ErrorsLog.write`.

**Что нужно дописать:**
- `Sources/CityDeveloper/Game/Templates/DistrictTemplate.swift` (НОВЫЙ) —
  модель + slot + role.
- `Sources/CityDeveloper/Game/Templates/DistrictTemplateCatalog.swift` (НОВЫЙ) —
  singleton-loader.
- 5 JSON в `Sources/CityDeveloper/Resources/DistrictTemplates/egyptian/`.
- `Tests/CityDeveloperTests/DistrictTemplateCatalogTests.swift` (НОВЫЙ).

### Архитектурное решение

**Модель — три типа в одном файле** (`DistrictTemplate.swift`):
- `enum SlotRole: String, Codable, CaseIterable, Sendable` (13 cases).
- `struct TemplateSlot: Codable, Sendable` (x, y, role, footprint).
- `struct DistrictTemplate: Codable, Sendable` (name, family, stage, width,
  height, biomePreference, slots).

Все три — `Sendable` (F-25 требование, value types с примитивными полями).
Файл компактный (≤80 строк), один отвественный — модель данных.

**Catalog — synchronously lazy singleton** (`DistrictTemplateCatalog.swift`):
- `enum DistrictTemplateCatalog` (caseless namespace).
- Static `private static var cache: [DistrictTemplate]?` — кеш.
- Static `private static let ioQueue = DispatchQueue(label: "city.district.catalog.io")` —
  serialization для read/write `cache` (по образцу `ErrorsLog`). Решает
  race condition при concurrent test setUp / multiple thread access.
- `static func all() -> [DistrictTemplate]` — lazy init: первый вызов
  сканирует **все подпапки** `Bundle.module.urls(forResourcesWithExtension:
  "json", subdirectory: "DistrictTemplates/<family>")` для **каждой
  обнаруженной family-папки** (через `Bundle.module.urls(forResourcesWithExtension:
  nil, subdirectory: "DistrictTemplates")` + filter isDirectory). Парсит каждый JSON,
  фильтрует невалидные, кеширует. Family определяется из поля JSON `"family"`,
  не из имени папки (защита от рассинхронизации).
  - **MVP fallback (если scan папок не работает в SwiftPM bundle)**: hardcode
    список families = `["egyptian"]`. TASK-051 / Roman/Greek follow-up
    задачи добавят новые имена в этот список явно. Это **приемлемое
    ограничение MVP**, документируем в Catalog header.
- `static func byFamily(_ family: String) -> [DistrictTemplate]` —
  `all().filter { $0.family == family }`. Поддерживает любую family,
  присутствующую в catalog.
- `static func byStage(_ stage: Int, family: String) -> [DistrictTemplate]` —
  `byFamily(family).filter { $0.stage == stage }`.
- `static func availableFamilies() -> Set<String>` — `Set(all().map(\.family))`
  (нужно в TASK-051 для Picker).

**Validation `validate(_:)` — `internal` (НЕ private)**, чтобы тесты могли
вызвать через `@testable import` (test `testNoOverlappingSlots`).

**`Sendable` note**: `TemplateSlot.footprint: GridSize` неявно требует
`GridSize: Sendable`. В Swift 5.10 без `-strict-concurrency=complete` (текущая
конфигурация Package.swift) компилятор это пропускает молча. **План явно
оставляет `GridSize` без Sendable** (CityState.swift не трогаем). Если в
будущем включат strict-concurrency — добавить `Sendable` к `GridSize` в одну
строку (это будет отдельная micro-task).

**Validation — pure-функция, отдельная**:
- `static func validate(_ template: DistrictTemplate) -> ValidationError?`
  проверяет: bbox (все slots в границах), no overlapping footprints, валидная
  role (через decoding уже проверено, но defence in depth).
- Невалидные шаблоны не попадают в catalog, ошибка в `ErrorsLog.write`.

**Почему не protocol/struct trait для validation?** Прагматично: 5 правил
валидации, fits в 30 строк pure-функции. Protocol только усложнит.

### JSON-схема (формальная)

```json
{
  "name": "stage1-deir-el-medina",
  "family": "egyptian",
  "stage": 1,
  "width": 8,
  "height": 5,
  "biomePreference": ["meadow", "desert"],
  "slots": [
    { "x": 1, "y": 1, "role": "residential", "footprint": { "width": 1, "height": 1 } },
    { "x": 2, "y": 1, "role": "residential", "footprint": { "width": 1, "height": 1 } },
    { "x": 4, "y": 1, "role": "residential", "footprint": { "width": 1, "height": 1 } },
    { "x": 5, "y": 1, "role": "residential", "footprint": { "width": 1, "height": 1 } },
    { "x": 1, "y": 2, "role": "road",         "footprint": { "width": 1, "height": 1 } },
    { "x": 2, "y": 2, "role": "road",         "footprint": { "width": 1, "height": 1 } },
    { "x": 3, "y": 2, "role": "road",         "footprint": { "width": 1, "height": 1 } },
    { "x": 4, "y": 2, "role": "road",         "footprint": { "width": 1, "height": 1 } },
    { "x": 5, "y": 2, "role": "road",         "footprint": { "width": 1, "height": 1 } },
    { "x": 6, "y": 2, "role": "road",         "footprint": { "width": 1, "height": 1 } },
    { "x": 1, "y": 3, "role": "residential", "footprint": { "width": 1, "height": 1 } },
    { "x": 2, "y": 3, "role": "well",        "footprint": { "width": 1, "height": 1 } },
    { "x": 3, "y": 3, "role": "residential", "footprint": { "width": 1, "height": 1 } },
    { "x": 5, "y": 3, "role": "residential", "footprint": { "width": 1, "height": 1 } },
    { "x": 6, "y": 3, "role": "residential", "footprint": { "width": 1, "height": 1 } }
  ]
}
```

Это **stage1-deir-el-medina.json** в финальном виде. Остальные 4 шаблона
исполнитель собирает по тому же принципу из ASCII-эскизов (см. ниже шаг 4).

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку. Шаг непонятен — НЕ импровизируй.

1. **Модель `DistrictTemplate.swift`** `[AC:1,2,3]`
   - Файл: `Sources/CityDeveloper/Game/Templates/DistrictTemplate.swift` (НОВЫЙ,
     включая создание директории `Game/Templates/`)
   - Содержимое (скелет, не финальный код):
     ```swift
     import Foundation

     enum SlotRole: String, Codable, CaseIterable, Sendable {
         case residential, well, road, market, temple, workshop, farm,
              bath, school, obelisk, gate, warehouse, monumental
     }

     struct TemplateSlot: Codable, Sendable {
         let x: Int
         let y: Int
         let role: SlotRole
         let footprint: GridSize
     }

     struct DistrictTemplate: Codable, Sendable {
         let name: String
         let family: String
         let stage: Int
         let width: Int
         let height: Int
         let biomePreference: [BiomeKind]
         let slots: [TemplateSlot]
     }
     ```
   - Все типы — `Codable, Sendable`. `GridSize` уже Codable из CityState.swift.

2. **Catalog `DistrictTemplateCatalog.swift`** `[AC:6]`
   - Файл: `Sources/CityDeveloper/Game/Templates/DistrictTemplateCatalog.swift` (НОВЫЙ)
   - Скелет:
     ```swift
     import Foundation

     enum DistrictTemplateCatalog {
         private static var cache: [DistrictTemplate]?
         private static let ioQueue = DispatchQueue(label: "city.district.catalog.io")

         static func all() -> [DistrictTemplate] {
             ioQueue.sync {
                 if let cache { return cache }
                 let loaded = loadFromBundle()
                 cache = loaded
                 return loaded
             }
         }

         static func byFamily(_ family: String) -> [DistrictTemplate] {
             all().filter { $0.family == family }
         }

         static func byStage(_ stage: Int, family: String) -> [DistrictTemplate] {
             byFamily(family).filter { $0.stage == stage }
         }

         static func availableFamilies() -> Set<String> {
             Set(all().map(\.family))
         }

         private static func loadFromBundle() -> [DistrictTemplate] {
             let families = ["egyptian"]  // hardcoded MVP, TASK-051 follow-up для дин.списка
             var result: [DistrictTemplate] = []
             var seenNames = Set<String>()
             for family in families {
                 let urls = Bundle.module.urls(
                     forResourcesWithExtension: "json",
                     subdirectory: "DistrictTemplates/\(family)"
                 ) ?? []
                 for url in urls {
                     guard let data = try? Data(contentsOf: url) else {
                         ErrorsLog.write("[template-loader] failed to read \(url.lastPathComponent)")
                         continue
                     }
                     do {
                         let template = try JSONDecoder().decode(DistrictTemplate.self, from: data)
                         if let err = validate(template) {
                             ErrorsLog.write("[template-loader] skipped \(url.lastPathComponent): \(err)")
                             continue
                         }
                         if seenNames.contains(template.name) {
                             ErrorsLog.write("[template-loader] duplicate name '\(template.name)' (file \(url.lastPathComponent)) — using first wins")
                             continue
                         }
                         seenNames.insert(template.name)
                         result.append(template)
                     } catch {
                         ErrorsLog.write("[template-loader] decode failed for \(url.lastPathComponent): \(error)")
                     }
                 }
             }
             return result
         }

         // ВАЖНО: internal, не private — нужен для тестов через @testable import.
         static func validate(_ t: DistrictTemplate) -> String? {
             var occupied: Set<GridPoint> = []
             for slot in t.slots {
                 let cells = footprintCells(slot: slot)
                 for cell in cells {
                     if cell.x < 0 || cell.x >= t.width || cell.y < 0 || cell.y >= t.height {
                         return "slot at (\(slot.x),\(slot.y)) footprint \(slot.footprint.width)×\(slot.footprint.height) is out of bounds (template \(t.width)×\(t.height))"
                     }
                     if occupied.contains(cell) {
                         return "slot at (\(slot.x),\(slot.y)) overlaps existing slot at \(cell)"
                     }
                     occupied.insert(cell)
                 }
             }
             return nil
         }

         private static func footprintCells(slot: TemplateSlot) -> [GridPoint] {
             var cells: [GridPoint] = []
             for dx in 0..<slot.footprint.width {
                 for dy in 0..<slot.footprint.height {
                     cells.append(GridPoint(x: slot.x + dx, y: slot.y + dy))
                 }
             }
             return cells
         }

         // testing helper — позволяет тестам сбросить кеш
         #if DEBUG
         static func resetCache() { cache = nil }
         #endif
     }
     ```
   - Threading note: `cache` без локов; первый вызов из main thread (engine
     init), последующие читают immutable cache. Если в будущем потребуется
     concurrent reset — обернуть в DispatchQueue (out-of-scope сейчас).

3. **Директория Resources** `[AC:4]`
   - Создать `Sources/CityDeveloper/Resources/DistrictTemplates/egyptian/`
     (mkdir -p).
   - SwiftPM `.process("Resources")` подхватит автоматически.

4. **5 JSON-шаблонов egyptian-семьи** `[AC:4,5]`

   **Принцип построения (инвариант для TASK-049 migration):**
   `slots(stage N) ⊂ slots(stage N+1)` — каждый слот stage N присутствует в
   stage N+1 с **точно теми же координатами и той же role**. Stage N+1
   только **добавляет** новые слоты (≥10), bbox растёт. Этот инвариант
   проверяется тестом `testStageProgressionPreservesSlots` (шаг 5).

   **Файл 1: `stage1-deir-el-medina.json`** (15 слотов, 8×5) — финальный JSON:
   ```json
   {
     "name": "stage1-deir-el-medina",
     "family": "egyptian",
     "stage": 1,
     "width": 8,
     "height": 5,
     "biomePreference": ["meadow", "desert"],
     "slots": [
       { "x": 1, "y": 1, "role": "residential", "footprint": { "width": 1, "height": 1 } },
       { "x": 2, "y": 1, "role": "residential", "footprint": { "width": 1, "height": 1 } },
       { "x": 4, "y": 1, "role": "residential", "footprint": { "width": 1, "height": 1 } },
       { "x": 5, "y": 1, "role": "residential", "footprint": { "width": 1, "height": 1 } },
       { "x": 1, "y": 2, "role": "road", "footprint": { "width": 1, "height": 1 } },
       { "x": 2, "y": 2, "role": "road", "footprint": { "width": 1, "height": 1 } },
       { "x": 3, "y": 2, "role": "road", "footprint": { "width": 1, "height": 1 } },
       { "x": 4, "y": 2, "role": "road", "footprint": { "width": 1, "height": 1 } },
       { "x": 5, "y": 2, "role": "road", "footprint": { "width": 1, "height": 1 } },
       { "x": 6, "y": 2, "role": "road", "footprint": { "width": 1, "height": 1 } },
       { "x": 1, "y": 3, "role": "residential", "footprint": { "width": 1, "height": 1 } },
       { "x": 2, "y": 3, "role": "well", "footprint": { "width": 1, "height": 1 } },
       { "x": 3, "y": 3, "role": "residential", "footprint": { "width": 1, "height": 1 } },
       { "x": 5, "y": 3, "role": "residential", "footprint": { "width": 1, "height": 1 } },
       { "x": 6, "y": 3, "role": "residential", "footprint": { "width": 1, "height": 1 } }
     ]
   }
   ```

   **Файл 2: `stage2-kahun.json`** (25 слотов = 15 stage1 + 10 новых, 12×7) — финальный JSON:
   ```json
   {
     "name": "stage2-kahun",
     "family": "egyptian",
     "stage": 2,
     "width": 12,
     "height": 7,
     "biomePreference": ["meadow", "desert"],
     "slots": [
       { "x": 1, "y": 1, "role": "residential", "footprint": { "width": 1, "height": 1 } },
       { "x": 2, "y": 1, "role": "residential", "footprint": { "width": 1, "height": 1 } },
       { "x": 4, "y": 1, "role": "residential", "footprint": { "width": 1, "height": 1 } },
       { "x": 5, "y": 1, "role": "residential", "footprint": { "width": 1, "height": 1 } },
       { "x": 1, "y": 2, "role": "road", "footprint": { "width": 1, "height": 1 } },
       { "x": 2, "y": 2, "role": "road", "footprint": { "width": 1, "height": 1 } },
       { "x": 3, "y": 2, "role": "road", "footprint": { "width": 1, "height": 1 } },
       { "x": 4, "y": 2, "role": "road", "footprint": { "width": 1, "height": 1 } },
       { "x": 5, "y": 2, "role": "road", "footprint": { "width": 1, "height": 1 } },
       { "x": 6, "y": 2, "role": "road", "footprint": { "width": 1, "height": 1 } },
       { "x": 1, "y": 3, "role": "residential", "footprint": { "width": 1, "height": 1 } },
       { "x": 2, "y": 3, "role": "well", "footprint": { "width": 1, "height": 1 } },
       { "x": 3, "y": 3, "role": "residential", "footprint": { "width": 1, "height": 1 } },
       { "x": 5, "y": 3, "role": "residential", "footprint": { "width": 1, "height": 1 } },
       { "x": 6, "y": 3, "role": "residential", "footprint": { "width": 1, "height": 1 } },
       { "x": 4, "y": 3, "role": "residential", "footprint": { "width": 1, "height": 1 } },
       { "x": 7, "y": 2, "role": "road", "footprint": { "width": 1, "height": 1 } },
       { "x": 8, "y": 2, "role": "road", "footprint": { "width": 1, "height": 1 } },
       { "x": 1, "y": 4, "role": "residential", "footprint": { "width": 1, "height": 1 } },
       { "x": 2, "y": 4, "role": "residential", "footprint": { "width": 1, "height": 1 } },
       { "x": 3, "y": 4, "role": "road", "footprint": { "width": 1, "height": 1 } },
       { "x": 4, "y": 4, "role": "residential", "footprint": { "width": 1, "height": 1 } },
       { "x": 5, "y": 4, "role": "residential", "footprint": { "width": 1, "height": 1 } },
       { "x": 7, "y": 4, "role": "farm", "footprint": { "width": 2, "height": 2 } },
       { "x": 9, "y": 2, "role": "farm", "footprint": { "width": 2, "height": 2 } }
     ]
   }
   ```

   **Файлы 3-5: stage 3, 4, 5** — строятся по тому же принципу:

   - **Файл 3: `stage3-ahmarna-middle.json`** (35 слотов = 25 stage2 + 10 новых, 14×9). Новые слоты (примерно):
     - Продолжение cross-street: (3,5) road, (3,6) road.
     - Residential ряды y=5: (1,5)(2,5)(4,5)(5,5)(6,5) residential.
     - Temple: (5,6) с footprint 2×2 (cells 5,6 6,6 5,7 6,7).
     - Workshop: (11,3) workshop 1×1.
     - +1 residential для round-up до 10 новых.
     - bbox: (1,1)-(11,7), внутри 14×9.

   - **Файл 4: `stage4-pharaonic-services.json`** (45 слотов = 35 stage3 + 10 новых, 16×12). Новые:
     - Market 2×2 в (8,6) (cells 8,6 9,6 8,7 9,7).
     - Bath 2×2 в (1,8) (cells 1,8 2,8 1,9 2,9).
     - School 2×2 в (4,8) (cells 4,8 5,8 4,9 5,9).
     - Workshops 1×1: (11,5)(12,5)(11,6)(12,6).
     - Road: (3,8) road, (7,8) road, (8,8) road.

   - **Файл 5: `stage5-akhetaten-ceremonial.json`** (≥50 слотов = 45 stage4 + ≥5 monumental, 16×16). Новые:
     - "Manor" (= residential 3×3) в (10,8) (cells 10,8..12,10). Role: `residential`,
       footprint: 3×3. В SlotRole нет специального case «manor» — большие
       residential различаются footprint'ом, role одинаковая.
     - Monumental (пирамида) 3×3 в (4,11) (cells 4,11..6,13).
     - Obelisk 1×1 в (1,11).
     - Road: (2,11)(3,11).
     - Residential 1×1 в (1,12).

   **Исполнитель**: при написании stage 3-5 JSON начинать с копии слотов из
   предыдущего stage (буквально copy-paste из `stage2-kahun.json` в начало
   `stage3-ahmarna-middle.json`), затем добавлять новые слоты в конец. Это
   гарантирует инвариант. Тест `testStageProgressionPreservesSlots` поймает
   нарушения.

5. **Тесты** `[AC:7]`
   - Файл: `Tests/CityDeveloperTests/DistrictTemplateCatalogTests.swift` (НОВЫЙ)
   - Кейсы:
     - `testLoadsAllEgyptianTemplates`: `DistrictTemplateCatalog.byFamily("egyptian").count == 5`.
     - `testStageCoverageOneToFive`: для каждого `s` в 1...5,
       `byStage(s, family: "egyptian").count >= 1`.
     - `testNoOverlappingSlots`: для каждого шаблона в catalog проверить, что
       `validate(template) == nil` (commit-time guard, должно быть истинно
       всегда — иначе catalog бы не загрузил). Использует `internal` validate.
     - `testRolesValid`: для каждого шаблона все `slot.role` лежат в
       `SlotRole.allCases` (тоже tautology после decode, но guard).
     - `testBiomePreferenceValid`: для каждого шаблона все элементы
       `biomePreference` — валидные `BiomeKind` (decode-time check).
     - **`testStageProgressionPreservesSlots`** (R2 — критический инвариант
       для TASK-049): для каждой пары `(stage N, stage N+1)` в family
       "egyptian":
       - получить шаблон stage N (первый из `byStage(N, "egyptian")`).
       - получить шаблон stage N+1 (первый из `byStage(N+1, "egyptian")`).
       - для **каждого** слота из stage N проверить, что в stage N+1
         существует слот с **точно теми же** `x`, `y`, `role`, `footprint`.
       - failure message: «slot (x,y,role,footprint) из stage N отсутствует
         или изменён в stage N+1; нарушает инвариант для TASK-049 migration».
     - **`testStageProgressionBboxNonShrinking`** (R2 связанный): bbox slots
       stage N+1 включает bbox stage N (maxX, maxY не уменьшаются).
   - Helper: `private func loadCatalog()` вызывает `resetCache()` + `all()`
     чтобы тесты были независимы. **Лок DispatchQueue убирает race condition.**

6. **Документация** `[AC:DoD]`
   - Создать `concept/TemplateCatalog.md` с разделами:
     - Формат JSON (схема + пример из шага 4).
     - Список egyptian-шаблонов (имена + stage + ASCII-силуэт).
     - Как добавить новый шаблон (положить JSON, запустить swift test).
     - Инварианты (bbox stage N ⊆ stage N+1; no overlap).

### Edge cases (явно обработать)

- [ ] Bundle.module.urls возвращает nil → catalog возвращает пустой массив
      (не падает). Тест `testLoadsAllEgyptianTemplates` проверяет, что
      результат не пустой при наличии JSON-файлов.
- [ ] JSON с unknown role (например, "stadium") → JSONDecoder бросает
      error → catch → write to errors.log → шаблон не попадает в результат.
- [ ] JSON с duplicate name (две файла с `"name": "stage1-foo"`) → второй
      пропускается, warning. Используем `seenNames: Set<String>`.
- [ ] Slot footprint 2×2 в (width-1, height-1) → out-of-bounds (нужно
      (width-2, height-2)). validate ловит.
- [ ] Empty `slots: []` → валидно (validate проходит), но useless для
      placement. Allowed by spec — TASK-048 даст fallback.
- [ ] Empty `biomePreference: []` → валидно, значит «подходит для любого
      биома». Picker (TASK-048) интерпретирует.
- [ ] Cache между тестами: `resetCache()` в #if DEBUG для test isolation.
      В production cache не сбрасывается (она immutable).

### Файлы для изменения

- **НОВЫЕ:**
  - `Sources/CityDeveloper/Game/Templates/DistrictTemplate.swift` (модель, ~30 строк)
  - `Sources/CityDeveloper/Game/Templates/DistrictTemplateCatalog.swift` (catalog, ~80 строк)
  - `Sources/CityDeveloper/Resources/DistrictTemplates/egyptian/stage1-deir-el-medina.json`
  - `Sources/CityDeveloper/Resources/DistrictTemplates/egyptian/stage2-kahun.json`
  - `Sources/CityDeveloper/Resources/DistrictTemplates/egyptian/stage3-ahmarna-middle.json`
  - `Sources/CityDeveloper/Resources/DistrictTemplates/egyptian/stage4-pharaonic-services.json`
  - `Sources/CityDeveloper/Resources/DistrictTemplates/egyptian/stage5-akhetaten-ceremonial.json`
  - `Tests/CityDeveloperTests/DistrictTemplateCatalogTests.swift`
  - `concept/TemplateCatalog.md`

### Файлы НЕ трогать

- `Package.swift` — `.process("Resources")` уже настроен.
- `Sources/CityDeveloper/Data/CityState.swift` — `BiomeKind`, `GridSize`,
  `GridPoint` уже Codable, ничего не менять.
- `Sources/CityDeveloper/Game/UnitPlanner.swift` — интеграция в TASK-048.
- `Sources/CityDeveloper/Game/CityEngine.swift` — не сейчас.
- `Sources/CityDeveloper/Data/AppSettings.swift` — templateFamily в TASK-051.

### Команды проверки (для DoD)

- Компиляция: `swift build`
- Только новые тесты: `swift test --filter DistrictTemplateCatalogTests` →
  5/5 PASS.
- JSON-валидность offline: `for f in Sources/CityDeveloper/Resources/DistrictTemplates/egyptian/*.json; do jq . "$f" > /dev/null || echo "INVALID: $f"; done`
- Полный прогон: `swift test` → 76+5=81 PASS (1 known-fail BUG-020), нет регрессов.

### Сложность

`middle`

**Обоснование:** 3 новых файла кода + 5 JSON + 1 тестовый файл + 1 doc.
Логика валидации простая (≤30 строк), Bundle.module стандартный паттерн.
Не junior, потому что: (а) `Sendable` conformance не используется в проекте
сейчас (первый прецедент), (б) 5 JSON-шаблонов с инвариантом «bbox stage N
⊆ stage N+1» требует аккуратной координатной разметки, (в) errors.log
обработка для каждой развилки validation.

### Ожидаемое время

M (≤1д)

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_ (определит лид)
_Объём: M_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] `swift test --filter DistrictTemplateCatalogTests` зелёный

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Существующие 76 тестов не сломаны (77 total, 1 known-fail BUG-020) →
      после задачи: 76+7=83 PASS, 1 known-fail
- [ ] JSON-файлы валидны: `for f in Sources/CityDeveloper/Resources/DistrictTemplates/egyptian/*.json; do jq . "$f" > /dev/null || echo "INVALID: $f"; done`

#### Обновление документации
- [ ] `Current.md`: F-25 → ⚠️ (часть 1/5, есть формат + первая семья)
- [ ] `Diff.md`: D-25 не закрывать (закрывается только после TASK-051)
- [ ] `concept/UnitCatalog.md` или новый `concept/TemplateCatalog.md` —
      краткое описание формата JSON + список egyptian-шаблонов

---

## Статус

`[x] done` (closed 2026-05-24)

## Метаданные
- Создана PM: 2026-05-24
- Spec-review: approved
- Lead-model: opus
- Plan-review: revised (круг 1 → 6 правок применены → круг 2 approved + 3 micro-fix)
- Run-model: sonnet (delegated, middle complexity)
- Blocked-by: —
- Готова к работе: 2026-05-24
- Завершена: 2026-05-24
- Коммит: pending
- Артефакты:
  - `Sources/CityDeveloper/Game/Templates/DistrictTemplate.swift` (36 строк,
    модель + Sendable)
  - `Sources/CityDeveloper/Game/Templates/DistrictTemplateCatalog.swift` (120 строк,
    singleton + ioQueue + internal validate)
  - `Sources/CityDeveloper/Resources/DistrictTemplates/egyptian/` (5 JSON:
    stage1 15 слотов, stage2 25, stage3 35, stage4 45, stage5 51 — инвариант
    bbox+slot-preservation выполнен и проверен тестом)
  - `Tests/CityDeveloperTests/DistrictTemplateCatalogTests.swift` (7 тестов, PASS)
  - `concept/TemplateCatalog.md` (201 строка, формат JSON + список + инварианты)
- Отклонение от плана: SwiftPM `.process("Resources")` сглаживает подпапки,
  `Bundle.module.urls(...subdirectory:)` не работает с вложенными каталогами.
  Sonnet обошёл: загружает все JSON из bundle root и фильтрует по полю
  `family` из декодированного JSON. Это **лучше** чем hardcode семей —
  catalog динамически подхватывает любую family из JSON без правок кода.
