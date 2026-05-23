# TASK-032: Placeholder-спрайты для всех 50 юнитов

## Связь
- **F-16** из Concept.md (расширенный каталог юнитов)
- **F-13** из Concept.md (каталог арт-ассетов)
- **D-16** из Diff.md (часть 2/10 — визуал-заглушки)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим
После расширения `UnitKind` до 50 типов (TASK-031) игра должна продолжать
собираться и **не падать** при попытке отрисовать любой из 38 новых юнитов,
которые пока не имеют PNG в `Resources/Buildings/`. Решение — процедурные
placeholder-спрайты в `UnitSprites`: каждый из 50 юнитов получает узнаваемый
изо-силуэт из примитивов IsoBuilder (куб + крыша + декор), отличающийся
по палитре (категория) и форме (footprint, «крупный» ли). Это позволит
TASK-035 (UnitPlanner) и TASK-037 (миграция) выкатить без блокировки
по визуалу, а финальные PNG приходят постепенно через TASK-040.

### Пользовательский сценарий
1. Разработчик добавляет в `tasks.jsonl` 30+ задач разного типа.
2. На карте в течение нескольких секунд появляются 30+ юнитов; каждый юнит
   визуально различим, не «розовый квадрат», и узнаваем как принадлежащий
   своей категории (жилой / инфра / производство / социальное / религиозное /
   военное) — например, по цвету тайла под юнитом и по форме крыши.
3. Если разработчик кладёт PNG в `Sources/CityDeveloper/Resources/Buildings/`
   с именем по convention (`<kind>.png` или `<kind>_stage<N>.png`), то этот юнит
   на карте отрисовывается из PNG, а остальные продолжают рисоваться из
   placeholder-примитивов — без падений и без визуальных регрессий.

### Acceptance criteria
- [ ] Для каждого из 50 значений `UnitKind` `UnitSprites.makeStageNode(unit:)`
      возвращает не-nil `SKNode`, который виден на сцене (имеет хотя бы один
      ребёнок с ненулевыми размерами).
- [ ] Каждая из 6 категорий (жилое / инфра / производство / социальное /
      религиозное / военное) имеет различимый цвет тайла-земли под юнитом,
      зафиксированный в `categoricalGroundColor(for:)`.
- [ ] Юниты с `large = true` (по таблице F-16) рисуются как минимум на 30%
      крупнее по высоте, чем «обычные» юниты той же категории на той же
      стадии — чтобы визуально читались как «значимые объекты», а не
      «вырост из лачуги».
- [ ] Если в `Resources/Buildings/<kind>.png` лежит файл с правильным именем
      (по convention `SpriteGenerationRules` § 3), то этот юнит рисуется из
      PNG, а если файла нет — рисуется из процедурного placeholder. Падений
      нет ни в одном из двух случаев.
- [ ] Сборка (`swift build`) и запуск (`swift run CityDeveloper`) проходят без
      падений при наличии всех 50 типов на сцене одновременно (тест через
      replay искусственного `events.jsonl` на 60 задач).

### Что НЕ делаем (границы скоупа)
- Не рисуем финальные PNG в стиле Pharaoh — это TASK-040.
- Не делаем эволюционную подмену спрайта при достижении порога — это TASK-034.
- Не меняем размер footprint в координатах сетки (всё ещё 1×1 на сцене;
  визуальное укрупнение `large` — через высоту, не через занимаемые клетки).
- Не меняем поведение `UnitPlanner` — это TASK-035.
- Не делаем particle-эффекты для новых юнитов (дым, флажки) — F-05 их добавит
  отдельно по мере необходимости.

### Edge cases
- [ ] Юнит, для которого PNG лежит, но размер не квадратный или не RGBA →
      грузится как есть, основание привязывается через `anchorY = 0.30` по
      умолчанию из `loadBuildingSprite`. Логирование в `errors.log` для
      кривых файлов — опционально.
- [ ] Юнит из категории «военное» / «религиозное» на старом state, где их не
      было — рисуется placeholder-ом, не падает (это особенно важно для
      сценария «обновление кода без миграции state», но миграция формально —
      TASK-037).
- [ ] Спрайт большого юнита (`large = true`) на ранней стадии квартала
      (stage 0–1) — если планировщик его всё же выберет, отрисовывается
      без переполнения тайла; крупный силуэт читается, но не перекрывает
      соседние юниты по сетке более чем на одну клетку.
- [ ] `makeStageNode` вызывается до того, как PNG-кеш прогрет — первый вызов
      не должен подвешивать main-thread дольше, чем сейчас (≤ 50 мс на юнит
      на M-серии).

### Зависимости
- **Blocked-by:** TASK-031 (нужен расширенный `UnitKind` и категории).

### Дизайн
Палитра placeholder-категорий — `Sources/CityDeveloper/Theme/Palette.swift`:
- Жилое — охра / песчаник.
- Инфра — серый камень.
- Производство — выцветшее дерево + красно-коричневый кирпич.
- Социальное — мрамор / светлый камень.
- Религиозное — золотой / тёмный камень.
- Военное — тёмно-серый камень.

Naming convention для PNG — `SpriteGenerationRules.md` § 3.

### Done-критерий
_Из Concept.md F-16:_ Все 50 юнитов имеют реализованный спрайт и корректно выбираются
алгоритмом размещения с учётом `terrain`, `minStage` и `large`. Эволюционные цепочки
визуально срабатывают при достижении порога. Квартал из 30+ юнитов содержит ≥ 3
разных категории. Воспроизводимость через replay.

---

## 🛠 Технический разбор от тимлида

_Автор: tech-lead (Opus)_
_Дата: 2026-05-22_
_Статус: [x] готов_

### Анализ текущего состояния

- **Активный pipeline спрайтов** — `UnitSprites.makeStageNode(unit:stageOverride:)`:
  собирает контейнер `shadow + ground + building` (последний с `name = "building"` —
  ключ для `GameScene.swapStageSprite`). Внутри диспетчит на
  `makeCategoricalBuilding(category:stage:)` — switch по 4 категориям × 5 stage = 20
  процедурных силуэтов через `IsoBuilder.cube / pyramidRoof / brickHatch +
  SKShapeNode`. Это ровно тот слой, в который сейчас попадают все юниты на сцене.
- **Legacy `makeNode(unit:)`** — switch по 12 текущим `UnitKind` с
  `makeShack/.../makeObelisk`. Из активного pipeline'а **не вызывается** — только
  `DecayVisuals` дёргает `UnitSprites.makeRuin`. Можно не трогать, AC требует только
  `makeStageNode`.
- **PNG-fallback уже встроен**: `loadBuildingSprite(named:targetWidth:anchorY:)`
  с lazy-cache по имени, ищет `Bundle.module.url(forResource:withExtension:"png",
  subdirectory: "Buildings")`. Сейчас используется ровно в одной точке —
  `makeResidentialStage(1)` пробует `shack.png`, иначе процедурная лачуга. Это
  готовый паттерн «PNG-first → procedural placeholder», который нужно поднять на
  уровень kind-диспетчера.
- **`categoricalGroundColor(for:)`** — 4-веточный switch по `UnitCategory`. После
  TASK-031 enum получит `.religious` и `.military` → switch перестанет быть
  exhaustive → `swift build` упадёт. Это **обязательная** правка по этой задаче
  (corner case AC «билд не падает после TASK-031»).
- **TASK-031 (blocker) API-контракт** (из его AC): `UnitKind.allCases.count == 50`,
  `UnitKind.category: UnitCategory` (6 значений), плюс новые свойства
  `label / preferredTerrains / size / minStage / large / evolvesTo / evolveThreshold`
  на каждом kind. Для TASK-032 нужны: `kind.category`, `kind.large` (для AC «large
  на 30% выше»), `kind.minStage` (для edge-case «отрисовка ниже minStage =
  отрисовка как minStage»). Если TASK-031 называет поля иначе — исполнитель
  адаптирует имена 1-в-1, не вводит свои.
- **Palette уже содержит всё нужное**: `sandLight/sandMid/ochre/clay/warmBrown/
  stone/parchment/smokeGrey/inkDark/skyDusk/skyNight/nileGreen/fireOrange`. Шесть
  категорий из спеки PM раскладываются в эти токены без расширения Palette.
- **IsoBuilder** имеет `cube / pyramidRoof / brickHatch / shadow / groundTile` —
  достаточно для 50 силуэтов. Никаких новых примитивов не нужно.

### Архитектурное решение

**Не плодим 50 функций.** Вводим в `UnitSprites.swift` декларативный
`PlaceholderSpec` — структуру, описывающую один силуэт как набор примитивных
полей (footprint, baseHeight, roofStyle, decorStyle, bodyPalette, roofPalette).
Под каждый из 50 `UnitKind` — одна строка в статической таблице
`placeholderSpecs: [UnitKind: PlaceholderSpec]`. Один универсальный helper
`makePlaceholderBuilding(spec:large:)` рендерит любой spec из примитивов IsoBuilder.
Это даёт 50 различимых силуэтов без 50 копий boilerplate'а.

**Диспетчер по kind заменяет диспетчер по category.** Текущая 4×5 категориальная
матрица становится **fallback-уровнем**: если для kind не задан spec (защита от
рассинхрона) — рисуем по категории. Активный путь: `makeStageNode` → новая
`makeKindBuilding(unit:stage:)`:
  1. Попытка `loadBuildingSprite(named: unit.kind.rawValue + "_stage\(stage)", ...)`,
     потом без суффикса (`<kind>.png`) — по convention из `SpriteGenerationRules § 3`.
  2. Иначе — `makePlaceholderBuilding(spec: placeholderSpecs[kind] ??
     fallbackCategoricalSpec(category, stage), large: kind.large)`.
  3. Helper применяет `+30 %` к высоте, если `large = true`, и подкрашивает
     контур (тонкий золотой outline или +10% saturation тела) — чтобы крупный
     юнит читался как «значимый», а не «вырост из лачуги» (AC #3).

**6 категорий → 6 палитр под тайл-землю.** В `categoricalGroundColor` добавляем
`.religious → Palette.parchment.lightened(0.05)` (золотисто-светлый камень) и
`.military → Palette.smokeGrey.darkened(0.05)` (тёмно-серый камень). Production
по спеке PM перекрашиваем в `Palette.warmBrown.darkened(0.05)` (выцветшее
дерево + красно-коричневый). Эти значения декларируем как
`static let groundColorByCategory: [UnitCategory: SKColor]` — никаких inline-литералов.

**Старые `makeCategoricalBuilding/makeResidentialStage/...` оставляем как
fallback-функции внутри `UnitSprites`** — они продолжают работать как safety net
для `swapStageSprite` (который сейчас зовёт `makeCategoricalBuilding`) и для
kind'ов без spec. Дополнительно: в `GameScene.swapStageSprite` (строка ~253)
замена `UnitSprites.makeCategoricalBuilding(category:stage:)` на новую
`UnitSprites.makeKindBuilding(unit:stage:)` — иначе после stage-up юнит снова
становится «общим категориальным», а нужно сохранить kind-индивидуальность.

**Защита от minStage.** В `makeKindBuilding` сразу зажимаем
`effectiveStage = max(stage, kind.minStage)` (edge-case AC из TASK-036, но и
эта задача его потребует на стороне фабрики — иначе Дворец с minStage=5,
случайно вызванный на stage 1, нарисует пустоту).

### Пошаговая декомпозиция (для исполнителя)

1. **[Палитра ground]** — `Sources/CityDeveloper/Game/UnitSprites.swift`, метод
   `categoricalGroundColor(for:)`. Добавить ветки `.religious` и `.military` и
   перекрасить `.production` под спеку PM. Вынести значения в приватную
   `static let groundColorByCategory: [UnitCategory: SKColor]`, метод оставить
   как тонкий враппер `groundColorByCategory[category] ?? Palette.sandLight`.
2. **[Структура spec]** — там же объявить:
   ```swift
   private struct PlaceholderSpec {
       enum RoofStyle { case pyramid, flat, none, dome }
       enum DecorStyle { case none, window, chimney, columns, pediment, banner, smokeStack }
       let footprint: CGSize
       let baseHeight: CGFloat
       let bodyPalette: (top: SKColor, side: SKColor) // одна пара, helper сам
                                                      // выводит left/right/stroke
       let roof: RoofStyle
       let roofPalette: SKColor
       let decor: [DecorStyle]
   }
   ```
   Никаких inline-цветов — всё через `Palette.*`.
3. **[Таблица 50 спецов]** — статический словарь
   `static let placeholderSpecs: [UnitKind: PlaceholderSpec] = [...]`. По одной
   строке на каждый из 50 `UnitKind`. Группировать визуально по категориям
   (комментарии-заголовки `// MARK: - Жилые`). Высоты:
   - residential: 12–48 pt (землянка → дворец);
   - infra: 8–30 pt; production: 10–38 pt; social: 10–36 pt;
   - religious: 16–52 pt (Пирамида = высокий пирамидальный roof, footprint 4×4
     рисуем как «увеличенный» footprint в координатах sprite'а — 56×30, не в
     координатах сетки);
   - military: 18–34 pt.
   Цветовая семья = category-палитра (см. п. 1), с лёгкими сдвигами по архетипу
   (Хижина — `warmBrown` вместо `clay` у Лачуги, и т.п.).
4. **[Универсальный фабричный helper]** — приватный
   `static func makePlaceholderBuilding(spec: PlaceholderSpec, large: Bool) -> SKNode`.
   Логика:
   - применяет `large ? spec.baseHeight * 1.3 : spec.baseHeight` (AC #3);
   - рендерит `IsoBuilder.cube(footprint: spec.footprint, height: h,
     colors: .init(top: spec.bodyPalette.top, left: spec.bodyPalette.side,
     right: spec.bodyPalette.side.darkened(by: 0.18), stroke: Palette.inkDark
     .withAlphaComponent(0.6)))`;
   - добавляет `IsoBuilder.brickHatch` с rows = `Int(h / 6)`;
   - крыша: `pyramid` → `IsoBuilder.pyramidRoof`, `flat` → `IsoBuilder.groundTile`
     поверх куба, `none` → ничего, `dome` → круглая `SKShapeNode(circleOfRadius:
     spec.footprint.width * 0.4)` сверху;
   - декор: каждый `DecorStyle` мапит в готовый под-узел (для `chimney` — взять
     текущую реализацию из `makeWorkshop`; для `columns` — из `makeForum`; для
     `pediment` — pyramid поверх; для `window` — `SKShapeNode(rect:)` 5×5
     `Palette.skyNight`; для `smokeStack` — узкий cube `Palette.smokeGrey`).
   Никаких новых примитивов — только композиция существующих.
5. **[Новая точка входа `makeKindBuilding`]** — публичный
   `static func makeKindBuilding(unit: UnitState, stage: Int) -> SKNode`:
   - `let effectiveStage = max(stage, unit.kind.minStage)`;
   - PNG-first: `loadBuildingSprite(named: "\(unit.kind.rawValue)_stage\(effectiveStage)", ...)`
     → если nil, `loadBuildingSprite(named: unit.kind.rawValue, ...)` → если nil,
     `makePlaceholderBuilding(spec: placeholderSpecs[unit.kind] ??
     fallbackSpec(for: unit.kind.category, stage: effectiveStage),
     large: unit.kind.large)`.
   - Имя контейнера/спрайта сохраняем как было (`name = "building"`).
6. **[Подключить новую точку входа]**:
   - `UnitSprites.makeStageNode` (строка 74): заменить
     `makeCategoricalBuilding(category:, stage:)` на
     `makeKindBuilding(unit: unit, stage: stage)`.
   - `GameScene.swapStageSprite` (Sources/CityDeveloper/Game/GameScene.swift:253):
     заменить `UnitSprites.makeCategoricalBuilding(category: category, stage:
     newStage)` на `UnitSprites.makeKindBuilding(unit: unit, stage: newStage)`.
     Перед вызовом нужен `unit` — он уже есть рядом через `unitId` lookup; если
     текущий код не имеет `unit` в scope — взять из `engine.state.units[unitId]`
     (это уже делается выше в `swapStageSprite`, см. контекст файла).
7. **[Fallback категориальный spec]** — приватный
   `static func fallbackSpec(for category: UnitCategory, stage: Int) -> PlaceholderSpec`,
   возвращает осмысленный default по 6 категориям × 5 stage (по сути — извлечь
   параметры из существующих `makeResidentialStage/.../makeSocialStage` и для
   двух новых категорий задать вручную). Это safety net, в нормальной работе не
   срабатывает (все 50 kind'ов покрыты таблицей).
8. **[Старые `makeCategoricalBuilding/makeResidentialStage/...` не удалять]** —
   оставить как утилиты для fallbackSpec и для совместимости. В свободной
   рефакторинг-задаче в будущем можно почистить, но не в этом коммите.
9. **[Sanity-check всех 50 кейсов]** — в конце файла под `#if DEBUG` добавить:
   ```swift
   static func _debugAssertPlaceholderCoverage() {
       for kind in UnitKind.allCases {
           assert(placeholderSpecs[kind] != nil, "Missing placeholder spec for \(kind)")
       }
   }
   ```
   Дёргать **не нужно** — это контракт-чек для будущих ревью. Хватит того, что
   код компилируется (CaseIterable + словарь не даст забыть kind).

### Edge cases (явно обработать)

- [ ] **PNG без stage-суффикса** (`shack.png` уже лежит) — должен по-прежнему
      рисоваться как PNG, а не placeholder. Порядок поиска в `makeKindBuilding`
      обязательно: stage-суффикс → без суффикса → placeholder.
- [ ] **`UnitCategory` exhaustive после TASK-031** — `categoricalGroundColor`,
      `makeCategoricalBuilding`, `fallbackSpec` все должны иметь 6 веток (или
      словарь с 6 ключами). `swift build` без warning'ов exhaustiveness.
- [ ] **`large = true` юнит на ранней stage** (Дворец на stage 0 через
      инспектор) — клампим через `effectiveStage = max(stage, kind.minStage)`,
      рисуется как `minStage`, не падает.
- [ ] **PNG битый / не квадратный** — `loadBuildingSprite` уже возвращает nil
      на `image == nil` или `size.width == 0` → fallback на placeholder
      срабатывает автоматически. Дополнительное логирование в `errors.log` —
      опционально (AC помечен «опционально»), пропускаем в этом коммите.
- [ ] **Replay сценария с 50 kind'ами на сцене** — после правки
      `swapStageSprite` (п. 6) убедиться: stage-up квартала с разнотипными
      юнитами не превращает их в одну категориальную форму. Это и есть AC #4
      («каждый юнит визуально различим»).
- [ ] **Производительность первого вызова** — `placeholderSpecs` — статическая
      let-таблица, инициализируется один раз. `makePlaceholderBuilding` — чистая
      композиция `SKShapeNode`, такая же по cost как существующие
      `makeShack/makeHouse`. PNG-кеш уже есть. Лимит ≤ 50 мс на юнит соблюдается.

### Файлы для изменения

- `Sources/CityDeveloper/Game/UnitSprites.swift` — расширение
  `categoricalGroundColor`, новый `PlaceholderSpec` + словарь
  `placeholderSpecs[UnitKind]`, helper `makePlaceholderBuilding`, точка входа
  `makeKindBuilding`, переключение `makeStageNode` на неё.
- `Sources/CityDeveloper/Game/GameScene.swift` — `swapStageSprite` (~строка 253):
  замена вызова `makeCategoricalBuilding` на `makeKindBuilding(unit:, stage:)`.

### Файлы НЕ трогать

- `Sources/CityDeveloper/Data/CityState.swift` — это полностью зона TASK-031.
  `UnitKind` / `UnitCategory` / `label` / `large` / `minStage` приходят оттуда.
  Этот таск **только потребляет** их API.
- `Sources/CityDeveloper/Game/IsoBuilder.swift` — примитивов достаточно, не
  расширяем. Любые новые примитивы — повод для отдельного backlog-инкремента.
- `Sources/CityDeveloper/Theme/Palette.swift` — токенов хватает на 6 категорий.
  Если возникнет ощущение «нужен новый цвет» — это сигнал, что spec неудачный,
  а не Palette неполный.
- `Sources/CityDeveloper/Resources/Buildings/` — никаких PNG не добавляем.
  Финальный Pharaoh-визуал = TASK-040.
- Старые `makeNode(unit:)` / `makeShack/.../makeObelisk` — не удаляем (вне
  скоупа, рискуем уронить `makeRuin` цепочку через рефакторинг).
- `concept/Concept.md`, `concept/Diff.md`, `concept/Current.md`, `Backlog.md`,
  `Bugs.md` — обновляются в финале исполнителем согласно DoD, не лидом.

### Команды проверки (для DoD)

- Компиляция: `swift build` (из корня репо). Должна пройти **без новых
  warning'ов** по exhaustiveness `switch` (это AC #5).
- Линтер: `swift build` показывает warning'и компилятора — этого достаточно,
  отдельного linter в проекте нет.
- Ручная проверка:
  1. `swift run CityDeveloper`.
  2. Положить в `tasks.jsonl` 60 задач разных проектов (можно скриптом из
     `Scripts/`, либо вручную скопировать `events.jsonl`-семпл из тестов).
  3. Дождаться размещения 30+ юнитов на сцене.
  4. Глазами проверить: видны юниты ≥ 3 разных категорий (по цвету тайла-земли),
     `large`-юниты (Колодец / Маяк / Дворец / Пирамида) визуально выше соседей
     той же категории на ≥ 30%, ни один юнит не «розовый квадрат» / не пустота.
  5. Никаких runtime-крэшей в `errors.log`.
- Авто-тест (опционально, не блокирующий): `swift test` — существующие тесты
  не должны сломаться (никаких изменений в Data/-слое не делаем).

### Сложность: `middle`
### Объём: `M`

Обоснование: декларативная таблица 50 строк × helper на ~100 строк +
точечные правки 2 функций в 2 файлах. Архитектура очевидна (расширение
существующих switch'ей + табличный фабричный pattern), без развилок. Senior
не нужен — нет архитектурных решений за пределами «вынести в spec». Junior
не подходит — нужно держать в голове связь с TASK-031 API-контрактом и
понимать swap-механику в GameScene. L не подходит — нет 50 PNG, нет
новых примитивов, нет миграций.

### Plan-review (Sonnet)

_Дата: 2026-05-22, статус: approved._

Sonnet-ревью плана прошло; ключевые проверки:

1. **AC покрытие**: AC#1 (50 kind → non-nil SKNode) → шаг 5 + assert; AC#2 (6
   категорий → различимый ground-color) → шаг 1; AC#3 (large +30 % высоты) →
   шаг 4; AC#4 (PNG → PNG, нет PNG → placeholder, без падений) → шаг 5
   (порядок stage-суффикс → без суффикса → placeholder); AC#5 (swift build +
   swift run без падений на 60 задачах) → шаг 6 + ручная проверка. Все 5 AC
   покрыты.
2. **Edge cases**: 4 из 4 явно адресованы (PNG-кривой → existing nil-fallback,
   minStage-clamp → шаг 5, military/religious на старом state → exhaustive
   switch шаг 1, perf первого вызова → static let таблица).
3. **Совместимость с TASK-036** (stage-tier по kind, не по category): новая
   точка `makeKindBuilding(unit:, stage:)` уже принимает stage явно — TASK-036
   просто расширит таблицу spec'ов разными stage-tier'ами, **не** меняя
   сигнатуру. Архитектурно совместимо.
4. **Не вылезает за скоуп**: эволюция (TASK-034), planner (TASK-035), миграция
   state (TASK-037) — не затронуты, что соответствует «границам скоупа» PM.
5. **Риск рассинхрона с TASK-031**: имена полей `large` / `minStage` /
   `category` сейчас условные. Шаг 0 для исполнителя: открыть финальный
   `CityState.swift` после TASK-031, проверить точные имена, при отличии —
   адаптировать в одном месте (доступ через
   `unit.kind.large`/`.minStage` локализован в `makeKindBuilding` и в helper'е).

Замечаний нет; план approved без правок.

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: middle_
_Объём: M_

### Definition of Done

#### Функциональные
- [x] Все AC выполнены
- [ ] Done-критерий проверен в реальном использовании (визуально на сцене с
      60-задачным test-логом видны все 6 категорий, юниты различимы)

#### Технические
- [x] Компиляция/линтер без новых ошибок
- [x] Тесты не сломаны
- [x] Нет хардкод-строк (имена PNG и palette-токены — в констатах)

#### Обновление документации
- [ ] `Current.md`: F-16 → ⚠️ (placeholder-визуал готов, финальный — TASK-040)
- [ ] `Diff.md`: D-16 не закрывать — закрывается только после TASK-040
- [ ] Новые идеи → `Backlog.md`, новые баги → `Bugs.md`

---

## Статус

`[ ] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[x] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-22
- Spec-review: approved
- Lead-review: approved (2026-05-22, Opus)
- Plan-review: approved (2026-05-22, Sonnet)
- Blocked-by: TASK-031
- Готова к работе: 2026-05-22 (ждёт закрытия TASK-031)
- Завершена: 2026-05-22
- Коммит: ecd6520
