# TASK-050: Era progression — долгоиграющая эволюция после stage 5 (monumental эпоха)

## Связь
- **F-25** из Concept.md (шаблоны кварталов + эпохи)
- **D-25** из Diff.md (часть 4/5 — эпохи)
- **F-09** (decay — era reset на decay-4 руины)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-24_

### Что хотим

Главное требование Ильи: «писать проекты годами, и город не только
разрастается, но и улучшается (эволюционирует)». Stage 1→5 — это «грубая»
эволюция за недели/месяцы. После stage 5 нужна **долгоиграющая
награда** — `eraLevel` 0..3, который растёт по двум осям:
**количество задач** и **возраст проекта**. Каждая эпоха подменяет
шаблон на `<base>-monumental.json` / `<base>-legacy.json` с
**уникальными monumental-зданиями** (пирамида, цитадель, акрополь),
которые **недоступны** на низких эпохах.

### Пользовательский сценарий

1. Пользователь ведёт проект 2 года, закрывает 600+ задач. Квартал давно
   на stage 5.
2. На 100-й задаче после stage 5 + 30 дней age — `eraLevel 0 → 1`. Шаблон
   `stage5-akhetaten-ceremonial` подменяется на
   `stage5-akhetaten-monumental` (расширенная версия с обелиск-комплексом
   и палаццо 4×4). Существующие юниты остаются, добавляются monumental-слоты.
3. На 500-й задаче + 180 дней — `eraLevel 1 → 2`. Появляется уникальный
   landmark проекта: пирамида (egyptian) / акрополь (greek) / цитадель
   (roman) — `monumental` SlotRole, footprint 4×4.
4. На 2000-й задаче + 365 дней — `eraLevel 2 → 3`. Появляется
   library/observatory/smelting district — финальная эпоха «древнего
   города культуры».
5. Каждый era-up → событие в журнале + лёгкая визуальная анимация
   («золотое сияние» 2 сек).

### Acceptance criteria

- [ ] `ProjectState.eraLevel: Int` (default 0). Codable backwards-compat
      (старые snapshot загружаются с eraLevel = 0).
- [ ] Новый `EraRules` (pure-функция):
      `func computeEra(taskCount: Int, stage: Int, ageDays: Int) -> Int`
      возвращает:
      - 0 если stage < 5
      - 1 если stage == 5 && taskCount ≥ 100 && ageDays ≥ 30
      - 2 если stage == 5 && taskCount ≥ 500 && ageDays ≥ 180
      - 3 если stage == 5 && taskCount ≥ 2000 && ageDays ≥ 365
- [ ] В `CityEngine.applyTaskCompleted` после увеличения taskCount
      вызывается `applyEraProgression(project:)`:
      - newEra = EraRules.computeEra(...)
      - если newEra > project.eraLevel:
        - emit `GameEvent.Kind.eraAdvanced(projectId, era: newEra)`
        - подменить шаблон на `<currentBase>-monumental.json` (era 1)
          или `<currentBase>-legacy.json` (era 2-3) через те же правила
          migration из TASK-049.
        - project.eraLevel = newEra
- [ ] В `Resources/DistrictTemplates/egyptian/` добавляются 3 era-шаблона:
      - `stage5-akhetaten-monumental.json` — расширение Akhetaten
        ceremonial: добавлен обелиск-комплекс + палаццо 4×4.
      - `stage5-akhetaten-legacy.json` — финал: + библиотека + ритуальный
        бассейн + священная роща.
      - `stage5-akhetaten-pyramid.json` — era 2 landmark (отдельный
        slot.role = .monumental в основном шаблоне). Может быть один и тот
        же шаблон с разной видимостью monumental-слотов по eraLevel.
- [ ] Новые SlotRole: уже есть `.monumental` (из TASK-047) — используем для
      пирамиды/цитадели/акрополя. Размер footprint = 3×3 или 4×4.
- [ ] В `DistrictTemplate` добавляется поле `minEra: Int` для каждого
      слота (default 0). UnitPlanner пропускает слоты, у которых
      `slot.minEra > project.eraLevel` — это и есть «недоступные»
      monumental-слоты.
- [ ] `GameEvent.Kind.eraAdvanced(projectId: String, era: Int)` — новый
      case, записывается в events.jsonl, replay-safe.
- [ ] `GameScene.handleEraAdvanced` — лёгкая анимация (золотая вспышка
      по контуру квартала, 2 сек).
- [ ] Тесты `EraRulesTests.swift`:
      `testComputeEraReturnsZeroBelowStage5`,
      `testComputeEraReachesOneAt100TasksAnd30Days`,
      `testComputeEraReachesTwoAt500TasksAnd180Days`,
      `testComputeEraReachesThreeAt2000TasksAnd365Days`.
- [ ] Тесты `CityEngineEraProgressionTests.swift`:
      `testEraAdvancesOnTaskCompleted`,
      `testEraTemplateMigrationKeepsUnitPositions`,
      `testEraIsReplayable`.

### Что НЕ делаем (границы скоупа)

- НЕ делаем era reset для guess-проектов (вернувшихся из руин) — пока
  era сохраняется при decay/restore.
- НЕ делаем Settings UI для era (это TASK-051 включит).
- НЕ делаем Roman/Greek monumental — это backlog follow-up.
- НЕ балансируем точные числа (100/500/2000 задач). Можно подкрутить
  после первого реального прогона.

### Edge cases

- [ ] Проект на stage 5 с 2000+ задач и 365+ дней (имеющийся
      «старый» проект Ильи на момент мерджа) → при первом
      task_completed после релиза скачком получает era 3 (eraLevel = 3),
      все 3 шаблона подменяются за один тик. Это **OK** (одноразовая
      миграция legacy).
- [ ] Replay events.jsonl до этой TASK (без `eraAdvanced` events) → все
      проекты получают era 0 при load, затем при следующем task_completed
      пересчитываются. Backwards-compat.
- [ ] ageDays считается от `project.createdAt` до now (или до
      `lastActivityAt`? — uniform: используем `lastActivityAt - createdAt`
      чтобы заброшенные проекты не «дозревали» в эпохах).
- [ ] decay-4 проект → era progression skipped (нет смысла улучшать руины).
- [ ] `EraRules.computeEra` чистая функция → тестируется без I/O.

### Зависимости

- **Blocked-by:** TASK-047 (catalog), TASK-048 (templateName),
  TASK-049 (migration mechanism).
- **Soft-blocks:** TASK-051 (Settings UI может показывать current era проекта).

### Дизайн

Не применимо (нет UI; визуал — золотая вспышка по контуру квартала на
era-up, можно использовать SKEmitterNode или SKAction.colorize).

### Done-критерий

_Часть F-25 Done-критерия:_ «После stage 5 + 100 задач + 30 дней появляется
уникальное здание (пирамида для egyptian-family), которое не появлялось
раньше. Replay 5000 событий воспроизводит выбор шаблонов и era-up
детерминированно».

---

## 🛠 Технический разбор от тимлида

_Статус: [ ] нужен разбор_

> Заполняется командой `/lead 050`.

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_ (определит лид)
_Объём: M_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Smoke: проект с simulated 100/500/2000 closed tasks + age >30/180/365 дней
      (через events.jsonl fixture) показывает 3 era-ups, на era 2 появляется
      пирамида.

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Тесты не сломаны (включая EraRulesTests новые)
- [ ] Replay events.jsonl с 5000 событиями детерминирован
- [ ] events.jsonl без `eraAdvanced` events backwards-compat

#### Обновление документации
- [ ] `Current.md`: F-25 → ⚠️ (часть 4/5)
- [ ] `Diff.md`: D-25 не закрывать
- [ ] `concept/LogFormat.md`: добавить `eraAdvanced` event

---

## Статус

`[x] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[ ] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-24
- Spec-review: approved
- Blocked-by: TASK-047, TASK-048, TASK-049
- Готова к работе: —
- Завершена: —
- Коммит: —
