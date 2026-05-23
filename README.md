# CommitPyramid

> Your real work builds a virtual city. A native macOS ambient companion that turns your closed tasks, git commits, and notes into an ever-growing isometric city — kept always behind your other windows so it lives on your desktop without distracting you.

![CommitPyramid screenshot placeholder](docs/screenshot-placeholder.png)

## What it is

You give CommitPyramid a stream of "things you closed" — completed tasks from your task manager, commits from your repositories, or `[x]` checkboxes in your notes. Each item builds a tile in your city. Long-untouched projects fall into disrepair; revived projects bloom again. Stages, evolution chains, biomes, and NPC citizens emerge from your real activity.

It is not gamification with badges. It is **ambient feedback** — a city that quietly reflects what you actually did this week.

## Status

This project is in active development. Core mechanics work; the visual layer relies on procedural placeholder sprites until contributors generate themed PNG assets via the catalog in [`docs/asset-prompts.md`](docs/asset-prompts.md).

Convergence (May 2026): 17 of 19 features done, 2 partial. See [`docs/architecture.md`](docs/architecture.md) for the technical map.

## Install

Requirements:

- macOS 14 (Sonoma) or later
- Xcode 15+ (Command Line Tools are not enough — the SpriteKit + XCTest stack needs the full Xcode)
- Swift 5.10

Build and run:

```bash
git clone https://github.com/Kvazemorda/CommitPyramid.git
cd CommitPyramid
swift build
swift run CommitPyramid
```

The app starts as a translucent window pinned behind all other apps. Press **⌘⌥G** anywhere to bring it to the foreground (explore mode) and back.

## How it works

CommitPyramid reads from event sources, each implementing the `EventSource` protocol:

1. **`tasks.jsonl` watcher** — one line per completed task. The simplest source, written by an external script or a cron job.
2. **Notes/Folder watcher** — scans `.md` files for `[x]` checkboxes, headings, bullets, or frontmatter, configurable in Settings.
3. **Git watcher** — runs `git log --since=<last-check-ts>` on configured local repositories, optionally derives weight from diff size and category from conventional-commit prefix.
4. **In-app journal** — type a task directly in the side panel or contextually by clicking an empty tile.

Every event becomes a `task_completed` line in `events.jsonl`. The engine deterministically builds units, raises stages, ages buildings into ruins, and animates citizens — all replayable from the log alone.

For the full architecture see [`docs/architecture.md`](docs/architecture.md).

## How to contribute

There are two main ways to help:

### Code

- Read [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md).
- Look at [issues with the `good first issue` label](../../labels/good%20first%20issue).
- Fork → branch → pull request.

### Art

The city currently renders procedural placeholders for all buildings and biomes — coloured isometric primitives. The visual goal is a **Pharaoh-style hand-painted look** (sand, ochre, lapis, reed greens). We have a complete prompt catalog for AI image generators (Midjourney, DALL·E, SDXL):

- Read [`docs/CONTRIBUTING-ASSETS.md`](docs/CONTRIBUTING-ASSETS.md) — pipeline from prompt to merged PNG.
- Pick any unit or biome from [`docs/asset-prompts.md`](docs/asset-prompts.md), generate it, open a PR with the PNG.
- Every merged sprite immediately replaces its procedural placeholder in the next build — no code changes needed.

## Concept and product principles

- [`docs/concept.md`](docs/concept.md) — what CommitPyramid is, who it's for, why.
- [`docs/sprite-generation-rules.md`](docs/sprite-generation-rules.md) — technical and stylistic rules for art assets.
- [`docs/log-format.md`](docs/log-format.md) — `tasks.jsonl` and `events.jsonl` specification.

## License

MIT. See [`LICENSE`](LICENSE).

## Maintainer

[@Kvazemorda](https://github.com/Kvazemorda)
