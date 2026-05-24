# TemplateCatalog — Шаблоны кварталов (F-25)

Документация по формату JSON, каталогу шаблонов и egyptian-семье.
Часть 1/5 F-25: egyptian family (stages 1–5). Roman + Greek — backlog.

---

## Формат JSON

Каждый шаблон — один `.json`-файл в `Sources/CityDeveloper/Resources/DistrictTemplates/<family>/`.

### Схема

```json
{
  "name": "<уникальное имя внутри family>",
  "family": "<имя семьи: egyptian | roman | greek | ...>",
  "stage": <целое 1..5>,
  "width": <ширина сетки>,
  "height": <высота сетки>,
  "biomePreference": ["<BiomeKind>", ...],
  "slots": [
    {
      "x": <0..width-1>,
      "y": <0..height-1>,
      "role": "<SlotRole>",
      "footprint": { "width": <1..N>, "height": <1..N> }
    }
  ]
}
```

### Поля

| Поле | Тип | Описание |
|---|---|---|
| `name` | String | Уникальный идентификатор внутри family. Дубль → первый wins, предупреждение в errors.log. |
| `family` | String | Семья шаблонов. Catalog фильтрует по этому полю. |
| `stage` | Int 1..5 | Стадия развития города. |
| `width` / `height` | Int | Размер grid в клетках. Все слоты обязаны быть внутри `[0..width)×[0..height)`. |
| `biomePreference` | [BiomeKind] | Предпочтительные биомы. Пустой массив = подходит для любого. |
| `slots` | [TemplateSlot] | Список слотов. Пустой — валидно, но при использовании fallback на legacy (TASK-048). |

### SlotRole (13 значений)

`residential`, `well`, `road`, `market`, `temple`, `workshop`, `farm`, `bath`, `school`, `obelisk`, `gate`, `warehouse`, `monumental`

Большие residential (2×2, 3×3) отличаются от 1×1 через `footprint`, role одна — `residential`.

### BiomeKind (7 значений)

`meadow`, `forest`, `mountain`, `stone`, `river`, `sea`, `desert`

### Пример — stage1-deir-el-medina.json

```json
{
  "name": "stage1-deir-el-medina",
  "family": "egyptian",
  "stage": 1,
  "width": 8,
  "height": 5,
  "biomePreference": ["meadow", "desert"],
  "slots": [
    { "x": 1, "y": 1, "role": "residential", "footprint": { "width": 1, "height": 1 } },
    { "x": 2, "y": 1, "role": "residential", "footprint": { "width": 1, "height": 1 } },
    { "x": 1, "y": 2, "role": "road",        "footprint": { "width": 1, "height": 1 } },
    { "x": 2, "y": 3, "role": "well",        "footprint": { "width": 1, "height": 1 } }
  ]
}
```

---

## Egyptian-семья: 5 шаблонов

### Сводная таблица

| Файл | Stage | Слотов | Width×Height | Новые роли |
|---|---|---|---|---|
| `stage1-deir-el-medina.json` | 1 | 15 | 8×5 | residential, road, well |
| `stage2-kahun.json` | 2 | 25 | 12×7 | + farm 2×2 |
| `stage3-ahmarna-middle.json` | 3 | 35 | 14×9 | + temple 2×2, workshop |
| `stage4-pharaonic-services.json` | 4 | 45 | 16×12 | + market 2×2, bath 2×2, school 2×2 |
| `stage5-akhetaten-ceremonial.json` | 5 | 51 | 16×16 | + monumental 3×3, obelisk, residential 3×3 |

### ASCII-силуэты

**Stage 1 — Deir el-Medina (8×5)**
```
. . . . . . . .
. R R . R R . .
. = = = = = = .
. R W R . R R .
. . . . . . . .
```
R=residential, W=well, ==road

**Stage 2 — Kahun (12×7)**
```
. . . . . . . . . . . .
. R R . R R . . . F F .
. = = = = = = = = F F .
. R W R R R . . . . . .
. R R = R R . F F . . .
. . . . . . . F F . . .
. . . . . . . . . . . .
```
F=farm 2×2

**Stage 3 — Ahmarna Middle (14×9)**
```
. . . . . . . R . . . . . .
. R R . R R . . . . . F F .
. = = = = = = = = F F . . .
. R W R R R . . . . W . . .
. R R = R R . F F . . . . .
. R R = R R R . F F . . . .
. . . = . T T . . . . . . .
. . . . . T T . . . . . . .
. . . . . . . . . . . . . .
```
T=temple 2×2, W=workshop

**Stage 4 — Pharaonic Services (16×12)**
```
. . . . . . . R . . . . . . . .
. R R . R R . . . F F . . . . .
. = = = = = = = = F F W . . . .
. R W R R R . . . . . W W . . .
. R R = R R . F F . . W W . . .
. R R = R R R . F F . M M . . .
. . . = . T T . M M . W W . . .
. . . . . T T . M M . W W . . .
. B B = S S . = = . . . . . . .
. B B . S S . . . . . . . . . .
. . . . . . . . . . . . . . . .
. . . . . . . . . . . . . . . .
```
B=bath 2×2, S=school 2×2, M=market 2×2

**Stage 5 — Akhetaten Ceremonial (16×16)**
```
. . . . . . . R . . . . . . . .
. R R . R R . . . F F . . . . .
. = = = = = = = = F F W . . . .
. R W R R R . . . . . W W . . .
. R R = R R . F F . . W W . . .
. R R = R R R . F F . M M . . .
. . . = . T T . M M . W W . . .
. . . . . T T . M M . W W . . .
. B B = S S . = = . H H H . . .
. B B . S S . . . . H H H . . .
. . . . . . . . . . H H H . . .
. O = = P P P . . . . . . . . .
. r . . P P P . . . . . . . . .
. . . . P P P . . . . . . . . .
. . . . . . . . . . . . . . . .
. . . . . . . . . . . . . . . .
```
H=manor (residential 3×3), P=pyramid (monumental 3×3), O=obelisk, r=residential

---

## Как добавить новый шаблон

1. Создать JSON-файл в `Sources/CityDeveloper/Resources/DistrictTemplates/<family>/`.
2. Поле `family` в JSON должно совпадать с именем семьи.
3. Если family новая (не `egyptian`) — добавить её имя в список `families` в `DistrictTemplateCatalog.swift` (строка `let families: Set<String> = ["egyptian"]`).
4. Запустить `swift test --filter DistrictTemplateCatalogTests` — тесты проверят валидность.
5. Запустить `for f in Sources/.../egyptian/*.json; do jq . "$f" > /dev/null || echo "INVALID: $f"; done`.

Никаких изменений в `Package.swift` не нужно — `.process("Resources")` подхватит файл автоматически.

---

## Инварианты (обязательны для TASK-049)

### 1. Прогрессия слотов: slots(stage N) ⊆ slots(stage N+1)

Каждый слот stage N должен присутствовать в stage N+1 с **точно теми же** `x`, `y`, `role`, `footprint`. Stage N+1 только **добавляет** новые слоты, не изменяет и не удаляет существующие.

Проверяется тестом `testStageProgressionPreservesSlots`.

### 2. bbox не уменьшается: width(N+1) >= width(N), height(N+1) >= height(N)

Проверяется тестом `testStageProgressionBboxNonShrinking`.

### 3. Нет пересекающихся footprint

Два слота не могут занимать одну и ту же клетку `(x, y)` с учётом footprint. Проверяется `DistrictTemplateCatalog.validate(_:)` при загрузке и тестом `testNoOverlappingSlots`.

### 4. Все слоты в bounds

Каждая клетка footprint слота обязана попасть в `[0..width) × [0..height)`. Нарушение → шаблон не загружается, ошибка в `errors.log`.

---

## UnitKind → SlotRole mapping (TASK-048b)

Каждый из 51 UnitKind знает свою предпочтительную роль слота через
`kind.preferredSlotRole`. Таблица соответствий см. `Sources/CityDeveloper/
Game/Templates/UnitKindSlotRole.swift`.

Ключевые group:
- residential (12 kinds) → `.residential` слот
- linear infra (road/bridge/cistern/canal/aqueduct/pier) → `.road` слот
- production (10 kinds) → `.workshop` слот
- social services → `.market`/`.bath`/`.school`
- monumental (pyramid/cathedral/lighthouse) → `.monumental`
- religious (chapel) → `.temple`
- military (watchtower/barracks) → `.gate`; shipyard → `.farm` (на воде)

Compile-time exhaustivity: добавление нового UnitKind = compile-error
до тех пор, пока в `preferredSlotRole` switch не добавлен соответствующий case.

---

## Техническое примечание: Bundle layout

SwiftPM `.process("Resources")` сглаживает директории — все JSON попадают в корень bundle без поддиректорий `DistrictTemplates/egyptian/`. `DistrictTemplateCatalog` загружает все JSON из корня bundle и фильтрует по полю `family` из самого JSON. При переходе на `.copy("Resources")` или Xcode bundle (сохраняет структуру) логика загрузки потребует обновления (TASK-051 follow-up).
