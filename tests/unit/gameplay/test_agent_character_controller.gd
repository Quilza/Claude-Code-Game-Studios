extends GutTest
##
## AgentCharacterController — unit tests.
##
## Focuses on the testable architecture: ASM dispatch, behavioral state
## machine, animation name resolution. Visual / pathfinding / wandering
## tests deferred to follow-up commits with sprite assets + NavigationRegion2D.
##

const ACCScript = preload("res://src/gameplay/agent_character_controller.gd")
const AsmScript = preload("res://src/integration/agent_state_machine.gd")


# ─── Helpers ─────────────────────────────────────────────────────────────────

func _make_acc(agent_id: String = "test_agent") -> AgentCharacterController:
	var acc: AgentCharacterController = ACCScript.new()
	acc.agent_id = agent_id
	return acc


# ─── ASM_STATE_TO_ANIM mapping ───────────────────────────────────────────────

func test_asm_state_to_anim_has_all_four_states() -> void:
	var mapping: Dictionary = ACCScript.ASM_STATE_TO_ANIM
	assert_true(mapping.has(AsmScript.STATE_IDLE))
	assert_true(mapping.has(AsmScript.STATE_WORKING))
	assert_true(mapping.has(AsmScript.STATE_COMPLETED))
	assert_true(mapping.has(AsmScript.STATE_ERRORED))


func test_asm_state_to_anim_idle_maps_to_idle_anim() -> void:
	assert_eq(ACCScript.ASM_STATE_TO_ANIM[AsmScript.STATE_IDLE], &"idle")


func test_asm_state_to_anim_working_maps_to_working_anim() -> void:
	assert_eq(ACCScript.ASM_STATE_TO_ANIM[AsmScript.STATE_WORKING], &"working")


# ─── Behavioral state enum ───────────────────────────────────────────────────

func test_behavioral_state_initial_is_uninitialized() -> void:
	var acc: AgentCharacterController = _make_acc()
	assert_eq(acc.get_behavioral_state(), ACCScript.BehavioralState.UNINITIALIZED)
	acc.free()


func test_force_state_to_idle_wandering() -> void:
	var acc: AgentCharacterController = _make_acc()
	add_child(acc)
	acc._test_force_state(ACCScript.BehavioralState.IDLE_WANDERING)
	assert_eq(acc.get_behavioral_state(), ACCScript.BehavioralState.IDLE_WANDERING)
	acc.queue_free()


# ─── ASM dispatch via signal ─────────────────────────────────────────────────

func test_asm_state_changed_to_working_enters_working() -> void:
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	acc._test_force_state(ACCScript.BehavioralState.IDLE_WANDERING)
	# Handler arg order (Godot 4 .bind() puts bound arg last):
	#   (fired_id, new_state, previous, bound_id)
	acc._on_asm_state_changed("agent_a", AsmScript.STATE_WORKING, AsmScript.STATE_IDLE, "agent_a")
	assert_eq(acc.get_behavioral_state(), ACCScript.BehavioralState.WORKING)
	acc.queue_free()


func test_asm_state_changed_to_completed_enters_completed_beat() -> void:
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	acc._test_force_state(ACCScript.BehavioralState.WORKING)
	acc._on_asm_state_changed("agent_a", AsmScript.STATE_COMPLETED, AsmScript.STATE_WORKING, "agent_a")
	assert_eq(acc.get_behavioral_state(), ACCScript.BehavioralState.COMPLETED_BEAT)
	acc.queue_free()


func test_asm_state_changed_to_errored_enters_errored() -> void:
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	acc._test_force_state(ACCScript.BehavioralState.WORKING)
	acc._on_asm_state_changed("agent_a", AsmScript.STATE_ERRORED, AsmScript.STATE_WORKING, "agent_a")
	assert_eq(acc.get_behavioral_state(), ACCScript.BehavioralState.ERRORED)
	acc.queue_free()


# ─── .bind(agent_id) Tier 2 filter ───────────────────────────────────────────

func test_state_changed_for_different_agent_is_ignored() -> void:
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	acc._test_force_state(ACCScript.BehavioralState.IDLE_WANDERING)
	# Different agent_id — must be ignored.
	# fired_id="different_agent", bound_id="agent_a" → filter rejects.
	acc._on_asm_state_changed("different_agent", AsmScript.STATE_WORKING, AsmScript.STATE_IDLE, "agent_a")
	assert_eq(acc.get_behavioral_state(), ACCScript.BehavioralState.IDLE_WANDERING)
	acc.queue_free()


# ─── WORKING signal during COMPLETED_BEAT is queued (Rule 4) ─────────────────

func test_working_signal_during_completed_beat_is_queued_not_immediate() -> void:
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	acc._test_force_state(ACCScript.BehavioralState.COMPLETED_BEAT)
	acc._on_asm_state_changed("agent_a", AsmScript.STATE_WORKING, AsmScript.STATE_COMPLETED, "agent_a")
	# Should still be in COMPLETED_BEAT with queued flag set.
	assert_eq(acc.get_behavioral_state(), ACCScript.BehavioralState.COMPLETED_BEAT)
	assert_true(acc._queued_working_during_beat)
	acc.queue_free()


# ─── last_asm_state accessor ─────────────────────────────────────────────────

func test_last_asm_state_tracks_received_signal() -> void:
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	acc._on_asm_state_changed("agent_a", AsmScript.STATE_WORKING, AsmScript.STATE_IDLE, "agent_a")
	assert_eq(acc.get_last_asm_state(), AsmScript.STATE_WORKING)
	acc._on_asm_state_changed("agent_a", AsmScript.STATE_ERRORED, AsmScript.STATE_WORKING, "agent_a")
	assert_eq(acc.get_last_asm_state(), AsmScript.STATE_ERRORED)
	acc.queue_free()


# ─── Tuning constants ────────────────────────────────────────────────────────

func test_completed_beat_duration_default_is_2_sec() -> void:
	assert_almost_eq(ACCScript.COMPLETED_BEAT_DURATION_SEC_DEFAULT, 2.0, 0.0001)


func test_error_timeout_default_is_30_sec() -> void:
	assert_almost_eq(ACCScript.ERROR_TIMEOUT_SEC_DEFAULT, 30.0, 0.0001)


func test_resigned_idle_speed_multiplier_is_0_6() -> void:
	assert_almost_eq(ACCScript.RESIGNED_IDLE_SPEED_MULTIPLIER, 0.6, 0.0001)


# ─── Phase 1 movement substrate ──────────────────────────────────────────────

func test_v_base_speed_is_40_px_per_sec() -> void:
	assert_almost_eq(ACCScript.V_BASE_PX_PER_SEC, 40.0, 0.0001)


func test_arrival_tolerance_is_1_px() -> void:
	assert_almost_eq(ACCScript.ARRIVAL_TOLERANCE_PX, 1.0, 0.0001)


func test_current_speed_is_v_base_when_not_resigned_idle() -> void:
	# Arrange
	var acc: AgentCharacterController = _make_acc()
	add_child(acc)
	# Act / Assert — default state is not resigned_idle
	assert_almost_eq(acc._current_speed_px_per_sec(), ACCScript.V_BASE_PX_PER_SEC, 0.0001)
	acc.queue_free()


func test_current_speed_is_24_px_per_sec_when_resigned_idle() -> void:
	# Arrange
	var acc: AgentCharacterController = _make_acc()
	add_child(acc)
	# Act — flip the resigned_idle flag directly (private but test-accessible)
	acc._resigned_idle = true
	# Assert — V_BASE (40) * RESIGNED_IDLE_SPEED_MULTIPLIER (0.6) = 24.0
	assert_almost_eq(acc._current_speed_px_per_sec(), 24.0, 0.0001)
	acc.queue_free()


func test_set_walk_target_sets_flag_and_position() -> void:
	# Arrange
	var acc: AgentCharacterController = _make_acc()
	add_child(acc)
	assert_false(acc.has_walk_target(), "Precondition: no walk target initially")
	# Act
	acc._set_walk_target(Vector2(100.0, 50.0))
	# Assert
	assert_true(acc.has_walk_target())
	assert_eq(acc.get_walk_target(), Vector2(100.0, 50.0))
	acc.queue_free()


func test_physics_process_no_target_is_noop() -> void:
	# Arrange — no walk target set.
	var acc: AgentCharacterController = _make_acc()
	add_child(acc)
	acc.position = Vector2(10.0, 10.0)
	# Act
	acc._physics_process(0.1)
	# Assert — position unchanged.
	assert_eq(acc.position, Vector2(10.0, 10.0))
	acc.queue_free()


func test_physics_process_step_advances_toward_target() -> void:
	# Arrange — target 100px to the right of current position.
	# At V_BASE = 40 px/sec, a 0.1s step should advance 4px.
	var acc: AgentCharacterController = _make_acc()
	add_child(acc)
	acc.position = Vector2.ZERO
	acc._set_walk_target(Vector2(100.0, 0.0))
	# Act
	acc._physics_process(0.1)
	# Assert — moved ~4px toward target, still has target.
	assert_almost_eq(acc.position.x, 4.0, 0.001)
	assert_eq(acc.position.y, 0.0)
	assert_true(acc.has_walk_target(), "Target not yet reached")
	acc.queue_free()


func test_physics_process_step_within_tolerance_snaps_and_clears() -> void:
	# Arrange — target 0.5px away; one step trivially overshoots tolerance.
	var acc: AgentCharacterController = _make_acc()
	add_child(acc)
	acc.position = Vector2.ZERO
	acc._set_walk_target(Vector2(0.5, 0.0))
	# Act
	acc._physics_process(0.1)
	# Assert — snapped to target, flag cleared.
	assert_eq(acc.position, Vector2(0.5, 0.0))
	assert_false(acc.has_walk_target())
	acc.queue_free()


func test_physics_process_step_overshoot_snaps_to_target() -> void:
	# Arrange — target 1px away; a 0.1s step at V_BASE=40 would move 4px,
	# which would overshoot. _physics_process must snap, not overshoot.
	var acc: AgentCharacterController = _make_acc()
	add_child(acc)
	acc.position = Vector2.ZERO
	acc._set_walk_target(Vector2(1.5, 0.0))
	# Act
	acc._physics_process(0.1)
	# Assert
	assert_eq(acc.position, Vector2(1.5, 0.0))
	assert_false(acc.has_walk_target())
	acc.queue_free()
