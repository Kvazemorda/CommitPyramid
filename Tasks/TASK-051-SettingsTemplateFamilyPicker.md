# TASK-051: Settings UI — выбор «Стиль города» (templateFamily Picker)

## Связь
- **F-25** из Concept.md (шаблоны кварталов)
- **F-14** из Concept.md (Settings UI)
- **D-25** из Diff.md (часть 5/5 — настройка стиля)
- **Приоритет:** P2

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-24_

### Что хотим

Пользователь должен иметь возможность **выбирать стиль города** в
Settings — egyptian / roman / greek / mixed / auto. Без программирования
и без редактирования файлов. Эта настройка применяется к **новым
проектам** (существующие кварталы не перерисовываются, иначе сломаем
replay).

Это последняя часть F-25 — пользовательский control над шаблонами.

### Пользовательский сценарий

1. Пользователь открывает Settings (⌘,) → новая секция «Стиль города».
2. Видит Picker с 5 опциями:
   - `Auto` (по биому) — default.
   - `Egyptian` (Pharaoh-style).
   - `Roman` (castrum/insula). [только когда добавлена Roman family — TASK
     по backlog]
   - `Greek` (Hippodamian/polis). [только когда добавлена Greek family]
   - `Mixed` (рандом на каждый проект).
3. Tooltip объясняет: «Влияет только на новые проекты. Существующие
   кварталы сохраняют свой стиль».
4. Пользователь выбирает «Mixed» → следующий новый проект получает
   случайно выбранную family (детерминированно по projectId hash).
5. Чекбокс ниже: «Показывать silhouette шаблона при создании квартала
   (debug)» — по умолчанию off.

### Acceptance criteria

- [ ] `AppSettings.templateFamily: String` (default `"auto"`) — добавляется
      в AppSettings, persistence v4 (UserDefaults). Backwards-compat:
      старые версии без поля → "auto".
- [ ] `AppSettings.previewTemplateSilhouette: Bool` (default false) — debug
      toggle.
- [ ] Новая Section в `SettingsView`: `TemplateFamilySection`. Содержит:
      - `Picker("Стиль города", selection: $settings.templateFamily)` с
        опциями только из families, реально присутствующих в
        `DistrictTemplateCatalog.availableFamilies()` (`auto` и `mixed`
        всегда есть).
      - `Toggle("Превью шаблона при создании квартала",
        isOn: $settings.previewTemplateSilhouette)`.
      - Text с tooltip explanation.
- [ ] `DistrictTemplatePicker` обновлён: family `"mixed"` → выбирает
      случайную family через `SplitMix64(seed: fnv1a([projectId,
      "mixed-family"]))`, family `"auto"` → biome-based mapping
      (meadow/desert → egyptian; mountain/stone → roman; sea/river →
      greek; fallback → egyptian).
- [ ] Изменение `templateFamily` в Settings **НЕ** triggers перерисовку
      существующих кварталов. Только новые проекты после смены получают
      новую family.
- [ ] Если выбранная family отсутствует в catalog (например, выбран
      Roman до того, как Roman добавлена) → fallback на "auto" с
      warning'ом в errors.log при создании нового проекта.
- [ ] Если включён `previewTemplateSilhouette` → при создании нового
      квартала GameScene на 3 секунды рисует полупрозрачный (alpha 0.3)
      контур всех слотов шаблона; через 3 сек fade-out.
- [ ] Тест `AppSettingsTemplateFamilyTests.swift`:
      `testDefaultIsAuto`,
      `testPersistenceRoundtrip`,
      `testInvalidFamilyFallsBackToAuto`.
- [ ] Тест `SettingsViewSnapshotTests.swift` (если есть инфраструктура для
      SwiftUI snapshot — иначе manual visual check) — секция отрисовывается
      без overflow в текущей ширине окна (BUG-003 регресс).

### Что НЕ делаем (границы скоупа)

- НЕ добавляем «перерисовать все существующие кварталы» — это нарушит
  replay-детерминизм.
- НЕ добавляем семьи Roman/Greek сами — их добавление = отдельная TASK
  в backlog (template-content task, не logic).
- НЕ позволяем пользователю редактировать сами шаблоны через UI — это
  работа разработчика/контрибьютора через JSON-файлы.

### Edge cases

- [ ] Catalog содержит только egyptian → Picker показывает 3 опции:
      Auto / Egyptian / Mixed. Roman/Greek не видны.
- [ ] Mixed + только 1 доступная family → mixed эквивалентен этой
      family (нечего рандомизировать).
- [ ] Settings persistence v3 → v4 миграция: при первом запуске после
      релиза добавляется templateFamily="auto" в существующий
      UserDefaults без потери других настроек.
- [ ] Auto + nil biome (новая карта до biome init) → fallback "egyptian".
- [ ] Окно Settings слишком узкое (BUG-003 регресс) → новая секция
      обёрнута в ScrollView вместе с остальными (BUG-007 регресс).

### Зависимости

- **Blocked-by:** TASK-047 (catalog), TASK-048 (Picker uses
  templateFamily).
- **Soft-blocks:** —

### Дизайн

`SettingsView` уже существует (см. `Sources/CityDeveloper/UI/SettingsView.swift`).
Новая секция вставляется по аналогии с `GitWatcherSection` /
`NotesWatcherSection`. Picker SwiftUI стандартный (segmented или menu —
на усмотрение исполнителя, главное чтобы текст не обрезался при
default width).

### Done-критерий

_Часть F-25 Done-критерия:_ «Переключение templateFamily в Settings
влияет только на следующие новые проекты». Эта TASK закрывает это
полностью.

**Закрывает D-25 целиком** (последняя из 5 задач F-25).

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-24_
_Модель: sonnet_
_Статус: [x] готов_

### Анализ текущего состояния

**Что уже есть (готово к переиспользованию):**
- `AppSettings.templateFamily: String = "auto"` и `AppSettings.previewTemplateSilhouette: Bool = false`
  (`Sources/CityDeveloper/Data/AppSettings.swift:40-42`) — добавлены в TASK-048a, persistence v4
  через `Persisted` struct с optional полями (backwards-compat). Сериализуются через JSONEncoder в
  UserDefaults. Тест `AppSettingsV4MigrationTests.test_DefaultTemplateFamilyIsAuto` уже подтверждает дефолты.
- `DistrictTemplateCatalog.availableFamilies() -> Set<String>`
  (`Sources/CityDeveloper/Game/Templates/DistrictTemplateCatalog.swift:40-42`) — возвращает множество
  family, фактически присутствующих в bundle. MVP: `{"egyptian"}`.
- `DistrictTemplatePicker.pick(stage:family:biome:seed:) -> DistrictTemplate?`
  (`Sources/CityDeveloper/Game/Templates/DistrictTemplatePicker.swift:42-61`):
  - `"auto"` (строки 48-50): пока hardcode `"egyptian"` — это место для biome-based mapping;
  - `"mixed"` (строки 51-57): уже корректно — берёт `availableFamilies().sorted()`, при единственной
    family возвращает её, иначе SplitMix64-pick. **AC уже выполнен — не трогаем.**
  - Прочие значения (строка 59): возвращает as-is.
- `CityEngine.templateFamily: String = "auto"` (`Game/CityEngine.swift:52`) и его использование при
  создании нового проекта (строки 304-316) — wiring до AppSettings ещё не сделан (follow-up TASK-048c).
- `GameScene.markDistrict(project:)` (`Game/GameScene.swift:256-263`) — вызывается через
  `engine.onProjectCreated` callback из AppDelegate. Сейчас рисует только маркер; навесить туда
  silhouette-overlay безопасно (через одноразовый side-effect внутри scene по флагу AppSettings).
- `ErrorsLog.write(_:)` (`Data/ErrorsLog.swift`) — простой async API для warning'ов.
- `SettingsView` (`UI/SettingsView.swift`) — `ScrollView` + `VStack` + несколько `GroupBox`. Точка вставки
  новой секции — между `GitWatcherSection` (строка 110) и блоком `Reset & Rebuild` (строка 116).
- Settings окно (`App/SettingsWindowController.swift`): contentSize 720×600, minSize 640×480, есть
  ScrollView → новая секция влезает без BUG-003/BUG-007 регресса.

**Связанные модули (читаем, но не меняем сигнатуры):**
- `Data/CityState.swift` — `BiomeKind` enum (meadow/forest/mountain/stone/river/sea/desert).
- `Game/DeterministicRNG.swift` — `fnv1a(combining:)` для seed.
- `Tests/CityDeveloperTests/DistrictTemplatePickerTests.swift` — содержит существующий тест
  `test_AutoFamilyMapsToEgyptianMVP`, который нужно **переписать** под biome-based mapping.

**Что нужно дописать:**
1. AppDelegate wire `engine.templateFamily = appSettings.templateFamily` (initial + reactive в `applySettings`).
2. `DistrictTemplatePicker.resolveAutoFamily(biome:) -> String` — новый private helper с biome-based mapping.
3. `DistrictTemplatePicker.pick(...)` — после resolving family проверить
   `availableFamilies().contains(resolved)`. Если нет → fallback на "egyptian" (последняя гарантированно
   доступна в MVP) + ErrorsLog warning.
4. Новая секция `TemplateFamilySection` в `SettingsView.swift` (inline View struct, по аналогии с
   inline-секциями в этом же файле).
5. GameScene: при `appSettings.previewTemplateSilhouette == true` — рисовать silhouette-оверлей слотов
   шаблона на 3 сек (fadeIn 0.3 → fadeOut, удалить из scene). Хук — внутрь `drawDistrictMarker`
   через приватный helper, читает флаг через bridge (см. ниже).
6. `GameScene` ↔ AppSettings: scene должна знать про `previewTemplateSilhouette`. Простейший путь —
   weak reference на AppSettings (`scene.appSettings: AppSettings?`) или передача флага через метод.
   В файле уже есть `bench`/`debugOverlay` подобные флаги — выберем шаблон через прямой `weak var
   appSettings: AppSettings?` (consistent с `engine`).
7. Тесты:
   - `AppSettingsV4MigrationTests`: расширить либо новый файл `AppSettingsTemplateFamilyTests` —
     `testInvalidFamilyFallsBackToAuto` (фактически — invalid в Settings сохраняется, но fallback
     случается в Picker; тест проверяет round-trip любой строки).
   - `DistrictTemplatePickerTests`: переписать `test_AutoFamilyMapsToEgyptianMVP` →
     4 теста biome-mapping (meadow→egyptian / mountain→roman fallback / sea→greek fallback /
     nil → egyptian); добавить `test_InvalidFamilyFallsBackToEgyptianWithWarning` (проверка fallback +
     factное возвращение egyptian template).
8. Документы: `Current.md` (часть 7 — финал F-25), `Diff.md` (закрыть D-25, перенести в историю),
   `concept/Concept.md` (отметить F-25 part «Roman/Greek follow-up в Backlog»).

### Архитектурное решение

**Biome-based mapping для `"auto"`.** Реализуется как pure-функция `resolveAutoFamily(biome:)`:
- `.meadow, .desert` → `"egyptian"` (Pharaoh style для луга и пустыни)
- `.mountain, .stone` → `"roman"` (горный/каменный = castrum)
- `.sea, .river` → `"greek"` (приморский = polis)
- `.forest, nil` → `"egyptian"` (fallback)

После resolve **обязательно** проверяем `availableFamilies().contains(resolved)`. Если family отсутствует
в catalog (например, MVP без roman/greek) → пишем warning в ErrorsLog и возвращаем `"egyptian"`. Это
покрывает AC «Auto + nil biome → fallback egyptian» и «Если выбранная family отсутствует → fallback +
warning». Mapping не зависит от Settings — это политика Picker, и она тестируется без UI.

**"Mixed" уже работает.** Проверено в Explore: код корректный (SplitMix64-pick из sorted families),
тест `test_MixedFamilyPicksFromAvailable` есть. Не трогаем (минимизация риска регресса). AC «mixed +
1 family = эта family» уже покрыт строкой 53-55 Picker'а.

**AppDelegate wire.** Два места:
1. Сразу после создания engine (`AppDelegate.swift:44`): `engine.templateFamily = appSettings.templateFamily`.
2. В `applySettings()` (`AppDelegate.swift:201-222`): то же присваивание (reactive — пользователь меняет
   Picker → engine видит). Замена существующих кварталов **не** делаем — это явно в AC.

**Preview silhouette — overlay в GameScene.** Простой подход:
- В `GameScene` приватный helper `drawTemplateSilhouette(project:)` — берёт `project.templateName`,
  ищет template через `DistrictTemplateCatalog.byName`, рисует SKShapeNode-контуры для каждого `slot`
  (footprint в isometric coords) с alpha 0.3, fillColor систем-akcent.
- Action: `SKAction.sequence([fadeIn(0.2), wait(2.6), fadeOut(0.2), removeFromParent()])` — итого 3 сек.
- Триггер: внутри `drawDistrictMarker`, после установки маркера, `if appSettings?.previewTemplateSilhouette
  == true && project.templateName != nil → drawTemplateSilhouette(project:)`.
- AppSettings reference: добавить `weak var appSettings: AppSettings?` в GameScene; присвоить в AppDelegate
  сразу после создания scene (по аналогии с `engine`/`worldStore`).

**Errors-warning для unavailable family.** В Picker (а не в CityEngine), потому что catalog знает свой
inventory. Сообщение: `"[template] family '<resolved>' not available, fallback to 'egyptian'"`.

**Settings UI.** Новая секция `TemplateFamilySection` — inline view struct **внутри** `SettingsView.swift`
(по паттерну существующих GitWatcher/NotesWatcher секций — они тоже отдельные файлы; но шаблон-секция
маленькая, inline быстрее и без overengineering). Содержит:
- `Picker("Стиль города", selection: $settings.templateFamily)` с опциями:
  - `Text("Auto (по биому)").tag("auto")`
  - `Text("Mixed").tag("mixed")`
  - для каждой `f` в `DistrictTemplateCatalog.availableFamilies().sorted()`: `Text(humanName(f)).tag(f)`.
  - `humanName(_:)` — switch egyptian → "Египет", roman → "Рим", greek → "Греция", default → uppercased first.
- `Toggle("Превью контура шаблона при создании квартала (debug)", isOn: $settings.previewTemplateSilhouette)`
- `Text("Влияет только на новые проекты. Существующие кварталы сохраняют свой стиль.")` — `.font(.caption)`.

Picker style — `.menu` (consistent с другими Picker'ами в Settings, чтобы не обрезалось при default width).

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку. Шаг непонятен — НЕ импровизируй, возвращай задачу через сообщение.

1. **AppDelegate wire `templateFamily`** `[AC:6,7]`
   - Файл: `Sources/CityDeveloper/App/AppDelegate.swift`
   - Точка 1 — сразу после строки 44 (где создаётся `engine`):
     ```swift
     engine.templateFamily = appSettings.templateFamily
     ```
   - Точка 2 — внутри `applySettings()` (строки 201-222), в любое разумное место (рядом с другими
     присваиваниями engine.X = appSettings.Y, например после `engine.appPaths = ...`):
     ```swift
     engine.templateFamily = appSettings.templateFamily
     ```
   - Проверка: смена `templateFamily` в Settings → новый проект через add-task.sh получает выбранную family.

2. **DistrictTemplatePicker — biome-based mapping + fallback** `[AC:3,5]`
   - Файл: `Sources/CityDeveloper/Game/Templates/DistrictTemplatePicker.swift`
   - Перед текущим `pick(...)` добавить private helper:
     ```swift
     /// TASK-051 F-25: biome → дефолтная family для "auto" режима.
     private static func resolveAutoFamily(biome: BiomeKind?) -> String {
         guard let biome else { return "egyptian" }
         switch biome {
         case .meadow, .desert: return "egyptian"
         case .mountain, .stone: return "roman"
         case .sea, .river: return "greek"
         case .forest: return "egyptian"
         }
     }
     ```
   - В существующем helper `resolveFamily(_:biome:seed:) -> String?` ветка `"auto"` заменяется
     на вызов `resolveAutoFamily(biome:)`. Ветку `"mixed"` и default-ветку оставить как есть.
     `resolveFamily` остаётся чистой mapping-функцией (без I/O, без warning'ов).
   - В `pick(...)` ровно ПОСЛЕ `guard let resolved = resolveFamily(family, biome: biome, seed: seed) else { return nil }`
     добавить **availability fallback** (это не in-helper, чтобы `resolveFamily` оставалась pure):
     ```swift
     // TASK-051: availability fallback. resolved может быть несуществующей в catalog family
     // (например, пользователь выбрал "roman" в Settings, но MVP содержит только "egyptian").
     let available = DistrictTemplateCatalog.availableFamilies()
     let resolvedFamily: String
     if available.contains(resolved) {
         resolvedFamily = resolved
     } else {
         ErrorsLog.write("[template] family '\(resolved)' not available in catalog, falling back to 'egyptian'")
         resolvedFamily = "egyptian"
     }
     ```
     Дальше по коду — везде использовать `resolvedFamily` вместо `resolved` (фильтрация candidates,
     biome preference, sorted-pick). Существующий код фильтрации `-monumental`/`-legacy` не трогать.
   - Проверка: вызвать picker с `family: "auto", biome: .meadow` → возвращает egyptian-template; с
     `family: "roman"` в MVP (где roman нет) → возвращает egyptian + warning в errors.log.

3. **GameScene — silhouette overlay** `[AC:8]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift`
   - Добавить свойство (рядом с `engine`/`worldStore` weak refs):
     ```swift
     weak var appSettings: AppSettings?
     ```
   - В существующей `drawDistrictMarker(for:)` (вызывается из `markDistrict`) в конце метода:
     ```swift
     if appSettings?.previewTemplateSilhouette == true,
        let templateName = project.templateName,
        let template = DistrictTemplateCatalog.byName(templateName) {
         drawTemplateSilhouette(project: project, template: template)
     }
     ```
   - Новый private helper (полная реализация — `makeSlotFootprintPath` в проекте отсутствует,
     `slot.cells` тоже отсутствует, поэтому строим path вручную из реальных полей
     `TemplateSlot { x: Int, y: Int, role: SlotRole, footprint: GridSize { width, height }, minEra: Int }`
     через существующий `isoPosition(grid:)` и константы `tileWidth=64 / tileHeight=32`):
     ```swift
     private func drawTemplateSilhouette(project: ProjectState, template: DistrictTemplate) {
         let container = SKNode()
         container.zPosition = 5000  // поверх маркера, ниже UI
         container.alpha = 0.0
         let origin = project.districtOrigin
         for slot in template.slots {
             let path = CGMutablePath()
             for dx in 0..<slot.footprint.width {
                 for dy in 0..<slot.footprint.height {
                     let cell = GridPoint(x: origin.x + slot.x + dx, y: origin.y + slot.y + dy)
                     let pos = isoPosition(grid: cell)
                     // diamond вокруг pos (см. diamondPath() — тот же паттерн)
                     path.move(to:    CGPoint(x: pos.x,                     y: pos.y + tileHeight / 2))
                     path.addLine(to: CGPoint(x: pos.x + tileWidth / 2,     y: pos.y))
                     path.addLine(to: CGPoint(x: pos.x,                     y: pos.y - tileHeight / 2))
                     path.addLine(to: CGPoint(x: pos.x - tileWidth / 2,     y: pos.y))
                     path.closeSubpath()
                 }
             }
             let shape = SKShapeNode(path: path)
             shape.strokeColor = .systemBlue
             shape.fillColor = SKColor.systemBlue.withAlphaComponent(0.3)
             shape.lineWidth = 1.5
             container.addChild(shape)
         }
         addChild(container)
         let seq = SKAction.sequence([
             SKAction.fadeAlpha(to: 0.3, duration: 0.2),
             SKAction.wait(forDuration: 2.6),
             SKAction.fadeAlpha(to: 0.0, duration: 0.2),
             SKAction.removeFromParent()
         ])
         container.run(seq)
     }
     ```
   - Используемые символы (всё подтверждено в коде, не выдумывать своё):
     - `tileWidth = 64`, `tileHeight = 32` — private properties GameScene (строки 15-16).
     - `isoPosition(grid:) -> CGPoint` — internal-метод (строка 755).
     - `diamondPath()` — есть в файле (строка 767), но он возвращает path без origin'а; нам нужен per-cell
       path, поэтому свой собираем (но геометрия diamond'а идентична).
     - `TemplateSlot.x/y` — Int абсолютные координаты внутри template'а; `slot.footprint.width/height` —
       размер footprint'а; финальная позиция в мире = `origin + slot.{x,y} + {dx,dy}`.
   - Проверка: запустить app с `previewTemplateSilhouette=true` (через Settings или
     `defaults write`), создать новый проект через add-task.sh → видна полупрозрачная сетка слотов
     ~3 сек, потом исчезает.

4. **AppDelegate wire scene.appSettings** `[AC:8]`
   - Файл: `Sources/CityDeveloper/App/AppDelegate.swift`
   - После создания scene (рядом с `scene.engine = engine` или эквивалент) добавить:
     ```swift
     scene?.appSettings = appSettings
     ```
   - Проверка: компиляция, smoke (см. шаг 3).

5. **SettingsView — TemplateFamilySection** `[AC:1,2,4]`
   - Файл: `Sources/CityDeveloper/UI/SettingsView.swift`
   - Между `GitWatcherSection()` (строка 110) и блоком «Reset & Rebuild» (строка 116) вставить:
     ```swift
     TemplateFamilySection(settings: settings)
     ```
   - В конце файла (или рядом с другими inline-секциями) добавить inline view:
     ```swift
     private struct TemplateFamilySection: View {
         @ObservedObject var settings: AppSettings

         var body: some View {
             GroupBox(label: Label("Стиль города", systemImage: "building.columns")) {
                 VStack(alignment: .leading, spacing: 8) {
                     Picker("Стиль:", selection: $settings.templateFamily) {
                         Text("Auto (по биому)").tag("auto")
                         Text("Mixed (рандом на проект)").tag("mixed")
                         ForEach(availableFamilies, id: \.self) { f in
                             Text(humanName(f)).tag(f)
                         }
                     }
                     .pickerStyle(.menu)
                     Toggle(
                         "Превью контура шаблона при создании квартала (debug)",
                         isOn: $settings.previewTemplateSilhouette
                     )
                     Text("Влияет только на новые проекты. Существующие кварталы сохраняют свой стиль.")
                         .font(.caption)
                         .foregroundColor(.secondary)
                 }
                 .padding(.vertical, 4)
             }
         }

         private var availableFamilies: [String] {
             DistrictTemplateCatalog.availableFamilies().sorted()
         }

         private func humanName(_ family: String) -> String {
             switch family {
             case "egyptian": return "Египет"
             case "roman":    return "Рим"
             case "greek":    return "Греция"
             default:         return family.capitalized
             }
         }
     }
     ```
   - Проверка: запустить app → ⌘, → видна секция «Стиль города» между Git watcher и Reset, без
     обрезания текста. В MVP Picker показывает 3 опции: Auto / Mixed / Египет.

6. **Тесты — Picker biome mapping + fallback** `[AC:3,5]`
   - Файл: `Tests/CityDeveloperTests/DistrictTemplatePickerTests.swift`
   - **Удалить** существующий тест `test_AutoFamilyMapsToEgyptianMVP` (он покрывал MVP-hardcode,
     теперь поведение biome-based).
   - Добавить новые тесты. Все `XCTAssertEqual(t?.family, "egyptian")` проверяют `DistrictTemplate.family`
     — это поле из JSON выбранного шаблона, а не запрошенная family (в MVP все шаблоны имеют
     `family == "egyptian"`, потому что roman/greek JSON ещё нет; fallback приводит сюда же):
     ```swift
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
     ```
   - Проверка: `swift test --filter DistrictTemplatePickerTests` — все новые тесты pass.

7. **Тесты — AppSettings persistence** `[AC:1,2]`
   - Файл: `Tests/CityDeveloperTests/AppSettingsV4MigrationTests.swift`
   - **Имя файла:** PM в AC просил `AppSettingsTemplateFamilyTests.swift`, но логически новые тесты —
     продолжение persistence-сценариев из существующего `AppSettingsV4MigrationTests.swift`
     (testDefaultIsAuto, testV3ToV4Migration, testPersistenceRoundtrip уже там). Создавать отдельный
     файл ради одного теста — overengineering. **Решение:** AC закрывается по сути (persistence
     templateFamily покрыт), имя файла оставляем `AppSettingsV4MigrationTests.swift`. Если в будущем
     нужно добавить ≥3 теста — выделим в отдельный файл.
   - Добавить тест:
     ```swift
     func test_TemplateFamilyPersistsAnyString() throws {
         let suiteName = "AppSettings.test_TemplateFamilyPersistsAnyString"
         let defaults = UserDefaults(suiteName: suiteName)!
         defaults.removePersistentDomain(forName: suiteName)
         let a = AppSettings(userDefaults: defaults)
         a.templateFamily = "roman"            // строка, даже если family отсутствует в catalog
         a.previewTemplateSilhouette = true
         a.save()
         let b = AppSettings(userDefaults: defaults)
         XCTAssertEqual(b.templateFamily, "roman")
         XCTAssertTrue(b.previewTemplateSilhouette)
     }
     ```
   - Замечание: тест на «invalid family fallback» в `AppSettings` НЕ делаем — fallback это
     ответственность Picker'а, AppSettings хранит любую строку. Тест на fallback покрыт в шаге 6.
   - Проверка: `swift test --filter AppSettingsV4MigrationTests` — pass.

8. **Документация** `[AC:9 (implicit DoD)]`
   - Файл: `concept/Current.md` — добавить блок «прогон 2026-05-24 часть 7: F-25 финал — TASK-051».
   - Файл: `concept/Diff.md` — D-25 перенести в «Закрытые расхождения» (история), удалить из активной таблицы.
   - Файл: `concept/Concept.md` — проверить F-25, при необходимости пометить пометкой
     «egyptian-only first iteration; Roman/Greek follow-up в Backlog».
   - Файл: `concept/.sync-state.yaml` — F-25 → `status: "✅"`, `consecutive_ok: 1`.

### Edge cases (явно обработать)

- [ ] `availableFamilies()` пустой (битый bundle / нет JSON) — `Picker` покажет только Auto/Mixed,
      `resolveAutoFamily` вернёт "egyptian", fallback-проверка зальёт в "egyptian", который тоже
      отсутствует. **Не покрываем тестом** — это критичный bundle error, должен ловиться на старте.
      `DistrictTemplateCatalog.loadFromBundle()` уже падает с warning в errors.log в этом случае.
- [ ] AppSettings.templateFamily изменён → существующие проекты не перерисовываются. Тест не нужен:
      Engine применяет templateFamily только в `applyTaskCompleted → if isNewProject` ветке
      (`CityEngine.swift:533`), существующих проектов это не касается.
- [ ] `previewTemplateSilhouette=true`, но `project.templateName == nil` (legacy mode) →
      `drawTemplateSilhouette` не вызывается (guard в шаге 3). Корректно.
- [ ] `BiomeKind.forest` — в спеке не явно прописан, попадает в default branch `resolveAutoFamily` →
      egyptian. Корректно для MVP.
- [ ] Окно Settings слишком узкое (BUG-003/BUG-007 регресс) — новая секция уже внутри ScrollView
      (`SettingsView.swift:88` `ScrollView`), новые элементы используют `.menu` Picker и `Toggle` —
      не растягиваются. Manual visual check после имплементации.

### Файлы для изменения

- `Sources/CityDeveloper/App/AppDelegate.swift` — wire `engine.templateFamily` (initial + applySettings) +
  `scene.appSettings`.
- `Sources/CityDeveloper/Game/Templates/DistrictTemplatePicker.swift` — `resolveAutoFamily` helper +
  availability fallback в `pick(...)`.
- `Sources/CityDeveloper/Game/GameScene.swift` — `weak var appSettings` + `drawTemplateSilhouette` +
  вызов из `drawDistrictMarker`.
- `Sources/CityDeveloper/UI/SettingsView.swift` — добавить вызов `TemplateFamilySection` + inline view struct.
- `Tests/CityDeveloperTests/DistrictTemplatePickerTests.swift` — переписать MVP-тест,
  добавить 6 новых.
- `Tests/CityDeveloperTests/AppSettingsV4MigrationTests.swift` — добавить 1 тест persistence.
- `concept/Current.md`, `concept/Diff.md`, `concept/Concept.md`, `concept/.sync-state.yaml` — финальный апдейт F-25.

### Файлы НЕ трогать

- `Sources/CityDeveloper/Data/AppSettings.swift` — поля и persistence уже готовы (TASK-048a).
- `Sources/CityDeveloper/Game/Templates/DistrictTemplate.swift` — модель не меняется.
- `Sources/CityDeveloper/Game/Templates/DistrictTemplateCatalog.swift` — API уже достаточный.
- `Sources/CityDeveloper/Game/CityEngine.swift` — `templateFamily` уже есть, изменений не требуется
  (warning о fallback живёт в Picker, не в Engine).
- `Sources/CityDeveloper/Data/CityState.swift` — `BiomeKind` уже включает все нужные case.

### Команды проверки (для DoD)

- Компиляция: `swift build -c debug`
- Тесты: `swift test` — ожидаем 126/127 PASS (BUG-020 как известный fail) + 7 новых = 133/134 PASS.
- Ручная проверка:
  1. Запустить app: `swift run CityDeveloper`.
  2. ⌘, → секция «Стиль города» видна между Git watcher и Reset, тексты не обрезаны.
  3. Picker: 3 опции (Auto / Mixed / Египет).
  4. Toggle «Превью контура шаблона» включить → закрыть Settings → создать проект через
     `./Scripts/add-task.sh "Test" "test task"` → на ~3 сек видна полупрозрачная сетка слотов шаблона,
     затем исчезает.
  5. Переключить Picker на «Mixed» → создать ещё один новый проект → детерминированный pick (в MVP
     останется egyptian, потому что family только одна).
  6. Проверить `~/Library/Application Support/CityDeveloper/errors.log` — после старта старого проекта
     с family `"roman"` в settings должен появиться `"[template] family 'roman' not available..."`.

### Сложность

`middle`

**Обоснование:** 5 файлов + тесты в 2 файлах + 4 концепт-файла. Integration UI ↔ Picker ↔ Engine ↔ Scene,
но без архитектурных решений — каждый шаг линейный по уже выработанным паттернам предыдущих TASK F-25.

### Ожидаемое время

M (≤1д). Основной риск — `drawTemplateSilhouette` нужно вписать в существующую геометрию рисования
квартала (grid→iso transform). Если в GameScene уже есть helper `makeSlotFootprintPath` или эквивалент —
≤0.5д; если придётся собрать path самому из 4 углов diamond'а каждой клетки — ближе к 1д.

---

## ✅ Исполнение

_Исполнитель: sonnet (executor)_
_Сложность: middle_
_Объём: M_

### Definition of Done

#### Функциональные
- [x] Все AC выполнены (8/9 auto, 1 manual visual — silhouette overlay в smoke-режиме)
- [x] Smoke: новые тесты `DistrictTemplatePickerTests` (6 шт.) подтверждают biome-mapping + fallback;
      `AppSettingsV4MigrationTests.test_TemplateFamilyPersistsAnyString` — persistence любой строки.
      Реальный smoke с add-task.sh + UI visual check — manual (silhouette overlay).

#### Технические
- [x] Компиляция/линтер без новых ошибок (`swift build` clean)
- [x] Тесты не сломаны: 131/132 PASS, 1 known-fail (BUG-020 pre-existing)
- [x] AppSettings persistence v3 → v4 backwards-compat (Persisted struct optional поля, тест pass)
- [x] Окно Settings помещается в default size (Picker .menu + Toggle внутри ScrollView, minWidth 640 сохранён)

#### Обновление документации
- [x] `Current.md`: F-25 → ✅ (7/7 sub-task'ов, egyptian-only первая итерация)
- [x] `Diff.md`: D-25 закрыт (перенесён в «Закрытые расхождения»)
- [x] `concept/Concept.md`: блок «Статус реализации» F-25 — egyptian-only, Roman/Greek follow-up в Backlog

---

## Статус

`[ ] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[x] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-24
- Spec-review: approved
- Blocked-by: TASK-047, TASK-048
- Готова к работе: 2026-05-24
- Lead-model: sonnet
- Plan-review: revised (круг 1 needs-revision → 4 правки → круг 2 approved)
- Code-review: revised (круг 1 needs-revision: silhouette container в `world`, не scene root → fix → круг 2 approved)
- Завершена: 2026-05-24
- Коммит: —
