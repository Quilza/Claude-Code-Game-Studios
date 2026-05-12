extends GutTest
##
## AgentDefaultAnimationFactory — unit tests.
##
## Validates the placeholder AnimationLibrary's shape against the ADR-0009
## §"Shared Asset: AnimationLibrary" table: 4 named anims, correct loop
## modes + durations, modulate targets present.
##

const FactoryScript = preload("res://src/gameplay/agent_default_animation_factory.gd")


# ─── Library composition ─────────────────────────────────────────────────────

func test_factory_library_has_all_four_required_anims() -> void:
	# Arrange / Act
	var lib: AnimationLibrary = FactoryScript.build_placeholder_library()
	# Assert — per ADR-0009 table: idle, working, completed, errored
	assert_true(lib.has_animation(FactoryScript.ANIM_IDLE))
	assert_true(lib.has_animation(FactoryScript.ANIM_WORKING))
	assert_true(lib.has_animation(FactoryScript.ANIM_COMPLETED))
	assert_true(lib.has_animation(FactoryScript.ANIM_ERRORED))


# ─── Loop modes (per ADR-0009 table) ─────────────────────────────────────────

func test_idle_animation_loops() -> void:
	var lib: AnimationLibrary = FactoryScript.build_placeholder_library()
	var anim: Animation = lib.get_animation(FactoryScript.ANIM_IDLE)
	assert_eq(anim.loop_mode, Animation.LOOP_LINEAR, "idle must loop")


func test_working_animation_loops() -> void:
	var lib: AnimationLibrary = FactoryScript.build_placeholder_library()
	var anim: Animation = lib.get_animation(FactoryScript.ANIM_WORKING)
	assert_eq(anim.loop_mode, Animation.LOOP_LINEAR, "working must loop")


func test_completed_animation_is_one_shot() -> void:
	# Per ADR-0009: completed is LOOP_NONE; reverts to idle on finish.
	var lib: AnimationLibrary = FactoryScript.build_placeholder_library()
	var anim: Animation = lib.get_animation(FactoryScript.ANIM_COMPLETED)
	assert_eq(anim.loop_mode, Animation.LOOP_NONE, "completed must NOT loop")


func test_errored_animation_loops() -> void:
	var lib: AnimationLibrary = FactoryScript.build_placeholder_library()
	var anim: Animation = lib.get_animation(FactoryScript.ANIM_ERRORED)
	assert_eq(anim.loop_mode, Animation.LOOP_LINEAR, "errored must loop")


# ─── Durations (per ADR-0009 table) ──────────────────────────────────────────

func test_idle_duration_is_1_2_sec() -> void:
	var lib: AnimationLibrary = FactoryScript.build_placeholder_library()
	assert_almost_eq(lib.get_animation(FactoryScript.ANIM_IDLE).length, 1.2, 0.0001)


func test_working_duration_is_0_6_sec() -> void:
	var lib: AnimationLibrary = FactoryScript.build_placeholder_library()
	assert_almost_eq(lib.get_animation(FactoryScript.ANIM_WORKING).length, 0.6, 0.0001)


func test_completed_duration_is_0_5_sec() -> void:
	var lib: AnimationLibrary = FactoryScript.build_placeholder_library()
	assert_almost_eq(lib.get_animation(FactoryScript.ANIM_COMPLETED).length, 0.5, 0.0001)


func test_errored_duration_is_1_5_sec() -> void:
	var lib: AnimationLibrary = FactoryScript.build_placeholder_library()
	assert_almost_eq(lib.get_animation(FactoryScript.ANIM_ERRORED).length, 1.5, 0.0001)


# ─── Track presence ──────────────────────────────────────────────────────────

func test_completed_animation_has_scale_track_for_bump() -> void:
	# completed has TWO tracks (modulate + scale) for the 1.0 -> 1.2 -> 1.0 bump.
	var lib: AnimationLibrary = FactoryScript.build_placeholder_library()
	var anim: Animation = lib.get_animation(FactoryScript.ANIM_COMPLETED)
	assert_eq(anim.get_track_count(), 2, "completed has modulate + scale tracks")


func test_idle_animation_targets_body_modulate() -> void:
	var lib: AnimationLibrary = FactoryScript.build_placeholder_library()
	var anim: Animation = lib.get_animation(FactoryScript.ANIM_IDLE)
	assert_eq(anim.track_get_path(0), FactoryScript.BODY_NODE_PATH)


# ─── Body color palette ──────────────────────────────────────────────────────

func test_body_color_for_unknown_agent_type_is_default() -> void:
	var c: Color = FactoryScript.body_color_for_agent_type("nonexistent_type")
	assert_eq(c, FactoryScript.DEFAULT_BODY_COLOR)


func test_body_color_for_known_agent_type_is_palette_entry() -> void:
	# Smoke check — "researcher" is in the palette.
	var c: Color = FactoryScript.body_color_for_agent_type("researcher")
	assert_ne(c, FactoryScript.DEFAULT_BODY_COLOR, "Palette entry differs from default")
