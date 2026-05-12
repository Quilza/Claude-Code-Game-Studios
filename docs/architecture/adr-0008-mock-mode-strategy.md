# ADR-0008: Mock Mode Strategy

## Status
Accepted (2026-05-12)

## Date
2026-05-11

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.2 |
| **Domain** | Core / FileAccess |
| **Knowledge Risk** | LOW — `FileAccess.open()`, `JSON.parse_string()` stable since Godot 4.0; no changes in 4.4–4.6 |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/deprecated-apis.md` |
| **Post-Cutoff APIs Used** | `FileAccess.store_*` return `bool` (changed 4.4 — but mock mode only READS files, no write calls needed here) |
| **Verification Required** | VERIFY: `FileAccess.open("res://assets/data/mock/[id].json", FileAccess.READ)` returns a valid handle in both editor and exported builds. VERIFY: mock JSON files included in export preset's Resources filter alongside `config.json`. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0002 (Configuration Loading + Persistence) — provides `ConfigLoader.is_mock()` which this ADR consumes; ADR-0006 (Signal-Based Decoupling Pattern) — mock DataBridge emits identical signals to live DataBridge |
| **Enables** | Data Bridge implementation (developer can build and test the full pipeline before any real AI APIs are connected); Agent State Machine GDD (mock data can stand in for prototype answers during initial design); all GUT integration tests that need DataBridge events |
| **Blocks** | No implementation file may use conditional `is_mock()` checks outside of DataBridge |
| **Ordering Note** | ADR-0002 must exist first (is_mock() is defined there). Write before DataBridge implementation begins. |

## Context

### Problem Statement

DataBridge polls real AI agent HTTP endpoints. During development — before real APIs are connected, and for running the full test suite without network access — the team needs a way to drive the rest of the pipeline (ASM → TCB → HUD) with synthetic data that behaves identically to real responses.

Without a defined strategy, each developer will implement mock mode differently (environment variables, `#if DEBUG` guards, hardcoded test data), producing inconsistent behavior and conditional code scattered across the codebase. The GDD (`data-bridge.md` Rule 7) specifies the mock mechanism; this ADR formalizes it architecturally.

**Scope clarification (GDD sync)**: `data-bridge.md` Rule 7 states "each agent in config may include `mock: true`" — implying per-agent granularity. This ADR constrains the MVP implementation to **project-wide mock mode only**: `config.json`'s top-level `"mock": true` field controls all agents simultaneously. Per-agent mock (some agents live, some mock) is deferred post-MVP. The GDD's language will be updated to reflect this.

### Constraints

- **No conditional code in consumers**: ASM, TCB, HUD, RoomSystem must not check `is_mock()`. Only DataBridge is mock-aware.
- **Identical signal interface**: mock DataBridge emits `agent_response_received`, `agent_connection_changed`, `agent_poll_failed` with identical signatures and semantics to live DataBridge. The ASM cannot distinguish mock from live.
- **No wasted HTTPRequest nodes in mock mode**: if is_mock() is true, DataBridge must not instantiate HTTPRequest nodes (up to 12 nodes × potential thread overhead from unused allocations).
- **Global scope for MVP**: is_mock() is a project-wide boolean — either all agents are mocked or none are.
- **Development artifact**: mock files live at `res://assets/data/mock/[agent_id].json` and are baked into the project. They are included in development exports but should be excluded from production/distribution exports.

### Requirements

- DataBridge checks is_mock() exactly once (at `_ready()`) and branches into either HTTP mode or mock mode for all agents
- Mock polling respects the same `poll_interval_sec` as HTTP polling
- Mock data cycles through a JSON array file, wrapping back to index 0 after the last entry
- A mock response with `http_status: 0` simulates a network timeout (DataBridge treats it as a poll failure)
- Missing mock file → treat identically to a poll failure (emit `agent_poll_failed`)
- Mock mode is invisible to all consumers — same signals, same semantics

## Decision

### Core Mechanism: Internal Flag at `_ready()`

DataBridge checks `ConfigLoader.is_mock()` **once** during `_ready()` and stores the result:

```gdscript
# In res://src/core/data_bridge.gd

var _is_mock: bool = false
var _mock_indices: Dictionary = {}  # agent_id -> current array index

func _ready() -> void:
    _is_mock = ConfigLoader.is_mock()
    var agents := ConfigLoader.get_agents()

    for agent in agents:
        var agent_id: String = agent["id"]
        if _is_mock:
            _mock_indices[agent_id] = 0
            _start_mock_polling_coroutine(agent_id)
        else:
            var request_node := HTTPRequest.new()
            add_child(request_node)
            _http_nodes[agent_id] = request_node
            _start_http_polling_coroutine(agent_id, request_node)
```

**After `_ready()`, no further `is_mock()` calls are made.** The branch is resolved once at initialization. Both paths emit identical signals — `agent_response_received`, `agent_connection_changed`, `agent_poll_failed` — with the same type signatures.

**In mock mode, zero HTTPRequest nodes are created.** Mock polling is pure file I/O on the coroutine schedule.

### Mock File Format and Location

```
assets/data/mock/
└── [agent_id].json          # One file per agent defined in config.json
```

The filename is the `id` field from the agent's config dictionary — the same string returned by `ConfigLoader.get_agents()[i]["id"]`.

**File format**: a JSON array of response objects. Each object is treated as one synthetic poll response. The array is cycled sequentially; index wraps to 0 after the last entry.

```json
[
  {"status": "working", "task": "writing tests", "progress": 0.3},
  {"status": "working", "task": "writing tests", "progress": 0.7},
  {"status": "completed", "task": "writing tests"},
  {"status": "idle"},
  {"status": "working", "task": "code review"}
]
```

**`http_status` field**: mock responses may include an optional `"http_status"` integer. If absent, DataBridge treats the entry as HTTP 200. If `"http_status": 0`, DataBridge treats it as a timeout (poll failure, same backoff behavior as a real network timeout).

```json
[
  {"status": "working"},
  {"http_status": 0},              // simulates a timeout — triggers backoff
  {"status": "connected"},
  {"status": "idle"}
]
```

### Mock Polling Coroutine

```gdscript
func _start_mock_polling_coroutine(agent_id: String) -> void:
    _agent_states[agent_id] = "UNINITIALIZED"
    _emit_connection_changed(agent_id, "CONNECTING")

    while true:
        await get_tree().create_timer(ConfigLoader.get_poll_interval()).timeout

        var mock_data := _read_mock_file(agent_id)
        if mock_data.is_empty():
            # File missing or malformed — treat as poll failure
            _handle_poll_failure(agent_id, -1, 0, "Mock file missing or invalid")
            continue

        var entry: Dictionary = mock_data[_mock_indices[agent_id]]
        _mock_indices[agent_id] = (_mock_indices[agent_id] + 1) % mock_data.size()

        var http_status: int = entry.get("http_status", 200)
        if http_status == 0:
            _handle_poll_failure(agent_id, ERR_CANT_CONNECT, 0, "Mock timeout")
        else:
            var payload := JSON.stringify(entry)
            agent_response_received.emit(agent_id, http_status, payload)
            _handle_poll_success(agent_id)


func _read_mock_file(agent_id: String) -> Array:
    var path := "res://assets/data/mock/%s.json" % agent_id
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_warning("DataBridge (mock): no mock file at %s" % path)
        return []
    var content := file.get_as_text()
    var parsed := JSON.parse_string(content)
    if not parsed is Array:
        push_warning("DataBridge (mock): %s is not a JSON array" % path)
        return []
    return parsed
```

**Timing**: `create_timer(poll_interval)` is identical between mock and HTTP modes. Mock polling fires on the same cadence — the ASM sees the same timing characteristics regardless of mode.

### Config.json Schema (recap from ADR-0002)

```json
{
  "mock": true,
  "agents": [
    { "id": "agent-claude", "endpoint_url": "", "auth_token": "" },
    { "id": "agent-cursor", "endpoint_url": "", "auth_token": "" }
  ]
}
```

When `"mock": true`, `endpoint_url` and `auth_token` values are ignored — DataBridge reads from mock files instead. They may be left empty or omitted in mock configs.

### Architecture Diagram

```
config.json: { "mock": true }
        │
        ▼
ConfigLoader._ready() reads file → ConfigLoader.is_mock() returns true
        │
        ▼
DataBridge._ready() → _is_mock = ConfigLoader.is_mock()
        │
        ├─ _is_mock == false ──► HTTPRequest nodes × N
        │                             │
        │                             └─► HTTP polling coroutines
        │                                       │
        └─ _is_mock == true ───► NO HTTPRequest nodes
                                      │
                                      └─► Mock polling coroutines
                                                │
                                                └─► _read_mock_file(agent_id)
                                                    cycling JSON array

Both paths emit:
  agent_response_received(agent_id, http_status, raw_payload)  ─►  AgentStateMachine
  agent_connection_changed(agent_id, connection_state)          ─►  CommandersRoomHUD
  agent_poll_failed(agent_id, error_code, ...)                  ─►  AgentStateMachine
```

### Post-MVP: Per-Agent Mock (deferred)

After MVP, individual agents may be mocked while others connect live. The mechanism would read a `"mock"` field from each agent's dictionary in the config array:

```json
{
  "agents": [
    { "id": "agent-claude", "endpoint_url": "https://...", "mock": false },
    { "id": "agent-cursor", "endpoint_url": "", "mock": true }
  ]
}
```

This requires updating `ConfigLoader.get_agents()` to preserve per-agent `mock` fields and updating DataBridge to branch per-agent rather than globally. A new ADR superseding ADR-0008 is required before this is implemented.

## Alternatives Considered

### Alternative B: Strategy Pattern (`IPollingDriver` interface)

- **Description**: DataBridge holds a `_driver: PollingDriver` reference. Two implementations: `HttpPollingDriver` and `MockPollingDriver`. Bootstrap passes the correct driver to DataBridge based on `is_mock()`.
- **Pros**: Clean separation; DataBridge doesn't know about mock mode at all.
- **Cons**: Adds two new classes and an interface for a behavior that's controlled by a single boolean flag checked once. Over-engineered for MVP with 2 polling modes and 12 max agents.
- **Rejection Reason**: The internal flag approach achieves the same outcome (consumers see identical signals) with significantly less code and one fewer concept. The strategy pattern becomes appropriate if a third driver (e.g., WebSocket) is added — that decision can supersede this ADR when needed.

### Alternative C: Separate `MockDataBridge` class

- **Description**: The bootstrap instantiates `MockDataBridge` (or `DataBridge`) based on `is_mock()`. Both classes emit the same signals. Bootstrap wires whichever is instantiated.
- **Pros**: True separation — live and mock code are completely isolated.
- **Cons**: Two classes to maintain with duplicated signal declarations, bootstrap complexity, and `MockDataBridge` needs to live in `src/` rather than `tests/` (it's used in production mock mode, not just tests). Adds cognitive overhead.
- **Rejection Reason**: The internal flag approach is simpler and keeps mock logic co-located with the HTTP logic it mirrors. The "mock is just test code" mental model doesn't hold here — mock mode is a legitimate developer workflow feature, not a test artifact.

### Alternative D: Environment variable / `#if` guards

- **Description**: Mock mode controlled by an environment variable or compile-time constant.
- **Pros**: No config.json changes needed.
- **Cons**: Non-portable across platforms; Godot 4 doesn't support compile-time conditional compilation in GDScript; environment variables are harder to configure reproducibly.
- **Rejection Reason**: `config.json`'s `"mock"` field provides a user-readable, version-controllable, platform-independent mock toggle. Developers can commit `"mock": true` config files for specific development scenarios.

## Consequences

### Positive

- The full pipeline (DataBridge → ASM → TCB → HUD) can be tested without any AI API credentials or network access.
- Mock data files are version-controlled — a `config.json` + mock data directory can represent a specific "scenario" (e.g., agent under heavy load, agent completing multiple tasks in sequence).
- Zero conditional code in consumers — the architectural boundary is clean and testable.
- HTTPRequest nodes are not created in mock mode — no wasted resources during development.

### Negative

- Mock files must be kept in sync with whatever the real API returns. If the API response shape changes, mock files need updating too.
- Mock polling timing is slightly less realistic than HTTP timing (no actual network latency). For testing completion detection, this is fine; for timing-sensitive behavior, a configurable delay could be added post-MVP.
- `res://assets/data/mock/` must be excluded from production (distribution) export presets manually — same class of issue as `addons/gut/`.

### Risks

- **Mock file missing at runtime**: if `config.json` has `"mock": true` but the mock file for an agent doesn't exist, DataBridge emits `agent_poll_failed` — the agent shows as disconnected. This is correct behavior, but confusing if the developer forgets to create the mock file. Mitigation: DataBridge startup validation should check for mock file existence when `is_mock()` is true and log a clear startup warning per missing file.
- **JSON array parse failure**: malformed JSON in a mock file returns an empty array, treating the next poll as a failure. Mitigation: `push_warning()` with the file path; developer sees the issue immediately.
- **Cycle index drift on hot reload**: if Godot hot-reloads a script mid-session, the `_mock_indices` dictionary is reset. Mock files will start cycling from index 0 again. Acceptable for a developer tool — hot reloads are explicit actions.
- **Mock files included in production export**: if the developer forgets to exclude `assets/data/mock/` from the export preset, mock JSON files ship with the production build. No security risk (they're synthetic status data), but wastes bytes. Mitigation: document in the export preset setup guide.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `data-bridge.md` (Rule 7) | "Mock mode replaces HTTP with synthetic cycling data" | Internal flag at `_ready()` selects the mock polling coroutine; cycling JSON array provides the synthetic data |
| `data-bridge.md` (Rule 7) | "The emitted event is structurally identical to a real response — the Agent State Machine cannot distinguish mock from live" | Mock coroutine emits `agent_response_received` with the same signature; ASM receives the same types |
| `data-bridge.md` (Rule 7) | "A mock response with `http_status: 0` simulates a timeout" | `entry.get("http_status", 200) == 0` → `_handle_poll_failure()` with `ERR_CANT_CONNECT` |
| `configuration-loader.md` | `is_mock()` reads the top-level `"mock"` field from config.json | ADR-0002 established this; this ADR formalizes that DataBridge is the sole consumer of `is_mock()` |

**GDD sync required**: `data-bridge.md` Rule 7 says "each agent in config may include `mock: true`" — this describes per-agent granularity that is deferred post-MVP. The GDD should be updated to clarify: MVP uses global `is_mock()` only; per-agent `mock` fields in individual agent dicts are post-MVP.

## Performance Implications

- **CPU**: Mock polling uses `create_timer()` (same as HTTP mode) + `FileAccess.open()` + `JSON.parse_string()` per poll per agent. At 5s poll interval × 12 agents = at most 12 file reads per 5 seconds. Each read is <1ms. Negligible.
- **Memory**: Mock cycling indices: one int per agent × 12 agents max = <100 bytes. Mock file content parsed per poll (not cached) to allow hot-editing of mock files during development.
- **Load Time**: No impact — mock mode init is identical speed to HTTP mode init (one `is_mock()` call, then coroutine setup).
- **Network**: Zero. Mock mode makes no HTTP connections whatsoever.

## Migration Plan

N/A — establishes from scratch before DataBridge is implemented.

## Validation Criteria

- GUT: `test_mock_mode_emits_no_http_requests()` — set is_mock() true, instantiate DataBridge, confirm no HTTPRequest nodes added to scene tree
- GUT: `test_mock_cycles_array_sequentially()` — provide a 3-entry mock file, poll 5 times, confirm response order matches entries in order (wrapping after entry 3)
- GUT: `test_mock_http_status_zero_triggers_failure()` — include `{"http_status": 0}` in mock array, confirm `agent_poll_failed` is emitted on that entry
- GUT: `test_mock_missing_file_emits_poll_failed()` — set is_mock() true for an agent with no mock file, confirm `agent_poll_failed` is emitted
- GUT: `test_live_mode_creates_http_nodes()` — set is_mock() false, confirm HTTPRequest nodes are added to DataBridge
- Manual: run with `"mock": true` in config, observe all agents cycling through their mock state sequences in the running application

## Related Decisions

- ADR-0002: Configuration Loading + Persistence — defines `is_mock()` and the `"mock"` field in config.json schema
- ADR-0006: Signal-Based Decoupling Pattern — both polling paths emit identical Tier 1 signals; consumers are unaffected by which path is active
- ADR-001: Data Bridge Transport — defines the HTTP polling implementation that mock mode replaces; the two ADRs are complementary halves of the DataBridge implementation
