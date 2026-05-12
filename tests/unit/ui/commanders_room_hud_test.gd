extends GutTest
##
## CommandersRoomHUD — unit tests.
##

const HUDScript = preload("res://src/ui/commanders_room_hud.gd")
const AsmScript = preload("res://src/integration/agent_state_machine.gd")


# ─── Helpers ─────────────────────────────────────────────────────────────────

func _make_hud() -> CommandersRoomHUD:
	# Note: HUD is a CanvasLayer. Construct directly; tests don't need scene tree.
	var hud: CommandersRoomHUD = HUDScript.new()
	# Manually seed slot state to bypass ConfigLoader bootstrap in test isolation.
	return hud


func _seed_slot(hud: CommandersRoomHUD, agent_id: String) -> void:
	hud._slot_state[agent_id] = {
		"state": AsmScript.STATE_IDLE,
		"connection_state": "CONNECTING",
		"tasks_completed": 0,
		"last_beat_ms": 0,
		"display_name": agent_id,
	}


# ─── Constants ──────────────────────────────────────────────────────────────

func test_hud_layer_index_is_10() -> void:
	assert_eq(HUDScript.HUD_LAYER_INDEX, 10)


func test_overlay_layer_index_is_20() -> void:
	assert_eq(HUDScript.OVERLAY_LAYER_INDEX, 20)


func test_completions_strip_max_is_6() -> void:
	assert_eq(HUDScript.COMPLETIONS_STRIP_MAX, 6)


func test_connection_alpha_map_per_adr_0011() -> void:
	assert_almost_eq(float(HUDScript.CONNECTION_ALPHA["CONNECTED"]), 1.0, 0.0001)
	assert_almost_eq(float(HUDScript.CONNECTION_ALPHA["STALE"]), 0.5, 0.0001)
	assert_almost_eq(float(HUDScript.CONNECTION_ALPHA["DISCONNECTED"]), 0.25, 0.0001)
	assert_almost_eq(float(HUDScript.CONNECTION_ALPHA["ERROR"]), 0.25, 0.0001)


func test_state_glyph_map() -> void:
	assert_eq(String(HUDScript.STATE_GLYPH[AsmScript.STATE_IDLE]), "▬")
	assert_eq(String(HUDScript.STATE_GLYPH[AsmScript.STATE_WORKING]), "●")
	assert_eq(String(HUDScript.STATE_GLYPH[AsmScript.STATE_COMPLETED]), "+")
	assert_eq(String(HUDScript.STATE_GLYPH[AsmScript.STATE_ERRORED]), "●")


# ─── Signal handlers update slot state ───────────────────────────────────────

func test_agent_state_changed_updates_slot() -> void:
	var hud: CommandersRoomHUD = _make_hud()
	_seed_slot(hud, "a1")
	hud._on_agent_state_changed("a1", AsmScript.STATE_WORKING, AsmScript.STATE_IDLE)
	assert_eq(String(hud._slot_state["a1"]["state"]), AsmScript.STATE_WORKING)
	hud.free()


func test_agent_state_changed_for_unknown_agent_is_ignored() -> void:
	var hud: CommandersRoomHUD = _make_hud()
	# No seeded slots. Call must not crash.
	hud._on_agent_state_changed("unknown", AsmScript.STATE_WORKING, AsmScript.STATE_IDLE)
	assert_eq(hud._slot_state.size(), 0)
	hud.free()


func test_connection_changed_updates_slot() -> void:
	var hud: CommandersRoomHUD = _make_hud()
	_seed_slot(hud, "a1")
	hud._on_agent_connection_changed("a1", "STALE")
	assert_eq(String(hud._slot_state["a1"]["connection_state"]), "STALE")
	hud.free()


# ─── beat_fired increments tasks_completed + prepends to strip ───────────────

func test_beat_fired_increments_tasks_completed() -> void:
	var hud: CommandersRoomHUD = _make_hud()
	_seed_slot(hud, "a1")
	hud._on_beat_fired("a1", 1704067200.0)
	assert_eq(int(hud._slot_state["a1"]["tasks_completed"]), 1)
	hud._on_beat_fired("a1", 1704067210.0)
	assert_eq(int(hud._slot_state["a1"]["tasks_completed"]), 2)
	hud.free()


func test_beat_fired_prepends_to_completions_strip() -> void:
	var hud: CommandersRoomHUD = _make_hud()
	_seed_slot(hud, "a1")
	hud._on_beat_fired("a1", 1000.0)
	hud._on_beat_fired("a1", 2000.0)
	var strip: Array = hud.get_completions_strip()
	assert_eq(strip.size(), 2)
	assert_eq(float(strip[0]["timestamp"]), 2000.0, "Most recent first")
	hud.free()


func test_completions_strip_caps_at_6() -> void:
	var hud: CommandersRoomHUD = _make_hud()
	_seed_slot(hud, "a1")
	for i: int in 10:
		hud._on_beat_fired("a1", float(i))
	assert_eq(hud.get_completions_strip().size(), 6, "Strip caps at COMPLETIONS_STRIP_MAX")
	hud.free()


# ─── Public read-only API ────────────────────────────────────────────────────

func test_get_slot_state_unknown_returns_empty_dict() -> void:
	var hud: CommandersRoomHUD = _make_hud()
	assert_eq(hud.get_slot_state("unknown"), {})
	hud.free()


func test_get_slot_alpha_connected_returns_1() -> void:
	var hud: CommandersRoomHUD = _make_hud()
	_seed_slot(hud, "a1")
	hud._slot_state["a1"]["connection_state"] = "CONNECTED"
	assert_eq(hud.get_slot_alpha("a1"), 1.0)
	hud.free()


func test_get_slot_alpha_stale_returns_0_5() -> void:
	var hud: CommandersRoomHUD = _make_hud()
	_seed_slot(hud, "a1")
	hud._slot_state["a1"]["connection_state"] = "STALE"
	assert_eq(hud.get_slot_alpha("a1"), 0.5)
	hud.free()


func test_get_slot_alpha_disconnected_returns_0_25() -> void:
	var hud: CommandersRoomHUD = _make_hud()
	_seed_slot(hud, "a1")
	hud._slot_state["a1"]["connection_state"] = "DISCONNECTED"
	assert_eq(hud.get_slot_alpha("a1"), 0.25)
	hud.free()


func test_get_slot_glyph_for_each_state() -> void:
	var hud: CommandersRoomHUD = _make_hud()
	_seed_slot(hud, "a1")
	hud._slot_state["a1"]["state"] = AsmScript.STATE_IDLE
	assert_eq(hud.get_slot_glyph("a1"), "▬")
	hud._slot_state["a1"]["state"] = AsmScript.STATE_WORKING
	assert_eq(hud.get_slot_glyph("a1"), "●")
	hud._slot_state["a1"]["state"] = AsmScript.STATE_COMPLETED
	assert_eq(hud.get_slot_glyph("a1"), "+")
	hud._slot_state["a1"]["state"] = AsmScript.STATE_ERRORED
	assert_eq(hud.get_slot_glyph("a1"), "●")
	hud.free()


func test_get_completions_strip_returns_copy() -> void:
	var hud: CommandersRoomHUD = _make_hud()
	_seed_slot(hud, "a1")
	hud._on_beat_fired("a1", 1000.0)
	var snapshot: Array = hud.get_completions_strip()
	snapshot.append({"injected": "noise"})
	assert_eq(hud.get_completions_strip().size(), 1, "Snapshot is a copy")
	hud.free()
