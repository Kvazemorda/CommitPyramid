# TASK-015: Фильтр журнала по типу события

## Связь
- **F-11** Инспектор / журнал событий (остаток после TASK-007/016)
- **F-03** Event sourcing (источник событий)
- **D-11** (закрывает финальный остаток)
- **Приоритет:** P2
- **Blocked-by:** **TASK-024** (запись `unit_built`/`stage_up` в `events.jsonl`).
  Без TASK-024 фильтр имеет смысл только для `task_completed` +
  `decay_tick/fire/restore`, что делает его половинчатым.

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22 (пересоздана после `[split-needed]`; запись событий вынесена в TASK-024)_

### Что хотим

Добавить Picker «Тип события» в floating-окно журнала
(`JournalWindowController` → `SidePanelView`) — выбор одного или нескольких типов
событий для отображения в журнале. Сейчас `filteredEvents` хардкодит
`e.kind == .taskCompleted` (`UI/SidePanelView.swift:61`) — это нужно заменить
на проверку по выбранному фильтру.

После закрытия TASK-024 в `events.jsonl` будут все 7 типов из `GameEvent.Kind`:
`task_completed`, `unit_built`, `stage_up`, `decay_tick`, `fire`, `restore`,
`ruins_cleared`. Юзер сможет смотреть, например, только «декей-историю» или
только «stage-up'ы».

### Пользовательский сценарий

1. Юзер открывает журнал (кнопка `list.bullet`).
2. Сверху над списком событий — Picker «Тип события» рядом с уже существующими
   фильтрами (Проект, Дата с / по).
3. По умолчанию — «Все типы». Можно выбрать «Только закрытые задачи»,
   «Только апгрейды стадии», «Только decay-события» или «Кастом…» (multi-select).
4. Выбор фильтра моментально пересчитывает `filteredEvents`. Дата+проект+тип
   комбинируются по `AND`.
5. Состояние фильтра живёт в `ContentView` через `@State` и пробрасывается
   через `@Binding` (как `selectedProject`, `dateFrom/To`, `didInitDates`).
   Закрытие/повторное открытие окна не сбрасывает выбор.

### Acceptance criteria

- [ ] **Модель фильтра:** новый тип
      `enum JournalKindFilter: Equatable { case all; case some(Set<GameEvent.Kind>) }`
      в `UI/SidePanelView.swift` (или отдельный файл — на усмотрение лида).
- [ ] **Binding пробрасывается** через `JournalWindowController.show(...)` →
      `SidePanelView`. Хранилище — `@State var journalKindFilter:
      JournalKindFilter = .all` в `ContentView`. Дефолт — `.all`.
- [ ] **UI Picker:** SwiftUI `Picker` или `Menu` со строками:
      - `Все типы` → `.all`
      - `Закрытые задачи` → `.some([.taskCompleted])`
      - `Постройки юнитов` → `.some([.unitBuilt])`
      - `Апгрейды стадии` → `.some([.stageUp])`
      - `Decay-события` → `.some([.decayTick, .fire, .restore, .ruinsCleared])`
      - `Кастом…` → открывает popover с чекбоксами на все 7 типов
      
      Стиль — 11–12pt caption, под/рядом с Picker «Проект». Лейбл «Тип:»
      11pt `paletteInkDark.opacity(0.7)`.
- [ ] **Popover «Кастом»:** список с 7 строк-чекбоксов. Кнопки «Все» и
      «Сбросить» сверху. Закрытие popover'а сохраняет выбор через Binding.
      Пустой набор → ничего не показывает (показать заглушку «Тип не выбран»).
- [ ] **Логика `filteredEvents`:** заменить хардкод
      `guard e.kind == .taskCompleted` на:
      ```swift
      switch journalKindFilter {
      case .all: break
      case .some(let kinds): guard kinds.contains(e.kind) else { return false }
      }
      ```
- [ ] **Заглушка пустого фильтра:** если `journalKindFilter == .some(∅)` —
      строка «Тип не выбран» (стиль аналогичен «Нет событий в выбранном диапазоне»).
- [ ] **Иконки/префиксы в `JournalRow` (опц., не блокирует приёмку):** в строке
      события рядом с проектом показывать иконку kind'а:
      - `task_completed` — `checkmark.circle`
      - `unit_built` — `building.2`
      - `stage_up` — `arrow.up.square`
      - `decay_tick` — `clock.arrow.circlepath`
      - `fire` — `flame`
      - `restore` — `arrow.uturn.up`
      - `ruins_cleared` — `trash.slash`
      
      Иконка 11pt, цвет `paletteInkDark.opacity(0.6)`. Это улучшает UX при
      смешанном выводе.
- [ ] **Persistence (опц.):** сохранение выбора в `AppSettings` — *не делаем*
      в этой задаче. Состояние живёт только в `@State` контейнере.

### Что НЕ делаем

- Не пишем сами события — это TASK-024.
- Не вводим persistence фильтра (UserDefaults) — состояние только in-memory.
- Не вводим фильтры по `source` (jsonl/notes/git/journal/system) — это
  отдельный enhancement в Backlog.
- Не реализуем поиск по `title` — отдельная фича.
- Не локализуем кроме рус. строк, перечисленных в AC.
- Не меняем формат `JournalRow` (если не делаем опциональные иконки —
  оставляем как есть).

### Edge cases

- [ ] **`.some(∅)`** (юзер снял все галочки в popover'е): показывать
      «Тип не выбран», `filteredEvents` пустой.
- [ ] **`.all` + пустой `engine.events`:** ничего нового — текущая заглушка
      «Событий пока нет» отрабатывает.
- [ ] **Фильтр + диапазон дат пуст** (`dateFrom > dateTo`): «Диапазон пуст»
      приоритетнее «Тип не выбран» (фильтр дат проверяется первым в
      существующей логике — так и оставляем).
- [ ] **Старый формат `events.jsonl`** (до TASK-024, без `unit_built/stage_up`):
      все 7 типов отображаются в Picker'е, но в логе их физически нет — выбор
      «Апгрейды стадии» даёт пустой результат. Поведение корректное.
- [ ] **Двойной выбор пресета и кастома:** Picker и popover ведут один и тот
      же binding — выбор пресета перезаписывает кастом и наоборот. Конфликта
      нет.
- [ ] **Сортировка после фильтрации:** сохранить текущую сортировку по
      `event.ts` (descending). Фильтр применяется до сортировки, как и сейчас.

### Зависимости

- **TASK-024** (запись `unit_built`/`stage_up`) — **pre-condition**. Без неё
  3 из 7 типов будут «мёртвыми» в Picker'е.
- **F-09** Decay — закрыт, `decay_tick/fire/restore` уже пишутся.
- **F-11** TASK-007/016 — закрыты. Журнал работает в отдельном окне.

### Дизайн

- **Layout фильтров** в шапке журнала (сверху вниз):
  1. `Picker «Проект»` (есть).
  2. Новый `Picker «Тип:»`.
  3. `DatePicker «c / по»` (есть).
- Высота шапки увеличится на ~28pt — допустимо.
- **Стиль Picker'а:** `.menu`-стиль (SwiftUI default для macOS). Ширина ≥120pt,
  чтобы влез самый длинный пресет «Постройки юнитов».
- **Popover «Кастом»:** parchment background, padding `padM`, чекбоксы 12pt.

### Done-критерий

> В журнале (floating-окно) есть фильтр «Тип события» с пресетами и кастомным
> multi-select. Выбор фильтра моментально сужает список событий. Все 7 типов из
> `GameEvent.Kind` доступны для фильтрации. Состояние фильтра переживает
> закрытие/открытие окна.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-22_
_Модель: opus (override; sonnet-default — пользователь явно «no-pause» режим)_
_Статус: [x] готов_

### Анализ текущего состояния

**В коде уже есть:**
- `Sources/CityDeveloper/UI/SidePanelView.swift`:
  - `filteredEvents` (стр. 56–70) — текущая фильтрация: хардкод `guard e.kind == .taskCompleted` (стр. 61), затем фильтр по `selectedProject` и `dateFrom/dateTo`. Сортировка `$0.ts > $1.ts` (desc).
  - Picker «Проект» (стр. 188–196), DatePicker «с/по» (стр. 198–220) — паттерн `Binding<…> + .pickerStyle(.menu) + 11pt label + paletteInkDark.opacity(0.7)`.
  - Журнал-блок (стр. 224–256): заглушки `"Событий пока нет"` / `"Диапазон пуст"` / `"Нет событий в выбранном диапазоне"`. `LazyVStack` с `ForEach(filteredEvents)`.
  - `JournalRow` (стр. 317–341, **private struct**): HStack `time | project | title`. 11pt, monospaced для времени.
  - Сигнатура `SidePanelView` (стр. 4–13): `@ObservedObject engine`, `@ObservedObject bridge`, `@Binding collapsed/selectedProject/dateFrom/dateTo/didInitDates`.
- `Sources/CityDeveloper/UI/ContentView.swift` (стр. 12–16): `@State` для всех 5 биндингов, проброс в `journalController.show(...)` (стр. 35–43).
- `Sources/CityDeveloper/App/JournalWindowController.swift` (стр. 15–21): `func show(engine:bridge:collapsed:selectedProject:dateFrom:dateTo:didInitDates:)` — нужно расширить сигнатуру.
- `Sources/CityDeveloper/Data/GameEvent.swift` — `enum Kind: String, Codable` с 7 case'ами: `taskCompleted`, `unitBuilt`, `stageUp`, `decayTick`, `fire`, `restore`, `ruinsCleared`. ✅ Identifiable через `let id: UUID`.
- `Sources/CityDeveloper/Theme/Palette.swift` — `paletteInkDark` подтверждён ранее.

**Зависимость TASK-024:** События `unit_built/stage_up` сейчас в `events.jsonl` не пишутся. После закрытия TASK-024 они начнут появляться. Lead-план TASK-024 готов; **порядок исполнения: 024 → 015**, иначе фильтр будет видеть только 4 из 7 типов в реальном логе (Picker всё равно покажет все 7 — просто пресеты `unit_built`/`stage_up` дадут пустоту до закрытия 024). План для 015 не блокируется фактом исполнения 024 — мы пишем код, который **готов** к 7 типам.

**Что переиспользуем:** существующий `Picker` стиль, `filteredEvents` логику, `JournalRow` рендер, паттерн `@State` в `ContentView` + `@Binding` через `JournalWindowController.show(...)`.

**Что нужно дописать:** `JournalKindFilter` тип + pure-функцию `JournalFilter.apply(...)` (для тестируемости), новый Picker «Тип» в журнал-блоке, popover «Кастом» с 7 чекбоксами, заглушку «Тип не выбран», опциональные иконки в `JournalRow`, проброс `Binding<JournalKindFilter>` через 3 слоя, тест с 7 пресетами.

### Архитектурное решение

**Pure-функция фильтрации.** Текущий `filteredEvents` — computed property внутри View, протестировать в изоляции сложно. Выносим логику в `enum JournalFilter { static func apply(...) -> [GameEvent] }` (или free function в новом файле `JournalKindFilter.swift`). Это закрывает AC «юнит-тест для каждого пресета» (DoD) без необходимости моков SwiftUI. `filteredEvents` в `SidePanelView` становится тонкой обёрткой над `JournalFilter.apply(...)`.

**`JournalKindFilter`** — отдельный `enum` в новом файле `Sources/CityDeveloper/UI/JournalKindFilter.swift`. Туда же кладём pure-функцию фильтрации и presets, чтобы тесты могли импортировать одну единицу. `Equatable` синтезируется автоматически (Set<GameEvent.Kind> уже Hashable через String raw value).

**UI расположение.** PM-дизайн: «Picker «Тип:» рядом с Picker «Проект»». Кладём **между** ними — порядок (1) Проект, (2) Тип, (3) Даты. Лейбл «Тип:» 11pt `paletteInkDark.opacity(0.7)` — копия стиля «с»/«по» (`SidePanelView.swift:199-201`).

**Picker как `Menu` с пресетами + «Кастом…»**. SwiftUI `Picker` с тегами требует чёткого Equatable-выбора; для switch между пресетами и кастомом удобнее `Menu` со списком `Button`-пунктов: каждый пресет — `Button` с `.tag` или `action`, последний пункт «Кастом…» открывает popover. Это даёт чистый UI без необходимости держать «промежуточный» selectedPreset enum.

**Popover «Кастом».** Контролируется `@State private var showCustomPopover: Bool` в `SidePanelView`. Содержимое — VStack с двумя кнопками («Все» / «Сбросить») и `ForEach(GameEvent.Kind.allCases, ...)` чекбоксами через `Toggle`. Чтобы `GameEvent.Kind` имел `.allCases`, добавляем `CaseIterable` к `enum Kind` (это безопасно — `enum` без ассоциированных значений). Запись текущего multi-select в `journalKindFilter: Binding<JournalKindFilter>` — двусторонняя: открываем popover на текущем `.some(Set)` (если был пресет — превращаем в Set; если `.all` — пустой Set).

**Иконки в `JournalRow`.** PM явно отмечает «не блокирует приёмку». Включаем — это малозатратная улучшение UX, особенно полезное при mixed-фильтре. SF Symbols, 11pt, в начале строки перед временем. `GameEvent.Kind`-extension `var iconName: String` рядом с `JournalKindFilter`.

**Заглушка «Тип не выбран».** Добавляется как новая ветка в существующий if/else в журнал-блоке (`SidePanelView.swift:225-256`). Приоритет ниже «Диапазон пуст» (PM: «Фильтр + диапазон дат пуст: "Диапазон пуст" приоритетнее»). Условие: `case .some(let kinds) = journalKindFilter, kinds.isEmpty`.

**Persistence — не делаем** (PM явно). State живёт в `ContentView.@State` как остальные фильтры.

**Тесты.** В тот же `Tests/CityDeveloperTests/` (создаётся TASK-014 / TASK-024). Файл `JournalFilterTests.swift` — фабрика из 7 событий по одному каждого kind'а, перебираем 4 пресета + `.all` + два кастом-варианта + проверка комбинаций project+date.

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку. Шаги 1–2 безопасны для промежуточной сборки. Шаги 3–7 меняют сигнатуры — между ними `swift build` упадёт, выполняй подряд.

0. **Pre-check: `.testTarget` в `Package.swift`** `[AC:8]`
   - Файл: `Package.swift`
   - Что проверить: открыть, найти `.testTarget(name: "CityDeveloperTests", …)`. Если **отсутствует** (TASK-014 и TASK-024 ещё не закрыты) — добавить idempotent:
     ```swift
     targets: [
         .executableTarget(name: "CityDeveloper", path: "Sources/CityDeveloper"),
         .testTarget(
             name: "CityDeveloperTests",
             dependencies: ["CityDeveloper"],
             path: "Tests/CityDeveloperTests"
         )
     ]
     ```
     и `mkdir -p Tests/CityDeveloperTests` из корня репозитория.
   - Если **присутствует** — пропустить.
   - Если этот шаг выпал — `swift test` в шаге 8 завалится с "no such module CityDeveloperTests".

1. **Сделать `GameEvent.Kind: CaseIterable`** `[AC:3]`
   - Файл: `Sources/CityDeveloper/Data/GameEvent.swift`
   - Блок: объявление `enum Kind: String, Codable` (стр. 5).
   - Что меняем: добавить `CaseIterable`:
     ```swift
     enum Kind: String, Codable, CaseIterable {
     ```
   - Никаких других изменений в файле. Безопасно: `enum` без ассоциированных значений, синтез автоматический.

2. **Новый файл `JournalKindFilter.swift`** `[AC:1,5]`
   - Файл: новый — `Sources/CityDeveloper/UI/JournalKindFilter.swift`.
   - Что создаём: тип фильтра, presets, иконки kind'ов и pure-функция фильтрации.
     ```swift
     import Foundation

     /// Фильтр по типу события в журнале (TASK-015).
     enum JournalKindFilter: Equatable {
         case all
         case some(Set<GameEvent.Kind>)
     }

     extension JournalKindFilter {
         /// Применяет фильтр к одному событию. true = пропустить, false = отбросить.
         func passes(_ event: GameEvent) -> Bool {
             switch self {
             case .all: return true
             case .some(let kinds): return kinds.contains(event.kind)
             }
         }

         /// Пустой `.some(∅)` — особое состояние «ничего не выбрано».
         var isEmptySelection: Bool {
             if case .some(let kinds) = self, kinds.isEmpty { return true }
             return false
         }
     }

     /// Иконки SF Symbols для каждого kind'а (используется в JournalRow).
     extension GameEvent.Kind {
         var iconName: String {
             switch self {
             case .taskCompleted: return "checkmark.circle"
             case .unitBuilt:     return "building.2"
             case .stageUp:       return "arrow.up.square"
             case .decayTick:     return "clock.arrow.circlepath"
             case .fire:          return "flame"
             case .restore:       return "arrow.uturn.up"
             case .ruinsCleared:  return "trash.slash"
             }
         }

         /// Человекочитаемое название для popover «Кастом» и пресетов.
         var displayName: String {
             switch self {
             case .taskCompleted: return "Закрытие задачи"
             case .unitBuilt:     return "Постройка юнита"
             case .stageUp:       return "Апгрейд стадии"
             case .decayTick:     return "Decay-тик"
             case .fire:          return "Пожар"
             case .restore:       return "Восстановление"
             case .ruinsCleared:  return "Снос руин"
             }
         }
     }

     /// Pure-функция фильтрации журнала. Вынесена сюда для юнит-тестируемости
     /// без зависимости от SwiftUI / engine.
     enum JournalFilter {
         static func apply(
             events: [GameEvent],
             projectId: String?,
             dateFrom: Date,
             dateTo: Date,
             kindFilter: JournalKindFilter
         ) -> [GameEvent] {
             // Edge: пустой `.some(∅)` → отбрасываем всё.
             if kindFilter.isEmptySelection { return [] }
             let dateRangeValid = dateFrom <= dateTo
             return events
                 .sorted { $0.ts > $1.ts }
                 .filter { e in
                     guard kindFilter.passes(e) else { return false }
                     if let sel = projectId, !sel.isEmpty {
                         guard e.project == sel else { return false }
                     }
                     if dateRangeValid {
                         guard e.ts >= dateFrom && e.ts <= dateTo.endOfDay else { return false }
                     }
                     return true
                 }
         }
     }
     ```
   - Файл self-contained, не меняет существующие. После шага 2 проект всё ещё компилируется.

3. **Расширить `SidePanelView`: `@Binding journalKindFilter` + новый Picker + popover** `[AC:2,3,4,6]`
   - Файл: `Sources/CityDeveloper/UI/SidePanelView.swift`
   - Блок: сигнатура (стр. 3–13).
   - Что меняем (3 части):

     **3.1.** Добавить `@Binding` в конец списка биндингов (после `didInitDates`):
     ```swift
     @Binding var journalKindFilter: JournalKindFilter
     ```

     **3.2.** Добавить `@State` для popover'а **внутри** структуры (рядом с `@Binding`):
     ```swift
     @State private var showCustomPopover: Bool = false
     ```

     **3.3.** В `journalSection` (стр. 178–258) внутри блока «Filters» (стр. 187–222) **между** `Picker «Проект»` (стр. 188–196) и `HStack «с/по»` (стр. 198–220) вставить:
     ```swift
     HStack(spacing: 6) {
         Text("Тип:")
             .font(.system(size: 11))
             .foregroundColor(.paletteInkDark.opacity(0.7))

         Menu {
             Button("Все типы") {
                 journalKindFilter = .all
             }
             Button("Закрытие задачи") {
                 journalKindFilter = .some([.taskCompleted])
             }
             Button("Постройки юнитов") {
                 journalKindFilter = .some([.unitBuilt])
             }
             Button("Апгрейды стадии") {
                 journalKindFilter = .some([.stageUp])
             }
             Button("Decay-события") {
                 journalKindFilter = .some([.decayTick, .fire, .restore, .ruinsCleared])
             }
         } label: {
             Text(currentFilterLabel)
                 .font(.system(size: 11))
                 .frame(minWidth: 120, alignment: .leading)
         }
         .menuStyle(.borderlessButton)
         .disabled(isEmpty)

         // Отдельная кнопка "Кастом…" — popover привязан к ней, а не к Menu.
         // На macOS Menu закрывает себя при выборе, и popover на самом Menu
         // получает нестабильный anchor.
         Button {
             showCustomPopover = true
         } label: {
             Image(systemName: "slider.horizontal.3")
                 .font(.system(size: 11))
                 .foregroundColor(.paletteInkDark.opacity(0.7))
         }
         .buttonStyle(.plain)
         .disabled(isEmpty)
         .popover(isPresented: $showCustomPopover, arrowEdge: .bottom) {
             customFilterPopover
         }
     }
     .padding(.horizontal, 16)
     ```

     **3.4.** Добавить computed/helper в `SidePanelView` (рядом с другими `private var`'ами):
     ```swift
     private var currentFilterLabel: String {
         switch journalKindFilter {
         case .all: return "Все типы"
         case .some(let kinds):
             if kinds.isEmpty { return "Не выбрано" }
             // Все 7 типов выбраны вручную через popover — семантически = "Все типы".
             if kinds.count == GameEvent.Kind.allCases.count { return "Все типы" }
             if kinds.count == 1, let k = kinds.first { return k.displayName }
             return "Кастом (\(kinds.count))"
         }
     }

     private var customFilterPopover: some View {
         VStack(alignment: .leading, spacing: 6) {
             HStack {
                 Button("Все") {
                     // Используем .all, чтобы UI и логика были консистентны:
                     // currentFilterLabel → "Все типы", filter passes всё.
                     journalKindFilter = .all
                 }
                 .buttonStyle(.link)
                 Button("Сбросить") {
                     journalKindFilter = .some([])
                 }
                 .buttonStyle(.link)
             }
             Divider()
             ForEach(GameEvent.Kind.allCases, id: \.self) { kind in
                 Toggle(kind.displayName, isOn: Binding(
                     get: {
                         switch journalKindFilter {
                         case .all: return true
                         case .some(let kinds): return kinds.contains(kind)
                         }
                     },
                     set: { newVal in
                         // Если был .all и юзер снимает галку — стартуем с полного набора минус этот.
                         var current: Set<GameEvent.Kind>
                         switch journalKindFilter {
                         case .all: current = Set(GameEvent.Kind.allCases)
                         case .some(let kinds): current = kinds
                         }
                         if newVal { current.insert(kind) } else { current.remove(kind) }
                         journalKindFilter = .some(current)
                     }
                 ))
                 .font(.system(size: 12))
             }
         }
         .padding(12)
         .frame(width: 220)
     }
     ```

4. **Заменить `filteredEvents` на pure-вызов + новая заглушка** `[AC:5,6]`
   - Файл: `Sources/CityDeveloper/UI/SidePanelView.swift`
   - Блок: `filteredEvents` (стр. 56–70).
   - Что меняем — заменить целиком на:
     ```swift
     private var filteredEvents: [GameEvent] {
         JournalFilter.apply(
             events: engine.events,
             projectId: selectedProject,
             dateFrom: dateFrom,
             dateTo: dateTo,
             kindFilter: journalKindFilter
         )
     }
     ```
   - В if/else журнал-блока (стр. 225–256) добавить **новую** ветку **между** «Диапазон пуст» (стр. 230–234) и `filteredEvents.isEmpty` (стр. 235–239):
     ```swift
     } else if journalKindFilter.isEmptySelection {
         Text("Тип не выбран")
             .font(.system(size: 11))
             .foregroundColor(.paletteInkDark.opacity(0.5))
             .padding(.horizontal, 16)
     ```
   - Полный порядок ветвей: `isEmpty` → `dateFrom > dateTo` → `isEmptySelection` → `filteredEvents.isEmpty` → рендер.

5. **Иконки в `JournalRow`** `[AC:7]`
   - Файл: `Sources/CityDeveloper/UI/SidePanelView.swift`
   - Блок: `private struct JournalRow` (стр. 317–341).
   - Что меняем: добавить SF Symbol в начале HStack:
     ```swift
     var body: some View {
         HStack(alignment: .top, spacing: 8) {
             Image(systemName: event.kind.iconName)
                 .font(.system(size: 11))
                 .foregroundColor(.paletteInkDark.opacity(0.6))
                 .frame(width: 14, alignment: .center)

             Text(formatter.string(from: event.ts))
                 .font(.system(size: 11, design: .monospaced))
                 .foregroundColor(.paletteInkDark.opacity(0.6))
                 .fixedSize()
             // ... остальное без изменений
         }
     ```

6. **`@State` в `ContentView`** `[AC:2]`
   - Файл: `Sources/CityDeveloper/UI/ContentView.swift`
   - Блок: `@State` свойства (стр. 12–16).
   - Что меняем: добавить:
     ```swift
     @State private var journalKindFilter: JournalKindFilter = .all
     ```
   - В вызове `journalController.show(...)` (стр. 35–43) добавить аргумент:
     ```swift
     journalController.show(
         engine: engine,
         bridge: bridge,
         collapsed: $collapsed,
         selectedProject: $selectedProject,
         dateFrom: $dateFrom,
         dateTo: $dateTo,
         didInitDates: $didInitDates,
         journalKindFilter: $journalKindFilter
     )
     ```

7. **`JournalWindowController.show(...)` — расширение сигнатуры** `[AC:2]`
   - Файл: `Sources/CityDeveloper/App/JournalWindowController.swift`
   - Блок: метод `show(...)` (стр. 15–65).
   - Что меняем — добавить параметр в сигнатуру и в вызов `SidePanelView(...)`:
     ```swift
     func show(engine: CityEngine,
               bridge: SceneBridge,
               collapsed: Binding<Bool>,
               selectedProject: Binding<String?>,
               dateFrom: Binding<Date>,
               dateTo: Binding<Date>,
               didInitDates: Binding<Bool>,
               journalKindFilter: Binding<JournalKindFilter>) {
         // ... idempotent guard без изменений ...
         let panel = SidePanelView(
             engine: engine,
             bridge: bridge,
             collapsed: collapsed,
             selectedProject: selectedProject,
             dateFrom: dateFrom,
             dateTo: dateTo,
             didInitDates: didInitDates,
             journalKindFilter: journalKindFilter
         )
         // ... остальное без изменений ...
     }
     ```
   - ⚠️ После шага 7 проект соберётся. Между 3 и 7 — нет.

8. **Юнит-тест `JournalFilterTests.swift`** `[AC:8]`
   - Файл: новый — `Tests/CityDeveloperTests/JournalFilterTests.swift` (директория и `.testTarget` уже добавлены через TASK-014/TASK-024).
   - Что создаём:
     ```swift
     import XCTest
     @testable import CityDeveloper

     final class JournalFilterTests: XCTestCase {

         private let allKinds: [GameEvent.Kind] = GameEvent.Kind.allCases

         /// Фабрика: по одному событию на каждый kind, у всех project="p1",
         /// ts на сутки назад/вперёд от base.
         private func sample() -> [GameEvent] {
             let base = Date(timeIntervalSince1970: 1_700_000_000)
             return allKinds.enumerated().map { (i, kind) in
                 GameEvent(
                     ts: base.addingTimeInterval(TimeInterval(i) * 60),
                     kind: kind, project: "p1",
                     title: kind.displayName,
                     taskId: nil, source: nil
                 )
             }
         }

         private let wideRange = (
             from: Date(timeIntervalSince1970: 0),
             to: Date(timeIntervalSince1970: 2_000_000_000)
         )

         func testAllPresetReturnsAll() {
             let out = JournalFilter.apply(
                 events: sample(), projectId: nil,
                 dateFrom: wideRange.from, dateTo: wideRange.to,
                 kindFilter: .all
             )
             XCTAssertEqual(out.count, 7)
         }

         func testTaskCompletedPreset() {
             let out = JournalFilter.apply(
                 events: sample(), projectId: nil,
                 dateFrom: wideRange.from, dateTo: wideRange.to,
                 kindFilter: .some([.taskCompleted])
             )
             XCTAssertEqual(out.map(\.kind), [.taskCompleted])
         }

         func testUnitBuiltPreset() {
             let out = JournalFilter.apply(
                 events: sample(), projectId: nil,
                 dateFrom: wideRange.from, dateTo: wideRange.to,
                 kindFilter: .some([.unitBuilt])
             )
             XCTAssertEqual(out.map(\.kind), [.unitBuilt])
         }

         func testStageUpPreset() {
             let out = JournalFilter.apply(
                 events: sample(), projectId: nil,
                 dateFrom: wideRange.from, dateTo: wideRange.to,
                 kindFilter: .some([.stageUp])
             )
             XCTAssertEqual(out.map(\.kind), [.stageUp])
         }

         func testDecayPreset() {
             let decay: Set<GameEvent.Kind> = [.decayTick, .fire, .restore, .ruinsCleared]
             let out = JournalFilter.apply(
                 events: sample(), projectId: nil,
                 dateFrom: wideRange.from, dateTo: wideRange.to,
                 kindFilter: .some(decay)
             )
             XCTAssertEqual(Set(out.map(\.kind)), decay)
             XCTAssertEqual(out.count, 4)
         }

         func testEmptySelectionReturnsEmpty() {
             let out = JournalFilter.apply(
                 events: sample(), projectId: nil,
                 dateFrom: wideRange.from, dateTo: wideRange.to,
                 kindFilter: .some([])
             )
             XCTAssertTrue(out.isEmpty)
         }

         func testProjectFilterAndKindCombine() {
             var events = sample()
             // подсадить событие из другого проекта
             events.append(GameEvent(
                 ts: Date(timeIntervalSince1970: 1_700_000_999),
                 kind: .taskCompleted, project: "p2",
                 title: "x", taskId: nil, source: nil
             ))
             let out = JournalFilter.apply(
                 events: events, projectId: "p2",
                 dateFrom: wideRange.from, dateTo: wideRange.to,
                 kindFilter: .some([.taskCompleted])
             )
             XCTAssertEqual(out.count, 1)
             XCTAssertEqual(out.first?.project, "p2")
         }

         func testInvalidDateRangeStillRespectsKind() {
             // dateFrom > dateTo → dateRangeValid = false → диапазон не применяется
             // (текущее поведение `filteredEvents` сохраняем).
             let out = JournalFilter.apply(
                 events: sample(), projectId: nil,
                 dateFrom: Date(timeIntervalSince1970: 2_000_000_000),
                 dateTo: Date(timeIntervalSince1970: 1_500_000_000),
                 kindFilter: .some([.fire])
             )
             XCTAssertEqual(out.map(\.kind), [.fire])
         }

         func testSortDescending() {
             let out = JournalFilter.apply(
                 events: sample(), projectId: nil,
                 dateFrom: wideRange.from, dateTo: wideRange.to,
                 kindFilter: .all
             )
             let timestamps = out.map(\.ts)
             XCTAssertEqual(timestamps, timestamps.sorted(by: >))
         }

         /// Событие с ts в середине того же дня, что и dateTo, должно проходить
         /// (т.к. сравнение идёт с `dateTo.endOfDay` — 23:59:59).
         func testEndOfDayBoundary() {
             let cal = Calendar.current
             let day = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
             let midDay = cal.date(byAdding: .hour, value: 14, to: day)!
             let nextDay = cal.date(byAdding: .day, value: 1, to: day)!

             let inside = GameEvent(
                 ts: midDay, kind: .taskCompleted, project: "p1",
                 title: "in", taskId: nil, source: nil
             )
             let outside = GameEvent(
                 ts: cal.date(byAdding: .hour, value: 1, to: nextDay)!,
                 kind: .taskCompleted, project: "p1",
                 title: "out", taskId: nil, source: nil
             )
             let out = JournalFilter.apply(
                 events: [inside, outside], projectId: nil,
                 dateFrom: day, dateTo: day,
                 kindFilter: .all
             )
             XCTAssertEqual(out.map(\.title), ["in"],
                            "Mid-day event of dateTo must pass, next-day must not")
         }
     }
     ```

### Edge cases (явно обработать)

- [x] **`.some(∅)`** `[AC:6]` — `JournalFilter.apply` возвращает `[]` (шаг 2 — `isEmptySelection` early-return). UI показывает «Тип не выбран» (шаг 4 — новая ветка).
- [x] **`.all` + пустой `engine.events`** — общий guard `isEmpty` (стр. 225 в текущем коде) перехватывает раньше → «Событий пока нет».
- [x] **Фильтр + диапазон дат пуст** — порядок ветвей `dateFrom > dateTo` → потом `isEmptySelection`. «Диапазон пуст» приоритетнее (шаг 4 — добавляем `isEmptySelection` **после** date-check).
- [x] **Старый формат `events.jsonl` (до TASK-024)** — Picker показывает все 7 типов, но пресет «Постройки юнитов» даст пустой результат. Это норма (PM acknowledges).
- [x] **Двойной выбор пресета и кастома** — оба ведут в один `Binding<JournalKindFilter>`. Пресет перезаписывает кастом, и наоборот. Popover при следующем открытии видит актуальный set.
- [x] **Сортировка** — внутри `JournalFilter.apply`, сохранена desc по `ts` (тест `testSortDescending`).

### Файлы для изменения

- `Sources/CityDeveloper/Data/GameEvent.swift` — `Kind: ..., CaseIterable`.
- `Sources/CityDeveloper/UI/JournalKindFilter.swift` — **новый файл**, содержит enum, extensions для иконок/имён, pure-функцию `JournalFilter.apply`.
- `Sources/CityDeveloper/UI/SidePanelView.swift` — `@Binding journalKindFilter`, `@State showCustomPopover`, новый Picker+popover в `journalSection`, замена `filteredEvents`, новая ветка «Тип не выбран», иконка в `JournalRow`.
- `Sources/CityDeveloper/UI/ContentView.swift` — `@State journalKindFilter`, проброс в `show(...)`.
- `Sources/CityDeveloper/App/JournalWindowController.swift` — расширение сигнатуры `show(...)` и вызова `SidePanelView(...)`.
- `Tests/CityDeveloperTests/JournalFilterTests.swift` — **новый файл**, 9 XCTest-кейсов.

### Файлы НЕ трогать

- `Sources/CityDeveloper/Data/GameEvent.swift` за пределами добавления `CaseIterable`. Поля и init НЕ меняем.
- `Sources/CityDeveloper/UI/SettingsView.swift` / `InspectorOverlayCard.swift` — другие части UI, не связаны с журналом.
- `AppSettings.swift` — persistence фильтра НЕ делаем (PM явно).
- Не вводим `JournalRow` source-фильтр (jsonl/notes/git) — Backlog.
- `Package.swift` / `Tests/CityDeveloperTests/` — `.testTarget` уже добавлен в TASK-014 / TASK-024; для 015 нужен ТОЛЬКО новый файл теста.

### Команды проверки (для DoD)

- Компиляция: `swift build` из `/Users/ilahohlov/CityDeveloper`. Ожидание: 0 ошибок, 0 новых warning'ов.
- Тесты: `swift test --filter JournalFilterTests`. Ожидание: 10 пройдены.
- Ручная проверка smoke `[AC:9]` (после TASK-024):
  1. Удалить `events.jsonl`, запустить приложение, закрыть 6 задач для одного проекта (хотя бы один stage-up).
  2. Открыть журнал (кнопка `list.bullet`) → видны 6 `task_completed` + 6 `unit_built` + минимум 1 `stage_up` + decay-tick'и за время. Меню «Тип» отображает текущий ярлык «Все типы».
  3. Выбрать «Апгрейды стадии» → виден только `stage_up`-ряд (≥1).
  4. Выбрать «Постройки юнитов» → 6 рядов.
  5. Выбрать «Все типы» → ≥13 рядов.
  6. Открыть «Кастом…» popover → 7 чекбоксов. Снять все → закрыть popover → в журнале «Тип не выбран», 0 рядов. Кнопка «Все» в popover возвращает все 7. Кнопка «Сбросить» делает пусто.
  7. Закрыть/открыть окно журнала → выбор фильтра сохранён.

### Сложность

`middle`

**Обоснование:** UI feature на нескольких слоях (ContentView → JournalWindowController → SidePanelView), с custom popover и multi-select state, плюс вынос pure-функции для тестируемости. 6 файлов, 9 тест-кейсов. Не junior (несколько слоёв @Binding-проброса + popover-state). Не senior (без архитектурных решений по persistence или новых паттернов — переиспользуем существующие).

### Ожидаемое время

M (≤1д) — 4 файла Swift-кода + 1 markdown-документация (нет, doc-файлы не меняем — Current.md обновится только если D-11 закрылся, что зависит от TASK-014) + 1 тест-файл. Реалистично 4–6 часов с popover-нюансами.

---

## ✅ Исполнение

_Исполнитель: sonnet (executor)_
_Сложность: middle_

### Definition of Done

#### Функциональные
- [x] AC1–AC7 — structural pass (verify Sonnet)
- [ ] Smoke-тест с реальными событиями — manual (GUI приложение, нужны live ingestTaskCompletion + UI клики)

#### Технические
- [x] Компиляция Swift без новых ошибок/варнингов (`swift build` clean)
- [ ] `swift test --filter JournalFilterTests` — n/a (нет Xcode.app/XCTest framework). Структура 10 кейсов корректна.

#### Обновление документации
- [x] `Current.md`: F-11 ⚠️ → ✅ — D-11 полностью закрыт (TASK-014 + TASK-024 + TASK-015)
- [x] `Diff.md`: D-11 вычеркнут (zaкрытие через TASK-014/024/015)

---

## Статус

`[x] done`

## Метаданные
- Создана PM: 2026-05-22
- Пересоздана PM (split → atomic, перенос записи событий в TASK-024): 2026-05-22
- Spec-review: implicit-approved (PM-блок полный: Done, AC, сценарий, «не делаем», edge cases, зависимости)
- Lead-model: opus (override — пользователь в режиме no-pause; sonnet-default по триггерам)
- Plan-review: revised (sonnet, 2 круга → approved)
- Code-review: approved (opus, 1 круг)
- Blocked-by: TASK-024 ✅
- Готова к работе: 2026-05-22
- Завершена: 2026-05-23
- Коммит: 1093693
