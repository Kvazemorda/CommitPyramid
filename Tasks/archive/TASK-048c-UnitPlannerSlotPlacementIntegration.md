# TASK-048c: `UnitPlanner.nextPosition` slot-based + `CityEngine.onProjectCreated` integration

## Связь
- **F-25** из Concept.md (шаблоны кварталов)
- **D-25** из Diff.md (часть 2.3/5 — интеграция в движок)
- **BUG-009** (квартал на воде — Picker через biomePreference)
- **BUG-010** (первый юнит должен быть road — slot-placement решает)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-24_

### Что хотим

Финальная интеграция Picker + slot-placement в реальный pipeline движка:
1. При создании нового проекта в CityEngine вызвать Picker, сохранить
   `project.templateName/templateFamily` в state.
2. При размещении нового юнита в `UnitPlanner.nextPosition` (или
   эквивалентная точка) — если шаблон задан, найти **свободный слот** с
   подходящей role; вернуть его координаты + footprint. Если шаблон
   закончился — fallback на legacy depth=1-от-road placement.
3. После этого квартал визуально становится «упорядоченным»: первый юнит
   road попадает в road-слот шаблона, residential — в residential-слоты,
   well — в well-слот, etc.

### Пользовательский сценарий

1. Пользователь добавляет новую задачу с новым projectId.
2. `CityEngine.applyTaskCompleted` (или `onProjectCreated`) видит «нет
   ProjectState с таким projectId» → создаёт ProjectState:
   - `templateFamily = AppSettings.shared.templateFamily` (из TASK-048a).
   - `seed = fnv1a([projectId])`.
   - `template = DistrictTemplatePicker.pick(stage: 1, family:
     templateFamily, biome: biomeReader?.biome(...), seed: seed)`.
   - Если template != nil → `project.templateName = template.name`,
     `project.templateFamily = template.family`. Если nil → оставить nil
     (legacy placement).
3. UnitPlanner возвращает road для первой задачи (BUG-010 инвариант).
4. `nextPosition` смотрит на `project.templateName` → загружает template из
   Catalog → ищет первый свободный road-слот в template → возвращает его
   координаты `(districtOrigin.x + slot.x, districtOrigin.y + slot.y)` +
   footprint.
5. Юнит ставится точно в road-слот шаблона. Следующие residential юниты
   заполняют residential-слоты по тому же принципу.
6. Когда все слоты заполнены — `nextPosition` возвращает nil → CityEngine
   fallback на legacy `RoadNetwork.consumeNextPlanCell` + depth=1 → юнит
   ставится «за периметром шаблона», warning в errors.log.

### Acceptance criteria

- [ ] `UnitPlanner.nextPosition` принимает новый необязательный
      параметр в конце сигнатуры:
      `template: DistrictTemplate? = nil` и `districtOrigin: GridPoint`
      (уже передаётся в planner? — уточнить в lead через Explore; если
      нет — добавить).
- [ ] Логика нового slot-based выбора в `nextPosition`:
      ```
      Если template == nil → idu в legacy ветку (как сейчас).
      Иначе:
        targetRole = kind.preferredSlotRole  // из TASK-048b
        Среди template.slots — найти первый свободный слот с
          slot.role == targetRole, отсортированный по (slot.y, slot.x).
        Слот занят, если в `occupiedCells` есть пересечение с footprint
          этого слота. occupiedCells — Set<GridPoint> со всеми клетками
          уже поставленных юнитов проекта.
        Если найден → вернуть absolutePosition (districtOrigin + slot.x,
          districtOrigin + slot.y) + footprint slot.footprint.
        Если не найден → return nil.
      ```
- [ ] CityEngine fallback на nil: если `nextPosition(...)` вернул nil И
      `project.templateName != nil` → ErrorsLog.write `[template] district
      <projectId> exceeded slot capacity, falling back to legacy
      placement` + вызвать **существующую** legacy ветку (current
      `nextPosition` логика без template). Не падать.
- [ ] В `CityEngine.applyTaskCompleted` (или существующей точке
      onProjectCreated) — при создании нового ProjectState вызывается
      `DistrictTemplatePicker.pick(...)` и результат пишется в
      `project.templateName/templateFamily`.
- [ ] Тесты `UnitPlannerSlotPlacementTests.swift`:
      - `testNextPositionUsesTemplateSlotForRoad`: создать тест-template
        (фикстура — stage1-deir-el-medina), вызвать
        `nextPosition(kind: .road, template: t, occupiedCells: [],
        districtOrigin: (0,0))` → результат == road-слот из шаблона
        (по sorted order: (1,2) — самый верхний-левый road).
      - `testNextPositionFindsNextFreeSlotWhenFirstOccupied`: занять (1,2)
        (cell в occupiedCells), вызвать с kind=.road → результат (2,2).
      - `testNextPositionReturnsNilWhenAllSlotsOccupied`: занять все
        road-слоты → kind=.road → nil.
      - `testNextPositionFallsBackToLegacyWhenTemplateNil`: template=nil →
        результат идёт через старую ветку (просто проверить что не nil
        для типовой ситуации с road-сетью).
      - `testFirstUnitIsRoadInTemplate` (BUG-010 регресс): через
        end-to-end `CityEngine.applyTaskCompleted` нового projectId —
        первый создаваемый юнит имеет `kind == .road` И его position лежит
        в одном из road-слотов template.
- [ ] Тесты `CityEngineTemplateAssignmentTests.swift`:
      - `testNewProjectGetsTemplateAssigned`: applyTaskCompleted для нового
        projectId → ProjectState имеет templateName != nil И templateFamily
        == AppSettings.shared.templateFamily (либо resolved через auto).
      - `testTemplateAssignmentIsDeterministic`: два движка с одинаковым
        AppSettings + одинаковым projectId → один и тот же templateName.
      - `testTemplateAssignmentReplayable`: applyTaskCompleted → save state
        → создать новый движок, load state → templateName тот же.

### Что НЕ делаем (границы скоупа)

- НЕ делаем stage-up migration — это TASK-049.
- НЕ делаем era progression — это TASK-050.
- НЕ делаем Settings UI — это TASK-051.
- НЕ удаляем legacy `extendDistrictPlan` / depth=1 placement — он
  остаётся как fallback при nil или exhausted template.
- НЕ закрываем BUG-009 (квартал на воде) — picker через biomePreference
  фильтрует только template, но DistrictPlanner.allocateNextOrigin ещё
  ставит origin на воду. Это отдельный bug fix, не часть F-25.

### Edge cases

- [ ] `project.templateName != nil` но template не найден в catalog
      (например, удалили JSON между запусками) → `loadTemplate` возвращает
      nil → fallback на legacy + warning в errors.log.
- [ ] `kind.preferredSlotRole` не имеет ни одного слота в template
      (например, шаблон без `.monumental` слотов, а planner вернул
      pyramid) → return nil → fallback (как «exhausted»).
- [ ] `kind.footprint != slot.footprint`: например, kind.size == 3×3 (manor),
      но slot.footprint == 1×1 (residential в Deir el-Medina). **На этом
      этапе игнорируем footprint match** — берём первый подходящий слот
      по role. Если получился overlap с другими юнитами — это будет
      поймано через `occupiedCells` (cells slot занимают только
      slot.footprint клеток, а юнит положится в kind.footprint клеток —
      если kind.footprint > slot.footprint, юнит «вылезет» за слот в
      соседние клетки; это OK в MVP, в follow-up можно фильтровать
      кандидатов по `slot.footprint == kind.size`).
- [ ] `districtOrigin + slot.x` уходит за границы карты (256×256) → не
      проверяем здесь, это работа BUG-009 fix. На текущем шаге Picker
      выдаёт template, который **точно** входит в bbox карты (шаблоны
      маленькие 8×5..16×16, district origin не на самом краю).
- [ ] Replay legacy state без templateName: `templateName == nil` → как
      «нет шаблона» → legacy placement. Дефолтное поведение существующих
      проектов не меняется.
- [ ] Concurrent access: `nextPosition` вызывается на main thread из
      CityEngine — нет concurrency issues.

### Зависимости

- **Blocked-by:** TASK-047 ✅, TASK-048a (поля ProjectState), TASK-048b
  (Picker + preferredSlotRole).
- **Soft-blocks:** TASK-049 (migration), TASK-050 (era progression), TASK-051
  (Settings UI).

### Дизайн

Не применимо (нет UI; визуально — юниты ставятся в чёткие позиции
шаблона, что и есть желаемый результат).

### Done-критерий

_Из F-25:_ «При создании нового проекта в Settings выбран "Egyptian" —
квартал выглядит как Deir el-Medina (компактный посёлок с одной улицей
и колодцем по центру)». Эта TASK даёт это полностью — после неё новые
проекты получают шаблон и слот-based placement.

Также **закрывает BUG-010** (первый юнит road) если slot-placement
выбирает road-слот для первого юнита через `preferredSlotRole`.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-24_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

- В коде уже есть:
  - `Sources/CityDeveloper/Game/UnitPlanner.swift:282-358` — `nextPosition(origin:buildingIndex:roadCells:builtCells:unitSize:)`, легаси depth=1 от anchor. Не принимает kind/template.
  - `Sources/CityDeveloper/Game/CityEngine.swift:210-453` — `applyTaskCompleted`. Создаёт ProjectState на 277-291, planDistrict на 295, road-branch через `RoadNetwork.consumeNextPlanCell` на 322-328, building-branch (kind = nextUnitKind → loop nextPosition + extendDistrictPlan до 5 раз) на 329-384.
  - `Sources/CityDeveloper/Game/Templates/DistrictTemplate.swift` — `DistrictTemplate { name, family, stage, width, height, biomePreference, slots }`, `TemplateSlot { x, y, role, footprint }`, `enum SlotRole { residential, well, road, market, temple, workshop, farm, bath, school, obelisk, gate, warehouse, monumental }`.
  - `Sources/CityDeveloper/Game/Templates/DistrictTemplateCatalog.swift` — `all()`, `byFamily(_:)`, `byStage(_:family:)`, `availableFamilies()`, `validate(_:)`. **Нет `byName(_:)`.**
  - `Sources/CityDeveloper/Game/Templates/DistrictTemplatePicker.swift` — `static func pick(stage:family:biome:seed:) -> DistrictTemplate?` (TASK-048b).
  - `Sources/CityDeveloper/Game/Templates/UnitKindSlotRole.swift` — `UnitKind.preferredSlotRole: SlotRole` exhaustive switch (TASK-048b).
  - `Sources/CityDeveloper/Data/CityState.swift:440-509` — `ProjectState` с полями `templateName: String?`, `templateFamily: String?`, `eraLevel: Int` (TASK-048a).
  - `Sources/CityDeveloper/Data/AppSettings.swift:40-42` — `templateFamily: String = "auto"` (TASK-048a).
  - `Sources/CityDeveloper/Data/ErrorsLog.swift` — `static func write(_ message: String)`.
  - `Sources/CityDeveloper/Game/DeterministicRNG.swift:40-53` — `func fnv1a(combining values: [String]) -> UInt64`.
  - `Sources/CityDeveloper/Game/BiomeMapReader.swift` — `protocol BiomeMapReader { func biome(atX:y:) -> BiomeKind }`.
  - `Sources/CityDeveloper/Resources/DistrictTemplates/egyptian/stage1-deir-el-medina.json` — name="stage1-deir-el-medina", 8×5. **Road slots sorted (y,x):** (1,2),(2,2),(3,2),(4,2),(5,2),(6,2). **Residential slots:** (1,1),(2,1),(4,1),(5,1),(1,3),(3,3),(5,3),(6,3). **Well:** (2,3).

- Связанные модули:
  - `Tests/CityDeveloperTests/UnitPlannerTests.swift` (TASK-038) — uses `simulateDistrict` helper для nextUnitKind. Не покрывают nextPosition.
  - `Tests/CityDeveloperTests/CityEngineTests.swift` — `makeTempDir()`, `makeEngine(at:)` helpers — переиспользуем.
  - `Tests/CityDeveloperTests/DistrictTemplateCatalogTests.swift` — `resetCache()` helper.

- Что переиспользуем:
  - `DistrictTemplatePicker.pick`, `UnitKind.preferredSlotRole`, `fnv1a`, `ErrorsLog.write`, существующий legacy `nextPosition` (как fallback-ветка).

- Что нужно дописать:
  - `DistrictTemplateCatalog.byName(_:)`.
  - Расширение `UnitPlanner.nextPosition` двумя optional-параметрами + ветка slot-placement.
  - В `CityEngine.applyTaskCompleted`: вызов Picker после создания ProjectState; template-aware ветка размещения с fallback.
  - 2 новых тест-файла.

### Архитектурное решение

**Главный принцип:** templated и legacy режимы изолированы по флагу `project.templateName != nil`. В templated режиме road-плансть RoadNetwork остаётся (для fallback на исчерпание), но `consumeNextPlanCell` НЕ дренируем в primary-пути; вместо этого все юниты (включая road) проходят через `nextUnitKind → nextPosition(template:kind:)`. При nil-результате — тихо проваливаемся в существующую legacy-ветку (которая сама вытащит road-cell из плана через `consumeNextPlanCell` или подберёт depth=1 для здания). Backwards-compat сохранён: legacy-проекты (templateName == nil) идут по неизменённому коду.

**BUG-010 закрывается локально в templated mode** жёстким правилом: при `project.taskCount == 1 && project.templateName != nil` → `kind = .road`. Без template BUG-010 остаётся открытым (известное ограничение в Bugs.md).

**Slot-выбор** — детерминированная сортировка `(slot.y, slot.x)` (как в JSON естественный порядок), фильтр `slot.role == kind.preferredSlotRole`, проверка занятости через пересечение footprint-клеток слота с `occupiedCells: Set<GridPoint>`. Возврат `(districtOrigin.x + slot.x, districtOrigin.y + slot.y)`. **Footprint mismatch** (kind.size != slot.footprint) — игнорируем, отмечено в edge cases (юнит может "выехать" за слот, овер-лап ловится через occupiedCells на следующих шагах).

**Сидирование Picker:** `fnv1a(combining: [projectKey])` — детерминировано по projectId, не зависит от времени/порядка. Это обеспечивает `testTemplateAssignmentIsDeterministic` и replay-эквивалентность.

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку. Не меняй сигнатур существующих публичных методов, кроме указанных. Не трогай legacy-ветку nextPosition. При сомнении — НЕ импровизируй, возвращай задачу.

1. **Добавить `DistrictTemplateCatalog.byName(_:)`** `[AC:1,7,8]`
   - Файл: `Sources/CityDeveloper/Game/Templates/DistrictTemplateCatalog.swift`
   - Добавь публичный static метод **в существующий enum/struct** (там же, где `byStage`):
     ```swift
     static func byName(_ name: String) -> DistrictTemplate? {
         all().first(where: { $0.name == name })
     }
     ```
   - Не изменяй кэш / threading — `all()` уже thread-safe (ioQueue).

2. **Расширить `UnitPlanner.nextPosition` slot-параметрами** `[AC:1,2]`
   - Файл: `Sources/CityDeveloper/Game/UnitPlanner.swift`
   - Метод: `nextPosition(...)` (строки 282-288).
   - Новая сигнатура (добавить два **trailing optional** параметра — backwards-compat обеспечен default'ами):
     ```swift
     func nextPosition(
         origin: GridPoint,
         buildingIndex: Int,
         roadCells: Set<GridPoint>,
         builtCells: Set<GridPoint>,
         unitSize: GridSize = GridSize(width: 1, height: 1),
         template: DistrictTemplate? = nil,
         kind: UnitKind? = nil
     ) -> GridPoint?
     ```
   - В самом начале метода (до `let i = max(0, buildingIndex)`) — slot-branch:
     ```swift
     if let t = template, let k = kind {
         let targetRole = k.preferredSlotRole
         let sorted = t.slots
             .filter { $0.role == targetRole }
             .sorted { ($0.y, $0.x) < ($1.y, $1.x) }
         for slot in sorted {
             // Проверка занятости: пересечение footprint слота с builtCells.
             var occupied = false
             for dx in 0..<slot.footprint.width {
                 for dy in 0..<slot.footprint.height {
                     let cell = GridPoint(
                         x: origin.x + slot.x + dx,
                         y: origin.y + slot.y + dy)
                     if builtCells.contains(cell) { occupied = true; break }
                 }
                 if occupied { break }
             }
             if !occupied {
                 return GridPoint(x: origin.x + slot.x, y: origin.y + slot.y)
             }
         }
         return nil  // exhausted — CityEngine провалит в legacy
     }
     ```
   - НЕ менять существующий legacy-блок ниже (lines 289-358 текущего файла).

3. **CityEngine: вызов Picker при создании ProjectState** `[AC:3,4]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`
   - **Точное место вставки:** строго **ВНУТРИ ветки нового проекта** (после строки 291 `eraLevel: 0` + закрывающей `)` инициализатора `ProjectState`), **ПЕРЕД** строкой 295 `roadNetwork?.planDistrict(projectId: projectKey, origin: origin)`. В этом скоупе локальные переменные `origin: GridPoint`, `projectKey: String`, `project: var ProjectState` уже доступны.
   - **Также:** строку 295 (`roadNetwork?.planDistrict(...)`) **обернуть в `if project.templateName == nil`** — для templated-проектов план дорог не строим (см. шаг 4 «архитектурное обоснование»). Если template exhausted, fallback пойдёт через legacy `nextPosition` (с магистралью в `roadCells` или legacyRingPosition).
   - Добавь точно такой код (заменить старую строку 295 на блок):
     ```swift
     // TASK-048c F-25: pick district template for new project.
     let resolvedFamily = AppSettings.shared.templateFamily
     let pickSeed = fnv1a(combining: [projectKey])
     let pickBiome = biomeReader?.biome(atX: origin.x, y: origin.y)
     if let picked = DistrictTemplatePicker.pick(
         stage: 1,
         family: resolvedFamily,
         biome: pickBiome,
         seed: pickSeed
     ) {
         project.templateName = picked.name
         project.templateFamily = picked.family
     }

     // Запланировать дорогу квартала ТОЛЬКО для legacy-проектов (без template).
     // Templated-проекты не используют RoadNetwork plan — road-юниты ставятся
     // в road-слоты template. Fallback (template exhausted) использует
     // legacy nextPosition с магистралью в roadCells / legacyRingPosition.
     if project.templateName == nil {
         roadNetwork?.planDistrict(projectId: projectKey, origin: origin)
     }
     ```
   - `AppSettings.shared` — синглтон, используется в проекте. `fnv1a` — top-level free function в `DeterministicRNG.swift`.

4. **CityEngine: template-aware ветка kind+position** `[AC:2,3,5]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`
   - Место: блок lines 322-384 (resolution of `kind` и `placedPos`).
   - Логика — обёртка вокруг существующих веток. Псевдо-структура (внутри `applyTaskCompleted`, после блока подсчёта счётчиков и `extendDistrictPlan` авто-расширения):
     ```swift
     let kind: UnitKind
     let placedPos: GridPoint

     // TASK-048c: templated path.
     // ВАЖНО: `project` к этому моменту уже взят из state.projects[...] или
     // создан выше — поле templateName уже заполнено для нового проекта.
     if let templateName = project.templateName,
        let template = DistrictTemplateCatalog.byName(templateName) {
         // BUG-010 fix (только в templated mode): первый юнит — всегда road.
         let resolvedKind: UnitKind
         if project.taskCount == 1 {
             resolvedKind = .road
         } else {
             let districtBiome = biomeReader?.biome(atX: project.districtOrigin.x, y: project.districtOrigin.y)
             resolvedKind = unitPlanner.nextUnitKind(
                 forTaskIndex: project.taskCount,
                 stage: project.stage,
                 biome: districtBiome,
                 residentialCount: residentialCount,
                 wellCount: wellCount,
                 infraCount: infraCount,
                 productionCount: productionCount,
                 socialCount: socialCount
             )
         }
         // Собираем occupiedCells заранее (то же, что в legacy ветке).
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
         let planLen = roadNetwork?.plannedCells(for: projectKey).count ?? 0
         let buildingIndex = max(0, project.taskCount - planLen - 1)
         if let slotPos = unitPlanner.nextPosition(
             origin: project.districtOrigin,
             buildingIndex: buildingIndex,
             roadCells: roadNetwork?.allCells ?? [],
             builtCells: builtSet,
             unitSize: resolvedKind.size,
             template: template,
             kind: resolvedKind
         ) {
             kind = resolvedKind
             placedPos = slotPos
         } else {
             // Template exhausted (no free slot for this role) → fallback to legacy.
             ErrorsLog.write("[template] district \(projectKey) exceeded slot capacity for role \(resolvedKind.preferredSlotRole.rawValue), falling back to legacy placement")
             let legacy = resolveLegacyKindAndPosition(
                 project: &project,
                 projectKey: projectKey,
                 residentialCount: residentialCount,
                 wellCount: wellCount,
                 infraCount: infraCount,
                 productionCount: productionCount,
                 socialCount: socialCount
             )
             guard let legacy else { return }
             kind = legacy.kind
             placedPos = legacy.pos
         }
     } else {
         // Legacy path (templateName == nil или template не найден в catalog).
         if project.templateName != nil {
             ErrorsLog.write("[template] district \(projectKey): template \(project.templateName!) not found in catalog, falling back to legacy")
         }
         let legacy = resolveLegacyKindAndPosition(
             project: &project,
             projectKey: projectKey,
             residentialCount: residentialCount,
             wellCount: wellCount,
             infraCount: infraCount,
             productionCount: productionCount,
             socialCount: socialCount
         )
         guard let legacy else { return }
         kind = legacy.kind
         placedPos = legacy.pos
     }
     ```
   - **`resolveLegacyKindAndPosition`** — новый `private` хелпер в `CityEngine` (внизу класса). **Единственная финальная сигнатура** (project: `ProjectState`, НЕ inout — legacy-блок не модифицирует project; `silent: Bool` — параметр, чтобы хелпер мог решить, гасить ли `onRoadCellsAdded`):
     ```swift
     private func resolveLegacyKindAndPosition(
         project: ProjectState,
         projectKey: String,
         residentialCount: Int,
         wellCount: Int,
         infraCount: Int,
         productionCount: Int,
         socialCount: Int,
         silent: Bool
     ) -> (kind: UnitKind, pos: GridPoint)? {
         // Перенос текущего блока строк 322-384 целиком (road branch + building
         // loop + ErrorsLog "no position" guard) с возвратом tuple вместо
         // присваивания локальных kind/placedPos.
         if let rn = roadNetwork,
            !rn.isPlanComplete(for: projectKey),
            let roadCell = rn.consumeNextPlanCell(for: projectKey) {
             return (.road, roadCell)
         }
         let districtBiome = biomeReader?.biome(atX: project.districtOrigin.x, y: project.districtOrigin.y)
         let kind = unitPlanner.nextUnitKind(
             forTaskIndex: project.taskCount,
             stage: project.stage,
             biome: districtBiome,
             residentialCount: residentialCount,
             wellCount: wellCount,
             infraCount: infraCount,
             productionCount: productionCount,
             socialCount: socialCount
         )
         let planLen = roadNetwork?.plannedCells(for: projectKey).count ?? 0
         let buildingIndex = max(0, project.taskCount - planLen - 1)
         var foundPos: GridPoint? = nil
         var extends = 0
         while foundPos == nil && extends < 5 {
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
             foundPos = unitPlanner.nextPosition(
                 origin: project.districtOrigin,
                 buildingIndex: buildingIndex,
                 roadCells: roadNetwork?.allCells ?? [],
                 builtCells: builtSet,
                 unitSize: kind.size
             )
             if foundPos == nil {
                 extends += 1
                 let added = roadNetwork?.extendDistrictPlan(projectId: projectKey) ?? []
                 if added.isEmpty { break }
                 if !silent { onRoadCellsAdded?(added) }
             }
         }
         guard let resolved = foundPos else {
             ErrorsLog.write("CityEngine: no position for unit \(kind.rawValue) in \(projectKey) — skipping")
             return nil
         }
         return (kind, resolved)
     }
     ```
   - В обоих вызовах хелпера в шаге 4 передавай `silent: silent` (переменная `silent` — параметр `applyTaskCompleted`, видна в скоупе).
   - **Архитектурное обоснование выбора не вызывать `planDistrict` для templated-проектов** (см. шаг 3): иначе `isPlanComplete` навсегда остаётся `false` (т.к. `consumeNextPlanCell` не вызывается в templated пути), и блок auto-extend в строках 309-317 будет постоянно генерировать `extendDistrictPlan` бесплатные петли. Не вызывая planDistrict для templated, держим инвариант чистым: templated → нет плана дорог → `isPlanComplete == true` (план пустой) → auto-extend не срабатывает. Fallback на legacy при exhausted template работает через `nextPosition(template:nil)` с magistral roadCells / legacyRingPosition.

5. **Тесты `UnitPlannerSlotPlacementTests.swift`** `[AC:6]`
   - Файл: `Tests/CityDeveloperTests/UnitPlannerSlotPlacementTests.swift` (новый).
   - Скелет:
     ```swift
     import XCTest
     @testable import CityDeveloper

     final class UnitPlannerSlotPlacementTests: XCTestCase {
         private func makeFixtureTemplate() -> DistrictTemplate {
             // Точная копия stage1-deir-el-medina (8×5), но in-memory чтобы не зависеть от Bundle.
             DistrictTemplate(
                 name: "test-stage1",
                 family: "test",
                 stage: 1,
                 width: 8, height: 5,
                 biomePreference: [.meadow],
                 slots: [
                     TemplateSlot(x: 1, y: 1, role: .residential, footprint: GridSize(width: 1, height: 1)),
                     TemplateSlot(x: 2, y: 1, role: .residential, footprint: GridSize(width: 1, height: 1)),
                     TemplateSlot(x: 1, y: 2, role: .road, footprint: GridSize(width: 1, height: 1)),
                     TemplateSlot(x: 2, y: 2, role: .road, footprint: GridSize(width: 1, height: 1)),
                     TemplateSlot(x: 3, y: 2, role: .road, footprint: GridSize(width: 1, height: 1)),
                     TemplateSlot(x: 1, y: 3, role: .residential, footprint: GridSize(width: 1, height: 1)),
                     TemplateSlot(x: 2, y: 3, role: .well, footprint: GridSize(width: 1, height: 1))
                 ]
             )
         }

         func testNextPositionUsesTemplateSlotForRoad() {
             let planner = UnitPlanner()
             let template = makeFixtureTemplate()
             let pos = planner.nextPosition(
                 origin: GridPoint(x: 0, y: 0),
                 buildingIndex: 0,
                 roadCells: [],
                 builtCells: [],
                 unitSize: GridSize(width: 1, height: 1),
                 template: template,
                 kind: .road
             )
             XCTAssertEqual(pos, GridPoint(x: 1, y: 2))  // первый road slot (sorted y,x)
         }

         func testNextPositionFindsNextFreeSlotWhenFirstOccupied() {
             let planner = UnitPlanner()
             let template = makeFixtureTemplate()
             let pos = planner.nextPosition(
                 origin: GridPoint(x: 0, y: 0),
                 buildingIndex: 0,
                 roadCells: [],
                 builtCells: [GridPoint(x: 1, y: 2)],
                 unitSize: GridSize(width: 1, height: 1),
                 template: template,
                 kind: .road
             )
             XCTAssertEqual(pos, GridPoint(x: 2, y: 2))
         }

         func testNextPositionReturnsNilWhenAllSlotsOccupied() {
             let planner = UnitPlanner()
             let template = makeFixtureTemplate()
             let occupied: Set<GridPoint> = [
                 GridPoint(x: 1, y: 2),
                 GridPoint(x: 2, y: 2),
                 GridPoint(x: 3, y: 2)
             ]
             let pos = planner.nextPosition(
                 origin: GridPoint(x: 0, y: 0),
                 buildingIndex: 0,
                 roadCells: [],
                 builtCells: occupied,
                 unitSize: GridSize(width: 1, height: 1),
                 template: template,
                 kind: .road
             )
             XCTAssertNil(pos)
         }

         func testNextPositionRespectsDistrictOriginOffset() {
             let planner = UnitPlanner()
             let template = makeFixtureTemplate()
             let pos = planner.nextPosition(
                 origin: GridPoint(x: 100, y: 50),
                 buildingIndex: 0,
                 roadCells: [],
                 builtCells: [],
                 unitSize: GridSize(width: 1, height: 1),
                 template: template,
                 kind: .road
             )
             XCTAssertEqual(pos, GridPoint(x: 101, y: 52))
         }

         func testNextPositionFallsBackToLegacyWhenTemplateNil() {
             let planner = UnitPlanner()
             // Legacy branch: одна road-клетка на (5,5), origin рядом.
             let road: Set<GridPoint> = [GridPoint(x: 5, y: 5)]
             let pos = planner.nextPosition(
                 origin: GridPoint(x: 5, y: 5),
                 buildingIndex: 0,
                 roadCells: road,
                 builtCells: [],
                 unitSize: GridSize(width: 1, height: 1),
                 template: nil,
                 kind: nil
             )
             // Legacy: должен вернуть позицию depth=1 от road. Проверяем adjacency:
             // pos должна быть одной из {(4,5),(6,5),(5,4),(5,6)} (manhattan dist 1
             // к road-клетке (5,5)) и НЕ совпадать с road.
             let p = try XCTUnwrap(pos)
             let neighbors: Set<GridPoint> = [
                 GridPoint(x: 4, y: 5), GridPoint(x: 6, y: 5),
                 GridPoint(x: 5, y: 4), GridPoint(x: 5, y: 6)
             ]
             XCTAssertTrue(neighbors.contains(p),
                 "Expected depth-1 adjacency to road, got \(p)")
         }
     }
     ```
   - Тест `testNextPositionFallsBackToLegacyWhenTemplateNil` помечен `throws` (использует `try XCTUnwrap`) — добавь `throws` в сигнатуру func.

6. **Тесты `CityEngineTemplateAssignmentTests.swift`** `[AC:6]`
   - Файл: `Tests/CityDeveloperTests/CityEngineTemplateAssignmentTests.swift` (новый).
   - **Реальные API** (проверены по коду): module — `CommitPyramid`; engine init — `CityEngine(eventLog: EventLog, snapshotStore: SnapshotStore)`; ingest — `ingestTaskCompletion(project: String, title: String, taskId: String?, source: String?, ts: Date)`; state-доступ — `engine.state` (public-read через `@Published private(set)`).
   - Скелет (4 теста — добавлен `testTemplateAssignmentReplayable` для покрытия PM AC):
     ```swift
     import XCTest
     @testable import CommitPyramid

     final class CityEngineTemplateAssignmentTests: XCTestCase {
         private func makeTempDir() -> URL {
             let dir = FileManager.default.temporaryDirectory
                 .appendingPathComponent("ce-tmpl-\(UUID().uuidString)")
             try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
             return dir
         }

         private func makeEngine(at dir: URL) -> CityEngine {
             let log = EventLog(fileURL: dir.appendingPathComponent("events.jsonl"))
             let snap = SnapshotStore(url: dir.appendingPathComponent("state.json"))
             return CityEngine(eventLog: log, snapshotStore: snap)
         }

         override func setUp() {
             super.setUp()
             AppSettings.shared.templateFamily = "egyptian"  // детерминизм
         }

         override func tearDown() {
             AppSettings.shared.templateFamily = "auto"
             super.tearDown()
         }

         func testNewProjectGetsTemplateAssigned() {
             let dir = makeTempDir()
             let engine = makeEngine(at: dir)
             engine.ingestTaskCompletion(
                 project: "proj-A", title: "first task",
                 taskId: nil, source: nil, ts: Date()
             )
             let project = engine.state.projects["proj-A"]
             XCTAssertNotNil(project)
             XCTAssertNotNil(project?.templateName)
             XCTAssertEqual(project?.templateFamily, "egyptian")
         }

         func testTemplateAssignmentIsDeterministic() {
             let dir1 = makeTempDir(); let dir2 = makeTempDir()
             let e1 = makeEngine(at: dir1)
             let e2 = makeEngine(at: dir2)
             e1.ingestTaskCompletion(project: "proj-X", title: "t",
                 taskId: nil, source: nil, ts: Date())
             e2.ingestTaskCompletion(project: "proj-X", title: "t",
                 taskId: nil, source: nil, ts: Date())
             let n1 = e1.state.projects["proj-X"]?.templateName
             let n2 = e2.state.projects["proj-X"]?.templateName
             XCTAssertNotNil(n1)
             XCTAssertEqual(n1, n2)
         }

         func testFirstUnitIsRoadInTemplate() throws {
             let dir = makeTempDir()
             let engine = makeEngine(at: dir)
             engine.ingestTaskCompletion(project: "proj-R", title: "first",
                 taskId: nil, source: nil, ts: Date())
             let project = try XCTUnwrap(engine.state.projects["proj-R"])
             let firstUnitId = try XCTUnwrap(project.unitIds.first)
             let unit = try XCTUnwrap(engine.state.units[firstUnitId.uuidString])
             XCTAssertEqual(unit.kind, .road)
             let templateName = try XCTUnwrap(project.templateName)
             let template = try XCTUnwrap(DistrictTemplateCatalog.byName(templateName))
             let roadSlots = template.slots.filter { $0.role == .road }
             let absoluteRoadSlots: Set<GridPoint> = Set(roadSlots.map {
                 GridPoint(x: project.districtOrigin.x + $0.x,
                           y: project.districtOrigin.y + $0.y)
             })
             XCTAssertTrue(absoluteRoadSlots.contains(unit.position),
                 "Expected \(unit.position) to be in road slots \(absoluteRoadSlots)")
         }

         func testTemplateAssignmentReplayable() throws {
             // Записываем events первым движком, потом создаём второй движок на том же
             // dir → second движок должен восстановить тот же templateName (через
             // snapshot/replay из events.jsonl).
             let dir = makeTempDir()
             let e1 = makeEngine(at: dir)
             e1.ingestTaskCompletion(project: "proj-Replay", title: "t",
                 taskId: nil, source: nil, ts: Date())
             let nameFirst = try XCTUnwrap(e1.state.projects["proj-Replay"]?.templateName)

             // Второй engine на том же dir — должен прочитать events.jsonl и
             // получить тот же templateName.
             let e2 = makeEngine(at: dir)
             // Если CityEngine требует явного replay-метода — вызвать его здесь.
             // Иначе init сам делает replay (как в существующих CityEngineTests).
             let nameSecond = try XCTUnwrap(e2.state.projects["proj-Replay"]?.templateName)
             XCTAssertEqual(nameFirst, nameSecond)
         }
     }
     ```
   - **Исполнителю:** если init `CityEngine` не делает auto-replay (видно из остальных тестов в `CityEngineTests.swift`), нужно вручную вызвать тот же replay-механизм, что использует prod-код. **НЕ менять public API** ради теста — если replay сложнее, вместо `testTemplateAssignmentReplayable` использовать прямую сериализацию через `JSONEncoder/Decoder` ProjectState (поле `templateName` уже Codable по TASK-048a).

### Edge cases (явно обработать)

- [ ] `project.templateName != nil`, но `DistrictTemplateCatalog.byName(...)` вернул `nil` (JSON удалили между запусками) → fallback на legacy + warning. Шаг 4 (else-ветка с `if project.templateName != nil { ErrorsLog.write(...) }`).
- [ ] `kind.preferredSlotRole` не имеет ни одного слота в template (например, pyramid → .monumental, а в stage1-deir-el-medina нет monumental-слотов) → `nextPosition` вернёт nil → fallback на legacy + warning. Шаг 2 (return nil) + шаг 4 (ErrorsLog).
- [ ] `kind.size != slot.footprint` (например, manor 3×3 в residential 1×1 slot) → **игнорируем mismatch на MVP**: ставим в позицию slot, юнит "вылезает" в соседние клетки; пересечение поймается на следующем юните через `builtCells` → тогда тот юнит уйдёт в next slot или вернёт nil. Документировано в PM spec edge cases.
- [ ] `districtOrigin + slot.x/y` за границей карты — НЕ проверяем, ответственность DistrictPlanner.allocateNextOrigin (Picker дает только подходящие small templates). Если падает в `state.units` insert — это баг DistrictPlanner, не TASK-048c.
- [ ] Legacy state без templateName (replay старого events.jsonl) → `templateName == nil` → legacy path. Backwards-compat работает (init defaults `templateName: nil`).
- [ ] Replay events.jsonl: Picker детерминирован (fnv1a([projectKey])), сохранение templateName в ProjectState через Codable (TASK-048a) → replay даёт идентичные templateName. **Подтвердить** запуском существующего replay-теста.
- [ ] Multi-thread: `applyTaskCompleted` вызывается на serial engine queue — нет concurrency issues. `DistrictTemplateCatalog.all()` thread-safe через ioQueue.
- [ ] `AppSettings.shared.templateFamily == "mixed"` — Picker сам resolved через RNG. Тест `testTemplateAssignmentIsDeterministic` использует "egyptian" чтобы не зависеть от resolve-логики.
- [ ] `AppSettings.shared.templateFamily == "auto"` — `DistrictTemplatePicker.pick` (TASK-048b) сам разрешает "auto" → "egyptian". Этот контракт обеспечивается Picker'ом, не CityEngine. CityEngine **тупо проксирует** значение из настроек, без preprocessing.
- [ ] **Fallback на legacyRingPosition при exhausted template:** если шаблон не имеет свободного слота для нужной role (например, residential при заполненных 8 слотах), exhausted-fallback ведёт через `resolveLegacyKindAndPosition`. Поскольку для templated проекта `planDistrict` не вызывался, `districtPlans[projectKey] == nil`, и `extendDistrictPlan(projectId:)` вернёт `[]` (guard в RoadNetwork:154-155). Цикл `while foundPos == nil && extends < 5` сразу выйдет через `break` (added.isEmpty). `nextPosition` ОДИН раз вызовется с `roadCells = roadNetwork?.allCells ?? []` (только магистраль, не в halfSide=4 от districtOrigin для удалённых кварталов) → `nearby` пустое → `legacyRingPosition` вокруг origin вернёт позицию. **Это запланированное поведение MVP, не баг.** Документировано в «Файлы НЕ трогать».

### Файлы для изменения

- `Sources/CityDeveloper/Game/Templates/DistrictTemplateCatalog.swift` — +6 строк (метод `byName`).
- `Sources/CityDeveloper/Game/UnitPlanner.swift` — +2 параметра в сигнатуре `nextPosition` + ~25 строк slot-branch в начале метода.
- `Sources/CityDeveloper/Game/CityEngine.swift` — ~10 строк Picker-вызова после создания ProjectState; ~70 строк template-aware ветка + новый private хелпер `resolveLegacyKindAndPosition` (~50 строк, перенос текущего блока).
- `Tests/CityDeveloperTests/UnitPlannerSlotPlacementTests.swift` — НОВЫЙ файл, ~120 строк, 5 тестов.
- `Tests/CityDeveloperTests/CityEngineTemplateAssignmentTests.swift` — НОВЫЙ файл, ~110 строк, 4 теста.

### Файлы НЕ трогать

- `Sources/CityDeveloper/Game/RoadNetwork.swift` — не меняем. **Важно:** в templated mode `planDistrict` НЕ вызывается (см. шаг 3); fallback на exhausted template деградирует до `legacyRingPosition` (план квартала пустой → `extendDistrictPlan` возвращает `[]` → `nextPosition` с `roadCells` из магистрали попадает в legacyRingPosition вокруг origin). Это **известное ограничение MVP** — квартал с исчерпанным шаблоном получит дополнительные юниты по кольцу вокруг origin, без новой road-сети. Acceptable для F-25 первой волны.
- `Sources/CityDeveloper/Game/DistrictPlanner.swift` — outside scope (BUG-009).
- `Sources/CityDeveloper/Game/Templates/DistrictTemplatePicker.swift` — уже готов, не меняем.
- `Sources/CityDeveloper/Game/Templates/UnitKindSlotRole.swift` — уже готов.
- `Sources/CityDeveloper/Data/CityState.swift` — поля уже добавлены в TASK-048a.
- `Sources/CityDeveloper/Data/AppSettings.swift` — поле templateFamily готово.
- `Tests/CityDeveloperTests/UnitPlannerTests.swift` — существующие 9 тестов TASK-038 не должны сломаться (default-значения template/kind = nil → legacy ветка → старое поведение).
- `Tests/CityDeveloperTests/CityEngineTests.swift` — существующие тесты должны пройти; templateFamily default "auto" в AppSettings — Picker может приписать template новым проектам в этих тестах. **Если падают** — починить локально через `AppSettings.shared.templateFamily = "..." ` в setUp/tearDown (но не менять semantics существующих assertions).

### Команды проверки (для DoD)

- Компиляция: `swift build`
- Все тесты: `swift test`
- Целевые тесты: `swift test --filter UnitPlannerSlotPlacementTests` (5/5 PASS), `swift test --filter CityEngineTemplateAssignmentTests` (4/4 PASS)
- Регресс tests TASK-038: `swift test --filter UnitPlannerTests` — все 9 PASS (default-параметры nil → legacy)
- Smoke replay: `swift test --filter CityEngineTests` — replay-эквивалентность не сломалась

### Сложность

`middle`

**Обоснование:** Меняем публичный API одного метода + интеграция в hot-path движка (5 файлов изменено / создано). Логика slot-placement сама по себе линейная, но требует аккуратной обработки fallback и сохранения замены kind=.road для BUG-010. Без архитектурной развилки.

### Ожидаемое время

M (≤1д)

---

## ✅ Исполнение

_Исполнитель: sonnet_
_Сложность: middle (граничит с senior — меняет публичный API + integration)_
_Объём: M_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] `swift test --filter UnitPlannerSlotPlacementTests` — 5/5 PASS
- [ ] `swift test --filter CityEngineTemplateAssignmentTests` — 4/4 PASS
- [ ] Smoke: `swift run CommitPyramid` + новая задача → первый юнит .road
      в позиции (districtOrigin.x+1, districtOrigin.y+2) или (districtOrigin.x+2,
      districtOrigin.y+2) и т.д. (любой road-слот из stage1-deir-el-medina)

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Существующие тесты не сломаны (включая TASK-038 UnitPlannerTests —
      они вызывают `nextUnitKind`, не `nextPosition`; новый параметр
      default=nil гарантирует backwards-compat).
- [ ] Replay 100 events детерминирован.

#### Обновление документации
- [ ] `Current.md`: F-25 → ⚠️ (часть 2.3/5 — основная логика интегрирована)
- [ ] `Diff.md`: D-25 не закрывать
- [ ] `Bugs.md`: BUG-010 → закрыт (если применимо)

---

## Статус

`[ ] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[x] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-24
- Spec-review: approved
- Blocked-by: TASK-047 ✅, TASK-048a ✅, TASK-048b ✅
- Готова к работе: 2026-05-24
- Lead-model: opus
- Plan-review: revised (3 круга: round1 needs-revision → round2 needs-revision → round3 needs-revision на 1 косметику, применена)
- Исполнитель: sonnet
- Verify: pass (5/5 + 4/4 новых, 9/9 регресс TASK-038, 4/4 регресс CityEngineTests, full suite 109/110 с 1 known-fail BUG-020)
- Code-review: approved (opus, 2 soft-issues — syncRoadNetworkPlans guard + AppDelegate wire — переносятся в follow-up)
- Завершена: 2026-05-24
- Коммит: 72ffcbd
