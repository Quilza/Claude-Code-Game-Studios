# ADR-0007: Agent State Vocabulary

## Status
Accepted (2026-05-12)

## Date
2026-05-12

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.2 (prototype validated on Godot 4.3 — vocabulary is engine-agnostic) |
| **Domain** | Game state / Integration / Agent State Machine |
| **Knowledge Risk** | LOW — vocabulary is derived from empirical Anthropic Messages API observations + documented `stop_reason` enumeration. No post-cutoff engine APIs involved. |
| **References Consulted** | `prototypes/data-bridge/findings.md` (Sprint 1 empirical data), Anthropic Messages API documentation (`stop_reason` enumeration), ADR-0001 (transport contract), ADR-0005 (signal source), ADR-0006 (signal decoupling) |
| **Post-Cutoff APIs Used** | None (this ADR is about state vocabulary, not engine behaviour) |
| **Verification Required** | New VERIFY-21: `tool_use` and `pause_turn` `stop_reason` paths empirically confirmed once a non-trivial agent task surfaces them in production; new VERIFY-22: `refusal` `stop_reason` handling validated when first occurs (rare event) |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 Data Bridge Transport (Accepted) — established the connection-state vocabulary (CONNECTING/CONNECTED/STALE/DISCONNECTED/ERROR) and the orthogonality principle that this ADR builds on. ADR-0005 task_completed Signal Source (Accepted) — ASM is the sole emitter of `task_completed`; this ADR defines when ASM emits it. ADR-0006 Signal-Based Decoupling (Accepted) — agent_state_changed signal subscription patterns. |
| **Enables** | `design/gdd/agent-state-machine.md` (GDD #6, currently blocked); ACC implementation stories (TR-acc-002 dispatch dictionary keys); AAL implementation stories; TCB implementation (which fires on the `completed` transition); HUD slot glyph rendering (per ADR-0011 glyph state matrix) |
| **Blocks** | None (this ADR removes the last architectural block in the Pre-Production critical path) |
| **Ordering Note** | This ADR was authored AFTER the Sprint 1 Data Bridge prototype harvested real-API findings. It was held BLOCKED-on-prototype intentionally because the canonical state vocabulary depends on what the real API actually reports. |

## Context

### Problem Statement

Agent State Machine (ASM) is the canonical source of agent-level state and the sole emitter of `task_completed(agent_id: String)` and `agent_state_changed(agent_id: String, new_state: String, previous_state: String)`. Three things were unresolved until the Data Bridge prototype answered them:

1. **What is the canonical agent-state vocabulary?** — `{idle, working, completed, errored}` was the working assumption from art-bible.md, but it had never been validated against a real AI-API response shape.
2. **How does ASM derive agent state from the raw payloads emitted by Data Bridge?** — Data Bridge emits `agent_response_received(agent_id, payload: String)` per ADR-0001 (raw string, no parsing at bridge layer). ASM must parse the payload and translate to agent state.
3. **What is the relationship between connection state (ADR-0001's domain) and agent state (this ADR's domain)?** — Whether they're a single combined state or two orthogonal axes.

The Sprint 1 prototype (`prototypes/data-bridge/`) hit the real Claude API (`claude-haiku-4-5-20251001`) and harvested 11 successful response payloads plus several real failure modes. The findings inform every choice in this ADR. See `prototypes/data-bridge/findings.md`.

### Constraints
- Vocabulary must be **finite and small** — used as keys in `ASM_STATE_TO_ANIM` dictionary per ADR-0009; rendered as HUD glyphs per ADR-0011
- Vocabulary must be **stable** — every downstream system (ACC, AAL, HUD, TCB) depends on the exact string values
- Must accommodate Claude API's documented `stop_reason` enumeration: `{end_turn, max_tokens, stop_sequence, tool_use, pause_turn, refusal}`
- Must accommodate HTTP error responses + network failures from the transport layer
- Connection state remains separate per ADR-0001 (don't conflate)
- `agent_id: String` (per ADR-0001 / ADR-0005 contracts)

### Requirements
- Define the canonical state set
- Specify the derivation rule from Data Bridge raw payload → ASM state
- Specify state transition rules (what can move to what)
- Specify when `task_completed` fires (the special transition the rest of the system hangs on)
- Specify how connection state and agent state compose for HUD rendering

## Decision

### TL;DR
Four agent states: **`idle`, `working`, `completed`, `errored`**. ASM derives state primarily from the most recent payload's `stop_reason` field, plus a bridge-side "request in flight" boolean for `working`. `completed` is a **transient** state that auto-decays to `idle` after `COMPLETED_DECAY_SEC` (1.5s). Connection state remains a separate orthogonal axis owned by ADR-0001's Data Bridge. `task_completed` fires on **every transition into `completed`**.

### Canonical State Vocabulary

ASM maintains exactly four agent states (StringName constants):

| State | Meaning | Visual (per art-bible + ADR-0011) |
|---|---|---|
| `idle` | No request in flight; no recent activity | Slot glyph `▬` amber `#D4882A` |
| `working` | Request in flight, OR last response indicated mid-flight work continues | Slot glyph `●` green `#5BAD63` |
| `completed` | Most recent response settled with a "normal completion" stop_reason; this state is transient and decays | Slot glyph `+` green `#5BAD63` for 1.5s, then `idle` |
| `errored` | Most recent response was a refusal, HTTP error, or unparseable payload | Slot glyph `●` sienna `#A03520` |

These four match the original art-bible.md vocabulary. The prototype findings did not surface a need for a fifth state.

### Derivation Rule (Data Bridge raw payload → ASM state)

ASM subscribes to `DataBridge.agent_response_received(agent_id: String, payload: String)` and `DataBridge.agent_connection_changed(agent_id: String, new_state: String)`. On each `agent_response_received`:

```gdscript
# pseudocode in ASM
func _on_agent_response_received(agent_id: String, payload: String) -> void:
    var parsed: Variant = JSON.parse_string(payload)
    if parsed == null or not parsed is Dictionary:
        _set_state(agent_id, &"errored")
        return
    var p: Dictionary = parsed as Dictionary
    if p.has("error"):
        # Anthropic error envelope: {"type":"error","error":{...}}
        _set_state(agent_id, &"errored")
        return
    var stop: String = String(p.get("stop_reason", ""))
    match stop:
        "end_turn", "max_tokens", "stop_sequence":
            _set_state(agent_id, &"completed")
            # _set_state schedules COMPLETED_DECAY_SEC timer to revert to idle
        "tool_use", "pause_turn":
            _set_state(agent_id, &"working")
        "refusal":
            _set_state(agent_id, &"errored")
        _:
            # Unknown stop_reason — treat as completed conservatively + log
            push_warning("[ASM] Unknown stop_reason=%s for agent %s" % [stop, agent_id])
            _set_state(agent_id, &"completed")
```

Key rules:
- `working` state is set when a request is in flight (bridge-tracked side state — ASM queries `DataBridge.is_request_in_flight(agent_id)` or subscribes to a new signal). When the response settles with `tool_use`/`pause_turn`, `working` persists across the poll because more work is coming.
- `completed` is **transient**: a Timer of duration `COMPLETED_DECAY_SEC` (1.5s — matches ADR-0011 TR-hud-004 slot glyph timer) is scheduled on entry; on expiry, ASM transitions back to `idle`. If a new response arrives before the timer expires, the timer is killed and the new response's stop_reason determines the next state.
- `errored` does **not** auto-decay. It persists until the next non-error response.

### Connection State / Agent State Orthogonality

Two-axis state. Per ADR-0001, connection state is `{CONNECTING, CONNECTED, STALE, DISCONNECTED, ERROR}`. Per this ADR, agent state is `{idle, working, completed, errored}`. They compose:

| Connection | Agent | Slot rendering (per ADR-0011) |
|---|---|---|
| CONNECTED | idle | `▬` amber, `modulate.a = 1.0` |
| CONNECTED | working | `●` green, `modulate.a = 1.0` |
| CONNECTED | completed | `+` green for 1.5s, `modulate.a = 1.0` |
| CONNECTED | errored | `●` sienna, `modulate.a = 1.0` |
| STALE | * (any) | glyph unchanged, `modulate.a = 0.5` |
| DISCONNECTED | * (any) | glyph unchanged, `modulate.a = 0.25` |
| ERROR | errored | `●` sienna, `modulate.a = 0.25 + red tint` |

The HUD slot logic reads both via Tier 2 signal subscription per ADR-0006:
```gdscript
ASM.agent_state_changed.connect(_on_agent_state_changed.bind(agent_id))
DataBridge.agent_connection_changed.connect(_on_connection_changed.bind(agent_id))
```

### `task_completed` Emission Contract (per ADR-0005)

ASM emits `task_completed(agent_id: String)` **on every transition INTO `completed`**, regardless of which `stop_reason` triggered it. This is the signal TCB subscribes to.

Transitions that fire `task_completed`:
- `idle` → `completed` (rare — would require the bridge to deliver a finished response without prior in-flight visibility)
- `working` → `completed` (the canonical case)
- `errored` → `completed` (recovery: previous task errored, current task succeeded)

Transitions that do NOT fire `task_completed`:
- `completed` → `idle` (the decay; this is automatic, no real event)
- Any → `working`
- Any → `errored`
- Any → `idle` (other than via the completed decay)

### State Transition Diagram

```
                    ┌────────┐
            ┌──────▶│  idle  │◀──────┐
            │       └───┬────┘       │
            │ decay     │ request    │
            │ (1.5s)    │ dispatched │
            │           ▼            │
            │     ┌──────────┐       │
            │     │ working  │       │ first_settle
            │     └────┬─────┘       │ (no stop_reason
            │          │             │  yet — straight to
            │ resp.    │ resp.       │  completed)
            │ stop=    │ stop=       │
            │ refusal  │ end_turn /  │
            │ /error   │ max_tokens/ │
            │          │ stop_seq    │
            │          ▼             │
            │    ┌───────────┐       │
            │    │ completed │───────┘
            │    └─────┬─────┘
            │          │ resp.
            │          │ stop=
            │          │ tool_use /
            │          │ pause_turn
            │          ▼
            │    ┌──────────┐
            │    │ working  │
            │    └──────────┘
            │
        ┌───┴────┐
        │ errored│  (persistent — no auto-decay)
        └────────┘
```

`task_completed` fires on every entry into `completed` (entry edges marked `*→completed` in the diagram).

### Tuning Knobs

| Constant | Default | Range | Where defined |
|---|---|---|---|
| `COMPLETED_DECAY_SEC` | 1.5 | 0.5 – 3.0 | ASM constant (matches TR-hud-004 slot glyph timer for consistency) |
| `UNKNOWN_STOP_REASON_FALLBACK` | `completed` | one of `{completed, errored, idle}` | ASM constant — conservative default |
| `INITIAL_AGENT_STATE` | `idle` | one of `{idle, working}` | ASM constant — `idle` until first response |

### Architecture Diagram

```
DataBridge (per ADR-0001)
   │
   ├─ agent_response_received(id, raw_payload_string)
   ├─ agent_connection_changed(id, conn_state_string)
   │
   ▼
ASM (per this ADR + ADR-0005)
   │
   ├─ parse payload JSON
   ├─ match stop_reason → state
   ├─ schedule 1.5s decay on entry to `completed`
   ├─ emit agent_state_changed(id, new_state, prev_state)
   └─ emit task_completed(id) on entry to `completed`
   │
   ├──────────────────┬────────────────────────┐
   ▼                  ▼                        ▼
   TCB (audio        ACC (sprite              HUD (slot glyph +
   + room beat       animation                connection-quality
   per ADR-0010)     per ADR-0009)            modulate per ADR-0011)
```

### Key Interfaces

Public read-only API on ASM (per ADR-0006 Tier 3):

```gdscript
func get_agent_state(agent_id: String) -> String       # returns one of {idle, working, completed, errored}
func get_agent_stats(agent_id: String) -> Dictionary    # {tasks_completed: int, last_state_change_ms: int, last_payload_id: String, ...}
func is_agent_known(agent_id: String) -> bool
```

Signals (ASM emits):
```gdscript
signal agent_state_changed(agent_id: String, new_state: String, previous_state: String)
signal task_completed(agent_id: String)
```

(Both signal contracts pre-existed via ADR-0005 + ADR-0006. This ADR doesn't add new signals.)

Registry updates when this ADR Accepted:
- `agent_state_vocabulary` api_decision in `docs/registry/architecture.yaml`
- `unknown_stop_reason_falls_back_to_completed` api_decision
- `completed_state_transient_with_decay` api_decision
- `connection_state_and_agent_state_orthogonal` api_decision
- `agent_state_string_not_stringname` forbidden_pattern reinforcement

## Alternatives Considered

### Alternative A — Five-state vocabulary (add `disconnected` as an agent state)

- **Description**: Merge connection state into agent state. `{idle, working, completed, errored, disconnected}`.
- **Pros**: One axis, simpler HUD rendering.
- **Cons**: Loses the orthogonality from ADR-0001; HUD modulate.a + glyph become tangled; can't distinguish "agent was working but bridge dropped" from "agent erored". The prototype empirically validated that both axes carry independent information.
- **Rejection Reason**: Orthogonality is a feature, not an accident. Two axes match the underlying reality.

### Alternative B — Map `max_tokens` to `errored` instead of `completed`

- **Description**: `max_tokens` could be considered an incomplete response — the model didn't finish what it wanted to say.
- **Pros**: Captures "the task didn't fit in budget" as a distinct concern.
- **Cons**: From the **user's** perspective, `max_tokens` is usually a completed task (the response is what they asked for, within their budget cap). Conflating it with `errored` confuses the user-facing signal. Also, the prototype's `max_tokens=1` runs are the textbook case where `max_tokens` is the *expected* normal completion.
- **Rejection Reason**: User-facing semantics matter. `max_tokens` is "I finished within budget", not "I errored".

### Alternative C — Six-state vocabulary (split `working` into `working_normal` and `working_tool_use`)

- **Description**: Distinguish "agent is thinking" from "agent is calling a tool".
- **Pros**: HUD could show tool-use as a distinct glyph (useful for debugging agent workflows).
- **Cons**: HUD has no room for a fifth glyph; the distinction is observable but not user-meaningful in the current bunker aesthetic; can be added post-MVP without breaking the four-state contract.
- **Rejection Reason**: Yagni. Keep four; revisit if HUD ever displays detailed agent stats panel.

### Alternative D — Make `completed` persistent (no auto-decay)

- **Description**: `completed` stays until the next request fires.
- **Pros**: Simpler ASM (no Timer required).
- **Cons**: Slot glyph would stay `+` indefinitely after one task — confusing. The 1.5s transient matches the slot-timer requirement (TR-hud-004) and the "satisfying feedback then return to ambient" loop from the game-concept pillars.
- **Rejection Reason**: Transience is the design intent.

### Alternative E — `working` derived purely from stop_reason (no in-flight tracking)

- **Description**: ASM only listens to `agent_response_received`; if last response was `tool_use`, state is `working`, otherwise `idle` or `completed`. No bridge-side in-flight signal needed.
- **Pros**: Simpler signal contract — ASM doesn't need to know about request lifecycle.
- **Cons**: The gap between request dispatch and response arrival (could be seconds for slow API calls) leaves the agent in `idle` when it's actually `working`. HUD users would see "this agent is doing nothing" while the bridge is mid-request.
- **Rejection Reason**: HUD responsiveness matters. Bridge must surface in-flight state.
- **Implementation note**: This ADR requires Data Bridge to expose `is_request_in_flight(agent_id) -> bool` and/or emit a `request_dispatched(agent_id)` signal. This is a small ADR-0001 amendment, recommended as a follow-up.

## Consequences

### Positive
- Unblocks `design/gdd/agent-state-machine.md` (GDD #6) — the 10th MVP GDD can now be designed
- Unblocks 4 ASM-related TRs (TR-asm-002, 004, 005, 006) in the traceability index
- Unblocks ACC implementation stories (TR-acc-002 dispatch dictionary now has canonical keys)
- Unblocks AAL implementation stories (room-state derivation from agent-state aggregation)
- Locks the contract for HUD slot glyph rendering (per ADR-0011 glyph state matrix)
- `task_completed` emission contract is now precise — TCB implementation can begin
- Vocabulary matches both art-bible's design intent AND empirical API reality

### Negative
- ASM now has a JSON parse on every payload (cheap, ~µs at our scale)
- ASM needs a Timer per agent for `completed` decay (12 timers max — negligible)
- A follow-up amendment to ADR-0001 is recommended to expose request-in-flight state (Alternative E discussion above)

### Risks

| Risk | Mitigation |
|---|---|
| New `stop_reason` values added by Anthropic API in future | Fallback maps unknown to `completed` + push_warning; smoke test in CI verifies known stop_reasons land in expected states |
| `tool_use` / `pause_turn` paths not empirically validated this sprint (VERIFY-21) | Smoke test as soon as a non-trivial agent task surfaces them; documented as future verification |
| `refusal` handling unvalidated (VERIFY-22) | Rare event; will validate when first observed in production |
| HUD shows stale `completed` glyph if Timer is killed unexpectedly | ASM owns the Timer; documented kill path; GUT test asserts decay fires within ±50ms of 1.5s |
| Multiple rapid `tool_use` responses chain `working` indefinitely | This is correct behaviour — the agent IS working. HUD shows green. No issue. |
| Provider-specific (non-Anthropic) APIs have different stop_reason vocabularies | ADR is Anthropic-shaped; future ADR-0007.x or amendment can add provider-specific parsers. The state vocabulary itself ({idle, working, completed, errored}) is provider-agnostic. |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `design/gdd/agent-state-machine.md` (BLOCKED → now unblocks) | TR-asm-002 (Agent state vocabulary) | This ADR defines the four states |
| `agent-state-machine.md` | TR-asm-004 (Connection-quality reporting mechanism) | Orthogonality decision: connection state and agent state are separate axes |
| `agent-state-machine.md` | TR-asm-005 (Parses Data Bridge raw payload into canonical state) | Derivation rule via stop_reason match |
| `agent-state-machine.md` | TR-asm-006 (Per-agent stats dictionary via get_agent_stats) | Read-only API spec |
| `agent-character-controller.md` | TR-acc-002 (AnimationPlayer state driven by ASM) | ASM_STATE_TO_ANIM dictionary in ADR-0009 now has canonical keys |
| `task-completion-beat.md` | TCB fires on task_completed | Emission contract pinned: every transition INTO completed |
| `commanders-room-hud.md` | TR-hud-002, TR-hud-004 (slot grid + per-slot glyph timer) | Visual matrix in this ADR matches HUD GDD glyph table |

## Performance Implications
- **CPU**: JSON parse per payload (~10µs at our scale × 12 agents × 1 poll/5s = trivial); Timer scheduling on `completed` entry (~µs)
- **Memory**: ASM stores `_agent_states: Dictionary[String, String]` (12 entries max, ~500 bytes); per-agent decay Timer instances
- **Load Time**: Zero (no asset dependency)
- **Network**: N/A (this ADR is local state derivation)

## Migration Plan
No existing ASM code to migrate (pre-implementation). When ASM implementation story begins:

1. ASM Autoload (or scene-scoped node — design TBD in ASM GDD) implements the state machine per this ADR
2. ASM subscribes to `DataBridge.agent_response_received` and `DataBridge.agent_connection_changed`
3. ASM emits `agent_state_changed` and `task_completed` per ADR-0005 / ADR-0006
4. ACC subscribes via `.bind(agent_id)` per ADR-0009
5. TCB subscribes to `task_completed` per ADR-0005
6. HUD subscribes via Tier 2 per ADR-0011

The prototype's data_bridge.gd already emits the two signals this ADR requires. ASM is the next piece.

## Validation Criteria

- GUT test: `test_stop_reason_end_turn_maps_to_completed`
- GUT test: `test_stop_reason_max_tokens_maps_to_completed`
- GUT test: `test_stop_reason_tool_use_maps_to_working`
- GUT test: `test_stop_reason_refusal_maps_to_errored`
- GUT test: `test_unknown_stop_reason_falls_back_to_completed_with_warning`
- GUT test: `test_malformed_payload_maps_to_errored`
- GUT test: `test_completed_decays_to_idle_after_1500ms`
- GUT test: `test_task_completed_emits_on_every_completed_entry`
- GUT test: `test_state_change_emits_agent_state_changed_with_correct_previous_state`
- GUT test: `test_connection_and_agent_state_are_independent` (mock both signal sources, assert no coupling)
- Manual smoke: run prototype with Sprint 1 setup; observe agent state derives correctly from real Claude API responses

## Related Decisions
- ADR-0001 Data Bridge Transport — provides the raw payloads this ADR consumes; orthogonal connection-state vocabulary
- ADR-0005 task_completed Signal Source — ASM is sole emitter; this ADR specifies when
- ADR-0006 Signal-Based Decoupling — Tier 2 subscription pattern used by consumers
- ADR-0008 Mock Mode Strategy — mock payloads must conform to the parse rule in this ADR
- ADR-0009 AnimationPlayer Strategy — `ASM_STATE_TO_ANIM` dictionary keys are pinned by this ADR
- ADR-0011 HUD Rendering Strategy — slot glyph + modulate composition table
- New VERIFY-21, VERIFY-22 — opened by this ADR
- TR-asm-002 / 004 / 005 / 006 — covered by this ADR
- Sprint 1 (`production/sprints/sprint-1.md`) — empirical source for the decisions in this ADR; `prototypes/data-bridge/findings.md`

## Provenance Note

This ADR is the **last architectural block in the Pre-Production critical path**. It was held BLOCKED-on-prototype intentionally per ADR-0006's "design from contact with reality" principle — the agent-state vocabulary was the one place where the system's design depended on empirical knowledge of real AI-API response shapes. Sprint 1's Data Bridge prototype against the live Anthropic API (`claude-haiku-4-5-20251001`) provided that empirical grounding. With this ADR Accepted, all 14 architectural ADRs are now in their final state and implementation can begin.
