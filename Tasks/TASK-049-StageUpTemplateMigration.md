# TASK-049: Template migration на stage-up (квартал «улучшается», юниты остаются)

## Связь
- **F-25** из Concept.md (шаблоны кварталов)
- **D-25** из Diff.md (часть 3/5 — миграция формы при stage-up)
- **F-08** (стадии 0→5 — миграция должна работать на каждый stage++)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-24_

### Что хотим

Сейчас при stage-up квартала (F-08) меняется только визуал юнитов (tier).
**Форма квартала остаётся та же** — шаблон stage 1 не превращается в
шаблон stage 2. Этого Илья хочет: чтобы квартал «улучшался годами», а не
только «обрастал юнитами в одной и той же форме».

Эта TASK: на каждом `applyProjectStageChange` (stage_up event) подменять
текущий `ProjectState.templateName` на новый шаблон stage+1 той же
family, **сохраняя позиции существующих юнитов**.

Инвариант дизайна шаблонов (заложен в TASK-047): для каждой пары
`(stage N, stage N+1)` в одной family bbox stage N ⊆ bbox stage N+1 и
роли слотов совместимы (slot (x,y) с role X в N → есть slot (x,y) с
role X в N+1, либо пустая клетка которая роль не блокирует).

### Пользовательский сценарий

1. Квартал «Foo» в stage 1 имеет шаблон Deir el-Medina (10 юнитов).
2. Stage 1 → 2 (formula StageRules) → CityEngine triggers
   `applyTemplateMigration`: новый шаблон = Kahun (stage 2 egyptian).
3. Все 10 существующих юнитов (хижины + колодец + дорога) **остаются на
   своих координатах**. Их позиции (3, 2), (4, 2), ... соответствуют слотам
   Kahun (потому что Deir el-Medina ⊆ Kahun bbox).
4. У Kahun добавились новые слоты по периметру (ферма, амбар, дом
   старосты) — они **свободны**, заполнятся следующими task_completed.
5. Визуально пользователь видит: квартал не «передёрнулся», а **раскрылся**
   — появились новые тайлы дорог и пустые слоты, готовые принять новые
   здания. Анимация: cross-fade новых тайлов земли + road-extension за
   ≤1 сек.
6. Если миграция невозможна (например, в catalog нет stage+1 шаблона той
   же family) → fallback: квартал остаётся со старым шаблоном, warning в
   errors.log: `[template-migration] no stage+1 template for family X,
   keeping stage N template`.

### Acceptance criteria

- [ ] В `CityEngine.applyProjectStageChange` (или эквивалент — найти точку
      через Explore) после изменения `project.stage` вызывается
      `applyTemplateMigration(project:)`.
- [ ] `applyTemplateMigration` алгоритм:
      a) Получить `currentTemplate` через `templateName`.
      b) Получить `nextTemplate` через Picker(stage: project.stage,
         family: project.templateFamily, biome: ..., seed: ...).
      c) Проверить инвариант: для каждого занятого слота currentTemplate
         (`projectUnits` имеют позицию = слот) в `nextTemplate` есть слот
         с **той же координатой** и **совместимой role**. Совместимость:
         residential ↔ residential (любого footprint), well ↔ well,
         road ↔ road; обновлять role для слотов с одной ролью точно
         можно, для разных — нет.
      d) Если инвариант нарушен (хоть один существующий юнит «выпадает»
         из nextTemplate) → НЕ мигрировать, warning, оставить currentTemplate.
      e) Если ОК — обновить `project.templateName` на `nextTemplate.name`,
         emit `GameEvent.Kind.templateMigrated(projectId, fromTemplate,
         toTemplate)`.
- [ ] Новый `GameEvent.Kind` case `templateMigrated(projectId: String,
      fromTemplate: String, toTemplate: String)` — записывается в events.jsonl,
      replay воспроизводит.
- [ ] `GameScene.handleProjectStageChanged` дорисовывает новые road-клетки
      и пустые тайлы земли через `drawAddedRoadCells` (уже есть в BUG-017
      инфраструктуре) + cross-fade ≤1 сек.
- [ ] Инвариант шаблонов проверяется в `DistrictTemplateCatalogTests`:
      `testStageNContainsStageNMinusOne(family: "egyptian")` для каждой
      пары (1→2, 2→3, 3→4, 4→5). Если падает — шаблоны нужно переделать.
- [ ] Тест `CityEngineTemplateMigrationTests.swift`:
      `testStageUpMigratesTemplate`, `testMigrationPreservesUnitPositions`,
      `testMigrationSkippedWhenIncompatible`, `testMigrationIsReplayable`.

### Что НЕ делаем (границы скоупа)

- НЕ делаем era progression (era 1-3 после stage 5) — это TASK-050.
- НЕ делаем Settings UI — это TASK-051.
- НЕ позволяем «перерасставить» юниты (это сломало бы replay) — только
  bbox-расширение шаблона.

### Edge cases

- [ ] Старый проект без `templateName` (legacy snapshot) → миграция
      пропускается, продолжает работать на legacy placement.
- [ ] `nextTemplate == nil` (для stage 5 нет stage 6 шаблона — это
      ожидаемо до TASK-050 era progression) → миграция пропускается без
      warning'а.
- [ ] Quick double stage-up (1→2→3 за один тик) → миграция применяется
      последовательно: 1→2, потом 2→3. Каждая отдельным
      `templateMigrated` event.
- [ ] Юнит в позиции, которая в nextTemplate занята слотом другой role
      (например, residential было, а в nextTemplate тут warehouse) →
      инвариант нарушен, миграция skipped. Это сигнал «шаблоны надо
      пересмотреть».
- [ ] decay-4 квартал (руины) → миграция skipped (нет смысла улучшать
      руины).
- [ ] Replay: при чтении старого `templateMigrated` event'а из
      events.jsonl шаблоны должны иметь те же `name` (иначе replay
      сломается). При смене формата шаблона нужна явная миграция
      `events.jsonl v2` (out-of-scope этой TASK).

### Зависимости

- **Blocked-by:** TASK-047 (catalog), TASK-048 (templateName в ProjectState).
- **Soft-blocks:** TASK-050 (era progression — для stage 5 → era 1
  использует тот же mechanism).

### Дизайн

Не применимо (нет UI; визуал — расширение road-сети + новые пустые
тайлы, уже покрыто BUG-017 инфраструктурой).

### Done-критерий

_Часть F-25 Done-критерия:_ «При stage-up до 2 квартал визуально
превращается в Kahun-сетку, существующие хижины остаются на своих
местах + появляются новые слоты». Эта TASK закрывает это полностью.

---

## 🛠 Технический разбор от тимлида

_Статус: [ ] нужен разбор_

> Заполняется командой `/lead 049`.

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_ (определит лид)
_Объём: M_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Smoke: создать проект, закрыть 10 задач (stage 1 → 2 через
      StageRules) — визуально на карте квартал «раскрылся», старые
      юниты на своих местах, новые слоты доступны для следующих задач.

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Тесты не сломаны (включая UnitPlannerTests, DistrictTemplateCatalogTests,
      DistrictTemplatePickerTests)
- [ ] Replay 500 events детерминирован (templateMigrated порядок и
      результат)
- [ ] events.jsonl v1 backwards-compat (старые logs без templateMigrated
      грузятся, миграция пропускается)

#### Обновление документации
- [ ] `Current.md`: F-25 → ⚠️ (часть 3/5)
- [ ] `Diff.md`: D-25 не закрывать
- [ ] `concept/LogFormat.md`: добавить описание `templateMigrated`
      event'а

---

## Статус

`[x] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[ ] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-24
- Spec-review: approved
- Blocked-by: TASK-047, TASK-048
- Готова к работе: —
- Завершена: —
- Коммит: —
