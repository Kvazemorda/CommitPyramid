# TASK-052: z-sort с учётом footprint — дальние юниты не перекрывают ближние

## Связь
- **F-02** из Concept.md (изометрический рендер)
- **F-13** из Concept.md (каталог арт-ассетов)
- **BUG-019** из Bugs.md (P1)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-24_

### Что хотим

Дальние юниты и дорожные клетки не должны визуально перекрывать ближние.
Изометрический y-sort должен учитывать **дальний угол footprint'а** (а не
только origin), и road-cell'ы должны рисоваться **под** зданиями при равном
y-score. После TASK-044 (анкер крупных юнитов сместился) формула zPosition
осталась прежней — отсюда регресс. Фикс закрывает BUG-019 и даёт property-тест
как регресс-щит.

### Пользовательский сценарий

1. Игрок видит два соседних квартала вдоль одной диагонали (например,
   квартал A в `(10, 10)` и квартал B в `(15, 15)`).
2. Дальний дом 2×2 в квартале B **не** перекрывает крышу/угол ближнего
   1×1 дома в квартале A.
3. На road-полотне магистрали: дальняя дорога **не** рисуется поверх
   ближнего здания — она остаётся «полом» под зданиями.
4. После TASK-044 крупные юниты (palace, pyramid 4×4) по-прежнему ведут
   себя корректно: их «дальний угол» учитывается, а не origin.
5. Property-тест на каждом запуске `swift test` проверяет инварианты для
   набора фикстурных пар юнитов (1×1+1×1, 1×1+2×2, 2×2+2×2, road+building).

### Acceptance criteria

- [ ] При размещении или sprite-swap юнита `zPosition` считается по
      **дальнему углу footprint'а** (`max(cell.x + cell.y)` среди
      `unit.cells`), а не только по `unit.position`.
- [ ] Road-клетки получают zPosition в **отдельной подгруппе layer-z**:
      road < buildings < citizens (например, road-base = 1000 + (x+y),
      buildings-base = 2000 + maxFarCorner, citizens-base = 3000 + y).
      Конкретные base-константы — решит lead, но **строгий порядок:
      road < buildings < citizens** обязателен.
- [ ] Дальний юнит / road-клетка **не перекрывает** ближний у пары
      `(a, b)`, где `farCorner(a) < farCorner(b)`. Property-инвариант:
      для любых двух юнитов A и B одной layer-группы, если
      `(A.maxX + A.maxY) < (B.maxX + B.maxY)`, то
      `A.node.zPosition < B.node.zPosition`.
- [ ] Property-тест `ZSortInvariantsTests` с фикстурой:
      - `test_1x1Plus1x1_FarUnitGetsHigherZ`,
      - `test_1x1Plus2x2_FarUnitGetsHigherZ_LargeAnchorFix`
        (регресс щит для TASK-044),
      - `test_2x2Plus2x2_FarUnitGetsHigherZ`,
      - `test_RoadBelowBuildingAtSameXPlusY` (layer-z порядок),
      - `test_CitizenAboveBuildingAtSameXPlusY` (layer-z порядок).
- [ ] При sprite-swap (stage-up, evolution) новый node наследует
      пересчитанный zPosition — не остаётся старая формула.

### Что НЕ делаем (границы скоупа)

- НЕ переписываем алгоритм размещения (это про z-сортировку, не про
  positioning).
- НЕ меняем формат `events.jsonl` / state.json.
- НЕ добавляем 3D depth-buffer и подобные тяжёлые механики — это
  чистая 2D y-sort коррекция.
- НЕ трогаем тайл-карту земли (SKTileMapNode сам управляет z для
  base-слоя).

### Edge cases

- [ ] Юнит с footprint 1×1 — `maxFarCorner == position.x + position.y`,
      поведение совпадает с текущим (regression-free для маленьких юнитов).
- [ ] Юнит с footprint 4×4 (pyramid, palace) — `maxFarCorner` сильно
      смещён вниз/вправо относительно position; ближний 1×1 в позиции
      `(palace.x + 2, palace.y + 2)` должен оказаться **под** palace
      (он попадает внутрь footprint'а или рядом — z-formula покрывает).
- [ ] Соседние road-клетки и building на одной диагонали — layer-z база
      гарантирует road < building, даже если их `x+y` одинаковые.
- [ ] Юнит с decay-overlay — overlay рисуется поверх юнита (z +1) —
      пересчёт zPosition не должен ломать overlay-инвариант.
- [ ] Citizens (waypoint random walk) — двигаются непрерывно, их z
      пересчитывается каждый tick по их `y` (citizens-base + worldY);
      должны оставаться поверх buildings даже когда близко.
- [ ] Сцена с 500+ юнитами — расчёт maxFarCorner per-юнит требует
      ≤ 16 операций (для 4×4 footprint'а) — производительность OK.

### Зависимости

- **Blocked-by:** —
- **Soft-blocks:** —

### Дизайн

Не применимо (визуальная корректировка, не UI).

### Done-критерий

_Из BUG-019 expected:_ «Пересчитать `zPosition` по дальнему углу
footprint'а (max `x+y` среди cells) + явная подгруппа layer-z для
road < buildings < citizens; добавить регресс-тест на пару юнитов
(1×1 и 2×2 соседних)».

Закрывает BUG-019. Property-тест — постоянный регресс-щит на случай
будущих правок sprite-anchor.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-24_
_Модель: sonnet_
_Статус: [x] готов_

### Анализ текущего состояния

Текущие места установки zPosition в `Sources/CityDeveloper/Game/GameScene.swift`:

| Источник | Формула | Назначение |
|----------|---------|------------|
| `drawUnit` (`:364`) | `z = -(position.x + position.y + size.width + size.height - 2)` | **Все** unit-юниты, включая road-кварталы |
| `drawRoadCells` (`:718`) | `z = -(cell.x + cell.y) - 0.5` | Магистраль (highway road) |
| `CitizenManager` (`:164/201/238/269`) | `z = -(target.x + target.y) + 0.5` | Жители (waypoint walk) |
| `bg` (`:98`) | `-2000` | Фон |
| `dustNode` (`:310`) | `5000` | Эффекты при создании квартала |
| `outline` (`:473`) | `9998` | Outline |
| Marker container (`:751`) | `9999` | District marker |
| Template silhouette (`:764`) | `5000` | TASK-051 preview |

**Главный bug**: формула `drawUnit` единая для **всех** kind'ов. Road-юнит (kind == .road,
size 1×1) и building 1×1 на той же координате `(x,y)` получают **идентичный** z =
`-(x+y+1+1-2) = -(x+y)`. Drawing order между ними undefined — иногда road рисуется поверх
building. Это и есть основной BUG-019.

Дополнительная корректность far-corner: формула уже учитывает `w + h - 2` — это и есть
`(w-1) + (h-1)`, т.е. смещение до дальнего угла. Для прямоугольного footprint'а это
эквивалентно `max(cell.x + cell.y for cell in footprint)`. **Формула far-corner уже
корректна для прямоугольных юнитов** — не меняем.

Связанные модули:
- `Sources/CityDeveloper/Data/CityState.swift:145` — `UnitKind.size: GridSize` (прямоугольный).
- `Sources/CityDeveloper/Game/CitizenManager.swift:164/201/238/269` — citizens уже на `+0.5`.
- `Tests/CityDeveloperTests/` — есть `UnitPlannerTests` (placement), нет
  `ZSortInvariantsTests` (нужно создать).

### Архитектурное решение

Минимально invasive фикс — **explicit layer offsets для road-kind units**.

Новая формула в `drawUnit`:
```swift
let farSum = unit.position.x + unit.position.y + gridSize.width + gridSize.height - 2
let layerOffset: CGFloat = unit.kind == .road ? -0.5 : 0.0
node.zPosition = -CGFloat(farSum) + layerOffset
```

Это даёт:
- Road-kind unit at (10,10) 1×1: z = -(20) + (-0.5) = -20.5.
- Building 1×1 at (10,10): z = -20.
- Building -20 > Road -20.5 → building drawn ON TOP. Bug fixed.

Для citizens — формула в `CitizenManager` уже корректна (+0.5) и не меняется.

Для магистрали — `drawRoadCells:718` уже использует -0.5 offset, не трогаем.

**Layer-z иерархия после фикса:**
```
Road kind units / магистраль:  z = -(farSum) - 0.5  ← back layer
Buildings:                      z = -(farSum)        ← middle layer
Citizens:                       z = -(walkSum) + 0.5 ← front layer
```

Между ними гарантированный gap = 0.5 (это >> floating-point precision).

Property-инвариант для тестов:
- Same-layer ordering: for units A, B of same layer, `farSum(A) > farSum(B) → A.z < B.z`
  (negation convention: больший farSum = «дальше» → меньшее z → drawn first).
- Cross-layer ordering: `road.z < building.z < citizen.z` для одинаковых farSum.

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку.

1. **Добавить road layer-offset в drawUnit** `[AC:1,2,3]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift:362-365`
   - Заменить блок:
     ```swift
     // z-sort: lower-front corner = (x + y + (w-1) + (h-1)); negate for painter's order.
     node.zPosition = -CGFloat(unit.position.x + unit.position.y + gridSize.width + gridSize.height - 2)
     ```
     на:
     ```swift
     // z-sort: far corner = (x + y + (w-1) + (h-1)). Negate for painter's order.
     // TASK-052 BUG-019: road kind units получают -0.5 offset, чтобы оставаться под
     // buildings того же far-sum (layer-z hierarchy: road < buildings < citizens).
     let farSum = unit.position.x + unit.position.y + gridSize.width + gridSize.height - 2
     let layerOffset: CGFloat = (unit.kind == .road) ? -0.5 : 0.0
     node.zPosition = -CGFloat(farSum) + layerOffset
     ```

2. **Создать `ZSortInvariantsTests.swift`** `[AC:3,4]`
   - Файл (новый): `Tests/CityDeveloperTests/ZSortInvariantsTests.swift`
   - Подход: тестируем **формулу z**, а не реальную SpriteKit-сцену.
     Извлекаем формулу в небольшой pure-helper или копируем её в тестовый код
     (один источник истины — формула, дублирование допустимо для одной строки).
   - Скелет:
     ```swift
     import XCTest
     @testable import CommitPyramid  // или имя модуля

     final class ZSortInvariantsTests: XCTestCase {
         // Voспроизводит формулу из GameScene.drawUnit (TASK-052)
         private func zPositionForUnit(_ kind: UnitKind, position: GridPoint) -> Double {
             let s = kind.size
             let farSum = position.x + position.y + s.width + s.height - 2
             let layerOffset: Double = (kind == .road) ? -0.5 : 0.0
             return -Double(farSum) + layerOffset
         }

         func test_1x1Plus1x1_FarUnitGetsHigherZBackward() {
             // Far building (higher x+y) gets MORE NEGATIVE z → drawn first.
             let near = zPositionForUnit(.house, position: GridPoint(x: 5, y: 5))    // 1×1, farSum=10
             let far  = zPositionForUnit(.house, position: GridPoint(x: 10, y: 10))  // 1×1, farSum=20
             XCTAssertGreaterThan(near, far,
                 "Ближний 1×1 должен иметь больший zPosition чем дальний 1×1")
         }

         func test_1x1Plus2x2_FarUnitGetsHigherZ_LargeAnchorFix() {
             // 2×2 at (8,8) covers (8..9, 8..9) → far corner (9,9) → farSum=18.
             // 1×1 at (5,5) → farSum=10. 2×2 should be "further" → lower z.
             let small = zPositionForUnit(.house, position: GridPoint(x: 5, y: 5))   // farSum=10
             let large = zPositionForUnit(.manor, position: GridPoint(x: 8, y: 8))   // 2×2, farSum=18
             XCTAssertGreaterThan(small, large)
         }

         func test_2x2Plus2x2_FarUnitGetsHigherZ() {
             let near = zPositionForUnit(.manor, position: GridPoint(x: 5, y: 5))    // farSum=10
             let far  = zPositionForUnit(.manor, position: GridPoint(x: 10, y: 10))  // farSum=22
             XCTAssertGreaterThan(near, far)
         }

         func test_RoadBelowBuildingAtSameFarSum() {
             // At same far-sum, road should have STRICTLY LOWER z (drawn first).
             let road    = zPositionForUnit(.road, position: GridPoint(x: 10, y: 10))  // farSum=20, offset=-0.5 → -20.5
             let building = zPositionForUnit(.house, position: GridPoint(x: 10, y: 10)) // farSum=20, offset=0 → -20
             XCTAssertLessThan(road, building)
         }

         func test_FarRoadStillBelowNearBuilding() {
             // Кросс-layer: дальняя road НЕ должна перекрывать ближнее building.
             let farRoad   = zPositionForUnit(.road, position: GridPoint(x: 15, y: 15))   // -30.5
             let nearBldg  = zPositionForUnit(.house, position: GridPoint(x: 5, y: 5))    // -10
             XCTAssertLessThan(farRoad, nearBldg)
         }
     }
     ```
   - Проверка: `swift test --filter ZSortInvariantsTests` → 5/5 PASS.

3. **Проверить, что sprite-swap (stage-up, evolution) использует новый формат** `[AC:5]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift`
   - Найти все места, где node.zPosition присваивается для unit-нодов (помимо drawUnit).
     Существующие: только `drawUnit:364` (stage swap идёт через `swapStageSprite` —
     найти его и убедиться, что он либо переиспользует `drawUnit`, либо обновляет z по
     той же формуле).
   - Если `swapStageSprite` (если есть) пишет z отдельно — добавить туда тот же
     layerOffset механизм.

4. **Сборка + тесты** `[AC:1-5]`
   - `swift build -c debug`
   - `swift test 2>&1 | grep "Executed"` — ожидание 137/137 PASS (132 текущих + 5 новых).

5. **Manual smoke + Bugs.md** `[AC:3,6]`
   - Smoke: запустить app, через add-task.sh создать 2 проекта вдоль диагонали (например
     "ProjectA"×8 для stage 2 с tenement 2×2, "ProjectB" с дорогой по соседству). Убедиться,
     что дальняя road не перекрывает ближний building visually.
   - `Bugs.md` → перенести BUG-019 в «Закрытые»:
     `| BUG-019 | 2026-05-24 | z-sort дальние юниты перекрывают ближние | Layer-z иерархия в drawUnit: road получает -0.5 offset под buildings. Property-тесты ZSortInvariantsTests (5 кейсов) — регресс-щит. TASK-052. |`

### Edge cases (явно обработать)

- [ ] Unit с size 1×1 — formula `farSum = x+y+0` (после w+h-2=0). Поведение совпадает с
      текущим для не-road. Для road — добавляется -0.5 offset. (`GameScene.swift:364`)
- [ ] Unit с size 4×4 (pyramid): farSum = `x+y+6`. Ближайший 1×1 на (x+3, y+3) имеет
      farSum = (x+3)+(y+3) = x+y+6 → совпадает! → undefined ordering. Это уже текущее
      поведение, не регресс. Но если pyramid позиция (10,10), его cells (10..13, 10..13),
      и building 1×1 на (13,13) находится **поверх угла pyramid'а** — корректно, они занимают
      ту же визуальную точку. Если building 1×1 на (14,14) — far + 1 → z должен быть BELOW pyramid (ну ниже = более негативный = drawn first = back). 14+14=28, pyramid 10+10+6=26, building z=-28, pyramid z=-26. -28 < -26 → building drawn first (back) → pyramid on top. ✅
- [ ] Citizens (`CitizenManager.swift:164/201/238/269`) — `z = -(target.x + target.y) + 0.5`.
      После фикса road получает -0.5, citizens +0.5, building 0. Strict ordering сохраняется.
- [ ] Decay overlay (если есть) — TODO: проверить grep'ом, есть ли overlay с z = unit.z + 1.
      Не должно ломаться (наш offset -0.5 << 1).
- [ ] Магистраль через `drawRoadCells:718` — её формула `-(cell.x+cell.y)-0.5` совпадает с
      road-юнитом 1×1 — корректно (магистраль и юнит-дорога на одной layer'е).
- [ ] Производительность: per-unit + 1 проверка `unit.kind == .road` — O(1), 500 юнитов = 500
      проверок. Не задевает FPS.

### Файлы для изменения

- `Sources/CityDeveloper/Game/GameScene.swift` — `drawUnit:362-365` (layer-offset).
- `Tests/CityDeveloperTests/ZSortInvariantsTests.swift` — НОВЫЙ (5 тестов).
- `concept/Bugs.md` — BUG-019 → Закрытые.

### Файлы НЕ трогать

- `Sources/CityDeveloper/Game/CitizenManager.swift` — citizens уже на +0.5, не меняем.
- `Sources/CityDeveloper/Data/CityState.swift` — модель GridSize не меняется.
- `Sources/CityDeveloper/Game/UnitSprites.swift` — sprite generation отдельно.

### Команды проверки

- Компиляция: `swift build -c debug`
- Тесты: `swift test --filter ZSortInvariantsTests`
- Полный suite: `swift test 2>&1 | grep "Executed"` → 137/137 PASS (если 132 текущих + 5 новых).
- Smoke: `swift run CityDeveloper` + создать 2 квартала через add-task.sh → визуально нет
  road-over-building артефактов.

### Сложность

`junior`

**Обоснование:** одно-строчное изменение в GameScene + один новый файл с 5 простыми
формулами-тестами. Единственная архитектурная мысль (layer offset) уже принята в плане.

### Ожидаемое время

S (≤2ч, фактически 30-45 мин).

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: junior_
_Объём: S_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Property-тесты проходят: 5 кейсов в `ZSortInvariantsTests`
- [ ] Manual visual smoke: два соседних квартала, один с pyramid 4×4 —
      pyramid не перекрывается соседним 1×1

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Тесты не сломаны
- [ ] events.jsonl / state.json формат не меняется
- [ ] Производительность: 500 юнитов рендерятся без падения FPS (smoke)

#### Обновление документации
- [ ] `Bugs.md`: BUG-019 → перенести в «Закрытые» с указанием коммита
- [ ] `Current.md`: упомянуть BUG-019 closure в текущем прогоне

---

## Статус

`[ ] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[x] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-24
- Spec-review: approved
- Готова к работе: 2026-05-24
- Lead-model: sonnet
- Plan-review: skipped (junior + single-file change + 5 property-тестов формализуют корректность)
- Исполнитель: haiku (junior)
- Code-review: approved (opus, триггер P1)
- Завершена: 2026-05-24
- Коммит: f0e727a
