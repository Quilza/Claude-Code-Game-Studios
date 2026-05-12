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


# ─── Layout constants ────────────────────────────────────────────────────────

# Per ADR-0013, viewport is 480×270. Slot grid is 3 cols × 4 rows in top-left.
# Status panel is top-right (~88×80 px). Completions strip is bottom-center.
const SLOT_GRID_COLS: int = 3
const SLOT_GRID_ROWS: int = 4
const SLOT_GRID_ORIGIN: Vector2 = Vector2(4, 4)
const SLOT_SIZE: Vector2 = Vector2(24, 28)
const SLOT_SPACING: Vector2 = Vector2(2, 2)

const STATUS_PANEL_ORIGIN: Vector2 = Vector2(388, 4)   # 480 − 88 − 4 = 388
const STATUS_PANEL_SIZE: Vector2 = Vector2(88, 80)

const COMPLETIONS_STRIP_SIZE: Vector2 = Vector2(280, 22)
const COMPLETIONS_STRIP_ORIGIN: Vector2 = Vector2(100, 244)  # bottom-center: (480-280)/2 ≈ 100; 270-22-4 = 244

# Per art-bible.md (post WCAG fix 2026-05-12)
const COLOR_AMBER: Color = Color8(0xD4, 0x88, 0x2A)
const COLOR_GREEN: Color = Color8(0x5B, 0xAD, 0x63)
const COLOR_SIENNA: Color = Color8(0xA0, 0x35, 0x20)
const COLOR_PANEL_BG: Color = Color(0.1, 0.08, 0.07, 0.85)
const COLOR_PANEL_BORDER: Color = Color(0.4, 0.36, 0.32, 0.6)
const COLOR_TEXT: Color = Color(0.95, 0.85, 0.65, 1.0)
const COLOR_TEXT_DIM: Color = Color(0.6, 0.55, 0.45, 1.0)


# ─── Internal state ──────────────────────────────────────────────────────────

# Per-slot state: agent_id → {state, connection_state, tasks_completed, last_beat_ms, completed_glyph_timer}
var _slot_state: Dictionary = {}

# Completions strip: array of dicts {agent_id, timestamp}; capped at COMPLETIONS_STRIP_MAX
var _completions_strip: Array[Dictionary] = []

# Layout — built lazily in _ready() after subscriptions wire up.
var _root_control: Control = null
var _status_panel: Control = null
var _summary_label: Label = null
var _slot_grid: Control = null
var _slot_controls: Dictionary = {}        # agent_id → SlotControl (Panel with children)
var _completions_strip_root: Control = null
var _completions_label: Label = null


# ─── Godot lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	layer = HUD_LAYER_INDEX   # set CanvasLayer Z order per ADR-0011
	process_mode = Node.PROCESS_MODE_ALWAYS   # per ADR-0011 — HUD runs during pause
	_load_persisted_visibility()
	_subscribe_to_signals()
	_initialise_slots_from_config()
	_build_layout()
	_refresh_all()


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
	_refresh_slot(agent_id)
	_refresh_summary()


func _on_agent_connection_changed(agent_id: String, new_state: String) -> void:
	if not _slot_state.has(agent_id):
		return
	_slot_state[agent_id]["connection_state"] = new_state
	_refresh_slot(agent_id)


func _on_beat_fired(agent_id: String, timestamp: float) -> void:
	if not _slot_state.has(agent_id):
		return
	_slot_state[agent_id]["tasks_completed"] = int(_slot_state[agent_id]["tasks_completed"]) + 1
	_slot_state[agent_id]["last_beat_ms"] = Time.get_ticks_msec()
	_prepend_completion(agent_id, timestamp)
	_refresh_slot(agent_id)
	_refresh_completions_strip()


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


# ─── Layout construction (Control hierarchy per ADR-0011) ────────────────────

func _build_layout() -> void:
	_root_control = Control.new()
	_root_control.name = "HudRoot"
	_root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE   # per ADR-0011 default IGNORE
	add_child(_root_control)

	_build_slot_grid()
	_build_status_panel()
	_build_completions_strip()


func _build_slot_grid() -> void:
	_slot_grid = Control.new()
	_slot_grid.name = "SlotGrid"
	_slot_grid.position = SLOT_GRID_ORIGIN
	_slot_grid.size = Vector2(
		SLOT_GRID_COLS * (SLOT_SIZE.x + SLOT_SPACING.x),
		SLOT_GRID_ROWS * (SLOT_SIZE.y + SLOT_SPACING.y),
	)
	_slot_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_control.add_child(_slot_grid)

	# Build a fixed 3×4 grid (12 slots). Slots beyond the configured agent
	# count render dimmed/empty.
	var agent_ids: Array = _slot_state.keys()
	for row: int in SLOT_GRID_ROWS:
		for col: int in SLOT_GRID_COLS:
			var slot_index: int = row * SLOT_GRID_COLS + col
			var agent_id: String = ""
			if slot_index < agent_ids.size():
				agent_id = String(agent_ids[slot_index])
			var slot: Panel = _build_single_slot(agent_id, col, row)
			_slot_grid.add_child(slot)
			if not agent_id.is_empty():
				_slot_controls[agent_id] = slot


func _build_single_slot(agent_id: String, col: int, row: int) -> Panel:
	var slot: Panel = Panel.new()
	slot.name = "Slot_%d_%d" % [col, row] if agent_id.is_empty() else "Slot_%s" % agent_id
	slot.position = Vector2(
		col * (SLOT_SIZE.x + SLOT_SPACING.x),
		row * (SLOT_SIZE.y + SLOT_SPACING.y),
	)
	slot.size = SLOT_SIZE
	# Per ADR-0011: STOP only on the 12 clickable slots; IGNORE everywhere else.
	# For MVP we leave it IGNORE — clicks open detail overlay (TODO).
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Background tint
	var bg: ColorRect = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.18, 0.14, 0.12, 0.9) if not agent_id.is_empty() else Color(0.12, 0.10, 0.08, 0.5)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(bg)

	# Glyph label (centered)
	var glyph: Label = Label.new()
	glyph.name = "Glyph"
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 14)
	glyph.text = STATE_GLYPH.get(AgentStateMachine.STATE_IDLE, "▬") if not agent_id.is_empty() else ""
	glyph.modulate = COLOR_AMBER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(glyph)

	# Agent ID label (bottom)
	var id_label: Label = Label.new()
	id_label.name = "IdLabel"
	id_label.position = Vector2(0, SLOT_SIZE.y - 8)
	id_label.size = Vector2(SLOT_SIZE.x, 8)
	id_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	id_label.add_theme_font_size_override("font_size", 7)
	id_label.text = _short_label(agent_id)
	id_label.modulate = COLOR_TEXT_DIM
	id_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(id_label)

	return slot


func _build_status_panel() -> void:
	_status_panel = Panel.new()
	_status_panel.name = "StatusPanel"
	_status_panel.position = STATUS_PANEL_ORIGIN
	_status_panel.size = STATUS_PANEL_SIZE
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_control.add_child(_status_panel)

	var bg: ColorRect = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = COLOR_PANEL_BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_panel.add_child(bg)

	_summary_label = Label.new()
	_summary_label.name = "SummaryLabel"
	_summary_label.position = Vector2(4, 4)
	_summary_label.size = STATUS_PANEL_SIZE - Vector2(8, 8)
	_summary_label.add_theme_font_size_override("font_size", 8)
	_summary_label.modulate = COLOR_TEXT
	_summary_label.text = "—"
	_summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_panel.add_child(_summary_label)


func _build_completions_strip() -> void:
	_completions_strip_root = Panel.new()
	_completions_strip_root.name = "CompletionsStrip"
	_completions_strip_root.position = COMPLETIONS_STRIP_ORIGIN
	_completions_strip_root.size = COMPLETIONS_STRIP_SIZE
	_completions_strip_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_control.add_child(_completions_strip_root)

	var bg: ColorRect = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = COLOR_PANEL_BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_completions_strip_root.add_child(bg)

	_completions_label = Label.new()
	_completions_label.name = "CompletionsLabel"
	_completions_label.position = Vector2(4, 4)
	_completions_label.size = COMPLETIONS_STRIP_SIZE - Vector2(8, 8)
	_completions_label.add_theme_font_size_override("font_size", 8)
	_completions_label.modulate = COLOR_TEXT_DIM
	_completions_label.text = "no completions yet"
	_completions_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_completions_strip_root.add_child(_completions_label)


# ─── Render refresh methods ──────────────────────────────────────────────────

func _refresh_all() -> void:
	for agent_id: Variant in _slot_state.keys():
		_refresh_slot(String(agent_id))
	_refresh_summary()
	_refresh_completions_strip()


func _refresh_slot(agent_id: String) -> void:
	if not _slot_controls.has(agent_id):
		return
	var slot: Panel = _slot_controls[agent_id]
	var state: String = String(_slot_state[agent_id].get("state", AgentStateMachine.STATE_IDLE))
	var conn: String = String(_slot_state[agent_id].get("connection_state", "CONNECTING"))
	var alpha: float = float(CONNECTION_ALPHA.get(conn, 1.0))

	var glyph: Label = slot.get_node_or_null("Glyph") as Label
	if glyph != null:
		glyph.text = String(STATE_GLYPH.get(state, "▬"))
		glyph.modulate = _color_for_state(state)
		glyph.modulate.a = alpha


func _refresh_summary() -> void:
	if _summary_label == null:
		return
	var s: Dictionary = get_summary()
	_summary_label.text = "agents: %d/%d\n● working: %d\n+ done: %d\n▬ idle: %d\n● err: %d" % [
		int(s.get("total_count", 0)),
		int(s.get("total_count", 0)),
		int(s.get("working_count", 0)),
		int(s.get("completed_count", 0)),
		int(s.get("idle_count", 0)),
		int(s.get("errored_count", 0)),
	]


func _refresh_completions_strip() -> void:
	if _completions_label == null:
		return
	if _completions_strip.is_empty():
		_completions_label.text = "no completions yet"
		return
	var parts: PackedStringArray = PackedStringArray()
	for entry: Dictionary in _completions_strip:
		var ts: float = float(entry.get("timestamp", 0.0))
		var time_str: String = Time.get_time_string_from_unix_time(int(ts)).left(5)  # HH:MM
		parts.append("%s %s" % [time_str, String(entry.get("agent_id", "?"))])
	_completions_label.text = "  ·  ".join(parts)


# ─── Helpers ────────────────────────────────────────────────────────────────

func _color_for_state(state: String) -> Color:
	match state:
		AgentStateMachine.STATE_IDLE:
			return COLOR_AMBER
		AgentStateMachine.STATE_WORKING, AgentStateMachine.STATE_COMPLETED:
			return COLOR_GREEN
		AgentStateMachine.STATE_ERRORED:
			return COLOR_SIENNA
		_:
			return COLOR_TEXT_DIM


func _short_label(agent_id: String) -> String:
	# Slot labels are 24 px wide × 7 px font — fits maybe 4-5 chars.
	if agent_id.is_empty():
		return ""
	if agent_id.length() <= 5:
		return agent_id
	return agent_id.substr(0, 5)


# ─── Helpers ────────────────────────────────────────────────────────────────

func _config_loader_available() -> bool:
	return Engine.has_singleton("ConfigurationLoader") or (
		get_tree() != null
		and get_tree().root != null
		and get_tree().root.has_node("ConfigurationLoader")
	)
