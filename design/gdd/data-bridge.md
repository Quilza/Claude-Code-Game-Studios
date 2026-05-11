# Data Bridge

> **Status**: Designed — pending /design-review (prototype gate: ACs 18–21 block Approved status)
> **Author**: Thomas + agents
> **Last Updated**: 2026-05-09
> **Implements Pillar**: Alive by Default (Pillar 1) — the live data feed that animates the bunker

> **TL;DR (Claude: read this, skip the full doc unless you need detail)**
> Integration layer. Polls up to 12 AI agent HTTP endpoints on a configurable interval (default 5.0s). One `HTTPRequest` node per agent, independent polling coroutines. Emits raw `String` payload — no JSON parsing. Signals: `agent_response_received(agent_id, http_status, raw_payload)`, `agent_connection_changed(agent_id, connection_state)`, `agent_poll_failed(agent_id, error_code, http_status, error_message)`. Per-agent states: UNINITIALIZED → CONNECTING → CONNECTED / STALE / DISCONNECTED / ERROR. Backoff: grace(1) → STALE(2nd) → DISCONNECTED(4th), cap 30s, auto-heal. Mock mode: `mock: true` in config + `assets/data/mock/[agent_id].json` cycling array. MVP: `http_poll` only (websocket post-MVP). Web CORS deferred to prototype. **Agent State Machine GDD blocked until prototype Qs 4+5 answered.** 21 ACs; 4 prototype-gated.

## Overview

The Data Bridge is the integration layer that connects the Godot application to external AI agent APIs. It reads agent definitions from the Configuration Loader — endpoint URLs, authentication credentials, polling interval, and protocol — and maintains a polling loop that periodically fetches the current status of each configured agent. Raw API responses are normalized into a consistent event format and emitted as signals for the Agent State Machine to consume.

The Data Bridge owns one responsibility: get the data. It does not interpret what agent state means. If an API responds with `{"status": "running", "task": "code review"}`, the Data Bridge passes that payload forward without judgment. The Agent State Machine owns the mapping from raw response fields to canonical game states (`idle / working / completed / errored`). This boundary is a hard constraint — interpretation logic must never bleed into the Data Bridge.

In MVP, the Data Bridge supports the `http_poll` protocol only: each agent endpoint is polled independently on the configured interval (default 5.0 seconds), with up to 12 concurrent poll loops. The system handles network errors, timeouts, and malformed responses without crashing the application. A development mock mode provides synthetic state-change events so the rest of the tool can be built and tested without live API connectivity.

The highest technical risk in the project lives here: real AI agent APIs have unknown response formats, authentication methods, and rate-limit behaviors. This GDD therefore doubles as a prototype specification — the Data Bridge cannot be called "designed" until a working HTTP connection to at least one real agent API has been validated in Godot.

## Player Fantasy

The developer does not monitor their agents. They glance at the bunker.

The modern developer's experience of AI agents is anxiety by default: terminal windows accumulating output, status logs refreshing faster than they can be read, three notification channels open simultaneously. The Situation Room is a deliberate rejection of that mode. The Data Bridge makes it possible.

A figure asleep at their station means the agent is idle. A figure walking to the terminal means work is underway. There is no log to parse, no JSON to read, no retry button to click. The bunker is the interface, and it is always honest. The developer feels relief, not vigilance.

The fantasy the Data Bridge serves is **continuous presence without constant attention.** The developer can look away and trust that when they look back, the bunker will have kept current. It polls on its own. It updates on its own. It does not require supervision. When the developer glances at the screen between their own tasks, the bunker has already caught up to reality.

The experience of the Data Bridge working is indistinguishable from the experience of the bunker being alive. That invisibility is the design target — if the developer ever notices the bridge (a frozen character, a stale status, a connection error they have to manually dismiss), the fantasy breaks. Success is the developer glancing at their bunker at 2pm, 4pm, and 9pm, and each time finding it correct. Failure is any moment where the developer has to *check* whether the bunker is still connected.

## Detailed Design

### Core Rules

1. **One `HTTPRequest` node per configured agent.** The Data Bridge pre-instantiates up to 12 `HTTPRequest` nodes during `_ready()` — one per agent returned by `ConfigurationLoader.get_agents()`. Nodes are never created or freed at runtime. Each node is owned by the Data Bridge and handles only its assigned agent.

2. **Each agent runs an independent polling coroutine.** One `while true: await create_timer(interval).timeout` coroutine starts per agent on startup. Each coroutine fires its `HTTPRequest`, awaits the `request_completed` signal, waits `poll_interval_sec`, then repeats. Polls within a single agent never overlap — the next poll waits for the previous one to complete. Polls across different agents are independent and may overlap.

3. **Poll interval is read from the Configuration Loader once at startup.** All agents share the same interval. The interval is not dynamically adjustable at runtime in MVP.

4. **The Data Bridge emits raw data only — no interpretation.** When a poll returns HTTP 200 with a non-empty body, the bridge emits `agent_response_received(agent_id, http_status, raw_payload)` where `raw_payload` is the response body as a raw `String`. The bridge does NOT parse JSON, does NOT check for specific field names, and does NOT attempt to determine agent state. All interpretation belongs to the Agent State Machine.

5. **Authentication is Bearer token per-agent.** If an agent's `auth_token` field is non-empty in config, every request to that agent's endpoint includes `Authorization: Bearer [auth_token]` as a custom header. If `auth_token` is empty, no Authorization header is sent.

6. **Error recovery uses per-agent backoff — agents auto-heal.** Polling never stops. When polls fail, the bridge enters a graduated backoff:
   - **Grace period** (1st failure): stay CONNECTED, emit nothing
   - **2nd failure**: transition to STALE, emit `agent_connection_changed`
   - **4th consecutive failure**: transition to DISCONNECTED, retry interval caps at `poll_interval_sec × 6` (30s default)
   - **Any success**: immediately return to CONNECTED, emit `agent_response_received`

   Backoff is per-agent — one agent going offline does not affect the other 11.

7. **Mock mode replaces HTTP with synthetic cycling data.** Controlled by the top-level `"mock": true` field in `config.json` (read via `ConfigLoader.is_mock()`) — this is a **global flag**: either all agents are mocked or none are (per-agent granularity is post-MVP). When mock mode is active, DataBridge reads from `assets/data/mock/[agent_id].json` on each "poll" instead of sending HTTP. No `HTTPRequest` nodes are created. The mock file is a JSON array of response objects cycled sequentially (index wraps to 0 after the last entry). A mock response with `"http_status": 0` simulates a timeout. The emitted event is structurally identical to a real response — the Agent State Machine cannot distinguish mock from live. *(Mock mechanism formalized by ADR-0008.)*

8. **MVP supports `http_poll` only.** If `ConfigurationLoader.get_protocol()` returns `"websocket"`, the Data Bridge logs a warning and falls back to `http_poll`. WebSocket support is post-MVP.

9. **Web export CORS strategy is deferred to the prototype phase.** The Data Bridge is designed for PC in MVP. If target AI APIs do not support the required CORS headers for browser requests, a proxy strategy or Web-only mock mode will be designed before any Web deployment.

---

### States and Transitions

Each agent has its own connection state, tracked independently:

| State | Meaning |
|---|---|
| `UNINITIALIZED` | Agent config loaded; no poll attempted yet |
| `CONNECTING` | First poll in flight; no successful response yet |
| `CONNECTED` | Last poll returned HTTP 200 within the staleness window |
| `STALE` | No successful poll for > `poll_interval × 2.5` seconds |
| `DISCONNECTED` | N consecutive failures; retrying with backoff |
| `ERROR` | Unrecoverable config error (unparseable URL, invalid protocol) |

| From | Event | To |
|---|---|---|
| `UNINITIALIZED` | System startup | `CONNECTING` |
| `CONNECTING` | HTTP 200 + non-empty body | `CONNECTED` |
| `CONNECTING` | Error (any), retries < limit | `CONNECTING` |
| `CONNECTING` | Retry limit reached | `DISCONNECTED` |
| `CONNECTED` | Poll success within window | `CONNECTED` (refresh) |
| `CONNECTED` | Staleness window exceeded | `STALE` |
| `STALE` | Poll succeeds | `CONNECTED` |
| `STALE` | 3rd consecutive failure | `DISCONNECTED` |
| `DISCONNECTED` | Poll succeeds | `CONNECTED` |
| `DISCONNECTED` | Poll fails | `DISCONNECTED` (stay, backoff) |
| `ANY` | URL/protocol invalid | `ERROR` |
| `ERROR` | Config reloaded | `UNINITIALIZED` |

---

### Interactions with Other Systems

**Configuration Loader → Data Bridge (upstream, read at startup):**
- `ConfigurationLoader.get_agents()` → `Array[Dictionary]`: agent definitions with `id`, `endpoint_url`, `auth_token`
- `ConfigurationLoader.get_poll_interval()` → `float`: applied to all coroutines
- `ConfigurationLoader.get_protocol()` → `String`: must equal `"http_poll"` in MVP

**Data Bridge → Agent State Machine (downstream, signals):**
- `agent_response_received(agent_id: String, http_status: int, raw_payload: String)` — emitted on every successful HTTP 200 poll
- `agent_connection_changed(agent_id: String, connection_state: String)` — emitted on every state transition
- `agent_poll_failed(agent_id: String, error_code: int, http_status: int, error_message: String)` — emitted after grace period when errors surface
  *(agent_id type corrected from StringName → String per ADR-0001; value originates from JSON parsing)*

---

### Prototype Plan

**This GDD is not approved until a working prototype validates the following six questions in order:**

1. Does `HTTPRequest.request()` with a custom `Authorization: Bearer [token]` header work in Godot 4.6.2 (editor + PC export)?
2. Does `HTTPRequest.timeout` cleanly cancel an in-flight request? Does `request_completed` fire with a timeout error code, or does the node hang?
3. Do 12 simultaneous poll coroutines cause measurable frame budget impact during cold-start? (Profile with Godot's built-in profiler — budget is 16.6ms.)
4. What does a real AI agent status endpoint actually return? (Record the exact JSON structure of at least one target API.)
5. What state-change cadence do real agents produce in practice? Does 5-second polling capture completions, or do rate limits block at 12 polls/minute per token?
6. Does polling from a locally-served Godot HTML5 export fail due to CORS restrictions? (Inspect browser console for CORS errors when polling a real AI API endpoint.)

**Prototype results directly inform the Agent State Machine GDD** (questions 4 and 5). Do not begin designing Agent State Machine until questions 4 and 5 are answered.

## Formulas

The Data Bridge has no gameplay math. All timing values derive from the configured poll interval.

**Staleness threshold:**
```
stale_after_sec = poll_interval_sec × stale_multiplier
                = 5.0 × 2.5
                = 12.5 seconds (at default interval)
```

*Variables:* `poll_interval_sec` (float, from Configuration Loader, default 5.0) · `stale_multiplier` (float, tuning knob, default 2.5)
*Output range:* `stale_after_sec` > 0; must always be > `poll_interval_sec` to avoid false positives on single missed polls

**Backoff retry interval:**
```
retry_interval_sec = min(poll_interval_sec × 2^(attempt - 1), max_retry_interval_sec)
                   = min(5.0 × 2^(attempt - 1), 30.0)

attempt = 1: 5.0s
attempt = 2: 10.0s
attempt = 3: 20.0s
attempt = 4+: 30.0s (capped)
```

*Variables:* `poll_interval_sec` (float, default 5.0) · `attempt` (int, 1-indexed consecutive failure count) · `max_retry_interval_sec` (float, tuning knob, default 30.0)
*Output range:* `poll_interval_sec` ≤ `retry_interval_sec` ≤ `max_retry_interval_sec`

**STALE transition trigger:**
```
is_stale = (current_time_usec - last_success_time_usec) > (stale_after_sec × 1_000_000)
```

*Note:* Staleness is checked on each poll coroutine tick, not on a separate timer. If the coroutine is delayed by a slow network request, the stale check is delayed by the same amount. This is acceptable — a slow but eventually-succeeding request does not trigger STALE.

## Edge Cases

**E1: All 12 agents fire simultaneously on cold start.**
The poll coroutines all start in `_ready()`. With 12 agents, all 12 fire their first HTTP request within the same frame — maximum concurrent load. If cold-start profiling (prototype Q3) shows frame budget impact, introduce a staggered start: add `await get_tree().create_timer(float(agent_index) * 0.1).timeout` before the first poll, distributing cold-start requests across 1.2 seconds.

**E2: An agent endpoint URL is empty or malformed.**
Detected at startup. The agent transitions to `ERROR` state immediately without attempting a poll. `agent_connection_changed` is emitted with `connection_state: "error"`. The error is logged with the agent ID and malformed URL. All other agents continue normally.

**E3: HTTP 200 response with an empty body.**
Treated as a failed poll, not a success. An empty body provides no data for the Agent State Machine to interpret. Emit `agent_poll_failed` with `error_message: "empty_body"`. Enter the grace-period failure sequence. This distinguishes "server reached, no data" from "server unreached."

**E4: HTTP 200 response with a body that is not valid JSON.**
The Data Bridge does not parse JSON — this is intentional. `raw_payload` is passed as-is. If the Agent State Machine cannot parse it, that failure is the State Machine's responsibility. The Data Bridge treats any non-empty body on HTTP 200 as a success. Known tradeoff: invalid JSON propagates upstream rather than being caught at the bridge. Flag this in the Agent State Machine GDD.

**E5: Mock mode active, an agent's mock data file is missing or unreadable.**
Log a warning and emit `agent_poll_failed` on every poll tick. Do not crash. The agent remains in `CONNECTING` state indefinitely. This makes missing mock files visible during development (persistent console warning) without blocking the rest of the tool.

**E6: Mock mode active, an agent's mock file contains an empty array.**
No responses to cycle through. Treat identically to E5: emit `agent_poll_failed` every tick, log `error_message: "empty_mock_array"`.

**E7: Configuration Loader is not in `READY` state when Data Bridge initializes.**
The Data Bridge checks `ConfigurationLoader.get_state()` in `_ready()`. If the state is not `READY`, all agents remain in `UNINITIALIZED` and polling does not begin. The Data Bridge listens for `ConfigurationLoader.state_changed` and retries initialization when `READY` is received. If the Configuration Loader enters a permanent error state (`CONFIG_MISSING`, `CONFIG_MALFORMED`, `CONFIG_INVALID`), the Data Bridge logs the dependency failure and emits no signals.

**E8: `get_protocol()` returns `"websocket"` in MVP.**
Log a warning: `"WebSocket protocol not supported in MVP — falling back to http_poll."` All agents initialize with `http_poll` regardless of configured protocol. Not a crash condition.

**E9: Two agents in config share the same `id`.**
The Configuration Loader is responsible for validating uniqueness — this is caught upstream. The Data Bridge assumes all IDs in `get_agents()` are unique. If duplicates somehow reach the bridge, the second agent's node overwrites the first in the internal agent map (undefined behavior). Flag for the Configuration Loader GDD to enforce uniqueness validation.

## Dependencies

**Upstream (Data Bridge depends on):**

| System | What Data Bridge needs | Status |
|---|---|---|
| Configuration Loader | `get_agents()`, `get_poll_interval()`, `get_protocol()`, `get_state()`, `state_changed` signal | ✅ Designed |

**Downstream (depends on Data Bridge):**

| System | What it needs from Data Bridge | Status |
|---|---|---|
| Agent State Machine | `agent_response_received`, `agent_connection_changed`, `agent_poll_failed` signals | ⬜ Not yet designed — **Agent State Machine GDD must not be authored until prototype questions 4 and 5 are answered** |

**Implementation dependencies (not GDD dependencies):**

- **Godot `HTTPRequest` node**: verified stable through Godot 4.6.2; no breaking changes in 4.4–4.6 range. Confirm `request_completed` signal signature against live docs before implementation.
- **Godot `SceneTree` timer** (`create_timer`): used for poll interval scheduling; respects node `process_mode`
- **Mock data files** (`assets/data/mock/[agent_id].json`): must exist for every agent when mock mode is active; the Data Bridge does not create them at runtime

**Bidirectional note:** The Configuration Loader GDD already references the Data Bridge as a downstream consumer of its Integration data class. No update to that GDD required.

## Tuning Knobs

| Knob | Default | Safe Range | Gameplay Effect |
|---|---|---|---|
| `poll_interval_sec` | `5.0` | `1.0 – 60.0` | How often each agent is polled. Lower = more responsive but higher API request volume and rate-limit risk. Upper bound depends on target API rate limits (see prototype Q5). Owned by Configuration Loader; read by Data Bridge. |
| `stale_multiplier` | `2.5` | `1.5 – 5.0` | Multiplied by `poll_interval_sec` to set the staleness window. Below 1.5: STALE triggers on normal single-missed polls (too sensitive). Above 5.0: a truly stale connection goes undetected for 25+ seconds. At default (5s × 2.5 = 12.5s), one full missed poll is allowed before visual warning. |
| `max_retry_interval_sec` | `30.0` | `10.0 – 120.0` | Caps the backoff retry interval. Lower: more aggressive recovery attempts. Higher: fewer retry requests against a known-offline endpoint. |
| `grace_period_failures` | `1` | `1 – 3` | Number of consecutive failed polls before any state change is emitted. At 1, a single timeout triggers the backoff sequence (STALE warning at failure 2). Increasing this adds resilience against transient network hiccups at the cost of delayed error visibility. |
| `staggered_start_delay_sec` | `0.0` | `0.0 – 0.2` | Per-agent startup delay multiplier for cold-start staggering (`agent_index × delay`). Disabled by default. Enable if prototype Q3 reveals frame budget impact from simultaneous cold-start polls. At `0.1`, 12 agents stagger across 1.2 seconds. |

**Notes:**
- `poll_interval_sec` is the only knob exposed in `config.json`. All other knobs are constants in the Data Bridge implementation — not user-configurable in MVP.
- Do not reduce `poll_interval_sec` below `1.0` without validating that target APIs do not rate-limit at 60 requests/minute per token. Most AI APIs enforce rate limits by API key, not by IP.

## Visual/Audio Requirements

The Data Bridge produces no visual output and triggers no audio directly. All visual and audio expressions of bridge state are owned by the systems that consume its signals:

- **STALE / DISCONNECTED states** → The Agent Character Controller and Ambient Animation Layer translate `agent_connection_changed` events into visual state changes (e.g., a frozen or offline visual on the agent character). See Agent Character Controller GDD.
- **Error states** → The Commander's Room HUD surfaces connection errors to the developer. The Data Bridge emits signals only — it owns no UI.
- **Mock mode indicator** → During development, mock-mode agents should be visually distinguishable from live agents in any debug overlay. This is a dev-tools concern only, not present in shipped builds.

The Data Bridge's contribution to Pillar 1 (Alive by Default) and Pillar 2 (Readable at a Glance) is entirely indirect: it keeps the data current so that character animations remain accurate. If the bridge falls silent, the bunker freezes. That consequence is the only "visual" the bridge produces.

## Acceptance Criteria

### Connectivity

- [ ] **AC-01** The Data Bridge successfully polls a real HTTP endpoint returning a JSON body, receives the `agent_response_received` signal with the correct `agent_id`, `http_status: 200`, and a non-empty `raw_payload` string.
- [ ] **AC-02** The Data Bridge sends `Authorization: Bearer [token]` on every request for agents with a non-empty `auth_token` in config. Verify by inspecting request headers in a local debug HTTP server.
- [ ] **AC-03** The Data Bridge polls at the configured interval (±200ms tolerance). With `poll_interval_sec: 5.0`, consecutive polls arrive at 5.0 ±0.2 seconds apart, measured over 5 cycles.
- [ ] **AC-04** With 12 agents configured, all 12 polling loops run concurrently without frame budget impact. Cold-start frame time remains ≤ 16.6ms during the first poll cycle (measured via Godot profiler).

### Error Handling

- [ ] **AC-05** When polls fail, the agent transitions through grace period (1 failure, no event) → STALE (2nd failure, emit `agent_connection_changed`) → DISCONNECTED (4th failure, emit `agent_connection_changed`) in the correct sequence.
- [ ] **AC-06** When a poll times out, the `HTTPRequest` node cancels cleanly. The coroutine receives the timeout error, waits the retry interval, and re-polls. The node is not left in a hung state.
- [ ] **AC-07** When a poll returns HTTP 200 with an empty body, `agent_poll_failed` is emitted (not `agent_response_received`). The agent enters the grace period sequence.
- [ ] **AC-08** When a disconnected agent's endpoint becomes reachable again, the next successful poll transitions the agent to CONNECTED and emits `agent_response_received`. No manual intervention required.
- [ ] **AC-09** One agent entering DISCONNECTED state has zero effect on the polling cadence of all other agents.

### Mock Mode

- [ ] **AC-10** In mock mode, an agent with a valid mock data file cycles through all entries in sequence across successive poll ticks. After the last entry, the next poll returns index 0.
- [ ] **AC-11** In mock mode, an agent with a mock entry of `http_status: 0` emits `agent_poll_failed` and enters the backoff sequence identically to a real timeout.
- [ ] **AC-12** In mock mode, an agent with a missing mock file emits `agent_poll_failed` on every poll tick and never reaches CONNECTED state.
- [ ] **AC-13** Mock-mode agents emit events that are structurally indistinguishable from live-mode events. A connected Agent State Machine cannot determine which mode is active from signal data alone.

### Initialization

- [ ] **AC-14** When the Configuration Loader is in `READY` state, the Data Bridge begins polling within one frame of `_ready()` completing.
- [ ] **AC-15** When the Configuration Loader is NOT in `READY` state at startup, no polling begins. Polling starts automatically when `ConfigurationLoader.state_changed` fires with `READY`.
- [ ] **AC-16** An agent with an empty or malformed endpoint URL emits `agent_connection_changed` with `connection_state: "error"` at startup and never sends an HTTP request.
- [ ] **AC-17** When `get_protocol()` returns `"websocket"`, the Data Bridge logs a warning, falls back to `http_poll`, and does not crash.

### Prototype Gate (blocking — must be answered before GDD is marked Approved)

- [ ] **AC-18 (PROTOTYPE)** `HTTPRequest.request()` with a custom Bearer token header successfully reaches and authenticates against at least one real AI agent API endpoint in Godot 4.6.2 (editor build).
- [ ] **AC-19 (PROTOTYPE)** `HTTPRequest.timeout` cleanly cancels an in-flight request and the coroutine recovers in the normal retry sequence without node state corruption.
- [ ] **AC-20 (PROTOTYPE)** At least one real AI agent status API endpoint has been identified, polled, and its response JSON structure documented. The Agent State Machine GDD is unblocked.
- [ ] **AC-21 (PROTOTYPE)** Rate limit behavior of at least one target API is documented: maximum safe poll frequency per token, and whether 12 agents × 5-second interval stays within that limit.

## Open Questions

1. **Web export CORS strategy** — Deferred to prototype Q6. Decision required before any Web deployment: (a) add CORS headers to controlled agent endpoints, (b) route through a same-origin proxy, or (c) Web export shows mock data only. The answer may vary per target AI API.

2. **`request_completed` signal signature** — Must be verified against live Godot 4.6.2 docs before implementation. Historical signature: `(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray)`. Confirm it has not changed in 4.4–4.6.

3. **Which AI agent APIs to target first** — Unknown at design time. Prototype Q4 will answer this. The answer determines the mock data format used during development and may influence the Agent State Machine state model.

4. **Rate limit discovery** — The `poll_interval_sec` default of 5.0 seconds was chosen conservatively before any real API rate limits are known. Prototype Q5 may require adjusting this default upward (if rate limits are tight) or confirm it is safe.
