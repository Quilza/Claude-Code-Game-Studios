class_name RoomSystem extends Node2D
##
## RoomSystem — Core layer.
##
## Registry of bunker rooms: bounds, agent assignments, workstation tiles.
## Knows WHERE + WHO; ASM knows WHAT. Neither knows the other exists.
##
## Governing architecture:
##   • ADR-0003 (Autoload Scene Composition) — scene-scoped, not Autoload
##   • ADR-0006 (Signal-Based Decoupling)    — Tier 1 broadcast signals
##
## GDD: design/gdd/room-system.md (post cross-GDD review reconciliation)
##
## Type convention (per ADR-0001 reconciliation 2026-05-12):
##   • room_id is StringName (internal constants like &"commander")
##   • agent_id is String (matches Data Bridge / ASM / ConfigLoader contract)
##

# ─── Signals ─────────────────────────────────────────────────────────────────

signal agent_assigned(room_id: StringName, agent_id: String)
signal agent_unassigned(room_id: StringName, agent_id: String)
signal computer_interacted   # forwarded from the commander's computer prop


# ─── Room ID constants (per Rule 3) ──────────────────────────────────────────

const COMMANDERS_ROOM_ID: StringName = &"commander"
const AGENT_ROOM_ID: StringName = &"agent_01"


# ─── RoomData (typed inner class, per Rule 4) ────────────────────────────────

class RoomData:
	var bounds: Rect2i
	var agent_ids: Array[String]
	var workstation_tiles: Array[Vector2i]

	func _init(p_bounds: Rect2i, p_workstations: Array[Vector2i]) -> void:
		bounds = p_bounds
		workstation_tiles = p_workstations
		agent_ids = []


# ─── Dependencies (scene-wired) ──────────────────────────────────────────────

@export var tile_map_renderer: TileMapRenderer = null


# ─── Internal state ──────────────────────────────────────────────────────────

var _rooms: Dictionary = {}    # room_id (StringName) → RoomData


# ─── Godot lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	_populate_mvp_rooms()
	_register_rooms_with_tilemap()
	# Per Rule 6: agent assignment is NOT done in _ready() — Bootstrap calls
	# assign_agent() after all _ready()s complete so signals don't fire before
	# subscribers connect.


# ─── MVP room population (per Rule 3) ────────────────────────────────────────

func _populate_mvp_rooms() -> void:
	# MVP: 2 hardcoded rooms. V1 expansion: loop over ConfigLoader.get_agents().
	#
	# Default bounds — sized to fit the 480×270 viewport per ADR-0013 with
	# room for HUD chrome on the right edge. Cell coordinates.
	#   Commander's Room: 20 wide × 15 tall = 320×240 px at top-left
	#   Agent Room:        18 wide × 13 tall to the right of Commander's
	var commanders_room: RoomData = RoomData.new(
		Rect2i(1, 1, 20, 15),
		[],   # No workstations in Commander's Room — Commander wanders
	)
	_rooms[COMMANDERS_ROOM_ID] = commanders_room

	# Agent Room: one workstation slot at tile (24, 5).
	var agent_room: RoomData = RoomData.new(
		Rect2i(22, 1, 18, 13),
		[Vector2i(28, 5)] as Array[Vector2i],
	)
	_rooms[AGENT_ROOM_ID] = agent_room


func _register_rooms_with_tilemap() -> void:
	if tile_map_renderer == null:
		push_warning("[RoomSystem] tile_map_renderer not wired; rooms not registered with TileMapRenderer")
		return
	for room_id: Variant in _rooms.keys():
		var data: RoomData = _rooms[room_id]
		tile_map_renderer.register_room(StringName(room_id), data.bounds)


# ─── Public API (per Rule 7 / GDD §Interactions) ─────────────────────────────

## Returns the RoomData for a room, or null if unknown.
func get_room(room_id: StringName) -> RoomData:
	return _rooms.get(room_id, null)


## Returns the list of registered room IDs.
func get_all_room_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for k: Variant in _rooms.keys():
		ids.append(k)
	return ids


## Returns the room_id for an agent's department (&"" if not assigned).
func get_room_for_agent(agent_id: String) -> StringName:
	for room_id: Variant in _rooms.keys():
		var data: RoomData = _rooms[room_id]
		if agent_id in data.agent_ids:
			return room_id
	return &""


## Returns the workstation tile for an agent within their department room.
## Returns Vector2i(-1, -1) if the agent is not assigned.
func get_workstation_for_agent(agent_id: String) -> Vector2i:
	for room_id: Variant in _rooms.keys():
		var data: RoomData = _rooms[room_id]
		var index: int = data.agent_ids.find(agent_id)
		if index != -1 and index < data.workstation_tiles.size():
			return data.workstation_tiles[index]
	return Vector2i(-1, -1)


## Adds an agent to a room's department, emits agent_assigned.
## Idempotent: if agent already assigned to this room, no-op + warning.
## If agent is already in a DIFFERENT room, removes from old then adds to new.
## If room is unregistered, push_warning + no-op (per E2).
func assign_agent(room_id: StringName, agent_id: String) -> void:
	if not _rooms.has(room_id):
		push_warning("[RoomSystem] assign_agent: unknown room_id '%s'" % room_id)
		return
	# If already assigned to this room, no-op.
	var data: RoomData = _rooms[room_id]
	if agent_id in data.agent_ids:
		push_warning("[RoomSystem] assign_agent: agent '%s' already in room '%s'" % [agent_id, room_id])
		return
	# If assigned elsewhere, remove first.
	var current_room: StringName = get_room_for_agent(agent_id)
	if current_room != &"":
		unassign_agent(current_room, agent_id)
	# Check workstation availability — if all slots taken, warn (the room is
	# a "department" so capacity is the number of authored workstations).
	if data.agent_ids.size() >= data.workstation_tiles.size():
		push_warning("[RoomSystem] assign_agent: room '%s' has no free workstation slots (%d agents, %d workstations)" % [room_id, data.agent_ids.size(), data.workstation_tiles.size()])
		return
	data.agent_ids.append(agent_id)
	agent_assigned.emit(room_id, agent_id)


## Removes an agent from a room. Emits agent_unassigned.
## If room or agent not found, push_warning + no-op (per E3 / Rule 8).
func unassign_agent(room_id: StringName, agent_id: String) -> void:
	if not _rooms.has(room_id):
		push_warning("[RoomSystem] unassign_agent: unknown room_id '%s'" % room_id)
		return
	var data: RoomData = _rooms[room_id]
	var index: int = data.agent_ids.find(agent_id)
	if index == -1:
		push_warning("[RoomSystem] unassign_agent: agent '%s' not in room '%s'" % [agent_id, room_id])
		return
	data.agent_ids.remove_at(index)
	agent_unassigned.emit(room_id, agent_id)


## Re-emits the computer_interacted signal forwarded from the commander's
## computer prop Area2D. Called by the prop scene script.
func emit_computer_interacted() -> void:
	computer_interacted.emit()
