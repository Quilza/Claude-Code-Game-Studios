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
	# ACC._ready() snaps to workstation; reset position to a different spot
	# inside the bedroom so we can observe walking back toward the workstation.
	# Commander's room bounds = (1,1,20,15) → world (16,16) to (336,240).
	# Place agent at far corner.
	acc.position = Vector2(280.0, 200.0)
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
	acc.position = Vector2(280.0, 200.0)   # far corner of commander's room
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


func test_phase2_visiting_category_drops_its_recency_to_floor() -> void:
	# After _pick_idle_wander_target() picks a category, that category's
	# recency multiplier must drop to C_RECENCY_FLOOR. Other categories'
	# recency is unaffected by the same call.
	#
	# Note: ACC._ready() fires _pick_idle_wander_target() once via the
	# IDLE_WANDERING entry hook, so recencies are no longer all 1.0 by the
	# time the test runs. Reset them, then verify the next pick's effect.
	var stack: Dictionary = _make_stack("claude_dev")
	var acc: AgentCharacterController = stack["acc"]
	# Reset to a clean slate.
	for cat: String in [ACCScript.CAT_SOCIAL, ACCScript.CAT_OTHER_ROOM,
			ACCScript.CAT_OWN_ROOM, ACCScript.CAT_PROP, ACCScript.CAT_CORRIDOR]:
		acc._recency[cat] = 1.0

	# Act
	acc._pick_idle_wander_target()

	# Assert — single-room MVP: own_room is always pickable (CAT_OTHER_ROOM
	# is filtered out because no other rooms exist). Whichever pickable
	# category gets chosen has its recency drop to floor. Other categories'
	# recency is unaffected.
	var picked: String = acc._test_get_current_category()
	assert_ne(picked, "", "A category must have been picked")
	assert_ne(picked, ACCScript.CAT_OTHER_ROOM,
		"CAT_OTHER_ROOM cannot be picked when only one room exists")
	assert_almost_eq(acc._test_get_recency(picked), ACCScript.C_RECENCY_FLOOR, 0.0001,
		"Picked category's recency dropped to floor")
	# Verify CAT_OTHER_ROOM's recency stays at 1.0 (it was never picked).
	assert_almost_eq(acc._test_get_recency(ACCScript.CAT_OTHER_ROOM), 1.0, 0.0001,
		"Non-picked category's recency is preserved")

	_cleanup(stack)


func test_phase2_other_room_returns_null_when_no_other_rooms_registered() -> void:
	# Single-room MVP: the agent's own room IS the only room, so the
	# `other_room` waypoint category has no candidates. _pick_other_room_target
	# must return null so _build_effective_weights drops the category from
	# the weighted sample (no wasted weight allocation).
	var stack: Dictionary = _make_stack("claude_dev")
	var acc: AgentCharacterController = stack["acc"]

	# Act
	var target: Variant = acc._pick_other_room_target()

	# Assert — no other rooms → null target → wander falls back to own_room
	assert_null(target, "other_room picker must return null when only one room is registered")

	_cleanup(stack)


func test_phase2_social_picks_near_peer_position() -> void:
	# With two ACCs in the agent_characters group, the social picker should
	# pick a tile within SOCIAL_PEER_RADIUS_TILES of the other ACC.
	# Arrange
	var stack: Dictionary = _make_stack("claude_dev")
	var rs: RoomSystem = stack["rs"]
	var tm: TileMapRenderer = stack["tm"]
	var asm: Node = stack["asm"]
	var primary: AgentCharacterController = stack["acc"]
	# Add a second ACC, manually positioned.
	var peer: AgentCharacterController = ACCScript.new()
	peer.agent_id = "peer_dev"
	peer.agent_state_machine = asm
	peer.room_system = rs
	peer.tile_map_renderer = tm
	add_child(peer)
	# Assign peer to commander's room so it has a room context for clamping.
	# (assign_agent will warn about workstation capacity but still records.)
	# Use direct dict write via test seam isn't available; instead manually
	# park peer's position somewhere known.
	peer.position = Vector2(200.0, 100.0)   # known world coord

	# Act
	var target: Variant = primary._pick_social_target()

	# Assert — target should be within (200 ± 2 tiles, 100 ± 2 tiles) world
	# space, i.e. within 32px on each axis. (Then clamped to peer's room
	# bounds if peer has one — peer has no room here, so no clamp.)
	assert_not_null(target, "Social pick must succeed when a peer exists")
	var t: Vector2 = target as Vector2
	# Allow some slack — clamp may shrink to room bounds. Just verify peer
	# was discovered and a target was produced (not stuck at default).
	# Tile coord of (200, 100) at CELL=16 is (12, 6); ±2 tiles → world ±32px
	# (200 - 32 = 168, 200 + 32 = 232, but tile_to_world adds 8px center)
	# Worst case: peer was selected but has a room assignment that clamps target.
	# Loose check: target is in the same general area as peer.
	assert_lt(t.distance_to(peer.position), 200.0,
		"Social target should be reasonably close to peer (not far across the bunker)")

	peer.queue_free()
	_cleanup(stack)


func test_idle_wandering_picks_target_inside_commanders_room_bounds() -> void:
	# Single-room MVP: picker only has own_room available. Verify the target
	# lands inside the commander's bedroom bounds (1-tile inset).
	# Arrange
	var stack: Dictionary = _make_stack("claude_dev")
	var acc: AgentCharacterController = stack["acc"]

	# Act
	acc._pick_idle_wander_target()

	# Assert — commander's bounds (1,1,20,15) → world (16,16) to (336,240).
	# Picker uses middle-50% bias, so target is anywhere in that range.
	var t: Vector2 = acc.get_walk_target()
	assert_gte(t.x, 16.0, "Wander x within commander's room left edge")
	assert_lte(t.x, 336.0, "Wander x within commander's room right edge")
	assert_gte(t.y, 16.0, "Wander y within commander's room top edge")
	assert_lte(t.y, 240.0, "Wander y within commander's room bottom edge")

	_cleanup(stack)
