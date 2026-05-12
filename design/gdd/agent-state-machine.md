# Agent State Machine — Game Design Document

> **Status**: COMPLETE — all 8 sections authored 2026-05-12 (section-by-section with user approval per `.claude/rules/design-docs.md`)
> **Created**: 2026-05-12
> **Completed**: 2026-05-12
> **Owner**: game-designer (with technical-director consultation)
> **Linked**:
>   - ADR-0007 Agent State Vocabulary (Accepted 2026-05-12)
>   - ADR-0001 Data Bridge Transport (Accepted + Amendment 2026-05-12.b)
>   - ADR-0005 task_completed Signal Source
>   - ADR-0006 Signal-Based Decoupling
>   - `prototypes/data-bridge/findings.md` (empirical Anthropic API observations)

This is GDD #6 — the **10th and last MVP GDD**. It was BLOCKED on the Data Bridge prototype + ADR-0007. Both closed 2026-05-12. Authoring completed in the same session.

---

## 1. Overview

The Agent State Machine (ASM) is the canonical source of agent-level state in The Situation Room. It sits between the Data Bridge — which ferries raw payloads from configured AI agents — and the systems that visually or audibly respond to agent activity: the Agent Character Controller (sprite animation), Ambient Animation Layer (room mood), Task Completion Beat (room flash + audio cue), and Commander's Room HUD (slot rendering + detail overlay). ASM has one responsibility: parse each raw response payload, derive a canonical four-state agent vocabulary from it, and emit signals that downstream consumers subscribe to. ASM maintains per-agent state for the entire configured roster, persists per-agent stats across sessions via ConfigurationLoader, and exposes a read-only stats accessor for the HUD detail overlay. Without ASM, every consumer would parse payloads independently and the visual vocabulary would drift.

---

## 2. Player Fantasy

The Agent State Machine's fantasy is felt in your peripheral vision. You opened the bunker because you wanted to know what your AI agents are doing — not to micromanage them, but to feel their presence while you work alongside them. When an agent is *thinking*, you might catch a slow ambient hum in their room. When it's *working*, motion picks up — the agent paces, the monitor flickers more urgently, the room is alive but not loud. When it *finishes*, you feel it: a brief warm flash on their room tile, a soft completion chime, a green `+` on their HUD slot for a moment, then everything settles back. When it's *struggling*, the room dims, the slot shows sienna, the agent visibly hesitates — but nothing pops up demanding your attention. The bunker is a companion, not a notification system. You glance, you learn, you return to your work.

---

## 3. Detailed Rules

### 3.1 Lifecycle and registration

1. **ASM is scene-scoped, not an Autoload.** Per ADR-0003, only ConfigurationLoader and AudioManager are Autoloads. ASM is instantiated as a child node of the Main scene root at bootstrap, after ConfigurationLoader and Data Bridge.

2. **Agent registration occurs once, at `_ready()`.** ASM iterates `ConfigurationLoader.get_agents()` and creates a per-agent state entry for each. After `_ready()` completes, the agent registry is immutable for the session — adding or removing agents requires app restart (no `setting_changed` subscription per the bootstrap-only decision).

3. **Initial state on registration is `idle`.** Stats counters are loaded from `user://settings.json` via `ConfigurationLoader.get_setting("asm_stats_<agent_id>", {})` if present; otherwise zero-initialized. `session_start_ms` is set to `Time.get_ticks_msec()` at registration regardless of persisted stats.

### 3.2 State derivation rule

4. **ASM parses every payload from `agent_response_received`.** The mapping rule is canonically defined in ADR-0007 § Decision and embedded here for reference:

   | Payload condition | Resulting state |
   |---|---|
   | JSON parse fails OR result not a Dictionary | `errored` |
   | Has top-level `"error"` key (Anthropic error envelope) | `errored` |
   | `stop_reason` ∈ `{end_turn, max_tokens, stop_sequence}` | `completed` |
   | `stop_reason` ∈ `{tool_use, pause_turn}` | `working` |
   | `stop_reason` = `refusal` | `errored` |
   | Unknown `stop_reason` (any other value) | `completed` + `push_warning` |

5. **In-flight tracking via Data Bridge B2 signals.** ASM subscribes to `request_dispatched(agent_id)` and `request_settled(agent_id)` per ADR-0001 B2. On `request_dispatched`, ASM transitions the agent to `working`. On `request_settled` with no preceding `agent_response_received` (clean settle with no payload — i.e., network error), ASM transitions to `errored`.

### 3.3 Transient state and decay

6. **`completed` is transient.** On entry into `completed`, ASM schedules a per-agent `Timer` of duration `COMPLETED_DECAY_SEC` (1.5s). On timeout, ASM transitions back to `idle`. If a new response arrives before the Timer fires, the Timer is killed and the new response's state takes precedence immediately.

7. **`errored` does not auto-decay.** It persists until the next non-error response arrives.

8. **`idle` and `working` are stable.** No automatic transitions out of them — only signal-driven changes.

### 3.4 Signal emission

9. **`agent_state_changed(agent_id, new_state, previous_state)` emits on every actual state change.** Same-state "transitions" (e.g., another `tool_use` while already `working`) do NOT emit the signal.

10. **`task_completed(agent_id)` emits on every entry into `completed`.** Sole emission point per ADR-0005. The 1.5s decay back to `idle` does NOT emit `task_completed`.

### 3.5 Connection-drop handling

11. **Bridge connection state and ASM agent state are orthogonal.** ASM does NOT subscribe to `agent_connection_changed`. Connection-state rendering is a downstream concern (HUD slot `modulate.a` per ADR-0011).

12. **If the bridge drops during an in-flight request, the agent stays `working` until `request_settled` arrives.** The bridge contract (ADR-0001 B2) guarantees every `request_dispatched` is followed by exactly one `request_settled` — even on network errors. ASM then transitions to `errored` per Rule 5.

### 3.6 Stats accumulation and persistence

13. **Stats counters update on these events**:
    - On entry to `completed`: `tasks_completed += 1`, `last_state_change_ms = now`, `last_payload_id = <id from payload>`, `last_stop_reason = <stop_reason>`
    - On entry to `errored`: `errored_count += 1`, `last_state_change_ms = now`, plus payload fields if available
    - On every successful payload (regardless of state change): `total_input_tokens += <usage.input_tokens>`, `total_output_tokens += <usage.output_tokens>`
    - On any state change: `current_state` is kept in sync with the public API

14. **Stats persistence is debounced + flush-on-close.** ASM maintains a `_stats_dirty: Dictionary[String, bool]` keyed by `agent_id`. On any counter update, the agent's dirty flag is set. A `Timer` of period `STATS_WRITE_INTERVAL_SEC` (5.0s) ticks: for each dirty agent, ASM writes `ConfigurationLoader.set_setting("asm_stats_<agent_id>", <stats dict>)` and clears the flag. On `_exit_tree()`, ASM forces a flush of all dirty agents regardless of Timer state.

### 3.7 Public read-only API

15. **ASM exposes four read-only methods** (Tier 3 per ADR-0006):
    - `get_agent_state(agent_id: String) -> String` — one of `{idle, working, completed, errored}`; returns `"idle"` if agent unknown
    - `get_agent_stats(agent_id: String) -> Dictionary` — 9 fields per Section 4 (returns empty `{}` if agent unknown)
    - `get_bunker_summary() -> Dictionary` — `{working_count, errored_count, completed_count, idle_count, total_count}`; computed on demand
    - `is_agent_known(agent_id: String) -> bool` — true iff agent was registered at bootstrap

    No write methods. No setters. Cross-system writes go through signals only.

### 3.8 What ASM never does

16. **ASM has no spatial or rendering concept.** It does not know about rooms, tiles, sprites, or audio. The state vocabulary is a pure data model.

17. **ASM does not parse beyond `stop_reason` + error envelope + usage tokens.** Everything else in the payload (content blocks, model, id, full usage breakdown, service tier, inference geo) is preserved as raw String for future consumers but never interpreted by ASM.

18. **Mock mode and web mode are invisible to ASM.** Per ADR-0008 the mock bridge emits the same signal contract. Per ADR-0004 the web override forces mock. ASM sees identical signal streams regardless of mode.

---

## 4. Formulas

### 4.1 Constants

| Constant | Default | Safe range | Gameplay impact |
|---|---|---|---|
| `COMPLETED_DECAY_SEC` | `1.5` | `0.5 – 3.0` | Time `completed` state lingers before reverting to `idle`. Must stay ≤ slot glyph timer (1.5s per TR-hud-004) so HUD glyph and agent state decay in sync. Shorter = snappier feedback; longer = more time to notice. |
| `STATS_WRITE_INTERVAL_SEC` | `5.0` | `1.0 – 30.0` | Frequency at which dirty stats flush to `user://settings.json`. Smaller = less data loss on crash, more I/O. Larger = better I/O, more loss window. |
| `UNKNOWN_STOP_REASON_FALLBACK` | `"completed"` | one of `{completed, errored, idle}` | What ASM does when a `stop_reason` is not in the known mapping. Conservative default: assume normal completion. |
| `INITIAL_AGENT_STATE` | `"idle"` | one of `{idle, working}` | State assigned to newly-registered agents. `idle` = "no activity until first response". |

### 4.2 State transition matrix

Row = current state. Column = event. Cell = next state.

| from \ event | `request_dispatched` | payload→`completed` | payload→`working` | payload→`errored` | `request_settled` w/o payload | Timer expires |
|---|---|---|---|---|---|---|
| `idle` | `working` | `completed` | `working` | `errored` | — (no in-flight) | n/a |
| `working` | `working` (no-op) | `completed` | `working` (no-op) | `errored` | `errored` | n/a |
| `completed` | `working` | `completed` (no-op; restart Timer) | `working` | `errored` | — (no in-flight) | `idle` |
| `errored` | `working` | `completed` | `working` | `errored` (no-op) | — (no in-flight) | n/a |

Notes:
- "no-op" = same-state transition; `agent_state_changed` is NOT emitted (per Rule 9)
- "— (no in-flight)" = defensive cell; if it occurs, ASM should `push_warning` and ignore
- Timer expires only fires from `completed`; from any other state the Timer is killed before it can fire

### 4.3 Stats accumulator math

Per agent `a` with state `S(a)` and most recent payload `P(a)`:

```
on transition S(a) → "completed":
    stats[a].tasks_completed       += 1
    stats[a].last_state_change_ms   = Time.get_ticks_msec()
    stats[a].last_payload_id        = P(a).id
    stats[a].last_stop_reason       = P(a).stop_reason

on transition S(a) → "errored":
    stats[a].errored_count         += 1
    stats[a].last_state_change_ms   = Time.get_ticks_msec()
    if P(a) is not null:
        stats[a].last_payload_id    = P(a).id    if P(a).id    != null
        stats[a].last_stop_reason   = P(a).stop_reason if P(a).stop_reason != null

on every successful payload P(a) (state change or not):
    stats[a].total_input_tokens   += P(a).usage.input_tokens   ?? 0
    stats[a].total_output_tokens  += P(a).usage.output_tokens  ?? 0

on every state change:
    stats[a].current_state = S(a)
```

### 4.4 Bunker summary formula

```
get_bunker_summary():
    summary = {idle_count: 0, working_count: 0, completed_count: 0, errored_count: 0, total_count: 0}
    for a in registered_agents:
        state = states[a]
        summary[state + "_count"] += 1
        summary.total_count       += 1
    return summary
```

Cost: O(N) per call where N ≤ 12. Trivial.

### 4.5 Write-budget envelope

Worst-case I/O at 12 agents averaging 1 state change/minute with `STATS_WRITE_INTERVAL_SEC = 5`:
- Maximum writes per minute = `60 / 5 = 12` (only if at least one agent is dirty every interval)
- Each write rewrites one settings.json blob via `ConfigLoader.set_setting`
- ConfigLoader uses Godot's atomic write (write-to-tmp + rename) = one file syscall per write

Performance envelope is well within budget. No optimization needed for MVP scale.

### 4.6 Stats schema (persisted)

Persisted in `user://settings.json` under the key `asm_stats_<agent_id>`:

```json
{
  "current_state": "idle",
  "tasks_completed": 0,
  "errored_count": 0,
  "last_state_change_ms": 0,
  "last_payload_id": "",
  "last_stop_reason": "",
  "total_input_tokens": 0,
  "total_output_tokens": 0,
  "session_start_ms": 0
}
```

Note: `session_start_ms` is rewritten on each ASM `_ready()` to reflect the current session. Other fields persist across sessions if the agent's `agent_id` matches.

---

## 5. Edge Cases

Each case explicitly states the observable behavior. Cases marked "rule" reference the canonical handling rule from Section 3.

### 5.1 Payload-shape edge cases

**E-1: Malformed JSON payload from Data Bridge.** ASM calls `JSON.parse_string(payload)`. If result is `null` or not a `Dictionary`, ASM transitions the agent to `errored`, increments `errored_count`, leaves `last_payload_id` and `last_stop_reason` untouched (no valid id to record), and `push_warning("[ASM:<agent_id>] malformed payload")`. (Rule 4 row 1.)

**E-2: HTTP error envelope.** Payload parses successfully but contains a top-level `"error"` key (Anthropic's error shape: `{"type":"error","error":{...},"request_id":"..."}`). ASM transitions to `errored`. If the envelope includes `request_id`, ASM uses that as `last_payload_id` for debug traceability. `last_stop_reason` is set to `"error_envelope"` (a synthetic value, not a real `stop_reason`). (Rule 4 row 2.)

**E-3: Unknown `stop_reason` value.** Payload parses, no `"error"` key, but `stop_reason` is some value not in the canonical set (e.g., a future Anthropic addition we haven't mapped). ASM transitions to `completed` (conservative fallback per `UNKNOWN_STOP_REASON_FALLBACK`), records the unknown value in `last_stop_reason`, and `push_warning("[ASM:<agent_id>] unknown stop_reason=<value>")`. (Rule 4 row 6.)

**E-4: Empty `content[]` array.** Payload is valid, `stop_reason` is `max_tokens`, but `content` is `[]` because the model didn't produce any output token before hitting the limit. Treated as a completed task per Section 4.2 transition matrix. The HUD slot fires the `+` glyph; TCB fires the room beat. (This is the observed behavior with our prototype's `max_tokens=1` runs.)

**E-5: Missing `usage` block.** Some providers might omit the `usage` object. ASM's token counter increments use `?? 0` semantics — missing `usage.input_tokens` or `usage.output_tokens` increments by 0 (no-op). No warning emitted (this is normal for non-Anthropic providers).

### 5.2 Timing / cascade edge cases

**E-6: Rapid response cascade — new response before decay Timer fires.** Agent is in `completed`, its 1.5s Timer is running. A new `agent_response_received` arrives at, say, T+0.8s. ASM kills the Timer immediately, parses the new payload, applies the new state. If the new state is also `completed`, ASM emits `task_completed` again (Rule 10) AND starts a fresh 1.5s Timer (the no-op-with-Timer-restart case in the transition matrix).

**E-7: Multiple `request_dispatched` without intervening `request_settled`.** Bridge contract (ADR-0001 B2) guarantees these signals come in matched pairs. If ASM observes a violation (two dispatches in a row), ASM stays `working` and `push_warning("[ASM:<agent_id>] bridge contract violation — dispatch without settle")`. No state corruption.

**E-8: `request_settled` arriving in `idle`.** Shouldn't happen — implies a settle without preceding dispatch. ASM logs a warning, ignores the signal, agent stays in `idle`.

**E-9: Timer expires while a new request is already in-flight.** Possible race: agent in `completed` with Timer running, a new request dispatches, ASM transitions to `working`, then the (orphaned) Timer fires. ASM checks current state inside the Timer callback; if not `completed`, the callback is a no-op (Timer's revert-to-idle action is gated on `current_state == "completed"`).

### 5.3 Bridge interaction edge cases

**E-10: Bridge drops mid-request (connection STALE/DISCONNECTED while agent is `working`).** Per Rule 12, ASM stays `working`. The bridge contract guarantees `request_settled` will fire — even on network errors. When it does, ASM transitions to `errored` per Rule 5. The HUD will show `working` + dimmed alpha during the drop window (because connection-state and agent-state are orthogonal — Rule 11).

**E-11: Hot-reload of `config.json` mid-session.** Per the bootstrap-only decision, ASM does NOT react. The added/removed agent has no effect until app restart. ConfigurationLoader's `setting_changed` signal is unsubscribed by ASM. (Rule 2.)

**E-12: ConfigurationLoader returns an empty agents list at bootstrap.** ASM registers zero agents. All public accessors return empty/safe defaults (`get_agent_state` returns `"idle"`, `get_agent_stats` returns `{}`, `get_bunker_summary` returns all-zero, `is_agent_known` returns `false`). No `agent_state_changed` signals will ever fire. Downstream HUD shows an empty slot grid. Not an error condition — this is the "no agents configured" state.

**E-13: ASM `_ready()` runs before Data Bridge `_ready()`.** Both are children of Main scene; their bootstrap order depends on tree ordering. Per ADR-0003, ConfigurationLoader is an Autoload (initialised before any scene `_ready()`), but Data Bridge is scene-scoped. ASM's signal subscriptions to Data Bridge happen in `_ready()`; if Data Bridge hasn't `_ready()`'d yet, its signals don't exist to connect to. **Mitigation**: ASM must use `call_deferred("_subscribe_to_bridge")` or be placed BELOW Data Bridge in the scene tree (children are ready in order). The Main Scene Bootstrap GDD owns this ordering contract.

### 5.4 Persistence edge cases

**E-14: Corrupt persisted stats blob on bootstrap.** If `ConfigLoader.get_setting("asm_stats_<agent_id>", {})` returns a value that doesn't match the expected schema (missing required fields, wrong types), ASM zero-initializes that agent's stats, leaves other agents' persisted stats intact, and `push_warning("[ASM:<agent_id>] persisted stats corrupt — zeroed")`. The app continues to run normally.

**E-15: Orphan stats blob (agent removed from `config.json`).** ASM leaves the orphan `asm_stats_<agent_id>` key in `user://settings.json` untouched. If the user later re-adds that `agent_id` (typo fix, renamed back), historical counters resume. Tiny disk cost per orphan.

**E-16: App force-quit before `_exit_tree()` flushes.** Up to `STATS_WRITE_INTERVAL_SEC` (5s) of stats updates may be lost. This is the accepted data-loss window for the debounced+flush strategy. Documented as a known trade-off; recoverable on next session (state resumes from last-flushed snapshot).

**E-17: `agent_id` collision in `config.json` (two entries with same id).** ConfigurationLoader is the authoritative deduplicator (ADR-0002). ASM trusts whatever `get_agents()` returns — if duplicates slip through, ASM's per-agent dictionary will have one entry per unique id, with later entries overwriting earlier ones. ConfigurationLoader should `push_error` on duplicate detection; ASM does not re-validate.

### 5.5 Mode edge cases

**E-18: Mock mode.** Per ADR-0008, the mock bridge emits the same signal contract as the real bridge. ASM does not differentiate. Mock payloads must conform to the parse rule in Section 3.2 — any mock fixture that doesn't include a valid `stop_reason` will trigger the unknown-stop-reason fallback (Rule 4 row 6).

**E-19: Web mode (mock forced by ADR-0004).** ASM is unaware. The web override happens at ConfigurationLoader; downstream of that, ASM sees identical signals to PC mock mode.

### 5.6 Defensive cases (don't expect, but document)

**E-20: `agent_response_received` signal with empty `payload` string.** ASM treats this as a parse failure (E-1). Transitions to `errored`.

**E-21: ASM destroyed (scene exit) while Timers are pending.** Godot frees child Timer nodes when ASM is freed. No leak. Stats are flushed via `_exit_tree()` (Rule 14). On the next session, state restarts from the persisted stats but agent state begins at `idle` (initial state per Rule 3).

---

## 6. Dependencies

### 6.1 Upstream — systems ASM consumes from

| System | Interface used | Purpose |
|---|---|---|
| **Data Bridge** | `agent_response_received(agent_id: String, payload: String)` signal | Raw payload to parse and derive agent state from |
| Data Bridge | `request_dispatched(agent_id: String)` signal (per ADR-0001 B2) | Marks in-flight start → ASM enters `working` state |
| Data Bridge | `request_settled(agent_id: String)` signal (per ADR-0001 B2) | Marks in-flight end → ASM evaluates last payload to determine next state |
| Data Bridge | `is_request_in_flight(agent_id: String) -> bool` accessor (per ADR-0001 B2) | Read-only query for current in-flight status |
| **ConfigurationLoader** | `get_agents() -> Array[Dictionary]` | Agent registry at bootstrap |
| ConfigurationLoader | `get_setting(key, default) -> Variant` | Reads persisted per-agent stats on bootstrap (per the persist-across-sessions decision) |
| ConfigurationLoader | `set_setting(key, value) -> void` | Writes per-agent stats updates to `user://settings.json` |

**Note**: ASM does NOT subscribe to ConfigurationLoader's `setting_changed` signal — per the bootstrap-only decision, agent registry is fixed after `_ready()`. Mid-session config edits require app restart.

**Note**: ASM does NOT directly consume `agent_connection_changed` from Data Bridge — connection state is orthogonal per ADR-0007. Downstream consumers subscribe to both signals independently.

### 6.2 Downstream — systems ASM provides to

| System | Interface provided | Purpose |
|---|---|---|
| **Agent Character Controller (ACC)** | `agent_state_changed(agent_id: String, new_state: String, previous_state: String)` signal (Tier 2 subscription with `.bind(agent_id)`) | Drives sprite animation via `AnimationPlayer.play(state_name)` per ADR-0009 |
| **Ambient Animation Layer (AAL)** | `agent_state_changed` signal + Room System's room-membership data | AAL aggregates per-room state internally; ASM exposes nothing room-aware |
| **Task Completion Beat (TCB)** | `task_completed(agent_id: String)` signal | Fires on every entry into `completed` state; TCB triggers room flash + audio beat per ADR-0005 |
| **Commander's Room HUD** | `agent_state_changed` signal (per-slot Tier 2) + `get_agent_stats(agent_id) -> Dictionary` accessor (Tier 3) | Slot glyph + detail overlay per ADR-0011 |
| Commander's Room HUD (status panel) | `get_bunker_summary() -> Dictionary` accessor (Tier 3) | Returns `{working_count, errored_count, completed_count, idle_count, total_count}` for the status panel header |

### 6.3 Bidirectional consistency

Each downstream system's GDD must list ASM as an upstream dependency. Specifically:
- `agent-character-controller.md` § Dependencies — ASM
- `ambient-animation-layer.md` § Dependencies — ASM (via `agent_state_changed`)
- `task-completion-beat.md` § Dependencies — ASM (via `task_completed`)
- `commanders-room-hud.md` § Dependencies — ASM (via `agent_state_changed` + accessors)

The traceability index (`docs/architecture/traceability-index.md`) confirms reverse-lookups: every TR-asm-* requirement is referenced from at least one downstream system.

### 6.4 What ASM explicitly does NOT depend on

- **Room System** — ASM is room-blind. Room aggregation happens in AAL.
- **TileMap Renderer** — ASM has no spatial concept.
- **Audio Manager** — ASM emits `task_completed`; TCB calls Audio Manager. ASM and Audio Manager never speak directly.
- **HUD nodes** — ASM doesn't know HUD exists. HUD subscribes; ASM emits to all listeners equally.

This list exists so future implementers don't accidentally couple ASM to systems it shouldn't know about.

---

## 7. Tuning Knobs

ASM exposes four knobs. Their configuration source and governance:

### 7.1 Knob inventory

| Knob | Default | Range | Configuration source | Tuner authority |
|---|---|---|---|---|
| `COMPLETED_DECAY_SEC` | 1.5 | 0.5 – 3.0 | `entities.yaml` → `asm.completed_decay_sec` | game-designer (playtest-driven) |
| `STATS_WRITE_INTERVAL_SEC` | 5.0 | 1.0 – 30.0 | `entities.yaml` → `asm.stats_write_interval_sec` | technical-director (perf trade-off) |
| `UNKNOWN_STOP_REASON_FALLBACK` | `"completed"` | one of `{completed, errored, idle}` | hardcoded `const` in `asm.gd` | technical-director (architectural; requires ADR amendment) |
| `INITIAL_AGENT_STATE` | `"idle"` | one of `{idle, working}` | hardcoded `const` in `asm.gd` | technical-director (architectural; requires ADR amendment) |

**Why split data-driven vs hardcoded**:
- The first two are *tuning* — playtest-driven values you'd expect to adjust during MVP polish. `entities.yaml` exposure means no code change for tuning passes (per coding-standards' "gameplay values must be data-driven, never hardcoded").
- The last two are *architectural decisions* — changing them flips the safety stance of the system. Locked behind code review + ADR amendment intentionally.

### 7.2 Bridge-derived knobs (NOT owned by ASM)

These affect ASM behavior but live in ADR-0001's domain:

| Knob | Owner | Note |
|---|---|---|
| Poll interval per agent | Data Bridge / ConfigurationLoader (per-agent config) | Influences how often ASM sees state changes |
| Backoff curve (1 / 2 / 4 / 30s cap) | Data Bridge (ADR-0001) | ASM never re-derives these |
| HTTP timeout | Data Bridge (ADR-0001) | ASM never sees timeout directly — only `request_settled` |
| 4xx vs 5xx differentiation | Data Bridge (ADR-0001 B1) | Affects connection state, orthogonal to ASM |

### 7.3 entities.yaml schema additions

```yaml
asm:
  completed_decay_sec: 1.5       # range 0.5–3.0; visual feedback duration
  stats_write_interval_sec: 5.0  # range 1.0–30.0; persistence debounce
```

ASM reads these at `_ready()` via `ConfigLoader.get_setting("asm.completed_decay_sec", 1.5)` and `ConfigLoader.get_setting("asm.stats_write_interval_sec", 5.0)`. If `entities.yaml` is missing the keys, ASM falls back to the documented defaults.

### 7.4 What ASM does NOT make tunable (intentional)

- **State vocabulary itself** — adding/removing states requires ADR-0007 amendment + downstream changes (HUD glyph mapping, ACC animation mapping, AAL aggregation). Not a knob.
- **`stop_reason` → state mapping table** — same rationale. Architectural lock.
- **`task_completed` emission timing** — per ADR-0005, sole emitter rule. Not tunable.
- **Stats persistence path** — `user://settings.json` via ConfigurationLoader. Architectural per ADR-0002.

### 7.5 Post-MVP tuning candidates

Knobs that don't exist today but may be added later:
- **Per-provider `stop_reason` mapping override** — for non-Anthropic AI APIs whose vocabulary differs. Would require an ADR-0007 amendment + entities.yaml schema extension.
- **Per-agent decay duration override** — e.g., "Claude completed states linger longer than Cursor's." Currently global. Adding requires schema-per-agent.
- **Stats reset command** — a UI affordance to zero out persisted stats. Today this requires deleting `user://settings.json` manually.
- **Token budget alerts** — emit a signal when `total_input_tokens + total_output_tokens` crosses a threshold. Useful for cost-conscious users.

---

## 8. Acceptance Criteria

ACs are testable conditions QA can verify pass/fail. Each maps to a Section 3 rule or Section 5 edge case. GUT test files at `tests/unit/asm/` per coding-standards' file naming rule.

### 8.1 State derivation (Rule 4)

**AC-1**: Given a payload with `stop_reason: "end_turn"`, when `agent_response_received` fires, ASM transitions the agent to `completed`. (GUT: `test_stop_reason_end_turn_maps_to_completed`)

**AC-2**: Given a payload with `stop_reason: "max_tokens"`, ASM transitions to `completed`. (GUT: `test_stop_reason_max_tokens_maps_to_completed`)

**AC-3**: Given a payload with `stop_reason: "stop_sequence"`, ASM transitions to `completed`.

**AC-4**: Given a payload with `stop_reason: "tool_use"`, ASM transitions to `working`. (GUT: `test_stop_reason_tool_use_maps_to_working`)

**AC-5**: Given a payload with `stop_reason: "pause_turn"`, ASM transitions to `working`.

**AC-6**: Given a payload with `stop_reason: "refusal"`, ASM transitions to `errored`. (GUT: `test_stop_reason_refusal_maps_to_errored`)

**AC-7**: Given a payload with `stop_reason: "future_unknown_value"`, ASM transitions to `completed` AND emits a `push_warning` containing the unknown value. (GUT: `test_unknown_stop_reason_falls_back_to_completed_with_warning`)

**AC-8**: Given a payload that fails JSON parse, ASM transitions to `errored`. (GUT: `test_malformed_payload_maps_to_errored`)

**AC-9**: Given a payload with a top-level `"error"` key (Anthropic error envelope), ASM transitions to `errored` AND sets `last_payload_id` to `request_id` if present.

### 8.2 In-flight tracking (Rule 5)

**AC-10**: On `request_dispatched(agent_id)` from Data Bridge, ASM transitions the agent to `working` (from any prior state).

**AC-11**: On `request_settled(agent_id)` with no preceding `agent_response_received`, ASM transitions the agent to `errored`.

### 8.3 Transient state and decay (Rule 6)

**AC-12**: Entering `completed` schedules a Timer of duration `COMPLETED_DECAY_SEC`. After 1.5s ± 100ms, ASM transitions to `idle`. (GUT: `test_completed_decays_to_idle_after_1500ms`)

**AC-13**: When a new payload arrives mid-decay (e.g., at T+0.8s), the active decay Timer is killed, and the new payload's state takes precedence immediately.

**AC-14**: `errored` state does NOT auto-decay. It persists indefinitely until the next non-error payload.

### 8.4 Signal emission (Rules 9, 10)

**AC-15**: `agent_state_changed(agent_id, new_state, previous_state)` emits on every state transition where `new_state != previous_state`. The `previous_state` argument matches the agent's prior state correctly. (GUT: `test_state_change_emits_agent_state_changed_with_correct_previous_state`)

**AC-16**: `agent_state_changed` does NOT emit on same-state transitions (e.g., consecutive `tool_use` payloads while already `working`).

**AC-17**: `task_completed(agent_id)` emits exactly once on every entry into `completed`, regardless of prior state (`idle → completed`, `working → completed`, `errored → completed`). (GUT: `test_task_completed_emits_on_every_completed_entry`)

**AC-18**: `task_completed` does NOT emit on `completed → idle` decay.

### 8.5 Public read-only API (Rule 15)

**AC-19**: `get_agent_state(agent_id)` returns the canonical state String for a known agent. For an unknown agent, returns `"idle"` (safe default).

**AC-20**: `get_agent_stats(agent_id)` returns a Dictionary with all 9 fields (`current_state`, `tasks_completed`, `errored_count`, `last_state_change_ms`, `last_payload_id`, `last_stop_reason`, `total_input_tokens`, `total_output_tokens`, `session_start_ms`). For an unknown agent, returns empty `{}`.

**AC-21**: `get_bunker_summary()` returns a Dictionary `{idle_count, working_count, completed_count, errored_count, total_count}` where `total_count == sum of all state counts`.

**AC-22**: `is_agent_known(agent_id)` returns `true` only for agents registered at bootstrap.

### 8.6 Stats accumulation and persistence (Rules 13, 14)

**AC-23**: On entry to `completed`, `tasks_completed` increments by exactly 1.

**AC-24**: On entry to `errored`, `errored_count` increments by exactly 1.

**AC-25**: On every successful payload, `total_input_tokens` and `total_output_tokens` increment by the respective `usage` values. Missing `usage` fields contribute 0 (no error).

**AC-26**: After a state transition, the `_stats_dirty[agent_id]` flag is set. Within `STATS_WRITE_INTERVAL_SEC + 100ms`, ConfigurationLoader receives a `set_setting("asm_stats_<agent_id>", ...)` call. The flag is then cleared.

**AC-27**: On `_exit_tree()`, all dirty agents flush regardless of Timer state.

**AC-28**: At `_ready()`, ASM reads persisted stats via `ConfigLoader.get_setting("asm_stats_<agent_id>", {})` and seeds in-memory counters. `session_start_ms` is overwritten to current `Time.get_ticks_msec()`.

### 8.7 Orthogonality (Rules 11, 16)

**AC-29**: ASM does NOT subscribe to `agent_connection_changed`. Mocking both `agent_response_received` (with a `completed` payload) AND `agent_connection_changed("DISCONNECTED")` simultaneously produces the same agent state result as mocking just `agent_response_received`. (GUT: `test_connection_and_agent_state_are_independent`)

### 8.8 Edge case ACs

**AC-30**: Corrupt persisted stats blob (E-14) → that agent's stats zero-initialize, other agents preserved, warning emitted, app continues.

**AC-31**: Orphan stats blob (E-15) → no automatic deletion. The `asm_stats_<orphan_id>` key remains in `user://settings.json` indefinitely.

**AC-32**: Empty agent list at bootstrap (E-12) → ASM accessors return safe defaults; no signals fire; no errors.

**AC-33**: `agent_response_received` with empty payload (E-20) → transitions to `errored` (treated as parse failure).

### 8.9 Test fixtures (recommended)

GUT test files should use fixture helpers for common payloads to keep tests deterministic and DRY:

```gdscript
# tests/helpers/asm_fixtures.gd
static func payload_end_turn(text: String = "ok") -> String:
    return JSON.stringify({
        "model": "claude-haiku-4-5-20251001",
        "id": "msg_test_end_turn",
        "stop_reason": "end_turn",
        "content": [{"type": "text", "text": text}],
        "usage": {"input_tokens": 8, "output_tokens": 5}
    })

static func payload_error(error_type: String = "invalid_request_error") -> String:
    return JSON.stringify({
        "type": "error",
        "error": {"type": error_type, "message": "test error"},
        "request_id": "req_test_error"
    })

static func payload_tool_use() -> String:
    return JSON.stringify({
        "model": "claude-haiku-4-5-20251001",
        "id": "msg_test_tool_use",
        "stop_reason": "tool_use",
        "content": [{"type": "tool_use", "id": "toolu_test", "name": "test_tool", "input": {}}],
        "usage": {"input_tokens": 14, "output_tokens": 12}
    })
```

(Helper file location: `tests/helpers/` per ADR-0014.)

---

## Authoring provenance

This GDD was authored 2026-05-12 in a single session via section-by-section AskUserQuestion panels for design decisions. Sections were written in the order: Overview → Player Fantasy → Dependencies → Detailed Rules → Formulas → Edge Cases → Tuning Knobs → Acceptance Criteria.

### Resolved design decisions (locked during authoring)

| # | Question | Decision |
|---|---|---|
| 1 | Stats persistence across sessions | **Persist** via `ConfigurationLoader.set_setting("asm_stats_<agent_id>", ...)` |
| 2 | Runtime hot-reload of agents | **Bootstrap-only** — no `setting_changed` subscription; config edits require restart |
| 3 | `get_agent_stats(id)` field set | **Full kitchen sink** (9 fields per §4.6) |
| 4 | Conversation context per agent | **Stateless** per poll — ASM stores only the most recent payload's derived state |
| 5 | Player fantasy tone | **Ambient awareness** — companion, not notification system |
| 6 | Vocabulary framing in fantasy section | Name the four feelings (*thinking, working, finishing, struggling*), not the formal state strings |
| 7 | Per-room state aggregation | **AAL aggregates internally** — ASM is room-blind |
| 8 | Bunker-wide summary accessors | **Yes** — `get_bunker_summary()` is part of ASM's public API |
| 9 | Stats persistence write strategy | **Debounced (5s) + flush on `_exit_tree()`** |
| 10 | Bridge connection drop while agent is `working` | **Stay `working`** until `request_settled` arrives per ADR-0001 B2 contract |
| 11 | Corrupt persisted stats blob on bootstrap | **Zero-init that agent + warning** — other agents preserved |
| 12 | Orphan stats blob (agent removed from config) | **Leave untouched** — historical counters resume if agent_id re-added later |
