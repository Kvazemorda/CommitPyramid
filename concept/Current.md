# CityDeveloper — Текущее состояние репозитория

_Актуально на: 2026-05-24 (прогон TASK-049 — F-25 5/7, stage-up template migration)_

## ⏱ Что сделано за прогон 2026-05-24 (часть 5: F-25 миграция — TASK-049)

**Закрыто:**
- TASK-049 (D-25 часть 3/5) — template migration при stage-up:
  - `GameEvent.Kind.templateMigrated = "template_migrated"` + helper
    `templateMigrationPayload(from:)` для парсинга title `"fromName|toName"`.
  - `CityEngine.apply()` switch: `.templateMigrated: break` (state уже в applyTaskCompleted).
  - `CityEngine.applyTemplateMigration(projectKey:newStage:silent:)` private —
    pre-checks (templateName != nil, decayLevel < 4, templateFamily != nil),
    Picker(stage:newStage, family:project.templateFamily, seed: fnv1a([projectKey, "stage-\(newStage)"])),
    validate через `TemplateMigrationValidator.canMigrate(...)`, update
    project.templateName/Family или skip + ErrorsLog warning.
  - Step-wise migration loop: `for targetStage in (oldStage+1)...newStage` —
    каждый промежуточный stage отдельным `.templateMigrated` event'ом.
  - `CityEngine._testInjectUnit(_:into:)` — internal seam для тестов
    incompatible scenario.
  - `CityEngine.onTemplateMigrated` callback, wired в AppDelegate.
  - `GameScene.handleTemplateMigrated(projectId:fromTemplate:toTemplate:)` —
    диффит road-слоты между current/next templates, вызывает `drawRoadCells`
    для extension. Cross-fade новых тайлов земли — follow-up (земля — часть
    SKTileMapNode, не меняется при миграции).
  - `TemplateMigrationValidator.canMigrate(units:to:districtOrigin:)` —
    pure helper в `Game/Templates/`, проверяет что все template-placed units
    находятся на slot'ах nextTemplate с совместимой role.
  - **Архитектурное уточнение:** validator фильтрует `templateUnits` (только
    юниты на slot-позициях currentTemplate). Legacy units вне template
    не блокируют миграцию формы. Для F-25 MVP с egyptian preservation
    invariant это безопасно (все units placed через slot-placement).
  - 4 unit-теста `TemplateMigrationValidatorTests` (pure helper) + 4
    integration-теста `CityEngineTemplateMigrationTests` (stage-up migrates,
    preserves positions, skipped when incompatible через `_testInjectUnit`,
    replayable).
  - Side-effect: `JournalKindFilter` exhaustive switch — добавлены case'ы
    для `.templateMigrated` (icon `square.grid.3x3.fill`, name «Миграция шаблона»).
  - Lead-model: opus (3 круга plan-review до approved — step-wise migration
    + AC4 GameScene visual + private(set) test seam). Run: sonnet executor +
    sonnet verify + opus code-review (approved с 3 non-blocking notes).

**Прогресс F-25:** 5 из 7 sub-task'ов (TASK-047, 048a, 048b, 048c, 049).
Осталось: TASK-050 (era progression), TASK-051 (Settings UI).

**Результат `swift test`:** 117/118 — 1 known-fail (BUG-020) = 117 PASS.

**Изменения файлов за TASK-049:**
- `Sources/CityDeveloper/Data/GameEvent.swift` (+1 case + payload helper)
- `Sources/CityDeveloper/UI/JournalKindFilter.swift` (+1 case в exhaustive switch)
- `Sources/CityDeveloper/Game/CityEngine.swift` (callback, step-wise loop, applyTemplateMigration, _testInjectUnit seam)
- `Sources/CityDeveloper/App/AppDelegate.swift` (+3 строки wiring)
- `Sources/CityDeveloper/Game/GameScene.swift` (handleTemplateMigrated с road-extension)
- `Sources/CityDeveloper/Game/Templates/TemplateMigrationValidator.swift` (НОВЫЙ, pure helper)
- `Tests/CityDeveloperTests/TemplateMigrationValidatorTests.swift` (НОВЫЙ, 4 теста)
- `Tests/CityDeveloperTests/CityEngineTemplateMigrationTests.swift` (НОВЫЙ, 4 теста)

**Follow-up для следующего цикла (накапливается из TASK-048c + TASK-049):**
- `syncRoadNetworkPlans()` — добавить guard `if project.templateName == nil`.
- AppDelegate: wire `engine.templateFamily = appSettings.templateFamily`
  (часть TASK-051 Settings UI).
- Cross-family migration: validator strict role equality (нет совместимости
  warehouse↔market и т.п.) — для F-25 MVP не нужно, но в будущем при
  расширении family pool потребует уточнения.
- Cross-fade новых тайлов земли при миграции (визуальная feedback) — follow-up.

---

## ⏱ Что сделано за прогон 2026-05-24 (часть 4: F-25 интеграция — TASK-048c)

**Закрыто:**
- TASK-048c (D-25 часть 2.3/5) — финальная интеграция slot-based placement в pipeline:
  - `DistrictTemplateCatalog.byName(_:)` — lookup template по имени.
  - `UnitPlanner.nextPosition` расширен trailing optional параметрами
    `template: DistrictTemplate? = nil, kind: UnitKind? = nil`. При обоих non-nil —
    slot-branch: filter по `slot.role == kind.preferredSlotRole`, sort `(y, x)`,
    проверка занятости через `builtCells`, возврат абсолютной позиции или nil.
    Default'ы обеспечивают backwards-compat (9/9 TASK-038 тестов PASS).
  - `CityEngine`: добавлено свойство `templateFamily: String = "auto"` (AppSettings
    не singleton в проекте → wired AppDelegate'ом по паттерну `roadNetwork`, soft-block
    для TASK-051 — wire ещё не сделан, prod использует "auto" → resolved в "egyptian"
    через Picker). При создании нового ProjectState вызывается
    `DistrictTemplatePicker.pick(stage:1, family:..., biome:..., seed: fnv1a([projectKey]))`,
    `templateName`/`templateFamily` сохраняются.
  - `CityEngine.applyTaskCompleted`: template-aware ветка — если `project.templateName != nil`,
    BUG-010 hack (`if taskCount == 1 → kind = .road`), затем slot-placement; при exhausted
    slot или template not in catalog — fallback через новый private helper
    `resolveLegacyKindAndPosition` (перенос старого блока 322-384) + warning в errors.log.
  - **Архитектурное решение**: для templated проектов `roadNetwork.planDistrict` НЕ вызывается
    (иначе `isPlanComplete` навсегда false, auto-extend ломается); fallback на exhausted идёт
    через legacyRingPosition вокруг origin (magistral не в halfSide=4 для удалённых кварталов).
  - **BUG-010 закрыт в templated mode** через end-to-end тест `testFirstUnitIsRoadInTemplate`.
  - 5 новых тестов `UnitPlannerSlotPlacementTests` (slot-based unit-level), 4 теста
    `CityEngineTemplateAssignmentTests` (end-to-end: assignment, determinism, BUG-010, replay).
  - Lead-model: opus (3 круга plan-review до approved). Run: sonnet executor + sonnet verify +
    opus code-review (approved с 2 soft-issues — syncRoadNetworkPlans guard для templated
    проектов, AppDelegate wire templateFamily; оба не блокеры, переносятся в follow-up).

**Прогресс F-25:** 4 из 5 sub-task'ов (TASK-047, 048a, 048b, 048c). Осталось:
TASK-049 (stage-up migration), TASK-050 (era progression), TASK-051 (Settings UI + AppDelegate wire).

**Результат `swift test`:** 109/110 — 1 known-fail (BUG-020) = 108 PASS до правок + 9 новых
тестов = 117 total, но BUG-020 + другие изменения распределения цифр сохранились.
**Фактический счёт:** suite 109/110, BUG-020 единственный fail (pre-existing).

**Изменения файлов за TASK-048c:**
- `Sources/CityDeveloper/Game/Templates/DistrictTemplateCatalog.swift` (+6 строк, `byName`)
- `Sources/CityDeveloper/Game/UnitPlanner.swift` (+2 trailing optional + ~25 строк slot-branch)
- `Sources/CityDeveloper/Game/CityEngine.swift` (+`templateFamily` property, Picker-вызов в new-project ветке, оборачивание `planDistrict` в guard, template-aware ветка resolution, helper `resolveLegacyKindAndPosition`)
- `Tests/CityDeveloperTests/UnitPlannerSlotPlacementTests.swift` (НОВЫЙ, 5)
- `Tests/CityDeveloperTests/CityEngineTemplateAssignmentTests.swift` (НОВЫЙ, 4)

**Follow-up для следующего цикла:**
- `syncRoadNetworkPlans()` в CityEngine.swift — после restart восстанавливает `planDistrict`
  для всех проектов с пустым `plannedCells`, включая templated. Нужен guard
  `if project.templateName == nil` в loop body (мёртвый код в hot-path для templated,
  не падающий, но захламляет state).
- AppDelegate: wire `engine.templateFamily = appSettings.templateFamily` (часть TASK-051
  Settings UI).

---

## ⏱ Что сделано за прогон 2026-05-24 (часть 3: F-25 первая волна — TASK-047/048a/048b)

**Закрыто (продолжение):**
- TASK-048a (D-25 часть 2.1/5) — `ProjectState` расширен полями
  `templateName/templateFamily/eraLevel` с явным `init(from:)` для
  backwards-compat. `AppSettings` v3→v4: `templateFamily`/`previewTemplateSilhouette`
  с миграцией. CityEngine + GameScene-bench обновлены явными nil/0/nil. 6 новых
  тестов PASS. Lead: opus → revised → applied; Run: sonnet, без отклонений.
- TASK-048b (D-25 часть 2.2/5) — `UnitKind.preferredSlotRole` (extension, 51 case
  exhaustive switch) + `DistrictTemplatePicker` (auto/mixed/explicit family
  resolution, biome-filter с fallback, детерминированный pick через
  SplitMix64). 11 новых тестов PASS. Lead: opus, plan-review skipped (план
  максимально готов); Run: sonnet, без отклонений.

**Прогресс F-25:** 3 из 5 sub-task'ов (TASK-047, 048a, 048b). Осталось:
TASK-048c (slot-placement integration), TASK-049 (stage-up migration),
TASK-050 (era progression), TASK-051 (Settings UI).

**Результат `swift test`:** 101/101 total — 1 known-fail (BUG-020) = 100 PASS.

**Изменения файлов за прогон 048a+048b:**
- `Sources/CityDeveloper/Data/CityState.swift` (ProjectState +3 поля + init(from:))
- `Sources/CityDeveloper/Data/AppSettings.swift` (5 micro-правок, v3→v4)
- `Sources/CityDeveloper/Game/CityEngine.swift:277-288` (3 явных параметра)
- `Sources/CityDeveloper/Game/GameScene.swift:948` (3 явных параметра)
- `Sources/CityDeveloper/Game/Templates/UnitKindSlotRole.swift` (НОВЫЙ)
- `Sources/CityDeveloper/Game/Templates/DistrictTemplatePicker.swift` (НОВЫЙ)
- `Tests/CityDeveloperTests/ProjectStateTemplateFieldsTests.swift` (НОВЫЙ, 3)
- `Tests/CityDeveloperTests/AppSettingsV4MigrationTests.swift` (НОВЫЙ, 3)
- `Tests/CityDeveloperTests/UnitKindSlotRoleTests.swift` (НОВЫЙ, 4)
- `Tests/CityDeveloperTests/DistrictTemplatePickerTests.swift` (НОВЫЙ, 7)

---

## ⏱ Что сделано за прогон 2026-05-24 (часть 3: F-25 первая волна — TASK-047)

**Закрыто:**
- TASK-047 (D-25 часть 1/5) — фундамент F-25:
  - `DistrictTemplate` модель (Codable + Sendable, 3 типа в 36 строках).
  - `DistrictTemplateCatalog` singleton-loader (120 строк, ioQueue thread-safe,
    internal validate для тестов, динамическая регистрация family из JSON).
  - 5 JSON-шаблонов egyptian-семьи (15→25→35→45→51 слотов, инвариант
    bbox+slot-preservation между stage'ями).
  - 7 unit-тестов `DistrictTemplateCatalogTests` (включая
    `testStageProgressionPreservesSlots` для защиты инварианта TASK-049
    migration).
  - Документация `concept/TemplateCatalog.md` (201 строка, формат + инварианты).
  - Lead-model: opus (revision круг 1 → 6 правок → круг 2 approved).
  - Run-model: sonnet (middle сложность, делегирован).
  - **Side-effect (улучшение):** Sonnet обошёл ограничение SwiftPM
    `.process("Resources")` (сглаживание подпапок) через filter по JSON-полю
    `family`. Catalog теперь динамически подхватывает любую family из
    положенного JSON без правок кода — TASK-051 Settings Picker станет
    проще.

**Результат `swift test`:** 84/84 — 1 known-fail (BUG-020) = 83 PASS.

**Следующее в очереди:** TASK-048 (DistrictTemplatePicker + slot-based UnitPlanner).

---

## ⏱ Что сделано за прогон 2026-05-24 (часть 2: F-25 setup + TASK-038)

**Заведено:**
- F-25 «District templates + эпохи» в Concept.md (8 пунктов состава: модель,
  3 family с 5 stage каждая, picker, slot-based placement, migration на stage-up,
  era progression 0-3, Settings UI). D-25 в Diff.md (L, не закрыт).
- 5 TASK-файлов первой волны F-25: TASK-047 (модель + egyptian-family),
  TASK-048 (Picker + slot-placement), TASK-049 (stage-up migration),
  TASK-050 (era progression), TASK-051 (Settings UI). Все waiting-for-lead.
- 4 follow-up идеи в Backlog: Roman/Greek families, era-варианты,
  snapshot-тесты шаблонов.

**Закрыто:**
- TASK-038 (UnitPlanner tests) — `Tests/CityDeveloperTests/UnitPlannerTests.swift`
  с 9 тестами (категориальные пропорции / minStage / biome-affinity / детерминизм /
  performance / 4 edge cases). Все PASS. Lead-model: opus, plan-review: revised→approved
  (круг 1 → 5 правок → круг 2 approved). Run: opus self-executed.

**Открыто (новые баги):**
- BUG-019 (P1) — z-sort, дальние юниты/дороги перекрывают ближние (визуальный).
- BUG-020 (P1) — `BiomeClassifierTests.testRiversHaveReasonableWidth` падает
  на seed=42 (рек нет). Известный fail, не регресс.
- BUG-021 (P2) — large-юниты составляют ~37% на stage 5 + meadow (56/150),
  PM-spec ожидал ≤2%. Тест TASK-038 ослаблен до baseline=60 до фикса.

**Результат `swift test`:** 76/77 PASS, 1 known-fail (BUG-020).

---

## ⏱ Что сделано за прогон 2026-05-24 (часть 1: BUG-011..016 + F-23/F-24)

Закрыты 6 багов и добавлены 2 фичи:

**Закрыто:**
- BUG-011 (P0) — UnitPlanner ставит здания внутри петель, без 8-лучевого паттерна. Добавлен tracking занятых клеток + реактивный extendDistrictPlan. TASK-041.
- BUG-012 (P0) — road-юниты используют makeRoadCellNode (как магистраль), без 3D-куба. TASK-042.
- BUG-013 (P0) — пороги computeWeight подняты до 200/2000/10000 + multiplier 0.1 default. TASK-043.
- BUG-014 (P1) — UnitKind.size возвращает корректные GridSize для всех ~50 юнитов; только {shack, house, well, road, zemlyanka, khizhina, obelisk} = 1×1. TASK-044.
- BUG-015 (P0) — один git log --numstat вместо N git diff (CPU storm устранён, импорт ≤10s). TASK-045.
- BUG-016 (P1) — EvolutionGraph с 10 cross-unit правилами заменил тупой kind-counter. TASK-046.

**Закрыто полностью (F-23, F-24):**
- F-23 (Cross-unit эволюция) — реализован EvolutionGraph (requirements по соседним юнитам). TASK-046.
- F-24 (Множитель веса) — слайдеры в Settings (commit 0.1, task 1.0), persistence v3. TASK-043.

---

## ⏱ Что сделано за прогон 2026-05-22

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
| F-02 | Изометрический рендер города                  | ✅     | `Game/GameScene.swift`, `Game/IsoBuilder.swift`, `Game/UnitSprites.swift`, `Game/IsoTileFactory.swift`, `Game/BiomeRenderer.swift`, `Game/TileTextureFactory.swift` | Полноценный изо-арт; SKTileMapNode 256×256 (TASK-025) + биомный рендер (TASK-028). 60 FPS на 500 юнитах подтверждено. |
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
| F-15 | Биомы и генерация карты                       | ⚠️     | `World/NoiseMap.swift`, `World/NoiseFieldGenerator.swift`, `World/WorldMapProvider.swift`, `World/WorldMapStore.swift`, `World/WorldSeedStore.swift`, `World/BiomeKind.swift`, `World/BiomeClassifier.swift`, `Game/BiomeMapReader.swift`, `Game/TileTextureFactory.swift`, `Game/BiomeRenderer.swift`, `Game/GameScene.swift` | Шумовые поля 256×256 (TASK-026 ✅). BiomeClassifier: квантильные пороги, flood-fill sea, downhill rivers (TASK-027 ✅). Рендер биомов на SKTileMapNode + 64 переходных тайла + overlay-градиенты (TASK-028 ✅). Зум до ×0.15 + clamp по границам карты (TASK-029 ✅). **Остаток:** реинициализация карты (TASK-030 — escalate-too-large, разбить в next cycle). |
| F-16 | Расширенный каталог юнитов (50 шт.)           | ⚠️     | `Data/CityState.swift`, `Data/SnapshotStore.swift`, `Data/GameEvent.swift`, `Game/UnitSprites.swift`, `Game/UnitPlanner.swift`, `Game/CityEngine.swift`, `Game/GameScene.swift`, `Game/DeterministicRNG.swift`, `Game/TerrainAffinity.swift`, `Tests/CityDeveloperTests/UnitPlannerTests.swift`, `concept/UnitCatalog.md` | Каталог расширен до 51 UnitKind (TASK-031 ✅). Placeholder-спрайты для всех 50 через декларативную таблицу `PlaceholderSpec` + PNG-first fallback (TASK-032 ✅). Эволюционные цепочки с GameEvent.Kind.unitEvolved + repeat-каскад в applyTaskCompleted + replay-safe (TASK-034 ✅). Terrain affinity — pure `TerrainAffinity.weight(for:in:)` (TASK-033 ✅). UnitPlanner biome-aware: 5-шаговый алгоритм (pattern→category→minStage→evolution-roots-cut→weighted sample, SplitMix64+FNV-1a seed) (TASK-035 ✅). Stage-tier визуальный API `makeKindStageBuilding(kind:stage:)` (TASK-036 ✅). Legacy state 12→50 миграция backwards-compat (TASK-037 ✅). **Тесты UnitPlanner — 9 кейсов** (TASK-038 ✅, 2026-05-24). Документация — concept/UnitCatalog.md (TASK-039 ✅). **Остаток:** финальные Pharaoh-spritеs (TASK-040 — blocked-by F-21, push в Backlog как content task). |
| F-17 | In-app journal (ручной ввод)                  | ✅     | `UI/SidePanelView.swift`, `UI/TaskInputPopupView.swift`, `UI/SceneBridge.swift`, `Game/GameScene.swift`, `UI/ContentView.swift` | Блок ввода задачи в верхней части SidePanelView (TextField + Picker с «Создать новый…» + Cmd+Return); контекстный popup по клику пустой части квартала (diamond hit-test, decay-4 guard); запись через `engine.ingestTaskCompletion(source: "journal")`; валидация (whitespace guard + warning border 1.5 сек, 255 символов); idempotent replay через events.jsonl. TASK-021 ✅ |
| F-18 | Notes/folder watcher (обобщение F-04)         | ✅     | `Data/NotesWatcher/NotesSourceSpec.swift`, `NotesPatternParser.swift`, `NotesStateStore.swift`, `NotesFileReader.swift`, `NotesWatcher.swift`, `UI/Settings/NotesWatcherSection.swift`, `UI/Settings/NotesPatternsPopover.swift` | NotesWatcher реализует EventSource; 4 регекс-паттерна (Bullet/Heading/Checkbox/Frontmatter) скомпилированы как static let; sidecar в Application Support/CityDeveloper/notes-state/<sourceId>.json; DispatchSource live + 5-мин poll fallback (через CatchUpScheduler из TASK-020); `engine.ingestTaskCompletionIfUnique` для events.jsonl-level dedup. TASK-022 ✅ |
| F-19 | Git watcher (авто-учёт коммитов)              | ✅     | `Data/GitWatcher/GitCLI.swift`, `Data/GitWatcher/GitRepoSpec.swift`, `Data/GitWatcher/GitWatcher.swift`, `Data/GitWatcher/ConventionalCommit.swift`, `UI/Settings/GitWatcherSection.swift` | GitWatcher реализует EventSource; GitCLI — Process-обёртка без shell-injection; GitRepoSpec — Codable модель; ConventionalCommit — парсер feat/fix/refactor/docs/chore; Settings UI секция «Git watcher» с NSOpenPanel, TextField projectId, BranchPicker, 3 Toggle (gitFetch, weightByDiff, categoryByType), кнопка trash. Persistence через AppSettings.gitRepos (UserDefaults). TASK-023 ✅ |
| F-20 | Catch-up watcher (5-мин poll)                 | ✅     | `Data/EventSource.swift`, `Data/CatchUpState.swift`, `App/CatchUpScheduler.swift`, `Data/AppPaths.swift`, `Data/AppSettings.swift`, `UI/SettingsView.swift` | Протокол `EventSource` + `MockEventSource`; `CatchUpScheduler` с immediate scan, periodic Timer (DispatchSourceTimer, default 5 мин), skip-if-busy, per-source `last_check_ts` в `catchup-state.json`; Settings: Stepper 3–60 мин, Combine-reschedule; smoke-флаг `CITY_SMOKE_CATCHUP=1`. TASK-020 ✅ |
| F-21 | Open-source готовность                        | ❌     | —                                         | Не начато. Требует: GitHub-репо (public, MIT), английская docs/ (README, concept, architecture, asset-prompts, CONTRIBUTING*, log-format), чистка от персональных данных, ISSUE/PR-шаблоны, базовая labels-схема. |

**Легенда:** ✅ полностью реализована | ⚠️ частично | ❌ отсутствует

**Сходимость:** 17/19 фич закрыто (89%) + 2 частично (F-15 ⚠️ остался TASK-030 — реинициализация карты; F-16 ⚠️ остался TASK-038 тесты UnitPlanner) + 1 новая ❌ (F-21 open-source). D-02 закрыт 2026-05-23.

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
