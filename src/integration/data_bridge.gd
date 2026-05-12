class_name DataBridge extends Node
##
## DataBridge — Integration layer.
##
## Polls per-agent HTTP endpoints (or cycles mock payloads in mock mode)
## and emits raw payloads to downstream consumers. Stateless transport —
## ASM parses payloads per ADR-0007.
##
## Governing architecture:
##   • ADR-0001 (Data Bridge Transport)               — Accepted
##   • ADR-0001 Amendment 2026-05-12.b (B1, B2, B3, B5) — applied here
##   • ADR-0004 (Web Export Compatibility)            — Accepted (mock forced on web)
##   • ADR-0006 (Signal-Based Decoupling)             — Accepted
##   • ADR-0008 (Mock Mode Strategy)                  — Accepted
##
## GDD: design/gdd/data-bridge.md (post-Amendment 2026-05-12.b)
##
## Signal contract:
##   agent_response_received(agent_id: String, payload: String)
##     — emitted on every HTTP 2xx with a non-empty body, or on every
##       mock-cycle dispatch in mock mode
##   agent_connection_changed(agent_id: String, new_state: String)
##     — emitted on every connection-state transition
##       new_state ∈ {CONNECTING, CONNECTED, STALE, DISCONNECTED, ERROR}
##   request_dispatched(agent_id: String)
##     — emitted immediately before each HTTPRequest.request() call
##       (per Amendment B2 — required by ASM Rule 5 for `working` visibility)
##   request_settled(agent_id: String)
##     — emitted after request completes regardless of outcome (per B2)
##
## Public read-only accessors:
##   is_request_in_flight(agent_id) -> bool
##   get_connection_state(agent_id) -> String
##   get_failure_count(agent_id) -> int
##

# ─── Signals ─────────────────────────────────────────────────────────────────

signal agent_response_received(agent_id: String, payload: String)
signal agent_connection_changed(agent_id: String, new_state: String)
signal request_dispatched(agent_id: String)
signal request_settled(agent_id: String)


# ─── Connection state constants ──────────────────────────────────────────────

const STATE_UNINITIALIZED: String = "UNINITIALIZED"
const STATE_CONNECTING: String = "CONNECTING"
const STATE_CONNECTED: String = "CONNECTED"
const STATE_STALE: String = "STALE"
const STATE_DISCONNECTED: String = "DISCONNECTED"
const STATE_ERROR: String = "ERROR"


# ─── Backoff curve constants (per ADR-0001 §Decision) ────────────────────────

const STALE_AFTER_FAILURES: int = 2     # 1st failure stays CONNECTED (grace); 2nd → STALE
const DISCONNECTED_AFTER_FAILURES: int = 4
const POLL_INTERVAL_DEFAULT: float = 5.0
const MAX_BACKOFF_SEC: float = 30.0
const HTTP_TIMEOUT_SEC: float = 10.0
const MOCK_ASSETS_BASE_PATH: String = "res://assets/data/mock/"


# ─── Inner class: per-agent channel ──────────────────────────────────────────

class AgentChannel:
	var agent_id: String
	var config: Dictionary
	var http: HTTPRequest = null       # null in mock mode
	var timer: Timer
	var connection_state: String = DataBridge.STATE_UNINITIALIZED
	var failure_count: int = 0
	var current_backoff: float = 0.0
	var in_flight: bool = false
	# Mock-mode driver state
	var mock_cycle: Array = []
	var mock_index: int = 0


# ─── Internal state ──────────────────────────────────────────────────────────

var _channels: Dictionary = {}   # agent_id (String) → AgentChannel
var _is_mock_global: bool = false


# ─── Godot lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	if not _config_loader_available():
		push_error("[DataBridge] ConfigurationLoader autoload not found — bridge cannot initialise")
		return
	_is_mock_global = ConfigurationLoader.is_mock()
	for agent: Dictionary in ConfigurationLoader.get_agents():
		var id: String = String(agent.get("id", ""))
		if id.is_empty():
			push_warning("[DataBridge] Skipping agent with empty id")
			continue
		_spawn_channel(id, agent)


# ─── Channel spawning ────────────────────────────────────────────────────────

func _spawn_channel(id: String, config: Dictionary) -> void:
	var ch: AgentChannel = AgentChannel.new()
	ch.agent_id = id
	ch.config = config

	if _is_mock_global:
		ch.mock_cycle = _load_mock_payloads(id)
		print("[DataBridge] Spawning MOCK channel for agent %s (cycle len=%d)" % [id, ch.mock_cycle.size()])
	else:
		ch.http = HTTPRequest.new()
		ch.http.timeout = HTTP_TIMEOUT_SEC
		add_child(ch.http)
		ch.http.request_completed.connect(_on_request_completed.bind(id))

	# Timer (one-shot; re-armed after each settle).
	ch.timer = Timer.new()
	ch.timer.one_shot = true
	ch.timer.wait_time = _resolve_poll_interval()
	add_child(ch.timer)
	ch.timer.timeout.connect(_on_poll_timer.bind(id))

	_channels[id] = ch
	_transition_state(id, STATE_CONNECTING)
	ch.timer.start()


# ─── Mock payload loading (per ADR-0008) ─────────────────────────────────────

func _load_mock_payloads(agent_id: String) -> Array:
	# ADR-0008: cycle JSON arrays from assets/data/mock/[agent_id].json
	var path: String = MOCK_ASSETS_BASE_PATH + agent_id + ".json"
	if not FileAccess.file_exists(path):
		push_warning("[DataBridge] Mock file %s not found; using inline fallback cycle" % path)
		return _inline_fallback_cycle()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[DataBridge] Could not open mock file %s" % path)
		return _inline_fallback_cycle()
	var raw: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Array:
		return parsed
	push_warning("[DataBridge] Mock file %s did not contain a JSON array" % path)
	return _inline_fallback_cycle()


func _inline_fallback_cycle() -> Array:
	# Minimal 4-payload cycle used when mock asset is missing. Covers the four
	# canonical ASM states: completed, working, errored (via refusal), completed.
	return [
		'{"model":"mock","id":"msg_mock_1","stop_reason":"end_turn","content":[{"type":"text","text":"done"}],"usage":{"input_tokens":4,"output_tokens":2}}',
		'{"model":"mock","id":"msg_mock_2","stop_reason":"tool_use","content":[{"type":"tool_use","name":"search","input":{}}],"usage":{"input_tokens":6,"output_tokens":3}}',
		'{"model":"mock","id":"msg_mock_3","stop_reason":"end_turn","content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":4,"output_tokens":1}}',
		'{"model":"mock","id":"msg_mock_4","stop_reason":"refusal","content":[],"usage":{"input_tokens":4,"output_tokens":0}}',
	]


# ─── Poll dispatch ───────────────────────────────────────────────────────────

func _on_poll_timer(agent_id: String) -> void:
	var ch: AgentChannel = _channels.get(agent_id)
	if ch == null:
		return
	if ch.in_flight:
		# Don't pile up requests; reschedule next interval.
		_reschedule(agent_id)
		return
	if _is_mock_global:
		_dispatch_mock(agent_id)
	else:
		_dispatch_http(agent_id)


func _dispatch_mock(agent_id: String) -> void:
	var ch: AgentChannel = _channels[agent_id]
	if ch.mock_cycle.is_empty():
		_handle_failure(agent_id, "empty mock cycle", false)
		return
	ch.in_flight = true
	request_dispatched.emit(agent_id)
	var payload: String = str(ch.mock_cycle[ch.mock_index])
	ch.mock_index = (ch.mock_index + 1) % ch.mock_cycle.size()
	# In mock mode, every cycle dispatch succeeds (the bridge does not
	# simulate failures — that's the prototype's job). Production behavior:
	# emit response, settle, reschedule.
	ch.in_flight = false
	_handle_success(agent_id, payload)
	request_settled.emit(agent_id)


func _dispatch_http(agent_id: String) -> void:
	var ch: AgentChannel = _channels[agent_id]
	var endpoint: String = String(ch.config.get("endpoint_url", ""))
	if endpoint.is_empty():
		_handle_failure(agent_id, "no endpoint configured", true)
		return
	var token: String = String(ch.config.get("auth_token", ""))
	var headers: PackedStringArray = PackedStringArray()
	if not token.is_empty():
		headers.append("x-api-key: %s" % token)
		headers.append("anthropic-version: 2023-06-01")
	headers.append("content-type: application/json")

	# MVP request body — minimal poll. Real-API production tuning of body
	# shape is per-provider concern; this is the prototype-validated shape.
	var model: String = String(ch.config.get("model", "claude-haiku-4-5-20251001"))
	var body_dict: Dictionary = {
		"model": model,
		"max_tokens": 1,
		"messages": [{"role": "user", "content": "ping"}]
	}
	var body: String = JSON.stringify(body_dict)
	ch.in_flight = true
	request_dispatched.emit(agent_id)
	var err: int = ch.http.request(endpoint, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		ch.in_flight = false
		_handle_failure(agent_id, "HTTPRequest.request() returned err=%d" % err, false)
		request_settled.emit(agent_id)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, agent_id: String) -> void:
	var ch: AgentChannel = _channels.get(agent_id)
	if ch == null:
		return
	ch.in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_handle_failure(agent_id, "result=%d" % result, false)
		request_settled.emit(agent_id)
		return
	if response_code < 200 or response_code >= 300:
		# Amendment B1: 4xx is config-fatal — skip backoff curve, go directly to DISCONNECTED.
		# 5xx + network use the original grace → STALE → DISCONNECTED curve.
		var is_4xx: bool = response_code >= 400 and response_code < 500
		var err_body: String = body.get_string_from_utf8()
		print("[DataBridge:%s] HTTP %d error body: %s" % [agent_id, response_code, err_body])
		_handle_failure(agent_id, "http %d" % response_code, is_4xx)
		request_settled.emit(agent_id)
		return
	var payload: String = body.get_string_from_utf8()
	_handle_success(agent_id, payload)
	request_settled.emit(agent_id)


# ─── Success / failure handling ──────────────────────────────────────────────

func _handle_success(agent_id: String, payload: String) -> void:
	var ch: AgentChannel = _channels[agent_id]
	ch.failure_count = 0
	ch.current_backoff = 0.0
	_transition_state(agent_id, STATE_CONNECTED)
	agent_response_received.emit(agent_id, payload)
	_reschedule(agent_id)


## Records a failure and advances connection state.
## fatal_4xx flag (per Amendment B1): when true, skip the grace curve and
## transition directly to DISCONNECTED. Bridge will NOT auto-heal until
## config changes (or scene reload).
func _handle_failure(agent_id: String, reason: String, fatal_4xx: bool) -> void:
	var ch: AgentChannel = _channels[agent_id]
	ch.failure_count += 1
	push_warning("[DataBridge:%s] failure #%d — %s" % [agent_id, ch.failure_count, reason])

	if fatal_4xx:
		_transition_state(agent_id, STATE_DISCONNECTED)
		# Don't reschedule — wait for ConfigurationLoader.setting_changed to retry,
		# or for scene reload. For MVP, the channel goes dormant.
		return

	# 5xx + network: grace → STALE → DISCONNECTED curve.
	if ch.failure_count >= DISCONNECTED_AFTER_FAILURES:
		_transition_state(agent_id, STATE_DISCONNECTED)
	elif ch.failure_count >= STALE_AFTER_FAILURES:
		_transition_state(agent_id, STATE_STALE)
	# failure_count == 1 stays CONNECTED (grace per ADR-0001).

	# Exponential backoff, cap MAX_BACKOFF_SEC
	var base: float = _resolve_poll_interval()
	ch.current_backoff = minf(base * pow(2.0, ch.failure_count - 1), MAX_BACKOFF_SEC)
	_reschedule(agent_id)


func _reschedule(agent_id: String) -> void:
	var ch: AgentChannel = _channels[agent_id]
	var wait: float
	if ch.current_backoff > 0.0:
		wait = ch.current_backoff
	else:
		wait = _resolve_poll_interval()
	ch.timer.wait_time = wait
	ch.timer.start()


## Reads the project-wide `poll_interval_sec` from ConfigurationLoader. The
## per-agent config dict does NOT carry this — it's a top-level config.json
## field, validated and stored by ConfigLoader. Returns POLL_INTERVAL_DEFAULT
## when ConfigLoader is unreachable (test paths).
##
## Pre-fix: each channel read `poll_interval` from its per-agent config dict
## (wrong key name, wrong source), silently fell through to the 5.0s default,
## ignored the user's config.json override. Audited 2026-05-13.
func _resolve_poll_interval() -> float:
	if Engine.has_singleton("ConfigurationLoader") or (
			get_tree() != null
			and get_tree().root != null
			and get_tree().root.has_node("ConfigurationLoader")):
		return ConfigurationLoader.get_poll_interval()
	return POLL_INTERVAL_DEFAULT


func _transition_state(agent_id: String, new_state: String) -> void:
	var ch: AgentChannel = _channels[agent_id]
	if ch.connection_state == new_state:
		return
	var prev: String = ch.connection_state
	ch.connection_state = new_state
	print("[DataBridge:%s] %s → %s" % [agent_id, prev, new_state])
	agent_connection_changed.emit(agent_id, new_state)


# ─── Public read-only accessors (per ADR-0006 Tier 3 + Amendment B2) ─────────

## True iff a request is in flight for this agent (between dispatched and settled).
## Required by ASM Rule 5 for `working` state visibility.
func is_request_in_flight(agent_id: String) -> bool:
	var ch: AgentChannel = _channels.get(agent_id)
	if ch == null:
		return false
	return ch.in_flight


## Current connection state for an agent. Returns UNINITIALIZED if unknown.
func get_connection_state(agent_id: String) -> String:
	var ch: AgentChannel = _channels.get(agent_id)
	if ch == null:
		return STATE_UNINITIALIZED
	return ch.connection_state


## Current consecutive-failure count for an agent. Returns 0 if unknown.
func get_failure_count(agent_id: String) -> int:
	var ch: AgentChannel = _channels.get(agent_id)
	if ch == null:
		return 0
	return ch.failure_count


## Returns the list of registered agent IDs (read-only).
func get_agent_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: Variant in _channels.keys():
		ids.append(String(id))
	return ids


# ─── Helpers ────────────────────────────────────────────────────────────────

func _config_loader_available() -> bool:
	return Engine.has_singleton("ConfigurationLoader") or (
		get_tree() != null
		and get_tree().root != null
		and get_tree().root.has_node("ConfigurationLoader")
	)


# ─── Test-only seam ─────────────────────────────────────────────────────────

## Inject a pre-built channel for unit testing. Production code must not call this.
func _test_inject_channel(agent_id: String, config: Dictionary) -> AgentChannel:
	var ch: AgentChannel = AgentChannel.new()
	ch.agent_id = agent_id
	ch.config = config
	ch.connection_state = STATE_UNINITIALIZED
	_channels[agent_id] = ch
	return ch
