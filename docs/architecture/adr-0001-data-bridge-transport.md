# ADR-0001: Data Bridge Transport Strategy

## Status
Accepted (2026-05-12)

## Date
2026-05-11

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.2 |
| **Domain** | Core / Networking (HTTP Client) |
| **Knowledge Risk** | MEDIUM — HTTPRequest node has no documented changes in 4.4–4.6 (engine reference shows no HTTPRequest entries in breaking-changes.md), but post-cutoff behavior is not explicitly confirmed in project reference docs |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/deprecated-apis.md`, `docs/engine-reference/godot/modules/networking.md` |
| **Post-Cutoff APIs Used** | `HTTPRequest.timeout` (property, confirmed present since 4.0); `HTTPRequest.RESULT_TIMEOUT` (enum constant, confirmed by engine specialist); `PackedByteArray.get_string_from_utf8()` (stable) |
| **Verification Required** | VERIFY-7: `HTTPRequest.request_completed` signal fires with the correct 4-arg signature `(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray)` in Godot 4.6.2 — test against a real HTTP endpoint before shipping. VERIFY-8: `HTTPRequest.timeout` cancels an in-flight request cleanly and fires `request_completed` with `RESULT_TIMEOUT` — test against a slow/unresponsive endpoint before shipping. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0002 (Configuration Loading + Persistence) — DataBridge reads `get_agents()`, `get_poll_interval()`, `is_mock()`, `get_protocol()` from ConfigLoader; ADR-0003 (Autoload Scene Composition) — DataBridge is a Phase 2 system instantiated by the Main Scene Bootstrap; ADR-0006 (Signal-Based Decoupling Pattern) — DataBridge emits Tier 1 signals; ADR-0008 (Mock Mode Strategy) — is_mock() controls which polling path DataBridge uses |
| **Enables** | Agent State Machine GDD and implementation (consumes DataBridge signals); Data Bridge prototype (implements this transport spec); all systems downstream of ASM |
| **Blocks** | DataBridge implementation; Data Bridge prototype; Agent State Machine GDD cannot be finalized until prototype answers Questions 4 and 5 (see `data-bridge.md`) |
| **Ordering Note** | All four dependency ADRs must exist before DataBridge implementation begins. Write before the prototype. |

## Context

### Problem Statement

DataBridge must poll up to 12 AI agent HTTP endpoints simultaneously, handle network errors gracefully, and emit consistent signals that the Agent State Machine can consume regardless of which AI API is being polled. Without explicit architectural decisions, the transport implementation will vary by developer and the signal contracts that all downstream systems depend on cannot be locked.

This ADR decides: the HTTP transport mechanism, the HTTPRequest node lifecycle, the coroutine polling pattern, the signal signatures for the three DataBridge events, the authentication approach, the timeout strategy, and the CORS posture for web exports.

### Constraints

- **Godot 4.6.2 HTTP client**: `HTTPRequest` is the Godot-native HTTP client node. No external networking libraries are used (no GDExtension, no GDNative). This ensures the transport works on all target platforms with no additional build steps.
- **One node per agent**: the GDD (`data-bridge.md` Rule 1) establishes this constraint — pre-instantiated at `_ready()`, never created or freed at runtime.
- **12 agent maximum**: `max_agents` from the entity registry. Performance budget: 12 simultaneous poll coroutines must not exceed the 16.6ms frame budget.
- **Raw payload only**: DataBridge emits the body as a raw `String` — no JSON parsing. All interpretation belongs to the Agent State Machine.
- **MVP: HTTP polling only**: WebSocket support is post-MVP (GDD Rule 8).
- **Web export CORS**: browser security policies apply CORS restrictions to cross-origin requests. Most AI APIs do not support CORS for browser clients. This is a known risk deferred to the prototype phase.
- **No conditional code in consumers**: all DataBridge consumers (ASM, HUD) must not check is_mock(). DataBridge's mock/live branching is internal (see ADR-0008).

### Requirements

- Signal signatures are typed and stable — ASM and HUD connect to them; changes require a superseding ADR
- One HTTPRequest node per agent, instantiated at _ready(), never freed at runtime
- Per-agent polling coroutines are independent — one agent failing does not block others
- Authorization: Bearer token header per-agent if auth_token is non-empty in config
- Timeout per request: 10.0 seconds default (configurable)
- Backoff per GDD Rule 6: grace(1) → STALE(2nd) → DISCONNECTED(4th); cap 30s; auto-heal
- Connection state transitions emit `agent_connection_changed` signal
- All errors after grace period emit `agent_poll_failed` signal
- `agent_id` parameter type is `String` throughout (not `StringName` — source value is JSON-parsed)

## Decision

### Signal Contracts (Locked)

These three signals are the complete public interface of DataBridge. All systems that consume DataBridge events connect to exactly these signals.

```gdscript
# In res://src/core/data_bridge.gd

## Emitted on every successful HTTP 200 response.
## raw_payload: the response body as a UTF-8 string — no JSON parsing performed.
## Consumers: AgentStateMachine (interprets payload → agent state transitions)
signal agent_response_received(agent_id: String, http_status: int, raw_payload: String)

## Emitted on every per-agent connection state transition.
## connection_state: one of "UNINITIALIZED" | "CONNECTING" | "CONNECTED" | "STALE" | "DISCONNECTED" | "ERROR"
## Consumers: CommandersRoomHUD (connection status indicators)
signal agent_connection_changed(agent_id: String, connection_state: String)

## Emitted after the grace period when poll errors persist.
## error_code: Godot error code (e.g. ERR_CANT_CONNECT) or 0 if not applicable
## http_status: the HTTP response code, or 0 if no response was received
## Consumers: AgentStateMachine (drives STALE/DISCONNECTED state logic)
signal agent_poll_failed(agent_id: String, error_code: int, http_status: int, error_message: String)
```

**GDD sync**: `data-bridge.md`'s Interactions section lists these signals with `StringName` for `agent_id`. This ADR corrects the type to `String` (the value originates from JSON parsing and config loading as `String`; using `StringName` forces a conversion on every emission). The GDD will be updated.

### HTTPRequest Node Lifecycle

```gdscript
# DataBridge._ready() — node setup
var _http_nodes: Dictionary = {}       # agent_id (String) -> HTTPRequest
var _agent_configs: Dictionary = {}    # agent_id (String) -> agent Dictionary
var _agent_states: Dictionary = {}     # agent_id (String) -> connection_state String
var _failure_counts: Dictionary = {}   # agent_id (String) -> int
var _mock_indices: Dictionary = {}     # agent_id (String) -> int (mock mode only)
var _is_mock: bool = false
var _poll_interval: float = 5.0

const DEFAULT_TIMEOUT_SEC: float = 10.0

func _ready() -> void:
    _is_mock = ConfigLoader.is_mock()
    _poll_interval = ConfigLoader.get_poll_interval()

    for agent in ConfigLoader.get_agents():
        var agent_id: String = agent["id"]
        _agent_configs[agent_id] = agent
        _agent_states[agent_id] = "UNINITIALIZED"
        _failure_counts[agent_id] = 0

        if _is_mock:
            _mock_indices[agent_id] = 0
            _start_mock_polling_coroutine(agent_id)  # defined in ADR-0008
        else:
            _validate_agent_config(agent_id)  # → ERROR state if URL invalid
            var node := HTTPRequest.new()
            node.timeout = DEFAULT_TIMEOUT_SEC
            add_child(node)
            _http_nodes[agent_id] = node
            _start_http_polling_coroutine(agent_id, node)
```

**HTTPRequest nodes are never freed at runtime.** They live for the application lifetime alongside DataBridge (a Phase 2 / Main Scene system). Re-use: after `request_completed` fires, the node is automatically ready for the next `request()` call — no reset required.

### HTTP Polling Coroutine

```gdscript
func _start_http_polling_coroutine(agent_id: String, node: HTTPRequest) -> void:
    _emit_connection_changed(agent_id, "CONNECTING")

    while true:
        # Build request
        var config: Dictionary = _agent_configs[agent_id]
        var url: String = config["endpoint_url"]
        var auth_token: String = config.get("auth_token", "")
        var headers := PackedStringArray()
        if not auth_token.is_empty():
            headers.append("Authorization: Bearer " + auth_token)

        var err := node.request(url, headers)
        if err != OK:
            _handle_poll_failure(agent_id, err, 0,
                "HTTPRequest.request() failed with error %d" % err)
            await get_tree().create_timer(_backoff_interval(agent_id)).timeout
            continue

        # Await response — typed Array: [result: int, response_code: int,
        #                                headers: PackedStringArray, body: PackedByteArray]
        var response: Array = await node.request_completed
        var result_code: int = response[0]
        var http_status: int = response[1]
        # response[2] = headers (unused — DataBridge does not parse response headers)
        var body: PackedByteArray = response[3]

        if result_code == HTTPRequest.RESULT_TIMEOUT:
            _handle_poll_failure(agent_id, result_code, 0, "Request timed out")
        elif result_code != HTTPRequest.RESULT_SUCCESS:
            _handle_poll_failure(agent_id, result_code, http_status,
                "HTTPRequest failed with result %d" % result_code)
        elif http_status != 200:
            _handle_poll_failure(agent_id, 0, http_status,
                "Non-200 response: %d" % http_status)
        else:
            _failure_counts[agent_id] = 0
            _handle_poll_success(agent_id)
            agent_response_received.emit(agent_id, http_status,
                body.get_string_from_utf8())

        await get_tree().create_timer(_poll_interval).timeout
```

### Backoff and Connection State Machine

Per `data-bridge.md` Rule 6:

```gdscript
func _handle_poll_failure(agent_id: String, error_code: int,
                           http_status: int, message: String) -> void:
    _failure_counts[agent_id] += 1
    var count: int = _failure_counts[agent_id]

    if count == 1:
        pass  # Grace period — stay CONNECTING/CONNECTED, emit nothing
    elif count == 2:
        _emit_connection_changed(agent_id, "STALE")
        agent_poll_failed.emit(agent_id, error_code, http_status, message)
    elif count >= 4:
        _emit_connection_changed(agent_id, "DISCONNECTED")
        agent_poll_failed.emit(agent_id, error_code, http_status, message)

func _handle_poll_success(agent_id: String) -> void:
    var was_disconnected := _agent_states[agent_id] in ["STALE", "DISCONNECTED"]
    _failure_counts[agent_id] = 0
    _emit_connection_changed(agent_id, "CONNECTED")
    # agent_response_received is emitted by the caller

func _backoff_interval(agent_id: String) -> float:
    # Cap retry interval at poll_interval × 6 (30s default) when DISCONNECTED
    if _agent_states[agent_id] == "DISCONNECTED":
        return minf(_poll_interval * 6.0, 30.0)
    return _poll_interval

func _emit_connection_changed(agent_id: String, new_state: String) -> void:
    if _agent_states[agent_id] == new_state:
        return  # Suppress duplicate transitions
    _agent_states[agent_id] = new_state
    agent_connection_changed.emit(agent_id, new_state)
```

### Timeout Configuration

`HTTPRequest.timeout` is set to `DEFAULT_TIMEOUT_SEC = 10.0` seconds per node. When exceeded, `request_completed` fires with `result_code == HTTPRequest.RESULT_TIMEOUT`. This is treated as a poll failure subject to the standard backoff.

A 10-second timeout is appropriate for AI agent status endpoints (expected to be fast internal APIs). It prevents a slow/unresponsive endpoint from blocking the coroutine indefinitely while still allowing reasonable latency.

The timeout is per-request (not per-session) and resets automatically before each `node.request()` call.

### Web Export CORS Strategy (Deferred)

In HTML5 exports, all HTTP requests originate from the browser's context and are subject to the browser's Same-Origin Policy. AI agent API endpoints (e.g., the Anthropic Claude API, Cursor API) do not typically include `Access-Control-Allow-Origin` headers for browser clients. This means:

- **PC exports** (Windows, macOS, Linux): DataBridge works as specified; no CORS restrictions apply.
- **Web exports**: `HTTPRequest.request()` will succeed in Godot's networking layer, but the browser will block the response before it reaches `request_completed`. The response body will be empty and the result may be `RESULT_SUCCESS` with an empty body, or the browser may silently drop it.

**This is deferred to the Data Bridge prototype phase** (prototype Question 6 in `data-bridge.md`). Resolution options include:

1. **Proxy server**: route DataBridge requests through a developer-controlled server that adds CORS headers.
2. **Web-only mock mode**: force `is_mock() = true` in web exports regardless of config.
3. **Accept PC-only for MVP**: ship web export in mock mode; live connectivity is PC-only.

A new ADR superseding this one will formalize the CORS resolution once the prototype identifies which option is feasible. Until then, the web export CORS constraint is explicitly **unresolved and non-blocking for MVP**.

### Architecture Diagram

```
config.json                      DataBridge._ready()
  agents[0..11]  ──────────────► HTTPRequest × 12 nodes (add_child)
  poll_interval                       │
  auth_tokens                         │  per-agent coroutines (independent)
                                      │
                          ┌───────────┼───────────┐
                          │           │           │
                       agent-0     agent-1  ... agent-11
                          │           │           │
                    node.request()  node.request()  ...
                          │
                    await request_completed  ← (result, code, headers, body)
                          │
                  ┌───────┴──────────────┐
                  │ success (HTTP 200)   │ failure / timeout
                  │                     │
           agent_response_received   _handle_poll_failure()
           (agent_id, 200, payload)       │
                  │               ┌──────┴──────┐
                  ▼               │ count==2    │ count>=4
           AgentStateMachine    STALE         DISCONNECTED
                                  └──► agent_connection_changed
                                  └──► agent_poll_failed
```

### Key Interfaces

```gdscript
# Public signals (complete DataBridge event API):
signal agent_response_received(agent_id: String, http_status: int, raw_payload: String)
signal agent_connection_changed(agent_id: String, connection_state: String)
signal agent_poll_failed(agent_id: String, error_code: int, http_status: int, error_message: String)

# Public methods (Tier 2 — injected ref access by bootstrap):
func get_agent_state(agent_id: String) -> String:    # returns current connection_state
    return _agent_states.get(agent_id, "UNINITIALIZED")

func get_all_agent_states() -> Dictionary:           # returns copy — never internal ref
    return _agent_states.duplicate()
```

## Alternatives Considered

### Alternative B: WebSocket for all agents

- **Description**: Establish a WebSocket connection per agent rather than polling.
- **Pros**: Real-time push — no polling latency; lower API request volume.
- **Cons**: Most AI agent status APIs do not expose WebSocket endpoints. Requires the API server to maintain the connection. Godot's `WebSocketPeer` API is more complex than `HTTPRequest`. Authentication over WebSocket varies by API.
- **Rejection Reason**: MVP targets AI agent HTTP status APIs as they exist today — none of the initially targeted APIs (Claude API, Cursor) expose WebSocket status endpoints. WebSocket is documented as post-MVP in the GDD (Rule 8).

### Alternative C: Single shared HTTPRequest node with a request queue

- **Description**: One HTTPRequest node for all agents, with a queue that dispatches one request at a time.
- **Pros**: Fewer nodes; simpler node management.
- **Cons**: Sequential — agent 12 cannot poll until agents 1–11 complete their polls. With 12 agents at 10s timeout each, worst-case round-trip is 120 seconds. Destroys the "alive by default" design pillar. Rate-limits the feedback loop unacceptably.
- **Rejection Reason**: Independent per-agent polling is a core GDD requirement (Rule 2: "Polls across different agents are independent and may overlap"). A queue directly contradicts this.

### Alternative D: GDExtension HTTP client (libcurl or similar)

- **Description**: A native GDExtension wrapper around a battle-tested HTTP library.
- **Pros**: More control over connection pooling, timeouts, TLS options.
- **Cons**: Requires building and shipping a native extension for each target platform (Windows, macOS, Linux, Web). Significant toolchain overhead for a developer tool project. Web export support for GDExtensions is limited.
- **Rejection Reason**: `HTTPRequest` satisfies all requirements at zero build overhead. Native HTTP client is warranted only if `HTTPRequest` proves insufficient during the prototype.

## Consequences

### Positive

- Per-agent independence: one failing endpoint never blocks others.
- Simple coroutine pattern: each coroutine is self-contained and easy to debug.
- Signal contracts are stable: ASM and HUD are isolated from transport implementation details.
- Mock mode (ADR-0008) uses the same signal interface — switching mock ↔ live requires only a config change.
- Timeout is explicit and configurable — no hanging requests.

### Negative

- 12 HTTPRequest nodes add to the scene tree (12 extra nodes). Each is a lightweight resource; total memory impact is negligible but tooling (Scene debugger) will show them.
- Polling is inherently bursty — 12 agents at 5.0s interval means up to 12 HTTP requests firing in the same frame on startup (staggered only by coroutine scheduling, not explicit jitter). A future improvement is randomized startup jitter per agent.
- Web export CORS is unresolved for MVP. Web users who want live connectivity must wait for the prototype resolution.

### Risks

- **`request_completed` signature change (MEDIUM risk)**: If Godot 4.4–4.6 changed `request_completed`'s parameter types (e.g., `headers` type), the `response[2]` index would be wrong. Mitigation: VERIFY-7 — test against a real endpoint before shipping.
- **RESULT_TIMEOUT behavior (MEDIUM risk)**: If timeout fires a different result code than `HTTPRequest.RESULT_TIMEOUT`, the failure detection logic silently miscategorizes it as `RESULT_SUCCESS != 0`. Mitigation: VERIFY-8 — test against a slow endpoint before shipping.
- **Startup poll burst**: all 12 coroutines fire their first poll immediately in `_ready()`. If the API rate-limits based on requests-per-second, the burst may trigger 429 responses. Mitigation: a startup jitter flag (random 0–poll_interval delay before first poll) can be added if the prototype reveals rate-limit problems.
- **Freed node reference in coroutine**: if DataBridge's scene is unloaded while a coroutine is `await`ing `request_completed`, Godot may deliver the signal to a freed object. Mitigation: coroutines check `is_instance_valid(self)` or use the scene-tree quit signal to cancel; this pattern should be implemented and tested before ship.
- **Web CORS silently succeeds**: the browser may return a result code of 0 (SUCCESS) with an empty body rather than an error when CORS blocks the response. This would cause DataBridge to emit `agent_response_received` with an empty payload, which ASM would fail to interpret as a valid state. Mitigation: ASM must handle empty payloads as parse failures; this is documented in the prototype scope.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `data-bridge.md` (Rule 1) | "One HTTPRequest node per configured agent, pre-instantiated during `_ready()`" | Confirmed: one `HTTPRequest.new()` per agent, `add_child()` at init, stored in `_http_nodes` dict |
| `data-bridge.md` (Rule 2) | "Each agent runs an independent polling coroutine" | Per-agent `_start_http_polling_coroutine()` call; coroutines are independent — one blocking does not pause others |
| `data-bridge.md` (Rule 4) | "Data Bridge emits raw data only — no interpretation" | `agent_response_received` carries `body.get_string_from_utf8()` unmodified |
| `data-bridge.md` (Rule 5) | "Authorization is Bearer token per-agent" | `headers.append("Authorization: Bearer " + auth_token)` if `auth_token` non-empty |
| `data-bridge.md` (Rule 6) | Backoff: grace(1) → STALE(2nd) → DISCONNECTED(4th); cap 30s; auto-heal | `_handle_poll_failure()` with `_failure_counts` + `_backoff_interval()` |
| `data-bridge.md` (Rule 9) | "Web export CORS strategy is deferred to prototype" | This ADR explicitly marks CORS as unresolved; a superseding ADR covers it post-prototype |
| All GDDs | Signals consumed by ASM, HUD | Signal signatures locked and typed in this ADR |

**GDD sync required**: `data-bridge.md` Interactions section lists signal parameters with `StringName` for `agent_id`. This ADR changes the type to `String`. Update the GDD to match.

## Performance Implications

- **CPU**: 12 coroutines × 1 poll per 5s = 2.4 polls/sec across the whole system. Each poll is an async network round-trip — the coroutine suspends at `await request_completed` and does not burn CPU while waiting. Frame budget impact during polling: negligible. Signal dispatch on response: <0.01ms for 12 agents.
- **Memory**: 12 HTTPRequest nodes × ~few KB each = <100 KB. Acceptable. Each node holds one in-flight request buffer (body is a PackedByteArray on the heap until `request_completed` fires).
- **Load Time**: `_ready()` synchronously creates 12 nodes and starts 12 coroutines. First polls fire on the next event loop tick. No blocking I/O in `_ready()`.
- **Network**: 12 agents × ~1 request/5s = 2.4 requests/sec outbound. AI API rate limits are per-token, not per-request-rate at this scale. Monitor during prototype.

## Migration Plan

N/A — establishes pattern before implementation. Prototype validation (data-bridge.md Section C Questions 1–6) must be completed before this ADR can be Accepted.

## Validation Criteria

- GUT: `test_one_http_node_per_agent()` — ConfigLoader mock returns 3 agents; DataBridge._ready() must add exactly 3 HTTPRequest nodes as children
- GUT: `test_grace_period_on_first_failure()` — mock first poll failure; `agent_connection_changed` must NOT be emitted; state must remain "CONNECTING"
- GUT: `test_stale_on_second_failure()` — mock two consecutive failures; `agent_connection_changed("STALE")` must be emitted on the second failure
- GUT: `test_disconnected_on_fourth_failure()` — mock four consecutive failures; `agent_connection_changed("DISCONNECTED")` must be emitted
- GUT: `test_auto_heal_on_success()` — mock failures then a success; `agent_connection_changed("CONNECTED")` emitted; `_failure_counts` reset to 0
- GUT: `test_response_received_payload_unmodified()` — mock HTTP 200 with body `'{"status": "ok"}'`; `agent_response_received` payload must equal `'{"status": "ok"}'` exactly
- GUT: `test_bearer_header_attached()` — agent config with `auth_token`; mock HTTPRequest captures headers; verify `Authorization: Bearer [token]` present
- GUT: `test_no_auth_header_when_empty()` — agent config with empty `auth_token`; verify no `Authorization` header sent
- GUT: `test_timeout_triggers_failure()` — mock `RESULT_TIMEOUT` from HTTPRequest; verify `_handle_poll_failure` called
- Manual (prototype): VERIFY-7 — `request_completed` fires with correct 4-arg signature against a real HTTP endpoint
- Manual (prototype): VERIFY-8 — `timeout = 10.0` cancels cleanly; `RESULT_TIMEOUT` fires; node ready for next request immediately after

## Related Decisions

- ADR-0002: Configuration Loading + Persistence — defines `get_agents()`, `get_poll_interval()`, `is_mock()`, `get_protocol()` that DataBridge reads
- ADR-0003: Autoload Scene Composition — DataBridge is a Phase 2 system, bootstrap-instantiated; HTTPRequest nodes are DataBridge's children (scene-scoped, not application-lifetime)
- ADR-0006: Signal-Based Decoupling Pattern — three DataBridge signals are Tier 1 events; all consumers connect via bootstrap
- ADR-0008: Mock Mode Strategy — is_mock() determines which polling path activates; both paths emit identical signals
- ADR-0005: task_completed Signal Source — ASM (downstream consumer) interprets `agent_response_received` and emits `task_completed` when a task completes

---

## Amendment 2026-05-12.b (post-Sprint-1 prototype)

Source: `prototypes/data-bridge/findings.md` (Sprint 1 real-API observations against Anthropic Messages API) + `docs/architecture/adr-0007-agent-state-vocabulary.md` (ADR-0007's `working` state requires in-flight visibility).

### B1 — 4xx config-fatal vs 5xx/network transient differentiation

**Empirical finding**: Anthropic returns **HTTP 400** for credit-balance errors (not the conventional 402 Payment Required). Other config-fatal errors land on 400 (invalid_request_error) and 404 (model not_found_error). These will never auto-heal — the user must fix configuration. Treating them as transient burns API calls and confuses the bridge into a perpetual backoff loop.

**Amended backoff rule**:

```gdscript
# pseudocode in _handle_poll_failure
if response_code >= 400 and response_code < 500:
    # Config-fatal — do not retry. Transition to DISCONNECTED immediately.
    _transition_state(agent_id, STATE_DISCONNECTED)
    push_warning("[DataBridge:%s] HTTP %d config-fatal — bridge will not retry until config changes" % [agent_id, response_code])
    return
# 5xx or network errors fall through to the original backoff curve:
#   grace(1) → STALE(2) → DISCONNECTED(4); cap 30s; auto-heal on success
```

Recovery from a 4xx-induced DISCONNECTED state requires either:
- a ConfigurationLoader `setting_changed` signal (e.g., user updated token in user://settings.json)
- a manual bridge restart (re-bootstrap on scene reload)

Production HUD should surface 4xx-induced DISCONNECTED with explicit copy ("Configuration error — check your API key and model") distinct from network-induced DISCONNECTED ("Connection lost — retrying").

### B2 — Request-in-flight signal exposure (required by ADR-0007 `working` state)

**Findings link**: ADR-0007 specifies that ASM's `working` state is entered when a request is in flight, BEFORE the response arrives. Without bridge-side visibility into in-flight state, the HUD shows `idle` during the request window — which can be hundreds of milliseconds for slow API endpoints or actual agent workloads.

**New signals added to DataBridge contract**:

```gdscript
signal request_dispatched(agent_id: String)   # fires immediately before HTTPRequest.request() call
signal request_settled(agent_id: String)      # fires after _on_request_completed, regardless of success/failure
```

**New read-only accessor**:

```gdscript
func is_request_in_flight(agent_id: String) -> bool
```

ASM subscribes to `request_dispatched` and `request_settled` per ADR-0006 Tier 2 (`.bind(agent_id)`) and updates its in-flight tracking. Combined with `agent_response_received` payload parsing, ASM can correctly derive `working` for the entire request window plus the multi-step `tool_use`/`pause_turn` cases.

The new signals are additive — existing consumers (HUD, AAL, TCB) are not required to subscribe. Only ASM needs them.

### B3 — Anthropic error envelope shape (documented for ASM)

Empirically observed Anthropic error response body:

```json
{
  "type": "error",
  "error": {
    "type": "invalid_request_error" | "not_found_error" | "rate_limit_error" | "api_error" | "overloaded_error",
    "message": "human-readable reason"
  },
  "request_id": "req_..."
}
```

DataBridge does NOT parse this (raw String passthrough per ADR-0001 single-writer rule). ASM parses it per ADR-0007's derivation rule. Documented here for cross-reference.

### B4 — Rate-limit header parsing (deferred, post-MVP)

Anthropic returns `anthropic-ratelimit-requests-limit`, `anthropic-ratelimit-requests-remaining`, `anthropic-ratelimit-requests-reset`, and tokens-equivalents in response headers. A production-grade Data Bridge should parse these and adapt poll cadence dynamically (back off when remaining is low, resume when reset time passes).

**MVP stance**: ignore these headers. Default 15-30s cadence at 12-agent scale is well within free-tier limits. Revisit post-MVP when real users at scale trigger rate-limiting.

### Validation criteria added

- GUT: `test_4xx_transitions_to_disconnected_immediately()` — mock HTTP 400 response; verify `_failure_counts == 0` (skipped the grace curve); `STATE_DISCONNECTED` emitted on first failure
- GUT: `test_5xx_uses_grace_curve()` — mock HTTP 503; verify CONNECTED → CONNECTED (grace) → STALE → DISCONNECTED transitions across 4 failures
- GUT: `test_request_dispatched_and_settled_fire_in_order()` — mock one request; verify `request_dispatched` precedes `request_settled` precedes `agent_response_received`
- GUT: `test_is_request_in_flight_during_request()` — between `request_dispatched` and `request_settled`, `is_request_in_flight(agent_id) == true`

### Registry updates (when amendment lands)

- `http_4xx_config_fatal_skip_retry` api_decision
- `http_5xx_network_use_backoff_curve` api_decision
- `request_dispatched_settled_signal_pair` api_decision
- `bridge_parses_response_body` forbidden_pattern reinforcement (ASM parses, never bridge)
