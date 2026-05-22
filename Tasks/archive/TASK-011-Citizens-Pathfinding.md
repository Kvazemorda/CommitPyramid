# TASK-011: Жители — waypoint pathfinding по дорогам внутри квартала

## Связь
- **F-10** Жители и анимация
- **D-10**
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим

Оживить квартал движущимися жителями. Простые спрайты ходят по дорожной сетке
квартала, не выходят за границы. Население = функция от количества юнитов и
stage; при уменьшении юнитов лишние жители плавно «уходят» с карты. Не AI,
не behaviour trees — простой waypoint random walk.

### Пользовательский сценарий

1. В explore-режиме в квартале со stage 2+ я вижу 3-5 движущихся жителей,
   которые перемещаются между точками дорожной сетки квартала.
2. Жители используют дороги (юниты типа `road`) как пути; на тайлы зданий не
   заходят.
3. Когда я добавляю задачи в проект (растёт `taskCount`, юниты прибавляются) —
   количество жителей плавно увеличивается до целевого.
4. Когда юниты уменьшаются (decay уничтожил пару) — жители плавно уходят с
   карты с анимацией исчезновения (alpha fade) за 5-10 сек.
5. Жители не выходят за границы своего квартала.

### Acceptance criteria

- [ ] **Файл:** `Game/CitizenManager.swift` — менеджер, **owned by `GameScene`**.
      Поддерживает целевое количество жителей для каждого проекта со stage ≥ 2.
- [ ] **Население квартала:**
  - **Жёсткие инварианты** (приёмочные):
    - `stage ≥ 2 ∧ decay < 4 ∧ unitIds.count > 0 ⇒ target ≥ 3`
    - `target ≤ 20` всегда
    - `decay == 4 ∨ unitIds.count == 0 ⇒ target == 0`
  - **Default-формула** (тюнится лидом, не приёмочное AC):
    `target = min(20, stage * 2 + unitIds.count / 4)` при выполнении первого
    инварианта; `target = 0` при выполнении третьего.
  - **Глобальный лимит:** не более **150** жителей одновременно на карте.
    При превышении — приоритет проектам с высоким `lastActivityAt`. При
    `N кварталов × 3 > 150` инвариант «≥ 3 в каждом» ослабляется
    пропорционально (зафиксировать в `Bugs.md` если фактически наступает).
- [ ] **Спрайт:** через `CitizenSprites.makeCitizen(seed:)` из TASK-009.
      `seed = "\(project.id)-\(citizenIndex)"`.hashValue.
- [ ] **Waypoint pathfinding:**
  - На каждый юнит типа `road` в проекте создаётся waypoint в центре его
    изометрического тайла.
  - Если в квартале нет дорог — fallback waypoints: центры нежилых тайлов
    (`forum`, `market`, `well`, `warehouse`). Если их тоже нет — случайные
    точки в bounding box ± 4 тайла от `districtOrigin`.
  - Путь от текущей точки до следующей — `SKAction.move(to:duration:)`,
    скорость **30 pt/сек** по экрану (единственная единица; «изометрический
    тайл/сек» не используется как мера).
  - По достижении waypoint житель выбирает следующий случайный waypoint,
    не совпадающий с текущим.
- [ ] **Bounding box:** жители не выходят за пределы `districtOrigin ± 6
      тайлов` (квадратный регион в grid-координатах). Шаг между кварталами
      из `DistrictPlanner` — 14 клеток, поэтому ±6 даёт зазор 1 клетки до
      соседа. Граничные тайлы между кварталами **не** являются waypoint-
      кандидатами ни для одного из соседних проектов.
- [ ] **Появление новых жителей при росте target:** fade-in 1 сек на
      случайном waypoint квартала.
- [ ] **Уход при уменьшении target:** лишние жители заканчивают текущий путь,
      затем исчезают с fade-out 1 сек. Полное обновление до нового target
      укладывается в 5-10 сек (Done-критерий F-10).
- [ ] **z-positioning:** `zPosition` пересчитывается **при достижении
      waypoint** (момент смены тайла), значение `-CGFloat(currentGridPos.x +
      currentGridPos.y) + 0.5`. Между waypoint'ами z не меняется (житель
      «несёт» зет своего стартового тайла до конца отрезка).
- [ ] **Click-события:** `isUserInteractionEnabled = false` на всех нодах
      жителей.
- [ ] **Производительность:**
  - При 50 жителях одновременно на карте FPS ≥ 60 на M1+.
  - При 100 жителях FPS ≥ 45 на M1+ (мягкая граница).
  - Метод измерения: `SKView.showsFPS = true` в debug, контрольный сценарий
    explore-режим со статичной камерой, измерение 30 сек.
- [ ] **Decay 4 (руины):**
  - Если руины **остаются за тем же проектом** (TASK-008 без перехода
    владельца) — `target = 0`, все жители уходят с fade-out.
  - Если руины **заняты новым проектом** (будущая F-06) — `CitizenManager`
    пересчитывает target для нового проекта-владельца; жители старого проекта
    исчезли, жители нового появляются по обычному pipeline (через target).
- [ ] **Behind-режим:** при переходе в behind все жители замирают
      (`SKView.isPaused = true` или собственный флаг); при возврате в
      explore — продолжают с того же waypoint. Это решение принято для
      экономии CPU/батареи; дух «город живёт когда смотришь».
- [ ] **Cold start / replay:** жители появляются с задержкой 1-2 сек после
      открытия explore-режима (визуально приятнее: сначала видна карта,
      потом «оживает» движение).

### Что НЕ делаем (границы скоупа)

- Не делаем A*-pathfinding — только waypoint random walk.
- Не делаем коллизии между жителями (могут проходить друг сквозь друга).
- Не делаем «работу» жителей (стояние у мастерской, торговля).
- Не делаем диалоги, попап при клике на жителя.
- Не делаем караваны между кварталами — backlog.
- Не сохраняем позиции жителей в `events.jsonl` или state — жители
  эфемерны.
- Не делаем приоритет «правильных» путей (вдоль дорог, не диагонали) —
  жители ходят по прямой между waypoint'ами.

### Edge cases

- [ ] **Квартал без дорог:** fallback waypoints (forum/market/well/warehouse).
      Если их нет — случайные точки в ±4.
- [ ] **`stage ≥ 2 ∧ units == 0`** (теоретически невозможно): инвариант
      `target = 0` выигрывает над формулой; жителей нет.
- [ ] **decay 4 без передачи владения:** все жители уходят.
- [ ] **decay 4 с передачей владения** (F-06): target пересчитывается под
      нового владельца; старые жители уже ушли, новые появляются.
- [ ] **Replay лога / cold start:** жителей нет, разворачиваются на 1-2 сек
      позже.
- [ ] **Behind-режим:** жители замирают.
- [ ] **Системная пауза (`SKView.isPaused = true`):** жители замирают;
      при resume — продолжают с текущего waypoint.
- [ ] **Большое количество кварталов (16+ × 3 жителя > 50):** глобальный
      лимит 150 не превышен. Если когда-нибудь будет 51+ квартал — инвариант
      «≥ 3 в каждом» ослабляется (это пограничный сценарий, через который
      город вряд ли пройдёт за разумное время).
- [ ] **Замена юнита `road` на руины (decay 4):** waypoint удаляется из
      списка; жители, идущие на него, выбирают ближайший живой waypoint.

### Зависимости

- **F-13 / TASK-009** (`CitizenSprites.makeCitizen(seed:)`) — спрайт жителя
  с анимацией ходьбы. Без TASK-009 эта задача не стартует.
- **F-08** (stage) — триггер «появились жители» при stage ≥ 2.
- **F-06** (district planner) — `districtOrigin` и шаг между кварталами
  (14). Бесшовная передача владения руинами — будущая F-06, в TASK-011
  только реакция (см. AC «decay 4»).
- **F-09 / TASK-008** (decay) — при decay 4 убрать жителей; рассчитанный
  decay уже в `ProjectState.decayLevel`.
- **Существующая инфраструктура:** `GameScene`, `CityEngine`,
  `DistrictPlanner` (шаг 14), `Palette`.

### Дизайн

Из `DesignConcept.md`:
- Стилистика — упрощённая египетская изометрия; силуэт.
- Скорость ходьбы — 30 pt/сек по экрану.
- z-order: между дорогой и зданиями.
- tileSize 64×32 pt.

### Done-критерий

_Из `Concept.md` F-10 (дословно):_ В каждом квартале со stage ≥ 2 видны
минимум 3 движущихся жителя. Жители не выходят за границы своего квартала.
FPS не падает при 50+ жителях на карте. При уменьшении количества юнитов
число жителей плавно (за 5-10 сек) приходит к новому целевому значению.

_Уточнение FPS:_ ≥ 60 FPS при 50 жителях; ≥ 45 FPS при 100 жителях
(M1+). Сценарий «50+» в концепте трактуется как «не ниже 50», верхняя
граница теста — 100; за пределами лимита 150 поведение не гарантировано.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-22_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния
- `CitizenSprites.makeCitizen(seed:)` — будет создан в TASK-009. Зависимость.
- `DistrictPlanner.allocateNextOrigin(currentIndex:)` — шаг между кварталами 14 клеток (TASK-005).
- `Game/GameScene.swift` — owner-кандидат для `CitizenManager`. Изометрия: `isoPosition(grid:) -> CGPoint`.
- `CityEngine.state.projects` / `.units` доступны через engine.
- `UnitState.kind == .road` — waypoints из дорог.

### Архитектурное решение
`CitizenManager` — обычный класс, owned by `GameScene`. Держит:
- `projectCitizens: [String: [CitizenNode]]` — список нод по проекту.
- Глобальный счётчик `totalCitizens` (с лимитом 150).
- `SKAction.repeatForever` tick раз в 2 сек: для каждого проекта пересчитать target, добавить/убрать жителей.

Движение: на каждого жителя — `SKAction.move(to:duration:)` через цепочку waypoint'ов. По достижении waypoint — completion handler выбирает новый и запускает следующий move. Не используем `SKAction.repeatForever` со static-цепочкой, потому что waypoint'ы могут меняться (decay → роад удалён). Также completion handler пересчитывает `zPosition` по новой grid-позиции.

Glоbal лимит 150: при пересчёте target — если `currentTotal + delta > 150`, режем `target` пропорционально, приоритет — проекты с `lastActivityAt` desc.

### Пошаговая декомпозиция

1. **CitizenManager — каркас** `[AC:1,2]`
   - Файл: `Sources/CityDeveloper/Game/CitizenManager.swift` (новый)
   - Скелет:
     ```swift
     final class CitizenManager {
         weak var engine: CityEngine?
         weak var scene: GameScene?
         private struct Citizen {
             let id: UUID
             let projectId: String
             let node: SKNode
             var currentGrid: GridPoint
         }
         private var citizens: [String: [Citizen]] = [:]
         private let speed: CGFloat = 30  // pt/сек по экрану
         private let globalCap = 150
         func start() {
             let tick = SKAction.repeatForever(SKAction.sequence([
                 SKAction.wait(forDuration: 2.0),
                 SKAction.run { [weak self] in self?.tick() }
             ]))
             scene?.run(tick, withKey: "citizenTick")
         }
         func stop() { scene?.removeAction(forKey: "citizenTick") }
     }
     ```

2. **Target-расчёт с инвариантами** `[AC:2]`
   - Файл: `Sources/CityDeveloper/Game/CitizenManager.swift`
   - Метод:
     ```swift
     private func targetCount(for project: ProjectState) -> Int {
         if project.unitIds.isEmpty || project.decayLevel == 4 { return 0 }
         if project.stage < 2 { return 0 }
         let formula = min(20, project.stage * 2 + project.unitIds.count / 4)
         return max(3, formula)  // инвариант ≥ 3 при stage ≥ 2 ∧ units > 0
     }
     ```

3. **tick — основной цикл** `[AC:2,5,6,7,12]`
   - Файл: `Sources/CityDeveloper/Game/CitizenManager.swift`
   - Логика:
     ```swift
     private func tick() {
         guard let engine = engine else { return }
         // 1. Подсчитать желаемые target'ы
         var desired: [(String, Int, Date)] = []
         for project in engine.state.projects.values {
             desired.append((project.id, targetCount(for: project), project.lastActivityAt))
         }
         // 2. Глобальный лимит — урезаем по приоритету lastActivityAt desc
         let sortedDesired = desired.sorted { $0.2 > $1.2 }
         var remaining = globalCap
         var allocated: [String: Int] = [:]
         for (id, target, _) in sortedDesired {
             let alloc = min(target, remaining)
             allocated[id] = alloc
             remaining -= alloc
         }
         // 3. Применить
         for (projectId, target) in allocated {
             guard let project = engine.state.projects[projectId] else { continue }
             let current = (citizens[projectId] ?? []).count
             if current < target {
                 for _ in 0..<(target - current) { spawnCitizen(in: project) }
             } else if current > target {
                 let toRemove = current - target
                 removeCitizens(projectId: projectId, count: toRemove)
             }
         }
         // 4. Cleanup: проекты, удалённые из state
         for projectId in citizens.keys where engine.state.projects[projectId] == nil {
             removeAllCitizens(projectId: projectId)
         }
     }
     ```

4. **Waypoint-фабрика** `[AC:3]`
   - Файл: `Sources/CityDeveloper/Game/CitizenManager.swift`
   - Метод:
     ```swift
     private func waypoints(for project: ProjectState) -> [GridPoint] {
         guard let engine = engine else { return [] }
         let units = project.unitIds.compactMap { engine.state.units[$0] }
         // Priority 1: roads
         let roads = units.filter { $0.kind == .road }.map { $0.position }
         if !roads.isEmpty { return roads }
         // Priority 2: non-residential
         let nonRes = units.filter { [.forum, .market, .well, .warehouse].contains($0.kind) }.map { $0.position }
         if !nonRes.isEmpty { return nonRes }
         // Priority 3: random ±4 from districtOrigin
         let origin = project.districtOrigin
         return (0..<6).map { _ in GridPoint(x: origin.x + Int.random(in: -4...4), y: origin.y + Int.random(in: -4...4)) }
     }
     ```

5. **spawnCitizen + walk** `[AC:1,3,4,8]`
   - Файл: `Sources/CityDeveloper/Game/CitizenManager.swift`
   - Скелет:
     ```swift
     private func spawnCitizen(in project: ProjectState) {
         guard let scene = scene else { return }
         let waypts = waypoints(for: project)
         guard let firstWp = waypts.randomElement() else { return }
         let index = (citizens[project.id]?.count ?? 0)
         let seed = "\(project.id)-\(index)".hashValue
         let node = CitizenSprites.makeCitizen(seed: seed)
         node.isUserInteractionEnabled = false
         node.alpha = 0
         node.position = scene.isoPosition(grid: firstWp)
         node.zPosition = -CGFloat(firstWp.x + firstWp.y) + 0.5
         scene.worldNode.addChild(node)
         let citizen = Citizen(id: UUID(), projectId: project.id, node: node, currentGrid: firstWp)
         citizens[project.id, default: []].append(citizen)
         node.run(SKAction.fadeIn(withDuration: 1.0))
         walk(citizen: citizen)
     }
     private func walk(citizen: Citizen) {
         guard let engine = engine, let project = engine.state.projects[citizen.projectId],
               let scene = scene else { return }
         let waypts = waypoints(for: project)
         guard let next = waypts.filter({ $0 != citizen.currentGrid }).randomElement() else { return }
         // Bounding box clamp ±6 от districtOrigin (исключая граничные)
         let origin = project.districtOrigin
         let dx = next.x - origin.x, dy = next.y - origin.y
         guard abs(dx) < 6 && abs(dy) < 6 else { walk(citizen: citizen); return }  // повтор
         let targetPos = scene.isoPosition(grid: next)
         let distance = hypot(targetPos.x - citizen.node.position.x, targetPos.y - citizen.node.position.y)
         let duration = distance / speed
         citizen.node.run(SKAction.move(to: targetPos, duration: duration)) { [weak self] in
             guard let self = self else { return }
             // Обновить grid и zPosition
             if var c = self.findCitizen(id: citizen.id) {
                 c.node.zPosition = -CGFloat(next.x + next.y) + 0.5
                 self.updateCitizen(id: c.id, currentGrid: next)
                 self.walk(citizen: c)
             }
         }
     }
     ```

6. **removeCitizens — fade-out 1 сек** `[AC:5]`
   - Файл: `Sources/CityDeveloper/Game/CitizenManager.swift`
   - Метод:
     ```swift
     private func removeCitizens(projectId: String, count: Int) {
         guard var list = citizens[projectId] else { return }
         let toGo = Array(list.prefix(count))
         for c in toGo {
             c.node.run(SKAction.sequence([SKAction.fadeOut(withDuration: 1.0), SKAction.removeFromParent()]))
         }
         list.removeFirst(min(count, list.count))
         citizens[projectId] = list
     }
     ```

7. **Cold-start задержка + behind пауза** `[AC:14,13]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift`
   - В `didMove`: `let citizenMgr = CitizenManager(); citizenMgr.engine = engine; citizenMgr.scene = self`. Запуск `citizenMgr.start()` через `run(SKAction.wait(forDuration: 1.5))` — задержка 1-2 сек.
   - Behind-пауза — общая через `SKView.isPaused = true` (см. TASK-010 шаг 9). Не нужно отдельно паузить CitizenManager.

8. **Глобальный лимит и приоритет** `[AC:2 + edge: 16+ кварталов]`
   - Реализовано в `tick()` (шаг 3) через sort by `lastActivityAt` desc и режущий цикл remaining=150.

9. **Decay 4 + передача владения**
   - При `tick()` проект с `decayLevel == 4` получает target = 0 → citizens плавно уходят.
   - Передача владения (новый проект на руинах) — F-06, не в TASK-011. CitizenManager на это среагирует автоматически: старый проект исчез из state.projects (или новый занял слот) — citizens мигрируют через стандартный target-pipeline.

### Edge cases (явно обработать)
- [ ] Квартал без дорог: fallback waypoints (forum/market/well/warehouse) → если их нет, random ±4 (шаг 4).
- [ ] `stage ≥ 2 ∧ units == 0`: невозможно по модели (units пишется до stage-up); но `targetCount` возвращает 0 (см. шаг 2 — `unitIds.isEmpty` checked first).
- [ ] decay 4: target = 0, все уходят за 1 сек.
- [ ] decay 4 + новый проект-владелец (F-06): pipeline сам разрулит через смену state.
- [ ] Replay/cold start: задержка 1.5 сек через `SKAction.wait` в `didMove`.
- [ ] Behind: `SKView.isPaused = true` (общая пауза, как в TASK-010).
- [ ] App pause: то же.
- [ ] 50+ кварталов: глобальный лимит 150 ослабляет инвариант ≥3 пропорционально (по AC; фиксировать в `Bugs.md` если фактически наступает).
- [ ] Road→ruin: на следующем tick'е `waypoints(for:)` пересчитает (этот юнит больше не .road, либо удалён); идущие закончат текущий segment, на следующем walk()-вызове выберут живой waypoint.

### Файлы для изменения
- `Sources/CityDeveloper/Game/GameScene.swift` — init CitizenManager + публичный `worldNode` (либо доступ через `scene.world` — сделать internal).

### Файлы НЕ трогать
- `CityEngine`, `DistrictPlanner`, `UnitPlanner` — модель неизменна
- `CitizenSprites` — потребитель, не модифицирует

### Новые файлы
- `Sources/CityDeveloper/Game/CitizenManager.swift`

### Команды проверки (для DoD)
- Компиляция: `swift build`
- Запуск: `swift run CityDeveloper`
- `SKView.showsFPS = true`.
- Создать проект, накопить 10+ задач (включая дорогу/road) → дождаться stage 2 → видны 3+ жителей, движутся по дорогам.
- Тест: поднять `decayLevel = 4` вручную → жители уходят за 1 сек.

### Сложность
`middle`

**Обоснование:** 1 новый файл, 1 правка. Логика waypoint-walker — линейная, но требует аккуратности в управлении completion-handler'ами и lifetime нод. Глобальный лимит и инвариант ≥3 — внимательно.

### Ожидаемое время
M (≤ 1 день)

### Plan-review правки (round 1 → applied)

1. **CRITICAL — `citizens` хранилище: flat dict по UUID + project-index.** Заменить `citizens: [String: [Citizen]]` на:
   ```swift
   private var citizens: [UUID: Citizen] = [:]
   private var citizensByProject: [String: Set<UUID>] = [:]
   private var citizensLeaving: Set<UUID> = []  // двухфазное удаление
   ```
   `Citizen` — `final class` (reference type), чтобы mutation `currentGrid` работала естественно.

2. **CRITICAL — bounding box `<= 6` (inclusive), не `< 6`:**
   ```swift
   guard abs(dx) <= 6 && abs(dy) <= 6 else { walkFallback(citizen: c, project: project); return }
   ```
   Bounded retry: `walkFallback` — выбирает waypoint строго в пределах ±6 (если все вне — выбирает `districtOrigin`).

3. **CRITICAL — двухфазное удаление в `removeCitizens`:**
   ```swift
   private func removeCitizens(projectId: String, count: Int) {
       let ids = (citizensByProject[projectId] ?? []).filter { !citizensLeaving.contains($0) }.prefix(count)
       for id in ids {
           citizensLeaving.insert(id)
           guard let c = citizens[id] else { continue }
           c.node.removeAllActions()
           c.node.run(SKAction.sequence([
               SKAction.fadeOut(withDuration: 1.0),
               SKAction.run { [weak self] in
                   self?.citizens.removeValue(forKey: id)
                   self?.citizensByProject[projectId]?.remove(id)
                   self?.citizensLeaving.remove(id)
               },
               SKAction.removeFromParent()
           ]))
       }
   }
   ```
   `totalActiveCitizens` (для лимита 150) считает `citizens.count` — включая `leaving`. Это предотвращает double-spawn.

4. **Walk-completion:** обновление currentGrid через class-reference (`c.currentGrid = next`), `findCitizen`/`updateCitizen` не нужны — работаем с reference прямо. Защита от смерти:
   ```swift
   c.node.run(SKAction.move(to: targetPos, duration: duration)) { [weak self] in
       guard let self, let citizen = self.citizens[c.id], !self.citizensLeaving.contains(c.id) else { return }
       citizen.currentGrid = next
       citizen.node.zPosition = -CGFloat(next.x + next.y) + 0.5
       self.walk(citizen: citizen)
   }
   ```

5. **handleUnitBuilt не используется** — все spawn'ы через `tick()` раз в 2 сек. Это явное design-decision: задержка ≤ 2 сек между появлением юнита и реакцией CitizenManager приемлема (Done F-10 требует 5-10 сек).

6. **Behind-pause — общий `SKView.isPaused`** (через WindowModeManager.onModeChange, см. TASK-010 правки). Если TASK-010 не готов — временный fallback: подписка CitizenManager на NSApplication.willResignActive прямо.

7. **`seed` для жителей при respawn:** использовать монотонно растущий счётчик `nextCitizenSeed` (не `count`), чтобы удалённые/новые жители получали разные seed'ы.

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Done-критерий проверен: в квартале со stage 2 видны 3+ жителя;
      decay-тест — плавно уходят за 5-10 сек

#### Технические
- [ ] `swift build` без новых ошибок
- [ ] FPS ≥ 60 при 50 жителях (метод измерения по AC)
- [ ] Жители замирают в behind-режиме

#### Обновление документации
- [ ] `current.md`: F-10 ❌ → ✅
- [ ] `diff.md`: D-10 удалён

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
- Исполнитель: sonnet
- Code-review: approved (opus)
- Коммит: —
