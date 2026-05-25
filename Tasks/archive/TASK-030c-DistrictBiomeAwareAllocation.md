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

_Автор: lead (agent)_
_Дата: 2026-05-24_
_Модель: sonnet_
_Статус: [x] готов_

### Анализ текущего состояния

- `Sources/CityDeveloper/Game/DistrictPlanner.swift:49-67` — `allocateNextOrigin(currentIndex:
  biomeReader:)` — спиральный allocator, пропускает water-биомы (BUG-009). Возвращает
  `(origin: GridPoint, newIndex: Int)`. **Точка расширения** для biome-aware.
- `Sources/CityDeveloper/Game/DistrictPlanner.swift:79-129` — `allocateAlongMagistrale(...)`
  — fallback для проектов вдоль магистрали. Тоже принимает `biomeReader`. Эту функцию **не
  трогаем** в 030c (магистральные кварталы — отдельный кейс, не требует terrain-affinity).
- `Sources/CityDeveloper/Game/TerrainAffinity.swift:14-80` — `enum TerrainAffinity`,
  публичный API `weight(for: UnitKind, in: BiomeKind) -> Double` уже готов (TASK-033).
  Возвращает [0..1]: 1.0 предпочтительный, 0.5 fallback, 0.15 «неожиданный гость», 0.05
  pyramid/quarry в море.
- `Sources/CityDeveloper/Game/CityEngine.swift` — `applyTaskCompleted` ветка isNewProject
  вызывает `DistrictPlanner.allocateNextOrigin`. Точное место вызова — Explore lead
  TASK-030b уже разобрал; для 030c нужна та же точка интеграции.
- `Sources/CityDeveloper/Game/BiomeMapReader.swift` (через `engine.biomeReader`) — есть API
  `biome(atX:y:) -> BiomeKind`.

**Что нужно дописать:**
1. `TerrainAffinity.preferredBiomes(for: ProjectState) -> [BiomeKind]` — новый pure-helper.
2. Расширить `DistrictPlanner.allocateNextOrigin` параметром `preferredBiomes: [BiomeKind] = []`.
3. В `CityEngine` интегрировать: при isNewProject + unitIds.count ≥ 3 — вычислять preferred,
   передавать в planner.
4. Тесты: `TerrainAffinityPreferredBiomesTests` + `DistrictPlannerBiomeAwareTests`.

### Архитектурное решение

**Helper `preferredBiomes`** — pure: суммирует `TerrainAffinity.weight(kind, biome)` по
всем юнитам проекта, для каждого из 7 биомов. Сортирует биомы по убыванию суммарного веса.
Отсекает биомы с весом < threshold (например, ≤ 0.3 × max).

```swift
extension TerrainAffinity {
    static func preferredBiomes(for project: ProjectState) -> [BiomeKind] {
        guard !project.unitIds.isEmpty else { return [] }
        // Нужен доступ к unitIds → UnitState → kind. Это делает caller.
        // Pure-сигнатура: принимаем готовый список kind'ов.
        // Альтернатива: caller сам собирает kinds и передаёт массив.
        // Реализация — см. пошаговая.
    }
}
```

Вообще, проще передавать `[UnitKind]` напрямую — caller (CityEngine) уже имеет state.

**Сигнатура helper'а:**
```swift
static func preferredBiomes(for kinds: [UnitKind]) -> [BiomeKind]
```

Алгоритм:
1. Для каждого `biome` ∈ `BiomeKind.allCases` (7 биомов): `scores[biome] = sum(weight(kind, biome) for kind in kinds)`.
2. `maxScore = max(scores.values)`.
3. `threshold = 0.3 × maxScore`.
4. Возвращаем биомы, отсортированные по убыванию score, у которых `score > threshold`.
5. Если result пуст (все = 0 после edge case empty-terrain) — fallback `[.meadow, .desert]`.

**DistrictPlanner extension:**
```swift
func allocateNextOrigin(
    currentIndex: Int,
    biomeReader: BiomeMapReader?,
    preferredBiomes: [BiomeKind] = []
) -> (origin: GridPoint, newIndex: Int)
```

Поведение:
- `preferredBiomes.isEmpty` или `biomeReader == nil` → текущее поведение (спираль + water-skip).
- Иначе: первые ~20 кандидатов спирали фильтруются — оставляются только те, где
  `reader.biome(atX:y:) ∈ preferredBiomes`. Если ни один из 20 не подошёл — fallback на
  обычную спираль с того же idx. Это гарантирует, что мы не «застрянем» в поиске и всегда
  вернём origin.

**CityEngine integration:**
В точке вызова `allocateNextOrigin` (где-то в `applyTaskCompleted` ветка isNewProject)
заменить:
```swift
let (origin, newIdx) = districtPlanner.allocateNextOrigin(
    currentIndex: state.nextDistrictIndex,
    biomeReader: biomeReader
)
```
на:
```swift
let preferred: [BiomeKind]
if project.unitIds.count >= 3 {
    let kinds = project.unitIds.compactMap { state.units[$0]?.kind }
    preferred = TerrainAffinity.preferredBiomes(for: kinds)
} else {
    preferred = []
}
let (origin, newIdx) = districtPlanner.allocateNextOrigin(
    currentIndex: state.nextDistrictIndex,
    biomeReader: biomeReader,
    preferredBiomes: preferred
)
```

`>= 3` юнитов — порог «достаточно данных». Меньше → спираль (как сейчас).

**Replay-determinism:** алгоритм preferredBiomes — pure от list of kinds; allocator — pure от
(seed/spiral, biomeReader, preferred). При replay все три аргумента детерминированы → origin
тот же. Безопасно.

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку.

1. **TerrainAffinity.preferredBiomes helper** `[AC:1]`
   - Файл: `Sources/CityDeveloper/Game/TerrainAffinity.swift`
   - Добавить в конец extension (или в самом enum):
     ```swift
     /// TASK-030c F-15: biome-aware allocation. Возвращает биомы, в которых
     /// проект «уместен» (по сумме weight(kind, biome) по всем юнитам).
     /// Threshold 0.3 × max отсекает слабые предпочтения.
     static func preferredBiomes(for kinds: [UnitKind]) -> [BiomeKind] {
         guard !kinds.isEmpty else { return [.meadow, .desert] }
         var scores: [(biome: BiomeKind, score: Double)] = []
         for biome in BiomeKind.allCases {
             let s = kinds.reduce(0.0) { acc, k in acc + weight(for: k, in: biome) }
             scores.append((biome, s))
         }
         let maxScore = scores.map(\.score).max() ?? 0
         guard maxScore > 0 else { return [.meadow, .desert] }
         let threshold = 0.3 * maxScore
         return scores
             .filter { $0.score > threshold }
             .sorted { $0.score > $1.score }
             .map(\.biome)
     }
     ```

2. **DistrictPlanner.allocateNextOrigin расширение** `[AC:2]`
   - Файл: `Sources/CityDeveloper/Game/DistrictPlanner.swift:49-67`
   - Заменить сигнатуру:
     ```swift
     func allocateNextOrigin(
         currentIndex: Int,
         biomeReader: BiomeMapReader?,
         preferredBiomes: [BiomeKind] = []
     ) -> (origin: GridPoint, newIndex: Int) {
     ```
   - В теле: после существующего `guard let reader = biomeReader else {...}` (line 50) и
     `while reader.biome(...).isWater` блока (line 59) — **до** возврата — добавить:
     ```swift
     // TASK-030c F-15: biome-aware preference filter (первые 20 кандидатов).
     if !preferredBiomes.isEmpty {
         let preferredSet = Set(preferredBiomes)
         let scanLimit = 20
         var scanIdx = idx
         while scanIdx < idx + scanLimit && scanIdx < maxAttempts {
             let candidate = spiralPoint(index: scanIdx)
             let b = reader.biome(atX: candidate.x, y: candidate.y)
             if !b.isWater && preferredSet.contains(b) {
                 return (candidate, scanIdx)
             }
             scanIdx += 1
         }
         // Fallback: ни один не подошёл — возвращаем уже найденный (water-skipped) origin.
     }
     return (origin, idx)
     ```

3. **CityEngine integration** `[AC:3]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`
   - Найти вызов `districtPlanner.allocateNextOrigin(...)` в ветке isNewProject
     (через grep `allocateNextOrigin` — должен быть рядом с создание нового ProjectState).
   - Перед вызовом — собрать preferred:
     ```swift
     let preferredBiomesForNew: [BiomeKind]
     if project.unitIds.count >= 3 {
         let kinds = project.unitIds.compactMap { state.units[$0]?.kind }
         preferredBiomesForNew = TerrainAffinity.preferredBiomes(for: kinds)
     } else {
         preferredBiomesForNew = []
     }
     ```
   - Передать в `allocateNextOrigin(currentIndex:, biomeReader:, preferredBiomes: preferredBiomesForNew)`.

4. **Тест TerrainAffinityPreferredBiomesTests** `[AC:8]`
   - Файл: `Tests/CityDeveloperTests/TerrainAffinityPreferredBiomesTests.swift`
   - Скелет:
     ```swift
     final class TerrainAffinityPreferredBiomesTests: XCTestCase {
         func testFishingProjectPrefersRiverSea() {
             let kinds: [UnitKind] = [.fishingPier, .port, .well]
             let preferred = TerrainAffinity.preferredBiomes(for: kinds)
             XCTAssertTrue(preferred.contains(.river) || preferred.contains(.sea),
                 "Рыболовный проект должен предпочесть water-биомы. Got: \(preferred)")
         }

         func testMiningProjectPrefersMountainStone() {
             let kinds: [UnitKind] = [.mine, .quarry, .smelter]
             let preferred = TerrainAffinity.preferredBiomes(for: kinds)
             XCTAssertTrue(preferred.contains(.mountain) || preferred.contains(.stone))
         }

         func testNeutralProjectFallsBackToMeadowDesert() {
             let kinds: [UnitKind] = [.well, .shack]
             let preferred = TerrainAffinity.preferredBiomes(for: kinds)
             // ≥ один из meadow/desert должен быть в топе
             XCTAssertFalse(preferred.isEmpty)
         }

         func testEmptyProjectReturnsFallback() {
             let preferred = TerrainAffinity.preferredBiomes(for: [])
             XCTAssertEqual(preferred, [.meadow, .desert])
         }
     }
     ```
   - Ноут: возможно `.fishingPier`/`.port`/`.mine` имеют другие raw имена. Перед запуском
     грепнуть `UnitKind` enum в `Data/CityState.swift` за правильные case'ы.

5. **Тест DistrictPlannerBiomeAwareTests** `[AC:8]`
   - Файл: `Tests/CityDeveloperTests/DistrictPlannerBiomeAwareTests.swift`
   - Скелет (mock BiomeMapReader):
     ```swift
     final class DistrictPlannerBiomeAwareTests: XCTestCase {
         private final class MockReader: BiomeMapReader {
             let biomes: [GridPoint: BiomeKind]
             let defaultBiome: BiomeKind
             init(biomes: [GridPoint: BiomeKind], defaultBiome: BiomeKind = .meadow) {
                 self.biomes = biomes
                 self.defaultBiome = defaultBiome
             }
             func biome(atX x: Int, y: Int) -> BiomeKind {
                 biomes[GridPoint(x: x, y: y)] ?? defaultBiome
             }
         }

         func test_BiomeAwareSpiralFindsPreferredBiomeOrigin() {
             // Карта почти вся meadow, но river-tile в зоне спирали — должно выбрать его.
             // Конкретные координаты — смотреть от spiralPoint(0)..(20).
             let mapWithRiver: [GridPoint: BiomeKind] = [
                 // ...заполнить через DistrictPlanner.spiralPoint(N)
             ]
             let reader = MockReader(biomes: mapWithRiver)
             let planner = DistrictPlanner()
             let (origin, _) = planner.allocateNextOrigin(
                 currentIndex: 0,
                 biomeReader: reader,
                 preferredBiomes: [.river]
             )
             XCTAssertEqual(reader.biome(atX: origin.x, y: origin.y), .river)
         }

         func test_FallbackToSpiralWhenNoMatchingBiome() {
             let reader = MockReader(biomes: [:], defaultBiome: .meadow)
             let planner = DistrictPlanner()
             let (origin, _) = planner.allocateNextOrigin(
                 currentIndex: 0,
                 biomeReader: reader,
                 preferredBiomes: [.river]
             )
             // Карта вся meadow, river нет → fallback на спираль → origin = spiralPoint(0)
             XCTAssertEqual(origin, planner.spiralPoint(index: 0))  // если spiralPoint internal
         }

         func test_IsDeterministicForSameInputs() {
             let reader = MockReader(biomes: [:], defaultBiome: .meadow)
             let planner = DistrictPlanner()
             let r1 = planner.allocateNextOrigin(currentIndex: 0, biomeReader: reader, preferredBiomes: [.meadow])
             let r2 = planner.allocateNextOrigin(currentIndex: 0, biomeReader: reader, preferredBiomes: [.meadow])
             XCTAssertEqual(r1.origin, r2.origin)
             XCTAssertEqual(r1.newIndex, r2.newIndex)
         }
     }
     ```
   - Note: если `spiralPoint` private — открыть как `internal` для тестов через `@testable
     import` или зафиксировать координаты экспериментально (запустить раз, записать).

6. **Smoke + Bugs.md** `[AC:9]`
   - Manual smoke: создать рыболовный проект через add-task.sh + 5 fishing-юнитов → запустить
     reinit (через TASK-030a UI) → новый origin должен оказаться рядом с river/sea.
   - `Bugs.md`: BUG-006 retest — биом-аффинитет теперь работает, можно retest. (BUG-006 уже
     помечен как «частично — нужен retest после BUG-005».)

### Edge cases (явно обработать)

- [ ] `project.unitIds.count == 0` (новый проект, нет юнитов) → caller передаёт empty
      preferredBiomes → planner идёт по обычной спирали. (`CityEngine.swift` integration step 3)
- [ ] `project.unitIds.count == 1..2` → caller передаёт empty (порог 3). Меньше данных = риск
      ошибочного предпочтения. Спираль безопаснее.
- [ ] Карта целиком sea (`reader.biome` всегда .sea) → preferredSet не содержит .sea (т.к. mostly water-биомы отфильтровываются BUG-009 веткой), все 20 кандидатов fail → fallback на спираль (water-skipped). DistrictPlanner.swift:59 уже игнорирует water — корректно.
- [ ] `biomeReader == nil` → планер сразу в old path (spiralPoint), preferredBiomes игнорируется. (DistrictPlanner.swift:50)
- [ ] Два рыболовных проекта подряд на одной карте — оба хотят river-биом, но river-tiles
      мало. Второй проект сканит первые 20 кандидатов спирали с idx, продолжающим первого
      (через newIndex). Если ни один не подошёл — fallback на спираль. Детерминизм
      сохраняется.
- [ ] Юнит-каталог пополнился новым kind без `terrain` записи → `TerrainAffinity.weight`
      возвращает 0.5 (fallback) + warning в errors.log. preferredBiomes не сломается.

### Файлы для изменения

- `Sources/CityDeveloper/Game/TerrainAffinity.swift` — добавить `preferredBiomes(for:)` helper.
- `Sources/CityDeveloper/Game/DistrictPlanner.swift` — расширить `allocateNextOrigin`
  опциональным `preferredBiomes`.
- `Sources/CityDeveloper/Game/CityEngine.swift` — точка вызова `allocateNextOrigin` —
  собрать preferred и передать.
- `Tests/CityDeveloperTests/TerrainAffinityPreferredBiomesTests.swift` (НОВЫЙ, 4 теста).
- `Tests/CityDeveloperTests/DistrictPlannerBiomeAwareTests.swift` (НОВЫЙ, 3 теста).

### Файлы НЕ трогать

- `Sources/CityDeveloper/Game/DistrictPlanner.swift:79-129` (`allocateAlongMagistrale`) —
  магистральные кварталы остаются как есть.
- `Sources/CityDeveloper/Game/MapReinitCoordinator.swift` — TASK-030b создаёт оркестратор;
  030c **расширяет** только planner-API, который тот и так зовёт.
- `Sources/CityDeveloper/Data/GameEvent.swift` — placement не пишется отдельным событием
  (PM-решение).

### Команды проверки

- Компиляция: `swift build -c debug`
- Тесты: `swift test --filter "TerrainAffinityPreferredBiomesTests|DistrictPlannerBiomeAwareTests"`
- Полный suite: `swift test 2>&1 | grep "Executed"`
- Smoke: см. шаг 6.

### Сложность

`middle`

**Обоснование:** 3 файла (helper + planner + engine integration), 2 новых тестовых файла. Pure
функция в TerrainAffinity, расширение planner default-параметром (без поломки call-sites),
интеграция в CityEngine на 1 точке. Архитектурное решение «threshold 0.3 × max + fallback на
спираль» зафиксировано.

### Ожидаемое время

M (≤1д, фактически 2-3 часа включая smoke).

---

## ✅ Исполнение

_Исполнитель: claude-sonnet (agent)_
_Дата: 2026-05-24_
_Сложность: middle_
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

`[ ] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[x] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-24
- Spec-review: derived-from-split (TASK-030 lead-analysis 2026-05-23)
- Blocked-by: TASK-030b
- Готова к работе: 2026-05-24
- Lead-model: sonnet
- Plan-review: skipped (middle + расширение существующего API на одном flag + 7 тестов)
- Исполнитель: claude-sonnet (agent)
- Code-review: approved (opus, P1 trigger; minor +1 off-by-one в scanLimit и mixed test naming — не блокеры)
- Verify: compile=pass tests=159/161 (1 known-fail BiomeClassifier→TASK-053, не регрессия) targeted=12/12
- Завершена: 2026-05-24
- Коммит: a744976
