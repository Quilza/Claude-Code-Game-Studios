# Agent Character Controller

> **Status**: Designed — pending /design-review in fresh session
> **Author**: Thomas + agents
> **Last Updated**: 2026-05-12 (post-ASM reconciliation per `design/reviews/gdd-cross-review-2026-05-12.md`)
> **Implements Pillar**: Alive by Default (Pillar 1) + Readable at a Glance (Pillar 2)
> **ASM contract**: locked by ADR-0007 + `design/gdd/agent-state-machine.md` (Accepted 2026-05-12).

## Overview

The Agent Character Controller is the visible face of every AI agent in the bunker. It owns the pixel-art character sprite for a single agent: its position in the tile grid, its current animation state, and its response to state changes arriving from the Agent State Machine. When the agent starts working, the character stands up and walks to a terminal. When a task completes, the character reacts. When the connection goes stale, the character freezes. The developer reads the agent's status by watching the character — no text, no charts.

One Agent Character Controller instance exists per configured agent (up to 12). Each instance is responsible for one character only. It listens to two upstream sources: the Room System (which room this agent occupies, where it spawns) and the Agent State Machine (what state the agent is currently in). It drives one output: the `AnimatedSprite2D` node that renders the character on screen.

The Agent Character Controller is the primary proof of Pillar 2 (Readable at a Glance) and the central legibility test of the project: can `idle`, `working`, `completed`, and `errored` be distinguished by animation alone, within three seconds, without text? If this fails, the bunker becomes a chart with a skin on it. This GDD specifies how the four states are animated and defines the legibility test that must be run with placeholder art before full production begins.

*ASM contract reconciled 2026-05-12. Signal interface and state names per ADR-0007 + ASM GDD §3.*

## Player Fantasy

These are *your* agents. Not processes, not threads, not jobs in a queue — small persistent people who live in the bunker and move through it freely. The research agents have a room where they work. The marketing agents have theirs. But the bunker belongs to everyone, and when agents aren't working, they go where they want: through corridors, into rooms that aren't their department, past things that don't have functions but feel right to be near.

When an agent has a task, they're at their workstation, doing the actual job your AI is doing right now. When the task finishes, they react — something small, something human — and then they're off. Where they go is theirs to decide. The bunker has its own ambient life: agents passing through, gathering somewhere without purpose, the bunker breathing in the background while you do other work.

You notice before you notice — a character stands up from their desk and you already know something changed before you consciously look. The rest of the time, you just live alongside them. The bunker is not a dashboard you stare at. It's a place that exists whether you're watching or not.

## Detailed Design

### Core Rules

1. **One instance per agent.** Each configured agent (up to 12) has exactly one Agent Character Controller Node2D instance. Each instance owns exactly one character's world position, animation state, and behavioral logic.

2. **Tile-grid movement.** All characters move on the 16×16px tile grid defined by the TileMap Renderer. Pathfinding uses `NavigationAgent2D` + `NavigationRegion2D`. On arrival, the character snaps to the tile center (`tile_coord * cell_size + Vector2i(8, 8)`).

3. **4-directional sprites with H-flip.** Characters use `AnimatedSprite2D` with walk and idle rows for right, up, and down directions. Left-facing movement reuses the right-facing row with `flip_h = true`. Idle and non-walk animations face the last cardinal direction walked.

4. **Behavioral state machine.** A lightweight GDScript `enum` with four values drives behavior: `WORKING`, `IDLE_WANDERING`, `COMPLETED_BEAT`, `ERRORED`. Each state runs as a `while state == STATE: await …` coroutine. Transitions call a shared `_set_state(new_state)` function that cancels the current coroutine and starts the incoming one. AnimationTree is not used.

5. **Immediate interrupt on WORKING.** If the Agent State Machine signals `WORKING` while the character is in any non-WORKING state, the character immediately abandons its current path and reroutes to its assigned workstation tile. No transition animation — the character simply redirects.

6. **Workstation assignment.** Each agent has exactly one assigned workstation tile in its department room, retrieved from `RoomSystem.get_workstation_for_agent(agent_id)`. Only one agent may occupy a workstation tile at a time (enforced by the WORKING state). Staggered departure prevents collisions when multiple agents in the same room begin working simultaneously: `T_depart = agent_index * STAGGER_BASE + RNG_uniform(0.0, STAGGER_JITTER)`.

7. **Idle wandering with weighted waypoints.** In `IDLE_WANDERING`, the character selects waypoints by weighted random sampling across five categories. Waypoints are filtered to NavigationRegion2D-walkable positions. Characters may share any tile during wandering — tile overlap is valid and desirable during idle (social clustering is intentional).

   | Waypoint Category | Base Weight | Dwell Time |
   |---|---|---|
   | Social (near another agent) | 35 | 5–10s |
   | Ambient prop | 25 | 4–8s |
   | Other department room | 20 | 3–6s |
   | Corridor | 15 | 0–0.5s |
   | Own department room | 5 | 2–4s |

8. **Recency cooldown.** After visiting a waypoint category, a multiplier `C_recency` (between 0.2 and 1.0) is applied to that category's weight to reduce repeat visits. The cooldown decays back to 1.0 over time.

9. **COMPLETED beat.** On the `COMPLETED` signal, the character plays its completion animation at its current world position — no movement to a special tile. After `completed_beat_duration_seconds` (default 2.0s, floor 1.0s), the character enters `IDLE_WANDERING`.

10. **ERRORED behavior.** On the `ERRORED` signal, the character freezes at its current position for `error_timeout_seconds` (default 30s). After the freeze, the character enters resigned idle: `IDLE_WANDERING` with movement speed reduced to `0.6 ×` base and a red `!` indicator floating above the sprite. Resigned idle continues until the error-clear signal is received.

11. **Three-tier connection/error visual distinction.**
    - **Task ERRORED** (Agent State Machine error): red `!` above character + freeze + resigned idle (character behavior changes)
    - **STALE** (Data Bridge stale): amber flicker overlay on character sprite — character continues current behavior uninterrupted
    - **DISCONNECTED** (Data Bridge disconnected): HUD indicator only — no character-level visual change

12. **Prop interaction.** Decorative props that support character visits belong to the `"ambient_prop"` group and expose two properties: a `Marker2D` node named `interaction_point` (the world position the character navigates to) and an exported `StringName` `interaction_animation` (the animation key to play on arrival). The ACC reads these from the scene tree with `get_tree().get_nodes_in_group("ambient_prop")`.

### States and Transitions

| State | Entry | Exit | Character Behavior |
|---|---|---|---|
| `IDLE_WANDERING` | Startup · COMPLETED_BEAT ends · error clears · no new task after WORKING | `WORKING` signal (immediate) | Roams freely: picks weighted-random waypoints, dwells, repeats. Tile overlap allowed. |
| `WORKING` | `WORKING` signal (immediate, from any state) | `COMPLETED` signal → COMPLETED_BEAT · `ERRORED` signal → ERRORED | Walks to assigned workstation tile; plays work loop animation at desk |
| `COMPLETED_BEAT` | `COMPLETED` signal | Beat duration elapsed → IDLE_WANDERING · `WORKING` signal **queued**, not immediate | Plays completion animation at current world position |
| `ERRORED` | `ERRORED` signal | Error-clear signal → IDLE_WANDERING · `WORKING` signal → WORKING (implies clear) | Freeze (30s) → resigned idle (0.6× speed, red `!`) |

**Interrupt priority rules:**
- `WORKING` signal always preempts `IDLE_WANDERING` and `ERRORED` immediately (Pillar 2 — task start must be legible at a glance)
- `WORKING` signal during `COMPLETED_BEAT` is queued and applied when the beat finishes
- Only the Agent State Machine may trigger state changes — the ACC has no self-initiated state exits

**Animation rows (provisional — requires art specification before production):**

| Row key | Used in state |
|---|---|
| `idle_right / idle_up / idle_down` | IDLE_WANDERING (standing still at waypoint) |
| `walk_right / walk_up / walk_down` | IDLE_WANDERING (in transit) + WORKING (walking to workstation) |
| `work` | WORKING (at workstation — looping terminal interaction) |
| `completed` | COMPLETED_BEAT (reaction, e.g. lean-back or fist pump) |
| `errored_freeze` | ERRORED (first 30s — rigid frozen pose) |
| `errored_resigned` | ERRORED (after 30s — slumped walk loop) |

### Interactions with Other Systems

| System | Direction | Interface | Notes |
|---|---|---|---|
| **Agent State Machine** | → ACC | `agent_state_changed(agent_id: String, new_state: String, previous_state: String)` | Primary driver of all behavioral transitions. `new_state` ∈ {`idle`, `working`, `completed`, `errored`} per ADR-0007. Recovery from `errored` arrives via this same signal (no separate error-clear signal — when the next non-error payload arrives, ASM emits `agent_state_changed(id, <new>, "errored")`). |
| **Room System** | → ACC | `RoomSystem.get_workstation_for_agent(agent_id: String) → Vector2i` | Called on spawn and on each `working` entry |
| **Room System** | → ACC | `RoomSystem.get_room(room_id).bounds` (RoomData.bounds: Rect2i) | Used to generate waypoints within room bounds during IDLE_WANDERING |
| **TileMap Renderer** | → ACC | `cell_size = 16` constant; `NavigationRegion2D` baked from tilemap | Tile centers computed from `cell_size`; path requests filtered by NavigationRegion2D |
| **Data Bridge** *(indirect)* | → ACC | Connection state is orthogonal per ADR-0007. ACC does NOT subscribe to `agent_connection_changed` — HUD owns connection-state rendering per ADR-0011. | ACC only renders agent-state (4 states). STALE/DISCONNECTED is a HUD `modulate.a` concern, not a sprite-animation concern. |
| **Audio Manager** | ACC → | `AudioManager.play_sfx("completed_beat", agent_id)` | Called at COMPLETED_BEAT entry |
| **Task Completion Beat** | — | (No direct ACC↔TCB edge.) Per ADR-0005 + ASM Rule 10, `task_completed` is emitted **solely by ASM**. TCB subscribes directly to ASM. ACC plays the completion animation when it receives `agent_state_changed(id, "completed", ...)` — ACC does NOT emit `task_completed`. |
| **Ambient prop nodes** | ACC ↔ | ACC calls `get_tree().get_nodes_in_group("ambient_prop")` | Reads `interaction_point: Marker2D` and `interaction_animation: StringName` from prop scenes |

## Formulas

**F1 — Effective Waypoint Weight**

```
W_effective = W_base × C_recency
```

| Variable | Type | Range | Definition |
|---|---|---|---|
| `W_base` | int | 5–35 | Base weight for the waypoint category (see Core Rule 7 table) |
| `C_recency` | float | 0.2–1.0 | Recency cooldown multiplier. 1.0 = full weight; decays to 0.2 immediately after a visit, then recovers toward 1.0 at `recency_cooldown_decay_per_second` |
| `W_effective` | float | 1.0–35.0 | Weighted value fed into the random sampler |

Selection probability for any category = `W_effective(i) / Σ W_effective(all categories)`

*Example:* Own room recently visited (`C_recency` = 0.2, `W_base` = 5) → `W_effective` = 1.0. Social cluster unvisited (`W_base` = 35) → `W_effective` = 35.0. With all other categories at full weight: P(social) = 35 / (35 + 25 + 20 + 15 + 1) ≈ 36%.

---

**F2 — Dwell Time**

```
T_dwell = lerp(T_min, T_max, RNG_uniform(0.0, 1.0))
```

| Variable | Type | Range | Definition |
|---|---|---|---|
| `T_min` | float | 0.0–5.0s | Minimum dwell time for the waypoint category |
| `T_max` | float | 0.5–10.0s | Maximum dwell time for the waypoint category |
| `RNG_uniform(0.0, 1.0)` | float | 0.0–1.0 | Uniform random draw per visit |
| `T_dwell` | float | T_min–T_max | How long the character waits at the waypoint |

Per-category T_min / T_max (see Tuning Knobs for adjustment):

| Category | T_min | T_max |
|---|---|---|
| Corridor | 0.0s | 0.5s |
| Own department room | 2.0s | 4.0s |
| Other department room | 3.0s | 6.0s |
| Ambient prop | 4.0s | 8.0s |
| Social cluster | 5.0s | 10.0s |

*Example:* Social cluster, RNG = 0.6 → `T_dwell` = lerp(5, 10, 0.6) = 8.0s.

---

**F3 — Staggered Departure**

```
T_depart = agent_index × STAGGER_BASE + RNG_uniform(0.0, STAGGER_JITTER)
```

| Variable | Type | Range | Definition |
|---|---|---|---|
| `agent_index` | int | 0–(N−1) | This agent's position in the room's agent list (0-based) |
| `STAGGER_BASE` | float | 0.2s | Registered constant `stagger_base_seconds` |
| `STAGGER_JITTER` | float | 0.1s | Maximum additional random offset (tuning knob) |
| `T_depart` | float | 0.0–~2.3s | Delay before this agent begins walking to its workstation |

With 12 agents at defaults: max delay = 11 × 0.2 + 0.1 = 2.3s total spread.

*Example:* Agent at index 2, jitter draw = 0.05s → T_depart = 2 × 0.2 + 0.05 = 0.45s.

---

**F4 — Tile Center World Position**

```
world_pos = tile_coord × cell_size + Vector2i(cell_size / 2, cell_size / 2)
```

| Variable | Type | Range | Definition |
|---|---|---|---|
| `tile_coord` | Vector2i | grid bounds | Integer grid coordinate of the target tile |
| `cell_size` | int | 16px | Registered constant from TileMap Renderer |
| `world_pos` | Vector2i | scene bounds | World-space pixel position of the tile center |

*Example:* Tile (3, 2) → world_pos = (3 × 16 + 8, 2 × 16 + 8) = (56, 40).

---

**F5 — Resigned Idle Speed**

```
v_resigned = v_base × ERRORED_SPEED_MULTIPLIER
```

| Variable | Type | Range | Definition |
|---|---|---|---|
| `v_base` | float | >0 px/s | Agent's base walk speed (tuning knob, set on NavigationAgent2D `max_speed`) |
| `ERRORED_SPEED_MULTIPLIER` | float | 0.6 | Fixed multiplier; produces visually distinct slowed movement |
| `v_resigned` | float | 0.6 × v_base | Speed during ERRORED resigned idle state |

*Example:* v_base = 40 px/s → v_resigned = 24 px/s.

## Edge Cases

**EC-1: Agent spawns directly into WORKING state.**
If the first signal received is `WORKING` (no prior IDLE period), the ACC navigates immediately to the assigned workstation tile. No special handling needed — the state machine's WORKING entry is self-contained. The character does not wait for an IDLE period before being allowed to walk to a desk.

**EC-2: Workstation tile is unreachable.**
If `NavigationAgent2D` finds no path to the assigned workstation tile (room not yet connected to the NavigationRegion2D, or the tile is physically blocked), the character logs a warning and stands at its current position. The work animation plays in place. This is a content authoring error — NavigationRegion2D must be baked to cover all workstation tiles before shipping.

**EC-3: No ambient props in scene.**
If `get_tree().get_nodes_in_group("ambient_prop")` returns an empty array, the Ambient Prop waypoint category has zero candidates. The ACC treats it as W_effective = 0 and excludes it from sampling. No crash — the sampler works on whichever categories have candidates.

**EC-4: Only one agent in the scene (no social targets).**
The Social waypoint category requires at least one other agent within range. If no other agents exist (single-agent MVP), Social candidates are empty → W_effective = 0 for Social. The remaining categories absorb the weight. The character still wanders; it just never clusters.

**EC-5: WORKING signal arrives during COMPLETED_BEAT.**
The new task signal is queued — COMPLETED_BEAT runs to completion (full `completed_beat_duration_seconds`). Only then does the character begin walking to the workstation. The beat is never skipped, even under load. Maximum delay before task visually starts: `completed_beat_duration_seconds` (2.0s default).

**EC-6: ERRORED signal arrives while character is mid-walk to workstation.**
The character freezes immediately at its current world position — which may be mid-corridor. This is intentional: the frozen mid-stride character signals something unexpected happened, which is more expressive than freezing only at the desk. The red `!` indicator appears at the frozen world position.

**EC-7: COMPLETED signal before character reaches workstation.**
A task that completes nearly instantly may fire `COMPLETED` before the character arrives at the desk. The completion animation plays at the character's current position (mid-walk or mid-corridor). This is intentional — "Readable at a Glance" requires the beat to play immediately on signal, not to wait for a sprite to reach a tile.

**EC-8: All waypoint categories suppressed by recency simultaneously.**
Cannot happen in normal play — the five categories have different base weights and independent cooldown timers, so at most a few are suppressed at once. As a safety net: if the sum of all `W_effective` values is 0.0 (only possible with a bug), fall back to the character's own department room with T_dwell = T_min.

**EC-9: NavigationRegion2D not baked at scene start.**
If `NavigationAgent2D` has no navigation map, all path requests return empty. All characters stand at their spawn tiles. An error is logged at scene start (`push_error`). This is a critical content error — the NavigationRegion2D bake is a required step in the scene authoring checklist.

**EC-10: Two agents assigned to the same workstation tile (data error).**
Room System is responsible for ensuring each agent has a unique workstation tile. If two agents try to navigate to the same tile simultaneously (Room System data corruption), both will arrive and overlap. The WORKING state does not enforce physical exclusion — that constraint lives in the Room System's `assign_agent` logic. The ACC trusts the tile assignment it receives.

## Dependencies

### Upstream Dependencies *(systems the ACC requires)*

| System | What the ACC Needs | When It's Needed |
|---|---|---|
| **Agent State Machine** | `agent_state_changed(agent_id: String, new_state: String, previous_state: String)` signal per ADR-0007 + ASM GDD §6.2 | Every behavioral state transition. No separate error-clear signal — recovery from `errored` arrives as `agent_state_changed(id, <new>, "errored")`. |
| **Room System** | `get_workstation_for_agent(agent_id: String) → Vector2i`; `get_room(room_id).bounds: Rect2i` (via RoomData) | On spawn (initial assignment); on each `working` entry; during IDLE_WANDERING waypoint generation |
| **TileMap Renderer** | `cell_size` constant (16px); `NavigationRegion2D` baked from the tilemap | Tile center calculation (F4); all path requests |
| **Configuration Loader** | Agent list (agent IDs and their department room assignments) | At startup — determines how many ACC instances are created and which room each belongs to |

### Downstream Dependents *(systems that depend on the ACC)*

| System | What It Needs from ACC | Notes |
|---|---|---|
| **Task Completion Beat** | — (no direct edge) | Per ADR-0005 + ASM Rule 10, `task_completed` is emitted solely by ASM. TCB subscribes directly to ASM. ACC plays the completion animation when it sees `agent_state_changed(id, "completed", ...)` but emits nothing. |
| **Audio Manager** | `play_sfx("completed_beat", agent_id)` call from ACC at COMPLETED_BEAT entry | Audio Manager is a service dependency — it does not depend on ACC, but ACC calls into it |
| **Commander's Room HUD** | Agent status (WORKING / IDLE / ERRORED) per agent | HUD may read agent states directly from Agent State Machine rather than through ACC — exact interface TBD when HUD GDD is authored |

### Lateral Dependencies *(scene-level, not signal-based)*

| System | Relationship | Notes |
|---|---|---|
| **Ambient prop nodes** | ACC reads `"ambient_prop"` group at runtime | Props are passive; ACC polls them. Props do not subscribe to ACC signals. Prop nodes must be in the scene tree before ACC's first IDLE_WANDERING waypoint selection. |
| **Ambient Animation Layer** | No direct dependency — loose spatial sharing | Both ACC and Ambient Animation Layer render into the same tile space. No coordination signal — they operate independently. Authored to avoid visual conflicts. |

### Provisional Dependency Notes

*⚠ Agent State Machine interface is assumed throughout this GDD. When Agent State Machine GDD is authored:*
- Confirm signal name: `agent_state_changed` and its signature
- Confirm state name constants: `IDLE`, `WORKING`, `COMPLETED`, `ERRORED`
- Confirm error-clear signal name (currently TBD)
- Confirm whether STALE / DISCONNECTED are forwarded as sub-states or emitted as separate signals

## Tuning Knobs

### Movement

| Knob | Default | Safe Range | Effect |
|---|---|---|---|
| `v_base` | 40 px/s | 20–80 px/s | Base walk speed for all agents. Too slow: feels sluggish. Too fast: characters pop across rooms. |
| `ERRORED_SPEED_MULTIPLIER` | 0.6 | 0.3–0.8 | Speed during resigned idle. Lower = more visually distressing (intentional). Do not set above 0.9 — legibility is lost. |

### Idle Wandering — Waypoint Weights

| Knob | Default | Safe Range | Effect |
|---|---|---|---|
| `w_social` | 35 | 10–50 | Weight of social clustering. Higher = agents clump more often. Raises Pillar 1 (bunker feels alive). |
| `w_prop` | 25 | 5–40 | Weight of ambient prop interaction. Higher = more character "moments" at decorations. |
| `w_other_room` | 20 | 5–40 | Weight of cross-room wandering. Higher = agents move through more of the bunker. |
| `w_corridor` | 15 | 5–30 | Weight of corridor traversal. Higher = more purposeful cross-bunker movement. |
| `w_own_room` | 5 | 2–20 | Weight of returning to own department. Intentionally low — agents should prefer to roam, not stay home. |

### Idle Wandering — Dwell Times

| Knob | Default (T_min / T_max) | Safe Range | Effect |
|---|---|---|---|
| `dwell_corridor` | 0.0s / 0.5s | 0.0–2.0s | How long a character pauses mid-corridor. Keep short — corridors are for passing through. |
| `dwell_own_room` | 2.0s / 4.0s | 1.0–8.0s | Dwell when agent returns to its own department. |
| `dwell_other_room` | 3.0s / 6.0s | 1.0–12.0s | Dwell when visiting another department. |
| `dwell_prop` | 4.0s / 8.0s | 2.0–15.0s | Dwell while interacting with a decorative prop. Longer = more "character". |
| `dwell_social` | 5.0s / 10.0s | 3.0–20.0s | Dwell when clustering near another agent. Longer = groups linger together. |

### Recency Cooldown

| Knob | Default | Safe Range | Effect |
|---|---|---|---|
| `C_recency_floor` | 0.2 | 0.05–0.5 | Minimum multiplier immediately after visiting a category. Lower = stronger avoidance of repeat visits. |
| `recency_cooldown_decay_per_second` | 0.1 | 0.02–0.5 | Rate at which `C_recency` recovers toward 1.0 per second. Lower = categories stay suppressed longer. |

### ERRORED State

| Knob | Default | Safe Range | Effect |
|---|---|---|---|
| `error_timeout_seconds` | 30.0s | 5.0–60.0s | Freeze duration before resigned idle begins. Registered constant. Too short: freeze isn't read as critical. Too long: it dominates the visual read. |
| `error_indicator_offset_px` | 8px above sprite | 4–16px | Vertical offset of the red `!` indicator above the character sprite. |

### Multi-Agent Workstation

| Knob | Default | Safe Range | Effect |
|---|---|---|---|
| `stagger_base_seconds` | 0.2s | 0.1–0.5s | Per-agent delay multiplier for staggered workstation departure. Registered constant. |
| `stagger_jitter_seconds` | 0.1s | 0.0–0.3s | Max random offset added to each agent's stagger delay. |

### Completion Beat

| Knob | Default | Safe Range | Effect |
|---|---|---|---|
| `completed_beat_duration_seconds` | 2.0s | 1.0–4.0s | Duration of COMPLETED_BEAT state. Registered constant. Must match (or exceed) the completion SFX duration in Audio Manager. Floor is 1.0s — below this, the beat is not legible. |

## Visual/Audio Requirements

### Sprite & Animation

**One sprite sheet per character type.** Sprites follow the Art Bible standard: PNG-8, Aseprite source, row-per-state layout. Characters are 16×16px (one tile cell) or 16×32px (two cells tall) — exact sprite height is an art decision; the ACC only cares that the sprite fits within tile boundaries for pathfinding collision.

**Required animation rows per character:**

| Row Key | Description | Recommended Frame Count | Loop |
|---|---|---|---|
| `idle_right` | Standing, facing right — slight breathing or blink | 2–4 frames | Loop |
| `idle_up` | Standing, facing up | 2–4 frames | Loop |
| `idle_down` | Standing, facing down (toward camera — primary idle direction) | 2–4 frames | Loop |
| `walk_right` | Walking right (left = H-flip of this row) | 4–6 frames | Loop |
| `walk_up` | Walking up (away from camera) | 4–6 frames | Loop |
| `walk_down` | Walking down (toward camera) | 4–6 frames | Loop |
| `work` | Sitting at terminal — looping desk activity | 3–6 frames | Loop |
| `completed` | Reaction beat — e.g. lean-back, fist-pump, swivel | 4–8 frames | Play once |
| `errored_freeze` | Rigid frozen stance — no movement | 1–2 frames | Loop (static) |
| `errored_resigned` | Slumped walk loop — heavier, slower step cycle | 4–6 frames | Loop |

All rows use the same SpriteFrames resource. `walk_left` and `idle_left` are not separate rows — the ACC sets `flip_h = true` on the `AnimatedSprite2D` when facing left.

**Art legibility requirement:** A tester must be able to distinguish `idle`, `working`, `completed`, and `errored_resigned` as four different states within 3 seconds using placeholder pixel art before full art production begins. This test must be run and passed before sprite production is approved. (See Acceptance Criteria.)

### Visual Indicators

**ERRORED red `!` indicator:**
- A small sprite node (separate from the character AnimatedSprite2D) positioned `error_indicator_offset_px` above the character's world position
- Color: `#A03520` (Sienna — the project alert color)
- Drawn above the character's sprite layer (Z-order: character + 1)
- Visible during both freeze phase and resigned idle phase of ERRORED state
- Hidden in all other states

**STALE amber flicker overlay:**
- A `ColorRect` or `CanvasItem` modulate effect applied to the `AnimatedSprite2D` node
- Flickers between the character's normal modulate and `#D4882A80` (Amber, 50% alpha) at approximately 2Hz
- Does not interrupt current animation or behavior
- Applied and removed by the ACC when it receives STALE / STALE-clear sub-states from the Agent State Machine

### Audio

**Completion SFX:** The ACC calls `AudioManager.play_sfx("completed_beat", agent_id)` at the start of COMPLETED_BEAT. The SFX asset must be authored to a duration ≤ `completed_beat_duration_seconds` (2.0s). Audio direction and SFX design are owned by the Audio Director/Audio Manager GDD — the ACC only specifies the call site and the timing constraint.

**No other direct audio.** Movement, idle, and error states produce no character-level SFX in MVP. Ambient audio is owned by the Audio Manager and Ambient Animation Layer.

## Acceptance Criteria

**Legibility (the central mandate)**

1. **Legibility test passes before art production.** A test observer unfamiliar with the system watches a screen showing at least 4 agents in different behavioral states simultaneously (idle wandering, working, completed beat, errored). Without any text labels, the observer correctly identifies all four states within 3 seconds. This test must pass with placeholder pixel art before full sprite production is approved.

2. **States are visually unambiguous.** No two behavioral states share the same animation in the same context. An agent at a desk in `work` and an agent at a desk in `idle` must look different.

**Behavioral State Machine**

3. **Idle wandering is continuous.** An agent with no active tasks wanders indefinitely. It never stands motionless for more than `dwell_social` seconds (maximum 10s at default tuning).

4. **WORKING interrupts immediately.** When `agent_state_changed(id, "WORKING")` fires, the agent begins walking toward its workstation within the same frame (no deferred routing, no animation delay).

5. **COMPLETED beat plays at current position.** On `agent_state_changed(id, "COMPLETED")`, the completed animation plays at the agent's world position at signal time. The character does not move to a special tile before playing the animation.

6. **COMPLETED beat queues WORKING.** If `agent_state_changed(id, "WORKING")` fires during COMPLETED_BEAT, the agent does not transition until the beat finishes. The workstation walk begins immediately after the beat completes.

7. **ERRORED freezes then enters resigned idle.** On `agent_state_changed(id, "ERRORED")`: (a) character freezes at current position, (b) red `!` appears, (c) after `error_timeout_seconds` the character resumes wandering at `v_base × 0.6`, (d) `!` remains visible.

8. **Error clear restores normal behavior.** On error-clear signal: red `!` disappears, speed returns to `v_base`, character re-enters normal `IDLE_WANDERING`.

**Multi-Agent & Pathfinding**

9. **12 agents operate simultaneously at 60fps.** With all 12 agents active and wandering, frame rate does not drop below 60fps on the target PC platform (Win/Mac/Linux). Profile if needed — NavigationAgent2D coroutines are expected to spend most time suspended.

10. **Staggered departure prevents workstation collision.** When all agents in a department room receive `WORKING` simultaneously, no two agents arrive at the same workstation tile at the same time. Each agent navigates to its own assigned tile.

11. **Agents cluster socially during idle.** Over a 5-minute idle observation, agents are observed grouping near each other at least once (social waypoint category fires). No quantitative threshold — a visual observer confirms "agents clearly spend time near each other."

12. **Agents visit other rooms during idle.** Over a 5-minute idle observation, at least one agent is observed in a room that is not its department room.

**Visual Indicators**

13. **STALE flicker does not interrupt behavior.** When the STALE indicator is applied (amber flicker), the character continues its current animation and path without interruption or animation reset.

14. **ERRORED `!` renders above sprite.** The red `!` indicator is visible above the character sprite at all times during ERRORED state, even while the character is mid-walk (resigned idle phase).

**Signal Interface**

15. **ACC plays the completion animation on `agent_state_changed(id, "completed", ...)` but emits no signal.** Per ADR-0005 + ASM Rule 10, `task_completed` is emitted solely by ASM. TCB subscribes directly to ASM. ACC's role on `completed` entry is purely visual: trigger the COMPLETED_BEAT sprite animation. (Reconciled 2026-05-12 — previous draft incorrectly claimed ACC was the emitter.)

16. **ACC calls Audio Manager on COMPLETED entry.** `AudioManager.play_sfx("completed_beat", agent_id)` is called at the start of every COMPLETED_BEAT state, no more than once per COMPLETED signal.

## Open Questions

1. **Agent State Machine signal interface (HIGH — blocks implementation).** This GDD uses provisional signal names: `agent_state_changed(agent_id, new_state)` and an unnamed error-clear signal. The exact names, signatures, and state string constants must be confirmed when the Agent State Machine GDD is authored. Review and update this GDD at that point.

2. **STALE/DISCONNECTED forwarding mechanism.** Does the Agent State Machine forward Data Bridge connection states (STALE, DISCONNECTED) as sub-states on the same `agent_state_changed` signal, or does the ACC need to subscribe to a separate Data Bridge signal? The three-tier visual distinction in Core Rule 11 depends on this. Decide when Agent State Machine GDD is authored.

3. **Sprite height: 16×16 vs 16×32 (MEDIUM — affects art production and pathfinding).** A 16×32 character (two cells tall) is more expressive but requires the NavigationRegion2D to treat the character as a 1×2 footprint for collision avoidance. A 16×16 character fits cleanly in one cell. This is an art direction decision that must be made before NavigationRegion2D is configured and before sprite production begins.

4. **NavigationRegion2D bake strategy.** Is the NavigationRegion2D baked in the Godot editor and saved as a static resource (fast startup, requires re-bake when tilemap changes), or baked at runtime on scene load (always current, small startup cost)? For MVP with a static tilemap, editor-baked is preferred — but this must be confirmed as an architecture decision.

5. **STALE flicker visual implementation.** `ColorRect` overlay, `AnimatedSprite2D` modulate tween, or a shader on the sprite material? The choice affects art pipeline integration and performance. A shader is most flexible but requires godot-shader-specialist input. Decision needed before implementation.

6. **Y-sort interaction with character sprites.** `TileMapLayer` Y-sort (`y_sort_enabled`) determines whether characters visually sort behind tilemap objects (desks, walls). Whether character Node2D instances participate in Y-sorting with TileMapLayer in Godot 4.6.2 needs to be verified (see VERIFY list in active.md — item 3). Incorrect Y-sort order will produce characters rendering on top of walls.
