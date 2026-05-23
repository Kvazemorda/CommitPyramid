# TASK-026: Шумовая основа карты (seed + поля высоты/температуры/влажности)

## Связь
- **F-15** из Concept.md
- **D-15** из Diff.md (часть 1/5 — фундамент)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-23_

### Что хотим
Получить детерминированный «генератор мира» — стабильное представление карты ≥ 256×256
тайлов, где для каждой клетки известны три скалярных параметра (высота, температура,
влажность). Это фундамент для назначения биомов (TASK-027) и реинициализации
(TASK-030): без воспроизводимого seed нельзя ни сохранить мир, ни пересобрать его
тем же или новым жребием. Само по себе ничего на экране не меняется — это
внутренний слой данных.

### Пользовательский сценарий
1. Игрок запускает игру первый раз — мир молча получает seed (например, на основе
   текущего времени), карта рассчитывается за доли секунды и сохраняется в данные
   игры рядом с `events.jsonl` / `state.json`.
2. Игрок выходит и заходит снова — мир тот же: тот же seed, те же значения по
   клеткам.
3. Игрок (в TASK-030, не здесь) задаёт другой seed — мир ощутимо другой, но
   снова стабильно воспроизводимый при том же значении.

### Acceptance criteria
- [ ] При первом запуске генерируется карта размером не меньше 256×256 клеток
      и сохраняется в данные игры (`~/Library/Application Support/CityDeveloper/`),
      переживая перезапуск приложения.
- [ ] Для каждой клетки доступны три поля — высота, температура, влажность —
      каждое в нормализованном диапазоне `0.0…1.0` (или эквивалентном, согласованном
      по всей карте).
- [ ] Один и тот же seed на одной и той же версии генератора даёт идентичные
      значения по всем клеткам (детерминизм проверяется повторным запуском без
      сохранённой карты, либо отдельной командой регенерации с тем же seed).
- [ ] Поля «плавные»: разница соседних клеток по любому из параметров типично
      небольшая, без резких ступенек — это нужно для плавных переходов биомов
      (TASK-028).
- [ ] Генерация карты 256×256 укладывается в ≤ 1 секунду на типичной M-серии
      (не блокирует UI на видимое время).

### Что НЕ делаем (границы скоупа)
- Не назначаем биомы и не рисуем ничего на экране — это TASK-027 и TASK-028.
- Не реализуем UI «новая карта / новый seed» — это TASK-030.
- Не делаем карты крупнее 256×256 на этом шаге; более крупные размеры — на
  будущее, важно лишь чтобы структура данных не мешала вырасти.
- Не оптимизируем под фоновую регенерацию во время игры.

### Edge cases
- [ ] Файл сохранённой карты отсутствует или повреждён → молча перегенерировать
      из сохранённого seed; если seed тоже отсутствует — сгенерировать новый и
      сохранить.
- [ ] Версия генератора изменилась с прошлого запуска (несовместимый формат) →
      пересобрать карту с тем же seed, в `errors.log` оставить отметку, игру не
      ронять.
- [ ] Запрос значений за пределами карты (отрицательные координаты, > 256) →
      безопасный дефолт (например, граничные значения), без падения.
- [ ] Seed = 0 / отрицательный / огромный — работает корректно, без переполнений
      и пустой карты.

### Зависимости
- Внешних нет. Это первый кирпич D-15: TASK-027 и TASK-028 строятся поверх,
  TASK-030 использует механизм seed для смены мира.

### Дизайн
Не применимо (нет UI).

### Done-критерий
_Из Concept.md F-15:_ При первом запуске генерируется карта ≥ 256×256 тайлов с не менее
чем 4 разными биомами, соединёнными плавными переходами. Карта воспроизводима из seed.
Кнопка «Сбросить карту» + подтверждение → новая генерация, кварталы переразмещаются.
Зум позволяет увидеть всю карту в одном экране. Новый квартал рядом с рекой получает
водные/речные юниты с заметно большей вероятностью, чем равномерная.

---

## 🛠 Технический разбор от тимлида

_Статус: [x] разобрано_
_Автор: lead (agent, Opus)_
_Дата: 2026-05-22_

### Анализ

**Что есть сейчас:**
- Поверхность мира — плоский `SKSpriteNode(color: nileGreen, size: 8000×8000)` в `GameScene.didMove(to:)` (`Sources/CityDeveloper/Game/GameScene.swift:38-41`). Никакого понятия «клетка» / «тайл-данные» нет; TASK-025 переведёт это в `SKTileMapNode`, но эта задача — про **слой данных**, а не про рендер.
- Координаты клеток — `GridPoint(x: Int, y: Int)` (`Data/CityState.swift:72-75`), центр карты = (0, 0). Преобразование в экранные координаты — `GameScene.isoPosition(grid:)` (`Game/GameScene.swift:409-415`), формула классическая иза `(x-y)·tw/2, (x+y)·th/2`.
- `DistrictPlanner.allocateNextOrigin(currentIndex:)` (`Game/DistrictPlanner.swift:5-28`) детерминированно раскладывает кварталы по растущей спирали от (0, 0) с шагом `spacing = 14`. Никакого знания о биомах/полях у него сейчас нет (это уйдёт в TASK-030). Для оценки диапазона: `n` кварталов → радиус ≈ `(sqrt(n)/2)·14`. Для 300 кварталов это ≈ ±120 клеток, т.е. карта 256×256 с центром в (0, 0) (диапазон –128…+127) перекрывает обозримое будущее.
- `CityState` (`Data/CityState.swift:90-102`) — event-sourced, сохраняется через `SnapshotStore` (`Data/SnapshotStore.swift`) в `AppPaths.stateJson`. Карта мира **в state намеренно не должна попадать** (по TASK-025 явный edge: «Тайл-сет не сохраняется в `events.jsonl` и snapshot. Тайл-карта — чисто визуальный слой, не часть state.»). Значит, для шумовой карты нужен **отдельный sidecar-файл** рядом со `state.json`.
- `AppPaths` (`Data/AppPaths.swift:3-20`) — единая точка путей в `~/Library/Application Support/CityDeveloper/`. Сейчас знает про `tasks.jsonl`, `events.jsonl`, `state.json`, `ingestion-state.json`, `errors.log`, `catchup-state.json`. Сюда добавится новый файл.
- `AppDelegate.applicationDidFinishLaunching` (`App/AppDelegate.swift:22-127`) синхронно создаёт `SnapshotStore` + `CityEngine` до построения сцены. Бутстрап карты мира должен встать сюда же, **до** создания `GameScene`, чтобы при `didMove(to:)` шумовая карта уже была доступна (она ещё не нужна для рисования в этой задаче, но в TASK-028 будет нужна).
- `ErrorsLog.write(_:)` (`Data/ErrorsLog.swift`) — готовый канал для записи в `errors.log`. Используется именно так в `SnapshotStore.load()` при invalid snapshot.
- Существующие seed/random в коде — поверхностные: `CitizenSprites.makeCitizen(seed:)` индексирует палитру (`Game/CitizenSprites.swift:17-21`); `LifeSimulationManager` использует `Double.random(in:)` для дрожаний анимации — не детерминирован, но это намеренно (визуал, не state). Никакого готового seed-based генератора полей нет — строим с нуля.
- **GameplayKit доступен** на macOS 14 как системный фреймворк (нативно поставляется с SDK). `GKPerlinNoiseSource` / `GKBillowNoiseSource` + `GKNoise` + `GKNoiseMap` дают именно «Perlin/simplex шум, нормализуемый в диапазон». Альтернативно — самописный value/Perlin-noise на seedable PRNG (`SeededGenerator: RandomNumberGenerator` поверх `xorshift64*` / `splitmix64`). GameplayKit короче, читабельнее, точно детерминирован при фиксированном `seed: Int32`. Минус: API оперирует `Float` (для нашего точностного диапазона нормали → нормально), и noise значения в `[-1, +1]` → надо нормализовать в `[0, 1]`.
- Тесты лежат в `Tests/CityDeveloperTests/`: `CityEngineTests`, `CitizenManagerTests`, `JournalFilterTests`. Новый файл с unit-тестами добавляется по тому же шаблону (без зависимости от SpriteKit-сцены).

**Что планируется поверх:**
- TASK-027 — биом-классификатор: вход = (height, temperature, humidity) → выход = один из 7 биомов. Полностью полагается на API, которое отдадим из TASK-026.
- TASK-028 — рендер биомов в `SKTileMapNode`.
- TASK-030 — «Сбросить карту» + миграция кварталов; будет дёргать «пересоздать карту с новым seed» — наш API должен это уметь.

### Архитектурное решение

**Главное:** добавить отдельный модуль данных «мир» (seed + три плотных 2D-массива `Float` 256×256), полностью изолированный от `CityState`/event-log, со своей сериализацией в sidecar-файл `worldmap.json`. Никакой завязки на SpriteKit; чистый Foundation + GameplayKit для генерации.

**Структура (новые файлы в `Sources/CityDeveloper/World/`):**

1. `World/NoiseMap.swift` — модель данных:
   - `struct NoiseMap: Codable` с полями `version: Int`, `seed: Int64`, `size: Int` (= 256), `height: [Float]`, `temperature: [Float]`, `humidity: [Float]` (плотные row-major массивы длиной `size*size`).
   - Константа `NoiseMap.currentVersion = 1`.
   - Утилитарные методы `height(at x:Int, y:Int) -> Float`, `temperature(at:)`, `humidity(at:)` — с **граничной выборкой через clamp**: координаты вне `0..<size` → возвращают значение ближайшей клетки на границе (это «безопасный дефолт» из AC4 edge cases). Доступ к buffer — через `index(x,y) = y*size + x` после clamp.
   - Все три поля нормализованы в `0.0...1.0`.

2. `World/NoiseFieldGenerator.swift` — детерминированный генератор:
   - `enum NoiseFieldGenerator { static func generate(seed: Int64, size: Int) -> NoiseMap }`.
   - Использует **GameplayKit**: для каждого из трёх полей создаём `GKPerlinNoiseSource(frequency:octaveCount:persistence:lacunarity:seed:)` с разными значениями `seed`, производными от входного (`heightSeed = Int32(truncatingIfNeeded: seed)`, `tempSeed = Int32(truncatingIfNeeded: seed &+ 0x9E37_79B9_7F4A_7C15)`, `humSeed = ...` — две разные большие константы splitmix64, гарантируем разные паттерны).
   - Параметры шума: `frequency = 1.0`, `octaveCount = 4`, `persistence = 0.5`, `lacunarity = 2.0` — стандартный «плавный» Perlin (для AC «плавные поля» — соседи близки).
   - Через `GKNoise(noiseSource)` → `GKNoiseMap(noise, size: vector_double2(1.0, 1.0), origin: .zero, sampleCount: vector_int2(Int32(size), Int32(size)), seamless: false)`. Затем `.value(at: vector_int2(x, y))` по всем (x, y) → нормализация `(v + 1) / 2` → clamp в `[0, 1]`.
   - **Bench-таргет:** 256×256 × 3 поля × 4 октавы ≈ ~785k сэмплов Perlin (~3M FLOPs) — на M1 укладывается в ≤50 мс. AC1 (≤1 сек) с большим запасом.

3. `World/WorldMapStore.swift` — персистенция (по аналогии с `SnapshotStore`):
   - `final class WorldMapStore { var url: URL; init(url: URL = AppPaths.worldmapJson); func load() -> NoiseMap?; func save(_ map: NoiseMap) -> Bool }`.
   - `load()`: читает файл, декодирует. Если файл отсутствует / повреждён / `version != currentVersion` → пишет диагностику в `ErrorsLog` (без падения) и возвращает `nil`.
   - `save(_:)`: атомарная запись (`Data.write(to: options: .atomic)`), `dateEncodingStrategy = .iso8601` (по тому же шаблону, что `SnapshotStore`).

4. `World/WorldSeedStore.swift` — хранение seed отдельно от карты:
   - `seed` хранится в `UserDefaults` под ключом `com.outbyte.citydeveloper.worldSeed` (по аналогии с `AppSettings`). Это даёт возможность «карта удалена, но seed уцелел → пересобрать ту же карту» (edge case AC1/EC1).
   - API: `static func loadSeed() -> Int64?`, `static func saveSeed(_ seed: Int64)`.

5. `World/WorldMapProvider.swift` — фасад/координатор бутстрапа:
   - `final class WorldMapProvider { let map: NoiseMap; let seed: Int64; init(...) }` — формируется в `AppDelegate.applicationDidFinishLaunching` до создания `GameScene`.
   - Логика инициализации (порядок строгий):
     1. Прочитать `WorldSeedStore.loadSeed()`. Если `nil` → сгенерировать новый `Int64.random(in: .min ... .max)` и сохранить.
     2. Прочитать `WorldMapStore.load()`. Если `nil` ИЛИ `loaded.seed != currentSeed` ИЛИ `loaded.version != currentVersion` ИЛИ `loaded.size != 256` → перегенерировать через `NoiseFieldGenerator.generate(seed:size:)` и `store.save(_:)`. В любом случае несоответствия (формат/seed) — `ErrorsLog.write(...)`.
     3. Готовая `NoiseMap` оседает в `provider.map` и передаётся в `GameScene` (через слабую ссылку `scene.worldMap = provider.map`, добавим на сцене опциональное поле — рендера ещё нет, поле просто хранится для TASK-028).
   - Метод `regenerate(newSeed: Int64? = nil)` — для TASK-030 (НЕ вызываем сейчас, но API готовим): обновляет seed, перегенерирует карту, сохраняет, возвращает новый `NoiseMap`. UI «Сбросить карту» — НЕ делаем (TASK-030).

6. `Data/AppPaths.swift` — добавить:
   - `static var worldmapJson: URL { appSupport.appendingPathComponent("worldmap.json") }`.

**Куда подключаем:**
- `App/AppDelegate.swift:25-31` — после `appSettings = AppSettings.load()`, до `engine = CityEngine(...)`, добавить:
  ```
  let worldMapProvider = WorldMapProvider(
      seedStore: WorldSeedStore.self,
      mapStore: WorldMapStore(url: appSettings.dataDirectory.appendingPathComponent("worldmap.json"))
  )
  ```
  и сохранить как `private var worldMapProvider: WorldMapProvider!`.
- `Game/GameScene.swift` — добавить `var worldMap: NoiseMap?` (опциональное поле; сценарий рендера приедет в TASK-028, сейчас лишь хранится). Установка: в `AppDelegate` после `scene = GameScene()` написать `scene.worldMap = worldMapProvider.map`.

**Размер по умолчанию:** `NoiseMap.defaultSize = 256` (константа). 256×256 покрывает спиральный диапазон `DistrictPlanner` (см. оценку выше). Структура `[Float]` row-major: 3 поля × 65536 × 4 байта ≈ 786 КБ в памяти; JSON-сериализация — около 6–8 МБ (массивы Float как числа). Это приемлемо для sidecar-файла; в будущем (вне этой задачи) можно перевести на бинарный формат — фиксируется в backlog как идея.

**Детерминизм:** GameplayKit `GKPerlinNoiseSource(seed: Int32)` — детерминирован при одном и том же seed на одной и той же версии iOS/macOS SDK. Для AC3 этого достаточно. Версионируем формат через `NoiseMap.currentVersion`; если в будущем поменяется алгоритм — bump версии, и existing файлы будут регенерированы (это и есть EC2 поведение).

### Пошаговая декомпозиция

1. **[AC: 1, 2]** Создать каталог `Sources/CityDeveloper/World/` и файл `World/NoiseMap.swift` со структурой `NoiseMap: Codable` (поля `version`, `seed`, `size`, `height`, `temperature`, `humidity`), константой `currentVersion = 1`, accessors `height(at:x:y:)`, `temperature(at:)`, `humidity(at:)` с clamp граничных координат.
2. **[AC: 2, 3, 4, 5]** Создать `World/NoiseFieldGenerator.swift` с `static func generate(seed:size:) -> NoiseMap`, использующим GameplayKit (`GKPerlinNoiseSource` → `GKNoise` → `GKNoiseMap`), три разных производных seed для трёх полей, нормализацией `[-1,1] → [0,1]`, и параметрами шума (`frequency=1.0, octaveCount=4, persistence=0.5, lacunarity=2.0`).
3. **[AC: 1]** Создать `World/WorldMapStore.swift` (load/save с атомарной записью, диагностикой через `ErrorsLog`, проверкой `version == currentVersion`).
4. **[AC: 1, 3]** Создать `World/WorldSeedStore.swift` (статические `loadSeed/saveSeed` через `UserDefaults` под ключом `com.outbyte.citydeveloper.worldSeed`).
5. **[AC: 1, 3, 5]** Создать `World/WorldMapProvider.swift` с инициализацией (load seed → если нет, генерим и сохраняем; load map → если нет/несовпадение → регенерим и сохраняем), методом `regenerate(newSeed:)` для будущего, и логированием несоответствий формата в `ErrorsLog`.
6. **[AC: 1]** Добавить в `Data/AppPaths.swift` строку `static var worldmapJson: URL { appSupport.appendingPathComponent("worldmap.json") }`.
7. **[AC: 1]** Подключить в `App/AppDelegate.swift:applicationDidFinishLaunching` — между `appSettings = ...` и `engine = CityEngine(...)` создать `worldMapProvider` (с `WorldMapStore` на `appSettings.dataDirectory`), сохранить как поле класса; после `scene = GameScene()` написать `scene.worldMap = worldMapProvider.map`.
8. **[AC: 1, инфраструктура]** Добавить в `Game/GameScene.swift` поле `var worldMap: NoiseMap?` (опциональное, ничего не рисуется — потребитель TASK-028).
9. **[AC: 3, 4, EC]** Создать тестовый файл `Tests/CityDeveloperTests/NoiseFieldGeneratorTests.swift` с проверками:
   - `generate(seed: 42)` дважды даёт идентичные массивы (детерминизм).
   - `generate(seed: 42)` и `generate(seed: 43)` дают РАЗНЫЕ массивы (разный seed → разный мир).
   - Все значения в `[0, 1]` (нормализация).
   - Соседние клетки отличаются типично менее чем на 0.15 (плавность; усреднённое по 1000 случайных позиций).
   - Граничный clamp: `map.height(at: -10, y: 500)` не падает, возвращает крайнее граничное значение.
   - Граничные seed: `seed = 0`, `seed = Int64.min`, `seed = Int64.max` — генерация проходит, длина массивов корректна.
10. **[AC: 5, дев-проверка]** Запустить `swift build` + `swift test` локально; вручную: удалить `~/Library/Application Support/CityDeveloper/worldmap.json`, запустить приложение, убедиться по `ls -la` что файл создан; перезапустить — убедиться что seed и значения те же (диагностика через временный print или через ассерт в тестах; print-ы убрать перед коммитом).

### Edge cases (с привязкой к коду)

- **Карта отсутствует или повреждена** → `WorldMapStore.load()` возвращает `nil` после `try? JSONDecoder().decode(...)` (по шаблону `Data/SnapshotStore.swift:9-18`). `WorldMapProvider` идёт в ветку «генерим из сохранённого seed». Если seed тоже отсутствует — `WorldSeedStore.loadSeed()` возвращает `nil` → генерим новый и сохраняем (см. шаг 5).
- **Версия генератора изменилась** → `WorldMapStore.load()` дополнительно сверяет `loaded.version == NoiseMap.currentVersion` (по шаблону `SnapshotStore.swift:12-14`). При несовпадении → `ErrorsLog.write("Worldmap version mismatch, regenerating")` и возврат `nil`, после чего провайдер пересобирает с тем же seed (он живёт в UserDefaults, не в файле карты).
- **Запрос значений вне карты** → `NoiseMap.index(x, y)` сначала делает `let cx = max(0, min(size-1, x))`, аналогично для `y`. Возвращает значение ближайшей граничной клетки — никаких force-unwrap, никаких выходов за `[Float]`.
- **`seed = 0` / отрицательный / `Int64.min` / `Int64.max`** → `Int32(truncatingIfNeeded: seed)` обрабатывает любое значение Int64 без переполнения; `GKPerlinNoiseSource(seed: Int32)` принимает любой Int32 включая `.min` (документация GameplayKit явно это разрешает). Тест с этими граничными значениями — в `NoiseFieldGeneratorTests`.
- **Параллельный запуск двух копий приложения** → не рассматриваем (вне скоупа; приложение single-instance де-факто, нет конфликта блокировок в `SnapshotStore`/`EventLog`).
- **Гонка между записью карты и регенерацией** → `WorldMapProvider` синхронен в `init`, выполняется на main-queue в `applicationDidFinishLaunching` до создания сцены и watchers. Гонок не существует на этом этапе.
- **Размер файла worldmap.json** → ~6–8 МБ JSON. Это явно больше остальных sidecar'ов, но всё ещё атомарная запись `Data.write(.atomic)` (один временный файл, rename). На M-серии — миллисекунды. Если в будущем размер вырастет — переход на бинарный формат в backlog (вне скоупа задачи).

### Файлы для изменения

- **NEW:** `Sources/CityDeveloper/World/NoiseMap.swift`
- **NEW:** `Sources/CityDeveloper/World/NoiseFieldGenerator.swift`
- **NEW:** `Sources/CityDeveloper/World/WorldMapStore.swift`
- **NEW:** `Sources/CityDeveloper/World/WorldSeedStore.swift`
- **NEW:** `Sources/CityDeveloper/World/WorldMapProvider.swift`
- **NEW:** `Tests/CityDeveloperTests/NoiseFieldGeneratorTests.swift`
- **EDIT:** `Sources/CityDeveloper/Data/AppPaths.swift` — добавить одно поле `worldmapJson`.
- **EDIT:** `Sources/CityDeveloper/App/AppDelegate.swift` — два места: добавить поле класса `worldMapProvider`; инициализация между `appSettings` и `engine`; передача `scene.worldMap = worldMapProvider.map` после создания сцены.
- **EDIT:** `Sources/CityDeveloper/Game/GameScene.swift` — добавить `var worldMap: NoiseMap?` (одно опциональное поле, без логики).

### НЕ трогать

- `Sources/CityDeveloper/Game/CityEngine.swift` — карта мира НЕ часть event-sourced state, не должна попадать ни в `CityState`, ни в `StateSnapshot`, ни в `events.jsonl`.
- `Sources/CityDeveloper/Data/CityState.swift`, `Data/StateSnapshot.swift`, `Data/SnapshotStore.swift` — без изменений (карта живёт в отдельном sidecar).
- `Sources/CityDeveloper/Game/DistrictPlanner.swift` — биом-аффинитет размещения это TASK-030, не сейчас. Спираль остаётся как есть.
- `Sources/CityDeveloper/Game/UnitPlanner.swift` — terrain-веса это TASK-033 и далее.
- `Sources/CityDeveloper/UI/*` — UI «новая карта / новый seed» это TASK-030. В этой задаче никакого UI вообще.
- `Sources/CityDeveloper/Game/IsoBuilder.swift`, `Game/UnitSprites.swift`, `Game/CitizenSprites.swift` — никакого визуала; задача чисто про данные.
- Любые файлы под `concept/` и `Tasks/` (кроме раздела «🛠 Технический разбор» текущего файла).

### Команды проверки

```sh
# Сборка пакета (должен пройти без новых ошибок/варнингов).
cd <repo-root> && swift build

# Юнит-тесты целиком (детерминизм, нормализация, плавность, граничные значения).
cd <repo-root> && swift test

# Только новые тесты (быстрее в TDD-цикле).
cd <repo-root> && swift test --filter NoiseFieldGeneratorTests

# Ручной smoke-тест детерминизма (после первой сборки):
# 1. Удалить артефакты: предыдущий мир, но сохранить seed в UserDefaults.
rm -f ~/Library/Application\ Support/CityDeveloper/worldmap.json
# 2. Запустить — должна появиться worldmap.json (≈ 6–8 МБ).
swift run CityDeveloper
# 3. Проверить файл.
ls -la ~/Library/Application\ Support/CityDeveloper/worldmap.json
# 4. Удалить только карту (не seed), запустить снова — карта пересоздаётся с тем же seed.
#    (Для побайтовой проверки идентичности можно временно вынести dump.)

# Чистый старт (нет ни seed, ни карты) — должен сгенерировать обе сущности:
defaults delete com.outbyte.citydeveloper.settings 2>/dev/null
defaults delete com.outbyte.citydeveloper "com.outbyte.citydeveloper.worldSeed" 2>/dev/null
rm -f ~/Library/Application\ Support/CityDeveloper/worldmap.json
swift run CityDeveloper
```

### Сложность

**middle** — задача требует знания GameplayKit Noise API (узкое место для junior'а), аккуратной работы с persistence и edge cases (версионирование формата, отсутствующие файлы, граничные значения seed), и понимания event-sourcing границы (что НЕ должно попасть в `CityState`). Алгоритмически это не senior-уровень (нет сложных решений по архитектуре, нет конкурентности, нет производительности на пределе), но дизайн API «провайдера + двух хранилищ» и тест-стратегия требуют опыта. Middle-разработчик закроет за день уверенно.

### Объём

**M** — 5 новых небольших файлов в `World/`, 1 файл тестов, 3 точечные правки (одна строка в `AppPaths`, ~5–7 строк в `AppDelegate`, 1 строка в `GameScene`). Чистого кода: ~300–400 строк (без тестов) + ~120 строк тестов. Никаких миграций, никаких сложных интеграций. Однодневная задача.

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_ (определит лид)
_Объём: M_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Done-критерий проверен в реальном использовании (в части, относящейся к этой подзадаче — наличие воспроизводимых полей карты)

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Тесты не сломаны
- [ ] Нет хардкод-строк (i18n/env где требует проект)

#### Обновление документации
- [ ] `current.md`: F-15 → ⚠️ (часть фундамента)
- [ ] `diff.md`: D-15 не закрывать — закрывается только после TASK-030
- [ ] Новые идеи → `backlog.md`, новые баги → `bugs.md`

---

## Статус

`[x] waiting-for-lead` / `[ ] ready` / `[x] in-progress` / `[ ] review` / `[x] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-23
- Spec-review: approved
- Blocked-by: —
- Готова к работе: 2026-05-22
- Завершена: 2026-05-22
- Коммит: 07bcd5c
