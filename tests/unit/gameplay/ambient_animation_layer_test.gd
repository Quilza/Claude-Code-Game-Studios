extends GutTest
##
## AmbientAnimationLayer — unit tests.
##

const AALScript = preload("res://src/gameplay/ambient_animation_layer.gd")
const AsmScript = preload("res://src/integration/agent_state_machine.gd")


# ─── Constants ──────────────────────────────────────────────────────────────

func test_transition_sec_is_0_3() -> void:
	assert_almost_eq(AALScript.TRANSITION_SEC, 0.3, 0.0001)


func test_ambient_prop_group_is_set() -> void:
	assert_eq(AALScript.AMBIENT_PROP_GROUP, &"ambient_prop")


# ─── Priority ordering ──────────────────────────────────────────────────────

func test_errored_has_higher_priority_than_working() -> void:
	assert_gt(
		AALScript.ROOM_PRIORITY[AsmScript.STATE_ERRORED],
		AALScript.ROOM_PRIORITY[AsmScript.STATE_WORKING],
	)


func test_working_has_higher_priority_than_completed() -> void:
	assert_gt(
		AALScript.ROOM_PRIORITY[AsmScript.STATE_WORKING],
		AALScript.ROOM_PRIORITY[AsmScript.STATE_COMPLETED],
	)


func test_completed_has_higher_priority_than_idle() -> void:
	assert_gt(
		AALScript.ROOM_PRIORITY[AsmScript.STATE_COMPLETED],
		AALScript.ROOM_PRIORITY[AsmScript.STATE_IDLE],
	)


# ─── Per-room state accessor ─────────────────────────────────────────────────

func test_get_room_state_default_is_idle() -> void:
	var aal: AmbientAnimationLayer = AALScript.new()
	assert_eq(aal.get_room_state(&"never_set"), AsmScript.STATE_IDLE)
	aal.free()


func test_test_set_room_state_and_read_back() -> void:
	var aal: AmbientAnimationLayer = AALScript.new()
	aal._test_set_room_state(&"room_a", AsmScript.STATE_WORKING)
	assert_eq(aal.get_room_state(&"room_a"), AsmScript.STATE_WORKING)
	aal.free()


func test_get_all_room_states_returns_snapshot() -> void:
	var aal: AmbientAnimationLayer = AALScript.new()
	aal._test_set_room_state(&"a", AsmScript.STATE_IDLE)
	aal._test_set_room_state(&"b", AsmScript.STATE_WORKING)
	var snapshot: Dictionary = aal.get_all_room_states()
	assert_eq(snapshot.size(), 2)
	# Mutating snapshot should NOT affect AAL's internal state.
	snapshot[&"injected"] = "noise"
	assert_eq(aal.get_all_room_states().size(), 2, "Snapshot is a copy")
	aal.free()


# ─── _set_room_state idempotence ─────────────────────────────────────────────

func test_set_room_state_same_value_no_change() -> void:
	var aal: AmbientAnimationLayer = AALScript.new()
	aal._test_set_room_state(&"a", AsmScript.STATE_IDLE)
	aal._set_room_state(&"a", AsmScript.STATE_IDLE)
	assert_eq(aal.get_room_state(&"a"), AsmScript.STATE_IDLE)
	aal.free()
