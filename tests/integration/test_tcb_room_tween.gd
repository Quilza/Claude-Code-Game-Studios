extends GutTest
##
## TaskCompletionBeat × RoomSystem — integration test.
##
## Validates the end-to-end wiring established by Room System GDD §11:
## when ASM emits `task_completed(agent_id)`, TCB resolves the agent's
## room via `RoomSystem.get_room_node(...)` and applies a 3-phase modulate
## Tween to that room's Node2D.
##
## Covers the gap flagged in design/gdd/task-completion-beat.md §10 / §318
## ("Room System GDD needs a Node2D resolution API"). Without this test,
## production reports `[TCB] no room node found ...` because no scene tree
## node matches the room_id.
##
## Structure:
##   • Arrange — instantiate TileMapRenderer, RoomSystem, ASM, TCB; wire
##     dependencies; assign agent to a room.
##   • Act — drive ASM.task_completed via the public seam.
##   • Assert — room node's `modulate` is no longer the neutral white that
##     a Tween was started against (the attack phase is in flight).
##

const TileMapRendererScript = preload("res://src/core/tilemap_renderer.gd")
const RoomSystemScript = preload("res://src/core/room_system.gd")
const AgentStateMachineScript = preload("res://src/integration/agent_state_machine.gd")
const TaskCompletionBeatScript = preload("res://src/gameplay/task_completion_beat.gd")


func _make_stack() -> Dictionary:
	# Returns a freshly composed { tm, rs, asm, tcb } stack ready for the test.
	var tm: TileMapRenderer = TileMapRendererScript.new()
	add_child(tm)
	var rs: RoomSystem = RoomSystemScript.new()
	rs.tile_map_renderer = tm
	add_child(rs)
	var asm: Node = AgentStateMachineScript.new()
	add_child(asm)
	var tcb: TaskCompletionBeat = TaskCompletionBeatScript.new()
	tcb.agent_state_machine = asm
	tcb.room_system = rs
	add_child(tcb)
	return {"tm": tm, "rs": rs, "asm": asm, "tcb": tcb}


func _cleanup(stack: Dictionary) -> void:
	for key: String in ["tcb", "asm", "rs", "tm"]:
		var node: Node = stack[key]
		if is_instance_valid(node):
			node.queue_free()


# ─── End-to-end wiring ───────────────────────────────────────────────────────

func test_task_completed_triggers_modulate_tween_on_assigned_room_node() -> void:
	# Arrange
	var stack: Dictionary = _make_stack()
	var rs: RoomSystem = stack["rs"]
	var asm: Node = stack["asm"]
	var tcb: TaskCompletionBeat = stack["tcb"]
	rs.assign_agent(RoomSystemScript.AGENT_ROOM_ID, "claude_dev")
	var room_node: Node2D = rs.get_room_node_for_agent("claude_dev")
	assert_not_null(room_node, "Precondition: room node exists for assigned agent")
	# Confirm neutral modulate at rest.
	assert_eq(room_node.modulate, Color(1, 1, 1, 1), "Precondition: modulate is neutral before beat")

	# Act — emit task_completed via ASM. TCB is subscribed in its _ready().
	asm.task_completed.emit("claude_dev")
	# Advance one frame so the Tween's first step runs.
	await get_tree().process_frame

	# Assert — modulate has shifted toward BEAT_PEAK_COLOR (attack phase in flight).
	# Tween eases into the peak; after one frame the value is between neutral
	# and peak, so we just check it's no longer perfectly neutral.
	var still_neutral: bool = (room_node.modulate == Color(1, 1, 1, 1))
	assert_false(still_neutral, "Modulate should have started shifting after task_completed")

	_cleanup(stack)


# ─── Unassigned agent — no Tween, no crash ───────────────────────────────────

func test_task_completed_for_unassigned_agent_does_not_crash() -> void:
	# Arrange — no assign_agent call.
	var stack: Dictionary = _make_stack()
	var asm: Node = stack["asm"]

	# Act — emit for an agent that has no room.
	asm.task_completed.emit("ghost_agent")
	await get_tree().process_frame

	# Assert — we got here without a crash. (TCB push_warns and skips.)
	assert_true(true, "TCB must handle unassigned agent without crashing")

	_cleanup(stack)


# ─── Same-room collision (Rule 7) ────────────────────────────────────────────

func test_double_task_completed_same_room_kills_and_restarts_tween() -> void:
	# Per TCB Rule 7: if a Tween is already running for a room, kill it and
	# restart. We assert that after a second emit, a fresh Tween reference is
	# tracked for the room.
	# Arrange
	var stack: Dictionary = _make_stack()
	var rs: RoomSystem = stack["rs"]
	var asm: Node = stack["asm"]
	var tcb: TaskCompletionBeat = stack["tcb"]
	rs.assign_agent(RoomSystemScript.AGENT_ROOM_ID, "claude_dev")

	# Act — fire twice with a frame between.
	asm.task_completed.emit("claude_dev")
	await get_tree().process_frame
	var first_tween: Tween = tcb._room_tweens.get(RoomSystemScript.AGENT_ROOM_ID, null) as Tween
	assert_not_null(first_tween, "First task_completed should register a Tween")

	asm.task_completed.emit("claude_dev")
	await get_tree().process_frame
	var second_tween: Tween = tcb._room_tweens.get(RoomSystemScript.AGENT_ROOM_ID, null) as Tween

	# Assert — the new Tween is a different instance (old one was killed).
	assert_not_null(second_tween, "Second task_completed should register a new Tween")
	assert_ne(first_tween, second_tween, "Second Tween must be a new instance, not the killed one")

	_cleanup(stack)
