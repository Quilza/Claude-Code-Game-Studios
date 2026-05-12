class_name DataBridge extends Node
##
## Sprint 1 prototype — Data Bridge implementation.
##
## Implements the transport pattern from ADR-0001:
##   - One HTTPRequest node per agent (or MockDriver if is_mock())
##   - Independent per-agent polling timers
##   - Raw String payload (NO json parsing at this layer)
##   - Backoff: grace(1) → STALE(2) → DISCONNECTED(4); cap 30s; auto-heal
##   - Signals: agent_response_received(agent_id: String, payload: String)
##              agent_connection_changed(agent_id: String, new_state: String)
##   - agent_id: String everywhere
##
## What this prototype DELIBERATELY does NOT do (per ADR-0001 single-writer
## rule + ADR-0007 BLOCKED):
##   - Decide agent "state" vocabulary (idle/working/completed/errored)
##   - Parse the payload JSON
##   - Emit task_completed (that's ASM's job)
##
## This prototype emits raw payloads + connection state. The findings doc
## captures what the payloads look like so ADR-0007 can be written.
##

signal agent_response_received(agent_id: String, payload: String)
signal agent_connection_changed(agent_id: String, new_state: String)

const POLL_INTERVAL_DEFAULT: float = 5.0
const MAX_BACKOFF_SEC: float = 30.0
const STALE_AFTER_FAILURES: int = 2     # 1st failure = grace, 2nd = STALE
const DISCONNECTED_AFTER_FAILURES: int = 4

# Connection state vocabulary (per ADR-0001 — NOT agent state, which is ADR-0007's domain)
const STATE_UNINITIALIZED: String = "UNINITIALIZED"
const STATE_CONNECTING: String = "CONNECTING"
const STATE_CONNECTED: String = "CONNECTED"
const STATE_STALE: String = "STALE"
const STATE_DISCONNECTED: String = "DISCONNECTED"
const STATE_ERROR: String = "ERROR"


class AgentChannel:
	## Per-agent polling channel. One per configured agent.
	var agent_id: String
	var config: Dictionary
	var http: HTTPRequest = null         # null if mock mode
	var timer: Timer
	var connection_state: String = STATE_UNINITIALIZED
	var failure_count: int = 0
	var current_backoff: float = 0.0
	var in_flight: bool = false
	# Mock-mode state
	var mock_cycle: Array = []
	var mock_index: int = 0


var _channels: Dictionary = {}   # agent_id (String) → AgentChannel


func _ready() -> void:
	_initialize_from_config()


func _initialize_from_config() -> void:
	for agent: Dictionary in ConfigurationLoader.get_agents():
		var id: String = String(agent.get("id", ""))
		if id.is_empty():
			push_warning("[DataBridge] Skipping agent with empty id")
			continue
		_spawn_channel(id, agent)


func _spawn_channel(id: String, config: Dictionary) -> void:
	var ch: AgentChannel = AgentChannel.new()
	ch.agent_id = id
	ch.config = config

	if ConfigurationLoader.is_mock():
		ch.mock_cycle = _load_mock_payloads(id)
		print("[DataBridge] Spawning MOCK channel for agent %s (cycle len=%d)" % [id, ch.mock_cycle.size()])
	else:
		ch.http = HTTPRequest.new()
		ch.http.timeout = 10.0
		add_child(ch.http)
		ch.http.request_completed.connect(_on_request_completed.bind(id))
		print("[DataBridge] Spawning HTTP channel for agent %s" % id)

	ch.timer = Timer.new()
	ch.timer.one_shot = true
	var interval: float = float(config.get("poll_interval", POLL_INTERVAL_DEFAULT))
	ch.timer.wait_time = interval
	add_child(ch.timer)
	ch.timer.timeout.connect(_on_poll_timer.bind(id))

	_channels[id] = ch
	_transition_state(id, STATE_CONNECTING)
	ch.timer.start()


func _load_mock_payloads(agent_id: String) -> Array:
	# Per ADR-0008: cycle JSON arrays from assets/data/mock/[agent_id].json
	var path: String = "res://assets/data/mock/%s.json" % agent_id
	if not FileAccess.file_exists(path):
		# Inline default cycle — keeps prototype runnable without authoring mock files
		return [
			"{\"content\":\"working on it\",\"stop_reason\":null}",
			"{\"content\":\"still thinking\",\"stop_reason\":null}",
			"{\"content\":\"here is your answer\",\"stop_reason\":\"end_turn\"}",
			"{\"content\":\"\",\"stop_reason\":\"error\",\"error\":{\"type\":\"rate_limit\"}}",
		]
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var raw: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Array:
		return parsed
	push_warning("[DataBridge] Mock file %s did not contain a JSON array" % path)
	return []


func _on_poll_timer(agent_id: String) -> void:
	var ch: AgentChannel = _channels.get(agent_id)
	if ch == null:
		return
	if ch.in_flight:
		# Don't pile up requests; reschedule
		_reschedule(agent_id)
		return
	if ConfigurationLoader.is_mock():
		_dispatch_mock(agent_id)
	else:
		_dispatch_http(agent_id)


func _dispatch_mock(agent_id: String) -> void:
	var ch: AgentChannel = _channels[agent_id]
	if ch.mock_cycle.is_empty():
		_handle_failure(agent_id, "empty mock cycle")
		return
	var payload: String = str(ch.mock_cycle[ch.mock_index])
	ch.mock_index = (ch.mock_index + 1) % ch.mock_cycle.size()
	# Simulate occasional failure (every 7th request) to exercise backoff
	var simulated_failure: bool = (ch.mock_index % 7) == 0
	if simulated_failure:
		_handle_failure(agent_id, "simulated mock failure")
	else:
		_handle_success(agent_id, payload)


func _dispatch_http(agent_id: String) -> void:
	var ch: AgentChannel = _channels[agent_id]
	var endpoint: String = String(ch.config.get("endpoint", ""))
	if endpoint.is_empty():
		_handle_failure(agent_id, "no endpoint configured")
		return
	var token: String = String(ch.config.get("token", ""))
	var headers: PackedStringArray = PackedStringArray()
	if not token.is_empty():
		headers.append("x-api-key: %s" % token)
		headers.append("anthropic-version: 2023-06-01")
	headers.append("content-type: application/json")

	# Sprint 1 stub body — cheapest viable Claude API call.
	# Real Sprint 1 work: discover what shape we want here.
	var body_dict: Dictionary = {
		"model": String(ch.config.get("model", "claude-3-5-haiku-latest")),
		"max_tokens": 1,
		"messages": [{"role": "user", "content": "ping"}]
	}
	var body: String = JSON.stringify(body_dict)
	ch.in_flight = true
	var err: int = ch.http.request(endpoint, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		ch.in_flight = false
		_handle_failure(agent_id, "request() returned err=%d" % err)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, agent_id: String) -> void:
	var ch: AgentChannel = _channels.get(agent_id)
	if ch == null:
		return
	ch.in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_handle_failure(agent_id, "result=%d" % result)
		return
	if response_code < 200 or response_code >= 300:
		_handle_failure(agent_id, "http %d" % response_code)
		return
	var payload: String = body.get_string_from_utf8()
	_handle_success(agent_id, payload)


func _handle_success(agent_id: String, payload: String) -> void:
	var ch: AgentChannel = _channels[agent_id]
	ch.failure_count = 0
	ch.current_backoff = 0.0
	_transition_state(agent_id, STATE_CONNECTED)
	agent_response_received.emit(agent_id, payload)
	_reschedule(agent_id)


func _handle_failure(agent_id: String, reason: String) -> void:
	var ch: AgentChannel = _channels[agent_id]
	ch.failure_count += 1
	push_warning("[DataBridge:%s] failure #%d — %s" % [agent_id, ch.failure_count, reason])

	# State transitions per ADR-0001
	if ch.failure_count >= DISCONNECTED_AFTER_FAILURES:
		_transition_state(agent_id, STATE_DISCONNECTED)
	elif ch.failure_count >= STALE_AFTER_FAILURES:
		_transition_state(agent_id, STATE_STALE)
	# failure_count == 1 stays CONNECTED (grace per ADR-0001)

	# Exponential backoff, cap 30s
	var base: float = float(ch.config.get("poll_interval", POLL_INTERVAL_DEFAULT))
	ch.current_backoff = min(base * pow(2.0, ch.failure_count - 1), MAX_BACKOFF_SEC)
	_reschedule(agent_id)


func _reschedule(agent_id: String) -> void:
	var ch: AgentChannel = _channels[agent_id]
	var wait: float
	if ch.current_backoff > 0.0:
		wait = ch.current_backoff
	else:
		wait = float(ch.config.get("poll_interval", POLL_INTERVAL_DEFAULT))
	ch.timer.wait_time = wait
	ch.timer.start()


func _transition_state(agent_id: String, new_state: String) -> void:
	var ch: AgentChannel = _channels[agent_id]
	if ch.connection_state == new_state:
		return
	var prev: String = ch.connection_state
	ch.connection_state = new_state
	print("[DataBridge:%s] %s → %s" % [agent_id, prev, new_state])
	agent_connection_changed.emit(agent_id, new_state)


# Public accessors (Tier 3 read-only per ADR-0006)

func get_connection_state(agent_id: String) -> String:
	var ch: AgentChannel = _channels.get(agent_id)
	if ch == null:
		return STATE_UNINITIALIZED
	return ch.connection_state


func get_failure_count(agent_id: String) -> int:
	var ch: AgentChannel = _channels.get(agent_id)
	if ch == null:
		return 0
	return ch.failure_count
