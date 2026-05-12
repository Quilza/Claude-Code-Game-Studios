# Main Scene Bootstrap — Game Design Document

> **Status**: COMPLETE — all 8 sections authored 2026-05-12 (section-by-section with user approval per `.claude/rules/design-docs.md`)
> **Created**: 2026-05-12
> **Completed**: 2026-05-12
> **Owner**: technical-director (with creative-director consultation on boot UX)
> **System #**: 16 (architecture-tier; final system in systems-index)
> **Linked**:
>   - ADR-0003 Autoload Scene Composition (Accepted) — defines the two-Autoload limit + bootstrap ordering
>   - ADR-0011 HUD Rendering Strategy — defines the two CanvasLayer topology Bootstrap must produce
>   - ADR-0013 Stretch Mode + Pixel-Perfect — defines viewport + Y-sort topology Bootstrap must enforce
>   - All 10 implemented MVP systems in `src/` (Sprint 3 commits `a35579c` through `742d01a`)

Main Scene Bootstrap is the **wiring layer**. It owns the scene composition that turns 10 independently-implemented systems into a runnable game. Without it, the systems sit in `src/` unable to find each other. It is the final system designed because it depends on every other system's contract being locked.

---

## 1. Overview

The Main Scene Bootstrap is the wiring layer that turns 10 independently-implemented systems into a runnable bunker. It owns the scene hierarchy — Main → WorldRoot + HudLayer + OverlayLayer — and the boot order: Autoloads (ConfigurationLoader, AudioManager) initialize first per ADR-0003, then scene-scoped systems instantiate in dependency order (DataBridge → ASM → TileMap → Room → ACC×N → AAL → TCB → HUD), then deferred-signal-wiring + initial agent assignments fire post-`_ready()` to avoid the ASM E-13 race. Per-agent ACC nodes are spawned programmatically from `ConfigurationLoader.get_agents()`. On config-load failure, Bootstrap swaps to `PreBunkerError.tscn` and the bunker never renders. Bootstrap is designed last because it depends on every other system's contract being locked — but it is the keystone that makes the project runnable.

---

## 2. Player Fantasy

Press the button. For half a second — the briefest pause, just enough that you notice — the screen is black. Then the bunker resolves: floor, walls, every prop, your agents already at their stations. Nothing animated in; nothing announced itself. The place was waiting. You can hear that one of the agents is already working, see another wandering the corridor, glance at the recent completions strip showing yesterday's last task. The tool didn't *start*; you simply joined a room that was already running.

If something goes wrong — config missing, token invalid, agents unreachable — you don't get the bunker. You get an error screen styled in the bunker's own visual language, telling you exactly what's broken. Failure feels like part of the same world, not a leak from underneath it.

> **MVP scope note**: the 8–12s sequential boot animation from art-bible.md is deferred to V1 polish (per authoring Q3). MVP boots straight in.

---

## 3. Detailed Rules

### 3.1 Bootstrap lifecycle

1. **Bootstrap script is attached to the root node of `Main.tscn`.** Its `_ready()` runs after both Autoloads have completed their own `_ready()` per Godot's autoload ordering (ConfigurationLoader → AudioManager → scene).

2. **Gate on ConfigurationLoader state.** Bootstrap's first action: check `ConfigurationLoader.get_state()`. If not `"READY"`, immediately swap the scene to `PreBunkerError.tscn` via `get_tree().change_scene_to_file()`. Bunker composition is skipped entirely.

3. **No gameplay rendering until composition completes.** Bootstrap hides the WorldRoot at start of `_ready()` and shows it only after all 10 systems are wired. Prevents partial-state UI flashes.

### 3.2 Scene hierarchy assembly

4. **Main scene root has three sub-roots authored in `.tscn`** (not programmatic): `WorldRoot` (Node2D, `y_sort_enabled = true` per ADR-0013), `HudLayer` (CanvasLayer with `layer = 10` per ADR-0011), `OverlayLayer` (CanvasLayer with `layer = 20`).

5. **TileMapRenderer + NavigationRegion2D are scene-authored** under WorldRoot. The 4 TileMapLayers and the NavigationRegion2D's polygon are baked at scene-save time (per Q5), not at runtime.

### 3.3 System instantiation order

6. **Order is fixed by dependency graph** (Bootstrap instantiates):
   1. `DataBridge` → Main child
   2. `AgentStateMachine` → Main child
   3. `RoomSystem` → WorldRoot child
   4. `AgentCharacterController × N` → WorldRoot children
   5. `AmbientAnimationLayer` → WorldRoot child
   6. `TaskCompletionBeat` → WorldRoot child
   7. `CommandersRoomHUD` → HudLayer child

7. **`@export` wiring happens at instantiation time** — Bootstrap sets each new node's exported properties to canonical references **before** calling `add_child()`. After `add_child()`, the node's `_ready()` runs with valid references already populated.

### 3.4 ACC instantiation loop

8. **ACC nodes are programmatic (per Q2).** Bootstrap iterates `ConfigurationLoader.get_agents()`. For each agent dict (index `i`):
   - Instantiate `AgentCharacterController.tscn` (a future scene with AnimationPlayer + Sprite2D + NavigationAgent2D pre-wired)
   - Set `acc.agent_id = agent["id"]`, `acc.agent_index = i`
   - Set system refs: `agent_state_machine`, `room_system`, `tile_map_renderer`
   - `world_root.add_child(acc)`

9. **Zero agents is a valid state.** Bootstrap spawns no ACC nodes; HUD shows empty slot grid (per HUD E-12); bunker is otherwise normal.

### 3.5 Deferred signal wiring + initial assignments

10. **Use `call_deferred` to avoid the ASM E-13 race.** After all 10 systems are instantiated and added to the scene tree, Bootstrap calls `call_deferred("_perform_initial_wiring")`. This runs at the end of the current frame, after every node's `_ready()` has fired. Inside:
    - Call `room_system.assign_agent(AGENT_ROOM_ID, agent_id)` for each agent — these emit `agent_assigned` to already-subscribed listeners (per RoomSystem Rule 6)
    - Show WorldRoot (was hidden in Rule 3)

### 3.6 Ambient music

11. **Ambient music is optional (per Q6).** Bootstrap reads `entities.yaml → bootstrap.ambient_music_path` (default `res://assets/audio/ambient.ogg`). If `ResourceLoader.exists(path)` is true: `AudioManager.play_music(load(path))`. Otherwise: `push_warning("[Bootstrap] ambient music asset not found; running silent")` and continue. **Not a fatal condition.**

### 3.7 Error scene takeover

12. **Pre-bunker error scene is a separate `.tscn` (per Q4).** Path: `res://src/ui/scenes/PreBunkerError.tscn`. Scene reads `ConfigurationLoader.get_state()` + last error message via public accessor. Bootstrap performs the swap with `get_tree().change_scene_to_file(ERROR_SCENE_PATH)`. The bunker is never rendered when this fires.

### 3.8 Re-entry safety

13. **Scene reload (F5 in editor) is supported.** Autoloads persist across reloads in Godot. Bootstrap does not duplicate Autoload state; it re-creates the scene-scoped systems from scratch. Per-agent stats persist via ConfigurationLoader settings (per ASM Rule 14).

14. **No `_exit_tree()` cleanup required** on Bootstrap itself — Godot frees scene-scoped systems on reload, and ASM's own `_exit_tree()` flushes its dirty stats per ASM Rule 14.

### 3.9 What Bootstrap does NOT do

15. **Bootstrap does not configure Godot subsystems.** Window size, viewport, stretch mode, input map — all are configured in `project.godot` (per ADR-0013 + ADR-0011). Bootstrap does not read or modify these.

16. **Bootstrap does not handle individual system errors after launch.** If `DataBridge` enters DISCONNECTED post-launch, HUD displays it; Bootstrap is uninvolved.

17. **Bootstrap is web-mode-agnostic.** Per ADR-0004, ConfigurationLoader's `is_mock()` reflects the web override. DataBridge consumes that. Bootstrap behavior is identical on PC and web.

18. **Boot animation deferred per Q3.** MVP boots straight to the bunker after composition (a 0.2s alpha fade-in from black is acceptable as the only transition). The 8–12s sequential boot from art-bible.md §613 is a V1 polish item.

---

## 4. Formulas

Bootstrap contains essentially no math. One degenerate formula for completeness:

**F1 — Per-agent ACC instantiation iteration**

```
for i in range(config_agents.size()):
    agent = config_agents[i]
    instantiate_acc(agent_id = agent["id"], agent_index = i)
```

| Variable | Type | Range |
|---|---|---|
| `i` | int | `0` to `MAX_AGENTS - 1` (per ConfigurationLoader's 12 cap) |
| `config_agents` | Array[Dictionary] | size 0–12 |

That's the only iteration in Bootstrap. No game-tuning math exists in this system.

---

## 5. Edge Cases

**E-1: `ConfigurationLoader.get_state() != "READY"` at Bootstrap `_ready()`.**
Bootstrap swaps to `PreBunkerError.tscn`. The bunker scene is freed; no scene-scoped systems instantiate. (Rule 2)

**E-2: Empty agents list (`ConfigurationLoader.get_agents().size() == 0`).**
Bootstrap spawns zero ACC nodes. HUD's slot grid is empty (per HUD E-12). DataBridge has no channels. ASM has no registered agents. Everything works — the bunker shows itself but is uninhabited. Not an error.

**E-3: `AgentCharacterController.tscn` template asset missing.**
Bootstrap's ACC instantiation loop calls `load(...)` which returns null. Bootstrap logs `push_error("[Bootstrap] AgentCharacterController.tscn missing — agents will not render")` and continues without ACC nodes. HUD still renders slot states (which read from ASM, not ACC). Logical bug, not a crash.

**E-4: `NavigationRegion2D` not baked (empty NavigationPolygon).**
ACC pathfinding requests silently fail (NavigationAgent2D logs warnings). Characters appear at spawn tiles but cannot move. Per art-bible's MVP scope this is acceptable degradation while waiting for level art. Bootstrap is uninvolved.

**E-5: `bootstrap.ambient_music_path` points to nonexistent file.**
`ResourceLoader.exists()` returns false. Bootstrap logs `push_warning` and skips `AudioManager.play_music()`. Bunker runs silent. Not fatal (Q6).

**E-6: `PreBunkerError.tscn` missing.**
`change_scene_to_file()` returns an error code. Bootstrap falls back to `push_error` + leaves the (broken) main scene running. User sees a half-loaded screen but error is logged. **Mitigation**: `PreBunkerError.tscn` MUST ship with the project; treat its absence as a build-time error.

**E-7: Re-entry mid-scene-load (rapid F5).**
If the user reloads the scene before Bootstrap's `call_deferred("_perform_initial_wiring")` fires, the deferred call still executes against now-freed nodes. Godot's deferred calls null-check; the call is a no-op. No crash.

**E-8: Agent count exceeds `MAX_AGENTS` (12).**
ConfigurationLoader already rejects this with `CONFIG_INVALID` before Bootstrap runs (per ConfigLoader §Edge Cases). E-1 handles the downstream.

**E-9: Web mode (`OS.has_feature("web")` true).**
Bootstrap behavior is identical to PC. `ConfigurationLoader.is_mock()` returns true (forced by ADR-0004 web override); DataBridge instantiates its mock driver; everything else is unchanged. No Bootstrap-level branch.

---

## 6. Dependencies

### 6.1 Upstream — systems Bootstrap reads from

| System | Interface used | Purpose |
|---|---|---|
| **ConfigurationLoader** (Autoload) | `get_state()`, `config_loaded` / `config_load_failed` signals, `get_agents()`, `is_mock()`, `get_setting()` | Gate the bootstrap sequence on config validity; iterate agents to spawn ACC nodes; read tuning knobs |
| **AudioManager** (Autoload) | `play_music(stream)` | Begin ambient music after scene composition (silent if asset missing per Q6) |

### 6.2 Composition — systems Bootstrap instantiates and wires

These are not "downstream" in the conventional sense — Bootstrap creates them and wires their cross-system `@export` references at scene-compose time, then they communicate among themselves via signals. Bootstrap is the integrator, not a consumer.

| System | Scene placement | Cross-references Bootstrap wires |
|---|---|---|
| **DataBridge** | Main child (sibling of WorldRoot) | None — DataBridge reads ConfigurationLoader autoload directly |
| **AgentStateMachine** | Main child | `agent_state_machine._bridge_ref` ← DataBridge (deferred per ASM E-13) |
| **TileMapRenderer** | WorldRoot child (scene-authored) | Self-contained |
| **RoomSystem** | WorldRoot child | `room_system.tile_map_renderer` ← TileMapRenderer |
| **AgentCharacterController × N** | WorldRoot children (one per agent) | `agent_state_machine`, `room_system`, `tile_map_renderer`, `animation_player` refs; `agent_id`, `agent_index` |
| **AmbientAnimationLayer** | WorldRoot child | `agent_state_machine`, `room_system` |
| **TaskCompletionBeat** | WorldRoot child | `agent_state_machine`, `room_system` |
| **CommandersRoomHUD** | HudLayer (CanvasLayer=10) child | `agent_state_machine`, `data_bridge`, `task_completion_beat`, `room_system` |
| **OverlayLayer** | Main child (CanvasLayer=20) | Reserved for HUD's detail overlay panel per ADR-0011 |

After all instantiation completes, Bootstrap uses `call_deferred` to fire:
- `room_system.assign_agent(AGENT_ROOM_ID, agent_id)` for each configured agent (per RoomSystem Rule 6 — assignments NOT done in `_ready()` so signals reach already-subscribed listeners)

### 6.3 Assets / scene resources Bootstrap touches

| Asset | Path | Required? |
|---|---|---|
| Pre-bunker error scene | `res://src/ui/scenes/PreBunkerError.tscn` | Yes — Bootstrap swaps the main scene to this on config failure |
| Ambient music | configurable via `entities.yaml → bootstrap.ambient_music_path` | Optional — silent if missing per Q6 |
| `NavigationRegion2D` | child of WorldRoot, baked at scene-save time per Q5 | Required for ACC pathfinding |
| Main scene file | `res://src/scenes/Main.tscn` | The scene this script attaches to |

### 6.4 What Bootstrap explicitly does NOT do

- Does not parse `config.json` — ConfigurationLoader's job
- Does not subscribe to `agent_state_changed`, `agent_response_received`, `task_completed`, `beat_fired` — those are wired between the systems Bootstrap composes; Bootstrap itself doesn't consume them
- Does not own per-agent state — ASM's job
- Does not implement gameplay logic — pure wiring + ordering
- Does not handle hot-reload of agents — bootstrap-only registration per ConfigurationLoader's scope

### 6.5 Bidirectional consistency

Bootstrap is the **only** system whose dependency relationships are inverse of every other GDD: every other GDD references the systems it consumes; Bootstrap references the systems it composes. The 9 systems Bootstrap instantiates do **not** need to list Bootstrap in their Dependencies sections — they don't consume Bootstrap's output. This asymmetry is correct and matches Bootstrap's architecture-tier role.

---

## 7. Tuning Knobs

| Knob | Default | Range | Configuration source | Tuner authority |
|---|---|---|---|---|
| `BOOTSTRAP_FADE_IN_SEC` | `0.2` | `0.0 – 1.0` | `entities.yaml → bootstrap.fade_in_sec` | game-designer (MVP polish) |
| `AMBIENT_MUSIC_PATH` | `"res://assets/audio/ambient.ogg"` | path or `""` | `entities.yaml → bootstrap.ambient_music_path` | technical-director (asset coordination) |
| `ERROR_SCENE_PATH` | `"res://src/ui/scenes/PreBunkerError.tscn"` | fixed path | hardcoded `const` in `main_scene_bootstrap.gd` | technical-director (architectural — changing requires ADR amendment) |
| `AGENT_ROOM_ID` | `&"agent_01"` (per Room System) | fixed | re-exported constant from `RoomSystem.AGENT_ROOM_ID` | technical-director |

**Post-MVP candidates** (when V1 boot animation lands per Q3 deferral):
- `BOOT_SEQUENCE_DURATION_SEC` (default 8.0; per art-bible §613)
- `BOOT_SEQUENCE_PHASES` — ordered list of fade-in waypoints (rooms, props, agents, HUD)
- `FIRST_OPEN_DETECTION_HOURS` (default 4.0; per art-bible — when to show boot animation vs straight-in)

---

## 8. Acceptance Criteria

Testable conditions. Bootstrap-level tests are integration tests by nature (they verify scene composition). Unit-test-tier ACs are limited.

### 8.1 Lifecycle gate

**AC-1**: Given `ConfigurationLoader.get_state() == "READY"` at scene load, Bootstrap proceeds with composition.
**AC-2**: Given `ConfigurationLoader.get_state() != "READY"` at scene load, Bootstrap calls `change_scene_to_file(ERROR_SCENE_PATH)` and the bunker scene is freed without any of the 10 systems being instantiated. `[integration test]`
**AC-3**: Given `WorldRoot.visible == false` at the start of `_ready()`, after `_perform_initial_wiring()` fires deferred, `WorldRoot.visible == true`.

### 8.2 Scene hierarchy

**AC-4**: After Bootstrap `_ready()` completes, the scene tree contains: Main with children WorldRoot (Node2D, `y_sort_enabled = true`), HudLayer (CanvasLayer with `layer == 10`), OverlayLayer (CanvasLayer with `layer == 20`). `[integration test]`

### 8.3 System instantiation order

**AC-5**: After composition, the following nodes exist exactly once each (under their expected parents per §3.3 Rule 6): DataBridge, AgentStateMachine, RoomSystem, AmbientAnimationLayer, TaskCompletionBeat, CommandersRoomHUD. `[integration test]`
**AC-6**: The count of `AgentCharacterController` children of WorldRoot equals `ConfigurationLoader.get_agents().size()`. `[integration test]`
**AC-7**: Each ACC's `agent_id` matches the `id` field of the corresponding agent dict; `agent_index` matches the array position. `[integration test]`

### 8.4 @export wiring

**AC-8**: After composition, each ACC's `agent_state_machine`, `room_system`, `tile_map_renderer` properties are non-null. `[unit test via mock]`
**AC-9**: HUD's `agent_state_machine`, `data_bridge`, `task_completion_beat`, `room_system` properties are non-null after composition. `[unit test via mock]`

### 8.5 Deferred wiring

**AC-10**: `room_system.assign_agent` is called for each configured agent exactly once, *after* every system's `_ready()` has completed. Verified by: HUD subscribed to `agent_assigned` BEFORE the call fires (no missed signals). `[integration test]`

### 8.6 Ambient music

**AC-11**: Given a valid `bootstrap.ambient_music_path` pointing to an existing AudioStream, `AudioManager.play_music` is called with the loaded stream. `[unit test with mock AudioManager]`
**AC-12**: Given a `bootstrap.ambient_music_path` pointing to a nonexistent file, Bootstrap logs `push_warning` and does NOT call `AudioManager.play_music`. `[unit test]`

### 8.7 Re-entry

**AC-13**: Reloading the main scene (`get_tree().reload_current_scene()`) does not duplicate Autoload state; ASM still reports the same per-agent stats counters (loaded from persisted user://settings.json on second-bootstrap). `[integration test]`

### 8.8 Edge cases

**AC-14**: Given zero configured agents, Bootstrap completes composition without spawning ACC nodes. HUD slot grid renders empty. No errors. `[integration test]`
**AC-15**: Given `AgentCharacterController.tscn` missing on disk, Bootstrap logs `push_error` but does not crash; remaining composition completes. `[integration test]`
**AC-16**: Given `PreBunkerError.tscn` missing and `ConfigurationLoader` not READY, Bootstrap logs `push_error` and the scene fails to swap cleanly. (Build-time test: assert the asset exists.) `[CI gate]`
**AC-17**: In web mode (`OS.has_feature("web") == true`), Bootstrap behavior is identical to PC mode. No branches on the web feature in Bootstrap code. `[code review check]`

---

## Authoring provenance

This GDD was authored 2026-05-12 in a single session via section-by-section AskUserQuestion panels for design decisions. Sections were written in the order: Overview → Player Fantasy → Dependencies → Detailed Rules → Formulas → Edge Cases → Tuning Knobs → Acceptance Criteria.

### Resolved design decisions

| # | Question | Decision |
|---|---|---|
| 1 | Scene hierarchy | **Grouped sub-roots** — Main → WorldRoot + HudLayer + OverlayLayer |
| 2 | ACC instantiation | **Programmatic loop** — Bootstrap iterates ConfigurationLoader.get_agents() |
| 3 | Boot animation | **Deferred to V1** — MVP boots straight; 0.2s fade-in only |
| 4 | Error scene | **Separate .tscn** — `res://src/ui/scenes/PreBunkerError.tscn` |
| 5 | NavigationRegion2D baking | **Scene-authored at build time** (not runtime-baked) |
| 6 | Ambient music | **Run silent if asset missing** — `ResourceLoader.exists()` check, no shipped placeholder |
