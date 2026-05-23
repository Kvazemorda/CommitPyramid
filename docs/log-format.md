# CommitPyramid — `tasks.jsonl` Format Specification

> English version. The Russian source is `concept/LogFormat.md` and remains the working document for the maintainer.

_This is the technical contract between the external cron agent and the game. Any change to this
format breaks compatibility and requires a format version bump (see below)._

## Purpose

`tasks.jsonl` is the sole data ingestion point into the game. The user's external cron agent
appends new lines to it when completed tasks are detected. The game watches the file, reads only
the tail (offset is persisted), validates each line, and converts valid lines into `TaskCompleted`
events in its own `events.jsonl`.

## Location

The file path is configured in game settings (F-14). Default:

```
~/Library/Application Support/CommitPyramid/tasks.jsonl
```

If the file does not exist, the game creates an empty file on first launch and begins watching it.

## Format

- Encoding: **UTF-8**.
- Line ending: **LF** (`\n`), not CRLF.
- Each line is an **independent JSON object**. No wrapping array.
- The file is **append-only** from the cron agent side. The game **never modifies** the file.
- Empty lines are allowed (skipped by the game).
- Lines starting with `#` are comments (skipped by the game). Use these for debug annotations from
  the cron agent.

## Record Schema

### Required Fields

| Field      | Type             | Description                                                                                 |
|------------|------------------|---------------------------------------------------------------------------------------------|
| `ts`       | string (ISO8601) | Record timestamp (scan-time). Format `YYYY-MM-DDThh:mm:ssZ` or with timezone offset        |
| `project`  | string           | Human-readable project name. **The name is the identifier.** Case is preserved             |
| `title`    | string           | Task text. Length 1–500 characters. Used in the inspector and the log                      |

### Optional Fields

| Field      | Type    | Description                                                                                                    |
|------------|---------|----------------------------------------------------------------------------------------------------------------|
| `task_id`  | string  | Stable task identifier. If omitted, the game generates a UUID v4. Used for deduplication in the future        |
| `source`   | string  | Arbitrary source string (file path, ticket URL). Persisted and shown in the inspector                         |
| `version`  | integer | Record format version. Default `1`. The game rejects versions >1 (until an upgrade is released)               |

### Extra Fields

Any fields not listed above are **preserved as-is** in `events.jsonl` but have no effect on game
logic. This allows the cron agent to embed service metadata without breaking the contract.

## Examples

### Minimal Valid Line

```json
{"ts": "2026-05-21T10:30:00Z", "project": "my-website", "title": "Approved the spec with the client"}
```

### Full Line

```json
{"ts": "2026-05-21T10:30:00Z", "project": "my-website", "title": "Approved the spec with the client", "task_id": "site-001", "source": "/path/to/brief.md", "version": 1}
```

### Multiple Consecutive Lines (file fragment)

```
# 2026-05-21 — tasks added for the week
{"ts": "2026-05-15T09:00:00Z", "project": "CommitPyramid", "title": "Drafted the concept"}
{"ts": "2026-05-21T10:30:00Z", "project": "my-website", "title": "Approved the spec"}
{"ts": "2026-05-21T11:00:00Z", "project": "my-website", "title": "Sent the contract"}
```

## Project Identification

- `project` is compared **case-sensitive, as-is, without trim**. That is, `"my-website"` and
  `"my-site"` are **two different districts**.
- To avoid accidental "duplicates" (typo in name → new district), the cron agent must use a
  stable canonical name.
- If the project name genuinely changes and the district needs to be "renamed", that is a
  migration operation — not part of the standard flow. Tracked in the backlog.

## Error Handling (game behavior)

| Situation                                        | Game behavior                                                                       |
|--------------------------------------------------|-------------------------------------------------------------------------------------|
| Malformed JSON line                              | Written to `errors.log` with line offset; line is skipped                           |
| Missing required field                           | Written to `errors.log`; line is skipped                                            |
| `ts` in wrong format                             | Written to `errors.log`; line is skipped                                            |
| `title` longer than 500 characters               | Truncated to 500 + `…`, written to `errors.log` (warning), line is processed        |
| Unknown `version > 1`                            | Written to `errors.log`; line is skipped                                            |
| `ts` in the future (> now + 1 day)               | Written to `errors.log` (warning); line is processed with `future` flag             |
| File deleted / moved                             | Watcher keeps watching (DispatchSource). When a new file is created — resumes from offset 0 |

## Deduplication (current MVP)

In the MVP **deduplication is disabled**. Every line is a new event, even if it looks identical to
the previous one. This is a deliberate decision:

- Keeps the contract simple (the agent does not need to track "what was already written").
- If the agent writes a duplicate — that is the agent's responsibility to avoid.

In the future (see `Backlog.md`) deduplication by `task_id` may be introduced when the field is
present.

## Offset Persistence

The game stores the offset of the last processed position in `tasks.jsonl` in the file:

```
~/Library/Application Support/CommitPyramid/ingestion-state.json
```

Format:
```json
{"file_path": "/path/to/tasks.jsonl", "offset_bytes": 12345, "last_read_ts": "2026-05-21T11:00:00Z"}
```

On startup the game checks:
- File size >= offset → read from offset to end.
- File size < offset → file was truncated/replaced; read from 0.
- `file_path` changed in settings → read the new file from 0.

## Format Versioning

Current version: **1**.

Future format changes must:
- Increment the `version` value in new lines.
- Support backward reading of old lines (`version: 1` is always readable).
- Be documented in a separate section in this file with a changelog.

## Minimal Working Example

1. The user creates `~/Library/Application Support/CommitPyramid/tasks.jsonl` (or the game creates it
   automatically).
2. The user's cron agent appends a line to the file:
   ```json
   {"ts": "2026-05-21T10:30:00Z", "project": "Test", "title": "First task"}
   ```
3. The game (watcher active) detects the change within 2 seconds, reads the new line,
   creates a `TaskCompleted` event in `events.jsonl`, and renders a new unit in the "Test" district
   on the map (a fresh district is created since none existed before).

## Events in events.jsonl (system)

In addition to `task_completed`, the engine writes system events from `applyTaskCompleted`
and `DecayEngine`. All use the `GameEvent` structure (see `Data/GameEvent.swift`).

### Event Kinds

| Kind            | When written                                                    | `title` field             |
|-----------------|-----------------------------------------------------------------|---------------------------|
| `task_completed`| live ingest and from watcher                                    | task title                |
| `unit_built`    | each completed task → a new unit is built (`!silent`)           | `UnitKind.label`          |
| `stage_up`      | district stage increase 0→…→5 (`!silent`)                       | `S<old> → S<new>`         |
| `restore`       | return to a project with `decayLevel 1..3` (`!silent`)          | nil                       |
| `decay_tick`    | `DecayEngine` tick increasing decay level                       | nil                       |
| `fire`          | decay transition 2→3 (fire visualization)                       | nil                       |
| `ruins_cleared` | (reserved; not yet written separately)                          | nil                       |
| `unit_evolved`  | visual unit evolution at F-16 threshold                         | `<uid>\|<from>\|<to>`     |

### Event Order for a Single Task (normative)

`task_completed` → (`restore` optional) → `unit_built` → (`unit_evolved` × N optional) → (`stage_up` optional)

All four events are written within a single call to `applyTaskCompleted` (live tick).
In the `silent: true` branch (replay from log / snapshot tail) **no new records are written**:
events are already on disk. Idempotency is guaranteed by
`apply(.unitBuilt) = apply(.stageUp) = break`.

### Backwards Compatibility v1 → current

Old logs (only `task_completed` + decay series) replay without modification:
state aggregates (`taskCount`, `stage`, `unitIds`) are derived from `task_completed` branches.
New logs contain `unit_built/stage_up`, but these are no-ops on apply — state is identical.
The format version is **not** bumped (there is no `version` field in `GameEvent`).

### Behavior for Unknown `kind`

`GameEvent.Kind` is a closed `Codable enum` without `@unknown default`. A line in
`events.jsonl` with an unknown `kind` is skipped: `EventLog.readAll` catches the
decoding error via `try?` and writes to `ErrorsLog`
(`EventLog.swift:42-45`). This means:
- An old binary reading a log with a new `kind` does not crash, but loses those lines;
- When adding a new `kind`, authors must update `LogFormat.md` and maintain compatibility
  via `apply = break` or a dedicated no-op branch.

---

## Compatibility: 12 → 50 Units (TASK-037)

_Added 2026-05-23_

### rawValue Guarantees

The original 12 rawValues (`shack`, `house`, `villa`, `well`, `road`, `warehouse`,
`workshop`, `raw`, `market`, `forum`, `temple`, `obelisk`) are **guaranteed to be valid
in all future versions**. Do not rename them or move them to different cases.

- `temple` and `obelisk` remain in the `.social` category until TASK-035 (reclassification
  to `.religious` will happen simultaneously with the rewrite of `UnitPlanner`).
- The test `testRawValuesStable12()` in `LegacyStateMigrationTests.swift` is the safety
  net against accidental renames.

### state.json Compatibility

- Old snapshots (`StateSnapshot.version == 1`) are read by new code as-is;
  the version is **not bumped** when the `UnitKind` catalog is extended.
- `currentVersion` is incremented only when the structure of `CityState` / `ProjectState` /
  `UnitState` changes in a breaking way.
- When adding new fields to these structures, fields must be `Optional` or have a default
  (e.g., via a custom `init(from:)` with `decodeIfPresent`).
- An unknown `UnitKind` rawValue in a snapshot → `JSONDecoder` cannot decode the whole
  `StateSnapshot` → `SnapshotStore.load()` returns `nil` and writes to `errors.log` →
  the engine falls back to a full replay from `events.jsonl`.
  Partial resilience (skipping a single broken unit) is in the backlog as
  "partial-snapshot robustness".

### events.jsonl Compatibility

- `UnitKind` is **not serialized in `events.jsonl`**. The `title` field of the `unit_built`
  event stores only the human-readable `UnitKind.label`, not the rawValue. Therefore
  extending the catalog from 12 to 50 cases **does not require migrating the event log**.
- On full replay, `UnitKind` is recalculated by the current version of the planner
  (`UnitPlanner`) — this is an architectural property, not a bug. A full replay after an
  app update may produce different kinds than were in the original state (this is
  acceptable and documented).

### Diagnostics

`SnapshotStore.load()` distinguishes three scenarios:

| Situation | Written to errors.log | Action |
|-----------|----------------------|--------|
| File does not exist | No | Return nil → full replay |
| File exists but cannot be read | Yes | Return nil → full replay |
| File readable, decode failed (unknown rawValue, schema mismatch) | Yes + error details | Return nil → full replay |
| Snapshot version ≠ currentVersion | Yes | Return nil → full replay |
| All OK | No | Return snapshot |
