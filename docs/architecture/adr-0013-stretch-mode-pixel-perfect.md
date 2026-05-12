# ADR-0013: Stretch Mode + Pixel-Perfect Rendering

## Status
Accepted (2026-05-12)

## Date
2026-05-12

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.2 |
| **Domain** | Rendering / Viewport / TileMapLayer |
| **Knowledge Risk** | MEDIUM — Godot 4.4 unified `keep_integer` into a `mode + scale_mode` split. Pre-cutoff LLM knowledge will reference `stretch_mode = "keep_integer"`, which is incorrect for 4.6.2. TileMapLayer Y-sort semantics also changed from the legacy TileMap API. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, Godot 4.4 → 4.5 + 4.5 → 4.6 migration guides, art-bible.md, tilemap-renderer GDD, commanders-room-hud GDD |
| **Post-Cutoff APIs Used** | `display/window/stretch/scale_mode = "integer"` (4.4+ — replaces `keep_integer` mode); TileMapLayer Y-sort propagation via parent Node2D `y_sort_enabled` |
| **Verification Required** | VERIFY-1 (stretch mode path in 4.6.2 Project Settings) — closed by this ADR; VERIFY-3 (TileMapLayer Y-sort behaviour in 4.6.2) — closed by this ADR; new VERIFY-13: confirm HiDPI handling on Mac Retina at 480×270 base (does `window/dpi/allow_hidpi = true` produce crisp ×N scaling?); new VERIFY-14: confirm web canvas behaviour at non-integer browser zoom (does `image-rendering: pixelated` in the shell hold up?) |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0003 Autoload Scene Composition (Accepted) — TileMap Renderer node lives under Main Scene; rendering substrate is established at bootstrap. |
| **Enables** | ADR-0011 HUD Rendering Strategy (needs fixed-size viewport for CanvasLayer math); ADR-0012 BitmapFont/FontFile Strategy (needs integer scaling for crisp glyph rendering); all TileMap Renderer + Room System + Agent Character Controller implementation. |
| **Blocks** | Any rendering-touching story until Accepted. Project bootstrap settings cannot be finalised without this ADR. |
| **Ordering Note** | This is the foundation rendering ADR. Should be Accepted **before** ADR-0011 + ADR-0012 (both depend on the viewport contract established here). |

## Context

### Problem Statement

The project is pixel art (8×8 module → 16×16 cell). Without an explicit pixel-perfect rendering contract, the following will break:

1. **Tile edges bleed at non-integer scales.** A 480-wide viewport upscaled by ×2.5 to 1200px produces sub-pixel tile boundaries, visible as 1-pixel cracks between tiles.
2. **Bitmap font glyphs (5×7 px) become unreadable.** Non-integer scaling smudges glyph outlines into anti-aliased blur.
3. **HUD layout shifts unpredictably per window size.** Without a fixed base resolution, the 3×4 slot grid + status panel anchor math has no reference frame.
4. **TileMapLayer Y-sort is ambiguous.** The legacy TileMap had per-layer Y-sort flags; TileMapLayer (the 4.4+ replacement) requires a parent Node2D with Y-sort enabled. Without an explicit decision, agents will render above or below wall tiles inconsistently.
5. **VERIFY-1 + VERIFY-3 remain open.** The exact 4.6.2 project setting paths for stretch mode and Y-sort behaviour are post-cutoff knowledge.

A single foundation ADR must pin: base resolution, stretch mode, aspect handling, Y-sort topology, and the constants `CELL_SIZE` / `MODULE_SIZE`.

### Constraints
- Engine: Godot 4.6.2 / GDScript / 2D Renderer
- Target platforms: PC (Windows/macOS/Linux) at 1920×1080, 2560×1440, 3840×2160; Web (HTML5) at variable browser dimensions
- Pixel art is non-negotiable per art-bible.md — no anti-aliasing, no sub-pixel positioning
- HUD must fit a 3×4 slot grid + status panel + recent-completions strip + 5×7 bitmap font at the base resolution
- World view must show a full one-room bunker (~30×17 visible cells) without scrolling

### Requirements
- Pixel-perfect rendering at every integer scale multiple of base resolution
- Letterbox or pillarbox on non-16:9 displays (no stretching, no cropping)
- Fixed reference frame for HUD anchoring
- Single canonical Y-sort topology for TileMapLayer + agent sprites
- Code constants `CELL_SIZE` + `MODULE_SIZE` defined once, referenced everywhere

## Decision

### TL;DR
Base resolution **480×270**. Stretch mode `viewport` with aspect `keep` and `scale_mode = "integer"`. Y-sort on the Wall layer's parent Node2D only. `CELL_SIZE = 16`, `MODULE_SIZE = 8` as project-wide constants in `tilemap-renderer.gd`. Camera2D zoom locked at 1×; integer scaling does all upscale work.

### Base Resolution: 480×270

Selected after weighing:
- **320×180** — too cramped: HUD chrome (3×4 slot grid + status panel + completions strip) leaves no room for the world view at 5×7 bitmap font
- **480×270** ⭐ — sweet spot: scales to 1920×1080 (×4), 2160p (×8); letterboxes cleanly at 1440p (×5.3 → letterbox to ×5); HUD chrome and world view both fit
- **640×360** — too generous: loses the "tight bunker" claustrophobia aesthetic; pixel art at 16px-tile starts looking blocky-by-accident

480×270 is 16:9. World view occupies ~30×17 cells at 16px/cell with HUD chrome anchored to screen edges.

### Stretch Mode Configuration (Project Settings)

```
display/window/stretch/mode = "viewport"
display/window/stretch/aspect = "keep"
display/window/stretch/scale_mode = "integer"
display/window/size/viewport_width = 480
display/window/size/viewport_height = 270
display/window/size/window_width_override = 1920    # default window
display/window/size/window_height_override = 1080
window/dpi/allow_hidpi = true                       # Mac Retina / Windows scaling
```

**VERIFY-1 closure**: In Godot 4.6.2, the legacy `stretch_mode = "keep_integer"` is gone. The equivalent is the three-setting tuple above — `mode + aspect + scale_mode`. The split was introduced in 4.4. Setting `scale_mode = "integer"` is what guarantees integer-only upscaling.

Tradeoff: `aspect = "keep"` letterboxes on non-16:9 displays. The alternative (`expand`) gives wider viewports on ultra-wide monitors but breaks fixed HUD anchoring. Letterbox accepted as the consistent-layout-first choice.

### Y-Sort Topology

The TileMap Renderer composes 4 TileMapLayer nodes under a single Y-sort-enabled parent Node2D:

```
WorldRoot : Node2D
├── y_sort_enabled = true
│
├── FloorLayer : TileMapLayer        (y_sort_enabled = false — never occludes)
├── AlertOverlayLayer : TileMapLayer (y_sort_enabled = false — full-room tint)
├── WallLayer : TileMapLayer         (y_sort_enabled = true  — Y-sort vs agents)
│   └── (agents are siblings here)
├── Agent[0..N] : CharacterBody2D    (y_sort_enabled inherited from parent)
└── OverlayLayer : TileMapLayer      (y_sort_enabled = false — always-on-top props)
```

**VERIFY-3 closure**: A TileMapLayer's `y_sort_enabled` property only takes effect when the layer's *parent* is a Node2D with `y_sort_enabled = true`. The TileMapLayer alone is not enough — both flags are required. Agents (CharacterBody2D) live as siblings under the same Y-sort-enabled parent and participate in the sort.

Layers:
- **FloorLayer**: tile bodies (no Y-sort needed — always drawn first)
- **AlertOverlayLayer**: full-room amber/sienna tint overlay (no Y-sort)
- **WallLayer**: wall tiles + agents Y-sort together (agents pass behind walls when their Y is less than the wall's Y)
- **OverlayLayer**: props (computers, decoration) drawn above all (no Y-sort — positioned to never visually conflict with agents per art-bible workstation tile rules)

### Project-Wide Constants

```gdscript
# tilemap-renderer.gd (or a shared constants module)
const CELL_SIZE: int = 16    # Godot world units per tile cell
const MODULE_SIZE: int = 8   # art source module size — 4 modules per cell
```

`CELL_SIZE` is the Godot TileSet cell dimension. `MODULE_SIZE` is the art-source unit used in Aseprite. The relationship is fixed (4 modules per cell) and enforced by the asset import pipeline.

A canonical helper lives on TileMap Renderer:

```gdscript
func cell_to_world(cell: Vector2i) -> Vector2:
    return Vector2(cell.x * CELL_SIZE, cell.y * CELL_SIZE)

func world_to_cell(world: Vector2) -> Vector2i:
    return Vector2i(int(world.x) / CELL_SIZE, int(world.y) / CELL_SIZE)
```

**No system may hardcode `16` or `8` for tile math.** All cell↔world conversions go through these helpers.

### Camera2D Configuration

```gdscript
# Main Camera2D
zoom = Vector2(1, 1)                       # no per-camera scaling — viewport handles it
position_smoothing_enabled = false         # pixel-snap on every frame
limit_smoothed = false
anchor_mode = ANCHOR_MODE_DRAG_CENTER
```

The base resolution + integer stretch_mode does all the work. One screen always shows the same world rect regardless of window size — just rendered at a higher integer multiple.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ Display: 1920×1080 (×4 integer scale)                       │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ Viewport: 480×270 (logical resolution)                  │ │
│ │                                                          │ │
│ │  WorldRoot (y_sort_enabled = true)                       │ │
│ │  ├── FloorLayer       (no Y-sort)                        │ │
│ │  ├── AlertOverlayLay  (no Y-sort)                        │ │
│ │  ├── WallLayer        (Y-sort ON — sorts with agents)    │ │
│ │  ├── Agent_0..N       (siblings under WorldRoot)         │ │
│ │  └── OverlayLayer     (no Y-sort — props on top)         │ │
│ │                                                          │ │
│ │  HUD (CanvasLayer — see ADR-0011)                        │ │
│ │  ├── Status panel (anchored TR)                          │ │
│ │  ├── Slot grid (anchored TL)                             │ │
│ │  └── Completions strip (anchored BR)                     │ │
│ └─────────────────────────────────────────────────────────┘ │
│ Letterbox bars on non-16:9 displays                          │
└─────────────────────────────────────────────────────────────┘
```

### Key Interfaces

Registry updates when Accepted:
- `stretch_mode_integer_viewport` api_decision: stretch mode triple `(viewport, keep, integer)` is the project standard
- `pixel_perfect_camera_zoom` api_decision: Camera2D `zoom = Vector2(1, 1)` always
- `cell_world_conversion_via_helpers` api_decision: never hardcode `16` or `8`
- `non_integer_camera_zoom` forbidden_pattern: any Camera2D with non-1.0 zoom value
- `subpixel_tile_position` forbidden_pattern: positioning a Node2D at non-integer pixel coords on a Y-sorted layer
- `hardcoded_cell_size_literal` forbidden_pattern: any literal `16` or `8` in tile math (use `CELL_SIZE` / `MODULE_SIZE`)

## Alternatives Considered

### Alternative A — Stretch mode `viewport` + aspect `expand`

- **Description**: Same viewport + integer scale_mode, but aspect `expand` lets the viewport widen on ultra-wide monitors.
- **Pros**: Uses every pixel; no letterbox bars.
- **Cons**: Breaks fixed HUD anchoring — the slot grid would float in space at 21:9; world reveals more cells on wider monitors (gameplay inconsistency).
- **Rejection Reason**: Consistent layout > using every pixel. Letterbox is honest.

### Alternative B — Stretch mode `canvas_items`

- **Description**: Godot's "pixel-perfect for UI, smooth for world" mode.
- **Pros**: HUD stays crisp at every zoom; world looks smooth.
- **Cons**: World TileMap would also be smoothed, killing the pixel-art aesthetic per art-bible.md.
- **Rejection Reason**: World pixel art is non-negotiable.

### Alternative C — `disabled` stretch + manual Camera2D zoom

- **Description**: No engine-level stretch; Camera2D zoom adjusts to window size manually.
- **Pros**: Full control over scaling logic.
- **Cons**: Foot-gun for non-integer window sizes (sub-pixel tile rendering ruins pixel art); every system must handle the zoom factor in its own coordinate math.
- **Rejection Reason**: Engine integer stretch is the documented solution for this exact use case.

### Alternative D — 320×180 base resolution

- **Description**: Smaller base for more retro feel; scales ×6 to 1080p.
- **Pros**: Truly retro; tile work looks chunky in a good way.
- **Cons**: 3×4 slot grid + status panel + 5×7 font cramps to the point of unusability; world view shrinks to ~20×11 cells which doesn't fit the bunker layout per art-bible.
- **Rejection Reason**: HUD doesn't fit.

### Alternative E — 640×360 base resolution

- **Description**: Larger base for more visible world; scales ×3 to 1080p.
- **Pros**: More world cells visible; HUD has lots of room.
- **Cons**: Loses the claustrophobia aesthetic; pixel art at 16px-tile looks blocky-by-accident; scales awkwardly to 1440p (×4 = 2560×1440 fine, but at 1080p there's only ×3 = 540 letterbox — wasted vertical space).
- **Rejection Reason**: Too generous; breaks aesthetic intent.

### Alternative F — Y-sort enabled on every layer (including Overlay)

- **Description**: Overlay props (computers, decoration) Y-sort with agents too.
- **Pros**: Agent could pass behind a tall prop convincingly.
- **Cons**: Workstation tiles are positioned per art-bible to never visually overlap agents anyway; adds Y-sort cost on a layer that doesn't need it; complicates the sort order mental model.
- **Rejection Reason**: Simpler model wins; art-bible workstation placement avoids the problem.

## Consequences

### Positive
- Closes VERIFY-1 (stretch mode path in 4.6.2)
- Closes VERIFY-3 (TileMapLayer Y-sort behaviour)
- Pixel-perfect at every integer scale; no sub-pixel artifacts possible
- Fixed reference frame for HUD anchoring (480×270)
- Single canonical Y-sort topology — no per-system confusion
- `CELL_SIZE` / `MODULE_SIZE` constants prevent magic-number drift
- Foundation for ADR-0011 (HUD) and ADR-0012 (BitmapFont)

### Negative
- Letterbox/pillarbox on non-16:9 displays (ultra-wide, mobile portrait)
- HiDPI handling on Mac Retina + Windows scaling needs verification (VERIFY-13)
- Web canvas at non-integer browser zoom may need shell-level CSS (`image-rendering: pixelated`) — covered by ADR-0004

### Risks

| Risk | Mitigation |
|---|---|
| Developer hardcodes `16` for tile math, misses `CELL_SIZE` refactor later | `hardcoded_cell_size_literal` forbidden_pattern in registry; lint check; documented in control manifest |
| Camera2D zoom accidentally set non-1.0 in editor | `non_integer_camera_zoom` forbidden_pattern; GUT test asserting Camera2D.zoom == Vector2(1,1) at scene load |
| HiDPI Mac Retina produces blurry scaling (VERIFY-13) | `window/dpi/allow_hidpi = true` is the documented fix; manual smoke on Retina before release |
| Web non-integer browser zoom blurs canvas (VERIFY-14) | `image-rendering: pixelated` in custom HTML shell (per ADR-0004); browser DevTools smoke check |
| Y-sort silently fails because parent Node2D has y_sort_enabled = false | GUT test asserting WorldRoot.y_sort_enabled == true; documented in control manifest |
| Ultra-wide users complain about letterbox | Documented stance: pixel-perfect over edge-to-edge; reconsider post-MVP if material complaints arrive |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `tilemap-renderer.md` | TR-tilemap-001 (TileMapLayer wrapper, CELL_SIZE=16, MODULE_SIZE=8 constants) | Constants pinned at code level; helper functions canonicalised |
| `tilemap-renderer.md` | TR-tilemap-002 (4-layer structure with Y-sort on Wall) | Y-sort topology codified; WallLayer + parent both `y_sort_enabled = true` |
| `tilemap-renderer.md` | TR-tilemap-003 (Single writer rule) | Helpers (`cell_to_world` / `world_to_cell`) live on TileMap Renderer only |
| `tilemap-renderer.md` | TR-tilemap-004 (Room registry via register_room) | Compatible — uses `Rect2i` over CELL_SIZE coords |
| `commanders-room-hud.md` | TR-hud-009 (`keep_integer` stretch mode required for pixel-perfect HUD) | Replaced with 4.6.2-correct `scale_mode = "integer"` |
| `art-bible.md` | 8×8 module → 16×16 cell relationship | Pinned as constants; helpers enforce |

## Performance Implications
- **CPU**: Integer stretch is a single GPU upscale per frame — negligible cost
- **Memory**: Viewport is 480×270 RGBA8 = ~518KB — trivial
- **Load Time**: Zero impact — settings are project-level
- **Network**: N/A
- **Frame Budget**: Y-sort on the Wall+Agent layer is the dominant cost; ≤12 agents + ~50 wall tiles = ~62 nodes to sort = sub-ms

## Migration Plan
No existing code to migrate (pre-production). Settings applied at first project bootstrap. Existing `tilemap-renderer.md` GDD already specifies the layer structure; this ADR codifies it.

## Validation Criteria
- GUT test: `test_stretch_mode_settings` — assert `ProjectSettings.get_setting("display/window/stretch/mode") == "viewport"`, `scale_mode == "integer"`, `aspect == "keep"`
- GUT test: `test_camera_zoom_locked_at_one` — load main scene, assert Camera2D.zoom == Vector2(1, 1)
- GUT test: `test_y_sort_parent_enabled` — assert WorldRoot.y_sort_enabled == true and WallLayer.y_sort_enabled == true
- GUT test: `test_cell_to_world_helper` — assert `cell_to_world(Vector2i(3, 5)) == Vector2(48, 80)`
- Manual smoke at 1920×1080 (×4), 2560×1440 (×5 with letterbox), 1366×768 (×2 with letterbox), Mac Retina (HiDPI), mobile-portrait — confirm letterbox + integer scale + no tile-edge bleeding
- Manual smoke (web build): canvas at 100%, 150%, 200% browser zoom — confirm `image-rendering: pixelated` holds

## Related Decisions
- ADR-0003 Autoload Scene Composition — TileMap Renderer lives under Main Scene
- ADR-0004 Web Export Compatibility — custom HTML shell with `image-rendering: pixelated`
- ADR-0011 HUD Rendering Strategy (planned) — depends on the 480×270 viewport contract
- ADR-0012 BitmapFont/FontFile Strategy (planned) — depends on integer scaling for glyph crispness
- VERIFY-1, VERIFY-3 — closed by this ADR
- New VERIFY-13, VERIFY-14 — opened by this ADR
- TR-tilemap-001 through TR-tilemap-004, TR-hud-009 — covered by this ADR
