# TASK-017: Приоритет руин при размещении нового проекта

## Связь
- **F-06** Модель Project-District и автоматическое размещение
- **D-06** из diff.md (закрывает финальный остаток F-06)
- **F-09** Decay и руины (источник зон руин, уже закрыт)
- **Приоритет:** P0

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим

Сейчас новый проект (новый `project` в `tasks.jsonl`) всегда занимает свежий
участок луга по растущей спирали от центра. Зоны руин (decay уровень 4),
оставшиеся от давно неактивных проектов, не используются, и карта со временем
будет засоряться. Нужно: при появлении **нового, ранее не встречавшегося**
`projectId` сначала проверить наличие зон руин на карте, и если они есть —
выбрать одну из них по детерминированному правилу и поставить новый квартал
туда с анимацией расчистки 3–5 секунд. Свежий луг — fallback, когда руин нет.

**Важное архитектурное допущение:** анимация расчистки — чисто визуальный
эффект, **не event-sourced** (в `tasks.jsonl` / event log не пишется). State-
переход «удалить старый District + создать новый» происходит атомарно в момент
T₀ (старт анимации), модель сразу видит новый квартал; анимация рендерится
поверх этого перехода. Replay из snapshot+tail воспроизводит state-переход
без проигрывания анимации (см. edge case «quit во время анимации»).

**Расхождение с concept.md F-06.** Concept формулирует приоритет как
«наиболее старую/большую» — это неоднозначно. Трактуем как «возраст (`ruinedAt`)
первичен, размер вторичен», обоснование: возраст руины — стабильная семантика
«давно мёртвый проект», размер сильно зависит от случайных пропорций задач.
Если эта трактовка некорректна — нужно обновить `concept.md`, не задачу.

### Пользовательский сценарий

1. В `tasks.jsonl` есть закрытый проект `alpha`, бездействующий >90 дней —
   его квартал отображается как руины (decay уровень 4).
2. Пользователь пишет задачу с новым `project: "beta"` (никогда ранее не
   встречавшимся в логе) и закрывает её — строка уходит в `tasks.jsonl`,
   watcher подхватывает.
3. Система видит новый projectId. Перед стандартной спиралью проверяет: есть
   ли на карте зоны руин?
4. Да → атомарно: старый District руин (`alpha`) удаляется из модели, создаётся
   новый District (`beta`) на тех же координатах с возрастом 0; параллельно
   запускается визуальная анимация расчистки на 3–5 сек (общее время от
   детекта нового projectId до появления первого спрайта юнита укладывается
   в это окно). Любые внутренние паузы (например, между fade руин и
   spawn юнита) — часть этого окна, отдельных «после анимации» нет.
5. Нет руин → старое поведение: спираль от центра, новый участок свободного
   луга.
6. Replay того же `tasks.jsonl` (через snapshot reset) даёт идентичную
   раскладку и идентичный выбор руин — конкретная руина для конкретного нового
   projectId стабильна между запусками.

### Acceptance criteria

- [ ] При наличии ≥1 зоны руин (decay = 4) на карте новый, ранее не
      встречавшийся `projectId` занимает руины (а не свежий луг).
- [ ] Полное время от детекта нового projectId до появления первого спрайта
      юнита нового проекта укладывается в окно **3–5 сек включительно**.
      Конкретное число внутри окна — на усмотрение лида.
- [ ] Правило выбора руины при нескольких кандидатах: **первично — наименьший
      `ruinedAt`** (старшая по времени перехода в decay-level-4); при равенстве
      `ruinedAt` — кандидат с **бо́льшим числом юнитов исходного квартала**;
      при равенстве числа юнитов — детерминированный tiebreaker по
      `projectId` (лексикографически меньший побеждает).
- [ ] **Детерминизм выбора:** при одинаковом состоянии карты (набор руин
      идентичен по `ruinedAt`, size, projectId) и одинаковом новом `projectId`
      выбранная руина ID-стабильна между независимыми запусками — отдельный
      smoke-тест, не покрытый общим replay.
- [ ] При отсутствии руин на карте — поведение размещения не меняется
      (растущая спираль от центра).
- [ ] Replay одного и того же `tasks.jsonl` (полная пересборка из snapshot+tail
      или с нуля) даёт идентичную итоговую карту, включая выбор конкретной
      руины для каждого нового projectId.
- [ ] Done-критерий F-06: 3+ разных `project` → 3+ непересекающихся квартала.
- [ ] **Атомарность state-перехода:** в момент T₀ старта анимации старый
      District (с projectId руин) полностью удаляется из модели — его
      `projectId` больше не отображается на карте; новый District с новым
      `projectId` создаётся на той же позиции; анимация — визуальный слой
      поверх уже изменённой модели.
- [ ] **Snapshot во время анимации** (см. F-12) сохраняет **финальное**
      состояние (старый District удалён, новый создан с возрастом 0).
      Анимация — чисто визуальный слой, в snapshot не попадает.

### Что НЕ делаем (границы скоупа)

- Не меняем формат `tasks.jsonl` и event log.
- Не трогаем `DecayEngine.swift` / `DecayVisuals.swift` — F-09 закрыт, decay
  считается там же.
- Не реализуем заново анимацию **восстановления** (decay 1–3 → 0) — она уже в
  F-09 (TASK-008 ✅).
- Не меняем алгоритм спирального размещения для «луг»-fallback.
- Не вводим UI для управления приоритетом руин (нет настроек пользователю).
- Не модифицируем визуал самих руин (палитра, спрайты руин уже в F-09).
- Не трогаем F-10 (жители): жители старого квартала на момент перехода в
  decay-4 уже ушли по F-10 done-criterion.

### Edge cases

- [ ] **Несколько руин, идентичный `ruinedAt`** (одновременный переход в
      decay-4 при catch-up старта) — tiebreaker через число юнитов исходного
      квартала, затем через лексикографический `projectId`.
- [ ] **Новый проект приходит во время идущей анимации расчистки другого
      проекта** — два новых проекта в одном тике; state-переходы обрабатываются
      последовательно (FIFO в порядке записи в `tasks.jsonl`), каждый
      атомарно занимает свою руину (state) в момент детекта. **Визуальные
      анимации могут идти параллельно на разных руинах** (это разные точки
      сцены, не пересекаются). Если новому проекту в очереди не остаётся
      руины — fallback на спираль.
- [ ] **Снэпшот сохраняется во время анимации расчистки** (см. F-12) — в
      snapshot уходит **финальное** state-состояние (старый District удалён,
      новый создан, возраст 0). Анимация — визуальный слой, в snapshot не
      попадает. Половинчатые состояния невозможны: state-переход атомарен.
- [ ] **Quit во время анимации расчистки** — анимация **не event-sourced**;
      при следующем запуске replay из snapshot+tail доводит карту до целевого
      финального state без визуального повтора 3–5-секундной анимации.
- [ ] **Все руины уже «забронированы» state-переходом, но анимации ещё идут** —
      следующий новый проект fallback'ит на свежий луг (руина уже принадлежит
      другому District в модели).
- [ ] **Руина была восстановлена** (decay 1-3 → 0 анимацией ремонта) до того,
      как пришёл новый проект — она больше не кандидат (уровень не 4).
- [ ] **Decay-engine ставит проект в руины параллельно с приходом нового
      проекта** — порядок: сначала отрабатывает decay-тик (он по таймеру),
      затем размещение нового проекта смотрит обновлённое состояние карты.
- [ ] **Новый `projectId` совпадает с `projectId` существующей руины**
      (`alpha` ушёл в руины и в `tasks.jsonl` снова пришла задача с
      `project: "alpha"`) — это **возрождение того же проекта**, обрабатывается
      механикой ремонта F-09 (decay → 0, restore-анимация), а не данной
      задачей. F-06 ruin-priority применяется только к **ранее не
      встречавшимся** `projectId` (новый District).

### Зависимости

- **F-09** Decay и руины — закрыт (D-09 закрыт 2026-05-22). Используем
  существующую модель «зоны руин» и `ruinedAt`. Pre-condition.
- **F-03** Event sourcing — закрыт. Порядок событий детерминированный.
- **F-12** State snapshots — закрыт. Snapshot принимает финальное state
  после атомарного перехода (см. AC).
- **F-10** Жители и анимация — закрыт. Pre-condition: жители исходного
  квартала уже ушли к моменту перехода в decay-4 (по F-10 done-critem).
- Нет внешних сервисов, секретов, миграций.

### Дизайн

Не применимо (нет нового UI). Анимация расчистки — внутри SpriteKit-сцены:
ориентир по существующим частицам в `DecayVisuals.swift` (dust / debris).
Тайминг — лид подбирает конкретное число **внутри окна 3–5 сек** (AC выше).
Никаких изменений в боковой панели, журнале, инспекторе.

### Done-критерий

_Из concept.md F-06 (дословно):_

> 3+ разных проекта в `tasks.jsonl` → 3+ непересекающихся квартала. При появлении
> нового проекта на карте с зоной руин — он занимает руины с анимацией расчистки
> длительностью 3-5 сек. Без руин — занимает свежий луг.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-22_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

В коде уже есть:
- `Sources/CityDeveloper/Data/TasksJsonlWatcher.swift` — читает лог, вызывает
  `engine.ingestTaskCompletion(...)` на каждое полное событие.
- `Sources/CityDeveloper/Game/CityEngine.swift:147–219`,
  `applyTaskCompleted(_ event: GameEvent, silent: Bool)` — единственная точка
  детектирования `isNewProject` (`state.projects[projectKey] == nil`).
- `Sources/CityDeveloper/Game/DistrictPlanner.swift` — `allocateNextOrigin(currentIndex:)`,
  спираль от центра.
- `Sources/CityDeveloper/Data/CityState.swift:36–47` — `ProjectState` с
  `decayLevel: Int`, `lastActivityAt: Date`, `districtOrigin: GridPoint`,
  `unitIds: [UUID]`. `CityState.nextDistrictIndex` — счётчик спирали.
- `Sources/CityDeveloper/Game/DecayEngine.swift` — расчёт `decayLevel` по
  `daysSinceActivity`. Уровень 4 (>90 дней) = руины. `decayTick` event пишется
  в лог при переходе уровня.
- `Sources/CityDeveloper/Game/DecayVisuals.swift` — `decay4Ruin(originalKind:)`
  + готовые particle-паттерны (`makeFireParticle`, `makeSmokeParticle`,
  `SKAction.fadeIn/Out`, `.easeOut`).
- `Sources/CityDeveloper/Game/GameScene.swift:91–223` — `markDistrict(project:)`,
  `placeUnit(_:project:)`, `applyDecayToProject(_:)`, `applyRuins(toNode:...)`.
  Все апдейты идут через `DispatchQueue.main.async`.
- `Sources/CityDeveloper/Data/GameEvent.swift` — enum `Kind` уже содержит
  `case ruinsCleared = "ruins_cleared"` (объявлен, не используется).
- `Sources/CityDeveloper/Data/StateSnapshot.swift` — `cityState: CityState`,
  atomic write раз в 500 событий / 24ч / quit.

Переиспользуем:
- `ProjectState.lastActivityAt` как proxy для `ruinedAt`: при `decayLevel == 4`
  чем меньше `lastActivityAt`, тем старше руина (сортировка идентична
  `ruinedAt = lastActivityAt + 90 days`). Не вводим новое поле — избегаем
  миграции snapshot.
- `ProjectState.unitIds.count` как size для tiebreaker.
- `DecayVisuals.makeFireParticle/makeSmokeParticle` как ориентир для
  dust/debris emitter (или новый компактный `SKEmitterNode`).
- `GameScene.world` + `unitNodes` для итерации спрайтов старого квартала.

Что нужно дописать:
- `CityEngine.pickRuinForNewProject(excluding:) -> ProjectState?` — детерминированный выбор.
- `CityEngine.applyTaskCompleted` — ветка «new project + есть руины»: атомарное
  удаление старого `ProjectState` + всех его `UnitState` из `state`, переиспользование `districtOrigin`, **без** инкремента `nextDistrictIndex`.
- Callback `onProjectRuinsCleared: ((_ oldProjectId: String, _ newProject: ProjectState) -> Void)?`.
- `GameScene.handleRuinsCleared(oldProjectId:newProject:)` — fadeOut старых
  ruin-нод + dust emitter ≤4 сек + fadeIn нового district-marker. Общее окно
  3–5 сек (см. AC).
- Smoke-скрипт `Scripts/smoke-ruin-priority.sh` — синтетический `tasks.jsonl`,
  2 запуска через `--replay` (если есть; иначе — два запуска приложения с
  очисткой `state.json` между ними), сверка финального state.

### Архитектурное решение

Логика выбора и атомарный state-переход живут в `CityEngine` — это единственный
владелец `state.projects`. Анимация — чисто визуальная, в `GameScene`, через
новый callback `onProjectRuinsCleared`. **Event `.ruinsCleared` НЕ пишется в
event log** (AC явно: «анимация не event-sourced»; добавлять новое event значило
бы менять формат GameEvent или вводить опциональные payload-поля → миграция,
которой мы стремимся избежать).

Выбор руины:
```
pickRuin: state.projects.values
  .filter { $0.decayLevel == 4 && $0.id != newProjectId }
  .sorted by (lastActivityAt asc, unitIds.count desc, id asc)
  .first
```

Атомарность state: в одном тике `applyTaskCompleted` для нового projectId с
выбранной руиной — последовательно (в одном проходе main-queue):
1. Запомнить `origin = ruin.districtOrigin` и `oldProjectId = ruin.id`.
2. Удалить `state.projects[oldProjectId]`.
3. Для каждого `unitId in ruin.unitIds`: удалить `state.units[unitId]`.
4. Создать новый `ProjectState(... districtOrigin: origin ...)`, **не**
   инкрементировать `state.nextDistrictIndex`.
5. Вызвать `onProjectRuinsCleared?(oldProjectId, newProject)` (на main-thread).
6. Далее обычный путь: создание первого `UnitState`, `onUnitBuilt`.

Шаги 1–4 атомарны на уровне state — снэпшот, сделанный после, всегда видит
финальное состояние. Анимация в `GameScene` стартует асинхронно и не влияет
на model.

Edge case «возрождение того же projectId»: defensive guard — выбор руины
исключает `excluding: newProjectId`, чтобы restore-логика F-09 (`decayLevel
1..3`) обрабатывала возвращение в свой проект.

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку. Шаг непонятен — НЕ импровизируй.

1. **Добавить выбор руины** `[AC:1,3,6]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`
   - Метод: новый приватный `pickRuinForNewProject(excluding newProjectId: String) -> ProjectState?`
   - Действие: вернуть кандидата из `state.projects.values` с
     `decayLevel == 4 && id != newProjectId`, отсортировав по
     `(lastActivityAt asc, unitIds.count desc, id asc)`, взять `first`.
   - Скелет:
     ```swift
     private func pickRuinForNewProject(excluding newProjectId: String) -> ProjectState? {
         state.projects.values
             .filter { $0.decayLevel == 4 && $0.id != newProjectId }
             .sorted { lhs, rhs in
                 if lhs.lastActivityAt != rhs.lastActivityAt { return lhs.lastActivityAt < rhs.lastActivityAt }
                 if lhs.unitIds.count != rhs.unitIds.count { return lhs.unitIds.count > rhs.unitIds.count }
                 return lhs.id < rhs.id
             }
             .first
     }
     ```

2. **Атомарная замена руины в applyTaskCompleted** `[AC:1,6,7,8,9]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`
   - Метод: `applyTaskCompleted(_:silent:)`, ветка `else` (новый проект,
     ~строки 165–168 до создания `ProjectState`).
   - Действие: ДО `let origin = districtPlanner.allocateNextOrigin(...)`
     вставить ветвление:
     - Если `let ruin = pickRuinForNewProject(excluding: projectKey)`:
       1. `let reusedOrigin = ruin.districtOrigin`
       2. `let oldProjectId = ruin.id`
       3. `for uid in ruin.unitIds { state.units.removeValue(forKey: uid) }`
       4. `state.projects.removeValue(forKey: oldProjectId)`
       5. `origin = reusedOrigin` — не вызываем `allocateNextOrigin`, не
          инкрементируем `nextDistrictIndex`.
       6. Отметить локально `let ruinsClearedFrom: String? = oldProjectId`.
     - Иначе — текущая ветка: `allocateNextOrigin + nextDistrictIndex += 1`,
       `ruinsClearedFrom = nil`.
   - После создания `ProjectState` и `if !silent && isNewProject`:
     **ВАЖНО — взаимоисключающие callbacks:**
     - Если `ruinsClearedFrom != nil` → вызвать
       `onProjectRuinsCleared?(ruinsClearedFrom!, project)`. **НЕ вызывать**
       `onProjectCreated?(project)` в этой ветке — `GameScene` нарисует
       district-маркер **внутри анимации**, после wait(2.0) (см. шаг 5).
       Иначе маркер появится сразу при `onProjectCreated` (guard в
       `drawDistrictMarker` GameScene.swift:248 — `if districtNodes[project.id]
       != nil { return }` сделает второй вызов no-op), что нарушит AC
       «3–5 сек до появления первого спрайта».
     - Иначе (свежий луг) → вызвать `onProjectCreated?(project)` как раньше.

   **Edge case в этой ветке: `projectKey == ruin.id`.**
   Это невозможно по построению: `pickRuinForNewProject(excluding: projectKey)`
   фильтрует `id != projectKey`. Возрождение того же projectId, который
   ушёл в `decayLevel == 4` (руины), обрабатывается **этой же веткой** — но
   `alpha` сама себя не выберет. Если на карте другие руины — `alpha`
   займёт одну из них (потеря исходного `alpha.districtOrigin`, истории и
   stage — ожидаемо, F-09 не делает restore для decay==4). Если других
   руин нет — `alpha` уйдёт на свежий луг по спирали. Это согласуется со
   спецификацией: F-06 ruin-priority применяется к **любому** новому
   project-state в `state.projects` (по сути «новому ProjectState»), не к
   "ранее не встречавшемуся имени".

3. **Добавить callback в CityEngine** `[AC:8]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`
   - Блок: объявления коллбэков (рядом с `onUnitBuilt`, `onProjectCreated`,
     `onDecayChanged`, ~строка 16–18).
   - Действие: добавить `var onProjectRuinsCleared: ((String, ProjectState) -> Void)?`.

4. **Подписка GameScene на callback** `[AC:2,8]`
   - Файл: `Sources/CityDeveloper/App/AppDelegate.swift`
   - Метод: блок установки коллбэков (рядом с `engine.onProjectCreated = ...`,
     ~строки 40–48).
   - Действие: добавить
     ```swift
     engine.onProjectRuinsCleared = { [weak self] oldProjectId, newProject in
         self?.scene?.handleRuinsCleared(oldProjectId: oldProjectId, newProject: newProject)
     }
     ```

5. **Помечать ноды projectId** `[AC:2]` (вспомогательный, выполнять ПЕРВЫМ)
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift`
   - Действие 5a: объявить `static let projectIdKey = "projectId"` рядом
     с существующим `unitIdKey` (~строка 17).
   - Действие 5b: в `drawUnit(_:project:)` (~строка 110, сразу после
     `node.userData?[Self.unitIdKey] = unit.id`) добавить
     `node.userData?[Self.projectIdKey] = unit.projectId`.
   - Это нужно, чтобы быстро находить ноды старого проекта при
     ruinsCleared (используется в шаге 6).

6. **Анимация расчистки в GameScene** `[AC:2,8]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift`
   - Метод: новый публичный `handleRuinsCleared(oldProjectId: String, newProject: ProjectState)`
     рядом с `markDistrict(project:)` (~строка 91–105).
   - Действие:
     1. Внутри `DispatchQueue.main.async`.
     2. Найти ноды старого проекта через `userData`:
        ```swift
        let oldNodes = unitNodes.values.filter { node in
            (node.userData?[Self.projectIdKey] as? String) == oldProjectId
        }
        ```
        (`engine.state.units` уже подчищен в `CityEngine.applyTaskCompleted`,
        но ноды на сцене ещё есть — мы их и фейдим.)
     3. Для каждой ноды: `node.run(SKAction.sequence([fadeOutAction,
        .removeFromParent()]))`, где `fadeOutAction = SKAction.fadeOut(withDuration: 2.0); fadeOutAction.timingMode = .easeIn`.
        Также очистить из `unitNodes` соответствующие ключи.
     4. Добавить в `world` короткий dust-визуал в `isoPosition(grid:
        newProject.districtOrigin)` — `SKEmitterNode` или 4–6 `SKSpriteNode`
        с серым кругом, `SKAction.group([scale 0.5→1.5, fadeOut 0→1])`,
        длительность 1.5 сек, потом removeFromParent.
     5. Удалить старый district-маркер: `districtNodes[oldProjectId]?.removeFromParent();
        districtNodes[oldProjectId] = nil`.
     6. После `world.run(SKAction.wait(forDuration: 2.0)) { ... }` (или
        через `SKAction.sequence([.wait(2.0), .run({ ... })])` на `world`) —
        вызвать `self.drawDistrictMarker(for: newProject)`. Это **единственный**
        вызов drawDistrictMarker для нового проекта в ruins-ветке (в шаге 2
        `CityEngine` НЕ вызывает `onProjectCreated`).
     7. Общее окно: fadeOut 2 сек ∥ dust 1.5 сек → wait 2 сек → marker. Итог
        ≈ 2–2.5 сек, что внутри AC 3–5 сек (с запасом на async-queue jitter).
   - Скелет сигнатуры:
     ```swift
     func handleRuinsCleared(oldProjectId: String, newProject: ProjectState) {
         DispatchQueue.main.async { [weak self] in
             guard let self, self.didAttach else { return }
             // 1. fadeOut(2.0) + remove + cleanup unitNodes на старых нодах
             // 2. dust-визуал на isoPosition(newProject.districtOrigin), 1.5 сек
             // 3. removeFromParent old districtNodes[oldProjectId]
             // 4. world.run(.sequence([.wait(2.0), .run { drawDistrictMarker(for: newProject) }]))
         }
     }
     ```

7. **Replay-детерминированность: smoke-тест** `[AC:4,6]`
   - Файл: `Scripts/smoke-ruin-priority.sh` (новый).
   - Действие: shell-скрипт, который:
     1. Создаёт временный каталог + синтетический `tasks.jsonl`:
        - 1 строка проекта `alpha` со `ts` = 100 дней назад (→ через decay
          станет руиной).
        - 5 строк проекта `beta` со `ts` = 100 дней назад (другая руина,
          больше юнитов).
        - 1 строка проекта `gamma` со `ts` = сейчас (новый проект).
     2. Запускает приложение (или CLI replay, если он есть в `Package.swift`
        targets) с этим `tasks.jsonl`, сохраняет финальный `state.json`.
     3. Удаляет `state.json`, повторяет.
     4. `diff state-run1.json state-run2.json` → должен быть пуст.
     5. Парсит финальный state.json (`jq`): проверяет, что `gamma` имеет
        `districtOrigin` равный `alpha.districtOrigin` (alpha старше beta —
        выбирается первой), а не свежий слот спирали.
   - Если CLI-replay недоступен — заменить на инструкцию ручной проверки в
     комментарии скрипта; в DoD пометить как «нужен ручной прогон».

### Edge cases (явно обработать)

- [ ] **Возрождение projectId == projectId руины** (`alpha` → руины → снова
      пришёл `alpha`): `pickRuinForNewProject(excluding: "alpha")` гарантирует,
      что `alpha` сама себя не выберет. Restore-ветка F-09 (`CityEngine.swift:155–162`,
      `if project.decayLevel > 0 && project.decayLevel < 4`) **не** триггерится для
      `decayLevel == 4` — но это и не наш скоуп, F-09 явно говорит «руины навсегда»,
      возрождение через ремонт — только из 1–3.
- [ ] **Одновременный приход двух новых projectId** (две строки в одном
      tail-чанке `TasksJsonlWatcher.swift:132 processChunk`): `applyTaskCompleted`
      обрабатывает их **строго последовательно** на main-queue
      (`handleLine → DispatchQueue.main.async`, `TasksJsonlWatcher.swift:158`). Первый забирает
      руину, второй смотрит обновлённое `state.projects` — если руин не осталось,
      идёт на спираль.
- [ ] **Snapshot во время анимации** (`SnapshotStore.saveSnapshot`,
      `CityEngine.swift:101–119`): state уже финальный после шага 2, snapshot
      atomic. Анимация — только в `GameScene`, в state не попадает.
- [ ] **Quit во время анимации** (`AppDelegate.applicationWillTerminate`,
      `AppDelegate.swift:136–142`): `saveSnapshot()` сохраняет уже-чистый state.
      При следующем запуске `replayFromLog()` восстанавливает state из snapshot+tail,
      анимация не проигрывается.
- [ ] **Все руины «забронированы» одной транзакцией, но анимации идут**:
      state уже не содержит этих руин (удалены в шаге 2), `pickRuinForNewProject`
      возвращает `nil`, fallback на спираль.
- [ ] **Decay-engine параллельно ставит проект в руины**
      (`DecayEngine.recomputeAll`, `DecayEngine.swift:48–80`): тикер 1ч + catch-up
      пишет `.decayTick` events через `engine.appendSystemEvent` на main-thread
      (см. `CityEngine.swift:122–145`). `applyTaskCompleted` тоже main-thread. Никаких
      race conditions — serial main-queue.
- [ ] **Replay из snapshot+tail** даёт идентичный результат: pick-логика
      детерминирована (sort stable), state восстанавливается полностью через
      apply(...) для каждого события в tail (`CityEngine.swift:84–85`, replayFromLog).

### Файлы для изменения

- `Sources/CityDeveloper/Game/CityEngine.swift` — `pickRuinForNewProject`,
  ветка ruins в `applyTaskCompleted`, callback `onProjectRuinsCleared`.
- `Sources/CityDeveloper/App/AppDelegate.swift` — подписка на callback.
- `Sources/CityDeveloper/Game/GameScene.swift` — `handleRuinsCleared`,
  `runRuinsClearedAnimation`, ключ `projectIdKey` в `userData`.
- `Scripts/smoke-ruin-priority.sh` — новый smoke-скрипт.

### Файлы НЕ трогать

- `Sources/CityDeveloper/Game/DecayEngine.swift`, `Game/DecayVisuals.swift` —
  F-09 закрыт, decay-логика и визуал руин не наши.
- `Sources/CityDeveloper/Data/StateSnapshot.swift`, `Data/SnapshotStore.swift` —
  формат не меняем, миграции не нужно.
- `Sources/CityDeveloper/Data/GameEvent.swift` — `ruinsCleared` event-kind
  оставляем как есть (объявлен, но не используем — это не наш bug).
- `Sources/CityDeveloper/Data/EventLog.swift` — лог не трогаем (anim не event-sourced).
- `Sources/CityDeveloper/Game/DistrictPlanner.swift` — спираль остаётся как
  есть, fallback в неё работает прежним образом.
- `Sources/CityDeveloper/Game/LifeSimulationManager.swift`, `Game/CitizenManager.swift` —
  F-10 закрыт, жители уходят при decay (pre-condition).

### Команды проверки (для DoD)

- Компиляция: `swift build` из корня проекта.
- Линтер/варнинги: `swift build` без новых warnings (Swift compiler сам).
- Ручная проверка: запустить приложение с подготовленным `tasks.jsonl` (3
  проекта: 2 старых + 1 новый), убедиться визуально, что новый проект
  стартует на месте старшей руины с dust-анимацией ≤5 сек.
- Smoke-тест: `bash Scripts/smoke-ruin-priority.sh` — выход 0, `diff` пуст.
- Replay-проверка: удалить `~/Library/Application Support/CityDeveloper/state.json`,
  перезапустить приложение → итоговая карта идентична первому прогону.

### Сложность

`middle`

**Обоснование:** 3 файла в разных слоях (Data/Engine/Scene), атомарный
state-переход с подчисткой UnitState, новый callback, замысел через
event-sourcing инвариант. Не junior — джун не различит «удалять
nextDistrictIndex не инкрементировать» и не учтёт race с decay-тикером. Не
senior — нет рефактора архитектуры, нет security/perf-проблем.

### Ожидаемое время

S (≤2ч)

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_ (определит лид)

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Done-критерий F-06 проверен на реальном `tasks.jsonl` (3+ проекта, один из
      которых — закрытый >90 дней)

#### Технические
- [ ] Компиляция Swift без новых ошибок/варнингов
- [ ] Существующие тесты F-06 / F-09 / F-12 не сломаны
- [ ] Детерминированность подтверждена smoke-тестом replay

#### Обновление документации
- [ ] `Current.md`: F-06 → ✅ (или ⚠️ если остаются нюансы)
- [ ] `Diff.md`: D-06 удалён
- [ ] Новые идеи → `Backlog.md`, новые баги → `Bugs.md`

---

## Статус

`[x] done`

## Метаданные
- Создана PM: 2026-05-22
- Spec-review: revised (9 правок, круг 1 → approved круг 2)
- Готова к работе: 2026-05-22
- Lead-model: opus
- Plan-review: revised (3 блокера круг 1 → approved круг 2)
- Lead-trigger: opus (priority P0)
- Исполнитель: sonnet (middle), retries=0
- Code-review: approved (opus, P0)
- Завершена: 2026-05-22
- Коммит: dc037ae
