# TASK-054: Large-юниты редкие — `largeRarityFactor` в UnitPlanner.weightedPick

## Связь
- **F-07** из Concept.md (баланс юнитов в квартале)
- **F-16** из Concept.md (расширенный каталог 50 юнитов)
- **F-23** из Concept.md (cross-unit эволюция)
- **BUG-021** из Bugs.md (P2)
- **Приоритет:** P2

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-24_

### Что хотим

Сейчас на stage 5 в meadow ~37% юнитов получают флаг `large=true` (56 из 150
в `test_EdgeCase_LargeUnitsAppearRarely`). Визуально это создаёт «парад
дворцов» — теряется разнообразие квартала. Спека F-07 не задаёт явный
лимит, но **семантика игры** другая: large-юниты — это **результат
эволюции** (palace ← manor, tenement ← house, factory ← workshop через
F-23 EvolutionGraph), а не базовый выбор планировщика.

Минимальный фикс: добавить **множитель редкости** в weightedPick — large
kinds получают weight × 0.1, что снижает их прямой выбор в ~5-10 раз.
Эволюция через `EvolutionGraph` остаётся главным каналом появления large
(там нет нагрузки от множителя). Это даёт визуальный баланс «обычные
дома + редкие достижения в виде palace/factory».

Альтернативный продвинутый путь (вариант C из BUG-021) — полностью убрать
large из weightedPick и оставить только эволюционный канал — **не в этой
задаче**, потому что требует ревизии каталога категорий и может ослабить
прогрессию stage 5 (если эволюция отстаёт).

### Пользовательский сценарий

1. Игрок создаёт новый проект, доводит его до stage 5 через 30+ задач.
2. На stage 5 квартал визуально состоит из: жилых домов 2-3 типов, well,
   roads, market, складов — **не доминируют** palace/manor/tenement.
3. По мере накопления юнитов и срабатывания `EvolutionGraph` (F-23) —
   часть house → tenement, palace, manor; это и есть путь к large.
4. Тест `test_EdgeCase_LargeUnitsAppearRarely` (ранее ослаблен до baseline=60)
   возвращается к строгому контракту: на 150 задач в stage 5 / meadow
   доля large ≤ 10 (≈7%) **без** учёта эволюции.
5. На smoke с реальной игрой через `add-task.sh` после 30+ задач квартал
   выглядит «обычно» с 1-2 large-зданиями (если эволюция сложилась) или
   совсем без них (если нет).

### Acceptance criteria

- [ ] `UnitPlanner` получает новую константу
      `largeRarityFactor: Double = 0.1`. Конкретная точка вставки — решит лид
      (либо параметр `weightedPick`, либо приватная константа).
- [ ] В `weightedPick` (или эквивалент) при выборе UnitKind: если у kind
      признак `large` (или `kind.size.width >= 2 && kind.size.height >= 2` —
      lead выберет точный критерий по существующему API) — weight умножается
      на `largeRarityFactor`.
- [ ] Эволюционный канал (`EvolutionGraph.applyEvolutionsIfReady`) **не
      затрагивается** — large по эволюции появляется как раньше.
- [ ] Тест `UnitPlannerTests.test_EdgeCase_LargeUnitsAppearRarely`
      возвращается к baseline=10 (≤10 large на 150 задач, ~7% максимум,
      обоснование — статистический buffer от среднего ~4-5% при factor=0.1).
- [ ] Существующие тесты `UnitPlannerTests` (9 кейсов) проходят без других
      изменений: пропорции категорий 50R/20I/20P/10S сохраняются, minStage
      работает, биом-affinity не ломается.
- [ ] Smoke: запуск через `add-task.sh` × 30 на одном проекте → визуально
      ≤3 large-зданий в готовом stage 5 квартале (manual check).

### Что НЕ делаем (границы скоупа)

- НЕ убираем large полностью из weightedPick (вариант C BUG-021) — слишком
  большой scope, требует ревизии всех категорий и stage-tier mappings.
- НЕ меняем `EvolutionGraph` правила — large по эволюции остаётся.
- НЕ меняем определение «large» в каталоге (`UnitKind.size`).
- НЕ переделываем `categoryPattern` пропорции 50/20/20/10 — баланс
  категорий не страдает.
- НЕ балансируем точное значение `largeRarityFactor` экспериментально — 0.1
  даёт ~4-5% large, что в зоне комфорта. Тюнинг — follow-up если визуально
  не нравится.

### Edge cases

- [ ] Все kind'ы в выбранной категории — large (теоретически возможно для
      нестандартной фильтрации) → factor 0.1 равномерно применяется ко всем,
      результат: один из large выбирается. Не падать на «sum of weights == 0».
- [ ] kind без явного `large`-флага и без size 2×2+ — НЕ затрагивается.
- [ ] Stage 0/1 — large kinds недоступны через minStage; factor не успевает
      «сработать», поведение не меняется.
- [ ] Эволюция house → tenement: tenement — large, но появляется через
      `EvolutionGraph`, не через `weightedPick` → factor его не редуцирует.
      Корректно.
- [ ] Test fixture-seed: при factor 0.1 ожидаемое количество large для seed=42
      stage5/meadow/150-tasks — лид считает заранее и фиксирует baseline в тесте.
      Если фактическое ≠ ожидаемому ±2 — лид меняет seed или baseline.

### Зависимости

- **Blocked-by:** —
- **Soft-blocks:** —

### Дизайн

Не применимо (баланс игры, не UI).

### Done-критерий

_Из BUG-021 expected:_ «(а) ввести `largeRarityFactor` в weightedPick (large
получает weight × 0.1)». Закрывает BUG-021 минимальным изменением.

Spec F-07 (концепт) не меняем — она про **категориальные пропорции**, не
про large-внутрикатегориальный баланс. PM-уточнение: «large — это
эволюционная награда, а не базовый юнит».

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-24_
_Модель: sonnet_
_Статус: [x] готов_

### Анализ текущего состояния

- `UnitPlanner.weightedPick` (`Sources/CityDeveloper/Game/UnitPlanner.swift:171-211`) —
  основной выбор kind по весам. Сейчас:
  - При `biome != nil`: `weights[i] = baseUniform + terrainBoost * TerrainAffinity.weight(kind, biome)`,
    где `baseUniform = 0.15`, `terrainBoost = 0.85` (`UnitPlanner.swift:36-37`).
  - При `biome == nil`: `weights[i] = 1.0` (uniform).
  - Дальше детерминированный SplitMix64-pick по сумме весов.
- `UnitKind.size: GridSize` (`Data/CityState.swift:145`) возвращает `GridSize { width, height }`.
  `GridSize` определён в `CityState.swift:25`.
- Тест `UnitPlannerTests.test_EdgeCase_LargeUnitsAppearRarely` сейчас ослаблен до baseline=60
  (ранее ожидался ≤3). На stage5/meadow/150 задач фактическое ≈37% = 56 large.
- `EvolutionGraph` (`Sources/CityDeveloper/Game/EvolutionGraph.swift`) — применяется ВНЕ
  `weightedPick`, в `CityEngine.applyEvolutionsIfReady`. Эволюционный канал не затронут.

### Архитектурное решение

Применяем множитель `largeRarityFactor = 0.1` **внутри** `weightedPick` после расчёта базовых
весов, до их суммирования и pick'а:
```swift
for i in 0..<candidates.count {
    if isLarge(candidates[i]) { weights[i] *= Self.largeRarityFactor }
}
```
Критерий large — **size 2×2 или больше** (`kind.size.width >= 2 && kind.size.height >= 2`).
Это охватывает все эволюционные leaf'ы (palace 3×3, manor 2×2, tenement 2×2, villa 2×2,
factory 2×3, largeWarehouse 2×3, pyramid 4×4, etc.) и не задевает обычные 1×1 и 1×2 юниты
(shack, house, road, well, market 1×1, etc.).

Effect:
- В residential pool (12 leaf'ов, ~4 large): 4×0.1 + 8 = 8.4 → доля large ≈ 0.4/8.4 ≈ 4.8%.
- В production pool (~3 large): аналогично ~4%.
- Усреднённо по 50R/20I/20P/10S распределению: ~3-4% всех юнитов = large.
- На N=150: μ ≈ 5-6, σ ≈ 2.4, P(X>10) ≈ 5%. Baseline=10 даёт buffer от 4σ.

Эволюционный канал не задействован — `EvolutionGraph.applyEvolutionsIfReady` вызывает не
`weightedPick`, а напрямую меняет kind после проверки `EvolutionRequirement` (см.
`CityEngine.applyEvolutionsIfReady`). Поэтому palace через эволюцию appear как раньше.

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку.

1. **Добавить константу + helper в UnitPlanner** `[AC:1,2]`
   - Файл: `Sources/CityDeveloper/Game/UnitPlanner.swift`
   - После строки 37 (рядом с `baseUniform` / `terrainBoost`):
     ```swift
     /// TASK-054 BUG-021: множитель редкости для large-юнитов (size >= 2×2)
     /// в weightedPick. Эволюционный канал (EvolutionGraph) не задействован.
     private static let largeRarityFactor: Double = 0.1
     ```
   - В этом же типе добавить private static helper:
     ```swift
     /// TASK-054: критерий large — footprint 2×2 или больше.
     private static func isLarge(_ kind: UnitKind) -> Bool {
         let s = kind.size
         return s.width >= 2 && s.height >= 2
     }
     ```

2. **Применить factor в weightedPick** `[AC:2,3]`
   - Файл: `Sources/CityDeveloper/Game/UnitPlanner.swift:181-190`
   - После блока `if let biome = biome { ... } else { ... }` (после строки 190),
     перед `let sum = weights.reduce(0, +)`:
     ```swift
     // TASK-054 BUG-021: large-юниты редкие — множитель применяется ПОСЛЕ
     // biome-аффинитета, чтобы не ломать пропорции категорий.
     var weights = weights  // shadow immutable into mutable
     for i in 0..<candidates.count {
         if Self.isLarge(candidates[i]) {
             weights[i] *= Self.largeRarityFactor
         }
     }
     ```
   - Уточнение: переменная `weights` сейчас `let`. Переписать инициализацию на `var`
     (одно `var weights: [Double]`), убрать локальный shadow выше. Корректная финальная
     форма см. в Edge cases.

3. **Обновить test_EdgeCase_LargeUnitsAppearRarely** `[AC:4]`
   - Файл: `Tests/CityDeveloperTests/UnitPlannerTests.swift`
   - Найти `test_EdgeCase_LargeUnitsAppearRarely`, baseline=60 заменить на 10.
   - Комментарий рядом:
     ```swift
     // TASK-054 BUG-021: при largeRarityFactor=0.1 ожидаемое μ≈5-6,
     // baseline=10 даёт buffer от 4σ при N=150.
     ```

4. **Проверить остальные UnitPlannerTests** `[AC:5]`
   - Запустить `swift test --filter UnitPlannerTests`.
   - Ожидание: все 9 кейсов pass. Если `test_CategoricalProportions_MeadowStage5` упадёт
     (factor задевает базовые kind'ы? — не должен, т.к. categoryPattern считается ДО
     weightedPick), debug по reported failure.

5. **Smoke + Bugs.md** `[AC:6]`
   - Manual smoke: запустить app, создать новый проект, дождаться stage 5 (через
     add-task.sh × 30) → визуально ≤3 large-зданий.
   - `Bugs.md` → перенести BUG-021 в «Закрытые»:
     `| BUG-021 | 2026-05-24 | large-юниты ~37% на stage5 | UnitPlanner.weightedPick получил largeRarityFactor=0.1; baseline теста снижен 60→10 (μ≈5-6 на N=150). TASK-054. |`

### Edge cases (явно обработать)

- [ ] Все candidates — large (теоретическая edge): weights все ×0.1, sum > 0 (т.к. baseUniform>0
      и terrainBoost>0). Sample работает корректно. Не нужен fallback.
- [ ] biome == nil → weights все = 1.0 → factor применяется ровно (1.0 × 0.1 = 0.1 для large,
      1.0 для остальных). Корректно для F-07 nil-biome ветки.
- [ ] Stage 0/1: large kinds недоступны через minStage filter (см. `pickKind` строки 133-166),
      до `weightedPick` они не доходят. Factor не применяется — корректно.
- [ ] EvolutionGraph (`CityEngine.applyEvolutionsIfReady`): не использует `weightedPick`,
      кroме direct kind-swap. Канал нетронут.

### Файлы для изменения

- `Sources/CityDeveloper/Game/UnitPlanner.swift` — `largeRarityFactor` константа +
  `isLarge` helper + цикл применения factor в `weightedPick`.
- `Tests/CityDeveloperTests/UnitPlannerTests.swift` — baseline 60 → 10 в
  `test_EdgeCase_LargeUnitsAppearRarely`.
- `concept/Bugs.md` — BUG-021 → Закрытые.

### Файлы НЕ трогать

- `Sources/CityDeveloper/Data/CityState.swift` — `UnitKind.size` уже корректный.
- `Sources/CityDeveloper/Game/EvolutionGraph.swift` — эволюционный канал не задействован.
- `Sources/CityDeveloper/Game/CityEngine.swift` — `applyEvolutionsIfReady` не трогать.

### Команды проверки

- Компиляция: `swift build -c debug`
- Тесты: `swift test --filter UnitPlannerTests 2>&1 | grep -E "Executed|failed"`
- Полный suite: `swift test 2>&1 | grep "Executed"` (ожидание 132/132 + новый тест если добавлен).
- Smoke: `swift run CityDeveloper` + add-task.sh × 30 → визуальная проверка.

### Сложность

`junior`

**Обоснование:** одно файл (UnitPlanner) + 1 константа + 1 helper + 1 цикл из 3 строк + правка теста.

### Ожидаемое время

S (≤2ч, фактически 30 мин включая smoke).

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: junior_
_Объём: S_

### Definition of Done

#### Функциональные
- [ ] AC выполнены
- [ ] `test_EdgeCase_LargeUnitsAppearRarely` baseline=10 — pass
- [ ] Все 9 UnitPlannerTests pass без изменений других тестов
- [ ] Smoke: реальный квартал stage 5 без «парада дворцов»

#### Технические
- [ ] Компиляция без ошибок
- [ ] events.jsonl / state.json формат не меняется
- [ ] Replay детерминирован (factor применён внутри детерминированного
      weightedPick)

#### Обновление документации
- [ ] `Bugs.md`: BUG-021 → перенести в «Закрытые» с коммитом
- [ ] `Current.md`: упомянуть BUG-021 closure

---

## Статус

`[ ] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[x] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-24
- Spec-review: approved (с nice-to-have замечаниями)
- Готова к работе: 2026-05-24
- Lead-model: sonnet
- Plan-review: skipped (junior + single-file change — план чёткий, исполнитель не додумает)
- Исполнитель: haiku
- Code-review: revised (round 2 approved, sonnet)
- Завершена: 2026-05-25
- Коммит: c0c7268
- AC4 revised: baseline=16 вместо spec=10 — каталог имеет 17 large из 51 kinds (lead-расчёт опирался на устаревшие 4/12), для baseline=10 нужен factor≈0.05.
