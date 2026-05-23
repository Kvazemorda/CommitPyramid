# Contributing Assets to CommitPyramid

CommitPyramid needs art — and you don't have to be a professional artist to help. This guide covers everything from picking a sprite to opening a PR.

---

## What We Need

CommitPyramid aims for a hand-painted, isometric look inspired by classic city-builders like Pharaoh — warm colors, strong silhouettes, a slightly painterly texture. Right now, buildings and biome tiles are procedural placeholders: colored rectangles with geometry. Every sprite you contribute replaces one of those placeholders with something that actually brings the city to life.

If you can generate or hand-draw a sprite that fits the aesthetic, we want it.

---

## Quick Start

1. **Pick a sprite** from [`docs/asset-prompts.md`](asset-prompts.md) — each entry has a name, size, and a suggested prompt.
2. **Generate or draw it** — use Midjourney, DALL·E, SDXL, or draw it by hand. PNG output preferred from the start.
3. **Save the file** to `Sources/CommitPyramid/Resources/Buildings/<rawValue>.png` — the filename must match the `rawValue` exactly (see [Naming](#naming) below).
4. **Open a PR** using the asset contribution template (`.github/PULL_REQUEST_TEMPLATE.md`) — include a screenshot of the sprite in-game if you can.

That's it. We'll handle the rest.

---

## Technical Requirements

- **Format:** PNG, RGBA (RGB + alpha channel)
- **Background:** fully transparent — no white fill, no canvas color
- **Size:** correct pixel dimensions per sprite type, as specified in [`docs/sprite-generation-rules.md`](sprite-generation-rules.md) § 1
- **Tested locally:** run the app and confirm your sprite appears on the scene before submitting (see [Testing Locally](#testing-locally))

---

## Naming

The filename must exactly match the `rawValue` of the corresponding case in `enum UnitKind` in [`Sources/CommitPyramid/Data/CityState.swift`](../Sources/CommitPyramid/Data/CityState.swift).

That enum is the single source of truth for sprite filenames. If your file is named anything else, the engine won't find it.

Example: if the enum has `case townHall = "town_hall"`, the file goes in as `town_hall.png`.

---

## AI Generator Tips

**Midjourney**
- Use `--ar 1:1` or match the target aspect ratio from the rules doc
- Style keywords that work well: `isometric, hand-painted, warm palette, Pharaoh game art style, soft lighting, no background`
- `--no text, watermark, frame` to keep it clean
- `--stylize 200-400` for more painterly results

**DALL·E**
- Describe the target size explicitly: "512x512 isometric sprite"
- Add "transparent background, game asset, top-down isometric view"
- Post-process to remove any remaining background (Photoshop, GIMP, or remove.bg)

**SDXL / local models**
- Models like `juggernautXL` or `DreamShaper XL` handle isometric game art reasonably well
- ControlNet with an isometric depth map gives more consistent angles
- Always export at 2x your target size and downscale — looks cleaner

---

## Testing Locally

Build and run the app:

```bash
swift build && swift run CommitPyramid
```

To spawn many units quickly and find your sprite on the scene, use the bench env var:

```bash
CITY_BENCH_UNITS=200 swift run CommitPyramid
```

Scroll around the map until you see your unit type. If it shows up and looks right in context, it's good to go.

---

## License Note

By submitting an asset, you agree to license it under the project's [MIT License](../LICENSE). Please only submit AI-generated content from generators whose terms of service allow commercial use of outputs (Midjourney Basic+ plan, DALL·E via OpenAI API, most open-weight models). If you're unsure, mention the tool in your PR and we'll figure it out together.

---

## Common Pitfalls

- **Wrong size** — double-check the pixel dimensions in `sprite-generation-rules.md` before submitting
- **Opaque background** — white or solid-color backgrounds will show as a box in-game; the background must be transparent
- **File in wrong directory** — assets go in `Sources/CommitPyramid/Resources/Buildings/`, not anywhere else
- **Mismatched filename** — the filename must match the `rawValue` character-for-character, including case and underscores

---

## Help

Stuck on the prompt, the size, or anything else? Open an Issue with the `[ASSET]` label, paste your prompt, and attach any preview you have. We'll help iterate.
