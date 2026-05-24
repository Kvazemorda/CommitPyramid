# TASK-030b: MapReinit orchestrator — atomic пересборка карты + replayFromLog

## Связь
- **F-15** из Concept.md (реинициализация)
- **D-15** из Diff.md (часть 2/3 финального шага)
- **Родитель:** TASK-030 (split-into-030a-b-c, lead-разбор 2026-05-23)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-24_

### Что хотим

Атомарный реинит-пайплайн: после клика «Сбросить карту» (TASK-030a уже сохранил
новый seed) — движок останавливает симуляцию, удаляет snapshot, перезапускает
`replayFromLog()` от пустого state, в результате чего кварталы пересобираются на
новом рельефе. Без записи в `events.jsonl`, без миграции snapshot формата. Это
**ядро F-15 финала** — обеспечивает контракт «реинициализация работает».

### Пользовательский сценарий

1. Игрок в TASK-030a кликает «Сбросить карту» с seed=42 и confirm.
2. AppDelegate / SceneBridge получает уведомление `mapSeedChanged`.
3. Новый `MapReinitCoordinator` исполняет:
   a. `engine.pauseSimulation()` (decay timer стоп).
   b. `WorldMapStore.regenerate(seed: 42)` — пересоздаёт noise + biome map +
      `worldmap.json` атомарно (через tmp + rename).
   c. `SnapshotStore.delete()` — удаляет `state.json`.
   d. `engine.state = CityState.empty()` — сбрасывает in-memory state.
   e. `engine.replayFromLog()` — reapply все `events.jsonl` от нуля. Каждый
      `task_completed` идёт через `applyTaskCompleted(silent: true)`, который в
      ветке `isNewProject` спросит `DistrictPlanner.allocateNextOrigin` на новой
      карте → получит новый `districtOrigin` (детерминированно от seed + sorted projectIds).
   f. `engine.resumeSimulation()`.
   g. `GameScene.handleMapReinitComplete()` — teardown старый tile-rendering,
      перезагрузить biome-tiles, переразместить markers/units по новым projectOrigins.
4. Если любой шаг (a-f) упал — coordinator откатывает: restore старый snapshot
   (если он был временно сохранён в `.bak`), restore старый seed, errors.log
   warning, user-alert «Не удалось пересобрать карту, восстановлено
   прежнее состояние».
5. Двойной reinit во время выполнения — игнорируется (boolean flag `isReiniting`).

### Acceptance criteria

- [ ] Новый `Sources/CityDeveloper/Game/MapReinitCoordinator.swift` —
      `@MainActor class` с методом `func reinit(newSeed: UInt64?) async throws`.
      `newSeed: nil` → генерится случайный.
- [ ] Coordinator делает шаги a-g по порядку **атомарно**: при ошибке на шаге
      ≥ d делается rollback `.bak`-снапшота.
- [ ] До удаления snapshot: `SnapshotStore.save(state, to: .bak)` —
      бекап существующего snapshot во временный `state.json.bak`. После
      успешного reinit `.bak` удаляется. При failure → `.bak` восстанавливается.
- [ ] `WorldMapStore.regenerate(seed:)` — atomic write через tmp-file +
      rename (existing pattern). При write failure — throw.
- [ ] `CityEngine.pauseSimulation()` / `resumeSimulation()` — публичные
      методы. `pause` останавливает DecayEngine timer и блокирует
      `ingestTaskCompletion*` (возвращает ошибку «engine paused»). `resume`
      возобновляет.
- [ ] `CityEngine.replayFromLog()` (если уже есть — расширить; если нет —
      добавить) — переиспользует существующий `applyTaskCompleted(silent: true)`
      путь от `state = CityState.empty()` для всех записей `events.jsonl`.
- [ ] `GameScene.handleMapReinitComplete(newSeed:)` callback — teardown
      tile-map + districtMarkers + unitNodes, rebuild по новому биому, reposition
      всё по `engine.state.projects` (которое уже на новых origin после replay).
- [ ] `AppDelegate` wire: `engine.onMapReinitRequested = { [weak self] seed in
      Task { await coordinator.reinit(newSeed: seed) } }`.
- [ ] Boolean guard `MapReinitCoordinator.isReiniting` — повторный вызов в
      процессе reinit → throw `MapReinitError.alreadyInProgress`, user-alert.
- [ ] Тест `MapReinitCoordinatorTests`:
      - `testReinitChangesSeedAndPersists`,
      - `testReinitDeletesSnapshot`,
      - `testReinitTriggersReplayFromLog` (mock engine),
      - `testReinitWithFailureRollsBackSnapshot` (inject failure в WorldMapStore.regenerate),
      - `testDoubleReinitIsRejected`.

### Что НЕ делаем (границы скоупа)

- НЕ меняем формат `events.jsonl` (нет `map_regenerated` event — PM-решение).
- НЕ меняем формат `state.json` (snapshot v не bump'ается).
- НЕ реализуем умное размещение по биомам — это TASK-030c.
  В 030b кварталы получают origin через **существующий** `DistrictPlanner.allocateNextOrigin`
  (спиральный, без аффинитета). 030c заменит на biome-aware.
- НЕ перерисовываем здания процедурно — после replay sprite-генерация
  переиспользует существующий код F-08 / F-13.

### Edge cases

- [ ] `events.jsonl` пустой → `state` остаётся empty, GameScene показывает
      просто новую карту без кварталов. Корректно.
- [ ] Во время reinit пользователь жмёт ⌘Q → coordinator завершает текущий
      этап, потом завершает приложение. Atomicity: `.bak` остаётся (при
      следующем старте — fallback на `.bak` если основной `state.json` битый).
- [ ] `worldmap.json` write failure (disk full / permissions) → throw до
      удаления snapshot. Старая карта остаётся активной, errors.log warning.
- [ ] `replayFromLog()` упал на повреждённой строке → лог записывается
      в errors.log, replay продолжается до конца, кварталы по уцелевшим
      `task_completed` записям. Это уже текущее поведение, не меняем.
- [ ] `DistrictPlanner` не смог найти origin (карта полностью «непригодна»)
      → fallback на центр карты + warning. Не должно блокировать reinit.

### Зависимости

- **Blocked-by:** TASK-030a (AppSettings.mapSeed готов).
- **Soft-blocks:** TASK-030c (biome-aware placement встаёт после оркестратора).

### Дизайн

UI part — user-alert при failure через NSAlert (по аналогии с существующими
ошибками в Settings). Прогресс-индикатор не нужен (reinit ожидается
< 2 сек на современной машине).

### Done-критерий

_Часть F-15 Done-критерия:_ «Кнопка "Сбросить карту" + подтверждение → новая
генерация, кварталы переразмещаются». 030b закрывает функциональную половину
(пересборка + replay + reposition). 030c добавит biome-aware размещение.

---

## 🛠 Технический разбор от тимлида

_Статус: [ ] нужен разбор_

> Заполняется командой `/lead 030b`.

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_ (определит лид)
_Объём: M_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Smoke: добавить 3 проекта через add-task.sh → reinit с новым seed →
      все 3 квартала видны на новой карте на новых origin → перезапуск
      приложения сохраняет результат.

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Тесты не сломаны (включая MapReinitCoordinatorTests новые)
- [ ] events.jsonl формат не меняется (regression-check через diff формата)
- [ ] state.json формат не меняется

#### Обновление документации
- [ ] `Current.md`: F-15 ⚠️ → reinit-pipeline ✅ (остался biome-affinity placement)
- [ ] `Diff.md`: D-15 — отметить «оркестратор ✅»

---

## Статус

`[x] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[ ] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-24
- Spec-review: derived-from-split (TASK-030 lead-analysis 2026-05-23)
- Blocked-by: TASK-030a
- Готова к работе: —
- Завершена: —
- Коммит: —
