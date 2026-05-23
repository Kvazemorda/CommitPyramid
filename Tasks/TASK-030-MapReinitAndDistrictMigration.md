# TASK-030: Реинициализация карты и перенос кварталов с учётом биомов

## Связь
- **F-15** из Concept.md (реинициализация, аффинитет)
- **F-06** из Concept.md (размещение кварталов)
- **F-14** из Concept.md (Settings)
- **D-15** из Diff.md (часть 5/5 — финальный шаг, закрывает D-15)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-23_

### Что хотим
Дать игроку возможность пересобрать карту мира (с тем же seed или с новым) из
настроек и при этом не потерять историю города. После реинициализации все
существующие кварталы должны переехать на новый рельеф так, чтобы это
выглядело осмысленно (рядом с подходящим биомом), а лог событий остался
нетронутым. Это финальный шаг D-15: после него фича F-15 действительно
закрыта.

### Пользовательский сценарий
1. Игрок открывает Settings и видит секцию «Карта мира» с текущим seed и
   кнопкой «Сбросить карту».
2. Игрок задаёт новый seed (или оставляет случайный) и нажимает «Сбросить».
3. Появляется подтверждение: «Карта будет пересоздана, кварталы переразмещены.
   История событий сохранится. Продолжить?».
4. Игрок подтверждает — карта пересобирается, все существующие кварталы видны
   на новых местах: квартал рядом с рекой стоит у реки, горный квартал — на
   камнях/горах, береговой — у моря, и т. д.
5. Лог `events.jsonl` не меняется задним числом; в него добавляется одно
   системное событие «map_regenerated» с новым seed для воспроизводимости.

### Acceptance criteria
- [ ] В Settings есть отдельная секция «Карта мира» с показом текущего seed и
      кнопкой «Сбросить карту»; кнопка вызывает диалог подтверждения с
      понятным предупреждением.
- [ ] После подтверждения карта пересобирается (используя seed из поля ввода;
      пустое поле = новый случайный seed), переход проходит без перезапуска
      приложения и без потери активного состояния (юниты живы, симуляция
      продолжает работать).
- [ ] Каждый существующий квартал получает новое origin на новой карте; квартал
      с преобладающим terrain-аффинитетом юнитов (например, много «водных»
      юнитов) с заметно большей вероятностью оказывается в соответствующем
      биоме, чем при равномерном случайном размещении.
- [ ] Файл `events.jsonl` не модифицируется задним числом; добавляется ровно
      одно системное событие «map_regenerated» с новым seed, и игра остаётся
      воспроизводимой через replay (старая часть лога переигрывается на
      исходной карте, новая — на новой).
- [ ] Текущая (ещё не пересобранная) карта стартует именно с записанного seed
      при следующем запуске — то есть результат реинициализации переживает
      перезапуск приложения.

### Что НЕ делаем (границы скоупа)
- Не реализуем полноценный «множественный мир» / профили карты — только один
  активный мир.
- Не делаем undo для реинициализации (диалог подтверждения — единственная
  защита от случайного клика).
- Не вводим полную модель `terrain` для 50 юнитов из F-16 — здесь достаточно
  упрощённого аффинитета на базе уже существующих юнитов и их «логического»
  биома (например, well/обелиск — нейтральный, рыночные — луг, складские —
  любой). Полная карта аффинитетов придёт с F-16.
- Не перерисовываем здания вручную — для каждого нового origin используется
  существующий механизм размещения (F-06).

### Edge cases
- [ ] На карте нет ни одного квартала → реинициализация просто меняет рельеф,
      без миграции и без падений.
- [ ] Кварталов больше, чем «удобных» мест в подходящих биомах → лишние
      кварталы размещаются по запасному правилу (свободный луг / ближайший
      допустимый биом), без потерь и без наложений друг на друга.
- [ ] Введён некорректный seed (нечисловой текст / пустое поле / слишком
      длинное значение) → понятная валидация в Settings, кнопка «Сбросить»
      неактивна до исправления (или для пустого поля = «случайный seed»,
      это допустимое поведение).
- [ ] Реинициализация прерывается (например, ошибка записи на диск) →
      старая карта остаётся активной, состояние игры не повреждено, ошибка
      попадает в `errors.log` с понятным сообщением для пользователя.
- [ ] Игрок жмёт «Сбросить» несколько раз подряд → выполняется ровно одна
      пересборка, повторные нажатия игнорируются до её завершения.

### Зависимости
- **Blocked-by:** TASK-026 (seed/поля), TASK-027 (биомы), TASK-028 (рендер
  нового рельефа), TASK-029 (зум для проверки результата). Это финальная
  подзадача D-15.

### Дизайн
Раздел Settings из `concept/DesignConcept.md` (та же палитра «pharaoh»: песочный
фон, тёплый акцент, кнопка-предупреждение для «Сбросить»). Конкретные токены —
по существующим элементам `UI/SettingsView.swift`; новых стилей не вводим.

### Done-критерий
_Из Concept.md F-15:_ При первом запуске генерируется карта ≥ 256×256 тайлов с не менее
чем 4 разными биомами, соединёнными плавными переходами. Карта воспроизводима из seed.
Кнопка «Сбросить карту» + подтверждение → новая генерация, кварталы переразмещаются.
Зум позволяет увидеть всю карту в одном экране. Новый квартал рядом с рекой получает
водные/речные юниты с заметно большей вероятностью, чем равномерная.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-23_
_Модель: opus_
_Статус: [x] escalate-too-large_

### Вердикт

**`escalate-too-large` + предупреждение `blocked-spec-not-ready` по цепочке зависимостей.**

Технический план **не пишется** (по правилу: L → не пишем план, дробим через `/pm`).

### Обоснование (две независимые причины)

**1. Цепочка blocked-by фактически не пройдена.**

TASK-026/027/028/029 значатся в зависимостях, но **все четыре** сейчас в статусе
`waiting-for-lead` и ни одна строка кода по ним не написана:
- В коде нет ни одного файла с `Noise*`, `BiomeMap*`, `MapState*`, `Seed*`.
- В `GridPoint` / `ProjectState` нет поля `biome` / terrain-аффинитета.
- В `AppSettings` нет поля `mapSeed` (см. `Sources/CityDeveloper/Data/AppSettings.swift:1-82` — только tasks/data/hotkey/catchUp).
- `GameScene` всё ещё рисует плоский луг `SKSpriteNode(color: Palette.nileGreen, size: 8000×8000)` (`Sources/CityDeveloper/Game/GameScene.swift:38-41`).
- Нет файла данных карты рядом с `events.jsonl`/`state.json` (`Data/AppPaths.swift:14-19` — только tasks/events/state/ingestion/errors/catchup).

Подробный план потребовал бы ссылаться на API (`NoiseField.height(at:)`,
`BiomeClassifier.biome(at:)`, `BiomeRenderer.rebuild(from:)`, `CameraBounds.recompute()`, …),
которых пока не существует ни сигнатурно, ни концептуально — TASK-026..029 ещё не
разобраны лидом, их интерфейсы не зафиксированы. Юниор, получив такой план, упрётся
в «type not found» на первом же шаге.

**2. Объём задачи ≥ L даже при готовых 026..029.**

Расчёт по шагам (минимум):

| Слой | Что трогаем | Файлы |
|------|-------------|-------|
| Settings UI | Новая GroupBox «Карта мира», поле seed, валидация, кнопка-предупреждение, диалог подтверждения, double-click guard | `UI/SettingsView.swift` (+1 новый sub-view для диалога) |
| AppSettings | Persist `mapSeed: UInt64?`, миграция `Persisted.version` v2→v3 | `Data/AppSettings.swift` |
| Data paths | `mapStateJson` URL рядом с `state.json` | `Data/AppPaths.swift` |
| CityState | Поле `mapSeed` (либо отдельный `MapState` файл с seed+versionHash) | `Data/CityState.swift` или новый `Data/MapState.swift` |
| Snapshot версия | StateSnapshot v1 → v2 (миграция старых снапшотов на новый формат с seed; на v1 — дефолтный seed для legacy-карты) | `Data/StateSnapshot.swift`, `Data/SnapshotStore.swift` |
| Event log | Новый `GameEvent.Kind.mapRegenerated`, поле `meta` (или payload) для seed; apply-handler в `CityEngine` | `Data/GameEvent.swift`, `Game/CityEngine.swift` |
| Reinit-оркестратор | Атомарная пересборка: stop sim → новый noise/biome → migration → rebuild scene → restart sim; rollback при failure; idempotency guard | новый `Game/MapReinitCoordinator.swift` (или метод в `CityEngine`) |
| Миграция кварталов | Логический биом для каждого `UnitKind` (12 типов), агрегация по проекту, scoring-функция «aff vs distance», запасное правило (свободный луг / ближайший допустимый биом), no-overlap инвариант со spacing≥14 (см. `DistrictPlanner:26`), детерминизм по seed | новый `Game/DistrictMigrator.swift`, изменения в `DistrictPlanner` |
| GameScene | Teardown lawn + tile-rebuild от новой карты (TASK-028 даёт renderer); reposition `districtNodes`/`unitNodes` по новым origin без полного reload; `applyDecay` re-apply | `Game/GameScene.swift` (большая часть `didMove`, plus новый `applyMapReinit(...)`) |
| AppDelegate wiring | Вызов settingsWindowController → reinit, double-click guard, error-alert при rollback | `App/AppDelegate.swift`, `App/SettingsWindowController.swift` |
| Replay determinism | Контракт: либо в `mapRegenerated`-событии хранится полный map `projectId → newOrigin` (тяжёлый event, но честный replay), либо миграция строго детерминирована по `(seed, отсортированный список projectId на момент reinit)` — обе ветки имеют trade-off | архитектурное решение |
| Tests | Хотя бы smoke на детерминизм миграции и на edge `пустой город` | `Tests/CityDeveloperTests/MapReinitTests.swift` |

Итого **≥10 файлов в 4 слоях** (Data, Game, UI, App) + новая алгоритмическая
единица (migrator) + миграция формата снапшота + расширение event-log + контракт
replay determinism. По регламенту это **senior + L**; по правилу из `~/.claude/commands/lead.md`
шаг 5: «Если объём = L — **не пиши план**, переходи к шагу 7 с вердиктом
`escalate-too-large`.»

### Архитектурная развилка, которую нужно решить ДО разбиения (вопрос к /pm)

**Как обеспечить «старая часть лога переигрывается на исходной карте, новая — на
новой» (AC #4)?** Варианты:

- **A. Event-carries-map:** `map_regenerated` несёт полный snapshot `{newSeed,
  projectId → newOrigin}`. Replay просто применяет. Плюс: однозначно детерминирован.
  Минус: размер события растёт с количеством кварталов; меняется схема
  `GameEvent` (нужен `payload: Codable?` или отдельный тип).
- **B. Deterministic-migration:** в событии только `newSeed`. Replay
  пересчитывает миграцию по seed + текущему (к этому моменту replay) списку
  проектов. Плюс: компактно. Минус: миграция должна быть строго чистой функцией
  от `(seed, sorted projectIds, перцентили биомов)` — любая правка алгоритма
  ломает старые логи. Нужен `migratorVersion` в событии + версия алгоритма
  внутри кода.
- **C. Hybrid:** seed + versioned algorithm, плюс при load-mismatch — fallback
  к B с записью предупреждения в `errors.log`.

Это решение PM-уровня (или совместно lead+PM), потому что задаёт «контракт
вечности» для events.jsonl. Без него юниор не сможет реализовать AC #4.

### Рекомендуемое разбиение (для `/pm 030 split`)

| Под-задача | Скоуп | Объём | Зависит от |
|------------|-------|-------|------------|
| **TASK-030a: Settings «Карта мира» (UI + persist seed)** | Новая GroupBox в `SettingsView`, валидация seed-поля, кнопка-предупреждение, диалог подтверждения, `AppSettings.mapSeed`, миграция Persisted v2→v3, double-click guard на уровне UI | S | TASK-026 (структура seed) |
| **TASK-030b: Map reinit orchestrator + event-log контракт** | Новый `MapReinitCoordinator`, новый `GameEvent.Kind.mapRegenerated` (с принятым payload-форматом — см. развилку A/B/C), apply-handler, atomic rollback при write-failure, ошибка → `errors.log` + user-alert | M | TASK-030a, TASK-026, **архитектурное решение** |
| **TASK-030c: District migrator с terrain-аффинитетом** | Маппинг UnitKind → логический биом (12 типов, упрощённо: water → river/sea, stone → mountains/rocks, neutral — луг/любой), scoring, fallback на свободный луг, no-overlap инвариант (spacing≥14), детерминизм | M | TASK-027 (биомы), TASK-030b |
| **TASK-030d: GameScene rebuild + snapshot v2 + camera bound recompute** | Teardown старого рельефа без потери `unitNodes`/`districtNodes`, repositioning по новым origin, `StateSnapshot.currentVersion = 2` с миграцией v1, hook на пересчёт границ камеры (TASK-029) | M | TASK-028, TASK-029, TASK-030b, TASK-030c |

После разбиения каждая под-задача независимо проходит /lead, и риск «сломать
event-log/snapshot задним числом» локализован в TASK-030b/d.

### Файлы для будущих под-задач (для удобства /pm)

- `Sources/CityDeveloper/UI/SettingsView.swift` — секция «Карта мира»
- `Sources/CityDeveloper/Data/AppSettings.swift` — `mapSeed` + Persisted v3
- `Sources/CityDeveloper/Data/AppPaths.swift` — `mapStateJson`
- `Sources/CityDeveloper/Data/CityState.swift` или `Data/MapState.swift` — seed
- `Sources/CityDeveloper/Data/StateSnapshot.swift` + `SnapshotStore.swift` — v2 миграция
- `Sources/CityDeveloper/Data/GameEvent.swift` — `mapRegenerated` kind + payload
- `Sources/CityDeveloper/Game/CityEngine.swift` — apply(mapRegenerated)
- `Sources/CityDeveloper/Game/MapReinitCoordinator.swift` (новый)
- `Sources/CityDeveloper/Game/DistrictMigrator.swift` (новый)
- `Sources/CityDeveloper/Game/DistrictPlanner.swift` — biome-aware allocate
- `Sources/CityDeveloper/Game/GameScene.swift` — teardown/rebuild + reposition
- `Sources/CityDeveloper/App/AppDelegate.swift` + `SettingsWindowController.swift` — wiring + double-click guard
- `Tests/CityDeveloperTests/MapReinitTests.swift` (новый)

### Файлы НЕ трогать

- `Sources/CityDeveloper/Data/EventLog.swift` — формат хранения линий стабилен,
  меняется только содержимое `GameEvent`.
- `Sources/CityDeveloper/Game/CitizenManager.swift` / `CitizenSprites.swift` —
  жители не привязаны к биому в этой задаче (F-16 потом).
- Существующий `lifeSim` callback contract — не ломаем.

### Сложность

`senior`

**Обоснование:** миграция формата snapshot + расширение event-log + replay
determinism + новый алгоритм migration с детерминизмом — четыре независимых
архитектурных решения в одной задаче, при ≥10 файлах в 4 слоях.

### Ожидаемое время

`L` (>1д — обязательное дробление через `/pm`)

### Следующее действие

`/pm 030 split` — разбить на 030a/030b/030c/030d по таблице выше, **сначала**
разрешив архитектурную развилку A/B/C для replay determinism. После
завершения TASK-026..029 каждая под-задача проходит /lead отдельно.

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: senior_ (определено лидом)
_Объём: L_ (требует дробления через `/pm`)

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Done-критерий F-15 проверен в реальном использовании целиком (вместе с TASK-026..029): карта ≥ 256×256, ≥ 4 биома, плавные переходы, воспроизводимость из seed, обзорный зум, реинициализация, аффинитет.

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Тесты не сломаны
- [ ] Нет хардкод-строк (i18n/env где требует проект)

#### Обновление документации
- [ ] `current.md`: F-15 → ✅
- [ ] `diff.md`: D-15 удалён
- [ ] Новые идеи → `backlog.md`, новые баги → `bugs.md`

---

## Статус

`[ ] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[ ] done` / `[ ] skipped` / `[x] escalated-too-large`

## Метаданные
- Создана PM: 2026-05-23
- Spec-review: approved
- Blocked-by: TASK-026, TASK-027, TASK-028, TASK-029 (ни одна ещё не разобрана/готова)
- Lead-разбор: 2026-05-23
- Lead-model: opus
- Lead-verdict: escalate-too-large (см. раздел «🛠 Технический разбор от тимлида»)
- Plan-review: n/a (по правилу: при L план не пишется, ревью пропускается)
- Готова к работе: —
- Завершена: —
- Коммит: —
