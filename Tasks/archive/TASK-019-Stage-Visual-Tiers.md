# TASK-019: Визуальная подмена tier по стадиям квартала 0→5 (F-08)

## Связь
- **F-08** Стадии развития квартала (0 → 5)
- **D-08** из diff.md
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим

Расчёт stage 0→5 (по формуле от `taskCount`, `projectAge`, `activityRate`) уже
работает. Сейчас визуальная подмена tier юнитов при апгрейде сводится только к
изменению высоты куба — это недостаточно (см. D-08: «нужна замена силуэта/декора»).
Нужно: каждой стадии 0–5 сопоставить **отдельный sprite-tier** (силуэт +
декор), и при переходе квартала на новый stage заменять у существующих
юнитов sprite-tier **на месте**, без пересоздания координат. Stage-маппинг
из F-08: 0 = луг, 1 = лачуги, 2 = деревянная застройка, 3 = каменный квартал,
4 = развитый, 5 = роскошный.

**Расширение арт-каталога F-13.** Базовые силуэты 12 типов в `UnitSprites.swift`
не трогаем — добавляем поверх **категориальный tier-набор**: 4 категории
(жилые / инфра / производство / социальное) × 5 stage = **20 спрайтов**, по
одному на «категория × stage». Конкретный подтип юнита (например, лачуга vs
дом vs вилла внутри категории «жилые») в этой задаче не уточняем — все юниты
категории «жилые» на stage 3 показывают «каменный жилой» силуэт. Расширение
до 12 типов × 5 stage = 60 спрайтов — отдельная итерация в `Backlog.md`
(новая идея, не блокер).

### Пользовательский сценарий

1. Пользователь в `tasks.jsonl` накапливает задачи в проекте `delta` — stage
   квартала по формуле растёт со временем 0 → 1 → 2 → 3 → 4 → 5.
2. При переходе District'а на новый stage система видит изменение
   `district.stage`.
3. Для каждого юнита квартала система **заменяет sprite-tier** (силуэт +
   декор) на соответствующий новому stage. Координаты юнита (`x`, `y`) и его
   тип (жилой/инфра/прод/соц по F-07) **не меняются** — меняется только
   визуальный tier.
4. Пользователь визуально видит: лачуги → деревянные дома → каменные дома →
   многоэтажные → роскошные виллы (для категории «жилые»). Аналогично для
   остальных категорий — свой tier-набор каждой категории.
5. Replay того же `tasks.jsonl` (через snapshot reset) даёт ту же
   последовательность апгрейдов на тех же координатах.

### Acceptance criteria

- [ ] **Все 5 stage-переходов реализованы:** для каждого перехода 0→1, 1→2,
      2→3, 3→4, 4→5 у юнитов квартала меняется sprite-tier (силуэт + декор),
      не только высота куба. Визуально различимо при сравнении скриншотов до/после.
- [ ] **Координаты не меняются:** между переходами **bottom-centre anchor**
      каждого юнита `(unit.x, unit.y)` неизменен — проверяется smoke-тестом
      (запомнить anchor до перехода, сверить после; bbox не сверяем, т.к.
      высота меняется).
- [ ] **Категория не меняется:** жилой остаётся жилым, инфра — инфрой и т.д.
      Только tier-визуал изменяется внутри категории.
- [ ] **Категориальная матрица 4×5 = 20 спрайтов** (`stage 1..5`): жилые
      (лачуга→деревянный→каменный→многоэтажный→вилла), инфра
      (примитив→досчатый→каменный→облагороженный→роскошный), производство
      (аналогично), социальное (аналогично). На stage 0 — пустой луг, юниты
      не появляются.
- [ ] **Анимация перехода:** state-замена tier атомарна (1 тик SpriteKit).
      Визуальный кросс-фейд старый→новый sprite ≤ **0.5 сек на юнит**,
      запускается параллельно для всех юнитов квартала, общее визуальное
      окно ≤ 0.5 сек независимо от числа юнитов.
- [ ] **Tier выводится из stage детерминированно** (lookup-таблица
      `(category, stage) → sprite`). В snapshot tier отдельно НЕ
      сериализуется — миграции state-формата нет.
- [ ] **Replay-детерминированность:** двойной прогон одного `tasks.jsonl`
      даёт идентичную последовательность tier-замен на тех же anchor-
      координатах. При нормальном тике stage растёт по 1 — все промежуточные
      стадии видны; при load snapshot с большим разрывом — tier мгновенно
      целевой, без промежуточных (визуал отличается от первого прогона —
      это **ожидаемо** и не нарушает state-детерминированность).
- [ ] **FPS-метрика:** Instruments Time Profiler, сцена с 500 юнитов в
      одном квартале, форсированный переход stage 2→3, окно замера
      2 секунды после триггера, **минимум по фрейму ≥ 50 FPS** на M1
      baseline (1× scale, окно по умолчанию).

### Что НЕ делаем (границы скоупа)

- Не меняем формулу stage (F-08 «расчёт работает» — D-08 явно это
  отделяет).
- Не вводим новые типы юнитов (F-07 / D-16 — отдельный скоуп).
- Не редактируем существующие базовые силуэты F-13 — только **добавляем**
  20 новых категориальных tier-спрайтов поверх. Существующие 12 типов
  продолжают использоваться для логики/детекции, но визуал на сцене берётся
  из категориальной матрицы.
- Не делаем матрицу 12 типов × 5 stage (60 спрайтов) — это отдельная идея
  в `Backlog.md`, не блокер.
- Не trогаем decay-визуал (F-09 закрыт).
- Не trогаем размещение District'ов (F-06).
- Не реализуем production-decay → откат stage. Stage в F-08 формуле
  монотонно неубывающий по `taskCount` и `projectAge`; `activityRate`
  влияет только на темп, не отрицательный.
- Не меняем `RoadConnector.swift` — дороги не tier'уются.

### Edge cases

- [ ] **Quit во время stage-перехода:** stage хранится в state, при load
      snapshot+tail tier выводится из текущего `district.stage` через lookup.
      Визуальный кросс-фейд (≤0.5 сек) не event-sourced — после старта
      приложения юниты сразу с целевым tier, без проигрывания fade.
- [ ] **Юнит появляется в момент перехода stage**: новый юнит сразу
      создаётся с tier текущего stage (не tier предыдущего).
- [ ] **Большой квартал (500+ юнитов) переходит на новый stage:**
      state-смена tier атомарна в одном тике; визуальный кросс-фейд
      ≤0.5 сек запускается параллельно для всех юнитов (`SKAction` на
      каждом sprite, общий runner), общее визуальное окно ≤0.5 сек.
- [ ] **Stage пропускает шаг при load snapshot** (большой разрыв в логе):
      tier мгновенно целевой, без промежуточных. При нормальном live-тике
      stage растёт по 1 — все промежуточные стадии видны последовательно.
- [ ] **Координатная сетка изометрии** (после возможного D-02 / SKTileMapNode):
      tier-замена работает на уровне sprite-node, anchor **bottom-centre**
      фиксируется в `UnitSprites.swift`, smoke-тест сверяет anchor-позицию,
      а не bbox (т.к. высота tier меняется).

### Зависимости

- **F-08** формула — закрыта. Источник `district.stage` и `unit.category`.
- **TASK-018** — **жёсткий pre-condition** (см. шаг 1 декомпозиции):
  TASK-019 начинается только после закрытого и закоммиченного TASK-018,
  который ввёл `UnitCategory` enum и `UnitKind.category` в
  `CityState.swift`. Без этого `makeCategoricalBuilding(category:stage:)`
  не компилируется. `grep -n "enum UnitCategory"` обязателен перед началом.
- **F-07** закрывается через TASK-018 (см. выше). После мерджа TASK-018
  `unit.kind.category` доступен везде.
- **F-13** Арт-каталог — закрыт. `UnitSprites.swift` расширяем 20 новыми
  категориальными tier-спрайтами.
- **F-12** Snapshots — закрыт. Tier выводится из stage детерминированно,
  отдельно не сериализуется → миграции state-формата нет.
- **D-02** SKTileMapNode — открыт. Не блокер: tier-замена работает на
  уровне sprite-node, независимо от земли.
- Нет внешних сервисов, секретов, миграций.

### Дизайн

Дизайн-источник: `DesignConcept.md` — палитра «древнее» (терракот, песок,
тёплый камень, тёмное дерево); силуэты должны читаться без анти-алиасинга
на 1× и 2× scale (см. F-02 done-criterion в `Current.md`). Конкретные tier-
варианты (силуэт + декор) — за лидом / арт-агентом на этапе раскладки;
PM фиксирует только семантическую прогрессию stage 1→5: бедно → деревянно
→ каменно → развито → роскошно. Никакого нового UI поверх сцены.

### Done-критерий

_Из concept.md F-08 (дословно):_

> При накоплении задач и времени проект последовательно меняет визуал через
> все 5 стадий. Координаты конкретного юнита не меняются между стадиями.
> Проект с высокой активностью (>5 событий/неделю) достигает stage 3 за <2
> недели; проект с низкой активностью (1 событие/неделю) — за >2 месяца.

**Скоуп данной задачи (закрывает только D-08, визуальная часть):**

> При смене `district.stage` N→N+1 у каждого юнита квартала меняется
> sprite (силуэт + декор), bottom-centre anchor `(x, y)` сохраняется,
> визуальный кросс-фейд завершается ≤ 0.5 сек на юнит (параллельно для
> всех), FPS ≥ 50 на сцене 500 юнитов (Instruments, окно 2 сек после
> триггера, M1 baseline).

Часть Done F-08 про темп (>5 событий/нед → stage 3 < 2 недель) — формула
F-08 уже закрыта, отдельно не проверяем.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-22_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

В коде уже есть:
- `Sources/CityDeveloper/Game/UnitSprites.swift` — 12 factory methods
  (`makeShack`, `makeHouse`, `makeVilla`, `makeWell`, `makeRoad`, `makeWarehouse`,
  `makeWorkshop`, `makeRawPit`, `makeMarket`, `makeForum`, `makeTemple`,
  `makeObelisk`, `makeRuin`). Каждый принимает `tier: Int`, но использует tier
  только для высоты куба (`height = base + tier*2`). Категориального
  tier-набора нет.
- `Sources/CityDeveloper/Game/UnitSprites.swift:10–57` —
  `UnitSprites.makeNode(unit: UnitState) -> SKNode` — центральная точка
  создания ноды; сейчас вызывается из `GameScene.drawUnit` (~строка 108).
- `Sources/CityDeveloper/Data/CityState.swift:4–14` — `UnitState.tier: Int`
  (mutable). Поле есть, но **не обновляется** после создания юнита.
- `Sources/CityDeveloper/Game/CityEngine.swift:203–208` — место, где
  `project.stage = newStage`. Сейчас никакого callback на `stage-up`
  нет. Существующие юниты квартала не обновляются.
- `Sources/CityDeveloper/Game/GameScene.swift:18` —
  `unitNodes: [UUID: SKNode]` — словарь визуальных нод, ключ `UnitState.id`.
- `Sources/CityDeveloper/Game/GameScene.swift:106–131` — `drawUnit(_:project:)`,
  выставляет `node.position = isoPosition(grid: unit.position)`. Anchor
  **не выставлен явно** (default `(0.5, 0.5)`).
- `Sources/CityDeveloper/App/AppDelegate.swift:40–48` — паттерн подписки
  на engine callbacks (`onUnitBuilt`, `onProjectCreated`, `onDecayChanged`).
- SKAction-style в проекте: `SKAction.group/sequence`, `fadeIn/Out`,
  `.easeOut` timing, длительность 0.4–1.5 сек.

Переиспользуем:
- Паттерн callback'ов engine→scene (`onUnitBuilt` как референс).
- Паттерн анимации (`SKAction.group` для параллели, `fadeIn/Out`).
- `isoPosition(grid:)` для координат.

Что нужно дописать:
- `UnitCategory` enum + `UnitKind.category` (если TASK-018 уже не добавил;
  координация через шаг 1 этого плана).
- 4 новые factory-функции `UnitSprites.makeResidentialStage(_:)`,
  `makeInfrastructureStage(_:)`, `makeProductionStage(_:)`,
  `makeSocialStage(_:)` — каждая возвращает 5 вариантов sprite-tier
  (stage 1..5).
- Общий вход `UnitSprites.makeCategoricalNode(category:stage:) -> SKNode`
  с явным bottom-centre anchor.
- Callback `onProjectStageChanged: ((_ projectId: String, _ oldStage: Int,
  _ newStage: Int) -> Void)?` в `CityEngine`.
- Обновление `state.units[uid].tier = newStage` для всех юнитов проекта
  при stage-up.
- Метод `GameScene.handleProjectStageChanged(projectId:oldStage:newStage:)`
  с параллельным cross-fade.
- Smoke-скрипт `Scripts/smoke-stage-tiers.sh` + перформ-чеклист (Instruments).

### Архитектурное решение

Tier-визуал переходит с per-kind-узких factory methods на **категориальный
набор** 4×5: каждой паре `(category, stage 1..5)` соответствует один новый
спрайт. Внутри категории все юниты выглядят одинаково. Это сознательное
упрощение по PM-постановке («4 категории × 5 stage = 20 спрайтов, расширение
до 12×5 = 60 — отдельная идея в Backlog»).

`UnitSprites.makeNode(unit:)` остаётся для совместимости с decay-визуалом и
другими местами, но `GameScene.drawUnit` переключается на новую точку
входа `UnitSprites.makeCategoricalNode(category: unit.kind.category, stage:
max(project.stage, 1))`. Это сохраняет существующий контракт ноды (контейнер
с тенью + ground tile + building), просто building становится «категориальным
tier-спрайтом» с явным `anchorPoint = (0.5, 0)`.

Stage-up callback идёт через `CityEngine`: после
`project.stage = newStage` (`CityEngine.swift:208`) — синхронно
обновляем `state.units[uid].tier = newStage` для всех `uid in project.unitIds`
и вызываем `onProjectStageChanged(projectId, oldStage, newStage)`. GameScene
для каждого `uid` строит новый категориальный spritе с `alpha = 0`,
добавляет в `unitNodes[uid]` и параллельно `SKAction.group([fadeOut старого
building, fadeIn нового])` ≤ 0.5 сек. После анимации — старый building
удаляется из node.

Atomic state: `state.units[uid].tier` обновляется в одном проходе main-queue,
поэтому snapshot, сохранённый сразу после, всегда видит финальное состояние.
Cross-fade — чисто визуальный (`SKAction`-based), не event-sourced. При load
snapshot после quit-в-фейде каждый юнит сразу с целевым spritе (тираж
`unit.tier` в момент snapshot = `project.stage`, lookup в категориальную
матрицу).

**Live-тик vs catch-up:** в обычном тике `applyTaskCompleted` повышает
stage по 1 за раз (формула F-08 монотонна). Catch-up при `replayFromLog`
(`CityEngine.swift:84–85`) идёт через apply tail-событий → каждое событие может
поднимать stage на 1; визуально это replay-фаза, callback `onProjectStageChanged`
работает, но `GameScene.handleProjectStageChanged` под флагом `animated=false`
(во время replay-фазы) делает мгновенную замену без cross-fade. Флаг
определяется в `AppDelegate` через состояние `engine.isReplaying` (нужно
ввести; см. шаг 5b).

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку. Шаг непонятен — НЕ импровизируй.

1. **Pre-condition: TASK-018 закрыта и закоммичена** `[blocker]`
   - **СТОП.** Перед началом этой задачи проверить:
     `grep -n "enum UnitCategory" Sources/CityDeveloper/Data/CityState.swift`
     должен дать ровно одну строку (объявление от TASK-018) и
     `grep -n "var category: UnitCategory" Sources/CityDeveloper/Data/CityState.swift`
     должен дать одну строку (extension от TASK-018).
   - Если оба `grep` пусты — **TASK-019 не начинать**, дождаться TASK-018.
     Это устраняет merge-конфликт в `CityState.swift`.
   - Если объявления есть — переиспользовать в `UnitSprites.swift` и
     `GameScene.swift` без модификации `CityState.swift`.

2. **20 категориальных tier-спрайтов в UnitSprites** `[AC:1,4]`
   - Файл: `Sources/CityDeveloper/Game/UnitSprites.swift`.
   - Действие: добавить публичную функцию-точку входа и 4 приватные factory.
     Каждая factory возвращает sprite-варианты для stage 1..5 (силуэт +
     цвет/декор + размер). Anchor — `bottom-centre`.
     ```swift
     static func makeCategoricalBuilding(
         category: UnitCategory,
         stage: Int
     ) -> SKNode {
         let s = max(1, min(stage, 5))
         switch category {
         case .residential:    return makeResidentialStage(s)
         case .infrastructure: return makeInfrastructureStage(s)
         case .production:     return makeProductionStage(s)
         case .social:         return makeSocialStage(s)
         }
     }
     private static func makeResidentialStage(_ stage: Int) -> SKNode {
         // stage 1 — лачуга (низкая, бурая): height 14
         // stage 2 — деревянный дом (выше, окно): height 20
         // stage 3 — каменный дом (квадрат, окно, дверь): height 28
         // stage 4 — многоэтажный (узкий высокий, 2 ряда окон): height 38
         // stage 5 — вилла (широкая, балкон, орнамент): height 46
         // IsoBuilder.cube + декор-узлы; anchor bottom-centre
     }
     // makeInfrastructureStage / makeProductionStage / makeSocialStage —
     // 5 stage-вариантов каждая, по аналогичной логике (силуэт + цвет +
     // декор-узел, минималистично).
     ```
   - Каждая stage-вариация — отдельный `SKSpriteNode` или композит на
     `IsoBuilder.cube`, `anchorPoint = CGPoint(x: 0.5, y: 0)` явно
     выставлен на root building-node.
   - Палитра из `DesignConcept.md` («древнее»: терракот, песок, тёплый
     камень, тёмное дерево). Точные RGB — на исполнителя, лидирующая
     прогрессия по AC: бедно (stage 1) → деревянно (2) → каменно (3) →
     развито (4) → роскошно (5).

3. **Точка входа для GameScene** `[AC:2,3]`
   - Файл: `Sources/CityDeveloper/Game/UnitSprites.swift`.
   - Действие: добавить функцию
     ```swift
     static func makeStageNode(unit: UnitState, stageOverride: Int? = nil) -> SKNode {
         let category = unit.kind.category
         let stage = stageOverride ?? max(unit.tier, 1)
         let container = SKNode()
         // shadow + ground tile — переиспользовать существующие helpers
         //   (вынести из makeNode, если повторение)
         let building = makeCategoricalBuilding(category: category, stage: stage)
         building.name = "building"   // ← КЛЮЧ для swapStageSprite (шаг 7)
         building.position = .zero
         container.addChild(building)
         container.userData = NSMutableDictionary()
         container.userData?[Self.unitIdKey] = unit.id
         container.userData?[Self.projectIdKey] = unit.projectId
         return container
     }
     ```
   - Объявить `static let projectIdKey = "projectId"` рядом с
     `unitIdKey` (если последнего ещё нет — добавить).

   **Архитектурное решение по anchor** (явное, не оставляем на лету):
   - Контейнер `SKNode` остаётся с **default anchor** (у `SKNode` нет
     `anchorPoint`, у `SKSpriteNode` — `(0.5, 0.5)` по умолчанию).
     `node.position = isoPosition(grid: unit.position)` в `GameScene.drawUnit`
     задаёт центр контейнера в координатах изометрической сетки — это
     текущее поведение.
   - Внутри `makeCategoricalBuilding`, если используется `SKSpriteNode`
     как корень building-узла, его `anchorPoint = CGPoint(x: 0.5, y: 0)`
     явно. `building.position = .zero` (на shadow/ground layer).
   - AC «координаты не меняются» трактуется как **`node.position` контейнера
     неизменно** между swap-операциями (smoke-тест сверяет именно его).
     Сам контейнер не пересоздаётся при swap, только building-child
     внутри — это автоматически выполняет AC.

4. **Переключить GameScene.drawUnit на makeStageNode** `[AC:1,2,3]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift:108`.
   - Действие: заменить
     `let node = UnitSprites.makeNode(unit: unit)`
     на
     `let node = UnitSprites.makeStageNode(unit: unit, stageOverride: project.stage)`.
   - Оставить `UnitSprites.makeNode(unit:)` без изменений (используется в
     других местах, в т.ч. в `decay4Ruin`).

5. **CityEngine: обновление tier и callback** `[AC:5,6,8]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`.
   - Действие 5a: рядом с другими callbacks (~строка 16–18) объявить
     ```swift
     var onProjectStageChanged: ((String, Int, Int) -> Void)?
     ```
   - Действие 5b: в `applyTaskCompleted` сохранить старый stage **до**
     обновления, обновить `unit.tier` для всех юнитов проекта, вызвать
     callback **только при `!silent`** (это автоматически делает callback
     no-op в `replayFromLog`, где `apply(e, silent: true)` —
     `CityEngine.swift:84–85`):
     ```swift
     let oldStage = project.stage
     // ... существующая логика computeStage / project.stage = newStage ...
     if newStage > oldStage {
         for uid in project.unitIds {
             state.units[uid]?.tier = newStage
         }
     }
     // (state.projects[projectKey] = project — где это происходит сейчас)
     if !silent && newStage > oldStage {
         onProjectStageChanged?(projectKey, oldStage, newStage)
     }
     ```
   - **Catch-up при load snapshot решается без флага isReplaying:**
     в `GameScene.didMove(to:)` (или эквивалентном hook, где сцена впервые
     рисует юниты из snapshot+tail) `drawUnit` уже вызывает
     `makeStageNode(unit:, stageOverride: project.stage)` — это даёт
     мгновенный целевой tier без анимации. Callback `onProjectStageChanged`
     не срабатывает во время replay (всё через `silent: true`), значит
     анимация не запускается. AC «при load snapshot с большим разрывом —
     tier мгновенно целевой» выполняется естественно.

6. **AppDelegate: подписка** `[AC:5]`
   - Файл: `Sources/CityDeveloper/App/AppDelegate.swift`, ~строка 46.
   - Действие: подписка простая, флага `isReplaying` нет —
     callback вызывается только при `!silent` (live-тике):
     ```swift
     engine.onProjectStageChanged = { [weak self] projectId, oldStage, newStage in
         self?.scene?.handleProjectStageChanged(
             projectId: projectId,
             oldStage: oldStage,
             newStage: newStage
         )
     }
     ```

7. **GameScene.handleProjectStageChanged + cross-fade** `[AC:1,2,3,5]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift`, рядом с
     `applyDecayToProject` (~строка 155).
   - Действие: новый метод (без флага `animated` — live-тик всегда
     анимированный; catch-up не идёт через этот callback):
     ```swift
     func handleProjectStageChanged(projectId: String, oldStage: Int, newStage: Int) {
         DispatchQueue.main.async { [weak self] in
             guard let self, self.didAttach,
                   let engine = self.engine,
                   let project = engine.state.projects[projectId] else { return }
             for uid in project.unitIds {
                 guard let oldNode = self.unitNodes[uid] else { continue }
                 self.swapStageSprite(in: oldNode, newStage: newStage)
             }
         }
     }
     private func swapStageSprite(in node: SKNode, newStage: Int) {
         // Guard: если на ноде уже руина (decayLevel == 4) —
         // skip swap, визуал руины приоритетен.
         if node.childNode(withName: "ruinNode") != nil { return }
         // 1. Найти старый building-child (name == "building"). Если nil —
         //    это нода, созданная старым makeNode без имени → skip swap
         //    (не наша проблема, легаси).
         guard let oldBuilding = node.childNode(withName: "building") else { return }
         // 2. Извлечь category из userData проекта/юнита (через engine
         //    или прокинуть параметром).
         guard let unitId = node.userData?[UnitSprites.unitIdKey] as? UUID,
               let unit = engine?.state.units[unitId] else { return }
         let category = unit.kind.category
         // 3. Построить новый building.
         let newBuilding = UnitSprites.makeCategoricalBuilding(category: category, stage: newStage)
         newBuilding.name = "building"
         newBuilding.alpha = 0
         node.addChild(newBuilding)
         // 4. Параллельный кросс-фейд ≤0.5 сек.
         let fadeOut = SKAction.sequence([
             SKAction.fadeOut(withDuration: 0.5),
             SKAction.removeFromParent()
         ])
         fadeOut.timingMode = .easeOut
         let fadeIn = SKAction.fadeIn(withDuration: 0.5)
         fadeIn.timingMode = .easeOut
         oldBuilding.run(fadeOut)
         newBuilding.run(fadeIn)
         // decay-overlay (name == DecayVisuals.overlayKey) на parent не
         // трогаем — он живёт независимо.
     }
     ```
   - В `UnitSprites.makeStageNode` (см. шаг 3) building-узел уже
     получает `name = "building"`. Для совместимости со старым `makeNode`
     (если где-то ещё используется и потом приходит swap) — старые ноды
     просто будут skip'ed: это безопасно.

8. **Smoke-тест `smoke-stage-tiers.sh`** `[AC:2,5,6]`
   - Файл: `Scripts/smoke-stage-tiers.sh` (новый).
   - Действие: shell-скрипт:
     1. Создаёт `tasks.jsonl` со 200 событиями одного проекта `tier-test`,
        даты — последние 60 дней (стимулируем рост до stage 5).
     2. Запуск 1 → сохранить итоговый `state.json` как `out1.json`.
     3. Очистить `state.json`, запуск 2 → `out2.json`.
     4. `jq` extract: для каждого `units[*].position` сверить (`x`, `y`)
        идентичность между out1 и out2 (это AC «координаты не меняются»
        и «replay одинаков»).
     5. Sanity: `jq` собрать `units[*].tier`, убедиться что
        `tier <= project.stage` для каждого юнита.
   - Если нет CLI-replay target — оставить как «ручной прогон» в комментарии
     заголовка, в DoD пометить.

9. **FPS-замер (manual, не CLI)** `[AC:7]`
   - Действие (документировать в PR-описании или в комментарии smoke-скрипта):
     1. Подготовить `tasks.jsonl` с проектом, на который накапливается ≥500
        задач (или скрипт-генератор на 600 строк с интервалом).
     2. Запустить приложение, дождаться формирования квартала на 500+ юнитов.
     3. Открыть Instruments → Time Profiler.
     4. Триггернуть переход stage 2→3 (новая задача, повышающая stage).
     5. Окно замера: 2 секунды после триггера.
     6. Минимум по фрейму ≥ 50 FPS. Сохранить trace как
        `Scripts/profiles/stage-transition.trace` (опционально, в .gitignore).

### Edge cases (явно обработать)

- [ ] **Quit во время cross-fade**: `unit.tier` уже обновлён в state,
      snapshot пишет финальный state. После рестарта `drawUnit` ставит
      spritе с `stage = project.stage` (через `stageOverride`), без fade.
- [ ] **Новый юнит во время cross-fade**: `drawUnit` (`GameScene.swift:106`)
      использует `UnitSprites.makeStageNode(unit:, stageOverride: project.stage)`,
      т.е. сразу с текущим stage квартала, без участия в fade-группе.
- [ ] **500+ юнитов**: цикл в `handleProjectStageChanged` обходит
      `project.unitIds` и запускает `SKAction` на каждой ноде — все экшены
      работают параллельно через SpriteKit runner. Общее окно ≤ 0.5 сек.
- [ ] **Catch-up при load snapshot**: callback `onProjectStageChanged`
      во время `replayFromLog` не срабатывает (`apply(e, silent: true)`,
      `CityEngine.swift:84–85`). Юниты рисуются `drawUnit` с
      `stageOverride: project.stage` — мгновенно целевой tier. Без флагов
      и доп. ветвлений.
- [ ] **D-02 / SKTileMapNode**: `swapStageSprite` работает на уровне
      child-нод контейнера `unitNodes[uid]`, не зависит от backing-layer
      земли. После D-02 anchor контейнера не меняется (см. шаг 3).
- [ ] **Юнит с decay-overlay во время stage-up**: `swapStageSprite` ищет
      и заменяет только child с `name == "building"`. Decay-overlay
      (`name == DecayVisuals.overlayKey`) на parent контейнере не
      трогается — продолжает накладываться поверх нового building после
      swap. Если overlay был на старом building как child — пересмотреть
      `applyDecay` (он сейчас добавляет overlay на parent `node` контейнер,
      см. `GameScene.swift:175`, → проблем нет).
- [ ] **Юнит — руина (decayLevel == 4)**: guard в начале `swapStageSprite`
      (`if node.childNode(withName: "ruinNode") != nil { return }`) пропускает
      swap. Это ожидаемо: руина визуально приоритетна, stage-up на руине
      не должен «оживлять» здание (decay-4 = руины навсегда по F-09).
- [ ] **stage 0** (новый проект, 0 юнитов): первая задача создаст юнит с
      `tier: project.stage`. При `project.stage = 0` `makeStageNode`
      использует `max(unit.tier, 1)` → stage 1 sprite — согласуется с
      концептом «лачуги при первой задаче».
- [ ] **Юнит без `name == "building"`** (создан старым `makeNode`): guard
      в `swapStageSprite` (`guard let oldBuilding = node.childNode(withName: "building") else { return }`)
      делает skip. Не наша задача мигрировать legacy-ноды — это сценарий
      «коммит TASK-019 поверх старого snapshot». При следующем создании
      юнит уже пойдёт через `makeStageNode`.

### Файлы для изменения

- `Sources/CityDeveloper/Data/CityState.swift` — **НЕ трогать** (TASK-018
  уже добавил `UnitCategory` и `UnitKind.category`; если `grep` из шага 1
  пуст — задача не начата).
- `Sources/CityDeveloper/Game/UnitSprites.swift` — 4 factory методы
  (residential/infra/production/social × 5 stage), точка входа
  `makeCategoricalBuilding` + `makeStageNode`, статический `projectIdKey`.
- `Sources/CityDeveloper/Game/CityEngine.swift` — `onProjectStageChanged`,
  обновление `unit.tier` в `applyTaskCompleted` (флаг `isReplaying` НЕ
  вводим — см. шаг 5).
- `Sources/CityDeveloper/App/AppDelegate.swift` — подписка на callback.
- `Sources/CityDeveloper/Game/GameScene.swift` — `handleProjectStageChanged`,
  `swapStageSprite`.
- `Scripts/smoke-stage-tiers.sh` — новый smoke-тест.

### Файлы НЕ трогать

- `Sources/CityDeveloper/Game/StageRules.swift` — формула F-08 закрыта.
- `Sources/CityDeveloper/Data/StateSnapshot.swift` — формат не меняется
  (`unit.tier` уже поле, просто перестаёт быть source of truth).
- `Sources/CityDeveloper/Game/DecayEngine.swift`, `DecayVisuals.swift` —
  decay-визуал не меняется.
- `Sources/CityDeveloper/Game/RoadConnector.swift` — дороги не tier'уются.
- `Sources/CityDeveloper/Game/UnitPlanner.swift` — TASK-018 владеет; tier-
  селекция (выбор stage) не его дело.
- Существующие `UnitSprites.make*` (12 factory) — оставляем, decay использует.

### Команды проверки (для DoD)

- Компиляция: `swift build` без новых warnings.
- Smoke-тест: `bash Scripts/smoke-stage-tiers.sh` — exit 0,
  position-идентичность между прогонами.
- FPS-замер: Instruments Time Profiler, см. шаг 9. Минимум фрейм ≥ 50 FPS.
- Ручная проверка: запустить приложение с генератором задач, наблюдать
  плавный кросс-фейд при переходе stage; перезапустить с большим
  накоплением — юниты сразу с целевым tier, без fade.

### Сложность

`middle`

**Обоснование:** 5 файлов в 3 слоях (Data + Engine + Scene + App), новый
callback с tier-обновлением, добавление 20 ассетов с anchor bottom-centre,
параллельный cross-fade с учётом catch-up флага, отдельная работа со
snapshot-инвариантом. Не junior — джун не различит обработку
isReplaying/animated и не учтёт, что decay-overlay не должен исчезать при
swap. Не senior — нет архитектурного рефактора, нет security/perf-рисков
(FPS-метрика — проверка, а не оптимизация).

### Ожидаемое время

S (≤2ч)

> Примечание: «S» в верхней половине окна — 20 спрайтов могут потянуть
> в M, если арт-проработка займёт >1ч. При первой реализации допустимо
> ограничиться минималистичными силуэтами (куб + 1 декор-узел на stage),
> детальная арт-работа — следующая итерация.

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_ (определит лид)

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Done F-08 (визуальная часть) проверена на синтетическом `tasks.jsonl`:
      форсирующее повышение stage 0→1→2→3→4→5, визуально подтверждено,
      координаты автотестом.

#### Технические
- [ ] Компиляция Swift без новых ошибок/варнингов
- [ ] FPS-замер 60 FPS базовый, не ниже 50 FPS на stage-переходе квартала
      из 50+ юнитов (M1 baseline)
- [ ] Существующие тесты F-12 / F-13 не сломаны

#### Обновление документации
- [ ] `Current.md`: F-08 → ✅
- [ ] `Diff.md`: D-08 удалён
- [ ] Новые арт-ассеты → отметить в `Current.md` под F-13 (расширение каталога)
- [ ] Новые идеи → `Backlog.md`, баги → `Bugs.md`

---

## Статус

`[x] done`

## Метаданные
- Создана PM: 2026-05-22
- Spec-review: revised (9 правок круг 1 → approved круг 2)
- Готова к работе: 2026-05-22
- Lead-model: opus
- Plan-review: revised (4 блокера круг 1 → 2 блокера круг 2 → resolved)
- Lead-trigger: opus (priority P1)
- Blocked-by: TASK-018 (pre-condition `enum UnitCategory` в CityState.swift) — выполнено
- Исполнитель: sonnet (middle), retries=0
- Code-review: approved (opus, P1)
- Завершена: 2026-05-22
- Коммит: 98dafa1
