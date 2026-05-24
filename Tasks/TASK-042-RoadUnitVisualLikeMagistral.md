# TASK-042: Дорога-юнит выглядит как магистраль (без кубика)

## Связь
- **F-21** из Concept.md (RoadNetwork)
- **BUG-012** из Bugs.md
- **Приоритет:** P0

---

## 📋 Постановка от менеджера

_Автор: opus_
_Дата: 2026-05-24_

### Что хотим

Сейчас в кварталах road-юниты выглядят как маленький тёмный кубоид
(`bodyHeight=4`), а магистраль через центр карты — как плоская дорожная клетка.
Это два разных визуала для одного и того же `UnitKind.road`. Хочется
единообразия: ВСЕ road-клетки (и магистраль, и ветки кварталов) — плоский
тайл sandMid с тёмным дорожным пятном, без 3D-куба.

### Пользовательский сценарий

1. Пользователь открывает карту с уже застроенными кварталами.
2. Видит магистраль через центр — плоская дорога.
3. Видит ветки дорог в кварталах — выглядят ИДЕНТИЧНО магистрали (без кубика).
4. Единая визуальная связность всей дорожной сети.

### Acceptance criteria

- [ ] Road-юнит в составе квартала и клетка магистрали визуально неотличимы.
- [ ] Нет тёмного «кубика» поверх дороги.
- [ ] Размер дорожной клетки одинаков для магистрали и юнита (плоский ромб 64×32
      минус padding).
- [ ] При наведении/клике на road-юнит инспектор показывает «Дорога» как и
      раньше — поведение не меняется.

### Что НЕ делаем

- Не меняем визуал других юнитов (residential/production остаются как есть).
- Не трогаем `makeRoadCellNode` (он уже правильный, его используем).

### Edge cases

- [ ] У road-юнита есть `tier` (стадия) — все стадии выглядят одинаково
      (дорога не эволюционирует).
- [ ] При stage-up квартала road-юниты НЕ меняются визуально (это уже так и
      есть, проверить что не сломалось).

### Зависимости

- Используется `UnitSprites.makeRoadCellNode()` — уже создан в предыдущей
  задаче.

### Дизайн

То же что для магистрали (см. `UnitSprites.makeRoadCellNode`):
- Тайл-земля sandMid размером (tileWidth-2)×(tileHeight-1).
- Дорожное пятно sandMid.darkened(0.08) размером (tileWidth-6)×(tileHeight-4)
  поверх.

### Done-критерий

_Из Concept.md F-21:_

> Дорожная сеть города состоит из магистрали и веток кварталов. Визуально
> единая система — все road-клетки выглядят одинаково и связно.

---

## 🛠 Технический разбор от тимлида

_Автор: opus_
_Дата: 2026-05-24_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

- **`UnitSprites.makeStageNode`** (`UnitSprites.swift:62`) для любого
  UnitKind, включая `.road`, делает:
  1. Тайл-земля (groundTile, категория = infrastructure → sandMid).
  2. `building = makeKindBuilding(unit:stage:)` — кладёт `placeholderSpecs[.road]`
     = `roadSpec` (`UnitSprites.swift:197`) — это `bodyHeight: 4`, проц-куб.
- **`UnitSprites.makeRoadCellNode()`** уже создан, используется в
  `GameScene.drawRoadCells` для магистрали. Делает ground + makeRoad() без
  cube.
- **`UnitSprites.makeKindBuilding`** диспатчит по kind в спецификацию.
  `.road` использует `roadSpec`. Нужно для `.road` возвращать узел БЕЗ cube.

### Архитектурное решение

В `UnitSprites.makeStageNode` сделать ранний return для `kind == .road` →
вернуть `makeRoadCellNode()` напрямую. Не использовать placeholderSpec для
road. Минимальное вмешательство.

Альтернатива (хуже): убрать roadSpec из placeholderSpecs и в makeKindBuilding
для .road возвращать makeRoad(). Но makeStageNode рисует ещё ground tile
поверх — будет двойной ground.

Поэтому ранний return на уровне makeStageNode правильнее.

### Пошаговая декомпозиция

1. **Early return для .road в makeStageNode** `[AC:1,2,3]`
   - Файл: `Sources/CityDeveloper/Game/UnitSprites.swift`
   - Метод: `makeStageNode(unit:stageOverride:)`
   - В начале метода, после объявления `container = SKNode()`:
     ```swift
     // Road-юниты рендерятся плоской дорожной клеткой (как магистраль),
     // без 3D-куба. См. BUG-012 / TASK-042.
     if unit.kind == .road {
         let road = makeRoadCellNode()
         road.userData = NSMutableDictionary()
         road.userData?[unitIdKey] = unit.id
         road.userData?[projectIdKey] = unit.projectId
         return road
     }
     ```

2. **Проверить что makeNode (legacy path) тоже OK** `[AC:1]`
   - Файл: `UnitSprites.swift` около строки 1813 (`static func makeNode(unit:)`).
   - Этот метод сейчас тоже рендерит road через `makeRoad()` напрямую (без
     specs) — проверить что результат идентичен `makeRoadCellNode()`. Если
     нет — сделать `makeNode` тоже early-return на `makeRoadCellNode()` для
     .road.

3. **Проверить swapStageSprite для road** `[AC:4]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift` (поиск
     `swapStageSprite`).
   - При stage-up юнита `placeUnit(unit, project:)` пересоздаёт sprite через
     `makeStageNode`. Для road это теперь всегда `makeRoadCellNode` — OK,
     визуал не меняется.

### Edge cases

- [ ] **Inspector клик на road** — кладёт по userData[unitIdKey]. Установить
      его в makeRoadCellNode-wrapped узле (см. шаг 1).
- [ ] **Decay overlay** — у road-юнита его НЕ должно быть (decay на дорогах не
      показывается визуально). Если DecayVisuals что-то делает с road —
      проверить.

### Файлы для изменения

- `Sources/CityDeveloper/Game/UnitSprites.swift` — early return в
  makeStageNode для .road.

### Файлы НЕ трогать

- `Sources/CityDeveloper/Game/GameScene.swift` — drawRoadCells остаётся как
  есть (магистраль).
- `Sources/CityDeveloper/Game/IsoBuilder.swift` — groundTile/shadow не
  трогаем.

### Команды проверки

- Компиляция: `swift build`
- Ручная проверка:
  1. Запустить приложение
  2. На построенном квартале клик на road-юнит — визуально как магистраль.
  3. Кликнуть на road в магистрали и в ветке — должны быть одинаковыми.

### Сложность
`junior` — точечная правка в одном файле, 5-10 строк.

### Объём
S (≤2ч)

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: junior_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Road-юниты выглядят как магистраль

#### Технические
- [ ] Компиляция без ошибок

#### Документация
- [ ] `Bugs.md`: BUG-012 → закрыт

---

## Статус
`[x] ready`

## Метаданные
- Создана: 2026-05-24
- Завершена: —
- Коммит: —
