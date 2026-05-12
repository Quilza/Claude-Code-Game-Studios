extends GutTest
##
## ConfigurationLoader — unit tests.
##
## Covers the critical ACs from `design/gdd/configuration-loader.md` §Acceptance Criteria.
## Not exhaustive — focuses on the bug-prone paths: validation exhaustiveness,
## slot conflict / gap-fill, error-state safe defaults, and the arbitrary-key
## get_setting / set_setting surface.
##
## GUT framework per ADR-0014. Test file naming per coding-standards:
## `test_<scenario>_<expected>()`.
##
## NOTE: ConfigurationLoader is an Autoload; in tests we instantiate it
## directly via load(...).new() and call _ready() manually, isolating each
## test from a real config.json on disk. We do NOT touch user://settings.json
## (would leak between tests); test methods that need persistence override the
## USER_SETTINGS_PATH constant via a test-only setter (see _override_paths).
##

const ConfigLoaderScript = preload("res://src/core/configuration_loader.gd")


# ─── Helpers ─────────────────────────────────────────────────────────────────

func _make_loader() -> Node:
	# Returns a fresh ConfigurationLoader instance. Caller is responsible for
	# add_child + free. We don't call _ready() automatically — tests choose
	# which config path to point at first.
	var loader: Node = ConfigLoaderScript.new()
	return loader


func _write_temp_config(content: String) -> String:
	# Writes a config file to user:// scope and returns its absolute path.
	# Each test should use a unique filename to avoid cross-test leaks.
	var path: String = "user://test_configs/" + str(Time.get_ticks_usec()) + ".json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()
	return ProjectSettings.globalize_path(path)


# ─── Public API safe-defaults (AC-24) ────────────────────────────────────────

func test_get_agents_returns_empty_array_before_ready() -> void:
	var loader: Node = _make_loader()
	# Don't add to tree — _ready() not called.
	var result: Array = loader.get_agents()
	assert_eq(result.size(), 0, "Pre-ready get_agents() should return []")
	assert_eq(loader.get_state(), ConfigLoaderScript.STATE_UNINITIALIZED, "State should be UNINITIALIZED")
	loader.free()


func test_get_poll_interval_returns_default_before_ready() -> void:
	var loader: Node = _make_loader()
	assert_eq(loader.get_poll_interval(), 5.0, "Pre-ready get_poll_interval() should return 5.0")
	loader.free()


func test_get_protocol_returns_default_before_ready() -> void:
	var loader: Node = _make_loader()
	assert_eq(loader.get_protocol(), "http_poll", "Pre-ready get_protocol() should return 'http_poll'")
	loader.free()


# ─── Returned arrays are isolated from caller mutation (AC-25) ───────────────

func test_get_agents_returns_copy_not_mutable_reference() -> void:
	var loader: Node = _make_loader()
	# Simulate READY state directly (without going through full _ready())
	loader._state = ConfigLoaderScript.STATE_READY
	loader._agents = [{"id": "a1", "display_name": "Agent 1", "endpoint_url": "http://x", "auth_token": "", "agent_type": "default", "room_slot": 0}]
	var first_call: Array = loader.get_agents()
	first_call.append({"id": "INJECTED"})
	var second_call: Array = loader.get_agents()
	assert_eq(second_call.size(), 1, "Caller mutation of returned array must not affect subsequent get_agents()")
	assert_eq(String(second_call[0].get("id", "")), "a1", "Original agent id preserved")
	loader.free()


# ─── Validation: required fields (AC-11) ─────────────────────────────────────

func test_missing_display_name_and_endpoint_url_both_in_error_message() -> void:
	var loader: Node = _make_loader()
	var errors: Array[String] = []
	loader._validate_single_agent({"id": "a1"}, 0, errors)
	var combined: String = "\n".join(errors)
	assert_true(combined.contains("display_name"), "Missing display_name should be in errors")
	assert_true(combined.contains("endpoint_url"), "Missing endpoint_url should be in errors")
	loader.free()


# ─── Validation: agents array bounds (AC-12) ─────────────────────────────────

func test_empty_agents_array_is_invalid() -> void:
	var loader: Node = _make_loader()
	loader._state = ConfigLoaderScript.STATE_LOADING
	loader._validate_and_apply({"agents": []})
	assert_eq(loader.get_state(), ConfigLoaderScript.STATE_CONFIG_INVALID)
	assert_true(loader._last_error_message.contains("agents"))
	loader.free()


func test_agents_array_with_13_entries_is_invalid() -> void:
	var loader: Node = _make_loader()
	loader._state = ConfigLoaderScript.STATE_LOADING
	var too_many: Array = []
	for i: int in 13:
		too_many.append({"id": "a%d" % i, "display_name": "Agent %d" % i, "endpoint_url": "http://x"})
	loader._validate_and_apply({"agents": too_many})
	assert_eq(loader.get_state(), ConfigLoaderScript.STATE_CONFIG_INVALID)
	loader.free()


# ─── Validation: id duplicates (AC-15) ───────────────────────────────────────

func test_duplicate_agent_ids_named_in_error_with_indices() -> void:
	var loader: Node = _make_loader()
	loader._state = ConfigLoaderScript.STATE_LOADING
	loader._validate_and_apply({
		"agents": [
			{"id": "researcher", "display_name": "R1", "endpoint_url": "http://x"},
			{"id": "marketing", "display_name": "M", "endpoint_url": "http://x"},
			{"id": "researcher", "display_name": "R2", "endpoint_url": "http://x"}
		]
	})
	assert_eq(loader.get_state(), ConfigLoaderScript.STATE_CONFIG_INVALID)
	assert_true(loader._last_error_message.contains("researcher"))
	assert_true(loader._last_error_message.contains("0") and loader._last_error_message.contains("2"),
		"Error should name both array indices")
	loader.free()


# ─── Validation: slot conflict + auto-assignment (AC-3, AC-16) ───────────────

func test_three_agents_no_explicit_slots_get_slots_0_1_2() -> void:
	var loader: Node = _make_loader()
	loader._state = ConfigLoaderScript.STATE_LOADING
	loader._validate_and_apply({
		"agents": [
			{"id": "a", "display_name": "A", "endpoint_url": "http://x"},
			{"id": "b", "display_name": "B", "endpoint_url": "http://x"},
			{"id": "c", "display_name": "C", "endpoint_url": "http://x"}
		]
	})
	assert_eq(loader.get_state(), ConfigLoaderScript.STATE_READY)
	var agents: Array = loader.get_agents()
	assert_eq(int(agents[0]["room_slot"]), 0)
	assert_eq(int(agents[1]["room_slot"]), 1)
	assert_eq(int(agents[2]["room_slot"]), 2)
	loader.free()


func test_slot_conflict_between_two_explicit_assignments_is_invalid() -> void:
	var loader: Node = _make_loader()
	loader._state = ConfigLoaderScript.STATE_LOADING
	loader._validate_and_apply({
		"agents": [
			{"id": "a", "display_name": "A", "endpoint_url": "http://x", "room_slot": 5},
			{"id": "b", "display_name": "B", "endpoint_url": "http://x", "room_slot": 5}
		]
	})
	assert_eq(loader.get_state(), ConfigLoaderScript.STATE_CONFIG_INVALID)
	assert_true(loader._last_error_message.contains("5"))
	loader.free()


func test_explicit_slot_plus_auto_gap_fills_correctly() -> void:
	# Agent 0 takes slot 1 explicitly; agents 1 and 2 should auto-fill slots 0 and 2.
	var loader: Node = _make_loader()
	loader._state = ConfigLoaderScript.STATE_LOADING
	loader._validate_and_apply({
		"agents": [
			{"id": "a", "display_name": "A", "endpoint_url": "http://x", "room_slot": 1},
			{"id": "b", "display_name": "B", "endpoint_url": "http://x"},
			{"id": "c", "display_name": "C", "endpoint_url": "http://x"}
		]
	})
	assert_eq(loader.get_state(), ConfigLoaderScript.STATE_READY)
	var agents: Array = loader.get_agents()
	assert_eq(int(agents[0]["room_slot"]), 1, "Explicit slot 1 preserved")
	assert_eq(int(agents[1]["room_slot"]), 0, "Auto-assigned to first gap (slot 0)")
	assert_eq(int(agents[2]["room_slot"]), 2, "Auto-assigned to next gap (slot 2)")
	loader.free()


# ─── Validation: range bounds (AC-17) ────────────────────────────────────────

func test_poll_interval_below_minimum_is_invalid() -> void:
	var loader: Node = _make_loader()
	loader._state = ConfigLoaderScript.STATE_LOADING
	loader._validate_and_apply({
		"agents": [{"id": "a", "display_name": "A", "endpoint_url": "http://x"}],
		"poll_interval_sec": 0.5
	})
	assert_eq(loader.get_state(), ConfigLoaderScript.STATE_CONFIG_INVALID)
	loader.free()


func test_poll_interval_at_minimum_boundary_is_ready() -> void:
	var loader: Node = _make_loader()
	loader._state = ConfigLoaderScript.STATE_LOADING
	loader._validate_and_apply({
		"agents": [{"id": "a", "display_name": "A", "endpoint_url": "http://x"}],
		"poll_interval_sec": 1.0
	})
	assert_eq(loader.get_state(), ConfigLoaderScript.STATE_READY)
	assert_eq(loader.get_poll_interval(), 1.0)
	loader.free()


# ─── Validation: type coercion edge cases (AC-18, AC-19, AC-20) ──────────────

func test_room_slot_whole_float_coerced_to_int() -> void:
	var loader: Node = _make_loader()
	loader._state = ConfigLoaderScript.STATE_LOADING
	loader._validate_and_apply({
		"agents": [{"id": "a", "display_name": "A", "endpoint_url": "http://x", "room_slot": 3.0}]
	})
	assert_eq(loader.get_state(), ConfigLoaderScript.STATE_READY)
	var agents: Array = loader.get_agents()
	assert_eq(typeof(agents[0]["room_slot"]), TYPE_INT, "Whole float coerced to int")
	assert_eq(int(agents[0]["room_slot"]), 3)
	loader.free()


func test_room_slot_non_whole_float_is_invalid() -> void:
	var loader: Node = _make_loader()
	loader._state = ConfigLoaderScript.STATE_LOADING
	loader._validate_and_apply({
		"agents": [{"id": "a", "display_name": "A", "endpoint_url": "http://x", "room_slot": 1.5}]
	})
	assert_eq(loader.get_state(), ConfigLoaderScript.STATE_CONFIG_INVALID)
	loader.free()


func test_auth_token_integer_is_invalid() -> void:
	var loader: Node = _make_loader()
	loader._state = ConfigLoaderScript.STATE_LOADING
	loader._validate_and_apply({
		"agents": [{"id": "a", "display_name": "A", "endpoint_url": "http://x", "auth_token": 42}]
	})
	assert_eq(loader.get_state(), ConfigLoaderScript.STATE_CONFIG_INVALID)
	loader.free()


func test_protocol_unrecognized_value_is_invalid() -> void:
	var loader: Node = _make_loader()
	loader._state = ConfigLoaderScript.STATE_LOADING
	loader._validate_and_apply({
		"agents": [{"id": "a", "display_name": "A", "endpoint_url": "http://x"}],
		"protocol": "grpc"
	})
	assert_eq(loader.get_state(), ConfigLoaderScript.STATE_CONFIG_INVALID)
	loader.free()


# ─── Defaults application (AC-2) ─────────────────────────────────────────────

func test_missing_optionals_apply_defaults_and_list_them() -> void:
	var loader: Node = _make_loader()
	loader._state = ConfigLoaderScript.STATE_LOADING
	loader._validate_and_apply({
		"agents": [{"id": "a", "display_name": "A", "endpoint_url": "http://x"}]
	})
	assert_eq(loader.get_state(), ConfigLoaderScript.STATE_READY)
	assert_eq(loader.get_poll_interval(), 5.0)
	assert_eq(loader.get_protocol(), "http_poll")
	var defaults: Array = loader.get_applied_defaults()
	assert_has(defaults, "poll_interval_sec")
	assert_has(defaults, "protocol")
	loader.free()


# ─── Mock mode (ADR-0008) ────────────────────────────────────────────────────

func test_mock_field_true_sets_is_mock() -> void:
	var loader: Node = _make_loader()
	loader._state = ConfigLoaderScript.STATE_LOADING
	loader._validate_and_apply({
		"mock": true,
		"agents": [{"id": "a", "display_name": "A", "endpoint_url": "http://x"}]
	})
	assert_eq(loader.get_state(), ConfigLoaderScript.STATE_READY)
	assert_true(loader.is_mock(), "is_mock() should be true when config sets mock: true")
	assert_false(loader.is_web_mock_forced(), "Web override should not have fired in non-web test env")
	loader.free()


# ─── Arbitrary-key access (C-9 extension) ────────────────────────────────────

func test_get_setting_returns_default_when_key_absent() -> void:
	var loader: Node = _make_loader()
	loader._user_settings = {}
	assert_eq(loader.get_setting("nonexistent.key", "fallback"), "fallback")
	assert_eq(loader.get_setting("nonexistent.key"), null, "No default → null")
	loader.free()


func test_set_setting_then_get_returns_value_and_emits_signal() -> void:
	var loader: Node = _make_loader()
	loader._user_settings = {}
	var emitted_payload: Array = []
	loader.setting_changed.connect(func(key: String, value: Variant) -> void:
		emitted_payload = [key, value]
	)
	loader.set_setting("test.key", 42)
	assert_eq(loader.get_setting("test.key"), 42, "Round-trip via set/get")
	assert_eq(emitted_payload[0], "test.key", "setting_changed key arg")
	assert_eq(emitted_payload[1], 42, "setting_changed value arg")
	# Cleanup: remove the test key from disk so subsequent tests start fresh
	loader._user_settings.erase("test.key")
	loader._save_user_settings()
	loader.free()


# ─── id charset validation ───────────────────────────────────────────────────

func test_id_with_special_chars_is_invalid() -> void:
	var loader: Node = _make_loader()
	loader._state = ConfigLoaderScript.STATE_LOADING
	loader._validate_and_apply({
		"agents": [{"id": "agent-1", "display_name": "A", "endpoint_url": "http://x"}]
	})
	assert_eq(loader.get_state(), ConfigLoaderScript.STATE_CONFIG_INVALID)
	assert_true(loader._last_error_message.contains("alphanumeric"))
	loader.free()


func test_id_with_underscore_and_digits_is_valid() -> void:
	var loader: Node = _make_loader()
	loader._state = ConfigLoaderScript.STATE_LOADING
	loader._validate_and_apply({
		"agents": [{"id": "claude_dev_2", "display_name": "Claude Dev 2", "endpoint_url": "http://x"}]
	})
	assert_eq(loader.get_state(), ConfigLoaderScript.STATE_READY)
	loader.free()


# ─── get_agent by id (AC-27) ─────────────────────────────────────────────────

func test_get_agent_by_unknown_id_returns_empty_dict() -> void:
	var loader: Node = _make_loader()
	loader._state = ConfigLoaderScript.STATE_READY
	loader._agents = [{"id": "a1", "display_name": "A1", "endpoint_url": "http://x", "auth_token": "", "agent_type": "default", "room_slot": 0}]
	assert_eq(loader.get_agent("nonexistent"), {})
	loader.free()


func test_get_agent_by_known_id_returns_full_dict() -> void:
	var loader: Node = _make_loader()
	loader._state = ConfigLoaderScript.STATE_READY
	loader._agents = [{"id": "a1", "display_name": "A1", "endpoint_url": "http://x", "auth_token": "", "agent_type": "default", "room_slot": 0}]
	var result: Dictionary = loader.get_agent("a1")
	assert_eq(String(result["id"]), "a1")
	assert_eq(String(result["display_name"]), "A1")
	loader.free()
