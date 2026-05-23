# TASK-031: Расширение каталога UnitKind до 50 типов

## Связь
- **F-16** из Concept.md (расширенный каталог юнитов)
- **D-16** из Diff.md (часть 1/10 — данные)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим
Сейчас в игре всего 12 юнитов (`shack`, `house`, `villa`, `well`, `road`,
`warehouse`, `workshop`, `raw`, `market`, `forum`, `temple`, `obelisk`). По
концепту F-16 их должно быть **50** — Землянка, Хижина, Дворец, Пирамида,
Лесопилка, Шахта, Маяк, Театр, Сторожевая башня и т.д. Эта задача — фундамент
для всех остальных подзадач D-16: расширяем словарь типов и описываем их
свойства (категория, биом-предпочтение, размер, минимальная стадия, «крупный»
ли юнит, в какой юнит эволюционирует и по какому порогу). Без визуала и без
изменения планировщика — только модель данных.

### Пользовательский сценарий
1. Разработчик открывает `CityState.swift` и видит, что `UnitKind` содержит все
   50 значений из таблицы F-16 (по 12 жилых + 8 инфра + 12 производство + 10
   социальное + 5 религиозное + 3 военное).
2. Для каждого юнита из 50 можно программно получить русский `label`, категорию,
   набор предпочтительных биомов, размер в клетках, минимальную стадию,
   признак «крупного» юнита и, если он эволюционирующий — целевой тип и
   количественный порог.
3. Существующие 12 юнитов остаются валидными `UnitKind` (миграция старого
   состояния — отдельная подзадача TASK-037, эта задача не ломает чтение
   старого state).

### Acceptance criteria
- [ ] Перечислено ровно **50 значений** `UnitKind`, по одной на каждую строку
      таблиц F-16 (жилые 12 + инфра 8 + производство 12 + социальное 10 +
      религиозное 5 + военное 3 = 50).
- [ ] Для каждого из 50 значений определён русский `label` (например, «Землянка»,
      «Каменоломня», «Пирамида»), категория из 6 типов (жилое, инфра,
      производство, социальное, религиозное, военное), список предпочтительных
      биомов, размер footprint, `minStage` (0..5), флаг `large` (true/false),
      целевой `UnitKind` для эволюции (или nil) и порог количества для
      эволюции (или nil).
- [ ] Категория `UnitCategory` расширена двумя новыми значениями —
      `.religious` и `.military` — и старые `.residential / .infrastructure /
      .production / .social` остаются.
- [ ] Старые 12 case'ов (`shack`, `house`, `villa`, `well`, `road`, `warehouse`,
      `workshop`, `raw`, `market`, `forum`, `temple`, `obelisk`) сохранены как
      валидные `UnitKind` (rawValue не меняется), чтобы старые `events.jsonl` и
      `state.json` декодировались без ошибок.
- [ ] Сборка проекта (`swift build`) проходит без новых предупреждений и без
      ошибок exhaustiveness в существующих `switch` по `UnitKind` (если
      `switch` теряет полноту — добавить default или явные ветки, не меняя
      продуктовое поведение).

### Что НЕ делаем (границы скоупа)
- Не рисуем спрайты для новых 38 юнитов — это TASK-032 (placeholder) и
  TASK-040 (финальные PNG).
- Не трогаем `UnitPlanner` (выбор юнита под биом/stage/counters — TASK-035).
- Не считаем terrain-аффинитет с биомом мира — это TASK-033.
- Не реализуем эволюционную подмену клеток в рантайме — это TASK-034.
- Не делаем миграцию старого state (12 → 50) — это TASK-037.
- Не пишем тесты планировщика — это TASK-038.

### Edge cases
- [ ] В исходных таблицах F-16 у некоторых юнитов биом «любой» — кодируется
      как «все 7 биомов разрешены равновероятно», а не как `nil`.
- [ ] Юниты с эволюцией (Землянка, Лачуга, Хижина, Дом, Каменный дом,
      Двухэтажный, Фермерский, Склад) указывают цель и порог; нет неявных
      циклов («A → B → A»).
- [ ] `large = true` и наличие эволюции — взаимоисключающие свойства (если
      `large = true`, то цель эволюции = nil). Все 8 эволюционирующих юнитов
      из таблицы — `large = false`.
- [ ] Юниты без минимального стейджа (`minStage = 0`) — Землянка, Лачуга,
      Хижина, Колодец, Дорога, Ферма, Рыболовецкий причал, Склад — должны
      быть выбираемы планировщиком уже на stage 0 (использование — в TASK-035).

### Зависимости
- Логически идёт первой среди подзадач D-16: блокирует TASK-032, TASK-033,
  TASK-034, TASK-035, TASK-036, TASK-037, TASK-038.
- Не блокирована другими задачами (опирается только на текущий `CityState.swift`).

### Дизайн
Не применимо (нет UI).

### Done-критерий
_Из Concept.md F-16:_ Все 50 юнитов имеют реализованный спрайт и корректно выбираются
алгоритмом размещения с учётом `terrain`, `minStage` и `large`. Эволюционные цепочки
визуально срабатывают при достижении порога. Квартал из 30+ юнитов содержит ≥ 3
разных категории. Воспроизводимость через replay.

---

## 🛠 Технический разбор от тимлида

_Статус: [x] разбор готов_
_Автор: lead (Opus)_
_Дата: 2026-05-22_

### Архитектурное решение

**Один enum на 50 case'ов**, плоская структура. Никакой иерархии
`UnitKind` (12) + `UnitSubKind` (38).

Обоснование (выбор между «плоский 50» vs «иерархия 12+UnitSubKind»):

1. **Совместимость со старым state (AC4).** Если ввести `UnitSubKind`, то
   старое поле `UnitState.kind: UnitKind` либо остаётся `UnitKind` (тогда
   38 новых юнитов некуда положить и `UnitPlanner` не сможет вернуть «Шахту»),
   либо превращается в составной тип — а это breaking change в Codable: ни
   `state.json`, ни `events.jsonl` уже не декодируются как раньше. Плоский enum
   с тем же `rawValue` для старых 12 case'ов даёт нулевую миграцию (AC4 «out
   of the box»).
2. **Source of truth — таблицы F-16.** Концепт описывает 50 юнитов как
   плоский список из 6 категорий; категория уже моделируется через
   `UnitCategory` (отдельный enum + `var category`), а не через тип `kind`.
   Это уже принятый подход в проекте — расширяем его, не ломаем.
3. **Exhaustive switch'и — управляемая проблема.** В кодовой базе ровно
   **5 мест** делают exhaustive switch по `UnitKind` (`UnitSprites.swift:839`
   building factory, `UnitSprites.swift:872` `groundColor`, `LifeSimulationManager
   .swift:90` animations, `InspectorOverlayCard.swift:59` russianKind,
   `InspectorPanel.swift:85` russianKind). Из них два дублирующих `russianKind`
   тривиально переписываются на `kind.label` (новый source of truth — AC2),
   а оставшиеся три закрываются одним `default:` веткой с разумным
   fallback'ом (для placeholder-визуала из TASK-032, для groundColor —
   `Palette.sandLight`, для анимации — `return`). Это **в скоупе данной
   задачи** — AC5 явно требует «no exhaustiveness errors».
4. **Стоимость дублирующего кода.** Иерархия требует дополнительный enum,
   функцию `kind.fullKind`, расширения для категории, label, и т.д. — в
   итоге больше кода и две точки правды для «что есть юнит». 50 case'ов в
   одном enum — компактнее и читабельнее (Swift отлично жуёт 50 case'ов,
   IDE справляется).

**Риски и компенсация:** добавление новых `case` в `UnitKind` в будущем
сломает любой свежий exhaustive switch — но политика «использовать
`default` + комментарий с TODO» закрывает риск. Это документируется в
коде комментарием над enum.

### Структура изменений (только `CityState.swift` + минимальная правка
exhaustive switch'ей)

#### 1. Биом-перечисление (нужно «здесь и сейчас» для поля `terrain`)

В `CityState.swift` добавить `enum BiomeKind`. TASK-027 пока не
реализован, поэтому вводим тип в той же файле, где живёт каталог; когда
TASK-027 принесёт свой `Biome`, миграция = переименование/перенос
(typealias оставить на короткий период).

```swift
enum BiomeKind: String, Codable, CaseIterable {
    case meadow, forest, mountain, stone, river, sea, desert
}
```

Маркер «любой биом» (из F-16) — это `BiomeKind.allCases` в `terrain: [BiomeKind]`,
**не** `nil` (см. AC edge case «любой = все 7 биомов»).

#### 2. Расширить `UnitCategory`

```swift
enum UnitCategory: String, Codable {
    case residential, infrastructure, production, social, religious, military
}
```

Старые 4 значения сохраняются с теми же `rawValue` → старый код не ломается.

#### 3. Расширить `UnitKind` до 50 case'ов

Группировка по категориям (комментарии-заголовки в коде). Старые 12
case'ов **сохраняют тот же rawValue** (написание идентично). Список
имён (rawValue, lowerCamelCase):

- **Residential (12):** `dugout`, `shack`, `hut`, `farmHouse`, `house`,
  `twoStoryHouse`, `stoneHouse`, `townhouse`, `tenement`, `manor`,
  `villa`, `palace`. (Из них старые: `shack`, `house`, `villa`.)
- **Infrastructure (8):** `well`, `road`, `gate`, `bridge`, `cistern`,
  `lighthouse`, `irrigationCanal`, `pier`. (Старые: `well`, `road`.
  `warehouse` уходит в production по F-16 — он там промаркирован как
  производственный склад с эволюцией 3→Большой склад, но **в текущем
  коде** он `.infrastructure`. Решение: **оставить `warehouse` в
  `.infrastructure`** для совместимости со старым state-категоризатором
  и UnitPlanner'ом; F-16-классификация уйдёт в TASK-035, который и так
  переписывает планировщик.)
- **Production (12):** `farm`, `fishingPier`, `workshop`, `raw` (старая
  «сырьевая яма» — остаётся как production-юнит, rawValue не меняется),
  `forge`, `pottery`, `brewery`, `sawmill`, `quarry`, `mine`,
  `largeWarehouse`, `factory`. Итого ровно 12.

  **Решение по `warehouse` (важный contradiction в спеке).** В таблице
  F-16 «Склад» помечен одновременно `large = да` и `Эволюция = 3 →
  Большой склад`. Это конфликтует с AC edge case задачи: «`large = true`
  и наличие эволюции — взаимоисключающие свойства; все 8 эволюционирующих
  юнитов — `large = false`». **AC задачи перевешивают концепт** (PM-постановка
  принята как source of truth). Конкретно:

  - `warehouse` остаётся в `.infrastructure` (legacy для AC4 — не меняем
    категоризатор в этой задаче; TASK-035 переклассифицирует в `.production`).
  - В каталоге для `warehouse`: `large = false`, `evolvesTo =
    .largeWarehouse`, `evolutionThreshold = 3`. Это консистентно с AC
    edge case «8 эволюционирующих → large=false» и с шапкой раздела
    «Эволюционные цепочки» из F-16 (там Склад явно перечислен в списке
    цепочек).
  - `largeWarehouse` — отдельный самостоятельный юнит в `.production`
    (`large = true`, `evolvesTo = nil`). В квартал попадает через
    механизм эволюционной подмены клетки (TASK-034) либо прямой выбор
    планировщиком при stage ≥ 3 (TASK-035). В этой задаче — только
    запись в каталоге.
  - В код добавляем `// TODO TASK-035: warehouse → .production по F-16;
    в текущей задаче оставлен .infrastructure для AC4 (не менять
    поведение UnitPlanner.pickKind(.infrastructure))`.
- **Social (10):** `tavern`, `market`, `plaza`, `bathhouse`, `school`,
  `hospital`, `forum`, `library`, `aqueduct`, `theater`. (Старые: `market`,
  `forum`.)
- **Religious (5):** `chapel`, `temple`, `obelisk`, `cathedral`, `pyramid`.
  (Старые: `temple`, `obelisk` — **переезжают** из `.social` в `.religious`.
  Это меняет поведение `UnitPlanner.pickKind(.social)`, который явно
  возвращает `.temple/.obelisk`. **Решение:** не меняем категорию `temple/
  obelisk` в этой задаче — оставляем `.social` (legacy), а новые
  religious-юниты `chapel/cathedral/pyramid` — в `.religious`. Полная
  ре-категоризация temple/obelisk → TASK-035 вместе с переписыванием
  планировщика. В этой задаче приоритет AC4 «старый state остаётся
  валидным и поведение не меняется».)
- **Military (3):** `watchtower`, `barracks`, `shipyard`.

Итого: 12 + 8 + 12 + 10 + 5 + 3 = **50** case'ов. ✅

#### 4. Описание свойств юнита

Вынести в отдельную структуру `UnitKindInfo` + словарь, а не 6 гигантских
switch'ей.

```swift
struct UnitKindInfo {
    let label: String
    let category: UnitCategory
    let terrain: [BiomeKind]       // [.meadow,.forest,...] — пусто никогда; «любой» = BiomeKind.allCases
    let size: GridSize             // {w: Int, h: Int}
    let minStage: Int              // 0..5
    let large: Bool
    let evolvesTo: UnitKind?       // nil если не эволюционирует или large
    let evolutionThreshold: Int?   // nil если evolvesTo == nil
}

struct GridSize: Codable, Hashable {
    let width: Int
    let height: Int
}

extension UnitKind {
    var info: UnitKindInfo { Self.catalog[self]! }  // словарь покрывает все 50

    var label: String          { info.label }
    var category: UnitCategory { info.category }
    var terrain: [BiomeKind]   { info.terrain }
    var size: GridSize         { info.size }
    var minStage: Int          { info.minStage }
    var large: Bool            { info.large }
    var evolvesTo: UnitKind?   { info.evolvesTo }
    var evolutionThreshold: Int? { info.evolutionThreshold }

    private static let catalog: [UnitKind: UnitKindInfo] = [
        .dugout: UnitKindInfo(label: "Землянка", category: .residential,
                              terrain: BiomeKind.allCases, size: .init(width:1,height:1),
                              minStage: 0, large: false,
                              evolvesTo: .shack, evolutionThreshold: 2),
        // … 49 строк по таблицам F-16 …
    ]
}
```

**Защитный compile-time тест** в `Tests/CityDeveloperTests/UnitKindCatalogTests.swift`
(директория `Tests/CityDeveloperTests/` существует — проверено):

- `UnitKind.allCases.count == 50`
- `UnitKind.allCases.allSatisfy { Self.catalog[$0] != nil }` (нет дыр)
- инварианты из AC edge cases: `large == true → evolvesTo == nil`,
  `evolvesTo != nil ↔ evolutionThreshold != nil`, нет циклов эволюции
  (BFS-проверка), `info.terrain` непустой.

Тесты обязательны — это «model integrity», их легко покрыть, и они
страхуют от ручных опечаток в таблице на 50 строк.

#### 5. Правки exhaustive switch'ей (5 мест, минимально)

- `UnitSprites.swift:839` (factory) — добавить `default: container.addChild(makePlaceholder(for: unit))`. `makePlaceholder` — простой однотонный куб с label-инициалом; финальный
  placeholder приедет в TASK-032, здесь — заглушка-однострочник в этом же
  файле, чтобы не ломать сборку. **Допустимо:** TASK-032 уже знает, что её
  стартовая точка — placeholder-фабрика поверх «default».
- `UnitSprites.swift:872` (`groundColor`) — `default: return Palette.sandLight` (уже есть `default` — ничего не трогаем; проверить).
- `LifeSimulationManager.swift:90` (animations) — добавить `default: return`.
  Новые юниты пока без анимации, это не регрессия.
- `InspectorOverlayCard.swift:57` (`russianKind`) — переписать на одну
  строку `kind.label`, удалить switch.
- `InspectorPanel.swift:83` (`russianKind`) — аналогично, на `kind.label`.

Дубль кода `russianKind` устраняется в этой задаче — это требование AC
«нет хардкод-строк в UI».

### Compile-time / runtime контракты (что обязательно держать)

- **rawValue стабилен** для старых 12 case'ов — `state.json` и
  `events.jsonl` должны декодироваться без миграции (AC4). Тесты
  миграции — TASK-037, но базовая совместимость закрыта здесь.
- **`UnitCategory` дополняется**, не переименовывается — старый
  `events.jsonl` с `"category":"residential"` валиден.
- **Категория `temple/obelisk` в этой задаче — `.social`**, не `.religious`.
  Это сознательное legacy-сохранение поведения `UnitPlanner` (он будет
  переписан в TASK-035). В коде ставим `// TODO TASK-035: переклассифицировать
  temple/obelisk в .religious одновременно с переписыванием планировщика`.
- **Категория `warehouse` — `.infrastructure`** (legacy), даже несмотря
  на F-16 («производство»). Тот же TODO с указанием на TASK-035.
- **`pickKind(.religious)` и `pickKind(.military)` в UnitPlanner** — НЕ
  добавляем (out of scope; планировщик не должен знать про новые категории
  до TASK-035, и его 4-категориальный pattern на 20 слотов остаётся
  нетронутым — никаких новых вызовов `pickKind` с этими category не
  будет).
- **Декодер `UnitKind`** — `String, Codable` через rawValue (как сейчас).
  Неизвестные rawValue из old events → throw в Codable. Обработка
  неизвестных значений (graceful skip) — это TASK-037.

### Файлы, которые меняются

1. `Sources/CityDeveloper/Data/CityState.swift` — главный диф (+~200
   строк): `BiomeKind`, `GridSize`, расширенный `UnitKind`, расширенный
   `UnitCategory`, `UnitKindInfo`, словарь `catalog`, accessors.
2. `Sources/CityDeveloper/Game/UnitSprites.swift` — `default:` в двух
   switch'ах (один — добавление placeholder-вызова, один — уже есть default,
   проверить); один маленький `makePlaceholder(for:)` приватный helper.
3. `Sources/CityDeveloper/Game/LifeSimulationManager.swift` — `default: return`.
4. `Sources/CityDeveloper/UI/InspectorOverlayCard.swift` — `russianKind` → `kind.label`.
5. `Sources/CityDeveloper/Game/InspectorPanel.swift` — `russianKind` → `kind.label`.
6. (Опционально, если есть `Tests/`) `Tests/CityDeveloperTests/UnitKindCatalogTests.swift`
   — 4 теста-инварианта.

### Что НЕ трогать

- `UnitPlanner.swift` — целиком out of scope (TASK-035).
- `DecayVisuals.swift`, `DecayEngine.swift` — `originalKind` принимает
  любой `UnitKind`, путь руины уже общий.
- `CityEngine.swift` — не трогать, продолжает звать
  `unitPlanner.nextUnitKind(...)` со старым контрактом.
- `CitizenManager.swift:124` — список `[forum, market, well, warehouse]`
  для гражданских AI: оставить как есть (TASK-036/038 расширят при
  необходимости).

### План работ (для исполнителя)

1. В `CityState.swift` — добавить `BiomeKind`, `GridSize`, расширить
   `UnitCategory`, расширить `UnitKind` до 50 case'ов (сначала сами
   case'ы — компилятор покажет где сломалось).
2. Залатать 5 exhaustive switch'ей минимальными `default:` (см. выше).
   Сборка должна пройти.
3. Заменить два дубля `russianKind` на `kind.label`.
4. Заполнить словарь `catalog` ровно 50 строк по таблицам F-16.
5. Добавить compile-time invariant-тесты в
   `Tests/CityDeveloperTests/UnitKindCatalogTests.swift`.
6. `swift build` — без новых warning'ов.
7. `swift test` — все тесты (включая 4 новых invariant'а) проходят.
8. Обновить `Current.md` (F-16 → ⚠️). Diff.md D-16 не закрывать.

### Команды проверки (для DoD)
- Компиляция: `swift build`
- Тесты: `swift test`
- Ручная проверка: запустить приложение, открыть инспектор любого
  юнита — русский label отображается (проверка, что замена `russianKind`
  → `kind.label` не сломала UI).

### Сложность / объём
- **Сложность:** middle (механическая работа на 50 строк таблицы +
  аккуратность с legacy-совместимостью; никакой алгоритмики).
- **Объём:** M (один большой файл данных + 4 мелкие правки call-site'ов
  + опционально тесты).

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: middle_
_Объём: M_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Done-критерий проверен в реальном использовании (на этой задаче — только
      словарь; полная проверка F-16 — после TASK-040)

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Тесты не сломаны
- [ ] Нет хардкод-строк (русские label — в `UnitKind.label`, не в UI-вьюхах)

#### Обновление документации
- [ ] `Current.md`: F-16 → ⚠️ (каталог расширен, визуал и планировщик —
      следующими задачами)
- [ ] `Diff.md`: D-16 не закрывать — закрывается только после TASK-040
- [ ] Новые идеи → `Backlog.md`, новые баги → `Bugs.md`

---

## Статус

`[ ] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[x] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-22
- Spec-review: approved
- Blocked-by: —
- Готова к работе: 2026-05-22
- Lead-model: opus
- Plan-review: revised (round 1 → approved, минорная правка по warehouse-contradiction и команде swift test)
- Завершена: 2026-05-23
- Исполнитель: sonnet
- Code-review: approved
- Коммит: 0473158 (bundled with TASK-039 by pre-commit hook)
