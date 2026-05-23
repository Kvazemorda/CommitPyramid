# TASK-025: Изометрический луг через SKTileMapNode + проверка FPS на 500+ юнитах (F-02)

## Связь
- **F-02** Изометрический рендер города (concept.md)
- **D-02** из Diff.md
- **Приоритет:** P0

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим

Закрыть последний хвост по F-02. Сейчас «земля» под городом — один большой
`SKSpriteNode` 8000×8000 цвета `nileGreen`. Это даёт зелёный квадрат,
не изометрическую сетку, и не масштабируется на «биомы» (D-15) — нет понятия
«тайл». Заменяем эту подложку на полноценную изометрическую тайл-карту
средствами SpriteKit (`SKTileMapNode` с `tileSetType = .isometric`), при этом
сохраняем уже работающие pan/zoom камеры и iso-координаты юнитов
(`tileWidth = 64`, `tileHeight = 32`).

Параллельно фиксируем, что F-02 не имеет подтверждения по производительности:
Done-критерий требует 60 FPS на 500+ юнитах, но реального замера нет. В этой же
задаче делаем замер и сохраняем артефакт.

Эта задача не трогает арт самих юнитов / зданий (F-13), не вводит биомы (D-15)
и не делает миникарту (B-NN). Только земля + измерение.

### Пользовательский сценарий

1. Юзер запускает приложение в explore-режиме (⌘⌥G).
2. Вместо плоского зелёного квадрата под городом видна изометрическая
   тайл-сетка: ромбовидные тайлы 64×32, выложенные в шахматном
   изо-порядке, базовый цвет травы (`nileGreen`). Стыки тайлов не видны
   (нет щелей/просветов фона).
3. Юзер делает drag мышью — камера панорамируется, сетка движется вместе
   с городом без рывков и без артефактов на краях.
4. Юзер крутит scroll/pinch — камера зумится в диапазоне, аналогичном
   текущему (0.3×–3.0×). На любом уровне зума сетка выглядит цельной,
   тайлы не «рассыпаются».
5. Юзер открывает встроенный отладочный оверлей FPS (см. AC) и видит
   текущий FPS поверх сцены. При сценарии «500 юнитов на карте» FPS
   стабильно ≥ 60 на типичном Mac M-серии.
6. Юзер закрывает оверлей, продолжает играть — внешне ничего не изменилось
   по сравнению с прошлой версией, кроме того, что земля теперь «тайловая».

### Acceptance criteria

- [ ] **Земля — `SKTileMapNode` isometric.** В `GameScene` луг
      реализован через `SKTileMapNode` с `tileSetType = .isometric`,
      `tileSize = CGSize(width: 64, height: 32)` (совпадает с существующей
      `isoPosition`). Прежний `SKSpriteNode(color: nileGreen, size: 8000×8000)`
      удалён из сцены.
- [ ] **Размер карты ≥ текущая видимая область.** Тайл-карта покрывает
      как минимум прямоугольник, эквивалентный сегодняшнему лугу
      (8000×8000 pt в мировых координатах). Конкретный
      `numberOfColumns × numberOfRows` — на усмотрение лида (ориентир:
      256×256 тайлов при tile 64×32 = 16384×8192 pt диагональ;
      допустимо меньше, если 8000×8000 покрывается). Центр карты — в
      точке `(0, 0)` мировых координат, чтобы существующая `isoPosition`
      не требовала смещения.
- [ ] **Базовый тайл травы.** В `SKTileSet` зарегистрирован минимум один
      `SKTileGroup` — «grass» — с заливкой `Palette.nileGreen`. Источник
      изображения тайла: программно сгенерированная ромб-текстура (path
      diamond → `SKTexture(image:)`) или статичный ассет PNG 64×32 — лид
      выбирает (**вариант A: программная генерация в `IsoBuilder` или
      отдельном `TileFactory`; вариант B: PNG в `Assets.xcassets/Tiles/` —
      решит lead**).
- [ ] **Заполнение всей карты grass-тайлом.** При инициализации сцены все
      ячейки `SKTileMapNode` заполняются `grass`-группой (один проход
      `fill(with:)` или эквивалент). Никаких пустых ячеек (видимых как
      «дыра» в фоне). Заполнение делается один раз при создании сцены,
      не каждый кадр; `SKTileMapNode` сам рендерит только видимые тайлы
      (на это полагаемся — ручной culling не нужен).
- [ ] **Стыки тайлов не видны.** Между соседними тайлами нет щелей,
      просветов фона `skyDay` и муара на стандартном зуме (1×) и на
      крайних значениях (0.3×, 3.0×). Допустим лёгкий aliasing на краях
      ромбов — это ожидаемо для растровых тайлов.
- [ ] **zPosition подложки ≤ `-1000`.** Тайл-карта рендерится под
      существующим водяным знаком `CityDeveloper` (zPosition = -500) и
      под всеми юнитами / районами. Сохраняем текущий контракт
      `zPosition = -1000` или ниже — водяной знак и все игровые объекты
      должны оставаться поверх.
- [ ] **Pan/zoom работают как раньше.** Существующие `mouseDragged`
      и `scrollWheel` не меняются по сигнатуре и поведению (диапазон зума
      0.3–3.0, инверсия по Y сохраняется как сейчас). На drag/zoom не
      появляется визуальных артефактов на сетке (мерцание, тиринг,
      «прыжки»).
- [ ] **Юниты и районы рисуются поверх тайл-карты без смещения.**
      Существующая `isoPosition(grid:)` не меняется, юниты и
      district-маркеры визуально остаются в тех же мировых координатах
      относительно сцены, что и до задачи (smoke-тест: добавь два юнита
      на координатах `(0,0)` и `(5,5)` — ромб тайла под юнитом
      выровнен с iso-«пьедесталом» юнита, отклонение по X/Y ≤ 1 px на
      зуме 1×).
- [ ] **Debug FPS overlay (toggle).** В `GameScene` (или `SceneBridge`)
      добавлен флаг для включения отладочного FPS-оверлея. Способ
      переключения — на усмотрение лида (**вариант A: горячая клавиша
      ⌘⌥F в explore-режиме; вариант B: галочка в Settings; вариант C:
      `showsFPS = true` через `SKView` — решит lead**). При включении —
      на экране видны: текущий FPS, число `drawCalls`, число `nodeCount`
      (стандартные `SKView.showsFPS / showsDrawCount / showsNodeCount`).
- [ ] **Бенчмарк-сценарий 500+ юнитов.** Добавлен dev-режим
      (CLI-флаг `--bench-units 500` или меню «Debug → Spawn 500 test
      units» — решит lead), который при старте создаёт ровно 500 синтетических
      юнитов (через тот же `UnitPlanner` / `drawUnit`) разнесённых по
      случайным `GridPoint` в радиусе 60 тайлов от центра. Бенчмарк должен
      быть детерминированным (фиксированный seed) — чтобы замер
      воспроизводился.
- [ ] **Замер FPS на 500 юнитах ≥ 60.** На устройстве уровня MacBook
      Air M2 / Mac mini M1 или новее (минимально, на чём ведётся
      разработка) при запущенном бенчмарк-сценарии 500 юнитов, окно
      в explore-режиме,
      зум 1×, debug overlay включён — средний FPS за 10 секунд устойчивого
      pan'а ≥ 60. Артефакт — скриншот overlay + одна строка в `concept/reports/`
      или в коммит-сообщении: дата, модель Mac, версия macOS, средний FPS,
      min FPS, drawCalls, nodeCount.
- [ ] **Сцена не утекает памятью при destroy.** При закрытии окна и
      повторном открытии (mode toggle wallpaper↔explore) тайл-карта не
      пересоздаётся каждый раз с нуля (или, если пересоздаётся, — старая
      деаллоцируется без retain-cycle, что подтверждается отсутствием
      роста `nodeCount` от итерации к итерации).
- [ ] **Done-критерий F-02 проверен.** См. блок ниже — выполняется
      целиком после задачи.

### Что НЕ делаем (границы скоупа)

- **Не делаем биомы / разные типы тайлов (D-15).** Только один тайл —
  «grass». Песок, вода, мостовая — отдельная задача после.
- **Не меняем арт юнитов и зданий (F-13).** `IsoBuilder.cube` и
  `UnitSprites` не трогаем.
- **Не меняем формулу `isoPosition`.** Если `SKTileMapNode` требует
  смещения origin для совпадения координат — корректировку делаем
  через `position` самого тайл-нода, а не правкой `isoPosition`.
- **Не добавляем миникарту, рулер, координатный grid-оверлей** —
  это backlog.
- **Не делаем декорации на лугу** (камни, кусты, тропы) — это уже
  F-05 / D-15.
- **Не оптимизируем `IsoBuilder.cube` / `pyramidRoof`** в этой задаче.
  Если бенчмарк покажет, что узкое место именно там (а не в подложке) —
  фиксируем в Backlog отдельным пунктом, не правим здесь.
- **Не делаем культинг (frustum culling) для тайлов вручную** —
  `SKTileMapNode` сам не рисует невидимые ячейки. Если этого
  недостаточно — это сигнал к отдельной задаче.
- **Не вводим параллельный sandbox-режим** для бенчмарка как
  отдельное приложение — бенчмарк живёт внутри основного бинаря под
  флагом / debug-меню.

### Edge cases

- [ ] **Старый snapshot сохраняет юниты на координатах за пределами
      тайл-карты.** Если карта `256×256`, а юнит был сохранён на
      `GridPoint(x: 200, y: 200)` — тайл-карта в этой точке всё равно
      есть (256×256 покрывает до x=128/y=128 от центра — может не
      покрывать). Решение: либо размер карты больше (≥ диапазона
      `DistrictPlanner`), либо за пределами карты — fallback
      `backgroundColor = nileGreen` у `SKScene`, чтобы не было
      `skyDay`-провала. Лид выбирает.
- [ ] **`scaleMode = .resizeFill` + произвольный размер окна.** Окно
      может растягиваться от 800×600 до full-screen 5120×2880 (XDR).
      Тайл-карта 8000×8000 покрывает оба, но на крайнем zoom-out
      (0.3×) виден край карты. Решение: либо `backgroundColor = nileGreen`,
      либо увеличить карту, либо зажать min-zoom так, чтобы край не
      попадал в кадр. Решит лид (P2 — UX «увидел край мира» допустим
      для MVP, главное — не дыра в `skyDay`).
- [ ] **Pan ушёл сильно за край карты.** Юзер протянул камеру на
      `(50000, 50000)` — за тайл-картой. Решение: либо clamp `cameraNode.position`
      в `mouseDragged` (квадрат ≈ size of tileMap), либо
      `backgroundColor = nileGreen` (виден фон цвета травы, не `skyDay`).
      В MVP — `backgroundColor = nileGreen` + опциональный clamp в будущем.
- [ ] **`SKTileMapNode` на macOS 14 sonoma — известные баги с
      drawCount.** На некоторых конфигурациях `showsDrawCount` показывает
      странные значения для тайл-карт. Не воспринимать как
      блокер — критерий замера: FPS, а не drawCalls. drawCalls — для
      справки.
- [ ] **Window paused при `willResignActive`.** Сейчас `view.isPaused = true`
      при уходе окна в фон. Это значит, FPS-замер нельзя делать в фон-режиме.
      Бенчмарк ставится только в explore-режиме (active window).
- [ ] **Текстура тайла размывается на high-DPI (Retina).** Если
      используем программный path → texture, рендерим в `@2x` (128×64
      points → texture с `size = 64×32` логических). Иначе на Retina —
      blur. Лид: ImageRenderer scale=2 или `SKShapeNode` cropped.
- [ ] **Старый луг был с `zPosition = -1000`, юниты — с большим z.**
      Сохраняем тот же контракт: тайл-карта `zPosition = -1000`, watermark
      `-500`, юниты ≥ 0. Проверить, что ничего не «упало» под карту.
- [ ] **500 юнитов на одном `GridPoint`.** В synthetic бенчмарке
      возможны коллизии случайных координат. Не критично, но визуально
      «куча кубов». Допустимо для замера.
- [ ] **Тайл-сет не сохраняется в `events.jsonl` и snapshot.** Тайл-карта —
      чисто визуальный слой, не часть state. Replay не должен её
      пересоздавать или валидировать. Если случайно попало в snapshot —
      ошибка лида, надо вычистить.
- [ ] **`mouseDragged` инвертирует Y.** Сейчас `cameraNode.position.y += event.deltaY`,
      без инверсии Y у `SKView`. При смене подложки не сломать.
- [ ] **Тёмная тема macOS.** Палитра не зависит от light/dark — это
      статические токены. `nileGreen` одинаково в любом режиме.

### Зависимости

- **F-02** — частично реализован. Эта задача закрывает оставшиеся 2
  пункта Done-критерия (тайл-карта + замер 60 FPS на 500+ юнитах).
- **F-05** Симуляция жизни — closed. Бенчмарк должен включать активный
  `LifeSimulationManager` (не выключать его на замере — реальный сценарий).
- **F-10** Citizen sprites — closed. Бенчмарк включает `CitizenManager`.
- **F-13** Арт юнитов — closed. Тестовые юниты идут через `UnitSprites`.
- **D-15** Биомы — **не зависим**, но эта задача упрощает её внедрение
  (тайл-сет уже готов, остаётся добавить группы).
- Внешних сервисов / секретов / миграций state нет.
- Артефакт замера: добавить запись в `concept/reports/` (или указать
  в коммит-сообщении — решит lead).

### Дизайн

Из `DesignConcept.md`:
- **Базовый цвет тайла** — `nileGreen` (`#4A6741`).
- **Размер тайла** — `tileSize = 64 × 32 pt` (токен `tileSize`).
- **Стилистика** — плоская, без градиента и тени на самом тайле.
  Опционально лид может добавить лёгкий внутренний градиент 5–10 %
  для «жизни» (как палитра рисует растительность с оттенком), но
  не обязательно.
- **Контуры тайлов:** **не рисовать** (в палитре нет «линия сетки»;
  тайлы должны выглядеть монолитно). Если нужен debug-grid — это
  отдельный overlay в backlog.
- **FPS-overlay** — системный, через `SKView.showsFPS`. Своего UI не
  делаем.

### Done-критерий

_Из concept.md F-02 (дословно):_

> На карте видна изометрическая сетка, по которой можно панорамировать
> (drag) и зумить (scroll/pinch). FPS не падает ниже 60 в режиме explore
> при 500+ юнитах на типичном Mac (M-серия). Тайлы корректно сортируются
> по глубине.

---

## 🛠 Технический разбор от тимлида

_Статус: [x] готово_
_Lead-model: opus_
_Plan-review: approved_

### Анализ текущего состояния

**Что уже есть и переиспользуем:**
- `GameScene.didMove(to:)` — единственная точка инициализации сцены, создаёт `world: SKNode`, `cameraNode: SKCameraNode`, привязывает `lawn`, watermark, инициализирует `LifeSimulationManager` и `CitizenManager` (`Sources/CityDeveloper/Game/GameScene.swift:30-92`).
- Текущая «подложка» — `SKSpriteNode(color: Palette.nileGreen, size: 8000×8000)` с `zPosition = -1000` (строки `GameScene.swift:38-41`). Это единственный фрагмент, который полностью удаляется в этой задаче.
- Изо-координаты юнитов: `isoPosition(grid:)` использует константы `tileWidth = 64`, `tileHeight = 32` (`GameScene.swift:14-15, 409-415`). Эти значения совпадают с требуемым `tileSize` `SKTileMapNode`. Формулу не трогаем.
- Watermark `CityDeveloper` имеет `zPosition = -500` и крепится к `world` (`GameScene.swift:45-51`) — должен оставаться поверх тайл-карты.
- Камера: `cameraNode` начало в `(0, 0)`, `mouseDragged` сдвигает `position` (инверсия Y по `+= event.deltaY`), `scrollWheel` зумит в диапазоне 0.3–3.0 (`GameScene.swift:437-455`). Никаких изменений по сигнатуре.
- Pause-on-background через `NSApplication.willResignActiveNotification` → `view?.isPaused = true` (`GameScene.swift:85-91`). Resume через `WindowModeManager.onModeChange` в `AppDelegate.swift:81-84`.
- В `IsoBuilder` уже есть `groundTile(width:height:fillColor:strokeColor:)` (`IsoBuilder.swift:162-180`) — рисует ромб 64×32 через `CGPath`. Эту функцию используем как шаблон для генерации текстуры тайла.
- Цвет травы — `Palette.nileGreen` (`Theme/Palette.swift:9`, RGB 0.29/0.40/0.25).
- Запуск через env-флаги уже есть (`AppDelegate.swift:86` — `CITY_START_EXPLORE`). Аналогично добавляем `CITY_BENCH_UNITS`.
- `UnitSprites.makeStageNode(unit:stageOverride:)` — корректная точка создания тестового юнита со всеми визуальными слоями (shadow + ground + building). Для бенчмарка не нужен `engine.applyTaskCompleted` — достаточно вызвать `drawUnit`-эквивалент.
- Тесты живут в `Tests/CityDeveloperTests/` — пакетная сборка SwiftPM.
- Папка `concept/reports/` существует (пустая) — туда складываем артефакт замера.

**FPS-метрик сейчас нет** — `showsFPS / showsDrawCount / showsNodeCount` нигде не выставлены (grep пустой по `Sources/`).

**Ассеты:** `Sources/CityDeveloper/Resources/Buildings/` есть, но `Tiles/` нет. Папка `Resources` подключена через `.process("Resources")` в `Package.swift:11-13`. Программная генерация ромба через `SKView.texture(from: SKShapeNode)` или `CGContext` — путь без новых ассетов.

### Архитектурное решение

Используем **`SKTileMapNode` + `SKTileSet` с типом `.isometric`**, как и предписывает spec. Текстура тайла — **программно сгенерированный ромб** (вариант A): создаём `CGImage` 128×64 px (×2 для Retina) с залитым `nileGreen`-ромбом без stroke, оборачиваем в `SKTexture`, кэшируем как `static let` внутри нового типа `IsoTileFactory` (отдельный файл — чтобы `IsoBuilder` остался про геометрию зданий). Без stroke — чтобы стыки тайлов выглядели монолитно (AC «стыки не видны»). Текстура размером 128×64 даёт `tileSize = 64×32` логических points и резкость на Retina.

`SKTileMapNode` создаётся в `GameScene.didMove(to:)` один раз, размер `256 × 256` тайлов = `16384 × 8192` pt диагональ, центр через `position = .zero` (по умолчанию `SKTileMapNode` центрирован в собственном `(0, 0)`). 256×256 покрывает `DistrictPlanner` ровно: spacing=14, `nextDistrictIndex` редко превышает 50-й слой, что соответствует максимум `(±42, ±42)` — глубоко внутри 128×128 половин-радиуса карты. Старого `lawn`-спрайта больше нет.

**Защита от «края мира»:** `scene.backgroundColor = Palette.nileGreen` (раньше был `skyDay`). Это закрывает edge cases «pan ушёл за карту» и «zoom-out 0.3× видит край» без введения clamp'а — край карты сольётся с фоном того же цвета. `skyDay` нигде больше не используется как реальный визуал — пусто за тайл-картой это нормально, цвет всё равно травяной.

**Debug overlay:** на флаг — комбинация двух источников.
1. Env `CITY_DEBUG_OVERLAY=1` — выставляет `showsFPS/showsDrawCount/showsNodeCount = true` при создании `SKView` в `ContentView` (через `SpriteView`-API нет прямого доступа, поэтому через `SKView`-инициализацию в `findSpriteKitView` или через `onAppear` на `SpriteView`).
2. Hotkey ⌘⌥F в explore-режиме — toggle тех же флагов рантайм.
Реализация флага — добавить `keyDown(with:)` в `GameScene` (его сейчас нет — будет первая клавиатурная подписка). Доступ к `view` идёт через `self.view`.

**Bench-режим:** при наличии `CITY_BENCH_UNITS=N` в `AppDelegate.applicationDidFinishLaunching` (после `modeManager.enterExploreMode()`) вызывается новый метод `GameScene.spawnBenchUnits(count:seed:)` — создаёт N синтетических `UnitState` с детерминированным `SeededGenerator` (Linear Congruential), распределяет их в радиусе 60 тайлов от `(0,0)`, рисует через **существующий приватный** `drawUnit(_:project:)`. Чтобы `unit.projectId` не падал — создаём один синтетический `ProjectState` с `id = "__bench__"`, кладём в локальный кэш сцены (не в `engine.state`, чтобы бенчмарк не попадал в snapshot/events). Edge case «тайл-сет не в snapshot» — выполнено автоматически: `SKTileMapNode` чисто визуальный, `engine.state` его не знает; bench-юниты тоже не в state.

**Артефакт замера:** скрипт-инструкция в Done-секции — оператор запускает `CITY_BENCH_UNITS=500 CITY_DEBUG_OVERLAY=1 swift run CityDeveloper`, делает скриншот overlay'а через 10 сек pan'а, сохраняет в `concept/reports/2026-MM-DD-fps-bench-500.md` (формат: дата, модель Mac, версия macOS, средний/min FPS, drawCalls, nodeCount + ссылка на screenshot).

### Пошаговая декомпозиция

**Шаг 1.** [AC: 3, 5] Создать `Sources/CityDeveloper/Game/IsoTileFactory.swift` — фабрика текстуры и тайл-сета.
```swift
enum IsoTileFactory {
    static let tileWidth: CGFloat = 64
    static let tileHeight: CGFloat = 32

    /// Кэш-singleton: текстура ромба-травы 128×64 px (Retina-ready).
    static let grassTexture: SKTexture = makeGrassTexture()

    /// SKTileSet с единственной группой "grass" (isometric).
    static let isometricGrassSet: SKTileSet = makeGrassSet()

    private static func makeGrassTexture() -> SKTexture {
        let pixelSize = CGSize(width: 128, height: 64) // ×2 для Retina
        let image = NSImage(size: pixelSize)
        image.lockFocus()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 64, y: 64))   // top
        path.line(to: NSPoint(x: 128, y: 32))  // right
        path.line(to: NSPoint(x: 64, y: 0))    // bottom
        path.line(to: NSPoint(x: 0, y: 32))    // left
        path.close()
        Palette.nileGreen.setFill()
        path.fill()
        image.unlockFocus()
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest // ромб — плоский, без размытия на стыках
        return texture
    }

    private static func makeGrassSet() -> SKTileSet {
        let definition = SKTileDefinition(texture: grassTexture,
                                          size: CGSize(width: tileWidth, height: tileHeight))
        let group = SKTileGroup(tileDefinition: definition)
        group.name = "grass"
        let set = SKTileSet(tileGroups: [group], tileSetType: .isometric)
        set.defaultTileSize = CGSize(width: tileWidth, height: tileHeight)
        return set
    }
}
```
Файл-новичок. Не трогает существующий `IsoBuilder`.

**Шаг 2.** [AC: 1, 2, 4, 6] В `GameScene.didMove(to:)` (`Sources/CityDeveloper/Game/GameScene.swift:30-43`) **удалить** `let lawn = SKSpriteNode(color: Palette.nileGreen, size: CGSize(width: 8000, height: 8000))` блок целиком (строки 38-41), **поменять** `backgroundColor = Palette.skyDay` → `backgroundColor = Palette.nileGreen`, **добавить** создание тайл-карты:
```swift
let tileMap = SKTileMapNode(
    tileSet: IsoTileFactory.isometricGrassSet,
    columns: 256, rows: 256,
    tileSize: CGSize(width: 64, height: 32)
)
tileMap.position = .zero
tileMap.zPosition = -1000
tileMap.fill(with: IsoTileFactory.isometricGrassSet.tileGroups.first)
world.addChild(tileMap)
```
`fill(with:)` гарантирует, что AC «заполнение всей карты» закрыт одной операцией без per-frame работы (`SKTileMapNode` сам ленится на видимые ячейки).

**Шаг 3.** [AC: 9] Добавить debug-overlay toggle в `GameScene`. В конце `didMove(to:)` (после строки 91, перед `}`) — прочитать env:
```swift
if ProcessInfo.processInfo.environment["CITY_DEBUG_OVERLAY"] != nil {
    setDebugOverlay(enabled: true)
}
```
Метод `setDebugOverlay(enabled:)` — приватный, выставляет `view?.showsFPS = enabled`, `view?.showsDrawCount = enabled`, `view?.showsNodeCount = enabled`. Хоткей-toggle ⌘⌥F: переопределить `override func keyDown(with event: NSEvent)` — проверить `event.keyCode == kVK_ANSI_F` (Carbon) и `event.modifierFlags.contains([.command, .option])`, переключить через сохранённый `var debugOverlayEnabled: Bool = false`. `keyDown` сейчас в `GameScene` отсутствует — это первая подписка, не сломает существующий ввод (mouse-обработчики не конфликтуют).

**Шаг 4.** [AC: 10] Добавить bench-режим. В `GameScene` — публичный метод:
```swift
/// Спавнит ровно `count` синтетических юнитов в радиусе 60 тайлов от центра.
/// Детерминирован при одинаковом seed.  
/// Юниты НЕ попадают в engine.state — это чисто визуальная нагрузка.
func spawnBenchUnits(count: Int, seed: UInt64 = 42) {
    guard didAttach else { return }
    var rng = SeededGenerator(seed: seed)
    let kinds = UnitKind.allCases
    let stages = [1, 2, 3, 4, 5]
    let benchProject = ProjectState(
        id: "__bench__", name: "Bench",
        createdAt: Date(), lastActivityAt: Date(),
        taskCount: count, stage: 3, decayLevel: 0,
        lastDecayLogged: 0, districtOrigin: .init(x: 0, y: 0),
        unitIds: []
    )
    for _ in 0..<count {
        let x = Int.random(in: -60...60, using: &rng)
        let y = Int.random(in: -60...60, using: &rng)
        let kind = kinds.randomElement(using: &rng)!
        let tier = stages.randomElement(using: &rng)!
        let unit = UnitState(
            id: UUID(), projectId: benchProject.id,
            kind: kind, position: GridPoint(x: x, y: y),
            tier: tier, decayLevel: 0,
            taskTitle: nil, taskTs: Date(), taskSource: "bench"
        )
        drawUnit(unit, project: benchProject)
    }
}
```
Здесь `SeededGenerator` — крошечная структура LCG, можно добавить fileprivate в том же файле (или внутри `GameScene` как nested). `drawUnit` уже приватный, но мы вызываем из того же `GameScene` — ОК. В `AppDelegate.applicationDidFinishLaunching` (после `enterExploreMode()`) — env-флаг:
```swift
if let raw = ProcessInfo.processInfo.environment["CITY_BENCH_UNITS"], let n = Int(raw), n > 0 {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        self?.scene.spawnBenchUnits(count: n)
    }
}
```
Задержка 0.5s — чтобы `didMove(to:)` гарантированно отработал (модель сцены требует `didAttach == true`).

**Шаг 5.** [AC: 11, 13] Артефакт замера. Создать `concept/reports/2026-05-DD-fps-bench-500.md` после ручного прогона. Шаблон — в команде проверки ниже. Это **не код-изменение** — оператор делает после успешного билда.

**Шаг 6.** [AC: 12] Проверка отсутствия утечек. `SKTileMapNode` живёт внутри `world`, который — child сцены. При уничтожении сцены (toggle mode пересоздаёт `SKView`? — проверить) или закрытии окна `world.removeFromParent` каскадно удалит `tileMap`. Поскольку текстура и `SKTileSet` кэшированы как `static let` в `IsoTileFactory` — они переживают пересоздание сцены, что **хорошо** (не пересоздаём при каждом open). На уровне сцены утечек нет, т.к. `tileMap` не имеет strong-ref на `self`. Документировать это в комментарии над `let tileMap = ...`.

**Шаг 7.** [AC: 8] Проверка координат. После Шага 2 — manual smoke: запустить с `CITY_BENCH_UNITS=2` и фиксированным seed, где юниты на `(0,0)` и `(5,5)`. Визуально ромб тайла под юнитом совпадает с ground-тайлом юнита (отклонение ≤1 px). Если есть смещение — корректировать через `tileMap.position`, не правя `isoPosition`. Эмпирически `SKTileMapNode` центрирован сам, формула `isoPosition` даёт `(0, 0)` для `GridPoint(0, 0)` — должно совпадать без коррекции.

### Edge cases

- **Pan за край карты** (`GameScene.swift:437-441`): `mouseDragged` без clamp'а. Решение — `backgroundColor = Palette.nileGreen` (Шаг 2), так что за тайл-картой виден тот же цвет травы, дыры нет. Clamp — в Backlog.
- **Zoom-out 0.3× видит край карты** (`GameScene.swift:449-455`): тот же `backgroundColor`-фикс. На XDR-мониторе 5120×2880 при 0.3× видимая область ≈ 17000×9600 pt, край карты 16384×8192 близок к границе кадра. Заметить край сложно (одинаковый цвет), артефакт допустим в MVP.
- **`SKTileMapNode` strange `drawCount` на Sonoma 14**: внутри AC и Done-критерия мы меряем FPS, а не drawCalls. drawCalls — справочно. Не блокер.
- **Pause при `willResignActive`** (`GameScene.swift:85-91`): bench-юниты не используют `SKAction.repeatForever` (только fade-in/scale на 0.5 сек), поэтому замораживание сцены не ломает их. FPS-замер делается только в active explore.
- **Retina-блюр текстуры**: создаём `NSImage` 128×64 px (×2 от логического 64×32), `SKTexture.filteringMode = .nearest`. На Retina пиксели 1:1, размытия нет (Шаг 1).
- **zPosition контракт**: тайл-карта `-1000` (Шаг 2), watermark `-500` (`GameScene.swift:50`), юниты `-CGFloat(x+y)` обычно `> -100` (`GameScene.swift:193`), inspector `100000` (`GameScene.swift:484`). Контракт сохранён.
- **mouseDragged Y-инверсия** (`GameScene.swift:437-441`): не трогаем подпись, не меняем поведение.
- **500 юнитов на одном `GridPoint`**: возможно из-за случайной коллизии при `rand%121`. Spec явно допускает «куча кубов» — оставляем.
- **Bench-юниты в snapshot**: bench-`ProjectState` создаётся локально в `spawnBenchUnits`, **не** проходит через `engine.applyTaskCompleted`, **не** пишется в `engine.state.projects`. `engine.saveSnapshot` в `AppDelegate.applicationWillTerminate` (`AppDelegate.swift:145-151`) сохраняет только `engine.state` — bench-юниты в snapshot не попадут. Артефакт замера — отдельный markdown, не state.
- **`UnitKind` `.raw` в bench** (`Data/CityState.swift:24`): `UnitSprites.makeStageNode` для `category = .production` рисует ту же геометрию, что `.workshop` — визуально допустимо. Не падает.
- **Pause бенчмарка от mode-toggle**: если пользователь закрывает explore во время bench — `view.isPaused = true` через `WindowModeManager.onModeChange` (`AppDelegate.swift:81-84`). Бенчмарк замораживается, но юниты остаются — при resume сцена та же. Не утечка.
- **Тёмная тема macOS**: `Palette.nileGreen` — статический RGB, не зависит от темы (`Theme/Palette.swift:9`). OK.

### Файлы для изменения

- `Sources/CityDeveloper/Game/IsoTileFactory.swift` — **новый файл** (Шаг 1).
- `Sources/CityDeveloper/Game/GameScene.swift` — модификация `didMove(to:)`, добавление `keyDown(with:)`, `setDebugOverlay(enabled:)`, `spawnBenchUnits(count:seed:)`, fileprivate `SeededGenerator` (Шаги 2, 3, 4).
- `Sources/CityDeveloper/App/AppDelegate.swift` — добавление env-чтения `CITY_BENCH_UNITS` после `enterExploreMode()` (Шаг 4).
- `concept/reports/2026-05-DD-fps-bench-500.md` — **новый артефакт**, создаётся вручную после прогона (Шаг 5).

### Файлы НЕ трогать

- `concept/Concept.md`, `concept/Diff.md`, `concept/Current.md`, `concept/Bugs.md`, `concept/Backlog.md` — обновляются другими командами (`/sync`, `/upd-concept`).
- `Sources/CityDeveloper/Game/IsoBuilder.swift` — геометрия зданий, к подложке отношения не имеет.
- `Sources/CityDeveloper/Game/UnitSprites.swift` — арт юнитов F-13 (spec явно запрещает).
- `Sources/CityDeveloper/Game/CitizenManager.swift` — F-10, не нужен для подложки.
- `Sources/CityDeveloper/Data/CityState.swift` — модели state, тайл-карта не state.
- `Sources/CityDeveloper/Game/CityEngine.swift` — engine не знает о визуале подложки.
- `isoPosition(grid:)` в `GameScene.swift:409-415` — координаты юнитов, оставляем как есть.
- `mouseDragged`, `scrollWheel` — спец явно запрещает менять сигнатуру/поведение.

### Команды проверки

**Компиляция:**
```bash
cd <repo-root> && swift build 2>&1 | tail -30
```
Ожидание: 0 ошибок, 0 новых warning'ов (существующие warning'и в `DecayEngine.swift`/др. — не наши).

**Тесты (не должны сломаться):**
```bash
cd <repo-root> && swift test 2>&1 | tail -20
```
Ожидание: все тесты `CityDeveloperTests` green.

**Manual smoke 1 — визуал тайл-карты:**
```bash
cd <repo-root> && CITY_START_EXPLORE=1 swift run CityDeveloper
```
Ожидание: explore-режим, под городом — изометрическая сетка ромбов (видна на pan); pan/zoom работают (drag мышью, scroll), на 0.3× и 3.0× нет визуальных дыр; цвет фона за картой = цвет травы.

**Manual smoke 2 — debug overlay:**
```bash
cd <repo-root> && CITY_DEBUG_OVERLAY=1 CITY_START_EXPLORE=1 swift run CityDeveloper
```
Ожидание: в правом нижнем углу `SKView` — FPS / drawCount / nodeCount. ⌘⌥F скрывает/показывает.

**Manual smoke 3 — bench + замер:**
```bash
cd <repo-root> && CITY_BENCH_UNITS=500 CITY_DEBUG_OVERLAY=1 CITY_START_EXPLORE=1 swift run CityDeveloper
```
Ожидание: через ~0.5 сек спавнятся 500 юнитов в кружке радиуса 60 тайлов вокруг центра. Делать pan мышью 10 секунд. Записать средний FPS (visual из overlay), min FPS (наблюдательно), drawCalls, nodeCount. Сохранить скриншот overlay. Создать файл:
```
concept/reports/2026-05-DD-fps-bench-500.md
---
Дата: 2026-05-DD
Mac: <модель, M1/M2/M3>
macOS: <версия>
Сценарий: CITY_BENCH_UNITS=500, explore, zoom 1×, 10 сек pan
Средний FPS: NN
Min FPS: NN
drawCalls: NN
nodeCount: NN
Screenshot: <relative path or inline>
---
```
Пороговое значение: средний FPS ≥ 60.

**Smoke 4 — pause при уходе окна:**
Запустить приложение, перейти в другое приложение (⌘Tab) — `nodeCount` overlay не должен расти при повторном включении (нет утечек подложки).

### Сложность

**middle** — задача требует знания SpriteKit (`SKTileMapNode`, `SKTileSet`, `tileSetType = .isometric`), понимания `NSImage`/`SKTexture` lifecycle на Retina, работы с env-флагами для двух разных режимов, аккуратной интеграции в существующий `didMove(to:)` без поломки z-order и pan/zoom-контракта. Junior справится с программной частью, но риск ошибки в `SKTileMapNode.fill` API и в подгонке текстуры под Retina — выше среднего.

### Объём

**M** — три файла, один новый, ≈ 150 строк кода + ручной артефакт замера. Без миграций state. Без правок engine/планировщиков.

---

---

## ✅ Исполнение

_Исполнитель: sonnet_
_Сложность: M_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Done-критерий F-02 проверен в реальном использовании (визуальный
      smoke + замер 500 юнитов)

#### Технические
- [ ] Компиляция Swift без новых ошибок/варнингов
- [ ] Тесты F-05 / F-10 / F-13 не сломаны
- [ ] `SKTileMapNode` создаётся один раз на сцену, не утекает при
      пересоздании сцены

#### Обновление документации
- [ ] `Current.md`: F-02 → ✅
- [ ] `Diff.md`: D-02 удалён
- [ ] Артефакт замера FPS — в `concept/reports/` или в коммит-сообщении
- [ ] Новые идеи (clamp камеры, биомы, debug-grid) → `Backlog.md`

---

## Статус

`[x] done`

## Метаданные
- Создана PM: 2026-05-22
- Spec-review: revised
- Lead-model: opus
- Plan-review: approved
- Готова к работе: 2026-05-22
- Исполнитель: sonnet
- Завершена: 2026-05-23
- Code-review: approved (sonnet, inline)
- Коммит: —
