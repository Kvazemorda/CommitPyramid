# TASK-053: BiomeClassifierTests — починить testRiversHaveReasonableWidth (seed=42 без рек)

## Связь
- **F-15** из Concept.md (биомы)
- **BUG-020** из Bugs.md (P1)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-24_

### Что хотим

Тест `BiomeClassifierTests.testRiversHaveReasonableWidth` (smoke-тест ширины
рек) сейчас падает на seed=42, потому что `BiomeClassifier.downhillRivers`
на этом seed'е не генерирует ни одной reки. Тест-щит для F-15 должен
**стабильно** проходить — иначе мы теряем regression-обнаружение реальных
поломок classifier'а. Самый дешёвый и правильный фикс — взять seed, где
реки **гарантированно** есть (одна из нескольких устойчиво «речных»
карт), и зафиксировать его в тесте с комментарием.

Тюнинг порогов classifier'а — отдельная задача (затрагивает распределение
всех биомов, ломает несколько других тестов, потенциально регрессирует
BUG-008). Не входит в эту задачу.

### Пользовательский сценарий

1. Разработчик запускает `swift test --filter BiomeClassifierTests` — тест
   `testRiversHaveReasonableWidth` проходит.
2. CI / автоматические `swift test` на каждом коммите больше не показывают
   1 known-fail (132/132 PASS вместо 131/132).
3. При изменении `BiomeClassifier.downhillRivers` логики разработчик
   узнаёт о регрессе сразу — тест надёжно даёт сигнал.

### Acceptance criteria

- [ ] Тест `BiomeClassifierTests.testRiversHaveReasonableWidth` использует
      seed, при котором `BiomeClassifier.classify(...)` детерминированно
      возвращает ≥1 компоненту `.river` с шириной ≥1 tile.
- [ ] В коде теста рядом с seed'ом — короткий комментарий: `// seed N
      выбран как устойчиво «речной» — TASK-053 / BUG-020`.
- [ ] Поиск нового seed — последовательным перебором 1..50 (пользовательский
      сценарий пишется лидом — выбрать первый по порядку seed, где
      `connectedComponents(in: map, biome: .river).count >= 1`).
- [ ] Файл с известным-fail `BUG-020` обновлён в Bugs.md → перенесён в
      «Закрытые» с описанием решения (smoke-щит: смена seed на стабильно
      речной).
- [ ] `swift test 2>&1 | grep "with [01] failure"` после фикса показывает
      0 failures.

### Что НЕ делаем (границы скоупа)

- НЕ тюним пороги `BiomeClassifier.classify` / `downhillRivers` —
  это отдельный больной вопрос (см. BUG-008 распределение биомов; tuning
  одного порога меняет распределение всех 7 биомов).
- НЕ переписываем алгоритм downhill-генерации рек.
- НЕ меняем `BiomeKind` enum / `River` модель.
- НЕ добавляем «генератор seed'ов с гарантией наличия рек» — это
  over-engineering для smoke-теста.

### Edge cases

- [ ] Перебор 1..50 не нашёл стабильного seed → расширить до 1..200.
      Если и там нет — escalate (значит реальная проблема в `downhillRivers`,
      не в seed; в этом случае задача переоткрывается как «BUG-020:
      downhillRivers не генерирует реки на типичных шумовых картах», и
      нужен совсем другой фикс).
- [ ] Найден seed=N, но `connectedComponents(.river).count == 1` (только
      одна река) — это OK. Тест проверяет «reasonable width», количество
      рек не критично.
- [ ] При смене seed остальные тесты `BiomeClassifierTests` (если они
      используют тот же seed=42 через fixture / global const) могут
      потребовать **отдельной** проверки — fixture не общая, каждый тест
      сам задаёт seed.

### Зависимости

- **Blocked-by:** —
- **Soft-blocks:** —

### Дизайн

Не применимо (тестовый seed, не UI).

### Done-критерий

_Из BUG-020 expected:_ «Либо подкрутить пороги, чтобы рек было всегда ≥1,
**либо изменить seed в тесте на устойчиво «речной»**. Связан с BUG-006/
BUG-008 (биомы перекошены).» Закрывает BUG-020 минимальным изменением
без вторжения в classifier-логику.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-24_
_Модель: sonnet_
_Статус: [x] готов_

### Анализ текущего состояния

- В коде уже есть: `Tests/CityDeveloperTests/BiomeClassifierTests.swift:101-125` — тест
  `testRiversHaveReasonableWidth` с `let world = makeWorld(seed: 42)` на строке 102.
- Тест проверяет: `connectedComponents(in: map, biome: .river)` не пустой; если пустой —
  XCTFail на строке 108.
- Помимо этого теста, `seed: 42` хардкожен в **остальных 4 тестах файла** (строки 16, 36, 45, 60,
  175 — `testDeterminism`, `testMinimumBiomeDiversity`, `testDominantBiomeDoesNotExceedThreshold`,
  `testNoSmallSeaComponents`, `testDebugAsciiDump`). Они **проходят** на seed=42 и **не
  затрагиваются** этой задачей — мы меняем seed **только в testRiversHaveReasonableWidth**.
- `BiomeClassifier.classify(world:)` (вызывается из теста) и `BiomeClassifier.downhillRivers`
  (TASK-027) — не трогаем, лежат в `Sources/CityDeveloper/World/BiomeClassifier.swift`.

### Архитектурное решение

Минимальное вмешательство: подобрать seed, при котором `connectedComponents(in: map, biome: .river)`
гарантированно возвращает ≥1 компоненту, и заменить `seed: 42` → `seed: <found>` только в
`testRiversHaveReasonableWidth`. Логику теста (ширина 1-8 tile) сохраняем — она правильная.

Способ поиска: пишем временный helper-тест, который перебирает seed 1..50 и принтит первый, где есть
реки. После находки — удаляем helper, прописываем найденный seed в тесте.

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку. Шаг непонятен — НЕ импровизируй.

1. **Найти стабильно-речной seed** `[AC:3]`
   - Файл: временно создать `Tests/CityDeveloperTests/RiverSeedFinder.swift`
     (или inline-helper в `BiomeClassifierTests.swift`).
   - Скелет:
     ```swift
     func findRiverSeed() throws {
         for seed in UInt64(1)...UInt64(50) {
             let world = makeWorld(seed: seed)
             let map = try BiomeClassifier.classify(world: world)
             let rivers = connectedComponents(in: map, biome: .river)
             if !rivers.isEmpty {
                 print("RIVER_SEED_FOUND: \(seed) (rivers: \(rivers.count))")
                 return
             }
         }
         XCTFail("Не найден seed с реками в 1..50")
     }
     ```
   - Запустить: `swift test --filter findRiverSeed 2>&1 | grep RIVER_SEED_FOUND`.
   - Зафиксировать найденный seed в head.

2. **Применить найденный seed в `testRiversHaveReasonableWidth`** `[AC:1,2]`
   - Файл: `Tests/CityDeveloperTests/BiomeClassifierTests.swift:102`
   - Заменить `let world = makeWorld(seed: 42)` → `let world = makeWorld(seed: <N>)`
     с комментарием:
     ```swift
     // seed <N> выбран как устойчиво «речной» — TASK-053 / BUG-020
     let world = makeWorld(seed: <N>)
     ```

3. **Удалить временный helper** `[AC:1]`
   - Удалить `RiverSeedFinder.swift` или inline `findRiverSeed()`.

4. **Запустить полный test suite** `[AC:1,5]`
   - `swift test 2>&1 | grep "Executed"`
   - Ожидание: 132/132 passed, 0 failures (закрытие 1 known-fail BUG-020).

5. **Обновить Bugs.md** `[AC:4]`
   - Перенести BUG-020 из «Активные» в «Закрытые» с строкой:
     `| BUG-020 | 2026-05-24 | testRiversHaveReasonableWidth seed=42 без рек | Сменён seed на <N> (устойчиво речной). TASK-053. |`

### Edge cases (явно обработать)

- [ ] Не найден seed в 1..50 → расширить до 1..200 (см. edge case PM). Если и там нет —
      эскалировать как «BUG-020: downhillRivers не генерирует реки на типичных шумовых картах».
- [ ] Найдено только seed с одной микро-рекой `count < 3` (отсекается на строке 115) →
      тест всё равно пройдёт (no rivers → XCTFail, а здесь rivers есть, но мелкие отфильтруются).
      Это OK — тест проверяет width у компонент `count >= 3`, не количество.

### Файлы для изменения

- `Tests/CityDeveloperTests/BiomeClassifierTests.swift` — строка 102 (seed change + comment).
- `concept/Bugs.md` — BUG-020 → Закрытые.
- `concept/Current.md` — упомянуть BUG-020 closure (минимальная строка).

### Файлы НЕ трогать

- `Sources/CityDeveloper/World/BiomeClassifier.swift` — пороги не тюним (см. PM «Что НЕ делаем»).
- Остальные тесты `BiomeClassifierTests.swift` (с seed=42) — не трогать.

### Команды проверки

- Компиляция: `swift build -c debug`
- Тесты: `swift test --filter BiomeClassifierTests 2>&1 | tail -10` → 5/5 PASS.
- Полный suite: `swift test 2>&1 | grep "Executed"` → 132/132 PASS.

### Сложность

`junior`

**Обоснование:** одно-файловое изменение seed-литерала + одна табличная строка в Bugs.md.

### Ожидаемое время

S (≤2ч, фактически 15 минут включая поиск seed)

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: junior_
_Объём: S_

### Definition of Done

#### Функциональные
- [ ] AC выполнены
- [ ] Полный `swift test` показывает 0 failures (132/132 PASS вместо 131/132)

#### Технические
- [ ] Компиляция без ошибок
- [ ] Других тестов не сломали

#### Обновление документации
- [ ] `Bugs.md`: BUG-020 → перенести в «Закрытые» с указанием коммита
- [ ] `Current.md`: упомянуть BUG-020 closure

---

## Статус

`[ ] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[x] done` / `[ ] skipped`

## 🔀 Pivot решения (2026-05-25)

PM-фикс «сменить seed на устойчиво речной» оказался неработоспособным:
перебор seed'ов 1..200 не нашёл ни одной карты с реками. Причина — не в
seed'е, а в том, что `BiomeClassifier.carveRivers(...)` был намеренно
удалён из pipeline ещё в коммите `31acaad` (commit body: «Реки отключены
(carveRivers убран)»). Илья подтвердил (2026-05-25): реки убраны, потому
что **плохо рендерились и пересекали город/дороги**. Возвращать фичу
без отдельного продуктового решения по рендеру не нужно.

Принято решение **won't-fix BUG-020 через cleanup** (вариант B из
обсуждения):

### Что сделано

1. **`Sources/CityDeveloper/World/BiomeClassifier.swift`:**
   - Удалена `private static func carveRivers(...)` (~20 строк).
   - Удалена `private static func carveOnePath(...)` (~50 строк).
   - Удалена `private static let maxRiverHalfWidth = 15`.
   - Удалена публичная `static let riverSourceCount: Int = 5` (была не
     задействована вне класса).
   - Из комментария «Ожидаемое распределение» убрано `river≈1%`, добавлен
     явный пояснительный комментарий, что фича отключена.

2. **`Tests/CityDeveloperTests/BiomeClassifierTests.swift`:**
   - Удалён `testRiversHaveReasonableWidth` (тест на несуществующую
     фичу). Helper `connectedComponents(in:biome:)` оставлен — его
     используют другие тесты (`testNoSmallSeaComponents`,
     `testDominantBiomeDoesNotExceedThreshold`) для `.sea`.

3. **`concept/Bugs.md`:** BUG-020 перенесён из «Активные» в «Закрытые» с
   полным описанием причины won't-fix.

4. **`concept/Current.md`:** добавлен прогон-блок 2026-05-25 (BUG-020 cleanup).

### Что НЕ тронуто

- Enum case `BiomeKind.river` — используется в `CityState`/`UnitKind.terrain`,
  `TileTextureFactory`, `BiomeRenderer`, `BiomeMapReader`, `DistrictPlanner`,
  `TerrainAffinity*Tests`. Удаление сломало бы tileset и terrain-matching.
  Реки могут вернуться как фича — enum остаётся.
- `BiomeClassifier.classify(...)` pipeline не менялся, пороги и распределение
  не сдвинуты. BUG-008 не задет.

### Verification

- `swift build -c debug` → pass.
- `swift test` → 165/165 passed, 1 skipped, 0 failures (BUG-020 known-fail
  устранён за счёт удаления нерелевантного теста, не подкручиванием).
- `swift test --filter BiomeClassifierTests` → 11 тестов, 0 failures.

## Метаданные
- Создана PM: 2026-05-24
- Spec-review: approved
- Готова к работе: 2026-05-24
- Lead-model: sonnet
- Plan-review: skipped (junior + 1-файл change — overengineering для S-задачи)
- Завершена: 2026-05-25
- Исполнитель: opus (главная сессия после эскалации haiku-executor'а; pivot решения согласован с Ильёй)
- Code-review: skipped (cleanup мёртвого кода без логических изменений; verify covered)
- Коммит: —
