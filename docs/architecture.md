# GitCity — Architecture

This document is for contributors who want to understand how GitCity is wired
together internally. For the product vision and feature scope, see
[`concept.md`](concept.md). For the on-disk wire format of events, snapshots and
sidecar files, see [`log-format.md`](log-format.md).

GitCity is a macOS desktop app written in **Swift 6** on top of **SwiftUI** (UI
shell), **SpriteKit** (city render), **AppKit** (window placement), and
**Carbon HIToolbox** (global hotkey). The build is driven by Swift Package
Manager — no Xcode project is required.

---

## 1. High-level diagram

```
            ┌──────────────────────────────────────────┐
            │            External producers            │
            │  (your editors, IDEs, shell, git, etc.)  │
            └──────────────────────────────────────────┘
                              │
                              ▼
   ┌──────────────────────────────────────────────────────────┐
   │                       EventSources                       │
   │                                                          │
   │   TasksJsonlWatcher    NotesWatcher    GitWatcher        │
   │   (~/.../tasks.jsonl)  (markdown dirs) (git log)         │
   │                                                          │
   │       │ live DispatchSource    │ 5-min poll fallback     │
   │       │                        │                         │
   │       └────────────┬───────────┴─── CatchUpScheduler ────┤
   │                    │ (DispatchSourceTimer, main queue)   │
   └────────────────────┼─────────────────────────────────────┘
                        │
                        ▼ engine.ingestTaskCompletion[IfUnique]
   ┌──────────────────────────────────────────────────────────┐
   │                       CityEngine                         │
   │                                                          │
   │   1.  Build GameEvent(.taskCompleted, …)                 │
   │   2.  EventLog.append → events.jsonl  (fsync per line)   │
   │   3.  events.append (in-memory)                          │
   │   4.  apply(event, silent: false) — mutate state         │
   │         ├─ create / restore project                      │
   │         ├─ UnitPlanner.nextUnitKind (seeded RNG)         │
   │         ├─ append .unitBuilt system event                │
   │         ├─ run evolution cascades (.unitEvolved × N)     │
   │         └─ append .stageUp if stage advanced             │
   │   5.  eventsSinceSnapshot++; saveSnapshot() if ≥ 500     │
   └──────────────────────────────────────────────────────────┘
                        │
            ┌───────────┼────────────────────────────────────┐
            ▼           ▼                                    ▼
   ┌────────────────┐ ┌──────────────────────┐  ┌──────────────────────┐
   │ @Published     │ │ SnapshotStore        │  │ Callbacks            │
   │ state, events  │ │ state.json (atomic)  │  │ onUnitBuilt          │
   │                │ │ + tail of events     │  │ onProjectCreated     │
   └────────────────┘ └──────────────────────┘  │ onProjectStageChanged│
            │                                   │ onUnitEvolved        │
            ▼                                   │ onDecayChanged       │
   ┌────────────────────────────┐               │ onProjectRuinsCleared│
   │ SwiftUI ContentView        │               └──────────────────────┘
   │  ├─ SidePanelView          │                          │
   │  ├─ InspectorOverlayCard   │                          ▼
   │  └─ JournalWindow          │              ┌──────────────────────┐
   └────────────────────────────┘              │ GameScene (SpriteKit)│
                                               │  ├─ BiomeRenderer    │
                                               │  ├─ unit nodes       │
                                               │  ├─ CitizenManager   │
                                               │  └─ InspectorPanel   │
                                               └──────────────────────┘
```

The dataflow has one direction: producers write tasks, the engine turns each
task into events and state mutations, and the UI is a read-only projection of
that state plus a handful of callback-driven animations.

---

## 2. Module overview

All source lives under `Sources/CommitPyramid/`. The layering is intentionally
flat — no inter-module Swift Package boundaries — but the directory structure
acts as a logical grouping.

| Package    | Role                                                  | Key types                                                                                                              |
|------------|-------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------|
| `App/`     | NSApplication lifecycle, window placement, hotkeys, scheduler wiring | `AppDelegate`, `CityWindow`, `WindowModeManager`, `GlobalHotkey`, `CatchUpScheduler`, `SettingsWindowController`, `JournalWindowController` |
| `Status/`  | Status-bar menu (the only persistent UI affordance)   | `StatusBarController`                                                                                                  |
| `Data/`    | Event sourcing core, persistence, watchers, settings  | `GameEvent`, `EventLog`, `SnapshotStore`, `StateSnapshot`, `CityState`, `EventSource`, `CatchUpState`, `AppPaths`, `AppSettings`, `TasksJsonlWatcher`, `NotesWatcher/*`, `GitWatcher/*` |
| `Game/`    | Pure game logic + SpriteKit scene graph               | `CityEngine`, `UnitPlanner`, `DistrictPlanner`, `StageRules`, `DecayEngine`, `DeterministicRNG`, `TerrainAffinity`, `GameScene`, `IsoBuilder`, `UnitSprites`, `CitizenManager`, `LifeSimulationManager`, `InspectorPanel`, `BiomeRenderer`, `BiomeMapReader` |
| `World/`   | Procedural noise → biome classification               | `NoiseFieldGenerator`, `NoiseMap`, `BiomeClassifier`, `BiomeKind`, `WorldMapProvider`, `WorldMapStore`, `WorldSeedStore` |
| `UI/`      | SwiftUI views and SpriteKit ↔ SwiftUI bridge          | `ContentView`, `SidePanelView`, `ProjectCard`, `InspectorOverlayCard`, `JournalKindFilter`, `SceneBridge`, `SettingsView`, `TaskInputPopupView`, `Settings/*` |
| `Theme/`   | Centralised colour palette                            | `Palette`                                                                                                              |

`main.swift` boots `NSApplication` and installs `AppDelegate`, which is the
composition root: it constructs the `CityEngine`, `AppSettings`,
`CatchUpScheduler`, the watcher set chosen by user settings, the SpriteKit
scene, and wires their callbacks to one another.

---

## 3. Event sourcing model

GitCity is an event-sourced application end to end. **The append-only event log
is the source of truth; `state` is a memoised fold over it.**

### 3.1 The pipeline for a single task

```
producer writes line ──► EventSource detects change ──► CityEngine.ingestTaskCompletion
   │
   ▼
GameEvent(.taskCompleted)
   │
   ├──► EventLog.append    (events.jsonl, one JSON object per line)
   ├──► events.append      (in-memory @Published mirror, drives UI)
   └──► apply(event, silent: false)
          │
          ├─ mutate `state.projects[...]` / `state.units[...]`
          ├─ if !silent: emit derived system events recursively
          │     • .restore         (project came back from decay 1–3)
          │     • .unitBuilt
          │     • .unitEvolved × N (cascading evolution thresholds)
          │     • .stageUp         (S_old → S_new)
          │     • .ruinsCleared    (district reused over a ruin)
          └─ invoke `on*` callbacks → GameScene animates
```

Each derived system event is appended to `events.jsonl` via the same
`appendSystemEvent` helper. The on-disk log therefore captures the full
chronological story (`task_completed → unit_built → unit_evolved × N →
stage_up?`), making replay deterministic and inspectable with `jq`.

### 3.2 Idempotent `apply`

`CityEngine.apply(_:silent:)` is the only function allowed to mutate `state`.
It is structured so that:

- It accepts any `GameEvent` and produces the same `state` mutation for the
  same input — no clocks, no `Date()`, no random source. All randomness lives
  in pure functions (`UnitPlanner`) that take seeds derived from event content.
- The `silent` flag controls only **side effects** (UI callbacks, recursive
  emission of derived system events). State changes are identical regardless.
  This is the contract that lets replay run with `silent: true` and produce
  byte-identical state to a live run.

### 3.3 De-duplication for external sources

`ingestTaskCompletion` accepts duplicates blindly — it is the entry point for
the legacy `tasks.jsonl` source, where lines are append-only and the watcher
tracks a byte offset.

For richer sources (notes, git) the engine exposes
`ingestTaskCompletionIfUnique(project:title:taskId:source:ts:)`, which checks
`events` for any prior event with the same non-nil `source` key before
appending. This is how `NotesWatcher` and `GitWatcher` keep events.jsonl free
of duplicates after re-scans.

See [`log-format.md`](log-format.md) for the event JSON schema.

---

## 4. Snapshot + tail replay

`StateSnapshot` is a Codable snapshot of `CityState` together with the index
and `UUID` of the event it was taken at (`lastEventIndex`, `lastEventId`,
`snapshotTs`, `version`). It lives in `state.json` and is managed by
`SnapshotStore`.

### 4.1 Boot algorithm (`CityEngine.replayFromLog`)

1. `SnapshotStore.load()` — if absent, fall through to full replay.
2. Read all events from `events.jsonl`.
3. Verify the snapshot is consistent with the log:
   `all[snap.lastEventIndex].id == snap.lastEventId`.
   - If `lastEventIndex == -1` and the log is empty → load snapshot, done.
   - If the consistency check fails → log to `errors.log` and full-replay.
   - If `snap.version != currentVersion` → full-replay.
4. Adopt snapshot state, then apply the tail
   (`eventLog.readSince(index: snap.lastEventIndex)`) with `silent: true`.
5. Update `lastSnapshotEventIndex` to the new end of the log and refresh the
   in-memory `events` mirror.

If anything in steps 1–4 fails (missing file, broken JSON, unknown
`UnitKind.rawValue`, version mismatch), the engine logs the reason and falls
back to a full replay of every event in `events.jsonl` from a fresh `CityState`.

### 4.2 Trigger conditions

A new snapshot is written when any of these hold:

- **Every 500 events**: `eventsSinceSnapshot >= 500` after any append.
- **Daily**: a `DispatchSourceTimer` fires hourly; if the previous snapshot is
  older than 24h *and* there have been events since, `saveSnapshot()` runs.
- **First boot of an existing log**: full-replay path always saves the
  resulting state.
- **Quit / settings change**: the snapshot timer plus the natural 500-event
  cadence cover this; there is no synchronous “save on quit”.

### 4.3 Atomic write

`SnapshotStore.save` uses `Data.write(to:options:.atomic)`, which writes to a
temp file and renames. A torn write therefore leaves the previous `state.json`
intact, and the worst case is one re-replay of the tail.

---

## 5. EventSource protocol

```swift
protocol EventSource: AnyObject {
    var id: String { get }                                  // stable, used as key
    func scan(since: Date) async throws -> Date             // returns new lastCheckTs
}
```

`scan(since:)` must:

- Be idempotent — calling it twice with the same `since` and no new producer
  activity must produce zero new events.
- Push events into `CityEngine` via `ingestTaskCompletionIfUnique`, using a
  stable, content-derived `source` key (e.g. `"notes:<sourceId>:<file>:<line>"`
  or `"git:<repo>:<sha>"`).
- Return the timestamp to persist as the next `since`. Typically `Date()` at
  the start of the scan; the scheduler clamps any future value back to “now”.

### 5.1 Concrete implementations

| Source              | File                                       | What it watches                              |
|---------------------|--------------------------------------------|----------------------------------------------|
| `TasksJsonlWatcher` | `Data/TasksJsonlWatcher.swift`             | `tasks.jsonl` (legacy single-file producer). Uses `DispatchSource.makeFileSystemObjectSource` + byte-offset state in `ingestion-state.json`. |
| `NotesWatcher`      | `Data/NotesWatcher/*`                      | User-configured markdown folders. Four regex patterns (Bullet/Heading/Checkbox/Frontmatter), one sidecar per source in `notes-state/<sourceId>.json`. Live `DispatchSource` + scheduler-driven 5-min poll fallback. |
| `GitWatcher`        | `Data/GitWatcher/*`                        | User-configured git repos. Shells out via `Process` (`GitCLI`, no shell injection), parses Conventional Commits (`feat`/`fix`/…), maps each commit to a `task_completed`. |
| `MockEventSource`   | `Data/EventSource.swift`                   | Smoke testing only (`CITY_SMOKE_CATCHUP=1`). |

### 5.2 CatchUpScheduler as orchestrator

`App/CatchUpScheduler.swift` is an `@MainActor` class that owns:

- A dictionary of registered `EventSource`s keyed by `id`.
- A `DispatchSourceTimer` on the main queue, firing every
  `AppSettings.catchUpIntervalMinutes` (3–60, default 5).
- An `isScanning` flag that drops ticks if the previous async scan is still
  running.
- A `CatchUpState` (loaded from `catchup-state.json`, persisted after each
  successful scan) holding per-source `lastCheckTs`.

`register(_:)` triggers an immediate scan of the new source so users see
results the moment they add a Notes folder or Git repo. The scheduler
subscribes to `AppSettings.$catchUpIntervalMinutes` via Combine and
re-schedules the timer when the user changes the interval — no restart.

If `scan` throws, the scheduler logs the failure to `errors.log` and **does
not** advance `lastCheckTs`, so the next tick retries the same window.

---

## 6. Rendering pipeline

The render layer is split between SpriteKit (the city) and SwiftUI (everything
overlaid on top of it).

### 6.1 SpriteKit (`Game/GameScene.swift`)

```
GameScene (SKScene, scaleMode = .resizeFill)
 ├── cameraNode (SKCameraNode, pan + zoom, clamped to map bounds)
 └── world (SKNode)
      ├── BiomeRenderer
      │     ├── SKTileMapNode (256×256, base biome tiles)
      │     ├── 64 transition tile variants between biomes
      │     └── overlay SKShapeNodes for gradients (sea depth, etc.)
      ├── district markers (one SKNode per project)
      ├── unit nodes (one SKNode per UnitState, keyed by UUID)
      │     └── built by UnitSprites.makeKindStageBuilding(kind:stage:)
      │           using IsoBuilder primitives (cube, pyramidRoof,
      │           brickHatch, shadow) plus PNG-first PlaceholderSpec fallback
      ├── CitizenManager: waypoint random-walk, cap = min(20, stage*2+units/4),
      │     global cap 150, two-phase fade-out, paused when window is behind
      ├── LifeSimulationManager: per-kind ambient effects (smoke, sparks,
      │     flags, ripples, silhouettes), paused with the view
      └── InspectorPanel: click-to-show SpriteKit popup with project / unit /
            task info; click-out hides
```

`unitNodes: [UUID: SKNode]` is the canonical mapping back from `CityState`
to scene graph. Engine callbacks drive scene mutations:

- `onUnitBuilt` → `drawUnit(unit, project:)` — adds a child to `world`.
- `onProjectStageChanged` → `swapStageSprite` (cross-fade ≤ 0.5 s, preserves
  bottom-anchor).
- `onUnitEvolved` → swap the sprite for the new `UnitKind` in place.
- `onProjectRuinsCleared` → 3–5 s clearing animation, then `drawDistrictMarker`
  for the freshly placed project.
- `onDecayChanged` → `DecayVisuals` overlays and (at level 4) ruin sprites.

### 6.2 SwiftUI overlay

`UI/ContentView.swift` is an `NSHostingView`-hosted root containing:

- `SidePanelView` — task ingestion form, project list, journal toggle.
- `InspectorOverlayCard` — trailing centre, mirrors the SpriteKit popup.
- `TaskInputPopupView` — contextual “add task” popup over empty land.
- `SceneBridge` — `ObservableObject` shuttle between SpriteKit (which has the
  click event) and SwiftUI (which renders the inspector card).

The SwiftUI tree observes `CityEngine` directly through `@Published state` and
`@Published events`, so any apply that mutates them re-renders panels and lists
without explicit notification plumbing.

---

## 7. Determinism contract

GitCity guarantees that replaying `events.jsonl` from an empty state yields
byte-identical `CityState` to the live run that produced it. The invariants
that make this work:

1. **`apply` is pure with respect to state.** Given identical input events in
   identical order, it produces identical state. No `Date()`, no `arc4random`,
   no environment reads inside `apply`.
2. **All randomness is seeded from event content.** `UnitPlanner` uses
   `SplitMix64` (a 64-bit splittable PRNG, see `Game/DeterministicRNG.swift`)
   seeded by `fnv1a(combining:)` of the task index, category, and biome
   raw values. The same `(idx, category, biome)` triple always produces the
   same `UnitKind`.
3. **Ordering is preserved.** `EventLog` writes are serialised on a private
   serial dispatch queue, and replay reads the file top-to-bottom. The
   in-memory `events` array is mirror-appended after each write, so UI
   observers see the same order as the disk.
4. **Evolution cascades are bounded and deterministic.** Within a single
   `apply(.taskCompleted)`, `applyEvolutionsIfReady` selects the
   `threshold`-oldest units per group sorted by `(taskTs asc, id asc)`, so
   replay picks the exact same units.
5. **District allocation is replay-safe.** `DistrictPlanner` is a pure spiral
   keyed by `state.nextDistrictIndex`. Ruin re-use (`pickRuinForNewProject`)
   sorts deterministically by `(lastActivityAt asc, unitIds.count desc, id
   asc)` and does **not** advance `nextDistrictIndex`.
6. **`silent: true` is a strict subset of live behaviour.** The replay path
   skips the recursive emission of derived system events because those events
   are already present in the log. The mutation it performs for each event is
   the same one the live run performed.

If you add new event kinds or mutate `apply`, the test bar is: drop
`state.json`, restart the app, and confirm the rebuilt state matches the
state-before-restart.

---

## 8. Data on disk

All runtime files live under
`~/Library/Application Support/CommitPyramid/`. The directory is created on
first launch by `AppPaths.appSupport`.

| File / directory             | Owner                       | Lifecycle / when written                                                                 |
|------------------------------|-----------------------------|------------------------------------------------------------------------------------------|
| `tasks.jsonl`                | external producers          | Append-only by users / scripts / cron. Read by `TasksJsonlWatcher`.                      |
| `ingestion-state.json`       | `TasksJsonlWatcher`         | After each successful scan, persists byte offset into `tasks.jsonl`.                     |
| `events.jsonl`               | `EventLog`                  | Append-only, one JSON object per line, written synchronously per `appendSystemEvent` / `ingestTaskCompletion`. |
| `state.json`                 | `SnapshotStore`             | Atomic overwrite via temp-file + rename. Triggered at 500-event boundaries, 24h timer, or after full replay. |
| `catchup-state.json`         | `CatchUpScheduler` / `CatchUpState` | Pretty-printed JSON, atomically replaced after each successful `EventSource.scan`. Holds per-source `lastCheckTs`. |
| `notes-state/<sourceId>.json`| `NotesWatcher` / `NotesStateStore` | Per-source sidecar with per-file offsets and seen-line hashes.                           |
| `worldmap.json`              | `WorldMapStore`             | Persisted procedural map (seed, noise field, classified biomes). Regenerated only on explicit reset (TASK-030 pending). |
| `errors.log`                 | `ErrorsLog`                 | Append-only diagnostics — every non-fatal error path writes here.                        |

The user-configurable data directory (see `AppSettings.dataDir`) relocates all
of the above; `CityEngine.relocateEventLog(to:)` and
`relocateSnapshotStore(to:)` move active file handles atomically.

The exact JSON schemas of `events.jsonl` and `state.json` are in
[`log-format.md`](log-format.md).

---

## 9. Threading model

GitCity uses a small, deliberately simple set of queues. The default is to do
everything on the main queue and step off it only when a clear reason exists
(file I/O, blocking shells, file-system events).

| Queue / actor                                | Owner / use                                                                                         |
|----------------------------------------------|-----------------------------------------------------------------------------------------------------|
| Main thread (`DispatchQueue.main`)           | All SwiftUI rendering, SpriteKit scene updates, `CityEngine.apply`, `CityEngine.ingest*`, all engine callbacks. |
| `city.eventlog.io` (serial)                  | `EventLog` writes / reads — serialises append + flush so replay never sees a torn line.             |
| `city.notes.io` (serial, utility QoS)        | `NotesWatcher` file I/O and regex scanning; engine ingestion is `DispatchQueue.main.sync`-back.     |
| `DispatchSource.makeFileSystemObjectSource`  | `TasksJsonlWatcher`, `NotesWatcher` — file change events; handlers dispatch onto their owner queue. |
| `DispatchSource.makeTimerSource` (`.main`)   | `CatchUpScheduler` (poll interval), `CityEngine` periodic snapshot timer (hourly), `DecayEngine` decay tick (hourly). |
| `@MainActor` class                           | `CatchUpScheduler` — Swift Concurrency hop ensures registration, scan dispatch, and state save all run on main. |
| `async`/`await` `Task`                       | `EventSource.scan` is `async throws`; the scheduler launches it in a `Task` and awaits completion before saving `lastCheckTs`. |
| Carbon RunLoop                               | `GlobalHotkey` (`RegisterEventHotKey` + `InstallEventHandler`) lives on the main run-loop; no Accessibility permission prompt. |

Rules of thumb when adding code:

- If you need to touch `CityEngine.state`, do it on the main queue.
- If you do file I/O or shell out, do it on a private serial queue and
  marshal results back to main before calling into the engine.
- Never block the main queue on a watcher scan; everything is wired so that
  scans are `async` and the scheduler enforces skip-if-busy.

---

## Further reading

- [`concept.md`](concept.md) — product vision, feature list, design principles.
- [`log-format.md`](log-format.md) — wire format of `events.jsonl`, `state.json`
  and watcher sidecars.
- `concept/UnitCatalog.md` — canonical list of all 50 `UnitKind`s and their
  evolution chains.
- `Sources/CommitPyramid/Game/CityEngine.swift` — the heart of the engine;
  read it top-to-bottom once before contributing.
