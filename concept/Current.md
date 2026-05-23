# CityDeveloper — Текущее состояние репозитория

_Актуально на: 2026-05-22 (после полу-ночного прогона: hotkey + инспектор + полноценный изо-арт)_

## ⏱ Что сделано за прогон 2026-05-22

Доведены три ключевые позиции, висевшие после ночи 2026-05-21:

**Закрыто полностью:**
- F-01 (Окно «всегда позади» + explore) — добавлен глобальный hotkey ⌘⌥G через
  Carbon `RegisterEventHotKey` / `InstallEventHandler` (без accessibility prompt).
  Закрывает D-01.

**Закрыто частично (было ❌ → стало ⚠️):**
- F-11 (Инспектор / журнал событий) — клик по юниту показывает SpriteKit-попап с
  именем проекта, типом юнита (русские названия), стадией, заголовком задачи и
  датой её закрытия. Журнал-история с фильтром по дате/проекту — пока нет.
- F-13 (Каталог арт-ассетов) — собран `IsoBuilder` (3-гранный куб, пирамидальная
  крыша, brick-hatch, тайл-земля, тень) и `UnitSprites` с фабриками для всех 12
  типов юнитов: жильё (shack/house/villa), инфраструктура (well/road/raw),
  производство (warehouse/workshop), социалка (market/forum/temple/obelisk).
  Окошки, колоннады, трубы, навесы. Без вариаций для decay/руин и без жителей.

## Реализация фич из концепта

| ID   | Фича                                          | Статус | Где в коде                                | Детали                                     |
|------|-----------------------------------------------|--------|-------------------------------------------|--------------------------------------------|
| F-01 | Окно «всегда позади» + explore-режим          | ✅     | `App/CityWindow.swift`, `WindowModeManager.swift`, `Status/StatusBarController.swift`, `App/GlobalHotkey.swift`, `App/AppDelegate.swift` | Behind/explore + ⌘⌥G через Carbon без accessibility |
| F-02 | Изометрический рендер города                  | ⚠️     | `Game/GameScene.swift`, `Game/IsoBuilder.swift`, `Game/UnitSprites.swift` | Полноценный изо-арт; луг всё ещё `SKSpriteNode`, не `SKTileMapNode` |
| F-03 | Event sourcing (лог + replay)                 | ✅     | `Data/EventLog.swift`, `Data/GameEvent.swift`, `Game/CityEngine.swift` | Подтверждено smoke-тестом                  |
| F-04 | Watcher `tasks.jsonl` (legacy / частный случай F-18) | ✅     | `Data/TasksJsonlWatcher.swift`, `Data/IngestionState.swift`, `Data/TaskRecord.swift` | DispatchSource, валидация, offset. После F-18 — частный случай (один файл с фиксированным форматом) |
| F-05 | Лёгкая симуляция жизни квартала               | ✅     | `Game/LifeSimulationManager.swift`, `Game/GameScene.swift` | 11 типов юнитов (кроме road) + smoke/sparks/flags/ripple/silhouettes + pause при behind |
| F-06 | Project-District и автоматическое размещение  | ✅     | `Game/DistrictPlanner.swift`, `Game/CityEngine.swift` (`pickRuinForNewProject`), `Game/GameScene.swift` (`handleRuinsCleared`) | Спираль + приоритет руин (детерминированный выбор по `lastActivityAt → unitIds.count → projectId`); атомарный state-переход; визуальная анимация расчистки 3–5 сек. TASK-017 ✅ |
| F-07 | Состав и баланс юнитов в квартале             | ✅     | `Game/UnitPlanner.swift` (categoryPattern + pickKind), `Data/CityState.swift` (UnitCategory + UnitKind.category) | Категориальная таблица 10R/4I/4P/2S = 50/20/20/10%, rotation по per-category счётчикам, stage-ограничения (market≥2, temple/obelisk≥4), well-правило 1:5. TASK-018 ✅ |
| F-08 | Стадии развития квартала (0 → 5)              | ✅     | `Game/StageRules.swift` (формула), `Game/UnitSprites.swift` (makeCategoricalBuilding + 4×5 factory), `Game/CityEngine.swift` (onProjectStageChanged), `Game/GameScene.swift` (handleProjectStageChanged + swapStageSprite) | Формула stage 0→5 + категориальный tier-набор 20 спрайтов (4 категории × 5 stage), cross-fade ≤0.5 сек параллельно, bottom-anchor сохраняется. TASK-019 ✅ |
| F-09 | Decay и руины                                 | ✅     | `Game/DecayEngine.swift`, `Game/DecayVisuals.swift`, `Game/CityEngine.swift`, `Game/GameScene.swift` | DecayEngine (DispatchSourceTimer 1h), уровни 0-4, системные события decay_tick/fire/restore, визуал overlay + руины |
| F-10 | Жители и анимация                             | ✅     | `Game/CitizenManager.swift`, `Game/GameScene.swift` | CitizenManager: waypoint random walk, target min(20, stage*2+units/4) ≥3, global cap 150, bounding box ±6, two-phase fade-out, behind-pause через view.isPaused |
| F-11 | Инспектор / журнал событий                    | ✅     | `Game/InspectorPanel.swift`, `Game/GameScene.swift`, `UI/SidePanelView.swift`, `UI/ProjectCard.swift`, `UI/SceneBridge.swift`, `UI/InspectorOverlayCard.swift`, `UI/JournalKindFilter.swift`, `App/JournalWindowController.swift` | SpriteKit-попап + SwiftUI overlay-карточка (trailing center) ✅; журнал в отдельном floating-окне через кнопку `list.bullet` ✅; население per-project (TASK-014) ✅; запись `unit_built`/`stage_up` в `events.jsonl` (TASK-024) ✅; фильтр по типу события с Menu-пресетами + popover «Кастом» (TASK-015) ✅ |
| F-12 | Снэпшоты состояния                            | ✅     | `Data/StateSnapshot.swift`, `Data/SnapshotStore.swift`, `Game/CityEngine.swift` | Snapshot+tail replay, trigger 500 events/24h/quit, atomic write, fallback на full replay |
| F-13 | Каталог арт-ассетов                           | ✅     | `Game/IsoBuilder.swift`, `Game/UnitSprites.swift`, `Game/CitizenSprites.swift`, `Game/RoadConnector.swift` | 12 типов + жители + руины + штабели + road-варианты. Particle-эффекты — F-05/F-09. |
| F-14 | Настройки (UI)                                | ✅     | `Data/AppSettings.swift`, `UI/SettingsView.swift`, `App/SettingsWindowController.swift` | Путь tasks.jsonl + dataDir + hotkey, применяются без рестарта, persistence UserDefaults |
| F-15 | Биомы и генерация карты                       | ❌     | —                                         | Не начато. Требует: Perlin/simplex-генератор, 7 биомов, плавные переходы, зум ×0.15, реинициализация |
| F-16 | Расширенный каталог юнитов (50 шт.)           | ⚠️     | `Data/CityState.swift`, `Data/SnapshotStore.swift`, `Tests/.../LegacyStateMigrationTests.swift` | Каталог расширен до 51 case (50 из F-16 + warehouse legacy): BiomeKind, GridSize, UnitKindInfo, catalog словарь. Миграция legacy state 12→50 готова (TASK-037): SnapshotStore различает «нет файла» и «decode error», 6 тестов backwards-compat, документация в LogFormat.md. Визуальные placeholder'ы (TASK-032), terrain-аффинитет (TASK-033), эволюция в runtime (TASK-034), обновление UnitPlanner (TASK-035) — следующие подзадачи D-16. |
| F-17 | In-app journal (ручной ввод)                  | ✅     | `UI/SidePanelView.swift`, `UI/TaskInputPopupView.swift`, `UI/SceneBridge.swift`, `Game/GameScene.swift`, `UI/ContentView.swift` | Блок ввода задачи в верхней части SidePanelView (TextField + Picker с «Создать новый…» + Cmd+Return); контекстный popup по клику пустой части квартала (diamond hit-test, decay-4 guard); запись через `engine.ingestTaskCompletion(source: "journal")`; валидация (whitespace guard + warning border 1.5 сек, 255 символов); idempotent replay через events.jsonl. TASK-021 ✅ |
| F-18 | Notes/folder watcher (обобщение F-04)         | ❌     | —                                         | Не начато. Требует: Settings UI со списком путей, 4 шаблона парсинга, режимы delete-processed / sidecar-dedup, in-game docs шаблонов |
| F-19 | Git watcher (авто-учёт коммитов)              | ❌     | —                                         | Не начато. Требует: Settings UI со списком репо, periodic `git log --since`, dedup по sha, опции вес-по-diff / категория-по-типу |
| F-20 | Catch-up watcher (5-мин poll)                 | ✅     | `Data/EventSource.swift`, `Data/CatchUpState.swift`, `App/CatchUpScheduler.swift`, `Data/AppPaths.swift`, `Data/AppSettings.swift`, `UI/SettingsView.swift` | Протокол `EventSource` + `MockEventSource`; `CatchUpScheduler` с immediate scan, periodic Timer (DispatchSourceTimer, default 5 мин), skip-if-busy, per-source `last_check_ts` в `catchup-state.json`; Settings: Stepper 3–60 мин, Combine-reschedule; smoke-флаг `CITY_SMOKE_CATCHUP=1`. TASK-020 ✅ |

**Легенда:** ✅ полностью реализована | ⚠️ частично | ❌ отсутствует

**Сходимость:** 11/18 фич закрыто (61%) + 6 частично (F-18, F-19 и др. ❌).

## Что увидит пользователь при запуске

1. `swift build && swift run CityDeveloper` запускает приложение
2. На главном экране появляется полупрозрачное окно с зелёным лугом, удерживается **позади
   всех приложений**, клики проходят к иконкам Finder
3. В правом верхнем углу — статус-бар «🏛», по клику меню:
   - «Открыть город (⌘⌥G)» — переключает explore-режим (окно поднимается, клики
     работают, можно drag-ом таскать камеру и scroll-ом зумить)
   - «Выйти»
4. **⌘⌥G из любого приложения** — переключает behind/explore без accessibility prompt
5. В `~/Library/Application Support/CityDeveloper/tasks.jsonl` уже есть **одна нулевая
   задача** («Заложил основание города…»), которая через 1-2 секунды после старта
   проявится на карте как первый юнит — лачуга в центре. Юнит — реальное изо-здание
   с двумя видимыми гранями, крышей и тенью (а не плоский квадрат)
6. **Клик по юниту в explore-режиме** — рядом появляется пергаментный попап с именем
   проекта, типом юнита (Лачуга / Дом / Вилла / Колодец / ...), стадией и заголовком
   закрытой задачи. Клик в пустоту — скрывает попап
7. Любая дозапись новой строки (вручную или через `./Scripts/add-task.sh "Проект" "Задача"`)
   добавляет юнит в течение 2 сек. Новые проекты получают свои кварталы по спирали
   от центра

## Проблемные участки и риски

### P0 — Критические
_Нет._ Глобальный hotkey был последним P0-блокером и закрыт.

### P1 — Важные
1. **Decay и снэпшоты не реализованы** — без F-09 заброшенные проекты не ветшают; без
   F-12 при тысячах событий старт будет тормозить.
2. **Инспектор без истории** — F-11 пока только tooltip; журнала с фильтром по
   дате/проекту нет. Для долгосрочной ценности (видеть «что я делал в марте») это
   обязательно.
3. **Нет жителей и руин в арте** — F-13 покрывает только статичные здания. Без F-10
   город «мёртвый», без F-09 — не визуализирует заброшенные проекты.

### P2 — Технический долг
1. `CityState.population` — наивная формула, не учитывает реальную игровую логику. Будет
   переписана с появлением F-10.
2. Нет миграций формата events.jsonl. Сейчас формат v1 неявный.
3. F-02: луг — это `SKSpriteNode` 8000×8000 цветом `nileGreen`, а не `SKTileMapNode`.
   Производительность пока не проверена на 500+ юнитах.
4. Tier-визуал в `UnitSprites` ограничен высотой куба (`height = base + tier * 2`).
   Полноценная визуальная подмена при stage-up — TODO в F-08/F-13.

## Технический стек

| Слой                  | Технология                          | Версия (факт)   |
|-----------------------|-------------------------------------|-----------------|
| Язык                  | Swift                               | 6.2.3           |
| UI shell              | SwiftUI + NSHostingView             | macOS 14+ SDK   |
| Рендер города         | SpriteKit (custom isometric)        | macOS 14+ SDK   |
| Управление окном      | AppKit (`NSWindow`, level=desktop)  | системный       |
| Глобальный hotkey     | Carbon HIToolbox (`RegisterEventHotKey`) | системный  |
| File watching         | `DispatchSource.makeFileSystemObjectSource` | системный |
| Персистенс            | JSONL + JSON (file-based)           | —               |
| Сборка                | Swift Package Manager (без Xcode)   | 5.10 tools      |
| Целевая платформа     | macOS                               | 14 Sonoma+      |

## Структура проекта

```
CityDeveloper/
├── Package.swift
├── Sources/CityDeveloper/
│   ├── main.swift
│   ├── App/
│   │   ├── AppDelegate.swift
│   │   ├── CityWindow.swift
│   │   ├── WindowModeManager.swift
│   │   └── GlobalHotkey.swift          ← Carbon-обёртка ⌘⌥G
│   ├── Status/
│   │   └── StatusBarController.swift
│   ├── UI/
│   │   └── ContentView.swift
│   ├── Game/
│   │   ├── GameScene.swift             ← + handleClick / showInspector
│   │   ├── CityEngine.swift
│   │   ├── DistrictPlanner.swift
│   │   ├── UnitPlanner.swift
│   │   ├── StageRules.swift
│   │   ├── InspectorPanel.swift        ← попап по клику
│   │   ├── IsoBuilder.swift            ← cube / pyramidRoof / brickHatch / groundTile / shadow
│   │   └── UnitSprites.swift           ← фабрики на все 12 типов юнитов
│   ├── Data/
│   │   ├── AppPaths.swift
│   │   ├── GameEvent.swift
│   │   ├── EventLog.swift
│   │   ├── ErrorsLog.swift
│   │   ├── CityState.swift             ← + taskTitle / taskTs / taskSource в UnitState
│   │   ├── IngestionState.swift
│   │   ├── TaskRecord.swift
│   │   └── TasksJsonlWatcher.swift
│   └── Theme/
│       └── Palette.swift
├── Scripts/
│   └── add-task.sh          ← тестовый помощник для дозаписи в tasks.jsonl
├── concept/                  ← документация концепта
└── Tasks/                    ← задачи цикла разработки
```

## Runtime-данные

```
~/Library/Application Support/CityDeveloper/
├── tasks.jsonl              ← вход (пишет крон-агент)
├── events.jsonl             ← полный лог событий игры
├── ingestion-state.json     ← offset последней обработанной позиции
├── state.json               ← (TODO F-12) снэпшот состояния
└── errors.log               ← ошибки парсинга
```
