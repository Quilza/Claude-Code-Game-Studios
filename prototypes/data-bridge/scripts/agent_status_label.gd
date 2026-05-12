class_name AgentStatusLabel extends VBoxContainer
##
## Sprint 1 prototype — per-agent visual indicator.
##
## Subscribes to DataBridge signals via .bind(agent_id) per ADR-0006 Tier 2.
## Displays: agent id, current connection state, last payload (truncated).
##
## This is intentionally crude — readability for the prototype operator,
## not aesthetic. The real HUD is ADR-0011 (Sprint 3+).
##

@export var agent_id: String = ""

var _state_label: Label
var _payload_label: Label
var _meta_label: Label
var _last_update_ticks: int = 0


func _ready() -> void:
	# Build a tiny three-line display
	_state_label = Label.new()
	_state_label.add_theme_font_size_override("font_size", 14)
	add_child(_state_label)

	_meta_label = Label.new()
	_meta_label.add_theme_font_size_override("font_size", 10)
	_meta_label.modulate = Color(0.7, 0.7, 0.7, 1.0)
	add_child(_meta_label)

	_payload_label = Label.new()
	_payload_label.add_theme_font_size_override("font_size", 10)
	_payload_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_payload_label.custom_minimum_size = Vector2(440, 0)
	add_child(_payload_label)

	_update_state(DataBridgeNode().get_connection_state(agent_id))
	_update_meta()

	# Tier 2 signal subscription per ADR-0006 — .bind(agent_id) filters per-entity
	DataBridgeNode().agent_response_received.connect(_on_response.bind(agent_id))
	DataBridgeNode().agent_connection_changed.connect(_on_connection_changed.bind(agent_id))


func DataBridgeNode() -> DataBridge:
	# Discovered via Main scene wiring — prototype convenience.
	# Production version: injected via @export, not get_node lookup.
	return get_tree().root.get_node("Main/DataBridge") as DataBridge


func _on_response(bound_id: String, _their_id: String, payload: String) -> void:
	if bound_id != agent_id:
		return
	_last_update_ticks = Time.get_ticks_msec()
	var truncated: String = payload
	if truncated.length() > 200:
		truncated = truncated.substr(0, 200) + "…"
	_payload_label.text = truncated
	_update_meta()


func _on_connection_changed(bound_id: String, _their_id: String, new_state: String) -> void:
	if bound_id != agent_id:
		return
	_update_state(new_state)
	_update_meta()


func _update_state(state: String) -> void:
	_state_label.text = "[%s] %s" % [agent_id, state]
	# Color per ADR-0011 connection-quality alpha map, but using rgb here for prototype legibility
	match state:
		DataBridge.STATE_CONNECTED:
			_state_label.modulate = Color(0.36, 0.68, 0.39, 1.0)  # green-ish
		DataBridge.STATE_STALE:
			_state_label.modulate = Color(0.83, 0.53, 0.16, 1.0)  # amber
		DataBridge.STATE_DISCONNECTED:
			_state_label.modulate = Color(0.63, 0.21, 0.13, 1.0)  # sienna
		DataBridge.STATE_ERROR:
			_state_label.modulate = Color(0.9, 0.2, 0.2, 1.0)
		_:
			_state_label.modulate = Color(0.5, 0.5, 0.5, 1.0)


func _update_meta() -> void:
	var bridge: DataBridge = DataBridgeNode()
	var fc: int = bridge.get_failure_count(agent_id)
	var age_ms: int = -1 if _last_update_ticks == 0 else (Time.get_ticks_msec() - _last_update_ticks)
	var age_str: String = "never" if age_ms < 0 else "%d ms ago" % age_ms
	_meta_label.text = "failures: %d   last response: %s" % [fc, age_str]


func _process(_delta: float) -> void:
	# Cheap continuous "last response age" tick so STALE is visually obvious
	if _last_update_ticks > 0:
		_update_meta()
