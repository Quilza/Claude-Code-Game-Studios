class_name AgentStateMachine extends Node
##
## AgentStateMachine (ASM) — Integration layer.
##
## Canonical source of per-agent state. Parses Data Bridge raw payloads
## and emits state-change signals consumed by ACC, AAL, TCB, HUD.
##
## Governing architecture:
##   • ADR-0007 (Agent State Vocabulary)          — Accepted 2026-05-12
##   • ADR-0005 (task_completed Signal Source)    — Accepted (ASM sole emitter)
##   • ADR-0006 (Signal-Based Decoupling)         — Accepted (Tier 2 subscription)
##   • ADR-0001 Amendment 2026-05-12.b            — uses request_dispatched/settled
##
## GDD: design/gdd/agent-state-machine.md (10/10 MVP GDDs designed)
##
## State vocabulary (4 states):
##   idle      — no request in flight, no recent activity
##   working   — request in flight OR last response stop_reason ∈ {tool_use, pause_turn}
##   completed — last response stop_reason ∈ {end_turn, max_tokens, stop_sequence}
##                 — TRANSIENT (1.5s decay → idle)
##   errored   — refusal, HTTP error, or unparseable payload — PERSISTENT
##
## Signals:
##   agent_state_changed(agent_id: String, new_state: String, previous_state: String)
##     — emits on actual transitions only (not same-state)
##   task_completed(agent_id: String)
##     — emits on every entry into `completed`. ASM is sole emitter per ADR-0005.
##

# ─── Signals ─────────────────────────────────────────────────────────────────

signal agent_state_changed(agent_id: String, new_state: String, previous_state: String)
signal task_completed(agent_id: String)


# ─── State constants ─────────────────────────────────────────────────────────

const STATE_IDLE: String = "idle"
const STATE_WORKING: String = "working"
const STATE_COMPLETED: String = "completed"
const STATE_ERRORED: String = "errored"

const INITIAL_AGENT_STATE: String = STATE_IDLE
const UNKNOWN_STOP_REASON_FALLBACK: String = STATE_COMPLETED


# ─── Stop-reason mapping table (per ADR-0007 Decision) ──────────────────────

const STOP_REASON_TO_STATE: Dictionary = {
	"end_turn": STATE_COMPLETED,
	"max_tokens": STATE_COMPLETED,
	"stop_sequence": STATE_COMPLETED,
	"tool_use": STATE_WORKING,
	"pause_turn": STATE_WORKING,
	"refusal": STATE_ERRORED,
}


# ─── Tuning constants ────────────────────────────────────────────────────────

const COMPLETED_DECAY_SEC_DEFAULT: float = 1.5         # matches beat_total_seconds
const STATS_WRITE_INTERVAL_SEC_DEFAULT: float = 5.0
const STATS_KEY_PREFIX: String = "asm_stats_"
const ASM_COMPLETED_DECAY_SETTING_KEY: String = "asm.completed_decay_sec"
const ASM_STATS_WRITE_INTERVAL_KEY: String = "asm.stats_write_interval_sec"


# ─── Internal state ──────────────────────────────────────────────────────────

var _agent_states: Dictionary = {}      # agent_id (String) → state String
var _agent_stats: Dictionary = {}       # agent_id (String) → stats Dictionary (9-field schema)
var _decay_timers: Dictionary = {}      # agent_id (String) → Timer node
var _stats_dirty: Dictionary = {}       # agent_id (String) → bool (dirty flag)
var _stats_flush_timer: Timer = null
var _bridge_ref: Node = null            # injected reference to DataBridge (or null in tests)

# Cached tuning (read at _ready from ConfigLoader, fall back to defaults)
var _completed_decay_sec: float = COMPLETED_DECAY_SEC_DEFAULT
var _stats_write_interval_sec: float = STATS_WRITE_INTERVAL_SEC_DEFAULT


# ─── Godot lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	if not _config_loader_available():
		push_error("[ASM] ConfigurationLoader autoload not found — ASM cannot initialise")
		return
	_load_tuning()
	_register_agents()
	_setup_stats_flush_timer()
	# Bridge subscription is deferred to call_deferred to handle the E-13
	# race condition (ASM _ready may run before Data Bridge _ready depending
	# on scene tree ordering).
	call_deferred("_subscribe_to_bridge")


func _exit_tree() -> void:
	# Per Rule 14 — flush all dirty stats on shutdown regardless of Timer state.
	_flush_all_dirty_stats()


# ─── Initialization ──────────────────────────────────────────────────────────

func _load_tuning() -> void:
	_completed_decay_sec = float(ConfigurationLoader.get_setting(
		ASM_COMPLETED_DECAY_SETTING_KEY, COMPLETED_DECAY_SEC_DEFAULT))
	_stats_write_interval_sec = float(ConfigurationLoader.get_setting(
		ASM_STATS_WRITE_INTERVAL_KEY, STATS_WRITE_INTERVAL_SEC_DEFAULT))


func _register_agents() -> void:
	# Per Rule 2: registration happens once at _ready(); bootstrap-only.
	for agent: Dictionary in ConfigurationLoader.get_agents():
		var id: String = String(agent.get("id", ""))
		if id.is_empty():
			continue
		_agent_states[id] = INITIAL_AGENT_STATE
		_agent_stats[id] = _load_or_initialise_stats(id)
		_stats_dirty[id] = false


func _load_or_initialise_stats(agent_id: String) -> Dictionary:
	# Per Rule 3 + E-14: load persisted stats from ConfigLoader.get_setting,
	# zero-init on corrupt blob, always overwrite session_start_ms with now.
	var key: String = STATS_KEY_PREFIX + agent_id
	var persisted: Variant = ConfigurationLoader.get_setting(key, null)
	var stats: Dictionary
	if persisted == null:
		stats = _default_stats_blob()
	elif _is_valid_stats_blob(persisted):
		stats = persisted as Dictionary
	else:
		push_warning("[ASM:%s] persisted stats corrupt — zeroed (per E-14)" % agent_id)
		stats = _default_stats_blob()
	stats["session_start_ms"] = Time.get_ticks_msec()
	stats["current_state"] = INITIAL_AGENT_STATE
	return stats


func _default_stats_blob() -> Dictionary:
	return {
		"current_state": INITIAL_AGENT_STATE,
		"tasks_completed": 0,
		"errored_count": 0,
		"last_state_change_ms": 0,
		"last_payload_id": "",
		"last_stop_reason": "",
		"total_input_tokens": 0,
		"total_output_tokens": 0,
		"session_start_ms": 0,
	}


func _is_valid_stats_blob(blob: Variant) -> bool:
	# Per AC-30: corrupt = (a) not Dict, (b) missing field, (c) type mismatch.
	if not (blob is Dictionary):
		return false
	var d: Dictionary = blob as Dictionary
	var required_keys: Array = [
		"tasks_completed", "errored_count", "last_state_change_ms",
		"total_input_tokens", "total_output_tokens",
	]
	for k: String in required_keys:
		if not d.has(k):
			return false
		if not (d[k] is int):
			return false
	return true


func _setup_stats_flush_timer() -> void:
	_stats_flush_timer = Timer.new()
	_stats_flush_timer.name = "StatsFlushTimer"
	_stats_flush_timer.wait_time = _stats_write_interval_sec
	_stats_flush_timer.one_shot = false
	_stats_flush_timer.autostart = true
	add_child(_stats_flush_timer)
	_stats_flush_timer.timeout.connect(_on_stats_flush_tick)


# ─── Bridge subscription ─────────────────────────────────────────────────────

func _subscribe_to_bridge() -> void:
	# Resolved deferred to avoid the E-13 race (ASM _ready before DataBridge _ready).
	# Main Scene Bootstrap (future) owns scene ordering; ASM's deferred path is
	# a defensive fallback.
	_bridge_ref = _find_bridge()
	if _bridge_ref == null:
		push_warning("[ASM] DataBridge node not found — ASM will not receive signals until manually wired")
		return
	_bridge_ref.agent_response_received.connect(_on_agent_response_received)
	if _bridge_ref.has_signal("request_dispatched"):
		_bridge_ref.request_dispatched.connect(_on_request_dispatched)
	if _bridge_ref.has_signal("request_settled"):
		_bridge_ref.request_settled.connect(_on_request_settled)


func _find_bridge() -> Node:
	# Look for a DataBridge child of the same parent (typical Main Scene layout).
	if get_parent() == null:
		return null
	for sibling: Node in get_parent().get_children():
		if sibling.get_script() != null and sibling.get_script().get_global_name() == "DataBridge":
			return sibling
		# Fall back to checking class via has_method (loose match)
		if sibling != self and sibling.has_method("is_request_in_flight"):
			return sibling
	return null


# ─── Signal handlers (subscriptions to DataBridge) ───────────────────────────

func _on_agent_response_received(agent_id: String, payload: String) -> void:
	# Per Rule 4 — parse payload + match stop_reason → state.
	var new_state: String = _derive_state_from_payload(payload, agent_id)
	# Apply usage token accumulation regardless of state change (Rule 13).
	_accumulate_tokens(agent_id, payload)
	# Apply state transition.
	_set_state(agent_id, new_state, payload)


func _on_request_dispatched(agent_id: String) -> void:
	# Per Rule 5 — on dispatch, transition to working.
	_set_state(agent_id, STATE_WORKING, "")


func _on_request_settled(agent_id: String) -> void:
	# Per Rule 5 — if settled WITHOUT preceding agent_response_received,
	# transition to errored. We detect this by checking whether the agent
	# is still in `working` (no response arrived between dispatched + settled).
	# A normal success path would have already transitioned via _on_agent_response_received.
	var current: String = _agent_states.get(agent_id, "")
	if current == STATE_WORKING:
		_set_state(agent_id, STATE_ERRORED, "")


# ─── State derivation (per ADR-0007 + ASM Rule 4) ────────────────────────────

func _derive_state_from_payload(payload: String, agent_id: String) -> String:
	if payload.is_empty():
		return STATE_ERRORED
	var parsed: Variant = JSON.parse_string(payload)
	if parsed == null or not (parsed is Dictionary):
		return STATE_ERRORED
	var p: Dictionary = parsed as Dictionary
	# Anthropic error envelope
	if p.has("error"):
		return STATE_ERRORED
	var stop_raw: Variant = p.get("stop_reason", null)
	if stop_raw == null or not (stop_raw is String):
		# No stop_reason — degrade to fallback with warning.
		push_warning("[ASM:%s] response has no stop_reason; falling back to %s" % [agent_id, UNKNOWN_STOP_REASON_FALLBACK])
		return UNKNOWN_STOP_REASON_FALLBACK
	var stop: String = String(stop_raw)
	if STOP_REASON_TO_STATE.has(stop):
		return STOP_REASON_TO_STATE[stop]
	# Unknown stop_reason — conservative fallback + warning.
	push_warning("[ASM:%s] unknown stop_reason='%s'; falling back to %s" % [agent_id, stop, UNKNOWN_STOP_REASON_FALLBACK])
	return UNKNOWN_STOP_REASON_FALLBACK


# ─── State application (per Rules 6, 7, 8, 9, 10) ────────────────────────────

func _set_state(agent_id: String, new_state: String, payload: String) -> void:
	if not _agent_states.has(agent_id):
		# Defensive — agent not registered. Defer to push_warning.
		push_warning("[ASM:%s] _set_state called for unregistered agent" % agent_id)
		return
	var previous: String = _agent_states[agent_id]
	if previous == new_state:
		# Same-state transitions don't emit (Rule 9).
		# However, if we just received a fresh response while in `completed`,
		# restart the decay timer (Rule 6 — new response before decay).
		if new_state == STATE_COMPLETED:
			_schedule_completed_decay(agent_id)
		# Even on no-op state, payload field updates apply.
		_update_payload_fields(agent_id, payload, new_state)
		return

	# Real state transition.
	_agent_states[agent_id] = new_state
	_update_payload_fields(agent_id, payload, new_state)
	_update_stats_counters(agent_id, previous, new_state)

	# Cancel any active decay timer if we're leaving `completed` to a new state.
	if previous == STATE_COMPLETED:
		_cancel_completed_decay(agent_id)

	# Schedule decay if we just entered `completed` (Rule 6).
	if new_state == STATE_COMPLETED:
		_schedule_completed_decay(agent_id)

	agent_state_changed.emit(agent_id, new_state, previous)

	# task_completed emits on every entry into completed (Rule 10, ADR-0005).
	if new_state == STATE_COMPLETED:
		task_completed.emit(agent_id)


func _schedule_completed_decay(agent_id: String) -> void:
	# Per Rule 6: 1.5s Timer; on timeout transition to idle.
	# Cancel and replace any existing Timer.
	_cancel_completed_decay(agent_id)
	var t: Timer = Timer.new()
	t.one_shot = true
	t.wait_time = _completed_decay_sec
	add_child(t)
	t.timeout.connect(_on_decay_timer_finished.bind(agent_id))
	_decay_timers[agent_id] = t
	t.start()


func _cancel_completed_decay(agent_id: String) -> void:
	if _decay_timers.has(agent_id):
		var t: Timer = _decay_timers[agent_id]
		if t != null and is_instance_valid(t):
			t.stop()
			t.queue_free()
		_decay_timers.erase(agent_id)


func _on_decay_timer_finished(agent_id: String) -> void:
	# Gate: only decay if still in completed (per E-9 — orphaned timer guard).
	if _agent_states.get(agent_id, "") != STATE_COMPLETED:
		return
	_set_state(agent_id, STATE_IDLE, "")


# ─── Stats updates (Rule 13) ─────────────────────────────────────────────────

func _update_payload_fields(agent_id: String, payload: String, new_state: String) -> void:
	var stats: Dictionary = _agent_stats[agent_id]
	stats["current_state"] = new_state
	stats["last_state_change_ms"] = Time.get_ticks_msec()
	# Extract id + stop_reason from payload if present (defensive parse).
	if not payload.is_empty():
		var parsed: Variant = JSON.parse_string(payload)
		if parsed is Dictionary:
			var p: Dictionary = parsed as Dictionary
			if p.has("id") and p["id"] is String:
				stats["last_payload_id"] = String(p["id"])
			elif p.has("request_id") and p["request_id"] is String:
				# Anthropic error envelope uses request_id
				stats["last_payload_id"] = String(p["request_id"])
			if p.has("stop_reason") and p["stop_reason"] is String:
				stats["last_stop_reason"] = String(p["stop_reason"])
			elif p.has("error"):
				stats["last_stop_reason"] = "error_envelope"
	_mark_dirty(agent_id)


func _update_stats_counters(agent_id: String, previous: String, new_state: String) -> void:
	var stats: Dictionary = _agent_stats[agent_id]
	if new_state == STATE_COMPLETED:
		stats["tasks_completed"] = int(stats.get("tasks_completed", 0)) + 1
	elif new_state == STATE_ERRORED:
		stats["errored_count"] = int(stats.get("errored_count", 0)) + 1
	_mark_dirty(agent_id)


func _accumulate_tokens(agent_id: String, payload: String) -> void:
	if payload.is_empty():
		return
	var parsed: Variant = JSON.parse_string(payload)
	if not (parsed is Dictionary):
		return
	var p: Dictionary = parsed as Dictionary
	if not p.has("usage"):
		return
	var usage: Variant = p["usage"]
	if not (usage is Dictionary):
		return
	var u: Dictionary = usage as Dictionary
	var stats: Dictionary = _agent_stats[agent_id]
	stats["total_input_tokens"] = int(stats.get("total_input_tokens", 0)) + int(u.get("input_tokens", 0))
	stats["total_output_tokens"] = int(stats.get("total_output_tokens", 0)) + int(u.get("output_tokens", 0))
	_mark_dirty(agent_id)


func _mark_dirty(agent_id: String) -> void:
	_stats_dirty[agent_id] = true


# ─── Persistence (Rule 14 — debounced + flush on close) ──────────────────────

func _on_stats_flush_tick() -> void:
	for agent_id: Variant in _stats_dirty.keys():
		if _stats_dirty[agent_id]:
			_flush_stats(String(agent_id))


func _flush_stats(agent_id: String) -> void:
	var key: String = STATS_KEY_PREFIX + agent_id
	ConfigurationLoader.set_setting(key, _agent_stats[agent_id])
	_stats_dirty[agent_id] = false


func _flush_all_dirty_stats() -> void:
	for agent_id: Variant in _stats_dirty.keys():
		if _stats_dirty[agent_id]:
			_flush_stats(String(agent_id))


# ─── Public read-only API (per Rule 15 + ADR-0006 Tier 3) ────────────────────

## Returns the current agent state. "idle" for unknown agents (safe default).
func get_agent_state(agent_id: String) -> String:
	return String(_agent_states.get(agent_id, STATE_IDLE))


## Returns the full 9-field stats dictionary for an agent. Empty {} if unknown.
func get_agent_stats(agent_id: String) -> Dictionary:
	if not _agent_stats.has(agent_id):
		return {}
	return _agent_stats[agent_id].duplicate()


## Returns bunker-wide state summary for the HUD status panel header.
## Per ASM GDD §3.7 Rule 15.
func get_bunker_summary() -> Dictionary:
	var summary: Dictionary = {
		"idle_count": 0,
		"working_count": 0,
		"completed_count": 0,
		"errored_count": 0,
		"total_count": 0,
	}
	for agent_id: Variant in _agent_states.keys():
		var state: String = String(_agent_states[agent_id])
		var key: String = state + "_count"
		summary[key] = int(summary.get(key, 0)) + 1
		summary["total_count"] = int(summary["total_count"]) + 1
	return summary


## True iff the agent was registered at bootstrap.
func is_agent_known(agent_id: String) -> bool:
	return _agent_states.has(agent_id)


# ─── Helpers ────────────────────────────────────────────────────────────────

func _config_loader_available() -> bool:
	return Engine.has_singleton("ConfigurationLoader") or (
		get_tree() != null
		and get_tree().root != null
		and get_tree().root.has_node("ConfigurationLoader")
	)


# ─── Test-only seam ─────────────────────────────────────────────────────────

## Inject an agent registration for unit tests. Production code must not call.
func _test_register_agent(agent_id: String) -> void:
	_agent_states[agent_id] = INITIAL_AGENT_STATE
	_agent_stats[agent_id] = _default_stats_blob()
	_agent_stats[agent_id]["session_start_ms"] = Time.get_ticks_msec()
	_stats_dirty[agent_id] = false
