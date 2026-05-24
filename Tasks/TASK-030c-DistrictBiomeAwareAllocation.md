# TASK-030c: District placement с terrain-аффинитетом (biome-aware allocation)

## Связь
- **F-15** из Concept.md (биомы + аффинитет)
- **F-06** из Concept.md (размещение кварталов)
- **D-15** из Diff.md (часть 3/3 — финал, закрывает D-15)
- **Родитель:** TASK-030 (split-into-030a-b-c, lead-разбор 2026-05-23)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-24_

### Что хотим

После TASK-030b реинициализация работает — кварталы пересаживаются на новую
карту через спиральный `DistrictPlanner`. Но **не учитывают биом**:
квартал с большим количеством водных юнитов может оказаться в горах.

030c добавляет biome-aware allocation: при выборе origin для нового
квартала (или при replay после reinit) `DistrictPlanner` считает
**terrain-affinity score** проекта по составу его юнитов и предпочитает
origin-кандидаты в подходящем биоме. Это закрывает финальный AC из F-15:
«новый квартал рядом с рекой получает водные/речные юниты с заметно
большей вероятностью, чем равномерная».

### Пользовательский сценарий

1. У игрока город из 5 проектов, каждый с разным составом юнитов
   (рыболовный, горный, торговый, обычный, монументальный).
2. Игрок жмёт «Сбросить карту» с новым seed (через TASK-030a + 030b).
3. После reinit:
   - Рыболовный квартал (содержит fishingPier, port) — origin рядом с
     рекой/морем.
   - Горный (mine, quarry) — origin рядом с горами/камнями.
   - Торговый (market, warehouse) — origin на лугу около магистрали.
   - Обычный (shack, house, well) — origin на лугу.
   - Монументальный (pyramid, temple) — на ровном лугу или у пустыни.
4. Если нет подходящего биома для нужного типа (карта вся-луг) — fallback
   на спиральный `allocateNextOrigin` (текущее поведение).
5. Размещение детерминировано: одинаковый seed + одинаковый список проектов
   → одинаковые origin. Replay воспроизводим.

### Acceptance criteria

- [ ] Новый pure-helper `TerrainAffinity.preferredBiomes(for: ProjectState) -> [BiomeKind]`:
      по `project.unitIds` и составу юнитов возвращает ranked-список предпочтительных
      биомов. Алгоритм:
      - Для каждого `UnitKind` в проекте используется уже существующая
        `TerrainAffinity.weight(for: UnitKind, in: BiomeKind)` (из TASK-033)
        — суммируется по биомам.
      - Биомы сортируются по убыванию суммарного веса.
      - Биомы с весом < threshold (например, ≤ 0.3 × max) отсекаются.
      - Пустой результат → fallback `[.meadow, .desert]`.
- [ ] `DistrictPlanner.allocateNextOrigin(in:)` принимает дополнительный
      параметр `preferredBiomes: [BiomeKind] = []`:
      - Если параметр пустой — текущее поведение (спираль от центра).
      - Если задан — спираль продолжается, но **первые 20 кандидатов** на
        каждом «витке» фильтруются: оставляются только те, где origin-tile в
        одном из `preferredBiomes`. Если ни один не подошёл — возвращаемся
        к обычной спирали (fallback).
      - `biomeReader` (доступен через CityEngine) используется для проверки
        биома по grid-координатам.
- [ ] `CityEngine.replayFromLog` (из TASK-030b) и `applyTaskCompleted`
      (ветка isNewProject) вызывают `allocateNextOrigin` с
      `preferredBiomes = TerrainAffinity.preferredBiomes(for: project)`,
      когда `project.unitIds.count >= 3` (иначе данных мало — спираль).
- [ ] При reinit (TASK-030b replay) — для каждого `project` сначала
      «накапливаются» юниты через replay существующих `task_completed`,
      потом DistrictPlanner выбирает origin. Это уже делается естественно:
      `applyTaskCompleted` каждый раз пересчитывает (но для **первого** юнита
      `unitIds.isEmpty` → спираль; ок, на следующих юнитах origin не меняется).
      **Альтернатива** (если выбор origin только при создании проекта):
      использовать список юнитов из **исходного** state перед reinit.
      _Lead решит точную точку входа в разборе._
- [ ] Тест `TerrainAffinityPreferredBiomesTests`:
      `testFishingProjectPrefersRiverSea`,
      `testMiningProjectPrefersMountainStone`,
      `testNeutralProjectFallsBackToMeadowDesert`,
      `testEmptyProjectReturnsFallback`.
- [ ] Тест `DistrictPlannerBiomeAwareTests`:
      `testBiomeAwareSpiralFindsPreferredBiomeOrigin`,
      `testFallbackToSpiralWhenNoMatchingBiome`,
      `testIsDeterministicForSameSeedAndState`.

### Что НЕ делаем (границы скоупа)

- НЕ переписываем `TerrainAffinity.weight(...)` — используем готовую функцию
  из TASK-033.
- НЕ меняем формат `events.jsonl` — placement не пишется в лог отдельным
  событием (он восстанавливается из replay).
- НЕ изменяем UI Settings — это TASK-030a.
- НЕ оркестрируем reinit — это TASK-030b.
- НЕ «передвигаем» уже размещённые кварталы между биомами при изменении состава
  юнитов (это разовое решение при создании проекта или при reinit).

### Edge cases

- [ ] Проект с unitIds.count == 0 (новый, нет юнитов) → fallback на спираль.
      Корректно для new-project ветки до первого юнита.
- [ ] Карта целиком одного биома (sea) → preferredBiomes filter всегда пуст
      → fallback на спираль. Не должно крашить.
- [ ] Два проекта хотят river-биом, но river-tiles мало → второй упадёт в
      fallback и поедет на спираль. Корректно (детерминизм сохранён).
- [ ] `biomeReader == nil` (карта ещё не загружена) → DistrictPlanner
      игнорирует `preferredBiomes`, fallback на спираль. Не падать.
- [ ] Юнит-каталог пополнился новым типом без записи в `TerrainAffinity` →
      `weight` для него возвращает дефолт 1.0 (нейтральный). Не нарушает
      алгоритм.

### Зависимости

- **Blocked-by:** TASK-030b (reinit pipeline) + TASK-033 (TerrainAffinity.weight, уже есть).
- **Soft-blocks:** —

### Дизайн

Не применимо (нет UI — pure-helper + planner extension).

### Done-критерий

_Из Concept.md F-15:_ «Новый квартал рядом с рекой получает водные/речные
юниты с заметно большей вероятностью, чем равномерная.»
**Закрывает D-15 целиком** после TASK-030a + 030b.

---

## 🛠 Технический разбор от тимлида

_Статус: [ ] нужен разбор_

> Заполняется командой `/lead 030c`.

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_ (определит лид)
_Объём: M_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Smoke: создать рыболовный проект (≥3 fishingPier/port) → reinit →
      origin рядом с river/sea на новой карте. Создать горный → origin
      рядом с mountain/stone.

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Все новые тесты pass
- [ ] Replay детерминирован при одинаковом seed
- [ ] events.jsonl формат не меняется

#### Обновление документации
- [ ] `Current.md`: F-15 ⚠️ → ✅ (D-15 закрыт)
- [ ] `Diff.md`: D-15 удалить (перенести в «Закрытые»)
- [ ] `.sync-state.yaml`: F-15 → ✅

---

## Статус

`[x] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[ ] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-24
- Spec-review: derived-from-split (TASK-030 lead-analysis 2026-05-23)
- Blocked-by: TASK-030b
- Готова к работе: —
- Завершена: —
- Коммит: —
