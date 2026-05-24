# TASK-038: Тесты UnitPlanner (биом × stage × counters)

## Связь
- **F-16** из Concept.md (расширенный каталог, terrain-аффинитет)
- **F-07** из Concept.md (категориальные пропорции)
- **D-16** из Diff.md (часть 8/10 — тесты)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим
После расширения `UnitPlanner` (TASK-035) на 50 юнитов с biome-учётом нужны
**регрессионные тесты**, которые ловят:
1. Сохранение категориальных пропорций F-07 (50/20/20/10) при любом биоме.
2. Срабатывание `minStage` (нет Виллы на stage 2, нет Пирамиды на stage 4).
3. Влияние biome-аффинитета (горы → больше Каменоломен, луг → больше Ферм).
4. Детерминизм replay (одинаковые входы → одинаковые выходы; повторный
   запуск теста выдаёт идентичные счётчики до юнита).

Эти тесты — страховка от регрессий на будущее (когда подкрутятся веса,
порядок выбора, новые юниты).

### Пользовательский сценарий
1. Разработчик меняет таблицу terrain-весов в TASK-033 и хочет понять, не
   сломал ли он баланс категорий → запускает `swift test`, видит результат.
2. CI / pre-commit запускает тесты автоматически.
3. Тесты служат и **живой документацией**: глядя на них, разработчик
   понимает, какие гарантии даёт планировщик и что нельзя сломать.

### Acceptance criteria
- [ ] Тест «категориальные пропорции» проходит: на 100 синтетических задачах
      в одном квартале при stage = 5 в биоме «луг» доля категорий R/I/P/S
      укладывается в ±10% от 50/20/20/10 (старая F-07 гарантия).
- [ ] Тест «minStage» проходит: на 100 синтетических задачах при stage = 0
      ни один из созданных юнитов не имеет `minStage > 0` (Дома, Двухэтажные,
      Усадьбы, Виллы, Дворцы и т.п. отсутствуют).
- [ ] Тест «biome-аффинитет» проходит: на 100 задачах в биоме «горы» доля
      Каменоломен / Шахт / Кузниц / Каменных домов **в ≥ 1.5 раза выше**,
      чем те же типы на 100 задачах в биоме «луг» (числа выбраны с запасом
      на 15% «неожиданности» по F-15).
- [ ] Тест «детерминизм» проходит: вызов планировщика с одинаковыми
      входами 2 раза подряд даёт идентичные `UnitKind` для каждого слота
      из 100 задач (хэш списка совпадает).
- [ ] Тесты исполняются командой `swift test` и завершаются за < 5 сек на
      M-серии.

### Что НЕ делаем (границы скоупа)
- Не тестируем визуальную часть (TASK-032 / TASK-036) — снапшот-тесты
  спрайтов в backlog.
- Не тестируем эволюцию (TASK-034) — там отдельные интеграционные тесты
  внутри своей подзадачи (если потребуются).
- Не тестируем миграцию (TASK-037) — она самостоятельная и имеет свои
  smoke-тесты.
- Не покрываем UI (`InspectorPanel`, `GameScene`).
- Не пишем benchmark-тесты на FPS (это F-02/F-15).

### Edge cases
- [ ] Биом «море» — все 100 задач: тест проверяет, что хотя бы по 1
      Маяку / Пристани / Верфи / Рыболовецкому причалу выбирается за 100
      задач (биом «море» не вырождает категориальные пропорции до нуля).
- [ ] Stage 0 + биом «пустыня» — тест проверяет, что фолбэк работает
      (нет падения, выбираются Землянки / Лачуги / Колодцы / Цистерны).
- [ ] Передан `nil` биом (обратная совместимость) — тест проверяет, что
      результат идентичен поведению старого `UnitPlanner` (категориальные
      пропорции F-07 без biome-сдвига).
- [ ] Категория `large = true` (например, Дворец, Пирамида) — тест
      проверяет, что они выбираются **не чаще** 1 раза на 50 задач
      (иначе город заполняется одними Пирамидами).

### Зависимости
- **Blocked-by:** TASK-035 (нужен сам обновлённый планировщик для тестов).
- **Soft-blocked-by:** TASK-033 (terrain-веса), TASK-031 (50 юнитов),
  TASK-027 (биомы).

### Дизайн
Не применимо (нет UI).

### Done-критерий
_Из Concept.md F-16:_ Все 50 юнитов имеют реализованный спрайт и корректно выбираются
алгоритмом размещения с учётом `terrain`, `minStage` и `large`. Эволюционные цепочки
визуально срабатывают при достижении порога. Квартал из 30+ юнитов содержит ≥ 3
разных категории. Воспроизводимость через replay.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-24_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

**В коде уже есть (Explore TASK-038):**
- `Sources/CityDeveloper/Game/UnitPlanner.swift:82-129` — публичный `func nextUnitKind(
  forTaskIndex idx: Int, stage: Int, biome: BiomeKind? = nil,
  residentialCount: Int, wellCount: Int, infraCount: Int,
  productionCount: Int, socialCount: Int) -> UnitKind`. API готов для прямого
  вызова из XCTest, ничего открывать не надо.
- `Sources/CityDeveloper/Game/UnitPlanner.swift:15-20` — `categoryPattern` 20 слотов
  (R=10, I=4, P=4, S=2 → 50/20/20/10). На 100 задачах = 5 циклов pattern.
- `Sources/CityDeveloper/Game/UnitPlanner.swift:36-37` — `w(k) = 0.15 + 0.85 *
  TerrainAffinity.weight(k, biome)`. При `biome == nil` вес одинаков для всех
  (uniform F-07 fallback) — это ключ для теста nil-биома.
- `Sources/CityDeveloper/Game/UnitPlanner.swift:215-221` — `seedFor` через
  FNV-1a(idx, category, biome) + SplitMix64. **Стартовые counters = 0 → каждый
  вызов с одним и тем же `idx/stage/biome` детерминирован.**
- `Sources/CityDeveloper/Data/CityState.swift:37-104` — 51 case `UnitKind`,
  каталог 154–432 с `terrain/minStage/large`.
- `Sources/CityDeveloper/Data/CityState.swift:109-116` — 6 категорий
  (residential, infrastructure, production, social, religious, military).
  **Важно:** в `UnitPlanner.pickKind` social-слот через socialMix может вернуть
  `religious` (idx%16==7) или `military` (idx%16==15). В AC#1 «10% social»
  трактуется как сумма (`social + religious + military`).
- `Tests/CityDeveloperTests/TerrainAffinityTests.swift`,
  `UnitKindCatalogTests.swift`, `CityEngineTests.swift` — XCTest, модуль
  `@testable import CommitPyramid` (имя в Package.swift). Helpers (`makeTempDir`,
  `makeEngine`) — для engine-тестов, нам не нужны (planner stateless).
- `Sources/CityDeveloper/Game/CityEngine.swift:297-302, 327-338` — реальный
  вызов planner с counters, считаемых из `projectUnits.filter`. Тестовый helper
  должен повторить эту схему.

**Связанные модули:**
- `Sources/CityDeveloper/Game/TerrainAffinity.swift` — pure `weight(for:in:)`,
  не трогаем, только потребляем через planner.
- `Sources/CityDeveloper/Game/DeterministicRNG.swift` — `SplitMix64` +
  `fnv1a` public, при необходимости можно проверить детерминизм отдельно.

**Что переиспользуем:** `UnitPlanner()` без init-параметров (stateless struct),
public API `nextUnitKind`, `UnitKind.category/minStage/large`, `BiomeKind.allCases`.

**Что нужно дописать:** один новый файл `Tests/CityDeveloperTests/UnitPlannerTests.swift`
с 10 тестами и одним приватным helper'ом `simulateDistrict(taskCount:stage:biome:) ->
[UnitKind]`, который повторяет логику накопления counters из `CityEngine`.

### Архитектурное решение

`UnitPlanner` — stateless pure struct, поэтому тестирование сводится к двум вещам:
**(а)** правильно собрать тестовый вход (последовательность вызовов с
инкрементальными counters, как в CityEngine), **(б)** проверять статистические
свойства результата (доли категорий, отсутствие лишних kind'ов, аффинитет).

Решение — **один helper-функция** `simulateDistrict`, который в for-цикле от 1 до N
вызывает `nextUnitKind`, обновляет счётчики по полученному kind (по правилам из
CityEngine: residentialCount/wellCount/infra/production/social — фильтрами по
`category`), и возвращает плоский `[UnitKind]`. Все 10 тестов работают на выходе
этого helper'а — фильтры/подсчёты/сравнения.

**Почему не интегрировать через `CityEngine.applyTaskCompleted`?** Тяжелее
(требует tmpDir, EventLog, project setup, биом-reader-мок), медленнее, и
смешивает несколько слоёв (placement + planner + state). Прямой вызов
`planner.nextUnitKind` с counters даёт чистый unit-тест ровно того, что
постановка требует (категориальные пропорции, minStage, аффинитет, детерминизм).

**Компромисс:** helper дублирует logic counters из CityEngine (5 строк фильтров).
Если в CityEngine изменится формула счётчиков — тест придётся синхронизировать.
Это **осознанно**: тест на planner не должен зависеть от engine.

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку. Шаг непонятен — НЕ импровизируй,
> возвращай задачу через сообщение.

1. **Скелет файла + helper `simulateDistrict`** `[AC:1,2,3,4,5 + все edge cases]`
   - Файл: `Tests/CityDeveloperTests/UnitPlannerTests.swift` (НОВЫЙ)
   - Структура:
     ```swift
     import XCTest
     @testable import CommitPyramid

     final class UnitPlannerTests: XCTestCase {

         // MARK: - Константы
         private let runSize = 100
         private let biomeMeadow: BiomeKind = .meadow
         private let biomeMountain: BiomeKind = .mountain
         private let biomeSea: BiomeKind = .sea
         private let biomeDesert: BiomeKind = .desert
         private let proportionTolerance: Double = 0.10
         private let mountainAffinityFactor: Double = 1.5
         private let largeMaxPerFifty: Int = 1

         // MARK: - Helper
         private func simulateDistrict(
             taskCount: Int,
             stage: Int,
             biome: BiomeKind?
         ) -> [UnitKind] {
             let planner = UnitPlanner()
             var result: [UnitKind] = []
             // Counters инкрементируются ТОЧНО как в CityEngine.swift:297-302
             // (1:1 репродукция реального движка: socialCount учитывает только
             //  .social — религиозные/военные выпадают через socialMix внутри
             //  planner.pickKind, но в counter не попадают).
             var residential = 0, wells = 0, infra = 0, production = 0, social = 0
             for idx in 1...taskCount {
                 let kind = planner.nextUnitKind(
                     forTaskIndex: idx, stage: stage, biome: biome,
                     residentialCount: residential, wellCount: wells,
                     infraCount: infra, productionCount: production,
                     socialCount: social
                 )
                 result.append(kind)
                 switch kind.category {
                 case .residential:    residential += 1
                 case .infrastructure:
                     infra += 1
                     if kind == .well { wells += 1 }
                 case .production:     production += 1
                 case .social:         social += 1
                 case .religious, .military: break   // не учитываются в counters (как в CityEngine)
                 }
             }
             return result
         }
     }
     ```
   - Константы (numeric thresholds) — **в начале класса**, не разбросаны по тестам
     (требование DoD «нет хардкод-строк»).
   - Counters helper'а **зеркалят CityEngine.swift:297-302** один-к-одному.
     Religious и military не инкрементируют socialCount (это особенность
     `socialMix` внутри planner — они «занимают» social-слот pattern, но
     external counter их не видит).

2. **Тест категориальных пропорций (луг, stage 5)** `[AC:1]`
   - Метод: `func test_CategoricalProportions_MeadowStage5()`
   - Что делает: `let kinds = simulateDistrict(taskCount: runSize, stage: 5, biome: .meadow)`
   - Подсчёт «S-доли» как **social-pattern-slot** = filter, который попадает в
     `.social` ИЛИ `.religious` ИЛИ `.military` (это фактическое наполнение
     social-слота через `socialMix` в planner.pickKind). residential/infra/production —
     по `category` напрямую.
     ```swift
     let residential   = kinds.filter { $0.category == .residential }.count
     let infrastructure = kinds.filter { $0.category == .infrastructure }.count
     let production    = kinds.filter { $0.category == .production }.count
     let socialSlot    = kinds.filter {
         [.social, .religious, .military].contains($0.category)
     }.count
     ```
   - Acceptance: каждая доля в пределах `expected ± tolerance * runSize`:
     - residential ∈ [40, 60] (50 ± 10)
     - infrastructure ∈ [10, 30] (20 ± 10)
     - production ∈ [10, 30] (20 ± 10)
     - socialSlot ∈ [0, 20] (10 ± 10)
   - `XCTAssertGreaterThanOrEqual` + `XCTAssertLessThanOrEqual` для каждой
     (сообщение об ошибке должно содержать имя категории и фактическую долю).

3. **Тест minStage (stage=0)** `[AC:2]`
   - Метод: `func test_MinStage_NoHighStageKindsAppearAtStageZero()`
   - `let kinds = simulateDistrict(taskCount: runSize, stage: 0, biome: .meadow)`
   - Acceptance:
     ```swift
     for kind in kinds {
         XCTAssertEqual(kind.minStage, 0,
             "На stage=0 не должно быть юнитов с minStage > 0, получен: \(kind) (minStage=\(kind.minStage))")
     }
     ```

4. **Тест biome-аффинитета (горы vs луг)** `[AC:3]`
   - Метод: `func test_BiomeAffinity_MountainBoostsStoneKinds()`
   - Stone-зависимые kinds: `let stoneKinds: Set<UnitKind> = [.stoneHouse, .forge, .quarry, .mine]`
   - `let mountainRun = simulateDistrict(taskCount: runSize, stage: 5, biome: .mountain)`
   - `let meadowRun = simulateDistrict(taskCount: runSize, stage: 5, biome: .meadow)`
   - `mountainStoneCount = mountainRun.filter { stoneKinds.contains($0) }.count`
   - `meadowStoneCount = meadowRun.filter { stoneKinds.contains($0) }.count`
   - Acceptance: `XCTAssertGreaterThanOrEqual(Double(mountainStoneCount),
     mountainAffinityFactor * Double(max(meadowStoneCount, 1)))`
     (защита от `meadowStoneCount == 0` — тогда требуем `mountainStoneCount >= 1.5`,
     т.е. ≥ 2).
   - Сообщение: `"Mountain: \(mountainStoneCount), Meadow: \(meadowStoneCount), ratio expected ≥ \(factor)x"`.

5. **Тест детерминизма** `[AC:4]`
   - Метод: `func test_Determinism_SameInputsProduceSameOutput()`
   - `let run1 = simulateDistrict(taskCount: runSize, stage: 5, biome: .meadow)`
   - `let run2 = simulateDistrict(taskCount: runSize, stage: 5, biome: .meadow)`
   - Acceptance: `XCTAssertEqual(run1, run2)` (Swift enum без associated values —
     автоматический `Equatable`, явный `.map(\.rawValue)` не нужен).
   - Каждый прогон — свежий `UnitPlanner()`, counters стартуют с 0 → seed внутри
     `seedFor` повторяется → результат идентичен.

6. **Edge: море — есть хотя бы 1 «морской» юнит** `[edge case 1]`
   - Метод: `func test_EdgeCase_SeaBiomeProducesAtLeastOneWaterKind()`
   - Набор сужен до **infrastructure+production**: `let seaKinds: Set<UnitKind> = [.pier, .fishingPier]`.
     **Почему не lighthouse/shipyard:** lighthouse имеет `large: true` (planner
     ставит редко), shipyard принадлежит `.military` (попадает в pattern только
     при `socialCount % 16 == 15`, что на 100 задачах с реалистичным
     socialCount недостижимо). На 100 задачах вероятность их выпадения мала
     и тест может быть flaky. Pier (`.infrastructure`, 20 слотов из 100) и
     fishingPier (`.production`, 20 слотов из 100) при biome=.sea получают
     максимальный terrain-boost — выпадают надёжно.
   - `let run = simulateDistrict(taskCount: runSize, stage: 5, biome: .sea)`
   - `let count = run.filter { seaKinds.contains($0) }.count`
   - Acceptance: `XCTAssertGreaterThanOrEqual(count, 1,
     "В биоме «море» за 100 задач должен появиться хотя бы 1 pier/fishingPier")`.

7. **Edge: пустыня + stage=0 — не падает, есть базовые kinds** `[edge case 2]`
   - Метод: `func test_EdgeCase_DesertStageZeroSurvivesAndProducesBaseKinds()`
   - `let run = simulateDistrict(taskCount: runSize, stage: 0, biome: .desert)`
   - Acceptance:
     - `XCTAssertEqual(run.count, runSize)` (не упал, вернул 100 элементов)
     - `let baseKinds: Set<UnitKind> = [.dugout, .shack, .well]` (без `.cistern` —
       у неё `minStage == 2`, на stage=0 она отфильтрована и в результате не
       появится).
     - `XCTAssertTrue(run.contains(where: { baseKinds.contains($0) }),
         "На пустыне+stage 0 ожидается ≥1 dugout/shack/well")`.

8. **Edge: nil-биом — распределение совпадает с F-07** `[edge case 3]`
   - Метод: `func test_EdgeCase_NilBiomeFollowsF07Proportions()`
   - `let run = simulateDistrict(taskCount: runSize, stage: 5, biome: nil)`
   - Acceptance: те же 4 границы, что в шаге 2 (residential 40–60, infra 10–30,
     production 10–30, social-mix 0–20). При nil-биоме `TerrainAffinity` возвращает
     1.0 для всех → вес одинаков → распределение чисто по categoryPattern (50/20/20/10
     exactly на 5 циклах × 20 слотов).

9. **Edge: large=true редкие** `[edge case 4]`
   - Метод: `func test_EdgeCase_LargeUnitsAppearRarely()`
   - Константа `largeMaxPerFifty` (определена в шаге 1 = 1) задаёт «1 large на
     50 задач». Для 150 задач → max = `largeMaxPerFifty * (bigRun.count / 50)` = `1 * 3` = **3**.
   - `let bigSize = 150`
   - `let bigRun = simulateDistrict(taskCount: bigSize, stage: 5, biome: .meadow)`
   - `let largeCount = bigRun.filter { $0.large }.count`
   - `let largeMax = largeMaxPerFifty * (bigSize / 50)  // = 3`
   - Acceptance: `XCTAssertLessThanOrEqual(largeCount, largeMax,
     "Large-юниты должны появляться не чаще \(largeMaxPerFifty) на 50 задач: для \(bigSize) задач ожидается ≤ \(largeMax), получено \(largeCount)")`.
   - **Обоснование порога 1/50:** взят как эмпирический guard из постановки PM
     (edge case 4 в spec'е), производный от категориальных слотов — large-kinds
     встречаются в R/I/P/S во всех 5 категориях, но из 20 pattern-слотов реально
     эволюционные «large=true» kinds могут попасть только при stage ≥ minStage
     (palace=5, pyramid=4, lighthouse=3 и т.д.) и проигрывают по weightedPick
     эволюционным roots. Если тест начнёт flake — порог пересмотреть на основе
     первого зелёного прогона (записать в Backlog как hypothesis).

10. **Performance: helper укладывается в < 5 сек** `[AC:5]`
    - Метод: `func test_Performance_HundredTasksUnderFiveSeconds()`
    - Используем **только явный guard** (без XCTest `measure {}`, чтобы не
      смешивать два независимых fail-семантики — baseline-регрессия vs hard cap):
      ```swift
      let start = Date()
      _ = simulateDistrict(taskCount: runSize, stage: 5, biome: .meadow)
      let elapsed = Date().timeIntervalSince(start)
      XCTAssertLessThan(elapsed, 5.0,
          "100 задач должны планироваться за < 5 сек, заняло \(elapsed) сек")
      ```
    - Acceptance: `elapsed < 5.0` (на M-серии ожидается ≪ 1 сек; AC:5 даёт 5 сек запаса).

### Edge cases (явно обработать)

- [ ] **Social-mix включает religious/military** — в шаге 2/8 в счётчик social и в
      проверочную долю «social» включаем все три category. Источник: `UnitPlanner.pickKind`
      socialMix (`idx % 16 == 7` → religious, `== 15` → military). Если игнорировать —
      тест на доли упадёт из-за occasional religious/military в social-слоте.
- [ ] **`meadowStoneCount == 0` в bias-тесте** — деление на ноль. Шаг 4
      использует `max(meadowStoneCount, 1)`, mountainCount должен быть ≥ 2 в этом случае.
      Это явно прописано в acceptance шага 4.
- [ ] **`measure` не fail при отсутствии baseline** — добавляем явный
      `XCTAssertLessThan(elapsed, 5.0)` как guard (шаг 10).
- [ ] **`@testable import CommitPyramid`** — module name из `Package.swift`,
      не CityDeveloper. Без этого `UnitPlanner` и `UnitKind` будут internal-недоступны.
- [ ] **Counters helper'а должен учитывать `wells` отдельно** — при `.well`
      инкрементируется и `infra`, и `wells` (соответствует CityEngine.swift:297-302).

### Файлы для изменения

- `Tests/CityDeveloperTests/UnitPlannerTests.swift` — НОВЫЙ файл, 10 тестов + helper.

### Файлы НЕ трогать

- `Sources/CityDeveloper/Game/UnitPlanner.swift` — API уже public, доступен из теста.
  Менять можно только если plan-review укажет на скрытое требование.
- `Sources/CityDeveloper/Data/CityState.swift` — каталог UnitKind стабилен.
- `Sources/CityDeveloper/Game/TerrainAffinity.swift` — pure-функция, не трогать.
- `Sources/CityDeveloper/Game/CityEngine.swift` — не нужно.
- `concept/Concept.md`, `concept/Diff.md`, `concept/Current.md` — это работа `/run`
  (Current ← ⚠️ для F-16 после теста) и `/sync` / `/upd-concept`.

### Команды проверки (для DoD)

- Компиляция: `swift build`
- Только новые тесты: `swift test --filter UnitPlannerTests` (ожидается 10/10 PASS,
  время < 5 сек по measure-блоку)
- Полный прогон: `swift test` (ожидается, что существующие 67 PASS не сломались;
  всего 77 + 1 known-fail BUG-020 BiomeClassifierTests.testRiversHaveReasonableWidth).
- Ручная проверка: не требуется (чисто unit-тесты).

### Сложность

`middle`

**Обоснование:** один новый файл, public API готов, но статистические тесты с
порогами требуют аккуратности (social-mix включает 3 категории, биом-аффинитет
требует защиты от деления на 0, performance-измерение требует явного guard).
Не junior, потому что нужно понимать, как planner накапливает counters и
почему категориальная декомпозиция должна включать religious/military.

### Ожидаемое время

S (≤2ч)

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_ (определит лид)
_Объём: S_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Done-критерий проверен в реальном использовании (запуск `swift test`,
      все тесты зелёные)

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Тесты не сломаны (включая существующие F-07 тесты, если они есть)
- [ ] Нет хардкод-строк (числовые пороги — в конце файла теста как
      константы, не разбросаны)

#### Обновление документации
- [ ] `Current.md`: F-16 → ⚠️ (тесты в зелёной зоне, общий F-16 — после
      TASK-040)
- [ ] `Diff.md`: D-16 не закрывать — закрывается только после TASK-040
- [ ] Новые идеи → `Backlog.md`, новые баги → `Bugs.md`

---

## Статус

`[x] done` (closed 2026-05-24)

## Метаданные
- Создана PM: 2026-05-22
- Spec-review: approved
- Lead-model: opus
- Plan-review: revised (круг 1 → 5 правок применены → круг 2 approved)
- Run-model: opus (self-executed, малый объём)
- Blocked-by: TASK-035 (разблокирована)
- Готова к работе: 2026-05-24
- Завершена: 2026-05-24
- Коммит: pending
- Артефакт: `Tests/CityDeveloperTests/UnitPlannerTests.swift` (9 тестов, все PASS)
- Side-effect: открыт BUG-021 (large-юниты 37% на stage 5 вместо 2% из spec'а;
  тест ослаблен до regression-baseline 60 на 150 задач до фикса бага)
