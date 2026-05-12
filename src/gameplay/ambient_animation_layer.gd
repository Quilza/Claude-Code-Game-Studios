class_name AmbientAnimationLayer extends Node2D
##
## AmbientAnimationLayer (AAL) — Presentation layer.
##
## Owns all non-character environmental motion: blinking status lights,
## spinning fans, terminal screens, flickering indicators. Always-on props
## loop indefinitely; state-sensitive props react to per-room agent state.
##
## Governing architecture:
##   • ADR-0006 (Signal-Based Decoupling)       — Tier 1 subscription
##   • ADR-0009 (AnimationPlayer Strategy)      — for ambient loops
##   • ADR-0010 (Tween Lifecycle)               — for cross-fade transitions
##
## GDD: design/gdd/ambient-animation-layer.md (post cross-GDD reconciliation)
##
## **Scope note**: this commit implements the architectural skeleton —
## room-state aggregation, signal subscription, prop registry. Actual prop
## animation choreography (white flash on COMPLETED, amber pulse on
## ERRORED, etc.) is structured but stubbed pending art assets.
##

# ─── Constants ───────────────────────────────────────────────────────────────

const AMBIENT_PROP_GROUP: StringName = &"ambient_prop"
const TRANSITION_SEC: float = 0.3   # state-sensitive cross-fade duration (Rule 8)


# ─── Dependencies (scene-wired) ──────────────────────────────────────────────

@export var agent_state_machine: AgentStateMachine = null
@export var room_system: RoomSystem = null


# ─── Internal state — per-room aggregated agent state ────────────────────────

# Per Rule (cross-GDD review C-1 decision): AAL aggregates room state
# internally; ASM is room-blind.
#
# Aggregation rule: a room's ambient state is the "highest priority" agent
# state of any agent in it.
#   ERRORED > WORKING > COMPLETED > IDLE
#
# Where priority means: if ANY agent in the room is in this state, the room
# shows it. A room with 3 idle agents + 1 errored shows errored ambient.
const ROOM_PRIORITY: Dictionary = {
	AgentStateMachine.STATE_ERRORED: 4,
	AgentStateMachine.STATE_WORKING: 3,
	AgentStateMachine.STATE_COMPLETED: 2,
	AgentStateMachine.STATE_IDLE: 1,
}

var _room_states: Dictionary = {}   # room_id (StringName) → ambient state (String)


# ─── Godot lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	_subscribe_to_asm()
	_initialise_room_states()


func _subscribe_to_asm() -> void:
	if agent_state_machine == null:
		push_warning("[AAL] agent_state_machine not wired — AAL will not respond to agent state changes")
		return
	agent_state_machine.agent_state_changed.connect(_on_asm_state_changed)


func _initialise_room_states() -> void:
	if room_system == null:
		return
	for room_id: StringName in room_system.get_all_room_ids():
		_room_states[room_id] = AgentStateMachine.STATE_IDLE


# ─── ASM signal handler ──────────────────────────────────────────────────────

func _on_asm_state_changed(agent_id: String, _new_state: String, _previous: String) -> void:
	# Aggregate the agent's room state.
	if room_system == null:
		return
	var room_id: StringName = room_system.get_room_for_agent(agent_id)
	if room_id == &"":
		return
	_recompute_room_state(room_id)


func _recompute_room_state(room_id: StringName) -> void:
	# Compute the highest-priority state in this room.
	if agent_state_machine == null or room_system == null:
		return
	var room_data = room_system.get_room(room_id)
	if room_data == null:
		return
	var highest_priority: int = ROOM_PRIORITY[AgentStateMachine.STATE_IDLE]
	var highest_state: String = AgentStateMachine.STATE_IDLE
	for agent_id: String in room_data.agent_ids:
		var s: String = agent_state_machine.get_agent_state(agent_id)
		var p: int = int(ROOM_PRIORITY.get(s, 0))
		if p > highest_priority:
			highest_priority = p
			highest_state = s
	_set_room_state(room_id, highest_state)


func _set_room_state(room_id: StringName, new_state: String) -> void:
	var previous: String = String(_room_states.get(room_id, AgentStateMachine.STATE_IDLE))
	if previous == new_state:
		return
	_room_states[room_id] = new_state
	# TODO(prop choreography): apply state-sensitive prop animation for this
	# room. Iterate ambient props in BUNKER_ROOMS_GROUP whose parent room
	# matches room_id and call their set_ambient_state(new_state). Cross-fade
	# over TRANSITION_SEC via Tween per ADR-0010.
	_apply_ambient_transition(room_id, previous, new_state)


# ─── Prop transition (stubbed) ──────────────────────────────────────────────

func _apply_ambient_transition(_room_id: StringName, _previous: String, _new_state: String) -> void:
	# TODO: locate state-sensitive props in this room, apply set_ambient_state
	# with cross-fade via Tween(TRANSITION_SEC) per ADR-0010.
	#
	# Pattern per Rule 8:
	#   for prop in props_in_room(room_id):
	#     if prop.is_state_sensitive:
	#       var t: Tween = create_tween()
	#       t.bind_node(prop)
	#       t.tween_property(prop, "modulate", target_color, TRANSITION_SEC)
	#       prop.set_ambient_state(new_state)
	#
	# Stubbed until prop scenes are authored.
	pass


# ─── Public read-only accessors ──────────────────────────────────────────────

## Returns the aggregated ambient state for a room.
## Default: STATE_IDLE for unknown rooms.
func get_room_state(room_id: StringName) -> String:
	return String(_room_states.get(room_id, AgentStateMachine.STATE_IDLE))


## Returns a snapshot of all room states.
func get_all_room_states() -> Dictionary:
	return _room_states.duplicate()


# ─── Test-only seam ─────────────────────────────────────────────────────────

func _test_set_room_state(room_id: StringName, state: String) -> void:
	_room_states[room_id] = state
