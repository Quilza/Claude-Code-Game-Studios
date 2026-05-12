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
	# Simulate Tier 2 bound signal: bound_id, fired_id, new_state, previous
	acc._on_asm_state_changed("agent_a", "agent_a", AsmScript.STATE_WORKING, AsmScript.STATE_IDLE)
	assert_eq(acc.get_behavioral_state(), ACCScript.BehavioralState.WORKING)
	acc.queue_free()


func test_asm_state_changed_to_completed_enters_completed_beat() -> void:
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	acc._test_force_state(ACCScript.BehavioralState.WORKING)
	acc._on_asm_state_changed("agent_a", "agent_a", AsmScript.STATE_COMPLETED, AsmScript.STATE_WORKING)
	assert_eq(acc.get_behavioral_state(), ACCScript.BehavioralState.COMPLETED_BEAT)
	acc.queue_free()


func test_asm_state_changed_to_errored_enters_errored() -> void:
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	acc._test_force_state(ACCScript.BehavioralState.WORKING)
	acc._on_asm_state_changed("agent_a", "agent_a", AsmScript.STATE_ERRORED, AsmScript.STATE_WORKING)
	assert_eq(acc.get_behavioral_state(), ACCScript.BehavioralState.ERRORED)
	acc.queue_free()


# ─── .bind(agent_id) Tier 2 filter ───────────────────────────────────────────

func test_state_changed_for_different_agent_is_ignored() -> void:
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	acc._test_force_state(ACCScript.BehavioralState.IDLE_WANDERING)
	# Different agent_id — must be ignored.
	acc._on_asm_state_changed("agent_a", "different_agent", AsmScript.STATE_WORKING, AsmScript.STATE_IDLE)
	assert_eq(acc.get_behavioral_state(), ACCScript.BehavioralState.IDLE_WANDERING)
	acc.queue_free()


# ─── WORKING signal during COMPLETED_BEAT is queued (Rule 4) ─────────────────

func test_working_signal_during_completed_beat_is_queued_not_immediate() -> void:
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	acc._test_force_state(ACCScript.BehavioralState.COMPLETED_BEAT)
	acc._on_asm_state_changed("agent_a", "agent_a", AsmScript.STATE_WORKING, AsmScript.STATE_COMPLETED)
	# Should still be in COMPLETED_BEAT with queued flag set.
	assert_eq(acc.get_behavioral_state(), ACCScript.BehavioralState.COMPLETED_BEAT)
	assert_true(acc._queued_working_during_beat)
	acc.queue_free()


# ─── last_asm_state accessor ─────────────────────────────────────────────────

func test_last_asm_state_tracks_received_signal() -> void:
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	acc._on_asm_state_changed("agent_a", "agent_a", AsmScript.STATE_WORKING, AsmScript.STATE_IDLE)
	assert_eq(acc.get_last_asm_state(), AsmScript.STATE_WORKING)
	acc._on_asm_state_changed("agent_a", "agent_a", AsmScript.STATE_ERRORED, AsmScript.STATE_WORKING)
	assert_eq(acc.get_last_asm_state(), AsmScript.STATE_ERRORED)
	acc.queue_free()


# ─── Tuning constants ────────────────────────────────────────────────────────

func test_completed_beat_duration_default_is_2_sec() -> void:
	assert_almost_eq(ACCScript.COMPLETED_BEAT_DURATION_SEC_DEFAULT, 2.0, 0.0001)


func test_error_timeout_default_is_30_sec() -> void:
	assert_almost_eq(ACCScript.ERROR_TIMEOUT_SEC_DEFAULT, 30.0, 0.0001)


func test_resigned_idle_speed_multiplier_is_0_6() -> void:
	assert_almost_eq(ACCScript.RESIGNED_IDLE_SPEED_MULTIPLIER, 0.6, 0.0001)
