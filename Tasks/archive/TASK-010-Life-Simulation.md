# TASK-010: Лёгкая симуляция жизни квартала (дым, штабели, торговля, поля)

## Связь
- **F-05** Лёгкая симуляция жизни
- **D-05**
- **Приоритет:** P1

**Скоуп F-05 — все 12 типов юнитов получают анимацию:**
- Решение Ильи (2026-05-22): анимация **у всех типов**, не только production.
  Жилые (shack/house/villa) — дымок из крыши/трубы или костерок у входа;
  инфраструктура (well/road) — лёгкая своя анимация; социалка (forum/temple/
  obelisk) — флажки/огоньки. Done-критерий концепта остаётся дословным.
- При `decay ≥ 2` все анимации юнита **выключаются** (затухание 1 сек) — мёртвый
  квартал не должен «дымить» как живой. Это design-decision из TASK-008.

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим

Сделать город визуально «живым»: поверх статичных юнитов идут лёгкие циклические
анимации, имитирующие деятельность. Никакой настоящей экономики (цепочек поставок,
дефицита) — только иллюзия. Это снимает ощущение «диорамы» и закрывает F-05.

### Пользовательский сценарий

1. В explore-режиме я подвожу камеру к кварталу stage 2+.
2. Над мастерскими (`workshop`) поднимается дымок (particle smoke); периодически
   видны короткие «искры» (particle burst).
3. На складах (`warehouse`) поверх статичных штабелей из TASK-009 видны **2
   дополнительных «торговых» штабеля**, которые пульсируют.
4. На рынках (`market`) колышутся флажки; раз в 10 сек у прилавков появляется
   силуэт-торговец.
5. На сырьевых ямах / полях (`raw`) — цикл «наполнение → опустошение».
6. **Над жилыми (`shack`/`house`/`villa`)** виден тонкий дымок из крыши/трубы
   (готовка), у лачуг — иногда огонёк костерка перед входом.
7. **Колодец (`well`)** — на воде раз в N сек появляется лёгкая рябь / блик.
8. **Дороги (`road`)** — собственной анимации не имеют (движение даёт F-10
   через жителей); исключение из правила «все 12 типов».
9. **Форум (`forum`)** — слабая «толпа»: 1-2 silhouette-фигурки появляются у
   колонн на 2-3 сек, потом исчезают.
10. **Храм (`temple`)** — тёплый огонёк у входа (chalice-light), мерцает.
11. **Обелиск (`obelisk`)** — у основания периодически появляется силуэт
    «паломника» / маленький блик от шпиля.
12. Все циклы независимы.
13. FPS остаётся ≥ 60 даже при 30+ юнитах с активной анимацией.

### Acceptance criteria

- [ ] `Game/LifeSimulationManager.swift` — менеджер, **owned by `GameScene`**
      (не singleton). Получает `weak engine: CityEngine?` и `world: SKNode`,
      проходит по всем юнитам со `stage ≥ 2 && decay < 2 && kind != .road` и
      привязывает к ним анимационные узлы по типу (см. шаги 4-11 ниже).
- [ ] **Триггер «новый юнит»:** менеджер подписывается на `CityEngine.onUnitBuilt`;
      при получении юнита, удовлетворяющего условиям (см. выше), привязывает
      анимацию с задержкой 0-10 сек (`SKAction.wait(forDuration:
      Double.random(in: 0...10))`).
- [ ] **Триггер «stage-up» / «decay change»:** `LifeSimulationManager.tick()`
      раз в 2 сек проходит по `engine.state.units`, сравнивает текущий
      stage/decay с предыдущим snapshot; при изменении — добавляет / снимает
      анимацию.
- [ ] **Мастерская (`workshop`):** `SKEmitterNode` particle smoke
      (`smokeGrey #5C5651`, частота 2/сек, alpha-fade, длительность жизни
      частицы 2 сек) + раз в 5-15 сек короткий `SKEmitterNode` искр
      (`fireOrange #E85D2C`, 4-5 частиц, длительность 0.5 сек).
- [ ] **Склад (`warehouse`):** **дополнительный «торговый» слой** поверх
      статичных штабелей из TASK-009 — 2 анимированных мини-куба
      (`ochre.darkened(by: 0.10)`); раз в 10-30 сек случайным образом
      исчезает / появляется один из них (alpha fade 0.5 сек). Базовые штабели
      TASK-009 не трогаются.
- [ ] **Рынок (`market`):** колышущиеся флажки `clay #B45A3C`
      (`SKAction.sequence` с поворотом на ±10° длительностью 800-1200 ms,
      `repeatForever`). Раз в 8-12 сек у прилавка появляется **локальный
      силуэт-торговец** (`SKShapeNode` — вытянутый прямоугольник 4×10 pt +
      кружок-голова диаметром 4 pt, цвет `clay` 60% alpha) на 2-3 секунды,
      fade-in/out 0.3 сек. Силуэт реализуется внутри TASK-010, не как
      зависимость от F-10.
- [ ] **Сырьевая яма / поле (`raw`):** цикл «наполнение → опустошение»:
      3 кучки сырья (точки `SKShapeNode`-circle radius 2 цвета
      `ochre.darkened(by: 0.20)`) появляются за 2 сек, остаются 4 сек,
      исчезают за 2 сек, пауза 2 сек, повтор. Каждый юнит со своим случайным
      offset (`Double.random(in: 0...10) sec` при старте), чтобы циклы не
      были синхронизированы.
- [ ] При смене stage юнита (1 → 2): если был без анимации — она появляется.
      При decay 0 → 1: анимация продолжает работать. При decay 1 → 2: анимация
      затухает за 1 сек и удаляется из иерархии. При возврате decay 2 → 1
      (restore): анимация добавляется заново.
- [ ] **Исключение:** для `workshop` при `decay == 3` дым (из F-09 / TASK-008)
      пишется как pursue-эффект пожара — этот эмиттер принадлежит F-09 и в
      рамках TASK-010 не управляется.
- [ ] **Particle-текстуры:** допускается процедурная генерация
      `SKTexture(image:)` через `SKShapeNode.texture(from:view:)` или
      использование дефолтного `SKEmitterNode` без custom-текстуры. Растровых
      ассетов (PNG) не подключаем.
- [ ] **Производительность и метод измерения:**
  - Целевая машина: Apple Silicon M1+.
  - `SKView.showsFPS = true` в debug-сборке.
  - Контрольный сценарий: explore-режим, камера статична, 30 production-юнитов
    в frustum, измерение 30 сек, FPS не падает ниже 60.
  - При просадке — throttling: уменьшить частоту particle до 50% и
    зафиксировать в `Bugs.md`.
- [ ] **Behind-режим:** при переходе в behind `LifeSimulationManager.pause()`
      (через `SKView.isPaused = true` либо собственный флаг); жители/анимации
      замирают, ресурсы CPU/GPU экономятся. При возврате в explore —
      `resume()`, анимации продолжаются с текущей фазы.
- [ ] Анимации **не пишут события** в `events.jsonl`. Проверка: code review —
      в `LifeSimulationManager` нет вызовов `EventLog.append(...)`.

### Что НЕ делаем (границы скоупа)

- Не делаем реальную экономику: нет цепочек поставок, нет дефицита, нет
  взаимовлияния юнитов.
- Не делаем звук — отдельный backlog-пункт.
- Не делаем сезонные изменения (зимние снеги, лето-жара).
- Не делаем анимации для `road` (движение там через жителей F-10).
- Не используем растровые particle-текстуры (PNG / texture atlas).
- Не настраиваем плотность/интенсивность анимаций через UI (F-14).
- Не используем спрайт жителя из F-10 / TASK-009 — для торговца локальный
  силуэт.
- Не работаем с базовыми штабелями TASK-009 — только дополнительный «торговый»
  слой.
- Не пишем системные события (`stage_up`, `unit_built`) — это в TASK-008
  отдельно (для decay) и в backlog (для всех остальных).

### Edge cases

- [ ] **Юнит со `stage < 2`:** анимация не присоединяется; никаких «спящих»
      эмиттеров.
- [ ] **Юнит non-production:** анимация не присоединяется.
- [ ] **Появление 30+ юнитов одновременно (massive ingest):** анимации
      разворачиваются с задержкой 0-10 сек случайной, чтобы не создавать spike.
- [ ] **Переключение explore → behind:** все анимации замирают (`pause()`),
      при возврате — продолжаются с текущей фазы.
- [ ] **Decay 2/3:** все анимации workshop/warehouse/market/raw остановлены и
      удалены из иерархии.
- [ ] **Decay 4 (руины):** юнит заменяется на `makeRuin` (TASK-009), анимации
      гарантированно очищены (`removeFromParent` на ноду удаляет всех потомков).
- [ ] **Restore (decay 1-3 → 0):** анимации добавляются заново через `tick()`
      в течение 2 сек.
- [ ] **App background / приостановка** (`NSApplication.willResignActiveNotification`):
      `SKView.isPaused = true` приостанавливает все анимации; при resume —
      продолжаются.
- [ ] **Длинная пауза (несколько часов):** при resume циклические анимации
      перезапускаются без артефактов (используется `SKAction.wait` с
      случайным offset).

### Зависимости

- **F-13 / TASK-009** (доарт) — статичные штабели на warehouse уже на месте;
  TASK-010 рисует поверх дополнительный «торговый» слой.
- **F-09 / TASK-008** (decay) — анимации выключаются при decay ≥ 2; пожар
  при decay 3 не конфликтует с дымом workshop (отдельные эмиттеры).
- **F-08** (stage) — триггер «появилась анимация» при stage-up; механизм —
  `LifeSimulationManager.tick()` раз в 2 сек со сравнением snapshot stages.
- **Существующая инфраструктура:** `GameScene`, `UnitSprites`, `Palette`,
  `CityEngine.onUnitBuilt`, `CityEngine.state.units`.

### Дизайн

Из `DesignConcept.md`:
- particle smoke: `smokeGrey #5C5651`
- particle огонь / искры: `fireOrange #E85D2C`
- Флажки на рынке: `clay #B45A3C`
- Силуэт торговца: `clay` 60% alpha
- «Торговые» штабели: `ochre.darkened(by: 0.10)`
- Тайминги: см. таблицу «Анимации» — особенно «Появление нового юнита»
  600 ms spring (для появления частиц), «Decay уровня» 1500 ms easeOut.

### Done-критерий

_Из `Concept.md` F-05 (дословно):_ В каждом квартале со stage ≥ 2 видна
минимум одна активная анимация (дым, штабели, флажки) одновременно. Симуляция
не влияет на FPS (>60). При появлении нового юнита он включается в общий ритм
симуляции в течение 10 секунд.

_Полное покрытие F-05_: анимации для всех 12 типов юнитов (кроме `road`).
Done выполняется и для квартала из одних жилых.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-22_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния
- `Game/GameScene.swift` — owner-кандидат для `LifeSimulationManager`.
- `Game/CityEngine.swift` — есть `onUnitBuilt`, `@Published state`. Stage-change через diff — нужен tick.
- `Game/UnitSprites.swift` — `makeWarehouse(tier:)` с (TASK-009) статичными штабелями; `makeMarket(tier:)` с колоннами и тентом — есть «прилавок» для размещения торговца; `makeWorkshop(tier:)` с трубой — над ней дым; `makeRawPit()` с 3 кучками — цикл наполнения.
- `Theme/Palette.swift` — все нужные токены есть (`smokeGrey`, `fireOrange`, `clay`, `ochre`).
- `SKEmitterNode` — нет настроенных эмиттеров; нужны процедурные текстуры через `SKShapeNode.texture(from:view:)` либо дефолтные.

### Архитектурное решение
`LifeSimulationManager` — обычный класс, owned by `GameScene` (`var lifeSim: LifeSimulationManager?`), создаётся в `didMove`. Держит `weak engine: CityEngine?` и словарь `attachedAnimations: [UUID: SKNode]` (root-нода анимаций для каждого юнита, чтобы при decay-выключении удалять её одним `removeFromParent`).

Триггеры:
1. `engine.onUnitBuilt = { [weak lifeSim] unit, project in lifeSim?.handleUnitBuilt(unit, project) }` — для новых.
2. `tick()` — `SKAction.repeatForever` на сцене раз в 2 сек (`SKAction.run + wait`), проходит по `engine.state.units`, сравнивает текущий stage/decay со snapshot, добавляет / снимает анимации.

Snapshot — `[UUID: (stage: Int, decay: Int)]`. После каждого tick — обновляется.

`pause()` / `resume()` — через `SKView.isPaused = true/false`, дёргается из `WindowModeManager` (там добавим callback `onModeChange`) или из публичных методов GameScene при переключении. Это пауза всей сцены, что также экономит CPU для жителей (TASK-011).

### Пошаговая декомпозиция

1. **LifeSimulationManager — каркас** `[AC:1,11]`
   - Файл: `Sources/CityDeveloper/Game/LifeSimulationManager.swift` (новый)
   - Скелет:
     ```swift
     final class LifeSimulationManager {
         weak var engine: CityEngine?
         weak var scene: GameScene?
         private(set) var attached: [UUID: SKNode] = [:]
         private var snapshot: [UUID: (Int, Int)] = [:]
         private let productionKinds: Set<UnitKind> = [.workshop, .warehouse, .market, .raw]
         func start() { scheduleTick() }
         func stop() { scene?.removeAction(forKey: "lifeSimTick") }
         private func scheduleTick() {
             let action = SKAction.repeatForever(SKAction.sequence([
                 SKAction.wait(forDuration: 2.0),
                 SKAction.run { [weak self] in self?.tick() }
             ]))
             scene?.run(action, withKey: "lifeSimTick")
         }
         func handleUnitBuilt(_ unit: UnitState, _ project: ProjectState) {
             guard shouldAnimate(unit: unit, project: project) else { return }
             // задержка 0-10 сек
             let delay = Double.random(in: 0...10)
             scene?.run(SKAction.wait(forDuration: delay), completion: { [weak self] in
                 self?.attachAnimation(to: unit)
             })
         }
         private func shouldAnimate(unit: UnitState, project: ProjectState) -> Bool {
             return project.stage >= 2 && project.decayLevel < 2 && productionKinds.contains(unit.kind)
         }
         private func tick() { /* см. шаг 2 */ }
     }
     ```

2. **tick() — обновление по stage/decay** `[AC:8]`
   - Файл: `Sources/CityDeveloper/Game/LifeSimulationManager.swift`
   - Логика:
     ```swift
     private func tick() {
         guard let engine = engine else { return }
         var newSnapshot: [UUID: (Int, Int)] = [:]
         for (id, unit) in engine.state.units {
             guard let project = engine.state.projects[unit.projectId] else { continue }
             newSnapshot[id] = (project.stage, project.decayLevel)
             let prev = snapshot[id]
             let isAttached = attached[id] != nil
             let shouldAnim = shouldAnimate(unit: unit, project: project)
             if shouldAnim && !isAttached { attachAnimation(to: unit) }
             else if !shouldAnim && isAttached { detachAnimation(from: id) }
         }
         // Cleanup: юниты, удалённые из state
         for id in attached.keys where newSnapshot[id] == nil { detachAnimation(from: id) }
         snapshot = newSnapshot
     }
     ```

3. **attachAnimation — фабрика анимации по типу** `[AC:2,3,4,5,7]`
   - Файл: `Sources/CityDeveloper/Game/LifeSimulationManager.swift`
   - Логика:
     ```swift
     private func attachAnimation(to unit: UnitState) {
         guard let scene = scene, let unitNode = scene.unitNode(for: unit.id) else { return }
         let anim: SKNode
         switch unit.kind {
         case .workshop:  anim = makeWorkshopSmoke()
         case .warehouse: anim = makeWarehouseTradingStacks()
         case .market:    anim = makeMarketAnimation()
         case .raw:       anim = makeRawPitCycle()
         default: return
         }
         unitNode.addChild(anim)
         attached[unit.id] = anim
     }
     private func detachAnimation(from id: UUID) {
         attached[id]?.run(SKAction.sequence([SKAction.fadeOut(withDuration: 1.0), SKAction.removeFromParent()]))
         attached.removeValue(forKey: id)
     }
     ```

4. **makeWorkshopSmoke — SKEmitterNode дым + искры** `[AC:2]`
   - Скелет внутри LifeSimulationManager:
     ```swift
     private func makeWorkshopSmoke() -> SKNode {
         let container = SKNode()
         let smoke = SKEmitterNode()
         smoke.particleBirthRate = 2
         smoke.particleLifetime = 2.0
         smoke.particleColor = Palette.smokeGrey
         smoke.particleColorBlendFactor = 1.0
         smoke.particleAlpha = 0.6
         smoke.particleAlphaSpeed = -0.3
         smoke.particleScale = 0.4
         smoke.particleSpeed = 8
         smoke.emissionAngle = .pi / 2  // вверх
         smoke.emissionAngleRange = .pi / 6
         smoke.position = CGPoint(x: -6, y: 30)  // над трубой workshop
         container.addChild(smoke)
         // Искры с интервалом 5-15 сек
         let sparkSequence = SKAction.repeatForever(SKAction.sequence([
             SKAction.wait(forDuration: TimeInterval.random(in: 5...15)),
             SKAction.run { [weak container] in
                 guard let container = container else { return }
                 let spark = SKEmitterNode()
                 spark.particleBirthRate = 20; spark.numParticlesToEmit = 4
                 spark.particleLifetime = 0.5; spark.particleColor = Palette.fireOrange
                 spark.particleColorBlendFactor = 1.0
                 spark.particleScale = 0.2; spark.particleSpeed = 30
                 spark.emissionAngleRange = .pi * 2
                 spark.position = CGPoint(x: -6, y: 30)
                 container.addChild(spark)
                 spark.run(SKAction.sequence([SKAction.wait(forDuration: 0.6), SKAction.removeFromParent()]))
             }
         ]))
         container.run(sparkSequence)
         return container
     }
     ```

5. **makeWarehouseTradingStacks** `[AC:3]`
   - Скелет:
     ```swift
     private func makeWarehouseTradingStacks() -> SKNode {
         let container = SKNode()
         for x in [-4, 4] {
             let stack = IsoBuilder.cube(footprint: CGSize(width: 3, height: 2), height: 4,
                 colors: .init(top: Palette.ochre.lightened(by: 0.05).darkened(by: 0.10),
                               left: Palette.ochre.darkened(by: 0.10),
                               right: Palette.ochre.darkened(by: 0.25),
                               stroke: Palette.inkDark.withAlphaComponent(0.5)))
             stack.position = CGPoint(x: CGFloat(x), y: 22)  // поверх плоской крыши
             let pulse = SKAction.repeatForever(SKAction.sequence([
                 SKAction.wait(forDuration: TimeInterval.random(in: 10...30)),
                 SKAction.fadeOut(withDuration: 0.5),
                 SKAction.wait(forDuration: TimeInterval.random(in: 2...5)),
                 SKAction.fadeIn(withDuration: 0.5)
             ]))
             stack.run(pulse)
             container.addChild(stack)
         }
         return container
     }
     ```

6. **makeMarketAnimation** `[AC:4]`
   - Скелет (флажки + торговец):
     ```swift
     private func makeMarketAnimation() -> SKNode {
         let container = SKNode()
         // 2 флажка над тентом
         for x in [-8, 8] {
             let flag = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 5, height: 3))
             flag.fillColor = Palette.clay
             flag.strokeColor = Palette.inkDark.withAlphaComponent(0.6)
             flag.position = CGPoint(x: CGFloat(x), y: 24)
             let sway = SKAction.repeatForever(SKAction.sequence([
                 SKAction.rotate(byAngle: 0.17, duration: 1.0),
                 SKAction.rotate(byAngle: -0.34, duration: 1.0),
                 SKAction.rotate(byAngle: 0.17, duration: 1.0)
             ]))
             flag.run(sway)
             container.addChild(flag)
         }
         // Локальный силуэт торговца
         let traderCycle = SKAction.repeatForever(SKAction.sequence([
             SKAction.wait(forDuration: TimeInterval.random(in: 8...12)),
             SKAction.run { [weak container] in
                 guard let container = container else { return }
                 let body = SKShapeNode(rect: CGRect(x: -2, y: 0, width: 4, height: 10))
                 body.fillColor = Palette.clay.withAlphaComponent(0.6)
                 body.strokeColor = Palette.inkDark.withAlphaComponent(0.5)
                 let head = SKShapeNode(circleOfRadius: 2)
                 head.fillColor = Palette.clay.withAlphaComponent(0.6)
                 head.position = CGPoint(x: 0, y: 12)
                 let trader = SKNode(); trader.addChild(body); trader.addChild(head)
                 trader.position = CGPoint(x: 0, y: 4); trader.alpha = 0
                 container.addChild(trader)
                 trader.run(SKAction.sequence([
                     SKAction.fadeIn(withDuration: 0.3),
                     SKAction.wait(forDuration: TimeInterval.random(in: 2...3)),
                     SKAction.fadeOut(withDuration: 0.3),
                     SKAction.removeFromParent()
                 ]))
             }
         ]))
         container.run(traderCycle)
         return container
     }
     ```

7. **makeRawPitCycle** `[AC:5]`
   - Скелет:
     ```swift
     private func makeRawPitCycle() -> SKNode {
         let container = SKNode()
         let dots = (0..<3).map { i -> SKShapeNode in
             let d = SKShapeNode(circleOfRadius: 2)
             d.fillColor = Palette.ochre.darkened(by: 0.20)
             d.strokeColor = Palette.inkDark; d.lineWidth = 0.5
             d.position = CGPoint(x: CGFloat(i - 1) * 6, y: 3); d.alpha = 0
             container.addChild(d); return d
         }
         let randomOffset = TimeInterval.random(in: 0...10)
         let cycle = SKAction.repeatForever(SKAction.sequence([
             SKAction.run {
                 for (i, dot) in dots.enumerated() {
                     dot.run(SKAction.sequence([
                         SKAction.wait(forDuration: 0.2 * Double(i)),
                         SKAction.fadeIn(withDuration: 0.6)
                     ]))
                 }
             },
             SKAction.wait(forDuration: 4),
             SKAction.run {
                 for dot in dots {
                     dot.run(SKAction.fadeOut(withDuration: 0.6))
                 }
             },
             SKAction.wait(forDuration: 2 + 2)  // 2 сек пауза + 2 сек на fadeOut
         ]))
         container.run(SKAction.sequence([SKAction.wait(forDuration: randomOffset), cycle]))
         return container
     }
     ```

8. **GameScene: unitNode(for:) + интеграция** `[AC:1]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift`
   - Добавить публичный метод `func unitNode(for id: UUID) -> SKNode? { unitNodes[id] }`.
   - В `didMove(to:)`: после init engine — создать `lifeSim = LifeSimulationManager(); lifeSim.engine = engine; lifeSim.scene = self; lifeSim.start()`.
   - Заменить engine.onUnitBuilt у AppDelegate: после установки `scene.placeUnit` дополнительно сделать `lifeSim?.handleUnitBuilt(unit, project)` — но удобнее завести второй колбэк `onUnitBuiltSimulation` или вызвать в `placeUnit` после `drawUnit`.

9. **Pause при behind-режиме** `[AC:10]`
   - Файл: `Sources/CityDeveloper/App/WindowModeManager.swift`
   - При переходе в `enterBehindMode()` — найти SpriteView (через AppDelegate.scene.view) и `view.isPaused = true`. При `enterExploreMode()` — `view.isPaused = false`. Это паузит всё в SpriteKit (анимации + жители).

10. **No-events guarantee** `[AC:11]`
    - Файл: `Sources/CityDeveloper/Game/LifeSimulationManager.swift`
    - В реализации никаких вызовов `EventLog.append` / `engine.appendSystemEvent`. Это инвариант — проверяется на code-review.

### Edge cases (явно обработать)
- [ ] `stage < 2` — `shouldAnimate` возвращает false, анимация не добавляется.
- [ ] Non-production юнит — `shouldAnimate` false (kind не в productionKinds).
- [ ] Massive ingest — `handleUnitBuilt` вешает задержку `0...10 sec` через `SKAction.wait`.
- [ ] Behind: `view.isPaused = true` (см. шаг 9) — все SKAction замирают.
- [ ] Decay 2/3 — `tick()` снимает анимацию (`detachAnimation`).
- [ ] Decay 4 — юнит-нода заменяется через TASK-008/TASK-009 makeRuin; `attached[id]` стало dangling — на следующем тике `unit.kind` остаётся .workshop/etc, но decayLevel=4 → `shouldAnimate=false` → detach. NB: при замене ноды dangling SKNode в `attached[id]` уже мёртв (`removeFromParent`), `detachAnimation` безопасен.
- [ ] Restore — `tick()` через 2 сек видит decay 0 + stage ≥ 2 → attach заново.
- [ ] App background — SKView paused на NSApp.willResignActiveNotification (см. шаг 9 расширить).
- [ ] Длинная пауза — `SKAction.repeatForever` корректно продолжает работу после `isPaused = false`.

### Файлы для изменения
- `Sources/CityDeveloper/Game/GameScene.swift` — `unitNode(for:)`, инициализация lifeSim
- `Sources/CityDeveloper/App/WindowModeManager.swift` — pause/resume SpriteView
- `Sources/CityDeveloper/App/AppDelegate.swift` — связать onUnitBuilt с lifeSim (опционально через scene)

### Файлы НЕ трогать
- `Game/UnitSprites.swift`, `IsoBuilder.swift` — статичные спрайты не меняются
- `Game/CityEngine.swift` — модель остаётся
- `Data/*` — модель неизменна

### Новые файлы
- `Sources/CityDeveloper/Game/LifeSimulationManager.swift`

### Команды проверки (для DoD)
- Компиляция: `swift build`
- Запуск: `swift run CityDeveloper`
- `SKView.showsFPS = true` в debug (в `GameScene.didMove` или `ContentView`).
- Ручная проверка: создать проект → накопить 5-10 задач → дождаться stage 2 → проверить анимации над workshop/warehouse/market/raw.
- Decay-тест: вручную поднять `decayLevel = 2` для проекта (через TASK-008) — анимации затухают.

### Сложность
`middle`

**Обоснование:** 1 новый файл, 3 правки, много мелких SKAction-цепочек. Технически линейно (фабрики по типу), но требует внимания к управлению жизненным циклом нод и предотвращению leak'ов.

### Ожидаемое время
M (≤ 1 день)

### Plan-review правки (round 1 → applied)

1. **CRITICAL — onUnitBuilt fan-out — выбран ОДИН путь: вызов `lifeSim?.handleUnitBuilt(unit, project)` ВНУТРИ `GameScene.placeUnit`,** после `drawUnit`. AppDelegate.engine.onUnitBuilt остаётся как есть (= `{ scene.placeUnit }`). Шаг 8 — финал:
   ```swift
   // В GameScene.placeUnit:
   func placeUnit(_ unit: UnitState, project: ProjectState) {
       DispatchQueue.main.async { [weak self] in
           guard let self, self.didAttach else { return }
           self.drawUnit(unit, project: project)
           self.lifeSim?.handleUnitBuilt(unit, project)
       }
   }
   ```
   Никакого второго колбэка, никакой перезаписи в AppDelegate.

2. **CRITICAL — pause/resume в behind: callback в WindowModeManager (не прямой доступ к SKView).**
   - `WindowModeManager` получает `var onModeChange: ((Bool) -> Void)?` (Bool = isExplore).
   - В `enterExploreMode()` → `onModeChange?(true)`. В `enterBehindMode()` → `onModeChange?(false)`.
   - AppDelegate в `applicationDidFinishLaunching` после установки modeManager:
     ```swift
     modeManager.onModeChange = { [weak self] isExplore in
         guard let view = self?.cityWindow.contentView?.findSpriteKitView() else { return }
         view.isPaused = !isExplore
     }
     ```
   - `findSpriteKitView()` — расширение `NSView` (recursive subview search для SKView).

3. **CRITICAL — detachAnimation race:** удаление из словаря — в completion handler:
   ```swift
   private func detachAnimation(from id: UUID) {
       guard let node = attached[id] else { return }
       node.removeAllActions()
       node.run(SKAction.sequence([
           SKAction.fadeOut(withDuration: 1.0),
           SKAction.run { [weak self] in self?.attached.removeValue(forKey: id) },
           SKAction.removeFromParent()
       ]))
       // НЕ удалять из словаря сразу
   }
   ```

4. **`shouldAnimate` использует `project.decayLevel` (квартал), не `unit.decayLevel`** — зафиксировано явно. `unit.decayLevel` пока не используется (на будущее, когда появится индивидуальный decay юнитов).

5. **makeRawPitCycle — тайминги исправлены:**
   ```swift
   let cycle = SKAction.repeatForever(SKAction.sequence([
       SKAction.run { /* fade-in all dots */ },
       SKAction.wait(forDuration: 2.0 + 4.0),  // 2 сек stagger + 4 сек видны
       SKAction.run { /* fade-out all dots */ },
       SKAction.wait(forDuration: 2.0 + 2.0)   // 2 сек fade + 2 сек пауза
   ]))
   ```

6. **App background:** добавить в `GameScene.didMove`:
   ```swift
   NotificationCenter.default.addObserver(forName: NSApplication.willResignActiveNotification, object: nil, queue: .main) { [weak view] _ in view?.isPaused = true }
   NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak view] _ in /* respect modeManager.isExplore */ }
   ```

7. **IsoBuilder.cube API подтверждено:** `cube(footprint:height:colors:)` с `CubeColors(top:left:right:stroke:)` — существует.

---

## ✅ Исполнение

_Исполнитель: sonnet_
_Сложность: middle_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Done-критерий в редакции TASK-010 проверен: в explore-режиме видны
      минимум 3 разных типа анимации одновременно при наличии production-юнитов
      со stage ≥ 2

#### Технические
- [ ] `swift build` без новых ошибок
- [ ] FPS ≥ 60 при 30+ production-юнитах с анимацией (метод измерения по AC)
- [ ] Анимации не пишутся в `events.jsonl` (code review)

#### Обновление документации
- [ ] `current.md`: F-05 ❌ → ✅ (все типы юнитов кроме road получают анимацию)
- [ ] `diff.md`: D-05 удалён
- [ ] Concept.md НЕ правится

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
- Code-review: revised (opus, round 2 sonnet)
- Коммит: —
