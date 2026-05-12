# The Situation Room — Master Architecture

## Document Status

- **Version**: 1.0
- **Last Updated**: 2026-05-11
- **Engine**: Godot 4.6.2 / GDScript / 2D CanvasItem
- **GDDs Covered**: configuration-loader, audio-manager, tilemap-renderer, data-bridge, room-system, agent-character-controller, ambient-animation-layer, task-completion-beat, commanders-room-hud (Agent State Machine BLOCKED until Data Bridge prototype)
- **ADRs Referenced**: 14 required (9 must-have, 5 should-have, 1 blocked) — see Required ADRs section
- **Technical Director Sign-Off**: 2026-05-11 — **APPROVED WITH CONDITIONS** (see TD assessment below)
- **Lead Programmer Feasibility**: SKIPPED — Lean mode

### TD-ARCHITECTURE Self-Review (2026-05-11)

Per gate TD-ARCHITECTURE in `.claude/docs/director-gates.md`:

1. **Is every technical requirement from the baseline covered by an architectural decision?** Yes — all ~70 TRs across 10 GDDs are mapped to a required ADR. Coverage is currently 0/70 in *Accepted* ADRs (none written), but the ADR plan covers every TR.
2. **Are all HIGH risk engine domains explicitly addressed or flagged as open questions?** Yes — HTTPRequest (ADR-001 + #4), Tween cleanup (ADR-010 + VERIFY #9), Web export (ADR-004 + VERIFY #4), BitmapFont (ADR-012 + VERIFY #2 #5), CanvasLayer (ADR-011) are all explicit. AnimationPlayer (MEDIUM) is in ADR-009. TileMapLayer Y-sort (MEDIUM) and stretch mode (MEDIUM) are in ADR-013.
3. **Are the API boundaries clean, minimal, and implementable?** Yes — each module's public surface is ≤6 methods + ≤2 signals. No method takes more than 2 parameters. All return types are concrete. Pseudocode compiles mentally.
4. **Are Foundation layer ADR gaps resolved before implementation begins?** No — and this is the condition. **No code may be written until ADR-002, ADR-003, ADR-006, ADR-014 (and ideally ADR-001, ADR-004, ADR-008, ADR-010) are written and Accepted.**

**Verdict**: APPROVED WITH CONDITIONS — the architecture is sound, but it is a *plan*, not yet a foundation. The Required ADRs (Phase 6) must be written and accepted before code begins. Recommend authoring ADR-002, ADR-003, ADR-006 first (low-risk, fast) to validate the workflow, then tackling ADR-001 + ADR-004 alongside the Data Bridge prototype.

---

## Engine Knowledge Gap Summary

LLM training data covers Godot ~4.3. Engine pinned at **4.6.2** (Apr 2026). Versions 4.4, 4.5, 4.6 are post-cutoff.

### HIGH RISK domains for this project
- **Networking — HTTPRequest** (Data Bridge depends on it). 4.4 changed some core return types. Signal signature and `timeout` cancellation behavior unverified.
- **Web export HTML5 / CORS** (target platform). 4.6 export options unverified.
- **2D — Tween cleanup on freed Node2D** (used by TCB room modulate and HUD overlay fade).
- **UI — BitmapFont + FontFile** (HUD uses 5×7 bitmap font). Class status in 4.6 unverified.

### MEDIUM RISK domains
- **TileMapLayer** (was TileMap pre-4.3). Y-sort behavior in 4.6.2 unverified.
- **AnimationMixer.active property** (moved to base class in 4.3) — used by ACC + AAL.
- **Project Settings — `keep_integer` stretch mode** path in 4.6.2 unverified.

### LOW RISK domains
- Audio (AudioServer, AudioStreamPlayer, bus topology) — stable since 4.0.
- Input (Input singleton, InputEvent) — stable.
- 2D physics — N/A (no physics in this project).
- JSON parsing (`JSON.parse_string`) — stable.

### Systems in HIGH/MEDIUM risk engine domains

| System | Risk | Domain |
|--------|------|--------|
| Data Bridge | HIGH | HTTPRequest, Web export CORS |
| Task Completion Beat | HIGH | Tween cleanup on freed nodes |
| Commander's Room HUD | HIGH | CanvasLayer, BitmapFont, Tween, web responsiveness |
| TileMap Renderer | MEDIUM | TileMapLayer Y-sort, stretch mode |
| Agent Character Controller | MEDIUM | AnimationPlayer / AnimationMixer |
| Ambient Animation Layer | MEDIUM | AnimationPlayer + Tween |

These risks are inherited as Open Questions and feed directly into the Required ADRs list. All must be addressed (verified or accepted with mitigation) before implementation begins.

---

## System Layer Map

```
┌────────────────────────────────────────────────────────────────────┐
│  PRESENTATION LAYER                                                │
│  ─ Commander's Room HUD (CanvasLayer panel + detail overlay)      │
│  ─ History/Activity Log [Alpha — deferred]                         │
├────────────────────────────────────────────────────────────────────┤
│  FEEDBACK LAYER (event-driven visual + audio response)             │
│  ─ Task Completion Beat (TCB)                                      │
│  ─ Alert State System [Vertical Slice — deferred]                  │
├────────────────────────────────────────────────────────────────────┤
│  FEATURE LAYER (per-agent / per-room behaviour)                    │
│  ─ Agent Character Controller (ACC)                                │
│  ─ Ambient Animation Layer (AAL)                                   │
│  ─ Commander Character [Vertical Slice — deferred]                 │
│  ─ Camera/Viewport System [Vertical Slice — deferred]              │
├────────────────────────────────────────────────────────────────────┤
│  CORE LAYER (data ingest + canonical state)                        │
│  ─ Data Bridge                                                     │
│  ─ Agent State Machine (ASM)  [BLOCKED until prototype]            │
│  ─ Room System                                                     │
├────────────────────────────────────────────────────────────────────┤
│  FOUNDATION LAYER (autoloaded singletons; project-wide services)   │
│  ─ Configuration Loader (Autoload)                                 │
│  ─ Audio Manager (Autoload)                                        │
│  ─ TileMap Renderer (helper / scene node — NOT autoload)           │
│  ─ State Persistence [Alpha — deferred]                            │
├────────────────────────────────────────────────────────────────────┤
│  PLATFORM LAYER (engine / OS surface — not our code)               │
│  ─ Godot 4.6.2 (CanvasItem, TileMapLayer, AudioServer, Tween)     │
│  ─ HTTPRequest (HTTP polling)                                      │
│  ─ FileAccess (config + settings)                                  │
│  ─ Web export runtime (HTML5 / JS interop)                         │
└────────────────────────────────────────────────────────────────────┘
```

### Layer Assignment Rationale

| System | Layer | Owns | Why this layer |
|--------|-------|------|----------------|
| Configuration Loader | Foundation | `config.json` schema, `agents[]` array, `mock` flag | Autoload — must boot before anything needing `agents[]`. Project-wide service. |
| Audio Manager | Foundation | Bus topology (Master → Music + SFX), 8-node pool, stream-agnostic `play_sfx(stream)` dispatch | Autoload — wraps AudioServer; called by TCB, settings, future alerts. |
| TileMap Renderer | Foundation | TileMapLayer wrapper, `cell_size=16`, `module_size=8`, programmatic placement | Helper/utility — NOT autoload. Imported by room scenes. |
| Data Bridge | Core | HTTPRequest instances per agent, polling cadence, raw-string payload buffer, per-agent connection state | Core because it bridges external API → engine. Nothing in Feature layer can reach external state without it. |
| Agent State Machine | Core | Canonical state per agent, state-change events, connection-quality flags, agent stats dictionary | Core because the rest of the project models state through ASM's vocabulary. |
| Room System | Core | Room registry, agent↔room mapping, `commanders_room_id`, room geometry, **computer prop emits `computer_interacted` signal** | Core because both Feature (ACC, AAL) and Presentation (HUD) consume room data. |
| Agent Character Controller | Feature | Per-agent CharacterBody2D, AnimationPlayer state per ASM state, navigation between desks | Feature — depends on Core (ASM + Room System) and Foundation (TileMap Renderer). |
| Ambient Animation Layer | Feature | Background ambient animations, room ambient state, layered with ACC | Feature — room-context-aware. |
| Task Completion Beat | Feedback | `AgentSoundRegistry`, room modulate Tween orchestration, `beat_fired(agent_id, timestamp)` signal | Pure reactive responder to a Core event; outputs visual + audio. Dedicated sub-layer keeps the responsibility crisp. |
| Commander's Room HUD | Presentation | Screen-edge CanvasLayer panel, screen-space detail overlay, slot grid state, `tasks_completed` accumulation | Presentation — the only system that draws screen-space. Subscribes to ASM + TCB but emits nothing read by anyone. |

### Notable layer decisions

1. **TCB occupies its own "Feedback" sub-layer.** Not Presentation (does in-world modulate), not Feature (not per-agent). The dedicated layer keeps responsibility crisp.
2. **The Commander's Room computer prop belongs to Room System, not HUD.** The prop is a scene object that emits a signal; HUD listens. This keeps HUD purely Presentation (no in-world ownership).
3. **TileMap Renderer is NOT an autoload.** Only true global services are autoloaded. TileMap Renderer is a helper imported where needed.
4. **Agent State Machine is shown in Core but blocked.** Placement is functional, not dependent on design completion.

---

## Module Ownership

### Foundation Layer

| Module | Owns | Exposes | Consumes | Engine APIs |
|--------|------|---------|----------|-------------|
| **Configuration Loader** | Parsed `config.json`, `agents[]`, `mock` flag, settings dict from `user://settings.json` | `get_config()`, `get_agents()`, `is_mock()`, `get_setting(key)`, `set_setting(key,value)`. Signals: `config_loaded`, `setting_changed` | nothing | `FileAccess` (LOW), `JSON.parse_string` (LOW), `OS.get_executable_path()` (LOW) |
| **Audio Manager** | Bus indices (Master/Music/SFX), 8-node pool, mute states, per-bus volumes | `play_sfx(stream)`, `set_bus_mute()`, `set_bus_volume_db()`, `toggle_global_mute()` | `Configuration Loader.get_setting()` | `AudioServer` (LOW), `AudioStreamPlayer` (LOW), `AudioBusLayout` (LOW) |
| **TileMap Renderer** | TileMapLayer reference, `CELL_SIZE=16`, `MODULE_SIZE=8` | `place_tile()`, `get_cell()`, `world_to_cell()`, `cell_to_world()` | nothing | `TileMapLayer` ⚠ MEDIUM, `Vector2i` (LOW) |

### Core Layer

| Module | Owns | Exposes | Consumes | Engine APIs |
|--------|------|---------|----------|-------------|
| **Data Bridge** | One `HTTPRequest` per agent (≤12), per-agent connection state machine, retry counters, raw String payload buffer | `get_last_payload(agent_id)`, `get_connection_state(agent_id)`. Signals: `agent_response_received(agent_id, raw_string)`, `agent_connection_changed(agent_id, new_state)` | `Configuration Loader.get_agents()`, `is_mock()` | `HTTPRequest` ⚠ HIGH, `Timer` (LOW), `FileAccess` (LOW) |
| **Agent State Machine** *(BLOCKED)* | Canonical state per agent (`idle`/`working`/`completed`/`errored`), state history, field-agnostic stats dict | `get_agent_state(id)`, `get_agent_stats(id)`. Signals: `agent_state_changed(id, new_state, previous_state)`, `task_completed(id)` | `Data Bridge` signals | None — pure state machine |
| **Room System** | Room registry (`Dictionary[StringName, RoomData]`), agent↔room mapping, `commanders_room_id="commander"`, computer prop ref | `get_all_room_ids()`, `get_room(id)`, `get_all_agent_ids()`, `get_agent_room(id)`. Signal: `computer_interacted` (forwarded from `Area2D`) | `Configuration Loader.get_agents()` | `Area2D` (LOW), `CollisionShape2D` (LOW), `Resource` (LOW) |

### Feature Layer

| Module | Owns | Exposes | Consumes | Engine APIs |
|--------|------|---------|----------|-------------|
| **Agent Character Controller** | Per-agent `CharacterBody2D`, `AnimationPlayer`, animation state, nav target | per-agent visible behavior; no signals outward | `ASM.agent_state_changed`, `Room System.get_room()`, `TileMap Renderer.cell_to_world()` | `CharacterBody2D` (LOW), `AnimationPlayer` ⚠ MEDIUM, `Sprite2D` (LOW), `Timer` (LOW) |
| **Ambient Animation Layer** | Per-room ambient nodes, ambient state | nothing | `Room System.get_all_room_ids()`, `ASM.agent_state_changed`, `TileMap Renderer.cell_to_world()` | `AnimationPlayer` ⚠ MEDIUM, `Tween` ⚠ HIGH, `Sprite2D` (LOW) |

### Feedback Layer

| Module | Owns | Exposes | Consumes | Engine APIs |
|--------|------|---------|----------|-------------|
| **Task Completion Beat** | `AgentSoundRegistry` (Dictionary[StringName, AudioStream]), active per-room modulate Tweens, `BEAT_TOTAL_SEC=1.5` | Signal: `beat_fired(agent_id, timestamp)` | `ASM.task_completed`, `Audio Manager.play_sfx()`, `Room System.get_room()`, `Configuration Loader.get_agents()` | `Tween` ⚠ HIGH, `CanvasItem.modulate` (LOW), `AudioStream` (LOW), `Time.get_ticks_msec()` (LOW) |

### Presentation Layer

| Module | Owns | Exposes | Consumes | Engine APIs |
|--------|------|---------|----------|-------------|
| **Commander's Room HUD** | `CanvasLayer` panel, screen-space detail overlay, 3×4 slot grid state, completions strip (cap 6), per-slot timers, `tasks_completed` counters | nothing (terminal subscriber) | `ASM.agent_state_changed`, `ASM.get_agent_stats()`, `TCB.beat_fired`, `Room System.computer_interacted`, `Room System.get_all_agent_ids()`, `Configuration Loader.get_setting()` | `CanvasLayer` ⚠ HIGH, `Control`/`Panel` (LOW), `Label` (LOW), `Timer` (LOW), `Tween` ⚠ HIGH, `BitmapFont`/`FontFile` ⚠ HIGH, `ScrollContainer` (LOW) |

### Cross-cutting Decision: `task_completed` source

**Resolution: ASM emits `task_completed`** (Option A). Keeps Feedback layer dependent on Core, not Feature. ACC observes the visual completion but does not announce it — that's ASM's role as the canonical state owner. This becomes **ADR-005: task_completed Signal Source**.

### Engine API risk consolidated

- **HIGH**: HTTPRequest (Data Bridge), Tween (TCB, AAL, HUD), BitmapFont/FontFile (HUD), CanvasLayer responsiveness on web (HUD)
- **MEDIUM**: TileMapLayer Y-sort (TileMap Renderer), AnimationPlayer/AnimationMixer (ACC, AAL)
- **LOW**: everything else

### Dependency diagram

```
                    ┌────────────────────────────────────┐
                    │     Commander's Room HUD           │ Presentation
                    └────────────────────────────────────┘
                           │           │             │
                           ▼           ▼             ▼
                    ┌──────────┐ ┌──────────┐ ┌────────────┐
                    │   ASM    │ │   TCB    │ │ Room       │   Feedback / Core
                    └──────────┘ └──────────┘ │ System     │
                          │            │      └────────────┘
                          │     ┌──────┘            ▲
                          │     │ (task_completed)  │
                          │     ▼                   │
                          │  emitted by ASM         │
                          │                         │
                          │     ┌─────────────────┐ │
                          │ ──→ │      ACC        │─┤
                          │     └─────────────────┘ │
                          │              ▲          │
                          │     ┌────────┴────────┐ │
                          │ ──→ │      AAL        │─┘
                          │     └─────────────────┘
                          ▼
                    ┌─────────────────┐
                    │   Data Bridge   │ Core
                    └─────────────────┘
                          │
              ┌───────────┴───────────┐
              ▼                       ▼
      ┌──────────────────┐   ┌──────────────────┐
      │  Config Loader   │   │  Audio Manager   │ Foundation (Autoloads)
      └──────────────────┘   └──────────────────┘

  TileMap Renderer: helper used by ACC, AAL, and any room scene
  needing programmatic tile placement.
```

---

## Data Flow

The Situation Room is **event-driven**, not frame-driven. Four flows define the architecture.

### Flow 1 — Initialization Order (Boot Sequence)

Autoloads (in Project Settings order):
1. **Configuration Loader** — reads `config.json` + `user://settings.json`, emits `config_loaded`
2. **Audio Manager** — subscribes to `setting_changed`, sets bus volumes/mutes, builds 8-node pool

Main scene `_ready` (Main Scene Bootstrap):
3. **TileMap Renderer** instantiated where needed
4. **Room System** — reads agents from Configuration Loader; builds room registry; wires computer prop `Area2D.input_event` → `computer_interacted` signal
5. **Data Bridge** — one `HTTPRequest` per configured agent; subscribes signals; starts polling timers; swaps mock driver if `is_mock()`
6. **Agent State Machine** (BLOCKED) — subscribes to Data Bridge signals; initializes each agent's state to `"idle"`
7. **ACC instances** (one per agent) — each subscribes to `ASM.agent_state_changed` filtered to its agent_id
8. **AAL** (one per room) — subscribes to ASM where ambient cares
9. **Task Completion Beat** — subscribes to `ASM.task_completed`; builds `AgentSoundRegistry`
10. **Commander's Room HUD** — subscribes to ASM (state + connection quality), TCB (beat_fired), Room System (computer_interacted); performs sync pass via `ASM.get_agent_state(agent_id)` per agent (per HUD AC-2 / EC-6)

**Strict rule**: Foundation autoloads (1, 2) MUST complete before main scene `_ready`. Within `_ready`, Room System (4) builds the agent list that Data Bridge (5), ACC (7), and HUD (10) consume.

### Flow 2 — Canonical Event Flow: a task completes

```
[external AI agent finishes a task]
   │
   ▼
HTTPRequest.request_completed (Data Bridge poll arrives)
   │
   ▼
Data Bridge.agent_response_received(agent_id, raw_string)
   │
   ▼
ASM ingests payload, observes transition working → completed
   │
   ├─► ASM.agent_state_changed(agent_id, "completed", "working")
   │       ├─► HUD: records last-known state (does NOT change glyph here)
   │       ├─► ACC: plays per-state animation
   │       └─► AAL: room ambient may react
   │
   └─► ASM.task_completed(agent_id)
           ▼
       TCB.on_task_completed:
           ├─► stream = AgentSoundRegistry[agent_type] OR default.ogg
           ├─► Audio Manager.play_sfx(stream)
           ├─► room_node = Room System.get_agent_room(id) → get_room().node
           ├─► Tween room modulate (attack 0.3s → hold 0.5s → decay 0.7s)
           └─► TCB.beat_fired(agent_id, timestamp)
                   ▼
               HUD:
                   ├─► slot glyph = "+" green
                   ├─► start per-slot 1.5s timer
                   ├─► tasks_completed[id] += 1
                   └─► prepend "[HH:MM] [agent_id]" to strip (cap 6)

   (1.5s later)
   ▼
HUD timer expiry:
   ├─► reads ASM.get_agent_state(agent_id)
   ├─► WORKING → ● green | ERRORED → ● Sienna | else → ▬ amber
```

**Decoupling rule**: HUD does NOT change glyph on `agent_state_changed("completed")` — TCB drives the `+` via `beat_fired`. This lets `BEAT_TOTAL_SEC` be tuned independently of how long ASM holds the `"completed"` state.

### Flow 3 — Connection-Quality Degradation

```
HTTPRequest fails (timeout / 5xx / network)
   ▼
Data Bridge increments retry counter
   ├─► 1: CONNECTED (grace)
   ├─► 2: STALE → emit agent_connection_changed(id, "stale")
   ├─► 3: STALE (further)
   └─► 4: DISCONNECTED → emit agent_connection_changed(id, "disconnected")
       (matches max_poll_retries = 4)
   ▼
ASM forwards / republishes (mechanism = HUD OQ-4)
   ▼
HUD applies slot alpha:
   CONNECTED → 1.0 | STALE → 0.5 | DISCONNECTED → 0.25
   (glyph + color unchanged — last-known state preserved)

   (next poll succeeds)
   ▼
Data Bridge resets counter → CONNECTED → emit signal → HUD restores α = 1.0
```

### Flow 4 — Settings Persistence

```
User changes mute / volume / hud_panel_anchor
   ▼
Configuration Loader.set_setting(key, value):
   ├─► update in-memory dict
   ├─► write user://settings.json
   └─► emit setting_changed(key, value)
   ▼
Subscribers react:
   ├─► Audio Manager: re-applies bus volume / mute if audio-related key
   └─► HUD: re-anchors panel if hud_panel_anchor changed
```

**No game state save/load in MVP.** State Persistence (Alpha-tier) is deferred. Mock-mode JSON in `assets/data/mock/[agent_id].json` is read-only.

### Threading Model

**No application-owned threads.** All Data Bridge polling is asynchronous on the engine's main loop via `HTTPRequest` (Godot manages internally). No user-code data flow crosses thread boundaries — eliminates a large class of race conditions; entire signal chain runs serially per frame.

⚠ Engine note: Web export's `HTTPRequest` may behave differently than desktop (CORS, request batching, response timing). This is VERIFY #4 and part of the Data Bridge prototype.

---

## API Boundaries

GDScript pseudocode for each module's public contract. Programmers implement against these. Invariants and guarantees are noted inline.

### Configuration Loader (Autoload)

```gdscript
class_name ConfigurationLoader extends Node

const MAX_AGENTS: int = 12
const POLL_INTERVAL_DEFAULT_SEC: float = 5.0
const MAX_POLL_RETRIES: int = 4

signal config_loaded
signal setting_changed(key: StringName, value: Variant)

func get_config() -> Dictionary
func get_agents() -> Array[Dictionary]
func is_mock() -> bool
func get_setting(key: StringName) -> Variant
func set_setting(key: StringName, value: Variant) -> void
```

**Invariants**: `get_agents()` length ≤ `MAX_AGENTS`. Callers must not mutate returned collections.
**Guarantees**: `config_loaded` fires exactly once. `setting_changed` fires after disk write completes.

### Audio Manager (Autoload)

```gdscript
class_name AudioManager extends Node

const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName  = &"Music"
const BUS_SFX: StringName    = &"SFX"
const POOL_SIZE: int = 8

func play_sfx(stream: AudioStream) -> void
func set_bus_mute(bus_name: StringName, muted: bool) -> void
func set_bus_volume_db(bus_name: StringName, db: float) -> void
func toggle_global_mute() -> void
func is_globally_muted() -> bool
```

**Invariants**: Caller owns `stream`. Audio Manager does not load or cache streams.
**Guarantees**: `play_sfx()` is non-blocking. Pool exhaustion drops the call with `push_warning()`.

### TileMap Renderer

```gdscript
class_name TileMapRenderer extends Node2D

const CELL_SIZE: int = 16
const MODULE_SIZE: int = 8

func place_tile(tile_id: int, cell_coord: Vector2i) -> void
func get_cell(cell_coord: Vector2i) -> Dictionary
func world_to_cell(pos: Vector2) -> Vector2i
func cell_to_world(coord: Vector2i) -> Vector2
```

**Invariants**: Never hardcode 16 — use `CELL_SIZE`. **Guarantees**: `world_to_cell`/`cell_to_world` are inverses up to integer rounding.

### Data Bridge

```gdscript
class_name DataBridge extends Node

const CONNECTION_STATES: Array[StringName] = [
    &"uninitialized", &"connecting", &"connected",
    &"stale", &"disconnected", &"error"
]

signal agent_response_received(agent_id: String, raw_string: String)
signal agent_connection_changed(agent_id: String, new_state: String)

func get_last_payload(agent_id: String) -> String
func get_connection_state(agent_id: String) -> String
```

**Invariants**: `raw_string` is unparsed. Consumers parse content.
**Guarantees**: `agent_response_received` only on success. `agent_connection_changed` only on transition. DISCONNECTED declared at `MAX_POLL_RETRIES = 4`.

### Agent State Machine [PROVISIONAL]

```gdscript
class_name AgentStateMachine extends Node

const STATES: Array[StringName] = [&"idle", &"working", &"completed", &"errored"]

signal agent_state_changed(agent_id: String, new_state: String, previous_state: String)
signal task_completed(agent_id: String)
# Connection-quality mechanism — Open Question HUD OQ-4.
# Recommended: re-emit DataBridge.agent_connection_changed verbatim.

func get_agent_state(agent_id: String) -> String
func get_agent_stats(agent_id: String) -> Dictionary
```

**Invariants**: `new_state` always one of `STATES`. **Guarantees**: `task_completed` fires once per task. **Provisional contract — locked when ASM GDD is written (blocked by Data Bridge prototype).**

### Room System

```gdscript
class_name RoomSystem extends Node

const COMMANDERS_ROOM_ID: StringName = &"commander"

signal computer_interacted

func get_all_room_ids() -> Array[StringName]
func get_room(room_id: StringName) -> RoomData
func get_all_agent_ids() -> Array[String]
func get_agent_room(agent_id: String) -> StringName

class_name RoomData extends Resource
@export var room_id: StringName
@export var bounds: Rect2
@export var agent_ids: Array[StringName]
@export var workstation_tiles: Array[Vector2i]
@export var node: Node2D
```

**Invariants**: Never hardcode `"commander"` — use `COMMANDERS_ROOM_ID`.
**Guarantees**: `computer_interacted` fires only from the Commander's Room prop, only on click.

### Agent Character Controller

```gdscript
class_name AgentCharacterController extends CharacterBody2D

const ERROR_TIMEOUT_SEC: float = 30.0
const STAGGER_BASE_SEC: float  = 0.2
const COMPLETED_BEAT_DURATION_SEC: float = 2.0

@export var agent_id: String
# Pure consumer — no public signals (per ADR-005: ASM emits task_completed)
```

### Ambient Animation Layer

```gdscript
class_name AmbientAnimationLayer extends Node2D

const TRANSITION_SEC: float = 0.3
@export var room_id: StringName
# No public API.
```

### Task Completion Beat

```gdscript
class_name TaskCompletionBeat extends Node

const BEAT_ATTACK_SEC: float = 0.3
const BEAT_HOLD_SEC: float   = 0.5
const BEAT_DECAY_SEC: float  = 0.7
const BEAT_TOTAL_SEC: float  = 1.5
const BEAT_PEAK: Color       = Color(1.15, 1.35, 1.15, 1.0)
const BEAT_NEUTRAL: Color    = Color(1.0, 1.0, 1.0, 1.0)

signal beat_fired(agent_id: String, timestamp: float)

# AgentSoundRegistry built at _ready from assets/audio/sfx/completion/[agent_type].ogg
# (default.ogg is mandatory fallback)
```

**Invariants**: TCB does not load sounds on demand. **Guarantees**: Per-room modulate Tweens are killed and restarted from current value on rapid re-trigger (no compounding).

### Commander's Room HUD

```gdscript
class_name CommandersRoomHUD extends CanvasLayer

# Tuning knobs read from Configuration Loader at _ready (see HUD GDD § Tuning Knobs)
# No public signals — terminal subscriber.

func open_detail_view() -> void
func close_detail_view() -> void
func is_detail_view_open() -> bool
```

**Invariants**: Status panel `mouse_filter = MOUSE_FILTER_IGNORE`. HUD never modifies upstream state.
**Guarantees**: Per-slot timers independent. `tasks_completed` exact. Detail overlay non-modal.

### Engine-specific type checks required before any ADR is Accepted

- `HTTPRequest.request_completed` signal signature (VERIFY #7) — affects Data Bridge
- `HTTPRequest.timeout` cancellation (VERIFY #8) — affects Data Bridge state transitions
- `Tween` cleanup on freed `Node2D` (VERIFY #9) — affects TCB + AAL + HUD
- `BitmapFont` / `FontFile` import path (VERIFY #2 + #5) — affects HUD
- `AnimationMixer.active` property (VERIFY #6) — affects ACC + AAL

---

## ADR Audit

### ADR Quality Check

**Zero ADRs exist** in `docs/architecture/`. Every architectural decision made in Phases 1–4 is currently undocumented as a formal ADR.

### Traceability Coverage

All ~70 Technical Requirements from the baseline are currently uncovered:

| GDD | TR Count | Future ADR Coverage |
|-----|----------|---------------------|
| Configuration Loader | 5 | ADR-002, ADR-003 |
| Audio Manager | 6 | ADR-003 (GDD itself sufficient otherwise) |
| TileMap Renderer | 4 | ADR-013 |
| Data Bridge | 8 | ADR-001, ADR-004, ADR-008 |
| Agent State Machine [blocked] | 6 | ADR-005, ADR-007 |
| Room System | 5 | ADR-003 (scene composition) |
| Agent Character Controller | 7 | ADR-009 |
| Ambient Animation Layer | 4 | ADR-009, ADR-010 |
| Task Completion Beat | 8 | ADR-010 |
| Commander's Room HUD | 12 | ADR-011, ADR-012 |
| Cross-cutting | 5 | ADR-006, ADR-008, ADR-014 |

**Coverage: 0 / ~70 TRs**. ADR Conflict Check: N/A (no ADRs). Engine Compatibility: N/A (none to validate).

Each ADR written from this list must:
- Carry an **Engine Compatibility** section stamped with version `4.6.2`
- Flag post-cutoff APIs with Knowledge Risk: HIGH / MEDIUM
- Cross-reference `docs/engine-reference/godot/modules/[domain].md`
- Include an **ADR Dependencies** section (even if all fields are "None")
- Include a **GDD Requirements Addressed** section linking the TRs it covers

---

## Required ADRs

14 ADRs total: 9 must-have before any coding, 5 should-have before their relevant system is implemented.

### Must have before coding starts (Foundation + Core)

| ADR | Title | Covers | Engine Risk |
|-----|-------|--------|-------------|
| **ADR-001** | Data Bridge Transport Strategy | HTTPRequest polling (not WebSocket/SSE for MVP), per-agent independent timers, web CORS plan, 5.0s default cadence | HIGH |
| **ADR-002** | Configuration Loading + Persistence | `config.json` next to executable on PC, embedded asset on web; `user://settings.json` for prefs; schema versioning | LOW |
| **ADR-003** | Autoload Scene Composition | Config Loader + Audio Manager are autoloads; everything else instantiated by Main Scene Bootstrap; init ordering | LOW |
| **ADR-004** | Web Export Compatibility | HTML5 pipeline: CORS for AI APIs, JS interop strategy, `keep_integer` stretch, texture compression option | HIGH |
| **ADR-005** | `task_completed` Signal Source | ASM emits `task_completed` (not ACC). Keeps Feedback dependent on Core, not Feature. | LOW |
| **ADR-006** | Signal-Based Decoupling Pattern | All cross-module communication uses Godot typed signals (not direct calls), except utility methods on autoload singletons | LOW |
| **ADR-008** | Mock Mode Strategy | `mock: true` swaps `HTTPRequest` for a cycling-JSON driver reading `assets/data/mock/[agent_id].json`. No conditional code in consumers. | LOW |
| **ADR-010** | Tween Lifecycle Management | Killing rules on rapid re-trigger; safe cleanup on freed `Node2D` (resolves VERIFY #9); Tween parenting | HIGH |
| **ADR-014** | Test Framework + CI | GUT; `tests/unit/`, `tests/integration/`; `.github/workflows/tests.yml`; CI: `godot --headless --script tests/gdunit4_runner.gd` | LOW |

### Should have before relevant system is implemented

| ADR | Title | Covers | Engine Risk |
|-----|-------|--------|-------------|
| **ADR-007** | Agent State Vocabulary | `STATES = ["idle", "working", "completed", "errored"]`. **Cannot be written until ASM GDD lands (blocked by Data Bridge prototype).** | LOW (blocked) |
| **ADR-009** | AnimationPlayer Strategy | Use `AnimationPlayer` with state-driven calls; defer `AnimationTree` to post-MVP; resolves VERIFY #6 | MEDIUM |
| **ADR-011** | HUD Rendering Strategy | Screen-space `CanvasLayer` + screen-space detail overlay (NOT in-world `SubViewport`). Resolved during HUD GDD redesign. | HIGH |
| **ADR-012** | BitmapFont / FontFile Strategy | Custom 5×7 BMFont via `FontFile` import (resolves VERIFY #2 + #5); fallback if `BitmapFont` is deprecated in 4.6 | HIGH |
| **ADR-013** | Stretch Mode + Pixel-Perfect Rendering | `keep_integer` stretch mode (resolves VERIFY #1); base resolution + integer-scale rule | MEDIUM |

### Suggested authoring order

1. ADR-002, ADR-003, ADR-006 (low-risk Foundation decisions — quick to write)
2. ADR-001, ADR-004 (Data Bridge transport + web compatibility — gate the prototype)
3. ADR-008, ADR-010, ADR-005 (mock mode, Tween lifecycle, signal source — unblock TCB + HUD work)
4. ADR-014 (test framework — enables TDD from day one)
5. ADR-013, ADR-011, ADR-012 (rendering decisions — needed before HUD coding)
6. ADR-009 (AnimationPlayer — needed before ACC + AAL coding)
7. ADR-007 (Agent state vocabulary — **after** Data Bridge prototype + ASM GDD)

---

## Architecture Principles

Five binding rules. Every ADR and every code change must respect these.

**1. Event-driven, not frame-driven.**
All cross-module communication is via Godot signals. No polling loops or `_process()` watching state in user code. The signal chain runs on the main thread serially.

**2. The state machine is the canonical source of truth.**
Anything that needs agent state asks ASM, never Data Bridge. Anything that needs room layout asks Room System, never the scene tree directly. The data layer (Data Bridge) is opaque — it passes raw String; ASM owns parsing.

**3. Tuning is data, not code.**
All numeric knobs come from Configuration Loader or from registered constants in `design/registry/entities.yaml` (`max_agents`, `cell_size`, `beat_total_seconds`, `commanders_room_id`, etc.). Never hardcoded.

**4. Pixel art is a contract.**
`CELL_SIZE = 16` and `MODULE_SIZE = 8` are global constants. Code placing sprites uses TileMap Renderer helpers (`cell_to_world`, `world_to_cell`) — never raw arithmetic on coordinates. Stretch mode is `keep_integer`.

**5. Web parity is non-negotiable.**
Every Foundation/Core ADR explicitly addresses PC + HTML5 web. HTTPRequest must work cross-origin. `user://` must persist in browser storage. BitmapFont must render. If a decision works on PC but not web, it is not approved.

---

## Open Questions

| # | Question | Resolved by | Blocks |
|---|----------|-------------|--------|
| 1 | ~~WCAG AA contrast — Active Green `#4A9A52` against Grey-Warm `#4A4035`~~ — **RESOLVED 2026-05-12**: S2 shifted to `#5BAD63` (3.65:1 PASS). Remaining: verify S2 over Void Black `#0A0A0F` + S3 Sienna over W2 + HUD font pairs. See `design/ux/accessibility-requirements.md` §1.1 | Art Director | Sprite/HUD production unblocked |
| 2 | Web export CORS — which AI APIs allow CORS for Godot HTML5? | Data Bridge prototype | ADR-001, ADR-004 |
| 3 | First AI agent API to target — Claude API, Cursor, others? | User decision before prototype | Data Bridge prototype |
| 4 | ASM connection-quality reporting mechanism — re-emit Data Bridge signal, or separate? | ASM GDD (blocked) | HUD overlay implementation |
| 5 | Computer prop affordance without hover (HUD OQ-2) | Art Director + UX | Commander's Room prop art |
| 6 | `beat_total_seconds` drift guard (HUD OQ-7) — runtime assert vs. HUD reads constant from TCB | Lead Programmer at implementation | HUD implementation |
| 7 | Zone 2 live updates while overlay open (HUD OQ-5) | Decided during HUD impl | HUD detail overlay logic |
| 8 | Per-agent_type completion sounds (TCB audio requirements) | Audio Director + Sound Designer | Audio production |
| 9 | Godot 4.6.2 VERIFY items #1–#9 (HOME.md) | Lead Programmer / sandbox testing | ADRs 001 (#7,8), 010 (#9), 011/12 (#2,5), 013 (#1), 009 (#6), TileMap Renderer (#3), Web export (#4) |

**Resolve items 1, 3, and 9 BEFORE the Data Bridge prototype runs.** Item 2 IS the prototype output. Items 4–8 are not blocking the prototype but should be resolved before the affected system implementation begins.
