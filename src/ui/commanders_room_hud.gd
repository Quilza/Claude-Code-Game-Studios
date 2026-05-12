class_name CommandersRoomHUD extends CanvasLayer
##
## CommandersRoomHUD — UI layer.
##
## Two-CanvasLayer topology per ADR-0011: HudLayer (this node, layer=10)
## holds status panel + slot grid + completions strip. OverlayLayer (sibling)
## holds detail overlay. HUD subscribes to ASM, DataBridge, TCB, RoomSystem.
##
## Governing architecture:
##   • ADR-0011 (HUD Rendering Strategy)          — Accepted (incl. A1, A2)
##   • ADR-0012 (BitmapFont/FontFile Strategy)    — Accepted (Theme-driven)
##   • ADR-0013 (Stretch Mode + Pixel-Perfect)    — Accepted (480×270 viewport)
##   • ADR-0006 (Signal-Based Decoupling)         — Tier 2 + Tier 3
##
## GDD: design/gdd/commanders-room-hud.md (post cross-GDD reconciliation)
##
## **Scope note**: this commit implements the architectural skeleton — signal
## wiring, per-slot state model, connection-alpha map, toggle persistence,
## bunker summary. Visual layout (Control hierarchy, glyph rendering, font
## theme application, slot click→overlay) is structured but Control node
## composition is left to the .tscn scene file (Main Scene Bootstrap GDD).
##

# ─── Constants ───────────────────────────────────────────────────────────────

const HUD_LAYER_INDEX: int = 10           # ADR-0011 §Two-CanvasLayer Topology
const OVERLAY_LAYER_INDEX: int = 20

const HUD_VISIBLE_SETTING_KEY: String = "hud_visible"
const COMPLETIONS_STRIP_MAX: int = 6      # per TR-hud-003
const COMPLETED_GLYPH_TIMER_SEC: float = 1.5  # per TR-hud-004 + beat_total_seconds

# Connection-quality alpha map (per ADR-0011 + GDD §State Visual Matrix)
const CONNECTION_ALPHA: Dictionary = {
	"CONNECTED": 1.0,
	"STALE": 0.5,
	"DISCONNECTED": 0.25,
	"ERROR": 0.25,
}

# Slot glyph map (per HUD GDD)
const STATE_GLYPH: Dictionary = {
	"idle":      "▬",   # amber
	"working":   "●",   # green
	"completed": "+",   # green, transient
	"errored":   "●",   # sienna
}


# ─── Signals ─────────────────────────────────────────────────────────────────

signal hud_visibility_toggled(visible: bool)


# ─── Dependencies (scene-wired) ──────────────────────────────────────────────

@export var agent_state_machine: AgentStateMachine = null
@export var data_bridge: DataBridge = null
@export var task_completion_beat: TaskCompletionBeat = null
@export var room_system: RoomSystem = null


# ─── Internal state ──────────────────────────────────────────────────────────

# Per-slot state: agent_id → {state, connection_state, tasks_completed, last_beat_ms, completed_glyph_timer}
var _slot_state: Dictionary = {}

# Completions strip: array of dicts {agent_id, timestamp}; capped at COMPLETIONS_STRIP_MAX
var _completions_strip: Array[Dictionary] = []


# ─── Godot lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	layer = HUD_LAYER_INDEX   # set CanvasLayer Z order per ADR-0011
	process_mode = Node.PROCESS_MODE_ALWAYS   # per ADR-0011 — HUD runs during pause
	_load_persisted_visibility()
	_subscribe_to_signals()
	_initialise_slots_from_config()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_hud"):
		toggle_visibility()
		get_viewport().set_input_as_handled()


# ─── Visibility toggle (per ADR-0011 user requirement) ───────────────────────

func toggle_visibility() -> void:
	visible = not visible
	if _config_loader_available():
		ConfigurationLoader.set_setting(HUD_VISIBLE_SETTING_KEY, visible)
	hud_visibility_toggled.emit(visible)


func _load_persisted_visibility() -> void:
	if _config_loader_available():
		visible = bool(ConfigurationLoader.get_setting(HUD_VISIBLE_SETTING_KEY, true))


# ─── Signal wiring (Tier 1 broadcasts; per-slot filtering in handlers) ───────

func _subscribe_to_signals() -> void:
	if agent_state_machine != null:
		agent_state_machine.agent_state_changed.connect(_on_agent_state_changed)
	else:
		push_warning("[HUD] agent_state_machine not wired")
	if data_bridge != null:
		data_bridge.agent_connection_changed.connect(_on_agent_connection_changed)
	else:
		push_warning("[HUD] data_bridge not wired")
	if task_completion_beat != null:
		task_completion_beat.beat_fired.connect(_on_beat_fired)
	else:
		push_warning("[HUD] task_completion_beat not wired")
	if room_system != null:
		room_system.computer_interacted.connect(_on_computer_interacted)
	else:
		push_warning("[HUD] room_system not wired")


# ─── Slot initialization from ConfigLoader.get_agents() ──────────────────────

func _initialise_slots_from_config() -> void:
	if not _config_loader_available():
		return
	var agents: Array = ConfigurationLoader.get_agents()
	for agent: Dictionary in agents:
		var id: String = String(agent.get("id", ""))
		if id.is_empty():
			continue
		_slot_state[id] = {
			"state": AgentStateMachine.STATE_IDLE,
			"connection_state": "CONNECTING",
			"tasks_completed": 0,
			"last_beat_ms": 0,
			"display_name": String(agent.get("display_name", id)),
		}


# ─── Signal handlers ─────────────────────────────────────────────────────────

func _on_agent_state_changed(agent_id: String, new_state: String, _previous: String) -> void:
	if not _slot_state.has(agent_id):
		return
	_slot_state[agent_id]["state"] = new_state
	# tasks_completed is updated by beat_fired (not state changes) so HUD
	# stays consistent with TCB's logic per GDD AC-23.


func _on_agent_connection_changed(agent_id: String, new_state: String) -> void:
	if not _slot_state.has(agent_id):
		return
	_slot_state[agent_id]["connection_state"] = new_state


func _on_beat_fired(agent_id: String, timestamp: float) -> void:
	if not _slot_state.has(agent_id):
		return
	_slot_state[agent_id]["tasks_completed"] = int(_slot_state[agent_id]["tasks_completed"]) + 1
	_slot_state[agent_id]["last_beat_ms"] = Time.get_ticks_msec()
	_prepend_completion(agent_id, timestamp)


func _on_computer_interacted() -> void:
	# TODO: open OverlayLayer detail overlay. Requires OverlayLayer reference
	# + detail panel composition (scene-authored).
	pass


# ─── Completions strip (per TR-hud-003) ──────────────────────────────────────

func _prepend_completion(agent_id: String, timestamp: float) -> void:
	_completions_strip.push_front({"agent_id": agent_id, "timestamp": timestamp})
	# Cap at COMPLETIONS_STRIP_MAX entries; drop oldest.
	while _completions_strip.size() > COMPLETIONS_STRIP_MAX:
		_completions_strip.pop_back()


# ─── Public read-only API ────────────────────────────────────────────────────

## Returns the snapshot of slot state for a given agent_id.
## Returns {} if agent unknown.
func get_slot_state(agent_id: String) -> Dictionary:
	if not _slot_state.has(agent_id):
		return {}
	return _slot_state[agent_id].duplicate()


## Returns the connection-quality alpha for an agent's slot.
## Per ADR-0011 — 1.0 CONNECTED, 0.5 STALE, 0.25 DISCONNECTED/ERROR.
func get_slot_alpha(agent_id: String) -> float:
	if not _slot_state.has(agent_id):
		return 0.0
	var conn: String = String(_slot_state[agent_id].get("connection_state", "CONNECTING"))
	return float(CONNECTION_ALPHA.get(conn, 1.0))


## Returns the glyph character for an agent's current state.
func get_slot_glyph(agent_id: String) -> String:
	if not _slot_state.has(agent_id):
		return ""
	var state: String = String(_slot_state[agent_id].get("state", AgentStateMachine.STATE_IDLE))
	return String(STATE_GLYPH.get(state, "▬"))


## Returns the completions strip in display order (most recent first).
func get_completions_strip() -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for entry: Dictionary in _completions_strip:
		copy.append(entry.duplicate())
	return copy


## Returns the bunker-wide summary for the status panel header.
## Delegates to ASM.get_bunker_summary() since ASM owns the canonical counts.
func get_summary() -> Dictionary:
	if agent_state_machine == null:
		return {"idle_count": 0, "working_count": 0, "completed_count": 0, "errored_count": 0, "total_count": 0}
	return agent_state_machine.get_bunker_summary()


# ─── Helpers ────────────────────────────────────────────────────────────────

func _config_loader_available() -> bool:
	return Engine.has_singleton("ConfigurationLoader") or (
		get_tree() != null
		and get_tree().root != null
		and get_tree().root.has_node("ConfigurationLoader")
	)
