# TASK-048: `DistrictTemplatePicker` + slot-based размещение в `UnitPlanner`

## Связь
- **F-25** из Concept.md (шаблоны кварталов)
- **D-25** из Diff.md (часть 2/5 — выбор + интеграция в planner)
- **BUG-009** (квартал на воде — picker может фильтровать через biomePreference)
- **BUG-010** (первый юнит должен быть road — picker должен дать road-слот в stage 1)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-24_

### Что хотим

После TASK-047 у нас есть формат и 5 egyptian-шаблонов. Теперь нужно научить
движок их **использовать**: при создании нового проекта (`onProjectCreated`)
выбрать шаблон через `DistrictTemplatePicker` и положить ссылку в
`ProjectState.templateName`. Дальше `UnitPlanner.nextPosition` должен
выбирать **следующий свободный слот** этого шаблона, подходящий по роли (для
выбранного `UnitKind` через `kind.preferredSlotRole`).

Если шаблон закончился (все слоты заняты) — fallback на legacy `nextPosition`
с warning'ом в errors.log (это сигнал «шаблон надо переделать» в follow-up).

### Пользовательский сценарий

1. Пользователь добавляет новый проект → CityEngine создаёт ProjectState,
   Picker выбирает Deir el-Medina (stage 1, egyptian) → `project.templateName =
   "stage1-deir-el-medina"`.
2. Закрывается первая задача → UnitPlanner возвращает `kind = .road` (BUG-010
   инвариант), nextPosition находит road-слот шаблона по позиции `(3, 2)` →
   юнит ставится туда. Дорога обозначена в шаблоне явно.
3. Следующие задачи закрывают residential-слоты, потом well-слот, и т.д.
4. Когда все 12 слотов Deir el-Medina заняты — fallback на legacy
   (квартал «выйдет за рамки шаблона»), errors.log: `[template] district X
   exceeded slot capacity (12/12), falling back to legacy placement`.

### Acceptance criteria

- [ ] `ProjectState` расширен полями `templateName: String?` (default nil) и
      `templateFamily: String?` (default nil). Codable с backwards-compat
      (старые snapshot загружаются, поля = nil).
- [ ] Создан `DistrictTemplatePicker` с методом `pick(stage: Int, family:
      String, biome: BiomeKind?, seed: UInt64) -> DistrictTemplate?`:
      фильтрует catalog по `stage`, `family`, `biomePreference`
      (если biome задан и biomePreference не пустой), детерминированно
      выбирает через SplitMix64(seed).
- [ ] `family` берётся из `AppSettings.templateFamily` (новое поле, default
      `"auto"`); если `auto` — выбирается по biome: meadow/desert →
      "egyptian", остальное → "egyptian" (пока единственная family; после
      добавления Roman/Greek в TASK-051 follow-up будет реальный map).
- [ ] В `CityEngine.onProjectCreated` (или эквиваленте — найти точку через
      Explore) вызывается Picker, результат записывается в
      `project.templateName` и `project.templateFamily`.
- [ ] Добавлен `extension UnitKind { var preferredSlotRole: SlotRole }` —
      mapping kind → SlotRole. Покрыты все 51 kind: residential-категория →
      `.residential`, .well → `.well`, .road → `.road`, .market → `.market`,
      .temple/.chapel/.cathedral/.pyramid → `.temple`, .workshop/.forge/etc →
      `.workshop`, .farm/.fishingPier → `.farm`, .bathhouse → `.bath`,
      .school/.library → `.school`, .obelisk → `.obelisk`, .gate → `.gate`,
      .warehouse/.largeWarehouse → `.warehouse`, monumental kinds →
      `.monumental`.
- [ ] `UnitPlanner.nextPosition` принимает новый необязательный параметр
      `template: DistrictTemplate?`. Если задан — находит **первый
      свободный слот** с `role == kind.preferredSlotRole` (по
      детерминированному порядку — отсортированному по `(slot.y, slot.x)`),
      возвращает его координаты + footprint.
- [ ] Если шаблон задан и подходящих свободных слотов нет —
      `nextPosition` возвращает nil (НЕ fallback), CityEngine ловит nil и
      делает fallback на legacy depth=1, пишет warning в errors.log.
- [ ] Тесты в `DistrictTemplatePickerTests.swift`:
      `testPickerFiltersByStageAndFamily`,
      `testPickerIsDeterministic`,
      `testPickerRespectsBiomePreference`,
      `testPickerReturnsNilWhenNoMatch`.
- [ ] Тесты в `UnitPlannerSlotPlacementTests.swift` (расширение
      UnitPlannerTests из TASK-038):
      `testNextPositionUsesTemplateSlot`,
      `testFallbackWhenSlotsExhausted`,
      `testFirstUnitIsRoadInTemplate` (BUG-010 регресс).

### Что НЕ делаем (границы скоупа)

- НЕ делаем stage-up migration — это TASK-049.
- НЕ делаем era progression — это TASK-050.
- НЕ делаем Settings UI Picker — это TASK-051.
- НЕ удаляем legacy `extendDistrictPlan` / `depth=1` placement — он
  остаётся как fallback.

### Edge cases

- [ ] `project.templateName == nil` (старый проект до миграции) →
      `nextPosition` идёт сразу в legacy ветку, без warning'а.
- [ ] Шаблон с пустыми slots (`[]`) → Picker всё равно может вернуть
      его (валидный), но `nextPosition` сразу даст nil → legacy.
- [ ] AppSettings.templateFamily = "auto" + biome = nil → дефолт
      "egyptian".
- [ ] `kind.preferredSlotRole` не нашёл свободного слота, но в шаблоне
      есть свободные слоты других ролей → НЕ переназначать (это сломает
      F-07 пропорции), а вернуть nil → legacy.
- [ ] `kind == .road` в шаблоне без road-слотов (теоретически возможно
      для нестандартных шаблонов) → legacy через `RoadNetwork.consumeNextPlanCell`.
- [ ] Slot.footprint = 2×2, но клетки (x+1, y) или (x, y+1) выходят за
      `template.width/height` → шаблон должен был быть отбракован при
      load (TASK-047), но defence in depth: warning + nil.

### Зависимости

- **Blocked-by:** TASK-047 (нужен DistrictTemplate + Catalog).
- **Soft-blocks:** TASK-049 (migration требует чтобы template уже был на
  ProjectState).

### Дизайн

Не применимо (нет UI — только модель + algorithm).

### Done-критерий

_Часть F-25 Done-критерия:_ «При создании нового проекта в Settings выбран
"Egyptian" — квартал выглядит как Deir el-Medina». Эта TASK даёт первую
половину (выбор шаблона + slot-based размещение); вторая половина
(визуальная читаемость квартала) — следствие.

---

## 🛠 Технический разбор от тимлида

_Статус: [ ] нужен разбор_

> Заполняется командой `/lead 048`.

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_ (определит лид)
_Объём: M_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] При запуске игры + создании нового проекта (через add-task.sh)
      первый юнит .road появляется на координатах road-слота из
      stage1-deir-el-medina.json, не на спирали

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Существующие 67+ тестов не сломаны (включая UnitPlannerTests из TASK-038)
- [ ] Replay 100 events детерминирован (один и тот же templateName)
- [ ] Снапшот state.json backwards-compat — старые без templateName грузятся

#### Обновление документации
- [ ] `Current.md`: F-25 → ⚠️ (часть 2/5)
- [ ] `Diff.md`: D-25 не закрывать
- [ ] BUG-010 (первый юнит road) — если slot-based размещение делает это
      автоматически через road-слот в шаблоне → закрыть BUG-010

---

## Статус

`[x] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[ ] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-24
- Spec-review: approved
- Blocked-by: TASK-047
- Готова к работе: —
- Завершена: —
- Коммит: —
