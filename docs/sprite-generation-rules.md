# Sprite Generation Rules (Units and Biomes)

> English version. The Russian source is `concept/SpriteGenerationRules.md` and remains the working document for the maintainer.

This document describes how to prepare raster sprites for CommitPyramid so they fit into the
isometric SpriteKit renderer without any in-code adjustments and maintain a consistent visual
style throughout the city.

## 1. Technical Parameters

These apply to **all** AI-generated images — without them sprites will not align in the shared
renderer.

| Parameter             | Value                                                             |
|-----------------------|-------------------------------------------------------------------|
| Format                | PNG, **8-bit RGBA** (with alpha)                                  |
| Resolution            | **1024×1024** or **1217×1217** (square, exactly one object)       |
| Background            | **Fully transparent** (no underlays / frames / shadows)           |
| Viewpoint             | Isometric 2:1 (classic "Pharaoh" style), top-right angle, no perspective, no camera rotation |
| Lighting              | Light from top-left (left faces — lighter, right faces — darker, top — brightest) |
| Composition           | Object **horizontally centered**, base ≈ in the lower third of the image (anchor ≈ `(0.5, 0.30)`) |
| Color range           | 24–48 colors per sprite, no HDR / neon                            |
| Style                 | Light illustrative quality, soft outline (1–2 px), no photorealism, no cel-shading |

The engine tile is **64×32**. A sprite renders at approximately "one tile" wide (64 px)
or "two tiles" wide (128 px) for large buildings. The full detail of the source PNG is only
visible at maximum zoom — do not waste resolution on small inscriptions.

## 2. Style (common to all assets)

- **Palette:** warm ochre, clay, sand, grey stone, weathered wood; blue only for water and rare
  accents (doors, windows — muted blue-grey).
  Reference: `Sources/CommitPyramid/Theme/Palette.swift`.
- **Aged texture:** materials are worn, plaster shows cracks, wood is sun-bleached. **No**
  plastic surfaces or shine.
- **Outline:** clean, colored (dark brown/charcoal, not pure black RGB(0,0,0)). Thickness 1–2 px
  to avoid "ringing" at `SKTexture.filteringMode = .linear`.
- **Shadows and ground decoration:** **not drawn on the sprite**. The shadow ellipse and ground
  tile are added by code in `UnitSprites.makeStageNode`. The building stands "in empty space" on
  the PNG.
- **Evolution:** adjacent stages (stage N and N+1) must read as "an upgrade of the same building",
  not as two independent structures. The silhouette base and color family are related; what changes
  is the material, height, and level of detail.

## 3. Where to Place Files

In the SwiftPM package (`Package.swift` already includes `resources: [.process("Resources")]`):

```
Sources/CommitPyramid/Resources/
├─ Buildings/         # currently a plain folder, ready for migration to .atlas
│  ├─ shack.png
│  ├─ house_stage2.png
│  └─ …
├─ Citizens/
└─ Terrain/
```

Once there are ≥ 4 buildings, rename `Buildings/` → `Buildings.atlas/`.
SpriteKit will pack the PNGs into a single atlas at build time; no code changes are needed
(loading via `SKTexture(imageNamed:)` / `Bundle.module.url(forResource:withExtension:)`).

**Naming convention.** Latin snake_case, `<kind>_stage<N>.png`. The `kind` name equals
`UnitKind.rawValue` from `Sources/CommitPyramid/Data/CityState.swift`. No stage suffix = stage 1
(used for categorical units such as shack/well/raw — a single stage each).

| File                    | What                                         |
|-------------------------|----------------------------------------------|
| `shack.png`             | Shack (residential stage 1)                  |
| `house_stage2.png`      | Wooden house (residential stage 2)           |
| `house_stage3.png`      | Stone house (residential stage 3)            |
| `house_stage4.png`      | Multi-storey (residential stage 4)           |
| `villa.png`             | Villa (residential stage 5)                  |
| `well.png` / `road.png` / `warehouse_stageN.png` | Infrastructure          |
| `workshop_stageN.png` / `raw.png` | Production                        |
| `market_stageN.png` / `forum_stageN.png` / `temple_stageN.png` / `obelisk.png` | Social |

## 4. Building Catalog (what to generate)

Target scope: **50 units** across 6 categories. The full registry with terrain, size,
minStage, large flag, and evolution chains is in `concept/Concept.md` § F-16
(source of truth — no need to duplicate here). This section covers only the work-volume
summary and a note on the current implementation.

### 4.1. Summary by Category (see F-16)

| Category       | Count | Examples                                                             |
|----------------|-------|----------------------------------------------------------------------|
| Residential    | 12    | Dugout, Shack, Hut, Farmhouse, House, Two-storey, Stone, Townhouse, Tenement, Manor, Villa, Palace |
| Infrastructure | 8     | Well, Road, Gate, Bridge, Cistern, Lighthouse, Canal, Pier          |
| Production     | 12    | Farm, Dock, Workshop, Warehouse, Forge, Pottery, Brewery, Sawmill, Quarry, Mine, Large Warehouse, Factory |
| Social         | 10    | Tavern, Market, Square, Bathhouse, School, Hospital, Forum, Library, Aqueduct, Theatre |
| Religious      | 5     | Chapel, Temple, Obelisk, Cathedral, Pyramid                         |
| Military       | 3     | Watchtower, Barracks, Shipyard                                       |

### 4.2. Evolution Chains

Chains from F-16 represent a **visual swap** of cells, not a relocation. Sprites "before"
and "after" **must** share the same stylistic family (silhouette base, palette, roofing
materials):

- Dugout → Shack → House → Tenement
- Hut → Stone House → Manor
- Two-storey → Tenement
- Farmhouse → Manor
- Warehouse → Large Warehouse

Generating entire chains in a single dialog session (see § 6) keeps the style coherent
between stages.

### 4.3. Current Implementation (what is already rendered in code)

`UnitSprites.makeCategoricalBuilding` currently holds a simplified set of 4 categories × 5 stages
(`UnitKind` = shack/house/villa/well/road/warehouse/workshop/raw/market/forum/temple/obelisk).
This 12-unit model is a transitional layer toward F-16; new assets can be placed in
`Resources/Buildings/` **with their final F-16 names** (`zemlyanka.png`, `khizhina.png`,
`dvorets.png`, etc.) even before the code loads them — they will be integrated as `UnitKind` is
extended.

### 4.4. Footprint Size → Sprite Size

The `size` value from F-16 determines how many tiles the building occupies:

| Footprint | Target sprite width when rendered | Recommended PNG resolution |
|-----------|------------------------------------|----------------------------|
| 1×1       | 64 px (1 tile)                     | 1024² is sufficient        |
| 1×2 / 2×1 | 96–112 px                         | 1024²                      |
| 2×2       | 128 px (2 tiles)                   | 1024² or 1217²             |
| 2×3 / 3×2 | 160–192 px                        | 1217² or 1536²             |
| 3×3       | 192 px                             | 1536²                      |
| 4×4       | 256 px (Pyramid, etc.)             | 2048²                      |

Larger units therefore use higher-resolution source PNGs — details remain readable even at
distant zoom levels.

### 4.5. Biome Decor (a separate sprite set)

In addition to the 50 units, a **decor set** is needed that the engine scatters across biome
tiles (not tied to grid cells):

| Biome   | Decor                                                               |
|---------|---------------------------------------------------------------------|
| Meadow  | Bushes, wildflowers, scattered stones, dirt paths                   |
| Forest  | 3–4 tree varieties (pine, deciduous, dead tree), stumps, boulders   |
| Desert  | Palm trees, cacti, skeletons, decorative dunes                      |
| Mountains | Rock outcrops, boulders, scree                                    |
| Rocks   | Scattered stones of varying shapes                                  |
| River   | Reeds, water lilies, wooden planks                                  |
| Sea     | Surf foam, coastal rocks                                            |

Place in `Resources/Terrain/decor/<biome>/`. 3–5 variations per biome so that Poisson
distribution does not look like copy-paste. This is an additional ~25–35 PNGs.

**Total visual backlog:** ~50 buildings (some with 1–3 evolutionary forms, totaling ~70 building
sprites) + ~30 decor sprites + ~21 biome tiles (7 biomes × 3 variations) + ~30 transition tiles
= **~150 PNGs** for the "complete" catalog.

## 5. Biomes (Terrain Tiles)

See `concept/Concept.md`, F-15. Seven biomes; seamless isometric tiles 64×32 px are needed
(for the atlas, terrain can be generated at 256×128 and then downscaled).

| Biome     | What to generate                                                        |
|-----------|-------------------------------------------------------------------------|
| Meadow    | Green grass with light tufts, default terrain                           |
| Desert    | Light sand, subtle ripple pattern, sparse pebbles                       |
| Forest    | Dark grass tile (no trees on the tile — trees are a separate sprite overlay) |
| Mountains | Rocky bedrock, stone texture                                            |
| Rocks     | Stony ground, transitional zone                                         |
| River     | Blue water with gentle ripple                                           |
| Sea       | Blue-green water, deeper tone                                           |

For each biome, **3 variants** are needed to avoid a "checkerboard" repeat, plus
**4 transition tiles** to the neighboring biome (meadow↔forest, meadow↔desert,
rocks↔mountains, land↔water). Transitions are created with an alpha mask on the corners.

Biome decor (trees, stones, bushes, oasis) are **separate** sprites with a transparent
background, placed in `Resources/Terrain/decor/`. This allows the engine to distribute them
with Poisson sampling rather than trying to encode a pattern on the tile itself.

## 6. Generation Workflow

**One sprite = one PNG.** AI models maintain detail and style better on individual requests
than on a "4×5 grid".

**Batch of 2–3 in one dialog session.** Generate stage 2 → then immediately request stage 3 in
the same session, with an explicit style prompt:

> "Same style, same palette, same viewpoint, same base scale. This is the next stage of the same
> residential building — a stone house instead of a wooden one."

This keeps the silhouette and palette consistent across stages without drift.

**Style anchor.** The first "reference" sprite (currently `shack.png`) acts as the style anchor.
Start every new request with "in the style of the attached reference" + the file itself. If an
asset deviates significantly — regenerate it; do **not** try to fix it in Photoshop.

**Pre-commit checklist:**
1. Transparent background (`file Resources/.../foo.png` → `RGBA, non-interlaced`).
2. Height ≈ width (square). If not — crop to square; otherwise `anchorY` will drift.
3. Run the build, place a unit in the game, and verify:
   - the base does not "float" above the tile and is not sunken;
   - the silhouette does not merge with neighboring units;
   - readable at minimum zoom (×0.5–0.7).

If the base drifts — fix it **in code**, adjusting `anchorY` in the call to
`loadBuildingSprite(...)` (standard range `0.25..0.35`), not by redrawing the PNG.

## 7. What NOT to Do

- **Do not** ask the AI to generate "a sprite sheet of 4×5 in one PNG" — per-object detail drops
  4–5× and style becomes inconsistent.
- **Do not** draw shadows or ground directly on the sprite — the renderer adds its own shadow and
  ground tile.
- **Do not** include a frame, white background, labels, or watermarks.
- **Do not** change the viewpoint between stages (everything in the same 2:1 isometry).
- **Do not** store PSD / source files inside `Resources/` — only final PNGs; otherwise SwiftPM
  will attempt to include them in the bundle.
- **Do not** add animation frames at this stage. Animation (chimney smoke, window lights) is a
  separate task (overlay nodes on top of the static sprite).

## 8. Checklist for a New Sprite

1. Generate the PNG (1024² or 1217², transparent background, viewpoint/lighting per the rules).
2. Name it per the convention (`<kind>[_stage<N>].png`), Latin snake_case.
3. Place it in `Sources/CommitPyramid/Resources/<Buildings|Citizens|Terrain>/`.
4. Run `swift build` — verify that `resource_bundle_accessor.swift` picks up the file.
5. Launch the game, place a unit, and verify the base alignment and silhouette.
6. If needed — adjust `anchorY` / `targetWidth` **in code**, not in the PNG.
