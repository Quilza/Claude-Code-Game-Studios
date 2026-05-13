extends GutTest
##
## TileMapRenderer — unit tests.
##
## Covers ACs from `design/gdd/tilemap-renderer.md` §Acceptance Criteria
## (unit-testable subset). Visual Y-sort tests (AC-16, AC-17) are deferred
## to manual smoke; structural checks here verify the y_sort_enabled flags
## are correct (AC-02).
##

const TileMapRendererScript = preload("res://src/core/tilemap_renderer.gd")


# ─── Helpers ─────────────────────────────────────────────────────────────────

func _make_renderer() -> TileMapRenderer:
	var renderer: TileMapRenderer = TileMapRendererScript.new()
	add_child(renderer)
	return renderer


# ─── AC-01 Layer instantiation ───────────────────────────────────────────────

func test_four_tilemaplayer_children_exist_after_ready() -> void:
	var r: TileMapRenderer = _make_renderer()
	assert_not_null(r.floor_layer, "floor_layer should be created")
	assert_not_null(r.alert_overlay_layer, "alert_overlay_layer should be created")
	assert_not_null(r.wall_layer, "wall_layer should be created")
	assert_not_null(r.overlay_layer, "overlay_layer should be created")
	r.queue_free()


# ─── AC-02 Y-sort topology ───────────────────────────────────────────────────

func test_only_wall_layer_has_y_sort_enabled() -> void:
	var r: TileMapRenderer = _make_renderer()
	assert_true(r.wall_layer.y_sort_enabled, "Wall layer should have y_sort_enabled = true")
	assert_false(r.floor_layer.y_sort_enabled, "Floor layer should have y_sort_enabled = false")
	assert_false(r.alert_overlay_layer.y_sort_enabled, "Alert layer should have y_sort_enabled = false")
	assert_false(r.overlay_layer.y_sort_enabled, "Overlay layer should have y_sort_enabled = false")
	r.queue_free()


func test_parent_node_has_y_sort_enabled() -> void:
	var r: TileMapRenderer = _make_renderer()
	assert_true(r.y_sort_enabled, "TileMapRenderer (parent) must have y_sort_enabled = true for Wall sort to work")
	r.queue_free()


# ─── AC-04..08 Coordinate conversion ─────────────────────────────────────────

func test_tile_to_world_origin_returns_cell_center() -> void:
	# AC-04
	var r: TileMapRenderer = _make_renderer()
	assert_eq(r.tile_to_world(Vector2i(0, 0)), Vector2(8.0, 8.0))
	r.queue_free()


func test_tile_to_world_arbitrary_cell() -> void:
	# AC-05
	var r: TileMapRenderer = _make_renderer()
	assert_eq(r.tile_to_world(Vector2i(2, 3)), Vector2(40.0, 56.0))
	r.queue_free()


func test_world_to_tile_basic_case() -> void:
	# AC-06
	var r: TileMapRenderer = _make_renderer()
	assert_eq(r.world_to_tile(Vector2(40.0, 56.0)), Vector2i(2, 3))
	r.queue_free()


func test_world_to_tile_negative_world_position_is_valid() -> void:
	# AC-07
	var r: TileMapRenderer = _make_renderer()
	assert_eq(r.world_to_tile(Vector2(-1.0, -1.0)), Vector2i(-1, -1))
	r.queue_free()


func test_round_trip_identity_for_cell_centers() -> void:
	# AC-08
	var r: TileMapRenderer = _make_renderer()
	for x: int in [0, 1, 5, 10, 19]:
		for y: int in [0, 1, 5, 14]:
			var coord: Vector2i = Vector2i(x, y)
			var world: Vector2 = r.tile_to_world(coord)
			var back: Vector2i = r.world_to_tile(world)
			assert_eq(back, coord, "Round-trip should preserve coord (%d, %d)" % [x, y])
	r.queue_free()


# ─── AC-09..12 Alert state ───────────────────────────────────────────────────

func test_set_alert_state_active_shows_overlay() -> void:
	# AC-09
	var r: TileMapRenderer = _make_renderer()
	r.register_room(&"commanders_room", Rect2i(0, 0, 20, 15))
	r.set_alert_state(&"commanders_room", true)
	assert_true(r.alert_overlay_layer.visible)
	r.queue_free()


func test_set_alert_state_inactive_hides_overlay() -> void:
	# AC-10
	var r: TileMapRenderer = _make_renderer()
	r.register_room(&"commanders_room", Rect2i(0, 0, 20, 15))
	r.set_alert_state(&"commanders_room", true)
	r.set_alert_state(&"commanders_room", false)
	assert_false(r.alert_overlay_layer.visible)
	r.queue_free()


func test_set_alert_state_on_unregistered_room_does_not_change_visibility() -> void:
	# AC-11
	var r: TileMapRenderer = _make_renderer()
	var initial: bool = r.alert_overlay_layer.visible
	r.set_alert_state(&"nonexistent", true)
	assert_eq(r.alert_overlay_layer.visible, initial, "Visibility unchanged for unregistered room")
	r.queue_free()


func test_set_alert_state_twice_is_idempotent() -> void:
	# AC-12
	var r: TileMapRenderer = _make_renderer()
	r.register_room(&"commanders_room", Rect2i(0, 0, 20, 15))
	r.set_alert_state(&"commanders_room", true)
	r.set_alert_state(&"commanders_room", true)
	assert_true(r.alert_overlay_layer.visible)
	r.queue_free()


func test_is_alert_active_tracks_per_room() -> void:
	var r: TileMapRenderer = _make_renderer()
	r.register_room(&"room_a", Rect2i(0, 0, 5, 5))
	r.register_room(&"room_b", Rect2i(10, 0, 5, 5))
	r.set_alert_state(&"room_a", true)
	assert_true(r.is_alert_active(&"room_a"))
	assert_false(r.is_alert_active(&"room_b"))
	r.queue_free()


# ─── AC-13, AC-14 Room registry ──────────────────────────────────────────────

func test_register_room_then_get_returns_same_rect() -> void:
	# AC-03 (unit test equivalent)
	var r: TileMapRenderer = _make_renderer()
	var rect: Rect2i = Rect2i(0, 0, 20, 15)
	r.register_room(&"commanders_room", rect)
	assert_eq(r.get_room_rect(&"commanders_room"), rect)
	r.queue_free()


func test_register_room_twice_overwrites_with_warning() -> void:
	# AC-13
	var r: TileMapRenderer = _make_renderer()
	r.register_room(&"room_a", Rect2i(0, 0, 10, 10))
	r.register_room(&"room_a", Rect2i(5, 5, 10, 10))
	assert_eq(r.get_room_rect(&"room_a"), Rect2i(5, 5, 10, 10), "Second registration wins")
	r.queue_free()


func test_get_room_rect_unregistered_returns_empty_rect() -> void:
	# AC-14
	var r: TileMapRenderer = _make_renderer()
	assert_eq(r.get_room_rect(&"never_registered"), Rect2i())
	r.queue_free()


func test_has_room_returns_true_for_registered() -> void:
	var r: TileMapRenderer = _make_renderer()
	r.register_room(&"room_a", Rect2i(0, 0, 5, 5))
	assert_true(r.has_room(&"room_a"))
	assert_false(r.has_room(&"unknown"))
	r.queue_free()


func test_get_all_room_ids_returns_registered_set() -> void:
	var r: TileMapRenderer = _make_renderer()
	r.register_room(&"room_a", Rect2i(0, 0, 5, 5))
	r.register_room(&"room_b", Rect2i(10, 0, 5, 5))
	var ids: Array = r.get_all_room_ids()
	assert_eq(ids.size(), 2)
	assert_has(ids, &"room_a")
	assert_has(ids, &"room_b")
	r.queue_free()


# ─── Constants ───────────────────────────────────────────────────────────────

func test_cell_size_constant_is_16() -> void:
	assert_eq(TileMapRendererScript.CELL_SIZE, 16)


func test_module_size_constant_is_8() -> void:
	assert_eq(TileMapRendererScript.MODULE_SIZE, 8)


func test_modules_per_cell_is_2() -> void:
	assert_eq(TileMapRendererScript.MODULES_PER_CELL, 2)


# ─── Alert layer hidden by default ───────────────────────────────────────────

func test_alert_overlay_starts_hidden() -> void:
	var r: TileMapRenderer = _make_renderer()
	assert_false(r.alert_overlay_layer.visible, "Alert overlay should start hidden per Rule 1")
	r.queue_free()


# ─── Tileset + room painting (LimeZu tile integration) ───────────────────────

func test_tileset_built_with_floor_and_wall_sources_when_assets_present() -> void:
	# Asserts: when floor + wall PNGs exist on disk, _setup_tileset builds
	# atlas sources for both and assigns the shared TileSet to floor + wall
	# layers. Asset files are committed at assets/sprites/tiles/.
	var r: TileMapRenderer = _make_renderer()
	assert_true(r._test_has_floor_source(),
		"Floor source should be built from floor_bedroom.png")
	assert_true(r._test_has_wall_source(),
		"Wall source should be built from wall_bedroom.png")
	assert_not_null(r.floor_layer.tile_set, "Floor layer must have a TileSet attached")
	assert_not_null(r.wall_layer.tile_set, "Wall layer must have a TileSet attached")
	assert_eq(r.floor_layer.tile_set, r.wall_layer.tile_set,
		"Floor + wall layers share a single TileSet for tile_size consistency")
	r.queue_free()


func test_register_room_paints_floor_in_interior_cells() -> void:
	# Arrange / Act — register a 6x4 room at (10, 10)
	var r: TileMapRenderer = _make_renderer()
	r.register_room(&"test_room", Rect2i(10, 10, 6, 4))

	# Assert — interior cell (12, 12) should have a floor source assigned
	# (not the empty sentinel -1).
	var interior_source: int = r._test_floor_source_at(Vector2i(12, 12))
	assert_ne(interior_source, -1, "Interior cell must have floor source painted")
	r.queue_free()


func test_register_room_paints_walls_on_all_four_perimeter_edges() -> void:
	# Arrange / Act — register a 6x4 room at (10, 10) → perimeter at
	# x ∈ {10, 15}, y ∈ {10, 13}.
	var r: TileMapRenderer = _make_renderer()
	r.register_room(&"test_room", Rect2i(10, 10, 6, 4))

	# Assert — all four corners should have wall sources.
	assert_ne(r._test_wall_source_at(Vector2i(10, 10)), -1, "Top-left corner has wall")
	assert_ne(r._test_wall_source_at(Vector2i(15, 10)), -1, "Top-right corner has wall")
	assert_ne(r._test_wall_source_at(Vector2i(10, 13)), -1, "Bottom-left corner has wall")
	assert_ne(r._test_wall_source_at(Vector2i(15, 13)), -1, "Bottom-right corner has wall")
	# Mid-edge samples
	assert_ne(r._test_wall_source_at(Vector2i(12, 10)), -1, "Top edge mid has wall")
	assert_ne(r._test_wall_source_at(Vector2i(12, 13)), -1, "Bottom edge mid has wall")
	assert_ne(r._test_wall_source_at(Vector2i(10, 11)), -1, "Left edge mid has wall")
	assert_ne(r._test_wall_source_at(Vector2i(15, 11)), -1, "Right edge mid has wall")
	r.queue_free()


func test_register_room_does_not_paint_walls_inside_room_interior() -> void:
	# Wall painting is perimeter-only. An interior cell (not on any edge)
	# should have NO wall source.
	var r: TileMapRenderer = _make_renderer()
	r.register_room(&"test_room", Rect2i(10, 10, 6, 4))

	# (12, 12) is 2 cells from any edge — fully interior.
	assert_eq(r._test_wall_source_at(Vector2i(12, 12)), -1,
		"Interior cell must NOT have wall source painted")
	r.queue_free()


func test_register_room_paints_floor_even_under_walls() -> void:
	# Floor fills the entire rect including perimeter cells (walls render on
	# top via higher z_index). This ensures no visible "gap" appears between
	# the floor edge and the wall.
	var r: TileMapRenderer = _make_renderer()
	r.register_room(&"test_room", Rect2i(10, 10, 6, 4))

	# Corner cell (10, 10) has BOTH floor + wall painted
	assert_ne(r._test_floor_source_at(Vector2i(10, 10)), -1, "Floor painted under corner")
	assert_ne(r._test_wall_source_at(Vector2i(10, 10)), -1, "Wall painted at corner")
	r.queue_free()
