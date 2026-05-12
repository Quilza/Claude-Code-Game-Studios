# Room System

> **Status**: Designed — pending /design-review
> **Author**: Thomas + agents
> **Last Updated**: 2026-05-09
> **Implements Pillar**: Earn Each Room (Pillar 5) + Commander Always Home (Pillar 4)

> **TL;DR (Claude: read this, skip the full doc unless you need detail)**
> Node2D in scene tree (not Autoload). MVP: 2 hardcoded rooms — `COMMANDERS_ROOM_ID = &"commander"` (permanent, no agent) and `AGENT_ROOM_ID = &"agent_01"`. Room data: `RoomData` inner class with `bounds: Rect2i`, `agent_id: StringName`, `spawn_tile: Vector2i`. Registry model — Config Loader pre-resolves assignments; Room System records them. Registers rooms with TileMap Renderer in `_ready()`. Public API: `get_room(id)`, `get_all_room_ids()`, `get_room_for_agent(id)`, `assign_agent()`, `unassign_agent()`. Signals: `agent_assigned`, `agent_unassigned` (NOT emitted during `_ready()`). Room System knows WHERE + WHO; Agent State Machine knows WHAT; HUD assembles both. `spawn_tile` = static (Room System); `current_tile` = dynamic (Character Controller). V1 expansion: loop over get_agents() replaces hardcoded entries; Dictionary structure unchanged. 15 ACs.

## Overview

The Room System is the spatial registry of the Situation Room bunker. It maintains the authoritative record of which rooms exist, which agent occupies each room, and where each room is located in the tile grid. Downstream systems — character controllers, the ambient animation layer, and the HUD — query the Room System as their single source of truth for all spatial and assignment data.

Rooms exist because agents exist. An agent room is created when an agent is assigned to a slot and does not exist before then. This is the expression of Pillar 5 (Earn Each Room): the bunker does not pre-allocate empty rooms waiting to be filled. The spatial layout of the bunker is an accurate reflection of the developer's active agent team, not a template that might be empty.

The MVP Room System manages exactly two rooms: the **Commander's Room** — a permanent, always-present room owned by no agent, always visible per Pillar 4 — and a single **agent room** occupied by the one configured agent. The MVP data contract is designed for this fixed two-room layout only. The multi-room registry (supporting up to 12 agents) is a planned expansion deferred to Vertical Slice, when the Camera/Viewport System and multi-room navigation are designed. This means the MVP implementation uses direct references rather than a dynamic keyed registry — simpler to build, with a clearly flagged expansion boundary.

The Room System's primary output is the **room data contract** — the set of facts about each room that every downstream system queries. Getting this contract right is the most important design decision in this GDD: it is queried by five other systems and any change propagates to all of them.

## Player Fantasy

The bunker is the spatial truth of your real agent operation.

When you provision a new agent, the bunker grows a room to hold them — the floor extends, lights come up, the wing becomes part of the map. This is not a notification or a badge; it is a physical change to a physical space. When an agent leaves, their room is gone with them; the bunker shrinks back to fit exactly what you actually have. The layout at any given moment is an honest answer to the question "what is my operation right now?"

Through every change, the Commander's Room stays lit at the center: your fixed point, the one room the bunker cannot shrink away. It is what makes the contingency of the other rooms feel like design rather than instability — every room is earned, but yours is always home. You are not managing a dashboard; you are watching your operation take physical form.

The experience the Room System must produce: a first-time observer can identify which room is the Commander's Room and which room belongs to the active agent, without any text labels, within three seconds of looking at the bunker. If this test passes, the spatial language is working. If it fails — if the two rooms look equivalent, or if the Commander's Room doesn't read as permanent — something in the visual treatment needs fixing before art production begins.

## Detailed Design

### Core Rules

1. **The Room System is a Node2D in the scene tree — not an Autoload.** It follows the same composition pattern as the TileMap Renderer: all callers hold `@export var room_system: RoomSystem` assigned at scene authoring time. This keeps it inspectable in the editor and avoids initialization order conflicts with TileMap Renderer.

2. **The Room System is a registry, not an allocator.** It records pre-resolved agent-to-room assignments provided by the Configuration Loader. It does not implement assignment logic (first-available room, slot conflict resolution) — that belongs to the Configuration Loader. If a `room_slot` value in config references a room ID the Room System does not recognize, this is a fatal startup assertion — not a silent fallback.

3. **MVP: two hardcoded rooms with well-known IDs.**
   - `COMMANDERS_ROOM_ID = &"commander"` — permanent, always present, never has an agent assigned. `agent_id = &""` always.
   - `AGENT_ROOM_ID = &"agent_01"` — the single agent room in MVP. Occupied by the configured agent if one exists; unoccupied (`agent_id = &""`) if no agent is configured.

   These IDs are constants exported as part of the Room System's public API. Downstream systems reference the constant — they do not hardcode the string `"commander"`.

4. **Room data is typed — not a bare Dictionary.** Each room is represented by a `RoomData` inner class with three fields:
   - `bounds: Rect2i` — the room's bounding box in tile coordinates
   - `agent_ids: Array[StringName]` — which agents belong to this department (`[]` if unoccupied). Rooms are departments; multiple agents of the same role share one room.
   - `workstation_tiles: Array[Vector2i]` — one workstation tile per agent slot in this department. Index-matched to `agent_ids` — `agent_ids[i]` works at `workstation_tiles[i]`.

   Rooms are stored as `Dictionary[StringName, RoomData]` keyed by room ID.

   > **⚠ Revised from v1:** Original design used `agent_id: StringName` (one agent per room) and `spawn_tile: Vector2i`. Revised to `agent_ids: Array[StringName]` and `workstation_tiles: Array[Vector2i]` to support department rooms shared by multiple same-role agents. Agent Character Controller GDD drove this change.

5. **Room System registers rooms with TileMap Renderer during `_ready()`.** For each room, it calls `tile_map_renderer.register_room(room_id, bounds)`. The TileMap Renderer is a dependency — Room System holds `@export var tile_map_renderer: TileMapRenderer`. TileMap Renderer does not know Room System exists.

6. **Initial agent assignment is performed by a bootstrap call, not during `_ready()`.** The Room System's `_ready()` populates the room registry with bounds and spawn tiles only. Agent assignment (`assign_agent(room_id, agent_id)`) is called by the Main Scene Bootstrap after all nodes have completed `_ready()`, to avoid signal emission before downstream systems have connected. Downstream systems read initial state via direct getter calls in their own `_ready()`; signals carry subsequent changes only.

7. **`spawn_tile` is a static room fact. Current character position is NOT tracked by the Room System.** The Agent Character Controller initializes character position from `spawn_tile` at startup and owns `current_tile` thereafter. The Room System is never updated when a character moves.

8. **The Commander's Room knows nothing about the Commander Character.** The Room System holds the Commander's Room's bounds and spawn tile. The Commander Character system reads these at startup to place the character. The Room System does not know a Commander Character exists, does not receive position updates from it, and does not manage its behavior.

---

### States and Transitions

Each room has one assignment state:

| State | Condition | Notes |
|---|---|---|
| `UNOCCUPIED` | `agent_ids.is_empty()` | Commander's Room is always UNOCCUPIED. Department rooms are UNOCCUPIED if no agents of that role are configured. |
| `OCCUPIED` | `agent_ids.size() > 0` | One or more agents assigned to this department. |

| From | Event | To | Signal emitted |
|---|---|---|---|
| `UNOCCUPIED` | `assign_agent(room_id, agent_id)` called | `OCCUPIED` | `agent_assigned(room_id, agent_id)` |
| `OCCUPIED` | `assign_agent(room_id, agent_id)` called | `OCCUPIED` (more agents) | `agent_assigned(room_id, agent_id)` |
| `OCCUPIED` | `unassign_agent(room_id, agent_id)` called, agents remain | `OCCUPIED` (fewer agents) | `agent_unassigned(room_id, agent_id)` |
| `OCCUPIED` | `unassign_agent(room_id, agent_id)` called, last agent | `UNOCCUPIED` | `agent_unassigned(room_id, agent_id)` |
| Commander's Room | — | Always `UNOCCUPIED` | Never transitions |

In MVP, only `AGENT_ROOM_ID` transitions. The Commander's Room always remains UNOCCUPIED.

---

### Interactions with Other Systems

**Configuration Loader → Room System (upstream, read at startup):**
- `ConfigurationLoader.get_agents()` → `Array[Dictionary]`: read by the bootstrap to populate `agent_id` assignments

**Room System → TileMap Renderer (registers rooms):**
- `tile_map_renderer.register_room(room_id: StringName, bounds: Rect2i)` called in `_ready()` for each room

**Room System public API (queried by downstream systems):**
- `get_room(room_id: StringName) → RoomData` — primary query: returns bounds, agent_id, spawn_tile
- `get_all_room_ids() → Array[StringName]` — returns all known room IDs (HUD, Camera enumerate rooms via this)
- `get_room_for_agent(agent_id: StringName) → StringName` — returns the room_id for an agent's department (`&""` if not assigned)
- `get_workstation_for_agent(agent_id: StringName) → Vector2i` — returns this agent's assigned workstation tile within their department room
- `assign_agent(room_id: StringName, agent_id: StringName)` — adds agent to department, assigns next available workstation tile, emits `agent_assigned`
- `unassign_agent(room_id: StringName, agent_id: StringName)` — removes agent from department, frees workstation slot, emits `agent_unassigned`
- Signal `agent_assigned(room_id: StringName, agent_id: StringName)`
- Signal `agent_unassigned(room_id: StringName, agent_id: StringName)`

**System boundary — Room System vs. Agent State Machine:**
Room System knows WHERE (bounds, spawn_tile) and WHO (agent_id). Agent State Machine knows WHAT (idle/working/completed/errored). The HUD assembles both by making separate getter calls to each system. Neither system knows the other exists.

---

### V1 Expansion Boundary

The MVP populates the room registry with two hardcoded `RoomData` entries. **V1 expansion replaces the hardcoded entries with a loop over `ConfigurationLoader.get_agents()`** — one entry per configured agent, plus the permanent Commander's Room. The `Dictionary[StringName, RoomData]` structure, the `RoomData` inner class, and all downstream query interfaces are unchanged. Only the population loop changes.

**Prerequisite:** Camera/Viewport System GDD must be designed first — multi-room spatial layout determines what the V1 room `bounds` constants will be.

## Formulas

The Room System contains no runtime formulas. All spatial math (tile-to-world coordinate conversion) is delegated to the TileMap Renderer via `tile_map_renderer.tile_to_world(Vector2i)`.

The only derived values are the room bounds constants, which are design decisions expressed as tile-coordinate rectangles — not calculated at runtime:

```
COMMANDERS_ROOM_BOUNDS: Rect2i   →  position and size in tile units (see Tuning Knobs)
COMMANDERS_ROOM_SPAWN:  Vector2i →  a tile within COMMANDERS_ROOM_BOUNDS
AGENT_ROOM_BOUNDS:      Rect2i   →  position and size in tile units (see Tuning Knobs)
AGENT_ROOM_SPAWN:       Vector2i →  a tile within AGENT_ROOM_BOUNDS
```

**Invariant (startup assertion):** `spawn_tile` must always fall within the `bounds` Rect2i of its room. If `bounds` is changed without updating `spawn_tile`, the assertion will catch the mismatch during development.

## Edge Cases

**E1: No agent is configured (empty agents array).**
Both rooms initialize as UNOCCUPIED. `assign_agent()` is never called for the agent room. The bunker renders with the Commander's Room present and the agent room empty. No crash. The HUD displays an empty agent panel. In MVP this is the "no config yet" state and should be visually distinguishable from an occupied room.

**E2: Configuration Loader is not in `READY` state when bootstrap runs.**
The bootstrap only calls `assign_agent()` after all nodes are ready. If the Configuration Loader is in a permanent error state, the bootstrap does not assign — all rooms initialize as UNOCCUPIED. The Room System is in a valid but empty state; no crash.

**E3: `assign_agent()` is called with an unknown room_id.**
Fatal startup assertion: `assert(room_id in _rooms, "assign_agent: unknown room_id")`. This is a programmer error — the bootstrap is referencing a room that was never registered. Loud fail during development. Cannot occur in MVP with only two well-known room IDs.

**E4: `assign_agent()` is called on a room that is already OCCUPIED.**
Log a warning, emit `agent_unassigned` for the old agent_id, then emit `agent_assigned` for the new one. Overwrites silently with a visible warning. Prevents data loss in edge cases without crashing.

**E5: `unassign_agent()` is called on an already UNOCCUPIED room.**
No-op with a warning log. No signal emitted. This is a programmer error; the warning makes it visible without crashing.

**E6: `unassign_agent()` is called on the Commander's Room.**
Fatal startup assertion: `assert(room_id != COMMANDERS_ROOM_ID, "Commander's Room cannot be unassigned")`. The Commander's Room is permanently UNOCCUPIED and must never enter the assignment state machine.

**E7: `spawn_tile` is outside the room's `bounds` Rect2i.**
Detected at `_ready()` as a startup assertion: `assert(bounds.has_point(spawn_tile), "spawn_tile is outside room bounds")`. Always a configuration error — the hardcoded constants are mismatched. Should never reach production.

**E8: `get_room()` is called with an unknown room_id.**
Return `null`. Downstream systems must null-check the return value. This is the expected path during development when room IDs are being iterated or when a V1 system queries before all rooms are registered. Log a warning.

**E9: Two rooms have overlapping `bounds`.**
Not validated at runtime in MVP — only two hardcoded rooms; overlap is prevented at design time. Flag for V1: when rooms are loaded dynamically, an overlap check must be added to `_ready()` to catch authoring errors early.

## Dependencies

**Upstream (Room System depends on):**

| System | What Room System needs | Status |
|---|---|---|
| Configuration Loader | `get_agents()` → agent list with `id` and `room_slot` (read by bootstrap at startup) | ✅ Designed |
| TileMap Renderer | `register_room(room_id, bounds)` — called by Room System in `_ready()` | ✅ Designed |

**Downstream (depends on Room System):**

| System | What it needs | Status |
|---|---|---|
| Agent Character Controller | `get_room(room_id)` → bounds, spawn_tile; `agent_assigned` / `agent_unassigned` signals | ⬜ Not Started |
| Commander Character | `get_room(COMMANDERS_ROOM_ID)` → bounds, spawn_tile | ⬜ Not Started |
| Ambient Animation Layer | `get_room(room_id)` → bounds (ambient element placement) | ⬜ Not Started |
| Commander's Room HUD | `get_all_room_ids()`, `get_room(room_id)` → spatial data; combines with Agent State Machine for status | ⬜ Not Started |
| History/Activity Log | `get_room(room_id)` → room context for log entries | ⬜ Not Started |
| Camera/Viewport System | `get_all_room_ids()`, `get_room(room_id)` → bounds for multi-room framing (V1 only) | ⬜ Not Started |

**Note on TileMap Renderer GDD:** That GDD states "Main Scene Bootstrap" calls `register_room()`. This GDD supersedes that note — Room System is the authoritative caller of `register_room()` in `_ready()`. Update the TileMap Renderer GDD at next review.

**Bidirectional note:** The Configuration Loader GDD already references Room System as a downstream consumer of its Layout data class. No update required.

## Tuning Knobs

| Knob | MVP Value | Notes |
|---|---|---|
| `COMMANDERS_ROOM_BOUNDS` | `Rect2i(0, 0, 10, 8)` | Position and size of the Commander's Room in tile units. `x, y` = top-left tile; `width, height` = room size. **Placeholder — final layout set during TileMap art production.** |
| `COMMANDERS_ROOM_SPAWN` | `Vector2i(2, 4)` | Tile where the Commander character initially stands. Must be inside `COMMANDERS_ROOM_BOUNDS`. Placeholder. |
| `AGENT_ROOM_BOUNDS` | `Rect2i(12, 0, 10, 8)` | Position and size of the agent room in tile units. Adjacent to Commander's Room with a 2-tile gap (corridor). Placeholder. |
| `AGENT_ROOM_SPAWN` | `Vector2i(14, 4)` | Tile where the agent character initially appears. Must be inside `AGENT_ROOM_BOUNDS`. Placeholder. |

**Safe ranges:** All `Rect2i` values must produce rooms that:
- Fit within the TileMapLayer tile sheet dimensions (verified during art production)
- Do not overlap with each other or with corridor/wall tiles
- Are large enough for meaningful ambient animation (minimum 6×6 tiles recommended)

**Who updates these:** Level designer / art director sets final values after the first TileMap tileset is produced. These constants are the single source of truth — changing them here automatically updates character placement, camera framing, and ambient element bounds for all downstream systems.

**V1 note:** When V1 adds more rooms, additional `Rect2i` constants are added here. The Camera/Viewport System GDD specifies the overall bunker layout that determines V1 room positions.

## Visual/Audio Requirements

The Room System produces no direct visual or audio output. All visual expressions of room state are owned by downstream systems:

- **Room "lighting up"** when an agent is assigned → TileMap Renderer (tile state) and Ambient Animation Layer (ambient elements activating)
- **Room going dark** when an agent is unassigned → same ownership
- **Commander's Room visual permanence** → TileMap art and Commander Character system
- **3-second legibility test** (Commander's Room vs. agent room identifiable at a glance) → validated by art direction and level design

The Room System's only obligation is to emit the correct signals (`agent_assigned`, `agent_unassigned`) at the correct times. The visual response to those signals belongs entirely to the systems that receive them.

## Acceptance Criteria

### Registry Correctness

- [ ] **AC-01** `get_room(COMMANDERS_ROOM_ID)` returns a valid `RoomData` with `agent_id == &""` at all times, including before any `assign_agent()` calls.
- [ ] **AC-02** `get_room(AGENT_ROOM_ID)` returns `agent_id == &""` before `assign_agent()` is called, and the correct agent_id after.
- [ ] **AC-03** `get_all_room_ids()` returns exactly 2 entries in MVP: `[COMMANDERS_ROOM_ID, AGENT_ROOM_ID]`.
- [ ] **AC-04** `get_room_for_agent(agent_id)` returns `AGENT_ROOM_ID` after the agent is assigned, and `&""` before or after unassignment.
- [ ] **AC-05** `get_room()` called with an unknown room_id returns `null` and logs a warning. No crash.

### Assignment Lifecycle

- [ ] **AC-06** Calling `assign_agent(AGENT_ROOM_ID, agent_id)` updates `room.agent_id` and emits `agent_assigned(AGENT_ROOM_ID, agent_id)`.
- [ ] **AC-07** Calling `unassign_agent(AGENT_ROOM_ID)` clears `room.agent_id` to `&""` and emits `agent_unassigned(AGENT_ROOM_ID, old_agent_id)`.
- [ ] **AC-08** `assign_agent()` called on the Commander's Room fails with a fatal assertion in debug builds.
- [ ] **AC-09** `assign_agent()` on an already-OCCUPIED room emits `agent_unassigned` for the displaced agent before emitting `agent_assigned` for the new one.
- [ ] **AC-10** No signals are emitted during `_ready()`. A downstream system connected to `agent_assigned` after the scene is fully ready receives the signal correctly when the bootstrap calls `assign_agent()`.

### TileMap Integration

- [ ] **AC-11** After Room System `_ready()` completes, `tile_map_renderer.get_room_rect(COMMANDERS_ROOM_ID)` returns `COMMANDERS_ROOM_BOUNDS`.
- [ ] **AC-12** After Room System `_ready()` completes, `tile_map_renderer.get_room_rect(AGENT_ROOM_ID)` returns `AGENT_ROOM_BOUNDS`.

### Spatial Integrity

- [ ] **AC-13** Both `spawn_tile` values fall within their respective `bounds` Rect2i. Startup assertion passes in debug builds.
- [ ] **AC-14** Neither room's `bounds` overlaps the other's bounds.

### Legibility (Design Test — evaluated after art is applied)

- [ ] **AC-15** A first-time observer can identify which room is the Commander's Room and which is the agent room, without text labels, within 3 seconds. Passes when the Commander's Room reads as permanent/distinct and the agent room reads as occupied/active.

## Open Questions

1. **Exact room bounds** — The tuning knob values (`Rect2i(0, 0, 10, 8)` etc.) are placeholders. Final values depend on the TileMap tileset layout, which is determined during art production. Lock before the Agent Character Controller GDD specifies character placement.

2. **Corridor tile ownership** — The 2-tile gap between rooms (MVP layout assumption) is not owned by either room's `bounds`. Who owns the corridor tiles for collision and ambient purposes? Flag for the TileMap Renderer and Ambient Animation Layer GDDs.

3. **V1 room layout** — When multi-room support is added, how are rooms arranged spatially? (Linear row? L-shape? Grid?) This is a Camera/Viewport System + level design decision. It must be resolved before V1 `bounds` constants can be set.

4. **Room unlock animation** — When an agent is assigned and a room "lights up," who owns the transition animation? The GDD delegates to Ambient Animation Layer, but the TileMap Renderer may also be involved (floor tile state change). This boundary needs to be clarified when both downstream GDDs are written.
