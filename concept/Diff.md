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
| ~~D-02~~ | ~~F-02 Изометрический рендер~~ | ✅ Закрыт: TASK-025 (SKTileMapNode 256×256 isometric + CITY_DEBUG_OVERLAY + CITY_BENCH_UNITS bench-режим). Manual FPS smoke 2026-05-23: **60 FPS на 500 юнитах подтверждено пользователем**. | — | M |

### Важные (P1 — продуктовая логика)

| ID    | Фича (F-NN)                              | Что не так | Done-критерий                                                                | Объём |
|-------|------------------------------------------|------------|------------------------------------------------------------------------------|-------|
| ~~D-11~~ | ~~F-11 Инспектор / журнал~~ | ✅ Закрыт: TASK-007 (боковая панель + журнал) + TASK-016 (floating-окно + overlay-карточка) + TASK-014 (население per-project) + TASK-024 (запись unit_built/stage_up) + TASK-015 (фильтр по типу события). | — | S |
| D-15  | F-15 Биомы и генерация карты             | Шумовая основа + классификатор + рендер + зум ✅ через TASK-026/027/028/029. **Остаток:** реинициализация карты (TASK-030 escalate-too-large, split на 030a/b/c/d в next cycle). | Реинициализация: Settings UI → «новая карта», seed input + миграция кварталов | M |
| D-16  | F-16 Расширенный каталог (50 юнитов)     | UnitKind 51 case + Legacy migration + Placeholder sprites + Terrain affinity + Evolution chains + UnitPlanner biome-aware + Stage-tier visuals + Документация + **Тесты UnitPlanner** ✅ через TASK-031/032/033/034/035/036/037/038/039. **Остаток:** каталог промптов для AI-генерации спрайтов (TASK-040 переписан 2026-05-23 — продакшн-арта НЕ делаем сами, контрибьюторы добавят через PR; blocked-by F-21). | TASK-040 в составе F-21 (docs/asset-prompts.md) | S |
| D-21  | F-21 Open-source готовность              | Не реализовано. Репо локальный, документация русская, нет CONTRIBUTING / LICENSE / docs/, в коммитах могут быть персональные данные. | Public репо на github.com с английской docs/, MIT LICENSE, CONTRIBUTING* + ISSUE/PR-шаблонами, чистый от персональных данных. Контрибьютор-художник за час от первого визита до merged PR. | M |
| ~~D-17~~ | ~~F-17 In-app journal~~ | ✅ Закрыт: TASK-021 (inputSection в SidePanelView + TaskInputPopupView + diamond hit-test в GameScene + SceneBridge.inputRequest + ContentView overlay). | — | M |
| ~~D-18~~ | ~~F-18 Notes/folder watcher~~ | ✅ Закрыт: TASK-022 (NotesWatcher + 4 паттерн-регекса + sidecar в Application Support + DispatchSource live + 5-мин poll fallback через CatchUpScheduler + ingestTaskCompletionIfUnique для dedup; Settings UI с pattern-popover). | — | M |
| ~~D-19~~ | ~~F-19 Git watcher~~ | ✅ Закрыт: TASK-023 (GitWatcher EventSource + GitCLI Process-обёртка + GitRepoSpec Codable + ConventionalCommit парсер + GitWatcherSection Settings UI; persistence в AppSettings.gitRepos; dedup по source "git:<repoId>:<sha>"). | — | M |

### Технический долг

| ID    | Фича (F-NN)                              | Что не так | Done-критерий                                                                | Объём |
|-------|------------------------------------------|------------|------------------------------------------------------------------------------|-------|
| ~~D-23~~ | ~~F-23 Cross-unit эволюция~~ | ✅ Закрыт: TASK-046 (EvolutionGraph с 10 правилами в `Game/EvolutionGraph.swift`; CityEngine.applyEvolutionsIfReady переписан + cascade limit 5). | — | M |
| ~~D-24~~ | ~~F-24 Множитель веса~~ | ✅ Закрыт: TASK-043 (AppSettings.commitWeightMultiplier=0.1 + taskWeightMultiplier=1.0, persistence v3; слайдеры в GitWatcherSection и NotesWatcherSection). | — | M |
| ~~D-25~~ | ~~F-25 District templates + эпохи~~ | ✅ Закрыт: TASK-047/048a/048b/048c/049/050/051 (7 sub-task). Egyptian family полная. Roman/Greek — follow-up в Backlog. | — | L |

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
| D-17  | F-17  | 2026-05-23 | `UI/SidePanelView.swift` (inputSection + trySubmitJournal), `UI/TaskInputPopupView.swift` (новый), `UI/SceneBridge.swift` (InputRequest struct + inputRequest publisher), `Game/GameScene.swift` (diamond hit-test + isPointInDistrictDiamond), `UI/ContentView.swift` (GeometryReader + onReceive + popup overlay) |
| D-19  | F-19  | 2026-05-23 | `Data/GitWatcher/GitCLI.swift`, `Data/GitWatcher/GitRepoSpec.swift`, `Data/GitWatcher/GitWatcher.swift`, `Data/GitWatcher/ConventionalCommit.swift`, `UI/Settings/GitWatcherSection.swift`, `Data/AppSettings.swift`, `UI/SettingsView.swift`, `App/SettingsWindowController.swift`, `App/AppDelegate.swift` |
| D-25  | F-25  | 2026-05-24 | `Game/Templates/DistrictTemplate.swift`, `DistrictTemplateCatalog.swift`, `DistrictTemplatePicker.swift`, `EraRules.swift`, `CityEngine.swift`, `GameScene.swift`, `UnitPlanner.swift`, `AppDelegate.swift`, `UI/SettingsView.swift`; 5 JSON egyptian-family (stage1-5) + 2 era-шаблона (monumental/legacy); 7 sub-task (TASK-047/048a/048b/048c/049/050/051). Egyptian-only первая итерация; Roman/Greek — follow-up Backlog. |

## Не относится к фичам concept (отдельный backlog)
См. `Backlog.md`. Эти пункты НЕ участвуют в подсчёте сходимости diff.

## Рекомендуемый порядок выполнения дальше

С учётом закрытия D-20 (TASK-020):

1. **D-17** (in-app journal, M) — самая приятная UX-часть, быстро виден результат.
   Не зависит ни от F-18/F-19, ни от D-02.
2. **D-18** (notes watcher, M) — заместит F-04 (TasksJsonlWatcher), требует D-20 ✅ (poll
   механизм уже готов). Шаблоны парсинга + опции dedup/удаление.
3. ~~**D-19** (git watcher, M) — закрыт TASK-023.~~
4. **D-02** (SKTileMapNode, M, P0) — переход рендера земли. Pre-req для D-15 биомов.
5. **D-15** (биомы, L) — после D-02. Нужно разбиение в /pm.
6. **D-16** (50 юнитов, L) — после D-15 (нужен `terrain`-аффинитет). Нужно разбиение.

**Сходимость:** 11/18 в diff (11/18 закрыто полностью, F-18 как открытое расхождение).
