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


# ─── Placeholder visual + AnimationPlayer self-bootstrap (ADR-0009) ──────────

func test_acc_creates_body_color_rect_placeholder() -> void:
	# Arrange / Act — _ready() should self-create a Body ColorRect.
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	# Assert
	var body: Node = acc.get_node_or_null(^"Body")
	assert_not_null(body, "Body placeholder must be auto-created")
	assert_true(body is ColorRect, "Body must be a ColorRect placeholder")
	assert_eq((body as ColorRect).size, Vector2(16, 16))
	acc.queue_free()


func test_acc_creates_animation_player_when_not_wired_at_scene_author() -> void:
	# Arrange / Act
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	# Assert
	assert_not_null(acc.animation_player, "AnimationPlayer must be auto-created when unwired")
	assert_true(acc.animation_player.active, "AnimationPlayer.active must be true per ADR-0009 VERIFY-6")
	acc.queue_free()


func test_acc_animation_player_has_placeholder_library_attached() -> void:
	# Arrange / Act
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	# Assert — default-namespace library is present with the 4 anims.
	assert_true(acc.animation_player.has_animation_library(&""))
	assert_true(acc.animation_player.has_animation(&"idle"))
	assert_true(acc.animation_player.has_animation(&"working"))
	assert_true(acc.animation_player.has_animation(&"completed"))
	assert_true(acc.animation_player.has_animation(&"errored"))
	acc.queue_free()


func test_acc_plays_idle_animation_after_ready() -> void:
	# Arrange / Act
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	# Assert — idle is playing as the initial state per _ready().
	assert_eq(acc.animation_player.current_animation, "idle")
	acc.queue_free()


func test_acc_completed_animation_finished_reverts_to_idle() -> void:
	# Per ADR-0009 §"One-Shot Animation Revert": when `completed` finishes,
	# ACC plays `idle`.
	# Arrange
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	# Force `completed` to be the playing anim, then fire the finished signal.
	acc.animation_player.play(&"completed")
	# Act — manually invoke the handler (signal will fire on its own in
	# production once the 0.5s anim ends; tests don't run real-time).
	acc._on_animation_finished(&"completed")
	# Assert
	assert_eq(acc.animation_player.current_animation, "idle")
	acc.queue_free()


func test_acc_uses_errored_anim_name_not_errored_freeze() -> void:
	# Regression: ACC's ASM_STATE_TO_ANIM previously mapped "errored" to
	# &"errored_freeze", which isn't in the placeholder library. Aligned to
	# ADR-0009 §Shared Asset table (single `errored` anim).
	assert_eq(ACCScript.ASM_STATE_TO_ANIM[AsmScript.STATE_ERRORED], &"errored")


# ─── Phase 2 weighted wandering: constants ───────────────────────────────────

func test_phase2_base_weights_match_gdd_defaults() -> void:
	# GDD §Tuning Knobs → Idle Wandering — Waypoint Weights
	# Note: prop/corridor are intentionally 0 in Phase 2 (deferred deps).
	# When ambient_prop / corridor concept land, set these back to GDD defaults.
	assert_almost_eq(ACCScript.W_SOCIAL_BASE, 35.0, 0.0001)
	assert_almost_eq(ACCScript.W_OTHER_ROOM_BASE, 20.0, 0.0001)
	assert_almost_eq(ACCScript.W_OWN_ROOM_BASE, 5.0, 0.0001)


func test_phase2_recency_floor_and_decay_match_gdd() -> void:
	# GDD §Tuning Knobs → Recency Cooldown
	assert_almost_eq(ACCScript.C_RECENCY_FLOOR, 0.2, 0.0001)
	assert_almost_eq(ACCScript.RECENCY_DECAY_PER_SEC, 0.1, 0.0001)


# ─── Phase 2 recency state ───────────────────────────────────────────────────

func test_recency_starts_at_1_0_for_all_categories() -> void:
	# Arrange / Act
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	# Assert
	assert_almost_eq(acc._test_get_recency(ACCScript.CAT_SOCIAL), 1.0, 0.0001)
	assert_almost_eq(acc._test_get_recency(ACCScript.CAT_PROP), 1.0, 0.0001)
	assert_almost_eq(acc._test_get_recency(ACCScript.CAT_OTHER_ROOM), 1.0, 0.0001)
	assert_almost_eq(acc._test_get_recency(ACCScript.CAT_CORRIDOR), 1.0, 0.0001)
	assert_almost_eq(acc._test_get_recency(ACCScript.CAT_OWN_ROOM), 1.0, 0.0001)
	acc.queue_free()


func test_process_delta_advances_recency_toward_1() -> void:
	# Arrange — manually depress recency, then run _process(delta).
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	acc._test_force_state(ACCScript.BehavioralState.IDLE_WANDERING)
	acc._recency[ACCScript.CAT_OWN_ROOM] = 0.5
	# Act — 1 second of process time at RECENCY_DECAY_PER_SEC (0.1) = +0.1
	acc._process(1.0)
	# Assert
	assert_almost_eq(acc._test_get_recency(ACCScript.CAT_OWN_ROOM), 0.6, 0.0001)
	acc.queue_free()


func test_process_delta_clamps_recency_at_1() -> void:
	# Arrange — recency at 0.95; one second of decay (+0.1) would overshoot.
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	acc._test_force_state(ACCScript.BehavioralState.IDLE_WANDERING)
	acc._recency[ACCScript.CAT_OWN_ROOM] = 0.95
	# Act
	acc._process(1.0)
	# Assert — clamped to 1.0
	assert_almost_eq(acc._test_get_recency(ACCScript.CAT_OWN_ROOM), 1.0, 0.0001)
	acc.queue_free()


func test_process_delta_does_not_decay_outside_idle_wandering() -> void:
	# Recency state should freeze when not wandering.
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	acc._test_force_state(ACCScript.BehavioralState.WORKING)
	acc._recency[ACCScript.CAT_OWN_ROOM] = 0.5
	# Act
	acc._process(1.0)
	# Assert — unchanged
	assert_almost_eq(acc._test_get_recency(ACCScript.CAT_OWN_ROOM), 0.5, 0.0001)
	acc.queue_free()


# ─── Phase 2 weighted random sampling ────────────────────────────────────────

func test_weighted_random_category_returns_only_key_when_one_choice() -> void:
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	# Act / Assert
	var result: String = acc._weighted_random_category({"only_cat": 10.0})
	assert_eq(result, "only_cat")
	acc.queue_free()


func test_weighted_random_category_returns_empty_when_zero_total() -> void:
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	# Act / Assert — all-zero weights
	var result: String = acc._weighted_random_category({"a": 0.0, "b": 0.0})
	assert_eq(result, "")
	acc.queue_free()


# ─── Phase 2 group membership ────────────────────────────────────────────────

func test_acc_joins_agent_characters_group_at_ready() -> void:
	var acc: AgentCharacterController = _make_acc("agent_a")
	add_child(acc)
	assert_true(acc.is_in_group(ACCScript.AGENT_CHARACTERS_GROUP),
		"ACC must self-join the peer-discovery group for social waypoint")
	acc.queue_free()
