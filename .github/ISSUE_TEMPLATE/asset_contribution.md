---
name: Asset contribution
about: Propose a new sprite or biome texture
title: "[ASSET] "
labels: art
assignees: ''
---

## What asset

- **Type:** building / biome / decay variant / citizen / effect
- **Name / kind:** (e.g., `pyramid`, `desert biome`, `temple stage 5 decay`)
- **File name:** `<rawValue>.png` matching the UnitKind rawValue from `Sources/CommitPyramid/Data/CityState.swift`

## Source

- **Generator:** Midjourney / DALL·E / SDXL / hand-drawn / Kenney pack / other
- **Prompt used** (if AI-generated):
  ```
  paste the prompt here
  ```

## Preview

Drag the PNG into this issue so reviewers see it inline before opening the PR.

## Technical checklist

- [ ] RGBA, transparent background
- [ ] Size matches `docs/sprite-generation-rules.md` § 1 (isometric 2:1, 64×32 or 128×64 px @2x)
- [ ] Palette in sand/ochre/lapis/reed-green family (or biome-appropriate)
- [ ] Tested locally: `swift build && swift run CommitPyramid` — sprite renders correctly in place of the placeholder

## License

By submitting this asset you agree to release it under the same MIT license as the rest of the project. AI-generated content must come from a generator whose terms allow commercial / redistribution use.
