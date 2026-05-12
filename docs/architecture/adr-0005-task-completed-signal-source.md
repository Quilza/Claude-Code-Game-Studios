# ADR-0005: task_completed Signal Source

## Status
Accepted (2026-05-12)

## Date
2026-05-11

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.2 |
| **Domain** | Core / Scripting |
| **Knowledge Risk** | LOW — signal system stable since Godot 4.0; no changes in 4.4–4.6 |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/deprecated-apis.md` |
| **Post-Cutoff APIs Used** | None — `signal.emit()` and typed signal declarations established in Godot 4.0 |
| **Verification Required** | None — signal system unchanged across 4.4–4.6 per engine reference |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0003 (Autoload Scene Composition) — establishes the bootstrap that wires signal connections; ADR-0006 (Signal-Based Decoupling Pattern) — governs the Tier 1 signal pattern this ADR uses |
| **Enables** | TaskCompletionBeat implementation (connects to task_completed to fire beat sequence); CommandersRoomHUD implementation (connects to task_completed to update recent completions panel); Agent State Machine GDD (ASM is now formally assigned ownership of this signal) |
| **Blocks** | Any implementation of TCB or HUD that subscribes to task completion events |
| **Ordering Note** | Write before ASM GDD is finalized, before TCB implementation, and before HUD implementation. ADR-0003 and ADR-0006 must be written first. |

## Context

### Problem Statement

`task_completed` is the central semantic event in this application — it is what the entire visual and audio feedback pipeline responds to. Three modules need it: TaskCompletionBeat (subscribes to trigger its beat sequence), CommandersRoomHUD (subscribes to update its recent completions panel), and by implication any future system that cares when an agent finishes work.

Without a designated emitter, every ADR and GDD that mentions this event must add a provisional note, and the wrong module may end up emitting it during implementation. This ADR designates the canonical owner so all downstream documents can reference a definitive source.

### Constraints

- **DataBridge must not emit semantic events.** DataBridge's core design constraint (from `data-bridge.md`) is that it passes raw API payloads without interpretation. It cannot determine "task completed" from a raw String payload — that requires field parsing and state logic that belongs elsewhere.
- **AgentCharacterController is per-agent.** ACC subscribes to ASM state changes to drive character animations. Having ACC re-emit a signal would create a double-dispatch pattern (ASM fires state_changed → ACC receives it → ACC re-emits task_completed) with coupled timing, duplicated interpretation logic across up to 12 ACC instances, and no single authoritative source.
- **task_completed is a state transition event.** State transitions are the Agent State Machine's domain by definition. ASM is the only module that interprets DataBridge raw payloads and maintains authoritative agent states.
- **Signal must be typed.** Per ADR-0006, all cross-module signals require typed parameters. No `Variant` in the signature.
- **`agent_id` must be `String`, not `StringName`.** The source value originates from HTTP response parsing (a `String`). Emitting as `StringName` forces a conversion on every emission. Dictionary key lookups in TCB's `AgentSoundRegistry` can accept `String` directly.

### Requirements

- One module is the sole emitter of `task_completed` — no other module may emit this signal
- Signal is typed: parameters carry only what subscribers need to react correctly
- Signal name is past-tense (per ADR-0006 naming convention)
- Emitter is semantically appropriate — it must own the knowledge of when a task has completed

## Decision

**AgentStateMachine (`AgentStateMachine`) is the sole emitter of `task_completed`.**

No other module may emit this signal. DataBridge, ACC, TCB, HUD, and all other modules are consumers only.

### Signal Declaration

Declared in `res://src/core/agent_state_machine.gd`:

```gdscript
## Emitted when an agent transitions to a task-completed state.
## Sole emitter: AgentStateMachine.
## Consumers: TaskCompletionBeat, CommandersRoomHUD
## agent_id: the ID string as returned by ConfigLoader.get_agents()
signal task_completed(agent_id: String)
```

### Emission Site

```gdscript
# In AgentStateMachine — called when interpreting a DataBridge payload
# that indicates a task has successfully completed for an agent.
func _evaluate_state_transition(agent_id: String, raw_payload: String) -> void:
    var new_state := _parse_agent_state(raw_payload)
    var previous_state := _agent_states.get(agent_id, "IDLE")

    if new_state == previous_state:
        return  # No transition — do not emit

    _agent_states[agent_id] = new_state
    agent_state_changed.emit(agent_id, new_state, previous_state)

    if new_state == "COMPLETED":
        task_completed.emit(agent_id)
```

`task_completed` is emitted **after** `agent_state_changed` on the same state transition. Consumers of `agent_state_changed` that react to the `"COMPLETED"` state will fire on the same frame as `task_completed` subscribers. The order of signal delivery for the two signals matches the order of `emit()` calls — `agent_state_changed` fires first, then `task_completed`.

### Connection Pattern (Bootstrap)

Per ADR-0006 Tier 1, connections are wired by the Main Scene Bootstrap after all Phase 2 systems are added to the scene tree:

```gdscript
# In res://src/main/main_bootstrap.gd — _ready(), after all systems added:
_agent_state_machine.task_completed.connect(_task_completion_beat._on_task_completed)
_agent_state_machine.task_completed.connect(_commanders_room_hud._on_task_completed)
```

**Subscriber disconnect rule**: TCB and HUD are the same lifetime as ASM (all Phase 2, same scene). Do NOT call `disconnect()` — Godot 4.x auto-cleans dead connections when a node is freed. If a shorter-lived node subscribes in the future, it must disconnect in its `_exit_tree()`.

### Architecture Diagram

```
DataBridge
    │
    └─► agent_response_received(agent_id, http_status, raw_payload)
            │
            ▼
    AgentStateMachine  ←── sole interpreter of raw payload
            │
            ├─► agent_state_changed(agent_id, new_state, previous_state)
            │         └─► ACC × N (animation), HUD (status display), AAL (ambient props)
            │
            └─► task_completed(agent_id)   ◄─── THIS ADR
                      ├─► TaskCompletionBeat   (audio beat + room modulate Tween + beat_fired signal)
                      └─► CommandersRoomHUD    (recent completions panel update)
```

### Key Interface

```gdscript
# AgentStateMachine — the complete task_completed contract
signal task_completed(agent_id: String)
# Emitted: exactly once per task completion transition, after agent_state_changed.
# Not emitted: on repeated COMPLETED payloads (no state change = no emission).
# Not emitted: on STALE, DISCONNECTED, or ERROR transitions.
# Emission order: agent_state_changed fires first on the same frame, then task_completed.
```

## Alternatives Considered

### Alternative B: AgentCharacterController emits task_completed

- **Description**: Each ACC instance (one per agent) subscribes to `agent_state_changed`, detects `"COMPLETED"`, and re-emits `task_completed`. Up to 12 ACC instances each emit the signal for their own agent.
- **Pros**: ACC already reacts to state transitions; adding an emit is a small addition.
- **Cons**: Creates double-dispatch (ASM → ACC → others) with frame-delayed emission relative to the state transition. Duplicates "is this a completion?" logic across all 12 ACC instances. ACC is an animation controller — emitting semantic application events is outside its domain. Any ACC that is freed mid-session would stop emitting for that agent.
- **Rejection Reason**: ASM already knows it's a completion (it emits `agent_state_changed` with `"COMPLETED"`). Having ACC re-emit adds a layer with no benefit and couples timing to ACC's lifecycle.

### Alternative C: DataBridge emits task_completed

- **Description**: DataBridge parses the API response payload to detect completion and emits `task_completed` directly, before ASM processes the same data.
- **Pros**: Earliest possible emission; consumers know immediately.
- **Cons**: Violates DataBridge's explicit design constraint ("The Data Bridge does NOT parse JSON, does NOT check for specific field names, and does NOT attempt to determine agent state" — `data-bridge.md`). Requires DataBridge to contain state interpretation logic, creating a second authoritative state source.
- **Rejection Reason**: DataBridge is an intentionally dumb transport layer. The moment it interprets "completion" from raw data, it becomes a second state machine, breaking the clean DataBridge / ASM boundary.

### Alternative D: No dedicated signal — subscribers detect completion from agent_state_changed

- **Description**: TCB and HUD subscribe to `agent_state_changed`, check if `new_state == "COMPLETED"`, and trigger their response inline. No separate `task_completed` signal.
- **Pros**: Fewer signals in the system; less wiring.
- **Cons**: The "what counts as completed?" logic is duplicated in every subscriber. If the definition of completion changes (e.g., a new terminal state), every subscriber must be updated. `task_completed` as a dedicated signal documents intent — the event is meaningful enough to name explicitly.
- **Rejection Reason**: `task_completed` is the primary semantic event of the application. Naming it explicitly is correct both semantically and architecturally. Subscribers should react to "a task completed," not to "an agent entered COMPLETED state" — the distinction matters if state names ever change.

## Consequences

### Positive

- Single authoritative emitter: any module that needs to respond to task completion connects to one signal from one module.
- Semantic clarity: `task_completed` is named for what happened, not the mechanism (`agent_state_changed` with `new_state == "COMPLETED"`).
- Removes all provisional notes from `task-completion-beat.md` regarding signal source.
- ASM GDD can now be written with `task_completed` emission as a confirmed responsibility.

### Negative

- ASM emits two signals on the same task-completion frame (`agent_state_changed` then `task_completed`). Subscribers to both signals will receive two callbacks. This is intentional and documented — they carry different semantics (state-changed is generic; task_completed is specific).

### Risks

- **Double-subscription bug**: a module subscribes to both `agent_state_changed` (checking for `"COMPLETED"`) AND `task_completed`, triggering its response twice per completion. Mitigation: code review verifies that no module subscribes to both for the same response; `task_completed` supersedes the `"COMPLETED"` check on `agent_state_changed` for all subscribers.
- **`task_completed` emitted before state write**: if `task_completed.emit()` is called before `_agent_states[agent_id] = new_state`, a subscriber calling `ASM.get_agent_state(agent_id)` during the callback would see the old state. Mitigation: implementation rule — always update internal state before emitting (shown in the code example above).
- **Repeated COMPLETED payloads**: if the API continues to return `"COMPLETED"` state on subsequent polls (agent stays in completed state), the ASM must NOT re-emit `task_completed` — the state hasn't changed. The implementation guard `if new_state == previous_state: return` prevents this.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `task-completion-beat.md` | "When the Agent State Machine signals that a task has completed, the Task Completion Beat subscribes to that event" | Confirms ASM as the emitter; TCB connects to `task_completed` via bootstrap |
| `task-completion-beat.md` | PROVISIONAL note: "Signal source (ASM vs ACC)" must be resolved | This ADR resolves it: ASM is the source, ACC is a co-subscriber |
| `commanders-room-hud.md` | HUD updates recent completions panel on task completion | HUD connects to `task_completed` via bootstrap; receives `agent_id` to format the entry |
| `data-bridge.md` | "All interpretation belongs to the Agent State Machine" | DataBridge is explicitly excluded as an emitter; ASM performs all semantic interpretation before emitting `task_completed` |

## Performance Implications

- **CPU**: Signal emission to two subscribers is two direct callable dispatches — negligible. The entire signal chain for one task completion (agent_state_changed + task_completed, dispatched to 4–5 total subscribers) is under 0.01ms.
- **Memory**: Two `Callable` objects stored for `task_completed` connections. <16 bytes.
- **Load Time**: Connection wiring happens once in the bootstrap. Negligible.
- **Network**: None.

## Migration Plan

N/A — establishes pattern before first implementation.

## Validation Criteria

- GUT: `test_task_completed_emits_on_completion_transition()` — inject ASM with a mock DataBridge; provide a payload that maps to `"COMPLETED"` state; confirm `task_completed` is emitted with correct `agent_id`
- GUT: `test_task_completed_not_emitted_on_non_completion()` — inject ASM with payloads mapping to `"IDLE"` and `"WORKING"`; confirm `task_completed` is NOT emitted
- GUT: `test_task_completed_not_repeated_on_same_state()` — inject two consecutive `"COMPLETED"` payloads for same agent; confirm `task_completed` fires exactly once
- GUT: `test_agent_state_written_before_emission()` — subscribe to `task_completed`; in the callback, call `ASM.get_agent_state(agent_id)`; confirm it returns `"COMPLETED"` (not the previous state)
- GUT: `test_task_completed_fires_after_state_changed()` — subscribe to both `agent_state_changed` and `task_completed`; confirm `agent_state_changed` callback fires before `task_completed` callback on the same transition
- Manual: Complete a task in the running application — confirm TCB fires its beat and HUD updates its recent completions panel

## Related Decisions

- ADR-0003: Autoload Scene Composition — defines the bootstrap that wires signal connections
- ADR-0006: Signal-Based Decoupling Pattern — governs Tier 1 signal usage this ADR follows
- ADR-001: Data Bridge Transport — DataBridge is explicitly NOT the emitter; this ADR confirms that boundary
