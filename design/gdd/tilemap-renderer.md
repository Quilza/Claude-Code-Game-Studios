# TileMap Renderer

> **Status**: Designed — pending /design-review
> **Author**: Thomas + Claude
> **Last Updated**: 2026-05-09
> **Implements Pillar**: Pillar 1 — Alive by Default (spatial canvas), Pillar 2 — Readable at a Glance (tile state)

> **TL;DR (Claude: read this, skip the full doc unless you need detail)**
> Node2D in scene tree (not Autoload). 4 TileMapLayer children sharing one TileSet: Floor (z=0), AlertOverlay (z=0.5, hidden by default), Wall (z=1, y_sort on), Overlay (z=2). CELL_SIZE=16px, MODULE_SIZE=8px. API: `tile_to_world(Vector2i) → Vector2` (cell center), `world_to_tile(Vector2) → Vector2i`, `register_room(id, Rect2i)`, `get_room_rect(id) → Rect2i`, `set_alert_state(id, bool)`. Alert state = show/hide AlertOverlay layer (zero per-cell writes). Single writer rule: no system touches TileMapLayer directly. Systems hold `@export var tile_map_renderer: TileMapRenderer`. 17 acceptance criteria.

## Overview

The TileMap Renderer wraps Godot's `TileMapLayer` node to provide a stable, addressable tile grid for all spatial systems in The Situation Room. It owns the tile coordinate system (8×8px logical module, 16×16px TileSet cell), the visual layer structure (floor, wall, overlay), and exposes a runtime API for setting and querying tile state. Other systems — character controllers, ambient animation, alert visuals — never interact with `TileMapLayer` directly; they go through the TileMap Renderer's interface. The bunker's rooms, corridors, and visual state all live in this grid. Without it, nothing in the scene has a location.

## Player Fantasy

The bunker feels *organized*. When the Commander glances at the screen, every agent is somewhere they belong — a room built for them, a floor beneath their feet, walls that frame rather than confuse. Nothing floats, nothing overlaps, nothing looks accidental. The player feels the quiet satisfaction of a well-run command post: this is a real place, staffed by professionals, and every footstep lands on solid ground.

The TileMap Renderer is the reason that feeling holds. Without a consistent, precisely-placed spatial substrate, characters drift and rooms lose their edges. The bunker stops feeling like a *place* and starts feeling like a screensaver — and the "Alive by Default" pillar collapses, because aliveness requires a believable stage.

## Detailed Design

### Core Rules

1. **Layer structure.** TileMap Renderer owns 4 `TileMapLayer` nodes as children of a parent `Node2D`, all sharing one `TileSet` resource:

   | Node name | Z-index | Y-sort | Purpose |
   |-----------|---------|--------|---------|
   | `TileMapLayer_Floor` | 0 | off | Walkable floor tiles — always behind characters |
   | `TileMapLayer_AlertOverlay` | 0.5 | off | Alert visual overlay — hidden by default, shown per-room on alert |
   | `TileMapLayer_Wall` | 1 | **on** | Wall and pillar tiles — sort against character sprites |
   | `TileMapLayer_Overlay` | 2 | off | Decorative ceiling/trim tiles — always in front of characters |

2. **Single writer rule.** No system outside TileMap Renderer calls any method on a `TileMapLayer` node directly. All tile placement, state changes, and coordinate queries go through TileMap Renderer's public API.

3. **Canonical tile constants** (defined once in `TileMapRenderer`, read by all callers):

   | Constant | Value | Unit |
   |----------|-------|------|
   | `CELL_SIZE` | 16 | px — width and height of one TileSet cell |
   | `MODULE_SIZE` | 8 | px — art grid unit (2×2 modules per cell) |
   | `MODULES_PER_CELL` | 2 | derived: `CELL_SIZE / MODULE_SIZE` |

4. **Coordinate system.** Tile `Vector2i(0, 0)` maps to world position `Vector2(0.0, 0.0)`. Column increases rightward; row increases downward (Godot's default). No per-room origin offsets — all coordinates are absolute in the world grid.

5. **`tile_to_world(tile_coord: Vector2i) -> Vector2`** returns the center of the given tile cell in world space: `Vector2(tile_coord.x * 16 + 8, tile_coord.y * 16 + 8)`. Character controllers assign this directly to `sprite.position`; any character-specific visual offset is the caller's responsibility via a local `SPRITE_OFFSET` constant.

6. **`world_to_tile(world_pos: Vector2) -> Vector2i`** returns `Vector2i(floor(world_pos.x / 16), floor(world_pos.y / 16))`.

7. **Room registry.** TileMap Renderer maintains a `Dictionary[StringName, Rect2i]` mapping room IDs to rectangular tile extents. Rooms are registered via `register_room(room_id: StringName, rect: Rect2i)` at scene initialization. The registry is read (never written) by downstream systems via `get_room_rect(room_id: StringName) -> Rect2i`.

   For MVP, one room is pre-registered by the Main Scene Bootstrap: `"commanders_room"`.

8. **Alert state.** `set_alert_state(room_id: StringName, active: bool) -> void` shows or hides the `TileMapLayer_AlertOverlay` tiles that cover the named room's `Rect2i`. The alert overlay is authored in the editor with tiles placed to match the floor footprint of each room. Showing the overlay requires zero per-cell writes at runtime — `visible` is the only flag changed.

9. **Y-sort setup.** `TileMapLayer_Wall` has `y_sort_enabled = true`. Each wall tile's y-sort origin in the TileSet editor is set at the tile's foot (bottom-center), not its top. Character sprite nodes are siblings of `TileMapRenderer` under a common parent that also has `y_sort_enabled = true`. This ensures characters sort correctly in front of and behind wall objects.

10. **Scene placement.** `TileMapRenderer` is a `Node2D` in the main scene tree with `class_name TileMapRenderer`. It is **not** an Autoload. Systems that call its API hold a typed `@export var tile_map_renderer: TileMapRenderer` reference, assigned at scene composition.

---

### States and Transitions

TileMap Renderer has no runtime state machine. It is always-ready after `_ready()` completes. The only per-room state tracked is alert visibility, stored as a `Dictionary[StringName, bool]` keyed by `room_id`:

| Per-room state | Default | Changed by |
|----------------|---------|------------|
| `alert_active` | `false` | `set_alert_state(room_id, true/false)` |

No initialization guard is needed — all four TileMapLayer nodes are authored in the editor and available immediately. `register_room()` calls in `_ready()` populate the room registry before any downstream system runs.

---

### Interactions with Other Systems

| Caller | Method | Data In | Data Out |
|--------|--------|---------|----------|
| Main Scene Bootstrap | `register_room(id, rect)` | `"commanders_room"`, `Rect2i` | — |
| Agent Character Controller | `tile_to_world(coord)` | `Vector2i` tile position | `Vector2` world center |
| Commander Character | `tile_to_world(coord)` | `Vector2i` fixed spawn tile | `Vector2` world center |
| Ambient Animation Layer | `get_room_rect(id)` | room id | `Rect2i` for ambient placement |
| Ambient Animation Layer | `tile_to_world(coord)` | individual tile coords | world positions |
| Room System | `get_room_rect(id)` | room id | `Rect2i` for spatial queries |
| Alert State System | `set_alert_state(id, active)` | room id + bool | — |

TileMap Renderer emits no signals. It is a pure-query / command interface.

## Formulas

**F1 — Tile to World (cell center)**

```
world_pos = Vector2(tile_coord.x × CELL_SIZE + CELL_SIZE / 2,
                    tile_coord.y × CELL_SIZE + CELL_SIZE / 2)
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `tile_coord.x` | int | 0 – map width | Tile column (world origin = column 0) |
| `tile_coord.y` | int | 0 – map height | Tile row (world origin = row 0) |
| `CELL_SIZE` | int | 16 (fixed) | Pixels per TileSet cell |
| `world_pos` | Vector2 | continuous | Center of the tile cell in world space |

**Output range**: unbounded — depends on map size. For a 20×15 tile room: x ∈ [8, 312], y ∈ [8, 232].

**Example**: Tile `(2, 3)` → world `Vector2(2×16+8, 3×16+8)` = `Vector2(40, 56)`.

*Implementation note*: Use `TileMapLayer.map_to_local(tile_coord) + TileMapLayer.global_position` in GDScript. The manual formula defines the intended result; the implementation should call the engine API and verify it matches.

---

**F2 — World to Tile (floor)**

```
tile_coord = Vector2i(floor(world_pos.x / CELL_SIZE),
                      floor(world_pos.y / CELL_SIZE))
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `world_pos.x` | float | ≥ 0.0 | World X position to convert |
| `world_pos.y` | float | ≥ 0.0 | World Y position to convert |
| `CELL_SIZE` | int | 16 (fixed) | Pixels per TileSet cell |
| `tile_coord` | Vector2i | ≥ (0,0) | Tile column and row |

**Output range**: (0, 0) to (map_width−1, map_height−1) for positions within the map. Positions outside registered room rects are valid but will have no authored tile.

**Example**: World `Vector2(40.0, 56.0)` → tile `Vector2i(floor(40/16), floor(56/16))` = `Vector2i(2, 3)`.

---

*Note: No gameplay formulas exist in this system. The two formulas above are pure spatial utilities.*

## Edge Cases

**E1 — `tile_to_world()` called with out-of-bounds tile coordinates**
The formula is applied regardless of whether the coordinate falls inside a registered room. The method returns a valid `Vector2` — it does not clamp or error. The caller is responsible for checking bounds via `get_room_rect()` before calling if the coordinate's validity matters. Out-of-bounds coordinates are not pathological — they may legitimately refer to corridor tiles or unregistered areas.

**E2 — `world_to_tile()` called with a negative world position**
GDScript's `floor()` handles negative inputs correctly (e.g., `floor(-1.0 / 16)` = `−1`). The returned tile coordinate will be negative, which is valid in the coordinate system. No authored tiles will exist there for MVP, but the conversion is defined and safe.

**E3 — `set_alert_state()` called for an unregistered room_id**
If `room_id` is not in the room registry, `get_room_rect()` returns an empty `Rect2i`. `set_alert_state()` logs a `push_warning` and returns without modifying any layer. No crash.

**E4 — `register_room()` called with a room_id that already exists**
The existing entry is overwritten and a `push_warning` is logged noting the re-registration. This handles scene reload or mis-ordered initialization without crashing. The last `register_room()` call for a given ID wins.

**E5 — `set_alert_state()` called redundantly (same state twice)**
If `set_alert_state("commanders_room", true)` is called when alert is already active, the overlay layer's `visible` is set to `true` again — a no-op with negligible cost. No guard needed. Same applies to `false → false`.

**E6 — `TileMapLayer_AlertOverlay` has no authored tiles for a room region**
If the alert overlay layer has no tiles placed in the room's `Rect2i`, `set_alert_state(room_id, true)` makes the layer visible but nothing changes visually. This is a content bug, not a code bug. All registered rooms must have corresponding alert overlay tiles authored in the editor before alert state is exercised.

**E7 — Multiple rooms share overlapping tile rects**
`register_room()` does not validate for overlaps between room rects. If two room rects overlap, `set_alert_state()` on one room may visually affect the shared area. Room rects must not overlap — enforced by content authoring convention, not code.

**E8 — Y-sort produces wrong draw order**
If a character appears in front of a wall it should be behind, the likely causes are: (a) the wall tile's y-sort origin is set incorrectly in the TileSet editor — it should be at the tile's foot, not its top; (b) the character node is not a sibling of `TileMapRenderer` under the y-sort-enabled ancestor — check the scene hierarchy. There is no runtime fallback for y-sort misconfiguration.

## Dependencies

### Upstream (what TileMap Renderer depends on)

**None.** TileMap Renderer is a Foundation-layer system. It initializes from editor-authored tile data and hardcoded room registration in the Main Scene Bootstrap. It has no runtime dependency on any other system.

### Downstream (systems that depend on TileMap Renderer)

| System | Priority | What it needs |
|--------|----------|---------------|
| **Agent Character Controller** | MVP | `tile_to_world()` for sprite position; `get_room_rect()` to validate placement |
| **Ambient Animation Layer** | MVP | `get_room_rect()` for placement region; `tile_to_world()` for individual element positions |
| **Commander Character** | Vertical Slice | `tile_to_world()` for fixed spawn position |
| **Alert State System** | Vertical Slice | `set_alert_state(room_id, active)` to trigger room visual change |
| **Room System** | MVP | `get_room_rect(room_id)` to answer "what tiles does this room occupy?" |
| **Camera/Viewport System** | Vertical Slice | `get_room_rect(room_id)` to determine camera bounds per room |

### Interface Note for Downstream GDDs

All downstream systems must reference TileMap Renderer's public API as defined in Section C. They hold a typed `@export var tile_map_renderer: TileMapRenderer` reference — they do not call engine tile APIs directly.

The `CELL_SIZE` constant (value: 16) is defined in `TileMapRenderer`. Any downstream system that needs this value must read it from `TileMapRenderer.CELL_SIZE`, not hardcode `16` locally.

## Tuning Knobs

| Knob | Constant | Default | Safe Range | Affects |
|------|----------|---------|------------|---------|
| Cell size | `CELL_SIZE` | 16 px | **fixed** | Changing requires re-authoring the entire TileSet and all room rects. Do not tune. |
| Module size | `MODULE_SIZE` | 8 px | **fixed** | Art grid unit. Changing requires re-exporting all tile art. Do not tune. |
| Commander's Room width | *(room rect — tunable)* | 20 tiles | 12 – 30 | Visual density of the room; wider = more ambient detail space |
| Commander's Room height | *(room rect — tunable)* | 15 tiles | 10 – 22 | Vertical room extent; affects camera framing |
| Alert overlay Z-index | `TileMapLayer_AlertOverlay.z_index` | 0.5 | 0.1 – 0.9 | Must stay between floor (0) and wall (1); adjusting affects whether alert overlay renders above floor decals |

**Post-MVP additions** (not tunable until implemented):
- Additional room rects — registered per-room as `Rect2i` values when V1 rooms are added
- Per-room alert overlay tiles — content decision, not a code constant

## Visual/Audio Requirements

*This system is the spatial substrate for all visual output — it produces no visual effects itself. The requirements below govern what must be true of the tile assets authored into the TileSet.*

- **Floor tiles**: Must tile seamlessly at 16×16px. Warm grey palette (W2 Institutional Grey-Warm `#4A4035` or adjacent). Subtle texture variation permitted; no strong focal elements that compete with character sprites.
- **Wall tiles**: Must have a clearly readable silhouette at 16×16px for y-sort to read correctly. Include a defined "foot" point for y-sort origin setting in the TileSet editor.
- **Alert overlay tiles**: Sienna `#A03520` tint or overlay pattern. Must be visually distinct from floor but must not obscure character sprites. Semi-transparent or cross-hatched pattern preferred over a fully opaque fill.
- **Overlay tiles**: Ceiling fixtures, wire runs, vent grilles. Purely decorative. Must not interfere with sprite readability beneath them.
- **No audio requirements.** TileMap Renderer produces no sound.

## UI Requirements

[To be designed]

## Acceptance Criteria

### Group 1 — Initialization

**AC-01** `[unit test]`
Given the main scene loads,
When `TileMapRenderer._ready()` completes,
Then 4 child `TileMapLayer` nodes exist (`Floor`, `AlertOverlay`, `Wall`, `Overlay`) and all share one `TileSet` resource.

**AC-02** `[unit test]`
Given the main scene loads,
When `TileMapRenderer._ready()` completes,
Then `TileMapLayer_Wall.y_sort_enabled == true` and the other three layers have `y_sort_enabled == false`.

**AC-03** `[integration test]`
Given the Main Scene Bootstrap calls `register_room("commanders_room", rect)`,
When `get_room_rect("commanders_room")` is called,
Then it returns the same `Rect2i` that was registered.

---

### Group 2 — Coordinate Conversion

**AC-04** `[unit test]`
When `tile_to_world(Vector2i(0, 0))` is called,
Then the result is `Vector2(8.0, 8.0)` (center of cell at world origin).

**AC-05** `[unit test]`
When `tile_to_world(Vector2i(2, 3))` is called,
Then the result is `Vector2(40.0, 56.0)`.

**AC-06** `[unit test]`
When `world_to_tile(Vector2(40.0, 56.0))` is called,
Then the result is `Vector2i(2, 3)`.

**AC-07** `[unit test]`
When `world_to_tile(Vector2(-1.0, -1.0))` is called,
Then the result is `Vector2i(-1, -1)` (negative coords are valid and do not crash).

**AC-08** `[unit test]`
Given `tile_to_world(coord)` returns `world_pos`,
When `world_to_tile(world_pos)` is called,
Then the result equals `coord` (round-trip identity for cell-center inputs).

---

### Group 3 — Alert State

**AC-09** `[integration test]`
Given `TileMapLayer_AlertOverlay.visible == false` (default),
When `set_alert_state("commanders_room", true)` is called,
Then `TileMapLayer_AlertOverlay.visible == true`.

**AC-10** `[integration test]`
Given alert is active (`visible == true`),
When `set_alert_state("commanders_room", false)` is called,
Then `TileMapLayer_AlertOverlay.visible == false`.

**AC-11** `[unit test]`
When `set_alert_state("nonexistent_room", true)` is called,
Then a `push_warning` is emitted and `TileMapLayer_AlertOverlay.visible` is unchanged.

**AC-12** `[unit test]`
When `set_alert_state("commanders_room", true)` is called twice in a row,
Then no error is emitted and `TileMapLayer_AlertOverlay.visible == true`.

---

### Group 4 — Room Registry

**AC-13** `[unit test]`
When `register_room("room_a", Rect2i(0,0,10,10))` is called followed by `register_room("room_a", Rect2i(5,5,10,10))`,
Then `get_room_rect("room_a")` returns `Rect2i(5,5,10,10)` and a `push_warning` was emitted.

**AC-14** `[unit test]`
When `get_room_rect("unregistered")` is called,
Then it returns an empty `Rect2i` with no crash.

---

### Group 5 — Single Writer Rule

**AC-15** `[code review / static check]`
No file outside `tilemap_renderer.gd` contains a direct call to any `TileMapLayer` method (`set_cell`, `erase_cell`, `map_to_local`, `local_to_map`, etc.).

---

### Group 6 — Y-Sort Visual

**AC-16** `[visual / manual test]`
Given a character sprite at tile `(x, y)` and a wall tile at tile `(x, y−1)`,
When the scene renders,
Then the character appears in front of the wall (character Y > wall foot Y → draws on top).

**AC-17** `[visual / manual test]`
Given a character sprite at tile `(x, y)` and a wall tile at tile `(x, y+1)`,
When the scene renders,
Then the character appears behind the wall (character Y < wall foot Y → draws underneath).

## Open Questions

[To be designed]
