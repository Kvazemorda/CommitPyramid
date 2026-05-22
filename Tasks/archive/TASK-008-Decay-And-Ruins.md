# TASK-008: Decay-механика и руины

## Связь
- **F-09** Decay и руины
- **D-09**
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим

Замкнуть продуктовый контур: проекты, в которых давно нет событий, должны визуально
дряхлеть и в конечном итоге становиться руинами. Возврат к проекту до перехода в руины
триггерит анимацию ремонта и сбрасывает decay. Руины остаются на карте навсегда, но
могут быть заняты новым проектом (см. F-06 — приоритет руин не входит в эту задачу,
это отдельная зависимость). Это даёт «обратную связь по заброшенным проектам» —
ключевую ценность из бизнес-модели.

### Пользовательский сценарий

1. Я закрываю задачи по проекту «Outbyte Website» в течение мая. На карте растёт
   квартал из жилых, складов, мастерских.
2. С июня я переключился на другой проект и не закрываю задачи по «Outbyte Website».
3. Через 15 дней без активности захожу в explore-режим — вижу, что квартал «Outbyte
   Website» подёрнут зеленью (decay 1): трава между плитами, тайлы тусклее.
4. Через 30 дней — трещины в стенах, провалившиеся крыши (decay 2).
5. Через 60 дней — над домами поднимается дым/пожар (decay 3, particle-эффект).
6. Через 90+ дней — квартал превращается в руины (decay 4).
7. Если я возвращаюсь к «Outbyte Website» (новая строка в `tasks.jsonl`) на этапе
   decay 1-3 — запускается короткая анимация ремонта (3-5 сек), визуал возвращается
   к нормальному состоянию, `decayLevel = 0`.

### Acceptance criteria

- [ ] `DecayEngine` (или эквивалент) тикает раз в час (`DispatchSourceTimer` или
      `Timer`); при старте приложения делает catch-up — пересчитывает все
      `ProjectState.decayLevel` от текущего момента.
- [ ] Расчёт `decayLevel` для проекта:
  - `days_since_last_activity < 14` → `decayLevel = 0`
  - `14 ≤ days < 29` → `decayLevel = 1`
  - `29 ≤ days < 57` → `decayLevel = 2`
  - `57 ≤ days < 91` → `decayLevel = 3`
  - `days ≥ 91` → `decayLevel = 4` (руины)
- [ ] При изменении `decayLevel` записывается системное событие в `events.jsonl`:
  - `decay_tick` при переходе 0→1, 1→2, 2→3
  - `fire` при переходе 2→3 (пожар)
  - `restore` при возврате к 0 из 1-3
  - При переходе 3→4 события `ruins_cleared` НЕ пишется (руины пока остаются;
    очистка — отдельная задача F-06).
- [ ] Визуальная подмена в SpriteKit:
  - decay 1: на тайл-земле под юнитами добавляется зелёная штриховка / texture overlay
    (низкая alpha); цвет юнита tone-down на 10%.
  - decay 2: на стенах юнитов появляются трещины (SKShapeNode-линии); крыша
    наклоняется или меняется на «провалившуюся» (lower peak).
  - decay 3: над юнитом particle smoke + fire (SKEmitterNode).
  - decay 4: юниты заменяются на «руины» — фрагменты стен, обломки (использует
    готовые формы из `IsoBuilder`).
- [ ] Restore-анимация при возврате к проекту: для каждого юнита плавный (3-5 сек)
      переход visual'а к decay 0; particle-эффекты затухают; `SKAction.sequence`.
- [ ] Все переходы детерминированны: replay лога с `events.jsonl` даёт
      идентичное состояние decay и идентичные системные события.
- [ ] decay-расчёт срабатывает только для проектов с `taskCount > 0`. Пустой
      / только что созданный проект не «начинает дряхлеть».

### Что НЕ делаем (границы скоупа)

- Не реализуем приоритет руин при размещении нового проекта (F-06 D-06) — это
  отдельная задача.
- Не делаем фильтр / звуковые эффекты при decay.
- Не делаем визуальное «уведомление» (P1-фича из backlog: native push при decay).
- Не модифицируем `tasks.jsonl`.
- Не меняем существующий формат `taskCompleted` событий.
- Не реализуем decay на уровне отдельных юнитов — только на уровне проекта.
- Не делаем UI-настройку пороговых дней (14/28/56/90 — хардкод; настройки в F-14).

### Edge cases

- [ ] **Системное время сдвинуто назад** (пользователь поправил время на ПК) —
      decay может «вернуться» в более раннюю стадию. Корректное поведение:
      пересчитать от фактического `lastActivityAt` и `Date.now`, без падений.
- [ ] **Длинный простой между запусками** (приложение не запускалось 6 месяцев) —
      при старте делается catch-up: для каждого проекта вычисляется текущий
      decay и пишутся пропущенные системные события (одно `decay_tick` на каждый
      пройденный уровень + `fire` при попадании в 3+).
- [ ] **Replay лога** — событие `decay_tick` / `fire` / `restore` применяется к
      state в `CityEngine.apply(...)` без побочных эффектов (не пишет в файл
      повторно).
- [ ] **Гонка между decay-тиком и новым `taskCompleted`** в момент тика — порядок
      обработки фиксированный: сначала `taskCompleted` (обновляет
      `lastActivityAt`), потом decay-перерасчёт.
- [ ] **Проект с `lastActivityAt` в будущем** (опечатка в `tasks.jsonl`,
      `ts > Date.now`) — decay = 0 пока not, событие не пишется. В `errors.log` —
      предупреждение.
- [ ] **Множество юнитов в квартале + decay 3 → 4:** все юниты заменяются на
      «руины» в рамках одного frame'а, без визуальных артефактов.
- [ ] **Restore при decay 4 (руины)** — не происходит. Руины можно только занять
      новым проектом (F-06).

### Зависимости

- **F-03** (event log) — пишем системные события через существующий `EventLog`.
- **F-04** (watcher) — `taskCompleted` обновляет `lastActivityAt`, что является
  входом для decay-расчёта.
- **F-13** (арт-ассеты) — для убедительного визуала decay нужны варианты
  «треснувшая стена», «обломок», particle-текстуры. На этапе TASK-008 допустимо
  использовать процедурную графику из `IsoBuilder`; полноценные ассеты — отдельная
  задача (TASK-009 / D-13).
- **F-06** (district planner) — приоритет руин при размещении нового проекта вне
  скоупа этой задачи.
- **Модель данных:** `ProjectState.decayLevel`, `ProjectState.lastActivityAt` уже
  есть. Возможно понадобится `var lastDecayLevelLogged: Int` для предотвращения
  дублей системных событий.

### Дизайн

Из `DesignConcept.md`:
- decay 1 (зелень/тусклость): overlay цвета `nileGreen` 25% opacity на ground tile;
  цвет здания tone-down через `darkened(by: 0.10)`.
- decay 2 (трещины): дополнительные `SKShapeNode`-линии `inkDark` 60% на гранях
  куба; крыша через `pyramidRoof` с пониженным peak.
- decay 3 (пожар): `SKEmitterNode` с particle огня (`fireOrange #E85D2C`) и дыма
  (`smokeGrey #5C5651`); см. таблицу «Анимации» в `DesignConcept.md` (restore
  3000-5000 ms scripted sequence).
- decay 4 (руины): силуэт здания заменяется на 2-3 фрагмента стен (короткие
  кубы из `IsoBuilder.cube` с цветом `stone.darkened(by: 0.20)`); декоративная
  трава поверх.
- Анимация перехода между decay-уровнями: 1500 ms easeOut (как в таблице
  «Анимации» — «Decay уровня (медленное появл.)»).
- Анимация restore: 3000-5000 ms scripted sequence.

### Done-критерий

_Из `Concept.md` F-09 (дословно):_ Проект без событий 14 дней показывает decay
уровня 1. Через 28 → 2, через 56 → 3 (с particle-эффектом пожара), через 90 → 4
(руины). Новая задача в проекте с decay 1-3 сбрасывает decay в 0 с анимацией
ремонта. Новый **другой** проект может занять руины (см. F-06 Done).

> Часть про F-06 закрывается отдельной задачей; в рамках TASK-008 — все остальные
> пункты Done.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-22_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния
- `GameEvent.Kind` уже содержит `decayTick`, `fire`, `restore`, `ruinsCleared` — модель готова.
- `CityEngine.apply(_:silent:)` обрабатывает `taskCompleted`; для остальных kind — `break`. Нужно добавить ветки `decayTick / fire / restore` (`ruinsCleared` пока без логики, см. AC).
- `ProjectState.decayLevel: Int`, `lastActivityAt: Date` уже есть.
- `EventLog.append(_:)` пишет событие append-only. Использовать его для системных событий.
- `CityEngine` инициализирует engine; нет тикера. Нужен `DispatchSourceTimer` или `Timer.scheduledTimer`.
- `Game/UnitSprites.swift` — фабрики на 12 типов; нужна `makeRuin(...)` (или из TASK-009 — здесь зависимость).
- `GameScene` — рендер юнитов через `UnitSprites.makeNode(unit:)`; нужны методы обновления visual'а юнита при decay-change.

### Архитектурное решение
Новый класс `Game/DecayEngine.swift`. Он принадлежит `CityEngine` (через композицию). Тикер — `DispatchSourceTimer` раз в 3600 сек (1 час) на main queue. При каждом тике + при старте + перед quit — `recomputeAll()`. Расчёт: для каждого проекта `daysSinceLastActivity = (Date.now - lastActivityAt) / 86400`, новый уровень по таблице. Если уровень изменился вверх — пишем `decayTick`, при переходе 2→3 дополнительно `fire`. При возврате `lastActivityAt` (новый `taskCompleted`) — если был decay > 0 → пишем `restore`, ставим `decayLevel = 0`.

Системные события — единственный path обновления `project.decayLevel`. В `CityEngine.apply(event:silent:)` ветки `decayTick / fire / restore` обновляют `state.projects[event.project].decayLevel` и триггерят колбэк `onDecayChanged?(project)` для визуала. Это даёт детерминированный replay (события в логе → одинаковое state). При replay тикер не работает: catch-up произведёт нужные системные события после applyOf-replay в `init`.

Визуальная подмена: новый `DecayVisuals` (extension `UnitSprites` или новый файл `Game/DecayVisuals.swift`) — для каждого юнита overlay-узлы (decay 1 — `nileGreen` overlay + tone-down; decay 2 — линии трещин; decay 3 — `SKEmitterNode` fire+smoke; decay 4 — заменить ноду через `UnitSprites.makeRuin(originalKind:)` из TASK-009). `GameScene` подписывается на `engine.onDecayChanged` и применяет.

### Пошаговая декомпозиция

1. **Расширить ProjectState новым полем `lastDecayLogged`** `[AC:2,3]`
   - Файл: `Sources/CityDeveloper/Data/CityState.swift`
   - Добавить `var lastDecayLogged: Int = 0` в `ProjectState` (Codable, дефолт 0 для миграции старых снэпшотов).
   - Назначение: предотвращать повторную запись `decayTick` при тиках на одном уровне.

2. **DecayEngine — расчёт уровня + тикер** `[AC:1,2,7]`
   - Файл: `Sources/CityDeveloper/Game/DecayEngine.swift` (новый)
   - Скелет:
     ```swift
     final class DecayEngine {
         weak var cityEngine: CityEngine?
         private var timer: DispatchSourceTimer?
         func start() {
             recomputeAll()  // catch-up при старте
             let t = DispatchSource.makeTimerSource(queue: .main)
             t.schedule(deadline: .now() + 3600, repeating: 3600)
             t.setEventHandler { [weak self] in self?.recomputeAll() }
             t.resume()
             timer = t
         }
         func stop() { timer?.cancel(); timer = nil }
         private func recomputeAll() { ... }  // см. шаг 3
         static func computeLevel(daysSinceActivity: Int) -> Int {
             if daysSinceActivity < 14 { return 0 }
             if daysSinceActivity < 29 { return 1 }
             if daysSinceActivity < 57 { return 2 }
             if daysSinceActivity < 91 { return 3 }
             return 4
         }
     }
     ```

3. **DecayEngine.recomputeAll() — генерация системных событий** `[AC:3]`
   - Файл: `Sources/CityDeveloper/Game/DecayEngine.swift`
   - Логика:
     ```swift
     for project in cityEngine.state.projects.values {
         guard project.taskCount > 0 else { continue }
         let days = Calendar.current.dateComponents([.day], from: project.lastActivityAt, to: Date()).day ?? 0
         guard days >= 0 else { continue }  // future ts — пропускаем
         let newLevel = Self.computeLevel(daysSinceActivity: days)
         if newLevel > project.lastDecayLogged {
             // пишем decay_tick для каждого пройденного уровня (catch-up)
             for level in (project.lastDecayLogged + 1)...newLevel {
                 cityEngine.appendSystemEvent(.decayTick, project: project.id)
                 if level == 3 { cityEngine.appendSystemEvent(.fire, project: project.id) }
             }
         }
     }
     ```

4. **CityEngine.appendSystemEvent + apply ветки** `[AC:3,7]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`
   - Метод:
     ```swift
     func appendSystemEvent(_ kind: GameEvent.Kind, project: String) {
         let e = GameEvent(ts: Date(), kind: kind, project: project)
         eventLog.append(e); apply(e, silent: false); events.append(e)
     }
     ```
   - В `apply(_:silent:)` заменить `break` на:
     ```swift
     case .decayTick:
         updateDecay(project: event.project, levelDelta: +1, silent: silent)
     case .fire:
         break  // визуальный сигнал, обрабатывается в onDecayChanged через decay = 3
     case .restore:
         updateDecay(project: event.project, levelDelta: nil, resetTo: 0, silent: silent)
     case .unitBuilt, .stageUp, .ruinsCleared:
         break
     ```
   - Helper `updateDecay(project:levelDelta:resetTo:silent:)` — модифицирует state, инвоукует `onDecayChanged?(project)` при `!silent`.

5. **Restore при новом `taskCompleted`** `[AC:3]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`
   - В `applyTaskCompleted(...)`: после обновления `lastActivityAt`, если `project.decayLevel > 0 && project.decayLevel < 4` → `appendSystemEvent(.restore, project: project.id)` ДО update state (или после — главное события в правильном порядке).
   - Edge: если `decayLevel == 4` (руины) — restore НЕ пишем; новый task просто добавляет юнит как обычно (передача владения руинами — отдельная задача F-06).

6. **AppDelegate: запустить DecayEngine** `[AC:1]`
   - Файл: `Sources/CityDeveloper/App/AppDelegate.swift`
   - В `applicationDidFinishLaunching` после `engine = CityEngine()` — `decayEngine = DecayEngine(); decayEngine.cityEngine = engine; decayEngine.start()`.
   - В `applicationWillTerminate` — `decayEngine.stop()`.

7. **DecayVisuals — overlay-узлы** `[AC:4,5]`
   - Файл: `Sources/CityDeveloper/Game/DecayVisuals.swift` (новый)
   - Фабрики: `decay1Overlay() -> SKNode` (зелёные пятна + tone-down модификатор), `decay2Cracks() -> SKNode` (линии `SKShapeNode` `inkDark` 60%), `decay3FireEmitter() -> SKNode` (`SKEmitterNode` fire + smoke; процедурная `SKTexture` через `SKShapeNode.texture(from:)`), `decay4Ruin(originalKind: UnitKind) -> SKNode` (вызывает `UnitSprites.makeRuin(originalKind:)` из TASK-009).
   - В `GameScene` — `func applyDecay(level:Int, toUnit unit: UnitState)`: снимает старые overlay'и (через `removeAction(forKey:)` + `removeFromParent` по naming convention), добавляет соответствующие.

8. **GameScene: подписка на onDecayChanged** `[AC:4,5,7]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift`
   - В `didMove`: после init `engine` — engine.onDecayChanged = `{ [weak self] project in self?.applyDecayToProject(project) }`. Метод `applyDecayToProject` итерирует `project.unitIds`, вызывает `applyDecay(level:, toUnit:)` для каждого.
   - Также при `drawUnit` — если `unit.decayLevel > 0` (replay) применять overlay сразу.

9. **Тесты: replay даёт идентичный decay** `[AC:7]`
   - Ручная проверка: создать `events.jsonl` с задачами, имитировать передвижение `lastActivityAt` в state (через закрытие приложения и редактирование state.json или системного времени), запустить — должны появиться `decay_tick` события и визуальный эффект.

### Edge cases (явно обработать)
- [ ] **Системное время сдвинуто назад:** `daysSinceActivity < 0` → `guard days >= 0 else { continue }` в `recomputeAll`. События НЕ пишутся; `lastDecayLogged` не меняется. Подтверждено в edge cases спеки.
- [ ] **Длинный простой (6 месяцев):** при старте `recomputeAll` пишет пропущенные `decay_tick` 0→1→2→3 + `fire` (при 3). `lastDecayLogged` после этого = 3.
- [ ] **Replay:** при init после `replayFromLog()` система-события из лога уже применены → `project.decayLevel` и `lastDecayLogged` восстановлены. Тикер при `start()` сделает catch-up только если с момента последнего системного события прошло время.
- [ ] **Гонка taskCompleted + decay tick:** обе операции на main queue (`DispatchSourceTimer.queue = .main`, `TasksJsonlWatcher` → main); порядок — кто пришёл первым.
- [ ] **`lastActivityAt > Date.now`:** edge сверху; пишем в `errors.log` через `ErrorsLog.write(_:)` (предупреждение).
- [ ] **Множество юнитов в квартале при decay 3 → 4:** `applyDecayToProject` итерирует `unitIds` — каждому ноду заменяем на `decay4Ruin`. SpriteKit обрабатывает в одном кадре без артефактов (атомарная замена).
- [ ] **Restore при decay 4:** не происходит (см. AC). В `applyTaskCompleted` — условие `decayLevel > 0 && decayLevel < 4`.
- [ ] **Переход 3→4:** decayTick пишется (по AC «decayTick для каждого уровня»). `ruinsCleared` не пишется (F-06).

### Файлы для изменения
- `Sources/CityDeveloper/Data/CityState.swift` — добавить `lastDecayLogged`
- `Sources/CityDeveloper/Game/CityEngine.swift` — `appendSystemEvent`, ветки `apply`, restore-логика
- `Sources/CityDeveloper/Game/GameScene.swift` — `applyDecayToProject`, `applyDecay(level:toUnit:)`
- `Sources/CityDeveloper/App/AppDelegate.swift` — запуск/остановка DecayEngine

### Файлы НЕ трогать
- `Data/EventLog.swift` — API готов
- `Data/GameEvent.swift` — Kind полный
- `Data/TasksJsonlWatcher.swift` — watcher не меняется

### Новые файлы
- `Sources/CityDeveloper/Game/DecayEngine.swift`
- `Sources/CityDeveloper/Game/DecayVisuals.swift`

### Зависимость от TASK-009
- `UnitSprites.makeRuin(originalKind:)` — для decay 4. Если TASK-009 ещё не выполнен — временно использовать заглушку: затемнённый `IsoBuilder.cube` без декора.

### Команды проверки (для DoD)
- Компиляция: `swift build`
- Запуск: `swift run CityDeveloper`
- Тест: смоделировать decay через ручную правку `lastActivityAt` в state (или временно понизить пороги в `DecayEngine.computeLevel` до секунд для smoke-теста).
- Replay-тест: удалить `state.json` (когда появится TASK-012) — replay из `events.jsonl` должен дать идентичные `decayLevel` и `lastDecayLogged`.

### Сложность
`middle`

**Обоснование:** Декомпозиция — 4 новых файла + 4 правки. Логика catch-up и replay требует аккуратности (легко получить дубли событий), но рисков «архитектурного перепроектирования» нет — модель уже готова.

### Ожидаемое время
M (≤ 1 день)

### Plan-review правки (round 1 → applied)

1. **CRITICAL — `apply(.decayTick)` должен обновлять `lastDecayLogged`.**
   В шаге 4 ветка `.decayTick`:
   ```swift
   case .decayTick:
       guard var project = state.projects[event.project] else { break }
       project.decayLevel = min(4, project.decayLevel + 1)
       project.lastDecayLogged = max(project.lastDecayLogged, project.decayLevel)
       state.projects[event.project] = project
       if !silent { onDecayChanged?(event.project) }
   ```
   Это даёт корректность и при catch-up (цикл `for level in ...` безопасен, потому что `appendSystemEvent → apply` синхронно обновляет `lastDecayLogged`), и при replay (восстановление `lastDecayLogged` из лога).

2. **`apply(.restore)` ветка:**
   ```swift
   case .restore:
       guard var project = state.projects[event.project] else { break }
       project.decayLevel = 0
       project.lastDecayLogged = 0
       state.projects[event.project] = project
       if !silent { onDecayChanged?(event.project) }
   ```

3. **Шаг 4 — убрать гибридный `updateDecay`-helper** (с `levelDelta: nil, resetTo:` — антипаттерн). Логику inline в `case`-ветках, как в правках 1-2.

4. **Шаг 7 — fallback заглушка `decay4Ruin` БЕЗ зависимости от TASK-009.** Inline:
   ```swift
   static func decay4Ruin(originalKind: UnitKind) -> SKNode {
       // Если UnitSprites.makeRuin доступен (TASK-009 готов) — использовать его.
       // Fallback: затемнённый куб без декора.
       let stub = IsoBuilder.cube(
           footprint: CGSize(width: 24, height: 14), height: 6,
           colors: .init(top: Palette.stone.darkened(by: 0.20),
                         left: Palette.stone.darkened(by: 0.30),
                         right: Palette.stone.darkened(by: 0.45),
                         stroke: Palette.inkDark))
       return stub
   }
   ```
   После выполнения TASK-009 — заменить тело на `return UnitSprites.makeRuin(originalKind: originalKind)`.

5. **Пороги:** AC говорит «14/29/57/91» (включает граничный день в новый уровень). Concept.md пишет «через 28/56/90» — это согласованно («через 28 дней» = на 29-й день уровень 2). Принимаем AC как первичную формулировку, в `computeLevel` — пороги как в AC.

6. **`ErrorsLog.write(_:)`** — проверено: класс существует в `Data/ErrorsLog.swift`. Использовать как есть.

---

## ✅ Исполнение

_Исполнитель: sonnet_
_Сложность: middle_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Done-критерий проверен: симулировал передвижением системного времени или
      ручным редактированием `lastActivityAt` в state.

#### Технические
- [ ] `swift build` без новых ошибок
- [ ] Replay лога даёт идентичные значения `decayLevel` для всех проектов
- [ ] Системные события (`decay_tick`, `fire`, `restore`) появляются в
      `events.jsonl` корректно, дублей нет

#### Обновление документации
- [ ] `current.md`: F-09 ❌ → ✅
- [ ] `diff.md`: D-09 удалён
- [ ] Если использована процедурная decay-графика без F-13 — отметить в
      `Diff.md` остаток D-13 (decay-ассеты)

---

## Статус

`[x] done`

## Метаданные
- Создана PM: 2026-05-22
- Spec-review: approved (round 1)
- Lead-model: opus
- Plan-review: needs-revision → applied (round 1)
- Сложность: middle
- Готова к работе: 2026-05-22
- Завершена: 2026-05-22
- Code-review: revised (sonnet, Opus 529 fallback)
- Коммит: —
