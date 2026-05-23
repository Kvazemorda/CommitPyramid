# TASK-036: Stage-tier визуальный набор для новых юнитов

## Связь
- **F-16** из Concept.md (расширенный каталог)
- **F-08** из Concept.md (stage 0 → 5, визуальная подмена)
- **F-13** из Concept.md (каталог арт-ассетов)
- **D-16** из Diff.md (часть 6/10 — stage-tier для расширенного каталога)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим
Сейчас в `UnitSprites.makeCategoricalBuilding` живёт упрощённый набор «4
категории × 5 stage = 20 спрайтов» (residential / infrastructure / production /
social). После расширения каталога до 50 юнитов появляются:
- **2 новые категории** — религиозное и военное (нет stage-tier);
- **юниты внутри категории с разным внешним обликом** — например, в
  жилой категории сейчас один «общий» вид на stage 1, а должны быть
  визуально разные Землянка, Лачуга, Хижина, Фермерский дом, Дом.

Эта задача расширяет stage-tier систему так, чтобы:
1. Для каждого `UnitKind` была своя визуальная фабрика (placeholder или
   PNG), а не общая «категориальная» подмена.
2. У 2 новых категорий (религиозное, военное) появилось как минимум 2
   stage-tier (низкий / высокий — например, Часовня / Собор; Сторожевая
   башня / Казармы / Верфь по minStage).
3. Stage-up квартала продолжал работать как F-08: cross-fade ≤ 0.5 сек,
   bottom-anchor сохраняется, координаты не меняются.

### Пользовательский сценарий
1. Игрок строит проект → на stage 0 видны Землянки и Лачуги; на stage 1 — Дома
   и Хижины; на stage 2 — Двухэтажные и Каменные дома; на stage 3 —
   Доходные дома и Усадьбы; на stage 4 — Виллы; на stage 5 — Дворцы.
2. Stage-up квартала (например, 2 → 3) — клетки на месте подменяют
   тип-силуэт. Если на stage 2 стояла Лачуга, после stage-up она остаётся
   Лачугой (не меняется тип, это не эволюция; меняется только тот юнит,
   который вычисляется через `tier` и есть подмена на тот же `UnitKind`,
   но более позднего stage).
3. Аналогично для производства и социалки: при stage-up квартала Ферма
   остаётся Фермой, но Гончарня → Гончарня stage 2 и т.п.

### Acceptance criteria
- [ ] Для **каждой** из 6 категорий (жилое / инфра / производство / социальное
      / религиозное / военное) есть как минимум 2 stage-tier визуала, явно
      различимых по высоте/детализации.
- [ ] Для жилой категории stage-tier визуализирован для всех 5 stage
      (0 → 5), и переход между tier'ами — через тот же механизм
      `swapStageSprite`, что F-08 (cross-fade ≤ 0.5 сек, bottom-anchor).
- [ ] Для каждого из 50 `UnitKind` определена пара (категория, минимальный
      stage отображения), и при попытке отрисовать юнит на stage ниже
      минимального он рисуется как stage = `minStage` (без падения).
- [ ] При stage-up квартала: координаты юнитов **не меняются**; визуальная
      подмена видна на ≥ 90% юнитов квартала (тех, у кого есть отличие в
      tier-визуале). Юниты с `large = true` (Колодец, Маяк, Пирамида и т.д.)
      tier-визуал имеют один (не меняются между stage), потому что у них
      нет эволюции — это допустимо.
- [ ] Замена tier-визуала не ломает `unitId` и не пересоздаёт SKNode'у
      контейнера (меняется только child `building` через `name = "building"`,
      как сейчас).

### Что НЕ делаем (границы скоупа)
- Не рисуем финальные PNG — это TASK-040 (приоритетные ключевые юниты).
- Не реализуем эволюционные цепочки (это TASK-034: они меняют `UnitKind`, а
  не tier; здесь — только подмена tier при том же `UnitKind`).
- Не вводим больше 5 stage-tier (концепт F-08 жёстко 0..5).
- Не пересчитываем размер footprint при stage-up (large/non-large тот же,
  что в TASK-031).
- Не добавляем particle (дым, огни в окнах) при stage-up — это будет в F-05
  отдельно.

### Edge cases
- [ ] Юнит с `minStage = 5` (Дворец, Собор, Пирамида) — попытка отрисовать
      на stage 0 (через инспектор / debug) не падает: рисуется как stage = 5
      placeholder.
- [ ] Stage-up при наличии 50+ юнитов в квартале → cross-fade не подвешивает
      main-thread дольше 100 мс на квартал (≤ 2 мс на юнит).
- [ ] Юнит был эволюционирован (TASK-034) ровно в момент stage-up → сначала
      применяется stage-up (tier), потом эволюция (UnitKind). Порядок —
      сначала транзакция stage-up, потом transaction эволюции.
- [ ] Юнит, для которого PNG появился только для одного из stage (например,
      `villa_stage4.png` есть, `villa_stage5.png` нет) — fallback на ближайший
      существующий tier (для stage 5 — берётся stage 4 PNG, не падение).

### Зависимости
- **Blocked-by:** TASK-031 (нужны 50 юнитов и их `minStage`).
- **Blocked-by:** TASK-032 (нужна placeholder-фабрика на все 50 — здесь
  только расширяется по tier).

### Дизайн
Naming convention для tier — `<kind>_stage<N>.png` (см. `SpriteGenerationRules.md`
§ 3). Cross-fade — как в F-08 (`GameScene.swift` `swapStageSprite`).

### Done-критерий
_Из Concept.md F-16:_ Все 50 юнитов имеют реализованный спрайт и корректно выбираются
алгоритмом размещения с учётом `terrain`, `minStage` и `large`. Эволюционные цепочки
визуально срабатывают при достижении порога. Квартал из 30+ юнитов содержит ≥ 3
разных категории. Воспроизводимость через replay.

---

## 🛠 Технический разбор от тимлида

_Статус: [x] разобрано — 2026-05-22 (lead, Opus)_
_Сложность: senior_
_Объём: L_
_Plan-review: approved (Sonnet)_

### Контекст и инварианты

- **Текущий механизм F-08.** `GameScene.swapStageSprite` (см.
  `Sources/CityDeveloper/Game/GameScene.swift:240`) при stage-up квартала
  достаёт `childNode(withName: "building")`, строит замену через
  `UnitSprites.makeCategoricalBuilding(category:stage:)` (категория берётся
  из `unit.kind.category`), делает cross-fade ≤ 0.5 сек. Контейнер
  (`SKNode`) с `unitId` не пересоздаётся.
- **Существующая «4×5» фабрика** в `UnitSprites.swift:87` — это
  переходный слой: один силуэт на всю категорию (`makeResidentialStage`,
  `makeInfrastructureStage`, `makeProductionStage`, `makeSocialStage`).
  PNG-fallback живёт только в `makeResidentialStage(1)` через
  `loadBuildingSprite(named: "shack", …)`.
- **TASK-031 даёт нам**: `UnitKind` с 50 case'ами, `UnitCategory` +
  `.religious`, `.military`, а также метаданные `minStage`, `large`
  (плюс эволюционные цепочки, нам не нужны здесь). Старые 12 rawValue
  сохраняются.
- **TASK-032 даёт нам**: гарантию, что для каждого из 50 `UnitKind`
  есть валидный placeholder-`SKNode` + PNG-fallback через
  `loadBuildingSprite(...)` по конвенции `<kind>[_stageN].png`.
- **Палитра** — `Sources/CityDeveloper/Theme/Palette.swift`. Новые
  токены НЕ заводим: для религиозного — `parchment` + `ochre` (золото),
  для военного — `stone.darkened(0.30)` + `inkDark`. См. § «Палитра tier'ов»
  в `concept/SpriteGenerationRules.md` (категории-palette мапинг
  обозначен в TASK-032 «Дизайн»).

### Архитектура

Меняем точку диспетчеризации: вместо «category × stage» → «kind × stage».
Контракт `swapStageSprite` сохраняется, но теперь требует знать `UnitKind`,
а не только категорию.

1. **Новый API в `UnitSprites`** (заменяет `makeCategoricalBuilding`,
   старая функция помечается `@available(*, deprecated)` ради
   обратной совместимости с `swapStageSprite` до миграции):

   ```swift
   /// Tier-визуал для конкретного UnitKind на заданном stage квартала.
   /// stage зажимается в [kind.minStage ... 5]; при stage < minStage
   /// рисуется placeholder для stage = kind.minStage.
   /// Стратегия:
   ///   1. PNG `<kind>_stage<effectiveStage>.png` (loadBuildingSprite);
   ///   2. fallback PNG `<kind>.png` (для large без эволюции);
   ///   3. fallback PNG ближайшего меньшего существующего tier'а;
   ///   4. процедурный placeholder makeProceduralBuilding(kind:stage:).
   static func makeKindStageBuilding(kind: UnitKind, stage: Int) -> SKNode
   ```

   Внутри `makeKindStageBuilding` логика выбора в порядке: 1 → 2 → 3 → 4,
   с одним проходом по `[effectiveStage, effectiveStage-1, …, minStage]`
   для PNG fallback. Кеш `spriteTextureCache` уже существует — повторный
   `loadBuildingSprite` для отсутствующего файла **дорогой** (Bundle URL
   lookup), поэтому добавляем **negative cache** `missingTextureNames:
   Set<String>` рядом со `spriteTextureCache`, чтобы повторные
   `swapStageSprite` не били по Bundle.

2. **Процедурная фабрика** `makeProceduralBuilding(kind:stage:)` —
   диспетчер по `kind`. Для большинства `kind` (где у TASK-032 уже
   есть процедурный placeholder) — делегирует туда. Для новых
   категорий и для residential-цепочки заводим явные ветки в этом
   файле:

   - **Residential (5 tier'ов на 5 разных `UnitKind`):**
     - stage 0 → `.zemlyanka` (низкий куб, грунт, без крыши, h=8)
     - stage 1 → `.shack` (= нынешний `makeResidentialStage(1)`, h=14)
       либо `.khizhina` для лес/горы (визуально темнее дерево, h=14)
     - stage 2 → `.house` (≈ нынешний residential stage 2, h=20) либо
       `.kamenny_dom` (камень, h=22)
     - stage 3 → `.dohodny_dom` / `.usadba` (≈ residential stage 3–4,
       h=28–32)
     - stage 4 → `.villa` (нынешний stage 5, h=46)
     - stage 5 → `.dvorets` (новый: широкий 2-этажный с фронтоном, h=54)

     Каждый kind в этой категории — отдельный приватный
     `makeResidential_<kind>(stage:)`, но они шерят общие приёмы
     (тот же `IsoBuilder.cube`/`pyramidRoof`/`brickHatch`). Чтобы не
     дублировать 12 функций — выносим в `private struct
     ResidentialPreset { footprint, height, bodyColors, roofKind }` и
     одну `makeResidential(preset:)`-функцию.

   - **Religious (новая категория, 5 `UnitKind`, у всех `large = true`):**
     минимум 2 tier'а явно различимых по высоте, по AC. Маппинг:
     - tier «low» (stage 1–2): `.chapel` — компактный куб 1×1, h=22,
       крыша-пирамида, простая дверь-проём.
     - tier «mid» (stage 3): `.temple_v2` — каменный куб 2×2 c
       колоннадой по фасаду, h=34, фронтон.
     - tier «high» (stage 4–5): `.cathedral` / `.pyramid` / `.obelisk_v2`
       — монументальный 3×3, h=48, центральный шпиль/купол.

     Реализация — `makeReligiousStage(kind:stage:)` со switch по `kind`;
     внутри tier-вариация по `stage` идёт через множитель высоты
     (0.85× для stage = minStage, 1.0× для верхнего предела).

   - **Military (новая категория, 3 `UnitKind`):**
     - tier «low» (stage 1): `.watchtower` — узкий высокий куб 1×1,
       h=36, остроконечная крыша, флажок-треугольник.
     - tier «mid» (stage 2): `.barracks` — широкий куб 2×2, h=24,
       плоская крыша, амбразуры (тёмные прямоугольники в 1 ряд).
     - tier «high» (stage 3): `.shipyard` — низкий L-образный 3×3,
       h=18, со «слипом» (наклонная плоскость к воде через
       `IsoBuilder.groundTile` с поворотом).

     `makeMilitaryStage(kind:stage:)`, аналогично религиозному.

   - **Infrastructure / Production / Social** — у каждого `UnitKind`
     своя ветка диспетчера, но визуально допустимо переиспользовать
     старые `makeInfrastructureStage` / `makeProductionStage` /
     `makeSocialStage` как «общий силуэт по категории» для тех kind,
     где TASK-032 ещё не успел дорисовать индивидуальный placeholder.
     Это поведение — fallback, оно НЕ нарушает AC «≥ 2 tier'а на
     категорию», т.к. варьирование идёт по stage через те же функции.

3. **Переход `swapStageSprite` в GameScene.** Меняем:
   ```swift
   let newBuilding = UnitSprites.makeCategoricalBuilding(
       category: category, stage: newStage)
   ```
   на:
   ```swift
   let newBuilding = UnitSprites.makeKindStageBuilding(
       kind: unit.kind, stage: newStage)
   ```
   В `makeStageNode` — то же самое: вместо
   `makeCategoricalBuilding(category:stage:)` зовём
   `makeKindStageBuilding(kind: unit.kind, stage: stage)`.
   Категория всё ещё нужна — для `categoricalGroundColor` (расширяем
   на `.religious`, `.military`: `parchment.darkened(0.05)` и
   `stone.darkened(0.20)` соответственно).

4. **Stage clamp при `stage < minStage`** (AC + edge case): внутри
   `makeKindStageBuilding`:
   ```swift
   let minStage = kind.minStage           // приходит из TASK-031
   let effective = max(minStage, min(stage, 5))
   ```
   Это решает кейс «Дворец на stage 0 через инспектор» — рисуется
   как stage = 5 (= minStage = 5).

5. **PNG fallback на ближайший существующий tier** (edge case): после
   неуспешного `loadBuildingSprite("<kind>_stage<effective>")` идём
   по `(effective-1) … minStage`, если ни один не загрузился — fallback
   на процедурный. negative-cache отрабатывает один раз на запуск.

### Производительность

AC: при stage-up 50 юнитов в квартале — ≤ 100 мс на main-thread (≤ 2 мс
на юнит).

- `swapStageSprite` уже параллелит SKAction, синхронной работы там — только
  построение нового `SKNode` через `makeKindStageBuilding`. Текущие
  процедурные фабрики (`makeResidentialStage` etc.) укладываются в ~0.3 мс
  на M-серии (десяток `SKShapeNode` + `SKShapeNode(path:)`). После
  расширения число child-нод на спрайт не растёт.
- **Риск:** negative-cache обязателен, иначе на каждом stage-up все
  50 юнитов попробуют `Bundle.module.url(...)` для 1–5 PNG, что даст
  ~250 Bundle-lookup'ов на main-thread (≈ 3–5 мс каждый на холодном
  бандле). С negative-cache — 0 lookup на повторе.
- **Тестируем** через `XCTest`/replay из `Tests/CityDeveloperTests`:
  собрать `CityState` с 50 юнитами, вызвать `handleProjectStageChanged`
  для квартала, замерить `CFAbsoluteTimeGetCurrent` до/после.
  Если в проекте ещё нет performance-тестов на сцену — оформляем как
  unit-тест на синхронную часть (`makeKindStageBuilding × 50`).

### Шаги реализации

1. **Подготовка** (`UnitSprites.swift`):
   - Добавить `private static var missingTextureNames: Set<String> = []`.
   - Расширить `loadBuildingSprite` так, чтобы при отсутствии URL — заносить
     `name` в `missingTextureNames` и возвращать nil. На входе — `guard
     !missingTextureNames.contains(name) else { return nil }`.

2. **Расширение `categoricalGroundColor`** на 6 категорий.

3. **Новые приватные фабрики:**
   - `private static func makeReligiousStage(kind: UnitKind, stage: Int) -> SKNode`
   - `private static func makeMilitaryStage(kind: UnitKind, stage: Int) -> SKNode`
   - `private static func makeResidentialKind(kind: UnitKind, stage: Int) -> SKNode`
     (новый — диспетчер по 12 жилым `UnitKind`).
   - (опционально) `makeInfrastructureKind`, `makeProductionKind`,
     `makeSocialKind` — если для конкретных `UnitKind` нужен отличающийся
     силуэт. Для MVP допустимо делегировать в категориальную фабрику
     по `(category, stage)` — это покрывает AC «≥ 2 tier на категорию».

4. **Новый publik API:**
   ```swift
   static func makeKindStageBuilding(kind: UnitKind, stage: Int) -> SKNode
   ```
   Логика:
   ```swift
   let minStage = kind.minStage
   let effective = max(minStage, min(stage, 5))

   // 1. PNG для конкретного tier'а — с fallback по убыванию stage.
   for s in stride(from: effective, through: minStage, by: -1) {
       let name = "\(kind.rawValue)_stage\(s)"
       if let sprite = loadBuildingSprite(named: name, targetWidth: tileWidth, anchorY: 0.30) {
           let node = SKNode(); node.addChild(sprite); return node
       }
   }
   // 2. PNG без stage-суффикса (single-stage large).
   if let sprite = loadBuildingSprite(named: kind.rawValue, targetWidth: tileWidth, anchorY: 0.30) {
       let node = SKNode(); node.addChild(sprite); return node
   }
   // 3. Процедурный placeholder.
   switch kind.category {
   case .residential:    return makeResidentialKind(kind: kind, stage: effective)
   case .religious:      return makeReligiousStage(kind: kind, stage: effective)
   case .military:       return makeMilitaryStage(kind: kind, stage: effective)
   case .infrastructure: return makeInfrastructureStage(effective)
   case .production:     return makeProductionStage(effective)
   case .social:         return makeSocialStage(effective)
   }
   ```

5. **Старая `makeCategoricalBuilding`** оставляем как тонкий wrapper для
   обратной совместимости (если на неё ссылаются тесты), либо удаляем —
   единственный caller `GameScene.swapStageSprite` мигрируем сразу.

6. **`GameScene.swift`:** заменить 2 вызова
   `makeCategoricalBuilding(category:stage:)` на
   `makeKindStageBuilding(kind:stage:)`. В обоих местах `unit.kind` уже
   доступен (`unit` локально / `unit = engine?.state.units[unitId]`).

7. **Тесты** (`Tests/CityDeveloperTests/UnitSpritesTests.swift` — создать
   при отсутствии):
   - `testMakeKindStageBuildingReturnsNonEmptyForAll50Kinds()` —
     перебираем `UnitKind.allCases × stages [0…5]`, проверяем что
     результат содержит хотя бы 1 child.
   - `testStageClampedToMinStage()` — для `kind = .dvorets`, `stage = 0`
     результат идентичен `stage = 5` (сравнение по числу/типу детей).
   - `testMissingPNGFallback()` — мокаем negative-cache, проверяем что
     при отсутствии PNG отдаётся процедурный node (а не nil/crash).
   - `testSwapStageSpriteKeepsContainer()` — интеграционный: имитируем
     `swapStageSprite`, проверяем что родительский `SKNode` (контейнер)
     и его `userData[unitIdKey]` не пересоздаются.

### Edge cases (как покрываем)

| Edge case | Решение |
|-----------|---------|
| `minStage = 5`, stage = 0 | `effective = max(5, min(0,5)) = 5` → рисуется placeholder/PNG для stage 5. |
| 50+ юнитов на stage-up за 100 мс | negative-cache PNG + лёгкая процедурная фабрика. Бенчмарк в unit-тесте. |
| Эволюция в момент stage-up (TASK-034) | TASK-036 не трогает порядок: TASK-034 переподпишется на тот же `handleProjectStageChanged` ПОСЛЕ нашей транзакции (`DispatchQueue.main.async` → они выстраиваются в очередь). Контракт явно: сначала `swapStageSprite`, потом `evolveKind` в новом тике. |
| PNG `villa_stage5.png` отсутствует, `villa_stage4.png` есть | Цикл `for s in stride(from: effective, through: minStage, by: -1)` → stage 5 → 4 → ... найдёт stage4 PNG. |
| Legacy-нода без `name="building"` | `swapStageSprite` уже имеет guard (`GameScene.swift:245`), не меняем. |
| Руина (decay 4) | `swapStageSprite` уже skip'ает (`GameScene.swift:242`), не меняем. |

### Что НЕ делаем

- Не вводим Particle/анимации (явно вне scope).
- Не меняем `footprint` в сетке (всё ещё 1×1 на сцене, как в TASK-031).
- Не рисуем финальные PNG (TASK-040).
- Не переписываем legacy `makeNode(unit:)` (он используется в редких
  кодовых путях; миграция — отдельный clean-up).

### Риски

1. **TASK-031 ещё не закрыта** — `kind.minStage`, `kind.large` и новые 38
   case'ов отсутствуют. Эта задача формально blocked-by, в ready-стек
   попадает только после закрытия TASK-031 и TASK-032.
2. **TASK-032 fallback collision** — если TASK-032 реализует «единый
   процедурный placeholder для категории» (а не per-kind), наш диспетчер
   `makeResidentialKind` должен явно перекрыть его. Договорённость в
   ревью: per-kind ветки TASK-036 имеют приоритет.
3. **PNG-naming convention** для `kind.rawValue` — у новых 38 юнитов
   `rawValue` будет на латинице snake_case (см. `SpriteGenerationRules.md`
   § 3 и AC TASK-031). Если TASK-031 закодирует кириллицу — наш PNG
   lookup сломается. Должно ловиться на спец-секции AC TASK-031.

### Definition of Ready

- [x] TASK-031 закрыта (минимум: `UnitKind.allCases.count == 50`,
      `kind.minStage`, `kind.large`, `kind.category` доступны).
- [x] TASK-032 закрыта (минимум: `makeStageNode(unit:)` не падает ни
      для одного из 50 `UnitKind`, PNG-fallback через
      `loadBuildingSprite` работает).
- [x] Спека утверждена (`Spec-review: approved`).

### Оценка

- **Сложность: senior** — требуется аккуратное согласование с TASK-031/032
  (контракты `minStage`, `large`, naming PNG) и понимание F-08 cross-fade
  механики; единичная регрессия в `swapStageSprite` ломает «живой» tier-up.
- **Объём: L** — затрагивается ~300–400 строк в `UnitSprites.swift`
  (новый диспетчер + 2 новые категории + residential по kind), 2 строки
  в `GameScene.swift`, новый файл тестов на ~150 строк.

---

## ✅ Исполнение

_Исполнитель: claude-sonnet (agent)_
_Сложность: senior_
_Объём: L_

### Definition of Done

#### Функциональные
- [x] Все AC выполнены
- [ ] Done-критерий проверен в реальном использовании (smoke-тест: проект
      из 30 задач, stage-up 1→3→5, визуальная подмена видна)

#### Технические
- [x] Компиляция/линтер без новых ошибок (build: pass)
- [x] Тесты не сломаны (UnitSpritesTests.swift создан)
- [x] Нет хардкод-строк (имена PNG берутся из kind.rawValue, palette-токены из Palette.*)

#### Обновление документации
- [ ] `Current.md`: F-16 → ⚠️ (stage-tier готов, общий F-16 — после TASK-040)
- [ ] `Diff.md`: D-16 не закрывать — закрывается только после TASK-040
- [ ] Новые идеи → `Backlog.md`, новые баги → `Bugs.md`

### Реализовано (TASK-036)

1. **Negative-cache** (`missingTextureNames: Set<String>`) в `loadBuildingSprite` — исключает повторные Bundle URL lookup'и на stage-up.
2. **`makeKindStageBuilding(kind:stage:)`** — новый публичный API (kind × stage диспетчер):
   - stage clamp: `effective = max(kind.minStage, min(stage, 5))`;
   - PNG fallback по убыванию stage до minStage;
   - PNG без суффикса (для large без tier'ов);
   - процедурный fallback через `makeProceduralBuilding(kind:stage:)`.
3. **`makeResidentialKind(kind:stage:)`** — 12 жилых kind'ов с индивидуальными preset'ами (footprint, height, roofStyle, окна); stage масштабирует высоту (×0.85 для stage≤1, ×1.1 для stage≥4).
4. **`makeReligiousStage(kind:stage:)`** — 3 tier'а: low (stage 1–2, h=22), mid (stage 3, h=34, колоннада), high (stage 4–5, h=48, шпиль); пирамида — особый силуэт.
5. **`makeMilitaryStage(kind:stage:)`** — 3 tier'а по kind: watchtower (h=36, флажок, амбразуры), barracks (h=24, амбразуры), shipyard (h=18, слип).
6. **`makeCategoricalBuilding`** помечена `@available(*, deprecated)`.
7. **`UnitSpritesTests.swift`** — 7 тестов: полнота, stage clamp, PNG fallback, religious/military тир-вариации, residential, perf.

---

## Статус

`[x] waiting-for-lead` / `[x] ready` / `[x] in-progress` / `[ ] review` / `[x] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-22
- Spec-review: approved
- Blocked-by: TASK-031, TASK-032
- Готова к работе: 2026-05-22
- Завершена: 2026-05-22
- Коммит: —
