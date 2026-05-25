# TASK-044: Корректные footprint-размеры юнитов (≥2 клеток для не-минимума)

## Связь
- **F-16** из Concept.md (расширенный каталог 50 юнитов)
- **BUG-014** из Bugs.md
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: opus_
_Дата: 2026-05-24_

### Что хотим

Сейчас все юниты занимают 1×1 клетку — игнорируется поле `size` из
UnitCatalog. Должно быть: минимум 1×1 только для {shack, house, well, road,
zemlyanka, khizhina}, всё остальное — ≥2 клеток. Это даёт визуальную иерархию
кварталов (вилла больше дома, форум больше таверны).

### Пользовательский сценарий

1. Игрок видит квартал: маленькие 1×1 шалаши, дом 1×1, рядом 2×2 рынок, 3×3
   форум. Иерархия размера соответствует значимости.
2. Большие здания (вилла, дворец, пирамида) визуально доминируют — занимают
   3×3 / 4×4 тайлов.
3. Эволюция: 3 дома (3×1×1 = 3 тайла) превращаются в 1 доходный дом (2×2 = 4
   тайла) — занимает в 1.5× больше места, что логично.

### Acceptance criteria

- [ ] `UnitKind.size` возвращает правильный `GridSize` для каждого из ~50
      юнитов согласно ревизированной таблице (см. ниже).
- [ ] При размещении 2×2 здания через `UnitPlanner.nextPosition` все 4
      клетки footprint'а помечены как занятые (используется в TASK-041).
- [ ] Визуально 2×2 спрайт занимает 2 диагонали изометрической сетки (то
      есть выглядит в 2 раза шире/длиннее).
- [ ] Никакие 2×2 здания не вылезают за пределы петли (или вылезают
      контролируемо, без коллизий).
- [ ] Эволюция учитывает разницу в footprint: при превращении 3×1 в 1×4 —
      освобождаются 3 старые клетки, занимаются 4 новые (или target ставится
      рядом — детали в TASK-046).

### Что НЕ делаем

- Не рисуем новые финальные PNG (placeholder остаётся через
  procedural-спрайты).
- Не меняем алгоритм UnitPlanner.nextPosition (это TASK-041).
- Не трогаем эволюционную логику (это TASK-046).

### Edge cases

- [ ] Замощение 2×2 спрайта поверх сетки — anchor-point юнита остаётся
      bottom-centre (как сейчас). Спрайт сам по себе процедурный,
      масштабируется по `footprint.size`.
- [ ] При size > 1×1 в `placeUnit` нужно корректно сдвинуть zPosition (учесть
      многоклеточность). Сейчас zPosition = -(x+y) для bottom-cell.
- [ ] Перенос/миграция существующих snapshots — если у юнита в `state.json`
      записано position (1,1), а теперь kind=farm имеет size (2,2) — он
      займёт клетки (1,1)..(2,2). Может быть overlap с существующими. Чинить
      переразметкой? Или просто принять — будут локальные overlap'ы пока
      реплеит, при следующем live-эвенте уже нормально.

### Зависимости

- TASK-041 (overlap detection в UnitPlanner) — параллельно. Без BUG-011 фикса
  большие здания будут хаотично перекрывать соседей.

### Дизайн

Ревизированная таблица размеров (см. lead-разбор ниже). Спрайты — процедурные
из `UnitSprites.placeholderSpecs` с увеличенным `footprint`.

### Done-критерий

_Из Concept.md F-16:_

> 50 юнитов с разными footprint-размерами по таблице UnitCatalog. Большие
> здания (`large = true`) занимают 2×2 и больше, маленькие — 1×1 / 1×2.

---

## 🛠 Технический разбор от тимлида

_Автор: opus_
_Дата: 2026-05-24_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

- **`UnitKind.size`** (`Sources/CityDeveloper/Data/CityState.swift` — поиск
  `var size`) возвращает GridSize. Многие kind'ы могут возвращать 1×1 без
  учёта каталога.
- **`UnitSprites.placeholderSpecs`** имеет `footprint: CGSize` для каждого
  kind — но это PX-размер спрайта, не grid-размер. Нужно различать.
- **`GameScene.drawUnit` / `placeUnit`** ставит SKNode в `isoPosition(grid:
  unit.position)`. Не учитывает footprint > 1×1 для z-sort и offset'а.

### Ревизированная таблица размеров

Только {shack, house, well, road, zemlyanka, khizhina} — 1×1. Всё остальное
≥1×2 / ≥2×2 / ≥2×3 / ≥3×3 / 4×4.

| №  | Kind             | Текущий size | Новый size (W×H) | Обоснование              |
|----|------------------|--------------|------------------|--------------------------|
| 1  | zemlyanka        | 1×1          | **1×1**          | земляная нора, мин.      |
| 2  | shack            | 1×1          | **1×1** ✓        | минимум                  |
| 3  | khizhina         | 1×1          | **1×1**          | минимум                  |
| 4  | farmhouse        | 1×1          | **2×2**          | дом + земля рядом        |
| 5  | house            | 1×1          | **1×1** ✓        | минимум                  |
| 6  | two_story_house  | 1×2          | **1×2** ✓        | удлинённый               |
| 7  | stone_house      | 1×1          | **2×1**          | каменный, больше         |
| 8  | townhouse        | 1×2          | **2×2**          | широкий городской        |
| 9  | tenement         | 2×2          | **2×2** ✓        | доходный                 |
| 10 | manor            | 2×2          | **3×2**          | усадьба, шире            |
| 11 | villa            | 2×2          | **3×3**          | большая вилла            |
| 12 | dvorets          | 3×3          | **3×3** ✓        | дворец                   |
| 13 | well             | 1×1          | **1×1** ✓        | минимум                  |
| 14 | road             | 1×1          | **1×1** ✓        | минимум                  |
| 15 | gates            | 1×2          | **1×2** ✓        | ворота                   |
| 16 | bridge           | 1×1          | **1×3**          | мост через реку          |
| 17 | cistern          | 1×1          | **2×2**          | резервуар                |
| 18 | lighthouse       | 2×2          | **2×2** ✓        | маяк                     |
| 19 | irrigation_canal | 1×1          | **2×1**          | канал                    |
| 20 | pier             | 2×2          | **3×2**          | пристань длинная         |
| 21 | farm             | 2×2          | **3×3**          | ферма с полями           |
| 22 | fishing_pier     | 1×2          | **2×2**          | рыбацкий причал          |
| 23 | workshop         | 1×1          | **2×1**          | мастерская               |
| 24 | warehouse        | 2×2          | **2×2** ✓        | склад                    |
| 25 | smithy           | 1×1          | **2×1**          | кузница                  |
| 26 | pottery          | 1×1          | **2×1**          | гончарня                 |
| 27 | brewery          | 1×2          | **2×2**          | пивоварня                |
| 28 | sawmill          | 1×2          | **2×2**          | лесопилка                |
| 29 | quarry           | 2×2          | **3×2**          | каменоломня              |
| 30 | mine             | 2×2          | **2×2** ✓        | шахта                    |
| 31 | great_warehouse  | 3×2          | **3×2** ✓        | большой склад            |
| 32 | factory          | 3×3          | **3×3** ✓        | завод                    |
| 33 | tavern           | 1×1          | **2×1**          | таверна                  |
| 34 | market           | 2×2          | **2×2** ✓        | рынок                    |
| 35 | plaza            | 2×2          | **3×3**          | площадь                  |
| 36 | bathhouse        | 2×1          | **2×2**          | баня                     |
| 37 | school           | 2×1          | **2×2**          | школа                    |
| 38 | hospital         | 2×2          | **2×2** ✓        | больница                 |
| 39 | forum            | 3×3          | **3×3** ✓        | форум                    |
| 40 | library          | 2×2          | **2×2** ✓        | библиотека               |
| 41 | aqueduct         | линейный     | **1×3** (сегмент) | акведук, ставим сегментами |
| 42 | theater          | 3×2          | **3×3**          | театр большой            |
| 43 | chapel           | 1×1          | **2×1**          | часовня                  |
| 44 | temple           | 2×2          | **3×3**          | храм                     |
| 45 | obelisk          | 1×1          | **1×1**          | обелиск (исключение, мин) |
| 46 | cathedral        | 3×3          | **3×3** ✓        | собор                    |
| 47 | pyramid          | 4×4          | **4×4** ✓        | пирамида                 |
| 48 | watchtower       | 1×1          | **2×1**          | башня                    |
| 49 | barracks         | 2×2          | **2×2** ✓        | казармы                  |
| 50 | shipyard         | 3×3          | **3×3** ✓        | верфь                    |

Исключения 1×1: shack, house, well, road, zemlyanka, khizhina, obelisk (51
юнит включая raw — у raw уже 1×1, без изменений).

### Архитектурное решение

1. **`UnitKind.size`** — переписать (или впервые написать корректно) switch
   по kind, возвращающий новые значения.
2. **`UnitSprites.placeholderSpecs`** — увеличить `footprint` (CGSize) и
   `baseHeight` для крупных зданий пропорционально grid-размеру. Один grid =
   tileWidth/2 PX по диагонали (примерно). Можно сделать формулой: `pxWidth
   = gridW * 0.9 * tileWidth/2`, `pxHeight = gridH * 0.5 * tileHeight`.
   Heights: малые 8, средние 14, большие 22, монументы 30+.
3. **`GameScene.drawUnit`** — для footprint > 1×1 ставить узел с
   `position.y + (gridSize.height-1) * tileHeight/2` чтобы здание визуально
   было НАД своими клетками. zPosition = -(unit.position.x +
   unit.position.y + (gridSize.width-1) + (gridSize.height-1)) — берём
   нижний-передний угол.
4. **GridSize.area** — добавить helper для подсчёта (для capacity loop'а в
   BUG-011).

### Пошаговая декомпозиция

1. **Переписать `UnitKind.size`** `[AC:1]`
   - Файл: `Sources/CityDeveloper/Data/CityState.swift`
   - Найти `var size: GridSize` в extension UnitKind.
   - Большой switch по 50+ case'ам с GridSize согласно таблице выше.

2. **Обновить `UnitSprites.placeholderSpecs`** `[AC:3]`
   - Файл: `Sources/CityDeveloper/Game/UnitSprites.swift`
   - В таблице `placeholderSpecs` для каждого kind с новым size — увеличить
     footprint и baseHeight. Использовать helper:
     ```swift
     func sizeFor(grid g: GridSize, h: CGFloat = 8) -> CGSize {
         CGSize(
             width: CGFloat(g.width) * (tileWidth/2 - 4),
             height: CGFloat(g.height) * (tileHeight/2 - 2)
         )
     }
     ```
   - Применить к каждому spec в `placeholderSpecs`.

3. **GameScene.drawUnit учитывает footprint** `[AC:3,4]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift:drawUnit`
   - При вычислении position и zPosition учесть `unit.kind.size`:
     ```swift
     let basePos = isoPosition(grid: unit.position)
     let size = unit.kind.size
     // Bottom anchor: для multi-cell здание визуально стоит на (x..x+w-1, y..y+h-1)
     let pos = CGPoint(x: basePos.x, y: basePos.y + CGFloat(size.height - 1) * tileHeight / 2)
     node.position = pos
     node.zPosition = -CGFloat(unit.position.x + unit.position.y + size.width + size.height - 2)
     ```

4. **GridSize.area helper** `[AC:1]`
   - Файл: `Sources/CityDeveloper/Data/CityState.swift`
   - В extension GridSize:
     ```swift
     var area: Int { width * height }
     ```

5. **Smoke test** `[AC:1,3,4]`
   - Запустить приложение
   - В дев-режиме: ингест 1 task в проект → должен встать road 1×1.
   - 2-й task → residential, скорее всего shack 1×1.
   - При достаточном кол-ве: появится farm 3×3 — визуально занимает 9
     клеток, не должен перекрывать соседние.

### Edge cases

- [ ] **Snapshot migration:** если в старом state.json position юнита kind=farm
      на (5,5), теперь farm = 3×3 → занимает (5,5)..(7,7). Может перекрыть
      соседние юниты. Принять — replay даст некоторые artifact'ы, в новом
      городе будет нормально. Лог warning при overlap в drawUnit.
- [ ] **Pyramid 4×4** — самое большое здание. Должно быть редкое (minStage=5).
      Визуально доминирует.
- [ ] **Aqueduct 1×3** — линейный, ставится по дороге.

### Файлы для изменения

- `Sources/CityDeveloper/Data/CityState.swift` — UnitKind.size +
  GridSize.area.
- `Sources/CityDeveloper/Game/UnitSprites.swift` — placeholderSpecs.
- `Sources/CityDeveloper/Game/GameScene.swift` — drawUnit offset для
  multi-cell.

### Файлы НЕ трогать

- `concept/UnitCatalog.md` — это справочник, обновится в TASK-039.

### Команды проверки

- Компиляция: `swift build`
- Ручная: импорт большого репо, осмотр кварталов. Farm должен быть 3×3, pyramid
  4×4 (редко), house/shack — 1×1.

### Сложность
`middle` — большой switch по 50 юнитам + visual layout для multi-cell. 3 файла.

### Объём
M

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: middle_

### Definition of Done

- [ ] AC выполнены
- [ ] Сборка чистая
- [ ] `Bugs.md`: BUG-014 → закрыт
- [ ] `concept/UnitCatalog.md`: обновить колонку Size в соответствии с
      новой таблицей

---

## Статус
`[x] done`

## Метаданные
- Создана: 2026-05-24
- Завершена: 2026-05-24
- Коммит: 2840287
