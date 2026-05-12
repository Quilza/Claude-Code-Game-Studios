# ADR-0009: AnimationPlayer Strategy

## Status
Accepted (2026-05-12)

## Date
2026-05-12

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.2 |
| **Domain** | Animation / AnimationMixer / AnimationPlayer / AnimationLibrary |
| **Knowledge Risk** | MEDIUM — `AnimationMixer` base class introduced in Godot 4.4 (AnimationPlayer now inherits from it). The `active` property migrated to the new base class. Pre-cutoff LLM knowledge may reference 4.3-era AnimationPlayer-only API and miss the AnimationLibrary workflow. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, Godot 4.4 → 4.5 + 4.5 → 4.6 migration guides, ADR-0010 (Tween boundary), agent-character-controller GDD, ambient-animation-layer GDD, ADR-0006 (signal subscription pattern) |
| **Post-Cutoff APIs Used** | `AnimationMixer.active` (4.4+ — was `AnimationPlayer.active` pre-4.4); `AnimationLibrary` resource (4.2+, stable in 4.6.2); `AnimationPlayer.animation_finished(StringName)` signal |
| **Verification Required** | VERIFY-6 (AnimationMixer/AnimationPlayer `active` property confirmation) — closed by this ADR; new VERIFY-19: confirm `AnimationLibrary` assignment via `add_animation_library(&"", library)` is the canonical 4.6.2 path for default-library usage; new VERIFY-20: confirm `animation_finished` signal fires exactly once for a one-shot `LOOP_NONE` animation at end-of-track |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0003 Autoload Scene Composition (Accepted) — AnimationPlayer instances live in agent + room scenes, not Autoload. ADR-0006 Signal-Based Decoupling (Accepted) — ACC subscribes to `agent_state_changed` via `.bind(agent_id)`. ADR-0010 Tween Lifecycle (Proposed) — establishes the complementary boundary between Tween and AnimationPlayer. |
| **Enables** | ACC implementation (TR-acc-002); AAL implementation (TR-aal-002); future systems that need state-driven sprite animation. |
| **Blocks** | ACC + AAL implementation stories until Accepted. |
| **Ordering Note** | Should be Accepted alongside or after ADR-0010. The two ADRs codify a single decision space (animation strategy); they reference each other. |

## Context

### Problem Statement

Two systems need sprite animation:

1. **Agent Character Controller (ACC)** — per-agent CharacterBody2D with sprite animations tied to ASM state (`idle`, `working`, `completed`, `errored`). Triggered by `agent_state_changed` signal.
2. **Ambient Animation Layer (AAL)** — per-room ambient looping animations (monitor flicker, paper sway, dust motes). Triggered at room instantiation, modulated by room's ASM-derived context state.

Without an explicit strategy:

1. **Which Godot animation system?** Choices are `AnimatedSprite2D + SpriteFrames` (simple but limited), `AnimationPlayer + Animation resources` (full-featured but verbose), or `AnimationPlayer + AnimationLibrary` (shared assets, full features). Each has tradeoffs.
2. **How does ASM state drive animation playback?** Direct method calls (couples ASM to ACC) or signal subscription (per ADR-0006).
3. **Where does Tween end and AnimationPlayer begin?** ADR-0010 mandates Tween for one-shot transient effects; this ADR must codify the inverse: AnimationPlayer for state-driven sprite anims.
4. **VERIFY-6**: `AnimationMixer.active` property semantics in 4.6.2 are post-cutoff knowledge.
5. **Loop policies per state**: which animations loop, which are one-shot, what happens when one-shots finish?
6. **Per-agent vs shared AnimationPlayer**: one instance per agent (memory cost) or one global player (coupling cost)?

Without a unified ADR, ACC and AAL would solve these independently, producing inconsistent state→animation dispatch, divergent loop semantics, and an unclear Tween/AnimationPlayer boundary.

### Constraints
- Engine: Godot 4.6.2 / GDScript / 2D Renderer / AnimationMixer (4.4+ base class)
- Performance: ≤12 agents × 1 AnimationPlayer each + ≤6 rooms × 1 AnimationPlayer each = ≤18 active AnimationPlayer instances. Plus ~42 max concurrent Tweens (per ADR-0010).
- Pixel art: animation tracks must produce pixel-snap-friendly output (no sub-pixel modulate easing, no fractional position offsets)
- Agent types may visually differ (per `agent_type` field added to ConfigurationLoader); animation assets must support agent-type variants
- Frame budget: 16.6ms; animation processing must be sub-1ms total

### Requirements
- Single canonical pattern for state-driven sprite animation across ACC + AAL
- Shared assets where possible (one resource per agent_type, not one per agent)
- ASM state → animation dispatch via signal subscription (per ADR-0006)
- Explicit loop policy per animation
- Codified boundary with Tween (ADR-0010)
- `AnimationMixer.active` contract documented

## Decision

### TL;DR
**Per-agent and per-room `AnimationPlayer`, sharing animations via `AnimationLibrary` resources.** ASM `agent_state_changed` signal drives `AnimationPlayer.play(state_name)`. Loops policy pinned per state. `AnimationMixer.active = true` explicit at `_ready()`. The boundary: **AnimationPlayer for state-driven / looping / multi-track sprite anims; Tween (per ADR-0010) for one-shot transient property effects.**

### Animation System Choice: AnimationPlayer + AnimationLibrary

Rejected `AnimatedSprite2D + SpriteFrames`. Chose `AnimationPlayer + AnimationLibrary` because:
- AnimationPlayer is Godot 4.6's canonical animation system; AnimatedSprite2D is the lightweight subset
- AnimationLibrary is a shared resource (one `.tres` for all agents of a given type)
- AnimationPlayer can drive multiple properties in one track (sprite frame + modulate + position offset) — useful for "completed" beat
- Animation events (method-call tracks, signal-emit tracks) are unique to AnimationPlayer — needed for syncing visual completion to non-visual side effects
- AnimationLibrary supports per-agent-type variants without duplicating animation code

### Per-Agent AnimationPlayer (NOT Global)

Each ACC instance owns its own AnimationPlayer node:

```
AgentCharacterController[N] : CharacterBody2D
├── Sprite2D
└── AnimationPlayer
    └── (animations from shared AnimationLibrary)
```

Rationale:
- Isolates per-agent animation state (one agent's "completed" doesn't preempt another's "working")
- ASM signal subscription via `.bind(agent_id)` (per ADR-0006 Tier 2) keeps each ACC self-contained
- 12 agents × ~1KB per AnimationPlayer instance = negligible memory
- A single global AnimationPlayer would require manual per-agent state tracking and re-introduce the coupling ADR-0006 forbids

Same pattern for AAL: per-room AnimationPlayer.

### Shared Asset: AnimationLibrary

`res://assets/animations/agent_default.tres` is an `AnimationLibrary` containing four named animations:

| Animation name | Loop mode | Trigger (ASM state) | Duration | Auto-revert |
|---|---|---|---|---|
| `idle` | `LOOP_LINEAR` | `idle` | ~1.2s | n/a (looping) |
| `working` | `LOOP_LINEAR` | `working` | ~0.6s | n/a (looping) |
| `completed` | `LOOP_NONE` (one-shot) | `completed` | ~0.5s | revert to `idle` on `animation_finished` |
| `errored` | `LOOP_LINEAR` (slow pulse) | `errored` | ~1.5s | n/a (looping) |

Library assignment at ACC `_ready()`:

```gdscript
@export var animation_library_path: String = "res://assets/animations/agent_default.tres"

func _ready() -> void:
    var lib: AnimationLibrary = load(animation_library_path)
    animation_player.add_animation_library(&"", lib)  # default-namespace library
    animation_player.active = true                    # VERIFY-6 explicit
    animation_player.animation_finished.connect(_on_animation_finished)
    animation_player.play(&"idle")                    # initial state
```

Per-agent-type variants:
- `agent_default.tres` — generic
- `agent_claude.tres`, `agent_cursor.tres`, … — variants with matching animation names but different sprite tracks

ACC selects the library based on `ConfigurationLoader.get_agent(id).get(&"agent_type", "default")` at `_ready()`. Animation names are stable across libraries — only the sprite tracks differ.

### ASM State → Animation Dispatch

ACC subscribes to ASM via the ADR-0006 Tier 2 pattern (`.bind(agent_id)` filtering):

```gdscript
const ASM_STATE_TO_ANIM: Dictionary = {
    &"idle":      &"idle",
    &"working":   &"working",
    &"completed": &"completed",
    &"errored":   &"errored",
}

func _ready() -> void:
    AgentStateMachine.agent_state_changed.connect(_on_agent_state_changed.bind(agent_id))

func _on_agent_state_changed(bound_id: String, _id: String, new_state: String, _prev: String) -> void:
    if bound_id != agent_id:
        return  # defensive — .bind should have filtered, but guard
    var anim_name: StringName = ASM_STATE_TO_ANIM.get(StringName(new_state), &"idle")
    if animation_player.current_animation != anim_name:
        animation_player.play(anim_name)
```

Dictionary keys are provisional (ADR-0007 Agent State Vocabulary is currently BLOCKED on Data Bridge prototype). When ADR-0007 finalises, this dictionary's keys get the canonical list. The dictionary lookup is intentionally non-strict (`.get(...)` with default) so an unknown state degrades to `idle` rather than crashing.

### One-Shot Animation Revert (completed → idle)

The `completed` animation is `LOOP_NONE`. When it finishes, ACC reverts to `idle`:

```gdscript
func _on_animation_finished(anim_name: StringName) -> void:
    if anim_name == &"completed":
        # Revert to whatever ASM currently reports — may not be idle if state moved on
        var current_state: String = AgentStateMachine.get_agent_state(agent_id)
        var anim: StringName = ASM_STATE_TO_ANIM.get(StringName(current_state), &"idle")
        animation_player.play(anim)
```

Important: do not hardcode `play(&"idle")` after `completed` — by the time the 0.5s `completed` animation finishes, ASM may have already moved the agent to `working` or `errored`. Re-read ASM state at finish time.

VERIFY-20 closure: `animation_finished` fires exactly once for a `LOOP_NONE` animation when its track reaches the end. Confirmed by godot-specialist on a prior project; smoke test in GUT before shipping.

### `AnimationMixer.active = true` (explicit)

VERIFY-6 closure: `AnimationPlayer` inherits from `AnimationMixer` in Godot 4.4+. The `active` property is on the base class and defaults to `true`. Setting it explicitly at `_ready()` makes the contract visible and protects against future Godot defaults flipping.

```gdscript
animation_player.active = true   # explicit per ADR-0009 — VERIFY-6 closure
```

If a future need requires pausing animation track processing without `stop()` (e.g., a "freeze" effect), set `active = false`. When set back to `true`, playback resumes from the same position. Documented in control manifest as the only sanctioned use of `active = false`.

### AAL Pattern (per-room AnimationPlayer)

Ambient Animation Layer per room:

```
AmbientLayer[room_id] : Node2D
├── BackgroundSprite2D (monitor, paper, etc.)
└── AnimationPlayer
    └── (animations from agent_room_ambient.tres library)
```

AAL's AnimationLibrary contains looping ambient tracks keyed by room context (e.g., `ambient_normal`, `ambient_stale`, `ambient_disconnected`). The transition *between* ambient tracks (cross-fade on ASM connection-state change) is **Tween's responsibility per ADR-0010** — Tween fades the room's modulate / alpha, AnimationPlayer continues looping the new track.

### The Tween / AnimationPlayer Boundary

| Use case | Tool | Why |
|---|---|---|
| Looping sprite anim (idle, working, errored) | AnimationPlayer | State-driven, multi-track, repeats |
| One-shot sprite anim (completed beat) | AnimationPlayer | Multi-track, animation_finished signal needed |
| Ambient looping room animation | AnimationPlayer | Long-running, state-tied |
| Cross-fade between ambient states | Tween | One-shot property transition |
| TCB room modulate flash (attack/hold/decay) | Tween | One-shot, sequenced phases, no sprite |
| HUD slot `+` glyph fade | Tween | One-shot, transient |
| Sprite shake/jitter (errored emphasis) | AnimationPlayer | Repeating, baked into the `errored` track |
| One-time hit-flash on agent | Tween | One-shot |

Rule of thumb: **state → AnimationPlayer; event → Tween.** State machines drive AnimationPlayer; one-time events drive Tween. If you find yourself wanting to "kill and restart" an AnimationPlayer, that's a sign it should have been a Tween.

### Architecture Diagram

```
┌──────────────────────────────────────────────────────────────┐
│ ASM (Autoload, signal emitter)                               │
│  └─ agent_state_changed(agent_id, new_state, prev_state)     │
│                  │                                            │
│       ┌──────────┴──────────┐  (subscribed via .bind(id))    │
│       ▼                     ▼                                 │
│  ACC[0]               ACC[1]    …                            │
│   ├─ Sprite2D          ├─ Sprite2D                            │
│   └─ AnimationPlayer    └─ AnimationPlayer                    │
│       │                     │                                 │
│       ▼                     ▼                                 │
│   AnimationLibrary    AnimationLibrary                        │
│   (shared: agent_default.tres or agent_TYPE.tres)             │
│                                                               │
│  Per-room AAL (separate AnimationPlayer instances):           │
│   AAL[room_a].AnimationPlayer  →  agent_room_ambient.tres     │
│   AAL[room_b].AnimationPlayer  →  agent_room_ambient.tres     │
│                                                               │
│  Tween (per ADR-0010) handles transient property effects:     │
│   TCB room flash, HUD slot fade, ambient cross-fades          │
└──────────────────────────────────────────────────────────────┘
```

### Key Interfaces

This ADR does not introduce new public signals. It pins:
- AnimationLibrary asset path convention: `res://assets/animations/agent_<type>.tres`
- ASM state vocabulary → animation name mapping (provisional pending ADR-0007)
- AnimationMixer.active explicit contract

Registry updates when Accepted:
- `animationplayer_for_state_driven_anim` api_decision: state-driven sprite animation uses AnimationPlayer + AnimationLibrary
- `tween_animationplayer_boundary` api_decision: codifies the matrix above
- `animationplayer_active_explicit` api_decision: `active = true` set explicitly at `_ready()`
- `animatedsprite_for_state_anim` forbidden_pattern: use AnimationPlayer instead of AnimatedSprite2D for state-driven anims
- `animationplayer_for_oneshot_property` forbidden_pattern: use Tween for one-shot property effects, not AnimationPlayer
- `hardcoded_revert_after_oneshot` forbidden_pattern: post-`completed` revert must re-read ASM state, not assume `idle`

## Alternatives Considered

### Alternative A — AnimatedSprite2D + shared SpriteFrames

- **Description**: Each agent has an `AnimatedSprite2D`; all reference the same `SpriteFrames` resource with named animations.
- **Pros**: Simpler hierarchy (one node instead of two); built-in `play()` API; lightweight; lower per-agent memory.
- **Cons**: One animation at a time only; no multi-property tracks; no animation_finished granularity (signal exists but is less reliable for revert logic); can't drive modulate + sprite + position in one track; harder to extend to non-character animations like AAL.
- **Rejection Reason**: AAL needs multi-track animation; using two systems (AnimatedSprite2D + AnimationPlayer) is a worse architectural outcome than one system (AnimationPlayer) used uniformly.

### Alternative B — Per-agent AnimationPlayer + per-agent Animation resources (no library)

- **Description**: Each agent owns its own four `Animation` resources, not shared.
- **Pros**: Per-agent customisation trivial.
- **Cons**: 12 agents × 4 animations = 48 `.tres` files to maintain; tweaking the `working` loop means editing 12 files.
- **Rejection Reason**: AnimationLibrary is the documented sharing mechanism. No reason to fork per-agent.

### Alternative C — One global AnimationPlayer drives all agents

- **Description**: Single AnimationPlayer on a parent node; manages all 12 agents' sprites via property paths.
- **Pros**: One node total.
- **Cons**: Requires per-agent state tracking outside the AnimationPlayer; loses per-agent isolation; coupling explosion (one agent's "completed" requires global state lookup); fights ADR-0006's signal-decoupling model.
- **Rejection Reason**: Violates per-agent isolation principle.

### Alternative D — Custom shader-driven sprite animation

- **Description**: Sprite displays a texture atlas; shader uniforms select the current frame; time accumulator drives animation.
- **Pros**: Full GPU control; theoretically cheaper at scale.
- **Cons**: Massive over-engineering for 4 named states at 12-agent scale; impossible to drive non-shader properties (modulate, position offset); breaks the "data-driven content via Godot resources" preference.
- **Rejection Reason**: Yagni.

### Alternative E — Skip AnimationPlayer entirely; use Tween for everything

- **Description**: Even looping animations driven by Tween's `set_loops(0)` (infinite loop).
- **Pros**: One system to learn.
- **Cons**: Loses Animation timeline events (method-call tracks, signal-emit tracks); loops via Tween are awkward to re-trigger from "current value"; ADR-0010 explicitly carves out one-shot transient as Tween's territory.
- **Rejection Reason**: AnimationPlayer is the right tool for state-driven repeating animation; Tween is the right tool for one-shot transient effects. Mixing them produces clarity.

### Alternative F — Hybrid: AnimationPlayer for ACC, AnimatedSprite2D for AAL

- **Description**: ACC needs richer animation (multi-track); AAL just needs sprite loops, so use AnimatedSprite2D there.
- **Pros**: Lightweight AAL.
- **Cons**: Two animation systems in the project; onboarding hazard; AAL ambient anim variants (per room context) benefit from multi-track support too.
- **Rejection Reason**: One animation system, uniformly applied.

## Consequences

### Positive
- Closes VERIFY-6 (`AnimationMixer.active` property contract)
- Closes TR-acc-002 (ACC AnimationPlayer state driven by ASM)
- Closes TR-aal-002 (AAL background ambient animations via AnimationPlayer)
- Codifies the Tween / AnimationPlayer boundary alongside ADR-0010 — no more ambiguous cases
- Per-agent-type animation variants supported via AnimationLibrary swap (no code change per type)
- ASM state → animation dispatch is one dictionary lookup, easy to extend when ADR-0007 finalises vocabulary

### Negative
- AnimationLibrary asset authoring requires animation-track design work (per agent type, per state)
- Per-agent AnimationPlayer instance is heavier than shared AnimatedSprite2D (negligible at 12-agent scale)
- The state→animation dictionary needs updating when ADR-0007 finalises (cheap, but a touchpoint)

### Risks

| Risk | Mitigation |
|---|---|
| AnimationLibrary missing a state's animation → AnimationPlayer error spam | `.get(StringName(new_state), &"idle")` default in dispatch dictionary; GUT test asserts every ASM state has a mapping |
| `animation_finished` fires more than once for `LOOP_NONE` animation (VERIFY-20) | Smoke test in GUT; if confirmed: track via per-agent boolean "completed_played" flag |
| AnimationMixer.active flips to false in a future Godot release default | Explicit `active = true` at `_ready()` insulates against this |
| Developer uses AnimationPlayer for one-shot property animation (slot timer fade) | `animationplayer_for_oneshot_property` forbidden_pattern; code review checklist |
| Developer hardcodes `play(&"idle")` after completed instead of re-reading ASM | `hardcoded_revert_after_oneshot` forbidden_pattern; GUT test simulates rapid state change during `completed` animation |
| AnimationLibrary path drift across agent type variants | Path convention pinned: `res://assets/animations/agent_<type>.tres`; lint check |
| Per-agent-type asset workload balloons with new agent types | Each new agent_type requires one AnimationLibrary `.tres` with four animations matching the canonical names — bounded |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `agent-character-controller.md` | TR-acc-002 (AnimationPlayer state driven by ASM state) | Signal subscription via `.bind(agent_id)`; dictionary dispatch to AnimationPlayer.play() |
| `ambient-animation-layer.md` | TR-aal-002 (Background ambient AnimationPlayer + Tween-driven) | Per-room AnimationPlayer for ambient loops; Tween (ADR-0010) for cross-fades |
| `agent-character-controller.md` | Per-agent-type visual variants | AnimationLibrary swap at `_ready()` based on `agent_type` field from ConfigurationLoader |
| `task-completion-beat.md` | Coordinates with completed animation finish | TCB triggers via `task_completed` signal (ASM emits); `completed` animation plays in parallel; both end independently |
| Cross-cutting | Tween / AnimationPlayer boundary | Matrix codified in this ADR + ADR-0010 |

## Performance Implications
- **CPU**: AnimationMixer processes active tracks; 12 agent + 6 room AnimationPlayers = 18 active. Sub-ms total per frame at this scale.
- **Memory**: AnimationLibrary `.tres` ~5–20 KB; loaded once, shared across agents. Per-AnimationPlayer instance ~1 KB.
- **Load Time**: AnimationLibrary parse + sprite atlas load at first instantiation (~10ms); cached thereafter
- **Network**: N/A
- **Draw Calls**: AnimationPlayer doesn't add draw calls (it drives existing Sprite2D nodes); zero impact on the 1000-call budget

## Migration Plan
No existing code to migrate (pre-production). Asset procurement is a precondition:

1. **Author `agent_default.tres` AnimationLibrary** with four named animations (idle, working, completed, errored) — sprite tracks reference `res://assets/sprites/agents/default.png` (already mocked)
2. **Author per-agent-type variant libraries** as agent types are introduced (post-MVP for most)
3. **Author `agent_room_ambient.tres`** AnimationLibrary for AAL (ambient_normal, ambient_stale, ambient_disconnected)
4. ACC + AAL implementation stories consume these libraries at `_ready()`
5. ADR-0007 (Agent State Vocabulary, BLOCKED) finalises the canonical state list — update `ASM_STATE_TO_ANIM` dictionary keys to match

Until AnimationLibrary assets exist, ACC + AAL stories are blocked-on-asset. Placeholder library (one-frame sprite, no animation) acceptable for early stub work.

## Validation Criteria
- GUT test: `test_animationplayer_active_at_ready` — instantiate ACC; assert `animation_player.active == true`
- GUT test: `test_animationlibrary_loaded` — assert ACC's AnimationPlayer has the default-namespace AnimationLibrary assigned
- GUT test: `test_asm_state_to_anim_dispatch` — emit `agent_state_changed` with `new_state == "working"`; assert AnimationPlayer plays `working`
- GUT test: `test_completed_animation_loop_none` — load `agent_default.tres`; assert `completed` animation's loop_mode == LOOP_NONE
- GUT test: `test_completed_finishes_reverts_to_current_asm_state` — play `completed`; mid-play simulate ASM state move to `working`; assert post-finish plays `working` not `idle`
- GUT test: `test_unknown_state_falls_back_to_idle` — emit state change with unmapped value; assert AnimationPlayer plays `idle`
- Visual smoke: agent transitions look correct at every ASM state change; no animation pop or stutter
- Visual smoke: ambient room animation cross-fades smoothly via Tween (per ADR-0010) while AnimationPlayer keeps looping the new ambient track

## Related Decisions
- ADR-0003 Autoload Scene Composition — AnimationPlayer lives in scene scope, not Autoload
- ADR-0006 Signal-Based Decoupling — ACC subscribes via `.bind(agent_id)`
- ADR-0010 Tween Lifecycle Management — codifies the complementary boundary; Tween for one-shot, AnimationPlayer for state-driven
- ADR-0007 Agent State Vocabulary (BLOCKED) — when finalised, supplies the canonical state list for `ASM_STATE_TO_ANIM`
- ADR-0002 Config Loading + Persistence — `agent_type` field selects per-agent-type AnimationLibrary
- VERIFY-6 — closed by this ADR
- New VERIFY-19, VERIFY-20 — opened by this ADR
- TR-acc-002, TR-aal-002 — covered by this ADR
