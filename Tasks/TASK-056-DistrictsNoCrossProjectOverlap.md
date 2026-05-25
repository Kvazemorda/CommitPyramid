# TASK-056: Кварталы разных проектов не пересекаются — DistrictPlanner защита от cross-project overlap

## Связь
- **F-06** из Concept.md (Модель Project-District и автоматическое размещение)
- **BUG-022** из Bugs.md (P0)
- **Приоритет:** P0

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-25_

### Что хотим

Фундаментальная регрессия F-06 («District-per-project»): на реальной сцене с
4 проектами по ~20 задач в `state.json` обнаружены **7 клеток, где сидят юниты
разных проектов одновременно** (15 юнитов в конфликтных позициях; например
`(123,129)`: warehouse Pyramid + warehouse finefit). Визуально это и есть жалоба
пользователя «здания друг на друга наезжают, всё скомкано» — кварталы прорастают
друг в друга на уровне `state.units`, а не рендера.

Done-критерий F-06 («3+ разных проекта → 3+ непересекающихся квартала») сейчас
**не выполняется**. Это P0, потому что ломает базовую семантику игры: каждый
рабочий проект должен иметь свою территорию, иначе теряется визуальный смысл
города как карты проектов пользователя.

Минимальный фикс: `DistrictPlanner.allocateNextOrigin` при выделении origin для
нового проекта должен учитывать клетки, уже занятые другими districts, и
гарантировать минимальный зазор между territory'ями. При росте квартала
(`extendDistrictPlan`) — не лезть в чужой claim. Конкретный механизм
(увеличить spacing спирали, ввести реестр claimed cells, комбинация) — выбор
лида; PM фиксирует только инвариант «никакая клетка `state.units` не содержит
двух юнитов с разным `projectId`».

### Пользовательский сценарий

1. Пользователь запускает свежий город (reset state) и подключает 4 источника
   (например, 4 git-репо или 4 markdown-папки с разными `project`).
2. Watcher'ы импортируют коммиты/задачи из всех 4 источников; каждый источник
   даёт свой `projectId`.
3. По мере накопления задач каждый из 4 проектов растёт до stage 3+ (≥20 юнитов
   в квартале).
4. На карте визуально видны 4 раздельных квартала, между ними — пустые клетки
   луга/биома (видимый зазор хотя бы 2-3 клетки).
5. Клик на любой юнит даёт plашку с именем «его» проекта — никаких ситуаций
   «здание Pyramid стоит внутри квартала finefit».
6. Если запустить `jq '[.cityState.units | to_entries | .[].value | {x:.position.x, y:.position.y, pid:.projectId}] | group_by("\(.x),\(.y)") | map(select(length > 1 and ([.[].pid] | unique | length) > 1))'` на `state.json` → результат `[]` (нет клеток с юнитами разных проектов).

### Acceptance criteria

- [ ] **Инвариант данных:** для любых двух юнитов A, B в `state.cityState.units`
      → `A.position != B.position` ИЛИ `A.projectId == B.projectId`. Никакая
      клетка не содержит юнитов из разных проектов. Проверка через `jq`-команду
      выше → `[]`.
- [ ] **Origin allocation:** `DistrictPlanner.allocateNextOrigin` при выделении
      origin для нового projectId возвращает такую `GridPoint`, что
      `bbox(district) ∩ bbox(other_districts) == ∅` для всех уже существующих
      districts (с учётом ожидаемого роста квартала — лид определит формулу
      радиуса).
- [ ] **District growth:** при росте квартала (например через `extendDistrictPlan`
      или вызов из `UnitPlanner.nextPosition`) новая клетка под здание/дорогу
      НЕ выбирается, если она принадлежит другому проекту (`engine.state.units`
      содержит юнит с другим `projectId` в этой клетке) — поиск продолжается
      дальше.
- [ ] **Свежий smoke:** свежий город (reset state) + 4 проекта × ≥20 задач каждый
      даёт 0 overlap в state.json. Команда `swift run CommitPyramid` с
      `add-task.sh` × 20 для каждого из 4 проектов — визуально 4 раздельных
      квартала с зазором ≥2 клетки между bbox'ами.
- [ ] **Property-тест:** добавить тест в `Tests/CityDeveloperTests/` (или в
      существующий `DistrictPlannerTests` если есть), который генерит 5 проектов
      по 30 задач через детерминированный seed и проверяет инвариант (никаких
      клеток с разными projectId). Тест должен ловить регрессию — если
      специально вернуть текущий spacing=14, тест падает.
- [ ] **Существующие тесты:** все текущие тесты (165 pass + 1 skip baseline)
      проходят без изменений.
- [ ] **Replay determinism:** при том же seed карты + той же
      последовательности `tasks.jsonl` events → тот же набор origin'ов и тот же
      набор позиций юнитов. Не нарушать F-03 (event sourcing replay).
- [ ] **Closes:** BUG-022 переезжает в «Закрытые» с указанием коммита.
      F-06 в Current.md остаётся ✅ (статус формально не меняется — фича есть,
      просто инвариант починен).

### Что НЕ делаем (границы скоупа)

- НЕ меняем алгоритм роста внутри одного квартала (BUG-017/018 close уже сделан
  — `UnitPlanner.nextPosition` работает корректно, только добавляется фильтр
  «не лезть в чужой claim»).
- НЕ переписываем спираль `DistrictPlanner.spiralPoint(index:)` целиком —
  можно скорректировать spacing или добавить пост-фильтр; полный реверс к
  другой топологии (например, grid 8×8) — не в этой задаче.
- НЕ трогаем приоритет руин (F-06 пункт 1: «новый проект занимает наиболее
  старую/большую зону руин с анимацией расчистки»). Если зона руин уже
  принадлежала старому проекту — это вообще другой случай (re-occupation),
  не cross-project overlap.
- НЕ делаем миграцию существующего `state.json` пользователя (там 7 overlap
  cells) — детерминизм replay сохраняется только при reset. Юзер сам решит,
  делать reset или жить со старым state до следующего естественного reset.
- НЕ добавляем UI визуализации claimed cells (debug overlay) — это отдельная
  идея для backlog.
- НЕ балансируем эстетику расстояний между кварталами (визуально приятный
  layout) — только корректность.

### Edge cases

- [ ] **Карта переполнена.** Если все клетки доступного биома уже принадлежат
      существующим districts (теоретически — на маленькой карте при 100+
      проектов) → `allocateNextOrigin` должен либо вернуть «нет места»
      (lead-решение: throw / return nil / extend map) либо использовать
      допустимый overlap с предупреждением. PM-дефолт: на 256×256 карте при
      ожидаемых 10-20 проектах это не возникает; lead выбирает поведение для
      теоретического случая.
- [ ] **Replay legacy state.** Существующие `events.jsonl` с overlap (как у
      текущего пользователя — 7 conflicting cells) при replay через новый
      алгоритм могут дать другие origin'ы. Это допустимое расхождение для
      P0-фикса (PM решение). В `Bugs.md` BUG-022 closure-записи указать, что
      для существующих state — рекомендуется reset.
- [ ] **Race condition при ingest.** Если два разных source (git + notes) одной
      transaction'ой создают юниты двух новых проектов — оба должны получить
      непересекающиеся origin'ы. `allocateNextOrigin` вызывается
      последовательно (single-threaded engine), поэтому race нет, но проверь
      что `currentIndex` правильно увеличивается между вызовами.
- [ ] **Single project.** При 1 проекте инвариант тривиально выполняется
      (нет других districts). Тест должен включать кейс «1 проект → 50 задач —
      не падает».
- [ ] **Удалённый/архивный проект.** Если проект «умер» (все юниты в decay-4
      ruins) — новый проект может занять его территорию (правило F-06 п.1).
      Это НЕ cross-project overlap — это reoccupation. Лид решает, нужно ли
      убирать старый projectId из claim-реестра при достижении decay-4 / при
      cleanup ruins.
- [ ] **Биом-filter conflict.** `allocateNextOrigin` уже умеет пропускать
      water-биомы (BUG-009) и preferredBiomes (TASK-030c). Новый фильтр
      «не overlap с другими districts» добавляется поверх — порядок lead
      определит. Все три фильтра должны совмещаться без deadlock'а.

### Зависимости

- **Blocked-by:** —
- **Soft-blocks:** —
- Внешние сервисы: —
- Миграции: state.json пользователя не мигрируется — детерминизм replay
  меняется, рекомендация reset (см. Edge case 2).
- Связанные баги: **BUG-009** (water-skip) и **TASK-030c** (preferredBiomes
  filter) — уже в коде, новый фильтр overlap добавляется в тот же
  `allocateNextOrigin`. **BUG-008** (биомное распределение) — независим,
  не блокер. **BUG-005** (Reset UI) — упрощает рекомендованный workflow, но
  не блокирующая зависимость.

### Дизайн

Не применимо (логика game state, не UI). Визуальное последствие — кварталы
видны раздельно, без overlap; layout эстетика — не в скоупе.

### Done-критерий

_Из Concept.md F-06:_ «3+ разных проекта в `tasks.jsonl` → 3+ непересекающихся
квартала. При появлении нового проекта на карте с зоной руин — он занимает руины
с анимацией расчистки длительностью 3-5 сек. Без руин — занимает свежий луг.»

PM-уточнение: текущий код выполняет «свежий луг» через спираль, но **не
обеспечивает «непересекающиеся» инвариант** для растущих кварталов. Задача
закрывает именно этот gap. Анимация расчистки руин и приоритет руин — не
затрагиваются.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-25_
_Модель: opus (P0-trigger + архитектурный — новый алгоритм cross-project защиты)_
_Статус: [x] готов_

### Анализ текущего состояния

**Где сейчас баг (две точки разрыва инварианта):**

1. **`DistrictPlanner.allocateNextOrigin` (`Sources/CityDeveloper/Game/DistrictPlanner.swift:50-93`)** —
   при выделении origin для нового проекта учитывает только water-skip (BUG-009) и
   preferredBiomes (TASK-030c). **Не проверяет, не занята ли клетка/окрестность
   юнитами других проектов.** Spacing спирали = 14 (`:34`) — этого мало для квартала,
   разрастающегося до радиуса 10-15 клеток с footprint'ами 2×2.

2. **`UnitPlanner.nextPosition` (`Sources/CityDeveloper/Game/UnitPlanner.swift:284-405`)** —
   при поиске позиции для нового юнита проверяет `builtCells` (через
   `footprintBlocked`, `:450-461`). Но `builtCells` собирается в
   `CityEngine.applyTaskCompleted:425-439` (template path) и `:697-710` (legacy path)
   с фильтром `.filter { $0.projectId == projectKey }` — **только клетки текущего
   проекта**. Юнит другого проекта в той же клетке не виден как blocker.

**Единственная точка вызова `allocateNextOrigin`/`allocateAlongMagistrale`:**
- `CityEngine.applyTaskCompleted:318-339` (для нового проекта, isNewProject ветка).
- `state.nextDistrictIndex` (CityState:511-524) — глобальный счётчик спирали,
  инкрементируется на `allocated.newIndex + 1` (`:338`). Используется для replay-детерминизма.

**Существующие тесты:**
- `Tests/CityDeveloperTests/DistrictPlannerBiomeAwareTests.swift` — 6 кейсов (water-skip,
  preferred-biome, fallback). Использует `MockBiomeReader` (`:12-29`).
  **Property-теста на overlap нет.**
- `Tests/CityDeveloperTests/CityEngineTests.swift` — 4 интеграционных кейса (replay
  determinism уже покрыт `testReplayEquivalence:59-91`). Можно расширить для multi-project.

**CityState (`Sources/CityDeveloper/Data/CityState.swift`):**
- `UnitState` (`:4-15`) имеет `projectId`, `position`, `kind` (с `size: GridSize`).
- `ProjectState` (`:440-509`) имеет `districtOrigin`, `unitIds`, `templateName`,
  `eraLevel` — **нет** явного `districtCells`/`claimedCells`.
- `CityState` (`:511-524`) — нет глобального claim-registry.

**Что переиспользуем:**
- `GridPoint`, `GridSize` (`CityState.swift`) — без изменений.
- Spiral формула `spiralPoint(index:)` (`DistrictPlanner:14-38`) — без изменений
  (детерминированная база, фильтр overlap добавляется поверх).
- `footprintBlocked` (`UnitPlanner:450-461`) — расширяем сигнатурой
  `otherProjectCells: Set<GridPoint>`.
- `MockBiomeReader` из существующих тестов — для нового property-теста.

**Что нужно дописать:**
- Helper для сбора `claimedCells` всех проектов (по `projectId`).
- Расширение `allocateNextOrigin` параметром `existingClaims: [String: Set<GridPoint>]`
  + `minDistrictRadius: Int = 8`. Логика: при поиске origin пропускать спираль-индексы,
  где в Чебышёвской `radius = minDistrictRadius` окрестности уже есть клетки **другого**
  проекта (`existingClaims` без учёта текущего projectKey).
- Расширение `UnitPlanner.nextPosition` параметром `otherProjectCells: Set<GridPoint>`
  + проброс в `footprintBlocked` (или новая `footprintBlockedExtended`).
- Property-тест: 5 проектов × 30 задач через `CityEngine` (а не unit DistrictPlanner —
  нужна интеграция allocate + nextPosition), проверка инварианта overlap == 0.
- Перенос BUG-022 в Bugs.md «Закрытые». F-06 в Current.md остаётся ✅ (статус не
  меняется), детали обновить упоминанием cross-project защиты.

### Архитектурное решение

**Подход: computed claim-map + расширение API двух методов, БЕЗ нового поля в CityState.**

Альтернативы рассмотрены:
- (A) **Новое поле `claimedCells: Set<GridPoint>` в ProjectState** — отвергнуто:
  требует миграции CityState.version (нарушает F-12 snapshot формат), увеличивает
  риск рассинхрона (нужно синхронизировать с unit ops).
- (B) **Bump spacing спирали с 14 до 24-30** — отвергнуто как самостоятельное решение:
  не закрывает корень (без претензии на конкретную клетку всё равно возможен overlap
  при росте). Применяется как complement: новый `minDistrictRadius=8` параллельно даёт
  эффективный зазор ~16, что **больше** текущего spacing, поэтому достаточно.
- (C) **Computed claim-map на лету** — выбрано: O(N) на каждый allocate
  (N=units count ≈ 100 на тестовой сцене), пыль; не требует миграции формата;
  замкнутая правка в trio (DistrictPlanner, UnitPlanner, CityEngine).

**Ключевая инвариантная защита:**

```
Для любого нового origin O нового проекта P:
  ∀ projectId ≠ P, ∀ cell ∈ existingClaims[projectId]:
    chebyshev_distance(O, cell) >= minDistrictRadius

Для любой новой клетки C под юнит проекта P:
  ∀ unit ∈ state.units, unit.projectId ≠ P:
    C ∉ footprintCells(unit)
```

Chebyshev distance (`max(|dx|, |dy|)`) выбрана вместо Euclidean — соответствует
квадратной природе спирали и footprint'ов. `minDistrictRadius = 8` даёт зазор
≥ 8 клеток от чужих юнитов; при росте квартала до радиуса 10+ это значит, что
свои юниты могут подойти к чужому ближе чем на 8, но защита в `nextPosition`
не даст overlap.

**Replay determinism:**
- `state.nextDistrictIndex` инкрементируется по новой формуле (skip больше клеток)
  — но **детерминированно**: один и тот же state → один и тот же набор skipped
  indices → один и тот же финальный origin.
- Edge case существующего state.json: при full replay через новый алгоритм первые
  N проектов получат origins, какие выберет новый алгоритм (не как в old events).
  Это **допустимое расхождение** для P0-фикса (PM явно зафиксировал в edge case
  «Replay legacy state»).

**Порядок шагов:** сначала helpers и тесты-skeleton (без логики), затем allocate,
затем nextPosition, затем интеграция в CityEngine, затем property-test, затем
docs. Каждый промежуточный коммит компилируется (но не обязательно проходит новые
тесты до их написания).

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку. Шаг непонятен — НЕ импровизируй,
> возвращай задачу через сообщение.

1. **Helper: собрать claimedCells всех проектов** `[AC:1,3]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`
   - Место: добавить **private static func** в extension в конце файла (после
     последнего method `}`):
     ```swift
     extension CityEngine {
         /// TASK-056 BUG-022: собирает footprint-клетки всех юнитов по projectId.
         /// Возвращает [projectId: Set<GridPoint>] для использования в
         /// DistrictPlanner.allocateNextOrigin и UnitPlanner.nextPosition.
         /// O(N) по числу юнитов; вызывается раз на applyTaskCompleted.
         static func claimedCellsByProjects(
             in state: CityState
         ) -> [String: Set<GridPoint>] {
             var result: [String: Set<GridPoint>] = [:]
             for unit in state.units.values {
                 let size = unit.kind.size
                 var cells = result[unit.projectId, default: []]
                 for dx in 0..<size.width {
                     for dy in 0..<size.height {
                         cells.insert(GridPoint(
                             x: unit.position.x + dx,
                             y: unit.position.y + dy))
                     }
                 }
                 result[unit.projectId] = cells
             }
             return result
         }
     }
     ```
   - Проверка: `swift build -c debug` — pass (никаких вызовов ещё нет).

2. **Расширить DistrictPlanner.allocateNextOrigin сигнатурой** `[AC:2,7]`
   - Файл: `Sources/CityDeveloper/Game/DistrictPlanner.swift:50-93`
   - Добавить два **необязательных** параметра в конец сигнатуры (back-compat
     с DistrictPlannerBiomeAwareTests где они не передаются):
     ```swift
     func allocateNextOrigin(
         currentIndex: Int,
         biomeReader: BiomeMapReader?,
         preferredBiomes: [BiomeKind] = [],
         otherProjectsClaims: Set<GridPoint> = [],
         minDistrictRadius: Int = 8
     ) -> (origin: GridPoint, newIndex: Int)
     ```
   - Внутри: после water-skip while loop (`:65-68`) и перед `preferredBiomes` блоком
     (`:74-88`) добавить **новый while loop**, который пропускает origin'ы со
     слишком близкими чужими клетками:
     ```swift
     // TASK-056 BUG-022: пропускаем origin'ы в Чебышёвской окрестности
     // minDistrictRadius от любой клетки другого проекта.
     while idx < maxAttempts {
         let tooClose = otherProjectsClaims.contains { cell in
             max(abs(cell.x - origin.x), abs(cell.y - origin.y)) < minDistrictRadius
         }
         if !tooClose { break }
         idx += 1
         origin = spiralPoint(index: idx)
         // Повторная проверка water-skip после bump'а:
         if reader.biome(atX: origin.x, y: origin.y).isWater { continue }
     }
     ```
   - **Внимание:** проверка чёткой последовательности `water-skip → cross-project-skip
     → preferred-biome scan` — лид выбрал такой порядок, потому что:
     - water — hard-block (никогда не возвращаем water).
     - cross-project — hard-block (никогда не overlap).
     - preferred-biome — soft-preference (fallback на water-skipped + cross-skipped).
   - `preferredBiomes` блок (`:74-88`) — обновить scanLimit чтобы он искал начиная
     с финального `idx` после двух skip'ов, а не от `currentIndex`:
     ```swift
     // TASK-056: scanStart = idx (после water+cross-skip), а не currentIndex.
     // Намеренно: cross-project — hard-block, preferred-biome — soft-preference;
     // preferred-скан не должен возвращаться на индексы, которые уже отвергнуты
     // как water или как лежащие в радиусе чужого квартала.
     let scanStart = idx
     let scanLimit = scanStart + 20
     var scanIdx = scanStart
     ```
     И внутри loop проверять и `isWater`, и `tooClose` для каждого кандидата.
   - **Замечание по back-compat существующих 6 BiomeAware тестов:** они не передают
     `otherProjectsClaims` → дефолт `[]` → cross-skip loop пропускает 0 итераций →
     `idx` после него = `idx` после water-skip → `scanStart` совпадает с
     `currentIndex` для случая meadow-only карты. То есть существующие
     `test_BiomeAwareSpiralFindsPreferredBiomeOrigin` и др. продолжают находить
     mountain-тайл в первых 20 кандидатах от 0. Подтверждение — обязательная
     проверка в шаге 7.

3. **Расширить allocateAlongMagistrale аналогично** `[AC:2,7]`
   - Файл: `Sources/CityDeveloper/Game/DistrictPlanner.swift:105-155`
   - **Это второй allocation path** (используется когда есть mainRoadCells).
   - Добавить те же два параметра `otherProjectsClaims`, `minDistrictRadius` в сигнатуру.
   - Внутри основного цикла поиска origin (где сейчас water-skip) добавить ту же
     проверку `tooClose`. Если кандидат `tooClose` → continue к следующему layer.
   - Структура цикла: при попытке принять кандидат → проверка water, затем
     проверка `tooClose`. Если ни одна не прошла → переход к следующей попытке.

4. **Расширить UnitPlanner.footprintBlocked сигнатурой** `[AC:3]`
   - Файл: `Sources/CityDeveloper/Game/UnitPlanner.swift:450-461`
   - Добавить параметр `otherProjectCells: Set<GridPoint> = []`:
     ```swift
     func footprintBlocked(
         at pos: GridPoint,
         size: GridSize,
         roads: Set<GridPoint>,
         built: Set<GridPoint>,
         otherProjectCells: Set<GridPoint> = []
     ) -> Bool {
         for dx in 0..<size.width {
             for dy in 0..<size.height {
                 let p = GridPoint(x: pos.x + dx, y: pos.y + dy)
                 if roads.contains(p) || built.contains(p) { return true }
                 if otherProjectCells.contains(p) { return true }
             }
         }
         return false
     }
     ```
   - Default `[]` обеспечивает back-compat с тестами, которые не передают.

5. **Расширить UnitPlanner.nextPosition сигнатурой + проброс** `[AC:3]`
   - Файл: `Sources/CityDeveloper/Game/UnitPlanner.swift:284-405`
   - Добавить параметр `otherProjectCells: Set<GridPoint> = []` в конец сигнатуры.
   - **Template path (`:312-334`):** при проверке footprint слота добавить проверку
     `otherProjectCells.contains(cell)`. Если хоть одна клетка footprint'а
     принадлежит другому проекту → слот недоступен, продолжать поиск.
   - **Legacy path (`:336-405`):** при итерации кандидатов вызывать
     `footprintBlocked(at:, size:, roads:, built:, otherProjectCells:)`. Если
     blocked → пропустить кандидат.

6. **Интеграция в CityEngine.applyTaskCompleted** `[AC:1,2,3,4]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`
   - **Перед** вызовом `allocateNextOrigin`/`allocateAlongMagistrale` (около `:318`)
     добавить:
     ```swift
     let allClaims = Self.claimedCellsByProjects(in: state)
     let otherClaims = allClaims
         .filter { $0.key != projectKey }
         .values
         .reduce(into: Set<GridPoint>()) { $0.formUnion($1) }
     ```
     (Note: `projectKey` уже определён в applyTaskCompleted — это `event.project`.)
   - **Передать в оба вызова** `allocateNextOrigin` и `allocateAlongMagistrale`:
     ```swift
     allocated = districtPlanner.allocateNextOrigin(
         currentIndex: state.nextDistrictIndex,
         biomeReader: biomeReader,
         otherProjectsClaims: otherClaims,
         minDistrictRadius: 8
     )
     // (аналогично для allocateAlongMagistrale)
     ```
   - **В местах сборки `builtSet`** (`:425-439` template path и `:697-710` legacy
     path) — после `.filter { $0.projectId == projectKey }` блока добавить ниже
     **`otherSet`**:
     ```swift
     let otherSet = Set(state.units.values
         .filter { $0.projectId != projectKey }
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
     ```
   - **Передать `otherSet` в `unitPlanner.nextPosition`** в template-call (`:442-451`)
     и legacy-call (`:697-718`):
     ```swift
     unitPlanner.nextPosition(
         origin: project.districtOrigin,
         buildingIndex: project.taskCount,
         roadCells: roadCells,
         builtCells: builtSet,
         unitSize: unitKind.size,
         template: template,
         kind: unitKind,
         projectEraLevel: project.eraLevel,
         otherProjectCells: otherSet     // ← новое
     )
     ```

7. **Существующие тесты не должны падать** `[AC:6]`
   - Файл: `Tests/CityDeveloperTests/DistrictPlannerBiomeAwareTests.swift`
   - Все 6 тестов вызывают `allocateNextOrigin` без новых параметров — это работает
     благодаря дефолтам `otherProjectsClaims: Set<GridPoint> = []`,
     `minDistrictRadius: Int = 8`. Проверь: `swift test --filter
     DistrictPlannerBiomeAwareTests` → 6/6 pass.
   - `UnitPlannerTests.swift` — все тесты вызывают `nextPosition` (или его части)
     без `otherProjectCells` → работает через дефолт. Проверь:
     `swift test --filter UnitPlannerTests` → 9/9 pass.
   - `CityEngineTests.swift` — `testReplayEquivalence` критичен (replay должен быть
     детерминирован). Проверь: `swift test --filter CityEngineTests` → 4/4 pass.

8. **Property-тест: 5 проектов × 30 задач, 0 overlap + replay determinism** `[AC:5,7]`
   - Файл: **новый** `Tests/CityDeveloperTests/DistrictNoOverlapPropertyTests.swift`
   - **Точные сигнатуры (verified против Sources):**
     - Модуль: `@testable import CommitPyramid` (название модуля — `CommitPyramid`, не `CityDeveloper`).
     - `EventLog(fileURL: URL)` (`Sources/CityDeveloper/Data/EventLog.swift:9`).
     - `SnapshotStore(url: URL)` (`Sources/CityDeveloper/Data/SnapshotStore.swift:6`).
     - `CityEngine(eventLog: EventLog, snapshotStore: SnapshotStore)` — без
       `biomeReader` в init (`Sources/CityDeveloper/Game/CityEngine.swift:67`).
       `biomeReader` — это `var` свойство (`:44`), выставляется после init
       присваиванием: `engine.biomeReader = mock`.
     - `ingestTaskCompletion(project: String, title: String, taskId: String?, source: String?, ts: Date)`
       (`Sources/CityDeveloper/Game/CityEngine.swift:156`) — все 5 параметров обязательны.
   - **Issue 5 из plan-review:** при `biomeReader == nil` ветка `allocateNextOrigin:55-57`
     возвращает `spiralPoint(currentIndex)` напрямую, без cross-project-skip. То есть
     property-тест с `biomeReader=nil` НЕ проверял бы регрессию (5 проектов
     получили бы overlap, как сейчас). Решение: использовать `MockBiomeReader`
     с `defaultBiome=.meadow` (скопировать определение из
     `Tests/CityDeveloperTests/DistrictPlannerBiomeAwareTests.swift:12-29`),
     чтобы cross-project-skip применялся и тест реально ловил регрессию.
   - Структура:
     ```swift
     import XCTest
     @testable import CommitPyramid

     final class DistrictNoOverlapPropertyTests: XCTestCase {

         // MARK: - Mock (skoпировано из DistrictPlannerBiomeAwareTests)
         private final class MockBiomeReader: BiomeMapReader {
             let biomes: [GridPoint: BiomeKind]
             let defaultBiome: BiomeKind
             let width: Int
             let height: Int
             init(biomes: [GridPoint: BiomeKind] = [:],
                  defaultBiome: BiomeKind = .meadow,
                  width: Int = 256, height: Int = 256) {
                 self.biomes = biomes
                 self.defaultBiome = defaultBiome
                 self.width = width
                 self.height = height
             }
             func biome(atX x: Int, y: Int) -> BiomeKind {
                 biomes[GridPoint(x: x, y: y)] ?? defaultBiome
             }
         }

         private func makeTempDir() -> URL {
             let dir = FileManager.default.temporaryDirectory
                 .appendingPathComponent("districts-overlap-\(UUID().uuidString)")
             try? FileManager.default.createDirectory(
                 at: dir, withIntermediateDirectories: true)
             return dir
         }

         private func makeEngine(at dir: URL) -> CityEngine {
             let log = EventLog(fileURL: dir.appendingPathComponent("events.jsonl"))
             let snap = SnapshotStore(url: dir.appendingPathComponent("state.json"))
             let engine = CityEngine(eventLog: log, snapshotStore: snap)
             engine.biomeReader = MockBiomeReader()  // meadow-only — cross-skip активен
             return engine
         }

         private func ingestProjects(_ engine: CityEngine,
                                      projects: [String], tasksPerProject: Int) {
             for (pIdx, project) in projects.enumerated() {
                 for tIdx in 0..<tasksPerProject {
                     let ts = Date(timeIntervalSince1970:
                         TimeInterval(pIdx * 1000 + tIdx) * 3600)
                     engine.ingestTaskCompletion(
                         project: project,
                         title: "task-\(tIdx)",
                         taskId: nil,
                         source: "test:\(project):\(tIdx)",
                         ts: ts
                     )
                 }
             }
         }

         /// AC:5 — 5 проектов × 30 задач → 0 cross-project overlap.
         func test_FiveProjects_ThirtyTasks_ZeroOverlap() {
             let dir = makeTempDir()
             defer { try? FileManager.default.removeItem(at: dir) }
             let engine = makeEngine(at: dir)
             let projects = ["alpha", "beta", "gamma", "delta", "epsilon"]
             ingestProjects(engine, projects: projects, tasksPerProject: 30)

             var cellToProject: [GridPoint: String] = [:]
             for unit in engine.state.units.values {
                 let size = unit.kind.size
                 for dx in 0..<size.width {
                     for dy in 0..<size.height {
                         let cell = GridPoint(
                             x: unit.position.x + dx,
                             y: unit.position.y + dy)
                         if let existing = cellToProject[cell] {
                             XCTAssertEqual(existing, unit.projectId,
                                 "Cross-project overlap at \(cell): " +
                                 "existing=\(existing), new=\(unit.projectId)")
                         } else {
                             cellToProject[cell] = unit.projectId
                         }
                     }
                 }
             }
         }

         /// AC:7 — multi-project replay детерминирован: тот же ввод →
         /// тот же итоговый state (origins + позиции юнитов).
         func test_FiveProjects_ThirtyTasks_DeterministicReplay() {
             let dir1 = makeTempDir()
             let dir2 = makeTempDir()
             defer {
                 try? FileManager.default.removeItem(at: dir1)
                 try? FileManager.default.removeItem(at: dir2)
             }
             let projects = ["alpha", "beta", "gamma", "delta", "epsilon"]

             let engine1 = makeEngine(at: dir1)
             ingestProjects(engine1, projects: projects, tasksPerProject: 30)

             let engine2 = makeEngine(at: dir2)
             ingestProjects(engine2, projects: projects, tasksPerProject: 30)

             // Сравнение state:
             XCTAssertEqual(engine1.state.units.count,
                            engine2.state.units.count,
                            "Unit counts diverge")
             XCTAssertEqual(engine1.state.nextDistrictIndex,
                            engine2.state.nextDistrictIndex,
                            "nextDistrictIndex diverge")
             for project in projects {
                 let p1 = engine1.state.projects[project]
                 let p2 = engine2.state.projects[project]
                 XCTAssertEqual(p1?.districtOrigin, p2?.districtOrigin,
                                "districtOrigin diverge for \(project)")
                 XCTAssertEqual(p1?.taskCount, p2?.taskCount,
                                "taskCount diverge for \(project)")
             }
         }
     }
     ```
   - **`GridPoint` уже `Codable, Hashable`** (`CityState.swift:435`) — без дополнительных
     правок.

9. **Bugs.md + Current.md update** `[AC:8]`
   - Файл: `concept/Bugs.md`
   - Удалить строку `| BUG-022 | P0 | 🔴 Открыт | F-06 | ...` из «Активные».
   - Добавить **первой строкой** в «Закрытые» (перед BUG-001 от TASK-055):
     ```
     | BUG-022 | 2026-05-25 (<commit>) | Кварталы разных проектов перекрываются в state.json — фундаментальная регрессия F-06 | TASK-056: DistrictPlanner.allocateNextOrigin + allocateAlongMagistrale получили параметры `otherProjectsClaims: Set<GridPoint>` + `minDistrictRadius=8`, пропускают origin'ы в Чебышёвской окрестности чужих клеток. UnitPlanner.nextPosition + footprintBlocked получили параметр `otherProjectCells`, отвергают footprint'ы, пересекающиеся с чужими юнитами. CityEngine.applyTaskCompleted собирает claims через computed helper `claimedCellsByProjects`. Property-тест DistrictNoOverlapPropertyTests (5 проектов × 30 задач) проверяет инвариант. Существующий state.json пользователя с 7 overlap не мигрируется — требуется reset (см. BUG-005). |
     ```
   - Файл: `concept/Current.md`
   - В строке F-06 (строка ~426) дописать упоминание cross-project защиты:
     добавить в детали `... + cross-project overlap защита через
     allocateNextOrigin(otherProjectsClaims:minDistrictRadius:) +
     UnitPlanner.nextPosition(otherProjectCells:) (TASK-056 BUG-022)`. F-06 ✅ остаётся.

### Edge cases (явно обработать)

- [ ] **Карта переполнена (отказ allocate).** Если в радиусе minDistrictRadius
      все клетки заняты → spiral loop крутится до `maxAttempts = currentIndex + 10_000`
      (текущий лимит). При достижении лимита — возвращается последний `origin`,
      даже если он `tooClose`. **Это backstop**, не silent silent — на 256×256
      карте при разумных 10-20 проектах не возникает. Если возникнет — отдельная
      задача с тяжёлым решением (extend map / shrink districts / etc.). Тест:
      `test_FiveProjects_ThirtyTasks_ZeroOverlap` гарантирует, что для базового
      сценария лимит достаточен.
- [ ] **Replay legacy state.json** (`~/Library/Application Support/CommitPyramid/state.json`
      пользователя — 7 overlap клеток). При первом запуске после фикса
      `engine.replayFromLog` (CityEngine:179-208) пересоздаст state. Первые
      N origins будут детерминированно те же (спираль не изменилась, water-skip
      работает идентично). Начиная с момента, когда новый allocate должен был бы
      выбрать другой origin (если бы алгоритм был старый) — origins разойдутся.
      **Это допустимое расхождение** (PM фиксировал). Пользователю
      рекомендуется reset (BUG-005). При replay-тесте `testReplayEquivalence`
      этот случай не проявится, потому что он стартует с пустого state.
- [ ] **Race в ingest** — `applyTaskCompleted` вызывается строго последовательно
      (single-threaded engine, см. `ingestTaskCompletion:156-175`). `state` не
      разделяется между потоками. Race нет.
- [ ] **Single project** — 1 проект → `otherClaims = {}` → `tooClose` всегда false →
      поведение идентично текущему. Тест `testSingleIngestProducesTwoEvents`
      (CityEngineTests:20-31) подтверждает.
- [ ] **Reoccupation руин (F-06 правило 1)** — если старый проект полностью в
      decay-4 (все его юниты — руины), его клетки всё равно есть в `state.units`
      → `claimedCellsByProjects` включает их → новый проект не может занять.
      **Этот edge case НЕ закрывается данной задачей** (отдельный продуктовый
      вопрос: снимать ли claim при decay-4 / при cleanup ruins). PM явно
      зафиксировал, что это не в скоупе TASK-056. **Документировать в коммите
      как known limitation**: если в state есть decay-4 проект — новый проект
      обходит его территорию через cross-project защиту, что приводит к
      «пустыне руин» вокруг старого мёртвого проекта. Следующая задача —
      claim-snapshot при ruins.
- [ ] **Биом-filter conflict** — порядок в `allocateNextOrigin`:
      water-skip (hard) → cross-project-skip (hard) → preferredBiomes-scan (soft).
      Если все три не сходятся → fallback на cross-project-skipped origin (без
      preferred biome). Detail: `preferredBiomes` блок (`:74-88`) обновлён с
      `scanStart = idx` (вместо `currentIndex`) — это означает, что биомное
      предпочтение **не возвращает** на ранние origin'ы, которые были skipped как
      `tooClose` или water. Корректно: cross-project — hard-инвариант.

### Файлы для изменения

- `Sources/CityDeveloper/Game/CityEngine.swift` — добавить
  `claimedCellsByProjects` helper в extension, интегрировать `otherClaims`/`otherSet`
  в `applyTaskCompleted` (2 место сборки + 2 место передачи).
- `Sources/CityDeveloper/Game/DistrictPlanner.swift` — расширить сигнатуры
  `allocateNextOrigin` + `allocateAlongMagistrale`, добавить cross-project skip loop
  в обоих, обновить scanStart для preferred-biome.
- `Sources/CityDeveloper/Game/UnitPlanner.swift` — расширить сигнатуры
  `nextPosition` + `footprintBlocked`, пробросить `otherProjectCells` в template
  path и legacy path.
- `Tests/CityDeveloperTests/DistrictNoOverlapPropertyTests.swift` — **новый файл**,
  2 теста (zero-overlap + deterministic-replay).
- `concept/Bugs.md` — BUG-022 в «Закрытые».
- `concept/Current.md` — F-06 строка обновлена упоминанием cross-project защиты.

### Файлы НЕ трогать

- `Sources/CityDeveloper/Data/CityState.swift` — НЕ добавляем новое поле
  `claimedCells` (это сломало бы CityState.version для snapshot формата F-12).
  Claim собирается на лету.
- `Sources/CityDeveloper/Game/EvolutionGraph.swift` — эволюция не задействована.
- `Sources/CityDeveloper/Game/RoadNetwork.swift` — рост дорог через
  `extendDistrictPlan` остаётся как есть. Если возникнет случай «дорога нового
  проекта залезла в чужой квартал» — это отдельный edge case (UnitPlanner кладёт
  здания вокруг road, защита `otherProjectCells` ловит overlap зданий; road
  ячейки чужого проекта пока не в скоупе — добавим followup в коммите если
  smoke выявит).
- `Sources/CityDeveloper/Data/EventLog.swift` / `SnapshotStore.swift` — формат
  events.jsonl/state.json не меняется.
- `concept/Concept.md` — F-06 спека не меняется (фича та же, инвариант починен).
- Tests/CityDeveloperTests/DistrictPlannerBiomeAwareTests.swift — back-compat через
  дефолты, **не правим существующие** 6 тестов.

### Команды проверки (для DoD)

- Компиляция: `cd /Users/ilahohlov/CityDeveloper && swift build -c debug 2>&1 | tail -10`
- Полный suite: `cd /Users/ilahohlov/CityDeveloper && swift test 2>&1 | tail -15`
- Целевой тест: `cd /Users/ilahohlov/CityDeveloper && swift test --filter DistrictNoOverlapPropertyTests 2>&1 | tail -10`
- Замёрзшие тесты (проверка back-compat): `cd /Users/ilahohlov/CityDeveloper && swift test --filter DistrictPlannerBiomeAwareTests 2>&1 | tail -10` (ожидание 6/6 pass).
- Replay-determinism: `cd /Users/ilahohlov/CityDeveloper && swift test --filter CityEngineTests 2>&1 | tail -10` (ожидание 4/4 pass).
- Manual smoke: `swift run CommitPyramid`, добавить 4 проекта через add-task.sh × 20 каждый, после прогона:
  ```bash
  jq '[.cityState.units | to_entries | .[].value | {x:.position.x, y:.position.y, pid:.projectId}] | group_by("\(.x),\(.y)") | map(select(length > 1 and ([.[].pid] | unique | length) > 1))' "$HOME/Library/Application Support/CommitPyramid/state.json"
  ```
  → ожидание: `[]`.

### Сложность

`senior`

**Обоснование:** новый алгоритм cross-project защиты, изменение API двух методов
(allocateNextOrigin + nextPosition) с back-compat дефолтами, интеграция в
CityEngine с двумя сборками `otherSet` (template/legacy path), новый property-тест
с CityEngine setup, риск задеть replay determinism (требует осознанной проверки).
6 файлов изменены, в т.ч. новый тест. Архитектурное решение между 3 альтернативами
(claim-registry vs spacing-bump vs computed claim-map) и его обоснование.

### Ожидаемое время

M (≤1д, реалистично 4-6 часов: 30 мин helper + 1ч allocate + 30 мин footprintBlocked
+ 1ч CityEngine integration + 1-2ч property-test (включая отладку CityEngine init
из теста) + 30 мин docs + 30 мин manual smoke).

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_ (определит лид)

### Definition of Done

#### Функциональные
- [ ] Инвариант данных: `jq`-проверка возвращает `[]` для cross-project overlap
- [ ] Property-тест ловит регрессию
- [ ] Smoke: 4 проекта × 20 задач → 0 overlap, видимые зазоры

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Все тесты pass (baseline 165+1 skip не падает)
- [ ] Replay determinism: тот же seed + tasks.jsonl → тот же state

#### Обновление документации
- [ ] `Bugs.md`: BUG-022 → «Закрытые» с TASK-056 + commit hash
- [ ] `Current.md`: F-06 остаётся ✅ (инвариант починен, статус не меняется)
- [ ] Если выбран механизм с claim-реестром — упомянуть его в Current.md F-06
      деталях

---

## Статус

`[ ] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[x] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-25
- Spec-review: approved (Opus, 0 blocking issues; minor notes: AC «bbox(district)» опережает дизайн — лид выберет между bbox-аппроксимацией и claim-реестром; edge case «карта переполнена» и «удалённый проект» отданы лиду на инженерное/продуктовое решение — норм для P0-фикса с свободой архитектурного выбора)
- Готова к работе: 2026-05-25
- Lead-model: opus (P0-trigger + архитектурный — новый алгоритм cross-project защиты через computed claim-map)
- Lead-trigger: opus (P0, фундаментальная регрессия F-06; новая логика в DistrictPlanner + UnitPlanner + CityEngine)
- Plan-review: revised round 2 → approved (Sonnet контр-модель к Opus-лиду; круг 1 нашёл 3 БЛОКЕРа — неверные сигнатуры CityEngine.init / ingestTaskCompletion в property-тесте + missing комментарий-обоснование scanStart=idx; круг 2 подтвердил закрытие всех + информационные DeterministicReplay/MockBiomeReader closed)
- Исполнитель: opus
- Code-review: approved (Opus, P0/Lead-opus/senior triggers; 0 blocking issues — 4 minor наблюдения: дубль кода template/legacy path, naming otherProjectsClaims vs otherProjectCells, legacyRingPosition pre-existing edge case, nil-fallback intentional для MapReinitCoordinator)
- Завершена: 2026-05-25
- Коммит: (заполнится после git commit)
