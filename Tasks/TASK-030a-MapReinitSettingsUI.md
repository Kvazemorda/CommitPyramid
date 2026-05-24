# TASK-030a: Settings «Карта мира» — seed-поле + кнопка «Сбросить карту» + confirm

## Связь
- **F-15** из Concept.md (реинициализация карты)
- **F-14** из Concept.md (Settings UI)
- **D-15** из Diff.md (часть 1/3 финального шага)
- **Родитель:** TASK-030 (split-into-030a-b-c, lead-разбор 2026-05-23)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-24_

### Что хотим

Дать игроку UI-контроль над seed карты: видимое поле с текущим seed, ввод нового
значения, кнопка «Сбросить карту» с обязательным подтверждением. Эта задача
**только UI + persistence**, без фактической реинициализации (последняя — в
TASK-030b). После 030a кнопка «Сбросить» должна логировать намерение в
errors.log и оставлять map нетронутой — это нормальный промежуточный шаг.

### Пользовательский сценарий

1. Игрок открывает Settings (⌘,) → видит новую секцию «Карта мира»
   между «GitWatcher» и «Reset & Rebuild».
2. В секции:
   - Поле «Текущий seed» с числом (read-only текст, выровнен моноширинным
     шрифтом).
   - Поле «Новый seed» — TextField с numeric validator (пустое = «случайный»).
   - Кнопка «Сбросить карту» с предупреждающим стилем (красноватая, по
     аналогии с существующими destructive actions в Reset & Rebuild секции).
   - Подпись `.font(.caption)`: «Карта пересоберётся, кварталы переразместятся.
     Лог событий сохранится.»
3. Клик на «Сбросить карту» → confirm-dialog (NSAlert или SwiftUI .alert):
   - Заголовок: «Сбросить карту мира?»
   - Текст: «Карта будет пересоздана с seed `<N>` (или случайным). Кварталы
     переразместятся на новом рельефе. Лог задач (`events.jsonl`)
     не меняется. Продолжить?»
   - Кнопки: «Сбросить» (destructive style), «Отмена» (default).
4. По «Сбросить» — записывается `appSettings.mapSeed = <validated value>`,
   persisted немедленно, и в errors.log пишется
   `[map-reinit] requested: seed=<N>` (заглушка — реальный reinit в TASK-030b).
5. Двойной клик / дребезг — кнопка дисейблится на 1.5 сек после нажатия.

### Acceptance criteria

- [ ] `AppSettings.mapSeed: UInt64` (default 0 = «случайный при первом старте»).
      Persisted v4 → v5 миграция: при загрузке версии ≤ 4 поле появляется как 0.
- [ ] Новая Section в `SettingsView`: `MapWorldSection`. Содержит:
      - Read-only Text «Текущий seed: <appSettings.mapSeed>».
      - TextField «Новый seed (пусто = случайный)» с numeric-only валидацией.
      - Button «Сбросить карту» с destructive стилем (или вторым акцентом).
      - Caption Text с предупреждением.
- [ ] Confirm-dialog появляется только при клике «Сбросить»; пользователь
      может отменить.
- [ ] При подтверждении: новый `mapSeed` сохраняется в AppSettings; в
      errors.log: `[map-reinit] requested: seed=<N>`.
- [ ] Двойной клик / повторный клик в течение 1.5 сек игнорируется (boolean
      guard в view-модели секции).
- [ ] Тест `AppSettingsMapSeedTests`:
      `testDefaultMapSeedIsZero`, `testMapSeedPersistenceRoundtrip`,
      `testV4ToV5MigrationKeepsOtherFields`.
- [ ] Тест валидации seed-ввода (если выделен в helper): пустое → nil,
      нечисловое → nil, «123» → 123 как UInt64, отрицательное / огромное → nil.

### Что НЕ делаем (границы скоупа)

- НЕ запускаем реальный reinit пайплайн — это TASK-030b.
- НЕ меняем формат `events.jsonl` / `state.json` — реинициализация без
  event-log изменений (PM-решение 2026-05-23: B+C hybrid).
- НЕ добавляем undo для reinit-намерения (confirm — единственная защита).

### Edge cases

- [ ] Поле «Новый seed» пустое → при confirm: новый случайный seed
      генерируется в момент применения (TASK-030b возьмёт `nil` и сгенерит).
      В Settings — записать sentinel `0` (= «random next time»).
- [ ] Поле содержит число больше UInt64.max → validator возвращает nil,
      кнопка дисейблится.
- [ ] Settings открыты, mapSeed уже = 42; пользователь вводит 42 и жмёт
      «Сбросить» — это валидно (тот же seed — детерминированно та же карта).
- [ ] Окно Settings слишком узкое (BUG-003/007 регресс) — секция уже
      внутри ScrollView (минимальный риск).

### Зависимости

- **Blocked-by:** —
- **Soft-blocks:** TASK-030b (нужен `appSettings.mapSeed` готовый).

### Дизайн

`SettingsView` использует существующие `GroupBox` + `Picker.menu` style.
Destructive button — `.tint(.red)` или существующий стиль из `Reset & Rebuild`
секции. Никаких новых токенов.

### Done-критерий

_Часть F-15 Done-критерия:_ «Кнопка "Сбросить карту" + подтверждение». 030a
закрывает UI-половину; функциональность (фактическая пересборка) — TASK-030b.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-24_
_Модель: sonnet_
_Статус: [x] готов_

### Анализ текущего состояния

- `AppSettings` (`Sources/CityDeveloper/Data/AppSettings.swift:1-150`) — текущий version=4 в
  `Persisted` struct (строка 114), optional поля для backwards-compat.
- `SettingsView` (`Sources/CityDeveloper/UI/SettingsView.swift`) — ScrollView + GroupBox-секции,
  `GitWatcherSection` на строке 110. Точка вставки новой секции — между `GitWatcherSection`
  и существующим блоком «Reset & Rebuild».
- `SettingsWindowController` — окно 720×600, minSize 640×480. ScrollView уже есть.
- `ErrorsLog.write(_:)` — простой API для warning.
- Persistence pattern (TASK-048a/051): добавляем поле `@Published var mapSeed: UInt64 = 0`
  в AppSettings, в Persisted — `mapSeed: UInt64?`, version=4→5, при decode дефолт 0.

**Что нужно дописать:**
1. `AppSettings.mapSeed: UInt64 = 0` + Persisted v5 + миграция.
2. Новая Section `MapWorldSection` (inline в SettingsView).
3. Numeric validator для UInt64 ввода (helper extension).
4. Confirm-dialog (NSAlert или SwiftUI .alert).
5. Тесты `AppSettingsMapSeedTests` (3 кейса) + validator-тест.

### Архитектурное решение

**Persistence:** добавляем `mapSeed` в существующий Persisted struct, version=4→5. Поле
optional (`mapSeed: UInt64?`), при загрузке версий ≤ 4 → `?? 0`. Этот паттерн уже отработан
в TASK-048a (templateFamily, previewTemplateSilhouette).

**UI:** новая inline View struct `MapWorldSection` после `GitWatcherSection`. Содержит:
- Read-only Text «Текущий seed: \(settings.mapSeed)» (monospaced).
- TextField «Новый seed» с numeric-only validator (стейт сохраняется как `@State var
  newSeedText: String = ""`).
- Button «Сбросить карту» с `.tint(.red)` + dialog confirmation.
- Caption-text с предупреждением.

**Confirm-dialog:** используем SwiftUI `.alert` через `@State var showResetConfirm: Bool`. По
confirm: `settings.mapSeed = parsedNewSeed`, ErrorsLog.write, isReinitButtonDisabled=true на
1.5 сек (через `DispatchQueue.main.asyncAfter`).

**Validator:** static func `parseMapSeed(_ text: String) -> UInt64?`:
- empty → nil (= «random next time», sentinel: записываем 0).
- numeric (digits only) → UInt64.
- overflow / non-numeric → nil.

**Reset trigger в 030a:** только запись в AppSettings + ErrorsLog. Реальная reinit-pipeline
живёт в TASK-030b. В 030a кнопка confirm пишет sentinel в ErrorsLog как заглушку.

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку.

1. **AppSettings.mapSeed + Persisted v5** `[AC:1]`
   - Файл: `Sources/CityDeveloper/Data/AppSettings.swift`
   - Добавить после строки 42 (`previewTemplateSilhouette`):
     ```swift
     /// TASK-030a F-15: seed карты мира. 0 = «случайный при первом старте/reinit».
     @Published var mapSeed: UInt64 = 0
     ```
   - В Persisted (строка 132):
     - Поднять `version: Int` константу на 5.
     - Добавить `mapSeed: UInt64?` в struct (как optional поле).
     - В save() (строка 113): `mapSeed: mapSeed`.
     - В init/load (строка 82): `self.mapSeed = decoded.mapSeed ?? 0`.

2. **MapWorldSection inline view** `[AC:2,3,4]`
   - Файл: `Sources/CityDeveloper/UI/SettingsView.swift`
   - Между `GitWatcherSection()` и блоком «Reset & Rebuild» (после строки 110) вставить:
     ```swift
     MapWorldSection(settings: settings)
     ```
   - В конец файла (рядом с `TemplateFamilySection` если есть, или в конце) добавить:
     ```swift
     private struct MapWorldSection: View {
         @ObservedObject var settings: AppSettings
         @State private var newSeedText: String = ""
         @State private var showResetConfirm: Bool = false
         @State private var isResetDisabled: Bool = false

         var body: some View {
             GroupBox(label: Label("Карта мира", systemImage: "map")) {
                 VStack(alignment: .leading, spacing: 8) {
                     Text("Текущий seed: \(settings.mapSeed)")
                         .font(.system(.body, design: .monospaced))
                     HStack {
                         TextField("Новый seed (пусто = случайный)", text: $newSeedText)
                             .textFieldStyle(.roundedBorder)
                         Button("Сбросить карту") {
                             showResetConfirm = true
                         }
                         .tint(.red)
                         .disabled(isResetDisabled || !isValidSeedInput)
                     }
                     Text("Карта пересоберётся, кварталы переразместятся. Лог событий сохранится.")
                         .font(.caption)
                         .foregroundColor(.secondary)
                 }
                 .padding(.vertical, 4)
             }
             .alert("Сбросить карту мира?", isPresented: $showResetConfirm) {
                 Button("Сбросить", role: .destructive) {
                     applyReset()
                 }
                 Button("Отмена", role: .cancel) {}
             } message: {
                 Text("Карта будет пересоздана с seed \(displaySeed). Кварталы переразместятся. Лог задач не меняется. Продолжить?")
             }
         }

         private var displaySeed: String {
             let parsed = MapSeedValidator.parse(newSeedText)
             if parsed == nil && !newSeedText.isEmpty { return "?" }
             return parsed.map(String.init) ?? "случайным"
         }

         private var isValidSeedInput: Bool {
             newSeedText.isEmpty || MapSeedValidator.parse(newSeedText) != nil
         }

         private func applyReset() {
             let newSeed = MapSeedValidator.parse(newSeedText) ?? 0
             settings.mapSeed = newSeed
             settings.save()
             ErrorsLog.write("[map-reinit] requested: seed=\(newSeed)")
             newSeedText = ""
             isResetDisabled = true
             DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                 isResetDisabled = false
             }
         }
     }
     ```

3. **MapSeedValidator helper** `[AC:5]`
   - Файл (новый или в конце AppSettings.swift): `Sources/CityDeveloper/Data/MapSeedValidator.swift`
     либо в `SettingsView.swift` как private enum.
   - Скелет:
     ```swift
     /// TASK-030a: парсер пользовательского ввода в seed карты.
     /// nil → «случайный» (для UI). 0-sentinel записывается в AppSettings.
     enum MapSeedValidator {
         static func parse(_ text: String) -> UInt64? {
             let trimmed = text.trimmingCharacters(in: .whitespaces)
             guard !trimmed.isEmpty else { return nil }
             // Только цифры.
             guard trimmed.allSatisfy(\.isNumber) else { return nil }
             return UInt64(trimmed)  // overflow → nil автоматически
         }
     }
     ```

4. **Тесты** `[AC:6,7]`
   - Файл (новый): `Tests/CityDeveloperTests/AppSettingsMapSeedTests.swift`
   - Тесты:
     ```swift
     final class AppSettingsMapSeedTests: XCTestCase {
         func testDefaultMapSeedIsZero() {
             let suite = "AppSettings.test_default_mapseed"
             let defaults = UserDefaults(suiteName: suite)!
             defaults.removePersistentDomain(forName: suite)
             let s = AppSettings(userDefaults: defaults)
             XCTAssertEqual(s.mapSeed, 0)
         }

         func testMapSeedPersistenceRoundtrip() {
             let suite = "AppSettings.test_persist_mapseed"
             let defaults = UserDefaults(suiteName: suite)!
             defaults.removePersistentDomain(forName: suite)
             let a = AppSettings(userDefaults: defaults)
             a.mapSeed = 12345
             a.save()
             let b = AppSettings(userDefaults: defaults)
             XCTAssertEqual(b.mapSeed, 12345)
         }

         func testV4ToV5MigrationKeepsOtherFields() {
             // Записать «v4» JSON вручную и проверить, что v5 load даёт mapSeed=0
             // и другие поля сохраняются.
             // Конкретный JSON-литерал для v4 — посмотреть формат Persisted.
             // ...
         }
     }
     ```
   - Файл (новый): `Tests/CityDeveloperTests/MapSeedValidatorTests.swift`
     ```swift
     final class MapSeedValidatorTests: XCTestCase {
         func testEmptyReturnsNil()        { XCTAssertNil(MapSeedValidator.parse("")) }
         func testWhitespaceReturnsNil()   { XCTAssertNil(MapSeedValidator.parse("   ")) }
         func testNumericReturnsValue()    { XCTAssertEqual(MapSeedValidator.parse("123"), 123) }
         func testAlphabeticReturnsNil()   { XCTAssertNil(MapSeedValidator.parse("abc")) }
         func testMixedReturnsNil()        { XCTAssertNil(MapSeedValidator.parse("12a3")) }
         func testHugeOverflowReturnsNil() {
             // UInt64.max + 1 - 1 округляется; явный overflow:
             XCTAssertNil(MapSeedValidator.parse("99999999999999999999999"))
         }
         func testNegativeReturnsNil()     { XCTAssertNil(MapSeedValidator.parse("-1")) }
     }
     ```

5. **Manual smoke** `[AC:2,3,4]`
   - Запустить app: `swift run CityDeveloper`.
   - Открыть Settings (⌘,) → видна секция «Карта мира» между Git и Reset.
   - Ввести seed=42 → жмём «Сбросить карту» → alert «Сбросить?» с «Карта будет пересоздана
     с seed 42...».
   - По «Сбросить» → видим в `~/Library/Application Support/CityDeveloper/errors.log`:
     `[map-reinit] requested: seed=42`.
   - Двойной клик на «Сбросить» → второй клик игнорируется (1.5 сек disabled).
   - Перезапуск app → текущий seed = 42 в read-only Text.

### Edge cases (явно обработать)

- [ ] Пустое поле новый seed + confirm → `parse("") == nil` → `applyReset` записывает 0
      (sentinel «случайный»). ErrorsLog: `[map-reinit] requested: seed=0`. TASK-030b
      должен интерпретировать 0 как «новый случайный».
- [ ] `UInt64.max` (18446744073709551615) — валиден. `UInt64.max + 1` — overflow → nil.
- [ ] При сохранении/загрузке v5 → v3 → v5 (откат к старой версии) — Persisted v3 не имеет
      `mapSeed`. Load v3 fallback → mapSeed = 0 (default). Корректно.
- [ ] Settings окно слишком узкое — текст «Карта пересоберётся...» обёрнут в caption,
      переносится. TextField не растягивается за HStack. Регресс BUG-003/007 не должен
      возникнуть, проверить manual.
- [ ] Reset button disabled while isResetDisabled=true — анимация состояния (1.5 сек) проходит
      на main queue. Не блокирует UI.

### Файлы для изменения

- `Sources/CityDeveloper/Data/AppSettings.swift` — `@Published var mapSeed` + Persisted v5.
- `Sources/CityDeveloper/UI/SettingsView.swift` — call MapWorldSection + inline struct.
- `Sources/CityDeveloper/Data/MapSeedValidator.swift` (НОВЫЙ) — validator helper.
- `Tests/CityDeveloperTests/AppSettingsMapSeedTests.swift` (НОВЫЙ, 3 теста).
- `Tests/CityDeveloperTests/MapSeedValidatorTests.swift` (НОВЫЙ, 7 тестов).

### Файлы НЕ трогать

- `Sources/CityDeveloper/Game/CityEngine.swift` — реальный reinit pipeline — TASK-030b.
- `Sources/CityDeveloper/World/WorldMapStore.swift` — regeneration — TASK-030b.
- `Sources/CityDeveloper/Game/GameScene.swift` — teardown/rebuild — TASK-030b.

### Команды проверки

- Компиляция: `swift build -c debug`
- Тесты: `swift test --filter "AppSettingsMapSeedTests|MapSeedValidatorTests"`
- Полный suite: `swift test 2>&1 | grep "Executed"`
- Smoke: см. шаг 5.

### Сложность

`junior`

**Обоснование:** AppSettings persistence — паттерн из TASK-048a (v3→v4); SwiftUI inline-section
+ alert — паттерн из TASK-051; validator — pure-функция. Нет архитектурных решений.

### Ожидаемое время

S (≤2ч, фактически 1ч включая smoke).

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: junior_
_Объём: S_

### Definition of Done

#### Функциональные
- [x] Все AC выполнены (7/7 auto-verified)
- [x] Smoke: 12/12 новых тестов pass (3 AppSettingsMapSeedTests + 9 MapSeedValidatorTests)

#### Технические
- [x] Компиляция/линтер без новых ошибок (`swift build` clean)
- [x] AppSettings v4 → v5 backwards-compat (`testV4ToV5MigrationDefaultsMapSeedToZero` pass)
- [x] Окно Settings помещается в default size (TextField + Button + caption в ScrollView)

#### Обновление документации
- [x] `Current.md`: упомянуто в прогоне 2026-05-24 часть 8
- [x] `Diff.md`: D-15 отмечен «Settings UI ✅, оркестратор и migrator открыты»

---

## Статус

`[ ] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[x] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-24
- Spec-review: derived-from-split (TASK-030 lead-analysis 2026-05-23)
- Готова к работе: 2026-05-24
- Lead-model: sonnet
- Plan-review: skipped (junior + AppSettings/SettingsView паттерн уже отработан в TASK-048a/051)
- Исполнитель: haiku
- Code-review: approved (sonnet, minor isResetDisabled timer note — not blocker)
- Завершена: 2026-05-24
- Коммит: 8839dd3
