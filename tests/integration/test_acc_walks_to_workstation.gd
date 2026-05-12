extends GutTest
##
## AgentCharacterController × {RoomSystem, AgentStateMachine, TileMapRenderer}
## — integration test.
##
## Validates the Phase 1 movement substrate end-to-end: when ASM emits
## `agent_state_changed(agent_id, "working", _)`, ACC walks toward its
## assigned workstation tile (not teleports).
##
## Per design/gdd/agent-character-controller.md §Acceptance Criteria #4:
##   "WORKING interrupts immediately. When agent_state_changed(id, 'working')
##    fires, the agent begins walking toward its workstation within the same
##    frame (no deferred routing, no animation delay)."
##
## Verifies the "begins walking" half. The "within the same frame" half is
## tested by `test_working_signal_sets_walk_target_same_frame` below.
##

const TileMapRendererScript = preload("res://src/core/tilemap_renderer.gd")
const RoomSystemScript = preload("res://src/core/room_system.gd")
const AsmScript = preload("res://src/integration/agent_state_machine.gd")
const ACCScript = preload("res://src/gameplay/agent_character_controller.gd")


func _make_stack(agent_id: String = "claude_dev") -> Dictionary:
	var tm: TileMapRenderer = TileMapRendererScript.new()
	add_child(tm)
	var rs: RoomSystem = RoomSystemScript.new()
	rs.tile_map_renderer = tm
	add_child(rs)
	var asm: Node = AsmScript.new()
	add_child(asm)
	var acc: AgentCharacterController = ACCScript.new()
	acc.agent_id = agent_id
	acc.agent_index = 0
	acc.agent_state_machine = asm
	acc.room_system = rs
	acc.tile_map_renderer = tm
	add_child(acc)
	# Assign agent to a room (with workstation slot).
	rs.assign_agent(RoomSystemScript.AGENT_ROOM_ID, agent_id)
	return {"tm": tm, "rs": rs, "asm": asm, "acc": acc}


func _cleanup(stack: Dictionary) -> void:
	for key: String in ["acc", "asm", "rs", "tm"]:
		var node: Node = stack[key]
		if is_instance_valid(node):
			node.queue_free()


# ─── ACC walks to workstation on WORKING ─────────────────────────────────────

func test_working_signal_sets_walk_target_same_frame() -> void:
	# Arrange
	var stack: Dictionary = _make_stack("claude_dev")
	var rs: RoomSystem = stack["rs"]
	var asm: Node = stack["asm"]
	var acc: AgentCharacterController = stack["acc"]
	# ACC._ready() snaps to workstation; reset position to room corner so we
	# can observe walking back toward the workstation.
	acc.position = Vector2(352.0, 16.0)   # AGENT_ROOM top-left in world space
	# Workstation tile is (28, 5); world center = (28*16+8, 5*16+8) = (456, 88).
	var expected_target: Vector2 = stack["tm"].tile_to_world(
		rs.get_workstation_for_agent("claude_dev"))

	# Act — fire ASM state change to WORKING.
	asm.agent_state_changed.emit("claude_dev", AsmScript.STATE_WORKING, AsmScript.STATE_IDLE)

	# Assert — same-frame: target is set, ACC hasn't teleported.
	assert_true(acc.has_walk_target(), "WORKING entry must set a walk target")
	assert_eq(acc.get_walk_target(), expected_target)
	assert_ne(acc.position, expected_target, "ACC must walk, not teleport")

	_cleanup(stack)


func test_acc_position_advances_toward_workstation_over_physics_frames() -> void:
	# Arrange — same setup as above.
	var stack: Dictionary = _make_stack("claude_dev")
	var asm: Node = stack["asm"]
	var acc: AgentCharacterController = stack["acc"]
	acc.position = Vector2(352.0, 16.0)
	asm.agent_state_changed.emit("claude_dev", AsmScript.STATE_WORKING, AsmScript.STATE_IDLE)
	var start_pos: Vector2 = acc.position
	var target: Vector2 = acc.get_walk_target()
	var initial_distance: float = start_pos.distance_to(target)

	# Act — drive 10 physics frames at the fixed 60Hz tick (1/60 sec).
	for i: int in 10:
		acc._physics_process(1.0 / 60.0)

	# Assert — moved toward target. At V_BASE=40, 10 frames * (1/60s) = 0.167s
	# of simulated time → ~6.7px of progress.
	var new_distance: float = acc.position.distance_to(target)
	assert_lt(new_distance, initial_distance, "ACC must close distance toward workstation")
	# Expected progress: 40 * (10/60) = ~6.67 px.
	var moved: float = start_pos.distance_to(acc.position)
	assert_almost_eq(moved, 6.667, 0.5)

	_cleanup(stack)


# ─── Idle wander target ──────────────────────────────────────────────────────

func test_working_signal_drives_animation_player_to_working_anim() -> void:
	# End-to-end: ASM.agent_state_changed → ACC.._on_asm_state_changed →
	# _play_animation_for_state("working") → AnimationPlayer.play("working").
	# Verifies ADR-0009 dispatch + Tier 2 .bind() arg order.
	# Arrange
	var stack: Dictionary = _make_stack("claude_dev")
	var asm: Node = stack["asm"]
	var acc: AgentCharacterController = stack["acc"]
	assert_eq(acc.animation_player.current_animation, "idle", "Precondition: idle at start")
	# Act
	asm.agent_state_changed.emit("claude_dev", AsmScript.STATE_WORKING, AsmScript.STATE_IDLE)
	# Assert
	assert_eq(acc.animation_player.current_animation, "working")
	_cleanup(stack)


func test_idle_wandering_picks_target_inside_own_room_bounds() -> void:
	# Arrange — ACC enters IDLE_WANDERING in _ready() (post-assign).
	var stack: Dictionary = _make_stack("claude_dev")
	var rs: RoomSystem = stack["rs"]
	var acc: AgentCharacterController = stack["acc"]

	# Re-pick to force a fresh target (the one from _ready() came before
	# add_child completed and may have run pre-assignment).
	rs.assign_agent(RoomSystemScript.AGENT_ROOM_ID, "claude_dev") if false else null
	acc._pick_idle_wander_target()

	# Assert — walk target is inside the agent room bounds (in world space).
	# bounds = (22, 1, 18, 13) → world rect (352, 16) to (640, 224)
	var t: Vector2 = acc.get_walk_target()
	assert_gte(t.x, 352.0, "Wander x should be >= room left edge in world space")
	assert_lte(t.x, 640.0, "Wander x should be <= room right edge")
	assert_gte(t.y, 16.0, "Wander y should be >= room top edge")
	assert_lte(t.y, 224.0, "Wander y should be <= room bottom edge")

	_cleanup(stack)
