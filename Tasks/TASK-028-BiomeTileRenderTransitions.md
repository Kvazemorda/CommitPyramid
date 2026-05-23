# TASK-028: Рендер биомов на изометрической карте с плавными переходами

## Связь
- **F-15** из Concept.md (биомы и переходы)
- **F-02** из Concept.md (изометрический рендер)
- **D-15** из Diff.md (часть 3/5 — визуализация биомов)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-23_

### Что хотим
Заменить текущий плоский зелёный луг (огромный одноцветный прямоугольник) на
настоящую карту биомов: на земле видно, где луг, где лес, где пустыня, где
горы, камни, река и море. Между соседними биомами — **плавный переход**, а не
ступенька-«пиксель», чтобы карта смотрелась как природный ландшафт в духе
Pharaoh. Это первый момент, когда D-15 становится виден глазами.

### Пользовательский сценарий
1. Игрок входит в explore-режим — видит большую изометрическую карту вместо
   зелёного квадрата.
2. По карте читаются разные зоны: зелёные луга, тёмный лес, песчаная пустыня,
   серые горы и каменистые склоны, голубая река и/или море.
3. На стыке луга и леса нет резкой границы — переход размыт на несколько
   клеток; то же между лугом и пустыней, камнями и горами, сушей и водой.
4. Уже расставленные здания и юниты по-прежнему видны и стоят на своих местах
   (поверх нового рельефа), просто фон под ними теперь не одноцветный.

### Acceptance criteria
- [ ] Карта отрисована изометрическими тайлами поверх данных биомов из
      TASK-027 (минимум 4 разных биома видны на экране без зума на конкретные
      участки).
- [ ] На стыке двух разных биомов виден переход шириной несколько клеток
      (визуальный blend / переходные тайлы), а не одна резкая линия.
- [ ] FPS в explore-режиме на типичной M-серии не падает ниже 60 при пустом
      городе и не падает ниже 55 при 500+ юнитах поверх биомов (порог F-02
      сохраняется).
- [ ] Существующие здания/юниты/жители видны корректно: глубина (z-order)
      сохраняется, тени и спрайты не уходят под тайлы рельефа.
- [ ] Старый «плоский луг» как одноцветный прямоугольник больше не отображается
      ни в одном режиме.

### Что НЕ делаем (границы скоупа)
- Не делаем декор-объекты биомов (деревья, камни, валуны, тростник) — это в
  Backlog как отдельный визуальный пас.
- Не меняем правила выбора биома для клетки — берём как есть из TASK-027.
- Не трогаем зум (TASK-029) и реинициализацию карты (TASK-030).
- Не делаем художественные PNG-тайлы биомов в этой задаче — стартовый
  визуал может быть сплошной заливкой по биому (палитра из `Theme/Palette.swift`
  и `concept/SpriteGenerationRules.md` §5); реальные PNG-тайлы — отдельный
  визуальный backlog.

### Edge cases
- [ ] Карта меняется на лету (TASK-030, реинициализация) → рендер чисто
      пересобирается без артефактов и без падения FPS на момент перестроения.
- [ ] Биом меньше переходной ширины (узкий язык в 1–2 клетки) → переходы не
      «съедают» биом целиком, он остаётся читаемым.
- [ ] Очень крупная карта (256×256+) → не загружается единым гигантским
      спрайтом, отрисовка масштабируется без выхода в свопинг и без рывков.
- [ ] Окно меняет размер / уходит в behind-режим и обратно → карта не моргает,
      переходы не «пересчитываются» с видимым лагом.

### Зависимости
- **Blocked-by:** TASK-026 (поля), TASK-027 (биомы).
- Учитывает правила палитры и тайлов из `concept/SpriteGenerationRules.md` §5
  (бесшовные тайлы, 3 вариации на биом, 4 переходных к соседнему — это уже
  визуальный план; здесь реализуем механизм, тайлы заменяются по мере появления).

### Дизайн
Палитра биомов — из `Sources/CityDeveloper/Theme/Palette.swift` и
`concept/SpriteGenerationRules.md` §5 (Луг — зелёная трава, Пустыня — светлый
песок, Лес — тёмная зелень, Горы — серый камень, Камни — переходная серо-охра,
Река — голубая вода, Море — сине-зелёная вода).

### Done-критерий
_Из Concept.md F-15:_ При первом запуске генерируется карта ≥ 256×256 тайлов с не менее
чем 4 разными биомами, соединёнными плавными переходами. Карта воспроизводима из seed.
Кнопка «Сбросить карту» + подтверждение → новая генерация, кварталы переразмещаются.
Зум позволяет увидеть всю карту в одном экране. Новый квартал рядом с рекой получает
водные/речные юниты с заметно большей вероятностью, чем равномерная.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-22_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

**В коде уже есть:**
- `Sources/CityDeveloper/Game/GameScene.swift:38-41` — плоский луг как `SKSpriteNode(color: Palette.nileGreen, size: 8000×8000)` на `zPosition = -1000`. Это объект, который нужно заменить.
- `Sources/CityDeveloper/Game/GameScene.swift:14-15` — `tileWidth = 64`, `tileHeight = 32` (изо-сетка).
- `Sources/CityDeveloper/Game/GameScene.swift:409-415` — `isoPosition(grid:)` — перевод `GridPoint → CGPoint`; нельзя менять (контракт с юнитами/жителями/руинами).
- `Sources/CityDeveloper/Game/GameScene.swift:417-425` — `diamondPath()` уже умеет рисовать ромб 64×32.
- `Sources/CityDeveloper/Game/IsoBuilder.swift:162-180` — `groundTile(width:height:fillColor:strokeColor:)` — уже готовая фабрика ромб-`SKShapeNode` с заливкой.
- `Sources/CityDeveloper/Theme/Palette.swift` — токены `nileGreen`, `sandLight`, `sandMid`, `ochre`, `clay`, `stone`, `skyDay` (вода будет введена новыми токенами).
- `concept/SpriteGenerationRules.md` §5 (строки 153-174) — список 7 биомов + правило «3 вариации + 4 переходных тайла».

**Связанные модули (читают сцену, не должны сломаться):**
- `Sources/CityDeveloper/Game/LifeSimulationManager.swift` (smoke/sparks/flags) — добавляет SKEmitter/SKShape поверх `world`, `zPosition` 5..—.
- `Sources/CityDeveloper/Game/CitizenManager.swift:152,197,228` — жители: `zPosition = -(x+y) + 0.5` (тот же контракт глубины, что и юниты).
- `Sources/CityDeveloper/Game/UnitSprites.swift:59,70,824,835` — у юнитов `shadow.zPosition = -2`, `ground.zPosition = -1` (относительно ноды юнита). После замены подложки — нужно подтвердить, что эти контракты не конфликтуют с биомным слоем (мой выбор: биом-тайлы строго ниже `zPosition = -1000`).
- `Sources/CityDeveloper/Game/DecayVisuals.swift:31-35,44` — `nileGreen` упомянут как fallback в overlay (не трогаем).

**Что переиспользуем:**
- `IsoBuilder.groundTile(...)` для генерации текстуры тайла (через `SKView.texture(from:)`).
- Существующий `tileWidth/tileHeight = 64/32` (совпадает с `SKTileMapNode.tileSize`).
- `isoPosition(grid:)` — координаты `SKTileMapNode` совпадают с этой формулой (центр карты в `(0,0)` — настраивается через `SKTileMapNode.position`).
- `Palette.*` для палитры биомов (без хардкод-цветов в новом коде).

**Что нужно дописать:**
- `Game/BiomeRenderer.swift` — новый модуль: создаёт `SKTileMapNode`, фабрики `SKTileSet/SKTileGroup` на 7 биомов + переходы, метод `attach(to: SKNode, biomeMap: BiomeMapReader)`.
- `Game/BiomeMapReader.swift` (protocol, тонкий) — контракт чтения биомов клеток, чтобы не зависеть жёстко от типов TASK-027. Реальный конформанс приходит из TASK-027 (BiomeClassifier/BiomeMap).
- `Game/TileTextureFactory.swift` — фабрика растровых тайлов 64×32 на каждый биом + 4 переходных шаблона (NE/NW/SE/SW). На Retina рендерим в `@2x`.
- `Theme/Palette.swift` — добавить токены: `forestGreen`, `mountainGrey`, `rockBrown`, `riverBlue`, `seaTeal` (см. §5 SpriteGenerationRules).
- `Game/GameScene.swift` — удалить плоский `SKSpriteNode` луг, заменить вызовом `BiomeRenderer.attach(...)`. Подменить `backgroundColor` на `Palette.nileGreen` (fallback за пределами карты).

### Архитектурное решение

**Слой подложки → `SKTileMapNode` + детерминированная композиция переходов.**
Один `SKTileMapNode` (isometric) с `tileSize = 64×32`, `numberOfColumns = numberOfRows = 256` (соответствует TASK-026/027). `SKTileSet` содержит **15 `SKTileGroup`**: 7 «чистых» биомов + 8 «переходных» (4 направления × 2 биом-пары для часто встречающихся стыков; остальные стыки обслуживаются через альфа-смешивание поверх через дополнительный overlay-узел — см. ниже). При `didMove` сцена строит `BiomeRenderer`, который проходит по `BiomeMapReader` (контракт TASK-027) и для каждой ячейки выбирает группу через **edge-aware lookup**: смотрит на 4 соседа, если все совпадают — ставит чистый биом; если 1–2 соседа отличаются — ставит переходный шаблон, ориентированный к «чужому» биому; на тройных стыках — выбирает по приоритетной шкале (вода > горы > пустыня > лес > камни > луг).

**Почему `SKTileMapNode`, а не множество `SKSpriteNode`-ромбов.** Тайл-нода рендерит только видимые ячейки (frustum culling «из коробки»), что критично для 256×256 = 65 536 ячеек и AC по FPS (60/55). Альтернатива «много шейпов» убивает FPS на >2k нод. Триггер из Concept и §5 SpriteGenerationRules — именно тайл-сет.

**Переходы — два слоя.** «Грубый» переход кодируется выбором переходной группы тайл-сета (по соседям). Над тайл-картой кладётся отдельный лёгкий `SKNode` overlay с диагональной альфа-маской на границе пар «суша↔вода» и «луг↔пустыня» (только для этих пар, шириной 1–2 клетки), чтобы избежать визуальной «ступеньки». Это держит число тайл-групп в разумных рамках (15, а не 7² × 4 = 196).

**Контракт с TASK-026/027 (через protocol BiomeMapReader).** Не зависим напрямую от классов TASK-027 — рендер компилируется и тестируется в изоляции через mock-конформанс. Когда TASK-027 готов — добавляется одна строка `extension BiomeMap: BiomeMapReader {}`.

**Контракт с TASK-025.** TASK-025 вводит `SKTileMapNode` для одного «grass»-тайла. TASK-028 строится поверх (расширяет тайл-сет до 7+8 групп). Если TASK-025 ещё не закрыт к моменту run TASK-028 — исполнитель сначала сделает мини-shim (один `SKTileMapNode`, как требует TASK-025 AC), потом расширит тайл-сет. Это явный шаг 1 ниже.

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку. Шаг непонятен — НЕ импровизируй, возвращай задачу через сообщение.
>
> ⚠️ Pre-flight: задача blocked-by TASK-026 (поля шума) и TASK-027 (классификатор биомов). Перед `/run 028` убедись, что обе задачи в статусе `done`. Если нет — исполнение TASK-028 невозможно, верни задачу в `waiting-for-lead`.

0. **Контракт-чек с TASK-026/027** `[AC:1]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift` (только чтение, не правка)
   - Что выяснить:
     1. Где TASK-027 положил `BiomeMap` / `BiomeClassifier` — модуль, тип, способ доступа.
     2. Как читается биом клетки: `map.biome(at: GridPoint)` / `map.biome(atX:y:)` / `classifier.classify(x:y:)` — точная сигнатура.
     3. Есть ли уже свой `enum Biome` — если да, не дублировать в шаге 2.
     4. Где живёт инстанс на CityEngine: `engine.biomeMap` / `engine.world.biomes` / отдельный singleton.
   - Если контракт расходится с допущением плана (`engine.biomeMap: BiomeMapReader?`) — **остановиться** и вернуть задачу в `lead-revision-needed` с заметкой; не «допиливать на ходу».
   - Этот шаг — sanity-check, ≤15 минут чтения. Если всё совпадает — переходим к шагу 1.

1. **Расширить палитру биомов** `[AC:1]`
   - Файл: `Sources/CityDeveloper/Theme/Palette.swift`
   - Метод/блок: `enum Palette`
   - Что меняем: добавить 5 новых токенов цвета биомов (точные RGB подобраны под §5 SpriteGenerationRules + согласованы с уже существующим `nileGreen`/`sandLight`/`stone`).
   - Скелет:
     ```swift
     static let forestGreen  = SKColor(red: 0.18, green: 0.32, blue: 0.18, alpha: 1.0)
     static let mountainGrey = SKColor(red: 0.45, green: 0.43, blue: 0.40, alpha: 1.0)
     static let rockBrown    = SKColor(red: 0.58, green: 0.50, blue: 0.40, alpha: 1.0)
     static let riverBlue    = SKColor(red: 0.40, green: 0.62, blue: 0.78, alpha: 1.0)
     static let seaTeal      = SKColor(red: 0.25, green: 0.45, blue: 0.58, alpha: 1.0)
     ```
   - Не трогать существующие токены (декай/юниты на них опираются).

2. **Завести контракт чтения биомов** `[AC:1,2]`
   - Файл: `Sources/CityDeveloper/Game/BiomeMapReader.swift` (новый)
   - Что меняем: ввести `enum Biome` (7 кейсов: `.meadow, .desert, .forest, .mountain, .rocks, .river, .sea`) и protocol `BiomeMapReader { var width: Int { get }; var height: Int { get }; func biome(atX x: Int, y: Int) -> Biome }`.
   - Скелет:
     ```swift
     enum Biome: String, CaseIterable {
         case meadow, desert, forest, mountain, rocks, river, sea
         /// Приоритет для разрешения тройных стыков (выше — выигрывает).
         var transitionPriority: Int { ... }
     }
     protocol BiomeMapReader {
         var width: Int { get }
         var height: Int { get }
         func biome(atX x: Int, y: Int) -> Biome
     }
     ```
   - Если в TASK-027 уже введён собственный `Biome`-тип — НЕ дублировать: импортировать его, наш `Biome` удалить, оставить только protocol. Решение принимается смотря на код TASK-027 перед началом шага.

3. **Сделать фабрику растровых тайлов на биом** `[AC:1]`
   - Файл: `Sources/CityDeveloper/Game/TileTextureFactory.swift` (новый)
   - Метод/блок: `enum TileTextureFactory { static func texture(for biome: Biome) -> SKTexture; static func transitionTexture(from: Biome, to: Biome, edge: Edge) -> SKTexture }`
   - Что меняем: для каждого биома — генерируем `SKTexture` 64×32 (на Retina — `@2x` через `NSImage`/`CGContext` 128×64) на базе `IsoBuilder.groundTile(width:height:fillColor:)` с заливкой из шага 1. Для переходов — рисуем ромб с альфа-градиентом по выбранному ребру (NE/NW/SE/SW).
   - Кэш текстур в `static var` (один раз на запуск, удержание не растёт между сценами).
   - Скелет:
     ```swift
     enum Edge { case ne, nw, se, sw }
     enum TileTextureFactory {
         private static var cache: [String: SKTexture] = [:]
         static func texture(for biome: Biome) -> SKTexture { ... }
         static func transitionTexture(from a: Biome, to b: Biome, edge: Edge) -> SKTexture { ... }
     }
     ```

4. **Построить `SKTileSet` со всеми группами** `[AC:1,2]`
   - Файл: `Sources/CityDeveloper/Game/BiomeRenderer.swift` (новый)
   - Метод/блок: `private static func buildTileSet() -> SKTileSet`
   - Что меняем: 7 чистых `SKTileGroup` (по 1 определению, можно расширить до 3 вариаций позже) + 8 наиболее частых переходных групп: `meadow↔forest`, `meadow↔desert`, `meadow↔rocks`, `rocks↔mountain`, и каждая пара земли↔вода (`meadow↔river`, `meadow↔sea`, `desert↔sea`, `rocks↔sea`). Каждая группа имеет `SKTileGroupRule` с `adjacency = .up/.right/...` где это поддержано (для иззометрии rules часто ограничены — fallback на ручной выбор группы в шаге 6).
   - Тип сета: `SKTileSet(tileGroups: [...], tileSetType: .isometric)`.

5. **Создать BiomeRenderer и заменить плоский луг** `[AC:1,4,5]`
   - Файл: `Sources/CityDeveloper/Game/BiomeRenderer.swift` (новый) + `Sources/CityDeveloper/Game/GameScene.swift`
   - Метод/блок:
     - `BiomeRenderer`:
       ```swift
       final class BiomeRenderer {
           private let tileMap: SKTileMapNode
           init(map: BiomeMapReader, tileSize: CGSize = CGSize(width: 64, height: 32)) {
               let tileSet = Self.buildTileSet()
               tileMap = SKTileMapNode(
                   tileSet: tileSet,
                   columns: map.width, rows: map.height,
                   tileSize: tileSize
               )
               tileMap.position = .zero
               tileMap.zPosition = -1000
               populate(from: map)
           }
           func attach(to world: SKNode) { world.addChild(tileMap) }
           private func populate(from map: BiomeMapReader) { ... }
       }
       ```
     - В `GameScene.didMove(to:)` (`GameScene.swift:38-41`) — удалить блок `lawn = SKSpriteNode(... nileGreen ... 8000×8000)`, заменить на:
       ```swift
       backgroundColor = Palette.nileGreen  // fallback за пределами карты
       if let reader = engine?.biomeMap {    // engine отдаёт через TASK-027
           let renderer = BiomeRenderer(map: reader)
           renderer.attach(to: world)
           self.biomeRenderer = renderer
       }
       ```
   - Сохранить `zPosition = -1000` (под watermark `-500` и под юнитами).
   - `backgroundColor` поменять с `Palette.skyDay` на `Palette.nileGreen` (см. edge case «pan за край карты» из TASK-025).

6. **Edge-aware выбор группы при заполнении** `[AC:2,4]`
   - Файл: `Sources/CityDeveloper/Game/BiomeRenderer.swift`
   - Метод/блок: `private func populate(from map: BiomeMapReader)`
   - Что меняем: двойной цикл по `(col, row)`. Для каждой клетки:
     1. Прочитать центр `b = map.biome(atX: col, y: row)`.
     2. Прочитать 4 соседа (с clamp по границам — за краем возвращаем сам `b`).
     3. Если все 4 == `b` → поставить чистую группу `groups[b]`.
     4. Если ровно 1–2 соседа отличаются и пара `(b, other)` поддерживается → поставить переходную группу с ребром в сторону `other`.
     5. Иначе — поставить чистую группу `b` (overlay покроет резкость, см. шаг 7).
   - Контракт: «биом меньше переходной ширины» (edge case PM) — переход НЕ съедает биом, потому что переходная группа сохраняет цвет центральной клетки на 50%+ площади ромба.

7. **Overlay-переход для крупных категорий** `[AC:2]`
   - Файл: `Sources/CityDeveloper/Game/BiomeRenderer.swift` + `Sources/CityDeveloper/Game/TileTextureFactory.swift`
   - Метод/блок: `private func attachOverlay(to world: SKNode, map: BiomeMapReader)` + `TileTextureFactory.alphaGradientTexture(color: SKColor, edge: Edge) -> SKTexture`
   - Что меняем:
     1. В `TileTextureFactory` добавить генератор альфа-маски: ромб 64×32, заливка цвета биома-«соседа», альфа линейно падает от 1.0 на ребре `edge` до 0.0 на противоположной стороне. Реализация — `NSImage` через `CGContext.drawLinearGradient` от opaque-color к clear-color, маска по diamondPath. **НЕ** использовать `SKSpriteNode(color:)` без альфа-канала — нужен `SKSpriteNode(texture: alphaGradientTexture)`.
     2. В `BiomeRenderer` пройти по карте; для каждой клетки на границе «суша↔вода» (river/sea с любой землёй) или «луг↔пустыня» — добавить поверх `SKSpriteNode(texture: ...)` на `world` в позиции `isoPosition(grid: GridPoint(col, row))`, `zPosition = -999` (выше тайла `-1000`, ниже watermark `-500`). Это «мягкий» переход шириной 1 клетка. Для остальных пар overlay НЕ добавляется (экономия нод).
   - Ограничение: не более 1 overlay на клетку, не более ~3000 overlay-нод на 256×256 карте (типичная граница земли/воды). Если получилось >5000 — логируем warning в `ErrorsLog` и оставляем только границу земли/воды (отбрасываем `meadow↔desert`-переходы).

8. **Утилитарный метод `rebuild(from:)` для TASK-030** `[AC:1]`
   - Файл: `Sources/CityDeveloper/Game/BiomeRenderer.swift`
   - Метод/блок: `func rebuild(from map: BiomeMapReader)`
   - Что меняем: удалить из tileMap все ячейки (`tileMap.fill(with: nil)`), удалить все overlay-ноды, повторить `populate(from:)` + `attachOverlay(...)`. Edge case PM «карта меняется на лету» — будет использовано TASK-030 (миграция кварталов после смены seed).
   - Не вызываем рекурсивно из `init` — `init` уже делает populate.

9. **Не трогать жителей/юниты/руины** `[AC:4]`
   - Файлы (не трогать): `Game/CitizenManager.swift`, `Game/UnitSprites.swift`, `Game/DecayVisuals.swift`, `Game/LifeSimulationManager.swift`.
   - Почему: `zPosition` нод юнитов `= -(x+y)` и жителей `= -(x+y) + 0.5` — оба заведомо > -1000 → визуально оказываются поверх биом-тайлов и overlay (`zPosition = -999`). Никакой переустановки z не требуется.

10. **Smoke-проверка и ручной DoD** `[AC:1,2,3,4,5]`
    - Команды:
      - Сборка: `swift build`
      - Тесты: `swift test`
      - Запуск: `swift run CityDeveloper`, ⌘⌥G, drag/scroll. На экране должны быть видны ≥ 4 разных биома (включая воду) с переходами на стыках.
    - Включить debug-FPS (через `view.showsFPS = true`, наследие TASK-025 — если TASK-025 уже закрыт, оверлей доступен по hotkey/настройке; если нет — временно вписать `view?.showsFPS = true` в `GameScene.didMove(to:)` и снять при коммите).
    - Замер FPS (требование AC 3):
      - Пустой город — FPS ≥ 60 (обязательно).
      - 500+ юнитов — FPS ≥ 55. Реализация замера зависит от TASK-025: если bench-сценарий из TASK-025 закрыт — запустить его; если ещё нет — временно создать 500 синтетических юнитов через прямой вызов `engine.applyTaskCompleted(...)` в цикле (детерминистский seed). Если оба невозможны — фиксируем замер только «пустой город», AC 3 (часть про 500 юнитов) переносим в проверку при закрытии TASK-025 и помечаем в `bugs.md`.

### Edge cases (явно обработать)

- [ ] **Карта меняется на лету (TASK-030).** Использовать `BiomeRenderer.rebuild(from:)` (шаг 8). После полной перестройки сцена не должна моргать — `fill(with: nil)` + `fill(with: group)` в одном RunLoop-тике. Проверка после интеграции с TASK-030.
- [ ] **Биом меньше переходной ширины (узкий язык 1–2 клетки).** Edge-aware алгоритм (шаг 6) сохраняет центр клетки тем биомом, который в ней лежит; переходный ромб занимает ≤50% площади → биом остаётся читаемым. Тест: вручную смокать `BiomeMapReader` с 1-клеточной полосой.
- [ ] **Очень крупная карта 256×256+.** `SKTileMapNode` сам рендерит только видимые тайлы; ручной culling не нужен. Память: 256² × 4 байта ссылки на группу ≈ 256 KB — приемлемо. Overlay-ноды ограничены 3000 (шаг 7).
- [ ] **Resize окна / behind-mode.** `SKTileMapNode` не пересоздаётся, потому что `scene` не пересоздаётся (контракт `WindowModeManager`). При `willResignActive` сцена паузится (`GameScene.swift:85-91`), при возврате — продолжает. Никаких пересчётов биомов.
- [ ] **`engine.biomeMap == nil` (например, в legacy-сценарии или при первом тесте без TASK-027).** В `GameScene.didMove` (новый код, шаг 5) — fallback: оставить `backgroundColor = Palette.nileGreen` БЕЗ биом-тайлов (на сцене будет цвет травы, не `skyDay`). Запись в `errors.log` через `ErrorsLog` (см. `Sources/CityDeveloper/Data/ErrorsLog.swift`).
- [ ] **`drawUnit` zPosition** в `GameScene.swift:193` `= -(x+y)` (отрицательный для дальних клеток). Минимум при 256×256 ≈ -512, что заведомо > -1000 (zPosition тайл-карты) → юниты остаются поверх. Подтверждено.
- [ ] **`handleRuinsCleared` dust** в `GameScene.swift:153` имеет `zPosition = 5000` → поверх биомов. Не трогаем.
- [ ] **inspector / district-маркеры** в `GameScene.swift:404,483` `zPosition = 9999/100000` → поверх. Не трогаем.
- [ ] **Тёмная тема macOS.** Палитра статическая (`SKColor` с конкретными RGB) — биом-тайлы выглядят одинаково в light/dark.
- [ ] **Retina blur тайлов.** Генерация через `NSImage` с `scale = 2` (см. шаг 3, аналогично решению из TASK-025 edge cases).

### Файлы для изменения

- `Sources/CityDeveloper/Game/GameScene.swift` — удалить плоский `SKSpriteNode` луг (стр. 38-41), заменить на `BiomeRenderer.attach(...)`; поменять `backgroundColor` на `Palette.nileGreen`.
- `Sources/CityDeveloper/Theme/Palette.swift` — добавить 5 новых биомных токенов (`forestGreen`, `mountainGrey`, `rockBrown`, `riverBlue`, `seaTeal`).
- `Sources/CityDeveloper/Game/BiomeRenderer.swift` — новый файл.
- `Sources/CityDeveloper/Game/BiomeMapReader.swift` — новый файл (protocol + enum Biome, если TASK-027 ещё не ввёл).
- `Sources/CityDeveloper/Game/TileTextureFactory.swift` — новый файл.

### Файлы НЕ трогать

- `Sources/CityDeveloper/Game/CitizenManager.swift` — жители работают через `zPosition` нод, контракт сохранён.
- `Sources/CityDeveloper/Game/UnitSprites.swift` — юниты сами заводят `shadow/ground`, контракт сохранён.
- `Sources/CityDeveloper/Game/DecayVisuals.swift` — overlay декая поверх юнита, не зависит от подложки.
- `Sources/CityDeveloper/Game/LifeSimulationManager.swift` — particle/silhouette поверх юнита.
- `Sources/CityDeveloper/Game/IsoBuilder.swift` — только импорт `groundTile(...)` из `TileTextureFactory`, никаких правок самого `IsoBuilder`.
- `Sources/CityDeveloper/Game/RoadConnector.swift`, `Game/CitizenSprites.swift` — арт жителей/дорог, не пересекается.
- `concept/*.md` (Concept/Diff/Current/Backlog/Bugs) — обновляются отдельной командой `/upd-concept` после `/run`.

### Команды проверки (для DoD)

- Компиляция: `swift build`
- Тесты: `swift test`
- Ручная проверка:
  1. `swift run CityDeveloper`
  2. ⌘⌥G (explore-режим).
  3. Глазами: ≥ 4 биома видны без зума на конкретный участок (AC 1).
  4. Глазами: на стыках разных биомов виден переход, не «ступенька» (AC 2).
  5. Debug FPS (`showsFPS = true`): пустой город ≥ 60 FPS, 500+ юнитов (bench из TASK-025) ≥ 55 FPS (AC 3).
  6. Юниты/жители/руины из live-добавления видны корректно поверх биомов (AC 4).
  7. Старого зелёного квадрата нет ни в одном режиме (AC 5).

### Сложность

`middle`

**Обоснование:** 3 новых файла (BiomeRenderer, BiomeMapReader, TileTextureFactory) + точечные правки в 2 существующих (GameScene, Palette); нет new framework / security / migrations; стандартный SpriteKit (`SKTileMapNode`/`SKTileSet`/`SKTileGroup`). Алгоритм edge-aware выбора группы и overlay требует аккуратности, но прямолинеен.

### Ожидаемое время

M (≤1д)

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: middle_
_Объём: M_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Done-критерий проверен в реальном использовании (на экране видны минимум 4 биома с плавными переходами)

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Тесты не сломаны
- [ ] Нет хардкод-строк (i18n/env где требует проект)

#### Обновление документации
- [ ] `current.md`: F-02 → пересмотреть статус (теперь земля — настоящие тайлы), F-15 → ⚠️ (без зума и реинициализации)
- [ ] `diff.md`: D-15 не закрывать — закрывается только после TASK-030; D-02 пересмотреть, если SKTileMapNode попадает сюда (решает лид)
- [ ] Новые идеи → `backlog.md`, новые баги → `bugs.md`

---

## Статус

`[ ] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[x] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-23
- Spec-review: approved
- Blocked-by: TASK-026, TASK-027
- Готова к работе: 2026-05-22
- Lead-model: opus
- Plan-review: revised (round 2 approved)
- Завершена: 2026-05-22
- Коммит: (см. git log)
