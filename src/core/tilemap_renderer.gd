class_name TileMapRenderer extends Node2D
##
## TileMapRenderer — Foundation layer (rendering substrate).
##
## Wraps 4 `TileMapLayer` children to provide the single addressable tile
## grid for all spatial systems. Owns CELL_SIZE/MODULE_SIZE constants,
## room registry, and the AlertOverlay show/hide flag.
##
## Governing architecture:
##   • ADR-0013 (Stretch Mode + Pixel-Perfect)            — Accepted
##   • ADR-0006 (Signal-Based Decoupling — single-writer) — Accepted
##
## GDD: design/gdd/tilemap-renderer.md
##
## Single-writer rule (per Rule 2): no system outside this file calls any
## TileMapLayer method directly. All callers use the public API.
##

# ─── Constants (per ADR-0013) ────────────────────────────────────────────────

const CELL_SIZE: int = 16
const MODULE_SIZE: int = 8
const MODULES_PER_CELL: int = 2

const LAYER_NAME_FLOOR: String = "TileMapLayer_Floor"
const LAYER_NAME_ALERT: String = "TileMapLayer_AlertOverlay"
const LAYER_NAME_WALL: String = "TileMapLayer_Wall"
const LAYER_NAME_OVERLAY: String = "TileMapLayer_Overlay"


# ─── Layer references ────────────────────────────────────────────────────────

# @export so the scene composer can wire them up. If unset (test scenarios or
# pre-scene-author code), _ready() instantiates them programmatically.
@export var floor_layer: TileMapLayer = null
@export var alert_overlay_layer: TileMapLayer = null
@export var wall_layer: TileMapLayer = null
@export var overlay_layer: TileMapLayer = null


# ─── Internal state ──────────────────────────────────────────────────────────

var _rooms: Dictionary = {}            # room_id (StringName) → Rect2i
var _alert_active: Dictionary = {}     # room_id (StringName) → bool


# ─── Godot lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	# Per Rule 9: parent must have y_sort_enabled for Wall layer's Y-sort to work.
	y_sort_enabled = true
	_ensure_layers()
	_validate_y_sort_topology()


# ─── Layer setup ─────────────────────────────────────────────────────────────

func _ensure_layers() -> void:
	# Create any layers not already wired. Order matters for z_index.
	if floor_layer == null:
		floor_layer = _create_layer(LAYER_NAME_FLOOR, 0, false)
	if alert_overlay_layer == null:
		alert_overlay_layer = _create_layer(LAYER_NAME_ALERT, 0, false)  # z_index 0 + z_as_relative; ordering by sibling position
		alert_overlay_layer.visible = false
	if wall_layer == null:
		wall_layer = _create_layer(LAYER_NAME_WALL, 1, true)
	if overlay_layer == null:
		overlay_layer = _create_layer(LAYER_NAME_OVERLAY, 2, false)
	# Hide alert layer by default (it's only shown on set_alert_state(id, true)).
	alert_overlay_layer.visible = false


func _create_layer(layer_name: String, z_index_value: int, y_sort: bool) -> TileMapLayer:
	var layer: TileMapLayer = TileMapLayer.new()
	layer.name = layer_name
	layer.z_index = z_index_value
	layer.y_sort_enabled = y_sort
	add_child(layer)
	return layer


func _validate_y_sort_topology() -> void:
	# Per ADR-0013 Y-sort topology: parent Node2D AND Wall layer both
	# y_sort_enabled. Validated at runtime so misconfiguration surfaces early.
	if not y_sort_enabled:
		push_warning("[TileMapRenderer] parent y_sort_enabled is false; Wall Y-sort will not function")
	if wall_layer != null and not wall_layer.y_sort_enabled:
		push_warning("[TileMapRenderer] wall_layer.y_sort_enabled is false; agent/wall Y-sort will not function")


# ─── Coordinate conversion (per Rule 5, 6 + F1, F2) ──────────────────────────

## Returns the world-space center of the given tile cell.
## tile_to_world(Vector2i(0, 0)) → Vector2(8.0, 8.0)  (center of origin cell)
## tile_to_world(Vector2i(2, 3)) → Vector2(40.0, 56.0)
func tile_to_world(tile_coord: Vector2i) -> Vector2:
	return Vector2(
		float(tile_coord.x * CELL_SIZE + CELL_SIZE / 2),
		float(tile_coord.y * CELL_SIZE + CELL_SIZE / 2),
	)


## Returns the tile coordinate containing the given world position.
## Negative inputs are valid (floor semantics).
## world_to_tile(Vector2(40.0, 56.0)) → Vector2i(2, 3)
## world_to_tile(Vector2(-1.0, -1.0)) → Vector2i(-1, -1)
func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / float(CELL_SIZE))),
		int(floor(world_pos.y / float(CELL_SIZE))),
	)


# ─── Room registry (per Rule 7) ──────────────────────────────────────────────

## Registers a room's tile-space rectangle. Idempotent; later calls overwrite
## with a push_warning (per E4).
func register_room(room_id: StringName, rect: Rect2i) -> void:
	if _rooms.has(room_id):
		push_warning("[TileMapRenderer] re-registering room '%s' (overwriting previous Rect2i)" % room_id)
	_rooms[room_id] = rect
	if not _alert_active.has(room_id):
		_alert_active[room_id] = false


## Returns the registered Rect2i for a room. Empty Rect2i() for unknown.
func get_room_rect(room_id: StringName) -> Rect2i:
	return _rooms.get(room_id, Rect2i())


## Returns true iff the room was registered.
func has_room(room_id: StringName) -> bool:
	return _rooms.has(room_id)


## Returns the list of registered room IDs.
func get_all_room_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for k: Variant in _rooms.keys():
		ids.append(k)
	return ids


# ─── Alert state (per Rule 8) ────────────────────────────────────────────────

## Shows or hides the alert overlay for the named room.
## Per Rule 8: zero per-cell writes — only toggles `visible` on the
## AlertOverlay layer. The overlay tiles must be authored to match each
## room's floor footprint in the editor.
## For unregistered rooms: push_warning, no visual change (E3).
func set_alert_state(room_id: StringName, active: bool) -> void:
	if not _rooms.has(room_id):
		push_warning("[TileMapRenderer] set_alert_state called for unregistered room '%s'" % room_id)
		return
	_alert_active[room_id] = active
	# MVP: alert visibility is layer-wide. Per-room masking is a post-MVP
	# enhancement (would require either separate alert layers per room or
	# a shader-based clip rect).
	if alert_overlay_layer != null:
		alert_overlay_layer.visible = _any_alert_active()


## True iff the named room's alert state is currently active.
func is_alert_active(room_id: StringName) -> bool:
	return bool(_alert_active.get(room_id, false))


func _any_alert_active() -> bool:
	for v: Variant in _alert_active.values():
		if bool(v):
			return true
	return false


# ─── Public read-only constants accessor (Tier 3 per ADR-0006) ───────────────

## Convenience for downstream systems that need CELL_SIZE without importing
## the class. Stored as a method rather than a static constant access for
## consistency with the Rule 3 reading pattern.
func get_cell_size() -> int:
	return CELL_SIZE
