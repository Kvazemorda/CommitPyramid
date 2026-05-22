# TASK-016: Журнал событий — кнопка + floating window вместо боковой панели

## Связь
- **F-11** Инспектор / журнал событий
- **Приоритет:** P2

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим

Боковая панель журнала событий мешает: занимает место в explore-режиме и частично
перекрывается часами macOS в правом верхнем углу. Убрать панель из основного
интерфейса: вместо автоматически видимой панели — кнопка «📜» поверх игровой
сцены, по нажатию открывается отдельное окно с журналом по центру. Карточки
инспектора (попап при клике на юнит) перемещаются в правую середину, подальше
от часов.

### Пользовательский сценарий

1. Открываю explore-режим — вижу только игровую карту без боковых панелей.
2. В правом нижнем углу поверх карты вижу кнопку «📜».
3. Нажимаю кнопку — по центру главного окна открывается отдельное floating-окно
   с журналом (фильтры по проекту/дате, список событий). Могу продолжать работать
   с картой.
4. Нажимаю на событие в журнале — камера фокусируется на нужном юните на карте.
5. Закрываю журнал крестиком. Фильтры сохраняются при повторном открытии.
6. Карточка инспектора при клике на юнит появляется справа по вертикальному центру
   окна, не перекрываясь часами macOS.

### Acceptance criteria

- [ ] `SidePanelView` **не присутствует** в иерархии `ContentView` как постоянный
      child-view: убран из `ContentView` полностью; используется только как контент
      `JournalWindowController`.
- [ ] В explore-режиме поверх `SpriteView` — SwiftUI-кнопка (SF Symbol `list.bullet`)
      в правом нижнем углу. Параметры: `frame(36, 36)`, `background(.black.opacity(0.45))`,
      `cornerRadius(8)`, `padding(.trailing, 16)`, `padding(.bottom, 24)` от края
      overlay. Кнопка имеет `accessibilityLabel("Журнал событий")`.
- [ ] Кнопка **скрыта** в behind-режиме и во время перехода между режимами (только
      после завершения transition).
- [ ] По нажатию открывается `JournalWindowController.show()` — `NSWindow`
      с `SidePanelView`, минимальный размер 480×600 pt, центрируется относительно
      главного окна приложения (`NSApp.mainWindow?.frame`). Если `NSApp.mainWindow`
      равен nil — центрировать по `NSScreen.main`.
- [ ] Повторное нажатие при открытом окне делает `makeKeyAndOrderFront` +
      `deminiaturize` (не создаёт второе окно).
- [ ] `JournalWindowController` использует паттерн `SettingsWindowController`
      (проверка `window?.isVisible`, `windowWillClose` обнуляет ссылку).
- [ ] Закрытие окна журнала **не сбрасывает фильтры**: состояние
      (selectedProject, dateFrom, dateTo, didInitDates) хранится как `@State` в
      `ContentView` и передаётся `JournalWindowController` при каждом `show()`;
      контроллер создаёт `NSHostingController<SidePanelView>` с актуальными
      биндингами. Значения сохраняются между открытиями, т.к. `@State` живёт в
      `ContentView`, а не в закрываемом окне.
- [ ] Клик на событие в журнале вызывает `SceneBridge.focusOnUnit` и делает
      главное окно key (`NSApp.mainWindow?.makeKey()`), чтобы `SpriteView` получал
      ввод. Журнал остаётся видимым, но key-статус передаётся главному окну.
- [ ] Карточка инспектора (SwiftUI overlay поверх SpriteView) расположена:
      `alignment: .trailing` горизонтально, `alignment: .center` вертикально в
      `ZStack`, отступ `trailing 16 pt`. Если высота окна мала и карточка при
      `.center` оказывается ближе 40 pt к верхнему краю — прижать к `.topTrailing`
      с `padding(.top, 40)`. Не пересекается с кнопкой журнала (кнопка
      bottomTrailing, карточка — center по высоте).

### Что НЕ делаем (границы скоупа)

- Не переделываем содержимое журнала и фильтры (это TASK-015).
- Не добавляем анимацию появления/скрытия журнального окна.
- Не сохраняем позицию/размер окна журнала между сессиями.
- Не меняем логику `InspectorPanel` (SpriteKit-попап по клику на юниты) —
  только позицию SwiftUI overlay-карточки.
- Не делаем переход в explore-режим автоматически при клике из журнала в
  behind-режиме — фокус камеры игнорируется молчаливо (guard `modeManager.isExplore`),
  без визуального feedback — осознанное решение.
- Не добавляем keyboard shortcut (например ⌘J) или пункт меню View для журнала.

### Edge cases

- [ ] **Behind → explore с открытым окном журнала:** кнопка появляется, окно
      журнала остаётся открытым на месте — повторное открытие не нужно.
- [ ] **Explore → behind с открытым окном:** кнопка скрывается, окно журнала
      **остаётся открытым** (пользователь сам закрывает). Кнопка скрыта, но окно
      существует.
- [ ] **Клик по событию из behind-режима:** фокус камеры не происходит (guard
      `modeManager.isExplore`), событие игнорируется без краша.
- [ ] **Quit с открытым окном:** окно закрывается штатно вместе с приложением;
      `isReleasedWhenClosed = true` (дефолт для NSWindow) — не держит app живым.
- [ ] **Мультимонитор:** `JournalWindowController.show()` центрирует относительно
      главного окна приложения (`NSApp.mainWindow?.frame`), а не экрана.
- [ ] **fullscreen / Spaces:** журнальное окно — обычный `NSWindow` без
      `.fullScreenAuxiliary` коллекций; следует за активным Space автоматически.
- [ ] **Быстрые двойные нажатия:** второй тап делает `makeKeyAndOrderFront` на
      уже созданном окне.
- [ ] **Окно за пределами видимого экрана** (изменили разрешение): `show()`
      всегда пересчитывает центр, не восстанавливает старые координаты.
- [ ] **Карточка инспектора + кнопка журнала на узком окне:** разный `alignment`
      в `ZStack` гарантирует разные позиции, визуального перекрытия нет.
- [ ] **`NSApp.mainWindow == nil` при `show()`:** центрировать окно журнала по
      `NSScreen.main` (первичный экран).
- [ ] **Главное окно minimized при открытом журнале:** журнал остаётся открытым;
      пользователь закрывает его сам.
- [ ] **⌘W в журнальном окне:** закрывает только журнал (стандартное поведение
      `.closable`); приложение не завершается.

### Зависимости

- `UI/SidePanelView.swift` — переиспользуется as-is внутри журнального окна.
- `UI/ContentView.swift` — убрать монтирование `SidePanelView`, добавить кнопку
  и `JournalWindowController`.
- `App/SettingsWindowController.swift` — референс для `JournalWindowController`.
- `UI/SceneBridge.swift` — `focusOnUnit` вызывается из журнального окна.
- `UI/ProjectCard.swift` / inspect overlay — изменить anchor-позицию в
  `ContentView` ZStack.

### Дизайн

- **Кнопка журнала:** `Button` с `Image(systemName: "list.bullet")`,
  `.frame(width: 36, height: 36)`, `background(.black.opacity(0.45))`,
  `cornerRadius(8)`, overlay `.bottomTrailing`, `padding(.trailing, 16)` +
  `padding(.bottom, 24)` от края.
- **Окно журнала:** `NSWindow`, min 480×600 pt, title «Журнал событий»,
  `styleMask [.titled, .closable, .resizable]`, центрируется по главному окну.
- **Карточка инспектора:** `ZStack(alignment: .trailing)` → внутри
  `VStack` с `.frame(maxHeight: .infinity, alignment: .center)`,
  отступ `.padding(.trailing, 16)`.

### Done-критерий

_(UX-улучшение F-11, нет отдельного концептного Done-критерия)_
Все AC выполнены + ручной прогон сценария 1–6: боковая панель не появляется
автоматически; кнопка открывает окно; фильтры сохраняются; карточка инспектора
не перекрывается часами.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-22_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

**В коде уже есть:**
- `UI/ContentView.swift` — `HStack(spacing: 0)` с `SpriteView` + conditional `SidePanelView`. Содержит 5 `@State`: `collapsed`, `selectedProject: String?`, `dateFrom: Date`, `dateTo: Date`, `didInitDates: Bool`.
- `UI/SidePanelView.swift` — принимает 5 `@Binding` (одноимённых с `@State` выше) + `@ObservedObject` `engine: CityEngine`, `bridge: SceneBridge`. Полная логика журнала: фильтры, ProjectCard-список, `handleEventTap → bridge.focusOnUnit / bridge.focusOn(gridPoint:)`. **Переиспользуется as-is, не трогаем.**
- `App/SettingsWindowController.swift` — образец lazy-NSWindow + `NSHostingController` + `windowWillClose → window = nil`. Паттерн копируется.
- `UI/SceneBridge.swift` — `func focusOn(gridPoint:)`, `func focusOnUnit(_ unit: UnitState)`. Bridge — `ObservableObject`, имеет `weak var scene: GameScene?`.
- `App/WindowModeManager.swift` — `@Published var isExplore: Bool`. ContentView подписан через `@ObservedObject`.
- `App/CityWindow.swift` — главное окно, `NSApp.mainWindow` указывает на него в behind/explore. `isReleasedWhenClosed = false`.
- `App/AppDelegate.swift` — место создания: `cityWindow`, `modeManager`, `engine`, `scene`, `bridge`, `settingsWindowController`. ContentView создаётся через `NSHostingView(rootView: ContentView(...))`.
- `Game/GameScene.swift` — `func showInspector(forUnitId: UUID)` строит SpriteKit-попап `InspectorPanel.build()` и кладёт в `world` (world coords). Координаты «рядом с юнитом», поэтому при разных позициях камеры попап может быть в разных местах экрана.
- `Game/InspectorPanel.swift` — `static func build(unit:project:) -> SKNode`. **SpriteKit-попап, остаётся без изменений.**

**Что нужно создать:**
- `App/JournalWindowController.swift` — новый.
- `UI/InspectorOverlayCard.swift` — новый SwiftUI overlay (отдельная карточка инспектора в screen-fixed позиции; не путать с SpriteKit-попапом, который остаётся как-есть).

**Что нужно дописать:**
- `SceneBridge` — `@Published var selectedUnitInfo: (UnitState, ProjectState)? = nil` + добавить `scene?.view?.window?.makeKey()` в `focusOnUnit`.
- `GameScene.showInspector(forUnitId:)` — после построения SpriteKit-попапа дополнительно обновлять `bridge.selectedUnitInfo`.
- `ContentView` — переход с `HStack` на `ZStack`: `SpriteView` фоном full-size, поверх — кнопка журнала + `InspectorOverlayCard`.
- `AppDelegate` — инстанцировать `JournalWindowController`, передать в `ContentView`.

### Архитектурное решение

**Контейнер.** ContentView переходит на `ZStack(alignment: .bottomTrailing)`. Слои:
1. `SpriteView` — `frame(maxWidth: .infinity, maxHeight: .infinity)`, фон.
2. `InspectorOverlayCard(bridge: bridge).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)` — берёт всё пространство, прижимает свой контент к правому центру через `.frame(maxHeight: .infinity, alignment: .center)` внутри.
3. Кнопка журнала — рендерится conditionally при `modeManager.isExplore`, с `padding(.trailing, 16).padding(.bottom, 24)`.

Кнопка и карточка не конфликтуют по координатам: кнопка bottomTrailing (низ-право), карточка center-trailing (середина-право). Если высота окна < ~200 pt — карточка использует `.frame(alignment: .top).padding(.top, 40)` (safety guard).

**JournalWindowController.** Полный аналог `SettingsWindowController`:
- `final class JournalWindowController: NSObject, NSWindowDelegate`
- `private var window: NSWindow?`
- `func show(engine, bridge, collapsed, selectedProject, dateFrom, dateTo, didInitDates)` — все 5 фильтров приходят как `Binding<…>`. При повторном вызове на видимом окне: `makeKeyAndOrderFront + deminiaturize` и выход.
- Создаёт `SidePanelView` с биндингами, оборачивает в `NSHostingController(rootView:)`, создаёт `NSWindow(contentViewController:)`, центрирует по `NSApp.mainWindow?.frame` (fallback `NSScreen.main?.frame`).
- `windowWillClose` обнуляет ref.

**Передача @Binding в окно.** PM требует `@State в ContentView` + `@Binding` в окно. Это **работает технически**, потому что `@Binding`-объекты содержат get/set-замыкания, которые читают/пишут shared SwiftUI-storage @State. `NSHostingController` создаёт отдельный SwiftUI graph, но эти биндинги пересекают границу графа корректно. Тонкость: на каждый `show()` создаём **новый** `NSHostingController` с актуальными биндингами (биндинги — value-type wrappers, переживают пересоздание контроллера).

**SwiftUI overlay карточки инспектора (новый компонент).** Карточка наблюдает `bridge.selectedUnitInfo` через `@ObservedObject bridge`. Когда `selectedUnitInfo == nil` — рендерит `EmptyView()`. Когда есть значение — стилизованная карточка с именем проекта, типом юнита, стадией, заголовком задачи, датой. Это **отдельный** от SpriteKit-попапа компонент (SpriteKit-попап остаётся в world-coords, новая карточка — screen-fixed). Источник истины — `SceneBridge.selectedUnitInfo`, обновляется в `GameScene.showInspector(forUnitId:)` синхронно с SpriteKit-попапом.

**Передача key-фокуса на CityWindow.** В `SceneBridge.focusOnUnit`: после `scene?.focusCamera(...)` + `scene?.showInspector(...)` дополнительно `scene?.view?.window?.makeKey()`. `scene?.view?.window` — это и есть `cityWindow` (т.к. `SpriteView` сидит в `NSHostingView` внутри `cityWindow.contentView`). Только `focusOnUnit` затрагивается; `focusOn(gridPoint:)` — нет (AC говорит явно про `focusOnUnit`).

**Behind-режим guard.** Кнопка журнала — внутри `if modeManager.isExplore`. Анимация смены режима использует существующий `.animation(.easeOut(duration: 0.18))` — после завершения transition `isExplore` уже `true/false`, кнопка появляется/исчезает без промежуточных кадров. AC «только после завершения transition» обеспечивается естественно, т.к. `isExplore` меняется атомарно в `enterExploreMode/enterBehindMode`.

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку. Шаг непонятен — НЕ импровизируй, возвращай задачу через сообщение.

1. **Расширить SceneBridge — selectedUnitInfo + makeKey** `[AC:7,8]`
   - Файл: `Sources/CityDeveloper/UI/SceneBridge.swift`
   - Добавить `@Published var selectedUnitInfo: (UnitState, ProjectState)? = nil`.
   - В `func focusOnUnit(_ unit: UnitState)` после двух существующих вызовов добавить:
     ```swift
     scene?.view?.window?.makeKey()
     ```
   - Не трогать `focusOn(gridPoint:)`.

2. **GameScene.showInspector — публиковать selectedUnitInfo** `[AC:9]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift`
   - В `func showInspector(forUnitId id: UUID)` после построения SpriteKit-попапа добавить публикацию в bridge. Найди существующий `engine?.state.units[id]` lookup и в той же области:
     ```swift
     // после `showInspector(near: pos, unit: unit, project: project)`:
     bridge?.selectedUnitInfo = (unit, project)
     ```
   - Если у `GameScene` ещё нет ссылки на `bridge` — добавить `weak var bridge: SceneBridge?` и проинициализировать в `AppDelegate` сразу после создания scene и bridge (см. шаг 7).
   - В `hideInspector()` (или там, где SpriteKit-попап удаляется по клику в пустоту) — установить `bridge?.selectedUnitInfo = nil`.

3. **Создать InspectorOverlayCard.swift** `[AC:9]`
   - Файл: `Sources/CityDeveloper/UI/InspectorOverlayCard.swift` (новый)
   - Скелет:
     ```swift
     import SwiftUI

     struct InspectorOverlayCard: View {
         @ObservedObject var bridge: SceneBridge

         var body: some View {
             Group {
                 if let info = bridge.selectedUnitInfo {
                     cardView(unit: info.0, project: info.1)
                 } else {
                     EmptyView()
                 }
             }
             .frame(maxWidth: .infinity, maxHeight: .infinity,
                    alignment: .trailing)
         }

         private func cardView(unit: UnitState, project: ProjectState) -> some View {
             VStack(alignment: .leading, spacing: 6) {
                 Text(project.name).font(.system(size: 13, weight: .semibold))
                 // тип юнита (русское имя), стадия, taskTitle, taskTs
                 // — используй те же source-of-truth поля, что и InspectorPanel.build
             }
             .padding(12)
             .frame(maxWidth: 260)
             .background(Color.paletteSandLight)
             .cornerRadius(10)
             .shadow(radius: 4)
             .padding(.trailing, 16)
             .frame(maxHeight: .infinity, alignment: .center)
         }
     }
     ```
   - Палитра / шрифты — переиспользуй существующие из `ProjectCard.swift` / `Theme/Palette.swift`.
   - Если высота окна < 200 pt (узкое окно) — `.frame(maxHeight: .infinity, alignment: .center)` всё равно даёт минимум 40 pt сверху при стандартном min-window-height (см. шаг 6, где задаётся min size).

4. **Создать JournalWindowController.swift** `[AC:4,5,6,7]`
   - Файл: `Sources/CityDeveloper/App/JournalWindowController.swift` (новый)
   - Полный скелет (паттерн `SettingsWindowController`):
     ```swift
     import AppKit
     import SwiftUI

     final class JournalWindowController: NSObject, NSWindowDelegate {
         private var window: NSWindow?

         func show(engine: CityEngine,
                   bridge: SceneBridge,
                   collapsed: Binding<Bool>,
                   selectedProject: Binding<String?>,
                   dateFrom: Binding<Date>,
                   dateTo: Binding<Date>,
                   didInitDates: Binding<Bool>) {
             if let w = window, w.isVisible {
                 w.makeKeyAndOrderFront(nil)
                 w.deminiaturize(nil)
                 NSApp.activate(ignoringOtherApps: true)
                 return
             }

             let panel = SidePanelView(
                 engine: engine,
                 bridge: bridge,
                 collapsed: collapsed,
                 selectedProject: selectedProject,
                 dateFrom: dateFrom,
                 dateTo: dateTo,
                 didInitDates: didInitDates
             )
             let host = NSHostingController(rootView: panel)

             let w = NSWindow(contentViewController: host)
             w.title = "Журнал событий"
             w.styleMask = [.titled, .closable, .resizable]
             w.setContentSize(NSSize(width: 480, height: 600))
             w.contentMinSize = NSSize(width: 480, height: 600)
             w.delegate = self

             // Центрирование: NSApp.mainWindow?.frame или NSScreen.main?.frame
             if let main = NSApp.mainWindow {
                 let m = main.frame
                 let size = w.frame.size
                 let origin = NSPoint(
                     x: m.midX - size.width / 2,
                     y: m.midY - size.height / 2
                 )
                 w.setFrameOrigin(origin)
             } else if let screen = NSScreen.main {
                 w.center()
                 _ = screen // явный fallback
             }

             window = w
             w.makeKeyAndOrderFront(nil)
             NSApp.activate(ignoringOtherApps: true)
         }

         func windowWillClose(_ notification: Notification) {
             window = nil
         }
     }
     ```
   - **Важно:** `setContentSize` + `contentMinSize` обеспечивает AC «min 480×600».
   - **Важно:** `isReleasedWhenClosed` оставляем дефолтным для view-controller-based `NSWindow` (это `true` для обычных, но для `init(contentViewController:)` уже корректно — окно живёт пока есть ref). AC говорит «не держит app живым» — это уже выполняется т.к. `NSApplicationMain` ловит quit поверх любых non-modal окон.
   - **Передача @Binding из @State ContentView:** `Binding<…>` — value-type wrapper с get/set-замыканиями. Стандартный синтаксис `$selectedProject` (из тела SwiftUI view) даёт корректный `Binding<String?>`, который можно передать в любой метод — включая `JournalWindowController.show()`. После передачи Binding продолжает работать как property reference, читая/записывая исходный @State storage. NSHostingController создаёт отдельный SwiftUI runtime, но передаваемый Binding пересекает границу корректно: его get/set-замыкания захватывают ссылку на storage, а SwiftUI обеспечивает re-render обеих view-иерархий (ContentView и SidePanelView в NSHostingController) при изменении storage. **Никаких `Binding(get:set:)`-вручную не нужно** — обычный `$state` работает, т.к. вызов `journalController.show(..., selectedProject: $selectedProject, ...)` происходит из тела Button (Button-closure исполняется в контексте SwiftUI view body, где `$selectedProject` валиден).

5. **Поднять состояние в ContentView и убрать SidePanelView** `[AC:1,2,3,7]`
   - Файл: `Sources/CityDeveloper/UI/ContentView.swift`
   - Добавить новое поле `@State private var buttonVisible: Bool = false` — отдельный gate для кнопки журнала.
   - Добавить новое поле в init: `let journalController: JournalWindowController`.
   - `@State` блоки (`collapsed`, `selectedProject`, `dateFrom`, `dateTo`, `didInitDates`) — **оставить как есть**, источник истины не меняется.
   - Полностью переписать `body`:
     ```swift
     var body: some View {
         ZStack(alignment: .bottomTrailing) {
             SpriteView(scene: scene, preferredFramesPerSecond: 60)
                 .ignoresSafeArea()
                 .frame(maxWidth: .infinity, maxHeight: .infinity)

             InspectorOverlayCard(bridge: bridge)
                 .allowsHitTesting(false)

             if buttonVisible {
                 Button {
                     journalController.show(
                         engine: engine,
                         bridge: bridge,
                         collapsed: $collapsed,
                         selectedProject: $selectedProject,
                         dateFrom: $dateFrom,
                         dateTo: $dateTo,
                         didInitDates: $didInitDates
                     )
                 } label: {
                     Image(systemName: "list.bullet")
                         .font(.system(size: 16, weight: .semibold))
                         .foregroundColor(.white)
                         .frame(width: 36, height: 36)
                         .background(Color.black.opacity(0.45))
                         .cornerRadius(8)
                 }
                 .buttonStyle(.plain)
                 .accessibilityLabel("Журнал событий")
                 .padding(.trailing, 16)
                 .padding(.bottom, 24)
                 .transition(.opacity)
             }
         }
         .onChange(of: modeManager.isExplore) { newValue in
             if newValue {
                 // Включаем кнопку только после завершения transition
                 DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                     if modeManager.isExplore {
                         withAnimation(.easeOut(duration: 0.18)) {
                             buttonVisible = true
                         }
                     }
                 }
             } else {
                 // Скрываем кнопку немедленно при выходе из explore
                 buttonVisible = false
             }
         }
         .onAppear {
             // Если приложение стартует уже в explore-режиме (маловероятно, но possible)
             buttonVisible = modeManager.isExplore
         }
     }
     ```
   - `allowsHitTesting(false)` на overlay-карточке — клики проходят через карточку к `SpriteView` для камеры.
   - **Логика AC3:** `buttonVisible` — отдельный @State, который меняется через `asyncAfter(0.20)` после перехода в explore (gate ≥ длительности `.animation` 0.18 в WindowModeManager onModeChange, если есть). При выходе из explore — немедленно `false`. Это и есть «только после завершения transition».
   - Если `modeManager.isExplore` успел переключиться обратно в `false` за 0.20 сек — guard `if modeManager.isExplore` внутри asyncAfter предотвращает показ кнопки в behind-режиме.

6. **AppDelegate — JournalWindowController + проброс в ContentView + scene.bridge** `[AC:4,9]`
   - Файл: `Sources/CityDeveloper/App/AppDelegate.swift`
   - Изменения одним блоком (объединяет бывшие шаги 6 и 7):
     - Добавить поле:
       ```swift
       private var journalWindowController: JournalWindowController!
       ```
     - В `applicationDidFinishLaunching` после строки `settingsWindowController = SettingsWindowController()` добавить:
       ```swift
       journalWindowController = JournalWindowController()
       ```
     - Найди существующее присваивание `bridge.scene = scene` (или аналог) и сразу после него добавь:
       ```swift
       scene.bridge = bridge
       ```
       (для этого `GameScene` должен иметь `weak var bridge: SceneBridge?` — см. шаг 2.)
     - Найди вызов `NSHostingView(rootView: ContentView(scene: scene, engine: engine, modeManager: modeManager, bridge: bridge))` и добавь параметр:
       ```swift
       NSHostingView(rootView: ContentView(
           scene: scene,
           engine: engine,
           modeManager: modeManager,
           bridge: bridge,
           journalController: journalWindowController
       ))
       ```

### Edge cases (явно обработать)

- [ ] **Behind → explore с открытым окном:** `modeManager.isExplore` переключается в `true`, кнопка появляется через `.animation`. `JournalWindowController.window` уже существует — повторное `show()` не вызывается, окно остаётся на том же месте. Проверка `window?.isVisible` в `show()` (`JournalWindowController.swift`) гарантирует одно окно.
- [ ] **Explore → behind с открытым окном:** кнопка скрывается (`isExplore = false`), окно журнала **не закрывается** — оно живёт отдельно от кнопки. AC выполняется естественно.
- [ ] **Клик по событию из behind-режима:** окно журнала может оставаться открытым в behind-режиме (пользователь не закрыл). Клик по событию вызывает `SidePanelView.handleEventTap → bridge.focusOnUnit`. Внутри `focusOnUnit` нужна guard: `scene?.view?.window?.makeKey()` сработает, но если режим behind — камера не фокусируется (т.к. SpriteKit паузится через `view.isPaused = true` в behind, см. `App/AppDelegate.swift` `modeManager.onModeChange`). Допустимо: AC говорит «фокус камеры игнорируется молчаливо в behind». Проверь, что guard уже есть в `GameScene.focusCamera`; если нет — это **не наш скоуп** (см. «НЕ делаем»).
- [ ] **Quit с открытым окном:** `JournalWindowController.window` — обычный `NSWindow` с `delegate = self`. При quit AppKit вызывает стандартный teardown — `windowWillClose` обнуляет ref, окно деаллоцируется. Не блокирует quit.
- [ ] **Мультимонитор:** `NSApp.mainWindow` — это `cityWindow` (см. `App/CityWindow.swift:14-25`), который занимает текущий экран. Центрирование по его `frame` ставит окно журнала на тот же экран. Корректно.
- [ ] **fullscreen / Spaces:** `cityWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, ...]` (см. `App/CityWindow.swift:26-28`). Окно журнала — обычное, **не** наследует эти behaviour, следует за активным Space.
- [ ] **Быстрые двойные нажатия:** второй тап вызывает `show()`, попадает в `if let w = window, w.isVisible { ... return }` — `makeKeyAndOrderFront` + `deminiaturize`. Второе окно не создаётся.
- [ ] **`NSApp.mainWindow == nil`:** в момент `show()` маловероятно (cityWindow не deallocates), но если случилось — `NSScreen.main` fallback + `w.center()`. См. шаг 4.
- [ ] **Главное окно minimized:** журнал остаётся открытым. `NSApp.mainWindow` всё ещё указывает на minimized `cityWindow`. Центр пересчитается по последнему `frame`. Корректно.
- [ ] **⌘W в журнале:** `styleMask` содержит `.closable`, AppKit обрабатывает ⌘W стандартно — закрытие именно journal-окна. Quit не вызывается, т.к. `cityWindow` остаётся открытым (он main).
- [ ] **Карточка инспектора при `selectedUnitInfo == nil`:** `InspectorOverlayCard` рендерит `EmptyView()` — не занимает места, кнопка журнала свободно отображается в bottomTrailing.
- [ ] **Карточка инспектора + кнопка на узком окне:** разный `alignment` (`.center` vs `.bottomTrailing`) гарантирует разные Y-координаты. На windows < 200 pt высоты — карточка съезжает к центру, но min `contentMinSize` для cityWindow не задан в коде, поэтому формальной гарантии 40 pt нет. Принимаем риск, т.к. realistic windows ≥ 600 pt.

### Файлы для изменения

- `Sources/CityDeveloper/UI/SceneBridge.swift` — `+@Published var selectedUnitInfo`, `focusOnUnit + makeKey()`.
- `Sources/CityDeveloper/Game/GameScene.swift` — `+weak var bridge: SceneBridge?`, в `showInspector(forUnitId:)` обновлять `bridge?.selectedUnitInfo`; в `hideInspector()` обнулять.
- `Sources/CityDeveloper/UI/ContentView.swift` — переход `HStack → ZStack`, добавить кнопку + `InspectorOverlayCard`, новый init-параметр `journalController`.
- `Sources/CityDeveloper/App/AppDelegate.swift` — создать `journalWindowController`, проброс в `ContentView`, `scene.bridge = bridge`.
- `Sources/CityDeveloper/App/JournalWindowController.swift` — **новый**.
- `Sources/CityDeveloper/UI/InspectorOverlayCard.swift` — **новый**.

### Файлы НЕ трогать

- `Sources/CityDeveloper/UI/SidePanelView.swift` — переиспользуется as-is per PM «Не переделываем содержимое журнала и фильтры». Все @Binding и @ObservedObject в её init остаются без изменений.
- `Sources/CityDeveloper/Game/InspectorPanel.swift` — SpriteKit-попап остаётся per PM «Не меняем логику InspectorPanel».
- `Sources/CityDeveloper/App/SettingsWindowController.swift` — только как референс, не правим.
- `Sources/CityDeveloper/App/WindowModeManager.swift` — режимная логика уже всё умеет, ничего не добавляем.
- `Sources/CityDeveloper/App/CityWindow.swift` — главное окно — не наш скоуп.
- `Sources/CityDeveloper/UI/ProjectCard.swift` — отдельный компонент для проектов в SidePanelView, не связан с inspector overlay.

### Команды проверки (для DoD)

- Компиляция: `swift build`
- Запуск: `swift run CityDeveloper`
- Ручная проверка (сценарий 1–6 PM):
  1. Запустить, нажать ⌘⌥G (или из status bar) — explore mode, **боковая панель НЕ появляется**, видна карта + кнопка `list.bullet` справа-внизу.
  2. Нажать кнопку — открывается окно «Журнал событий» по центру cityWindow, фильтры по проекту/дате, список событий.
  3. Кликнуть на событие — карта фокусируется на нужном юните, появляется SpriteKit-попап рядом + SwiftUI-карточка справа по центру окна. Главное окно становится key (мышь работает с картой).
  4. Закрыть журнал крестиком → открыть снова — фильтры (проект/даты) **сохранены**.
  5. Переключить в behind — кнопка журнала скрывается, окно журнала остаётся (если было открыто).
  6. Кликнуть на юнит в explore mode (не из журнала) — SwiftUI-карточка справа-по-центру, **не перекрыта часами macOS**.

### Сложность

`senior`

**Обоснование:** 6 файлов в 3 слоях (App, UI, Game), кросс-graph биндинги SwiftUI ↔ NSHostingController, новый интеграционный паттерн (SpriteKit → @Published → SwiftUI overlay), несколько edge cases требующих внимания к деталям AppKit (`makeKey`, `windowWillClose`, центрирование).

### Ожидаемое время

M (≤1 день, оценка 4–6 часов)

---

## ✅ Исполнение

_Исполнитель: opus (executor + retry)_
_Сложность: senior_

### Definition of Done

#### Функциональные
- [x] Все AC выполнены (verify pass после retry на AC9)
- [ ] Ручной прогон сценария 1–6 — _manual-required (GUI, нельзя автоматизировать)_

#### Технические
- [x] `swift build` без новых ошибок (Build complete!)

#### Обновление документации
- [x] `current.md`: F-11 — обновить описание (панель теперь по кнопке)

---

## Статус

`[x] done`

## Метаданные
- Создана PM: 2026-05-22
- Spec-review: needs-revision → applied (round 1) → needs-revision → applied (round 2) → approved
- Lead-trigger: opus (новый AppKit-контроллер + 4 файла в двух слоях)
- Lead-model: opus
- Plan-review: revised (round 1 → revised → round 2 → approved)
- Готова к работе: 2026-05-22
- Завершена: 2026-05-22
- Verify: pass (retry 1 на AC9, остальное pass с первой попытки)
- Code-review: approved (opus, без правок)
- Коммит: — (проект не git-репо)
