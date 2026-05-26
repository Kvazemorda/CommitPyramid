# TASK-059: Защита legacyRingPosition от cross-project overlap

## Связь
- **F-06** из Concept.md (Project-District и автоматическое размещение)
- **F-15** из Concept.md (Биомы и генерация карты)
- **BUG-025** из Bugs.md
- **Приоритет:** P2

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-26_

### Что хотим

Закрыть пробел в защите от overlap'а кварталов, который остался после
TASK-056 (BUG-022): в pre-mainRoad сценарии (первый юнит проекта, когда
магистраль ещё не построена) применяется отдельный fallback-путь
размещения, который не проверяет занятость клеток чужими проектами.
Это узкий edge case (триггерится только когда два проекта создаются почти
одновременно на свежей карте), но семантически он ломает инвариант F-06
«3+ разных проекта → 3+ непересекающихся квартала».

### Пользовательский сценарий

1. Пользователь только что сбросил карту (или запустил приложение впервые)
   — магистрали ещё нет, первые юниты ещё не появились.
2. В `tasks.jsonl` (или через journal) приходят почти одновременно записи
   двух разных проектов: `project: "alpha"` и `project: "beta"`.
3. Игра размещает первые юниты обоих проектов на карте.
4. Оба первых юнита оказываются в разных клетках — между ними чёткое
   разнесение по сетке, как и обещает F-06.
5. На сцене визуально видно два независимых стартовых пятна, без
   накладывающихся друг на друга домов.

### Acceptance criteria

- [ ] **AC1.** Property-инвариант «нет двух юнитов разных проектов в одной
      клетке» (`∀ A, B ∈ state.units, A.decayLevel < 4 ∧ B.decayLevel < 4 →
      A.position ≠ B.position ∨ A.projectId = B.projectId`) выполняется во
      **всех** сценариях размещения, включая pre-mainRoad (когда магистраль
      ещё отсутствует и квартал размещается по fallback-логике вокруг
      origin).
- [ ] **AC2.** При двух новых проектах, созданных подряд на свежей карте без
      магистрали, оба первых юнита оказываются в разных клетках с
      сохранением `minDistrictRadius` (≥8 клеток между origin'ами по
      Чебышёвской метрике, согласовано с TASK-056).
- [ ] **AC3.** Существующая защита mainRoad-сценариев (TASK-056) не
      регрессирует: тесты `DistrictNoOverlapPropertyTests` (ZeroOverlap +
      DeterministicReplay) проходят без изменений.
- [ ] **AC4.** Новый property-тест покрывает pre-mainRoad сценарий: 5
      проектов, по одному закрытию задач в каждом, без появления магистрали
      — 0 overlap клеток между проектами.
- [ ] **AC5.** Replay events с pre-mainRoad сценарием воспроизводит позиции
      первых юнитов идентично.
- [ ] **AC6.** Если на свежей карте все валидные origin'ы вокруг центра
      исчерпаны (теоретический случай, требует > 50 проектов разом без
      магистрали) — fallback должен либо возвращать корректную дальнюю
      позицию, либо логировать предупреждение в `errors.log` без crash.

### Что НЕ делаем (границы скоупа)

- Не меняем логику создания магистрали (mainRoad) и таймингов её появления.
- Не вводим новые поля в `CityState` / `ProjectState`.
- Не трогаем post-mainRoad сценарии (они уже защищены TASK-056).
- Не оптимизируем спираль / radius-параметры — только закрываем дыру.
- Не меняем поведение для одного-единственного проекта (не должно быть
  регрессии «первый юнит города теперь смещён»).

### Edge cases

- [ ] Два проекта создаются в **один тик** (один и тот же `applyTaskCompleted`
      не вызывается параллельно — main-queue serial, но порядок важен:
      второй проект должен видеть первого в state).
- [ ] Pre-mainRoad сценарий совмещён с decay-4 руинами (взаимодействие с
      TASK-058 BUG-024: если decay-4 проекта на свежей карте теоретически
      нет, но если есть — приоритет за `pickRuinForNewProject`).
- [ ] Pre-mainRoad сценарий на водном биоме (взаимодействие с BUG-009: за
      пределами скоупа этой задачи, но не должен регрессировать).
- [ ] Очень близко расположенные origin'ы из-за тесного спирального шага
      (защита через `minDistrictRadius=8`, уже введена TASK-056).

### Зависимости

- TASK-056 (BUG-022) — задаёт паттерн передачи `otherProjectsClaims` /
  `otherProjectCells` через параметры; lead должен расширить эту же модель
  на fallback-путь.
- TASK-058 (BUG-024) — если идёт раньше, refactor `claimedCellsByProjects`
  затронет и этот путь; lead должен учесть совместимость (одна и та же
  claim-карта должна работать в обоих сценариях).

### Дизайн

Не применимо (engine-level edge case без UI).

### Done-критерий

_Из Concept.md F-06:_ «3+ разных проекта в `tasks.jsonl` → 3+ непересекающихся
квартала. При появлении нового проекта на карте с зоной руин — он занимает
руины с анимацией расчистки длительностью 3-5 сек. Без руин — занимает свежий
луг.»

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-26_
_Модель: sonnet_
_Статус: [x] готов_

### Анализ текущего состояния

- `UnitPlanner.legacyRingPosition` (`Sources/CityDeveloper/Game/UnitPlanner.swift:478`)
  — pure-формула: 8 offsets × 3 rings = 24 позиции вокруг origin. Сейчас НЕ
  принимает `otherProjectCells` и `builtCells`.
- Вызывается из `nextPosition` дважды: строка 348 (когда `roadCells.isEmpty` —
  pre-mainRoad сценарий первого юнита) и строка 363 (когда `nearby` пуст после
  фильтра halfSide=4 — теоретически возможен на стыке кварталов).
- `CityEngine` уже собирает `otherSet` в legacy path (CityEngine.swift:743-756) и
  передаёт его в `nextPosition(otherProjectCells: otherSet)` (line 764). Канал
  работает — утечка только внутри `legacyRingPosition`.
- `footprintBlocked` (`UnitPlanner.swift:461`) уже принимает
  `otherProjectCells: Set<GridPoint>` и проверяет пересечение footprint'а с
  чужими клетками — переиспользуем.
- Комментарий `UnitPlanner.swift:343-346` утверждает «otherProjectCells также
  пуст» — это ложное оправдание, источник BUG-025.
- Существующие тесты: `Tests/CityDeveloperTests/DistrictNoOverlapPropertyTests.swift`
  (паттерн для нового property-теста), `UnitPlannerTests.swift`,
  `UnitPlannerSlotPlacementTests.swift` — не должны регрессировать.

### Архитектурное решение

Расширить сигнатуру `legacyRingPosition` опциональными параметрами `builtCells`
и `otherProjectCells` (default = `[]` для back-compat). Внутри — пройтись по
тем же 24 позициям в строгом порядке, начиная с индекса `i`; для каждой
проверить `footprintBlocked(roads: [], built: builtCells, otherProjectCells: …)`
и вернуть первую свободную. Если все 24 блокированы — записать warning в
`ErrorsLog` и вернуть позицию по исходной формуле (defensive — не падать). Это
сохраняет детерминизм (тот же порядок offsets), вводит skip-логику и
переиспользует существующий helper.

### Пошаговая декомпозиция

1. **Расширить сигнатуру `legacyRingPosition` + skip-логика** `[AC:1,6]`
   - Файл: `Sources/CityDeveloper/Game/UnitPlanner.swift:478`
   - Что: добавить `builtCells: Set<GridPoint> = []`, `otherProjectCells:
     Set<GridPoint> = []`. Внутри — `for j in 0..<24`: вычислить
     `(ring, slot)` от `i+j`, получить `pos`, проверить
     `footprintBlocked(at: pos, size: unitSize, roads: [], built: builtCells,
     otherProjectCells: otherProjectCells)`. Первая non-blocked → return. После
     цикла — `ErrorsLog.write("UnitPlanner.legacyRingPosition: all 24 ring
     positions blocked at origin=\(origin), i=\(i)")` + defensive return позиции
     по исходной формуле (`i`-й offset).

2. **Прокинуть параметры в оба call site** `[AC:1,2]`
   - Файл: `Sources/CityDeveloper/Game/UnitPlanner.swift:348` и `:363`
   - Что: дописать `builtCells: builtCells, otherProjectCells: otherProjectCells`
     к обоим вызовам `legacyRingPosition(...)` в `nextPosition`.

3. **Обновить устаревший комментарий** `[AC:1]`
   - Файл: `Sources/CityDeveloper/Game/UnitPlanner.swift:343-346`
   - Что: заменить блок `// TASK-056: legacyRingPosition не учитывает
     otherProjectCells...` на короткий `// Fallback на легаси-кольцо (TASK-059
     учитывает builtCells + otherProjectCells)`.

4. **Property-тест pre-mainRoad сценария** `[AC:2,4,5]`
   - Новый файл: `Tests/CityDeveloperTests/UnitPlannerLegacyRingOverlapTests.swift`
   - Стиль — взять из `DistrictNoOverlapPropertyTests.swift` (CityEngine-level
     ingest + property-инвариант). Два теста:
     - `test_PreMainRoadScenario_NoOverlapBetweenProjects` — на чистом CityEngine
       сделать ingest 5 проектов × 1 task каждый (только первая task → road
       через consumeNextPlanCell ИЛИ если templateName==nil legacy путь).
       Для воспроизведения именно pre-mainRoad legacy сценария можно вызвать
       `unitPlanner.nextPosition(origin: …, roadCells: [], otherProjectCells:
       accumulated)` напрямую — unit-level. Проверить: возвращённые позиции
       (с учётом unitSize=2×2 как worst case) не пересекаются между собой.
     - `test_PreMainRoadScenario_DeterministicReplay` — два прогона с теми же
       seed'ом дают идентичный результат.

5. **Регресс существующих тестов** `[AC:3]`
   - Запустить `swift test --filter DistrictNoOverlap` и
     `swift test --filter UnitPlanner` — должны проходить без изменений.

### Edge cases (явно обработать)

- [ ] Pre-mainRoad одиночный проект: `otherProjectCells=[]` (default) →
      поведение идентичное текущему (первая non-blocked позиция = первый
      offset i, как раньше). См. `UnitPlanner.swift:478` updated body.
- [ ] Большой footprint (2×2..4×4): `footprintBlocked` корректно учитывает все
      клетки footprint'а (`UnitPlanner.swift:466-473`) — переиспользуем.
- [ ] Все 24 позиции блокированы (теоретический: >50 проектов разом, очень
      плотно): `ErrorsLog.write` + defensive return — не crash. Реалистично
      blocked редко, но защита обязательна.
- [ ] Взаимодействие с TASK-058 (BUG-024 decay-4): `otherProjectCells`
      приходит из CityEngine; после TASK-058 эта карта будет фильтрована по
      `decayLevel < 4` — refactor совместим, контракт `Set<GridPoint>` не
      меняется.

### Файлы для изменения

- `Sources/CityDeveloper/Game/UnitPlanner.swift` — сигнатура + тело
  `legacyRingPosition` + 2 call site + комментарий (≤30 строк правок).
- `Tests/CityDeveloperTests/UnitPlannerLegacyRingOverlapTests.swift` —
  новый property-тест (≤120 строк).

### Файлы НЕ трогать

- `Sources/CityDeveloper/Game/CityEngine.swift` — call site уже передаёт
  `otherProjectCells` через `nextPosition` (line 757-765); фикс внутри
  `legacyRingPosition` не требует изменений вызывающего.
- `Sources/CityDeveloper/Game/DistrictPlanner.swift` — `claimedCellsByProjects`
  и origin allocation не в скоупе.
- `Sources/CityDeveloper/Data/ErrorsLog.swift` — используем существующий API.

### Команды проверки

- Компиляция: `swift build`
- Новые тесты: `swift test --filter UnitPlannerLegacyRingOverlapTests`
- Регресс: `swift test --filter DistrictNoOverlap`, `swift test --filter UnitPlanner`
- Полный suite: `swift test`

### Сложность

`middle`

**Обоснование:** 2 файла, точечное расширение signature с back-compat
default'ами + property-тест на детерминированной фикстуре; нет архитектурных
решений, переиспользуется существующий `footprintBlocked` helper.

### Ожидаемое время

S (≤2ч)

---

## ✅ Исполнение

_Исполнитель: sonnet (agent)_
_Дата: 2026-05-26_
_Сложность: S_ (как оценил лид)

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Done-критерий проверен в реальном использовании (или property-тест
      pre-mainRoad scenario, если manual UI test недоступен в CI)

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Тесты не сломаны (`DistrictNoOverlapPropertyTests` × 2 проходят)
- [ ] Добавлен property-тест pre-mainRoad scenario

#### Обновление документации
- [x] `Current.md`: F-06 запись упоминает закрытие edge case
- [x] `Bugs.md`: BUG-025 закрыт со ссылкой на коммит
- [x] Новые идеи → `Backlog.md`, новые баги → `Bugs.md` (followup: уточнить комментарий о «24 позиции» → реально 16 уникальных)

---

## Статус

`[x] done`

## Метаданные
- Создана PM: 2026-05-26
- Spec-review: approved (from-sync auto: PM-блок полный, все обязательные секции присутствуют)
- Lead-model: sonnet
- Plan-review: approved (Opus, 1 круг)
- Готова к работе: 2026-05-26
- Исполнитель: sonnet (middle)
- Verify: pass (176/176, AC1-5 auto, AC6 defensive в коде)
- Code-review: approved (sonnet, без блокеров)
- Завершена: 2026-05-26
- Коммит: —
