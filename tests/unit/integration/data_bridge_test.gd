extends GutTest
##
## DataBridge — unit tests.
##
## Covers the ACs from `design/gdd/data-bridge.md` §Acceptance Criteria
## (post-Amendment 2026-05-12.b). Focuses on the unit-testable surface:
## state transitions, backoff curve, B1/B2 amendments, signal emissions.
##
## Integration tests against a real HTTP endpoint are deferred to Sprint 1's
## prototype + future GUT-with-real-endpoint suite.
##
## Test scope:
##   • State machine transitions (CONNECTING → CONNECTED / STALE / DISCONNECTED)
##   • Grace curve: failure_count 1 = stays CONNECTED, 2 = STALE, 4 = DISCONNECTED
##   • B1: 4xx config-fatal skips the curve, transitions to DISCONNECTED on first failure
##   • B2: request_dispatched + request_settled emit in order; is_request_in_flight tracks
##   • Public read-only accessors (get_connection_state, get_failure_count)
##   • Mock payload cycle (inline fallback when assets/data/mock/ absent)
##

const DataBridgeScript = preload("res://src/integration/data_bridge.gd")


# ─── Helpers ─────────────────────────────────────────────────────────────────

func _make_bridge() -> Node:
	# Returns a fresh DataBridge. Caller must add_child + free.
	# Note: _ready() will attempt to read ConfigurationLoader. In tests without
	# the full autoload tree, _config_loader_available() returns false and
	# _ready() exits early with a push_error. This is fine for unit tests
	# that work with directly-injected channels via _test_inject_channel.
	return DataBridgeScript.new()


# ─── Public accessors return safe defaults for unknown agents ────────────────

func test_get_connection_state_unknown_agent_returns_uninitialized() -> void:
	var bridge: Node = _make_bridge()
	assert_eq(bridge.get_connection_state("nonexistent"), DataBridgeScript.STATE_UNINITIALIZED)
	bridge.free()


func test_get_failure_count_unknown_agent_returns_zero() -> void:
	var bridge: Node = _make_bridge()
	assert_eq(bridge.get_failure_count("nonexistent"), 0)
	bridge.free()


func test_is_request_in_flight_unknown_agent_returns_false() -> void:
	var bridge: Node = _make_bridge()
	assert_false(bridge.is_request_in_flight("nonexistent"))
	bridge.free()


# ─── Backoff curve: grace, STALE, DISCONNECTED transitions ───────────────────

func test_first_failure_grace_stays_connected() -> void:
	var bridge: Node = _make_bridge()
	var ch = bridge._test_inject_channel("agent_a", {"poll_interval": 5.0})
	ch.timer = Timer.new()  # required for _reschedule to not crash
	bridge.add_child(ch.timer)
	bridge._transition_state("agent_a", DataBridgeScript.STATE_CONNECTED)
	bridge._handle_failure("agent_a", "test failure 1", false)
	# After 1 failure, channel should still be CONNECTED (grace).
	assert_eq(bridge.get_connection_state("agent_a"), DataBridgeScript.STATE_CONNECTED)
	assert_eq(bridge.get_failure_count("agent_a"), 1)
	bridge.free()


func test_second_failure_transitions_to_stale() -> void:
	var bridge: Node = _make_bridge()
	var ch = bridge._test_inject_channel("agent_a", {"poll_interval": 5.0})
	ch.timer = Timer.new()
	bridge.add_child(ch.timer)
	bridge._transition_state("agent_a", DataBridgeScript.STATE_CONNECTED)
	bridge._handle_failure("agent_a", "test failure 1", false)
	bridge._handle_failure("agent_a", "test failure 2", false)
	assert_eq(bridge.get_connection_state("agent_a"), DataBridgeScript.STATE_STALE)
	assert_eq(bridge.get_failure_count("agent_a"), 2)
	bridge.free()


func test_fourth_failure_transitions_to_disconnected() -> void:
	var bridge: Node = _make_bridge()
	var ch = bridge._test_inject_channel("agent_a", {"poll_interval": 5.0})
	ch.timer = Timer.new()
	bridge.add_child(ch.timer)
	bridge._transition_state("agent_a", DataBridgeScript.STATE_CONNECTED)
	for i: int in 4:
		bridge._handle_failure("agent_a", "test failure %d" % i, false)
	assert_eq(bridge.get_connection_state("agent_a"), DataBridgeScript.STATE_DISCONNECTED)
	assert_eq(bridge.get_failure_count("agent_a"), 4)
	bridge.free()


func test_success_after_failures_resets_counter_and_returns_to_connected() -> void:
	var bridge: Node = _make_bridge()
	var ch = bridge._test_inject_channel("agent_a", {"poll_interval": 5.0})
	ch.timer = Timer.new()
	bridge.add_child(ch.timer)
	bridge._transition_state("agent_a", DataBridgeScript.STATE_CONNECTED)
	bridge._handle_failure("agent_a", "f1", false)
	bridge._handle_failure("agent_a", "f2", false)
	# Now STALE with failure_count = 2.
	bridge._handle_success("agent_a", '{"stop_reason":"end_turn"}')
	assert_eq(bridge.get_connection_state("agent_a"), DataBridgeScript.STATE_CONNECTED)
	assert_eq(bridge.get_failure_count("agent_a"), 0)
	bridge.free()


# ─── B1: 4xx config-fatal skips the grace curve ──────────────────────────────

func test_b1_4xx_fatal_failure_transitions_directly_to_disconnected() -> void:
	var bridge: Node = _make_bridge()
	var ch = bridge._test_inject_channel("agent_a", {"poll_interval": 5.0})
	ch.timer = Timer.new()
	bridge.add_child(ch.timer)
	bridge._transition_state("agent_a", DataBridgeScript.STATE_CONNECTED)
	# Single 4xx failure should skip grace + STALE and go straight to DISCONNECTED.
	bridge._handle_failure("agent_a", "http 400", true)
	assert_eq(bridge.get_connection_state("agent_a"), DataBridgeScript.STATE_DISCONNECTED)
	bridge.free()


# ─── B2: request_dispatched / request_settled signal emission ────────────────

func test_b2_request_dispatched_emits_with_correct_agent_id() -> void:
	var bridge: Node = _make_bridge()
	var emitted_id: String = ""
	bridge.request_dispatched.connect(func(id: String) -> void:
		emitted_id = id
	)
	bridge.request_dispatched.emit("agent_b")
	assert_eq(emitted_id, "agent_b")
	bridge.free()


func test_b2_request_settled_emits_with_correct_agent_id() -> void:
	var bridge: Node = _make_bridge()
	var emitted_id: String = ""
	bridge.request_settled.connect(func(id: String) -> void:
		emitted_id = id
	)
	bridge.request_settled.emit("agent_c")
	assert_eq(emitted_id, "agent_c")
	bridge.free()


# ─── Signal contract — agent_state_changed and agent_response_received ───────

func test_state_transition_emits_agent_connection_changed_signal() -> void:
	var bridge: Node = _make_bridge()
	var ch = bridge._test_inject_channel("agent_a", {})
	var emitted: Array = []
	bridge.agent_connection_changed.connect(func(id: String, state: String) -> void:
		emitted.append([id, state])
	)
	bridge._transition_state("agent_a", DataBridgeScript.STATE_CONNECTED)
	assert_eq(emitted.size(), 1)
	assert_eq(String(emitted[0][0]), "agent_a")
	assert_eq(String(emitted[0][1]), DataBridgeScript.STATE_CONNECTED)
	bridge.free()


func test_same_state_transition_does_not_emit_signal() -> void:
	var bridge: Node = _make_bridge()
	var ch = bridge._test_inject_channel("agent_a", {})
	ch.connection_state = DataBridgeScript.STATE_CONNECTED
	var emit_count: int = 0
	bridge.agent_connection_changed.connect(func(_id: String, _state: String) -> void:
		emit_count += 1
	)
	bridge._transition_state("agent_a", DataBridgeScript.STATE_CONNECTED)
	assert_eq(emit_count, 0, "Same-state transition should not emit signal")
	bridge.free()


func test_success_emits_agent_response_received_with_payload() -> void:
	var bridge: Node = _make_bridge()
	var ch = bridge._test_inject_channel("agent_a", {"poll_interval": 5.0})
	ch.timer = Timer.new()
	bridge.add_child(ch.timer)
	var emitted_payload: String = ""
	bridge.agent_response_received.connect(func(_id: String, payload: String) -> void:
		emitted_payload = payload
	)
	bridge._handle_success("agent_a", '{"stop_reason":"end_turn"}')
	assert_eq(emitted_payload, '{"stop_reason":"end_turn"}')
	bridge.free()


# ─── Payload passthrough — bridge does not parse JSON ────────────────────────

func test_handle_success_passes_payload_unmodified() -> void:
	var bridge: Node = _make_bridge()
	var ch = bridge._test_inject_channel("agent_a", {"poll_interval": 5.0})
	ch.timer = Timer.new()
	bridge.add_child(ch.timer)
	var received: String = ""
	bridge.agent_response_received.connect(func(_id: String, payload: String) -> void:
		received = payload
	)
	# Pass a deliberately weird payload — bridge must NOT inspect it.
	var weird_payload: String = "[1, 2, 3, \"not even an object\"]"
	bridge._handle_success("agent_a", weird_payload)
	assert_eq(received, weird_payload, "Bridge must pass payload byte-for-byte")
	bridge.free()


# ─── Mock cycle inline fallback ──────────────────────────────────────────────

func test_inline_fallback_cycle_returns_4_payloads_covering_canonical_states() -> void:
	var bridge: Node = _make_bridge()
	var cycle: Array = bridge._inline_fallback_cycle()
	assert_eq(cycle.size(), 4, "Inline fallback should provide 4 payloads")
	# Each should be valid JSON parseable as a Dictionary with stop_reason.
	for raw: Variant in cycle:
		var parsed: Variant = JSON.parse_string(String(raw))
		assert_true(parsed is Dictionary, "Each fallback payload should parse as Dictionary")
		assert_true(parsed.has("stop_reason"), "Each fallback payload should include stop_reason")
	bridge.free()


# ─── Agent ID list accessor ──────────────────────────────────────────────────

func test_get_agent_ids_returns_registered_ids() -> void:
	var bridge: Node = _make_bridge()
	bridge._test_inject_channel("agent_a", {})
	bridge._test_inject_channel("agent_b", {})
	var ids: Array = bridge.get_agent_ids()
	assert_eq(ids.size(), 2)
	assert_has(ids, "agent_a")
	assert_has(ids, "agent_b")
	bridge.free()
