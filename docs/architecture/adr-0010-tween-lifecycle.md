# ADR-0010: Tween Lifecycle Management

## Status
Accepted (2026-05-12)

## Date
2026-05-11

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.2 |
| **Domain** | Animation |
| **Knowledge Risk** | LOW for the API itself (no Tween-related breaking changes in 4.4–4.6 per `docs/engine-reference/godot/breaking-changes.md`); MEDIUM for behavioural detail on freed targets (VERIFY-9), mitigated by mandating `bind_node()` |
| **References Consulted** | `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/deprecated-apis.md`, `docs/engine-reference/godot/current-best-practices.md`, godot-specialist consultation 2026-05-11 |
| **Post-Cutoff APIs Used** | None — Tween API stable since 4.2 |
| **Verification Required** | Resolves VERIFY-9. New verification: GUT test confirming `bind_node()` cancels Tween cleanly when target freed mid-animation; GUT test confirming `kill()` does NOT emit `finished` |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0003 (Autoload Scene Composition — Accepted): establishes TCB/AAL/HUD as scene-scoped, instantiated by Main Scene Bootstrap. ADR-0006 (Signal-Based Decoupling — Accepted): establishes the forbidden patterns this ADR aligns with and carves out from |
| **Enables** | TCB, AAL, HUD implementation stories. ADR-0011 (HUD Rendering Strategy) will reference this for slot-timer Tween lifecycle |
| **Blocks** | All stories implementing room modulate beat, ambient state cross-fades, HUD slot timers — auto-blocked until this ADR is Accepted |
| **Ordering Note** | Should be Accepted before ADR-0009 (AnimationPlayer Strategy) so the Tween/AnimationPlayer boundary is established here first |

## Context

### Problem Statement

Three modules (Task Completion Beat, Ambient Animation Layer, Commander's Room HUD) create runtime `Tween` instances against Node2D / Control targets. Without a project-wide pattern, each module would independently solve:

1. **What happens when the target Node2D is freed mid-animation?** (VERIFY-9 — flagged in TCB E7, AAL state transitions, HUD slot timer expiry)
2. **How is a Tween re-triggered on the same target before the previous one finishes?** (TCB Rule 7 same-room rapid succession; AAL ERRORED preempting cross-fade)
3. **Does the Tween pause when the game pauses?** (HUD must keep running during a pause menu; TCB room flash must not)
4. **How is cleanup signalled — `finished` signal, `await`, or explicit?** (TCB Rule 5 expects emit-on-finish; HUD slot timer expects expiry callback)
5. **Does animating a presentation property like `modulate` on a node owned by another system violate the registered `direct_cross_system_state_write` forbidden pattern?** (TCB writes `modulate` on room nodes owned by Room System)

Inconsistent answers produce: silent reference-after-free errors, leaked Tweens, missed cleanup callbacks, double-trigger glitches, and architectural drift from the registered ban on cross-system state writes.

### Constraints
- Engine: Godot 4.6.2 / GDScript / 2D Renderer (CanvasItem)
- Target framerate: 60fps (≤16.6ms/frame budget)
- Scale: ≤12 concurrent agents, ≤12 concurrent room Tweens, ≤12 HUD slot-timer Tweens, ≤6 AAL ambient cross-fades = ~42 max concurrent Tweens
- Must align with existing forbidden patterns: `process_polling_for_state`, `scene_tree_discovery`, `direct_cross_system_state_write`
- Must work in headless GUT test mode (no rendering required)

### Requirements
- Project-wide single pattern for one-shot transient Tweens
- Safe under target-freed-mid-animation (no crash, no orphan leak, no "Object was freed" log spam)
- Predictable re-trigger semantics (kill+restart from current value)
- Pause-aware where appropriate (HUD always runs; game-world Tweens pause)
- Explicit cleanup contract that does not silently drop callbacks
- Codify whether Tween-driven presentation animation on cross-system nodes is sanctioned

## Decision

### TL;DR
Use Godot 4.6.2's `create_tween()` API with **mandatory `bind_node(target)`**. Re-trigger via `kill()` + new `create_tween()`. Subscribe to `finished` via signal (not `await`). Pause behaviour controlled by the owning Node's `process_mode`. Presentation-property animation (`modulate`, `scale`, transient `position`) on cross-system nodes is **explicitly sanctioned** and does not violate `direct_cross_system_state_write`.

### Tween Construction Pattern (mandatory)

Every runtime Tween in this project must follow this skeleton:

```gdscript
# ✅ CORRECT — mandatory pattern
var t: Tween = create_tween()
t.bind_node(target_node)                      # MANDATORY — auto-kill on target free
t.set_process_mode(Tween.TWEEN_PROCESS_IDLE)  # explicit even if default
t.set_ease(Tween.EASE_IN_OUT)                 # optional, set defaults here
t.set_trans(Tween.TRANS_SINE)
t.tween_property(target_node, "modulate", PEAK, ATTACK_SEC)
t.tween_property(target_node, "modulate", PEAK, HOLD_SEC)   # hold phase, linear
t.tween_property(target_node, "modulate", NEUTRAL, DECAY_SEC)
t.finished.connect(_on_tween_finished)        # cleanup via signal, NOT await
```

**`bind_node()` is non-negotiable.** It is the documented Godot 4.6.2 mechanism that auto-kills the Tween if `target_node` is freed mid-animation. Without it, the Tween's tweener step against the dead reference will log `"Object was freed"` errors and the Tween continues running as an orphan until SceneTree teardown.

### Sequential phases — single Tween, chained `tween_property()`

For multi-phase one-shot effects (TCB room flash: attack→hold→decay), use **one** `create_tween()` with three chained `tween_property()` calls. Do NOT create three separate Tweens.

```gdscript
# TCB room modulate Tween — single Tween, chained phases
var t: Tween = create_tween()
t.bind_node(room_node)
t.tween_property(room_node, "modulate", BEAT_PEAK, BEAT_ATTACK_SEC) \
    .set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
t.tween_property(room_node, "modulate", BEAT_PEAK, BEAT_HOLD_SEC) \
    .set_trans(Tween.TRANS_LINEAR)                                        # hold = linear
t.tween_property(room_node, "modulate", BEAT_NEUTRAL, BEAT_DECAY_SEC) \
    .set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
```

Note: `set_ease()` / `set_trans()` on the returned `PropertyTweener` apply per-step. On the Tween object itself they set defaults for subsequent tweeners.

### Re-trigger Pattern (kill + restart from current value)

When the same Tween must be re-triggered before completing (TCB Rule 7 same-room rapid succession, AAL ERRORED preempting cross-fade):

```gdscript
# ✅ CORRECT — kill the old, create a new from current value
if active_tween != null and active_tween.is_valid():
    active_tween.kill()
active_tween = create_tween()
active_tween.bind_node(target)
# rebuild tweener chain from target's CURRENT property value, not neutral
active_tween.tween_property(target, "modulate", PEAK, ATTACK_SEC)
```

**Never** use `Tween.stop()` for this purpose — `stop()` only pauses; `play()` resumes the original chain, which is not the intended semantic.

### `finished` Signal Behaviour (gotcha)

**`Tween.finished` is NOT emitted when the Tween is `kill()`ed.** This includes:
- Manual `tween.kill()` calls (re-trigger pattern)
- Auto-kill via `bind_node()` when target is freed

Therefore:
- Any cleanup logic that must run **whether the effect completes or is cancelled** must run *before* `kill()` is called, OR be tracked by a separate mechanism (e.g., a `state` variable cleared on both `_on_finished` and the kill path)
- Slot-timer logic (HUD) must NOT rely on `finished` to mark "effect ended" — it must use a `Timer` node or an explicit timeout coroutine

### Subscription Pattern — Signal, not `await`

```gdscript
# ✅ CORRECT
t.finished.connect(_on_beat_finished)

# ❌ FORBIDDEN — silently drops cleanup if the awaiting node is freed
await t.finished
```

`await tween.finished` is forbidden for any Tween whose target may be freed or whose Tween may be killed. If the awaiting coroutine's node is freed before completion, the continuation is silently abandoned and cleanup code never runs.

**Exception** (the only permitted use): purely local utility coroutines whose full lifetime is controlled within the same function and whose enclosing node is guaranteed alive for the duration. When in doubt, use a signal connection.

### Pause Behaviour

| Module | Effect | Node `process_mode` | Tween `process_mode` | Pauses with game? |
|---|---|---|---|---|
| TCB | Room flash | room node default (`INHERIT`) | `TWEEN_PROCESS_IDLE` | YES |
| AAL | Ambient cross-fade | room node default | `TWEEN_PROCESS_IDLE` | YES |
| HUD | Slot 1.5s timer + glyph | HUD root `PROCESS_MODE_ALWAYS` | `TWEEN_PROCESS_IDLE` | NO |
| HUD | Detail overlay fade | HUD root `PROCESS_MODE_ALWAYS` | `TWEEN_PROCESS_IDLE` | NO |

Pause behaviour is controlled by the **owning Node's** `process_mode`, not the Tween's. Set `PROCESS_MODE_ALWAYS` on the HUD root so its Tweens continue during a pause menu.

### Presentation-Property Carve-Out (sanctioned)

The registered forbidden pattern `direct_cross_system_state_write` (ADR-0006) prohibits a system from writing state owned by another system. This ADR establishes the following carve-out:

> **Presentation property animation** (`modulate`, `scale`, transient `position`/`rotation` for visual jitter) applied to a Node2D / Control owned by another system **is exempt** from `direct_cross_system_state_write`, provided:
> 1. The animating system has a sanctioned reference to the target node (injected at bootstrap or via signal payload)
> 2. The property has no semantic role in the owning system's domain logic (the Room System does not read `modulate` for decisions)
> 3. The Tween follows the mandatory `bind_node()` pattern in this ADR
>
> TCB's room modulate Tween qualifies under this exemption.

The general principle: properties whose value is purely visual and has no decision-affecting role for the owning system are presentation-layer side effects, not state writes.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ Module (TCB / AAL / HUD)                                        │
│                                                                  │
│  task_completed signal arrives                                  │
│         │                                                        │
│         ▼                                                        │
│  if active_tween: active_tween.kill()  ← re-trigger pattern     │
│         │                                                        │
│         ▼                                                        │
│  active_tween = create_tween()                                  │
│  active_tween.bind_node(target)         ← MANDATORY              │
│  active_tween.tween_property(...)       ← phase 1                │
│  active_tween.tween_property(...)       ← phase 2 (chained)      │
│  active_tween.finished.connect(...)     ← signal, NOT await      │
│                                                                  │
│  ◇ target freed mid-animation ────► Tween auto-killed silently  │
│  ◇ same module retriggers ────────► explicit kill() + recreate   │
│  ◇ game pauses ──────────────────► follows owning node's mode    │
└─────────────────────────────────────────────────────────────────┘
```

### Key Interfaces

This ADR does not introduce new APIs — it codifies the use pattern for Godot's existing `Tween` class. No interface contracts are added to `docs/registry/architecture.yaml` interfaces section. One new forbidden pattern (`tween_without_bind_node`) and one new API decision (`tween_lifecycle_pattern`) are added when this ADR is Accepted.

## Alternatives Considered

### Alternative A — AnimationPlayer-only

- **Description**: Replace all runtime Tweens with pre-authored `AnimationPlayer` tracks. Each effect (room flash, slot timer, ambient cross-fade) becomes a named animation in a `.tres` resource.
- **Pros**: Robust auto-cleanup (AnimationPlayer owns its tracks); editor-tunable; no `bind_node()` foot-gun.
- **Cons**: Heavyweight for one-shot transient effects; requires authoring 6+ animation resources for variants TCB currently does in code; `kill()` + restart-from-current-value requires AnimationPlayer-specific gymnastics (seeking, blend tree); does not match TCB Rule 3's "computed from constants" philosophy.
- **Rejection Reason**: Wrong tool for transient code-driven effects. Reserved for sprite state animations (covered by future ADR-0009).

### Alternative B — Centralised Tween Manager

- **Description**: One Autoload `TweenManager` owns all Tweens; modules call `TweenManager.beat_flash(room_node)` instead of `create_tween()`.
- **Pros**: Centralised lifecycle; easier to mock in tests; consistent.
- **Cons**: Violates `new_autoload_without_adr` (would require superseding ADR-0003); creates the exact "hidden global dependency" that ADR-0003 banned; turns module-local effects into cross-system coupling; Godot's `Tween` is already a managed object — wrapping it adds no value.
- **Rejection Reason**: Direct conflict with ADR-0003's two-Autoload limit and ADR-0006's Tier 1/2/3 communication model.

### Alternative C — Tween Pool

- **Description**: Pre-instantiate a pool of Tween objects at bootstrap, lease them per beat.
- **Pros**: Predictable memory allocation; matches Audio Manager's pool pattern.
- **Cons**: Tween state is entangled with its tweener chain — reuse creates ordering bugs; godot-specialist confirmed `create_tween()` is cheap at this project's scale (≤42 concurrent Tweens vs 16.6ms budget); pooling is documented as a Godot 4 anti-pattern for Tween specifically.
- **Rejection Reason**: No performance benefit, real risk of subtle bugs.

## Consequences

### Positive
- Single pattern across TCB, AAL, HUD — code review can mechanically verify
- VERIFY-9 closed: `bind_node()` is the documented mitigation
- TCB Rule 7 (kill+restart) is now codified project-wide, not TCB-local
- Presentation-property carve-out unblocks TCB without weakening `direct_cross_system_state_write` for actual state writes
- No new Autoload, no engine-API gymnastics, no post-cutoff features

### Negative
- `bind_node()` is easy to forget — adds a new code review checklist item
- `kill()` not emitting `finished` is a footgun that must be documented in onboarding
- `await tween.finished` is a natural-feeling pattern that's now forbidden — developers must learn the signal subscription idiom

### Risks

| Risk | Mitigation |
|---|---|
| Developer forgets `bind_node()` → orphan Tween on freed target | Lint check in code review; GUT test asserting `bind_node()` cleanup; documented in `docs/architecture/control-manifest.md` |
| Cleanup logic relies on `finished` for the killed path | Documented in this ADR + control manifest; GUT test confirming `finished` does NOT fire after `kill()` |
| HUD Tweens incorrectly pause with game | HUD root must set `PROCESS_MODE_ALWAYS` — covered by HUD GDD AC and code review |
| Presentation-property carve-out gets stretched to cover actual state writes | Carve-out explicitly enumerates allowed properties (`modulate`, `scale`, transient `position`/`rotation`); any other property requires a new ADR |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `task-completion-beat.md` | Rule 3 (room modulate Tween 3-phase shape) | Mandates single Tween with chained `tween_property()`, ease/trans applied per-phase |
| `task-completion-beat.md` | Rule 7 (same-room re-trigger from current value) | Codifies `kill()` + new `create_tween()` pattern project-wide |
| `task-completion-beat.md` | E7 / VERIFY-9 (Tween on freed Node2D) | Mandates `bind_node(target)`; closes VERIFY-9 |
| `ambient-animation-layer.md` | Rule 8 (state transitions cross-fade via Tween) | Same `bind_node()` + `kill()` patterns apply |
| `ambient-animation-layer.md` | Edge case (ERRORED preempts in-progress cross-fade) | Same kill+restart pattern as TCB Rule 7 |
| `commanders-room-hud.md` | TR-hud-004 (per-slot 1.5s timer after `beat_fired`) | HUD uses `PROCESS_MODE_ALWAYS` for pause-immune timers; cleanup via `Timer` node, not `Tween.finished` |
| Cross-cutting | Registry `direct_cross_system_state_write` interaction | Carve-out explicitly sanctions presentation-property animation on cross-system nodes |

## Performance Implications
- **CPU**: ~42 max concurrent Tweens × ~few µs each = negligible against 16.6ms budget; godot-specialist confirmed `create_tween()` is cheap
- **Memory**: Tween objects are lightweight; no pooling required; `bind_node()` ensures no leaks
- **Load Time**: Zero — Tweens are runtime constructs
- **Network**: N/A (single-player local tool)

## Migration Plan
No existing code to migrate (pre-production). This ADR's patterns apply at first implementation.

## Validation Criteria
- GUT test: `test_tween_bind_node_kills_on_target_free` — confirm Tween is killed (not orphaned) when bound target is freed
- GUT test: `test_tween_kill_does_not_emit_finished` — confirm `finished` is not emitted on `kill()`
- GUT test: `test_tcb_retrigger_starts_from_current_value` — TCB Rule 7 behaviour
- Code review checklist additions:
  - "Every `create_tween()` is followed immediately by `.bind_node()`?"
  - "No `await tween.finished` in any code path where target may be freed?"
  - "Cleanup logic does not assume `finished` fires on `kill()`?"

## Related Decisions
- ADR-0003: Autoload Scene Composition (foundation)
- ADR-0005: task_completed Signal Source (trigger for TCB Tweens)
- ADR-0006: Signal-Based Decoupling (carved-out forbidden pattern)
- ADR-0009 (planned): AnimationPlayer Strategy — will define the boundary between Tween (transient) and AnimationPlayer (repeating)
- VERIFY-9 in `production/session-state/active.md` — closed by this ADR
