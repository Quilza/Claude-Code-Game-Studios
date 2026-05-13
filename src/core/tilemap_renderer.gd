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


# ─── Tile asset paths (LimeZu Modern Interiors, locally curated) ─────────────

## Paths to the single-tile PNGs used by every room (single-room MVP).
## V1 (multi-room with varied décor): switch to a Dictionary of room_id →
## {floor: path, wall: path} so each room can use distinct tilework.
const FLOOR_TILE_PATH: String = "res://assets/sprites/tiles/floor_bedroom.png"
const WALL_TILE_PATH: String = "res://assets/sprites/tiles/wall_bedroom.png"

## Atlas coords of the single tile within each single-tile PNG. Always (0,0)
## because the PNGs are 16x16 with one tile each.
const ATLAS_COORDS_ORIGIN: Vector2i = Vector2i(0, 0)


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

# Tileset state — populated by _setup_tileset() in _ready().
# `_shared_tileset` is the single TileSet referenced by floor_layer + wall_layer.
# Source IDs are negative until populated; -1 means "no source loaded" and
# painting routines skip the corresponding layer gracefully.
var _shared_tileset: TileSet = null
var _floor_source_id: int = -1
var _wall_source_id: int = -1


# ─── Godot lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	# Per Rule 9: parent must have y_sort_enabled for Wall layer's Y-sort to work.
	y_sort_enabled = true
	_ensure_layers()
	_setup_tileset()
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


# ─── TileSet construction ────────────────────────────────────────────────────

## Builds a single shared TileSet with one TileSetAtlasSource per asset PNG
## (floor + wall). Assigns it to floor_layer + wall_layer so set_cell()
## calls have a valid TileSet to reference.
##
## Uses `Image.load_from_file()` (Godot 4 static method) rather than
## `load(res://...)` so PNGs work BEFORE the editor's import system has
## generated `.import` files — critical for headless unit tests and for
## the first run after dropping new tile assets into the project.
##
## Graceful degradation: if a tile PNG is missing on disk OR fails to
## load, that source ID stays at -1 and _paint_room() simply skips
## painting the corresponding layer. The room still renders, just without
## that texture.
func _setup_tileset() -> void:
	_shared_tileset = TileSet.new()
	_shared_tileset.tile_size = Vector2i(CELL_SIZE, CELL_SIZE)

	_floor_source_id = _try_register_tile_source(FLOOR_TILE_PATH)
	_wall_source_id = _try_register_tile_source(WALL_TILE_PATH)

	# Assign to layers (TileMapLayer requires a TileSet to call set_cell)
	if floor_layer != null:
		floor_layer.tile_set = _shared_tileset
	if wall_layer != null:
		wall_layer.tile_set = _shared_tileset


## Loads a single-tile PNG via Image.load_from_file (no import dependency),
## wraps it in a TileSetAtlasSource with one tile at (0,0), and adds it to
## the shared TileSet. Returns the assigned source_id, or -1 on any error.
func _try_register_tile_source(path: String) -> int:
	var img: Image = Image.load_from_file(path)
	if img == null:
		push_warning("[TileMapRenderer] could not load tile image at %s" % path)
		return -1
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	if tex == null:
		push_warning("[TileMapRenderer] failed to wrap image as texture: %s" % path)
		return -1
	var src: TileSetAtlasSource = TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(CELL_SIZE, CELL_SIZE)
	src.create_tile(ATLAS_COORDS_ORIGIN)
	return _shared_tileset.add_source(src)


# ─── Room painting ───────────────────────────────────────────────────────────

## Paints the floor + wall tiles for the given rect (in tile coords).
## - Floor: every tile inside the rect (including under the walls; walls
##   render on top via Wall layer's higher z_index).
## - Wall: the 1-tile perimeter (top + bottom + left + right edges).
##
## V1 (multi-style rooms): take a room_style param so different rooms can
## have different floor/wall textures.
func _paint_room(rect: Rect2i) -> void:
	# Floor fill — every cell in the rect
	if _floor_source_id != -1 and floor_layer != null:
		for y: int in range(rect.position.y, rect.position.y + rect.size.y):
			for x: int in range(rect.position.x, rect.position.x + rect.size.x):
				floor_layer.set_cell(Vector2i(x, y), _floor_source_id, ATLAS_COORDS_ORIGIN)

	# Wall perimeter — top + bottom + left + right (corners painted once)
	if _wall_source_id != -1 and wall_layer != null:
		var min_x: int = rect.position.x
		var max_x: int = rect.position.x + rect.size.x - 1
		var min_y: int = rect.position.y
		var max_y: int = rect.position.y + rect.size.y - 1
		# Top + bottom rows (full width)
		for x: int in range(min_x, max_x + 1):
			wall_layer.set_cell(Vector2i(x, min_y), _wall_source_id, ATLAS_COORDS_ORIGIN)
			wall_layer.set_cell(Vector2i(x, max_y), _wall_source_id, ATLAS_COORDS_ORIGIN)
		# Left + right columns (excluding corners — already painted above)
		for y: int in range(min_y + 1, max_y):
			wall_layer.set_cell(Vector2i(min_x, y), _wall_source_id, ATLAS_COORDS_ORIGIN)
			wall_layer.set_cell(Vector2i(max_x, y), _wall_source_id, ATLAS_COORDS_ORIGIN)


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
## with a push_warning (per E4). Also paints the room's floor + wall tiles
## immediately so the visual matches the registry the moment the call lands.
func register_room(room_id: StringName, rect: Rect2i) -> void:
	if _rooms.has(room_id):
		push_warning("[TileMapRenderer] re-registering room '%s' (overwriting previous Rect2i)" % room_id)
	_rooms[room_id] = rect
	if not _alert_active.has(room_id):
		_alert_active[room_id] = false
	_paint_room(rect)


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


# ─── Test seams (internal-but-exposed for unit tests) ────────────────────────

## True iff the tileset has a usable floor source. Used by tests to know
## whether they can assert on painted cells.
func _test_has_floor_source() -> bool:
	return _floor_source_id != -1


## True iff the tileset has a usable wall source.
func _test_has_wall_source() -> bool:
	return _wall_source_id != -1


## Returns the source_id of the cell at `coord` in the floor layer, or -1.
func _test_floor_source_at(coord: Vector2i) -> int:
	if floor_layer == null:
		return -1
	return floor_layer.get_cell_source_id(coord)


## Returns the source_id of the cell at `coord` in the wall layer, or -1.
func _test_wall_source_at(coord: Vector2i) -> int:
	if wall_layer == null:
		return -1
	return wall_layer.get_cell_source_id(coord)
