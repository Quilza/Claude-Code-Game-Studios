extends GutTest
##
## RoomSystem — unit tests.
##
## Covers ACs from `design/gdd/room-system.md`. Uses a real TileMapRenderer
## injected via @export so _ready() can call register_room() without error.
##

const RoomSystemScript = preload("res://src/core/room_system.gd")
const TileMapRendererScript = preload("res://src/core/tilemap_renderer.gd")


# ─── Helpers ─────────────────────────────────────────────────────────────────

func _make_room_system_with_tilemap() -> RoomSystem:
	var tm: TileMapRenderer = TileMapRendererScript.new()
	add_child(tm)
	var rs: RoomSystem = RoomSystemScript.new()
	rs.tile_map_renderer = tm
	add_child(rs)
	return rs


# ─── Constants exposed as public API ─────────────────────────────────────────

func test_commanders_room_id_constant() -> void:
	assert_eq(RoomSystemScript.COMMANDERS_ROOM_ID, &"commander")


func test_agent_room_id_constant() -> void:
	assert_eq(RoomSystemScript.AGENT_ROOM_ID, &"agent_01")


# ─── MVP room population ─────────────────────────────────────────────────────

func test_two_rooms_registered_after_ready() -> void:
	var rs: RoomSystem = _make_room_system_with_tilemap()
	var ids: Array = rs.get_all_room_ids()
	assert_eq(ids.size(), 2)
	assert_has(ids, RoomSystemScript.COMMANDERS_ROOM_ID)
	assert_has(ids, RoomSystemScript.AGENT_ROOM_ID)
	rs.queue_free()


func test_commanders_room_has_no_workstations() -> void:
	var rs: RoomSystem = _make_room_system_with_tilemap()
	var data = rs.get_room(RoomSystemScript.COMMANDERS_ROOM_ID)
	assert_eq(data.workstation_tiles.size(), 0, "Commander's room has no workstations — Commander wanders")
	rs.queue_free()


func test_agent_room_has_at_least_one_workstation() -> void:
	var rs: RoomSystem = _make_room_system_with_tilemap()
	var data = rs.get_room(RoomSystemScript.AGENT_ROOM_ID)
	assert_gt(data.workstation_tiles.size(), 0)
	rs.queue_free()


# ─── TileMapRenderer integration ─────────────────────────────────────────────

func test_rooms_registered_with_tilemap_at_ready() -> void:
	var rs: RoomSystem = _make_room_system_with_tilemap()
	assert_true(rs.tile_map_renderer.has_room(RoomSystemScript.COMMANDERS_ROOM_ID))
	assert_true(rs.tile_map_renderer.has_room(RoomSystemScript.AGENT_ROOM_ID))
	rs.queue_free()


# ─── No signals during _ready() (AC-10) ──────────────────────────────────────

func test_no_signals_emitted_during_ready() -> void:
	# We can't directly assert this, but we can verify no agents are auto-assigned.
	var rs: RoomSystem = _make_room_system_with_tilemap()
	for room_id: Variant in rs.get_all_room_ids():
		var data = rs.get_room(room_id)
		assert_eq(data.agent_ids.size(), 0, "No auto-assignment in _ready()")
	rs.queue_free()


# ─── assign_agent ────────────────────────────────────────────────────────────

func test_assign_agent_adds_to_room_and_emits_signal() -> void:
	var rs: RoomSystem = _make_room_system_with_tilemap()
	var emitted: Array = []
	rs.agent_assigned.connect(func(room_id: StringName, agent_id: String) -> void:
		emitted.append([room_id, agent_id])
	)
	rs.assign_agent(RoomSystemScript.AGENT_ROOM_ID, "claude_dev")
	assert_eq(emitted.size(), 1)
	assert_eq(StringName(emitted[0][0]), RoomSystemScript.AGENT_ROOM_ID)
	assert_eq(String(emitted[0][1]), "claude_dev")
	rs.queue_free()


func test_assign_agent_unknown_room_does_not_emit() -> void:
	# NOTE: GDScript 4.x lambdas can't write outer-scope scalars; use Array holder.
	var rs: RoomSystem = _make_room_system_with_tilemap()
	var emit_count_ref: Array[int] = [0]
	rs.agent_assigned.connect(func(_r: StringName, _a: String) -> void:
		emit_count_ref[0] += 1
	)
	rs.assign_agent(&"nonexistent", "claude_dev")
	assert_eq(emit_count_ref[0], 0)
	rs.queue_free()


func test_assign_agent_to_full_room_does_not_emit() -> void:
	var rs: RoomSystem = _make_room_system_with_tilemap()
	rs.assign_agent(RoomSystemScript.AGENT_ROOM_ID, "claude_dev")
	var emit_count_ref: Array[int] = [0]
	rs.agent_assigned.connect(func(_r: StringName, _a: String) -> void:
		emit_count_ref[0] += 1
	)
	rs.assign_agent(RoomSystemScript.AGENT_ROOM_ID, "second_agent")
	assert_eq(emit_count_ref[0], 0, "No assign signal for over-capacity")
	var data = rs.get_room(RoomSystemScript.AGENT_ROOM_ID)
	assert_eq(data.agent_ids.size(), 1)
	rs.queue_free()


func test_assign_agent_already_in_room_is_no_op() -> void:
	var rs: RoomSystem = _make_room_system_with_tilemap()
	rs.assign_agent(RoomSystemScript.AGENT_ROOM_ID, "claude_dev")
	var emit_count_ref: Array[int] = [0]
	rs.agent_assigned.connect(func(_r: StringName, _a: String) -> void:
		emit_count_ref[0] += 1
	)
	rs.assign_agent(RoomSystemScript.AGENT_ROOM_ID, "claude_dev")
	assert_eq(emit_count_ref[0], 0, "Re-assigning same agent is no-op")
	rs.queue_free()


# ─── unassign_agent ──────────────────────────────────────────────────────────

func test_unassign_agent_removes_and_emits_signal() -> void:
	var rs: RoomSystem = _make_room_system_with_tilemap()
	rs.assign_agent(RoomSystemScript.AGENT_ROOM_ID, "claude_dev")
	var emitted: Array = []
	rs.agent_unassigned.connect(func(room_id: StringName, agent_id: String) -> void:
		emitted.append([room_id, agent_id])
	)
	rs.unassign_agent(RoomSystemScript.AGENT_ROOM_ID, "claude_dev")
	assert_eq(emitted.size(), 1)
	var data = rs.get_room(RoomSystemScript.AGENT_ROOM_ID)
	assert_eq(data.agent_ids.size(), 0)
	rs.queue_free()


func test_unassign_agent_not_in_room_is_no_op() -> void:
	var rs: RoomSystem = _make_room_system_with_tilemap()
	var emit_count_ref: Array[int] = [0]
	rs.agent_unassigned.connect(func(_r: StringName, _a: String) -> void:
		emit_count_ref[0] += 1
	)
	rs.unassign_agent(RoomSystemScript.AGENT_ROOM_ID, "never_assigned")
	assert_eq(emit_count_ref[0], 0)
	rs.queue_free()


# ─── Accessor functions ──────────────────────────────────────────────────────

func test_get_room_for_agent_returns_room_id() -> void:
	var rs: RoomSystem = _make_room_system_with_tilemap()
	rs.assign_agent(RoomSystemScript.AGENT_ROOM_ID, "claude_dev")
	assert_eq(rs.get_room_for_agent("claude_dev"), RoomSystemScript.AGENT_ROOM_ID)
	rs.queue_free()


func test_get_room_for_agent_unassigned_returns_empty_stringname() -> void:
	var rs: RoomSystem = _make_room_system_with_tilemap()
	assert_eq(rs.get_room_for_agent("never_assigned"), &"")
	rs.queue_free()


func test_get_workstation_for_agent_returns_tile() -> void:
	var rs: RoomSystem = _make_room_system_with_tilemap()
	rs.assign_agent(RoomSystemScript.AGENT_ROOM_ID, "claude_dev")
	var data = rs.get_room(RoomSystemScript.AGENT_ROOM_ID)
	var expected: Vector2i = data.workstation_tiles[0]
	assert_eq(rs.get_workstation_for_agent("claude_dev"), expected)
	rs.queue_free()


func test_get_workstation_for_agent_unassigned_returns_sentinel() -> void:
	var rs: RoomSystem = _make_room_system_with_tilemap()
	assert_eq(rs.get_workstation_for_agent("never_assigned"), Vector2i(-1, -1))
	rs.queue_free()


func test_get_room_unknown_returns_null() -> void:
	var rs: RoomSystem = _make_room_system_with_tilemap()
	assert_null(rs.get_room(&"never_registered"))
	rs.queue_free()


# ─── Rule 11: Room Node2D instantiation ──────────────────────────────────────

func test_room_system_creates_room_node_per_registered_room() -> void:
	# Arrange / Act
	var rs: RoomSystem = _make_room_system_with_tilemap()
	# Assert — one Room node per room, named after room_id, child of RoomSystem.
	var commander_node: Node2D = rs.get_room_node(RoomSystemScript.COMMANDERS_ROOM_ID)
	var agent_node: Node2D = rs.get_room_node(RoomSystemScript.AGENT_ROOM_ID)
	assert_not_null(commander_node, "Room node for commander's room must exist")
	assert_not_null(agent_node, "Room node for agent room must exist")
	assert_eq(commander_node.get_parent(), rs, "Room node parent should be RoomSystem")
	assert_eq(agent_node.get_parent(), rs, "Room node parent should be RoomSystem")
	rs.queue_free()


func test_room_system_room_nodes_join_bunker_rooms_group() -> void:
	# Arrange / Act
	var rs: RoomSystem = _make_room_system_with_tilemap()
	# Assert — every room node is in RoomSystem.BUNKER_ROOMS_GROUP for the
	# TCB fallback group lookup path.
	var grouped: Array[Node] = rs.get_tree().get_nodes_in_group(RoomSystemScript.BUNKER_ROOMS_GROUP)
	assert_gte(grouped.size(), 2, "At least the two MVP room nodes should be in the bunker_rooms group")
	var room_ids_found: Array[StringName] = []
	for node: Node in grouped:
		if node is Node2D and "room_id" in node:
			room_ids_found.append(StringName(node.get("room_id")))
	assert_has(room_ids_found, RoomSystemScript.COMMANDERS_ROOM_ID)
	assert_has(room_ids_found, RoomSystemScript.AGENT_ROOM_ID)
	rs.queue_free()


func test_room_system_room_node_exposes_typed_room_id_property() -> void:
	# Arrange / Act
	var rs: RoomSystem = _make_room_system_with_tilemap()
	var commander_node: Node2D = rs.get_room_node(RoomSystemScript.COMMANDERS_ROOM_ID)
	# Assert — `room_id` is a real property (not metadata) so duck-typed
	# callers like TCB._find_room_node_via_group can read it.
	assert_true("room_id" in commander_node, "Room node must expose `room_id` property")
	assert_eq(StringName(commander_node.get("room_id")), RoomSystemScript.COMMANDERS_ROOM_ID)
	rs.queue_free()


func test_room_system_room_node_position_matches_bounds_top_left_world_space() -> void:
	# Per Rule 11: position = bounds.position * CELL_SIZE. The MVP agent room
	# is at bounds.position = (22, 1); CELL_SIZE = 16 → world (352, 16).
	# Arrange / Act
	var rs: RoomSystem = _make_room_system_with_tilemap()
	var agent_node: Node2D = rs.get_room_node(RoomSystemScript.AGENT_ROOM_ID)
	# Assert
	assert_eq(agent_node.position, Vector2(352.0, 16.0), "Agent room node position should be bounds.position * CELL_SIZE")
	rs.queue_free()


func test_get_room_node_unknown_returns_null() -> void:
	var rs: RoomSystem = _make_room_system_with_tilemap()
	assert_null(rs.get_room_node(&"never_registered"))
	rs.queue_free()


func test_get_room_node_for_agent_returns_node_after_assignment() -> void:
	# Arrange
	var rs: RoomSystem = _make_room_system_with_tilemap()
	rs.assign_agent(RoomSystemScript.AGENT_ROOM_ID, "claude_dev")
	# Act
	var node: Node2D = rs.get_room_node_for_agent("claude_dev")
	# Assert — matches the room the agent was assigned to.
	assert_not_null(node)
	assert_eq(StringName(node.get("room_id")), RoomSystemScript.AGENT_ROOM_ID)
	rs.queue_free()


func test_get_room_node_for_agent_unassigned_returns_null() -> void:
	var rs: RoomSystem = _make_room_system_with_tilemap()
	assert_null(rs.get_room_node_for_agent("never_assigned"))
	rs.queue_free()


# ─── computer_interacted forwarding ──────────────────────────────────────────

func test_emit_computer_interacted_fires_signal() -> void:
	var rs: RoomSystem = _make_room_system_with_tilemap()
	var fired_ref: Array[bool] = [false]
	rs.computer_interacted.connect(func() -> void:
		fired_ref[0] = true
	)
	rs.emit_computer_interacted()
	assert_true(fired_ref[0])
	rs.queue_free()
