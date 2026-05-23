# CommitPyramid — Application Concept

> This is the English version of the product concept used by external contributors. The Russian source is `concept/Concept.md`.

## Core principle
This file is a **frozen reference**. It is not edited automatically during development.
New ideas go into `Backlog.md`, not here. Any edit to `Concept.md` is a deliberate
decision that shifts the goal of the current cycle.

## What the product is

CommitPyramid is an interactive isometric ancient city that lives on the macOS desktop and
grows as the user closes real-world tasks in their daily work.

The data source is **a single external log file `tasks.jsonl`**, populated by the user's
external cron agent (out of scope for the game). The game watches this file and turns
each new completed-task entry into a unit on the map: a house, a well, a warehouse, a
workshop, a market. All tasks are equal — a unit has no "weight". The specific unit
type is chosen by the game according to internal district-balance rules (one well per N
residential buildings, one workshop per M, and so on).

A real-world project becomes a district. The speed and growth stage of a district depend
on the **number of completed tasks**, the **age of the project** (from first task to
last) and the **activity level** (event tempo). From wasteland through shacks to stone
construction, a developed quarter and luxury. If a project sees no events for a long time
(14 days by default), the district decays and eventually turns into ruins. Ruins remain
on the map forever, but when a **new** project appears, it claims the ruined zone first
and builds new buildings on top of it.

Inside a living district there is a **light visual simulation of life**: warehouses
accumulate piles of goods, workshops smoke and clang, the market trades, citizens walk
along the roads. It is an illusion of activity, not a real economy — there are no supply
chains or resource shortages.

The city lives **on the desktop** as a normal stable window held behind all other
windows (via `NSWindow.collectionBehavior`, without the `kCGDesktopWindowLevel` hack).
A hotkey raises the window into navigation mode — you can pan, zoom, click on buildings
and see which task each one was born from. A full log of all events is stored append-only —
the user can always answer the question "what did this city grow from".

The visual style is a simplified Egyptian isometric in the spirit of Pharaoh: sand and
ochre tones, an isometric grid, simple buildings, walking citizens.

## Business model

| Source of value                       | Mechanic                                                                                                  |
|---------------------------------------|-----------------------------------------------------------------------------------------------------------|
| Personal productivity gamification    | Closed tasks materialize as visible progress — motivation to see things through                           |
| Long-term artifact of your work       | Full log + reproducible city state = a "portfolio" of real activity over years                            |
| Feedback on abandoned projects        | The decay mechanic makes visible the projects you haven't come back to in a long time                     |

The project is not intended for commercial sale. It is a personal tool; an open-source
release for users with a similar workflow is possible in the future.

## Contract with the outside world

The game accepts **a single file** — `tasks.jsonl` (path configured in F-13).
Format of each line:

```json
{"ts": "2026-05-21T10:30:00Z", "project": "my-website", "title": "Approved the spec"}
```

- **`ts`** — scan-time timestamp (the moment the cron agent saw `[x]` and wrote the line)
- **`project`** — project name (human-readable; the unique name is the identifier)
- **`title`** — task text
- Optional fields (for future extensions): `task_id`, `source` — the game stores them
  but does not act on them

No task types, no weights, no categories. A unit is a unit.

The full specification of the format and watcher behavior lives in `LogFormat.md`.

## Features (reference set)

### F-01: Stable "always behind" window + explore mode
**What:** The app launches as a fullscreen window held **behind all other windows**
(via `NSWindow.collectionBehavior = .stationary + .canJoinAllSpaces`, without the
`kCGDesktopWindowLevel` hack). The window is click-through (`ignoresMouseEvents = true`)
and does not take focus. A hotkey (⌘⌥G by default, configurable) raises the window to
the foreground and makes it interactive; pressing it again returns the window to the
background.
**Why:** The city should live behind the working environment without distraction, but
should be explorable on demand. A stable window is more reliable than wallpaper-level
hacks.
**Done criterion:** The city is visible above the wallpaper and behind desktop icons;
clicks pass through to icons and other windows, not to the city. ⌘⌥G raises the window,
mouse works with the city (camera, building clicks). Pressing the hotkey again sends it
back. Mode switching is instant (<200ms). The window stays in the background when other
apps open or close.

### F-02: Isometric city renderer
**What:** SpriteKit + `SKTileMapNode` with `tileSetType = .isometric`. Camera with
pan/zoom. Grid at least 128×128 tiles, expandable as the city grows.
**Why:** Baseline visual layer — nothing can be shown without it.
**Done criterion:** The map shows an isometric grid that can be panned (drag) and zoomed
(scroll/pinch). FPS stays above 60 in explore mode with 500+ units on a typical Mac
(M-series). Tiles sort correctly by depth.

### F-03: Event sourcing (append-only log + replay)
**What:** All changes to city state are events in `events.jsonl` that are never
rewritten, only appended. Event sources: (a) new lines from `tasks.jsonl` →
`TaskCompleted`, (b) game system ticks → `DecayTick`, `Fire`, `Restore`, `StageUp`,
`UnitBuilt`, `RuinsCleared`. The `--replay` command rebuilds state from scratch from
the log.
**Why:** The core requirement is to keep a full history log and understand what the
city grew from. Also insurance against bugs: state can be rebuilt at any time.
**Done criterion:** The `events.jsonl` file grows without rewriting past lines.
Deleting `state.json` does not lose data — on the next launch state is restored from
the log. The `--replay` command is available from the CLI and produces an identical
result.

### F-04: `tasks.jsonl` watcher
**What:** `DispatchSource.makeFileSystemObjectSource` on the source file (path from
settings). The game remembers the offset of the last processed line. When the file
changes, the game reads only the tail, validates each line, and for valid lines creates
a `TaskCompleted` event in `events.jsonl` and applies it to state. Invalid lines are
logged in `errors.log` and skipped. The `tasks.jsonl` file is **never modified by the
game** — only read.
**Why:** This is the data channel from the external cron agent. The read-only contract
lets any source write to this file (cron, script, manual edit for testing).
**Done criterion:** Writing a new line to `tasks.jsonl` produces a unit on the map
within 2 seconds. The game does not lose events between launches (the offset is
persisted). A malformed JSON line does not break the watcher — the next line is
processed.

### F-05: Light district-life simulation
**What:** A layer of visual activity runs on top of static units:
- warehouses gradually accumulate piles of goods (tiles overlaid on the base warehouse);
- workshops emit smoke (particle smoke) and periodically "spark" (short particle bursts);
- the market shows activity animation (flags, traders at stalls);
- raw-material pits / fields have cycles (fill → empty);
- the cycles are independent of one another and do not block city growth.

There is no real supply chain or shortages. It is an illusion.
**Why:** The city should feel alive, not a static diorama. This creates the sense of a
working civilization.
**Done criterion:** Every district at stage ≥ 2 shows at least one active animation
(smoke, piles, flags) at any given moment. The simulation does not affect FPS (>60).
When a new unit appears it joins the overall simulation rhythm within 10 seconds.

### F-06: Project-District model and automatic placement
**What:** Each unique `project` (by name) corresponds to a District — a polygon on the
map. **Priority for placing a new project:**
1. If there are ruin zones on the map — the new project takes the oldest/largest ruin
   zone (with a clearing animation).
2. If there are no ruins — a fresh patch of free meadow is allocated (a growing spiral
   from the center).

A project's units live only inside its district. Layout is deterministic (replay yields
the same map).
**Why:** Visual semantics — every real-world project occupies its own place. The
priority on ruins gives the map regeneration — old "dead" projects provide ground for
new ones.
**Done criterion:** 3+ different projects in `tasks.jsonl` → 3+ non-overlapping
districts. When a new project appears on a map with a ruin zone — it takes the ruins
with a clearing animation lasting 3-5 sec. Without ruins — it takes fresh meadow.

### F-07: Unit composition and district balance
**What:** Internal game rules (no user config) determine which unit type appears with a
new task. Approximate proportions (exact numbers tuned in M2):
- ~50% residential (shack / house / villa depending on stage)
- ~20% infrastructure (well, road, warehouse)
- ~20% production (workshop, raw-material pit, field)
- ~10% social (market, square, forum, temple)

Additional rules: every N residentials require a well; the market appears only at
stage ≥ 2; temple/obelisk — at stage ≥ 4. Selection is deterministic (task ordinal
within the project → unit type via lookup table).
**Why:** Visual variety without forcing the source to annotate types. The game balances
the district itself.
**Done criterion:** A district of 20+ units contains buildings from all 4 categories
(residential, infra, production, social). Proportions stay within ±10% of targets.
Replaying the log yields an identical composition.

### F-08: District development stages (0 → 5)
**What:** Each District has a stage 0–5: meadow → shacks → wooden construction → stone
quarter → developed → luxurious. Transitions are computed by a formula from
`taskCount`, `projectAge` (from first task to last) and `activityRate` (events/week
over the last 30 days). An upgrade is an in-place sprite-tier swap on existing units,
not a relayout.
**Why:** Visible progress as the project grows. Active projects grow faster. History is
preserved (a unit stays where it was built).
**Done criterion:** As tasks and time accumulate, a project moves through all 5 stages
visually. A specific unit's coordinates do not change between stages. A project with
high activity (>5 events/week) reaches stage 3 in <2 weeks; a project with low activity
(1 event/week) — in >2 months.

### F-09: Decay and ruins
**What:** If a project has no events for > 14 days — `decayLevel` increases on a ticker
(once per hour + catch-up on launch). Levels:
- 1 (15–28 days): grass sprouts between flagstones, tiles fade;
- 2 (29–56 days): cracks in walls, collapsed roofs;
- 3 (57–90 days): fire (particle fire + smoke);
- 4 (>90 days): ruins. The district is marked as a ruin zone on the map.

Ruins **remain forever** — they are not removed and do not revert to meadow. But when a
**new project** appears (see F-06), ruins can be selected for construction and are
animated away to make room for the new district. If a new event arrives in the old
project before it transitions to ruins (decay 1-3) — a restoration animation plays (3-5
sec) and decay resets to 0.
**Why:** Feedback — forget a project, it visibly deteriorates. Coming back gives a
visible bonus. Ruins + regeneration give the map a cycle: nothing is lost, but the map
is not cluttered forever.
**Done criterion:** A project with no events for 14 days shows decay level 1. After 28
→ 2, after 56 → 3 (with a particle fire effect), after 90 → 4 (ruins). A new task in a
project with decay 1-3 resets decay to 0 with a repair animation. A new **different**
project can take over the ruins (see F-06 Done).

### F-10: Citizens and animation
**What:** Citizen sprites wander along the roads inside a district. Simple waypoint
pathfinding on the road network. District population = function of unit count and stage.
**If the unit count in a district decreases** (e.g. decay destroyed part of it) —
citizens leave the map with an animation.
**Why:** The city should "live" — static looks dead. Citizens are the main carrier of
the sense of motion.
**Done criterion:** Every district at stage ≥ 2 shows at least 3 moving citizens.
Citizens do not leave their district. FPS does not drop at 50+ citizens on the map.
When the unit count decreases, the citizen count smoothly (over 5-10 sec) converges to
the new target.

### F-11: Inspector / event journal
**What:** Click a building in explore mode → popup with the source task (title, ts,
project, the original log line). A SwiftUI side panel: list of projects with their
metrics (units, population, stage, decay, last activity), chronological event journal
with filters by date / project / event type.
**Why:** The user wants to understand "why is this house here" and see the full history
of the city.
**Done criterion:** Clicking any unit opens a popup with the task text, date and
project. The journal supports filters by project and date range. The side panel shows
all active projects with up-to-date metrics.

### F-12: State snapshots
**What:** Every 500 events or once per day — serialize `state.json`. On launch the game
loads the latest snapshot and replays only the tail of events after it.
**Why:** Fast start with a multi-thousand-event log. Without snapshots a replay of 10000
events takes seconds of delay.
**Done criterion:** A 10000-event log loads in under 1 second with a snapshot present.
Deleting snapshots does not lose data — the next launch restores everything from the
log and creates a new snapshot.

### F-13: Art-asset catalog (isometric tiles)
**What:** Minimal tile set:
- 5 unit types × 3 stages (residential, warehouse, workshop, market, well);
- decor (temple, obelisk, forum) — 1 tile each for stage 4-5;
- roads (4 corners + straights + crossings);
- grass tile (meadow), sand tile, ruins tile;
- 2-3 citizen sprites with walk animation (4 frames minimum);
- particle textures (smoke, fire, sparks);
- warehouse goods (piles of sacks, amphorae) — 3-4 variants.

Single style — simplified Egyptian isometric, pixel or vector.
**Why:** Without assets the city is placeholders; with assets it becomes pleasant to
look at.
**Done criterion:** All base units, stages and decor have rendered tiles in a unified
style. Roads connect to each other correctly. Citizens have walk animations. Ruins
tiles are visually distinct from fresh meadow. Particle effects fit the palette (see
`DesignConcept.md`).

### F-14: Settings (UI)
**What:** A SwiftUI settings panel with fields:
- **Path to `tasks.jsonl`** (file picker, validated on save);
- **Explore-mode hotkey** (⌘⌥G by default, rebindable);
- **Path to game data** (`events.jsonl`, `state.json`, snapshots) — defaults to
  `~/Library/Application Support/CommitPyramid/`;
- **Display for the city** (if several are connected — at launch only one, the main
  display; multi-display is in the backlog).

**Why:** The user must point at the log to read from and have control over the app's
behavior.
**Done criterion:** Settings allows changing the `tasks.jsonl` path — the change is
picked up by the watcher without a restart. A rebound hotkey starts working
immediately. The data path is validated on save (is it writable).

---

### F-15: Biomes and map generation

**What:** The map is generated **once** on first launch and saved as part of the game
data (reproducible via seed). Size — at least 256×256 tiles. Biomes:

| Biome     | Tile character                                       |
|-----------|------------------------------------------------------|
| Meadow    | Green grass, soft transitions — the default biome    |
| Desert    | Sand, ochre, rare oases                              |
| Forest    | Medium-density trees, darker grass                   |
| Mountains | Rocky relief, height, cliffs                         |
| Stones    | Rocky soil, a transition zone toward mountains       |
| River     | A linear body of water connecting biomes, 2-6 tiles wide |
| Sea       | A large body of water at the edge or as a bay        |

Transitions between biomes are **smooth** (simplex/Perlin noise): meadow blends into
forest, forest into mountains, desert into meadow through a transitional zone. Biomes
are distributed as "islands" or "peninsulas" — the sea / river along the borders create
natural geography.

**Re-initialization:** Settings has a "Reset map" button (with confirmation). The city
is rebuilt with a new seed: existing districts are re-placed in matching biomes, the
event log is not touched (history is preserved).

**Scale and zoom:** The map is large — minimum zoom should allow seeing the entire map
on a single screen (overview mode). Maximum zoom — detailed view of a single district.
The zoom range is wider than today's (add ×0.15–×0.25 for full overview).

**Unit and district affinity:** Each unit (see F-16) has a `terrain` field specifying
its preferred biome. When the placement algorithm picks a district location (F-06), it
takes the biome of the zone into account: a district next to a river — higher chance of
units with `terrain: river`; a mountain biome — forges and mines, a forest — sawmills.
Pure determinism is softened by **weighted randomness** (entropy): a district may get an
"unexpected" unit with ~15% probability — this creates natural variety.

**Why:** A large living map with varied relief turns a collection of districts into a
real city. Biomes give visual meaning to placement — a port district by the sea, a
mountain fortress on the cliffs. Smooth transitions deliver the Pharaoh-style
aesthetic.

**Done criterion:** On first launch the game produces a map ≥ 256×256 tiles with at
least 4 different biomes connected by smooth transitions. The map is reproducible from
a seed. The "Reset map" button + confirmation → new generation, districts are
re-placed. Zoom allows seeing the whole map in a single screen. A new district next to
a river receives water/river units with noticeably higher probability than uniform.

---

### F-16: Extended unit catalog (50 units + evolution chains)

**What:** Full list of units and their properties. Each unit has:
- **category** — residential / infrastructure / production / social / religious / military
- **terrain** — preferred biome (any / meadow / forest / mountains / stones / river / sea / desert)
- **size** — occupied cells (1×1, 1×2, 2×2, 2×3, 3×3, 4×4)
- **minStage** — minimum district stage for the unit to appear
- **evolves** — evolution chain (empty = large unit, placed as-is)
- **large** — "large unit" flag (does not evolve from small ones, placed straight away
  as a separate unit)

#### Evolution chains

Evolution triggers **visually**: cells are repainted, not moved. The data source is the
count of units of that type in the district reaching a threshold.

| Units | Type          | → | Result          |
|-------|---------------|---|-----------------|
| 2     | Dugout        | → | Shack           |
| 2     | Shack         | → | House           |
| 2     | Hut           | → | Stone house     |
| 3     | House         | → | Tenement        |
| 2     | Stone house   | → | Manor           |
| 2     | Two-story house | → | Tenement      |
| 2     | Farmhouse     | → | Manor           |
| 3     | Warehouse     | → | Large warehouse |

_(Evolution is a visual sprite swap only, not a re-placement)_

#### Full catalog

**Residential (12 units)**

| #  | Name              | Terrain         | Size | minStage | large | Evolution                  |
|----|-------------------|-----------------|------|----------|-------|----------------------------|
| 1  | Dugout            | any             | 1×1  | 0        | no    | 2 → Shack                  |
| 2  | Shack             | any             | 1×1  | 0        | no    | 2 → House                  |
| 3  | Hut               | forest/mountains| 1×1  | 0        | no    | 2 → Stone house            |
| 4  | Farmhouse         | meadow/river    | 1×1  | 1        | no    | 2 → Manor                  |
| 5  | House             | any             | 1×1  | 1        | no    | 3 → Tenement               |
| 6  | Two-story house   | meadow/river    | 1×2  | 2        | no    | 2 → Tenement               |
| 7  | Stone house       | mountains/stones| 1×1  | 2        | no    | 2 → Manor                  |
| 8  | Townhouse         | any             | 1×2  | 2        | yes   | —                          |
| 9  | Tenement          | any             | 2×2  | 3        | yes   | —                          |
| 10 | Manor             | meadow/forest   | 2×2  | 3        | yes   | —                          |
| 11 | Villa             | meadow/river    | 2×2  | 4        | yes   | —                          |
| 12 | Palace            | any             | 3×3  | 5        | yes   | —                          |

**Infrastructure (8 units)**

| #  | Name              | Terrain         | Size | minStage | large | Evolution |
|----|-------------------|-----------------|------|----------|-------|-----------|
| 13 | Well              | meadow/desert   | 1×1  | 0        | yes   | —         |
| 14 | Road              | any             | 1×1  | 0        | yes   | —         |
| 15 | Gate              | any             | 1×2  | 1        | yes   | —         |
| 16 | Bridge            | river/sea       | 1×1  | 1        | yes   | —         |
| 17 | Cistern           | desert          | 1×1  | 1        | yes   | —         |
| 18 | Lighthouse        | sea/river       | 2×2  | 2        | yes   | —         |
| 19 | Irrigation canal  | desert/meadow   | 1×1  | 1        | yes   | —         |
| 20 | Pier              | sea/river       | 2×2  | 2        | yes   | —         |

**Production (12 units)**

| #  | Name              | Terrain         | Size | minStage | large | Evolution           |
|----|-------------------|-----------------|------|----------|-------|---------------------|
| 21 | Farm              | meadow/river    | 2×2  | 0        | yes   | —                   |
| 22 | Fishing wharf     | river/sea       | 1×2  | 0        | yes   | —                   |
| 23 | Workshop          | any             | 1×1  | 1        | no    | —                   |
| 24 | Warehouse         | any             | 2×2  | 0        | yes   | 3 → Large warehouse |
| 25 | Forge             | mountains/stones| 1×1  | 1        | yes   | —                   |
| 26 | Pottery           | meadow/river    | 1×1  | 1        | yes   | —                   |
| 27 | Brewery           | meadow/forest   | 1×2  | 2        | yes   | —                   |
| 28 | Sawmill           | forest          | 1×2  | 1        | yes   | —                   |
| 29 | Quarry            | mountains/stones| 2×2  | 1        | yes   | —                   |
| 30 | Mine              | mountains       | 2×2  | 2        | yes   | —                   |
| 31 | Large warehouse   | any             | 3×2  | 3        | yes   | —                   |
| 32 | Factory           | any             | 3×3  | 3        | yes   | —                   |

**Social (10 units)**

| #  | Name        | Terrain        | Size | minStage | large | Evolution |
|----|-------------|----------------|------|----------|-------|-----------|
| 33 | Tavern      | any            | 1×1  | 1        | yes   | —         |
| 34 | Market      | any            | 2×2  | 2        | yes   | —         |
| 35 | Square      | any            | 2×2  | 2        | yes   | —         |
| 36 | Bathhouse   | meadow/river   | 2×1  | 2        | yes   | —         |
| 37 | School      | any            | 2×1  | 2        | yes   | —         |
| 38 | Hospital    | any            | 2×2  | 3        | yes   | —         |
| 39 | Forum       | any            | 3×3  | 3        | yes   | —         |
| 40 | Library     | any            | 2×2  | 4        | yes   | —         |
| 41 | Aqueduct    | mountains/meadow | —  | 3        | yes   | —         |
| 42 | Theater     | any            | 3×2  | 4        | yes   | —         |

**Religious (5 units)**

| #  | Name      | Terrain    | Size | minStage | large | Evolution |
|----|-----------|------------|------|----------|-------|-----------|
| 43 | Chapel    | any        | 1×1  | 1        | yes   | —         |
| 44 | Temple    | any        | 2×2  | 3        | yes   | —         |
| 45 | Obelisk   | desert     | 1×1  | 4        | yes   | —         |
| 46 | Cathedral | any        | 3×3  | 5        | yes   | —         |
| 47 | Pyramid   | desert     | 4×4  | 5        | yes   | —         |

**Military / defensive (3 units)**

| #  | Name           | Terrain    | Size | minStage | large | Evolution |
|----|----------------|------------|------|----------|-------|-----------|
| 48 | Watchtower     | any        | 1×1  | 1        | yes   | —         |
| 49 | Barracks       | any        | 2×2  | 2        | yes   | —         |
| 50 | Shipyard       | sea/river  | 3×3  | 3        | yes   | —         |

**Why:** Variety makes the city visually interesting and geographically meaningful.
Evolution chains create a sense of growth without complicating the logic — cells are
simply repainted. "Large" units flagged with `large` are placed straight away as a
single significant object — a warehouse is built, it does not "grow" out of small
sheds.

**Done criterion:** All 50 units have implemented sprites and are correctly chosen by
the placement algorithm with respect to `terrain`, `minStage` and `large`. Evolution
chains fire visually when the threshold is reached. A district of 30+ units contains
≥ 3 different categories. Reproducible via replay.

### F-17: In-app journal — manual task entry

**What:** A built-in log window inside the app for manually entering completed tasks.
This solves the problem of "remote" tasks with no visible code increment — the physical
world, meetings, calls, research. Two entry points:

1. **Global journal.** A separate window (a button in `JournalWindowController` or a new
   one) with the history of all events plus an input block: a text field "what did you
   do", a dropdown for picking a `projectId` (existing projects + a "new" button), Enter
   → a new event in `events.jsonl` → a unit on the map.
2. **Contextual entry by clicking a district.** In explore mode, clicking an empty part
   of a district → popup "add task to project X" (projectId is pre-filled from the
   district). This is an extension of the existing F-11 (inspector) for empty-cell mode.

The journal and the contextual entry share a common internal pipeline
`TaskCompletion(projectId, title, ts, source="journal")` → `events.jsonl`. The history
of journal events is visible in the same journal (filter by `source == "journal"`).

**Why:** Not all work is code or markdown. Some tasks are meetings, physical errands,
learning, remote work without an artifact. The journal provides a way to record them in
the city straight from the app, without dropping into a text editor.

**Done criterion:** The global journal opens via a button/hotkey, text input + project
+ Enter → a unit appears in the matching district within 1 sec. Clicking an empty part
of an existing district in explore → popup with pre-filled projectId, task entry works
identically. All journal events are visible in the shared log with `source: journal`.
Journal-event history survives restart (idempotent via `events.jsonl`).

### F-18: Notes/folder watcher — markdown source parser

**What:** The watcher monitors user-selected .md files / folders of notes and parses
completed tasks using built-in templates. This supersedes the old F-04 (single
`tasks.jsonl`) as a generalization.

**Built-in parsing templates** (described in in-game docs, accessible via the "?" button
in Settings):

| Template | Example | Extracted |
|----------|---------|-----------|
| `- [x] [project: <id>] <title>` | `- [x] [project: myapp] fixed login bug` | project=myapp, title=fixed... |
| `- [x] <title> #<project>` | `- [x] bought groceries #household` | project=household, title=bought... |
| `~~<title>~~ #<project>` | `~~called the doctor~~ #personal` | project=personal, title=called... |
| `- [x] <project>: <title>` | `- [x] myapp: added a test` | project=myapp, title=added... |

A line that matches none of the templates is ignored.

**Sources in Settings:**
- A list of paths: you can add a single file, a folder (non-recursive), or a folder
  recursively.
- Default extensions are `.md`, expandable.
- For each source — a processing mode: `delete-processed` (delete processed lines /
  files — `events.jsonl` is the source of truth) or `sidecar-dedup` (store
  `.processed-state.json` next to the file, don't touch the original .md).
- The watcher runs on `DispatchSource` (file changes) + a common 5-minute poll (see
  F-20).

**Why:** Many users already keep tasks in Obsidian / Bear / a plain `notes.md`. Don't
force them to relearn — let the app parse the existing notes. The "delete processed"
option removes the "junk piles up in the source files" problem.

**Done criterion:** The user adds a file/folder in Settings. Writes `- [x] [project:
test] hello` into a .md file and saves — within 5 sec a unit appears on the map in the
`test` district. In `delete-processed` mode the line is removed from the .md. In
`sidecar-dedup` mode the line hash is recorded in `.processed-state.json`, and a
re-parse does not create a duplicate. All 4 built-in templates work. In-game docs
describe the templates via the `?` button in Settings.

### F-19: Git watcher — auto-counting code increments

**What:** The watcher monitors selected local git repositories. Each new commit in the
main branch = a `TaskCompletion` event → a unit on the map. Languages don't matter —
only commit metadata is read.

**Configuration in Settings:**
- A list of repos: for each one `path`, `projectId` (defaults to the value derived from
  `git remote get-url origin`, e.g. `git@github.com:foo/myapp.git` → `myapp`), `branch`
  (defaults to `main`/`master` via auto-detection).
- Optional: `git fetch` before scan (to pick up pushes from other machines).
- Ignore: list of message prefixes (`chore:`, `wip:`, `style:` by default).

**Scan logic (driven by the 5-minute poll from F-20):**
1. For each repo: `git log <branch> --since <last_check_ts> --pretty=format:"%H|%ct|%s"`.
2. For each new sha → dedup check via `source: "git:<repo>:<sha>"` in `events.jsonl`.
3. If unique — create the event. Title = first line of the commit message.
4. **Optional (advanced):** `git diff --shortstat <prev>..<sha>` → volume. A small
   commit (≤10 lines) = 1 unit; medium (10–100) = 2-3; large (>100) = 4+.
5. **Optional (advanced):** unit category from the conventional-commits prefix:
   `feat:` → residential, `fix:` → infra (repair), `refactor:` → production,
   `docs:`/`chore:` → social/ignore.

**Why:** When the work is code in a repo, you don't want to manually write "closed task
X". Git already keeps an honest commit log. An automatic bridge commits → units gives
the city growth just for the developer doing their job.

**Done criterion:** The user adds a local git repo in Settings. Makes a commit in
`main` (locally or via `git pull` after a web-UI push). Within 5 min a unit appears on
the map in the matching district. Duplicates by sha are not created on rescan. The
"weight by diff" and "category by commit-type" options can be enabled/disabled
independently in Settings.

### F-20: Catch-up watcher — unified planner for all sources

**What:** A unified mechanism that drives all 3 sources (F-17 writes directly, not via
poll; F-18 + F-19 go through the poll). Consists of:

1. **Periodic poll every 5 minutes** — a main-thread Timer that, on fire, runs `scan()`
   for every active F-18 / F-19 source. The 5-min interval is a compromise between
   "responsiveness" and "CPU/disk load".
2. **Immediate scan on app start** — after snapshot+tail loading (F-12) and before
   wiring up watchers, a single full pass runs with `last_check_ts` from per-source
   state. This closes the "game was off for 3 days, what did I miss" gap.
3. **Per-source state** — every F-18 source (per-path) and F-19 source (per-repo)
   stores `last_check_ts` in Application Support. It updates on successful scan.
4. **Idempotent dedup** — F-18 via sidecar or line deletion, F-19 via sha. F-17 doesn't
   need it (writes go through the UI only).

**Why:** Without catch-up on start, gaps during downtime are lost. Without a unified
interval, every watcher does its own thing and the load is unpredictable.

**Done criterion:** When the app starts after ≥1 day of downtime, all commits in
configured repos + all new `[x]` in notes folders are detected and land on the map
within 30 sec. The periodic poll every 5 min catches changes in live mode (new
commits, new `[x]` in an open .md file). Per-source `last_check_ts` survives restart.
The 5-min interval is overridable in Settings (3–60 min).

---

### F-21: Open-source readiness (GitHub + contributors)

**What:** Prepare the project for publication on GitHub as open-source with an active
contributor pipeline. The idea: developers will get interested in the "commits grow
the city" concept, join the project and help finish it. The contribution channel is
especially valuable for art (AI-generated sprites from prepared prompts — see TASK-040
in Diff).

**Composition:**

1. **Connect to the user's GitHub account.** `gh` CLI authorization or SSH key, create
   the `CommitPyramid` repository (public, MIT license).
2. **Clean personal data from the code.** Audit: real names, email addresses, local
   paths in comments, `git config user.*` in commit metadata, any private API keys /
   tokens. Replace or strip them.
3. **Clean unrelated repositories** on the user's GitHub account (at the user's
   discretion, one-off operation — not part of the codebase).
4. **English documentation** in the `docs/` directory:
   - `docs/README.md` — main page (overview, demo screenshot, install, quick start,
     screenshot, badges).
   - `docs/concept.md` — product concept (adapted translation of `concept/Concept.md`).
   - `docs/architecture.md` — technical architecture (event-sourcing, snapshot+tail,
     EventSource).
   - `docs/asset-prompts.md` — catalog of AI prompts for contributor-artists (see
     TASK-040).
   - `docs/sprite-generation-rules.md` — technical requirements for assets (English
     translation).
   - `docs/CONTRIBUTING.md` — fork → branch → PR workflow.
   - `docs/CONTRIBUTING-ASSETS.md` — how to add a PNG sprite (for artists).
   - `docs/log-format.md` — `tasks.jsonl` / `events.jsonl` specification (English
     translation).
   - Root `README.md` — short description + link to `docs/`.
5. **Structure for contributors:**
   - `LICENSE` (MIT).
   - `.github/ISSUE_TEMPLATE/` — bug report, feature request, asset contribution.
   - `.github/PULL_REQUEST_TEMPLATE.md` — PR template.
   - Optional: GitHub Project board or Labels (`good first issue`, `help wanted`,
     `area:art`, `area:engine`, `area:ui`).
6. **Internal documentation (Russian, for the PM cycle)** stays in `concept/` — do not
   duplicate, link from `docs/architecture.md`.

**Why:** Without publication, the project stays a one-man pet — no external interest,
no artists, no ideas. The contributor channel is especially important for art (50
units × final PNGs — a task one person spends months on but a community finishes in a
week from prepared prompts).

**Done criterion:** The repository is public at github.com/<user>/CommitPyramid. Anyone can
clone it, read `README.md` and `docs/`, and understand what the project is and how to
help. Documentation is fully in English (the Russian version stays only in `concept/`
as internal). A contributor-artist takes under an hour from first visit to a merged PR
with a new PNG. No personal data leaks in commits or code.
