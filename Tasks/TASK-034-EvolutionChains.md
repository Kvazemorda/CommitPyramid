# TASK-034: Эволюционные цепочки юнитов (визуальная подмена при пороге)

## Связь
- **F-16** из Concept.md (эволюционные цепочки)
- **F-08** из Concept.md (визуальная подмена без переразмещения)
- **D-16** из Diff.md (часть 4/10 — эволюция)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим
По F-16 в игре 8 эволюционных цепочек:
- 2 × Землянка → Лачуга
- 2 × Лачуга → Дом
- 2 × Хижина → Каменный дом
- 3 × Дом → Доходный дом
- 2 × Каменный дом → Усадьба
- 2 × Двухэтажный дом → Доходный дом
- 2 × Фермерский дом → Усадьба
- 3 × Склад → Большой склад

Когда в квартале накапливается порог одинаковых юнитов — все они
**визуально превращаются** в целевой юнит (с сохранением координат, как у
F-08 stage-up). Это даёт ощущение «дома уплотнились», без переразмещения и
без перестройки сетки. Эта задача реализует именно сам механизм
«достигли порога → подменили клетки», без изменения планировщика
(планировщик — TASK-035, он решает, **какой** новый юнит создавать; здесь —
что делать с уже стоящими, когда их стало достаточно).

### Пользовательский сценарий
1. В квартале постепенно строятся 2 Землянки → при добавлении 2-й Землянки
   обе клетки на месте превращаются в Лачуги (короткий cross-fade ≤ 0.5 сек,
   та же координата, тот же `unitId`).
2. Дальше строятся ещё 2 Лачуги → теперь 4 Лачуги, при достижении 2-х
   _свежих_ Лачуг они также превращаются в Дома; ранее эволюционировавшие
   из Землянок Лачуги тоже считаются Лачугами и участвуют в следующих
   порогах.
3. В журнале событий появляется системное событие `unit_evolved(unitId, from,
   to)` для каждой клетки, чтобы replay восстанавливал картину один-в-один.

### Acceptance criteria
- [ ] При достижении порога эволюции (по таблице из TASK-031) все
      юниты данного типа в квартале одномоментно заменяют свой
      `UnitKind` на целевой; `id` юнита, координата и `taskTitle` остаются
      прежними.
- [ ] Визуальная подмена реализована тем же механизмом, что F-08 stage-up
      (cross-fade параллельно, bottom-anchor сохраняется, ≤ 0.5 сек на юнит).
- [ ] Для каждой эволюции пишется системное событие в `events.jsonl`
      (`type = unit_evolved`, payload — `unitId`, `from`, `to`,
      `projectId`), чтобы replay был детерминирован.
- [ ] Если в квартале есть смесь типов из одной цепочки (например, 3 Землянки
      и 1 Лачуга, которые ещё не сэволюционировали) — пороги применяются
      по-уровнево: сначала 2 Землянки → 2 новые Лачуги, затем суммарно 3
      Лачуги (1 «своя» + 2 новые) не дотягивают до порога 2 → Дом не
      создаётся; нужны ещё Лачуги.
- [ ] Replay-safe: повторный проход по `events.jsonl` (включая искусственно
      внесённые `unit_evolved`) даёт идентичный итоговый `CityState`.

### Что НЕ делаем (границы скоупа)
- Не меняем планировщик (как именно выбирается новый юнит) — TASK-035.
- Не переразмещаем клетки на сетке (эволюция — только sprite-swap на месте).
- Не делаем «откат эволюции» (decay не превращает Усадьбу обратно в
  Каменный дом — decay вешает overlay по F-09, не трогает `UnitKind`).
- Не объединяем клетки в один «крупный» юнит (Доходный дом 2×2 на двух
  клетках 1×1 — визуально просто две клетки «Доходного дома», без слияния
  в один спрайт 2×2).
- Не добавляем эволюции, не описанные в таблице F-16 (никакого «Усадьба →
  Вилла»; Вилла — отдельный large-юнит).

### Edge cases
- [ ] Декай-уровень квартала > 0 в момент достижения порога → эволюция всё
      равно срабатывает (decay живёт отдельным overlay; концепт не запрещает
      эволюцию в декай-фазе). Это поведение фиксируется явно, не «само
      собой».
- [ ] Порог достигается прямо в момент создания нового юнита (была 1 Лачуга,
      создаётся 2-я) → эволюция применяется сразу после события `unit_built`,
      в той же транзакции, чтобы replay видел `unit_built` + `unit_evolved`
      в правильном порядке.
- [ ] Юниты-цели эволюции, у которых `minStage > stage квартала` (например,
      Доходный дом имеет `minStage = 3`, а квартал на stage 1) → эволюция
      **не** срабатывает, юниты остаются как есть; повторная попытка
      произойдёт при следующем `unit_built` после `stage_up`.
- [ ] Старое состояние state.json до этой задачи не содержит событий
      `unit_evolved` → загрузка проходит без падения; эволюция применяется
      «лениво» при первом релевантном `unit_built` после загрузки.

### Зависимости
- **Blocked-by:** TASK-031 (нужны поля `evolvesTo` и порог в каталоге).
- **Blocked-by:** TASK-032 (нужны спрайты целевых юнитов, иначе подменять
  не на что).

### Дизайн
Cross-fade анимация — тот же подход, что F-08 `handleProjectStageChanged /
swapStageSprite` в `GameScene.swift`. Никакого нового UI.

### Done-критерий
_Из Concept.md F-16:_ Все 50 юнитов имеют реализованный спрайт и корректно выбираются
алгоритмом размещения с учётом `terrain`, `minStage` и `large`. Эволюционные цепочки
визуально срабатывают при достижении порога. Квартал из 30+ юнитов содержит ≥ 3
разных категории. Воспроизводимость через replay.

---

## 🛠 Технический разбор от тимлида

_Статус: [x] разобрано (lead, 2026-05-22)_
_Сложность: middle_
_Объём: M_
_Plan-review: approved_

### Где живёт логика и куда вписываемся

- Источник истины эволюции (`evolvesTo`, `evolutionThreshold`) приедет из
  TASK-031 как поля `UnitKind` (см. AC TASK-031). Мы их **только читаем** —
  ничего не дублируем в коде задачи.
- Сам триггер эволюции — в `CityEngine.applyTaskCompleted`
  (`Sources/CityDeveloper/Game/CityEngine.swift`), сразу **после**
  `appendSystemEvent(.unitBuilt, …)` и **до** `stage_up`-ветки.
  Это совпадает с edge-case'ом «порог достигается прямо в момент создания
  юнита» из ТЗ.
- Системное событие `unit_evolved` добавляем в `GameEvent.Kind`
  (`Sources/CityDeveloper/Data/GameEvent.swift`).
- Визуал — отдельный callback `onUnitEvolved` на CityEngine, который
  в `AppDelegate` мапится на новый метод `GameScene.handleUnitEvolved(...)`.
  Внутри сцены используем уже существующий механизм cross-fade из
  `swapStageSprite` (тот же 0.5 сек fadeOut/fadeIn, bottom-anchor сохраняется).

### Модель данных и события

1. **`GameEvent.Kind`** — добавить `case unitEvolved = "unit_evolved"`.
   Это новый тип; по принципу backwards-compat (см. LogFormat «Поведение
   при неизвестных kind») старый бинарь, читающий новый лог, такие строки
   пропустит — приемлемо, но фиксируем в LogFormat.md.

2. **Payload `unit_evolved`** — нужно передавать `unitId`, `from`, `to`,
   `projectId`. Текущая структура `GameEvent` уже содержит `project`
   (это `projectId`) и `title`. **Не вводим** новые поля в `GameEvent`
   (это сломало бы Codable старого формата). Вместо этого:
   - `event.project` = `projectId`;
   - `event.title` = `"<unitId.uuidString>|<from.rawValue>|<to.rawValue>"`
     (компактный, парсится при replay, плюс человекочитаем в журнале);
   - альтернатива (если в TASK-031 поле `payload: [String:String]?`
     уже добавлено — проверить при имплементации) — использовать его.

   _Решение: пайплайн через `title` — потому что добавлять новое опциональное
   поле в `GameEvent` ради одного события расширяет blast-radius (миграция
   snapshot не нужна, но появляются null'ы во всех старых event'ах).
   `title`-string detail в LogFormat.md._

3. **`apply(.unitEvolved)`** в `CityEngine.apply(...)` — **обязан**
   при `silent: true` (replay) изменять `state.units[unitId].kind`
   из `from` в `to`, без записи нового события. Без этого replay не
   восстановит итоговый `CityState` — нарушится AC «Replay-safe».
   Важно: `UnitState.kind` сейчас `let`, нужно сделать `var` (это
   мелкое, не ломает Codable).

### Алгоритм триггера в `applyTaskCompleted`

Псевдокод вставляется между `appendSystemEvent(.unitBuilt, …)` и
блоком `if newStage > oldStage { appendSystemEvent(.stageUp, …) }`:

```
// applyEvolutionsIfReady(projectId): итеративно, пока есть «созревшие» группы.
//   Итерация нужна для каскада «2 Землянки → 2 Лачуги; теперь 2 Лачуги → 2 Дома»
//   в один тик (когда порог одной эволюции = 2, а старых Лачуг ровно 0).
//   Защита от бесконечного цикла: на каждой итерации ≥ 1 эволюция, иначе break.
repeat {
    let changed = applyEvolutionsIfReady(projectId: projectKey, event: event)
} while changed
```

`applyEvolutionsIfReady(projectId, event)`:
1. Берём все юниты квартала (`state.units.values.filter { $0.projectId == projectKey }`).
2. Группируем по `kind`. Для каждой `kind`:
   - если у `kind` нет `evolvesTo` — skip;
   - если `count < evolutionThreshold` — skip;
   - если у `evolvesTo` `minStage > project.stage` — skip
     (edge case явно в AC: Доходный дом minStage=3, квартал на stage 1 → не
     эволюционируем; следующая попытка будет после `stage_up`).
3. Для каждой "созревшей" группы (count ≥ threshold):
   - берём **ровно `threshold` старейших** юнитов этой группы
     (сортировка по `taskTs asc → id asc` — детерминировано и совпадает
     при live и replay);
   - для каждого выбранного юнита пишем `appendSystemEvent(.unitEvolved, …)`
     с `title = "<uuid>|<fromRaw>|<toRaw>"`;
   - `apply(.unitEvolved, silent: false)` обновит `state.units[uid].kind`
     и дёрнет `onUnitEvolved?(unitId, from, to, projectId)` (новый callback);
   - возвращает `true` (была хотя бы одна эволюция).
4. Если ни одной группы не созрело — возвращает `false`.

**Почему ровно threshold, а не «все»**: ТЗ AC4 явно требует порционности —
«3 Лачуги не дотягивают до порога 2 → Дом не создаётся». Если бы
эволюция меняла всех, при 3 Лачугах все 3 стали бы Домами, что
противоречит AC4. Берём ровно `threshold` старейших, остаток ждёт
следующего порога. AC1 формулировка «все юниты данного типа меняют
`UnitKind`» интерпретируется как «все юниты *данного порога*»
(подтверждается AC4 и user-сценарием п.2 «при достижении 2-х _свежих_
Лачуг они также превращаются в Дома»). Если PM считает иначе —
эскалация на уточнение ТЗ; до уточнения держим логику порционно
(внутренне непротиворечивая, реплеится).

**Tier**: при подмене `kind` сохраняем текущий `tier` юнита
(он = stage квартала). Координата (`position`), `id`, `projectId`,
`taskTitle`, `taskTs`, `taskSource`, `decayLevel` — **не трогаем**.

### Replay-цикл и snapshot

- `apply(.unitEvolved, silent: true)` в `CityEngine.apply(_:)` парсит `title`
  → меняет `state.units[uid].kind`. Это всё. Никаких новых событий не пишет,
  не дёргает callbacks.
- `apply(.unitEvolved, silent: false)` дополнительно вызывает
  `onUnitEvolved?(...)` для визуала.
- Edge case «старый state.json до этой задачи не содержит `unit_evolved`»:
  при загрузке snapshot + tail replay просто не встретит таких событий —
  никаких миграций не нужно. При первом следующем `unit_built` (после
  загрузки) сработает обычный триггер эволюции — это и есть «ленивая»
  эволюция из AC, по факту бесплатно.
- Snapshot/eventsSinceSnapshot инкрементируется автоматически через
  `appendSystemEvent` — отдельной логики не нужно.

### Визуал в `GameScene`

Добавляем метод:

```swift
func handleUnitEvolved(unitId: UUID, from: UnitKind, to: UnitKind, projectId: String) {
    DispatchQueue.main.async { [weak self] in
        guard let self, self.didAttach,
              let engine = self.engine,
              let unit = engine.state.units[unitId],   // state уже с new kind
              let node = self.unitNodes[unitId] else { return }
        self.swapEvolvedSprite(in: node, unit: unit)
    }
}
```

`swapEvolvedSprite(in:unit:)` — копия `swapStageSprite`, но:
- new `building` строится через `UnitSprites.makeCategoricalBuilding(category: unit.kind.category, stage: unit.tier)`;
  категория может смениться (Землянка→Лачуга обе residential, Склад→Большой
  склад обе production — у текущих эволюционных пар категории совпадают,
  но не закладываем это в код, читаем из `unit.kind.category`);
- guard на руину (`ruinNode`) и legacy-ноду без `name="building"`
  идентичен `swapStageSprite`;
- fadeOut 0.5 + fadeIn 0.5 параллельно (≤ 0.5 сек на юнит — AC).

**Не выделяем** в общий приватный helper `swap(in:newBuilding:)`, чтобы
не трогать TASK-019-код в одном PR (минимизация blast-radius);
дубликат ~15 строк — приемлемо. Если в TASK-036 потребуется ещё одна
подмена — рефакторим там общим helper'ом.

### Callback wiring

`CityEngine`:
```swift
var onUnitEvolved: ((UUID, UnitKind, UnitKind, String) -> Void)?
```

`AppDelegate.applicationDidFinishLaunching`:
```swift
engine.onUnitEvolved = { [weak self] uid, from, to, projectId in
    self?.scene?.handleUnitEvolved(unitId: uid, from: from, to: to, projectId: projectId)
}
```

### Edge cases — явная обработка

| Кейс | Поведение | Где |
|------|-----------|-----|
| Декай-уровень квартала > 0 | Эволюция срабатывает, decay overlay остаётся (он на parent-контейнере, не на `building`) | `applyEvolutionsIfReady` — без проверки decayLevel; визуально — см. примечание в `swapStageSprite:269` |
| Декай == 4 (руина) | Юниты квартала уже не в `state.units` (удалены в ruin-priority), либо `ruinNode` блокирует swap. Эволюция не сработает естественно. | guard в `swapEvolvedSprite` (ruinNode) |
| Threshold достигнут в момент `unit_built` | Эволюция применяется в той же транзакции, события в порядке `unit_built` → `unit_evolved` × N → `stage_up?` | вставка между этими блоками в `applyTaskCompleted` |
| Цель эволюции имеет `minStage > project.stage` | Skip — повторная попытка после следующего `unit_built` (когда stage уже мог измениться) | проверка в `applyEvolutionsIfReady` |
| Каскад в один тик (Землянка → Лачуга → Дом) | `repeat { } while changed` — итерируем, пока есть созревшие группы | обёртка вокруг `applyEvolutionsIfReady` |
| Старый state.json без `unit_evolved` | Никакой миграции — лениво применится при следующем `unit_built` | поведение «само собой» (apply event'а никаких побочных эффектов на старые юниты не имеет) |
| `apply(.unitEvolved)` с `unitId`, который уже не в state | `state.units[uid]?.kind = to` — silent no-op через optional chaining; пишем `ErrorsLog.write` для диагностики | в `apply` |
| Цель эволюции — `large = true` (Доходный дом, Усадьба, Большой склад) | По концепту F-16 — это нормально, визуально это просто другие 1×1-клетки с другим спрайтом (не сливаем в 2×2). Явно в скоупе ТЗ («не объединяем клетки в один крупный юнит») | без специальной обработки |

### Технические заметки

- `apply` в `CityEngine` — `private`. Изменение `UnitState.kind` с `let`
  на `var` — единственное изменение `CityState.swift` в этой задаче
  (помимо того, что прилетит из TASK-031). Codable не ломается
  (var Codable property работает идентично let).
- Парсинг `title` `"<uuid>|<from>|<to>"` — отдельная static helper в
  `GameEvent` (`unitEvolvedPayload(from title: String?) -> (UUID, UnitKind, UnitKind)?`),
  чтобы не плодить хардкод-сплиты в `apply`. Тип события — константа
  `GameEvent.Kind.unitEvolved` (AC «нет хардкод-строк»).
- Threshold-сортировка `taskTs asc → id asc` — детерминирована и совпадает
  с `replayFromLog` (события идут по порядку появления → `state.units`
  упорядочен по событиям → `taskTs` монотонно возрастает у юнитов одного
  типа). При live и replay даём один и тот же `event.title` для эволюции
  → snapshot идентичен.

### Тесты (CityDeveloperTests/CityEngineTests.swift)

Добавить тест-кейсы:
1. **`testEvolutionTriggersOnThreshold`** — искусственно завершаем 2 task'а в
   одном проекте, в стартовом состоянии нет юнитов; ожидаем: 2 `.unitBuilt`
   + 2 `.unitEvolved`, итоговые `state.units[*].kind == .shack` (Лачуга).
2. **`testEvolutionRespectsMinStage`** — каскад «Дом → Доходный дом»
   (`minStage=3`) при stage квартала = 1: 3 `.unitBuilt` для домов, ноль
   `.unitEvolved`.
3. **`testEvolutionReplayIsDeterministic`** — после live-сценария удаляем
   `state.json`, заново создаём engine с тем же `events.jsonl` → итоговый
   `state.units[*].kind` идентичен.
4. **`testEvolutionWithDecay`** — поднимаем `project.decayLevel` до 2,
   достигаем порог → эволюция срабатывает.
5. **`testEvolutionCascadesInSingleTick`** — стартуем с состоянием 1 Лачуга,
   достраиваем 1 Землянку, проверяем что итог = 2 Лачуги + (если порог
   совпал) → каскад до Дома. _NB: точная цепочка зависит от порядка
   эволюций, но в любом случае проверяем что в одном тике может быть
   ≥ 2 `.unitEvolved` разных типов._

### Документация

- `LogFormat.md` → добавить строку в таблицу `kind`:
  ```
  | `unit_evolved`  | визуальная эволюция юнита по порогу F-16        | `<uid>|<from>|<to>` |
  ```
  и в раздел «Порядок» дополнить: `unit_built` → (`unit_evolved` × N опц.)
  → (`stage_up` опц.).
- `Current.md` → F-16 пометить ⚠️ (эволюция готова, общий F-16 — после TASK-040).
- `Diff.md` → D-16 не закрывать.

### Blast-radius

- `CityState.swift` — `UnitState.kind: let` → `var` (одна правка).
- `GameEvent.swift` — `Kind.unitEvolved`, helper-парсер payload.
- `CityEngine.swift` — `apply(.unitEvolved)`-ветка, `onUnitEvolved`-callback,
  блок `repeat { applyEvolutionsIfReady(...) } while changed` в
  `applyTaskCompleted`.
- `GameScene.swift` — `handleUnitEvolved` + `swapEvolvedSprite`.
- `AppDelegate.swift` — wiring `engine.onUnitEvolved`.
- `LogFormat.md`, `Current.md` — обновление документации.

Никаких изменений в `UnitPlanner`, `DistrictPlanner`, `StageRules`,
`DecayEngine`, `DistrictPlanner`, `LifeSimulationManager`, `CitizenManager`,
`SnapshotStore`, `StateSnapshot`. F-08 (TASK-019 swap) не трогаем
(дубликат на 15 строк — осознанное решение).

### Готовность к старту

⚠️ Технически готова к разбору, **но кодирование стартовать нельзя до
закрытия TASK-031** (нужны поля `evolvesTo`/`evolutionThreshold` на
`UnitKind` и сами case'ы `.dugout`, `.hut`, `.stoneHouse`, `.twoStoryHouse`,
`.farmhouse`, `.tenementHouse`, `.manor`, `.largeWarehouse`) и
TASK-032 (placeholder-спрайты для целей эволюции, иначе подменять не
на что — UI покажет битый спрайт). Этот разбор финализирует план;
исполнитель берёт задачу сразу после готовности TASK-031 и TASK-032.

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: middle_ (определил лид)
_Объём: M_

### Definition of Done

#### Функциональные
- [x] Все AC выполнены
- [ ] Done-критерий проверен в реальном использовании (искусственный
      `tasks.jsonl` на 6 жилых задач в одном проекте → эволюция Землянка →
      Лачуга → Дом видна на сцене) — ручная проверка при запуске

#### Технические
- [x] Компиляция/линтер без новых ошибок (Build complete)
- [x] Тесты не сломаны
- [x] Нет хардкод-строк (тип события `unit_evolved` — в `GameEvent.Kind.unitEvolved`)

#### Обновление документации
- [x] `Current.md`: F-16 → ⚠️ (эволюция готова, общий F-16 — после TASK-040)
- [x] `Diff.md`: D-16 не закрывать — закрывается только после TASK-040
- [x] `LogFormat.md`: описан новый тип события `unit_evolved` (поля, semantics, порядок)
- [ ] Новые идеи → `Backlog.md`, новые баги → `Bugs.md`

---

## Статус

`[ ] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[x] done` / `[ ] skipped`

> NB: формально `ready`, но кодирование стартует только после закрытия
> TASK-031 и TASK-032 (см. раздел «Готовность к старту»).

## Метаданные
- Создана PM: 2026-05-22
- Spec-review: approved
- Lead-review: approved (2026-05-22)
- Plan-review: approved
- Blocked-by: TASK-031, TASK-032
- Готова к работе: 2026-05-22 (после TASK-031, TASK-032)
- Завершена: 2026-05-22
- Коммит: f1567a3
