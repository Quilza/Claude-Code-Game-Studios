# Ambient Animation Layer

> **Status**: Designed — pending /design-review in fresh session
> **Author**: Thomas + agents
> **Last Updated**: 2026-05-09
> **Implements Pillar**: Alive by Default (Pillar 1)
> **⚠ PROVISIONAL**: Agent State Machine assumptions used throughout. Review this GDD after Agent State Machine GDD is complete.

## Overview

The Ambient Animation Layer owns all non-agent environmental animations in the bunker: the blinking status lights, spinning ventilation fans, scrolling terminal screens, flickering indicators, and any other decorative element that moves without being a character. It is the background machinery that keeps the bunker alive between task events — the persistent motion that plays whether or not any agent is working, completing, or errored.

One Ambient Animation Layer instance exists for the entire scene. It initializes a set of ambient prop controllers — one per registered decorative element — and drives their looping animation states. A subset of props are **state-sensitive**: they receive agent state change signals from the Agent State Machine and adjust their animation in response (a room's indicator lights might pulse faster when an agent is working, or flicker erratically when an agent errors). All other props are **always-on**: they loop indefinitely regardless of agent state.

The Ambient Animation Layer does not own character animations (those belong to the Agent Character Controller), tile state (TileMap Renderer), alert overlays (Alert State System), or task completion visuals (Task Completion Beat). It owns exactly one thing: the environmental motion of the bunker's decorative layer.

*⚠ Provisional: Agent State Machine GDD is not yet designed. The signal interface for state-sensitive props is assumed. Review this GDD after Agent State Machine GDD is complete.*

## Player Fantasy

The bunker is humming when you arrive, and it keeps humming when you look away. Status lights blink through their own private rhythms. A fan somewhere completes a slow rotation. A terminal in the corner scrolls through readouts no one asked it for. None of this is performing for you — it was happening before you opened the window, and it will keep happening after you close it.

This is what makes the bunker a place rather than a dashboard. A dashboard is dead between interactions. The Ambient Animation Layer is the reason the bunker isn't. Every loop is quiet enough to ignore and detailed enough to reward a second look: a light that pulses slightly out of sync with the others, a vent that takes just a little longer than expected to complete its cycle. The player isn't watching the bunker — they're *with* it. They feel, without consciously noticing, that the room would keep running if they walked away. And that it's quietly glad they came back.

*The design test for every ambient animation: does it play whether or not the player is paying attention to it? Does it reward a glance without demanding one? If it needs to be noticed to matter, it doesn't belong in this layer.*

## Detailed Design

### Core Rules

1. **One instance for the entire scene.** A single Ambient Animation Layer Node2D manages all ambient props in all rooms. It is a Node2D in the scene tree — not an Autoload. It has no cross-scene responsibilities and provides no data to other systems.

2. **Props are editor-placed scene instances, not runtime-spawned.** Each ambient prop is a `.tscn` instance placed by a level designer in the relevant room in the editor. The Ambient Animation Layer discovers them at startup by scanning groups — it does not build a spawn table or instantiate anything at runtime. This keeps the art pipeline straightforward at MVP scale (10–20 props).

3. **Group-based discovery.** Every ambient prop scene root belongs to the `"ambient_props"` Godot group. State-sensitive props also belong to a room-scoped group (e.g., `"ambient_room_commander"`, `"ambient_room_agent_01"`). The Ambient Animation Layer scans `get_tree().get_nodes_in_group(&"ambient_props")` in `_ready()` to build its prop list.

4. **AnimationPlayer drives all prop animations.** Each prop has an `AnimationPlayer` node with looping animation resources. No `AnimatedSprite2D` and no per-frame `_process()` code on props — the engine animation server handles playback. For a simple blink, one animation resource with two keyframes on `modulate:a` (or `visible`) is sufficient.

5. **Phase offset on startup for lived-in feel.** Every prop calls `anim_player.seek(phase_offset, true)` in its `_ready()`, where `phase_offset = randf_range(0.0, anim_player.current_animation_length)`. The random seed is derived from the node path hash (`hash(node.get_path()) % (2**31)`) so phase offsets are **deterministic across sessions** — the bunker looks the same every time it opens. The bunker was always running.

6. **Two prop classes — always-on and state-sensitive.** Always-on props loop without interruption forever. State-sensitive props implement `set_ambient_state(new_state: StringName) -> void` and transition to a different animation variant when called. All state-sensitive props use a `class_name AmbientProp` base class with an `@export var watched_room_id: StringName` field.

7. **Ambient Animation Layer is the single signal subscriber.** The Ambient Animation Layer subscribes to `agent_state_changed(agent_id, new_state)` (provisional). On receiving a state change, it looks up which room the agent belongs to via `RoomSystem.get_room_for_agent(agent_id)`, then calls `set_ambient_state(new_state)` on every prop in that room's group. Props do not subscribe directly to Agent State Machine signals.

8. **State transitions cross-fade, not snap.** When `set_ambient_state()` is called, props transition their animation speed and modulate over `ambient_state_transition_seconds` (0.3s default), using a `Tween`. This prevents the ambient layer from calling attention to itself during state changes — the character animation leads; the props follow quietly.

9. **Brightness-motion budget rule.** A prop may be bright OR fast-cycling, never both simultaneously. Always-on props in their default state must not use agent palette colors (amber `#D4882A`, green `#4A9A52`) — those hues are reserved for state-triggered responses so the eye learns to treat them as signals. Fan blades may spin faster but must use warm grey (desaturated), not amber.

10. **MVP prop counts.** Commander's Room: 12 props. Agent Room: 8 props per room. The bunker has at least 3–4 props mid-cycle at any moment for continuous peripheral motion.

### States and Transitions

State-sensitive props change their animation variant per agent state. These are prop-level states, not a system-level state machine.

| Agent State | Status Indicator Light | Progress Ticker | Transition |
|---|---|---|---|
| `IDLE` | Slow pulse, 4.0s cycle, dim amber | Slow constant scroll | Baseline — default state |
| `WORKING` | Medium pulse, 1.5s cycle, full amber | Fast scroll (+50% rate) | 0.3s cross-fade |
| `COMPLETED` | Single 0.5s bright flash → returns to IDLE | Brief burst → stops → resumes scroll | Matches `completed_beat_duration_seconds` (2.0s) then resets |
| `ERRORED` | Irregular pulse (on 0.4s / off 0.15s / on 0.2s / off 0.4s), red-amber mix, persists | Ticker halts completely | 0.3s to reach irregular state; cleared only on error-clear signal |
| `DISCONNECTED` *(provisional)* | Light off entirely | Ticker off entirely | Absence is the message |

**ERRORED irregularity rule:** the indicator light does NOT use a regular loop. The arrhythmic on/off pattern reads as malfunction without being epileptically fast. Do not convert this to a simple fast-blink loop.

**Always-on props** (fans, overhead light strips, terminal screens, reel-to-reel, cable bundle) have no state table — they loop forever, unaffected by agent state.

### Interactions with Other Systems

| System | Direction | Interface | Notes |
|---|---|---|---|
| **Agent State Machine** *(provisional)* | → AAL | `agent_state_changed(agent_id: StringName, new_state: StringName)` | AAL subscribes once; dispatches to room-scoped prop groups |
| **Room System** | → AAL | `RoomSystem.get_room_for_agent(agent_id) → StringName` | Called on each state change to identify which room group to update |
| **Room System** | → AAL | `RoomSystem.get_room_rect(room_id) → Rect2i` | Used if AAL validates prop placement within room bounds (authoring validation only) |
| **TileMap Renderer** | → AAL | `cell_size = 16` constant | Props snap to tile grid at placement time |
| **Ambient prop nodes** | AAL → | `set_ambient_state(new_state: StringName)` | AAL calls this on every prop in the affected room's group |

## Formulas

**F1 — Deterministic Phase Offset**

```
phase_offset = (hash(node_path) mod 2^31) / 2^31 × cycle_duration
```

| Variable | Type | Range | Definition |
|---|---|---|---|
| `node_path` | NodePath | — | The prop's canonical scene tree path (stable across sessions) |
| `hash(node_path)` | int | 0–2^63 | GDScript's built-in `hash()` function applied to the path string |
| `cycle_duration` | float | 0.5–8.0s | Full loop length for this prop's active animation |
| `phase_offset` | float | 0.0–cycle_duration | How far into its cycle the prop starts on scene load |

The prop calls `anim_player.seek(phase_offset, true)` in `_ready()`. Because the seed is derived from the node path (not `randf()`), the same scene produces identical prop phases every session. The bunker was always running.

*Example:* A status light with `cycle_duration = 4.0s`. Assuming `hash(path) % 2^31 = 1402751843`: `phase_offset = 1402751843 / 2^31 × 4.0 ≈ 2.61s`. The light starts 2.61s into its blink cycle.

---

**F2 — Scroll Rate (Working State)**

```
scroll_rate_working = scroll_rate_idle × WORKING_SCROLL_MULTIPLIER
```

| Variable | Type | Range | Definition |
|---|---|---|---|
| `scroll_rate_idle` | float | >0 px/s | Base scroll speed of the progress ticker in IDLE state (tuning knob) |
| `WORKING_SCROLL_MULTIPLIER` | float | 1.5 | Fixed multiplier — WORKING state scrolls 50% faster |
| `scroll_rate_working` | float | 1.5 × idle rate | Scroll rate during WORKING state |

*Example:* `scroll_rate_idle = 8 px/s` → `scroll_rate_working = 12 px/s`.

---

**F3 — ERRORED Indicator Pulse Pattern**

Not a formula — a fixed arrhythmic timing sequence that repeats:

| Step | Phase | Duration |
|---|---|---|
| 1 | ON (bright) | 0.4s |
| 2 | OFF | 0.15s |
| 3 | ON (bright) | 0.2s |
| 4 | OFF | 0.4s |
| → repeat | | Total cycle: 1.15s |

This pattern is hardcoded in the ERRORED animation resource. The irregular cadence reads as malfunction. Total cycle length (1.15s) is registered as `errored_pulse_cycle_seconds` in case the Audio Manager needs to sync alert audio to it.

## Edge Cases

**EC-1: No props discovered at startup.**
If `get_tree().get_nodes_in_group(&"ambient_props")` returns an empty array, the Ambient Animation Layer logs a warning and initializes with zero props. No crash. The bunker renders without ambient motion — this is a content authoring gap, not a code error.

**EC-2: ERRORED signal during a state transition (mid-fade).**
If `set_ambient_state("ERRORED")` is called while a 0.3s cross-fade to another state is in progress, the Tween is killed immediately and the ERRORED state begins from the current visual position. ERRORED always preempts an in-progress transition.

**EC-3: COMPLETED signal fires twice in rapid succession.**
If a second `COMPLETED` state change arrives while the 0.5s flash is still playing, the flash animation restarts from the beginning. Flashes do not stack or queue — only the most recent event plays.

**EC-4: Prop placed in wrong room group by authoring error.**
If a prop in room A is accidentally added to `"ambient_room_agent_01"` (room B's group), it will respond to room B's agent state changes. This is a content authoring error, not a code-level error. The Ambient Animation Layer has no way to validate spatial membership — room group assignment is the level designer's responsibility.

**EC-5: Agent State Machine signal not yet wired (before bootstrap).**
If a state-sensitive prop receives no `agent_state_changed` signal during initialization, it remains in its default IDLE state. The 0.3s transition logic only fires when a signal arrives. This is safe — props never enter a null/uninitialized visual state.

**EC-6: Scene tree restructuring changes node paths.**
If a prop's node path changes between sessions (level designer renames a node), its deterministic phase offset will differ from the previous session. This is acceptable — the new path produces a new stable offset. Document in the level designer's style guide: avoid renaming ambient prop nodes after initial placement.

**EC-7: DISCONNECTED state not forwarded by Agent State Machine.**
If the Agent State Machine does not emit a `DISCONNECTED` sub-state (design TBD), state-sensitive props will remain in whatever state they last received. The `DISCONNECTED` row in the state table (lights off) is provisional — if the Agent State Machine GDD decides not to forward this, DISCONNECTED visual behavior falls back to ERRORED or IDLE per the final ASM design.

## Dependencies

### Upstream Dependencies *(systems the AAL requires)*

| System | What the AAL Needs | When It's Needed |
|---|---|---|
| **Agent State Machine** *(provisional)* | `agent_state_changed(agent_id: StringName, new_state: StringName)` signal | Every state change that triggers state-sensitive prop updates |
| **Room System** | `get_room_for_agent(agent_id) → StringName` | On each state change, to route to the correct room group |
| **TileMap Renderer** | `cell_size = 16` constant | Prop placement authoring — props snap to tile grid |
| **Configuration Loader** | Agent list (which agents exist, which rooms they occupy) | Startup — determines which room groups to expect at scene load |

### Downstream Dependents *(systems that depend on the AAL)*

None. The Ambient Animation Layer drives visuals only and provides no data or signals to other systems.

### Provisional Dependency Notes

*⚠ Full DISCONNECTED visual behavior (lights off entirely) depends on whether Agent State Machine forwards DISCONNECTED as a sub-state on `agent_state_changed`. Review and update when Agent State Machine GDD is authored.*

## Tuning Knobs

| Knob | Default | Safe Range | Effect |
|---|---|---|---|
| `ambient_state_transition_seconds` | 0.3s | 0.05–1.0s | Cross-fade duration when `set_ambient_state()` is called. Too short = snap (calls attention to transitions). Too long = sluggish response behind character animations. |
| `idle_indicator_cycle_duration` | 4.0s | 2.0–8.0s | Full blink cycle in IDLE state. Longer = more languid. |
| `working_indicator_cycle_duration` | 1.5s | 0.8–3.0s | Full pulse cycle in WORKING state. Must be clearly faster than idle cycle to be legible. |
| `WORKING_SCROLL_MULTIPLIER` | 1.5 | 1.1–3.0 | Progress ticker speed multiplier in WORKING state relative to idle. |
| `scroll_rate_idle` | 8 px/s | 2–20 px/s | Base progress ticker scroll rate in IDLE. Too fast = distracting; too slow = imperceptible as motion. |
| `completed_flash_duration` | 0.5s | 0.2–1.0s | Duration of the COMPLETED indicator flash. Must not exceed `completed_beat_duration_seconds` (registered: 2.0s). |
| `commander_room_prop_count` | 12 | 8–16 | Total ambient props in Commander's Room. |
| `agent_room_prop_count` | 8 | 5–12 | Total ambient props per agent department room. |
| `errored_pulse_on_1` | 0.4s | 0.2–0.6s | First ON phase in ERRORED irregular pattern. |
| `errored_pulse_off_1` | 0.15s | 0.05–0.3s | First OFF phase. Must differ from on_1 to preserve arrhythmia. |
| `errored_pulse_on_2` | 0.2s | 0.1–0.4s | Second ON phase. Must differ from on_1. |
| `errored_pulse_off_2` | 0.4s | 0.2–0.6s | Second OFF phase. |

## Visual/Audio Requirements

### Prop Visual Specifications

All props follow the Art Bible standard: PNG-8, Aseprite source, 8×8px art module grid. Props are placed on the scene's `TileMapLayer_Overlay` (z=2) or as separate `AnimatedSprite2D` nodes positioned above floor tiles — always rendered in front of characters.

**Prop types and their art specs (MVP):**

| Prop Type | Art Size | Frame Count | Animation | Z-layer |
|---|---|---|---|---|
| Status indicator light | 8×8px | 2 (on/off) | Modulate alpha blink via AnimationPlayer | Above overlay |
| Ventilation fan | 16×16px | 4–8 | Rotation loop | Overlay |
| Terminal screen | 16×8px | Scrolling | Scanline scroll (AnimationPlayer UV offset or multi-frame) | Overlay |
| Overhead light strip | 32×8px | 2 | Very subtle modulate flicker | Overlay |
| Reel-to-reel logger | 16×16px | 4–8 | Rotation loop on reel element | Overlay |
| Progress ticker | 32×8px | Scrolling | UV offset scroll | Overlay |
| Cable bundle | 8×8px (tile) | 1 (static) | None — decorative only | Floor or Overlay |

**Color rules (enforced — not suggestions):**

- **Always-on props:** warm grey palette only (`#5A5048`, `#7A6F64`). Must NOT use amber `#D4882A` or green `#4A9A52` in their default state — those hues are reserved for state signals.
- **State-sensitive IDLE:** dim amber variant (`#8A5018` — desaturated). Subtle enough to not signal "active."
- **State-sensitive WORKING:** full amber `#D4882A`. The eye should recognize this as the same amber as the agent character WORKING state.
- **State-sensitive ERRORED:** pulses between off/dark and sienna `#A03520`. Arrhythmic timing per F3.
- **State-sensitive COMPLETED:** single frame at `#FFFFFF` (white flash), then returns immediately to IDLE color.

**Brightness-motion constraint (enforced at art review):** A prop that uses a bright color must animate slowly (cycle ≥ 2.0s). A prop that animates quickly (fan blades, fast scroll) must use desaturated colors. No exceptions — this is what keeps ambient props from stealing visual attention from character animations.

### Audio

The Ambient Animation Layer owns **no audio**. Ambient sound (machine hum, ventilation rumble, low drone) is owned by the Audio Manager. If a prop's animation creates an expectation of sound (e.g., a mechanical click), the Audio Manager must be separately specified to produce it — the AAL makes no audio calls.

## Acceptance Criteria

1. **Bunker is never still.** At any moment during normal operation, at least 3 props are visibly mid-animation cycle. A 30-second observation with no agent activity shows continuous background motion.

2. **Phase variation is visible.** Two status indicator lights of the same type in the same room blink noticeably out of sync. A tester confirms they do not blink together at startup.

3. **Phase offsets are deterministic.** Close and reopen the application. The same props are at the same phase in their cycle at the same elapsed time — the bunker looks the same on reopen.

4. **No always-on prop uses amber or green.** Fan blades, terminal screens, overhead light strips, and cable bundles use only warm grey tones in their looping state. Amber and green do not appear in any always-on prop sprite.

5. **State-sensitive props respond to WORKING.** When an agent transitions to WORKING, status indicator lights in that room's group visibly accelerate their pulse within 0.3s. The change is noticeable but not jarring.

6. **State-sensitive props respond to ERRORED.** When an agent transitions to ERRORED, the indicator light enters an arrhythmic pulse pattern. A tester who reads the character animation first notices the prop response second — it confirms, not leads.

7. **COMPLETED flash does not exceed beat duration.** The COMPLETED indicator flash lasts ≤ `completed_beat_duration_seconds` (2.0s). The flash begins simultaneously with the character's COMPLETED beat animation.

8. **ERRORED pattern is not a regular loop.** A tester confirms the ERRORED indicator does not blink at a steady even cadence. The irregular rhythm is visible and distinct from WORKING fast-pulse.

9. **State transitions cross-fade.** When any agent state change occurs, the prop visual change is a gradual shift over 0.3s — not an instantaneous cut.

10. **Character animations are primary.** In a room with an ERRORED agent, a tester unfamiliar with the system identifies the character's visual state before noticing the ambient prop changes.

11. **Zero props subscribe directly to Agent State Machine.** Code review confirms only `ambient_animation_layer.gd` connects to `agent_state_changed`. No prop script contains a signal connection to the Agent State Machine.

12. **Performance: 60fps with 20 active props.** With Commander's Room (12 props) and one agent room (8 props) all animating simultaneously, frame rate stays ≥60fps on target PC hardware.

## Open Questions

1. **Agent State Machine signal interface (HIGH — blocks implementation).** This GDD assumes `agent_state_changed(agent_id: StringName, new_state: StringName)`. Confirm signal name, signature, and whether DISCONNECTED is forwarded as a sub-state when Agent State Machine GDD is authored.

2. **DISCONNECTED visual fallback.** If Agent State Machine does not forward DISCONNECTED, what should state-sensitive props show? Options: stay in last-known state, return to IDLE, or a new "signal lost" visual. Decide after Agent State Machine GDD is complete.

3. **Prop Z-ordering with character sprites.** Confirm whether ambient prop `AnimatedSprite2D` nodes placed above `TileMapLayer_Wall` (z=1) correctly sort against character Node2D instances in Godot 4.6.2. This is related to VERIFY item #3 in active.md (TileMapLayer Y-sort behavior). If Y-sort conflicts cause props to render incorrectly relative to characters, a Z-index adjustment or separate CanvasLayer may be needed.

4. **Shader-based scroll vs. multi-frame animation for terminal screens.** The terminal screen prop can scroll using a UV-offset shader (one draw call, any speed) or a spritesheet with many frames (simple but requires large sprite). For MVP, multi-frame is sufficient. For V1, a shader provides smoother scrolling and smaller texture memory. Decision can be deferred to implementation.

5. **ERRORED_pulse_cycle_seconds registry entry.** The systems designer suggested registering `errored_pulse_cycle_seconds` = 1.15s in case the Audio Manager needs to sync alert audio to the pulse rhythm. Defer this decision to when Task Completion Beat and Audio Manager GDDs establish whether any alert SFX needs timing synchronization.
