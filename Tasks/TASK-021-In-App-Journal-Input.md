# TASK-021: In-app journal — ручной ввод задач (F-17)

## Связь
- **F-17** In-app journal (ручной ввод)
- **D-17** из diff.md
- **F-11** Инспектор / журнал (используем существующий `JournalWindowController`)
- **F-03** Event sourcing (запись через существующий механизм)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим

Дать пользователю возможность вручную закидывать выполненные задачи прямо
из приложения, без редактирования `tasks.jsonl` и других внешних файлов. Это
закрывает класс «удалённых» задач: встречи, физические дела, обучение, разговоры
— то, что не оставляет следа в коде / заметках, но реально сделано. Город
должен расти не только от автоматических источников, но и от ручного журнала.

Две точки входа, обе пишут в `events.jsonl` с тегом `source: "journal"`:

1. **Глобальный журнал.** Расширение существующего floating-окна журнала
   (`JournalWindowController` из TASK-016) — добавить блок ввода в верхней
   части: текстовое поле + dropdown с выбором projectId (существующие
   проекты + «Создать новый») + кнопка Enter / горячая клавиша Cmd+Return.
2. **Контекстный ввод по клику на квартал.** В explore-режиме клик по
   пустой части существующего квартала (НЕ на юните и НЕ на маркере) → popup
   «Добавить задачу к проекту \<name\>», projectId предзаполнен из квартала,
   только текстовое поле + Enter.

### Пользовательский сценарий

**Глобальный журнал:**
1. Пользователь нажимает кнопку 📜 поверх SpriteView (уже существует из TASK-016)
   или хоткей открытия журнала → открывается floating-окно `JournalWindowController`.
2. В верхней части окна — блок ввода: текстовое поле «что сделал», dropdown
   «проект» (список существующих + «Создать новый…»), кнопка «Добавить»
   (или Cmd+Return).
3. Пользователь вводит «купил продукты», выбирает `household` → Enter.
4. В течение 1 сек на карте появляется юнит в квартале `household` (если
   проекта не было — создаётся новый District по правилам F-06).
5. В журнале сразу видна свежая запись с тегом `journal`.

**Контекстный клик:**
1. Пользователь в explore-режиме видит свой квартал `myapp`. Кликает в
   пустую клетку рядом с юнитами (часть district'а, но не сам юнит).
2. Открывается popup-карточка «Добавить задачу к проекту myapp»: одно
   текстовое поле + Enter, projectId предзаполнен и неизменяем в этом
   контексте.
3. Ввёл строку → Enter → юнит появляется в квартале, popup закрывается.

### Acceptance criteria

- [ ] **Блок ввода в JournalWindowController:** в верхней части окна журнала
      присутствуют: `TextField` «что сделал», `Picker`/`Menu` «проект»
      (список существующих projectId + опция «Создать новый…»), кнопка
      «Добавить» (или Cmd+Return как hotkey).
- [ ] **Создание события из глобального журнала:** при отправке формируется
      `GameEvent.taskCompleted` с `project=<выбран>`, `title=<введённый
      текст>`, `ts=Date()`, `source="journal"`, проходит через
      `engine.ingestTaskCompletion(...)` или эквивалентный путь, в течение
      **1 сек** на карте появляется юнит в соответствующем квартале.
- [ ] **«Создать новый» проект:** при выборе опции «Создать новый…» в
      dropdown появляется inline-поле ввода имени проекта; после подтверждения
      проект становится текущим выбором, при первой задаче создаётся новый
      District (по правилам F-06).
- [ ] **Валидация ввода:** пустое поле задачи (или только whitespace) →
      кнопка/Enter не отправляет, поле подсвечивается лёгким `warning`-бордером
      (1 pt) на 1.5 сек. Пустой projectId → аналогично. Длина title ограничена
      255 символов (truncate с подсказкой).
- [ ] **Hit-test «пустая клетка квартала»:** в explore-режиме клик по позиции
      внутри bounding-box district'а, но не пересекающейся с существующим
      sprite-узлом юнита и не с district-маркером, открывает popup-карточку
      контекстного ввода. Клик строго на юните или маркере — старая логика
      (инспектор) не меняется.
- [ ] **Popup контекстного ввода** имеет тот же визуальный стиль, что и
      `InspectorOverlayCard` (parchment, padS отступы, radiusS), но в режиме
      «ввод»: одно `TextField` + кнопка «Добавить»/Enter, заголовок «Добавить
      задачу к проекту \<name\>», подзаголовок 11pt caption. ESC закрывает
      без сохранения.
- [ ] **Тег source=journal во всех событиях:** независимо от точки входа
      (глобальный журнал или контекст), `GameEvent.source` записывается как
      `"journal"`. В журнале они видны как обычные строки (без выделения), но
      фильтр по типу события (TASK-015) сможет в будущем их отделять.
- [ ] **Idempotency:** journal-события идут в `events.jsonl` через тот же
      eventLog, что и `tasks.jsonl`-события. Replay из snapshot+tail
      восстанавливает их корректно (юниты на тех же местах).
- [ ] **Done-критерий F-17:** см. блок ниже.

### Что НЕ делаем (границы скоупа)

- Не меняем существующее поведение клика по юниту (F-11 inspector) — только
  расширяем для пустых клеток квартала.
- Не вводим UI редактирования / удаления journal-событий из истории — событие
  попало в лог → остаётся (event-sourcing инвариант).
- Не делаем шаблоны быстрого ввода / автодополнение по истории — текстовое поле
  простое.
- Не вводим теги / категории внутри journal-задачи — только `project` + `title`.
- Не делаем поддержку Markdown / форматирования в title — plain text.
- Не делаем глобальный хоткей на открытие journal-popup откуда угодно
  (например, в wallpaper-режиме) — это отдельная фича в Backlog. Текущая
  кнопка 📜 в explore — достаточно.
- Не трогаем F-04 (TasksJsonlWatcher) — он продолжает работать параллельно.
- Не делаем «закрытие» / архивирование задач в журнале — событие = факт, факты
  не закрываются.

### Edge cases

- [ ] **Создание проекта со стороны journal == возврат к существующей руине**
      (F-06 ruin-priority): если введённое имя проекта совпадает с
      существующим decay-4 проектом — НЕ занимает руину (новый projectId
      становится «возвращением к проекту» — это поведение F-09 restore, не F-06).
      Если introduced как новое имя, никогда не встречавшееся — F-06 берёт
      руину если есть. Уточнение: journal не различает эти случаи семантически
      — он просто создаёт `GameEvent.taskCompleted`, далее всё работает как
      обычное событие из любого источника.
- [ ] **Два project в logе и пользователь ввёл точно совпадающее с одним**:
      событие пишется в существующий project, новый не создаётся.
- [ ] **Открытое окно журнала + новое событие пришло из tasks.jsonl/git
      одновременно**: список истории обновляется онлайн (через существующий
      механизм отображения). Поле ввода не теряет фокус.
- [ ] **Контекстный клик во время идущей анимации** (decay overlay, ruin clear)
      по тому же кварталу — popup всё равно открывается, событие пишется
      нормально. Не блокировать ввод.
- [ ] **Контекстный клик в зоне руины (decay-4)** — popup НЕ должен открыться
      (это «мёртвый» квартал, добавление задачи туда семантически = возврат
      проекта, что обрабатывается F-09 restore). Если хочется добавить
      задачу — использовать глобальный журнал и явно выбрать projectId.
- [ ] **Цикл клик→popup→Enter→popup закрылся→немедленно ещё клик** на ту же
      пустую клетку: следующий popup открывается заново, события не теряются.
- [ ] **JournalWindowController закрыт во время ввода**: введённый и не
      сохранённый текст теряется. Это ожидаемо. (Опционально лид может
      сохранять draft в `UserDefaults`, но это не AC.)
- [ ] **Длина title > 255 символов**: truncate до 255 + индикатор «обрезано»
      в caption (1 раз, чтобы юзер заметил).
- [ ] **Snapshot во время ввода** (не в момент Enter) — поле ввода живёт в
      SwiftUI-состоянии, не в `state.json`, snapshot не затрагивает.

### Зависимости

- **F-03** Event sourcing — закрыт. События идут через `eventLog.append + apply`.
- **F-06** Project-District — закрыт (TASK-017). Новый projectId создаст
  District по правилам (с приоритетом руин).
- **F-11** Инспектор/журнал — частично закрыт. `JournalWindowController` уже
  существует (TASK-016 done). Расширяем его блоком ввода.
- **F-12** Snapshots — закрыт. Journal-события сохраняются через snapshot+tail.
- **F-14** AppSettings — закрыт. Если потребуется флаг (например, autofocus
  на поле ввода) — добавить через существующий механизм.
- **D-02** SKTileMapNode — открыт. **Не блокер**: hit-test «пустая клетка
  квартала» работает на уровне sprite-нод и district-bounding-box,
  независимо от backing-layer.
- Нет внешних сервисов / секретов / миграций.

### Дизайн

Из `DesignConcept.md`:
- **Блок ввода в Side Panel/Journal Window:** фон `parchment` (как и сам
  журнал), padding `padM = 16pt` вокруг, разделитель 1pt `inkDark` 20%
  снизу под формой ввода. Текстовое поле — стандартный SwiftUI `TextField`
  с минимальной высотой 32pt. Picker для projectId — `Menu`-стиль или
  inline-`Picker` (на усмотрение лида). Кнопка «Добавить» —
  primary-button, цвет `info` (`#3C6A8C`).
- **Контекстный popup:** идентичный стиль `InspectorOverlayCard`
  (parchment + radiusS=6pt + 1pt inkDark border 30%, тень 10pt blur
  inkDark 25%). Заголовок «Добавить задачу к проекту \<name\>» 15pt
  Semibold inkDark, текстовое поле 13pt Regular, кнопка Add справа от поля
  или Enter.
- **Анимации:** popup появляется fadeIn 0.2 сек, исчезает fadeOut 0.15 сек.
  Подсветка warning-бордера при пустом вводе — 1.5 сек fadeOut.
- **Размещение глобального журнала** — без изменений (TASK-016 floating
  window остаётся).
- **Контекстный popup** размещается рядом с точкой клика (как
  `InspectorOverlayCard`), смещается чтобы не уйти за границы окна.

### Done-критерий

_Из concept.md F-17 (дословно):_

> Глобальный журнал открывается по кнопке/хоткею, ввод текста + проект + Enter
> → юнит появляется на соответствующем квартале в течение 1 сек. Клик по
> пустой части существующего квартала в explore → popup с предзаполненным
> projectId, ввод задачи работает идентично. Все журнальные события видны в
> общем логе с тегом `source: journal`. История journal-событий не теряется
> при перезапуске (idempotent через `events.jsonl`).

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-22_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

В коде уже есть:
- `App/JournalWindowController.swift` — NSWindow + NSHostingController с
  `SidePanelView` внутри. `show(engine:bridge:collapsed:selectedProject:
  dateFrom:dateTo:didInitDates:)`. Открывается кнопкой `list.bullet` в
  `ContentView` (TASK-016).
- `UI/SidePanelView.swift` — содержит две секции: **Projects** (карточки
  всех проектов с сортировкой по `lastActivityAt`) и **Journal** (список
  событий с фильтром по projectId + date range). Используется
  `engine.state.projects` через `@ObservedObject`. Дизайн: width=320pt,
  `regularMaterial`, `radiusS`.
- `UI/InspectorOverlayCard.swift` — карточка по клику на юнит. Стиль:
  `Color.paletteSandLight` фон, `cornerRadius(10)`, shadow, padding 12pt.
  Тексты на `paletteInkDark`. **Источник правды для стиля контекстного popup.**
- `Game/GameScene.swift` — `mouseUp` + `handleClick(at:)` (~строки ?–?):
  hit-test через `nodes(at:)`, traversal parent chain, поиск `unitIdKey` в
  `userData`. Если нет hit → `hideInspector()`. **Расширим**: после miss
  проверить попадание в district-diamond.
- `Game/GameScene.swift` — `isoPosition(grid:)` и приватный `diamondPath()`
  (есть, не используется) для diamond hit-test.
- `Game/CityEngine.swift:61–76` — `ingestTaskCompletion(project:title:
  taskId:source:ts:)` — точка записи. `source` — Optional String,
  передаём `"journal"`.
- `Data/CityState.swift` — `ProjectState` с `districtOrigin: GridPoint`,
  `id: String` (=projectId).
- `UI/SceneBridge.swift` — мост Scene↔SwiftUI (паттерн уже есть для
  инспектора). Расширим: новый publisher для входного popup.
- `Theme/Palette.swift` — `paletteParchment`, `paletteSandLight`,
  `paletteInkDark`, `paletteInfo` (если есть), и др.
- `UI/SettingsView.swift` — draft-pattern для текстовых полей (как
  reference).

Переиспользуем:
- Стиль `InspectorOverlayCard` для контекстного popup.
- Паттерн `engine.ingestTaskCompletion` без новых параметров engine.
- `SceneBridge` как мост Scene→SwiftUI для уведомления «клик в пустой
  части квартала X».
- Draft-pattern из `SettingsView` для валидации текстового поля.

Что нужно дописать:
- `inputSection` в `SidePanelView` (глобальный журнал).
- `TaskInputPopupView` — новый SwiftUI overlay для контекстного ввода.
- Расширение `handleClick` в `GameScene` — district hit-test после miss
  на юнит.
- Новый publisher в `SceneBridge` (например, `inputRequest:
  PassthroughSubject<(projectId: String, screenPoint: CGPoint), Never>`).
- `ContentView` — overlay-зона для `TaskInputPopupView`.

### Архитектурное решение

Два UX-канала, **общая запись** через `engine.ingestTaskCompletion(project:,
title:, taskId: nil, source: "journal", ts: Date())`:

1. **Глобальный журнал.** `SidePanelView` получает новую секцию `inputSection`
   в самом верху expanded-вида. Внутри: `TextField` (draftTitle) + `Picker`
   (draftProjectId), кнопка Add / hotkey Cmd+Return. Список Picker заполняется
   из `engine.state.projects.keys.sorted` + специальная опция
   `__new__` («Создать новый…»), при выборе которой появляется inline TextField
   для имени проекта.

2. **Контекстный popup.** `GameScene.handleClick` после неудачного hit-test
   на юнит выполняет diamond hit-test: для каждого `project in
   state.projects.values` рассчитывает diamond вокруг `isoPosition(districtOrigin)`
   с размером `tileWidth × N` (N = функция от `unitIds.count`, минимум 5×5
   клеток). Если клик попал в один из diamond'ов — `bridge.inputRequest.send(
   (projectId: project.id, screenPoint: convertPoint(...))`. Если попал в
   несколько (overlap кварталов) — выбираем `project` с минимальным расстоянием
   от центра квартала до точки клика.

   `ContentView` подписан на `bridge.inputRequest`, при получении показывает
   `TaskInputPopupView` через ZStack-overlay поверх SpriteView в позиции
   screenPoint. Закрывается по Esc / клику вне popup / после Add.

   **Edge: клик в зоне руины (decay==4)** — guard в `GameScene.handleClick`:
   если найденный проект имеет `decayLevel == 4` → не отправляем event в
   bridge (popup не открывается). См. AC edge cases.

`source: "journal"` — единственное обязательное при ingest, остальное обычный
path. Snapshot+tail replay восстанавливает journal-события как любые
taskCompleted — мест где замешана семантика «journal vs остальное» — нет, кроме
визуального тега в журнале (необязательно — фильтр TASK-015 future).

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку.

1. **SceneBridge.inputRequest publisher** `[AC:5,6]`
   - Файл: `Sources/CityDeveloper/UI/SceneBridge.swift`.
   - Действие:
     1. **Добавить `import Combine`** в начало файла (если ещё нет — без
        этого компиляция упадёт).
     2. Добавить в класс `SceneBridge`:
        ```swift
        struct InputRequest {
            let projectId: String
            let viewPoint: CGPoint   // в координатах SKView (origin top-left,
                                     // та же система, что у NSView). НЕ screen,
                                     // НЕ scene. SwiftUI converts через GeometryReader.
        }
        let inputRequest = PassthroughSubject<InputRequest, Never>()
        ```
     3. Объявить структуру `InputRequest` — tuple-сигнатуры в Combine
        неудобны при долгом использовании.

2. **GameScene.handleClick district hit-test** `[AC:5,7]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift`, метод
     `handleClick(at:)`.
   - Действие: после ветки `hideInspector()` (когда unit не найден), перед
     return добавить:
     ```swift
     guard let engine = engine, let bridge = bridge else { return }
     // Diamond hit-test: для каждого активного проекта (decayLevel < 4)
     // считаем isoPosition(districtOrigin) и diamond размером
     // tileWidth=64 × ceil(sqrt(max(unitIds.count, 4))).
     var bestMatch: (projectId: String, dist: CGFloat)?
     for project in engine.state.projects.values where project.decayLevel < 4 {
         let center = isoPosition(grid: project.districtOrigin)
         let radius = max(2, Int(ceil(sqrt(Double(max(project.unitIds.count, 4))))))
         if isPointInDistrictDiamond(point: location, center: center, gridRadius: radius) {
             let dist = hypot(location.x - center.x, location.y - center.y)
             if bestMatch == nil || dist < bestMatch!.dist {
                 bestMatch = (project.id, dist)
             }
         }
     }
     if let match = bestMatch {
         // Convert scene-coords → SKView-coords (NSView-system, origin top-left).
         // SpriteKit API: SKScene.convert(_:to:) переводит scene-точку в parent.
         // Для перехода scene → view используем view.convert(point, from: scene).
         let viewPoint = self.view?.convert(location, from: self) ?? location
         bridge.inputRequest.send(.init(projectId: match.projectId, viewPoint: viewPoint))
     }
     ```
   - Добавить приватный helper `isPointInDistrictDiamond(point:center:gridRadius:)`:
     ```swift
     private func isPointInDistrictDiamond(point: CGPoint, center: CGPoint, gridRadius: Int) -> Bool {
         // Diamond в изометрии: width = 2 * gridRadius * tileWidth/2,
         // height = 2 * gridRadius * tileHeight/2.
         // Тест: |dx|/(gridRadius*tw/2) + |dy|/(gridRadius*th/2) <= 1.
         let tileW: CGFloat = 64, tileH: CGFloat = 32
         let dx = abs(point.x - center.x)
         let dy = abs(point.y - center.y)
         let nx = dx / (CGFloat(gridRadius) * tileW / 2)
         let ny = dy / (CGFloat(gridRadius) * tileH / 2)
         return nx + ny <= 1.0
     }
     ```

3. **TaskInputPopupView (контекстный)** `[AC:6,7]`
   - Файл: `Sources/CityDeveloper/UI/TaskInputPopupView.swift` (новый).
   - Действие: SwiftUI View, принимает `projectId: String`, `onSubmit:
     (String) -> Void`, `onCancel: () -> Void`. Стиль аналогичен
     `InspectorOverlayCard` (parchment / sandLight, padding 12pt, radius 10,
     shadow). Поля:
     - Заголовок: «Добавить задачу к проекту \(projectId)» 15pt Semibold
       inkDark.
     - `TextField("Что сделал?", text: $draftTitle)` 13pt, autofocus.
     - Кнопка `Add` / Cmd+Return → `onSubmit(draftTitle)`. Esc / клик-out
       → `onCancel`.
     - Если `draftTitle.trimmingCharacters(.whitespacesAndNewlines).isEmpty`
       — кнопка disabled, бордер warning 1pt 1.5 сек при попытке submit.
   - Скелет:
     ```swift
     struct TaskInputPopupView: View {
         let projectId: String
         var onSubmit: (String) -> Void
         var onCancel: () -> Void
         @State private var draftTitle: String = ""
         @State private var showWarning: Bool = false
         @FocusState private var focused: Bool

         var body: some View {
             VStack(alignment: .leading, spacing: 8) {
                 Text("Добавить задачу к проекту \(projectId)")
                     .font(.system(size: 15, weight: .semibold))
                     .foregroundColor(.paletteInkDark)
                 TextField("Что сделал?", text: $draftTitle)
                     .textFieldStyle(.roundedBorder)
                     .focused($focused)
                     .onSubmit { trySubmit() }
                 HStack {
                     Spacer()
                     Button("Отмена") { onCancel() }
                     Button("Добавить") { trySubmit() }
                         .keyboardShortcut(.return, modifiers: [.command])
                         .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                 }
             }
             .padding(12)
             .frame(maxWidth: 320)
             .background(Color.paletteSandLight)
             .cornerRadius(10)
             .overlay(
                 // Используем paletteWarning из Theme/Palette.swift (стиль-гайд),
                 // не системный Color.orange.
                 RoundedRectangle(cornerRadius: 10)
                     .stroke(Color.paletteWarning.opacity(showWarning ? 1 : 0), lineWidth: 1)
             )
             .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
             .onAppear { focused = true }
         }
         private func trySubmit() {
             let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
             guard !trimmed.isEmpty else {
                 withAnimation { showWarning = true }
                 DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                     withAnimation { showWarning = false }
                 }
                 return
             }
             onSubmit(String(trimmed.prefix(255)))
         }
     }
     ```

4. **ContentView overlay для popup** `[AC:5,6]`
   - Файл: `Sources/CityDeveloper/App/ContentView.swift` (или эквивалент —
     корневой View, где сейчас живёт SpriteView; если ContentView это
     SidePanelView-обёртка — искать выше по иерархии).
   - Действие: подписаться на `bridge.inputRequest`, держать `@State
     private var contextInput: SceneBridge.InputRequest? = nil`. Через
     `GeometryReader` получить размеры контейнера, в ZStack поверх SpriteView
     показывать `TaskInputPopupView` с clamp координат.
   - Скелет:
     ```swift
     @State private var contextInput: SceneBridge.InputRequest? = nil
     @FocusState private var rootFocused: Bool

     var body: some View {
         GeometryReader { geo in
             ZStack {
                 SpriteView(scene: scene)
                 if let ci = contextInput {
                     // viewPoint уже в координатах SKView (origin top-left,
                     // Y вниз) — это та же система, что у SwiftUI внутри
                     // GeometryReader. Clamp по ширине popup (320pt) и
                     // высоте (~140pt).
                     let popupW: CGFloat = 320, popupH: CGFloat = 140
                     let clampedX = min(max(ci.viewPoint.x, popupW/2 + 8),
                                        geo.size.width  - popupW/2 - 8)
                     let clampedY = min(max(ci.viewPoint.y, popupH/2 + 8),
                                        geo.size.height - popupH/2 - 8)
                     TaskInputPopupView(
                         projectId: ci.projectId,
                         onSubmit: { title in
                             engine.ingestTaskCompletion(
                                 project: ci.projectId, title: title,
                                 taskId: nil, source: "journal", ts: Date()
                             )
                             contextInput = nil
                         },
                         onCancel: { contextInput = nil }
                     )
                     .frame(width: popupW)
                     .position(x: clampedX, y: clampedY)
                 }
             }
         }
         .focusable()
         .focused($rootFocused)
         .onAppear { rootFocused = true }
         .onReceive(bridge.inputRequest) { req in
             contextInput = req
         }
         .onKeyPress(.escape) {
             if contextInput != nil { contextInput = nil; return .handled }
             return .ignored
         }
     }
     ```
   - **Замечание для исполнителя:**
     - `.onKeyPress(.escape)` — macOS 14+ (проект таргетит `.macOS(.v14)`).
       Требует фокуса: `.focusable()` + `@FocusState`. Без этого Esc не
       сработает.
     - Конвертация координат: viewPoint из SceneBridge уже в системе SKView
       = NSView. SwiftUI внутри `GeometryReader` использует ту же систему
       (origin top-left). Прямое `.position(x:y:)` корректно. **НЕ нужно**
       лезть в `NSWindow.convertPoint(toScreen:)`.

5. **inputSection в SidePanelView (глобальный журнал)** `[AC:1,2,3,4,7]`
   - Файл: `Sources/CityDeveloper/UI/SidePanelView.swift`.
   - Действие: добавить вверху expandedView (перед Projects Section) новую
     секцию:
     ```swift
     VStack(alignment: .leading, spacing: 8) {
         Text("Добавить задачу")
             .font(.system(size: 13, weight: .semibold))
             .foregroundColor(.paletteInkDark)
         TextField("Что сделал?", text: $draftJournalTitle)
             .textFieldStyle(.roundedBorder)
         HStack(spacing: 6) {
             // Picker с проектами + "Создать новый…"
             Picker("Проект", selection: $draftJournalProject) {
                 ForEach(projectNames, id: \.self) { name in
                     Text(name).tag(name)
                 }
                 Text("Создать новый…").tag("__new__")
             }
             .pickerStyle(.menu)
             if draftJournalProject == "__new__" {
                 TextField("Имя проекта", text: $draftNewProjectName)
                     .textFieldStyle(.roundedBorder)
                     .frame(maxWidth: 120)
             }
             Spacer()
             Button("Add") { trySubmitJournal() }
                 .keyboardShortcut(.return, modifiers: [.command])
                 .disabled(!journalFormValid)
         }
     }
     .padding(.horizontal, 12)
     .padding(.vertical, 8)
     ```
   - `@State private var draftJournalTitle: String = ""`,
     `@State private var draftJournalProject: String = ""`,
     `@State private var draftNewProjectName: String = ""`.
   - **Переиспользовать существующий computed `projectNames`** в
     `SidePanelView` (~строка 42–46, сортировка через `localizedCompare`).
     Не объявлять повторно.
   - `journalFormValid`: title не пуст, project либо из списка либо
     `__new__` + newProjectName не пуст.
   - `trySubmitJournal()`:
     ```swift
     let project = (draftJournalProject == "__new__")
         ? draftNewProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
         : draftJournalProject
     let title = String(draftJournalTitle.prefix(255))
         .trimmingCharacters(in: .whitespacesAndNewlines)
     guard !project.isEmpty, !title.isEmpty else { /* подсветка */ return }
     engine.ingestTaskCompletion(
         project: project, title: title,
         taskId: nil, source: "journal", ts: Date()
     )
     draftJournalTitle = ""
     draftNewProjectName = ""
     // оставить draftJournalProject как есть для удобства быстрых записей.
     ```

### Edge cases (явно обработать)

- [ ] **Создание проекта с тем же projectId, что у активной руины (decay-4):**
      `engine.ingestTaskCompletion` создаст новый `taskCompleted` event,
      F-06 logic решит — рассматривать как «возвращение» (decay 1–3) или
      «новый проект на месте руины». Шаг 5 не различает — это поведение
      engine. См. F-09/F-06.
- [ ] **Пустой title** в обоих UX-каналах — guard в trySubmit, кнопка
      disabled, warning-бордер 1.5 сек. Шаги 3, 5.
- [ ] **Совпадение draftJournalProject с существующим (mode `__new__`):**
      `ingestTaskCompletion` найдёт существующий project, новый не создаст.
      OK.
- [ ] **Клик в зону руины (decay==4)** — guard в шаге 2 `where
      project.decayLevel < 4`. Popup не открывается. Юзер использует
      глобальный журнал.
- [ ] **Overlap нескольких district'ов**: выбираем ближайший к центру
      через `bestMatch.dist`. Шаг 2.
- [ ] **Popup открыт, новое событие пришло из tasks.jsonl/git**: SidePanelView
      переотрисуется через @ObservedObject. Поле ввода popup — `@State` в
      `TaskInputPopupView`, не теряется. Журнал в SidePanel обновится
      автоматически.
- [ ] **Контекстный popup ушёл за границы окна** (например, клик у правого
      края) — clamp `ci.point` в `.onReceive`: `let clampedX = min(max(ci.point.x,
      160), windowWidth - 160)` (320pt ширина popup). Шаг 4.
- [ ] **Esc при открытом popup** — `.onKeyPress(.escape)` в ContentView.
      Шаг 4.
- [ ] **Title >255 символов** — `String(trimmed.prefix(255))`. Шаги 3, 5.
- [ ] **JournalWindowController закрыт во время ввода** — draft теряется
      (по AC ожидаемо).
- [ ] **Hot-pathreplay** — journal-события идут через apply() как все
      taskCompleted, без особой ветки.

### Файлы для изменения

- `Sources/CityDeveloper/UI/SceneBridge.swift` — добавить publisher.
- `Sources/CityDeveloper/Game/GameScene.swift` — district hit-test +
  helper.
- `Sources/CityDeveloper/UI/TaskInputPopupView.swift` — новый View.
- `Sources/CityDeveloper/App/ContentView.swift` (или эквивалент) —
  overlay + onReceive.
- `Sources/CityDeveloper/UI/SidePanelView.swift` — inputSection.

### Файлы НЕ трогать

- `Game/CityEngine.swift` — `ingestTaskCompletion` уже подходит, не трогаем.
- `App/JournalWindowController.swift` — окно как контейнер, его не трогаем
  (только содержимое SidePanelView).
- `UI/InspectorOverlayCard.swift` — оставляем (reference для стиля, не
  трогаем).
- `Game/InspectorPanel.swift` — SpriteKit-попап для юнита, не трогаем.
- `Data/CityState.swift`, `Data/GameEvent.swift` — не меняем модель.
- `Game/DistrictPlanner.swift` — размещение, не трогаем.
- `Data/EventLog.swift`, `Data/StateSnapshot.swift` — не трогаем формат.

### Команды проверки (для DoD)

- Компиляция: `swift build`.
- Ручная проверка:
  1. Запустить приложение, открыть journal (кнопка `list.bullet`).
  2. В новой секции «Добавить задачу» ввести `купил продукты`, выбрать
     «Создать новый…», имя `household`, кнопка Add → юнит появляется в
     новом квартале `household`.
  3. В explore-режиме кликнуть в пустую часть квартала `household` →
     popup «Добавить задачу к проекту household» → ввести `позвонил
     врачу` → Enter → юнит в том же квартале.
  4. Esc / клик в произвольное место — popup закрывается без записи.
  5. Удалить `~/Library/Application Support/CityDeveloper/{events.jsonl,state.json}`,
     перезапустить — все добавленные через journal задачи теряются
     (replay из пустого лога). Это ожидаемо.

### Сложность

`middle`

**Обоснование:** 5 файлов в 3 слоях (UI + Game + App), новый Combine
publisher, diamond-hit-test геометрия, popup-overlay положение с clamp,
draft-pattern с подвалидацией, Esc-handling. Не junior — диамантный
hit-test и SceneBridge publisher требуют понимания нескольких подсистем
(SpriteKit, Combine, SwiftUI). Не senior — нет архитектурного рефактора,
нет security/perf.

### Ожидаемое время

M (≤1д)

> Примечание: M в нижней части (≈4–6ч). Если diamond hit-test или
> popup-clamp окажется тонкой — может уйти в верхнюю половину M.

---

## ✅ Исполнение

_Исполнитель: sonnet_
_Сложность: middle_ (определит лид)

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Done-критерий F-17 проверен в реальном использовании: глобальный
      журнал + контекстный клик + replay восстановления.

#### Технические
- [ ] Компиляция Swift без новых ошибок/варнингов
- [ ] Существующие тесты F-03 / F-06 / F-11 / F-12 не сломаны
- [ ] Snapshot+tail replay с journal-событиями даёт идентичную карту

#### Обновление документации
- [ ] `Current.md`: F-17 → ✅
- [ ] `Diff.md`: D-17 удалён
- [ ] Новые идеи → `Backlog.md`, баги → `Bugs.md`

---

## Статус

`[x] done`

## Метаданные
- Создана PM: 2026-05-22
- Spec-review: approved (round 1)
- Готова к работе: 2026-05-22
- Lead-model: opus
- Plan-review: approved-with-notes (3 ревизии применены: SpriteKit convert API, координаты через GeometryReader+focusable, Combine import + InputRequest struct)
- Lead-trigger: opus (priority P1, multi-module UI+Game+App)
- Исполнитель: sonnet
- Завершена: 2026-05-23
- Code-review: approved (sonnet, inline)
- Коммит: —
