# CommitPyramid Asset Prompts

A catalog of AI-image prompts for open-source contributors who want to add
sprites to CommitPyramid (the CommitPyramid SpriteKit engine). Pick an entry below,
copy the prompt into your tool of choice (Midjourney v6+, DALL-E 3, SDXL with
an isometric LoRA, Flux, Stable Cascade — anything that handles isometry),
clean the alpha channel, and open a pull request.

This document is the single canonical source of prompts. It mirrors
`concept/SpriteGenerationRules.md` (technical rules), `concept/UnitCatalog.md`
(unit metadata) and `Sources/CommitPyramid/Data/CityState.swift` (`UnitKind`
raw values, which are the authoritative file-name stems).

---

## Pipeline (what to do with a finished PNG)

1. Generate the image. Target resolution **1024×1024** (or **1217×1217** for
   2×2 / 2×3 / 3×3 footprints, **1536²** for 3×3, **2048²** for 4×4).
   8-bit RGBA, fully transparent background.
2. Name the file using the `rawValue` from `UnitKind`:
   `<rawValue>.png` for single-stage units, `<rawValue>_stage<N>.png` for
   units with stage evolution (stages 2–5; stage 1 has no suffix).
   Examples: `shack.png`, `house_stage3.png`, `villa.png`,
   `temple_stage5.png`, `pyramid.png`.
   File names are Latin **snake_case**, exactly matching the Swift raw value
   listed under each entry below.
3. Drop the file into `Sources/CommitPyramid/Resources/Buildings/`
   (biome tiles go into `Resources/Terrain/`, biome decor into
   `Resources/Terrain/decor/<biome>/`).
4. Run `swift build` locally to make sure SwiftPM picks it up
   (`resource_bundle_accessor.swift` should regenerate without errors).
5. Open a PR titled `assets: <unit_rawValue> stage<N>` and attach the prompt
   you used in the PR body. We do not require the generation seed, but it
   helps reviewers if a re-roll is needed.

**Do not:** burn shadows or ground into the PNG (the engine adds them),
draw frames / watermarks / text, change camera angle between stages, or
deliver sprite sheets (one object per PNG, always).

---

## Style guide (read once, then apply to everything)

CommitPyramid is a **hand-painted isometric city** set in a stylised
**Bronze-Age Mediterranean / Pharaonic** world. Think Pharaoh / Caesar 3 /
Nebuchadnezzar / Children of the Nile, repainted at modern resolution.

- **Projection:** classic 2:1 isometric, camera locked upper-right. No
  perspective foreshortening, no camera roll, no fisheye.
- **Light:** single warm sun from the upper-left. Left faces are bright,
  right faces a half-tone darker, tops the brightest, undersides in soft
  warm shadow. No rim lights, no neon, no HDR bloom.
- **Palette:** warm ochre, terracotta, sandstone, sun-bleached wood,
  weathered limestone, reed green. Accent colours — lapis blue (water,
  glass beads), Egyptian red, gold leaf — used sparingly. Avoid pure black
  outlines (use a deep umber/charcoal instead), avoid pure white highlights.
- **Texture:** painterly brushwork, soft 1–2 px outline, mild edge wear
  (cracked plaster, sun-faded paint, sand drift at the base). No
  photorealism, no cel-shading, no plastic shine, no chromatic aberration.
- **Composition:** object centred horizontally, base sits in the lower
  third of the canvas (engine anchor ≈ `(0.5, 0.30)`). The PNG canvas is
  empty around the object — no ground patch, no shadow ellipse, no terrain.

A single short style suffix you can append to every prompt:

> *hand-painted isometric 2:1 projection, Pharaonic Mediterranean palette
> (ochre, sandstone, terracotta, reed green, lapis accents), soft umber
> outline, warm upper-left sunlight, transparent background, single object
> centred, no shadow, no ground, no text, no frame*

---

## Universal negative prompt

Append this to every generation (or use it verbatim in tools with a
dedicated negative field):

> *text, letters, watermark, signature, logo, frame, border, UI, HUD,
> drop shadow on background, ground patch, grass under the building,
> people, characters, modern elements, cars, electric wires, neon,
> photorealism, 3D render, cel-shading, perspective distortion, fisheye,
> camera tilt, multiple objects, sprite sheet, grid, tiling, low contrast,
> blurry, JPEG artifacts*

Per-unit negatives below add only what is specific (e.g. "no boats" for
land-only structures).

---

# Buildings (50 prompts)

Each entry repeats the same compact contract:

- **rawValue / file name** — exact Swift raw value, used as the file stem.
- **Category** — drives ground-tint and planner behaviour.
- **Footprint / size** — controls how big the rendered sprite is.
- **Source PNG resolution** — what to generate (downscale happens in-engine).
- **Stage hint** — only present when the unit is part of an evolution chain.
- **Prompt** — drop into your generator.
- **Negative prompt** — append to your generator's negative field.

The category ground tint is added by code (see
`UnitSprites.categoricalGroundColor`), do not paint it.

---

## Residential (12)

### 1. Землянка — Dugout (`dugout.png`)

- **Category:** residential
- **Footprint:** 1×1 → 64 px wide at runtime
- **Source PNG:** 1024×1024
- **Stage hint:** earliest residential, evolves into Shack (`shack`) at
  threshold 2. Silhouette must read as "a hole in the ground with a roof",
  so the next stage looks like a clear upgrade.

**Prompt:**
> A tiny semi-subterranean dwelling: a low pit dug into compact earth,
> roofed with a shallow conical thatch of reeds and dried palm fronds
> lashed to wooden ribs. A crooked plank ramp leads down to a dark
> entrance covered by a stretched goat hide. Loose stones edge the rim.
> Warm sun-bleached ochre and dusty brown tones, dry reed yellow on the
> roof. Hand-painted isometric 2:1 projection, soft umber outline,
> upper-left sunlight, transparent background, single object centred,
> no ground, no shadow.

**Negative:** *universal +* people, smoke, well, fence.

---

### 2. Лачуга — Shack (`shack.png`)

- **Category:** residential
- **Footprint:** 1×1 → 64 px
- **Source PNG:** 1024×1024
- **Stage hint:** style anchor for the whole residential chain. Evolves
  into Hut (`hut`) at threshold 3. If a maintainer pins a reference image
  in a PR, it will be this one — keep the silhouette readable and the
  palette saturated but warm.

**Prompt:**
> A humble single-room shack with sagging walls of sun-dried mud brick
> and a patchy thatched roof of bundled reeds. A crooked wooden door
> faces front-left, a small square window with no shutter on the right
> face. Cracked plaster shows the straw inside the bricks. A clay water
> jar leans against one wall. Warm ochre walls, weathered grey-brown
> reed thatch, faded umber timber. Hand-painted isometric 2:1, soft
> umber outline, upper-left warm sun, transparent background.

**Negative:** *universal +* chimney, glass, stone walls, second storey.

---

### 3. Хижина — Hut (`hut.png`)

- **Category:** residential
- **Footprint:** 1×1 → 64 px
- **Source PNG:** 1024×1024
- **Stage hint:** forest/mountain-leaning variant of the early
  residential chain. Evolves into House (`house`) at threshold 4.

**Prompt:**
> A modest forest hut with walls of stacked rough timber logs chinked
> with pale clay, raised on a low fieldstone footing. A steeper thatched
> roof of long reeds overhangs the front to shelter a small porch with
> a single bench. A simple stone chimney pokes through the back of the
> roof, no smoke. Knot-holes and bark texture visible on the logs.
> Warm wood browns, mossy grey stone, dry reed thatch. Hand-painted
> isometric 2:1, soft umber outline, upper-left sun, transparent
> background.

**Negative:** *universal +* trees on canvas, animals, smoke plume.

---

### 4. Фермерский дом — Farmhouse (`farmhouse.png`)

- **Category:** residential
- **Footprint:** 1×1 → 64 px
- **Source PNG:** 1024×1024
- **Stage hint:** meadow/river-leaning early residential. Evolves into
  Two-storey house (`two_story_house`) at threshold 5.

**Prompt:**
> A single-storey farmhouse with whitewashed mud-brick walls warmed by
> sun, a low-pitched roof of overlapped clay tiles in faded terracotta
> red. A wooden lean-to on the right side shelters bundles of straw and
> a coiled rope. A small painted door in muted lapis blue, two square
> windows with wooden shutters. A clay grain bin sits flush against the
> back wall. Hand-painted isometric 2:1, soft umber outline, upper-left
> sun, painterly brushwork, transparent background, no ground.

**Negative:** *universal +* fields, fence, livestock, smoke.

---

### 5. Дом — House (`house_stage2.png`, `house_stage3.png`, `house_stage4.png`)

- **Category:** residential
- **Footprint:** 1×1 → 64 px
- **Source PNG:** 1024×1024
- **Stage hint:** three stages. Each stage is the same plot, upgraded —
  do not change orientation between stages. Evolves into Stone House
  (`stone_house`) at threshold 5.

**Stage 2 prompt — wooden house:**
> A compact one-storey house with framed walls of squared timber and
> sun-bleached plank cladding, narrow plank door, two shuttered windows.
> Low-pitched roof of split wood shingles greying with age. A small
> clay-lined hearth chimney on the rear roof slope. Warm honey-wood
> tones, soft grey-brown shingle. Hand-painted isometric 2:1, soft umber
> outline, upper-left warm sun, transparent background.

**Stage 3** — same house upgraded: lower walls switched to courses of
warm tan mud brick with a timber-framed first floor above, white-lime
plaster patches, a terracotta tile roof replacing the shingles. Door
now painted muted lapis blue under a small reed-mat awning. Same
footprint and orientation as stage 2.

**Stage 4** — same plot at full upgrade: solid honey-coloured limestone
walls with a carved string course, a steeper terracotta tile roof, a
small first-floor balcony with turned wooden balusters facing front-
left, a painted wooden lintel above the lapis door, two arched windows.

**Negative (all stages):** *universal +* second building, courtyard wall,
people, chimney smoke.

---

### 6. Двухэтажный дом — Two-storey house (`two_story_house.png`)

- **Category:** residential
- **Footprint:** 1×2 → ~96 px
- **Source PNG:** 1024×1024
- **Stage hint:** mid-tier residential. Evolves into Townhouse
  (`townhouse`) at threshold 6.

**Prompt:**
> A narrow two-storey townhouse with whitewashed lime walls, exposed
> timber framing on the upper floor, and a steeply pitched terracotta
> tile roof. Front door painted faded ochre with a wooden lintel, two
> shuttered windows on the ground floor, a small projecting balcony on
> the upper floor with a striped reed awning in cream and red. A clay
> drainpipe runs down the right corner. Sun-faded ochre and warm white,
> reed-green shutters. Hand-painted isometric 2:1, soft umber outline,
> upper-left sun, transparent background.

**Negative:** *universal +* third floor, attached neighbour buildings.

---

### 7. Каменный дом — Stone house (`stone_house.png`)

- **Category:** residential
- **Footprint:** 1×1 → 64 px
- **Source PNG:** 1024×1024
- **Stage hint:** mountain/stone biome leaning. Terminal in the small
  residential chain — does not evolve further (in current catalog).

**Prompt:**
> A sturdy single-storey stone house built from rough-hewn limestone
> blocks of mixed sizes, with deep window reveals and a heavy oak door
> bound in iron. A low-pitched roof of grey slate tiles with a stone
> chimney on the back ridge. A modest carved keystone above the door,
> a few weather-worn carvings of palm fronds along the lintel. Warm
> beige and pale grey stone, charcoal slate, muted ochre door. Hand-
> painted isometric 2:1, soft umber outline, upper-left sun, transparent
> background.

**Negative:** *universal +* moss, snow, ivy covering the building.

---

### 8. Таунхаус — Townhouse (`townhouse.png`)

- **Category:** residential
- **Footprint:** 1×2 → ~96 px (large)
- **Source PNG:** 1024×1024
- **Stage hint:** terminal large residential, no further evolution.

**Prompt:**
> An elegant narrow townhouse three storeys tall, clad in honey-coloured
> sandstone with carved cornices between floors. Tall arched windows on
> the ground floor with shutters folded back, smaller rectangular
> windows above with painted lapis frames. A small Juliet balcony on
> the top floor with wrought ironwork. Flat roof with a low parapet and
> a single decorative urn at one corner. Painted door in deep terracotta
> red with brass studs. Hand-painted isometric 2:1, soft umber outline,
> warm upper-left sunlight, transparent background.

**Negative:** *universal +* neighbouring walls, shopfront, awnings over
the street.

---

### 9. Доходный дом — Tenement (`tenement.png`)

- **Category:** residential
- **Footprint:** 2×2 → 128 px (large)
- **Source PNG:** 1217×1217
- **Stage hint:** evolution target for `house` and `two_story_house`.
  Densely populated city block; should feel "more building per tile" than
  a townhouse.

**Prompt:**
> A four-storey insula apartment building with thick rendered mud-brick
> walls painted in faded ochre and salmon pink, repeated rows of small
> shuttered windows with reed-green frames, a row of arched openings on
> the ground floor used as small workshops. A wide central doorway under
> a stone lintel, a worn step. Flat roof with hanging laundry lines on
> wooden poles and a few clay water jars. A drainpipe of split bamboo
> on one corner. Warm Mediterranean colours, sun-bleached walls, mild
> plaster cracks. Hand-painted isometric 2:1, soft umber outline,
> upper-left sun, transparent background.

**Negative:** *universal +* people on balconies, animals, modern signage.

---

### 10. Усадьба — Manor (`manor.png`)

- **Category:** residential
- **Footprint:** 2×2 → 128 px (large)
- **Source PNG:** 1217×1217
- **Stage hint:** evolution target for `stone_house` and `farmhouse`.
  Country-noble residence — should sit visually between a tenement and a
  villa.

**Prompt:**
> A two-storey country manor with a U-shaped plan around a small inner
> courtyard, walls of warm cream limestone with carved quoins, a
> low-pitched terracotta tile roof. A colonnaded loggia of four slender
> stone columns runs along the front, painted timber ceiling with
> faded geometric patterns. A tall double door of dark wood, brass
> handles. Two stone planters with cypress saplings flank the entrance.
> A small dovecote tower rises at the back corner. Hand-painted
> isometric 2:1, soft umber outline, warm upper-left sun, transparent
> background.

**Negative:** *universal +* fountain on canvas, garden walls extending
beyond footprint, people.

---

### 11. Вилла — Villa (`villa.png`)

- **Category:** residential
- **Footprint:** 2×2 → 128 px (large)
- **Source PNG:** 1217×1217
- **Stage hint:** the legacy "stage 5" residential cap before Palace was
  added. Should feel luxurious but still secular.

**Prompt:**
> A patrician seaside villa with bright white plastered walls, a portico
> of four red-painted columns with carved papyrus capitals, a low
> terracotta tile roof with carved acroteria at the corners. A central
> reflecting pool on the front terrace, edged in pale marble. Tall
> arched windows with reed-green wooden shutters, gilded bronze door
> handles, a painted frieze of stylised lotus flowers under the roofline.
> A pair of potted laurel trees beside the entrance. Hand-painted
> isometric 2:1, soft umber outline, warm upper-left sunlight,
> transparent background.

**Negative:** *universal +* sea on canvas, people, statue larger than
the building.

---

### 12. Дворец — Palace (`palace.png`)

- **Category:** residential
- **Footprint:** 3×3 → ~192 px (large)
- **Source PNG:** 1536×1536
- **Stage hint:** top of the residential ladder. Reads as a royal
  residence, not as a temple — keep religious iconography out of it.

**Prompt:**
> A grand three-storey palace with a wide colonnaded facade of twelve
> red-painted stone columns with carved lotus capitals, deep entablature
> painted with bands of blue and gold geometric ornament. Central great
> doorway flanked by twin obelisks in miniature, polished black granite.
> Flat roof with crenellated parapet and rows of golden pennants on
> tall poles. Side wings step back symmetrically. Pale limestone and
> warm sandstone walls, accents of lapis and gold leaf, painted reliefs
> of palm leaves above the door. Hand-painted isometric 2:1, soft umber
> outline, warm upper-left sun, transparent background, no shadow.

**Negative:** *universal +* religious symbols, crosses, crescent, large
sphinxes that dwarf the building.

---

## Infrastructure (8 + warehouse legacy)

### 13. Колодец — Well (`well.png`)

- **Category:** infrastructure
- **Footprint:** 1×1 → 64 px (large flag, single object)
- **Source PNG:** 1024×1024
- **Stage hint:** earliest infrastructure, paired with shacks in the
  oldest part of town.

**Prompt:**
> A circular village well built of mortared fieldstones, waist high,
> ringed by a worn flagstone step. A simple wooden A-frame above carries
> a rope and a tarnished bronze bucket suspended over the dark opening.
> A small clay drinking jar leans against the rim. Warm grey stone with
> moss in the joints, sun-bleached timber, dark green algae line at the
> water mark. Hand-painted isometric 2:1, soft umber outline, upper-left
> sun, transparent background, no ground.

**Negative:** *universal +* people drawing water, animals, puddle on
canvas, full bucket of water spilling.

---

### 14. Дорога — Road (`road.png`)

- **Category:** infrastructure
- **Footprint:** 1×1 → 64 px
- **Source PNG:** 1024×1024
- **Stage hint:** a single tile of paved street, designed to tile both
  horizontally and along the isometric grid axes. Keep edges centred so
  multiple copies join without obvious seams.

**Prompt:**
> A single isometric tile of a packed dirt-and-stone street, surfaced
> with irregular pale flagstones bedded in warm tan earth. A few worn
> grooves from cart wheels run diagonally across the tile. Tiny tufts
> of dry grass push up between two or three stones. Pale grey limestone
> and warm sand colours, soft variation but no strong directional
> feature — must repeat cleanly when stacked along an isometric grid.
> Hand-painted isometric 2:1, soft umber outline, upper-left sun,
> transparent background, edges fade to fully transparent.

**Negative:** *universal +* curbs, painted lane markings, vehicles,
people, lamp posts.

---

### 15. Ворота — Gate (`gate.png`)

- **Category:** infrastructure
- **Footprint:** 1×2 → ~96 px
- **Source PNG:** 1024×1024
- **Stage hint:** ceremonial city gate, no wall attached on the PNG (the
  engine does not draw walls yet).

**Prompt:**
> A monumental free-standing city gate: two massive sandstone pylons
> tapering slightly inward, faces carved with shallow reliefs of lotus
> and reed bundles painted in faded red and lapis. Between them a heavy
> dark cedar door studded with bronze, currently closed. A wooden lintel
> spans the top with a winged sun disk in dull gold. Warm honey
> sandstone, mild sand erosion at the base. Hand-painted isometric 2:1,
> soft umber outline, upper-left sun, transparent background, no walls
> extending past the footprint.

**Negative:** *universal +* city walls continuing off-canvas, guards,
banners larger than the gate.

---

### 16. Мост — Bridge (`bridge.png`)

- **Category:** infrastructure
- **Footprint:** 1×1 → 64 px
- **Source PNG:** 1024×1024
- **Stage hint:** a short footbridge tile; the engine will place it on
  river/sea tiles.

**Prompt:**
> A short arched stone footbridge made from neatly fitted pale limestone
> voussoirs forming a single semicircular span. Low parapet walls along
> both sides with carved finial stones at the corners. The deck is paved
> with flat slabs, slightly worn in the centre. Mild sand drift in the
> stone joints. Hand-painted isometric 2:1, soft umber outline,
> upper-left sun, transparent background, no water painted under the
> arch.

**Negative:** *universal +* river, water, boats, people, ropes.

---

### 17. Цистерна — Cistern (`cistern.png`)

- **Category:** infrastructure
- **Footprint:** 1×1 → 64 px
- **Source PNG:** 1024×1024
- **Stage hint:** desert-leaning water store, reads as half-buried.

**Prompt:**
> A squat round cistern of mortared rubble stone partly sunk into the
> ground, capped with a domed plastered roof painted dusty white-cream.
> A small arched access door on the front face with a dark interior, a
> stone gutter spout on one side draining into a shallow basin. A bronze
> ring set into the dome for a missing rope. Sun-bleached plaster with
> hairline cracks, warm sandstone base. Hand-painted isometric 2:1,
> soft umber outline, upper-left sun, transparent background.

**Negative:** *universal +* water spilling, palm trees on canvas, modern
tap, people.

---

### 18. Маяк — Lighthouse (`lighthouse.png`)

- **Category:** infrastructure
- **Footprint:** 2×2 → 128 px (large)
- **Source PNG:** 1217×1217
- **Stage hint:** harbour landmark. Should be tall — silhouette is the
  key feature.

**Prompt:**
> A tall slender stepped lighthouse in the style of the Pharos of
> Alexandria in miniature: a square stone base, an octagonal middle
> tier, and a small circular top with an open colonnade housing a brass
> fire bowl with a soft warm glow (no rays, no halo). White plastered
> walls with painted bands of pale ochre and lapis at each tier change,
> red-painted timber details. A spiral stair visible through narrow
> arched windows. Hand-painted isometric 2:1, soft umber outline,
> warm upper-left sun, transparent background.

**Negative:** *universal +* sea on canvas, light rays painted into the
sky, ships, seagulls.

---

### 19. Ирригационный канал — Irrigation canal (`irrigation_canal.png`)

- **Category:** infrastructure
- **Footprint:** 1×1 → 64 px
- **Source PNG:** 1024×1024
- **Stage hint:** linear element. Tile must work next to itself in any
  isometric direction.

**Prompt:**
> A single tile of a stone-lined irrigation channel running diagonally
> across the tile, shallow trapezoidal section, dressed limestone slabs
> at the sides and base. Clear blue-green water flows in a thin stream
> down the centre, gentle ripples, a few reed shoots growing at the
> edges. Pale stone, lapis-tinted water, dry sandy banks. Hand-painted
> isometric 2:1, soft umber outline, upper-left sun, transparent
> background, banks fade to alpha so adjacent tiles connect.

**Negative:** *universal +* fish, boats, people, large bridge, full
river bend.

---

### 20. Причал — Pier (`pier.png`)

- **Category:** infrastructure
- **Footprint:** 1×1 → 64 px (catalog: minStage 1, size 1×1)
- **Source PNG:** 1024×1024
- **Stage hint:** small civic pier, distinct from the production
  fishing pier — this one is for passengers and small craft.

**Prompt:**
> A short stone-and-timber jetty pushing out from a shore: a base of
> mortared limestone blocks topped with wide cedar deck planks worn
> silver by sun, two simple wooden bollards painted faded ochre at the
> end, a single iron mooring ring. A small bench of two stone slabs
> sits halfway along. Warm grey stone, sun-bleached wood, hint of
> seaweed at the waterline (no actual water painted). Hand-painted
> isometric 2:1, soft umber outline, upper-left sun, transparent
> background.

**Negative:** *universal +* large ship, water on canvas, fishermen,
nets, cargo crates dominating the tile.

---

### 21. Склад — Warehouse (`warehouse_stage2.png` → `warehouse_stage5.png`) [legacy infrastructure]

- **Category:** infrastructure (legacy; F-16 moves it to production —
  paint it neutrally so it works in either ground tint)
- **Footprint:** 1×1 → 64 px
- **Source PNG:** 1024×1024
- **Stage hint:** four stages. Evolves into Large Warehouse
  (`great_warehouse`) at threshold 3. Each stage adds capacity and
  permanence; silhouette family preserved.

**Stage 2 prompt — timber warehouse:**
> A simple rectangular warehouse with plank walls of weathered cedar on
> a low stone footing, wide double doors of dark timber barred with an
> iron lock. A shallow pitched roof of split shingles with a louvred
> vent at the ridge. Two clay storage amphorae lean against the front
> wall. Honey-wood and grey shingle. Hand-painted isometric 2:1, soft
> umber outline, upper-left sun, transparent background.

**Stage 3** — same plot upgraded: lower courses in tan mud brick, upper
half still cedar planks, wider doors of reinforced timber with iron
bands. Terracotta tile roof, a small wooden hoist arm above the door.

**Stage 4** — same plot, full mud-brick walls rendered in lime plaster
painted ochre, a row of small high ventilation windows, heavy double
doors with bronze studs, a longer hoist arm with rope and pulley, tile
roof with a low parapet.

**Stage 5** — same plot in dressed sandstone with carved corner blocks,
an arched main doorway, a small stone loading dock, two stone mooring
rings beside the door. Tile roof with ventilation louvres at the gable
— reads as the last step before evolving into a Great Warehouse.

**Negative (all stages):** *universal +* market stalls, people loading
goods, carts, animals, signage.

---

## Production (12)

### 22. Ферма — Farm (`farm.png`)

- **Category:** production
- **Footprint:** 2×2 → 128 px (large)
- **Source PNG:** 1217×1217
- **Stage hint:** appears next to meadow/river biomes. The PNG is the
  farm compound, fields are implied by surrounding biome tiles — do not
  paint fields onto the sprite.

**Prompt:**
> A small farm compound: a long low storage barn of mud brick with a
> reed-thatched roof, a small open-sided threshing shelter on timber
> posts, a tall woven grain silo of plaited reeds bound with rope. A
> wooden cart with two solid wheels parked beside the barn, an empty
> wicker basket on the ground. Warm ochre walls, dry reed yellows, soft
> straw on the threshing floor. Hand-painted isometric 2:1, soft umber
> outline, upper-left sun, transparent background, no surrounding
> fields painted on the canvas.

**Negative:** *universal +* crops growing on the tile, animals,
farmers, surrounding fence covering the canvas.

---

### 23. Рыболовецкий причал — Fishing pier (`fishing_pier.png`)

- **Category:** production
- **Footprint:** 1×2 → ~96 px (large)
- **Source PNG:** 1024×1024
- **Stage hint:** river/sea biome, distinct from civic Pier — more
  working, less ornamental.

**Prompt:**
> A working fishing pier: rough cedar deck on a row of timber piles, a
> small open-sided shelter of split planks at the end with drying nets
> draped over wooden rails, a stack of woven reed fish baskets, two
> spare oars leaning against the shelter post, a coiled rope. A simple
> wooden cleat at the corner for tying a boat (no boat painted). Warm
> wood greys, faded ochre nets, dull bronze net weights. Hand-painted
> isometric 2:1, soft umber outline, upper-left sun, transparent
> background.

**Negative:** *universal +* boats, fish painted onto the deck, people,
water on canvas.

---

### 24. Мастерская — Workshop (`workshop_stage2.png` → `workshop_stage5.png`)

- **Category:** production
- **Footprint:** 1×1 → 64 px
- **Source PNG:** 1024×1024
- **Stage hint:** four stages. Generic craft workshop — keep the trade
  unspecified so it can stand in for many crafts.

**Stage 2 prompt — open-front lean-to workshop:**
> A small open-front craft workshop: three plank walls and a sloping
> reed-thatched roof on timber posts, a stout wooden workbench in the
> front opening, a clay water jar and a few hand tools (mallet, chisel)
> on the bench. Sun-faded plank walls, dry yellow thatch. Hand-painted
> isometric 2:1, soft umber outline, upper-left sun, transparent
> background.

**Stage 3** — same plot upgraded to enclosed mud-brick walls plastered
warm ochre, a wide arched front opening with a half-shutter rolled up,
terracotta tile roof. A stone-lined hearth visible inside the opening
(no smoke), a wooden sign hook above the door (no text).

**Stage 4** — same plot, now two storeys: ground-floor workshop with
wide arched opening and a stone counter, upper floor with shuttered
window and a small woven-reed balcony, a short stone chimney at the
back roof slope (no smoke), tile roof.

**Stage 5** — same plot in dressed sandstone with carved string course,
an arched stone main opening with a polished bronze sign plaque (no
text), an awning of striped cream-and-red reed mat, tile roof with a
small decorative urn at one corner.

**Negative (all stages):** *universal +* people working, sparks, smoke
plume, finished goods piled on the canvas, modern tools.

---

### 25. Сырьевая яма — Raw pit (`raw.png`)

- **Category:** production
- **Footprint:** 1×1 → 64 px
- **Stage hint:** legacy "raw resources" placeholder unit. Reads as a
  small extraction site, materials unspecified.

**Prompt:**
> A small raw-material extraction pit: a shallow open rectangular dig
> with stepped earthen sides, a battered wooden ladder leaning into it.
> On the rim a pile of rough chunks of sandy rock and a single wicker
> basket with a leather strap. A short timber windlass with rope
> stands at one corner. Warm earth and dusty ochre tones, dull grey
> stone chunks. Hand-painted isometric 2:1, soft umber outline,
> upper-left sun, transparent background.

**Negative:** *universal +* people in the pit, fire, smoke, finished
products, gold or gems.

---

### 26. Кузница — Forge / Smithy (`forge.png`)

- **Category:** production
- **Footprint:** 1×1 → 64 px
- **Stage hint:** mountain/stone biome leaning. Faint warm glow at the
  forge mouth is allowed; no smoke plume.

**Prompt:**
> A small village forge: thick rough-stone walls open on the front
> like a deep shed, inside a stone-built forge hearth with a soft
> amber glow inside the opening (no flames escaping). A heavy timber
> anvil block holds a dark iron anvil with a hammer resting on it.
> A wooden bellows on the side, an open rack of tongs. A short
> conical stone chimney on the roof, no smoke. Soot streaks above the
> hearth mouth. Warm grey stone, charred timber, hint of orange from
> the embers. Hand-painted isometric 2:1, soft umber outline,
> upper-left sun, transparent background.

**Negative:** *universal +* tall smoke plume, blacksmith figure,
sparks flying off the canvas, electric forge.

---

### 27. Гончарная мастерская — Pottery (`pottery.png`)

- **Category:** production
- **Footprint:** 1×1 → 64 px
- **Stage hint:** meadow/river biome leaning.

**Prompt:**
> A village pottery: a small mud-brick workshop with a wide arched
> front opening showing a wooden potter's wheel and a low bench. A
> domed stone kiln stands beside the workshop, plastered cream-white
> with soot streaks around the loading door. On the ground in front,
> rows of finished amphorae and bowls drying on a reed mat. Warm
> ochre walls, deep terracotta of the pottery, pale cream kiln.
> Hand-painted isometric 2:1, soft umber outline, upper-left sun,
> transparent background.

**Negative:** *universal +* potter figure, wet clay on canvas, smoke
plume, glaze drips beyond the pots.

---

### 28. Пивоварня — Brewery (`brewery.png`)

- **Category:** production
- **Footprint:** 1×2 → ~96 px (large)
- **Stage hint:** meadow/river/forest biome leaning. Reads as a small
  beer/wine production hall.

**Prompt:**
> A modest brewery: a long mud-brick hall with a low terracotta tile
> roof, a wide double door of dark cedar, two arched windows. At one
> end of the building a tall wooden mash tun bound in iron hoops
> stands under a small lean-to of reed thatch, beside it two stacked
> oak barrels. A clay drainage gutter runs down the side wall. Warm
> ochre plaster, honey-coloured wood, faint malt-yellow accents.
> Hand-painted isometric 2:1, soft umber outline, upper-left sun,
> transparent background.

**Negative:** *universal +* people drinking, mugs on canvas, smoke,
modern bottles.

---

### 29. Лесопилка — Sawmill (`sawmill.png`)

- **Category:** production
- **Footprint:** 1×2 → ~96 px (large)
- **Stage hint:** forest biome only. No working figures.

**Prompt:**
> A forest sawmill: an open timber-framed shed with a steeply pitched
> shingle roof, inside a long sawing pit with a tall pit-saw resting
> in its frame. Beside the shed a stack of squared timber baulks and a
> pile of fresh sawdust. A water trough fed by a wooden flume on the
> back side suggests a small water-driven mechanism (no waterwheel
> needed). Sun-bleached cedar everywhere, warm sawdust yellow, fresh
> pine cream. Hand-painted isometric 2:1, soft umber outline, upper-
> left sun, transparent background.

**Negative:** *universal +* trees standing on canvas, lumberjack
figure, modern saw blade, water spraying.

---

### 30. Каменоломня — Quarry (`quarry.png`)

- **Category:** production
- **Footprint:** 2×2 → 128 px (large)
- **Stage hint:** stone/mountain biome. Reads as a stepped extraction
  site with hauling gear, not just a pile of rocks.

**Prompt:**
> An open-pit limestone quarry: a stepped rectangular excavation with
> two clean rock terraces of pale dressed stone, a wooden timber
> ramp running down one side. On the rim a heavy timber A-frame
> hoist with rope and a stone block hanging from a hook, a small
> stone-cutter's shed of plank walls with a tile roof, a pile of
> roughed-out blocks awaiting transport, a coil of hemp rope. Pale
> stone, warm sandy earth, honey wood. Hand-painted isometric 2:1,
> soft umber outline, upper-left sun, transparent background.

**Negative:** *universal +* quarry workers, oxen, modern machinery,
explosives, dynamite.

---

### 31. Шахта — Mine (`mine.png`)

- **Category:** production
- **Footprint:** 2×2 → 128 px (large)
- **Stage hint:** mountain biome. Adit-style entrance into a hillock,
  not a deep open pit.

**Prompt:**
> A small mountain mine: a dark arched timber-framed adit cut into a
> sandstone outcrop, heavy cedar door beams supporting the entrance,
> a pair of iron rails (rough not modern) leading a small wooden ore
> cart out of the mouth. Beside the entrance a sorting shed of plank
> walls and a tile roof, a stack of ore baskets, a heap of dark grey
> tailings. A short timber watch platform on stilts at one corner.
> Warm sandstone outcrop, dark mine mouth, weathered cedar. Hand-
> painted isometric 2:1, soft umber outline, upper-left sun,
> transparent background.

**Negative:** *universal +* miners with helmets, electric lights,
modern cart, gold visible in tailings.

---

### 32. Большой склад — Great warehouse (`great_warehouse.png`)

- **Category:** production
- **Footprint:** 3×2 → ~160 px (large)
- **Stage hint:** evolution target of `warehouse` (threshold 3).
  Should clearly read as a major commercial granary.

**Prompt:**
> A large granary-style warehouse: a long rectangular hall of dressed
> sandstone walls with carved string courses, a tile roof with three
> small clerestory vents along the ridge. A row of four wide arched
> loading doors along the front, each with a heavy timber lintel and
> a small stone loading platform. Two tall reed-bundle grain silos
> with conical thatched caps flank the building, painted bands of
> ochre and red on the silo rims. A timber hoist arm with rope above
> one of the doors. Warm honey stone, dry reed silos, faded red trim.
> Hand-painted isometric 2:1, soft umber outline, upper-left sun,
> transparent background.

**Negative:** *universal +* carts, animals, people, scattered grain
on canvas, modern signage.

---

### 33. Мануфактура — Factory (`factory.png`)

- **Category:** production
- **Footprint:** 2×2 → 128 px (large) (catalog) / 3×3 in some specs —
  generate at 1217×1217 to be safe.
- **Stage hint:** "factory" in this setting is a pre-industrial
  manufactory hall, NOT a Victorian smokestack. Keep tone consistent
  with the rest of the city.

**Prompt:**
> A large pre-industrial manufactory: a tall mud-brick hall plastered
> warm ochre with a long row of arched workshop bays open to the
> front, each bay showing a wooden bench and an array of hand tools.
> A central taller block with a tile roof and two small square
> chimneys (no smoke). A side wing for raw material storage with
> double cedar doors. Wooden hoist arm with rope above the central
> entrance, a stone water trough beside the front step. Honey ochre
> walls, terracotta tile, weathered cedar. Hand-painted isometric
> 2:1, soft umber outline, upper-left sun, transparent background.

**Negative:** *universal +* Victorian smokestacks, black smoke,
steam, gears visible, modern conveyor, workers.

---

## Social (10 + temple/obelisk legacy)

### 34. Таверна — Tavern (`tavern.png`)

- **Category:** social
- **Footprint:** 1×1 → 64 px (large flag in catalog)
- **Source PNG:** 1024×1024
- **Stage hint:** earliest social building. Reads cheerful and warm,
  not seedy.

**Prompt:**
> A welcoming neighbourhood tavern: a single-storey mud-brick building
> plastered warm ochre with a low tile roof and a wide open front
> arch. Inside the arch a stone counter with two clay amphorae of
> wine, a hanging cluster of dried herbs from the lintel, a striped
> awning of cream and red reed mat shading the entrance. A wooden
> sign-board on an iron bracket above the awning, blank (no text).
> Two empty stone stools outside. Warm honey walls, deep wine red
> accents, sun-bleached wood. Hand-painted isometric 2:1, soft umber
> outline, upper-left sun, transparent background.

**Negative:** *universal +* drunk patrons, modern beer mugs, text on
the sign, music notes.

---

### 35. Рынок — Market (`market_stage2.png` → `market_stage5.png`)

- **Category:** social
- **Footprint:** 1×1 → 64 px (catalog s1; legacy s2 in some specs)
- **Source PNG:** 1024×1024
- **Stage hint:** four stages, from a single stall to a covered
  market hall. Keep silhouette related across stages.

**Stage 2 prompt — single open stall:**
> A simple market stall: a wooden counter with a slanted reed-mat roof
> on four poles, on the counter neat rows of empty woven baskets and
> two clay amphorae. A small chalkboard hook on the post (no text).
> Sun-bleached wood, dry reed yellow. Hand-painted isometric 2:1, soft
> umber outline, upper-left sun, transparent background.

**Stage 3** — same plot, two adjoining wooden stalls under a continuous
striped cream-and-red reed awning, low mud-brick back wall plastered
ochre, more baskets and a few hanging strings of dried produce (no
specific food readable).

**Stage 4** — same plot, now a small pavilion: low mud-brick walls,
four stone columns carrying a tile roof, a central stone counter with
brass scales, sacks of grain (no spill on canvas), striped awning
extends from the front.

**Stage 5** — same plot at full upgrade: a covered market hall of
dressed sandstone with a wide arched front entry, tile roof with a
central clerestory, painted band of ochre and lapis under the eaves,
a pair of stone steps and two stone planters with laurel.

**Negative (all stages):** *universal +* shoppers, vendors, animals,
text on signs, scattered produce on the ground.

---

### 36. Площадь — Plaza (`plaza.png`)

- **Category:** social
- **Footprint:** 1×1 → 64 px (catalog) / 2×2 in some specs
- **Stage hint:** a public square tile — keep edges clean so multiple
  copies can stitch.

**Prompt:**
> A small civic plaza tile: a square paved with warm tan flagstones
> in a herringbone pattern, a low round central planter of carved
> stone holding a single small cypress tree, four stone benches
> arranged at the corners. A short bronze sundial on a low pedestal
> off-centre. Edges of the tile fade slightly so adjacent tiles
> connect cleanly. Warm pale stone, reed green cypress, dull bronze.
> Hand-painted isometric 2:1, soft umber outline, upper-left sun,
> transparent background.

**Negative:** *universal +* people, fountains spraying water,
buildings around the plaza on the same tile.

---

### 37. Баня — Bathhouse (`bathhouse.png`)

- **Category:** social
- **Footprint:** 2×1 → ~96 px (large)
- **Stage hint:** meadow/river/stone biome. Reads as a public bath, not
  a temple — keep ornament restrained.

**Prompt:**
> A public bathhouse: a long low building of dressed limestone with a
> shallow domed roof of lead-grey plaster, a row of three small arched
> windows along the front, a recessed entry under a striped reed
> awning. A pair of stone steps leads up to the door. A short stone
> chimney at the back, a small carved fountain spout on the side wall
> (dry, no water painted). Painted band of pale lapis under the eaves,
> faded floral motifs. Pale stone, soft blue-grey dome, lapis accents.
> Hand-painted isometric 2:1, soft umber outline, upper-left sun,
> transparent background.

**Negative:** *universal +* bathers, water spraying, steam clouds,
visible pool inside.

---

### 38. Школа — School (`school.png`)

- **Category:** social
- **Footprint:** 2×1 → ~96 px (large)
- **Stage hint:** modest civic building. Reads as a school of scribes /
  early academy, not a modern schoolhouse.

**Prompt:**
> A modest school of scribes: a single-storey sandstone building with
> a tile roof and a colonnaded front porch of four slender stone
> columns. Painted timber ceiling under the porch with faded
> geometric patterns. A wide cedar door painted muted lapis, two
> tall arched windows on the front. Beside the door a small stone
> bench and a clay water jar. A scroll-rack visible through one
> window (no readable text). Warm pale stone, lapis accents, honey
> wood. Hand-painted isometric 2:1, soft umber outline, upper-left
> sun, transparent background.

**Negative:** *universal +* children, modern desks, blackboard, bell
tower, text on signage.

---

### 39. Больница — Hospital (`hospital.png`)

- **Category:** social
- **Footprint:** 2×2 → 128 px (large)
- **Stage hint:** classical asclepeion-style healing house. Calm,
  clean lines.

**Prompt:**
> A small healing house: a square stone building with a low pyramidal
> tile roof and a central skylight oculus, a colonnaded portico of six
> slender stone columns wrapping the front. Pale lime-plastered walls,
> a carved frieze of stylised olive branches under the eaves. A
> central cedar double door painted dark green with bronze handles.
> Stone planters of medicinal herbs flank the entrance. Two stone
> water basins on either side of the portico. Pale honey stone, dark
> herb green, bronze accents. Hand-painted isometric 2:1, soft umber
> outline, upper-left sun, transparent background.

**Negative:** *universal +* red cross, modern medical symbol,
ambulances, people in beds visible.

---

### 40. Форум — Forum (`forum_stage3.png` → `forum_stage5.png`)

- **Category:** social
- **Footprint:** 2×2 → 128 px (catalog) / 3×3 in some specs (large)
- **Source PNG:** 1217×1217
- **Stage hint:** three stages (legacy chain), each a step toward a
  monumental civic forum.

**Stage 3 prompt — open columned platform:**
> A small civic forum: a raised stone platform with a low surrounding
> balustrade, four slender stone columns at the corners carrying a
> light timber pergola roofed with reed mat. A central stone speaker's
> rostrum with two steps. Pale limestone, sun-bleached wood, warm
> stone tones. Hand-painted isometric 2:1, soft umber outline,
> upper-left sun, transparent background.

**Stage 4** — same plot upgraded: the pergola becomes a proper
colonnade on three sides with a low tile-roofed gallery, the back side
now closed with a tall sandstone wall holding a recessed niche with a
painted medallion of a winged sun (no readable text), the rostrum
grown into a curved carved-stone bench.

**Stage 5** — same plot at full upgrade: a small basilica-style forum
with a tile roof and a central low cream-plaster dome, a colonnaded
front portico of six painted-red columns with papyrus capitals, bronze
double doors with stylised reliefs (no readable text), painted bands
of lapis and gold ornament.

**Negative (all stages):** *universal +* crowds, speakers, modern
flags, text panels, statues taller than the building.

---

### 41. Библиотека — Library (`library.png`)

- **Category:** social
- **Footprint:** 2×2 → 128 px (catalog s1 / s2 mix). Generate at 1217².
- **Stage hint:** scroll library, not a Gothic library. Reads as a
  classical study hall.

**Prompt:**
> A small classical library: a single-storey sandstone building with
> a tile roof and a colonnaded front portico of eight slender columns,
> painted timber ceiling under the portico with geometric patterns in
> faded blue and red. Tall cedar double doors painted dark green with
> bronze studs. Two tall narrow windows on each side. Inside, glimpsed
> through the doorway, rows of pigeon-hole shelves filled with scroll
> ends (no readable text). Warm honey stone, lapis trim, bronze
> accents. Hand-painted isometric 2:1, soft umber outline, upper-left
> sun, transparent background.

**Negative:** *universal +* books with spines, modern bookshelves,
people reading, text on the building.

---

### 42. Акведук — Aqueduct (`aqueduct.png`)

- **Category:** social
- **Footprint:** linear (treat as 2×1 tile)
- **Source PNG:** 1024×1024
- **Stage hint:** a single section of arched aqueduct, designed to
  tile along one axis. Ends fade in alpha for seamless joining.

**Prompt:**
> A single section of a Roman-style arched aqueduct: two pale
> sandstone pillars supporting a single semicircular arch, on top of
> the arch a continuous water channel of dressed stone, slightly
> wider than the arch. A thin trickle of clear blue-green water
> visible along the top channel (no spill). Warm honey stone with
> mild weathering, soft moss in the joints near the base. Ends of the
> section fade to alpha so adjacent sections meet cleanly. Hand-
> painted isometric 2:1, soft umber outline, upper-left sun,
> transparent background.

**Negative:** *universal +* water spilling down the arches, full
hillside, people walking on top, modern pipes.

---

### 43. Театр — Theater (`theater.png`)

- **Category:** social
- **Footprint:** 3×2 → ~160 px (large)
- **Source PNG:** 1217×1217 or 1536²
- **Stage hint:** half-classical amphitheatre. Stage building reads
  clearly, seating rises behind it.

**Prompt:**
> A small open-air theatre: a curved tier of stone seating rising in
> three steps wraps the back two-thirds of the footprint, in front a
> rectangular stage building (scenae frons) of dressed sandstone with
> three arched openings, painted bands of red and lapis between them,
> a flat tile roof. A small circular orchestra of pale flagstones
> between the stage and the seating. Carved acroteria on the stage
> roof corners. Honey stone, deep red and lapis accents. Hand-
> painted isometric 2:1, soft umber outline, upper-left sun,
> transparent background.

**Negative:** *universal +* actors on stage, audience, modern stage
curtains, electric lights.

---

### 44. Храм — Temple (legacy social) (`temple_stage4.png`, `temple_stage5.png`)

- **Category:** social (legacy; F-16 moves to religious)
- **Footprint:** 1×1 → 64 px (legacy) / 2×2 in F-16 — generate at
  1024² to be safe.
- **Stage hint:** two stages (legacy chain). Reads as a small precinct
  temple, not a full pyramid complex.

**Stage 4 prompt — modest temple:**
> A small precinct temple: a rectangular sandstone shrine with a flat
> tile roof, a front portico of four slender columns with carved
> lotus capitals painted red and gold. A central cedar door painted
> dark green, two carved relief panels on the side walls (faded
> figures of palm fronds, no readable text). A low stone offering
> table at the foot of the steps. Warm honey stone, deep red and
> gold accents. Hand-painted isometric 2:1, soft umber outline,
> upper-left sun, transparent background.

**Stage 5** — same plot upgraded: deeper portico with six columns,
side walls now carry a richer carved frieze with painted bands of blue
and gold, a small obelisk-shaped finial at each front corner of the
roof, cedar door now bronze-clad, a pair of small carved guardian
lions in pale stone flanks the offering table.

**Negative (both stages):** *universal +* priests, sacrificial smoke,
crowds, crosses, modern religious symbols.

---

### 45. Обелиск — Obelisk (legacy social) (`obelisk.png`)

- **Category:** social (legacy; F-16 moves to religious)
- **Footprint:** 1×1 → 64 px (large)
- **Stage hint:** tall, slender monument. Silhouette is everything.

**Prompt:**
> A tall four-sided obelisk on a stepped square base of dressed
> sandstone, faces carved with faded shallow reliefs of stylised
> reeds and a winged sun disk near the top, traces of red and gold
> paint in the carvings. A small gilded pyramidion at the apex
> catches the sun. Base ringed by a low stone curb with three shallow
> steps. Warm honey stone, dull gold accents, faded red. Hand-
> painted isometric 2:1, soft umber outline, upper-left sun,
> transparent background.

**Negative:** *universal +* text, hieroglyphs that read as words,
surrounding plaza paving that extends beyond the base.

---

## Religious (5)

### 46. Часовня — Chapel (`chapel.png`)

- **Category:** religious
- **Footprint:** 1×1 → 64 px (large)
- **Stage hint:** smallest religious building. Reads as a humble
  wayside shrine, not a church.

**Prompt:**
> A small wayside shrine: a single-cell stone building with a low
> shallow-pitched tile roof and a tiny carved finial at the ridge.
> A pointed-arch doorway open at the front, inside a niche with a
> faded painted medallion of a winged sun (no readable text). A
> single low stone step. A pair of small clay oil lamps on the step,
> unlit. Warm honey stone, faded gold and red in the niche.
> Hand-painted isometric 2:1, soft umber outline, upper-left sun,
> transparent background.

**Negative:** *universal +* crosses, crescents, monks, candles
burning brightly, incense smoke.

---

### 47. Собор — Cathedral (`cathedral.png`)

- **Category:** religious
- **Footprint:** 3×3 → ~192 px (large)
- **Source PNG:** 1536×1536
- **Stage hint:** monumental religious building in the same Pharaonic
  vocabulary — NOT a Gothic cathedral. Think great temple complex.

**Prompt:**
> A monumental religious complex: a tall central sanctuary of dressed
> sandstone with a flat tile roof crowned by a stepped finial, a
> grand front portico of ten massive columns with carved lotus and
> papyrus capitals painted red, blue and gold. Side wings step back
> symmetrically, each with smaller colonnaded loggias. A wide front
> stair of pale limestone leads up to bronze double doors, flanked by
> two tall stylised obelisks rising above the roofline. A frieze of
> painted reliefs runs above the columns, faded but vivid. Warm honey
> stone, deep red and lapis, gold leaf accents. Hand-painted
> isometric 2:1, soft umber outline, upper-left sun, transparent
> background.

**Negative:** *universal +* Gothic arches, spires, stained glass,
crosses, crescents, modern religious symbols.

---

### 48. Пирамида — Pyramid (`pyramid.png`)

- **Category:** religious
- **Footprint:** 4×4 → 256 px (large)
- **Source PNG:** 2048×2048
- **Stage hint:** the largest sprite in the catalog. Detail must hold
  at full zoom-out. Pyramid only — do not paint a surrounding
  necropolis.

**Prompt:**
> A great stepped stone pyramid rising in seven receding tiers of
> dressed warm honey sandstone, each tier with a slight setback and a
> mild weathering wash. At the foot, a small mortuary chapel of
> sandstone with a colonnaded portico of four red columns and a
> bronze double door, flanked by two short stylised obelisks. A wide
> processional ramp of pale flagstones leads up to the chapel from
> the bottom of the canvas. Faded bands of red and lapis painted at
> each tier edge, traces of gold at the apex. Mild sand drift at the
> base. Hand-painted isometric 2:1, soft umber outline, upper-left
> sun, transparent background.

**Negative:** *universal +* sphinxes that overshadow the pyramid,
caravans, full desert dunes painted on the canvas, modern restoration
scaffolding.

---

## Military (3)

### 49. Сторожевая башня — Watchtower (`watchtower.png`)

- **Category:** military
- **Footprint:** 1×1 → 64 px (large)
- **Stage hint:** tall slim silhouette. Reads as a lookout, not a
  fortress.

**Prompt:**
> A slender three-storey watchtower of rough mortared stone with
> small slit windows on each face, narrow at the base and slightly
> narrower at the top. A small open timber gallery near the top with
> a low parapet of plank rails and a single bronze warning bell on
> a wooden frame (no rope visible). A small tile-roofed cap on the
> very top. Heavy cedar door at the base painted faded ochre, bronze
> studs. Warm grey stone, sun-bleached wood, dull bronze. Hand-
> painted isometric 2:1, soft umber outline, upper-left sun,
> transparent background.

**Negative:** *universal +* guards, banners, full city wall extending
beyond footprint, modern searchlight.

---

### 50. Казармы — Barracks (`barracks.png`)

- **Category:** military
- **Footprint:** 2×2 → 128 px (large)
- **Stage hint:** spartan, functional. Reads as living quarters for
  soldiers, not a parade ground.

**Prompt:**
> A military barracks compound: a long rectangular two-storey
> sandstone hall with a low tile roof, a row of small shuttered
> windows on each floor, a wide central double door of cedar
> reinforced with iron bands. A short attached wing on the right
> houses an open weapons rack under a tile lean-to, with rows of
> spears and round wooden shields painted with simple geometric
> emblems. A low stone wall encloses a small front courtyard with a
> stone training post. Warm honey stone, dull bronze fittings, deep
> red shield rims. Hand-painted isometric 2:1, soft umber outline,
> upper-left sun, transparent background.

**Negative:** *universal +* soldiers drilling, horses, modern uniforms,
flags taller than the building.

---

### 51. Верфь — Shipyard (`shipyard.png`)

> Listed as unit #50 in `UnitCatalog.md`; numbered #51 here only because
> the legacy `raw` and `temple/obelisk` placements push the count.

- **Category:** military
- **Footprint:** 3×3 → ~192 px (large)
- **Source PNG:** 1536×1536
- **Stage hint:** river/sea biome. The half-built galley is the focal
  point — keep the slipway clean.

**Prompt:**
> A working shipyard: a wide stone-paved slipway tilted toward the
> front of the tile (toward water), on it a half-built wooden galley
> in cedar planks with its ribs partly exposed, no rigging yet. Behind
> the slipway a long workshop hall of mud brick plastered ochre, with
> a tile roof and a wide front opening showing timber stacks and
> shipwright benches. A tall timber A-frame crane with rope and a
> heavy stone counterweight stands beside the slipway. A coil of
> hemp rope, a stack of squared cedar baulks. Honey wood, ochre
> walls, dull bronze fittings. Hand-painted isometric 2:1, soft umber
> outline, upper-left sun, transparent background, no water painted
> on the canvas.

**Negative:** *universal +* finished sailing ship under sail, water
under the hull, sailors, modern crane, steel hull.

---

# Biomes (7 tiles)

Biome tiles are **seamless 2:1 isometric ground tiles**, painted to read
as a single diamond. The engine repeats them across the grid, so the
edges must blend with copies of themselves: keep brightness even, do not
paint a strong directional feature, and make the diamond corners fade
toward fully transparent for clean blending.

- **Source PNG:** 256×128 (or 512×256 if you want extra detail —
  the engine downsamples to 64×32 / 128×64 tile sizes).
- **File naming:** `tile-<biome>.png`. For the three required variants
  per biome (per `SpriteGenerationRules.md` § 5), suffix with `_a`, `_b`,
  `_c`: `tile-meadow_a.png`, `tile-meadow_b.png`, etc.
- **Folder:** `Sources/CommitPyramid/Resources/Terrain/`.
- **Decor** (trees, bushes, rocks, palms — see § 4.5 in
  `SpriteGenerationRules.md`) goes to
  `Resources/Terrain/decor/<biome>/` as **separate transparent PNGs**,
  not painted onto the ground tile.

The seven biomes correspond to `BiomeKind` in `CityState.swift`:
`meadow, forest, mountain, stone, river, sea, desert`.

---

### Biome 1. Луг — Meadow (`tile-meadow.png`)

- **BiomeKind:** `.meadow`
- **Tile:** 64×32 runtime / generate 256×128

**Prompt:**
> A seamless 2:1 isometric ground tile of sun-warmed meadow grass:
> a soft mix of warm sage and reed green with hints of dry straw
> yellow, very small painted tufts of grass scattered evenly, an
> occasional tiny daisy or red poppy spot. Even brightness across the
> diamond so it tiles cleanly with copies of itself. No strong
> directional feature, no large flowers, no trees. Hand-painted soft
> brushwork, very subtle 1-px umber edge, transparent outside the
> diamond, corners fade to fully transparent.

**Negative:** *universal +* trees, large flowers, paths, fences,
animals, shadows, characters, perspective.

---

### Biome 2. Лес — Forest floor (`tile-forest.png`)

- **BiomeKind:** `.forest`
- **Tile:** 64×32 runtime / generate 256×128
- **Note:** trees themselves are decor sprites — this tile is **only
  the floor**.

**Prompt:**
> A seamless 2:1 isometric ground tile of forest floor: a darker
> moss-and-leaf mix in deep reed green and warm brown, scattered tiny
> painted patches of fallen leaves in ochre and rust, a few small
> pine needle clusters, occasional small moss-covered stones. Even
> brightness so it tiles cleanly. No tree trunks, no full leaves,
> no shadows. Hand-painted soft brushwork, very subtle umber edge,
> diamond corners fade to alpha.

**Negative:** *universal +* trees, tree trunks, large leaves, animals,
mushrooms larger than thumb-tip, paths.

---

### Biome 3. Горы — Mountain (`tile-mountain.png`)

- **BiomeKind:** `.mountain`
- **Tile:** 64×32 runtime / generate 256×128

**Prompt:**
> A seamless 2:1 isometric ground tile of exposed mountain rock: a
> faceted painted texture of pale grey and warm tan stone with fine
> cracks, occasional small darker pebbles, a faint dusting of dry
> earth in the lower facets. Even brightness, no large outcrop, no
> snow, no peaks rising. Hand-painted soft brushwork, very subtle
> umber edge, diamond corners fade to alpha so it tiles cleanly.

**Negative:** *universal +* full mountain peak, snow, ice, climbers,
trees, animals, lava.

---

### Biome 4. Камни — Stone (`tile-stone.png`)

- **BiomeKind:** `.stone`
- **Tile:** 64×32 runtime / generate 256×128

**Prompt:**
> A seamless 2:1 isometric ground tile of stony scree: warm sandy
> earth covered with a scattering of small to medium painted stones
> in pale grey and dusty beige, a few darker rounded pebbles, very
> subtle dry tufts of grass between them. Even brightness so it
> tiles cleanly. Hand-painted soft brushwork, very subtle umber
> edge, diamond corners fade to alpha.

**Negative:** *universal +* one giant boulder, mining tools, ore
veins of gold or gems, animals, paths.

---

### Biome 5. Река — River (`tile-river.png`)

- **BiomeKind:** `.river`
- **Tile:** 64×32 runtime / generate 256×128
- **Note:** flat water tile only; reeds at the bank are decor.

**Prompt:**
> A seamless 2:1 isometric ground tile of calm river water: gentle
> blue-green hand-painted ripples over a slightly darker turquoise
> underlay, very small white highlight flecks, a hint of pale sandy
> bottom showing through in places. Even brightness, no strong flow
> direction, no banks, no reeds. Painted soft brushwork, very subtle
> deeper-blue edge, diamond corners fade to alpha so adjacent tiles
> blend.

**Negative:** *universal +* fish, boats, reeds on the tile, banks,
bridges, foam waves.

---

### Biome 6. Море — Sea (`tile-sea.png`)

- **BiomeKind:** `.sea`
- **Tile:** 64×32 runtime / generate 256×128

**Prompt:**
> A seamless 2:1 isometric ground tile of open sea water: a deeper
> lapis-and-teal mix with hand-painted soft ripples and a few faint
> white highlight flecks suggesting gentle swell, slightly darker
> than the river tile. No horizon, no waves cresting, no foam, no
> shore. Even brightness so it tiles cleanly. Painted soft brushwork,
> very subtle deeper-blue edge, diamond corners fade to alpha.

**Negative:** *universal +* horizon line, sky, sunset, ships, foam
crests, shoreline, fish.

---

### Biome 7. Пустыня — Desert (`tile-desert.png`)

- **BiomeKind:** `.desert`
- **Tile:** 64×32 runtime / generate 256×128

**Prompt:**
> A seamless 2:1 isometric ground tile of warm desert sand: very fine
> hand-painted ripple texture in soft ochre and pale honey, a few
> tiny darker pebbles scattered evenly, the lightest highlights near
> the centre and the very faintest warm shadow at the diamond
> corners. Even brightness so it tiles cleanly. No dunes, no
> footprints, no plants. Hand-painted soft brushwork, very subtle
> warm umber edge, diamond corners fade to alpha.

**Negative:** *universal +* full dunes rising, palm trees, oasis,
caravans, bones, footprints, animals.

---

# Decay variants

The engine ages buildings as their underlying GitHub project goes
inactive. From decay level 1 to 4 the same plot looks progressively
worse, with level 4 = ruin.

Decay sprites are **optional** in the asset pipeline (engine has a code
fallback that desaturates and adds cracks), but PR-ready painted
variants always win.

**Naming:** `<rawValue>_decay<N>.png`, N = 1..4. Generate only stage 5
units (or the highest stage a unit reaches) — earlier stages decay only
visually, the engine does not swap them.

**Universal decay prompt suffix** (append to any unit's stage prompt to
get its decay variant):

> *Same building, same orientation, same isometric footprint, same
> palette family — but in visible decay. Level <N>/4.*
>
> Level 1: hairline cracks in plaster, paint slightly faded, a few
> roof tiles missing, mild sand drift at the base, doors and windows
> still intact.
>
> Level 2: larger cracks running across walls, paint mostly gone in
> patches exposing the mud brick, one shutter hanging off a hinge,
> small pile of fallen tiles beside the wall, weeds growing at the
> threshold.
>
> Level 3: a section of wall partly collapsed showing the interior,
> most of the roof gone (only rafters remain), door missing, sand
> drifted halfway up one wall, dry grass and weeds inside.
>
> Level 4 (ruin): only fragments of two walls still standing, the
> roof fully collapsed inward, foundations exposed, heavy sand
> drift, a single skeletal timber beam leaning at an angle, tiny
> seedlings of dry brush sprouting from the rubble.
>
> Hand-painted isometric 2:1 projection, soft umber outline, upper-
> left warm sun, transparent background, single object centred, no
> shadow, no ground.

**Decay negative prompt:** *universal +* full skeleton/corpse, blood,
modern graffiti, fire actively burning, ghosts.

### Recommended decay sets (priority order)

Generate decay for these units first — they are the most visible in
typical play:

1. `shack_decay1..4.png` (default early-game unit, decays the most)
2. `house_decay1..4.png` (mid-game backbone)
3. `villa_decay1..4.png` (highly visible cap of residential)
4. `warehouse_decay1..4.png` (production sees most decay)
5. `workshop_decay1..4.png`
6. `market_decay1..4.png`
7. `forum_decay1..4.png`
8. `temple_decay1..4.png`
9. `cathedral_decay1..4.png`
10. `pyramid_decay1..4.png` (very satisfying ruin variant)

All other units can keep the engine-side desaturation fallback until
a contributor wants to paint them.

---

# Tips for generators

## Midjourney (v6, v6.1, v7)

- Suggested flags: `--ar 1:1 --style raw --stylize 150 --quality 1 --no perspective --no people --no text --no shadow --no frame`.
- Append the style suffix from the **Style guide** section above to the
  end of every prompt. Midjourney latches onto the last clause hardest.
- Use `--sref` with the project's existing `shack.png` once it lands
  in `Resources/Buildings/` to lock the painterly style across units.
- For 4×4 footprints (pyramid) bump to `--ar 1:1 --quality 2 --v 6.1`
  and upscale x2 manually if the result feels low on micro-detail.

## DALL-E 3 (via ChatGPT or API)

- Lead with one sentence describing the object, then a sentence about
  the projection (2:1 isometric, no perspective, upper-left sun), then
  a sentence about the palette, then the negative list inline.
- DALL-E does not honour a separate negative-prompt field — fold
  negatives into the prompt as "without people, without text…".
- Ask explicitly for "transparent PNG, alpha background" — DALL-E
  occasionally produces a flat-colour background. If that happens,
  re-roll once; if it persists, generate on a uniform lapis-blue
  background and remove it in step "transparency" below.

## SDXL / Flux / Stable Cascade (local)

- Recommended LoRAs for isometric: `isometric-dreams-v2`,
  `pixelhelper-iso`, or `architecture-isometric`. For Flux, the
  base model handles isometry better — skip the LoRA.
- Resolution: 1024×1024 for footprints up to 2×2, 1216×1216 for 2×3
  and 3×3, 1536×1536 or 2048×2048 for 3×3 to 4×4.
- Sampler: DPM++ 2M Karras, 30–40 steps, CFG 5.5–7.
- Use ControlNet `lineart` with a simple isometric box outline as the
  control image if your generator drifts off the 2:1 angle — even a
  hand-drawn diamond helps.
- Use ADetailer (or equivalent) only for very large 4×4 sprites and
  only on architectural detail, never on faces (there should be no
  faces).

## Getting a clean transparent background

If your generator outputs an opaque background:

1. Generate the sprite on a uniform high-saturation background colour
   that does not appear anywhere on the object — pure magenta
   (`#FF00FF`) or true cyan (`#00FFFF`) work well against this
   palette.
2. Run the PNG through `remove.bg`, `BRIA RMBG-1.4`, `rembg` (local
   CLI), or Photoshop's *Select Subject → Layer Mask*.
3. Verify the alpha channel: `file Resources/.../foo.png` should
   report `RGBA, non-interlaced`.
4. Verify no halo: open the file in Preview / Pixelmator and toggle a
   dark background view — any pale fringe should be cleaned with
   *Refine Edge* or `magick mogrify -channel A -blur 0x0.5`.

## Checklist before opening the PR

- [ ] Filename matches `UnitKind.rawValue` exactly (snake_case).
- [ ] PNG is RGBA, fully transparent outside the object.
- [ ] Canvas is square, object centred horizontally, base in the
      lower third.
- [ ] No shadow / no ground patch / no text / no frame.
- [ ] Style matches the project's existing reference (currently
      `shack.png` if present; otherwise the closest already-merged
      sprite in the same category).
- [ ] `swift build` succeeds locally — `resource_bundle_accessor.swift`
      sees the new file.
- [ ] PR title `assets: <rawValue>[_stage<N>]`, PR body includes the
      generator name and the prompt you used (saves time on re-rolls).

---

*Happy building. Pull requests welcome — see also
`concept/SpriteGenerationRules.md` for the full technical spec and
`concept/UnitCatalog.md` for unit metadata.*
