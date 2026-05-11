# ADR-0006: Signal-Based Decoupling Pattern

## Status
Accepted (2026-05-11)

## Date
2026-05-11

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.2 |
| **Domain** | Core / Scripting |
| **Knowledge Risk** | LOW — Godot signal system stable since 4.0; typed signals introduced in 4.0 |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/deprecated-apis.md` |
| **Post-Cutoff APIs Used** | None — `signal.connect(callable)` syntax and typed signals were established in Godot 4.0 |
| **Verification Required** | VERIFY: `CONNECT_ONE_SHOT` flag behavior in 4.6.2 — confirm one-shot signals auto-disconnect before the callable fires (not after). VERIFY: Godot 4.6.2 auto-cleans dead signal connections when source Node is freed — do NOT call disconnect() on already-freed nodes. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0003 (Autoload Scene Composition) — establishes which two modules are Autoloads (Tier 3 callers); this ADR governs all non-Autoload cross-module communication |
| **Enables** | ADR-001 (Data Bridge Transport — uses signals for agent state change events), ADR-005 (task_completed Signal Source), ADR-008 (Mock Mode Strategy — uses signals to swap the polling driver), ADR-010 (Tween Lifecycle Management — Tween completion is a signal event), and all remaining system-specific ADRs |
| **Blocks** | No implementation code may define cross-module communication without a pattern established here |
| **Ordering Note** | Write before any system-specific ADRs that define signal signatures, so those ADRs have this pattern to reference. ADR-0003 must be written first (Tier 3 depends on its Autoload list). |

## Context

### Problem Statement

This project has 10 interacting systems (ConfigLoader, AudioManager, DataBridge, RoomSystem, ASM, ACC×N, AAL, TCB, HUD). Without an explicit coupling rule, each ADR will independently invent a communication pattern. The resulting inconsistency creates hidden dependencies, untestable components, and brittle initialization order bugs.

There are three fundamentally different communication needs in this project:

1. **Event notification** ("something happened that other systems might care about") — decoupled by nature
2. **Synchronous query** ("I need a value right now from this specific system") — necessarily coupled, but can be bounded
3. **Global service access** ("I need the application-wide ConfigLoader or AudioManager") — legitimately singleton

Each need has a different correct tool. This ADR assigns the tool to the need and bans the wrong tools.

### Constraints

- Godot 4.x deprecated string-based `connect("signal_name", target, "method_name")` — it must not be used
- GUT unit tests must be able to instantiate individual systems without spinning up the full scene tree
- The bootstrap script (ADR-0003) injects dependencies after `add_child()` — no system may reach for its dependencies in `_ready()`
- Phase 2 systems must not hold strong references to other Phase 2 systems (creates GC pressure and tangled lifetimes)
- ConfigLoader and AudioManager are the only legitimate globals — all other cross-system access must be explicit

### Requirements

- One pattern per communication category: events, queries, global services
- Pattern must be testable — systems using it must be instantiatable in isolation
- Pattern must be typed — no `Variant` signal parameters in public interfaces
- Pattern must be safe across frame boundaries — no dangling references to freed nodes
- Pattern must be documented with code examples developers can copy

## Decision

### Three-Tier Communication Model

All cross-module communication in this project falls into exactly three tiers:

---

#### Tier 1 — Signals (Event Notifications)

**Use when**: one module needs to notify others that something happened.

**Rule**: ALL cross-module event notifications MUST use Godot typed signals. No other mechanism is permitted for events.

```gdscript
# ✅ CORRECT — typed signal declaration
signal agent_state_changed(agent_id: String, new_state: String, previous_state: String)
signal task_completed(agent_id: String)
signal config_loaded()
signal setting_changed(key: StringName, value: Variant)

# ✅ CORRECT — connect with callable syntax (Godot 4.x)
data_bridge.agent_state_changed.connect(_on_agent_state_changed)

# ✅ CORRECT — disconnect in _exit_tree() only when the subscriber is shorter-lived
func _exit_tree() -> void:
    if data_bridge and is_instance_valid(data_bridge):
        data_bridge.agent_state_changed.disconnect(_on_agent_state_changed)

# ✅ CORRECT — one-shot connection (auto-disconnects after first emission)
some_system.some_signal.connect(_on_one_shot_handler, CONNECT_ONE_SHOT)

# ✅ CORRECT — bind extra arguments with Callable.bind()
data_bridge.agent_state_changed.connect(_on_state_changed.bind(extra_context))

# ❌ BANNED — string-based connect (deprecated, untestable)
data_bridge.connect("agent_state_changed", self, "_on_agent_state_changed")

# ❌ BANNED — polling in _process() instead of reacting to a signal
func _process(delta: float) -> void:
    if data_bridge.get_agent_state(id) != _last_state:   # BANNED — use signal
        _on_state_changed()
```

**Signal naming**: snake_case past tense noun phrases describing what happened.
- ✅ `agent_state_changed`, `task_completed`, `config_loaded`, `room_entered`
- ❌ `on_state_change`, `stateUpdate`, `notifyTaskDone`

**Signal parameter typing**: All parameters must be typed. `Variant` is permitted only for the `setting_changed` signal (where the value is genuinely polymorphic by design) and must be documented explicitly.

**Disconnect rule**: Do NOT disconnect from signals in `_exit_tree()` when the source module outlives the subscriber — Godot 4.x automatically cleans up dead connections when a Node is freed. Only call `disconnect()` when the subscriber outlives the source (e.g., a long-lived HUD disconnecting from a short-lived room-scoped system before that system is freed).

**DO NOT call `disconnect()` on already-freed nodes** — check `is_instance_valid()` first if lifetime is uncertain.

---

#### Tier 2 — Direct Method Calls (Synchronous Queries)

**Use when**: a module needs a value from another module RIGHT NOW and cannot wait for a signal.

**Rule**: Synchronous queries are permitted ONLY via injected module references. The module must be injected by the bootstrap script — never fetched via `get_node()` or scene-tree discovery.

```gdscript
# ✅ CORRECT — reference injected by bootstrap
var _data_bridge: DataBridge  # type annotation required

func inject_data_bridge(bridge: DataBridge) -> void:
    _data_bridge = bridge

func _on_some_event() -> void:
    var agents := _data_bridge.get_connected_agents()   # synchronous query

# ✅ CORRECT — return a copy, not the internal collection
# (in DataBridge — prevents callers from mutating internal state)
func get_connected_agents() -> Array[String]:
    return _connected_agents.duplicate()   # MUST duplicate, never return the ref

# ❌ BANNED — scene-tree discovery (untestable, order-dependent)
var bridge := get_node("/root/MainScene/DataBridge")

# ❌ BANNED — cross-system state write via direct reference
func _on_event() -> void:
    _agent_state_machine._current_state = "IDLE"   # BANNED — only owner writes state

# ❌ BANNED — returning internal mutable reference
func get_agent_list() -> Array:
    return _agents   # BANNED — caller can mutate internal state
```

**Injection pattern**: The bootstrap script (`res://src/main/main_bootstrap.gd`) creates all Phase 2 systems and calls their `inject_*()` methods after all systems have been added to the scene tree. Systems must not access injected references during `_ready()` — they arrive after `_ready()` completes.

---

#### Tier 3 — Autoload Singleton Calls (Global Services)

**Use when**: accessing ConfigLoader or AudioManager from any module.

**Rule**: ONLY ConfigLoader and AudioManager may be accessed by singleton name. All other cross-module access uses Tier 1 or Tier 2.

```gdscript
# ✅ CORRECT — Autoload singleton access (only these two are permitted)
var agents := ConfigLoader.get_agents()
var interval := ConfigLoader.get_poll_interval()
AudioManager.play_sfx(my_stream)
AudioManager.play_music(my_track)

# ❌ BANNED — any other system accessed by singleton name
var hud := HUD.instance           # BANNED — HUD is not an Autoload
var bridge := DataBridge.instance  # BANNED — DataBridge is not an Autoload
```

This rule derives from ADR-0003 (Autoload Scene Composition). Adding any new Autoload singleton requires a new ADR superseding ADR-0003.

---

### Communication Pattern Routing Table

Use this table to decide which tier applies:

| Communication Need | Tier | Mechanism |
|---|---|---|
| "X just happened — tell anyone who cares" | **1 — Signal** | `emit_signal` / `signal.emit()` |
| "I need to know X's current value right now" | **2 — Method call** | injected reference + typed method |
| "I need to tell X to change its state" | **1 — Signal** | signal → X handles the change internally |
| "I need config data" | **3 — Autoload** | `ConfigLoader.*` |
| "I need to play audio" | **3 — Autoload** | `AudioManager.*` |
| "Two systems need the same derived value" | **2 — Method call** | owner system exposes read-only property |

**State-change operations always go through Tier 1**: if System A needs to cause a change in System B's state, it emits a signal; System B listens and mutates its own state. System A never writes to System B's internal state directly (see `direct_cross_system_state_write` in forbidden patterns).

### Architecture Diagram

```
Module A                    Module B
  │                           │
  ├──[Tier 1]──────────────── signal agent_state_changed
  │                           │ └─► B._on_agent_state_changed()
  │                           │       └─► B mutates own state
  │                           │
  ├──[Tier 2]── ref injected by bootstrap ──► A._bridge = bridge
  │             A calls bridge.get_agents()    B.get_agents() returns copy
  │
  │                     Bootstrap
  │                         │
  │                         ├─ ConfigLoader  (Autoload #1)
  │                         └─ AudioManager  (Autoload #2)
  └──[Tier 3]── ConfigLoader.get_agents()
                AudioManager.play_sfx()
```

### Key Interfaces

Every cross-module signal in this project is defined in a `signals.gd` annotation comment block at the top of the owning module's script. Signals are never declared in separate files — they belong to the emitting module.

**Pattern for declaring and documenting a signal:**

```gdscript
## Emitted when an agent's connection state changes.
## Consumers: AgentStateMachine, CommandersRoomHUD
signal agent_state_changed(agent_id: String, new_state: String, previous_state: String)
```

**Pattern for the injection method (Tier 2):**

```gdscript
## Called by the main bootstrap after all modules are added to the scene tree.
## Must be called before this module processes any events.
func inject_data_bridge(bridge: DataBridge) -> void:
    assert(bridge != null, "DataBridge reference must not be null")
    _data_bridge = bridge
```

## Alternatives Considered

### Alternative B: Event Bus (Global Signal Hub)

- **Description**: A single `EventBus` Autoload that all systems emit to and subscribe from. Systems never reference each other — only the bus.
- **Pros**: True decoupling; no injected references; bus is globally accessible; easy to add observers.
- **Cons**: Bus becomes a dumping ground; signal names must be globally unique strings; no type safety at the bus boundary (Godot's bus pattern uses `Variant` parameters); bus itself is an additional Autoload.
- **Rejection Reason**: Godot's native typed signals already provide decoupling without string-name collisions. Adding a bus Autoload violates the two-Autoload limit (ADR-0003). The bus pattern is powerful for large projects (50+ systems); for 10 systems, injected refs + native signals are cleaner.

### Alternative C: All Direct References (No Signals)

- **Description**: Every system holds direct references to every system it communicates with. Method calls everywhere, no signals.
- **Pros**: Synchronous, predictable, debuggable.
- **Cons**: Creates O(N²) coupling; every system must be started in exactly the right order; unit testing one system requires mocking all its dependencies; no decoupling for one-to-many notifications.
- **Rejection Reason**: HUD subscribes to ASM, TCB, RoomSystem, and DataBridge simultaneously. With direct refs, any of those four systems being absent causes null reference crashes. Signals allow HUD to receive events without knowing how many sources exist.

### Alternative D: Observable/Reactive Pattern (Signals + State Streams)

- **Description**: Systems expose observable properties that automatically notify subscribers on change. Similar to ReactiveX or GDScript's built-in property setter trick.
- **Pros**: Eliminates explicit signal emission; values and notifications are unified.
- **Cons**: Requires custom infrastructure; `_set()` overrides add overhead; not idiomatic GDScript; difficult to test.
- **Rejection Reason**: Adds framework overhead for no gain over typed signals. GDScript's signal system already handles the notification pattern idiomatically.

## Consequences

### Positive

- Systems are independently testable — inject mock dependencies, observe emitted signals.
- Signal graph is explicit and discoverable — read the `signal` declarations at the top of any module to see what it emits.
- Initialization order bugs are prevented — systems don't reach for each other during `_ready()`; all wiring happens in the bootstrap after all systems are ready.
- Adding a new observer to any event requires zero changes to the emitting module.
- Godot's typed signal system provides compile-time parameter checking in the editor.

### Negative

- Tier 2 injection means every system that depends on another must have an `inject_*()` method and a typed reference field — small boilerplate cost.
- Bootstrap script grows as each new system is added — this is intentional (explicit wiring in one place).
- Debugging an event chain requires following signals across module boundaries — the Godot debugger's signal panel helps.

### Risks

- **Uninjected reference crash**: If a system calls a Tier 2 method before the bootstrap injects the reference, a null reference crash results. Mitigation: `inject_*()` methods assert non-null; all Phase 2 systems check `assert(_injected_ref != null)` at first use; bootstrap always injects before the first event fires.
- **Signal connection order bug**: If a subscriber connects AFTER the source emits its one-time signal (e.g., `config_loaded`), the subscriber misses it. Mitigation: `config_loaded` subscribers must either connect before `_ready()` completes OR use `ConfigLoader.get_state() == "READY"` to check synchronously (see ADR-0002).
- **Mutable return regression**: If a Tier 2 method returns its internal collection directly (forgetting `.duplicate()`), callers can silently corrupt the owner's state. Mitigation: code review enforces the `.duplicate()` rule; unit tests verify that modifying a returned collection does NOT affect the owner's internal state.
- **`CONNECT_ONE_SHOT` timing**: In Godot 4.x, `CONNECT_ONE_SHOT` disconnects the callable *before* it fires. This means if the callable emits the same signal (re-entrancy), the one-shot connection is already gone — no infinite loop. Verify this behavior holds in 4.6.2 (VERIFY item).
- **Dead connection on freed source**: If a subscriber calls `disconnect()` on a source that has already been freed, a null method call crash results. Mitigation: always check `is_instance_valid(source)` before disconnecting; prefer letting Godot auto-clean dead connections by NOT calling disconnect on freed sources.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `data-bridge.md` | Agent state changes must propagate to ASM, HUD | Tier 1 signal `agent_state_changed` on DataBridge; ASM and HUD connect in bootstrap |
| `audio-manager.md` | AudioManager must react to `setting_changed` without tight coupling to ConfigLoader internals | Tier 1: ConfigLoader emits `setting_changed`; AudioManager connects in its `_ready()` (both are Autoloads, initialization order guaranteed) |
| `task-completion-beat.md` | TCB must trigger on task completion without polling | Tier 1 signal `task_completed` from ASM; TCB connects via bootstrap injection |
| `commanders-room-hud.md` | HUD must subscribe to multiple systems simultaneously | Tier 1 signals from ASM, TCB, RoomSystem; Tier 2 queries for synchronous HUD sync pass; Tier 3 for ConfigLoader settings |
| `room-system.md` | RoomSystem must notify HUD when rooms become active | Tier 1 signal `room_activated(room_id: String)` on RoomSystem |
| `configuration-loader.md` | `config_loaded` must notify all consumers exactly once | Tier 1 one-shot signal; consumers call `ConfigLoader.get_state()` as synchronous fallback if needed |
| `agent-character-controller.md` | ACC (one per agent) must react to ASM state changes | Tier 1 signal `agent_state_changed` from ASM; each ACC instance connects with `agent_id` filter via `.bind()` |

## Performance Implications

- **CPU**: Signal emission in Godot 4.x is a direct callable dispatch — negligible overhead vs. a method call. No dictionary lookup, no string comparison. At 60fps with ≤12 agents, total signal overhead is unmeasurable.
- **Memory**: Each connected signal stores one `Callable` object (~8 bytes). With ≤12 agents × ≤5 signals each = <1 KB total signal connection overhead.
- **Load Time**: Connection wiring happens in the bootstrap's `_ready()` — one-time, negligible.
- **Network**: None.

## Migration Plan

N/A — establishes pattern before first implementation.

## Validation Criteria

- GUT: `test_signal_type_checking()` — all signal declarations in all modules use typed parameters (grep for `signal.*Variant` and fail if found in non-approved locations)
- GUT: `test_no_string_connect()` — grep source for `.connect("` pattern and fail if any string-based connection is found
- GUT: `test_no_process_polling()` — grep source for `get_agent_state` or similar getter calls inside `_process()` and fail if found
- GUT: `test_tier2_duplicate_return()` — inject a test ASM, call `get_agents()`, mutate the returned array, call `get_agents()` again — result must be unchanged (confirms `.duplicate()` is used)
- GUT: `test_inject_null_assert()` — call a Tier 2 method without injecting first → must trigger assertion failure, not null reference crash
- GUT: `test_signal_subscriber_receives_event()` — emit a signal from source, confirm subscriber callable was called with correct typed arguments
- Manual: Add a new observer to `agent_state_changed` without modifying DataBridge — confirm it receives events

## Related Decisions

- ADR-0003: Autoload Scene Composition — defines which modules are Autoloads (Tier 3 callers); this ADR governs all Tier 1 and Tier 2 communication
- ADR-001: Data Bridge Transport — defines the `agent_state_changed` signal that is the primary event in the system
- ADR-005: task_completed Signal Source — defines which module owns and emits `task_completed`
- ADR-002: Configuration Loading + Persistence — defines `config_loaded` and `setting_changed` signals (the two Autoload signals)
