# ADR-0003: Autoload Scene Composition

## Status
Accepted (2026-05-11)

## Date
2026-05-11

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.2 |
| **Domain** | Core / Scripting |
| **Knowledge Risk** | LOW — Autoload system stable since Godot 4.0; no breaking changes in 4.4–4.6 |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/deprecated-apis.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | None — Autoload initialization order is governed by Project Settings, not a post-cutoff API |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None |
| **Enables** | ADR-001 (Data Bridge Transport), ADR-002 (Configuration Loading + Persistence), ADR-006 (Signal-Based Decoupling) — all downstream ADRs must know which modules are global singletons vs. injected before defining their interfaces |
| **Blocks** | All Foundation + Core implementation — no code may be written that accesses ConfigLoader or AudioManager by singleton name without this ADR being Accepted |
| **Ordering Note** | Write before ADR-001 and ADR-002 so downstream ADR authors know the global access model |

## Context

### Problem Statement

Godot's Autoload system makes a Node globally accessible via its singleton name. Over-using Autoloads creates hidden coupling and unpredictable initialization order. This ADR establishes the binding rule for which systems are Autoloads and which are instantiated by an explicit bootstrap sequence.

### Constraints

- Configuration Loader and Audio Manager must be accessible before any scene `_ready()` runs — they provide project-wide services all other `_ready()` methods consume.
- TileMap Renderer must be multi-instantiable (one per room) — a singleton Autoload cannot serve this need.
- Web (HTML5): browser AudioContext requires a user gesture before audio playback. AudioManager must not play sound at startup.
- DataBridge owns `HTTPRequest` nodes scoped to the scene lifetime; Autoloads are application-lifetime — these don't compose.
- All other systems (DataBridge, RoomSystem, ASM, ACC, AAL, TCB, HUD) are scene-scoped, not project-wide services.

### Requirements

- ConfigLoader accessible to ALL systems before any `_ready()` — registered as Autoload #1
- AudioManager accessible to TCB, HUD settings panel, and future alert systems — registered as Autoload #2
- Initialization order deterministic and explicitly documented
- Non-autoload modules receive dependencies through explicit bootstrap injection
- TileMapRenderer multi-instantiable — provided as a subscene, not an Autoload

## Decision

Exactly **two** Godot Autoloads are registered in Project Settings:

1. **`ConfigLoader`** → `res://src/foundation/configuration_loader.gd`
2. **`AudioManager`** → `res://src/foundation/audio_manager.gd`

All other systems — `DataBridge`, `RoomSystem`, `AgentStateMachine` (BLOCKED), `AgentCharacterController` (one per agent), `AmbientAnimationLayer`, `TaskCompletionBeat`, and `CommandersRoomHUD` — are instantiated by a **Main Scene Bootstrap** script attached to the root node of the main scene.

`TileMapRenderer` is a `Node2D` subscene (`res://src/foundation/tilemap_renderer.tscn`) instantiated per-room where tile placement is needed. It is NOT an Autoload.

### Initialization Order

**Phase 1 — Autoloads (Godot engine processes these before any scene `_ready()` fires):**

```
1. ConfigLoader   ← reads config.json; emits config_loaded
2. AudioManager   ← subscribes ConfigLoader.setting_changed; builds 8-node pool
```

**Phase 2 — Main Scene Bootstrap `_ready()` (sequential, dependency-ordered):**

```
3.  TileMapRenderer   (subscene, instantiated per-room)
4.  RoomSystem        ← reads ConfigLoader.get_agents()
5.  DataBridge        ← reads ConfigLoader.get_agents() + is_mock()
6.  AgentStateMachine [BLOCKED] ← subscribes DataBridge signals
7.  ACC × N           ← one per agent; subscribes ASM.agent_state_changed
8.  AAL               ← one per room; subscribes ASM.agent_state_changed
9.  TCB               ← subscribes ASM.task_completed; builds AgentSoundRegistry
10. HUD               ← subscribes ASM + TCB + RoomSystem; performs sync pass
```

**Rule**: No Phase 2 system may access another Phase 2 system during its own `_ready()`. All cross-system references are injected by the bootstrap after `add_child()` completes for each system.

### Instantiation Pattern

Phase 2 systems are constructed using one of two patterns depending on whether they need pre-authored scene children:

- **Pure-code** (no pre-authored child nodes needed): `SystemClass.new()` → `add_child(instance)`
- **Scene-backed** (pre-authored node hierarchy): `preload("res://src/[layer]/[scene].tscn").instantiate()` → `add_child(instance)`

The Main Scene Bootstrap script documents which pattern each system uses. Using `.new()` on a scene-backed system loses its pre-authored children — this is a common source of bugs and must be avoided.

### Autoload Access Pattern

Direct singleton name access is **only permitted for ConfigLoader and AudioManager**:

```gdscript
# Permitted — these are the only two global singletons:
var agents := ConfigLoader.get_agents()
AudioManager.play_sfx(my_stream)
```

All other cross-module communication uses injected references or Godot typed signals (see ADR-006).

### Architecture Diagram

```
[Godot Engine Boot]
       │
       ├─► ConfigLoader  (Autoload #1)   — config.json + user://settings
       │       └─► emits config_loaded
       │
       ├─► AudioManager  (Autoload #2)   — bus topology + 8-node pool
       │       └─► subscribes ConfigLoader.setting_changed
       │
       └─► [Main Scene _ready()]
               │
               ├─► TileMapRenderer  (subscene, per-room)
               ├─► RoomSystem        (reads ConfigLoader)
               ├─► DataBridge        (reads ConfigLoader)
               ├─► ASM [BLOCKED]     (subscribes DataBridge)
               ├─► ACC × N           (subscribes ASM)
               ├─► AAL               (subscribes ASM)
               ├─► TCB               (subscribes ASM.task_completed)
               └─► HUD               (subscribes ASM + TCB + RoomSystem)
```

### Key Interfaces

```gdscript
# ConfigLoader — Autoload, accessed by singleton name
ConfigLoader.get_agents() -> Array[Dictionary]
# Note: settings persistence API (get_setting / set_setting / is_mock) defined by ADR-002

# AudioManager — Autoload, accessed by singleton name
AudioManager.play_sfx(stream: AudioStream) -> void
```

## Alternatives Considered

### Alternative B: Expand Autoloads to include DataBridge and RoomSystem

- **Description**: Register DataBridge and RoomSystem as Autoloads for simpler global access.
- **Pros**: Any system can reach DataBridge without injection; simpler wiring in a small codebase.
- **Cons**: DataBridge owns `HTTPRequest` nodes (one per agent) with scene-scoped lifetimes. Autoloads are application-lifetime and cannot be freed mid-run. RoomSystem depends on scene geometry, creating a circular scene/singleton ambiguity.
- **Rejection Reason**: HTTPRequest lifetime must be scene-scoped. Expanding Autoloads beyond the minimum increases hidden coupling — any system can reach DataBridge without it being apparent from the code.

### Alternative C: Zero Autoloads — full manual bootstrap

- **Description**: ConfigLoader and AudioManager also instantiated by the Main Scene Bootstrap. All access via injection.
- **Pros**: No global state. Maximum testability.
- **Cons**: All 8 Phase 2 systems receive the same ConfigLoader and AudioManager references through injection. Overhead exceeds the coupling risk for genuinely project-wide services.
- **Rejection Reason**: ConfigLoader and AudioManager ARE used by every system in the project. The two-Autoload limit captures the correct boundary: global services are Autoloads; scene-specific systems are instantiated.

## Consequences

### Positive

- Deterministic boot with engine-guaranteed initialization order.
- Minimal coupling surface — only two systems are accessible globally by name.
- Non-autoload modules receive injected dependencies and are unit-testable in isolation.
- TileMapRenderer is multi-instantiable (one per room).
- New Autoloads require a superseding ADR — the forbidden pattern is registered.

### Negative

- The Main Scene Bootstrap becomes the most complex file in the codebase by design — it wires all Phase 2 systems. This is an intentional trade-off: explicit complexity in one place is better than hidden complexity distributed across many.
- Adding any new system requires touching the bootstrap.

### Risks

- **Phase 2 null reference crash**: if a Phase 2 system's `_ready()` accesses another Phase 2 system before the bootstrap has injected it, a null reference crash results. Mitigation: bootstrap always instantiates in dependency order; systems must not call each other in `_ready()` — all cross-system references arrive through bootstrap injection.
- **Autoload test isolation**: ConfigLoader and AudioManager exist as real singletons in GUT test scenes. ConfigLoader must provide a test-mode fallback (hardcoded safe defaults when `config.json` is absent) so GUT can run without a real configuration file. This constraint is delegated to ADR-002.
- **Web AudioContext unlock** (HTML5 export): browsers enforce that AudioContext can only resume after a user gesture. AudioManager must implement an "audio unlocked" flag set on the first `InputEventMouseButton` or `InputEventKey`. It must not attempt playback in `_ready()` or before this flag is set. Violating this policy silently drops audio in most browsers without throwing an error.
- **FileAccess write return type** (Godot 4.4+): `FileAccess.store_*` methods now return `bool` (was `void` pre-4.4, per breaking-changes.md). If ConfigLoader or any Autoload writes to `user://`, all write calls must check the return value. Responsibility for this verification is delegated to ADR-002.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `configuration-loader.md` | ConfigLoader must initialize before any scene's `_ready()` calls `get_agents()` | Registered as Autoload #1 — Godot engine guarantees this fires before any scene `_ready()` |
| `configuration-loader.md` | Config data must persist across potential scene changes | Autoload lifetime = application lifetime — ConfigLoader is never freed between scenes |
| `audio-manager.md` | AudioManager reachable by TCB, HUD settings panel, and future alert systems from any scene | Registered as Autoload #2 — globally accessible by singleton name from any scene |
| `audio-manager.md` | AudioManager must subscribe to `setting_changed` before TCB or HUD calls `play_sfx()` | Autoload #2 `_ready()` runs after Autoload #1 `_ready()` — subscription always succeeds |
| `room-system.md` | RoomSystem must read `get_agents()` during boot to build the room registry | This ADR guarantees ConfigLoader is available when RoomSystem._ready() runs (Phase 2, after Phase 1 completes) |

## Performance Implications

- **CPU**: Autoload `_ready()` runs once at boot. Negligible.
- **Memory**: Two persistent Node objects for the application lifetime. <1 KB each as pure GDScript nodes.
- **Load Time**: ConfigLoader reads `config.json` synchronously at boot. Acceptable for a developer tool with no startup SLA.
- **Network**: None.

## Migration Plan

N/A — no existing code. This ADR establishes the pattern before first implementation.

## Validation Criteria

- GUT: `test_config_loader_is_autoloaded()` — `ConfigLoader` is accessible as a global singleton in the GUT test scene without explicit instantiation.
- GUT: `test_audio_manager_is_autoloaded()` — `AudioManager` is accessible as a global singleton without explicit instantiation.
- GUT: `test_config_loader_has_test_mode_fallback()` — ConfigLoader returns safe defaults when `config.json` is absent (required for GUT test suite isolation).
- Manual: Boot the project — no null reference errors in the Godot Output panel during startup.
- Manual: GUT test suite passes without a real `config.json` present.

## Related Decisions

- ADR-002: Configuration Loading + Persistence — defines HOW ConfigLoader reads/writes its data; owns the test-mode fallback requirement and settings persistence API
- ADR-006: Signal-Based Decoupling Pattern — defines when Autoload direct calls are acceptable vs. when typed signals must be used
