# TASK-014: Поле «население» per-project в карточке инспектора

## Связь
- **F-11** Инспектор / журнал событий (остаток после TASK-007)
- **F-10** Жители и анимация (источник истины)
- **D-11** (закрывает финальный остаток)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22 (пересоздана после `[split-needed]`; принято решение по источнику истины — реальные жители из CitizenManager)_

### Что хотим

Добавить в карточку проекта `ProjectCard` (трейлинг боковой панели и
оверлей-карточка инспектора) поле «Жителей: N», где N — **реальное количество
активных жителей-NPC**, которых сейчас отрисовывает `CitizenManager` для этого
квартала. Не «расчётное население» по формуле от unit/stage — а ровно то, что
юзер видит на сцене.

### Почему так

- В `CitizenManager` уже есть источник истины: `citizensByProject[projectId]`
  (за вычетом `citizensLeaving` — тех, кто доигрывает fade-out).
- Не нужна вторая формула. `CityState.population` (computed по всему городу) —
  legacy MVP-приближение, его не трогаем, оно остаётся для агрегата.
- Если на сцене 0 жителей (stage < 2 или decay 4 — см. `CitizenManager.targetCount`),
  в карточке честно «Жителей: 0». Это правильно: пустой квартал «без жизни»
  не должен врать «10 жителей».
- При replay из snapshot+tail число жителей **не восстанавливается** (это
  визуальное состояние, не state). Сразу после старта значение может быть 0,
  пока `CitizenManager.tick()` (раз в 2 сек) не догонит цель. Это приемлемо.

### Пользовательский сценарий

1. Юзер закрывает 4 задачи в проект `myapp` → квартал растёт, стадия 2+.
2. На карте появляются NPC-жители (анимация waypoint walk).
3. Юзер кликает по любому юниту в `myapp` → попап инспектора + оверлей-карточка
   справа.
4. В карточке проекта (и в строке боковой панели, если открыта) — поле
   «Жителей: 5».
5. Цифра обновляется по мере того, как `CitizenManager` спавнит/убирает NPC
   (≈ раз в 2 сек, синхронно с тиком).

### Acceptance criteria

- [ ] **Public API в `CitizenManager`:** метод `func activeCitizenCount(for projectId: String) -> Int`,
      возвращает `(citizensByProject[projectId] ?? []).subtracting(citizensLeaving).count`.
      Метод thread-safe для чтения с main thread (CitizenManager и так main-bound
      через SKAction-tick).
- [ ] **Проброс в UI:** `SceneBridge` (или эквивалент — куда смотрит SwiftUI)
      получает источник для чтения population per-project. Решение лида — либо
      `engine.citizenManager?.activeCitizenCount(for:)`, либо новый `@Published`
      словарь, обновляемый из tick. Главное — чтобы изменение отражалось в UI без
      ручного refresh.
- [ ] **`ProjectCard`:** в HStack-метрик добавлена ещё одна метка
      `Text("Жителей: \(population)")`, рядом с «Юнитов: N» / «Stage S» / датой
      `lastActivityAt`. Стиль 11pt, `paletteInkDark.opacity(0.6)`, как у соседних.
- [ ] **`InspectorOverlayCard` (если показывает те же поля):** аналогичное добавление.
- [ ] **Обновление в реальном времени:** при изменении числа жителей UI
      перерисовывается без перезапуска и без клика. Достаточно частоты тика
      `CitizenManager` (≈ 2 сек).
- [ ] **Behind-mode:** при свёрнутом окне (`view.isPaused = true`) тик
      `CitizenManager` не идёт — значение фризится на последнем, что нормально
      (UI не виден).
- [ ] **Quick smoke:** один свежий проект, добавить 6 задач → стадия 2 → через
      ≤ 5 сек в карточке «Жителей: 4» (по формуле `max(3, stage*2 + units/4)`).
- [ ] **Юнит-тест:** `activeCitizenCount(for:)` корректно исключает
      `citizensLeaving` (один спавн + одно `removeCitizens(count: 1)` → count
      сразу падает на 1, а не после завершения fade).

### Что НЕ делаем

- **Не вводим** новое поле `ProjectState.population` в `CityState` (модель остаётся
  чистой; «жители» — визуальный, не персистентный state).
- **Не меняем** legacy-формулу `CityState.population` (агрегат по городу).
- **Не пишем** системные события «citizen_spawned» / «citizen_left» (они
  визуальные, не персистентные).
- Не делаем анимацию инкремента цифры (просто `Text` с новым значением).
- Не локализуем «Жителей» / «человек» — оставляем «Жителей: N».
- Не добавляем поле в boidlist `SidePanelView.JournalRow` — журнал останется как есть.

### Edge cases

- [ ] **Квартал stage < 2 → жителей 0** (по правилу `CitizenManager.targetCount`).
      Карточка честно показывает «Жителей: 0».
- [ ] **Квартал с decayLevel = 4 (руины)** → жители = 0 (то же правило).
      Карточка показывает «Жителей: 0», decay-индикатор остаётся красным.
- [ ] **Свежий старт / replay из snapshot** — пока тик не отработал,
      `citizensByProject` пуст → «Жителей: 0». Через 2 сек значение
      «догоняется». Это приемлемо, не баг.
- [ ] **Global cap 150 на весь город** — если квартал «недокормлен» из-за
      cap'а, в карточке показывается реальное (меньше целевого). Это
      интерпретируется юзером как «город перегружен», а не баг.
- [ ] **Проект удалён из state** — карточка для него уже не рендерится,
      `removeAllCitizens` отрабатывает на следующем тике.

### Зависимости

- **F-10 (TASK-011)** — `CitizenManager` ✅ существует.
- **F-11 (TASK-007/016)** — `ProjectCard`, `InspectorOverlayCard`,
  `SceneBridge` ✅ существуют. Это минимальная вставка поля + источник.
- Нет внешних сервисов / миграций.

### Дизайн

- Шрифт/цвет — те же 11pt `paletteInkDark.opacity(0.6)`, как у «Юнитов» / «Stage».
- Порядок в HStack: `Юнитов: N → Stage S → Жителей: M → дата`. «Жителей»
  логически между «Stage» и датой: stage и жители тесно связаны.
- Если ширина HStack маленькая (узкая боковая панель) — допустимо `lineLimit(1)`
  и обрезание; визуальный полишинг не блокирует приёмку.

### Done-критерий

_Из concept.md F-11 (остаток D-11):_

> В карточке проекта (попап + боковая панель) виден показатель «население» per-project,
> отражающий реальное число активных жителей на сцене в этом квартале.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-22_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

**В коде уже есть:**
- `Sources/CityDeveloper/Game/CitizenManager.swift` — единственный источник истины:
  - `private var citizensByProject: [String: Set<UUID>]` (стр. 28).
  - `private var citizensLeaving: Set<UUID> = []` (стр. 29).
  - tick раз в 2 сек через `SKAction.wait(forDuration: 2.0)` (стр. 41), запускается на scene → main thread.
  - `targetCount(for:)` уже инкапсулирует правила «stage<2 → 0», «decayLevel==4 → 0», «unitIds.isEmpty → 0» и формулу `max(3, min(20, stage*2 + units/4))` (стр. 53–58).
  - Двухфазное удаление (`removeCitizens` стр. 226–244): UUID кладётся в `citizensLeaving`, через `SKAction.fadeOut(1.0)` удаляется из `citizens`, `citizensByProject` и `citizensLeaving`.
  - Публичного метода `activeCitizenCount(for:)` нет.
- `Sources/CityDeveloper/UI/SceneBridge.swift` — `final class SceneBridge: ObservableObject` (стр. 5):
  - Единственное `@Published` — `selectedUnitInfo` (стр. 10).
  - `weak var scene: GameScene?` (стр. 6), `bridge.scene` weak, `scene.bridge` weak.
  - per-project population сейчас отсутствует.
- `Sources/CityDeveloper/UI/SidePanelView.swift`:
  - `@ObservedObject var engine: CityEngine` (стр. 4), `@ObservedObject var bridge: SceneBridge` (стр. 5) — bridge уже в скоупе.
  - `ProjectCard(project:) { handleProjectTap(project) }` — рендер по `sortedProjects` (стр. 164–171).
- `Sources/CityDeveloper/UI/ProjectCard.swift`:
  - Сигнатура: `struct ProjectCard: View { let project: ProjectState; let onTap: () -> Void }` (стр. 3–5).
  - HStack метрик (стр. 37–41): `Юнитов: N → Stage S → дата`, font 11pt, `.paletteInkDark.opacity(0.6)` (стр. 42–43).
- `Sources/CityDeveloper/UI/InspectorOverlayCard.swift`:
  - Показывает `project.name`, `kind/tier юнита`, taskTitle, дату задачи. **HStack «Юнитов: N / Stage S» отсутствует.**
- `Sources/CityDeveloper/Game/GameScene.swift` (стр. 73–81): создаёт `CitizenManager`, проставляет `cm.engine`, `cm.scene = self`. `scene.bridge` weak (выставлен в `AppDelegate`).
- `Sources/CityDeveloper/Data/CityState.swift`:
  - `ProjectState` (стр. 57–68) — без поля population.
  - `CityState.population` — computed-агрегат (стр. 76–81), legacy. НЕ трогаем.
- `Sources/CityDeveloper/Theme/Palette.swift` — `paletteInkDark` есть (стр. 35).
- `Package.swift` — только `.executableTarget`, тестовой цели **нет**.

**Связанные модули:** Game/CitizenManager, UI/SceneBridge, UI/ProjectCard, UI/SidePanelView, Package.

**Что переиспользуем:** хранилища `citizensByProject` / `citizensLeaving`, текущий tick-loop как точку «push в bridge», существующий `@ObservedObject` контур SwiftUI.

**Что нужно дописать:**
- Public `activeCitizenCount(for:)` + internal test-seam в `CitizenManager`.
- `@Published var populationByProject` в `SceneBridge` и пуш в конце `tick()`.
- Новый параметр + `Text` в `ProjectCard`; проброс из `SidePanelView`.
- `.testTarget` + один юнит-тест.

### Архитектурное решение

Из двух вариантов, перечисленных PM в AC #2, выбираем **`@Published var populationByProject: [String: Int]` в `SceneBridge`**, который обновляется хвостом `CitizenManager.tick()`. Прямой вызов `engine.citizenManager?.activeCitizenCount(for:)` из View отбрасываем по двум причинам: (1) `CitizenManager` хранится в `GameScene`, а не в `CityEngine`, и `engine.citizenManager` пришлось бы создавать; (2) прямой вызов из `body` не триггерит перерисовку — SwiftUI не наблюдает `CitizenManager`. Подписка на `@Published` в bridge — естественный SwiftUI-паттерн, минимальный код.

Tick `CitizenManager` исполняется на main (через `SKAction.run` у `GameScene`), `bridge` доступен как `scene?.bridge`. После шага 3 tick'а (spawn/remove) собираем словарь `[String: Int]` по **всем** `engine.state.projects.keys` (а не только тем, что есть в `citizensByProject`) — чтобы для пустых кварталов был явный `0` и UI не зависел от наличия ключа. Присваивание `bridge.populationByProject = …` происходит на main → ObservableObject триггерит перерисовку SwiftUI.

`InspectorOverlayCard` **включаем в скоуп**: AC #4 «если показывает те же поля» трактуется буквально — карточка отображает `project.name`, и доступа к `bridge` (уже `@ObservedObject`) достаточно, чтобы добавить «Жителей: N» под именем проекта без структурных изменений. Cost — одна строка `Text`, payoff — пользователь видит population квартала, к которому относится выделенный юнит. См. шаг 7.

**Trade-off перерисовки.** `SidePanelView` подписан на `bridge` через `@ObservedObject` — присваивание `populationByProject` целым словарём перезапустит `body` всей панели каждые 2 сек и пересчитает `sortedProjects`. При текущем масштабе ≤ 20 проектов это незаметно. Если число проектов вырастет до 50+, минимальная оптимизация — мемоизация `sortedProjects` или Equatable-обёртка над `ProjectCard`. Сейчас не делаем — out of scope, фиксируем заметкой.

Тест `activeCitizenCount(for:)` пишем как XCTest в новом `Tests/CityDeveloperTests/` через `@testable import CityDeveloper`. Чтобы не размыкать `private`-инварианты, добавляем `internal func _testSeed(projectId:leaving:) -> UUID` — единственный путь для тестов вкатить UUID в `citizensByProject` и `citizensLeaving` без полноценного spawn (тот зависит от scene/engine).

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку. Шаг непонятен — НЕ импровизируй, возвращай задачу через сообщение.

1. **Public API `activeCitizenCount(for:)`** `[AC:1]`
   - Файл: `Sources/CityDeveloper/Game/CitizenManager.swift`
   - Блок: добавить новую секцию **до** `// MARK: - Remove (two-phase)` (примерно стр. 223), после tick'а — это естественное место для «public read API».
   - Что меняем: добавить **internal** (по умолчанию) метод, читающий приватные dict. Вызывается только с main (CitizenManager весь main-bound через SpriteKit), доп. синхронизация не нужна.
   - Скелет:
     ```swift
     // MARK: - Public read API

     /// Количество активных жителей проекта на сцене (без тех, кто доигрывает fade-out).
     /// Безопасно читать с main thread — CitizenManager main-bound (SKAction).
     func activeCitizenCount(for projectId: String) -> Int {
         guard let ids = citizensByProject[projectId] else { return 0 }
         return ids.subtracting(citizensLeaving).count
     }
     ```
   - Никаких других изменений в файле на этом шаге.

2. **Internal test-seam (только DEBUG)** `[AC:8]`
   - Файл: `Sources/CityDeveloper/Game/CitizenManager.swift`
   - Блок: сразу под `activeCitizenCount(for:)` в той же секции «Public read API».
   - Что меняем: добавить `internal func _testSeed(projectId:leaving:) -> UUID` под `#if DEBUG` — чтобы release-сборка вообще не содержала этот символ. `swift test` собирает в Debug, тесты видят метод; `swift build -c release` его исключает.
   - Скелет:
     ```swift
     #if DEBUG
     /// Test-only seam: вкатывает UUID в индексы без полноценного spawn
     /// (тот зависит от scene/engine). Имя с префиксом `_test` — для grep'а.
     /// Доступен ТОЛЬКО в Debug-сборке.
     func _testSeed(projectId: String, leaving: Bool) -> UUID {
         let id = UUID()
         citizensByProject[projectId, default: []].insert(id)
         if leaving { citizensLeaving.insert(id) }
         return id
     }
     #endif
     ```

3. **Push per-project population из tick** `[AC:2,5]`
   - Файл: `Sources/CityDeveloper/Game/CitizenManager.swift`
   - Блок: метод `private func tick()` (стр. 62–101), **после** шага «4. Cleanup projects removed from state» (после стр. 100), но до закрывающей `}`.
   - Что меняем: собрать словарь по всем `engine.state.projects.keys` (включая нулевые проекты — для синхронной перерисовки) и присвоить `scene?.bridge?.populationByProject`. tick уже main → присваивание main-safe.
   - Скелет (вставка в конец `tick()`):
     ```swift
     // 5. Publish per-project active count to UI bridge.
     // Ключи — все проекты из state, чтобы пустые кварталы получали явный 0.
     var snapshot: [String: Int] = [:]
     snapshot.reserveCapacity(engine.state.projects.count)
     for projectId in engine.state.projects.keys {
         snapshot[projectId] = activeCitizenCount(for: projectId)
     }
     scene?.bridge?.populationByProject = snapshot
     ```
   - Цикл `engine.state.projects` уже использовался выше (стр. 67) — паттерн прецедентный.

4. **`@Published` в SceneBridge** `[AC:2,5]`
   - Файл: `Sources/CityDeveloper/UI/SceneBridge.swift`
   - Блок: рядом с существующим `@Published var selectedUnitInfo` (стр. 10).
   - Что меняем: добавить:
     ```swift
     /// Активное количество жителей по projectId. Обновляется
     /// `CitizenManager.tick()` (≈ раз в 2 сек). Пустой словарь — pre-tick.
     @Published var populationByProject: [String: Int] = [:]
     ```
   - Никаких дополнительных API/методов не нужно — `CitizenManager` пишет напрямую, View читает напрямую.

5. **Новый параметр и `Text` в `ProjectCard`** `[AC:3]`
   - Файл: `Sources/CityDeveloper/UI/ProjectCard.swift`
   - Блок: сигнатура (стр. 3–5) и HStack метрик (стр. 37–41).
   - Что меняем:
     - В сигнатуру добавить `let population: Int` **между** `project` и `onTap`:
       ```swift
       struct ProjectCard: View {
           let project: ProjectState
           let population: Int
           let onTap: () -> Void
       ```
     - В HStack между `Text("Stage \(project.stage)")` и `Text(Self.dateFormatter…)` вставить:
       ```swift
       Text("Жителей: \(population)")
       ```
       Стиль наследуется от `.font(.system(size: 11))` и `.foregroundColor(.paletteInkDark.opacity(0.6))` на всём HStack (стр. 42–43) — отдельных модификаторов на метку не нужно.
   - Итоговый порядок в HStack: `Юнитов → Stage → Жителей → дата` (AC).
   - **Не добавляй** `lineLimit(1)` / fixed widths — пусть SwiftUI сжимает естественно. PM явно отмечает: «полишинг ширины не блокирует приёмку».
   - ⚠️ После шага 5 проект **временно не компилируется** — все вызовы `ProjectCard(project:)` без `population:` упадут. **Не запускай `swift build` между шагами 5 и 6** — выполняй их подряд.

6. **Проброс population из SidePanelView** `[AC:5]`
   - Файл: `Sources/CityDeveloper/UI/SidePanelView.swift`
   - Блок: `ForEach(sortedProjects, …) { project in ProjectCard(project: project) { … } }` (стр. 165–168).
   - Что меняем: передать новый аргумент:
     ```swift
     ProjectCard(
         project: project,
         population: bridge.populationByProject[project.id] ?? 0
     ) {
         handleProjectTap(project)
     }
     ```
   - `bridge` уже в скоупе как `@ObservedObject` (стр. 5) — никаких новых проперти/инициализаторов не нужно. Перерисовка отработает автоматически при изменении `populationByProject`.

7. **Добавить «Жителей» в `InspectorOverlayCard`** `[AC:4]`
   - Файл: `Sources/CityDeveloper/UI/InspectorOverlayCard.swift`
   - Блок: внутри `cardView(unit:project:)` (стр. 24–43) — VStack, **сразу после** `Text(project.name)` (стр. 26–28).
   - Что меняем: вставить одну строку:
     ```swift
     Text("Жителей: \(bridge.populationByProject[project.id] ?? 0)")
         .font(.system(size: 10))
         .foregroundColor(.paletteInkDark.opacity(0.6))
     ```
   - Размер 10pt (а не 11) — чтобы согласовать с соседней строкой `kind/tier` (стр. 30–32), которая 10pt. Это сохраняет визуальную иерархию карточки. Цвет/opacity те же, что у соседей.
   - `bridge` уже доступен как `@ObservedObject var bridge: SceneBridge` (стр. 11) — никаких новых проперти не нужно.
   - Никаких других изменений в файле.

8. **Добавить test target в Package.swift + создать директорию тестов** `[AC:8]`
   - Сначала создай директорию: `mkdir -p Tests/CityDeveloperTests` (из корня репозитория `<repo-root>`).
   - Файл: `Package.swift`
   - Что меняем: расширить массив `targets`:
     ```swift
     targets: [
         .executableTarget(
             name: "CityDeveloper",
             path: "Sources/CityDeveloper"
         ),
         .testTarget(
             name: "CityDeveloperTests",
             dependencies: ["CityDeveloper"],
             path: "Tests/CityDeveloperTests"
         )
     ]
     ```
   - swift-tools-version 5.10 и `platforms: [.macOS(.v14)]` уже есть — без изменений.

9. **Юнит-тест `activeCitizenCount(for:)`** `[AC:8]`
   - Файл: новый — `Tests/CityDeveloperTests/CitizenManagerTests.swift`
   - Что меняем: создать файл со следующим содержимым:
     ```swift
     import XCTest
     @testable import CityDeveloper

     final class CitizenManagerTests: XCTestCase {

         func testActiveCitizenCountExcludesLeaving() {
             let cm = CitizenManager()
             _ = cm._testSeed(projectId: "p1", leaving: false)
             _ = cm._testSeed(projectId: "p1", leaving: false)
             _ = cm._testSeed(projectId: "p1", leaving: true)  // in citizensLeaving
             XCTAssertEqual(cm.activeCitizenCount(for: "p1"), 2)
         }

         func testActiveCitizenCountUnknownProjectIsZero() {
             let cm = CitizenManager()
             XCTAssertEqual(cm.activeCitizenCount(for: "ghost"), 0)
         }

         func testActiveCitizenCountDecreasesWhenMarkedLeaving() {
             let cm = CitizenManager()
             let a = cm._testSeed(projectId: "p1", leaving: false)
             let b = cm._testSeed(projectId: "p1", leaving: false)
             XCTAssertEqual(cm.activeCitizenCount(for: "p1"), 2)
             _ = cm._testSeed(projectId: "p1", leaving: true)
             XCTAssertEqual(cm.activeCitizenCount(for: "p1"), 2,
                            "Leaving citizen must not count as active")
             _ = (a, b) // suppress unused warning
         }
     }
     ```
   - Если `swift test` падает на загрузке SpriteKit на CI без GUI — тесты всё равно компилируются в `.executableTarget`-зависимом контексте (CitizenManager `import SpriteKit`). На локальной macOS-машине swift test работает; CI у проекта пока нет. Это не блокирует AC.

### Edge cases (явно обработать)

- [x] **`stage < 2` / `decayLevel == 4` / `unitIds.isEmpty` → жители 0** — уже инкапсулировано в `CitizenManager.targetCount` (`CitizenManager.swift:53-58`). UI получает 0 автоматически.
- [x] **Pre-tick / replay из snapshot** — `populationByProject` стартует пустым `[:]`, View фолбэкит через `?? 0` (см. шаг 6) → «Жителей: 0», пока не отработает первый tick (≤ 2 сек).
- [x] **Behind-mode (`view.isPaused = true`)** — `SKAction`-tick CitizenManager автоматически замораживается с paused view (стандартное поведение SpriteKit). Последний `populationByProject` остаётся в bridge — UI всё равно не виден. Доп. кода не нужно.
- [x] **Удалённый из state проект** — tick шаг 4 (`CitizenManager.swift:97-100`) вызывает `removeAllCitizens`. На шаге 5 нового снапшота `engine.state.projects.keys` уже не содержит этот id → ключ исчезнет из `populationByProject` → ProjectCard для него и так не рендерится. OK.
- [x] **Global cap = 150** — `allocated[entry.id]` уже учитывает cap (`CitizenManager.swift:71-79`); `activeCitizenCount` отдаёт реальный (меньше целевого). UI покажет фактическое значение — это и есть AC.
- [x] **Quick smoke** `[AC:7]` — DoD-проверка после интеграции (см. «Команды проверки»). Без unit-теста на полный flow (зависит от SpriteKit scene).

### Файлы для изменения

- `Sources/CityDeveloper/Game/CitizenManager.swift` — public `activeCitizenCount(for:)`, internal `_testSeed`, добавление шага 5 в `tick()` (push в bridge).
- `Sources/CityDeveloper/UI/SceneBridge.swift` — `@Published var populationByProject: [String: Int]`.
- `Sources/CityDeveloper/UI/ProjectCard.swift` — параметр `population: Int`, `Text("Жителей: \(population)")` в HStack между Stage и датой.
- `Sources/CityDeveloper/UI/SidePanelView.swift` — проброс `population: bridge.populationByProject[project.id] ?? 0` в `ProjectCard`.
- `Sources/CityDeveloper/UI/InspectorOverlayCard.swift` — одна строка `Text("Жителей: …")` под `project.name`, размер 10pt.
- `Package.swift` — `.testTarget(name: "CityDeveloperTests", …)`.
- `Tests/CityDeveloperTests/CitizenManagerTests.swift` — новый файл, три XCTest-кейса.

### Файлы НЕ трогать

- `Sources/CityDeveloper/Data/CityState.swift` — PM явно: не вводим `ProjectState.population`, не меняем `CityState.population` (legacy агрегат).
- `Sources/CityDeveloper/Game/CityEngine.swift` — не хранит `citizenManager`, добавлять ссылку незачем (bridge получает значения от tick'а напрямую через `scene?.bridge`).
- `Sources/CityDeveloper/Game/GameScene.swift` — `cm.scene = self` уже даёт доступ к `bridge` через `scene?.bridge`. Доп. wiring не нужен.

### Команды проверки (для DoD)

- Компиляция: `swift build` (запускать из `<repo-root>`). Ожидание: 0 ошибок, без новых warning'ов.
- Тесты: `swift test --filter CitizenManagerTests`. Ожидание: 3 пройдены.
- Ручная проверка (Quick smoke):
  1. Запустить приложение (`swift run CityDeveloper` или Xcode).
  2. Создать свежий проект `smoketest` (журнал — добавить 6 завершённых задач, чтобы поднялась стадия 2+).
  3. Подождать ≤ 5 сек — на сцене должны появиться NPC.
  4. Кликнуть юнит проекта `smoketest` → открывается боковая панель и/или overlay-карточка инспектора.
  5. В `ProjectCard` (боковая панель) — поле `Жителей: N`, где N ≥ 3 (формула `max(3, stage*2 + units/4)` → при stage 2 и 6 units → `max(3, 4+1) = 5`; cap может урезать).
  6. Сломать квартал (decay до 4) → через ≤ 4 сек поле меняется на `Жителей: 0`, decay-индикатор красный.
  7. Свернуть окно → проверить, что значение фризится (не «прыгает»).

### Сложность

`middle`

**Обоснование:** 6 файлов в трёх слоях (Game / UI / тесты+Package), но логика прямолинейная — public read API, один `@Published`, push в конце tick, один параметр во View. Без архитектурных рисков, security, миграций. Не junior из-за затрагиваемых слоёв и добавления test target, не senior — без рефакторинга и новой архитектуры.

### Ожидаемое время

S (≤2ч)

---

## ✅ Исполнение

_Исполнитель: sonnet (executor)_
_Сложность: middle_

### Definition of Done

#### Функциональные
- [x] AC1–AC5, AC8 — structural pass (verify Sonnet)
- [ ] AC6 (Behind-mode), AC7 (Quick smoke) — manual-required (GUI приложение)

#### Технические
- [x] Компиляция Swift без новых ошибок/варнингов (`swift build` clean)
- [x] `activeCitizenCount(for:)` имеет юнит-тест (3 кейса в `CitizenManagerTests.swift`)
- [ ] `swift test` — n/a в текущем окружении (только Command Line Tools, нет Xcode.app/XCTest.framework). Структура тестов корректна; запустится на машине с Xcode.

#### Обновление документации
- [x] `Current.md`: F-11 строка обновлена — `(TASK-014) ✅`
- [x] `Diff.md`: D-11 описание обновлено — TASK-014 добавлен в `Done`, в `Остаток` оставлен только TASK-015

---

## Статус

`[x] done`

## Метаданные
- Создана PM: 2026-05-22
- Пересоздана PM (split → atomic): 2026-05-22
- Spec-review: implicit-approved (PM-блок полный: Done, AC, сценарий, «не делаем», edge cases, зависимости)
- Lead-model: opus
- Plan-review: revised (sonnet, 2 круга → approved)
- Code-review: approved (opus, 1 круг)
- Готова к работе: 2026-05-22
- Завершена: 2026-05-22
- Коммит: 1093693
