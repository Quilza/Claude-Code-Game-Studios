extends GutTest
##
## AgentStateMachine — unit tests.
##
## Covers ACs from `design/gdd/agent-state-machine.md` §8. Maps directly to
## the AC numbering. Uses tests/helpers/asm_fixtures.gd payload factories
## (committed earlier in commit a04ec85).
##

const AsmScript = preload("res://src/integration/agent_state_machine.gd")
const AsmFixtures = preload("res://tests/helpers/asm_fixtures.gd")


# ─── Helpers ─────────────────────────────────────────────────────────────────

func _make_asm() -> Node:
	# Returns a fresh AgentStateMachine. Tests use _test_register_agent
	# to bypass ConfigLoader-based registration.
	return AsmScript.new()


# ─── §8.1 State derivation (Rule 4 / ADR-0007 mapping) ───────────────────────

func test_stop_reason_end_turn_maps_to_completed() -> void:
	# AC-1
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	asm._on_agent_response_received("a1", AsmFixtures.payload_end_turn())
	assert_eq(asm.get_agent_state("a1"), AsmScript.STATE_COMPLETED)
	asm.queue_free()


func test_stop_reason_max_tokens_maps_to_completed() -> void:
	# AC-2
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	asm._on_agent_response_received("a1", AsmFixtures.payload_max_tokens())
	assert_eq(asm.get_agent_state("a1"), AsmScript.STATE_COMPLETED)
	asm.queue_free()


func test_stop_reason_stop_sequence_maps_to_completed() -> void:
	# AC-3
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	asm._on_agent_response_received("a1", AsmFixtures.payload_stop_sequence())
	assert_eq(asm.get_agent_state("a1"), AsmScript.STATE_COMPLETED)
	asm.queue_free()


func test_stop_reason_tool_use_maps_to_working() -> void:
	# AC-4
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	asm._on_agent_response_received("a1", AsmFixtures.payload_tool_use())
	assert_eq(asm.get_agent_state("a1"), AsmScript.STATE_WORKING)
	asm.queue_free()


func test_stop_reason_pause_turn_maps_to_working() -> void:
	# AC-5
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	asm._on_agent_response_received("a1", AsmFixtures.payload_pause_turn())
	assert_eq(asm.get_agent_state("a1"), AsmScript.STATE_WORKING)
	asm.queue_free()


func test_stop_reason_refusal_maps_to_errored() -> void:
	# AC-6
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	asm._on_agent_response_received("a1", AsmFixtures.payload_refusal())
	assert_eq(asm.get_agent_state("a1"), AsmScript.STATE_ERRORED)
	asm.queue_free()


func test_unknown_stop_reason_falls_back_to_completed() -> void:
	# AC-7
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	asm._on_agent_response_received("a1", AsmFixtures.payload_unknown_stop_reason())
	assert_eq(asm.get_agent_state("a1"), AsmScript.UNKNOWN_STOP_REASON_FALLBACK)
	assert_eq(asm.get_agent_state("a1"), AsmScript.STATE_COMPLETED, "Fallback is completed")
	asm.queue_free()


func test_malformed_payload_maps_to_errored() -> void:
	# AC-8
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	asm._on_agent_response_received("a1", AsmFixtures.payload_malformed())
	assert_eq(asm.get_agent_state("a1"), AsmScript.STATE_ERRORED)
	asm.queue_free()


func test_error_envelope_maps_to_errored_and_uses_request_id() -> void:
	# AC-9
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	asm._on_agent_response_received("a1", AsmFixtures.payload_error_envelope())
	assert_eq(asm.get_agent_state("a1"), AsmScript.STATE_ERRORED)
	var stats: Dictionary = asm.get_agent_stats("a1")
	assert_eq(String(stats["last_payload_id"]), "req_test_error_envelope", "Error envelope's request_id used as last_payload_id")
	asm.queue_free()


# ─── §8.2 In-flight tracking (Rule 5) ────────────────────────────────────────

func test_request_dispatched_transitions_to_working() -> void:
	# AC-10
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	asm._on_request_dispatched("a1")
	assert_eq(asm.get_agent_state("a1"), AsmScript.STATE_WORKING)
	asm.queue_free()


func test_request_settled_without_response_transitions_to_errored() -> void:
	# AC-11
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	asm._on_request_dispatched("a1")
	# No agent_response_received in between
	asm._on_request_settled("a1")
	assert_eq(asm.get_agent_state("a1"), AsmScript.STATE_ERRORED)
	asm.queue_free()


# ─── §8.3 Transient state and decay (Rule 6) ─────────────────────────────────

func test_errored_does_not_auto_decay() -> void:
	# AC-14 — errored is persistent.
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	asm._on_agent_response_received("a1", AsmFixtures.payload_refusal())
	assert_eq(asm.get_agent_state("a1"), AsmScript.STATE_ERRORED)
	# No decay timer should be scheduled.
	assert_false(asm._decay_timers.has("a1"), "No decay timer scheduled for errored state")
	asm.queue_free()


func test_new_payload_mid_decay_kills_timer_and_applies_new_state() -> void:
	# AC-13
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	asm._on_agent_response_received("a1", AsmFixtures.payload_end_turn())
	assert_true(asm._decay_timers.has("a1"), "Decay timer scheduled after entering completed")
	# New payload arrives mid-decay
	asm._on_agent_response_received("a1", AsmFixtures.payload_tool_use())
	assert_eq(asm.get_agent_state("a1"), AsmScript.STATE_WORKING)
	assert_false(asm._decay_timers.has("a1"), "Decay timer cancelled on new state")
	asm.queue_free()


# ─── §8.4 Signal emission (Rules 9, 10) ──────────────────────────────────────

func test_state_change_emits_agent_state_changed_with_3args() -> void:
	# AC-15
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	var emitted: Array = []
	asm.agent_state_changed.connect(func(id: String, new_state: String, previous: String) -> void:
		emitted.append([id, new_state, previous])
	)
	asm._on_agent_response_received("a1", AsmFixtures.payload_end_turn())
	assert_eq(emitted.size(), 1)
	assert_eq(String(emitted[0][0]), "a1")
	assert_eq(String(emitted[0][1]), AsmScript.STATE_COMPLETED)
	assert_eq(String(emitted[0][2]), AsmScript.STATE_IDLE, "previous_state should be idle")
	asm.queue_free()


func test_same_state_transition_does_not_emit() -> void:
	# AC-16. NOTE: GDScript 4.x lambdas can read but not write outer-scope
	# scalars. Use single-element Array as a mutation holder.
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	asm._on_agent_response_received("a1", AsmFixtures.payload_tool_use())  # → working
	var emit_count_ref: Array[int] = [0]
	asm.agent_state_changed.connect(func(_id: String, _new: String, _prev: String) -> void:
		emit_count_ref[0] += 1
	)
	asm._on_agent_response_received("a1", AsmFixtures.payload_tool_use())
	assert_eq(emit_count_ref[0], 0, "Same-state transition does not emit signal")
	asm.queue_free()


func test_task_completed_emits_on_entry_to_completed() -> void:
	# AC-17
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	var emitted_id_ref: Array[String] = [""]
	asm.task_completed.connect(func(id: String) -> void:
		emitted_id_ref[0] = id
	)
	asm._on_agent_response_received("a1", AsmFixtures.payload_end_turn())
	assert_eq(emitted_id_ref[0], "a1")
	asm.queue_free()


func test_task_completed_emits_from_working_to_completed() -> void:
	# AC-17 — emits from any prior state.
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	asm._on_agent_response_received("a1", AsmFixtures.payload_tool_use())  # → working
	var emit_count_ref: Array[int] = [0]
	asm.task_completed.connect(func(_id: String) -> void:
		emit_count_ref[0] += 1
	)
	asm._on_agent_response_received("a1", AsmFixtures.payload_end_turn())  # → completed
	assert_eq(emit_count_ref[0], 1, "task_completed emits on working → completed")
	asm.queue_free()


# ─── §8.5 Public read-only API (Rule 15) ─────────────────────────────────────

func test_get_agent_state_unknown_returns_idle() -> void:
	# AC-19
	var asm: Node = _make_asm()
	assert_eq(asm.get_agent_state("nonexistent"), AsmScript.STATE_IDLE)
	asm.queue_free()


func test_get_agent_stats_unknown_returns_empty_dict() -> void:
	# AC-20
	var asm: Node = _make_asm()
	assert_eq(asm.get_agent_stats("nonexistent"), {})
	asm.queue_free()


func test_get_agent_stats_returns_full_9_field_schema() -> void:
	# AC-20
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	var stats: Dictionary = asm.get_agent_stats("a1")
	assert_true(stats.has("current_state"))
	assert_true(stats.has("tasks_completed"))
	assert_true(stats.has("errored_count"))
	assert_true(stats.has("last_state_change_ms"))
	assert_true(stats.has("last_payload_id"))
	assert_true(stats.has("last_stop_reason"))
	assert_true(stats.has("total_input_tokens"))
	assert_true(stats.has("total_output_tokens"))
	assert_true(stats.has("session_start_ms"))
	asm.queue_free()


func test_get_bunker_summary_aggregates_counts() -> void:
	# AC-21
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	asm._test_register_agent("a2")
	asm._test_register_agent("a3")
	# a1 → working
	asm._on_agent_response_received("a1", AsmFixtures.payload_tool_use())
	# a2 → errored
	asm._on_agent_response_received("a2", AsmFixtures.payload_refusal())
	# a3 stays idle
	var summary: Dictionary = asm.get_bunker_summary()
	assert_eq(int(summary["idle_count"]), 1)
	assert_eq(int(summary["working_count"]), 1)
	assert_eq(int(summary["errored_count"]), 1)
	assert_eq(int(summary["completed_count"]), 0)
	assert_eq(int(summary["total_count"]), 3)
	asm.queue_free()


func test_is_agent_known_returns_true_for_registered() -> void:
	# AC-22
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	assert_true(asm.is_agent_known("a1"))
	assert_false(asm.is_agent_known("nope"))
	asm.queue_free()


# ─── §8.6 Stats accumulation (Rules 13) ──────────────────────────────────────

func test_tasks_completed_increments_on_entry_to_completed() -> void:
	# AC-23
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	asm._on_agent_response_received("a1", AsmFixtures.payload_end_turn())
	assert_eq(int(asm.get_agent_stats("a1")["tasks_completed"]), 1)
	asm.queue_free()


func test_errored_count_increments_on_entry_to_errored() -> void:
	# AC-24
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	asm._on_agent_response_received("a1", AsmFixtures.payload_refusal())
	assert_eq(int(asm.get_agent_stats("a1")["errored_count"]), 1)
	asm.queue_free()


func test_token_counters_accumulate_per_payload() -> void:
	# AC-25
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	asm._on_agent_response_received("a1", AsmFixtures.payload_end_turn_with_usage(10, 5))
	asm._on_agent_response_received("a1", AsmFixtures.payload_end_turn_with_usage(8, 3))
	var stats: Dictionary = asm.get_agent_stats("a1")
	assert_eq(int(stats["total_input_tokens"]), 18)
	assert_eq(int(stats["total_output_tokens"]), 8)
	asm.queue_free()


func test_missing_usage_block_contributes_zero() -> void:
	# AC-25 negative case
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	asm._on_agent_response_received("a1", AsmFixtures.payload_missing_usage())
	var stats: Dictionary = asm.get_agent_stats("a1")
	assert_eq(int(stats["total_input_tokens"]), 0)
	assert_eq(int(stats["total_output_tokens"]), 0)
	asm.queue_free()


# ─── §8.8 Edge cases ─────────────────────────────────────────────────────────

func test_empty_payload_treated_as_parse_failure() -> void:
	# AC-33
	var asm: Node = _make_asm()
	asm._test_register_agent("a1")
	asm._on_agent_response_received("a1", "")
	assert_eq(asm.get_agent_state("a1"), AsmScript.STATE_ERRORED)
	asm.queue_free()


func test_corrupt_persisted_stats_blob_not_dict_zero_inits() -> void:
	# AC-30 variant (a) — not a Dictionary
	var asm: Node = _make_asm()
	assert_false(asm._is_valid_stats_blob("not a dict"))
	assert_false(asm._is_valid_stats_blob(42))
	asm.queue_free()


func test_corrupt_persisted_stats_blob_missing_field_zero_inits() -> void:
	# AC-30 variant (b) — missing required field
	var asm: Node = _make_asm()
	var partial: Dictionary = {"tasks_completed": 0}  # missing other required keys
	assert_false(asm._is_valid_stats_blob(partial))
	asm.queue_free()


func test_corrupt_persisted_stats_blob_type_mismatch_zero_inits() -> void:
	# AC-30 variant (c) — wrong type
	var asm: Node = _make_asm()
	var corrupt: Dictionary = AsmFixtures.stats_blob_corrupt()
	assert_false(asm._is_valid_stats_blob(corrupt))
	asm.queue_free()


func test_valid_stats_blob_passes_check() -> void:
	# AC-30 positive
	var asm: Node = _make_asm()
	var valid: Dictionary = AsmFixtures.stats_blob_default()
	assert_true(asm._is_valid_stats_blob(valid))
	asm.queue_free()
