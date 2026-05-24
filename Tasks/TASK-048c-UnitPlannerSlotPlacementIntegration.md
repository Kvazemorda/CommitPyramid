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

_Статус: [ ] нужен разбор_

> Заполняется командой `/lead 048c`.

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: middle (граничит с senior — меняет публичный API + integration)_
_Объём: M_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] `swift test --filter UnitPlannerSlotPlacementTests` — 5/5 PASS
- [ ] `swift test --filter CityEngineTemplateAssignmentTests` — 3/3 PASS
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

`[x] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[ ] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-24
- Spec-review: approved
- Blocked-by: TASK-047 ✅, TASK-048a, TASK-048b
- Готова к работе: —
- Завершена: —
- Коммит: —
