# TASK-007: Боковая панель «Список проектов + Журнал событий» с фильтрами

## Связь
- **F-11** Инспектор / журнал событий
- **D-11** (закрывает остаток: попап по клику уже сделан в `Game/InspectorPanel.swift`
  + `GameScene.handleClick`)
- **Приоритет:** P1

**Примечание о скоупе F-11:** TASK-007 закрывает остаток D-11 **частично**:
попап по клику (уже сделано), боковая панель со списком проектов (с stage / decay /
unitIds.count / lastActivityAt), журнал событий `taskCompleted` с фильтрами по
проекту и диапазону дат. **Не делает:**
- «Население» в карточке проекта — требует нового поля `ProjectState.population` и
  формулы (связано с F-10 «жители»). Вынесено в **TASK-014** (deferred, split-needed).
- «Фильтр по типу события» в журнале — требует чтобы системные события
  (`unit_built`, `stage_up`, `decay_tick`, `fire`, `restore`, `ruins_cleared`)
  начали писаться (это TASK-008 для decay + отдельная работа для unit_built/stage_up).
  Вынесено в **TASK-015** (deferred, split-needed, depends on TASK-008).

После завершения TASK-007 F-11 в `Current.md` остаётся **⚠️** (частично) — полное
✅ возможно только после TASK-014 + TASK-015. `Concept.md` НЕ правится.

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим

Дореализовать F-11 до Done-критерия концепта: в explore-режиме показать справа
выезжающую боковую панель со списком активных проектов и хронологическим журналом
событий с фильтрами по проекту и дате. Сейчас работает только попап по клику; без
журнала пользователь не может ответить на вопрос «что я делал в этом проекте в марте».
Это закрывает D-11.

### Пользовательский сценарий

1. Запускаю CityDeveloper, нажимаю ⌘⌥G — окно переходит в explore-режим.
2. Справа плавно выезжает боковая панель (≈180 ms) с двумя секциями.
3. Верхняя секция — список карточек проектов: имя, число юнитов, stage, дата
   последней активности, цветная полоса слева, отражающая decayLevel.
4. Нижняя секция — журнал: «дд.мм.гггг HH:mm — Проект — Заголовок задачи»,
   по убыванию даты. По умолчанию — все события, все проекты.
5. Над журналом выбираю проект из выпадающего списка («Все проекты» или конкретный)
   и/или диапазон дат («с» / «по») — журнал перефильтровывается мгновенно
   (≤ 50 ms на 5000 событий на M-серии Mac), без кнопки «Применить».
6. Кликаю по карточке проекта — камера плавно центрируется на районе этого проекта.
7. Кликаю по записи журнала — камера плавно центрируется на соответствующем юните,
   попап-инспектор открывается над юнитом.
8. Сворачиваю панель кнопкой-стрелкой; остаётся узкая полоска (20 pt), по клику на
   неё панель разворачивается обратно.
9. Возвращаюсь в behind-режим (⌘⌥G) — панель полностью скрывается одновременно с
   опусканием окна; значения фильтров и состояние свёрнутости сохраняются в памяти.

### Acceptance criteria

- [ ] В explore-режиме у правого края окна видна SwiftUI-панель шириной 320 pt,
      примыкающая к правому краю; в behind-режиме панель полностью скрыта (нет в
      иерархии или `opacity = 0`).
- [ ] Переход между состояниями панели (explore↔behind, развёрнуто↔свёрнуто)
      идёт через анимацию 180 ms easeOut, синхронно с переключением режима окна.
- [ ] В верхней секции «Проекты» отображаются **все** проекты из
      `CityEngine.state.projects`, отсортированные по `lastActivityAt` по убыванию;
      при равном значении — по `name` по возрастанию.
- [ ] Карточка проекта содержит: имя, число юнитов (`unitIds.count`), stage
      (`stage`), дату последней активности в формате «dd.MM.yyyy» (`DateFormatter`,
      `locale = ru_RU`, `timeZone = .current`), вертикальную цветную полосу слева
      шириной 4 pt: `success` при `decayLevel == 0`, `warning` при
      `decayLevel ∈ {1,2}`, `danger` при `decayLevel ≥ 3`.
- [ ] В нижней секции «Журнал» отображаются события из `EventLog.readAll()` с
      `kind == .taskCompleted`, отсортированные по `ts` по убыванию.
- [ ] Над журналом два UI-фильтра:
  - `Picker` «Проект» — по умолчанию «Все проекты», далее список имён проектов в
    алфавитном порядке (русская локаль для сортировки).
  - Пара `DatePicker` «с» / «по» (`.field` style, `displayedComponents: .date`).
    **Дефолты вычисляются один раз при первом открытии панели в сессии**:
    `from = floor(min(event.ts))`, `to = ceil(max(event.ts))` (либо обе =
    `Date.now` если лог пуст). При появлении новых событий дефолты не
    пересчитываются — пользовательский диапазон не должен «прыгать».
- [ ] При изменении любого фильтра журнал перефильтровывается мгновенно
      (без кнопки «Применить»). Порог приемлемости: ≤ 50 ms на 5000 событий на
      M-серии Mac; превышение — фиксировать в `Bugs.md`.
- [ ] Формат строки журнала: `«dd.MM.yyyy HH:mm  Проект  Заголовок задачи»`,
      `DateFormatter` с `locale = ru_RU`, `timeZone = .current`, секунды
      не выводятся.
- [ ] Клик по карточке проекта плавно (≈ 400 ms, easeOut) центрирует
      SpriteKit-камеру (`cameraNode.position`) на изометрической позиции
      `districtOrigin` этого проекта.
- [ ] Клик по записи журнала плавно (≈ 400 ms, easeOut) центрирует камеру на
      юните, соответствующем событию, и открывает попап-инспектор над ним.
- [ ] **Стратегия поиска юнита по записи журнала:**
  1. Если в `GameEvent.taskId != nil` — искать юнит с тем же `taskId`. Поле
     `UnitState.taskId` отсутствует в текущей модели → его нужно либо добавить как
     зависимость TASK-007, либо использовать только fallback (см. п. 2). Этот выбор
     — за лидом.
  2. Fallback: первый юнит, для которого
     `project == event.project && taskTitle == event.title && |unit.taskTs − event.ts| < 1.0 s`.
  3. Если не найден — клик ничего не делает (короткий тост «Юнит не найден»
     допустим, но не обязателен).
- [ ] **Механизм обновления журнала и карточек проектов при поступлении новых
      событий:** `CityEngine` публикует обновления state через `@Published var state`
      (уже есть в коде) и/или новый колбэк / `Combine`-publisher на каждое
      `apply(event)`. Боковая SwiftUI-панель подписывается через `@ObservedObject` /
      `@StateObject` на `CityEngine` и автоматически перестраивает оба списка при
      изменении. **Источник истины для журнала** — `EventLog.readAll()` при первом
      открытии панели + incremental append при новых событиях (через тот же
      publisher). Не делать polling по таймеру.
- [ ] Панель можно свернуть кнопкой-стрелкой (SF Symbol `chevron.right.2` /
      `chevron.left.2`, 20×20 pt в правом верхнем углу шапки); в свёрнутом
      состоянии остаётся вертикальная полоса 20 pt с обратной иконкой; клик на
      неё раскрывает панель.
- [ ] При появлении нового события (новая строка в `tasks.jsonl`) журнал и
      метрики проектов обновляются автоматически через механизм п. выше.
- [ ] При пустом городе (нет проектов и событий) обе секции показывают
      placeholder: «Город пуст» / «Событий пока нет»; фильтры неактивны (disabled).

### Что НЕ делаем (границы скоупа)

- Не меняем формат `events.jsonl` и `tasks.jsonl`.
- В журнале **не показываем системные события** в этой задаче. Системные события
  + фильтр по типу — это **TASK-015** (deferred).
- **Поле «население» в карточке проекта не показываем в этой задаче** — это
  **TASK-014** (deferred, требует разбиения: новое поле модели + формула расчёта).
  Концепт F-11 не правится; F-11 после TASK-007 остаётся ⚠️.
- Не делаем экспорт журнала в CSV/PDF/Markdown.
- Не делаем поиск по тексту задачи (только фильтр проект + диапазон дат).
- Не делаем виртуализацию списка (`LazyVStack` достаточно; полная виртуализация под
  10k+ событий — отдельная задача).
- Не трогаем существующий попап-инспектор (`InspectorPanel.swift`) и `handleClick`
  в `GameScene` — переиспользуем как есть.
- Не персистим состояние панели (свёрнута/нет, выбранный проект, диапазон дат)
  между запусками — только в памяти текущей сессии.

### Edge cases

- [ ] **Пустой город** (нет проектов и событий): обе секции показывают
      placeholders, фильтры disabled.
- [ ] **5000+ событий:** `LazyVStack` рендерится без заметных лагов; фильтрация
      должна укладываться в ≤ 50 ms. При просадке — зафиксировать в `Bugs.md`,
      оптимизация — отдельная задача.
- [ ] **Активный фильтр + переключение режима behind→explore:** фильтр и состояние
      свёрнутости сохраняются в `@State` / `@StateObject` панели; при возврате в
      explore значения те же, что были.
- [ ] **Выбранный в Picker проект исчез из state** (теоретически — если когда-то
      появится переименование): Picker откатывается на «Все проекты», журнал
      перестраивается.
- [ ] **У проекта нет `districtOrigin`** (если такое возможно из-за гонки при
      ingestion): клик по карточке игнорируется (или короткий тост «Район ещё не
      определён»), без падения.
- [ ] **Юнит не найден по записи журнала** (см. стратегию поиска): клик ничего не
      делает, попап-инспектор не показывается, приложение не падает.
- [ ] **Камера уже на нужном юните/проекте:** анимация всё равно отрабатывает
      плавно (без рывка); если `from == to`, `SKAction.move(to:)` корректно
      завершается за указанную длительность.
- [ ] **Часовые пояса:** `GameEvent.ts` хранится как `Date` (внутренний UTC при
      iso8601 encoding/decoding); отображение в журнале и фильтр-датапикерах —
      через `DateFormatter` с `locale = ru_RU`, `timeZone = .current`.
- [ ] **Дата «с» позже «по»:** журнал показывает пусто; над ним подсказка
      «Диапазон пуст».
- [ ] **Несколько событий с одинаковым `ts`:** сохраняют относительный порядок из
      `EventLog.readAll()` (порядок записи в файле).
- [ ] **Огромный диапазон дат** (10+ лет): `DatePicker` ограничивается `minDate =
      min(event.ts)`, `maxDate = max(event.ts) + 1 day` для удобства; за пределами
      ограничения выбор недоступен.

### Зависимости

- **F-03** (`EventLog`) — журнал берёт данные через публичный API
  `EventLog.readAll()`. Если такого API нет — добавить (минимальная правка).
- **F-04** (watcher) — добавление новой задачи в `tasks.jsonl` приводит к
  `CityEngine.ingestTaskCompletion(...)`, что должно триггерить обновление панели.
  Реализуется через `@Published`/`Combine` publisher на `CityEngine` (см. AC).
- **F-01** (window mode) — панель встраивается в `NSHostingView` поверх
  SpriteKit-сцены, реагирует на переход explore↔behind через `WindowModeManager`
  (через `@Published` свойство или `NotificationCenter`-сигнал).
- **Существующая модель данных:** `CityState`, `ProjectState`, `UnitState`,
  `GameEvent`, `CityEngine.onUnitBuilt`, `CityEngine.state`.
- **Возможная правка модели:** добавление `UnitState.taskId: String?` для надёжной
  привязки события журнала к юниту (см. AC «Стратегия поиска»). Если лид решит
  обойтись fallback — правка модели не нужна.
- **Палитра:** в `Theme/Palette.swift` добавить семантические токены `success`,
  `warning`, `danger`, `info` из `DesignConcept.md`.

### Дизайн

Из `DesignConcept.md`:

**Side Panel:**
- Ширина: `320 pt` fixed (свёрнуто — `20 pt`).
- Фон: `parchment` 95% opacity, blur background (`Material.regularMaterial`).
- Скролл: нативный SwiftUI `ScrollView` / `LazyVStack`, без видимой полосы по
  умолчанию.
- Скругление: `radiusM` = 10 pt только у левого края (правый край примыкает к окну).
- Анимация раскрытия / скрытия: 180 ms easeOut (как переключение wallpaper↔explore).

**Project Card:**
- Фон: `sandLight`.
- Скругление: `radiusM` = 10 pt.
- Внутренние отступы: `padS` = 8 pt (вертикально), `padM` = 16 pt (горизонтально).
- Заголовок: 13 pt Semibold `inkDark`, sentence case.
- Метрики (число юнитов, stage, дата): 11 pt Regular `inkDark` 60% (caption).
- Decay-индикатор: вертикальная полоса слева, ширина 4 pt, высота карточки;
  цвет — `success` / `warning` / `danger` по уровню decay.

**Журнал-строка:**
- Timestamp: `SF Mono` 11 pt `inkDark` 60%.
- Project: 11 pt Semibold `inkDark` 80%.
- Title: 11 pt Regular `inkDark` 85%.
- Разделитель между строками: 1 pt линия `inkDark` 12% opacity.
- Отступы: `padS` = 8 pt вертикально, `padM` = 16 pt горизонтально.

**Шапка панели:**
- Заголовки секций «Проекты» / «Журнал»: 13 pt Semibold uppercase letter-spacing
  +0.5, цвет `inkDark`.
- Кнопка свернуть/развернуть: SF Symbol `chevron.right.2` / `chevron.left.2`,
  20×20 pt, правый верхний угол шапки.

**Фильтры:**
- `Picker` `.menu` style.
- `DatePicker` `.field` style, `displayedComponents: .date`, `locale = ru_RU`.

### Done-критерий

_Из `Concept.md` F-11 (дословно):_ Клик на любой юнит открывает попап с текстом
задачи, датой и проектом. Журнал поддерживает фильтр по проекту и диапазону дат.
Боковая панель показывает все активные проекты с актуальными метриками.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-22_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния
- `Game/InspectorPanel.swift` + `Game/GameScene.swift` (`handleClick`/`showInspector`/`hideInspector`) — попап-инспектор по клику. Переиспользуем как есть.
- `Game/CityEngine.swift` — `@Published private(set) var state: CityState` уже есть; есть `onUnitBuilt`, `onProjectCreated`. Нет `@Published events: [GameEvent]`.
- `Data/EventLog.swift` — `readAll() -> [GameEvent]` существует (подтверждено).
- `App/WindowModeManager.swift` — методы `enterBehindMode()` / `enterExploreMode()` / `toggle()`. Нет `@Published isExplore: Bool`.
- `UI/ContentView.swift` — простой SwiftUI host для `SpriteView(scene:)` (143 байта файл).
- `Theme/Palette.swift` — нет семантических токенов `success/warning/danger/info`.
- `App/AppDelegate.swift` — биндит `engine.onUnitBuilt → scene.placeUnit`; через `NSHostingView(rootView: ContentView(scene: scene))` подключает SwiftUI.

### Архитектурное решение
Боковая панель — отдельная SwiftUI-View, биндится к `CityEngine` через `@ObservedObject`. `CityEngine` уже `ObservableObject` (есть `@Published state`); добавим `@Published private(set) var events: [GameEvent]`, при `apply(event)` приращиваем массив; при init — `events = eventLog.readAll()`. `WindowModeManager` становится `ObservableObject` с `@Published var isExplore: Bool`. `ContentView` расширяется до `HStack { SpriteView(scene) ; if mgr.isExplore { SidePanelView() } }`. Камерные команды — через callback-closures, прокинутые от `SidePanelView` в `GameScene` через тонкий `SceneBridge`. Это держит SpriteKit и SwiftUI разделёнными, без необходимости вытягивать GameScene в SwiftUI environment.

По стратегии поиска юнита из журнала — используем **только fallback** (`project + title + |ts diff| < 1s`); поле `UnitState.taskId` не добавляем (есть `taskTitle + taskTs` — достаточно для уникальности в текущей модели; добавление `taskId` — отдельная задача когда понадобится для жёсткой привязки).

### Пошаговая декомпозиция

1. **Палитра: добавить семантические токены** `[AC:4]`
   - Файл: `Sources/CityDeveloper/Theme/Palette.swift`
   - Метод/блок: расширение `enum Palette`
   - Добавить: `static let success = SKColor(hex: 0x4A8F3E)` (через `init(red:green:blue:alpha:)`), аналогично `warning #D49B2A`, `danger #B43A20`, `info #3C6A8C`. Также SwiftUI-обёртки `Color(success)`, и т.д. через расширение `Color(_ sk: SKColor)`.

2. **CityEngine: публикуемый список событий** `[AC:5,7,17]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`
   - Метод/блок: класс целиком
   - Добавить: `@Published private(set) var events: [GameEvent] = []`. В `init` после `replayFromLog()` — `self.events = eventLog.readAll()`. В `ingestTaskCompletion(...)` после `eventLog.append(event)` — `events.append(event)` и `apply(event)` (порядок: append events → apply state).
   - Edge: `apply(_:silent:)` вызывается и из replay, и из ingest — replay уже наполняет events через `eventLog.readAll()` в init, второй раз заполнять не надо. Поэтому: append в `events` делать только в `ingestTaskCompletion`, не в `apply`.

3. **WindowModeManager как ObservableObject** `[AC:2]`
   - Файл: `Sources/CityDeveloper/App/WindowModeManager.swift`
   - Класс → `final class WindowModeManager: ObservableObject`. Добавить `@Published private(set) var isExplore: Bool = false`. В `enterExploreMode()` — `isExplore = true`. В `enterBehindMode()` — `isExplore = false`.

4. **SceneBridge — мост SwiftUI → SpriteKit** `[AC:9,10]`
   - Файл: `Sources/CityDeveloper/UI/SceneBridge.swift` (новый)
   - Скелет:
     ```swift
     final class SceneBridge: ObservableObject {
         weak var scene: GameScene?
         func focusOn(gridPoint: GridPoint) { scene?.focusCamera(on: gridPoint, duration: 0.4) }
         func focusOnUnit(_ unit: UnitState) {
             scene?.focusCamera(on: unit.position, duration: 0.4)
             scene?.showInspector(forUnitId: unit.id)
         }
     }
     ```

5. **GameScene: публичные API для камеры и инспектора** `[AC:9,10]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift`
   - Добавить `func focusCamera(on grid: GridPoint, duration: TimeInterval)` — `SKAction.move(to: isoPosition(grid:), duration:)` с `.easeOut`.
   - Добавить `func showInspector(forUnitId id: UUID)` — внутри ищем `unitNodes[id]` + `engine?.state.units[id]` + `engine?.state.projects[unit.projectId]` → `showInspector(near:unit:project:)` (private уже есть, сделать internal).

6. **ProjectCard SwiftUI-View** `[AC:4]`
   - Файл: `Sources/CityDeveloper/UI/ProjectCard.swift` (новый)
   - Сигнатура: `struct ProjectCard: View { let project: ProjectState; let onTap: () -> Void }`
   - Реализация: `HStack` с decay-полосой 4pt слева (цвет по `project.decayLevel` через switch), `VStack(alignment: .leading)` с именем, числом юнитов, stage, датой `lastActivityAt`. Тап на всю карточку → `onTap()`.

7. **SidePanelView — основная SwiftUI-View панели** `[AC:1,3,4,5,6,7,8,16,17]`
   - Файл: `Sources/CityDeveloper/UI/SidePanelView.swift` (новый)
   - Скелет:
     ```swift
     struct SidePanelView: View {
         @ObservedObject var engine: CityEngine
         @ObservedObject var bridge: SceneBridge
         @State private var collapsed = false
         @State private var selectedProject: String? = nil  // nil = «Все проекты»
         @State private var dateFrom: Date = Date()
         @State private var dateTo: Date = Date()
         @State private var didInitDates = false
         var body: some View { ... }
     }
     ```
   - Внутри `body`: при `collapsed == true` — `VStack` шириной 20pt с chevron-кнопкой развернуть. Иначе — `VStack` шириной 320pt с `parchment + Material.regularMaterial`, далее header «Проекты» + ScrollView со списком `ProjectCard`, далее header «Журнал» + фильтры (`Picker` + 2× `DatePicker`) + `ScrollView` + `LazyVStack` со строками журнала.
   - Дефолт дат вычисляется в `.onAppear` при `!didInitDates && !engine.events.isEmpty`: `dateFrom = min(events.ts)`, `dateTo = max(events.ts)`, `didInitDates = true`.
   - Фильтрация: `let filtered = engine.events.filter { e in e.kind == .taskCompleted && (selectedProject == nil || e.project == selectedProject!) && e.ts >= dateFrom && e.ts <= dateTo.endOfDay }`.

8. **Поиск юнита из записи журнала (fallback)** `[AC:10]`
   - Файл: `Sources/CityDeveloper/UI/SidePanelView.swift`
   - Помощник: `func findUnit(for event: GameEvent, in state: CityState) -> UnitState? { state.units.values.first { $0.projectId == event.project && $0.taskTitle == event.title && abs($0.taskTs.timeIntervalSince(event.ts)) < 1.0 } }`. При `nil` — `bridge.focusOn(gridPoint: project.districtOrigin)` (если проект найден), иначе клик игнорируется.

9. **ContentView: интеграция HStack + анимация** `[AC:1,2]`
   - Файл: `Sources/CityDeveloper/UI/ContentView.swift`
   - Сигнатура изменится: `ContentView(scene: GameScene, engine: CityEngine, modeManager: WindowModeManager, bridge: SceneBridge)`.
   - Тело:
     ```swift
     HStack(spacing: 0) {
         SpriteView(scene: scene).frame(maxWidth: .infinity, maxHeight: .infinity)
         if modeManager.isExplore {
             SidePanelView(engine: engine, bridge: bridge)
                 .transition(.move(edge: .trailing))
         }
     }
     .animation(.easeOut(duration: 0.18), value: modeManager.isExplore)
     ```

10. **AppDelegate: создать bridge и прокинуть** `[AC:9,10]`
    - Файл: `Sources/CityDeveloper/App/AppDelegate.swift`
    - После создания `engine`, `scene`, `modeManager` — создать `bridge = SceneBridge(); bridge.scene = scene`.
    - `NSHostingView(rootView: ContentView(scene: scene, engine: engine, modeManager: modeManager, bridge: bridge))`.

### Edge cases (явно обработать)
- [ ] Пустой город: `engine.events.isEmpty && engine.state.projects.isEmpty` → placeholders «Город пуст» / «Событий пока нет», `Picker` и `DatePicker` `disabled(true)`. Проверка в `body` `SidePanelView`.
- [ ] Выбранный проект удалён из `state.projects` (теоретически): в `.onChange(of: engine.state.projects)` — если `selectedProject != nil && state.projects[selectedProject!] == nil` → `selectedProject = nil`.
- [ ] Юнит не найден по событию: `findUnit(...) == nil` → если проект найден — `bridge.focusOn(districtOrigin)`, инспектор не открываем; иначе клик no-op.
- [ ] `districtOrigin` отсутствует — невозможно в текущей модели (`GridPoint` не optional). Если в будущем станет optional — добавить guard.
- [ ] `dateFrom > dateTo`: фильтр вернёт пусто; в `body` показать `Text("Диапазон пуст")` если `filtered.isEmpty && !engine.events.isEmpty`.
- [ ] TZ: `DateFormatter.locale = .init(identifier: "ru_RU"); timeZone = .current`. Формат `dd.MM.yyyy HH:mm`. Хранение в `dateOnly` helper для удобства фильтра.
- [ ] Behind-режим: `modeManager.isExplore == false` → панель отсутствует в иерархии (через `if`). При возврате `@State` `collapsed/selectedProject/dateFrom/dateTo` сохранены, т.к. `SidePanelView` сохраняется по identity (SwiftUI `if` пересоздаёт — нужен `@StateObject` обёртка `SidePanelStateHolder` или `@State` поднять выше, в ContentView). **Решение:** поднять `@State` в ContentView, передавать как `@Binding`.

### Файлы для изменения
- `Sources/CityDeveloper/Theme/Palette.swift` — добавить семантические токены
- `Sources/CityDeveloper/Game/CityEngine.swift` — `@Published events`
- `Sources/CityDeveloper/App/WindowModeManager.swift` — `ObservableObject + @Published isExplore`
- `Sources/CityDeveloper/Game/GameScene.swift` — публичные `focusCamera`, `showInspector(forUnitId:)`
- `Sources/CityDeveloper/UI/ContentView.swift` — HStack + анимация
- `Sources/CityDeveloper/App/AppDelegate.swift` — создать bridge, прокинуть

### Файлы НЕ трогать
- `Sources/CityDeveloper/Game/InspectorPanel.swift` — попап работает, не меняем сигнатуру
- `Sources/CityDeveloper/Data/EventLog.swift` — публичный API `readAll()` уже есть
- `Sources/CityDeveloper/Data/GameEvent.swift`, `CityState.swift` — модель не меняем
- `Sources/CityDeveloper/Data/TasksJsonlWatcher.swift` — watcher на месте

### Новые файлы
- `Sources/CityDeveloper/UI/SceneBridge.swift`
- `Sources/CityDeveloper/UI/SidePanelView.swift`
- `Sources/CityDeveloper/UI/ProjectCard.swift`

### Команды проверки (для DoD)
- Компиляция: `swift build` (в корне проекта)
- Запуск: `swift run CityDeveloper`
- Ручная проверка:
  1. ⌘⌥G — панель выезжает справа (~180ms).
  2. Карточки проектов: видны все, decay-полоса корректного цвета.
  3. Журнал отсортирован по убыванию даты.
  4. Picker «Проект» переключается → журнал перефильтровывается.
  5. DatePicker «с»/«по» — журнал обновляется.
  6. Клик по карточке → камера плавно двигается на квартал.
  7. Клик по записи журнала → камера на юнит + попап.
  8. ⌘⌥G обратно → панель исчезает.
- Перф-тест: добавить 5000 событий через скрипт в `tasks.jsonl`, проверить FPS и время фильтрации.

### Сложность
`middle`

**Обоснование:** ≥ 5 файлов, новые SwiftUI-views, интеграция SwiftUI ↔ SpriteKit через bridge, биндинги между ObservableObject'ами. Без архитектурных рисков, но требует аккуратности.

### Ожидаемое время
M (≤ 1 день)

### Plan-review правки (round 1 → applied)

1. **CRITICAL — @State поднимается в ContentView, передаётся в SidePanelView через @Binding.**
   Скелет SidePanelView (шаг 7) — все `@State private var` заменить на `@Binding var`. ContentView (шаг 9) держит реальный `@State` (collapsed / selectedProject / dateFrom / dateTo / didInitDates) и пробрасывает `$`-binding'и. Это нужно потому что `if modeManager.isExplore { SidePanelView(...) }` пересоздаёт view при каждом возврате в explore — `@State` внутри SidePanelView сбросится. Подъём в ContentView сохраняет фильтры между переключениями режима.

2. **showInspector(near:unit:project:) → убрать `private`** (сделать `internal`), иначе SceneBridge.focusOnUnit не скомпилируется. См. шаг 5.

3. **ContentView должен принимать modeManager как `@ObservedObject`** (не `let`), иначе SwiftUI не отреагирует на смену isExplore.

4. **`Date.endOfDay` extension** — добавить отдельным шагом (новый файл `UI/DateExtensions.swift`):
   ```swift
   extension Date {
       var endOfDay: Date {
           Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: self) ?? self
       }
   }
   ```

5. **Status/StatusBarController.swift — в «НЕ трогать»** (получает modeManager как plain class — не трогать сигнатуру).

6. **findUnit fallback при двух nil:** добавить `guard event.title != nil else { return nil }` — иначе два события без title могут перепутать юнитов.

7. **AC#5 sort:** в body SidePanelView явно `engine.events.sorted { $0.ts > $1.ts }.filter { ... }`.

---

## ✅ Исполнение

_Исполнитель: sonnet_
_Сложность: middle_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Done-критерий проверен в реальном использовании: панель видна в explore,
      скрывается в behind, фильтры работают, клик по проекту/событию двигает камеру

#### Технические
- [ ] `swift build` без новых ошибок и варнингов
- [ ] Цвета берутся из `Palette` (включая добавленные `success` / `warning` /
      `danger` / `info`)
- [ ] Даты форматируются через единый `DateFormatter` (locale = ru_RU,
      timeZone = .current)

#### Обновление документации
- [ ] `current.md`: F-11 остаётся ⚠️ (закрыто частично; полное ✅ после
      TASK-014 + TASK-015)
- [ ] `diff.md`: D-11 переформулирован — «остаток: население per-project
      (TASK-014) + фильтр по типу события (TASK-015)»
- [ ] При просадке производительности на 5000+ событиях — запись в `bugs.md`

---

## Статус

`[x] done`

## Метаданные
- Создана PM: 2026-05-22
- Spec-review: needs-revision → applied → approved (round 2)
- Lead-model: opus
- Plan-review: needs-revision → applied (round 1)
- Сложность: middle
- Готова к работе: 2026-05-22
- Завершена: 2026-05-22
- Code-review: approved (opus)
- Коммит: —
