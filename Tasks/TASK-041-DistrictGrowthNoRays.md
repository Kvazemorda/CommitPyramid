# TASK-041: Перестроить рост квартала — без 8-лучевых выбросов

## Связь
- **F-07** из Concept.md (Алгоритм застройки квартала)
- **F-21** из Concept.md (Дорожная сеть города)
- **BUG-011** из Bugs.md
- **Приоритет:** P0

---

## 📋 Постановка от менеджера

_Автор: opus (orchestrator)_
_Дата: 2026-05-24_

### Что хотим

Сейчас при ≥100 зданиях в квартале UnitPlanner начинает класть здания по 8
фиксированным направлениям («лучами») всё дальше от origin — образуется звезда
из домов на расстоянии до 60 тайлов вокруг квартала, видимая как «город из 8
лучей». Нужно: квартал растёт плотными кольцами (петлями) дорог, здания
заполняют пространство ВНУТРИ петли, при заполнении — добавляется следующая
петля. Здания не перекрывают друг друга и не выходят за пределы петель.

### Пользовательский сценарий

1. Пользователь добавляет большой git-репо (500+ коммитов) → запускает Reset с
   датой 5 лет назад.
2. На карте появляется квартал, дорога-петля строится в первых 24 task'ах,
   потом — здания заполняют интерьер петли.
3. Когда интерьер заполнен, автоматически достраивается следующая петля
   рядом, и здания продолжают застраиваться в ней.
4. Здания НЕ выходят за пределы текущих петель, НЕ накладываются друг на
   друга, кварталы остаются визуально компактными.
5. Соседние кварталы не смешиваются — каждый занимает свой ограниченный
   ареал.

### Acceptance criteria

- [ ] При импорте репо 500+ коммитов нет ни одного здания дальше 8 тайлов от
      ближайшей road-клетки своего квартала.
- [ ] Ни одно здание не перекрывает другое (по footprint X×Y).
- [ ] Ни одно здание не стоит на road-клетке (магистраль или ветка).
- [ ] При заполнении первой петли (≈20 buildable клеток × loop) автоматически
      добавляется extendDistrictPlan ДО того как nextPosition спросит позицию.
- [ ] Кол-во петель растёт пропорционально числу зданий: capacity_per_loop ≈
      `(2*halfW-1)*(depth-1) - num_large_buildings*(size-1)`. После N зданий
      должно быть `ceil(N / capacity) + 1` петель.
- [ ] При визуальном осмотре карта НЕ имеет паттерна «8 лучей из origin».

### Что НЕ делаем (границы скоупа)

- Не меняем categoryPattern (F-07 ротация residential/infra/production/social).
- Не меняем форму петли (computeLoop геометрия остаётся U-shape).
- Не меняем алгоритм выбора kind (UnitPlanner.nextUnitKind — это task BUG-014).
- Не оптимизируем для overlap производительность ниже O(N×candidates) — для
  ≤2000 юнитов это OK.

### Edge cases

- [ ] Здание с footprint 2×2: занимает 4 клетки. Снова класть на эту зону
      ничего нельзя.
- [ ] Загруженный квартал (1000+ юнитов): extendDistrictPlan не должен
      бесконечно расти — стоп при `loopCount > 20` (limit, лог error).
- [ ] Два соседних квартала с overlap'ом петель — кто заполнил первым, того и
      клетки. Конфликта быть не должно благодаря allCells (общий Set).
- [ ] Replay 5000 событий: позиции должны быть детерминированы (тот же seed
      → те же позиции).

### Зависимости

- BUG-014 (footprint sizes) — без него все здания 1×1 и тест ослаблен. Делать
  параллельно, итог объединить визуально.
- F-21 RoadNetwork.extendDistrictPlan уже умеет добавлять петлю на следующую
  сторону.

### Дизайн

Не применимо (нет UI).

### Done-критерий

_Из Concept.md F-07:_

> Юниты группируются «кварталами» вокруг центра проекта (`districtOrigin`).
> Размещение детерминировано (`UnitPlanner.nextPosition`), без коллизий, в
> ограниченном radius'е, чтобы город оставался визуально читаемым.

---

## 🛠 Технический разбор от тимлида

_Автор: opus (orchestrator)_
_Дата: 2026-05-24_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

- **`UnitPlanner.nextPosition`** (`Sources/CityDeveloper/Game/UnitPlanner.swift:280-332`):
  - Перебирает `depth ∈ 1...6` × `anchor` (road-клетки в ±4 от origin) × `side
    ∈ [1,-1]`. Это даёт ≤ 6 × 30 × 2 = 360 кандидатов.
  - При `buildingIndex > 360` → `legacyRingPosition` с `ring = i/8 + 1` —
    бесконечные кольца в 8 фиксированных направлениях. ← **корень багa**.
  - `footprintOverlapsRoad` проверяет ТОЛЬКО road-клетки. Здания друг на друге
    не проверяются. ← **второй баг**.
- **`RoadNetwork.extendDistrictPlan`** (`Sources/CityDeveloper/Game/RoadNetwork.swift:139`):
  - Добавляет петлю с противоположной стороны при вызове. Возвращает кол-во
    добавленных клеток.
  - НЕ вызывается автоматически — нужен вызов из CityEngine.
- **`CityEngine.applyTaskCompleted`** (`Sources/CityDeveloper/Game/CityEngine.swift:302-308`):
  - Уже есть auto-extend: при `isPlanComplete && buildingsSoFar >= capacity`
    зовёт `extendDistrictPlan`. Но capacity считается заранее, без учёта
    footprint размеров (предполагает 1×1), и nextPosition вызывается СРАЗУ
    после в этом же тике — может не получить новых road-клеток (план обновлён,
    но клетки ещё не построены — `consumeNextPlanCell` строит по одной за task).
- **`RoadNetwork.loopInteriorCapacity`** = `(2*halfW-1) × (depth-1)` = 5×4 = 20.
  Это и есть N свободных клеток в одной петле.

### Архитектурное решение

Три изменения:

1. **Реактивный extendDistrictPlan.** В `CityEngine.applyTaskCompleted` ПОСЛЕ
   выбора kind и unitSize, ПЕРЕД вызовом `nextPosition`, цикл: пока
   `nextPosition` не находит non-overlap позицию в пределах текущих петель,
   звать `extendDistrictPlan` (до 3 раз / тик, потом ошибка в лог). Это
   гарантирует что nextPosition всегда видит достаточно road-клеток для
   ANCHORS.

2. **builtCells tracking в UnitPlanner.** UnitPlanner получает 3-й аргумент
   `builtCells: Set<GridPoint>` (все клетки, занятые другими зданиями этого И
   соседних кварталов). `footprintOverlapsRoad` переименовать в
   `footprintBlocked` — проверяет и `roads`, и `builtCells`. Передавать из
   CityEngine: `state.units.values.flatMap { $0.position и footprint }`.

3. **Убрать legacyRingPosition выход за пределы петель.** Если все depth/anchor
   позиции заняты → НЕ уходить в ring, а вернуть `nil` (через optional
   GridPoint). CityEngine видит nil → НЕ создаёт юнит для этого тика, кидает
   ошибку в лог. Альтернатива: вызвать ещё `extendDistrictPlan` (но это шаг 1
   уже покрывает). `legacyRingPosition` оставить только для строго empty
   roadCells (нет дорожной сети совсем) — fallback на спираль вокруг origin
   ограниченную radius'ом 6.

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку. Шаг непонятен — НЕ импровизируй,
> возвращай задачу через сообщение.

1. **Расширить сигнатуру `UnitPlanner.nextPosition`** `[AC:2,3]`
   - Файл: `Sources/CityDeveloper/Game/UnitPlanner.swift`
   - Метод: `nextPosition(origin:buildingIndex:roadCells:unitSize:)`
   - Добавить параметр `builtCells: Set<GridPoint>` (третий, перед unitSize).
   - Возвращаемый тип сменить на `GridPoint?` (optional).
   - Скелет:
     ```swift
     func nextPosition(
         origin: GridPoint,
         buildingIndex: Int,
         roadCells: Set<GridPoint>,
         builtCells: Set<GridPoint>,
         unitSize: GridSize = GridSize(width: 1, height: 1)
     ) -> GridPoint?
     ```

2. **Реализовать `footprintBlocked`** `[AC:2,3]`
   - В UnitPlanner добавить:
     ```swift
     private func footprintBlocked(
         at pos: GridPoint, size: GridSize,
         roads: Set<GridPoint>, built: Set<GridPoint>
     ) -> Bool {
         for dx in 0..<size.width {
             for dy in 0..<size.height {
                 let p = GridPoint(x: pos.x + dx, y: pos.y + dy)
                 if roads.contains(p) || built.contains(p) { return true }
             }
         }
         return false
     }
     ```
   - Заменить `footprintOverlapsRoad` на `footprintBlocked` во всех вызовах.

3. **Изменить логику перебора в `nextPosition`** `[AC:1,5]`
   - Заменить старый `for depth in 1...6 { ... attempts == i ... }` на:
     - Собрать ВСЕ свободные позиции (depth ∈ 1...depthLimit=5, anchor ∈
       nearby, side ∈ [+1,-1]) → массив `candidates: [GridPoint]`.
     - Если `candidates.isEmpty` → return nil.
     - Детерминировано выбрать i-й через `i % candidates.count` (НЕ растёт за
       пределы найденных).
   - depthLimit = depth, при котором ещё нет overlap с соседним кварталом
     (loopDepth = 5, depthLimit = 5 OK).

4. **Убрать `legacyRingPosition` из основного пути** `[AC:6]`
   - `nextPosition` НЕ вызывает legacyRingPosition если roadCells.isEmpty == false.
   - При empty roadCells оставить старый legacyRingPosition НО с
     `min(ring, 3)` (max 24 здания через ring).

5. **CityEngine: реактивный extendDistrictPlan** `[AC:4]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift:312-341`
   - В блоке после выбора kind и size, перед `position =`:
     ```swift
     var position: GridPoint? = nil
     var extends = 0
     while position == nil && extends < 5 {
         let builtSet = Set(state.units.values
             .filter { $0.projectId == projectKey }
             .flatMap { unit -> [GridPoint] in
                 let s = unit.kind.size
                 var cells: [GridPoint] = []
                 for dx in 0..<s.width {
                     for dy in 0..<s.height {
                         cells.append(GridPoint(
                             x: unit.position.x + dx,
                             y: unit.position.y + dy))
                     }
                 }
                 return cells
             })
         position = unitPlanner.nextPosition(
             origin: project.districtOrigin,
             buildingIndex: buildingIndex,
             roadCells: roadNetwork?.allCells ?? [],
             builtCells: builtSet,
             unitSize: kind.size
         )
         if position == nil {
             extends += 1
             let added = roadNetwork?.extendDistrictPlan(projectId: projectKey) ?? 0
             if added == 0 { break }
         }
     }
     guard let placedPos = position else {
         ErrorsLog.write("CityEngine: no position for unit \(kind.rawValue) in \(projectKey) — skipping")
         return
     }
     ```
   - Использовать `placedPos` вместо `position` в дальнейших строках UnitState.

6. **Лимит на loopCount** `[AC:4]`
   - Файл: `Sources/CityDeveloper/Game/RoadNetwork.swift:139`
   - В `extendDistrictPlan` ДО добавления петли:
     ```swift
     guard (districtLoopSides[projectId]?.count ?? 0) < 20 else {
         ErrorsLog.write("RoadNetwork: loop limit 20 reached for \(projectId)")
         return 0
     }
     ```

### Edge cases (явно обработать)

- [ ] **Quartile с 0 зданий** — buildingIndex = 0, builtCells пустое, должен
      найти первую позицию (anchor=любая road-клетка, depth=1, side=+1).
- [ ] **Все depth заняты** — extendDistrictPlan добавляет петлю, retry. Если
      `added == 0` (limit 20) → return nil, skip юнит.
- [ ] **2×2 здание в углу петли** — footprint может выйти за пределы петли.
      `footprintBlocked` проверит и road и built — если ни roads ни built не в
      выходящих клетках, считается валидно (юнит просто за петлёй).
- [ ] **Replay deterministic** — `nearby.sorted` остаётся, candidates строятся
      в детерминированном порядке. `i % candidates.count` детерминирован.

### Файлы для изменения

- `Sources/CityDeveloper/Game/UnitPlanner.swift` — сигнатура nextPosition,
  footprintBlocked, новый алгоритм перебора без legacyRing.
- `Sources/CityDeveloper/Game/CityEngine.swift` — реактивный
  extendDistrictPlan в applyTaskCompleted.
- `Sources/CityDeveloper/Game/RoadNetwork.swift` — лимит loopCount в
  extendDistrictPlan.

### Файлы НЕ трогать

- `Sources/CityDeveloper/Game/RoadNetwork.swift` (кроме одного лимита) —
  computeLoop и геометрия петель остаются как есть.
- `Sources/CityDeveloper/Game/UnitSprites.swift` — визуал не меняется.

### Команды проверки (для DoD)

- Компиляция: `swift build`
- Тесты: `swift test --filter UnitPlanner`
- Ручная проверка:
  1. Удалить `~/Library/Application Support/CommitPyramid/{events.jsonl,state.json,catchup-state.json,worldmap.json}`
  2. Запустить приложение
  3. В Settings выбрать дату 2024-01-01, Reset
  4. Подождать импорт (3 мин для 7 репо)
  5. Открыть карту, осмотреть кварталы — нет лучей, плотная застройка, петли
     заполнены целиком, новые петли добавлены пропорционально размеру

### Сложность
`senior` — архитектурное изменение алгоритма, несколько файлов, детерминизм
важен для replay.

### Объём
M (≤1д)

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: senior_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Done-критерий проверен в реальном использовании (визуально нет лучей)

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Тесты не сломаны (UnitPlannerTests если есть)
- [ ] Нет хардкод-строк

#### Обновление документации
- [ ] `Current.md`: F-07 → ✅
- [ ] `Bugs.md`: BUG-011 → закрыт
- [ ] Если найдены новые баги → `Bugs.md`

---

## Статус
`[x] done`

## Метаданные
- Создана PM+Lead: 2026-05-24
- Spec-review: skipped (opus single-pass)
- Готова к работе: 2026-05-24
- Завершена: 2026-05-24
- Коммит: 2840287
