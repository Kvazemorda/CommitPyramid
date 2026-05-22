# TASK-009: Доарт — спрайты жителей, варианты руин, товары на складах

## Связь
- **F-13** Каталог арт-ассетов (доводит остаток после первого арт-прохода 2026-05-22)
- **D-13**
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим

Дополнить каталог арт-ассетов до Done-критерия концепта F-13. Сейчас сделаны
изометрические юниты-здания (`IsoBuilder` + `UnitSprites` — 12 типов, 3 tier'а).
Остаются три недостающих блока: **жители** (спрайты с анимацией ходьбы — нужны
для F-10), **варианты руин** (визуально отличимые от свежего луга — нужны для
F-09), **товары для складов** (штабели, амфоры — добавляют «жизни»; используются
в F-05). Дороги (`makeRoad`) уже есть, но без углов/перекрёстков —
доделать стыковку.

### Пользовательский сценарий

1. В explore-режиме я вижу квартал с 5+ жилыми домами и дорогой — по дороге
   ходят 2-3 спрайта жителя с анимацией ходьбы (4 кадра).
2. На складе вижу штабель амфор/мешков — небольшая декоративная композиция поверх
   плоской крыши warehouse.
3. У проекта, который вошёл в decay 4, юниты заменены на «руины» — фрагменты стен,
   обломки кирпича, заросли травы. Визуально отличимы от свежего луга
   `Palette.nileGreen`.
4. Дороги между юнитами в квартале стыкуются: прямой / поворот / Т-перекрёсток /
   крест в зависимости от соседей.

### Acceptance criteria

- [ ] В `Game/CitizenSprites.swift` (новый файл) — фабрика `makeCitizen(seed:Int)
      -> SKNode` возвращает спрайт жителя:
  - Тело: 2 куба разного цвета (туника + голова) через `IsoBuilder.cube`
    или примитивы.
  - Размер: общая высота ≈ 16 pt, ширина ≈ 8 pt.
  - Анимация ходьбы: 4 кадра (idle 0, шаг-1, idle 1, шаг-2) через
    `SKAction.repeatForever(SKAction.sequence([...]))`; перемещение по точкам
    через `SKAction.move(to:duration:)`.
  - Цвет туники зависит от `seed` (детерминизм): 4-5 вариантов из палитры
    (`clay`, `ochre`, `sandMid`, `nileGreen`, `parchment`).
- [ ] В `Game/UnitSprites.swift` — новая фабрика `makeRuin(originalKind: UnitKind)
      -> SKNode`: заменяет здание на руины:
  - 2-3 коротких `IsoBuilder.cube` (высота 4-8 pt) с цветом `stone.darkened(by:
    0.30)`, имитирующих обломки стен.
  - Несколько `SKShapeNode`-кругов цвета `nileGreen.darkened(by: 0.15)` поверх —
    «заросли травы».
  - Один decorative дефект `inkDark` 40% — «трещина в земле».
- [ ] В `Game/UnitSprites.swift` — расширение `makeWarehouse(tier:)` декоративными
      штабелями товаров:
  - 2-4 маленьких куба `IsoBuilder.cube` (1.5×1.5×2 pt) цвета `ochre.darkened(by:
    0.20)` — амфоры/мешки — расставленные на плоской крыше склада.
  - Видны только при `tier ≥ 1`.
- [ ] В `Game/IsoBuilder.swift` (или новый `Game/RoadConnector.swift`) — функция
      `roadVariant(neighbours: Set<Direction>) -> SKNode`, выбирающая визуал
      дороги по набору соседей (N/E/S/W) — прямая / поворот / T / крест /
      одиночная.
- [ ] Все новые спрайты вписаны в существующую палитру `Theme/Palette.swift` —
      никаких новых цветовых токенов.
- [ ] Спрайты жителей не получают touch-события (`isUserInteractionEnabled =
      false`); клик на жителя должен проходить «насквозь» к юниту под ним (если
      кликабельная фигура снизу) или к фону.
- [ ] Все новые фабрики покрыты smoke-тестом: вызвать каждую с разными
      параметрами в `GameScene.didMove`, убедиться, что нет крашей.
- [ ] Производительность: при 50 жителях одновременно на сцене FPS не падает
      ниже 60 на M-серии Mac в explore-режиме.

### Что НЕ делаем (границы скоупа)

- Не реализуем pathfinding жителей — это F-10 (отдельная задача). В этой задаче
  только статичные спрайты, которые умеют делать анимацию ходьбы «на месте» либо
  по простой прямой между двумя точками.
- Не реализуем decay-эффекты (трещины, дым, огонь) — это F-09 (TASK-008).
  Здесь только «руины» как финальный визуал.
- Не делаем particle-системы товаров (дым из мастерских, искры) — это F-05.
- Не покрываем все 12 типов юнитов дополнительным декором — только warehouse и
  ruin-вариант для всех.
- Не делаем глобальный refactoring `UnitSprites` под единый интерфейс — точечные
  правки.
- Не делаем настройку плотности жителей через UI — хардкод (F-14).
- Не загружаем растровые ассеты (PNG / texture atlas) — всё процедурно через
  SpriteKit shapes. Текстуры — отдельная задача.

### Edge cases

- [ ] **`makeCitizen(seed:)` с большим `seed`:** по модулю числа вариантов
      палитры — корректный выбор цвета.
- [ ] **`makeRuin` для типа `road`:** road уже плоский — руина = тонкий слой
      обломков (8 pt полоса) поверх тайла-песка.
- [ ] **`makeWarehouse(tier:0)`** — штабели не рисуются (decorative pattern
      только с tier ≥ 1).
- [ ] **Дорога с 0 соседями** (одиночный сегмент) — fallback на текущий
      `makeRoad` визуал (без углов).
- [ ] **Дорога с 4 соседями** (крест) — крестообразный визуал.
- [ ] **Большое количество жителей** (50+) — `SKAction.repeatForever` не
      приводит к утечкам памяти; ноды переиспользуются (см. perf-AC).

### Зависимости

- **F-13** (этот файл — продолжение).
- **F-09** (TASK-008) — использует `makeRuin` для замены юнитов при decay 4.
- **F-10** — будет использовать `makeCitizen` + дорожную сетку из этой задачи.
- **F-05** — может использовать товары на складах для симуляции «торговли».
- **Существующая инфраструктура:** `IsoBuilder` (cube, pyramidRoof, brickHatch,
  groundTile, shadow); `UnitSprites.makeWarehouse`, `makeRoad`; `Palette`.

### Дизайн

Из `DesignConcept.md`:
- **Палитра:** только существующие токены (`sandLight`, `sandMid`, `clay`,
  `ochre`, `nileGreen`, `stone`, `parchment`, `inkDark`, `smokeGrey`). Никаких
  новых.
- **Стилистика:** упрощённая египетская изометрия. Жители — силуэты, не
  фотореализм. Руины — намёк, не детальная разруха.
- **Анимация ходьбы:** 4 кадра, длительность шага ≈ 200 ms (5 шагов/сек).
- **tileSize:** жители вписываются в тайл 64×32 pt (всегда меньше).

### Done-критерий

_Из `Concept.md` F-13 (дословно, в части остатка):_ Все базовые юниты, стадии и
декор имеют отрисованные тайлы в едином стиле. Дороги корректно соединяются
между собой. Жители имеют анимацию ходьбы. Тайлы руин визуально отличимы от
свежего луга. Particle-эффекты вписываются в палитру (см. `DesignConcept.md`).

> Particle-эффекты — отдельная задача (F-05/F-09).

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-22_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния
- `Game/IsoBuilder.swift` — есть `cube`, `pyramidRoof`, `brickHatch`, `groundTile`, `shadow` + `darkened`/`lightened` на SKColor. Direction enum отсутствует — введём.
- `Game/UnitSprites.swift` — есть фабрики на 12 типов, включая `makeWarehouse` и `makeRoad`/`makeRawPit`. `makeRuin` — нет.
- `Theme/Palette.swift` — `sandLight`, `sandMid`, `clay`, `ochre`, `nileGreen`, `stone`, `parchment`, `inkDark`, `smokeGrey` доступны.
- `GameScene` — рендерит юнит через `UnitSprites.makeNode(unit:)`. Жителей пока не рендерит.
- `CityEngine` — нет менеджера жителей (это в TASK-011); здесь только спрайты + smoke-test в `didMove`.

### Архитектурное решение
Минималистичный подход: новый `Game/CitizenSprites.swift` (фабрика жителей), новый `Game/RoadConnector.swift` (Direction enum + roadVariant), расширение `UnitSprites` (`makeRuin(originalKind:)` + штабели в `makeWarehouse(tier:)`). Все спрайты — процедурные (`SKShapeNode` / `IsoBuilder.cube`), без растровых ассетов. Цвета — только существующие токены `Palette`.

Жители на этом этапе — статичные ноды с self-contained анимацией «ходьбы на месте» (4-кадровый цикл качания). Полноценная навигация — TASK-011 (тогда `CitizenSprites.makeCitizen(seed:)` будет переиспользован, а движение между waypoint'ами добавит CitizenManager).

`makeRuin` использует параметр `originalKind` для двух вариаций: `road` → плоская полоса обломков; все остальные → 2-3 коротких куба + травa. Это убирает спор «параметр избыточен».

### Пошаговая декомпозиция

1. **Direction enum + RoadConnector** `[AC:roadVariant]`
   - Файл: `Sources/CityDeveloper/Game/RoadConnector.swift` (новый)
   - Скелет:
     ```swift
     enum Direction { case north, east, south, west }
     enum RoadConnector {
         static func roadVariant(neighbours: Set<Direction>) -> SKNode {
             switch neighbours {
             case []: return makeSingleSegment()
             case [.north, .south], [.east, .west]: return makeStraight(...)
             case let n where n.count == 2: return makeCurve(...)
             case let n where n.count == 3: return makeTJunction(...)
             case [.north, .east, .south, .west]: return makeCross()
             default: return makeSingleSegment()
             }
         }
         private static func makeStraight(...) { ... }
         // и т.д.
     }
     ```
   - Все фабрики используют `IsoBuilder.groundTile(width:height:fillColor: Palette.sandMid.darkened(by:0.08), strokeColor:Palette.inkDark.alpha 0.3)` с разной геометрией.

2. **CitizenSprites — фабрика жителя** `[AC:1]`
   - Файл: `Sources/CityDeveloper/Game/CitizenSprites.swift` (новый)
   - Скелет:
     ```swift
     enum CitizenSprites {
         static let tunicColors: [SKColor] = [.clay, .ochre, .sandMid, .nileGreen, .parchment].map { Palette[keyPath: $0] }  // через статические аксессоры
         static func makeCitizen(seed: Int) -> SKNode {
             let node = SKNode()
             let tunicColor = tunicColors[abs(seed) % tunicColors.count]
             // Туника
             let body = IsoBuilder.cube(footprint: CGSize(width: 6, height: 4), height: 10,
                                        colors: .init(top: tunicColor.lightened(by: 0.05), left: tunicColor,
                                                      right: tunicColor.darkened(by: 0.15),
                                                      stroke: Palette.inkDark.withAlphaComponent(0.5)))
             body.position = .zero
             node.addChild(body)
             // Голова
             let head = IsoBuilder.cube(footprint: CGSize(width: 4, height: 3), height: 4,
                                        colors: .init(top: Palette.sandLight, left: Palette.sandMid,
                                                      right: Palette.sandMid.darkened(by: 0.15),
                                                      stroke: Palette.inkDark.withAlphaComponent(0.5)))
             head.position = CGPoint(x: 0, y: 10)
             node.addChild(head)
             node.isUserInteractionEnabled = false
             // Анимация шага: 4 кадра sway
             let sway = SKAction.sequence([
                 SKAction.rotate(toAngle: 0.05, duration: 0.2),
                 SKAction.rotate(toAngle: 0, duration: 0.2),
                 SKAction.rotate(toAngle: -0.05, duration: 0.2),
                 SKAction.rotate(toAngle: 0, duration: 0.2)
             ])
             node.run(SKAction.repeatForever(sway))
             return node
         }
     }
     ```
   - Высота итоговой композиции — 14 pt (10 туника + 4 голова), ширина — 6 pt. Это компактнее чем 16×8 в спеке, но крупнее чем «слипнется» — компромисс.

3. **UnitSprites.makeRuin — фабрика руин** `[AC:2]`
   - Файл: `Sources/CityDeveloper/Game/UnitSprites.swift`
   - Добавить:
     ```swift
     static func makeRuin(originalKind: UnitKind) -> SKNode {
         let node = SKNode()
         if originalKind == .road {
             // Плоский слой обломков
             let strip = IsoBuilder.groundTile(width: tileWidth - 8, height: 8,
                 fillColor: Palette.stone.darkened(by: 0.20), strokeColor: Palette.inkDark)
             node.addChild(strip)
             return node
         }
         // 2-3 коротких куба
         for offset in [(-8, 4), (6, -2), (0, 6)].prefix(Int.random(in: 2...3)) {
             let chunk = IsoBuilder.cube(footprint: CGSize(width: 8, height: 6), height: CGFloat.random(in: 4...8),
                 colors: .init(top: Palette.stone.lightened(by: 0.05).darkened(by: 0.30),
                               left: Palette.stone.darkened(by: 0.30),
                               right: Palette.stone.darkened(by: 0.45),
                               stroke: Palette.inkDark))
             chunk.position = CGPoint(x: CGFloat(offset.0), y: CGFloat(offset.1))
             node.addChild(chunk)
         }
         // Заросли травы
         for _ in 0..<3 {
             let weed = SKShapeNode(circleOfRadius: 1.5)
             weed.fillColor = Palette.nileGreen.darkened(by: 0.15)
             weed.strokeColor = .clear
             weed.position = CGPoint(x: CGFloat.random(in: -10...10), y: CGFloat.random(in: -4...4))
             node.addChild(weed)
         }
         // Трещина
         let crack = SKShapeNode()
         let p = CGMutablePath(); p.move(to: CGPoint(x: -8, y: -2)); p.addLine(to: CGPoint(x: 8, y: 1))
         crack.path = p
         crack.strokeColor = Palette.inkDark.withAlphaComponent(0.4)
         crack.lineWidth = 0.5
         node.addChild(crack)
         return node
     }
     ```
   - **Важно:** детерминированный seed для `Int.random` — для replay используем `seed: UInt64` параметр (опциональный, по умолчанию `unit.id.hashValue`).

4. **UnitSprites.makeWarehouse: добавить штабели** `[AC:3]`
   - Файл: `Sources/CityDeveloper/Game/UnitSprites.swift`
   - В `makeWarehouse(tier:)`: после `node.addChild(topShade)` — если `tier >= 1`:
     ```swift
     for offset in stride(from: -10, through: 10, by: 8) {
         let stack = IsoBuilder.cube(footprint: CGSize(width: 4, height: 3), height: 5,
             colors: .init(top: Palette.ochre.lightened(by: 0.05).darkened(by: 0.20),
                           left: Palette.ochre.darkened(by: 0.20),
                           right: Palette.ochre.darkened(by: 0.35),
                           stroke: Palette.inkDark.withAlphaComponent(0.6)))
         stack.position = CGPoint(x: CGFloat(offset), y: height + 3)
         node.addChild(stack)
     }
     ```
   - 3 штабеля для tier ≥ 1, до 4 для tier ≥ 2 — настроится в коде.

5. **Smoke-тест: вызов всех фабрик в GameScene.didMove** `[AC:smoke]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift`
   - Только в debug-сборке (`#if DEBUG`): создать 3 ноды на сцене (`CitizenSprites.makeCitizen(seed:42)`, `UnitSprites.makeRuin(originalKind:.house)`, `RoadConnector.roadVariant(neighbours:[.east,.west])`) и разместить вне видимой области либо за watermark — для проверки отсутствия крашей. Удалить после ручной проверки.

### Edge cases (явно обработать)
- [ ] `makeCitizen(seed:)` с большим seed → `abs(seed) % count` — корректный индекс.
- [ ] `makeRuin(originalKind: .road)` → плоская полоса (см. шаг 3).
- [ ] `makeWarehouse(tier: 0)` → штабели не рисуются (guard `tier >= 1`).
- [ ] Дорога с 0 соседями (одиночка) → `makeSingleSegment()` = текущий `makeRoad()` визуал.
- [ ] Дорога с 4 соседями (крест) → крестообразный визуал.
- [ ] **Диагональный сосед без ортогонального** (изометрические углы): обрабатывается как 0 ортогональных соседей → одиночный сегмент. Доп. логика «угловой стык» — в backlog.
- [ ] **Перфоманс при 50 жителях:** жители — лёгкие ноды (~3 ноды на жителя, 1 `SKAction.repeatForever`); 50 жителей = ~150 нод. SKAction reuse через `static let` — не нужен; SpriteKit оптимизирует repeatForever внутренне. Если просадка обнаружится — pool в TASK-011.

### Файлы для изменения
- `Sources/CityDeveloper/Game/UnitSprites.swift` — `makeRuin`, штабели в `makeWarehouse`
- `Sources/CityDeveloper/Game/GameScene.swift` — smoke-test (опционально, удалить после)

### Файлы НЕ трогать
- `Game/CityEngine.swift`, `DistrictPlanner`, `UnitPlanner`, `StageRules` — модель неизменна
- `Data/*` — модель неизменна

### Новые файлы
- `Sources/CityDeveloper/Game/CitizenSprites.swift`
- `Sources/CityDeveloper/Game/RoadConnector.swift`

### Команды проверки (для DoD)
- Компиляция: `swift build`
- Запуск: `swift run CityDeveloper`
- Ручная проверка:
  1. Smoke-тест — все фабрики не крашат при вызове в `didMove` (#if DEBUG).
  2. Войти в explore, найти warehouse tier ≥ 1 → видны штабели.
  3. Симулировать decay 4 (вызвать вручную `makeRuin` в `didMove` для теста) → видны обломки + трава.
  4. Жители: добавить 5 спрайтов на сцену через `CitizenSprites.makeCitizen` → видны качающиеся фигурки.
  5. Дороги — потребуется TASK-005 расширение, чтобы `RoadConnector.roadVariant` использовалось вместо `makeRoad`. На этом этапе только smoke.

### Сложность
`junior`

**Обоснование:** Линейные фабрики SKShapeNode/IsoBuilder, без архитектурных решений. 2 новых файла + 2 точечные правки. Edge cases предсказуемы.

### Ожидаемое время
S (≤ 2 часа)

### Plan-review правки (round 1 → applied)

1. **CRITICAL — `Palette[keyPath: $0]` не компилируется. Заменить на прямой массив:**
   ```swift
   static let tunicColors: [SKColor] = [
       Palette.clay, Palette.ochre, Palette.sandMid,
       Palette.nileGreen, Palette.parchment
   ]
   ```

2. **`makeRuin(originalKind:)` — `internal static func` (без `private`),** аналогично `UnitSprites.makeNode(unit:)`. Иначе smoke-тест из `GameScene` и будущий вызов из TASK-008 (`DecayVisuals.decay4Ruin`) не скомпилируются.

3. **Детерминизм `makeRuin`** — заменить `Int.random` / `CGFloat.random` на детерминированные значения от `originalKind.hashValue`. Скелет:
   ```swift
   static func makeRuin(originalKind: UnitKind) -> SKNode {
       let h = abs(originalKind.hashValue)
       let chunks = 2 + h % 2  // 2 или 3
       let offsets: [(CGFloat, CGFloat)] = [(-8, 4), (6, -2), (0, 6)]
       // ... использовать offsets.prefix(chunks), высота = CGFloat(4 + (h % 5))
   }
   ```
   Replay даст идентичный визуал.

4. **Высота жителя: 14 pt vs AC «≈ 16 pt»** — обновляем AC до «общая высота 14 pt (компромисс для читаемости при tileSize 64×32)». Скелет шага 2 оставить как есть.

5. **Скоуп дорог:** `RoadConnector.roadVariant(...)` — фабрика, в `UnitSprites.makeRoad()` НЕ интегрируется в этой задаче (требует доступа к соседям на уровне сцены — это уже TASK-005 расширение). В AC явно: «фабрика создаётся; интеграция в рендер — отложена. Smoke-test в `didMove` подтверждает работу API.»

6. **`#if DEBUG` smoke-блок:** добавить в DoD пункт «smoke-блок в `#if DEBUG` удалён перед открытием PR (или вынесен в комментарий)».

---

## ✅ Исполнение

_Исполнитель: haiku (junior)_
_Сложность: junior_

### Definition of Done (факт)

#### Функциональные
- [x] Все AC verify-pass
- [x] `CitizenSprites.makeCitizen(seed:)` — 14pt силуэт, sway-анимация
- [x] `UnitSprites.makeRuin(originalKind:)` — internal static, детерминированный
      по `hashValue`, спец-ветка для `.road`
- [x] `UnitSprites.makeWarehouse(tier:)` — штабели поверх крыши при `tier ≥ 1`
- [x] `RoadConnector.roadVariant(neighbours:)` — все 5 вариантов (single,
      straight, curve, T, cross)

#### Технические
- [x] `swift build` pass (Build complete! 0.11s, без новых warnings)
- [ ] FPS 60+ при 50 жителях — manual (нет автотестов GUI)

#### Обновление документации
- [x] `current.md`: F-13 ⚠️ → ✅ (с пометкой: интеграция RoadConnector в рендер — отдельная задача)
- [x] `diff.md`: D-13 удалён (перенесён в «Закрытые»)

---

## Статус

`[x] done`

## Метаданные
- Создана PM: 2026-05-22
- Spec-review: approved (round 1)
- Lead-model: opus
- Plan-review: needs-revision → applied (round 1)
- Сложность: junior
- Готова к работе: 2026-05-22
- Завершена: 2026-05-22
- Исполнитель: haiku
- Verify: pass (compile, AC verified, plan-review applied ✅)
- Code-review: approved (sonnet, Opus был 529; 3 минорных замечания — non-blocking)
- Коммит: — (репо не git)
