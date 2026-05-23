# CityDeveloper — Разрыв между концептом и реальностью

_Обновлено: 2026-05-22 (после концепт-апдейта: добавлены F-17 in-app journal, F-18 notes/folder watcher, F-19 git watcher, F-20 catch-up 5 мин — новая архитектура источников событий, всё внутри приложения)_

## Принцип
Этот файл генерируется механически из `Current.md` по правилу:
**если статус F-NN в current ≠ ✅, появляется D-NN в diff.**
Цель цикла: `diff = 0`.

## Как закрывается пункт
1. Создана задача в `Tasks/` со ссылкой на D-NN.
2. Задача выполнена, `Current.md` обновлён (статус F-NN → ✅).
3. Пункт удалён из этого файла.

## Расхождения по фичам

### Критичные (P0 — фундамент)

| ID    | Фича (F-NN)                              | Что не так | Done-критерий                                                                | Объём |
|-------|------------------------------------------|------------|------------------------------------------------------------------------------|-------|
| D-02  | F-02 Изометрический рендер               | Луг — `SKSpriteNode` 8000×8000, не `SKTileMapNode`; FPS на 500+ юнитах не подтверждён | `SKTileMapNode` isometric, pan/zoom, 60 FPS на 500+ юнитах с реальными тайлами | M  |

### Важные (P1 — продуктовая логика)

| ID    | Фича (F-NN)                              | Что не так | Done-критерий                                                                | Объём |
|-------|------------------------------------------|------------|------------------------------------------------------------------------------|-------|
| ~~D-11~~ | ~~F-11 Инспектор / журнал~~ | ✅ Закрыт: TASK-007 (боковая панель + журнал) + TASK-016 (floating-окно + overlay-карточка) + TASK-014 (население per-project) + TASK-024 (запись unit_built/stage_up) + TASK-015 (фильтр по типу события). | — | S |
| D-15  | F-15 Биомы и генерация карты             | Не реализовано. Карта — плоский луг 8000×8000, биомов нет, зум ограничен | Perlin-генерация ≥256×256, 7 биомов, плавные переходы, зум до ×0.15, реинициализация | L |
| D-16  | F-16 Расширенный каталог (50 юнитов)     | Только 12 типов юнитов, нет terrain-аффинитета, нет эволюции | 50 юнитов, terrain-веса, эволюционные цепочки, обновлённый UnitPlanner | L |
| D-17  | F-17 In-app journal                      | Не реализовано. Ручного ввода задач из приложения нет — события приходят только через `tasks.jsonl` watcher | Глобальный журнал-окно с вводом + dropdown projectId; контекстный клик по кварталу в explore → попап ввода. Запись в `events.jsonl`, source=journal | M |
| D-18  | F-18 Notes/folder watcher                | Не реализовано. Есть только F-04 — single `tasks.jsonl` без шаблонов | Settings — список путей (файл/папка/папка рекурсивно); 4 встроенных шаблона парсинга описаны в in-game docs; режим `delete-processed` ИЛИ `sidecar-dedup`; работа через DispatchSource + 5-мин poll (F-20) | M |
| D-19  | F-19 Git watcher                         | Не реализовано | Settings — список локальных репо (`path`, `projectId` авто из remote, `branch`); periodic `git log --since`; dedup по sha; опции `git fetch`, вес по diff, категория по conventional-commits префиксу | M |

### Технический долг

| ID    | Фича (F-NN)                              | Что не так | Done-критерий                                                                | Объём |
|-------|------------------------------------------|------------|------------------------------------------------------------------------------|-------|
**Объёмы:** S ≤2ч | M ≤1д | L >1д.

## Закрытые расхождения (история)

| ID    | Фича  | Закрыто    | Артефакт                                                            |
|-------|-------|------------|---------------------------------------------------------------------|
| D-08  | F-08  | 2026-05-22 | `Game/UnitSprites.swift` (makeCategoricalBuilding + 20 factory), `Game/CityEngine.swift` (onProjectStageChanged), `Game/GameScene.swift` (handleProjectStageChanged / swapStageSprite) |
| D-07  | F-07  | 2026-05-22 | `Game/UnitPlanner.swift` (categoryPattern + pickKind), `Data/CityState.swift` (UnitCategory) |
| D-06  | F-06  | 2026-05-22 | `Game/CityEngine.swift` (pickRuinForNewProject + атомарная ruins-ветка), `Game/GameScene.swift` (handleRuinsCleared)  |
| D-03  | F-03  | 2026-05-21 | `Data/EventLog.swift`, smoke-тест с replay подтвердил идентичность   |
| D-04  | F-04  | 2026-05-21 | `Data/TasksJsonlWatcher.swift`, live+replay подтверждены             |
| D-01  | F-01  | 2026-05-22 | `App/GlobalHotkey.swift` + регистрация в `AppDelegate`, Carbon `RegisterEventHotKey` ⌘⌥G без accessibility prompt |
| D-13  | F-13  | 2026-05-22 | `Game/CitizenSprites.swift` + `Game/RoadConnector.swift` + `UnitSprites.makeRuin/штабели`; particle-эффекты вынесены в F-05/F-09 |
| D-09  | F-09  | 2026-05-22 | `Game/DecayEngine.swift` + `Game/DecayVisuals.swift`; DecayEngine тикер 1h + catch-up, overlay уровни 1-4, restore-анимация |
| D-05  | F-05  | 2026-05-22 | `Game/LifeSimulationManager.swift`; 11 типов юнитов smoke/flags/ripple/silhouettes, pause/resume, tick 2s |
| D-10  | F-10  | 2026-05-22 | `Game/CitizenManager.swift`; waypoint random walk, target ≥3 ≤20, global cap 150, two-phase fade-out, bounding box ±6 |
| D-12  | F-12  | 2026-05-22 | `Data/StateSnapshot.swift` + `SnapshotStore.swift`; snapshot+tail replay, trigger 500/24h/quit, atomic write |
| D-14  | F-14  | 2026-05-22 | `Data/AppSettings.swift` + `UI/SettingsView.swift`; путь tasks/data/hotkey без рестарта, UserDefaults persistence |
| D-20  | F-20  | 2026-05-22 | `Data/EventSource.swift` + `Data/CatchUpState.swift` + `App/CatchUpScheduler.swift`; протокол EventSource, immediate scan, periodic Timer, per-source lastCheckTs, Settings Stepper 3–60 мин |

## Не относится к фичам concept (отдельный backlog)
См. `Backlog.md`. Эти пункты НЕ участвуют в подсчёте сходимости diff.

## Рекомендуемый порядок выполнения дальше

С учётом закрытия D-20 (TASK-020):

1. **D-17** (in-app journal, M) — самая приятная UX-часть, быстро виден результат.
   Не зависит ни от F-18/F-19, ни от D-02.
2. **D-18** (notes watcher, M) — заместит F-04 (TasksJsonlWatcher), требует D-20 ✅ (poll
   механизм уже готов). Шаблоны парсинга + опции dedup/удаление.
3. **D-19** (git watcher, M) — авто-учёт прироста кода, требует D-20 ✅.
4. **D-02** (SKTileMapNode, M, P0) — переход рендера земли. Pre-req для D-15 биомов.
5. **D-15** (биомы, L) — после D-02. Нужно разбиение в /pm.
6. **D-16** (50 юнитов, L) — после D-15 (нужен `terrain`-аффинитет). Нужно разбиение.

**Сходимость:** 10/18 в diff (10/18 закрыто полностью, F-17..F-19 как открытые расхождения).
